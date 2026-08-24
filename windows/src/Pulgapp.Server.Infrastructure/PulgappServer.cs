using System.Buffers;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Hosting;
using Pulgapp.Server.Core;
using Pulgapp.Server.Protocol;

namespace Pulgapp.Server.Infrastructure;

public sealed record PulgappServerOptions(
    int TcpPort = 26760,
    int UdpPort = 26761,
    string? Pin = null,
    string ServerName = "Pulgapp Server",
    Guid? ServerId = null);

public sealed record PulgappServerStatus(
    bool IsRunning,
    string Pin,
    int TcpPort,
    int UdpPort,
    IReadOnlyList<PulgappSlotStatus> Slots);

public sealed record PulgappSlotStatus(
    int Slot,
    string ControllerType,
    LobbySlotState State,
    string ClientName,
    string SourceIpAddress,
    string ConnectionState,
    TimeSpan? LastInputAge,
    double PacketRate,
    string Rtt,
    string XInputUserIndex)
{
    public bool CanKick => State != LobbySlotState.Free;
}

public sealed class PulgappServer : IAsyncDisposable
{
    private const int MaximumControlMessageBytes = 4096;
    private readonly PulgappServerOptions _options;
    private readonly SessionCoordinator _coordinator;
    private string _pin;
    private readonly string _serverId;
    private readonly SemaphoreSlim _stateLock = new(1, 1);
    private readonly SemaphoreSlim _sendLock = new(1, 1);
    private WebApplication? _application;
    private UdpClient? _udpClient;
    private CancellationTokenSource? _stopping;
    private Task? _udpTask;
    private Task? _watchdogTask;
    private bool _acceptingConnections;
    private readonly Dictionary<ulong, ControlConnection> _connections = [];

    public PulgappServer(PulgappServerOptions options, SessionCoordinator coordinator)
    {
        _options = options ?? throw new ArgumentNullException(nameof(options));
        _coordinator = coordinator ?? throw new ArgumentNullException(nameof(coordinator));
        if (options.TcpPort is < 0 or > 65535 || options.UdpPort is < 0 or > 65535)
        {
            throw new ArgumentOutOfRangeException(nameof(options));
        }

        _pin = options.Pin ?? RandomNumberGenerator.GetInt32(1_000_000).ToString("D6", System.Globalization.CultureInfo.InvariantCulture);
        if (_pin.Length != 6 || _pin.Any(character => character is < '0' or > '9'))
        {
            throw new ArgumentException("The PIN must contain exactly six decimal digits.", nameof(options));
        }

        _serverId = (options.ServerId ?? Guid.NewGuid()).ToString("D");
    }

    public int UdpPort => ((IPEndPoint?)_udpClient?.Client.LocalEndPoint)?.Port ?? _options.UdpPort;

    public int TcpPort => _options.TcpPort;

    public async Task StartAsync(CancellationToken cancellationToken = default)
    {
        if (_application is not null)
        {
            throw new InvalidOperationException("The server is already started.");
        }

        _stopping = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        _udpClient = new UdpClient(new IPEndPoint(IPAddress.Any, _options.UdpPort));
        var builder = WebApplication.CreateSlimBuilder();
        builder.WebHost.UseKestrel().UseUrls($"http://0.0.0.0:{_options.TcpPort}");
        _application = builder.Build();
        _application.UseWebSockets();
        _application.MapGet("/health", () => Results.Json(new { status = "ok" }));
        _application.Map("/control", HandleControlAsync);
        await _application.StartAsync(_stopping.Token);
        _acceptingConnections = true;
        _udpTask = ReceiveUdpAsync(_stopping.Token);
        _watchdogTask = WatchInputTimeoutAsync(_stopping.Token);
    }

    public async Task<PulgappServerStatus> GetStatusAsync(CancellationToken cancellationToken = default)
    {
        await _stateLock.WaitAsync(cancellationToken);
        try
        {
            var now = DateTimeOffset.UtcNow;
            return new PulgappServerStatus(
                _application is not null,
                _pin,
                TcpPort,
                UdpPort,
                _coordinator.GetSlotStatuses()
                    .OrderBy(slot => slot.Slot)
                    .Select(slot => CreateSlotStatus(slot, now))
                    .ToArray());
        }
        finally
        {
            _stateLock.Release();
        }
    }

