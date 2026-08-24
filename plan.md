# Pulgapp Implementation Plan

This file is the execution queue for the coding agent. Work in task-ID order and update the checkboxes and evidence links as work is completed.

## Source Of Truth

Resolve conflicts in this order:

1. `protocol/protocol-v1.md` and `protocol/fixtures/` for wire behavior.
2. `AGENTS.md` for product, safety, and platform constraints.
3. This file for implementation order and phase gates.
4. `docs/architecture.md` for module ownership and execution flow.
5. `docs/acceptance.md` and `docs/compatibility-test.md` for verification.
6. Executable manifests, lockfiles, scripts, and CI once they exist.

If executable configuration conflicts with prose, stop and reconcile the documents rather than silently choosing one.

## Execution Rules

- Complete one task at a time. Do not begin a later phase while the current phase gate is open.
- Before each task, inspect the files it will modify and preserve unrelated work.
- Write or update focused tests with each behavior change.
- Run the focused verification for the changed module, then the phase verification suite.
- Record commands and outcomes under the task's `Evidence` entry.
- A manual or hardware check remains unchecked until a human reports the observed result.
- Never mark Pummel Party compatibility from compilation, unit tests, Device Manager, or `joy.cpl` alone.
- When a command is introduced in a manifest or script, add its exact focused and full forms to `AGENTS.md`.
- Do not redesign protocol fields, timeouts, slot types, or transports. Raise a blocker if an implementation constraint makes a change necessary.

## Current Status

- Current phase: `P2 - Four Independent X360 Clients`
- Next task: `P2-03` Complete multi-client UI and hardware checks
- Last completed task: `P2-02` Add load generation and concurrency verification
- Blockers: Flutter doctor reports a non-blocking `0.0.0-unknown` version-metadata warning and that the Visual Studio Windows desktop workload is absent; neither is required for the Android client or the .NET WPF host.
- Gate G0: PASS. Pummel Party accepts four X360 plus four DS4 virtual targets as eight independent players.

## Repository Shape

Use one monorepo so both codecs consume one canonical fixture:

```text
Pulgapp/
|-- AGENTS.md
|-- plan.md
|-- opencode.json
|-- protocol/
|-- docs/
|-- windows/
|   |-- Pulgapp.sln
|   |-- src/
|   |-- tests/
|   `-- tools/
|-- mobile/
|   |-- lib/
|   |-- test/
|   `-- integration_test/
`-- .opencode/
```

Do not split the project into separate repositories before v1. Shared protocol fixtures and coordinated CI are more valuable than independent release histories at this stage.

## Target Toolchains

- Windows host: .NET 10 LTS SDK, C#, WPF, `win-x64`.
- Mobile client: current stable Flutter/Dart at bootstrap time, Android min SDK 26, Android and iOS scaffolds retained.
- Driver: ViGEmBus 1.22.0 installed manually for development.
- Managed client: `Nefarius.ViGEm.Client` exactly 1.21.256.
- Automated Windows tests: xUnit with no installed-driver requirement.
- Protocol numbers: little-endian and version 1.

## Phase P0: Toolchain, Fixture, And Compatibility Spike

Goal: prove the riskiest driver/game assumption before building the networked product.

### P0-01 Validate local prerequisites

- [x] Run `dotnet --info` and confirm a .NET 10 SDK.
- [x] Run `flutter doctor -v` and record Android toolchain blockers.
- [x] Confirm Windows is x64 Windows 10 22H2 or Windows 11.
- [x] Confirm ViGEmBus 1.22.0 is installed, or record that driver installation requires user action.
- [x] Add the observed versions to `docs/development.md` without adding machine-specific absolute paths.

Evidence (2026-08-05):
- Automated: `dotnet --info` -> PASS, .NET SDK 10.0.302 and .NET host 10.0.10 detected on x64.
- Automated: `flutter --version` -> PASS, Flutter stable 3.44.8 and Dart 3.12.2 detected.
- Automated: `flutter doctor -v` -> PASS for the Android toolchain; WARNING for Flutter's non-blocking `0.0.0-unknown` version metadata and the missing Visual Studio Windows desktop workload.
- Automated: `flutter doctor --android-licenses` -> PASS, all Android SDK licenses accepted.
- Automated: `Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' | Select-Object ProductName,DisplayVersion,CurrentBuild,UBR` -> PASS, Windows 10 Pro 22H2 build 19045.
- Automated: `Get-CimInstance Win32_OperatingSystem | Format-List Caption,Version,BuildNumber,OSArchitecture; Get-CimInstance Win32_ComputerSystem | Format-List Manufacturer,Model,SystemType; [Environment]::Is64BitOperatingSystem` -> PASS, x64-based PC and 64-bit operating system.
- Automated: `winget list --id ViGEm.ViGEmBus -e` -> PASS, ViGEmBus package 1.22.0 installed.
- Automated: `Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceName -match 'ViGEm|Virtual Gamepad' -or $_.Manufacturer -match 'Nefarius|ViGEm' }` -> PASS, Nefarius virtual bus detected, driver version 1.21.442.0.
- Artifacts: `docs/development.md`.
- Exceptions: Flutter doctor metadata and Visual Studio Windows desktop workload warnings are outside the Android-first client and .NET WPF prerequisite set. Human driver and game checks remain pending.

### P0-02 Materialize the golden binary fixture

