# Repository Instructions

## Current State

- The Windows solution is bootstrapped under `windows/` with ten projects and one NuGet lockfile per project. P1 protocol codecs are implemented; the Flutter application is not yet bootstrapped.
- Do not guess build or verification commands. Derive commands from manifests/scripts and keep the exact focused and full verification commands below current.
- Treat this file as the bootstrap contract only. Once created, `protocol/protocol-v1.md` and its binary fixtures are the canonical protocol source.

## Windows Verification Commands

Run these commands from the repository root:

```powershell
dotnet restore windows/Pulgapp.sln --force-evaluate
dotnet build windows/Pulgapp.sln --configuration Release --no-restore -p:Platform=x64
dotnet test windows/tests/Pulgapp.Server.Protocol.Tests/Pulgapp.Server.Protocol.Tests.csproj --configuration Release --no-build -p:Platform=x64 --filter "FullyQualifiedName~UdpInputDecoderTests"
dotnet test windows/tests/Pulgapp.Server.Protocol.Tests/Pulgapp.Server.Protocol.Tests.csproj --configuration Release --no-build -p:Platform=x64
dotnet test windows/tests/Pulgapp.Server.Core.Tests/Pulgapp.Server.Core.Tests.csproj --configuration Release --no-build -p:Platform=x64 --filter "FullyQualifiedName~SessionCoordinatorTests"
dotnet test windows/tests/Pulgapp.Server.Core.Tests/Pulgapp.Server.Core.Tests.csproj --configuration Release --no-build -p:Platform=x64
dotnet test windows/tests/Pulgapp.Server.Infrastructure.Tests/Pulgapp.Server.Infrastructure.Tests.csproj --configuration Release --no-build -p:Platform=x64 --filter "FullyQualifiedName~X360ReportMapperTests"
dotnet test windows/tests/Pulgapp.Server.Infrastructure.Tests/Pulgapp.Server.Infrastructure.Tests.csproj --configuration Release --no-build -p:Platform=x64
dotnet test windows/tests/Pulgapp.Server.IntegrationTests/Pulgapp.Server.IntegrationTests.csproj --configuration Release --no-build -p:Platform=x64 --filter "FullyQualifiedName~PulgappServerTests"
dotnet test windows/tests/Pulgapp.Server.IntegrationTests/Pulgapp.Server.IntegrationTests.csproj --configuration Release --no-build -p:Platform=x64
dotnet run --project windows/tools/Pulgapp.LoadGenerator/Pulgapp.LoadGenerator.csproj --configuration Release --no-build -p:Platform=x64 -- --clients 5 --rate-hz 120 --duration-seconds 10 --loss-every 7 --duplicate-every 5 --reorder-every 9
dotnet run --project windows/tools/Pulgapp.LoadGenerator/Pulgapp.LoadGenerator.csproj --configuration Release --no-build -p:Platform=x64 -- --clients 4 --rate-hz 120 --duration-seconds 7200 --loss-every 7 --duplicate-every 5 --reorder-every 9
dotnet test windows/Pulgapp.sln --configuration Release --no-build -p:Platform=x64
```

Run these Dart/Flutter client commands from `mobile/`:

```powershell
dart pub get
dart test test/protocol_test.dart
dart analyze
dart test
flutter build apk --debug --no-pub
```

`dotnet run --project windows/tools/Pulgapp.DriverDiagnostics/Pulgapp.DriverDiagnostics.csproj --configuration Release -p:Platform=x64` is hardware-only and must not run in normal driver-free CI. Do not add `--no-build` for manual diagnostics because it can reuse an outdated target executable.

## Product Constraints

- Build a LAN phone-to-Windows virtual gamepad system for local multiplayer, not a single-controller demo product.
- Support up to eight independent phones: slots 1-4 are virtual Xbox 360/XInput controllers; slots 5-8 are virtual DualShock 4 HID controllers for games that consume them through DirectInput, Raw Input, SDL, or equivalent.
- XInput's four-device limit is external and must not be worked around by pretending additional X360 devices are available.
- Use WiFi/LAN transport and ViGEmBus/ViGEmClient. Do not pivot to Bluetooth HID or console pairing.
- Game support is not guaranteed by device enumeration alone. Pummel Party must recognize four X360 plus four DS4 devices before eight-player support is considered viable.

## Fixed Architecture

- Mobile: Android-first Flutter/Dart, but keep shared code and dependencies viable for a later iOS build.
- Windows: C#/.NET 10 LTS, x64 WPF desktop host; do not introduce a Windows Service for v1.
- Pin `Nefarius.ViGEm.Client` to `1.21.256`; target ViGEmBus `1.22.0` and surface a clear driver health failure.
- Use WebSocket/TCP for handshake, PIN, lobby, status, and reconnection; use UDP full-state binary snapshots for high-frequency input.
- Default ports are TCP `26760` and UDP `26761`. Initial discovery is manual IPv4 plus a six-digit PIN; mDNS comes later and manual entry remains the fallback.
- Slots are fixed by type. A Pulgapp slot is not necessarily the in-game player number or XInput user index.

## Input Safety

- Send complete idempotent gamepad snapshots, never input deltas. Authenticate UDP packets with the session ID/token assigned over WebSocket and discard duplicate or older sequence numbers.
- Cap active sends near 120 Hz, send an unchanged heartbeat every 50 ms, and neutralize a controller after 250 ms without valid input.
- Neutralize immediately on WebSocket loss, app suspension, explicit leave, server shutdown, and pointer cancellation. Preventing stuck buttons is more important than preserving the latest input.
- Serialize all updates to an individual ViGEm target. Set `AutoSubmitReport = false`, update the complete report, then submit once per accepted snapshot.
- Keep canonical stick Y positive upward; invert Y only in the DS4 adapter. Keep controller-specific mappings out of the mobile transport model.

## Lobby Semantics

- Allocate the lowest free slot atomically and expose it only after its ViGEm target connects successfully.
- Reserve a disconnected client's existing target and slot for 15 seconds, neutralized; a valid resume token reuses that target but receives fresh session and UDP tokens.
- Explicit leave or kick neutralizes, disconnects, invalidates tokens, and frees the slot immediately.
- Never log PINs, UDP tokens, or resume tokens. Restrict production firewall rules to Private profiles and `LocalSubnet`; never add UPnP or Internet-facing defaults.

## Implementation Order

- First build a Windows diagnostics spike that creates one X360, one DS4, then four of each, and verify them in Windows and inside Pummel Party. Stop and document a failed eight-player compatibility gate instead of continuing by assumption.
- Phase 1 is one Android phone controlling one X360 end to end with timeout neutralization.
- Phase 2 adds four independent X360 clients plus lease/reconnection behavior.
- Phase 3 adds DS4 slots 5-8 and repeats the real-game compatibility test.
- Add mDNS, UI customization, rumble, installers, and iOS only after the preceding functional gates pass.

## Protocol And Tests

- Define the protocol and a 60-byte little-endian UDP v1 golden fixture before implementing either codec. The C# and Dart test suites must consume byte-identical fixtures.
- Keep protocol parsing, sequence wrap handling, lobby timing, X360 mapping, and DS4 mapping testable without an installed driver.
- Use a fake virtual-controller adapter for CI and separate driver/game smoke tests from normal automated tests.
- Do not claim a phase complete from compilation or `joy.cpl` alone; run that phase's end-to-end phone, timeout, independence, and real-game checks.
