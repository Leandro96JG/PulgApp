namespace Pulgapp.Server.Protocol;

[Flags]
public enum CanonicalButtons : uint
{
    A = 1 << 0,
    B = 1 << 1,
    X = 1 << 2,
    Y = 1 << 3,
    LeftBumper = 1 << 4,
    RightBumper = 1 << 5,
    Back = 1 << 6,
    Start = 1 << 7,
    LeftStick = 1 << 8,
    RightStick = 1 << 9,
    Guide = 1 << 10,
    DpadUp = 1 << 11,
    DpadDown = 1 << 12,
    DpadLeft = 1 << 13,
    DpadRight = 1 << 14,
    TouchpadClick = 1 << 15,
}

public sealed record InputSnapshot(
    ulong SessionId,
    byte[] UdpToken,
    uint Sequence,
    ulong ClientTimeUs,
    CanonicalButtons Buttons,
    short LeftX,
    short LeftY,
    short RightX,
    short RightY,
    ushort LeftTrigger,
    ushort RightTrigger);
