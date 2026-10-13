using Pulgapp.Server.Protocol;

namespace Pulgapp.Server.Protocol.Tests;

public sealed class QrPairingPayloadTests
{
    [Fact]
    public void Format_builds_canonical_uri()
    {
        var uri = QrPairingPayload.Format("192.168.1.50", 26760, "123456");
        Assert.Equal("pulgapp://pair?ip=192.168.1.50&port=26760&pin=123456", uri);
    }

    [Theory]
    [InlineData("", 26760, "123456")]
    [InlineData("   ", 26760, "123456")]
    [InlineData("192.168.1.1", 0, "123456")]
    [InlineData("192.168.1.1", 70000, "123456")]
    [InlineData("192.168.1.1", 26760, "12345")]
    [InlineData("192.168.1.1", 26760, "1234567")]
    [InlineData("192.168.1.1", 26760, "abcdef")]
    public void Format_throws_on_invalid_arguments(string ip, int port, string pin)
    {
        Assert.ThrowsAny<ArgumentException>(() => QrPairingPayload.Format(ip, port, pin));
    }

    [Fact]
    public void TryParse_parses_canonical_uri()
    {
        var success = QrPairingPayload.TryParse("pulgapp://pair?ip=192.168.1.50&port=26760&pin=123456", out var ip, out var port, out var pin);
        Assert.True(success);
        Assert.Equal("192.168.1.50", ip);
        Assert.Equal(26760, port);
        Assert.Equal("123456", pin);
    }

    [Fact]
    public void TryParse_parses_uri_with_swapped_query_params_and_connect_host()
    {
        var success = QrPairingPayload.TryParse("pulgapp://connect?pin=654321&port=27000&ip=10.0.0.15", out var ip, out var port, out var pin);
        Assert.True(success);
        Assert.Equal("10.0.0.15", ip);
        Assert.Equal(27000, port);
        Assert.Equal("654321", pin);
    }

    [Fact]
    public void TryParse_defaults_port_when_omitted_in_uri()
    {
        var success = QrPairingPayload.TryParse("pulgapp://pair?ip=192.168.0.100&pin=112233", out var ip, out var port, out var pin);
        Assert.True(success);
        Assert.Equal("192.168.0.100", ip);
        Assert.Equal(26760, port);
        Assert.Equal("112233", pin);
    }

    [Fact]
    public void TryParse_parses_json_fallback()
    {
        var success = QrPairingPayload.TryParse("{\"ip\":\"192.168.1.200\",\"port\":26760,\"pin\":\"998877\"}", out var ip, out var port, out var pin);
        Assert.True(success);
        Assert.Equal("192.168.1.200", ip);
        Assert.Equal(26760, port);
        Assert.Equal("998877", pin);
    }

    [Fact]
    public void TryParse_parses_colon_separated_fallbacks()
    {
        var success3 = QrPairingPayload.TryParse("192.168.1.10:28000:445566", out var ip3, out var port3, out var pin3);
        Assert.True(success3);
        Assert.Equal("192.168.1.10", ip3);
        Assert.Equal(28000, port3);
        Assert.Equal("445566", pin3);

        var success2 = QrPairingPayload.TryParse("192.168.1.10:445566", out var ip2, out var port2, out var pin2);
        Assert.True(success2);
        Assert.Equal("192.168.1.10", ip2);
        Assert.Equal(26760, port2);
        Assert.Equal("445566", pin2);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("http://example.com")]
    [InlineData("pulgapp://pair?ip=192.168.1.1")]
    [InlineData("pulgapp://pair?pin=123456")]
    [InlineData("pulgapp://pair?ip=192.168.1.1&pin=1234")]
    [InlineData("{\"ip\":\"192.168.1.1\"}")]
    [InlineData("invalid-plain-text")]
    public void TryParse_rejects_malformed_payloads(string? invalidInput)
    {
        var success = QrPairingPayload.TryParse(invalidInput, out var ip, out var port, out var pin);
        Assert.False(success);
        Assert.Null(ip);
        Assert.Null(pin);
    }
}
