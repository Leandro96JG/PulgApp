using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Pulgapp.Server.Protocol;

public static partial class QrPairingPayload
{
    public const string Scheme = "pulgapp";
    public const string Host = "pair";
    public const int DefaultPort = 26760;

    [GeneratedRegex(@"^\d{6}$")]
    private static partial Regex PinRegex();

    public static string Format(string ip, int port, string pin)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(ip);
        ArgumentException.ThrowIfNullOrWhiteSpace(pin);

        if (port is < 1 or > 65535)
        {
            throw new ArgumentOutOfRangeException(nameof(port), port, "Port must be between 1 and 65535.");
        }

        if (!PinRegex().IsMatch(pin))
        {
            throw new ArgumentException("PIN must be exactly six decimal digits.", nameof(pin));
        }

        var normalizedIp = ip.Trim();
        return $"{Scheme}://{Host}?ip={Uri.EscapeDataString(normalizedIp)}&port={port}&pin={Uri.EscapeDataString(pin)}";
    }

    public static bool TryParse(string? raw, out string? ip, out int port, out string? pin)
    {
        ip = null;
        port = DefaultPort;
        pin = null;

        if (string.IsNullOrWhiteSpace(raw))
        {
            return false;
        }

        var trimmed = raw.Trim();

        // 1. Try URI format: pulgapp://pair?... or pulgapp://connect?...
        if (Uri.TryCreate(trimmed, UriKind.Absolute, out var uri) &&
            string.Equals(uri.Scheme, Scheme, StringComparison.OrdinalIgnoreCase))
        {
            var query = uri.Query;
            if (!string.IsNullOrEmpty(query))
            {
                var queryParams = ParseQuery(query);
                string? parsedIp = null;
                string? parsedPin = null;
                var parsedPort = DefaultPort;

                if (queryParams.TryGetValue("ip", out var queryIp) && !string.IsNullOrWhiteSpace(queryIp))
                {
                    parsedIp = queryIp.Trim();
                }

                if (queryParams.TryGetValue("pin", out var queryPin) && PinRegex().IsMatch(queryPin.Trim()))
                {
                    parsedPin = queryPin.Trim();
                }

                if (queryParams.TryGetValue("port", out var queryPortStr) &&
                    int.TryParse(queryPortStr, out var portVal) &&
                    portVal is >= 1 and <= 65535)
                {
                    parsedPort = portVal;
                }

                if (parsedIp is not null && parsedPin is not null)
                {
                    ip = parsedIp;
                    port = parsedPort;
                    pin = parsedPin;
                    return true;
                }
            }
        }

        // 2. Try JSON format: {"ip":"...","pin":"...","port":26760}
        if (trimmed.StartsWith('{') && trimmed.EndsWith('}'))
        {
            try
            {
                using var doc = JsonDocument.Parse(trimmed);
                var root = doc.RootElement;
                if (root.ValueKind == JsonValueKind.Object)
                {
                    string? jsonIp = null;
                    string? jsonPin = null;
                    var jsonPort = DefaultPort;

                    if (root.TryGetProperty("ip", out var ipProp) && ipProp.ValueKind == JsonValueKind.String)
                    {
                        jsonIp = ipProp.GetString()?.Trim();
                    }

                    if (root.TryGetProperty("pin", out var pinProp) && pinProp.ValueKind == JsonValueKind.String)
                    {
                        jsonPin = pinProp.GetString()?.Trim();
                    }

                    if (root.TryGetProperty("port", out var portProp))
                    {
                        if (portProp.ValueKind == JsonValueKind.Number && portProp.TryGetInt32(out var p))
                        {
                            jsonPort = p;
                        }
                    }

                    if (!string.IsNullOrWhiteSpace(jsonIp) && jsonPin is not null && PinRegex().IsMatch(jsonPin) &&
                        jsonPort is >= 1 and <= 65535)
                    {
                        ip = jsonIp;
                        port = jsonPort;
                        pin = jsonPin;
                        return true;
                    }
                }
            }
            catch
            {
                // Fall through to plain text check
            }
        }

        // 3. Fallback: IP:PORT:PIN or IP:PIN
        var parts = trimmed.Split(':');
        if (parts.Length == 3)
        {
            var rawIp = parts[0].Trim();
            if (!string.IsNullOrWhiteSpace(rawIp) &&
                int.TryParse(parts[1], out var parsedPort) && parsedPort is >= 1 and <= 65535 &&
                PinRegex().IsMatch(parts[2].Trim()))
            {
                ip = rawIp;
                port = parsedPort;
                pin = parts[2].Trim();
                return true;
            }
        }
        else if (parts.Length == 2)
        {
            var rawIp = parts[0].Trim();
            var rawPin = parts[1].Trim();
            if (!string.IsNullOrWhiteSpace(rawIp) && PinRegex().IsMatch(rawPin))
            {
                ip = rawIp;
                port = DefaultPort;
                pin = rawPin;
                return true;
            }
        }

        ip = null;
        port = DefaultPort;
        pin = null;
        return false;
    }

    private static Dictionary<string, string> ParseQuery(string query)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (query.StartsWith('?'))
        {
            query = query[1..];
        }

        var pairs = query.Split('&', StringSplitOptions.RemoveEmptyEntries);
        foreach (var pair in pairs)
        {
            var eq = pair.IndexOf('=');
            if (eq > 0)
            {
                var key = Uri.UnescapeDataString(pair[..eq]);
                var val = Uri.UnescapeDataString(pair[(eq + 1)..]);
                result[key] = val;
            }
        }

        return result;
    }
}
