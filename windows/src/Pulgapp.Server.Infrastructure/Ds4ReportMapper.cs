using Pulgapp.Server.Core;

namespace Pulgapp.Server.Infrastructure;

[Flags]
public enum Ds4Buttons : ushort
{
    None = 0,
    Square = 0x0010,
    Cross = 0x0020,
    Circle = 0x0040,
    Triangle = 0x0080,
    LeftShoulder = 0x0100,
    RightShoulder = 0x0200,
    LeftTrigger = 0x0400,
    RightTrigger = 0x0800,
    Share = 0x1000,
    Options = 0x2000,
    LeftThumb = 0x4000,
    RightThumb = 0x8000,
}

public enum Ds4DpadDirection : byte
{
    None,
    North,
    NorthEast,
    East,
    SouthEast,
    South,
    SouthWest,
    West,
    NorthWest,
}

public sealed record Ds4Report(
    Ds4Buttons Buttons,
    bool PsButton,
    Ds4DpadDirection Dpad,
    byte LeftTrigger,
    byte RightTrigger,
    byte LeftX,
    byte LeftY,
    byte RightX,
    byte RightY);

public static class Ds4ReportMapper
{
    public static Ds4Report Map(GamepadState state) => new(
        MapButtons(state.Buttons, state.LeftTrigger, state.RightTrigger),
        Has(state.Buttons, 10),
        MapDpad(state.Buttons),
        MapByte(state.LeftTrigger),
        MapByte(state.RightTrigger),
        MapAxis(state.LeftX),
        MapInvertedAxis(state.LeftY),
        MapAxis(state.RightX),
        MapInvertedAxis(state.RightY));

    private static Ds4Buttons MapButtons(uint buttons, ushort leftTrigger, ushort rightTrigger)
    {
        var mapped = Ds4Buttons.None;
        mapped |= Has(buttons, 0) ? Ds4Buttons.Cross : 0;
        mapped |= Has(buttons, 1) ? Ds4Buttons.Circle : 0;
        mapped |= Has(buttons, 2) ? Ds4Buttons.Square : 0;
        mapped |= Has(buttons, 3) ? Ds4Buttons.Triangle : 0;
        mapped |= Has(buttons, 4) ? Ds4Buttons.LeftShoulder : 0;
        mapped |= Has(buttons, 5) ? Ds4Buttons.RightShoulder : 0;
        mapped |= Has(buttons, 6) ? Ds4Buttons.Share : 0;
        mapped |= Has(buttons, 7) ? Ds4Buttons.Options : 0;
        mapped |= Has(buttons, 8) ? Ds4Buttons.LeftThumb : 0;
        mapped |= Has(buttons, 9) ? Ds4Buttons.RightThumb : 0;
        mapped |= leftTrigger != 0 ? Ds4Buttons.LeftTrigger : 0;
        mapped |= rightTrigger != 0 ? Ds4Buttons.RightTrigger : 0;
        return mapped;
    }

    private static Ds4DpadDirection MapDpad(uint buttons)
    {
        var up = Has(buttons, 11);
        var down = Has(buttons, 12);
        var left = Has(buttons, 13);
        var right = Has(buttons, 14);
        return (up, down, left, right) switch
        {
            (true, false, false, false) => Ds4DpadDirection.North,
            (true, false, false, true) => Ds4DpadDirection.NorthEast,
            (false, false, false, true) => Ds4DpadDirection.East,
            (false, true, false, true) => Ds4DpadDirection.SouthEast,
            (false, true, false, false) => Ds4DpadDirection.South,
            (false, true, true, false) => Ds4DpadDirection.SouthWest,
            (false, false, true, false) => Ds4DpadDirection.West,
            (true, false, true, false) => Ds4DpadDirection.NorthWest,
            _ => Ds4DpadDirection.None,
        };
    }

    private static bool Has(uint buttons, int bit) => (buttons & (1U << bit)) != 0;

    private static byte MapByte(ushort value) => (byte)((value * 255 + 32767) / 65535);

    private static byte MapAxis(short value) => (byte)((value - short.MinValue + 128) / 257);

    private static byte MapInvertedAxis(short value) => MapAxis(
        value == short.MinValue ? short.MaxValue : (short)-value);
}
