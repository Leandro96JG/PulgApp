import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'client_preferences.dart';
import 'gamepad_state.dart';
import 'input_send_scheduler.dart';
import 'protocol.dart';

enum PulgappConnectionState {
  disconnected,
  connecting,
  connected,
  inputUnavailable,
  error,
}

final class ControllerConnection {
  ControllerConnection({required this.preferences, required this.clientName}) {
    _scheduler = InputSendScheduler(_sendUdp);
  }

  final ClientPreferences preferences;
  final String clientName;
  late final InputSendScheduler _scheduler;
  final StreamController<PulgappConnectionState> _states =
      StreamController<PulgappConnectionState>.broadcast();
  final Stopwatch _clock = Stopwatch()..start();
  WebSocket? _webSocket;
  RawDatagramSocket? _udpSocket;
  Timer? _pingTimer;
  Timer? _udpReadyTimer;
  WelcomeMessage? _welcome;
  InternetAddress? _serverAddress;
  int _sequence = 0;
  int _pingId = 0;
  bool _closing = false;
  PulgappConnectionState _state = PulgappConnectionState.disconnected;
  String? _error;

  Stream<PulgappConnectionState> get states => _states.stream;
  PulgappConnectionState get state => _state;
  String? get error => _error;
  WelcomeMessage? get welcome => _welcome;

