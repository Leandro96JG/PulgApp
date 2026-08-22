using System.Security.Cryptography;
using Pulgapp.Server.Protocol;

namespace Pulgapp.Server.Core;

public sealed class SessionCoordinator : IDisposable
{
    private static readonly TimeSpan InputTimeout = TimeSpan.FromMilliseconds(250);
    private readonly VirtualControllerFactory _controllerFactory;
    private readonly TimeProvider _timeProvider;
    private VirtualController? _controller;
    private byte[]? _udpToken;
    private ulong _sessionId;
    private uint? _lastSequence;
    private DateTimeOffset _lastAcceptedInput;
    private bool _timedOut;

    public SessionCoordinator(VirtualControllerFactory controllerFactory, TimeProvider timeProvider)
    {
        _controllerFactory = controllerFactory ?? throw new ArgumentNullException(nameof(controllerFactory));
        _timeProvider = timeProvider ?? throw new ArgumentNullException(nameof(timeProvider));
    }

    public bool IsActive => _controller is not null;

    public bool IsInputTimedOut => _timedOut;

    public uint? LastSequence => _lastSequence;

    public void Start(ulong sessionId, ReadOnlySpan<byte> udpToken)
    {
        if (sessionId == 0)
        {
            throw new ArgumentOutOfRangeException(nameof(sessionId));
        }

        if (udpToken.Length != 16)
        {
            throw new ArgumentException("The UDP token must contain 16 bytes.", nameof(udpToken));
        }

        if (_controller is not null)
        {
            throw new InvalidOperationException("A session is already active.");
        }

        var controller = _controllerFactory.Create(ControllerKind.X360);
        if (controller.Kind != ControllerKind.X360)
        {
            throw new InvalidOperationException("The P1 slot requires an X360 controller.");
        }

        try
        {
            controller.Connect();
        }
        catch
        {
            controller.Disconnect();
            throw;
        }

        _controller = controller;
        _sessionId = sessionId;
        _udpToken = udpToken.ToArray();
        _lastSequence = null;
        _lastAcceptedInput = _timeProvider.GetUtcNow();
        _timedOut = false;
    }

    public bool TryAccept(InputSnapshot snapshot)
    {
        if (_controller is null || _udpToken is null ||
            snapshot.SessionId != _sessionId ||
            !CryptographicOperations.FixedTimeEquals(snapshot.UdpToken, _udpToken) ||
            (_lastSequence.HasValue && !UdpInputDecoder.IsNewerSequence(snapshot.Sequence, _lastSequence.Value)))
        {
            return false;
        }

        _controller.Apply(new GamepadState(
            (uint)snapshot.Buttons,
            snapshot.LeftX,
            snapshot.LeftY,
            snapshot.RightX,
            snapshot.RightY,
            snapshot.LeftTrigger,
            snapshot.RightTrigger));
        _lastSequence = snapshot.Sequence;
        _lastAcceptedInput = _timeProvider.GetUtcNow();
        _timedOut = false;
        return true;
    }

    public bool CheckInputTimeout()
    {
        if (_controller is null || _timedOut || _timeProvider.GetUtcNow() - _lastAcceptedInput < InputTimeout)
        {
            return false;
        }

        _controller.Neutralize();
        _timedOut = true;
        return true;
    }

    public void HandleControlLoss()
    {
        _controller?.Neutralize();
        _timedOut = true;
    }

    public void Leave() => EndSession();

    public void Shutdown() => EndSession();

    public void Cancel() => EndSession();

    public void Dispose() => EndSession();

    private void EndSession()
    {
        if (_controller is null)
        {
            return;
        }

        try
        {
            _controller.Neutralize();
        }
        finally
        {
            _controller.Disconnect();
            _controller = null;
            _udpToken = null;
            _sessionId = 0;
            _lastSequence = null;
            _timedOut = false;
        }
    }
}
