# Driver And Game Compatibility Test

This is a manual hardware/game procedure. An agent may prepare tooling and collect logs, but only a human observation can pass the Pummel Party gate.

## Test Environment Record

Fill this before testing:

```text
Date:
Windows edition/build:
CPU architecture:
ViGEmBus version:
Pulgapp diagnostics build/commit:
Pummel Party version/store:
Steam client version:
Steam Input setting:
Physical controllers connected:
Controller remapping software running:
Tester:
```

## Preparation

1. Reboot after installing or upgrading ViGEmBus.
2. Confirm the network test is not needed for P0; diagnostics drives targets locally.
3. Disconnect unnecessary physical controllers because they can consume XInput indices.
4. Exit DS4Windows, XOutput, BetterJoy, reWASD, and other controller virtualization tools.
5. Do not install or change HidHide as part of this test.
6. Close the game before changing target count or Steam Input settings.
7. Capture diagnostics logs without PINs or tokens.

## Test A: One X360

1. Start diagnostics in one-X360 mode with `--wait-for-cancel`.
2. Open `joy.cpl` and confirm one new controller.
3. Apply neutral and verify no button/axis remains active.
4. Exercise every button, both sticks, D-pad, and triggers.
5. Stop diagnostics and confirm the controller disappears.

Pass requires correct state and cleanup, not enumeration alone.

## Test B: One DS4

1. Start diagnostics in one-DS4 mode with `--wait-for-cancel`.
2. Confirm one new HID game controller in Windows.
3. Verify centered axes, all directions, diagonals, buttons, and analog triggers.
4. Specifically verify canonical up appears as up after DS4 Y inversion.
5. Stop diagnostics and confirm cleanup.

## Test C: Four Plus Four

1. Start diagnostics in eight-target mode with `--wait-for-cancel`.
2. Confirm exactly four X360 and four DS4 targets were created.
3. Assign a unique held state to each target, such as a different button or axis direction.
4. Verify each Windows device shows only its assigned state.
5. Return every target to neutral before opening the game.

Record target creation errors and reported XInput indices. A Pulgapp slot number is not proof of an XInput index.

## Test D: Pummel Party

Run variants in this order and stop once a stable eight-player configuration is found:

| Variant | Steam Input | Other remappers |
|---|---|---|
| D1 | Disabled for Pummel Party | All closed |
| D2 | Default | All closed |
| D3 | Enabled for Pummel Party | All closed |

For each variant:

1. Start the eight neutral virtual targets before launching the game.
2. Launch Pummel Party.
3. Open local multiplayer/lobby.
4. Join one target at a time using a unique input.
5. Record detected count after each join.
6. Start a match only if all eight joined.
7. Move each player separately and confirm no cross-control or duplicate input.
8. Disconnect/reconnect only after the baseline eight-player result is recorded.
9. Exit the game, stop diagnostics, and confirm all targets disappear.

Pass requires eight independently controllable in-game players. Seeing eight Windows devices is not sufficient.

Use a terminal opened manually before launching the diagnostic. For `joy.cpl`, keep the deterministic states. For Pummel Party, start the targets neutral, schedule one brief join pulse after enough time to open the local lobby, then schedule distinct held inputs after the match begins. The recommended game command is:

```powershell
dotnet run --project windows/tools/Pulgapp.DriverDiagnostics/Pulgapp.DriverDiagnostics.csproj --configuration Release -p:Platform=x64 -- --mode eight --wait-for-cancel --join-after-seconds 60 --exercise-after-seconds 180
```

The process writes `All targets remain neutral.`, a 60-second join-pulse schedule, and a 180-second distinct-state exercise schedule. Reach the local lobby before the join pulse, then start a match before the exercise. The join pulse sends A/Cross for 500 ms to all eight targets and returns them to neutral. The later exercise applies a different held button/stick state to each target so independent players must react differently. The targets remain present until `Ctrl+C` is pressed in that terminal. Increase either delay if it is insufficient.

## Test E: It Takes Two

1. Start two neutral X360 targets and schedule the join/exercise states:

```powershell
dotnet run --project windows/tools/Pulgapp.DriverDiagnostics/Pulgapp.DriverDiagnostics.csproj --configuration Release -p:Platform=x64 -- --mode two-x360 --wait-for-cancel --join-after-seconds 60 --exercise-after-seconds 180
```

2. Launch the game with the documented Steam Input setting.
3. Join both local players.
4. Confirm independent movement and actions.
5. Stop diagnostics after exiting the game and confirm cleanup.

## Result Table

| Test | Result | Observed count | Notes/artifacts |
|---|---|---:|---|
| One X360 | Pass | 1 | User reported 2026-08-22: recognized as Xbox controller and works in games. |
| One DS4 | Pass | 1 | User reported 2026-08-22: recognized as Wireless Controller and works in games. |
| Four X360 + four DS4 in Windows | Pass | 8 | User reported 2026-08-22: all eight devices recognized simultaneously. |
| Pummel D1 | Pass | 8 | User reported 2026-08-22: all eight players joined and responded independently in a match. |
| Pummel D2 | Pending | 0 | |
| Pummel D3 | Pending | 0 | |
| It Takes Two | Pending | 0 | |

## Failure Recording

For a failure, record the first failing step, exact exception or game behavior, target count, Steam Input variant, and whether the target worked in Windows immediately before the game test. Do not classify a DS4 recognition failure as a networking issue during P0 because no network path is involved.