- [x] Convert `protocol/fixtures/input-state-v1.hex` into `protocol/fixtures/input-state-v1.bin` without changing bytes.
- [x] Verify the binary length is exactly 60 bytes.
- [x] Verify its SHA-256 equals the value recorded in `input-state-v1.json` after that value has been computed once.
- [x] Do not implement either codec before this fixture exists.

Evidence (2026-08-05):
- Automated: `$hex = [IO.File]::ReadAllText('protocol/fixtures/input-state-v1.hex'); $bytes = [Convert]::FromHexString(($hex -replace '\s','')); [IO.File]::WriteAllBytes('protocol/fixtures/input-state-v1.bin',$bytes)` -> PASS, generated 60 bytes and SHA-256 `78d85292958a276290ef82a7cdc657a8eaf1d7f23ab27b3132732859210ff7df`.
- Automated: fixture comparison script validating JSON parse, declared length, `expectedHex`, canonical `.hex`, and metadata SHA-256 -> PASS, all five checks true.
- Artifacts: `protocol/fixtures/input-state-v1.bin`, `protocol/fixtures/input-state-v1.hex`, `protocol/fixtures/input-state-v1.json`.
- Exceptions: No codec implementation was added. Human driver and game checks remain pending.

### P0-03 Bootstrap the Windows solution

- [x] Create `windows/Pulgapp.sln` using the .NET 10 SDK.
- [x] Create WPF project `Pulgapp.Server.App` targeting `net10.0-windows` and x64.
- [x] Create class libraries `Pulgapp.Server.Core`, `Pulgapp.Server.Protocol`, and `Pulgapp.Server.Infrastructure`.
- [x] Create xUnit projects for Core, Protocol, Infrastructure, and Integration tests.
- [x] Create console tools `Pulgapp.DriverDiagnostics` and `Pulgapp.LoadGenerator`.
- [x] Add all projects to the solution and project references according to `docs/architecture.md`.
- [x] Enable nullable reference types, implicit usings, deterministic builds, warnings as errors for repository code, and NuGet lockfiles.
- [x] Pin `Nefarius.ViGEm.Client` 1.21.256 only in Infrastructure and DriverDiagnostics.
- [x] Add exact restore, build, focused-test, and full-test commands to `AGENTS.md`.

Evidence (2026-08-05):
- Automated: `dotnet restore windows/Pulgapp.sln --force-evaluate` -> PASS, all 10 projects restored and 10 `packages.lock.json` files generated.
- Automated: `dotnet build windows/Pulgapp.sln --configuration Release --no-restore -p:Platform=x64` -> PASS, 0 warnings, 0 errors, duration 9.97 seconds.
- Automated: `dotnet test windows/tests/Pulgapp.Server.Protocol.Tests/Pulgapp.Server.Protocol.Tests.csproj --configuration Release --no-build --filter "FullyQualifiedName~UnitTest1.Test1"` -> PASS, 1/1 test, duration 9 ms.
- Automated: `dotnet test windows/tests/Pulgapp.Server.Protocol.Tests/Pulgapp.Server.Protocol.Tests.csproj --configuration Release --no-build` -> PASS, 1/1 test, duration 10 ms.
- Automated: `dotnet test windows/Pulgapp.sln --configuration Release --no-build -p:Platform=x64` -> PASS, 4/4 tests, 0 errors.
- Automated: `grep Nefarius.ViGEm.Client windows/**/*.csproj` -> PASS, package version `1.21.256` appears only in Infrastructure and DriverDiagnostics.
- Artifacts: `windows/Pulgapp.sln`, `windows/Directory.Build.props`, 10 project files, 10 `packages.lock.json` files, `AGENTS.md`, `docs/acceptance.md`.
- Exceptions: Projects contain template-only source and tests; no application, protocol, or driver behavior was implemented. Driver diagnostics and game checks remain pending human verification.

### P0-04 Implement driver diagnostics

- [x] Detect and classify ViGEm bus missing, access failure, and version mismatch errors.
- [x] Create one neutral X360 target, submit deterministic test states, neutralize, and disconnect.
- [x] Create one neutral DS4 target and repeat the test.
- [x] Create four X360 and four DS4 targets simultaneously.
- [x] Always neutralize and dispose every successfully created target on cancellation, failure, or process exit.
- [x] Keep diagnostics isolated from the production WPF composition root.

