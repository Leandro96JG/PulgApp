library;

import 'dart:typed_data';

enum ControllerType { x360, ds4 }

final class HelloMessage {
  const HelloMessage({
    required this.clientId,
    required this.clientName,
    required this.appVersion,
    required this.capabilities,
    this.pin,
    this.resumeToken,
  });

  final String clientId;
  final String clientName;
  final String appVersion;
  final List<String> capabilities;
  final String? pin;
  final String? resumeToken;

  Map<String, Object> toJson() => {
    'v': 1,
    'type': 'hello',
    'clientId': clientId,
    'clientName': clientName,
    'appVersion': appVersion,
    'capabilities': capabilities,
    if (pin != null) 'pin': pin!,
    if (resumeToken != null) 'resumeToken': resumeToken!,
  };
}

final class WelcomeMessage {
  const WelcomeMessage({
    required this.serverId,
    required this.serverName,
    required this.sessionId,
    required this.udpToken,
    required this.udpPort,
    required this.slot,
    required this.controllerType,
    required this.resumed,
    required this.resumeToken,
    required this.inputTimeoutMs,
    required this.slotLeaseMs,
  });

  final String serverId;
  final String serverName;
  final String sessionId;
  final String udpToken;
  final int udpPort;
  final int slot;
  final ControllerType controllerType;
  final bool resumed;
  final String resumeToken;
  final int inputTimeoutMs;
  final int slotLeaseMs;
}

final class InputReadyMessage {
  const InputReadyMessage(this.sequence);

  final int sequence;
}

final class InputStatusMessage {
  const InputStatusMessage(this.state, this.lastSequence);

  final String state;
  final int? lastSequence;
}

final class PingMessage {
  const PingMessage(this.id, this.clientTimeUs);

  final int id;
  final String clientTimeUs;

  Map<String, Object> toJson() => {
    'v': 1,
    'type': 'ping',
    'id': id,
    'clientTimeUs': clientTimeUs,
  };
}

final class PongMessage {
  const PongMessage(
    this.id,
    this.clientTimeUs,
    this.serverReceiveTimeUs,
    this.serverSendTimeUs,
  );

  final int id;
  final String clientTimeUs;
  final String serverReceiveTimeUs;
  final String serverSendTimeUs;
}

final class LeaveMessage {
  const LeaveMessage();

  Map<String, Object> toJson() => {'v': 1, 'type': 'leave'};
}

final class SuspendMessage {
  const SuspendMessage();

  Map<String, Object> toJson() => {'v': 1, 'type': 'suspend'};
}

final class RumbleMessage {
  const RumbleMessage(this.lowFrequency, this.highFrequency);

  final int lowFrequency;
  final int highFrequency;
}

final class ErrorMessage {
  const ErrorMessage(this.code, this.message, this.fatal, this.retryAfterMs);

  final String code;
  final String message;
  final bool fatal;
  final int? retryAfterMs;
}

final class InputSnapshot {
  const InputSnapshot({
    required this.sessionId,
    required this.udpToken,
    required this.sequence,
    required this.clientTimeUs,
    required this.buttons,
    required this.leftX,
    required this.leftY,
    required this.rightX,
    required this.rightY,
    required this.leftTrigger,
    required this.rightTrigger,
  });

  final Uint64Value sessionId;
  final Uint8List udpToken;
  final int sequence;
  final Uint64Value clientTimeUs;
  final int buttons;
  final int leftX;
  final int leftY;
  final int rightX;
  final int rightY;
  final int leftTrigger;
  final int rightTrigger;
}

final class Uint64Value {
  const Uint64Value(this.highBits, this.lowBits)
    : assert(highBits >= 0 && highBits <= 0xffffffff),
      assert(lowBits >= 0 && lowBits <= 0xffffffff);

  final int highBits;
  final int lowBits;

  static const zero = Uint64Value(0, 0);
}

final class UdpInputEncoder {
  static const int datagramLength = 60;
  static const int _knownButtonMask = 0x0000ffff;
  static const int _dpadUp = 1 << 11;
  static const int _dpadDown = 1 << 12;
  static const int _dpadLeft = 1 << 13;
  static const int _dpadRight = 1 << 14;

  static Uint8List encode(InputSnapshot snapshot) {
    _checkUint64(snapshot.sessionId, 'sessionId');
    if (snapshot.udpToken.length != 16) {
      throw ArgumentError.value(
        snapshot.udpToken.length,
        'udpToken.length',
        'must be 16 bytes',
      );
    }
    _checkRange(snapshot.sequence, 0, 0xffffffff, 'sequence');
    _checkUint64(snapshot.clientTimeUs, 'clientTimeUs');
    _checkRange(snapshot.buttons, 0, 0xffffffff, 'buttons');
    _checkRange(snapshot.leftX, -0x8000, 0x7fff, 'leftX');
    _checkRange(snapshot.leftY, -0x8000, 0x7fff, 'leftY');
    _checkRange(snapshot.rightX, -0x8000, 0x7fff, 'rightX');
    _checkRange(snapshot.rightY, -0x8000, 0x7fff, 'rightY');
    _checkRange(snapshot.leftTrigger, 0, 0xffff, 'leftTrigger');
    _checkRange(snapshot.rightTrigger, 0, 0xffff, 'rightTrigger');

    final bytes = Uint8List(datagramLength);
    final data = ByteData.sublistView(bytes);
    bytes.setRange(0, 4, 'PULG'.codeUnits);
    data.setUint8(4, 1);
    data.setUint8(5, 1);
    data.setUint16(6, 0, Endian.little);
    data.setUint32(8, snapshot.sessionId.lowBits, Endian.little);
    data.setUint32(12, snapshot.sessionId.highBits, Endian.little);
    bytes.setRange(16, 32, snapshot.udpToken);
    data.setUint32(32, snapshot.sequence, Endian.little);
    data.setUint32(36, snapshot.clientTimeUs.lowBits, Endian.little);
    data.setUint32(40, snapshot.clientTimeUs.highBits, Endian.little);
    data.setUint32(44, _normalizeButtons(snapshot.buttons), Endian.little);
    data.setInt16(48, snapshot.leftX, Endian.little);
    data.setInt16(50, snapshot.leftY, Endian.little);
    data.setInt16(52, snapshot.rightX, Endian.little);
    data.setInt16(54, snapshot.rightY, Endian.little);
    data.setUint16(56, snapshot.leftTrigger, Endian.little);
    data.setUint16(58, snapshot.rightTrigger, Endian.little);
    return bytes;
  }

  static int _normalizeButtons(int buttons) {
    buttons &= _knownButtonMask;
    if (buttons & (_dpadUp | _dpadDown) == (_dpadUp | _dpadDown)) {
      buttons &= ~(_dpadUp | _dpadDown);
    }
    if (buttons & (_dpadLeft | _dpadRight) == (_dpadLeft | _dpadRight)) {
      buttons &= ~(_dpadLeft | _dpadRight);
    }
    return buttons;
  }

  static void _checkRange(int value, int minimum, int maximum, String name) {
    if (value < minimum || value > maximum) {
      throw RangeError.range(value, minimum, maximum, name);
    }
  }

  static void _checkUint64(Uint64Value value, String name) {
    _checkRange(value.highBits, 0, 0xffffffff, '$name.highBits');
    _checkRange(value.lowBits, 0, 0xffffffff, '$name.lowBits');
  }
}
