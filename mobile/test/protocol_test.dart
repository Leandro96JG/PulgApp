import 'dart:io';
import 'dart:typed_data';

import 'package:pulgapp_mobile/protocol.dart';
import 'package:test/test.dart';

void main() {
  final fixturePath =
      '${Directory.current.path}${Platform.pathSeparator}..${Platform.pathSeparator}protocol${Platform.pathSeparator}fixtures${Platform.pathSeparator}input-state-v1.bin';

  test('encodes the repository golden fixture at every offset', () {
    final actual = UdpInputEncoder.encode(
      InputSnapshot(
        sessionId: const Uint64Value(0x01234567, 0x89abcdef),
        udpToken: Uint8List.fromList([
          0x00,
          0x11,
          0x22,
          0x33,
          0x44,
          0x55,
          0x66,
          0x77,
          0x88,
          0x99,
          0xaa,
          0xbb,
          0xcc,
          0xdd,
          0xee,
          0xff,
        ]),
        sequence: 42,
        clientTimeUs: const Uint64Value(0, 1234567),
        buttons: (1 << 0) | (1 << 5) | (1 << 7) | (1 << 11),
        leftX: 16384,
        leftY: -8192,
        rightX: 0,
        rightY: 32767,
        leftTrigger: 32768,
        rightTrigger: 65535,
      ),
    );

    expect(actual, orderedEquals(File(fixturePath).readAsBytesSync()));
  });

  test('normalizes opposing D-pad pairs and ignores reserved buttons', () {
    final encoded = UdpInputEncoder.encode(
      _snapshot(
        buttons:
            (1 << 0) |
            (1 << 11) |
            (1 << 12) |
            (1 << 13) |
            (1 << 14) |
            (1 << 31),
      ),
    );

    expect(ByteData.sublistView(encoded).getUint32(44, Endian.little), 1);
  });

  test('rejects invalid field ranges and token length', () {
    expect(
      () => UdpInputEncoder.encode(_snapshot(leftX: 32768)),
      throwsRangeError,
    );
    expect(
      () => UdpInputEncoder.encode(_snapshot(leftTrigger: -1)),
      throwsRangeError,
    );
    expect(
      () => UdpInputEncoder.encode(
        InputSnapshot(
          sessionId: const Uint64Value(0, 1),
          udpToken: Uint8List(15),
          sequence: 1,
          clientTimeUs: const Uint64Value(0, 1),
          buttons: 0,
          leftX: 0,
          leftY: 0,
          rightX: 0,
          rightY: 0,
          leftTrigger: 0,
          rightTrigger: 0,
        ),
      ),
      throwsArgumentError,
    );
  });
}

InputSnapshot _snapshot({
  int buttons = 0,
  int leftX = 0,
  int leftTrigger = 0,
}) => InputSnapshot(
  sessionId: const Uint64Value(0, 1),
  udpToken: Uint8List(16),
  sequence: 1,
  clientTimeUs: const Uint64Value(0, 1),
  buttons: buttons,
  leftX: leftX,
  leftY: 0,
  rightX: 0,
  rightY: 0,
  leftTrigger: leftTrigger,
  rightTrigger: 0,
);