Evidence (2026-08-05):
- Automated: `dotnet build windows/tools/Pulgapp.DriverDiagnostics/Pulgapp.DriverDiagnostics.csproj --configuration Release --no-restore -p:Platform=x64` -> PASS, 0 warnings, 0 errors.
- Automated driver smoke: `dotnet run --project windows/tools/Pulgapp.DriverDiagnostics/Pulgapp.DriverDiagnostics.csproj --configuration Release --no-build -p:Platform=x64 -- --mode one-x360 --duration-seconds 1` -> PASS, one X360 target connected, received neutral and deterministic complete reports, then neutralized and disposed.
- Automated driver smoke: `dotnet run --project windows/tools/Pulgapp.DriverDiagnostics/Pulgapp.DriverDiagnostics.csproj --configuration Release --no-build -p:Platform=x64 -- --mode one-ds4 --duration-seconds 1` -> PASS, one DS4 target connected, received neutral and deterministic complete reports, then neutralized and disposed.
- Automated driver smoke: `dotnet run --project windows/tools/Pulgapp.DriverDiagnostics/Pulgapp.DriverDiagnostics.csproj --configuration Release --no-build -p:Platform=x64 -- --mode eight --duration-seconds 0` -> PASS, four X360 and four DS4 targets connected simultaneously, received deterministic states, then all eight were neutralized and disposed.
- Automated: `dotnet test windows/Pulgapp.sln --configuration Release --no-build -p:Platform=x64` -> PASS, 4/4 driver-free tests.
- Automated (2026-08-22): diagnostic `--help` -> PASS, `--wait-for-cancel` is available for manual Windows/game checks and keeps targets active until Ctrl+C.
- Manual (2026-08-22), user reported: eight targets remain active while switching to `joy.cpl` when diagnostics runs with `--wait-for-cancel`.
- Automated (2026-08-22): diagnostics supports neutral game startup plus one scheduled A/Cross join pulse, so its Windows inspection states do not hold game menus open.
- Artifacts: `windows/tools/Pulgapp.DriverDiagnostics/Program.cs`, `AGENTS.md`, `docs/acceptance.md`.
- Exceptions: P0-05 Windows device observation and Pummel Party/It Takes Two compatibility checks remain pending human hardware/game verification.

### P0-05 Execute the eight-player compatibility gate

- [x] Follow `docs/compatibility-test.md` on a real PC.
- [x] Verify one X360 and one DS4 in Windows.
- [x] Verify four X360 and four DS4 in Windows.
- [x] Test Pummel Party with Steam Input disabled.
- [x] If needed, test the documented Steam Input variants without running DS4Windows or XOutput.
- [x] Record whether all eight devices can join independently inside Pummel Party.
- [x] Record It Takes Two behavior with two X360 targets.

Gate `G0`: PASS only if Pummel Party accepts eight independent inputs. If it fails, stop product implementation and document the exact failure. Do not invent a fallback target type.

Evidence (2026-08-22):
- Manual, user reported: one X360 virtual target is recognized as an Xbox controller in Windows and works correctly in games.
- Manual, user reported: one DS4 virtual target is recognized as a Wireless Controller in Windows and works correctly in games.
- Manual, user reported: four X360 plus four DS4 virtual targets are recognized simultaneously in Windows.
- Manual, user reported: with Steam Input disabled, Pummel Party accepted joins from all eight virtual targets.
- Manual, user reported: Pummel Party accepts eight independent inputs during a real match.
- Gate G0: PASS. Steam Input variants are not needed because the disabled configuration works.
- Manual, user reported: It Takes Two accepts two independent X360 virtual targets.
- P0-05: PASS. Proceed to P1-01.

## Phase P1: One Android Phone To One X360

Goal: deliver one complete low-latency and fail-safe path using the final protocol shape.

### P1-01 Implement protocol models and codecs

- [x] Implement C# control DTOs and strict UDP v1 decoding in `Pulgapp.Server.Protocol`.
- [x] Implement Dart control DTOs and UDP v1 encoding.
- [x] Make both test suites consume `protocol/fixtures/input-state-v1.bin` from the repository root.
- [x] Test all offsets, endianness, ranges, invalid length, magic, version, type, flags, and reserved button handling.
- [x] Implement modular `uint32` sequence comparison and wrap tests.

Evidence (2026-08-22):
- Automated: `dotnet test windows/tests/Pulgapp.Server.Protocol.Tests/Pulgapp.Server.Protocol.Tests.csproj --configuration Release --no-build -p:Platform=x64 --filter "FullyQualifiedName~UdpInputDecoderTests"` -> PASS, 13/13 tests.
- Automated: `dotnet test windows/tests/Pulgapp.Server.Protocol.Tests/Pulgapp.Server.Protocol.Tests.csproj --configuration Release --no-build -p:Platform=x64` -> PASS, 13/13 tests.
- Automated: from `mobile/`, `dart test test/protocol_test.dart` -> PASS, 3/3 tests; `dart analyze` -> PASS, no issues; `dart test` -> PASS, 3/3 tests.
- Automated: `dotnet build windows/Pulgapp.sln --configuration Release --no-restore -p:Platform=x64` -> PASS, 0 warnings, 0 errors.
- Automated: `dotnet test windows/Pulgapp.sln --configuration Release --no-build -p:Platform=x64` -> PASS, 16/16 driver-free tests.
- Artifacts: `windows/src/Pulgapp.Server.Protocol/ControlMessages.cs`, `windows/src/Pulgapp.Server.Protocol/InputSnapshot.cs`, `windows/src/Pulgapp.Server.Protocol/UdpInputDecoder.cs`, `windows/tests/Pulgapp.Server.Protocol.Tests/UdpInputDecoderTests.cs`, `mobile/lib/protocol.dart`, `mobile/test/protocol_test.dart`, `mobile/pubspec.yaml`, `mobile/pubspec.lock`.
- Exceptions: Flutter Android/iOS scaffolding and hardware/game checks remain pending P1-05 and P1-06.

### P1-02 Implement the driver-independent core

- [x] Add immutable canonical `GamepadState` with neutral singleton.
- [x] Add `VirtualController` and `VirtualControllerFactory` seams described in `docs/architecture.md`.
- [x] Add pure X360 report mapping tests before using ViGEm.
- [x] Add `SessionCoordinator` for one slot with token validation and a 250 ms watchdog.
- [x] Use `TimeProvider` so timeout tests do not sleep.
- [x] Ensure WebSocket loss, explicit leave, timeout, shutdown, and cancellation all reach neutralization.

