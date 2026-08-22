using System.Buffers.Binary;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.WebUtilities;
using Pulgapp.Server.Core;
using Pulgapp.Server.Infrastructure;

namespace Pulgapp.Server.IntegrationTests;

public sealed class PulgappServerTests
{
    [Fact]
    public async Task HealthHelloPingAndUdpInputUseTheConfiguredProtocol()
    {
        var factory = new FakeControllerFactory();
        await using var server = new PulgappServer(
            new PulgappServerOptions(FindAvailablePort(), 0, "482913", "Test Server", Guid.Parse("65fd878c-6001-45ee-b20d-24e471e4fa5b")),
            new SessionCoordinator(factory, TimeProvider.System));
        await server.StartAsync();
        var port = GetTcpPort(server);
        using var http = new HttpClient();
        Assert.Equal("{\"status\":\"ok\"}", await http.GetStringAsync($"http://127.0.0.1:{port}/health"));

        using var socket = new ClientWebSocket();
        await socket.ConnectAsync(new Uri($"ws://127.0.0.1:{port}/control"), CancellationToken.None);
        await SendJsonAsync(socket, new
        {
            v = 1,
            type = "hello",
            clientId = "263b2310-4e1a-48df-8836-c5600ac77719",
            clientName = "Test Phone",
            appVersion = "0.1.0",
            pin = "482913",
            capabilities = new[] { "udp_input_v1" },
        });
        using var welcome = await ReceiveJsonAsync(socket);
        Assert.Equal("welcome", welcome.RootElement.GetProperty("type").GetString());
        Assert.Equal(1, welcome.RootElement.GetProperty("slot").GetInt32());
        Assert.Equal("x360", welcome.RootElement.GetProperty("controllerType").GetString());

        await SendJsonAsync(socket, new { v = 1, type = "ping", id = 42, clientTimeUs = "123456789" });
        using var pong = await ReceiveJsonAsync(socket);
        Assert.Equal("pong", pong.RootElement.GetProperty("type").GetString());
        Assert.Equal(42U, pong.RootElement.GetProperty("id").GetUInt32());

        var sessionId = Convert.ToUInt64(welcome.RootElement.GetProperty("sessionId").GetString(), 16);
        var token = WebEncoders.Base64UrlDecode(welcome.RootElement.GetProperty("udpToken").GetString()!);
        using var udp = new UdpClient();
        await udp.SendAsync(CreateDatagram(sessionId, token, 7), new IPEndPoint(IPAddress.Loopback, server.UdpPort));
        using var inputReady = await ReceiveJsonAsync(socket);
        Assert.Equal("input_ready", inputReady.RootElement.GetProperty("type").GetString());
        Assert.Equal(7U, inputReady.RootElement.GetProperty("sequence").GetUInt32());
        using var inputStatus = await ReceiveJsonAsync(socket);
        Assert.Equal("ready", inputStatus.RootElement.GetProperty("state").GetString());
        Assert.True(SpinWait.SpinUntil(() => factory.Controller.AppliedStates.Any(state => state.Buttons == 1), TimeSpan.FromSeconds(2)));
        Assert.Equal((ushort)65535, factory.Controller.AppliedStates.Last().RightTrigger);

        using var timedOut = await ReceiveJsonAsync(socket);
        Assert.Equal("timed_out", timedOut.RootElement.GetProperty("state").GetString());
        await udp.SendAsync(CreateDatagram(sessionId, token, 8), new IPEndPoint(IPAddress.Loopback, server.UdpPort));
        using var restored = await ReceiveJsonAsync(socket);
        Assert.Equal("restored", restored.RootElement.GetProperty("state").GetString());
    }

    [Fact]
    public async Task InvalidPinDoesNotCreateATarget()
    {
        var factory = new FakeControllerFactory();
        await using var server = new PulgappServer(new PulgappServerOptions(FindAvailablePort(), 0, "482913"), new SessionCoordinator(factory, TimeProvider.System));
        await server.StartAsync();
        using var socket = new ClientWebSocket();
        await socket.ConnectAsync(new Uri($"ws://127.0.0.1:{GetTcpPort(server)}/control"), CancellationToken.None);
        await SendJsonAsync(socket, new { v = 1, type = "hello", clientId = Guid.NewGuid(), clientName = "Test", appVersion = "1", pin = "000000", capabilities = new[] { "udp_input_v1" } });
        using var error = await ReceiveJsonAsync(socket);
        Assert.Equal("invalid_pin", error.RootElement.GetProperty("code").GetString());
        Assert.Equal(0, factory.CreateCount);
    }

