using Pulgapp.Server.Core;
using Pulgapp.Server.Infrastructure;

namespace Pulgapp.Server.Infrastructure.Tests;

public sealed class X360ReportMapperTests
{
    [Fact]
    public void Maps_every_supported_button_and_preserves_canonical_axes()
    {
        const uint buttons = 0x00007FFF;

        var report = X360ReportMapper.Map(new GamepadState(buttons, 123, -456, 789, -1011, 0, ushort.MaxValue));

        Assert.Equal(
            X360Buttons.A | X360Buttons.B | X360Buttons.X | X360Buttons.Y |
            X360Buttons.LeftShoulder | X360Buttons.RightShoulder |
            X360Buttons.Back | X360Buttons.Start | X360Buttons.LeftThumb | X360Buttons.RightThumb |
            X360Buttons.Guide | X360Buttons.DpadUp | X360Buttons.DpadDown | X360Buttons.DpadLeft | X360Buttons.DpadRight,
            report.Buttons);
        Assert.Equal((byte)0, report.LeftTrigger);
        Assert.Equal(byte.MaxValue, report.RightTrigger);
        Assert.Equal(123, report.LeftX);
        Assert.Equal(-456, report.LeftY);
        Assert.Equal(789, report.RightX);
        Assert.Equal(-1011, report.RightY);
    }

    [Theory]
    [InlineData((ushort)1, (byte)0)]
    [InlineData((ushort)128, (byte)0)]
    [InlineData((ushort)129, (byte)1)]
    [InlineData((ushort)32768, (byte)128)]
    [InlineData(ushort.MaxValue, byte.MaxValue)]
    public void Rounds_uint16_triggers_to_x360_bytes(ushort trigger, byte expected)
    {
        var report = X360ReportMapper.Map(new GamepadState(0, 0, 0, 0, 0, trigger, trigger));

        Assert.Equal(expected, report.LeftTrigger);
        Assert.Equal(expected, report.RightTrigger);
    }

    [Fact]
    public void Ignores_touchpad_and_reserved_buttons()
    {
        var report = X360ReportMapper.Map(new GamepadState((1U << 15) | (1U << 31), 0, 0, 0, 0, 0, 0));

        Assert.Equal(X360Buttons.None, report.Buttons);
    }
}