Evidence (2026-08-22):
- Automated: `dotnet test windows/tests/Pulgapp.Server.Core.Tests/Pulgapp.Server.Core.Tests.csproj --configuration Release --no-build -p:Platform=x64 --filter "FullyQualifiedName~SessionCoordinatorTests"` -> PASS, 8/8 tests.
- Automated: `dotnet test windows/tests/Pulgapp.Server.Core.Tests/Pulgapp.Server.Core.Tests.csproj --configuration Release --no-build -p:Platform=x64` -> PASS, 8/8 tests.
- Automated: `dotnet test windows/tests/Pulgapp.Server.Infrastructure.Tests/Pulgapp.Server.Infrastructure.Tests.csproj --configuration Release --no-build -p:Platform=x64 --filter "FullyQualifiedName~X360ReportMapperTests"` -> PASS, 7/7 tests.
- Automated: `dotnet test windows/tests/Pulgapp.Server.Infrastructure.Tests/Pulgapp.Server.Infrastructure.Tests.csproj --configuration Release --no-build -p:Platform=x64` -> PASS, 7/7 tests.
- Automated: `dotnet build windows/Pulgapp.sln --configuration Release --no-restore -p:Platform=x64` -> PASS, 0 warnings, 0 errors.
- Automated: `dotnet test windows/Pulgapp.sln --configuration Release --no-build -p:Platform=x64` -> PASS, 29/29 driver-free tests.
- Artifacts: `windows/src/Pulgapp.Server.Core/GamepadState.cs`, `windows/src/Pulgapp.Server.Core/VirtualController.cs`, `windows/src/Pulgapp.Server.Core/SessionCoordinator.cs`, `windows/src/Pulgapp.Server.Infrastructure/X360ReportMapper.cs`, `windows/tests/Pulgapp.Server.Core.Tests/SessionCoordinatorTests.cs`, `windows/tests/Pulgapp.Server.Infrastructure.Tests/X360ReportMapperTests.cs`.
- Exceptions: ViGEm calls, network transport, Flutter Android/iOS scaffolding, and hardware/game checks remain pending P1-03 through P1-06.

### P1-03 Implement Windows transport and X360 adapter

- [x] Host `GET /health` and WebSocket `/control` on TCP 26760.
- [x] Bind one IPv4 UDP socket on port 26761.
- [x] Implement hello, welcome, ping/pong, input-ready, status, leave, suspend, and errors exactly as specified.
- [x] Generate PIN and tokens cryptographically; never log their values.
- [x] Validate UDP source IP against the WebSocket peer.
- [x] Set `AutoSubmitReport = false`, update the complete X360 report, and submit once.
- [x] Serialize updates through a bounded per-session worker, never on the WPF dispatcher.

Evidence (2026-08-22):
- Automated: `dotnet restore windows/Pulgapp.sln --force-evaluate` -> PASS, all 10 projects restored with lockfiles updated.
- Automated: `dotnet build windows/Pulgapp.sln --configuration Release --no-restore -p:Platform=x64` -> PASS, 0 warnings, 0 errors.
- Automated: `dotnet test windows/tests/Pulgapp.Server.IntegrationTests/Pulgapp.Server.IntegrationTests.csproj --configuration Release --no-build -p:Platform=x64 --filter "FullyQualifiedName~PulgappServerTests"` -> PASS, 2/2 tests, duration 701 ms.
- Automated: `dotnet test windows/tests/Pulgapp.Server.IntegrationTests/Pulgapp.Server.IntegrationTests.csproj --configuration Release --no-build -p:Platform=x64` -> PASS, 2/2 tests, duration 1 s.
- Automated: `dotnet test windows/Pulgapp.sln --configuration Release --no-build -p:Platform=x64` -> PASS, 30/30 driver-free tests.
- Automated: from `mobile/`, `dart test test/protocol_test.dart` -> PASS, 3/3 tests; `dart analyze` -> PASS, no issues; `dart test` -> PASS, 3/3 tests.
- Artifacts: `windows/src/Pulgapp.Server.Infrastructure/PulgappServer.cs`, `windows/src/Pulgapp.Server.Infrastructure/X360VirtualController.cs`, `windows/tests/Pulgapp.Server.IntegrationTests/PulgappServerTests.cs`, `windows/Pulgapp.sln`, `AGENTS.md`, `docs/acceptance.md`.
- Exceptions: Physical Android, ViGEm driver, Windows controller, and game checks remain pending human verification in P1-06.

### P1-04 Implement the minimal WPF dashboard

- [x] Show driver status, server status, candidate LAN IPv4 addresses, ports, and PIN.
- [x] Show one slot with client name, connection state, last input age, packet rate, and RTT.
- [x] Provide Regenerate PIN, Kick, Start Server, and Stop Server actions.
- [x] Stop accepting connections before neutralizing and disposing targets during shutdown.
- [x] Keep normal runtime non-elevated.

