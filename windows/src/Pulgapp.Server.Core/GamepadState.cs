namespace Pulgapp.Server.Core;

public sealed record GamepadState(
    uint Buttons,
    short LeftX,
    short LeftY,
    short RightX,
    short RightY,
    ushort LeftTrigger,
    ushort RightTrigger)
{
    public static GamepadState Neutral { get; } = new(0, 0, 0, 0, 0, 0, 0);
}
