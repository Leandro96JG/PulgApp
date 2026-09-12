using System.Threading.Channels;
using Nefarius.ViGEm.Client;
using Nefarius.ViGEm.Client.Targets;
using Nefarius.ViGEm.Client.Targets.DualShock4;
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
        return kind switch
        {
            ControllerKind.X360 => new X360VirtualController(_client.CreateXbox360Controller()),
            ControllerKind.Ds4 => new Ds4VirtualController(_client.CreateDualShock4Controller()),
            _ => throw new ArgumentOutOfRangeException(nameof(kind)),
        };
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

public sealed class Ds4VirtualController : VirtualController
{
    private readonly IDualShock4Controller _target;
    private readonly Channel<GamepadState> _states = Channel.CreateBounded<GamepadState>(new BoundedChannelOptions(1)
    {
        FullMode = BoundedChannelFullMode.DropOldest,
        SingleReader = true,
        SingleWriter = false,
    });
    private readonly IDisposable? _disposable;
    private Task? _worker;
    private bool _connected;

    public Ds4VirtualController(IDualShock4Controller target)
    {
        _target = target ?? throw new ArgumentNullException(nameof(target));
        _disposable = target as IDisposable;
        _target.AutoSubmitReport = false;
    }

    public ControllerKind Kind => ControllerKind.Ds4;

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
            var report = Ds4ReportMapper.Map(state);
            _target.ResetReport();
            _target.SetButtonsFull((ushort)report.Buttons);
            _target.SetSpecialButtonsFull(report.PsButton ? (byte)1 : (byte)0);
            _target.SetDPadDirection(CreateDpadDirection(report.Dpad));
            _target.LeftTrigger = report.LeftTrigger;
            _target.RightTrigger = report.RightTrigger;
            _target.LeftThumbX = report.LeftX;
            _target.LeftThumbY = report.LeftY;
            _target.RightThumbX = report.RightX;
            _target.RightThumbY = report.RightY;
            _target.SubmitReport();
        }
    }

    private static DualShock4DPadDirection CreateDpadDirection(Ds4DpadDirection direction)
    {
        var name = direction switch
        {
            Ds4DpadDirection.North => "NorthDPadDirection",
            Ds4DpadDirection.NorthEast => "NortheastDPadDirection",
            Ds4DpadDirection.East => "EastDPadDirection",
            Ds4DpadDirection.SouthEast => "SoutheastDPadDirection",
            Ds4DpadDirection.South => "SouthDPadDirection",
            Ds4DpadDirection.SouthWest => "SouthwestDPadDirection",
            Ds4DpadDirection.West => "WestDPadDirection",
            Ds4DpadDirection.NorthWest => "NorthwestDPadDirection",
            _ => "NoneDPadDirection",
        };
        var type = typeof(DualShock4DPadDirection).GetNestedType(
            name,
            System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.NonPublic)
            ?? throw new InvalidOperationException($"ViGEm client does not expose DS4 D-pad direction '{name}'.");
        return (DualShock4DPadDirection)(Activator.CreateInstance(type)
            ?? throw new InvalidOperationException($"Could not create DS4 D-pad direction '{name}'."));
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
