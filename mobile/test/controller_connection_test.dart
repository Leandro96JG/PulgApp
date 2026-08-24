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
}
