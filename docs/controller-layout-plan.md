# Controller Touch Layout Plan

## Status And Scheduling

This document specifies the P5 controller-layout redesign. Its fixed touch-first layout was implemented on 2026-08-31 after the user rejected the physical-gamepad imitation as cramped and hard to control. It does not change protocol v1, slot behavior, reconnection, input scheduling, or neutralization safety.

## Objective

Make the phone usable as a controller without watching its screen during play. Increase effective touch areas, prioritize natural thumb reach over Xbox/PlayStation geometry, preserve reliable multi-touch, and keep connection information visible without consuming the gameplay surface.

Success means a player can locate the sticks, D-pad, face buttons, bumpers, and triggers by position and reach them comfortably with both thumbs and index fingers in landscape orientation.

## Current Problems

- Primary buttons are only 46 logical pixels in diameter.
- Sticks are fixed at 96 logical pixels and do not scale with the available height.
- Face-button and D-pad clusters are fixed at 120 logical pixels.
- The left-side order places the D-pad above the left stick, opposite the familiar Xbox layout.
- Shoulder controls share one narrow row and do not provide strong edge landmarks.
- Back, Start, and Guide compete with the gameplay controls.
- Connection status is an overlay instead of a reserved, non-interactive status area.
- All controller widgets live in `mobile/lib/main.dart`, making layout iteration and widget testing harder.

## Design Direction

Treat the phone as a dedicated handheld instrument, not a dashboard. Use a quiet graphite surface with edge-defined control zones and Xbox face-button colors as the only strong accents.

### Visual Tokens

- `surface`: `#101419`
- `control`: `#252C34`
- `controlPressed`: `#E8EEF4`
- `outline`: `#46515E`
- `statusOk`: `#61D6A3`
- `statusWarning`: `#FFB454`
- Face buttons: A `#56C271`, B `#E35D67`, X `#4E9BE8`, Y `#E7C64D`
- Use the platform sans-serif in semibold for control labels and tabular figures for status where available. Do not add a font dependency for this task.

### Signature Element

Use broad rounded touch panels, with the primary stick and the colored action grid anchoring opposite edges. No decorative overlays share their hit areas.

## Landscape Layout

Use four independent hand zones: a large left stick, one continuous D-pad, a right stick, and a 2x2 action-button grid. Shoulder controls sit against the top edge and secondary controls use one recessed bottom row. This deliberately does not imitate a physical gamepad.

```text
+--------------------------------------------------------------------------+
| [ LT trigger zone ] [ LB ]   slot/status   [ RB ] [ RT trigger zone ]    |
|                                                                          |
| ( LARGE LEFT STICK ) | D-PAD | RIGHT STICK |  [X] [Y]                    |
|                      | slide |             |  [A] [B]                    |
|       [L3]            [Back]    [Guide]       [Start]            [R3]     |
+--------------------------------------------------------------------------+
```

The drawing shows relationships, not fixed coordinates. The final layout must derive sizes from available width and height.

## Responsive Geometry

Support landscape logical sizes from 640x320 upward, including display cutouts and system safe areas.

- Reserve 48-60 logical pixels for the status/shoulder band and 48 for the bottom secondary row.
- Split the main surface using `3 / 2 / 2 / 3` flex units for left stick, D-pad, right stick, and actions.
- Primary face buttons use four non-overlapping rounded rectangles with an 8-pixel gutter; their entire rectangle accepts input.
- Sticks accept input across their complete rectangular zone and establish a floating neutral origin wherever the thumb first lands.
- The D-pad uses one continuous rectangular gesture surface with eight-way sliding and a central dead zone.
- Bumpers and triggers: at least 48 logical pixels high; place them against the top edge so fingers can find them by touch.
- Back, Guide, and Start: at least 48x48 logical pixels, with 8 logical pixels between hit areas.
- Keep at least 8 logical pixels of dead space between unrelated controls to reduce accidental activation.
- If space is constrained, reduce decorative padding first, then secondary controls, and primary controls last.
- No control may overlap the safe-area inset or produce a Flutter overflow at 640x320, 740x360, 800x360, 915x412, or 1280x720.

## Interaction Requirements

- Preserve independent pointer IDs so any valid combination can be held simultaneously.
- Keep complete-state snapshots and the existing send scheduler unchanged.
- `onPointerCancel`, app suspension, navigation, WebSocket loss, and disposal must continue to neutralize input.
- Every press must have an immediate visual state change. Optional haptics remain a separate P5 feature.
- Sticks must clamp to their circular range and return to neutral on pointer release or cancellation.
- The D-pad must support diagonals with one continuous pointer gesture; sliding between directions must not require lifting the finger.
- Face buttons must support sliding between buttons only if the implementation explicitly transfers ownership without leaving a stuck bit. Otherwise, require release before another button claims that pointer.
- Trigger behavior must remain protocol-compatible. Do not silently convert analog triggers to digital-only buttons. If the larger trigger surface changes its gesture, add model tests for minimum, midpoint, maximum, release, and cancellation.
- Status and decorative grip zones must use `IgnorePointer` so they cannot steal gameplay touches.
- Back, Guide, and Start should be visually recessed to avoid accidental presses but must retain accessible touch targets.

