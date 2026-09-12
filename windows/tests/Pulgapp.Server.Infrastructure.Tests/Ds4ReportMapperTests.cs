using Pulgapp.Server.Core;
using Pulgapp.Server.Infrastructure;

namespace Pulgapp.Server.Infrastructure.Tests;

public sealed class Ds4ReportMapperTests
{
    [Fact]
    public void Maps_face_buttons_shoulders_thumb_buttons_and_ps_button()
    {
        const uint buttons = 0x000007FF;

        var report = Ds4ReportMapper.Map(new GamepadState(buttons, 0, 0, 0, 0, 0, 0));

        Assert.Equal(
            Ds4Buttons.Cross | Ds4Buttons.Circle | Ds4Buttons.Square | Ds4Buttons.Triangle |
            Ds4Buttons.LeftShoulder | Ds4Buttons.RightShoulder | Ds4Buttons.Share | Ds4Buttons.Options |
            Ds4Buttons.LeftThumb | Ds4Buttons.RightThumb,
            report.Buttons);
        Assert.True(report.PsButton);
    }

    [Theory]
    [InlineData(0, 0, 0, 0, Ds4DpadDirection.None)]
    [InlineData(1, 0, 0, 0, Ds4DpadDirection.North)]
    [InlineData(1, 0, 0, 1, Ds4DpadDirection.NorthEast)]
    [InlineData(0, 1, 1, 0, Ds4DpadDirection.SouthWest)]
    [InlineData(1, 1, 0, 0, Ds4DpadDirection.None)]
    public void Converts_valid_dpad_combinations_to_one_hat_direction(
        int up, int down, int left, int right, Ds4DpadDirection expected)
    {
        var buttons = (up << 11) | (down << 12) | (left << 13) | (right << 14);

        var report = Ds4ReportMapper.Map(new GamepadState((uint)buttons, 0, 0, 0, 0, 0, 0));

        Assert.Equal(expected, report.Dpad);
    }

    [Fact]
    public void Inverts_only_y_axes_and_maps_the_full_canonical_axis_range()
    {
        var report = Ds4ReportMapper.Map(new GamepadState(0, short.MinValue, short.MaxValue, short.MaxValue, short.MinValue, 0, 0));

        Assert.Equal(byte.MinValue, report.LeftX);
        Assert.Equal(byte.MinValue, report.LeftY);
        Assert.Equal(byte.MaxValue, report.RightX);
        Assert.Equal(byte.MaxValue, report.RightY);
    }

    [Fact]
    public void Maps_analog_triggers_and_sets_their_digital_button_state_when_nonzero()
    {
        var report = Ds4ReportMapper.Map(new GamepadState(0, 0, 0, 0, 0, 129, ushort.MaxValue));

        Assert.Equal((byte)1, report.LeftTrigger);
        Assert.Equal(byte.MaxValue, report.RightTrigger);
        Assert.Equal(Ds4Buttons.LeftTrigger | Ds4Buttons.RightTrigger, report.Buttons);
    }
}
