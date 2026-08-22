final class GamepadState {
  const GamepadState({
    this.buttons = 0,
    this.leftX = 0,
    this.leftY = 0,
    this.rightX = 0,
    this.rightY = 0,
    this.leftTrigger = 0,
    this.rightTrigger = 0,
  });

  static const neutral = GamepadState();

  final int buttons;
  final int leftX;
  final int leftY;
  final int rightX;
  final int rightY;
  final int leftTrigger;
  final int rightTrigger;

  GamepadState copyWith({
    int? buttons,
    int? leftX,
    int? leftY,
    int? rightX,
    int? rightY,
    int? leftTrigger,
    int? rightTrigger,
  }) => GamepadState(
    buttons: buttons ?? this.buttons,
    leftX: leftX ?? this.leftX,
    leftY: leftY ?? this.leftY,
    rightX: rightX ?? this.rightX,
    rightY: rightY ?? this.rightY,
    leftTrigger: leftTrigger ?? this.leftTrigger,
    rightTrigger: rightTrigger ?? this.rightTrigger,
  );

  @override
  bool operator ==(Object other) =>
      other is GamepadState &&
      buttons == other.buttons &&
      leftX == other.leftX &&
      leftY == other.leftY &&
      rightX == other.rightX &&
      rightY == other.rightY &&
      leftTrigger == other.leftTrigger &&
      rightTrigger == other.rightTrigger;

  @override
  int get hashCode => Object.hash(
    buttons,
    leftX,
    leftY,
    rightX,
    rightY,
    leftTrigger,
    rightTrigger,
  );
}

abstract final class GamepadButton {
  static const a = 1 << 0;
  static const b = 1 << 1;
  static const x = 1 << 2;
  static const y = 1 << 3;
  static const lb = 1 << 4;
  static const rb = 1 << 5;
  static const back = 1 << 6;
  static const start = 1 << 7;
  static const l3 = 1 << 8;
  static const r3 = 1 << 9;
  static const guide = 1 << 10;
  static const dpadUp = 1 << 11;
  static const dpadDown = 1 << 12;
  static const dpadLeft = 1 << 13;
  static const dpadRight = 1 << 14;
}
