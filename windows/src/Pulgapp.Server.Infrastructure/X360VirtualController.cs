using System.Threading.Channels;
using Nefarius.ViGEm.Client;
using Nefarius.ViGEm.Client.Targets;
using Nefarius.ViGEm.Client.Targets.Xbox360;
using Pulgapp.Server.Core;

namespace Pulgapp.Server.Infrastructure;

public sealed class X360VirtualControllerFactory : VirtualControllerFactory, IDisposable
{
    private readonly ViGEmClient _client = new();
    private bool _disposed;

    public VirtualController Create(ControllerKind kind)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        return kind == ControllerKind.X360
            ? new X360VirtualController(_client.CreateXbox360Controller())
            : throw new NotSupportedException("DS4 targets are not available before P3.");
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _client.Dispose();
    }
}

public sealed class X360VirtualController : VirtualController
{
    private readonly IXbox360Controller _target;
    private readonly Channel<GamepadState> _states = Channel.CreateBounded<GamepadState>(new BoundedChannelOptions(1)
    {
        FullMode = BoundedChannelFullMode.DropOldest,
        SingleReader = true,
        SingleWriter = false,
    });
    private readonly IDisposable? _disposable;
    private Task? _worker;
    private bool _connected;

    public X360VirtualController(IXbox360Controller target)
    {
        _target = target ?? throw new ArgumentNullException(nameof(target));
        _disposable = target as IDisposable;
        _target.AutoSubmitReport = false;
    }

    public ControllerKind Kind => ControllerKind.X360;

    public void Connect()
    {
        if (_connected)
        {
            return;
        }

        _target.Connect();
        _connected = true;
        _worker = Task.Run(ProcessStatesAsync);
        Apply(GamepadState.Neutral);
    }

    public void Apply(GamepadState state)
    {
        if (_connected)
        {
            _states.Writer.TryWrite(state);
        }
    }

    public void Neutralize() => Apply(GamepadState.Neutral);

    public void Disconnect()
    {
        if (!_connected)
        {
            return;
        }

        _states.Writer.TryWrite(GamepadState.Neutral);
        _states.Writer.TryComplete();
        _worker!.GetAwaiter().GetResult();
        _target.Disconnect();
        _disposable?.Dispose();
        _connected = false;
    }

    private async Task ProcessStatesAsync()
    {
        await foreach (var state in _states.Reader.ReadAllAsync())
        {
            var report = X360ReportMapper.Map(state);
            _target.ResetReport();
            _target.SetButtonsFull((ushort)report.Buttons);
            _target.LeftTrigger = report.LeftTrigger;
            _target.RightTrigger = report.RightTrigger;
            _target.LeftThumbX = report.LeftX;
            _target.LeftThumbY = report.LeftY;
            _target.RightThumbX = report.RightX;
            _target.RightThumbY = report.RightY;
            _target.SubmitReport();
        }
    }
}
