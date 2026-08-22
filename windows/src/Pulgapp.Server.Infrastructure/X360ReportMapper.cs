using Pulgapp.Server.Core;

namespace Pulgapp.Server.Infrastructure;

[Flags]
public enum X360Buttons : ushort
{
    None = 0,
    DpadUp = 0x0001,
    DpadDown = 0x0002,
    DpadLeft = 0x0004,
    DpadRight = 0x0008,
    Start = 0x0010,
    Back = 0x0020,
    LeftThumb = 0x0040,
    RightThumb = 0x0080,
    LeftShoulder = 0x0100,
    RightShoulder = 0x0200,
    Guide = 0x0400,
    A = 0x1000,
    B = 0x2000,
    X = 0x4000,
    Y = 0x8000,
}

public sealed record X360Report(
    X360Buttons Buttons,
    byte LeftTrigger,
    byte RightTrigger,
    short LeftX,
    short LeftY,
    short RightX,
    short RightY);

public static class X360ReportMapper
{
    public static X360Report Map(GamepadState state) => new(
        MapButtons(state.Buttons),
        MapTrigger(state.LeftTrigger),
        MapTrigger(state.RightTrigger),
        state.LeftX,
        state.LeftY,
        state.RightX,
        state.RightY);

    private static X360Buttons MapButtons(uint buttons)
    {
        var mapped = X360Buttons.None;
        mapped |= Has(buttons, 0) ? X360Buttons.A : 0;
        mapped |= Has(buttons, 1) ? X360Buttons.B : 0;
        mapped |= Has(buttons, 2) ? X360Buttons.X : 0;
        mapped |= Has(buttons, 3) ? X360Buttons.Y : 0;
        mapped |= Has(buttons, 4) ? X360Buttons.LeftShoulder : 0;
        mapped |= Has(buttons, 5) ? X360Buttons.RightShoulder : 0;
        mapped |= Has(buttons, 6) ? X360Buttons.Back : 0;
        mapped |= Has(buttons, 7) ? X360Buttons.Start : 0;
        mapped |= Has(buttons, 8) ? X360Buttons.LeftThumb : 0;
        mapped |= Has(buttons, 9) ? X360Buttons.RightThumb : 0;
        mapped |= Has(buttons, 10) ? X360Buttons.Guide : 0;
        mapped |= Has(buttons, 11) ? X360Buttons.DpadUp : 0;
        mapped |= Has(buttons, 12) ? X360Buttons.DpadDown : 0;
        mapped |= Has(buttons, 13) ? X360Buttons.DpadLeft : 0;
        mapped |= Has(buttons, 14) ? X360Buttons.DpadRight : 0;
        return mapped;
    }

    private static bool Has(uint buttons, int bit) => (buttons & (1U << bit)) != 0;

    private static byte MapTrigger(ushort trigger) => (byte)((trigger * 255 + 32767) / 65535);
}
