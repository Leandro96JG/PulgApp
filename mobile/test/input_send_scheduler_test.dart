import 'dart:async';

import 'package:pulgapp_mobile/gamepad_state.dart';
import 'package:pulgapp_mobile/input_send_scheduler.dart';
import 'package:test/test.dart';

void main() {
  test('caps changed snapshots and sends an unchanged heartbeat', () async {
    final sent = <GamepadState>[];
    final scheduler = InputSendScheduler(sent.add);
    addTearDown(scheduler.dispose);

    scheduler.start();
    scheduler.update(const GamepadState(buttons: 1));
    scheduler.update(const GamepadState(buttons: 2));
    expect(sent, hasLength(1));
    expect(sent.single.buttons, 1);

    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(sent, hasLength(2));
    expect(sent.last.buttons, 2);

    await Future<void>.delayed(const Duration(milliseconds: 55));
    expect(sent.last.buttons, 2);
    expect(sent.length, greaterThanOrEqualTo(3));
  });

  test('sends three immediate neutral snapshots on safety cleanup', () async {
    final sent = <GamepadState>[];
    final scheduler = InputSendScheduler(sent.add);
    addTearDown(scheduler.dispose);
    scheduler.start();
    scheduler.update(const GamepadState(buttons: 1));

    await scheduler.sendNeutralRedundantly();

    expect(sent.takeLast(3), everyElement(GamepadState.neutral));
  });
}

extension on List<GamepadState> {
  Iterable<GamepadState> takeLast(int count) => skip(length - count);
}