  Future<void> connect({required String endpoint, required String pin}) async {
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      throw ArgumentError.value(pin, 'pin', 'must be six decimal digits');
    }
    final host = _normalizeHost(endpoint);
    await _close(sendSuspend: false);
    _closing = false;
    _setState(PulgappConnectionState.connecting);
    try {
      final addresses = await InternetAddress.lookup(host);
      _serverAddress = addresses.firstWhere(
        (address) => address.type == InternetAddressType.IPv4,
        orElse: () => throw const SocketException('No IPv4 address found.'),
      );
      final webSocket = await WebSocket.connect('ws://$host:26760/control');
      _webSocket = webSocket;
      final welcome = Completer<WelcomeMessage>();
      webSocket.listen(
        (message) => _handleControlMessage(message, welcome),
        onDone: () => _onControlClosed(),
        onError: (_, __) => _onControlClosed(),
        cancelOnError: true,
      );
      webSocket.add(
        jsonEncode(
          HelloMessage(
            clientId: preferences.clientId,
            clientName: clientName,
            appVersion: '0.1.0',
            capabilities: const ['udp_input_v1'],
            pin: pin,
          ).toJson(),
        ),
      );
      _welcome = await welcome.future.timeout(const Duration(seconds: 10));
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _scheduler.start();
      _scheduler.sendNeutralNow();
      _pingTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _sendPing(),
      );
      _udpReadyTimer = Timer(const Duration(seconds: 2), () {
        if (_state == PulgappConnectionState.connected) {
          _setState(PulgappConnectionState.inputUnavailable);
        }
      });
      await preferences.saveEndpoint(host);
      _setState(PulgappConnectionState.connected);
    } catch (error) {
      _error = 'Connection failed: $error';
      _setState(PulgappConnectionState.error);
      await _close(sendSuspend: false);
      rethrow;
    }
  }

  void sendState(GamepadState state) => _scheduler.update(state);

  Future<void> suspend() => _close(sendSuspend: true);

  Future<void> leave() async {
    await _scheduler.sendNeutralRedundantly();
    _webSocket?.add(jsonEncode(const LeaveMessage().toJson()));
    await _close(sendSuspend: false);
  }

  Future<void> dispose() async {
    await _close(sendSuspend: false);
    await _states.close();
  }

  void _handleControlMessage(
    Object? message,
    Completer<WelcomeMessage> welcome,
  ) {
    if (message is! String) return;
    try {
      final value = jsonDecode(message);
      if (value is! Map<String, dynamic> || value['v'] != 1) return;
      switch (value['type']) {
        case 'welcome':
          if (!welcome.isCompleted) welcome.complete(_parseWelcome(value));
        case 'input_ready':
          _udpReadyTimer?.cancel();
          _setState(PulgappConnectionState.connected);
        case 'error':
          _error =
              value['message'] as String? ?? 'Server rejected the connection.';
          if (!welcome.isCompleted) welcome.completeError(StateError(_error!));
          _setState(PulgappConnectionState.error);
      }
    } catch (error) {
      if (!welcome.isCompleted) welcome.completeError(error);
    }
  }

  WelcomeMessage _parseWelcome(Map<String, dynamic> value) {
    final controllerType = value['controllerType'];
    if (controllerType != 'x360' && controllerType != 'ds4') {
      throw const FormatException('Invalid controller type.');
    }
    return WelcomeMessage(
      serverId: value['serverId'] as String,
      serverName: value['serverName'] as String,
      sessionId: value['sessionId'] as String,
      udpToken: value['udpToken'] as String,
      udpPort: value['udpPort'] as int,
      slot: value['slot'] as int,
      controllerType: controllerType == 'x360'
          ? ControllerType.x360
          : ControllerType.ds4,
      resumed: value['resumed'] as bool,
      resumeToken: value['resumeToken'] as String,
      inputTimeoutMs: value['inputTimeoutMs'] as int,
      slotLeaseMs: value['slotLeaseMs'] as int,
    );
  }

  void _sendUdp(GamepadState state) {
    final welcome = _welcome;
    final socket = _udpSocket;
    final address = _serverAddress;
    if (welcome == null || socket == null || address == null) return;
    final token = base64Url.decode(base64Url.normalize(welcome.udpToken));
    final sessionId = BigInt.parse(welcome.sessionId, radix: 16);
    final snapshot = InputSnapshot(
      sessionId: _uint64(sessionId),
      udpToken: Uint8List.fromList(token),
      sequence: _sequence++ & 0xffffffff,
      clientTimeUs: _uint64(BigInt.from(_clock.elapsedMicroseconds)),
      buttons: state.buttons,
      leftX: state.leftX,
      leftY: state.leftY,
      rightX: state.rightX,
      rightY: state.rightY,
      leftTrigger: state.leftTrigger,
      rightTrigger: state.rightTrigger,
    );
    socket.send(UdpInputEncoder.encode(snapshot), address, welcome.udpPort);
  }

  void _sendPing() {
    final socket = _webSocket;
    if (socket == null) return;
    socket.add(
      jsonEncode(
        PingMessage(
          _pingId++ & 0xffffffff,
          _clock.elapsedMicroseconds.toString(),
        ).toJson(),
      ),
    );
  }

  void _onControlClosed() {
    if (_closing) return;
    _scheduler.sendNeutralNow();
    _error = 'Control connection closed.';
    _setState(PulgappConnectionState.disconnected);
    _close(sendSuspend: false);
  }

  Future<void> _close({required bool sendSuspend}) async {
    _closing = true;
    if (sendSuspend) {
      await _scheduler.sendNeutralRedundantly();
      _webSocket?.add(jsonEncode(const SuspendMessage().toJson()));
    }
    _pingTimer?.cancel();
    _udpReadyTimer?.cancel();
    _scheduler.dispose();
    _udpSocket?.close();
    _udpSocket = null;
    final socket = _webSocket;
    _webSocket = null;
    if (socket != null) await socket.close();
    _welcome = null;
    _serverAddress = null;
    _setState(PulgappConnectionState.disconnected);
  }

  void _setState(PulgappConnectionState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }

  static String _normalizeHost(String endpoint) {
    final host = endpoint.trim().replaceFirst(RegExp(r'^https?://'), '');
    if (host.isEmpty || host.contains('/') || host.contains(':')) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'must be an IPv4 address or hostname',
      );
    }
    return host;
  }

  static Uint64Value _uint64(BigInt value) => Uint64Value(
    ((value >> 32) & BigInt.from(0xffffffff)).toInt(),
    (value & BigInt.from(0xffffffff)).toInt(),
  );
}