    [Fact]
    public async Task DashboardStatusTracksClientInputAndAdministrativeActions()
    {
        var factory = new FakeControllerFactory();
        await using var server = new PulgappServer(
            new PulgappServerOptions(FindAvailablePort(), 0, "482913"),
            new SessionCoordinator(factory, TimeProvider.System));
        await server.StartAsync();

        var initial = await server.GetStatusAsync();
        Assert.True(initial.IsRunning);
        Assert.Equal("482913", initial.Pin);
        Assert.Equal("Waiting for client", initial.ConnectionState);

        using var socket = new ClientWebSocket();
        await socket.ConnectAsync(new Uri($"ws://127.0.0.1:{GetTcpPort(server)}/control"), CancellationToken.None);
        await SendJsonAsync(socket, new { v = 1, type = "hello", clientId = Guid.NewGuid(), clientName = "Dashboard Phone", appVersion = "1", pin = "482913", capabilities = new[] { "udp_input_v1" } });
        using var welcome = await ReceiveJsonAsync(socket);
        var sessionId = Convert.ToUInt64(welcome.RootElement.GetProperty("sessionId").GetString(), 16);
        var token = WebEncoders.Base64UrlDecode(welcome.RootElement.GetProperty("udpToken").GetString()!);
        using var udp = new UdpClient();
        await udp.SendAsync(CreateDatagram(sessionId, token, 1), new IPEndPoint(IPAddress.Loopback, server.UdpPort));
        using var inputReady = await ReceiveJsonAsync(socket);

        var connected = await server.GetStatusAsync();
        Assert.Equal("Dashboard Phone", connected.ClientName);
        Assert.Equal("Input ready", connected.ConnectionState);
        Assert.NotNull(connected.LastInputAge);
        Assert.True(connected.PacketRate >= 0);

        var regeneratedPin = await server.RegeneratePinAsync();
        Assert.Matches("^[0-9]{6}$", regeneratedPin);
        await server.KickAsync();
        Assert.Equal("Waiting for client", (await server.GetStatusAsync()).ConnectionState);
    }

    private static int GetTcpPort(PulgappServer server)
    {
        var property = typeof(PulgappServer).GetField("_options", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance)!;
        return ((PulgappServerOptions)property.GetValue(server)!).TcpPort;
    }

    private static int FindAvailablePort()
    {
        using var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        return ((IPEndPoint)listener.LocalEndpoint).Port;
    }

    private static async Task SendJsonAsync(ClientWebSocket socket, object value)
    {
        var bytes = JsonSerializer.SerializeToUtf8Bytes(value);
        await socket.SendAsync(bytes, WebSocketMessageType.Text, true, CancellationToken.None);
    }

    private static async Task<JsonDocument> ReceiveJsonAsync(ClientWebSocket socket)
    {
        var bytes = new byte[4096];
        var result = await socket.ReceiveAsync(bytes, CancellationToken.None);
        return JsonDocument.Parse(bytes.AsMemory(0, result.Count));
    }

    private static byte[] CreateDatagram(ulong sessionId, byte[] token, uint sequence)
    {
        var datagram = new byte[60];
        Encoding.ASCII.GetBytes("PULG", datagram);
        datagram[4] = 1;
        datagram[5] = 1;
        BinaryPrimitives.WriteUInt64LittleEndian(datagram.AsSpan(8), sessionId);
        token.CopyTo(datagram, 16);
        BinaryPrimitives.WriteUInt32LittleEndian(datagram.AsSpan(32), sequence);
        BinaryPrimitives.WriteUInt32LittleEndian(datagram.AsSpan(44), 1);
        BinaryPrimitives.WriteUInt16LittleEndian(datagram.AsSpan(58), ushort.MaxValue);
        return datagram;
    }

    private sealed class FakeControllerFactory : VirtualControllerFactory
    {
        public FakeController Controller { get; } = new();

        public int CreateCount { get; private set; }

        public VirtualController Create(ControllerKind kind)
        {
            Assert.Equal(ControllerKind.X360, kind);
            CreateCount++;
            return Controller;
        }
    }

    private sealed class FakeController : VirtualController
    {
        public List<GamepadState> AppliedStates { get; } = [];

        public ControllerKind Kind => ControllerKind.X360;

        public void Connect() { }

        public void Apply(GamepadState state) => AppliedStates.Add(state);

        public void Neutralize() => AppliedStates.Add(GamepadState.Neutral);

        public void Disconnect() { }
    }
}
