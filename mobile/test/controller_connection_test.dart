import 'dart:convert';
import 'dart:io';

import 'package:pulgapp_mobile/controller_connection.dart';
import 'package:test/test.dart';

void main() {
  test('returns after a fatal invalid PIN response', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 26760);
    addTearDown(server.close);
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((_) {
        socket.add(
          jsonEncode({
            'v': 1,
            'type': 'error',
            'code': 'invalid_pin',
            'message': 'The PIN is invalid.',
            'fatal': true,
          }),
        );
      });
    });

    final connection = ControllerConnection(
      clientId: '263b2310-4e1a-48df-8836-c5600ac77719',
      clientName: 'Test phone',
      saveEndpoint: (_) async {},
    );
    addTearDown(connection.dispose);

    await expectLater(
      connection.connect(endpoint: '127.0.0.1', pin: '123456'),
      throwsA(isA<StateError>()),
    ).timeout(const Duration(seconds: 2));
    expect(connection.state, PulgappConnectionState.disconnected);
  });

  test('offers rumble_v1 and emits incoming rumble messages', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 26760);
    addTearDown(server.close);

    var receivedCapabilities = <String>[];
    WebSocket? serverSocket;

    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      serverSocket = socket;
      socket.listen((raw) {
        final data = jsonDecode(raw as String) as Map<String, dynamic>;
        if (data['type'] == 'hello') {
          receivedCapabilities = List<String>.from(data['capabilities'] as List);
          socket.add(
            jsonEncode({
              'v': 1,
              'type': 'welcome',
              'serverId': '65fd878c-6001-45ee-b20d-24e471e4fa5b',
              'serverName': 'Test PC',
              'sessionId': '0123456789abcdef',
              'udpToken': 'ABEiM0RVZneImaq7zN3u_w',
              'udpPort': 26761,
              'slot': 1,
              'controllerType': 'x360',
              'resumed': false,
              'resumeToken': 'jP5dP4vJxPgmO8OpH4zgwAjiyXOSe3JvIwQfKHctnzM',
              'inputTimeoutMs': 250,
              'slotLeaseMs': 15000,
            }),
          );
        }
      });
    });

    final connection = ControllerConnection(
      clientId: '263b2310-4e1a-48df-8836-c5600ac77719',
      clientName: 'Test phone',
      saveEndpoint: (_) async {},
    );
    addTearDown(connection.dispose);

    await connection.connect(endpoint: '127.0.0.1', pin: '123456');
    expect(receivedCapabilities, contains('rumble_v1'));

    final rumbleFuture = connection.rumble.first;

    serverSocket?.add(
      jsonEncode({
        'v': 1,
        'type': 'rumble',
        'lowFrequency': 180,
        'highFrequency': 64,
      }),
    );

    final receivedRumble = await rumbleFuture.timeout(const Duration(seconds: 2));
    expect(receivedRumble.lowFrequency, 180);
    expect(receivedRumble.highFrequency, 64);
  });
}
