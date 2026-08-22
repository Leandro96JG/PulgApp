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
    string? ClientName,
    string ConnectionState,
    TimeSpan? LastInputAge,
    double PacketRate,
    string Rtt);

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
    private WebSocket? _controlSocket;
    private IPAddress? _controlAddress;
    private bool _inputReadySent;
    private bool _acceptingConnections;
    private string? _clientName;
    private DateTimeOffset? _lastInputAt;
    private DateTimeOffset? _packetRateStartedAt;
    private long _acceptedPacketCount;

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
            var elapsed = _packetRateStartedAt is { } started ? now - started : TimeSpan.Zero;
            var packetRate = elapsed.TotalSeconds > 0 ? _acceptedPacketCount / elapsed.TotalSeconds : 0;
            var connectionState = _application is null
                ? "Stopped"
                : !_coordinator.IsActive
                    ? "Waiting for client"
                    : _coordinator.IsInputTimedOut
                        ? "Input timed out"
                        : _lastInputAt is null
                            ? "Control connected"
                            : "Input ready";
            return new PulgappServerStatus(
                _application is not null,
                _pin,
                TcpPort,
                UdpPort,
                _clientName,
                connectionState,
                _lastInputAt is { } inputAt ? now - inputAt : null,
                packetRate,
                "Unavailable");
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

    public async Task KickAsync(CancellationToken cancellationToken = default)
    {
        await _stateLock.WaitAsync(cancellationToken);
        try
        {
            _coordinator.Leave();
            _clientName = null;
            _lastInputAt = null;
            _packetRateStartedAt = null;
            _acceptedPacketCount = 0;
            if (_controlSocket is { State: WebSocketState.Open } socket)
            {
                try
                {
                    await socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, "Kicked by server.", cancellationToken);
                }
                catch (WebSocketException) { }
                catch (ObjectDisposedException) { }
                catch (OperationCanceledException) { }
            }
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
            _clientName = null;
            _lastInputAt = null;
            _packetRateStartedAt = null;
            _acceptedPacketCount = 0;
            if (_controlSocket is { State: WebSocketState.Open } socket)
            {
                try
                {
                    await socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, "Server shutting down.", cancellationToken);
                }
                catch (WebSocketException) { }
                catch (ObjectDisposedException) { }
                catch (OperationCanceledException) { }
            }
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
        await _stateLock.WaitAsync(context.RequestAborted);
        try
        {
            if (!_acceptingConnections)
            {
                await SendAndCloseAsync(socket, new ErrorMessage(1, "error", "server_shutting_down", "The server is shutting down.", true), (WebSocketCloseStatus)1013, context.RequestAborted);
                return;
            }

            if (_controlSocket is not null || _coordinator.IsActive)
            {
                await SendAndCloseAsync(socket, new ErrorMessage(1, "error", "client_already_connected", "A client is already connected.", true), WebSocketCloseStatus.PolicyViolation, context.RequestAborted);
                return;
            }

            var hello = await ReceiveJsonAsync(socket, context.RequestAborted);
            if (!TryParseHello(hello, out var parsedHello, out var error))
            {
                await SendAndCloseAsync(socket, error!, WebSocketCloseStatus.ProtocolError, context.RequestAborted);
                return;
            }

            if (!CryptographicOperations.FixedTimeEquals(Encoding.ASCII.GetBytes(parsedHello.Pin!), Encoding.ASCII.GetBytes(_pin)))
            {
                await SendAndCloseAsync(socket, new ErrorMessage(1, "error", "invalid_pin", "The PIN is invalid.", true), WebSocketCloseStatus.PolicyViolation, context.RequestAborted);
                return;
            }

            var token = RandomNumberGenerator.GetBytes(16);
            ulong sessionId;
            do { sessionId = BitConverter.ToUInt64(RandomNumberGenerator.GetBytes(8)); } while (sessionId == 0);
            try
            {
                _coordinator.Start(sessionId, token);
            }
            catch (Exception)
            {
                await SendAndCloseAsync(socket, new ErrorMessage(1, "error", "controller_create_failed", "The virtual controller could not be created.", true), WebSocketCloseStatus.InternalServerError, context.RequestAborted);
                return;
            }

            _controlSocket = socket;
            _controlAddress = remoteAddress.MapToIPv4();
            _inputReadySent = false;
            _clientName = parsedHello.ClientName;
            _lastInputAt = null;
            _packetRateStartedAt = DateTimeOffset.UtcNow;
            _acceptedPacketCount = 0;
            await SendJsonAsync(socket, new WelcomeMessage(1, "welcome", _serverId, _options.ServerName, sessionId.ToString("x16"), WebEncoders.Base64UrlEncode(token), UdpPort, 1, "x360", false, WebEncoders.Base64UrlEncode(RandomNumberGenerator.GetBytes(32)), 250, 15000), context.RequestAborted);
        }
        finally
        {
            _stateLock.Release();
        }

        try
        {
            await ProcessControlMessagesAsync(socket, context.RequestAborted);
        }
        finally
        {
            await _stateLock.WaitAsync();
            try
            {
                if (ReferenceEquals(_controlSocket, socket))
                {
                    _controlSocket = null;
                    _controlAddress = null;
                    _clientName = null;
                    _lastInputAt = null;
                    _packetRateStartedAt = null;
                    _acceptedPacketCount = 0;
                    _coordinator.HandleControlLoss();
                    _coordinator.Leave();
                }
            }
            finally
            {
                _stateLock.Release();
            }
        }
    }

    private async Task ProcessControlMessagesAsync(WebSocket socket, CancellationToken cancellationToken)
    {
        while (socket.State == WebSocketState.Open)
        {
            JsonDocument document;
            try { document = await ReceiveJsonAsync(socket, cancellationToken); }
            catch (WebSocketException) { return; }
            catch (InvalidDataException)
            {
                await SendAndCloseAsync(socket, new ErrorMessage(1, "error", "malformed_message", "The control message is malformed.", true), WebSocketCloseStatus.ProtocolError, cancellationToken);
                return;
            }

            using (document)
            {
                var root = document.RootElement;
                if (!HasVersionAndType(root, out var type))
                {
                    await SendAndCloseAsync(socket, new ErrorMessage(1, "error", "protocol_mismatch", "Unsupported protocol version.", true), WebSocketCloseStatus.ProtocolError, cancellationToken);
                    return;
                }

                if (type == "ping" && root.TryGetProperty("id", out var id) && id.TryGetUInt32(out var pingId) &&
                    root.TryGetProperty("clientTimeUs", out var clientTime) && clientTime.ValueKind == JsonValueKind.String)
                {
                    var received = MonotonicMicroseconds();
                    await SendJsonAsync(socket, new PongMessage(1, "pong", pingId, clientTime.GetString()!, received, MonotonicMicroseconds()), cancellationToken);
                }
                else if (type is "leave" or "suspend")
                {
                    await socket.CloseAsync(WebSocketCloseStatus.NormalClosure, type, cancellationToken);
                    return;
                }
                else
                {
                    await SendAndCloseAsync(socket, new ErrorMessage(1, "error", "malformed_message", "The control message is malformed.", true), WebSocketCloseStatus.ProtocolError, cancellationToken);
                    return;
                }
            }
        }
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
                    if (_controlAddress is null || !received.RemoteEndPoint.Address.Equals(_controlAddress) ||
                        !UdpInputDecoder.TryDecode(received.Buffer, out var snapshot) || snapshot is null)
                    {
                        continue;
                    }

                    var restored = _coordinator.IsInputTimedOut;
                    if (!_coordinator.TryAccept(snapshot))
                    {
                        continue;
                    }

                    _lastInputAt = DateTimeOffset.UtcNow;
                    _acceptedPacketCount++;

                    if (!_inputReadySent)
                    {
                        _inputReadySent = true;
                        await SendJsonAsync(_controlSocket, new InputReadyMessage(1, "input_ready", snapshot.Sequence), cancellationToken);
                        await SendJsonAsync(_controlSocket, new InputStatusMessage(1, "input_status", "ready", snapshot.Sequence), cancellationToken);
                    }
                    else if (restored)
                    {
                        await SendJsonAsync(_controlSocket, new InputStatusMessage(1, "input_status", "restored", snapshot.Sequence), cancellationToken);
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
                    if (_coordinator.CheckInputTimeout())
                    {
                        await SendJsonAsync(_controlSocket, new InputStatusMessage(1, "input_status", "timed_out", _coordinator.LastSequence), cancellationToken);
                    }
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

    private static bool TryParseHello(JsonDocument document, out (string Pin, string ClientId, string ClientName) hello, out ErrorMessage? error)
    {
        hello = default;
        error = null;
        var root = document.RootElement;
        if (!HasVersionAndType(root, out var type) || type != "hello" ||
            !root.TryGetProperty("clientId", out var clientId) || clientId.ValueKind != JsonValueKind.String || !Guid.TryParse(clientId.GetString(), out _) ||
            !root.TryGetProperty("clientName", out var clientName) || clientName.ValueKind != JsonValueKind.String || string.IsNullOrWhiteSpace(clientName.GetString()) || clientName.GetString()!.EnumerateRunes().Count() > 64 ||
            !root.TryGetProperty("appVersion", out var appVersion) || appVersion.ValueKind != JsonValueKind.String || string.IsNullOrWhiteSpace(appVersion.GetString()) || appVersion.GetString()!.Length > 32 ||
            !root.TryGetProperty("capabilities", out var capabilities) || capabilities.ValueKind != JsonValueKind.Array ||
            !capabilities.EnumerateArray().Any(value => value.ValueKind == JsonValueKind.String && value.GetString() == "udp_input_v1") ||
            !root.TryGetProperty("pin", out var pin) || pin.ValueKind != JsonValueKind.String ||
            root.TryGetProperty("resumeToken", out _))
        {
            error = new ErrorMessage(1, "error", "malformed_message", "The hello message is malformed.", true);
            return false;
        }

        var pinValue = pin.GetString()!;
        if (pinValue.Length != 6 || pinValue.Any(character => character is < '0' or > '9'))
        {
            error = new ErrorMessage(1, "error", "malformed_message", "The hello message is malformed.", true);
            return false;
        }

        hello = (pinValue, clientId.GetString()!, clientName.GetString()!);
        return true;
    }

    private static bool HasVersionAndType(JsonElement root, out string? type)
    {
        type = null;
        return root.ValueKind == JsonValueKind.Object && root.TryGetProperty("v", out var version) && version.ValueKind == JsonValueKind.Number && version.TryGetInt32(out var value) && value == 1 &&
            root.TryGetProperty("type", out var typeElement) && typeElement.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(type = typeElement.GetString());
    }

    private static string MonotonicMicroseconds() => ((Stopwatch.GetTimestamp() * 1_000_000L) / Stopwatch.Frequency).ToString(System.Globalization.CultureInfo.InvariantCulture);

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
