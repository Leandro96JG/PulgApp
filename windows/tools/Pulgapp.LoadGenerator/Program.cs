using System.Buffers.Binary;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.WebUtilities;
using Pulgapp.Server.Core;
using Pulgapp.Server.Infrastructure;

var options = LoadOptions.Parse(args);
if (options.ShowHelp)
{
    LoadOptions.WriteHelp();
    return;
}

try
{
    await LoopbackLoadRun.RunAsync(options);
}
catch (Exception exception)
{
    Console.Error.WriteLine($"Load generation failed: {exception.Message}");
    Environment.ExitCode = 1;
}

internal sealed record LoadOptions(
    int Clients,
    int RateHz,
    TimeSpan Duration,
    uint SequenceStart,
    int LossEvery,
    int DuplicateEvery,
    int ReorderEvery,
    bool ShowHelp)
{
    public static LoadOptions Parse(string[] args)
    {
        var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        for (var index = 0; index < args.Length; index++)
        {
            if (args[index] is "--help" or "-h")
            {
                return Defaults with { ShowHelp = true };
            }

            if (!args[index].StartsWith("--", StringComparison.Ordinal) || index + 1 == args.Length)
            {
                throw new ArgumentException("Arguments must use --name value format. Use --help for usage.");
            }

            values.Add(args[index][2..], args[++index]);
        }

        return new LoadOptions(
            GetInt(values, "clients", Defaults.Clients, 1, 8),
            GetInt(values, "rate-hz", Defaults.RateHz, 1, 1000),
            TimeSpan.FromSeconds(GetInt(values, "duration-seconds", (int)Defaults.Duration.TotalSeconds, 1, 86_400)),
            GetUInt(values, "sequence-start", Defaults.SequenceStart),
            GetInt(values, "loss-every", Defaults.LossEvery, 0, int.MaxValue),
            GetInt(values, "duplicate-every", Defaults.DuplicateEvery, 0, int.MaxValue),
            GetInt(values, "reorder-every", Defaults.ReorderEvery, 0, int.MaxValue),
            false);
    }

    public static void WriteHelp()
    {
        Console.WriteLine("Pulgapp loopback load generator");
        Console.WriteLine("  --clients <1-8>                 Default: 4");
        Console.WriteLine("  --rate-hz <1-1000>              Default: 120");
        Console.WriteLine("  --duration-seconds <1-86400>    Default: 10");
        Console.WriteLine("  --sequence-start <uint32>       Default: 4294967280");
        Console.WriteLine("  --loss-every <packets, 0=off>   Default: 7");
        Console.WriteLine("  --duplicate-every <packets>     Default: 5");
        Console.WriteLine("  --reorder-every <packets>       Default: 9");
    }

    private static LoadOptions Defaults { get; } = new(4, 120, TimeSpan.FromSeconds(10), uint.MaxValue - 15, 7, 5, 9, false);

    private static int GetInt(IReadOnlyDictionary<string, string> values, string name, int defaultValue, int minimum, int maximum)
    {
        if (!values.TryGetValue(name, out var text) || !int.TryParse(text, out var value) || value < minimum || value > maximum)
        {
            if (values.ContainsKey(name))
            {
                throw new ArgumentOutOfRangeException(name, $"{name} must be between {minimum} and {maximum}.");
            }

            return defaultValue;
        }

        return value;
    }

    private static uint GetUInt(IReadOnlyDictionary<string, string> values, string name, uint defaultValue)
    {
        if (!values.TryGetValue(name, out var text))
        {
            return defaultValue;
        }

        return uint.TryParse(text, out var value)
            ? value
            : throw new ArgumentOutOfRangeException(name, $"{name} must be a uint32 value.");
    }
}

internal static class LoopbackLoadRun
{
    private const string Pin = "482913";

    public static async Task RunAsync(LoadOptions options)
    {
        var factory = new RecordingControllerFactory();
        var tcpPort = FindAvailablePort();
        await using var server = new PulgappServer(
            new PulgappServerOptions(tcpPort, 0, Pin, "Loopback Load Server"),
            new SessionCoordinator(factory, TimeProvider.System));
        await server.StartAsync();

        var clients = new List<LoadClient>();
        try
        {
            for (var clientNumber = 1; clientNumber <= options.Clients; clientNumber++)
            {
                var client = await LoadClient.ConnectAsync(tcpPort, clientNumber, options.SequenceStart);
                clients.Add(client);
            }

            var activeClients = clients.Where(client => client.IsAccepted).ToArray();
            var rejectedClients = clients.Where(client => !client.IsAccepted).ToArray();
            var expectedActiveClients = Math.Min(options.Clients, 4);
            if (activeClients.Length != expectedActiveClients || rejectedClients.Any(client => client.ErrorCode != "server_full"))
            {
                throw new InvalidOperationException("The server did not assign the expected X360 slots or reject excess clients as server_full.");
            }

            if (activeClients.Select(client => client.Slot).OrderBy(slot => slot).SequenceEqual(Enumerable.Range(1, expectedActiveClients)) is false)
            {
                throw new InvalidOperationException("Accepted clients did not receive unique, lowest-free slots.");
            }

            await SendLoadAsync(activeClients, options, server.UdpPort);
            await VerifyIsolationAsync(activeClients, factory, server.UdpPort);
            Console.WriteLine($"PASS: {activeClients.Length} active client(s), {rejectedClients.Length} server_full rejection(s), {options.RateHz} Hz for {options.Duration.TotalSeconds:F0} second(s).");
        }
        finally
        {
            foreach (var client in clients)
            {
                await client.DisposeAsync();
            }
        }
    }

