import 'package:flutter/services.dart';

/// Manages tactile button haptics using Android's native Vibrator service
/// with predefined click effects (zero latency, active braking, crisp touch),
/// with fallback to standard Flutter HapticFeedback when native channels are unavailable.
abstract final class AppHaptics {
  static const _channel = MethodChannel('pulgapp/vibrate');

  /// Crisp, tactile click for button and D-pad touches (zero lag, pleasant click).
  static void buttonPress() {
    try {
      _channel.invokeMethod<void>('click');
    } catch (_) {
      HapticFeedback.lightImpact();
    }
  }

  /// Firmer tactile click for stick clicks (L3/R3) and trigger thresholds.
  static void firmImpact() {
    try {
      _channel.invokeMethod<void>('heavyClick');
    } catch (_) {
      HapticFeedback.mediumImpact();
    }
  }

  /// Subtle tick for minor threshold adjustments.
  static void tick() {
    try {
      _channel.invokeMethod<void>('tick');
    } catch (_) {
      HapticFeedback.selectionClick();
    }
  }
}
