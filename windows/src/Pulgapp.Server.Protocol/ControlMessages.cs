using System.Text.Json.Serialization;

namespace Pulgapp.Server.Protocol;

public abstract record ControlMessage(
    [property: JsonPropertyName("v")] int Version,
    [property: JsonPropertyName("type")] string Type);

public sealed record HelloMessage(
    int Version,
    string Type,
    [property: JsonPropertyName("clientId")] string ClientId,
    [property: JsonPropertyName("clientName")] string ClientName,
    [property: JsonPropertyName("appVersion")] string AppVersion,
    [property: JsonPropertyName("capabilities")] IReadOnlyList<string> Capabilities,
    [property: JsonPropertyName("pin")] string? Pin = null,
    [property: JsonPropertyName("resumeToken")] string? ResumeToken = null)
    : ControlMessage(Version, Type);

public sealed record WelcomeMessage(
    int Version,
    string Type,
    [property: JsonPropertyName("serverId")] string ServerId,
    [property: JsonPropertyName("serverName")] string ServerName,
    [property: JsonPropertyName("sessionId")] string SessionId,
    [property: JsonPropertyName("udpToken")] string UdpToken,
    [property: JsonPropertyName("udpPort")] int UdpPort,
    [property: JsonPropertyName("slot")] int Slot,
    [property: JsonPropertyName("controllerType")] string ControllerType,
    [property: JsonPropertyName("resumed")] bool Resumed,
    [property: JsonPropertyName("resumeToken")] string ResumeToken,
    [property: JsonPropertyName("inputTimeoutMs")] int InputTimeoutMs,
    [property: JsonPropertyName("slotLeaseMs")] int SlotLeaseMs)
    : ControlMessage(Version, Type);

public sealed record PingMessage(
    int Version,
    string Type,
    [property: JsonPropertyName("id")] uint Id,
    [property: JsonPropertyName("clientTimeUs")] string ClientTimeUs)
    : ControlMessage(Version, Type);

public sealed record PongMessage(
    int Version,
    string Type,
    [property: JsonPropertyName("id")] uint Id,
    [property: JsonPropertyName("clientTimeUs")] string ClientTimeUs,
    [property: JsonPropertyName("serverReceiveTimeUs")] string ServerReceiveTimeUs,
    [property: JsonPropertyName("serverSendTimeUs")] string ServerSendTimeUs)
    : ControlMessage(Version, Type);

public sealed record InputReadyMessage(
    int Version,
    string Type,
    [property: JsonPropertyName("sequence")] uint Sequence)
    : ControlMessage(Version, Type);

public sealed record InputStatusMessage(
    int Version,
    string Type,
    [property: JsonPropertyName("state")] string State,
    [property: JsonPropertyName("lastSequence")] uint? LastSequence)
    : ControlMessage(Version, Type);

public sealed record LeaveMessage(int Version, string Type) : ControlMessage(Version, Type);

public sealed record SuspendMessage(int Version, string Type) : ControlMessage(Version, Type);

public sealed record RumbleMessage(
    int Version,
    string Type,
    [property: JsonPropertyName("lowFrequency")] byte LowFrequency,
    [property: JsonPropertyName("highFrequency")] byte HighFrequency)
    : ControlMessage(Version, Type);

public sealed record ErrorMessage(
    int Version,
    string Type,
    [property: JsonPropertyName("code")] string Code,
    [property: JsonPropertyName("message")] string Message,
    [property: JsonPropertyName("fatal")] bool Fatal,
    [property: JsonPropertyName("retryAfterMs")] int? RetryAfterMs = null)
    : ControlMessage(Version, Type);