Evidence (2026-08-22):
- Automated: `dotnet build windows/Pulgapp.sln --configuration Release --no-restore -p:Platform=x64` -> PASS, 0 warnings, 0 errors.
- Automated: `dotnet test windows/tests/Pulgapp.Server.IntegrationTests/Pulgapp.Server.IntegrationTests.csproj --configuration Release --no-build -p:Platform=x64 --filter "FullyQualifiedName~PulgappServerTests"` -> PASS, 3/3 tests, duration 652 ms.
- Automated: `dotnet test windows/tests/Pulgapp.Server.IntegrationTests/Pulgapp.Server.IntegrationTests.csproj --configuration Release --no-build -p:Platform=x64` -> PASS, 3/3 tests, duration 1 s.
- Automated: `dotnet test windows/Pulgapp.sln --configuration Release --no-build -p:Platform=x64` -> PASS, 31/31 driver-free tests.
- Automated: from `mobile/`, `dart test test/protocol_test.dart` -> PASS, 3/3 tests; `dart analyze` -> PASS, no issues; `dart test` -> PASS, 3/3 tests.
- Artifacts: `windows/src/Pulgapp.Server.App/MainWindow.xaml`, `windows/src/Pulgapp.Server.App/MainWindow.xaml.cs`, `windows/src/Pulgapp.Server.App/app.manifest`, `windows/src/Pulgapp.Server.Infrastructure/PulgappServer.cs`, `windows/tests/Pulgapp.Server.IntegrationTests/PulgappServerTests.cs`.
- Exceptions: Physical Android, ViGEm driver, Windows controller, and game checks remain pending human verification in P1-06.

### P1-05 Bootstrap and implement the Flutter client

- [x] Create Flutter project under `mobile/` with Android and iOS scaffolds.
- [x] Set Android min SDK 26, landscape orientation, cleartext LAN network configuration, Internet permission, vibration permission, and screen-awake behavior.
- [x] Persist a random client UUID and the last successful endpoint.
- [x] Implement manual IPv4/hostname plus six-digit PIN connection UI.
- [x] Implement one connection module that owns WebSocket, UDP, tokens, state, and cleanup.
- [x] Implement the 120 Hz cap, 50 ms unchanged heartbeat, and immediate neutral snapshots.
- [x] Implement raw multitouch controls with pointer IDs, including pointer cancellation.
- [x] Use canonical Xbox labels and canonical Y-positive-up values.

Evidence (2026-08-22):
- Automated: from `mobile/`, `dart pub get` -> PASS, Flutter application dependencies resolved.
- Automated: from `mobile/`, `dart test test/input_send_scheduler_test.dart` -> PASS, 2/2 tests.
- Automated: from `mobile/`, `dart test test/protocol_test.dart` -> PASS, 3/3 tests.
- Automated: from `mobile/`, `dart analyze` -> PASS, no issues.
- Automated: from `mobile/`, `dart test` -> PASS, 5/5 tests.
- Automated: from `mobile/`, `flutter build apk --debug --no-pub` -> PASS, produced `build/app/outputs/flutter-apk/app-debug.apk`.
- Artifacts: `mobile/android/`, `mobile/ios/`, `mobile/lib/client_preferences.dart`, `mobile/lib/controller_connection.dart`, `mobile/lib/gamepad_input_model.dart`, `mobile/lib/gamepad_state.dart`, `mobile/lib/input_send_scheduler.dart`, `mobile/lib/main.dart`, `mobile/test/input_send_scheduler_test.dart`, `mobile/pubspec.yaml`, `mobile/pubspec.lock`, `AGENTS.md`, `docs/acceptance.md`.
- Exceptions: P1-06 physical Android, ViGEm driver, Windows controller, Wi-Fi-loss, and game checks remain pending human verification.

### P1-06 Verify end to end

- [x] Execute all P1 automated tests.
- [x] Confirm every button, both sticks, D-pad diagonals, and analog triggers in Windows and a real game.
- [x] Confirm stick + button + trigger simultaneous input.
- [x] Confirm wrong PIN creates no target.
- [x] Confirm blocked UDP is reported within two seconds.
- [x] Confirm app kill, app suspension, WiFi loss, pointer cancellation, and server stop neutralize within 300 ms.
- [x] Run for 30 minutes without stuck input.

Gate `G1`: PASS only with one real Android phone, one real X360 target, and timeout-neutralization evidence.

