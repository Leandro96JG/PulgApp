import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'client_preferences.dart';
import 'controller_connection.dart';
import 'gamepad_input_model.dart';
import 'gamepad_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await ClientPreferences.load();
  runApp(PulgappApp(preferences: preferences));
}

final class PulgappApp extends StatelessWidget {
  const PulgappApp({super.key, required this.preferences});

  final ClientPreferences preferences;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Pulgapp',
    theme: ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff75e6b0),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    home: ConnectPage(preferences: preferences),
  );
}

final class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key, required this.preferences});
  final ClientPreferences preferences;

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

final class _ConnectPageState extends State<ConnectPage> {
  late final TextEditingController _endpoint;
  final _pin = TextEditingController();
  String? _error;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _endpoint = TextEditingController(
      text: widget.preferences.lastEndpoint ?? '',
    );
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _error = null;
      _connecting = true;
    });
    final connection = ControllerConnection(
      preferences: widget.preferences,
      clientName: 'Pulgapp phone',
    );
    try {
      await connection.connect(endpoint: _endpoint.text, pin: _pin.text);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ControllerPage(connection: connection),
        ),
      );
    } catch (error) {
      await connection.dispose();
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'PULGAPP',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 8),
                const Text('Manual LAN pairing for one Xbox controller.'),
                const SizedBox(height: 32),
                TextField(
                  controller: _endpoint,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Windows IPv4 address or hostname',
                    hintText: '192.168.1.42',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _pin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(labelText: 'Six-digit PIN'),
                ),
                if (_error case final error?) ...[
                  const SizedBox(height: 8),
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _connecting ? null : _connect,
                  child: Text(_connecting ? 'CONNECTING...' : 'CONNECT'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

final class ControllerPage extends StatefulWidget {
  const ControllerPage({super.key, required this.connection});
  final ControllerConnection connection;

  @override
  State<ControllerPage> createState() => _ControllerPageState();
}

final class _ControllerPageState extends State<ControllerPage>
    with WidgetsBindingObserver {
  final _input = GamepadInputModel();
  StreamSubscription<PulgappConnectionState>? _connectionSubscription;
  PulgappConnectionState _connectionState = PulgappConnectionState.connected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Wakelock.enable();
    _input.addListener(_sendInput);
    _connectionSubscription = widget.connection.states.listen((state) {
      if (mounted) setState(() => _connectionState = state);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _input.cancelAll();
      unawaited(widget.connection.suspend());
    }
  }

  void _sendInput() => widget.connection.sendState(_input.state);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.removeListener(_sendInput);
    _input.cancelAll();
    _connectionSubscription?.cancel();
    Wakelock.disable();
    unawaited(widget.connection.leave());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: AnimatedBuilder(
        animation: _input,
        builder: (context, _) => Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            _Trigger(
                              label: 'LT',
                              left: true,
                              model: _input,
                              value: _input.state.leftTrigger,
                            ),
                            const SizedBox(width: 8),
                            _Button(
                              label: 'LB',
                              bit: GamepadButton.lb,
                              model: _input,
                            ),
                            const Spacer(),
                            _Button(
                              label: 'RB',
                              bit: GamepadButton.rb,
                              model: _input,
                            ),
                            const SizedBox(width: 8),
                            _Trigger(
                              label: 'RT',
                              left: false,
                              model: _input,
                              value: _input.state.rightTrigger,
                            ),
                          ],
                        ),
                        const Spacer(),
                        _Dpad(model: _input),
                        const Spacer(),
                        _Stick(left: true, model: _input),
                        const SizedBox(height: 8),
                        _Button(
                          label: 'L3',
                          bit: GamepadButton.l3,
                          model: _input,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _Button(
                              label: 'BACK',
                              bit: GamepadButton.back,
                              model: _input,
                            ),
                            const SizedBox(width: 8),
                            _Button(
                              label: 'START',
                              bit: GamepadButton.start,
                              model: _input,
                            ),
                            const SizedBox(width: 8),
                            _Button(
                              label: 'GUIDE',
                              bit: GamepadButton.guide,
                              model: _input,
                            ),
                          ],
                        ),
                        const Spacer(),
                        _FaceButtons(model: _input),
                        const Spacer(),
                        _Stick(left: false, model: _input),
                        const SizedBox(height: 8),
                        _Button(
                          label: 'R3',
                          bit: GamepadButton.r3,
                          model: _input,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Text(
                _connectionState == PulgappConnectionState.inputUnavailable
                    ? 'UDP unavailable: check Wi-Fi and firewall'
                    : 'Slot ${widget.connection.welcome?.slot ?? '-'} | ${_connectionState.name}',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

final class _Stick extends StatelessWidget {
  const _Stick({required this.left, required this.model});
  final bool left;
  final GamepadInputModel model;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 96,
    child: LayoutBuilder(
      builder: (context, constraints) => Listener(
        onPointerDown: (event) => _update(event, constraints.biggest),
        onPointerMove: (event) => _update(event, constraints.biggest),
        onPointerUp: (event) => model.releasePointer(event.pointer),
        onPointerCancel: (event) => model.releasePointer(event.pointer),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: .12),
          ),
          child: Center(child: Text(left ? 'LS' : 'RS')),
        ),
      ),
    ),
  );

  void _update(PointerEvent event, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final delta = event.localPosition - center;
    model.updateStick(
      pointer: event.pointer,
      left: left,
      x: delta.dx / center.dx,
      y: delta.dy / center.dy,
    );
  }
}

