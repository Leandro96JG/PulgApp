using Makaretu.Dns;
using System.Net;

namespace Pulgapp.Server.Infrastructure;

/// <summary>Advertises only public connection metadata; pairing secrets never enter DNS-SD records.</summary>
public sealed class PulgappMdnsAdvertiser : IDisposable
{
    private readonly ServiceDiscovery _discovery = new();
    private ServiceProfile? _profile;

    public void Start(string serverName, int tcpPort, string serverId, IEnumerable<IPAddress> addresses)
    {
        Stop();
        _profile = new ServiceProfile($"{serverName} ({serverId[..8]})", "_pulgapp._tcp", checked((ushort)tcpPort), addresses);
        _profile.AddProperty("v", "1");
        _profile.AddProperty("id", serverId);
        _discovery.Advertise(_profile);
    }

    public void Stop()
    {
        if (_profile is null) return;
        _discovery.Unadvertise(_profile);
        _profile = null;
    }

    public void Dispose()
    {
        Stop();
        _discovery.Dispose();
    }
}