    private static async Task SendLoadAsync(IReadOnlyList<LoadClient> clients, LoadOptions options, int udpPort)
    {
        var stopwatch = Stopwatch.StartNew();
        var interval = TimeSpan.FromSeconds(1d / options.RateHz);
        var nextSend = TimeSpan.Zero;
        var packetNumber = 0;
        while (stopwatch.Elapsed < options.Duration)
        {
            foreach (var client in clients)
            {
                packetNumber++;
                var sequence = client.NextSequence++;
                var packet = CreateDatagram(client.SessionId, client.UdpToken, sequence, client.State);
                if (options.LossEvery == 0 || packetNumber % options.LossEvery != 0)
                {
                    await client.Udp.SendAsync(packet, new IPEndPoint(IPAddress.Loopback, udpPort));
                }

                if (options.DuplicateEvery != 0 && packetNumber % options.DuplicateEvery == 0)
                {
                    await client.Udp.SendAsync(packet, new IPEndPoint(IPAddress.Loopback, udpPort));
                }

                if (options.ReorderEvery != 0 && packetNumber % options.ReorderEvery == 0 && client.PreviousPacket is not null)
                {
                    await client.Udp.SendAsync(client.PreviousPacket, new IPEndPoint(IPAddress.Loopback, udpPort));
                }

                client.PreviousPacket = packet;
            }

            nextSend += interval;
            var delay = nextSend - stopwatch.Elapsed;
            if (delay > TimeSpan.Zero)
            {
                await Task.Delay(delay);
            }
        }

        await Task.Delay(TimeSpan.FromMilliseconds(100));
    }

    private static async Task VerifyIsolationAsync(IReadOnlyList<LoadClient> clients, RecordingControllerFactory factory, int udpPort)
    {
        foreach (var client in clients)
        {
            if (!factory.TryGet(client.Slot, out var controller) || controller.LastAppliedState != client.State)
            {
                throw new InvalidOperationException($"Slot {client.Slot} did not receive its fixed client state.");
            }
        }

        if (clients.Count < 2)
        {
            return;
        }

        var first = clients[0];
        var second = clients[1];
        var mismatchedToken = CreateDatagram(first.SessionId, second.UdpToken, first.NextSequence++, second.State);
        var mismatchedSession = CreateDatagram(second.SessionId, first.UdpToken, second.NextSequence++, first.State);
        await first.Udp.SendAsync(mismatchedToken, new IPEndPoint(IPAddress.Loopback, udpPort));
        await second.Udp.SendAsync(mismatchedSession, new IPEndPoint(IPAddress.Loopback, udpPort));
        await Task.Delay(TimeSpan.FromMilliseconds(100));

        foreach (var client in clients)
        {
            if (!factory.TryGet(client.Slot, out var controller) || controller.LastAppliedState != client.State)
            {
                throw new InvalidOperationException("A session credential mismatch changed another session's target.");
            }
        }
    }

    private static byte[] CreateDatagram(ulong sessionId, byte[] token, uint sequence, GamepadState state)
    {
        var datagram = new byte[60];
        Encoding.ASCII.GetBytes("PULG", datagram);
        datagram[4] = 1;
        datagram[5] = 1;
        BinaryPrimitives.WriteUInt64LittleEndian(datagram.AsSpan(8), sessionId);
        token.CopyTo(datagram, 16);
        BinaryPrimitives.WriteUInt32LittleEndian(datagram.AsSpan(32), sequence);
        BinaryPrimitives.WriteUInt64LittleEndian(datagram.AsSpan(36), (ulong)(Stopwatch.GetTimestamp() * 1_000_000L / Stopwatch.Frequency));
        BinaryPrimitives.WriteUInt32LittleEndian(datagram.AsSpan(44), state.Buttons);
        BinaryPrimitives.WriteInt16LittleEndian(datagram.AsSpan(48), state.LeftX);
        BinaryPrimitives.WriteInt16LittleEndian(datagram.AsSpan(50), state.LeftY);
        BinaryPrimitives.WriteInt16LittleEndian(datagram.AsSpan(52), state.RightX);
        BinaryPrimitives.WriteInt16LittleEndian(datagram.AsSpan(54), state.RightY);
        BinaryPrimitives.WriteUInt16LittleEndian(datagram.AsSpan(56), state.LeftTrigger);
        BinaryPrimitives.WriteUInt16LittleEndian(datagram.AsSpan(58), state.RightTrigger);
        return datagram;
    }

