import 'dart:convert';

final class QrPairingData {
  const QrPairingData({
    required this.ip,
    this.port = defaultPort,
    required this.pin,
  });

  static const int defaultPort = 26760;

  final String ip;
  final int port;
  final String pin;

  String get endpoint => port == defaultPort ? ip : '$ip:$port';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QrPairingData &&
          runtimeType == other.runtimeType &&
          ip == other.ip &&
          port == other.port &&
          pin == other.pin;

  @override
  int get hashCode => Object.hash(ip, port, pin);

  @override
  String toString() => 'QrPairingData(ip: $ip, port: $port, pin: $pin)';
}

abstract final class QrPairingParser {
  static final RegExp _pinRegex = RegExp(r'^\d{6}$');

  static QrPairingData? tryParse(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // 1. Try URI: pulgapp://pair?... or pulgapp://connect?...
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme && uri.scheme.toLowerCase() == 'pulgapp') {
      final q = uri.queryParameters;
      final ip = q['ip']?.trim();
      final pin = q['pin']?.trim();
      final portStr = q['port']?.trim();
      var port = QrPairingData.defaultPort;
      if (portStr != null) {
        final p = int.tryParse(portStr);
        if (p != null && p >= 1 && p <= 65535) {
          port = p;
        } else {
          return null;
        }
      }
      if (ip != null && ip.isNotEmpty && pin != null && _pinRegex.hasMatch(pin)) {
        return QrPairingData(ip: ip, port: port, pin: pin);
      }
    }

    // 2. Try JSON: {"ip":"...","pin":"...","port":26760}
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final dynamic decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          final ip = decoded['ip']?.toString().trim();
          final pin = decoded['pin']?.toString().trim();
          var port = QrPairingData.defaultPort;
          final portVal = decoded['port'];
          if (portVal is int && portVal >= 1 && portVal <= 65535) {
            port = portVal;
          } else if (portVal is String) {
            final p = int.tryParse(portVal);
            if (p != null && p >= 1 && p <= 65535) {
              port = p;
            }
          }
          if (ip != null && ip.isNotEmpty && pin != null && _pinRegex.hasMatch(pin)) {
            return QrPairingData(ip: ip, port: port, pin: pin);
          }
        }
      } catch (_) {
        // Fall through
      }
    }

    // 3. Try plain format: IP:PORT:PIN or IP:PIN
    final parts = trimmed.split(':');
    if (parts.length == 3) {
      final ip = parts[0].trim();
      final port = int.tryParse(parts[1].trim());
      final pin = parts[2].trim();
      if (ip.isNotEmpty && port != null && port >= 1 && port <= 65535 && _pinRegex.hasMatch(pin)) {
        return QrPairingData(ip: ip, port: port, pin: pin);
      }
    } else if (parts.length == 2) {
      final ip = parts[0].trim();
      final pin = parts[1].trim();
      if (ip.isNotEmpty && _pinRegex.hasMatch(pin)) {
        return QrPairingData(ip: ip, port: QrPairingData.defaultPort, pin: pin);
      }
    }

    return null;
  }
}