Evidence (2026-08-22):
- Automated: `dotnet restore windows/Pulgapp.sln --force-evaluate` -> PASS, all 10 projects restored with lockfiles evaluated.
- Automated: `dotnet build windows/Pulgapp.sln --configuration Release --no-restore -p:Platform=x64` -> PASS, 0 warnings, 0 errors, duration 3.48 seconds.
- Automated: `dotnet test windows/tests/Pulgapp.Server.Protocol.Tests/Pulgapp.Server.Protocol.Tests.csproj --configuration Release --no-build -p:Platform=x64 --filter "FullyQualifiedName~UdpInputDecoderTests"` -> PASS, 13/13 tests, duration 70 ms.
- Automated: `dotnet test windows/tests/Pulgapp.Server.Protocol.Tests/Pulgapp.Server.Protocol.Tests.csproj --configuration Release --no-build -p:Platform=x64` -> PASS, 13/13 tests, duration 115 ms.
- Automated: `dotnet test windows/tests/Pulgapp.Server.Core.Tests/Pulgapp.Server.Core.Tests.csproj --configuration Release --no-build -p:Platform=x64 --filter "FullyQualifiedName~SessionCoordinatorTests"` -> PASS, 8/8 tests, duration 43 ms.
- Automated: `dotnet test windows/tests/Pulgapp.Server.Core.Tests/Pulgapp.Server.Core.Tests.csproj --configuration Release --no-build -p:Platform=x64` -> PASS, 8/8 tests, duration 51 ms.
- Automated: `dotnet test windows/tests/Pulgapp.Server.Infrastructure.Tests/Pulgapp.Server.Infrastructure.Tests.csproj --configuration Release --no-build -p:Platform=x64 --filter "FullyQualifiedName~X360ReportMapperTests"` -> PASS, 7/7 tests, duration 39 ms.
- Automated: `dotnet test windows/tests/Pulgapp.Server.Infrastructure.Tests/Pulgapp.Server.Infrastructure.Tests.csproj --configuration Release --no-build -p:Platform=x64` -> PASS, 7/7 tests, duration 42 ms.
- Automated: `dotnet test windows/tests/Pulgapp.Server.IntegrationTests/Pulgapp.Server.IntegrationTests.csproj --configuration Release --no-build -p:Platform=x64 --filter "FullyQualifiedName~PulgappServerTests"` -> PASS, 3/3 tests, duration 1 second.
- Automated: `dotnet test windows/tests/Pulgapp.Server.IntegrationTests/Pulgapp.Server.IntegrationTests.csproj --configuration Release --no-build -p:Platform=x64` -> PASS, 3/3 tests, duration 1 second.
- Automated: `dotnet test windows/Pulgapp.sln --configuration Release --no-build -p:Platform=x64` -> PASS, 31/31 driver-free tests.
- Automated: from `mobile/`, `dart pub get` -> PASS, dependencies resolved.
- Automated: from `mobile/`, `dart test test/input_send_scheduler_test.dart` -> PASS, 2/2 tests.
- Automated: from `mobile/`, `dart test test/protocol_test.dart` -> PASS, 3/3 tests.
- Automated: from `mobile/`, `dart analyze` -> PASS, no issues.
- Automated: from `mobile/`, `dart test` -> PASS, 5/5 tests.
- Automated: from `mobile/`, `flutter build apk --debug --no-pub` -> PASS, produced `build/app/outputs/flutter-apk/app-debug.apk`.
- Automated (2026-08-22): from `mobile/`, `dart test test/controller_connection_test.dart` -> PASS, 1/1 test; a fatal `invalid_pin` response returns control to the caller without waiting for the WebSocket close handshake.
- Automated (2026-08-23): from `mobile/`, `dart test test/controller_connection_test.dart` -> PASS, 1/1 test; focused invalid-PIN recovery verification remains driver-free.
- Automated (2026-08-22): from `mobile/`, `dart analyze` -> PASS, no issues; `dart test` -> PASS, 6/6 tests; `flutter build apk --debug --no-pub` -> PASS, produced `build/app/outputs/flutter-apk/app-debug.apk`.
- Manual, user reported: physical Android phone, X360 target, and real-game play all worked; all buttons, sticks, D-pad diagonals, and analog triggers responded quickly and correctly.
- Manual (2026-08-23), user reported: both analog sticks, A, B, and LB stayed active simultaneously with correct input.
- Manual (2026-08-23), user reported: an invalid PIN was rejected and created no target; entering a valid PIN afterwards connected successfully without restarting the app.
- Manual (2026-08-23), user reported: blocking UDP showed the unavailable state and removing the temporary rule restored input without noticeable delay; the required two-second reporting threshold was not measured.
- Manual (2026-08-23), user reported: closing, backgrounding, opening notifications, locking the phone while holding a control, and stopping the server disconnected safely; opening notifications is an Android inactive-lifecycle transition. The required 300 ms neutralization threshold and an isolated Wi-Fi-loss observation were not measured.
- Manual (2026-08-23), user reported: UDP unavailable appeared in under two seconds; input recovered after removing the temporary UDP rule.
- Manual (2026-08-23), user reported: app-close, suspension, pointer cancellation, Wi-Fi loss, and server-stop neutralization completed in under 300 ms; turning off the router confirmed the isolated Wi-Fi-loss case.
- Manual, user reported: temporarily blocking UDP with a firewall rule prevented input/UDP operation, and removing the rule restored operation; the required two-second reporting threshold was not measured.
- Manual, user reported: app kill, app suspension, WiFi loss, pointer cancellation, and server stop neutralized input correctly with no observed safety issue; the required 300 ms threshold was not measured.
- Manual, user reported: 30-minute real-game test completed without noticeable delay or stuck input.
- Artifacts: `mobile/lib/controller_connection.dart`, `mobile/lib/main.dart`, `mobile/test/controller_connection_test.dart`; device, OS, and game model/version were not provided.
- Gate G1: PASS. One real Android phone controls one real X360 target with measured UDP-unavailable reporting and timeout-neutralization evidence.

## Phase P2: Four Independent X360 Clients

Goal: support the XInput maximum with stable slot ownership and reconnection.

### P2-01 Generalize lobby and session ownership

- [x] Support slots 1-4 with atomic lowest-free allocation.
- [x] Connect the target before publishing the slot.
- [x] Add 15-second neutralized leases.
- [x] Reuse target and slot only with a valid resume token.
- [x] Issue fresh session, UDP, and resume tokens after every resume.
- [x] Make explicit leave and kick free the slot immediately.
- [x] Handle a duplicate client ID according to the protocol.

