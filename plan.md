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

- Current phase: `P0 - Toolchain, protocol fixture, and driver compatibility spike`
- Next task: `P0-03`
- Last completed task: `P0-02`
- Blockers: Flutter doctor reports a non-blocking `0.0.0-unknown` version-metadata warning and that the Visual Studio Windows desktop workload is absent; neither is required for the Android client or the .NET WPF host. Human driver and game checks remain pending.
- Blocking gate: Pummel Party must recognize four X360 plus four DS4 virtual targets.

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

- [ ] Create `windows/Pulgapp.sln` using the .NET 10 SDK.
- [ ] Create WPF project `Pulgapp.Server.App` targeting `net10.0-windows` and x64.
- [ ] Create class libraries `Pulgapp.Server.Core`, `Pulgapp.Server.Protocol`, and `Pulgapp.Server.Infrastructure`.
- [ ] Create xUnit projects for Core, Protocol, Infrastructure, and Integration tests.
- [ ] Create console tools `Pulgapp.DriverDiagnostics` and `Pulgapp.LoadGenerator`.
- [ ] Add all projects to the solution and project references according to `docs/architecture.md`.
- [ ] Enable nullable reference types, implicit usings, deterministic builds, warnings as errors for repository code, and NuGet lockfiles.
- [ ] Pin `Nefarius.ViGEm.Client` 1.21.256 only in Infrastructure and DriverDiagnostics.
- [ ] Add exact restore, build, focused-test, and full-test commands to `AGENTS.md`.

Evidence: pending.

### P0-04 Implement driver diagnostics

- [ ] Detect and classify ViGEm bus missing, access failure, and version mismatch errors.
- [ ] Create one neutral X360 target, submit deterministic test states, neutralize, and disconnect.
- [ ] Create one neutral DS4 target and repeat the test.
- [ ] Create four X360 and four DS4 targets simultaneously.
- [ ] Always neutralize and dispose every successfully created target on cancellation, failure, or process exit.
- [ ] Keep diagnostics isolated from the production WPF composition root.

Evidence: pending.

### P0-05 Execute the eight-player compatibility gate

- [ ] Follow `docs/compatibility-test.md` on a real PC.
- [ ] Verify one X360 and one DS4 in Windows.
- [ ] Verify four X360 and four DS4 in Windows.
- [ ] Test Pummel Party with Steam Input disabled.
- [ ] If needed, test the documented Steam Input variants without running DS4Windows or XOutput.
- [ ] Record whether all eight devices can join independently inside Pummel Party.
- [ ] Record It Takes Two behavior with two X360 targets.

Gate `G0`: PASS only if Pummel Party accepts eight independent inputs. If it fails, stop product implementation and document the exact failure. Do not invent a fallback target type.

Evidence: pending human hardware/game test.

## Phase P1: One Android Phone To One X360

Goal: deliver one complete low-latency and fail-safe path using the final protocol shape.

### P1-01 Implement protocol models and codecs

- [ ] Implement C# control DTOs and strict UDP v1 decoding in `Pulgapp.Server.Protocol`.
- [ ] Implement Dart control DTOs and UDP v1 encoding.
- [ ] Make both test suites consume `protocol/fixtures/input-state-v1.bin` from the repository root.
- [ ] Test all offsets, endianness, ranges, invalid length, magic, version, type, flags, and reserved button handling.
- [ ] Implement modular `uint32` sequence comparison and wrap tests.

Evidence: pending.

### P1-02 Implement the driver-independent core

- [ ] Add immutable canonical `GamepadState` with neutral singleton.
- [ ] Add `VirtualController` and `VirtualControllerFactory` seams described in `docs/architecture.md`.
- [ ] Add pure X360 report mapping tests before using ViGEm.
- [ ] Add `SessionCoordinator` for one slot with token validation and a 250 ms watchdog.
- [ ] Use `TimeProvider` so timeout tests do not sleep.
- [ ] Ensure WebSocket loss, explicit leave, timeout, shutdown, and cancellation all reach neutralization.

Evidence: pending.

