import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'client_preferences.dart';
import 'controller/profile_manager_page.dart';
import 'controller/test_pad_page.dart';
import 'controller_profile.dart';
import 'controller_connection.dart';
import 'gamepad_input_model.dart';
import 'controller/touch_controller.dart';
import 'qr_pairing.dart';
import 'qr_scanner_page.dart';
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
        surface: const Color(0xff11161c),
      ),
      scaffoldBackgroundColor: const Color(0xff0b0e12),
      cardTheme: const CardThemeData(
        color: Color(0xff161d24),
        elevation: 0,
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
  late final TextEditingController _pin;
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
    _pin = TextEditingController(
      text: widget.preferences.lastPin ?? '',
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
      await connection.connect(
        endpoint: _endpoint.text,
        pin: _pin.text,
        preferredController: _profiles.selected.controllerType.name,
      );
      await widget.preferences.savePin(_pin.text);
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

  Future<void> _scanQr() async {
    final result = await Navigator.of(context).push<QrPairingData>(
      MaterialPageRoute(builder: (_) => const QrScannerPage()),
    );
    if (!mounted || result == null) return;
    setState(() {
      _endpoint.text = result.endpoint;
      _pin.text = result.pin;
      _endpointError = null;
      _pinError = null;
      _error = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Scanned QR code: ${result.endpoint}'),
        duration: const Duration(seconds: 2),
      ),
    );
    await _connect();
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

  Future<void> _openTestPad() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ControllerTestPadPage(profile: _profiles.selected),
      ),
    );
  }

  Future<void> _pasteToEndpoint() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      setState(() {
        _endpoint.text = text;
        _endpointError = null;
        _error = null;
      });
    }
  }

  Future<void> _pasteToPin() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      final cleanPin = text.replaceAll(RegExp(r'\D'), '');
      if (cleanPin.isNotEmpty) {
        setState(() {
          _pin.text = cleanPin.length > 6 ? cleanPin.substring(0, 6) : cleanPin;
          _pinError = null;
          _error = null;
        });
      }
    }
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
          final verticalPadding = compact ? 10.0 : 20.0;
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
              suffix: IconButton(
                icon: Icon(
                  Icons.content_paste_rounded,
                  size: compact ? 18 : 20,
                ),
                tooltip: 'Paste address',
                onPressed: _pasteToEndpoint,
              ),
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
            style: const TextStyle(
              fontFamily: 'monospace',
              letterSpacing: 2.0,
              fontWeight: FontWeight.w600,
            ),
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
              suffix: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.content_paste_rounded,
                      size: compact ? 18 : 20,
                    ),
                    tooltip: 'Paste PIN',
                    onPressed: _pasteToPin,
                  ),
                  IconButton(
                    key: const ValueKey('toggle-pin-visibility'),
                    icon: Icon(
                      _showPin
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      size: compact ? 18 : 20,
                    ),
                    tooltip: _showPin ? 'Hide PIN' : 'Show PIN',
                    onPressed: () => setState(() => _showPin = !_showPin),
                  ),
                ],
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
                      _buildHeader(context, compact),
                      SizedBox(height: compact ? 8 : 16),
                      _buildProfileCard(context, compact),
                      SizedBox(height: compact ? 8 : 16),
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
                      _buildActionButtons(context, landscapeForm, compact),
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

  Widget _buildHeader(BuildContext context, bool compact) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      children: [
        Container(
          width: compact ? 38 : 46,
          height: compact ? 38 : 46,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withAlpha(40),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            Icons.sports_esports_rounded,
            color: colorScheme.onPrimaryContainer,
            size: compact ? 22 : 26,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 2,
                children: [
                  Text(
                    'PULGAPP',
                    style: (compact
                            ? theme.textTheme.titleMedium
                            : theme.textTheme.headlineSmall)
                        ?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withAlpha(30),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: colorScheme.primary.withAlpha(80),
                      ),
                    ),
                    child: Text(
                      'Wi-Fi LAN',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                'Pair over your local network',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          icon: const Icon(Icons.gamepad_outlined),
          tooltip: 'Offline Test Pad',
          onPressed: _connecting ? null : _openTestPad,
        ),
      ],
    );
  }

  Widget _buildProfileCard(BuildContext context, bool compact) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final profile = _profiles.selected;
    final deadzonePct = (profile.sticks.deadZone * 100).round();
    final sens = profile.sticks.sensitivity.toStringAsFixed(1);
    final triggerMode = profile.sticks.digitalTriggers ? 'Digital' : 'Analog';

    return Material(
      color: colorScheme.surfaceContainerHighest.withAlpha(70),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _connecting ? null : _manageProfiles,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: compact ? 8 : 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: colorScheme.outlineVariant.withAlpha(70),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.tune_rounded,
                  color: colorScheme.primary,
                  size: compact ? 18 : 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'CONTROLS: ${profile.name.toUpperCase()}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: colorScheme.primary,
                          ),
                        ),
                        _buildMiniBadge(
                          profile.controllerType.shortLabel,
                          colorScheme,
                        ),
                        _buildMiniBadge('DZ: $deadzonePct%', colorScheme),
                        _buildMiniBadge('${sens}x', colorScheme),
                        _buildMiniBadge(triggerMode, colorScheme),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile.visibleSummary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniBadge(String text, ColorScheme colorScheme) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(
        color: colorScheme.outlineVariant.withAlpha(50),
      ),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 9,
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _buildActionButtons(
    BuildContext context,
    bool landscapeForm,
    bool compact,
  ) {
    final scanQrBtn = OutlinedButton.icon(
      onPressed: (_connecting || _discovering) ? null : _scanQr,
      icon: const Icon(Icons.qr_code_scanner_rounded),
      label: const FittedBox(
        fit: BoxFit.scaleDown,
        child: Text('SCAN QR'),
      ),
      style: _actionStyle(compact),
    );

    final findServerBtn = OutlinedButton.icon(
      onPressed: _discovering ? null : _discover,
      icon: const Icon(Icons.radar_rounded),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(_discovering ? 'SEARCHING…' : 'FIND SERVER'),
      ),
      style: _actionStyle(compact),
    );

    final connectBtn = FilledButton.icon(
      onPressed: _connecting ? null : _connect,
      icon: const Icon(Icons.link_rounded),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(_connecting ? 'CONNECTING…' : 'CONNECT'),
      ),
      style: _actionStyle(compact).copyWith(
        backgroundColor: WidgetStatePropertyAll(
          Theme.of(context).colorScheme.primary,
        ),
        foregroundColor: WidgetStatePropertyAll(
          Theme.of(context).colorScheme.onPrimary,
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1),
        ),
      ),
    );

    if (landscapeForm) {
      return Row(
        children: [
          Expanded(child: scanQrBtn),
          const SizedBox(width: 10),
          Expanded(child: findServerBtn),
          const SizedBox(width: 10),
          Expanded(child: connectBtn),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: scanQrBtn),
            const SizedBox(width: 10),
            Expanded(child: findServerBtn),
          ],
        ),
        const SizedBox(height: 10),
        connectBtn,
      ],
    );
  }

  InputDecoration _fieldDecoration(
    BuildContext context, {
    required String label,
    required String hint,
    required IconData icon,
    required String? error,
    required bool compact,
    Widget? suffix,
  }) {
    final theme = Theme.of(context);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: error,
      prefixIcon: Icon(icon, color: theme.colorScheme.primary.withAlpha(200)),
      suffixIcon: suffix,
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(50),
      isDense: compact,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: compact ? 10 : 16,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: theme.colorScheme.outlineVariant.withAlpha(80),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: theme.colorScheme.outlineVariant.withAlpha(80),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: theme.colorScheme.primary,
          width: 2,
        ),
      ),
    );
  }

  ButtonStyle _actionStyle(bool compact) => ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size.fromHeight(compact ? 44 : 50)),
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
        controllerType: widget.profile.controllerType,
        stickSettings: widget.profile.sticks,
        buttonMapping: widget.profile.buttons,
        layoutSettings: widget.profile.layout,
        enabled: _connectionState == PulgappConnectionState.connected,
        status: _connectionState == PulgappConnectionState.inputUnavailable
            ? 'UDP unavailable: check Wi-Fi and firewall'
            : 'Slot ${widget.connection.welcome?.slot ?? '-'} (${widget.profile.controllerType.shortLabel}) | ${_connectionState.name}',
      ),
    ),
  );
}

abstract final class Wakelock {
  static const _channel = MethodChannel('pulgapp/wakelock');

  static void enable() => _channel.invokeMethod<void>('enable');
  static void disable() => _channel.invokeMethod<void>('disable');
}