    private static int FindAvailablePort()
    {
        using var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        return ((IPEndPoint)listener.LocalEndpoint).Port;
    }

    private sealed class RecordingControllerFactory : VirtualControllerFactory
    {
        private readonly Dictionary<int, RecordingController> _controllers = [];

        public VirtualController Create(ControllerKind kind)
        {
            if (kind != ControllerKind.X360)
            {
                throw new InvalidOperationException("P2 loopback load only supports X360 slots.");
            }

            var controller = new RecordingController();
            _controllers.Add(_controllers.Count + 1, controller);
            return controller;
        }

        public bool TryGet(int slot, out RecordingController controller) => _controllers.TryGetValue(slot, out controller!);
    }

    private sealed class RecordingController : VirtualController
    {
        public ControllerKind Kind => ControllerKind.X360;

        public GamepadState LastAppliedState { get; private set; } = GamepadState.Neutral;

        public void Connect() { }

        public void Apply(GamepadState state) => LastAppliedState = state;

        public void Neutralize() => LastAppliedState = GamepadState.Neutral;

        public void Disconnect() { }
    }

    private sealed class LoadClient : IAsyncDisposable
    {
        private LoadClient(ClientWebSocket socket, UdpClient udp, int slot, ulong sessionId, byte[] udpToken, GamepadState state)
        {
            Socket = socket;
            Udp = udp;
            Slot = slot;
            SessionId = sessionId;
            UdpToken = udpToken;
            State = state;
        }

        public ClientWebSocket Socket { get; }

        public UdpClient Udp { get; }

        public int Slot { get; }

        public ulong SessionId { get; }

        public byte[] UdpToken { get; }

        public GamepadState State { get; }

        public uint NextSequence { get; set; }

        public byte[]? PreviousPacket { get; set; }

        public bool IsAccepted { get; private init; }

        public string? ErrorCode { get; private init; }

        public static async Task<LoadClient> ConnectAsync(int tcpPort, int clientNumber, uint sequenceStart)
        {
            var socket = new ClientWebSocket();
            await socket.ConnectAsync(new Uri($"ws://127.0.0.1:{tcpPort}/control"), CancellationToken.None);
            await SendJsonAsync(socket, new
            {
                v = 1,
                type = "hello",
                clientId = $"00000000-0000-0000-0000-{clientNumber:D12}",
                clientName = $"Load Client {clientNumber}",
                appVersion = "1",
                pin = Pin,
                capabilities = new[] { "udp_input_v1" },
            });
            using var response = await ReceiveJsonAsync(socket);
            if (response.RootElement.GetProperty("type").GetString() == "error")
            {
                await socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, "Load test rejection acknowledged.", CancellationToken.None);
                return new LoadClient(socket, new UdpClient(), 0, 0, [], GamepadState.Neutral)
                {
                    ErrorCode = response.RootElement.GetProperty("code").GetString(),
                };
            }

            var slot = response.RootElement.GetProperty("slot").GetInt32();
            var sessionId = Convert.ToUInt64(response.RootElement.GetProperty("sessionId").GetString(), 16);
            var token = WebEncoders.Base64UrlDecode(response.RootElement.GetProperty("udpToken").GetString()!);
            var state = new GamepadState((uint)(1 << (clientNumber - 1)), (short)(clientNumber * 5000), (short)(-clientNumber * 4000), (short)(clientNumber * 3000), (short)(-clientNumber * 2000), (ushort)(clientNumber * 10000), (ushort)(ushort.MaxValue - clientNumber));
            return new LoadClient(socket, new UdpClient(), slot, sessionId, token, state)
            {
                IsAccepted = true,
                NextSequence = sequenceStart,
            };
        }

        public ValueTask DisposeAsync()
        {
            Udp.Dispose();
            Socket.Dispose();
            return ValueTask.CompletedTask;
        }

        private static async Task SendJsonAsync(ClientWebSocket socket, object value)
        {
            var bytes = JsonSerializer.SerializeToUtf8Bytes(value);
            await socket.SendAsync(bytes, WebSocketMessageType.Text, true, CancellationToken.None);
        }

        private static async Task<JsonDocument> ReceiveJsonAsync(ClientWebSocket socket)
        {
            var buffer = new byte[4096];
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            var result = await socket.ReceiveAsync(buffer, timeout.Token);
            return JsonDocument.Parse(buffer.AsMemory(0, result.Count));
        }
    }
}
