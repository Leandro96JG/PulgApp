import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'client_preferences.dart';
import 'controller/profile_manager_page.dart';
import 'controller_profile.dart';
import 'controller_connection.dart';
import 'gamepad_input_model.dart';
import 'controller/touch_controller.dart';
import 'server_discovery.dart';

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
  bool _showPin = true;
  String? _error;
  String? _endpointError;
  String? _pinError;
  bool _connecting = false;
  bool _discovering = false;
  late ControllerProfileLibrary _profiles;

  @override
  void initState() {
    super.initState();
    _endpoint = TextEditingController(
      text: widget.preferences.lastEndpoint ?? '',
    );
    _profiles = widget.preferences.controllerProfiles;
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final endpointError = _validateEndpoint(_endpoint.text);
    final pinError = _validatePin(_pin.text);
    if (endpointError != null || pinError != null) {
      setState(() {
        _endpointError = endpointError;
        _pinError = pinError;
        _error = null;
      });
      return;
    }
    setState(() {
      _error = null;
      _endpointError = null;
      _pinError = null;
      _connecting = true;
    });
    final connection = ControllerConnection(
      clientId: widget.preferences.clientId,
      clientName: 'Pulgapp phone',
      saveEndpoint: widget.preferences.saveEndpoint,
    );
    try {
      await connection.connect(endpoint: _endpoint.text, pin: _pin.text);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ControllerPage(
            connection: connection,
            profile: _profiles.selected,
          ),
        ),
      );
    } catch (error) {
      await connection.dispose();
      if (mounted) _showConnectionError(error);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _discover() async {
    setState(() {
      _discovering = true;
      _error = null;
      _endpointError = null;
    });
    try {
      final servers = await ServerDiscovery.find();
      if (!mounted) return;
      if (servers.isEmpty) {
        setState(
          () => _error = 'No servers found. Enter the IPv4 address manually.',
        );
        return;
      }
      if (servers.length == 1) {
        setState(() {
          _endpoint.text = servers.first.host;
          _endpointError = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Found server: ${servers.first.host}'),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        final chosen = await showModalBottomSheet<DiscoveredServer>(
          context: context,
          builder: (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Available servers (${servers.length})',
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: servers.length,
                    itemBuilder: (context, index) {
                      final server = servers[index];
                      return ListTile(
                        leading: const Icon(Icons.sports_esports_rounded),
                        title: Text(server.host),
                        subtitle: Text(server.name),
                        onTap: () => Navigator.of(sheetContext).pop(server),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
        if (mounted && chosen != null) {
          setState(() {
            _endpoint.text = chosen.host;
            _endpointError = null;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Server search failed. Check Wi-Fi and enter the address manually.',
        );
      }
    } finally {
      if (mounted) setState(() => _discovering = false);
    }
  }

  Future<void> _manageProfiles() async {
    final result = await Navigator.of(context).push<ControllerProfileLibrary>(
      MaterialPageRoute(
        builder: (_) => ProfileManagerPage(
          preferences: widget.preferences,
          initialProfiles: _profiles,
        ),
      ),
    );
    if (mounted && result != null) setState(() => _profiles = result);
  }

  String? _validateEndpoint(String value) {
    final host = value.trim().replaceFirst(RegExp(r'^https?://'), '');
    if (host.isEmpty || host.contains('/') || host.contains(':')) {
      return 'Enter an IPv4 address or hostname.';
    }
    return null;
  }

  String? _validatePin(String value) =>
      RegExp(r'^\d{6}$').hasMatch(value) ? null : 'Enter the six-digit PIN.';

  void _showConnectionError(Object error) {
    final detail = error.toString().toLowerCase();
    setState(() {
      if (detail.contains('pin')) {
        _pinError = 'The server rejected this PIN.';
        _error = null;
      } else if (detail.contains('socket') ||
          detail.contains('host') ||
          detail.contains('timed out') ||
          detail.contains('connection refused')) {
        _endpointError = 'Could not reach this server on the local network.';
        _error = null;
      } else if (detail.contains('virtual controller')) {
        _error =
            'Windows could not create the controller. Check the PC driver and try again.';
      } else {
        _error = 'Connection failed. Check the server and try again.';
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    resizeToAvoidBottomInset: true,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final landscapeForm = constraints.maxWidth >= 560;
          final compact = constraints.maxHeight < 420;
          final horizontalPadding = landscapeForm ? 20.0 : 16.0;
          final verticalPadding = compact ? 12.0 : 24.0;
          final endpointField = TextField(
            key: const ValueKey('endpoint-field'),
            controller: _endpoint,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              if (_endpointError != null || _error != null) {
                setState(() {
                  _endpointError = null;
                  _error = null;
                });
              }
            },
            decoration: _fieldDecoration(
              context,
              label: 'Windows IP or hostname',
              hint: '192.168.1.42',
              icon: Icons.lan_outlined,
              error: _endpointError,
              compact: compact,
            ),
          );
          final pinField = TextField(
            key: const ValueKey('pin-field'),
            controller: _pin,
            obscureText: !_showPin,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 6,
            onSubmitted: (_) {
              if (!_connecting) _connect();
            },
            onChanged: (_) {
              if (_pinError != null || _error != null) {
                setState(() {
                  _pinError = null;
                  _error = null;
                });
              }
            },
            decoration: _fieldDecoration(
              context,
              label: 'Six-digit PIN',
              hint: '000000',
              icon: Icons.dialpad_rounded,
              error: _pinError,
              compact: compact,
              suffix: IconButton(
                key: const ValueKey('toggle-pin-visibility'),
                icon: Icon(
                  _showPin
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: compact ? 18 : 22,
                ),
                tooltip: _showPin ? 'Hide PIN' : 'Show PIN',
                onPressed: () => setState(() => _showPin = !_showPin),
              ),
            ).copyWith(counterText: ''),
          );
          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              verticalPadding,
              horizontalPadding,
              verticalPadding + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - verticalPadding * 2,
              ),
              child: Center(
                child: ConstrainedBox(
                  key: const ValueKey('pairing-panel'),
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: compact ? 40 : 48,
                            height: compact ? 40 : 48,
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.sports_esports_rounded),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PULGAPP',
                                  style: compact
                                      ? Theme.of(context).textTheme.titleLarge
                                      : Theme.of(
                                          context,
                                        ).textTheme.headlineMedium,
                                ),
                                Text(
                                  'Pair over your local Wi-Fi',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: compact ? 10 : 18),
                      OutlinedButton.icon(
                        onPressed: _connecting ? null : _manageProfiles,
                        icon: const Icon(Icons.tune),
                        label: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'CONTROLS: ${_profiles.selected.name.toUpperCase()}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    _profiles.selected.buttons.visibleSummary,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 9,
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 10 : 18),
                      if (landscapeForm)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: endpointField),
                            const SizedBox(width: 12),
                            Expanded(child: pinField),
                          ],
                        )
                      else ...[
                        endpointField,
                        const SizedBox(height: 12),
                        pinField,
                      ],
                      if (_error case final error?) ...[
                        const SizedBox(height: 10),
                        Semantics(
                          liveRegion: true,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline_rounded,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onErrorContainer,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    error,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      SizedBox(height: compact ? 10 : 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _discovering ? null : _discover,
                              icon: const Icon(Icons.radar_rounded),
                              label: Text(
                                _discovering ? 'SEARCHING…' : 'FIND SERVER',
                              ),
                              style: _actionStyle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _connecting ? null : _connect,
                              icon: const Icon(Icons.link_rounded),
                              label: Text(
                                _connecting ? 'CONNECTING…' : 'CONNECT',
                              ),
                              style: _actionStyle,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  InputDecoration _fieldDecoration(
    BuildContext context, {
    required String label,
    required String hint,
    required IconData icon,
    required String? error,
    required bool compact,
    Widget? suffix,
  }) => InputDecoration(
    labelText: label,
    hintText: hint,
    errorText: error,
    prefixIcon: Icon(icon),
    suffixIcon: suffix,
    filled: true,
    isDense: compact,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
  );

  ButtonStyle get _actionStyle => ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

final class ControllerPage extends StatefulWidget {
  const ControllerPage({
    super.key,
    required this.connection,
    this.profile = ControllerProfile.fallback,
  });
  final ControllerConnection connection;
  final ControllerProfile profile;

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
    } else if (state == AppLifecycleState.resumed) {
      unawaited(widget.connection.resume());
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
      child: TouchController(
        model: _input,
        stickSettings: widget.profile.sticks,
        buttonMapping: widget.profile.buttons,
        layoutSettings: widget.profile.layout,
        enabled: _connectionState == PulgappConnectionState.connected,
        status: _connectionState == PulgappConnectionState.inputUnavailable
            ? 'UDP unavailable: check Wi-Fi and firewall'
            : 'Slot ${widget.connection.welcome?.slot ?? '-'} | ${_connectionState.name}',
      ),
    ),
  );
}

abstract final class Wakelock {
  static const _channel = MethodChannel('pulgapp/wakelock');

  static void enable() => _channel.invokeMethod<void>('enable');
  static void disable() => _channel.invokeMethod<void>('disable');
}