Evidence (2026-08-23):
- Automated: `dotnet test windows/tests/Pulgapp.Server.Core.Tests/Pulgapp.Server.Core.Tests.csproj --configuration Release --no-build -p:Platform=x64 --filter "FullyQualifiedName~SessionCoordinatorTests"` -> PASS, 7/7 tests, duration 43 ms.
- Automated: `dotnet test windows/tests/Pulgapp.Server.IntegrationTests/Pulgapp.Server.IntegrationTests.csproj --configuration Release -p:Platform=x64 --filter "FullyQualifiedName~Four_clients"` -> PASS, 1/1 test, duration 308 ms.
- Automated: `dotnet test windows/tests/Pulgapp.Server.Core.Tests/Pulgapp.Server.Core.Tests.csproj --configuration Release --no-build -p:Platform=x64` -> PASS, 7/7 tests, duration 51 ms.
- Automated: `dotnet test windows/tests/Pulgapp.Server.IntegrationTests/Pulgapp.Server.IntegrationTests.csproj --configuration Release --no-build -p:Platform=x64` -> PASS, 4/4 tests, duration 772 ms.
- Automated: `dotnet build windows/src/Pulgapp.Server.Infrastructure/Pulgapp.Server.Infrastructure.csproj --configuration Release --no-restore -p:Platform=x64` -> PASS, 0 warnings, 0 errors.
- Automated: `dotnet test windows/Pulgapp.sln --configuration Release --no-build -p:Platform=x64` -> PASS, 31/31 driver-free tests.
- Artifacts: `windows/src/Pulgapp.Server.Core/SessionCoordinator.cs`, `windows/src/Pulgapp.Server.Infrastructure/PulgappServer.cs`, `windows/tests/Pulgapp.Server.Core.Tests/SessionCoordinatorTests.cs`, `windows/tests/Pulgapp.Server.IntegrationTests/PulgappServerTests.cs`.
- Exceptions: Human multi-phone, driver, and game checks remain pending P2-03. The full solution build is blocked while an already-running `Pulgapp.Server.App` process holds its output DLLs; the changed Infrastructure project builds successfully.

### P2-02 Add load generation and concurrency verification

- [x] Implement a loopback load generator using the real WebSocket and UDP protocol.
- [x] Simulate 1-8 clients, configurable rate, fixed states, sequence wrap, packet loss, duplicates, and reordering.
- [x] Verify four clients at 120 Hz for two hours.
- [x] Verify no session can update another session's target.
- [x] Verify a fifth X360 request receives `server_full`.

Evidence (2026-08-24):
- Automated: `dotnet build windows/tools/Pulgapp.LoadGenerator/Pulgapp.LoadGenerator.csproj --configuration Release --no-restore -p:Platform=x64` -> PASS, 0 warnings, 0 errors, duration 8.07 seconds.
- Automated: `dotnet run --project windows/tools/Pulgapp.LoadGenerator/Pulgapp.LoadGenerator.csproj --configuration Release --no-build -p:Platform=x64 -- --clients 5 --rate-hz 120 --duration-seconds 10 --loss-every 7 --duplicate-every 5 --reorder-every 9` -> PASS, four independent fixed states with sequence wrap, loss, duplicates, and reordering; mismatched session/token datagrams changed no target; fifth client received `server_full`.
- Automated: `dotnet run --project windows/tools/Pulgapp.LoadGenerator/Pulgapp.LoadGenerator.csproj --configuration Release --no-build -p:Platform=x64 -- --clients 8 --rate-hz 120 --duration-seconds 10 --loss-every 7 --duplicate-every 5 --reorder-every 9` -> PASS, four active X360 clients and four `server_full` rejections; confirms the P2 simulator accepts the 1-8 range while slots 5-8 remain unavailable until P3.
- Automated: `dotnet run --project windows/tools/Pulgapp.LoadGenerator/Pulgapp.LoadGenerator.csproj --configuration Release --no-build -p:Platform=x64 -- --clients 4 --rate-hz 120 --duration-seconds 7200 --loss-every 7 --duplicate-every 5 --reorder-every 9` -> PASS, four clients at 120 Hz for 7,200 seconds with internal fixed-state, sequence-wrap, loss, duplicate, reorder, and session-isolation assertions.
- Automated: `dotnet build windows/Pulgapp.sln --configuration Release --no-restore -p:Platform=x64` -> PASS, 0 warnings, 0 errors, duration 3.30 seconds.
- Automated: `dotnet test windows/tests/Pulgapp.Server.IntegrationTests/Pulgapp.Server.IntegrationTests.csproj --configuration Release --no-build -p:Platform=x64 --filter "FullyQualifiedName~PulgappServerTests"` -> PASS, 4/4 tests, duration 725 ms.
- Automated: `dotnet test windows/Pulgapp.sln --configuration Release --no-build -p:Platform=x64` -> PASS, 31/31 driver-free tests.
- Artifacts: `windows/tools/Pulgapp.LoadGenerator/Program.cs`, `windows/tools/Pulgapp.LoadGenerator/Pulgapp.LoadGenerator.csproj`, `AGENTS.md`.
- Exceptions: Human multi-phone, driver, reconnection, and game checks remain pending P2-03.

### P2-03 Complete multi-client UI and hardware checks

