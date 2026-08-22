import 'dart:math';

import 'package:flutter/services.dart';

final class ClientPreferences {
  ClientPreferences._(this._values);

  static const _clientIdKey = 'client-id';
  static const _endpointKey = 'last-endpoint';
  static const _channel = MethodChannel('pulgapp/preferences');
  final Map<String, String> _values;

  static Future<ClientPreferences> load() async {
    final values =
        await _channel.invokeMapMethod<String, String>('getAll') ?? {};
    return ClientPreferences._(values);
  }

  String get clientId {
    final existing = _values[_clientIdKey];
    if (existing != null) return existing;
    final bytes = Uint8List(16);
    final random = Random.secure();
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = random.nextInt(256);
    }
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final value =
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    _values[_clientIdKey] = value;
    _channel.invokeMethod<void>('setString', {
      'key': _clientIdKey,
      'value': value,
    });
    return value;
  }

  String? get lastEndpoint => _values[_endpointKey];

  Future<void> saveEndpoint(String endpoint) async {
    _values[_endpointKey] = endpoint;
    await _channel.invokeMethod<void>('setString', {
      'key': _endpointKey,
      'value': endpoint,
    });
  }
}
