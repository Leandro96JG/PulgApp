# Acceptance And Evidence

No phase is complete without evidence for every applicable item in this file. Automated evidence is command output from the current worktree. Manual evidence is a dated human observation on named hardware/software.

## Evidence Format

Record evidence under the matching task in `plan.md`:

```text
Evidence (YYYY-MM-DD):
- Automated: `<exact command>` -> PASS, N tests, duration.
- Manual: device/OS/game version, observed result, tester name or "user reported".
- Artifacts: relative paths to logs/screenshots/reports.
- Exceptions: skipped checks and the concrete reason.
```

Do not paste secrets, PINs, tokens, machine usernames, or absolute user-profile paths.

## Verification Commands

The Windows solution is bootstrapped. The following commands are run from the repository root; mobile commands remain pending until P1-05 bootstraps Flutter.

The completed command table must contain:

| Scope | Required command |
|---|---|
| Windows restore | `dotnet restore windows/Pulgapp.sln --force-evaluate` |
| Windows build | `dotnet build windows/Pulgapp.sln --configuration Release --no-restore -p:Platform=x64` |
| One C# test | `dotnet test windows/tests/Pulgapp.Server.Protocol.Tests/Pulgapp.Server.Protocol.Tests.csproj --configuration Release --no-build --filter "FullyQualifiedName~UnitTest1.Test1"` |
| One C# project | `dotnet test windows/tests/Pulgapp.Server.Protocol.Tests/Pulgapp.Server.Protocol.Tests.csproj --configuration Release --no-build` |
| All driver-free C# tests | `dotnet test windows/Pulgapp.sln --configuration Release --no-build -p:Platform=x64` |
| Driver diagnostics | `dotnet run --project windows/tools/Pulgapp.DriverDiagnostics/Pulgapp.DriverDiagnostics.csproj --configuration Release --no-build -p:Platform=x64` (hardware-only) |
| Flutter dependencies | Pending P1-05 mobile bootstrap |
| One Dart test | Pending P1-05 mobile bootstrap |
| Flutter analyze | Pending P1-05 mobile bootstrap |
| All mobile tests | Pending P1-05 mobile bootstrap |
| APK build | Pending P1-05 mobile bootstrap |

## Global Safety Acceptance

- [ ] Every accepted packet applies one complete report, never a delta.
- [ ] Every path that loses ownership neutralizes before disconnecting or leasing.
- [ ] A malformed, stale, duplicated, or unauthenticated UDP packet cannot change a target.
- [ ] One session cannot address another session's target.
- [ ] Each ViGEm target receives serialized calls.
- [ ] No PIN, UDP token, or resume token appears in logs or UI diagnostics exports.
- [ ] Normal automated tests pass on a machine without ViGEmBus.
- [ ] Production firewall rules are Private profile plus `LocalSubnet` only.

## Gate G0: Driver And Game Feasibility

- [ ] One X360 target is visible and responds in Windows.
- [ ] One DS4 target is visible and responds in Windows.
- [ ] Four X360 and four DS4 targets coexist.
- [ ] Pummel Party allows eight independent devices to join.
- [ ] The working Steam Input setting is documented.
- [ ] It Takes Two accepts two X360 devices.

Failure policy: stop after documenting the failed matrix. Device enumeration alone is not a partial pass for the product's eight-player objective.

## Gate G1: One Phone End To End

- [ ] Real Android phone connects using manual IPv4 and PIN.
- [ ] All digital controls map correctly.
- [ ] Both sticks have correct center, direction, and full-scale behavior.
- [ ] LT and RT report analog values.
- [ ] At least one stick, one button, and one trigger work simultaneously.
- [ ] Wrong PIN creates no virtual target.
- [ ] UDP failure is distinguished from WebSocket failure.
- [ ] App suspension, app kill, WiFi loss, server stop, and pointer cancellation neutralize within 300 ms.
- [ ] Thirty-minute play/soak test produces no stuck state.

## Gate G2: Four X360 Clients

- [ ] Four phones receive unique slots 1-4.
- [ ] Four independent fixed test states appear on four targets.
- [ ] Fifth client receives `server_full` without target leakage.
- [ ] Resume inside 15 seconds keeps target identity and slot.
- [ ] Lease expiry neutralizes, disconnects, and frees the slot.
- [ ] Four-client 120 Hz load test runs for two hours.
- [ ] Four-real-phone test passes.

## Gate G3: Eight Mixed Controllers

- [ ] Slots 1-4 are X360 and slots 5-8 are DS4.
- [ ] DS4 Y axes, hat directions, face buttons, and triggers map correctly.
- [ ] Eight-client simulated load test runs for two hours.
- [ ] Eight real clients or the agreed real-phone/load-generator combination remain independent.
- [ ] Pummel Party allows all eight to join and control distinct players.
- [ ] Existing two-player X360 behavior remains valid.

## Gate G4: Discovery And Recovery

- [ ] mDNS finds the server on a supported flat LAN.
- [ ] Discovery exposes no PIN or session secret.
- [ ] Manual IPv4 works when multicast is blocked.
- [ ] Reconnect backoff follows the specified schedule.
- [ ] Reconnect inside the lease preserves the target.
- [ ] Server restart and expired lease produce a clear new-pairing state.
- [ ] Android releases multicast resources after leaving discovery.

## Gate G5: Customization

- [ ] Profiles are versioned and invalid data recovers to defaults.
- [ ] Remapping changes mobile canonical state, not the wire schema.
- [ ] Layout remains usable on the smallest and largest tested screens.
- [ ] Customization cannot disable cancellation or timeout neutralization.
- [ ] Rumble failure never delays or disconnects input.

## Gate G6: Release

- [ ] Clean Windows 10 22H2 x64 install.
- [ ] Clean Windows 11 x64 install.
- [ ] Missing driver has an actionable health error.
- [ ] App runtime is non-elevated.
- [ ] Firewall rules are removed by uninstall.
- [ ] Signed APK installs on a clean Android device.
- [ ] CI restores from lockfiles and reproduces test/build artifacts.
- [ ] Upgrade preserves user settings but not transient credentials.
- [ ] Uninstall leaves no active virtual targets.

## Performance Budgets

These are budgets measured on a healthy local network, not universal latency guarantees:

| Metric | Budget |
|---|---:|
| Mobile change coalescing | At most 8 ms |
| UDP receive to ViGEm submit p95 | Under 5 ms |
| Control RTT p95 | Under 25 ms |
| Missing-input neutralization | Under 300 ms observed |
| Eight clients at 120 Hz | Under 10% of a representative four-core x64 CPU |
| Windows host memory | Under 200 MB |

Record the hardware and measurement method with every performance result.