final class _Trigger extends StatelessWidget {
  const _Trigger({
    required this.label,
    required this.left,
    required this.model,
    required this.value,
  });
  final String label;
  final bool left;
  final GamepadInputModel model;
  final int value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 64,
    height: 42,
    child: LayoutBuilder(
      builder: (context, constraints) => Listener(
        onPointerDown: (event) => _update(event, constraints.maxHeight),
        onPointerMove: (event) => _update(event, constraints.maxHeight),
        onPointerUp: (event) => model.releasePointer(event.pointer),
        onPointerCancel: (event) => model.releasePointer(event.pointer),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: value / 131070),
          ),
          child: Center(child: Text(label)),
        ),
      ),
    ),
  );

  void _update(PointerEvent event, double height) => model.updateTrigger(
    pointer: event.pointer,
    left: left,
    amount: 1 - (event.localPosition.dy / height),
  );
}

final class _Button extends StatelessWidget {
  const _Button({required this.label, required this.bit, required this.model});
  final String label;
  final int bit;
  final GamepadInputModel model;

  @override
  Widget build(BuildContext context) {
    final pressed = model.state.buttons & bit != 0;
    return Listener(
      onPointerDown: (event) => model.pressButton(event.pointer, bit),
      onPointerUp: (event) => model.releasePointer(event.pointer),
      onPointerCancel: (event) => model.releasePointer(event.pointer),
      child: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: pressed
              ? Theme.of(context).colorScheme.primary
              : Colors.white.withValues(alpha: .12),
        ),
        child: Text(label),
      ),
    );
  }
}

final class _FaceButtons extends StatelessWidget {
  const _FaceButtons({required this.model});
  final GamepadInputModel model;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 120,
    height: 120,
    child: Stack(
      children: [
        Positioned(
          top: 0,
          left: 37,
          child: _Button(label: 'Y', bit: GamepadButton.y, model: model),
        ),
        Positioned(
          bottom: 0,
          left: 37,
          child: _Button(label: 'A', bit: GamepadButton.a, model: model),
        ),
        Positioned(
          top: 37,
          left: 0,
          child: _Button(label: 'X', bit: GamepadButton.x, model: model),
        ),
        Positioned(
          top: 37,
          right: 0,
          child: _Button(label: 'B', bit: GamepadButton.b, model: model),
        ),
      ],
    ),
  );
}

final class _Dpad extends StatelessWidget {
  const _Dpad({required this.model});
  final GamepadInputModel model;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 120,
    height: 120,
    child: Stack(
      children: [
        Positioned(
          top: 0,
          left: 37,
          child: _Button(label: 'UP', bit: GamepadButton.dpadUp, model: model),
        ),
        Positioned(
          bottom: 0,
          left: 37,
          child: _Button(
            label: 'DN',
            bit: GamepadButton.dpadDown,
            model: model,
          ),
        ),
        Positioned(
          top: 37,
          left: 0,
          child: _Button(
            label: 'LT',
            bit: GamepadButton.dpadLeft,
            model: model,
          ),
        ),
        Positioned(
          top: 37,
          right: 0,
          child: _Button(
            label: 'RT',
            bit: GamepadButton.dpadRight,
            model: model,
          ),
        ),
      ],
    ),
  );
}

abstract final class Wakelock {
  static const _channel = MethodChannel('pulgapp/wakelock');

  static void enable() => _channel.invokeMethod<void>('enable');
  static void disable() => _channel.invokeMethod<void>('disable');
}