### P1-03 Implement Windows transport and X360 adapter

- [ ] Host `GET /health` and WebSocket `/control` on TCP 26760.
- [ ] Bind one IPv4 UDP socket on port 26761.
- [ ] Implement hello, welcome, ping/pong, input-ready, status, leave, suspend, and errors exactly as specified.
- [ ] Generate PIN and tokens cryptographically; never log their values.
- [ ] Validate UDP source IP against the WebSocket peer.
- [ ] Set `AutoSubmitReport = false`, update the complete X360 report, and submit once.
- [ ] Serialize updates through a bounded per-session worker, never on the WPF dispatcher.

Evidence: pending.

### P1-04 Implement the minimal WPF dashboard

- [ ] Show driver status, server status, candidate LAN IPv4 addresses, ports, and PIN.
- [ ] Show one slot with client name, connection state, last input age, packet rate, and RTT.
- [ ] Provide Regenerate PIN, Kick, Start Server, and Stop Server actions.
- [ ] Stop accepting connections before neutralizing and disposing targets during shutdown.
- [ ] Keep normal runtime non-elevated.

Evidence: pending.

### P1-05 Bootstrap and implement the Flutter client

- [ ] Create Flutter project under `mobile/` with Android and iOS scaffolds.
- [ ] Set Android min SDK 26, landscape orientation, cleartext LAN network configuration, Internet permission, vibration permission, and screen-awake behavior.
- [ ] Persist a random client UUID and the last successful endpoint.
- [ ] Implement manual IPv4/hostname plus six-digit PIN connection UI.
- [ ] Implement one connection module that owns WebSocket, UDP, tokens, state, and cleanup.
- [ ] Implement the 120 Hz cap, 50 ms unchanged heartbeat, and immediate neutral snapshots.
- [ ] Implement raw multitouch controls with pointer IDs, including pointer cancellation.
- [ ] Use canonical Xbox labels and canonical Y-positive-up values.

Evidence: pending.

### P1-06 Verify end to end

- [ ] Execute all P1 automated tests.
- [ ] Confirm every button, both sticks, D-pad diagonals, and analog triggers in Windows and a real game.
- [ ] Confirm stick + button + trigger simultaneous input.
- [ ] Confirm wrong PIN creates no target.
- [ ] Confirm blocked UDP is reported within two seconds.
- [ ] Confirm app kill, app suspension, WiFi loss, pointer cancellation, and server stop neutralize within 300 ms.
- [ ] Run for 30 minutes without stuck input.

Gate `G1`: PASS only with one real Android phone, one real X360 target, and timeout-neutralization evidence.

Evidence: pending.

## Phase P2: Four Independent X360 Clients

Goal: support the XInput maximum with stable slot ownership and reconnection.

### P2-01 Generalize lobby and session ownership

- [ ] Support slots 1-4 with atomic lowest-free allocation.
- [ ] Connect the target before publishing the slot.
- [ ] Add 15-second neutralized leases.
- [ ] Reuse target and slot only with a valid resume token.
- [ ] Issue fresh session, UDP, and resume tokens after every resume.
- [ ] Make explicit leave and kick free the slot immediately.
- [ ] Handle a duplicate client ID according to the protocol.

Evidence: pending.

### P2-02 Add load generation and concurrency verification

- [ ] Implement a loopback load generator using the real WebSocket and UDP protocol.
- [ ] Simulate 1-8 clients, configurable rate, fixed states, sequence wrap, packet loss, duplicates, and reordering.
- [ ] Verify four clients at 120 Hz for two hours.
- [ ] Verify no session can update another session's target.
- [ ] Verify a fifth X360 request receives `server_full`.

Evidence: pending.

### P2-03 Complete multi-client UI and hardware checks

- [ ] Show four independent slot rows and administrative actions.
- [ ] Display Pulgapp slot separately from XInput user index.
- [ ] Test four real Android phones simultaneously.
- [ ] Test reconnect inside and outside the lease window.

Gate `G2`: PASS only when four phones independently control four X360 targets for the required stability run.

Evidence: pending.

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
