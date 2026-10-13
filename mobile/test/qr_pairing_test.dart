import 'package:pulgapp_mobile/qr_pairing.dart';
import 'package:test/test.dart';

void main() {
  group('QrPairingParser', () {
    test('parses canonical pulgapp URI', () {
      final data = QrPairingParser.tryParse(
        'pulgapp://pair?ip=192.168.1.50&port=26760&pin=123456',
      );
      expect(data, isNotNull);
      expect(data!.ip, '192.168.1.50');
      expect(data.port, 26760);
      expect(data.pin, '123456');
      expect(data.endpoint, '192.168.1.50');
    });

    test('parses URI with custom port', () {
      final data = QrPairingParser.tryParse(
        'pulgapp://pair?ip=10.0.0.5&port=27000&pin=654321',
      );
      expect(data, isNotNull);
      expect(data!.ip, '10.0.0.5');
      expect(data.port, 27000);
      expect(data.pin, '654321');
      expect(data.endpoint, '10.0.0.5:27000');
    });

    test('parses URI with omitted port defaulting to 26760', () {
      final data = QrPairingParser.tryParse(
        'pulgapp://connect?pin=112233&ip=192.168.0.100',
      );
      expect(data, isNotNull);
      expect(data!.ip, '192.168.0.100');
      expect(data.port, 26760);
      expect(data.pin, '112233');
      expect(data.endpoint, '192.168.0.100');
    });

    test('parses JSON format', () {
      final data = QrPairingParser.tryParse(
        '{"ip": "192.168.1.200", "port": 26760, "pin": "998877"}',
      );
      expect(data, isNotNull);
      expect(data!.ip, '192.168.1.200');
      expect(data.port, 26760);
      expect(data.pin, '998877');
    });

    test('parses plain text formats', () {
      final data3 = QrPairingParser.tryParse('192.168.1.10:28000:445566');
      expect(data3, isNotNull);
      expect(data3!.ip, '192.168.1.10');
      expect(data3.port, 28000);
      expect(data3.pin, '445566');

      final data2 = QrPairingParser.tryParse('192.168.1.10:445566');
      expect(data2, isNotNull);
      expect(data2!.ip, '192.168.1.10');
      expect(data2.port, 26760);
      expect(data2.pin, '445566');
    });

    test('rejects invalid inputs', () {
      expect(QrPairingParser.tryParse(null), isNull);
      expect(QrPairingParser.tryParse(''), isNull);
      expect(QrPairingParser.tryParse('   '), isNull);
      expect(QrPairingParser.tryParse('http://google.com'), isNull);
      expect(QrPairingParser.tryParse('pulgapp://pair?ip=192.168.1.1'), isNull);
      expect(QrPairingParser.tryParse('pulgapp://pair?pin=123456'), isNull);
      expect(
        QrPairingParser.tryParse('pulgapp://pair?ip=192.168.1.1&pin=12345'),
        isNull,
      );
      expect(
        QrPairingParser.tryParse('pulgapp://pair?ip=192.168.1.1&pin=abcdef'),
        isNull,
      );
      expect(
        QrPairingParser.tryParse('pulgapp://pair?ip=192.168.1.1&port=99999&pin=123456'),
        isNull,
      );
      expect(QrPairingParser.tryParse('{"ip":"192.168.1.1"}'), isNull);
      expect(QrPairingParser.tryParse('not-a-qr-code'), isNull);
    });
  });
}
