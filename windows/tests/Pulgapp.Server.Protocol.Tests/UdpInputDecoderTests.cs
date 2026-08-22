using System.Buffers.Binary;
using Pulgapp.Server.Protocol;

namespace Pulgapp.Server.Protocol.Tests;

public sealed class UdpInputDecoderTests
{
    private const string FixtureFileName = "input-state-v1.bin";

    [Fact]
    public void Fixture_decodes_every_field_at_its_little_endian_offset()
    {
        var decoded = DecodeFixture();

        Assert.Equal(0x0123456789ABCDEFUL, decoded.SessionId);
        Assert.Equal(Convert.FromHexString("00112233445566778899AABBCCDDEEFF"), decoded.UdpToken);
        Assert.Equal(42U, decoded.Sequence);
        Assert.Equal(1_234_567UL, decoded.ClientTimeUs);
        Assert.Equal(CanonicalButtons.A | CanonicalButtons.RightBumper | CanonicalButtons.Start | CanonicalButtons.DpadUp, decoded.Buttons);
        Assert.Equal(16_384, decoded.LeftX);
        Assert.Equal(-8_192, decoded.LeftY);
        Assert.Equal(0, decoded.RightX);
        Assert.Equal(short.MaxValue, decoded.RightY);
        Assert.Equal(32_768, decoded.LeftTrigger);
        Assert.Equal(ushort.MaxValue, decoded.RightTrigger);
    }

    [Theory]
    [InlineData(59)]
    [InlineData(61)]
    public void Rejects_invalid_length(int length)
    {
        var datagram = new byte[length];

        Assert.False(UdpInputDecoder.TryDecode(datagram, out _));
    }

    [Theory]
    [InlineData(0, (byte)'X')]
    [InlineData(4, 2)]
    [InlineData(5, 2)]
    [InlineData(6, 1)]
    public void Rejects_invalid_header(int offset, byte value)
    {
        var datagram = ReadFixture();
        datagram[offset] = value;

        Assert.False(UdpInputDecoder.TryDecode(datagram, out _));
    }

    [Fact]
    public void Normalizes_opposed_dpad_and_ignores_reserved_buttons()
    {
        var datagram = ReadFixture();
        var buttons = (uint)(CanonicalButtons.A | CanonicalButtons.DpadUp | CanonicalButtons.DpadDown | CanonicalButtons.DpadLeft | CanonicalButtons.DpadRight) | 0x80000000;
        BinaryPrimitives.WriteUInt32LittleEndian(datagram.AsSpan(44, 4), buttons);

        Assert.True(UdpInputDecoder.TryDecode(datagram, out var decoded));
        Assert.NotNull(decoded);
        Assert.Equal(CanonicalButtons.A, decoded.Buttons);
    }

    [Theory]
    [InlineData(1U, 0U, true)]
    [InlineData(0U, uint.MaxValue, true)]
    [InlineData(uint.MaxValue, 0U, false)]
    [InlineData(42U, 42U, false)]
    [InlineData(0x80000000U, 0U, false)]
    public void Compares_sequences_modulo_uint32(uint candidate, uint previous, bool expected)
    {
        Assert.Equal(expected, UdpInputDecoder.IsNewerSequence(candidate, previous));
    }

    private static InputSnapshot DecodeFixture()
    {
        Assert.True(UdpInputDecoder.TryDecode(ReadFixture(), out var decoded));
        return Assert.IsType<InputSnapshot>(decoded);
    }

    private static byte[] ReadFixture() => File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, FixtureFileName));
}