## Information Hierarchy

During gameplay show only:

- Slot number.
- Connected, reconnecting, or input unavailable state.
- A concise warning when UDP input is unavailable.

Do not show IP, PIN, packet rate, or instructional copy on the controller surface. Use semantics labels such as `A button`, `left stick`, and `D-pad up` for accessibility and widget-test lookup.

## Proposed Code Shape

Keep connection and lifecycle ownership in `ControllerPage`, but extract layout concerns:

- `mobile/lib/main.dart`: application bootstrap, connection page, navigation and existing controller connection/lifecycle ownership.
- `mobile/lib/controller/touch_controller.dart`: responsive four-zone layout, visual tokens, gesture ownership, and controls driven by `GamepadInputModel`.
- `mobile/test/controller_layout_test.dart`: viewport, hit-area, pointer-safety tests and optional screenshot capture.

Do not introduce a third-party state-management or UI package. Continue routing all pointer transitions through `GamepadInputModel`.

## Implementation Steps

1. Add widget tests that capture the current safety behavior before moving widgets: press/release, pointer cancellation, and two simultaneous buttons.
2. Extract `ControllerPage` and controls without intentionally changing behavior; run the focused tests.
3. Add a responsive `ControllerLayoutMetrics` calculation based on `LayoutBuilder`, safe-area padding, and the minimum supported viewport.
4. Implement the four-zone touch-first arrangement and larger control areas.
5. Replace the four independent D-pad circles with a continuous cross/gesture surface that supports diagonals and direction changes.
6. Add visible stick thumb displacement and clear pressed states without changing canonical axis orientation.
7. Reserve the status band and make all non-control layers ignore pointers.
8. Add widget tests for all target viewport sizes and multi-pointer combinations.
9. Run static analysis, all Dart tests, and the Android debug build.
10. Perform manual ergonomic testing on Android, followed later by the deferred multi-phone real-game session.

## Automated Verification

Run from `mobile/` using the repository commands:

```powershell
flutter pub get
flutter analyze --no-pub
flutter test test/controller_layout_test.dart --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
```

Add focused widget/model tests that verify:

- A, B, X, and Y press, release, and cancellation.
- D-pad cardinal directions, all four diagonals, slide transitions, release, and cancellation.
- Left and right sticks can operate simultaneously with two face buttons.
- LB, RB, LT, and RT can be held with sticks and face buttons.
- Back, Start, Guide, L3, and R3 remain reachable.
- No overflow or exception at each target viewport.
- Lifecycle cancellation still sends/returns to a neutral state.

Widget tests do not replace physical multi-touch testing.

## Manual Acceptance Checklist

- [ ] A player can identify primary controls by position after less than five minutes of familiarization.
- [ ] All primary controls can be reached while holding the phone naturally in landscape.
- [ ] Thirty minutes of play produces no hand-blocking layout issue, stuck input, or accidental Guide/Start presses.
- [ ] Four real phones remain independent in Pummel Party or Overcooked! 2.
- [ ] Small phones show no overlap, clipping, or unsafe cutout placement.
- [ ] The UDP-unavailable warning is noticeable without obscuring or disabling controls.
- [ ] App backgrounding, navigation back, pointer cancellation, and disconnect still neutralize safely.

## Out Of Scope

- User-editable control placement and profile persistence.
- Button remapping.
- Dead-zone and sensitivity settings.
- Haptic configuration and rumble forwarding.
- Portrait mode.
- Protocol or server changes.

Those remain separate P5 tasks after the fixed ergonomic layout is validated.

## Validation Record

- Automated layout, multitouch, cancellation and safe-area tests passed on 2026-08-31.
- Manual (2026-09-03, user-reported): the new controls work very well on a real phone.
- This approves the fixed layout only. Tablet coverage and the deferred eight-phone game test remain separate checks.

## Handoff Prompt

Give the implementation model this instruction after Gates G2, G3, and G4 pass:

```text
Implement the fixed ergonomic controller-layout redesign specified in
docs/controller-layout-plan.md. Read AGENTS.md, plan.md, protocol/protocol-v1.md,
docs/architecture.md, and docs/acceptance.md first. Keep protocol, networking,
input scheduling, lifecycle neutralization, and GamepadInputModel ownership intact.
Do not implement editable profiles, remapping, haptics, or other P5 features.
Add the specified focused tests, run the exact mobile verification commands, update
plan.md with evidence, and stop before the next P5 task.
```