    public async Task<string> RegeneratePinAsync(CancellationToken cancellationToken = default)
    {
        await _stateLock.WaitAsync(cancellationToken);
        try
        {
            _pin = RandomNumberGenerator.GetInt32(1_000_000).ToString("D6", System.Globalization.CultureInfo.InvariantCulture);
            return _pin;
        }
        finally
        {
            _stateLock.Release();
        }
    }

    public async Task<bool> KickAsync(int slot, CancellationToken cancellationToken = default)
    {
        await _stateLock.WaitAsync(cancellationToken);
        try
        {
            var connection = _connections.Values.SingleOrDefault(connection => connection.Slot == slot);
            if (connection is null)
            {
                return _coordinator.ReleaseSlot(slot);
            }

            _coordinator.Release(connection.SessionId);
            _connections.Remove(connection.SessionId);
            try
            {
                if (connection.Socket.State == WebSocketState.Open)
                {
                    await connection.Socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, "Kicked by server.", cancellationToken);
                }
            }
            catch (WebSocketException) { }
            catch (ObjectDisposedException) { }
            catch (OperationCanceledException) { }

            return true;
        }
        finally
        {
            _stateLock.Release();
        }
    }

    public async Task StopAsync(CancellationToken cancellationToken = default)
    {
        var stopping = _stopping;
        if (stopping is null)
        {
            return;
        }

        _acceptingConnections = false;
        await _stateLock.WaitAsync(cancellationToken);
        try
        {
            _coordinator.Shutdown();
            foreach (var connection in _connections.Values.ToArray())
            {
                try
                {
                    if (connection.Socket.State == WebSocketState.Open)
                    {
                        await connection.Socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, "Server shutting down.", cancellationToken);
                    }
                }
                catch (WebSocketException) { }
                catch (ObjectDisposedException) { }
                catch (OperationCanceledException) { }
            }
            _connections.Clear();
        }
        finally
        {
            _stateLock.Release();
        }

        stopping.Cancel();
        _udpClient?.Dispose();
        if (_application is not null)
        {
            await _application.StopAsync(cancellationToken);
            await _application.DisposeAsync();
            _application = null;
        }

        await AwaitBackgroundTaskAsync(_udpTask);
        await AwaitBackgroundTaskAsync(_watchdogTask);
        _udpTask = null;
        _watchdogTask = null;
        _udpClient = null;
        stopping.Dispose();
        _stopping = null;
    }

    public async ValueTask DisposeAsync()
    {
        await StopAsync();
        _stateLock.Dispose();
        _sendLock.Dispose();
    }

    private async Task HandleControlAsync(HttpContext context)
    {
        if (!context.WebSockets.IsWebSocketRequest || context.Connection.RemoteIpAddress is not { } remoteAddress ||
            !remoteAddress.IsIPv4MappedToIPv6 && remoteAddress.AddressFamily != AddressFamily.InterNetwork || !_acceptingConnections)
        {
            context.Response.StatusCode = _acceptingConnections ? StatusCodes.Status400BadRequest : StatusCodes.Status503ServiceUnavailable;
            return;
        }

        using var socket = await context.WebSockets.AcceptWebSocketAsync();
        ControlConnection? connection = null;
        await _stateLock.WaitAsync(context.RequestAborted);
        try
        {
            if (!_acceptingConnections)
            {
                await SendAndCloseAsync(socket, new ErrorMessage(1, "error", "server_shutting_down", "The server is shutting down.", true), (WebSocketCloseStatus)1013, context.RequestAborted);
                return;
            }

            var hello = await ReceiveJsonAsync(socket, context.RequestAborted);
            if (!TryParseHello(hello, out var parsedHello, out var error))
            {
                await SendAndCloseAsync(socket, error!, WebSocketCloseStatus.ProtocolError, context.RequestAborted);
                return;
            }

            LobbyStartResult start;
            if (parsedHello.ResumeToken is not null)
            {
                try
                {
                    start = _coordinator.Resume(parsedHello.ClientId, WebEncoders.Base64UrlDecode(parsedHello.ResumeToken));
                }
                catch (FormatException)
                {
                    start = new LobbyStartResult(LobbyStartStatus.ResumeRejected);
                }
            }
            else
            {
                if (!CryptographicOperations.FixedTimeEquals(Encoding.ASCII.GetBytes(parsedHello.Pin!), Encoding.ASCII.GetBytes(_pin)))
                {
                    await SendAndCloseAsync(socket, new ErrorMessage(1, "error", "invalid_pin", "The PIN is invalid.", true), WebSocketCloseStatus.PolicyViolation, context.RequestAborted);
                    return;
                }

                start = _coordinator.StartNew(parsedHello.ClientId);
            }

            if (!start.Succeeded)
            {
                var (code, message, closeStatus) = start.Status switch
                {
                    LobbyStartStatus.ServerFull => ("server_full", "All X360 slots are occupied.", (WebSocketCloseStatus)1013),
                    LobbyStartStatus.ClientAlreadyConnected => ("client_already_connected", "This client is already connected or reserved.", WebSocketCloseStatus.PolicyViolation),
                    LobbyStartStatus.ResumeRejected => ("resume_rejected", "The resume token is invalid or expired.", WebSocketCloseStatus.PolicyViolation),
                    _ => ("controller_create_failed", "The virtual controller could not be created.", WebSocketCloseStatus.InternalServerError),
                };
                await SendAndCloseAsync(socket, new ErrorMessage(1, "error", code, message, true), closeStatus, context.RequestAborted);
                return;
            }

            var credentials = start.Credentials!;
            connection = new ControlConnection(socket, remoteAddress.MapToIPv4(), credentials.SessionId, start.Slot!.Value, parsedHello.ClientName, DateTimeOffset.UtcNow);
            _connections.Add(credentials.SessionId, connection);
            await SendJsonAsync(socket, new WelcomeMessage(1, "welcome", _serverId, _options.ServerName, credentials.SessionId.ToString("x16"), WebEncoders.Base64UrlEncode(credentials.UdpToken), UdpPort, connection.Slot, "x360", parsedHello.ResumeToken is not null, WebEncoders.Base64UrlEncode(credentials.ResumeToken), 250, 15000), context.RequestAborted);
        }
        finally
        {
            _stateLock.Release();
        }

        try
        {
            var release = await ProcessControlMessagesAsync(socket, context.RequestAborted);
            if (release)
            {
                await _stateLock.WaitAsync();
                try { _coordinator.Release(connection.SessionId); }
                finally { _stateLock.Release(); }
            }
        }
        finally
        {
            await _stateLock.WaitAsync();
            try
            {
                if (connection is not null && _connections.Remove(connection.SessionId))
                {
                    _coordinator.HandleControlLoss(connection.SessionId);
                }
            }
            finally
            {
                _stateLock.Release();
            }
        }
    }

    private async Task<bool> ProcessControlMessagesAsync(WebSocket socket, CancellationToken cancellationToken)
    {
        while (socket.State == WebSocketState.Open)
        {
            JsonDocument document;
            try { document = await ReceiveJsonAsync(socket, cancellationToken); }
            catch (WebSocketException) { return false; }
            catch (InvalidDataException)
            {
                await SendAndCloseAsync(socket, new ErrorMessage(1, "error", "malformed_message", "The control message is malformed.", true), WebSocketCloseStatus.ProtocolError, cancellationToken);
                return false;
            }

            using (document)
            {
                var root = document.RootElement;
                if (!HasVersionAndType(root, out var type))
                {
                    await SendAndCloseAsync(socket, new ErrorMessage(1, "error", "protocol_mismatch", "Unsupported protocol version.", true), WebSocketCloseStatus.ProtocolError, cancellationToken);
                    return false;
                }

                if (type == "ping" && root.TryGetProperty("id", out var id) && id.TryGetUInt32(out var pingId) &&
                    root.TryGetProperty("clientTimeUs", out var clientTime) && clientTime.ValueKind == JsonValueKind.String)
                {
                    var received = MonotonicMicroseconds();
                    await SendJsonAsync(socket, new PongMessage(1, "pong", pingId, clientTime.GetString()!, received, MonotonicMicroseconds()), cancellationToken);
                }
                else if (type is "leave" or "suspend")
                {
                    await socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, type, cancellationToken);
                    return type == "leave";
                }
                else
                {
                    await SendAndCloseAsync(socket, new ErrorMessage(1, "error", "malformed_message", "The control message is malformed.", true), WebSocketCloseStatus.ProtocolError, cancellationToken);
                    return false;
                }
            }
        }

        return false;
    }

    private async Task ReceiveUdpAsync(CancellationToken cancellationToken)
    {
        try
        {
            while (!cancellationToken.IsCancellationRequested && _udpClient is not null)
            {
                var received = await _udpClient.ReceiveAsync(cancellationToken);
                await _stateLock.WaitAsync(cancellationToken);
                try
                {
                    if (!UdpInputDecoder.TryDecode(received.Buffer, out var snapshot) || snapshot is null ||
                        !_connections.TryGetValue(snapshot.SessionId, out var connection) ||
                        !received.RemoteEndPoint.Address.Equals(connection.Address))
                    {
                        continue;
                    }

                    var restored = _coordinator.TryGetSlotStatus(snapshot.SessionId, out var status) && status!.State == LobbySlotState.InputTimedOut;
                    if (!_coordinator.TryAccept(snapshot))
                    {
                        continue;
                    }

                    connection.LastInputAt = DateTimeOffset.UtcNow;
                    connection.AcceptedPacketCount++;

                    if (!connection.InputReadySent)
                    {
                        connection.InputReadySent = true;
                        await SendJsonAsync(connection.Socket, new InputReadyMessage(1, "input_ready", snapshot.Sequence), cancellationToken);
                        await SendJsonAsync(connection.Socket, new InputStatusMessage(1, "input_status", "ready", snapshot.Sequence), cancellationToken);
                    }
                    else if (restored)
                    {
                        await SendJsonAsync(connection.Socket, new InputStatusMessage(1, "input_status", "restored", snapshot.Sequence), cancellationToken);
                    }
                }
                finally
                {
                    _stateLock.Release();
                }
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { }
        catch (ObjectDisposedException) when (cancellationToken.IsCancellationRequested) { }
    }

    private async Task WatchInputTimeoutAsync(CancellationToken cancellationToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromMilliseconds(25));
        try
        {
            while (await timer.WaitForNextTickAsync(cancellationToken))
            {
                await _stateLock.WaitAsync(cancellationToken);
                try
                {
                    var activeSessions = _connections.Keys.ToArray();
                    if (_coordinator.CheckInputTimeout())
                    {
                        foreach (var sessionId in activeSessions)
                        {
                            if (_connections.TryGetValue(sessionId, out var connection) &&
                                _coordinator.TryGetSlotStatus(sessionId, out var status) && status!.State == LobbySlotState.InputTimedOut)
                            {
                                await SendJsonAsync(connection.Socket, new InputStatusMessage(1, "input_status", "timed_out", status.LastSequence), cancellationToken);
                            }
                        }
                    }
                    _coordinator.ExpireLeases();
                }
                finally { _stateLock.Release(); }
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { }
    }

    private async Task SendJsonAsync(WebSocket? socket, ControlMessage message, CancellationToken cancellationToken)
    {
        if (socket is null || socket.State != WebSocketState.Open)
        {
            return;
        }

        var bytes = JsonSerializer.SerializeToUtf8Bytes(message, message.GetType());
        await _sendLock.WaitAsync(cancellationToken);
        try { await socket.SendAsync(bytes, WebSocketMessageType.Text, true, cancellationToken); }
        finally { _sendLock.Release(); }
    }

    private async Task SendAndCloseAsync(WebSocket socket, ErrorMessage error, WebSocketCloseStatus closeStatus, CancellationToken cancellationToken)
    {
        await SendJsonAsync(socket, error, cancellationToken);
        await socket.CloseAsync(closeStatus, error.Code, cancellationToken);
    }

    private static async Task<JsonDocument> ReceiveJsonAsync(WebSocket socket, CancellationToken cancellationToken)
    {
        var buffer = ArrayPool<byte>.Shared.Rent(MaximumControlMessageBytes + 1);
        try
        {
            var count = 0;
            ValueWebSocketReceiveResult result;
            do
            {
                result = await socket.ReceiveAsync(buffer.AsMemory(count, buffer.Length - count), cancellationToken);
                if (result.MessageType != WebSocketMessageType.Text || count + result.Count > MaximumControlMessageBytes)
                {
                    throw new InvalidDataException();
                }

                count += result.Count;
            } while (!result.EndOfMessage);
            return JsonDocument.Parse(buffer.AsMemory(0, count));
        }
        catch (JsonException exception) { throw new InvalidDataException("Invalid JSON.", exception); }
        finally { ArrayPool<byte>.Shared.Return(buffer); }
    }

    private static bool TryParseHello(JsonDocument document, out (string? Pin, string ClientId, string ClientName, string? ResumeToken) hello, out ErrorMessage? error)
    {
        hello = default;
        error = null;
        var root = document.RootElement;
        if (!HasVersionAndType(root, out var type) || type != "hello" ||
            !root.TryGetProperty("clientId", out var clientId) || clientId.ValueKind != JsonValueKind.String || !Guid.TryParse(clientId.GetString(), out _) ||
            !root.TryGetProperty("clientName", out var clientName) || clientName.ValueKind != JsonValueKind.String || string.IsNullOrWhiteSpace(clientName.GetString()) || clientName.GetString()!.EnumerateRunes().Count() > 64 ||
            !root.TryGetProperty("appVersion", out var appVersion) || appVersion.ValueKind != JsonValueKind.String || string.IsNullOrWhiteSpace(appVersion.GetString()) || appVersion.GetString()!.Length > 32 ||
            !root.TryGetProperty("capabilities", out var capabilities) || capabilities.ValueKind != JsonValueKind.Array ||
            !capabilities.EnumerateArray().Any(value => value.ValueKind == JsonValueKind.String && value.GetString() == "udp_input_v1"))
        {
            error = new ErrorMessage(1, "error", "malformed_message", "The hello message is malformed.", true);
            return false;
        }

        var hasPin = root.TryGetProperty("pin", out var pin);
        var hasResumeToken = root.TryGetProperty("resumeToken", out var resumeToken);
        if (hasPin == hasResumeToken ||
            hasPin && (pin.ValueKind != JsonValueKind.String || pin.GetString()!.Length != 6 || pin.GetString()!.Any(character => character is < '0' or > '9')) ||
            hasResumeToken && resumeToken.ValueKind != JsonValueKind.String)
        {
            error = new ErrorMessage(1, "error", "malformed_message", "The hello message is malformed.", true);
            return false;
        }

        hello = (hasPin ? pin.GetString() : null, clientId.GetString()!, clientName.GetString()!, hasResumeToken ? resumeToken.GetString() : null);
        return true;
    }

    private sealed class ControlConnection(WebSocket socket, IPAddress address, ulong sessionId, int slot, string clientName, DateTimeOffset packetRateStartedAt)
    {
        public WebSocket Socket { get; } = socket;
        public IPAddress Address { get; } = address;
        public ulong SessionId { get; } = sessionId;
        public int Slot { get; } = slot;
        public string ClientName { get; } = clientName;
        public DateTimeOffset PacketRateStartedAt { get; } = packetRateStartedAt;
        public bool InputReadySent { get; set; }
        public DateTimeOffset? LastInputAt { get; set; }
        public long AcceptedPacketCount { get; set; }
    }

    private static bool HasVersionAndType(JsonElement root, out string? type)
    {
        type = null;
        return root.ValueKind == JsonValueKind.Object && root.TryGetProperty("v", out var version) && version.ValueKind == JsonValueKind.Number && version.TryGetInt32(out var value) && value == 1 &&
            root.TryGetProperty("type", out var typeElement) && typeElement.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(type = typeElement.GetString());
    }

    private static string MonotonicMicroseconds() => ((Stopwatch.GetTimestamp() * 1_000_000L) / Stopwatch.Frequency).ToString(System.Globalization.CultureInfo.InvariantCulture);

    private PulgappSlotStatus CreateSlotStatus(LobbySlotStatus slot, DateTimeOffset now)
    {
        var connection = _connections.Values.SingleOrDefault(connection => connection.Slot == slot.Slot);
        var elapsed = connection is null ? TimeSpan.Zero : now - connection.PacketRateStartedAt;
        var packetRate = elapsed.TotalSeconds > 0 ? connection!.AcceptedPacketCount / elapsed.TotalSeconds : 0;
        var connectionState = _application is null
            ? "Stopped"
            : slot.State switch
            {
                LobbySlotState.Free => "Available",
                LobbySlotState.Reserved => "Reserved (lease)",
                LobbySlotState.InputTimedOut => "Input timed out",
                _ when connection?.LastInputAt is null => "Control connected",
                _ => "Input ready",
            };
        return new PulgappSlotStatus(
            slot.Slot,
            "Xbox 360",
            slot.State,
            connection?.ClientName ?? (slot.State == LobbySlotState.Reserved ? "Reserved client" : "No client connected"),
            connection?.Address.ToString() ?? "-",
            connectionState,
            connection?.LastInputAt is { } inputAt ? now - inputAt : null,
            packetRate,
            "Unavailable",
            "Not reported");
    }

    private static async Task AwaitBackgroundTaskAsync(Task? task)
    {
        if (task is null)
        {
            return;
        }

        try { await task; }
        catch (OperationCanceledException) { }
    }
}
