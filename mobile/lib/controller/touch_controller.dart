import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../gamepad_input_model.dart';
import '../gamepad_state.dart';
import '../controller_profile.dart';

const _surface = Color(0xff101419);
const _control = Color(0xff252c34);
const _outline = Color(0xff46515e);
const _ink = Color(0xffe8eef4);
const _accent = Color(0xff91bdd8);

/// Touch-first layout. Every control owns a disjoint rectangular hit area.
/// Networking and canonical input remain outside this widget.
class TouchController extends StatefulWidget {
  const TouchController({
    super.key,
    required this.model,
    required this.status,
    this.stickSettings = ControllerStickSettings.defaults,
    this.buttonMapping = ControllerButtonMapping.identity,
    this.layoutSettings = ControllerLayoutSettings.defaults,
    this.enabled = true,
  });
  final GamepadInputModel model;
  final String status;
  final bool enabled;
  final ControllerStickSettings stickSettings;
  final ControllerButtonMapping buttonMapping;
  final ControllerLayoutSettings layoutSettings;

  @override
  State<TouchController> createState() => _TouchControllerState();
}

class _TouchControllerState extends State<TouchController>
    with WidgetsBindingObserver {
  int _gestureEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(TouchController oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) {
      widget.model.cancelAll();
      _gestureEpoch++;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      widget.model.cancelAll();
      // Old pointer moves must not reactivate input after backgrounding.
      setState(() => _gestureEpoch++);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget _button(String slot, {Color color = _ink}) {
    final action = widget.buttonMapping.actionFor(slot);
    return _TouchButton(
      controlId: slot,
      positionLabel: slot,
      label: action.label,
      bit: action.bit,
      model: widget.model,
      color: color,
    );
  }

  Widget _mainZone(String zone) => switch (zone) {
    'leftStick' => _Stick(
      left: true,
      model: widget.model,
      settings: widget.stickSettings,
    ),
    'dpad' => _Dpad(model: widget.model),
    'rightStick' => _Stick(
      left: false,
      model: widget.model,
      settings: widget.stickSettings,
    ),
    'actions' => Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _button('X', color: const Color(0xff71b7f3))),
              const SizedBox(width: 8),
              Expanded(child: _button('Y', color: const Color(0xffe7c64d))),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _button('A', color: const Color(0xff7cda96))),
              const SizedBox(width: 8),
              Expanded(child: _button('B', color: const Color(0xfff08790))),
            ],
          ),
        ),
      ],
    ),
    _ => const SizedBox.shrink(),
  };

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: _surface,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(
        builder: (context, bounds) {
          final band = (bounds.maxHeight * .18).clamp(48.0, 60.0);
          return IgnorePointer(
            ignoring: !widget.enabled,
            child: AnimatedBuilder(
              animation: widget.model,
              builder: (context, _) => Column(
                key: ValueKey(_gestureEpoch),
                children: [
                  SizedBox(
                    height: band,
                    child: Row(
                      children: [
                        Expanded(
                          child: _Trigger(left: true, model: widget.model),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: _button('LB')),
                        Expanded(
                          flex: 2,
                          child: IgnorePointer(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Text(
                                widget.status,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: widget.enabled
                                      ? _accent
                                      : const Color(0xffffb454),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(child: _button('RB')),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _Trigger(left: false, model: widget.model),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (
                          var index = 0;
                          index < widget.layoutSettings.order.length;
                          index++
                        ) ...[
                          if (index != 0) const SizedBox(width: 8),
                          Expanded(
                            flex: widget.layoutSettings.widthFor(
                              widget.layoutSettings.order[index],
                            ),
                            child: _mainZone(
                              widget.layoutSettings.order[index],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 48,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _button('L3')),
                        const SizedBox(width: 8),
                        Expanded(child: _button('Back')),
                        const SizedBox(width: 8),
                        Expanded(child: _button('Guide')),
                        const SizedBox(width: 8),
                        Expanded(child: _button('Start')),
                        const SizedBox(width: 8),
                        Expanded(child: _button('R3')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _TouchButton extends StatelessWidget {
  const _TouchButton({
    required this.controlId,
    required this.positionLabel,
    required this.label,
    required this.bit,
    required this.model,
    required this.color,
  });
  final String controlId;
  final String positionLabel;
  final String label;
  final int bit;
  final GamepadInputModel model;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pressed = model.state.buttons & bit != 0;
    final remapped = positionLabel.toLowerCase() != label.toLowerCase();
    return Semantics(
      label: '$label button',
      button: true,
      value: pressed ? 'pressed' : 'released',
      child: Listener(
        key: ValueKey('control-$controlId'),
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          HapticFeedback.lightImpact();
          model.pressButton(event.pointer, bit);
        },
        onPointerUp: (event) => model.releasePointer(event.pointer),
        onPointerCancel: (event) => model.releasePointer(event.pointer),
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 70),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: pressed ? color : _control,
            border: Border.all(
              color: pressed ? color : color.withValues(alpha: .45),
              width: 2,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: pressed ? _surface : color,
                      fontSize: label.length == 1 ? 26 : 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (remapped)
                    Text(
                      '$positionLabel → $label',
                      maxLines: 1,
                      style: TextStyle(
                        color: (pressed ? _surface : color).withValues(
                          alpha: .78,
                        ),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One owner per analog/slide surface; another finger cannot steal its origin.
class _GestureSurface extends StatefulWidget {
  const _GestureSurface({
    required this.id,
    required this.model,
    required this.onUpdate,
    required this.builder,
  });
  final String id;
  final GamepadInputModel model;
  final void Function(int pointer, Offset position, Offset origin, Size size)
  onUpdate;
  final Widget Function(Size size, bool active, Offset origin) builder;

  @override
  State<_GestureSurface> createState() => _GestureSurfaceState();
}

class _GestureSurfaceState extends State<_GestureSurface> {
  int? _pointer;
  Offset _origin = Offset.zero;

  @override
  void dispose() {
    // Flutter may still route an existing gesture to a removed render object.
    _pointer = null;
    super.dispose();
  }

  void _release(PointerEvent event) {
    if (event.pointer != _pointer) return;
    widget.model.releasePointer(event.pointer);
    setState(() => _pointer = null);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      void update(PointerEvent event) {
        if (event.pointer == _pointer) {
          widget.onUpdate(
            event.pointer,
            event.localPosition,
            _origin,
            bounds.biggest,
          );
        }
      }

      return Semantics(
        label: widget.id,
        child: Listener(
          key: ValueKey('control-${widget.id}'),
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (_pointer != null) return;
            setState(() {
              _pointer = event.pointer;
              _origin = event.localPosition;
            });
            update(event);
          },
          onPointerMove: update,
          onPointerUp: _release,
          onPointerCancel: _release,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _control.withValues(alpha: .55),
              border: Border.all(color: _pointer == null ? _outline : _accent),
              borderRadius: BorderRadius.circular(20),
            ),
            child: widget.builder(bounds.biggest, _pointer != null, _origin),
          ),
        ),
      );
    },
  );
}

class _Stick extends StatelessWidget {
  const _Stick({
    required this.left,
    required this.model,
    required this.settings,
  });
  final bool left;
  final GamepadInputModel model;
  final ControllerStickSettings settings;

  @override
  Widget build(BuildContext context) => _GestureSurface(
    id: left ? 'LS' : 'RS',
    model: model,
    onUpdate: (pointer, position, origin, size) {
      final radius = math.min(size.width, size.height) * .28;
      final delta = (position - origin) / radius;
      final distance = delta.distance;
      final clamped = distance == 0
          ? Offset.zero
          : delta / distance * settings.mapMagnitude(distance);
      model.updateStick(
        pointer: pointer,
        left: left,
        x: clamped.dx,
        y: clamped.dy,
      );
    },
    builder: (size, active, origin) {
      final diameter = math.min(size.width, size.height) * .80;
      final radius = diameter / 2;
      final x = (left ? model.state.leftX : model.state.rightX) / 32767;
      final y = -(left ? model.state.leftY : model.state.rightY) / 32767;
      final center = active
          ? Offset(
              origin.dx.clamp(radius, size.width - radius),
              origin.dy.clamp(radius, size.height - radius),
            )
          : Offset(size.width / 2, size.height / 2);
      return Stack(
        children: [
          Positioned(
            left: center.dx - radius,
            top: center.dy - radius,
            width: diameter,
            height: diameter,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _outline, width: 2),
              ),
              child: Center(
                child: Transform.translate(
                  offset: Offset(x, y) * diameter * .22,
                  child: Container(
                    width: diameter * .52,
                    height: diameter * .52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active ? _accent : _control,
                      border: Border.all(
                        color: _accent.withValues(alpha: .6),
                        width: 2,
                      ),
                    ),
                    child: Text(
                      left ? 'LS' : 'RS',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: active ? _surface : _ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _Dpad extends StatelessWidget {
  const _Dpad({required this.model});
  final GamepadInputModel model;

  @override
  Widget build(BuildContext context) => _GestureSurface(
    id: 'D-pad',
    model: model,
    onUpdate: (pointer, position, origin, size) {
      final delta = position - Offset(size.width / 2, size.height / 2);
      var bits = 0;
      final deadZone = math.min(size.width, size.height) * .12;
      if (delta.distance > deadZone) {
        // Eight sectors; the whole square accepts directions and diagonals.
        if (delta.dx.abs() >= delta.dy.abs() * .45) {
          bits |= delta.dx < 0
              ? GamepadButton.dpadLeft
              : GamepadButton.dpadRight;
        }
        if (delta.dy.abs() >= delta.dx.abs() * .45) {
          bits |= delta.dy < 0 ? GamepadButton.dpadUp : GamepadButton.dpadDown;
        }
      }
      final currentDpad = model.state.buttons &
          (GamepadButton.dpadUp |
              GamepadButton.dpadDown |
              GamepadButton.dpadLeft |
              GamepadButton.dpadRight);
      if (bits != 0 && bits != currentDpad) {
        HapticFeedback.selectionClick();
      }
      model.pressButton(pointer, bits);
    },
    builder: (size, active, origin) => Stack(
      children: [
        for (final item in const [
          (Alignment(0, -.72), Icons.keyboard_arrow_up, GamepadButton.dpadUp),
          (
            Alignment(0, .72),
            Icons.keyboard_arrow_down,
            GamepadButton.dpadDown,
          ),
          (
            Alignment(-.82, 0),
            Icons.keyboard_arrow_left,
            GamepadButton.dpadLeft,
          ),
          (
            Alignment(.82, 0),
            Icons.keyboard_arrow_right,
            GamepadButton.dpadRight,
          ),
        ])
          Align(
            alignment: item.$1,
            child: Icon(
              item.$2,
              size: 28,
              color: model.state.buttons & item.$3 != 0 ? _accent : _ink,
            ),
          ),
        Center(
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _outline,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Trigger extends StatelessWidget {
  const _Trigger({required this.left, required this.model});
  final bool left;
  final GamepadInputModel model;

  @override
  Widget build(BuildContext context) => _GestureSurface(
    id: left ? 'LT' : 'RT',
    model: model,
    onUpdate: (pointer, position, origin, size) {
      final prev = left ? model.state.leftTrigger : model.state.rightTrigger;
      final amount = 1 - position.dy / size.height;
      if (prev == 0 && amount > 0) {
        HapticFeedback.selectionClick();
      }
      model.updateTrigger(
        pointer: pointer,
        left: left,
        amount: amount,
      );
    },
    builder: (size, active, origin) => Stack(
      children: [
        Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            widthFactor: 1,
            heightFactor:
                (left ? model.state.leftTrigger : model.state.rightTrigger) /
                65535,
            child: ColoredBox(color: _accent.withValues(alpha: .35)),
          ),
        ),
        Center(
          child: Text(
            left ? 'LT' : 'RT',
            style: const TextStyle(
              color: _ink,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ],
    ),
  );
}
