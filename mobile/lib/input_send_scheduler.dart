import 'dart:async';

import 'gamepad_state.dart';

/// Rate-limits changed snapshots while preserving a 50 ms liveness heartbeat.
final class InputSendScheduler {
  InputSendScheduler(this._send, {Duration? minimumInterval})
    : _minimumInterval = minimumInterval ?? const Duration(milliseconds: 8);

  final void Function(GamepadState state) _send;
  final Duration _minimumInterval;
  final Stopwatch _clock = Stopwatch()..start();
  GamepadState _latest = GamepadState.neutral;
  Duration? _lastSent;
  Timer? _coalesceTimer;
  Timer? _heartbeatTimer;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _sendNow();
    });
  }

  void update(GamepadState state) {
    _latest = state;
    if (!_started) return;
    final now = _clock.elapsed;
    final lastSent = _lastSent;
    if (lastSent == null || now - lastSent >= _minimumInterval) {
      _sendNow();
      return;
    }
    _coalesceTimer ??= Timer(_minimumInterval - (now - lastSent), () {
      _coalesceTimer = null;
      _sendNow();
    });
  }

  void sendNeutralNow() {
    _latest = GamepadState.neutral;
    _sendNow();
  }

  Future<void> sendNeutralRedundantly() async {
    for (var attempt = 0; attempt != 3; attempt++) {
      sendNeutralNow();
      if (attempt != 2)
        await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  void dispose() {
    _coalesceTimer?.cancel();
    _heartbeatTimer?.cancel();
  }

  void _sendNow() {
    if (!_started) return;
    _coalesceTimer?.cancel();
    _coalesceTimer = null;
    _lastSent = _clock.elapsed;
    _send(_latest);
  }
}
