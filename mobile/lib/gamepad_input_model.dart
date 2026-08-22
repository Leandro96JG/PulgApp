import 'package:flutter/foundation.dart';

import 'gamepad_state.dart';

/// Owns canonical state. Widgets only report pointer transitions here.
final class GamepadInputModel extends ChangeNotifier {
  GamepadState _state = GamepadState.neutral;
  final Map<int, int> _buttonPointers = {};
  final Map<int, _StickPointer> _stickPointers = {};
  final Map<int, _TriggerPointer> _triggerPointers = {};

  GamepadState get state => _state;

  void pressButton(int pointer, int button) {
    _buttonPointers[pointer] = button;
    _updateButtons();
  }

  void releasePointer(int pointer) {
    final removed = _buttonPointers.remove(pointer) != null;
    _stickPointers.remove(pointer);
    _triggerPointers.remove(pointer);
    if (removed) {
      _updateButtons();
    } else {
      _updateAxes();
    }
  }

  void updateStick({
    required int pointer,
    required bool left,
    required double x,
    required double y,
  }) {
    _stickPointers[pointer] = _StickPointer(left, x, y);
    _updateAxes();
  }

  void updateTrigger({
    required int pointer,
    required bool left,
    required double amount,
  }) {
    _triggerPointers[pointer] = _TriggerPointer(left, amount);
    _updateAxes();
  }

  void cancelAll() {
    _buttonPointers.clear();
    _stickPointers.clear();
    _triggerPointers.clear();
    _setState(GamepadState.neutral);
  }

  void _updateButtons() {
    var buttons = 0;
    for (final button in _buttonPointers.values) {
      buttons |= button;
    }
    _setState(_state.copyWith(buttons: buttons));
  }

  void _updateAxes() {
    var leftX = 0;
    var leftY = 0;
    var rightX = 0;
    var rightY = 0;
    for (final stick in _stickPointers.values) {
      final x = _axis(stick.x);
      // Flutter's screen Y grows down; canonical gamepad Y grows up.
      final y = _axis(-stick.y);
      if (stick.left) {
        leftX = x;
        leftY = y;
      } else {
        rightX = x;
        rightY = y;
      }
    }
    var leftTrigger = 0;
    var rightTrigger = 0;
    for (final trigger in _triggerPointers.values) {
      final amount = (trigger.amount.clamp(0.0, 1.0) * 65535).round();
      if (trigger.left) {
        leftTrigger = amount;
      } else {
        rightTrigger = amount;
      }
    }
    _setState(
      _state.copyWith(
        leftX: leftX,
        leftY: leftY,
        rightX: rightX,
        rightY: rightY,
        leftTrigger: leftTrigger,
        rightTrigger: rightTrigger,
      ),
    );
  }

  void _setState(GamepadState next) {
    if (next == _state) return;
    _state = next;
    notifyListeners();
  }

  static int _axis(double value) => (value.clamp(-1.0, 1.0) * 32767).round();
}

final class _StickPointer {
  const _StickPointer(this.left, this.x, this.y);
  final bool left;
  final double x;
  final double y;
}

final class _TriggerPointer {
  const _TriggerPointer(this.left, this.amount);
  final bool left;
  final double amount;
}