- [x] Show four independent slot rows and administrative actions.
- [x] Display Pulgapp slot separately from XInput user index.
- [ ] Test four real Android phones simultaneously.
- [ ] Test reconnect inside and outside the lease window.

Gate `G2`: PASS only when four phones independently control four X360 targets for the required stability run.

Evidence (2026-08-24):
- Automated: `dotnet build windows/Pulgapp.sln --configuration Release --no-restore -p:Platform=x64` -> PASS, 0 warnings, 0 errors, duration 9.33 seconds.
- Automated: `dotnet test windows/tests/Pulgapp.Server.IntegrationTests/Pulgapp.Server.IntegrationTests.csproj --configuration Release --no-build -p:Platform=x64 --filter "FullyQualifiedName~PulgappServerTests"` -> PASS, 4/4 tests, duration 831 ms.
- Automated: `dotnet test windows/tests/Pulgapp.Server.IntegrationTests/Pulgapp.Server.IntegrationTests.csproj --configuration Release --no-build -p:Platform=x64` -> PASS, 4/4 tests, duration 776 ms.
- Automated: `dotnet test windows/Pulgapp.sln --configuration Release --no-build -p:Platform=x64` -> PASS, 31/31 driver-free tests.
- Artifacts: `windows/src/Pulgapp.Server.App/MainWindow.xaml`, `windows/src/Pulgapp.Server.App/MainWindow.xaml.cs`, `windows/src/Pulgapp.Server.Core/SessionCoordinator.cs`, `windows/src/Pulgapp.Server.Infrastructure/PulgappServer.cs`, `windows/tests/Pulgapp.Server.IntegrationTests/PulgappServerTests.cs`.
- Exceptions: Four real Android phones, lease-window reconnection, driver, Windows device, and game checks remain pending human verification; Gate G2 remains unchecked.

## Phase P3: DS4 Slots Five Through Eight

Goal: expose four additional HID devices without violating the XInput limit.

### P3-01 Implement the DS4 adapter

- [ ] Add pure DS4 report mapping with full tests.
- [ ] Invert only DS4 Y axes.
- [ ] Convert canonical D-pad bits to one DS4 hat direction.
- [ ] Map A/B/X/Y to Cross/Circle/Square/Triangle.
- [ ] Set analog L2/R2 values and their digital button state when nonzero.
- [ ] Set `AutoSubmitReport = false` and submit one complete report per snapshot.

Evidence: pending.

### P3-02 Expand lobby and perform eight-client tests

- [ ] Enable slots 5-8 as fixed DS4 targets.
- [ ] Refuse any attempt to configure slots 5-8 as X360.
- [ ] Extend WPF status and load generator to eight clients.
- [ ] Run eight simulated clients for two hours.
- [ ] Run the complete compatibility matrix again with real devices/phones.

Gate `G3`: PASS only when Pummel Party accepts eight independent players from four X360 plus four DS4 targets.

Evidence: pending.

## Phase P4: Discovery And Robust Recovery

- [ ] Pin `Makaretu.Dns.Multicast` 0.27.0 in Windows Infrastructure and `multicast_dns` 0.3.3+1 in Flutter; keep both behind discovery modules because mDNS remains optional.
- [ ] Advertise `_pulgapp._tcp.local.` without exposing the PIN.
- [ ] Discover with Flutter mDNS and retain manual entry.
- [ ] Hold Android multicast resources only during discovery.
- [ ] Implement reconnect delays of 250 ms, 500 ms, 1 s, and then 2 s until lease expiry.
- [ ] Add clear states for control connected/input missing and discovery blocked.
- [ ] Test mDNS success, mDNS failure, AP isolation, WiFi toggle, and server restart.

Gate `G4`: automatic discovery works on supported LANs and manual IPv4 remains reliable everywhere else.

## Phase P5: Product UX And Optional Feedback

- [ ] Add versioned local controller profiles without changing the wire protocol.
- [ ] Add layout movement/sizing, button remapping, dead zones, sensitivity, and local haptics.
- [ ] Add optional rumble forwarding over WebSocket.
- [ ] Add QR connection, tray behavior, single-instance handling, and start-at-login.
- [ ] Verify safe areas and multitouch on small phones and tablets.

Gate `G5`: invalid profiles recover to defaults and no customization can bypass neutralization behavior.

## Phase P6: Packaging And Release Hardening

- [ ] Publish the Windows host self-contained for `win-x64` as a folder, not single-file until native loading is proven.
- [ ] Build a WiX installer and Private/LocalSubnet-only TCP and UDP firewall rules.
- [ ] Detect a Public Windows network and explain remediation instead of opening Public access.
- [ ] Keep ViGEmBus installation as an explicit prerequisite until redistribution licensing and upgrade behavior are reviewed.
- [ ] Produce a signed Android APK.
- [ ] Add CI for restore, formatting, build, unit tests, integration tests, and APK build.
- [ ] Test install, upgrade, run, and uninstall on clean Windows 10 and Windows 11 systems.

Gate `G6`: clean-machine installation and the release checklist in `docs/acceptance.md` pass.

## Deferred Until After V1

- Official iOS distribution and TestFlight testing.
- Internet relay, cloud accounts, or NAT traversal.
- Bluetooth HID or console pairing.
- Generic keyboard/mouse emulation.
- A Windows Service.
- Automatic driver replacement or an unvalidated ViGEm alternative.
