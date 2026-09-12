import 'package:flutter/material.dart';

import '../controller_profile.dart';
import '../gamepad_input_model.dart';
import '../gamepad_state.dart';
import 'touch_controller.dart';

/// Interactive offline test pad to calibrate sticks, triggers, buttons, and layout
/// without connecting to a Windows host.
class ControllerTestPadPage extends StatefulWidget {
  const ControllerTestPadPage({
    super.key,
    required this.profile,
  });

  final ControllerProfile profile;

  @override
  State<ControllerTestPadPage> createState() => _ControllerTestPadPageState();
}

class _ControllerTestPadPageState extends State<ControllerTestPadPage> {
  final _model = GamepadInputModel();

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  String _statusText(GamepadState state) {
    final pressed = <String>[];
    for (final action in ControllerButtonAction.all) {
      if (state.buttons & action.bit != 0) {
        pressed.add(action.label);
      }
    }
    if (state.buttons & GamepadButton.dpadUp != 0) pressed.add('Up');
    if (state.buttons & GamepadButton.dpadDown != 0) pressed.add('Down');
    if (state.buttons & GamepadButton.dpadLeft != 0) pressed.add('Left');
    if (state.buttons & GamepadButton.dpadRight != 0) pressed.add('Right');

    final btnStr = pressed.isEmpty ? 'None' : pressed.join('+');
    final lt = ((state.leftTrigger / 65535) * 100).round();
    final rt = ((state.rightTrigger / 65535) * 100).round();
    final lsX = (state.leftX / 32767).toStringAsFixed(1);
    final lsY = (state.leftY / 32767).toStringAsFixed(1);

    return 'LS: ($lsX, $lsY)  LT: $lt%  RT: $rt%\nActive: $btnStr';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff101419),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: _model,
        builder: (context, _) => Stack(
          children: [
            TouchController(
              model: _model,
              stickSettings: widget.profile.sticks,
              buttonMapping: widget.profile.buttons,
              layoutSettings: widget.profile.layout,
              enabled: true,
              status: _statusText(_model.state),
            ),
            Positioned(
              top: 10,
              left: 0,
              right: 0,
              child: Center(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const ValueKey('exit-test-pad'),
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xff252c34).withValues(alpha: .9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xff91bdd8).withValues(alpha: .5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.arrow_back_rounded,
                            size: 13,
                            color: Color(0xff91bdd8),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Exit Test Pad (${widget.profile.name})',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xff91bdd8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
