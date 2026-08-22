using Nefarius.ViGEm.Client;
using Nefarius.ViGEm.Client.Exceptions;
using Nefarius.ViGEm.Client.Targets;
using Nefarius.ViGEm.Client.Targets.DualShock4;
using Nefarius.ViGEm.Client.Targets.Xbox360;

var options = DiagnosticOptions.Parse(args);
if (options.ShowHelp)
{
    DiagnosticOptions.PrintHelp();
    return 0;
}

using var cancellation = new CancellationTokenSource();
ConsoleCancelEventHandler cancelHandler = (_, eventArgs) =>
{
    eventArgs.Cancel = true;
    cancellation.Cancel();
};
Console.CancelKeyPress += cancelHandler;

var run = new DiagnosticRun(options);
EventHandler processExitHandler = (_, _) => run.Dispose();
AppDomain.CurrentDomain.ProcessExit += processExitHandler;

try
{
    return await run.ExecuteAsync(cancellation.Token);
}
catch (Exception exception)
{
    var failure = DriverFailureClassifier.Classify(exception);
    Console.Error.WriteLine($"Driver diagnostics failed ({failure}, {exception.GetType().Name}): {exception.Message}");
    if (failure is DriverFailure.BusMissing or DriverFailure.AccessDenied or DriverFailure.VersionMismatch)
    {
        Console.Error.WriteLine("Install ViGEmBus 1.22.0, then restart this diagnostic.");
    }

    return 1;
}
finally
{
    run.Dispose();
    AppDomain.CurrentDomain.ProcessExit -= processExitHandler;
    Console.CancelKeyPress -= cancelHandler;
}

internal enum DiagnosticMode
{
    OneX360,
    OneDs4,
    EightTargets
}

internal sealed record DiagnosticOptions(
    DiagnosticMode Mode,
    TimeSpan? Duration,
    bool StartNeutral,
    TimeSpan? JoinAfter,
    TimeSpan? ExerciseAfter,
    bool ShowHelp)
{
    public static DiagnosticOptions Parse(string[] args)
    {
        var mode = DiagnosticMode.EightTargets;
        var duration = TimeSpan.FromSeconds(30);
        var waitForCancel = false;
        var startNeutral = false;
        TimeSpan? joinAfter = null;
        TimeSpan? exerciseAfter = null;

        for (var index = 0; index < args.Length; index++)
        {
            switch (args[index].ToLowerInvariant())
            {
                case "--help":
                case "-h":
                    return new DiagnosticOptions(mode, duration, startNeutral, joinAfter, exerciseAfter, true);
                case "--mode":
                    if (++index >= args.Length)
                    {
                        throw new ArgumentException("--mode requires one-x360, one-ds4, or eight.");
                    }

                    mode = args[index].ToLowerInvariant() switch
                    {
                        "one-x360" => DiagnosticMode.OneX360,
                        "one-ds4" => DiagnosticMode.OneDs4,
                        "eight" or "eight-targets" => DiagnosticMode.EightTargets,
                        _ => throw new ArgumentException("--mode requires one-x360, one-ds4, or eight.")
                    };
                    break;
                case "--duration-seconds":
                    if (++index >= args.Length ||
                        !double.TryParse(args[index], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var seconds) ||
                        seconds < 0)
                    {
                        throw new ArgumentException("--duration-seconds requires a non-negative number.");
                    }

                    duration = TimeSpan.FromSeconds(seconds);
                    break;
                case "--wait-for-cancel":
                    waitForCancel = true;
                    break;
                case "--start-neutral":
                    startNeutral = true;
                    break;
                case "--join-after-seconds":
                    if (++index >= args.Length ||
                        !double.TryParse(args[index], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var joinSeconds) ||
                        joinSeconds < 0)
                    {
                        throw new ArgumentException("--join-after-seconds requires a non-negative number.");
                    }

                    joinAfter = TimeSpan.FromSeconds(joinSeconds);
                    startNeutral = true;
                    break;
                case "--exercise-after-seconds":
                    if (++index >= args.Length ||
                        !double.TryParse(args[index], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var exerciseSeconds) ||
                        exerciseSeconds < 0)
                    {
                        throw new ArgumentException("--exercise-after-seconds requires a non-negative number.");
                    }

                    exerciseAfter = TimeSpan.FromSeconds(exerciseSeconds);
                    startNeutral = true;
                    break;
                default:
                    throw new ArgumentException($"Unknown argument '{args[index]}'. Use --help for usage.");
            }
        }

        if ((joinAfter is not null || exerciseAfter is not null) && !waitForCancel)
        {
            throw new ArgumentException("Scheduled game states require --wait-for-cancel.");
        }

        if (joinAfter is { } joinDelay && exerciseAfter is { } exerciseDelay &&
            exerciseDelay <= joinDelay + TimeSpan.FromMilliseconds(500))
        {
            throw new ArgumentException("--exercise-after-seconds must occur after the join pulse finishes.");
        }

        return new DiagnosticOptions(mode, waitForCancel ? null : duration, startNeutral, joinAfter, exerciseAfter, false);
    }

    public static void PrintHelp()
    {
        Console.WriteLine("Pulgapp ViGEm driver diagnostics");
        Console.WriteLine("Usage: dotnet run --project windows/tools/Pulgapp.DriverDiagnostics -- [options]");
        Console.WriteLine("  --mode one-x360       Create and exercise one X360 target.");
        Console.WriteLine("  --mode one-ds4        Create and exercise one DS4 target.");
        Console.WriteLine("  --mode eight           Create four X360 and four DS4 targets.");
        Console.WriteLine("  --duration-seconds N   Hold deterministic states for N seconds (default: 30).");
        Console.WriteLine("  --wait-for-cancel      Hold targets until Ctrl+C; overrides --duration-seconds.");
        Console.WriteLine("  --start-neutral        Keep all targets neutral instead of applying test states.");
        Console.WriteLine("  --join-after-seconds N Start neutral, then pulse A/Cross on all targets after N seconds; requires --wait-for-cancel.");
        Console.WriteLine("  --exercise-after-seconds N Start neutral, then apply distinct held test states after N seconds; requires --wait-for-cancel.");
        Console.WriteLine("  --help                 Show this help.");
    }
}

internal enum DriverFailure
{
    Unknown,
    BusMissing,
    AccessDenied,
    VersionMismatch,
    TargetCreationFailed
}

internal static class DriverFailureClassifier
{
    public static DriverFailure Classify(Exception exception)
    {
        for (var current = exception; current is not null; current = current.InnerException)
        {
            switch (current)
            {
                case VigemBusNotFoundException:
                case DllNotFoundException:
                    return DriverFailure.BusMissing;
                case VigemBusAccessFailedException:
                case UnauthorizedAccessException:
                    return DriverFailure.AccessDenied;
                case VigemBusVersionMismatchException:
                    return DriverFailure.VersionMismatch;
            }
        }

        return exception is VigemAllocFailedException or VigemInvalidTargetException
            ? DriverFailure.TargetCreationFailed
            : DriverFailure.Unknown;
    }
}

internal sealed class DiagnosticRun : IDisposable
{
    private readonly DiagnosticOptions _options;
    private readonly List<DiagnosticTarget> _targets = [];
    private ViGEmClient? _client;
    private bool _disposed;

    public DiagnosticRun(DiagnosticOptions options)
    {
        _options = options;
    }

    public async Task<int> ExecuteAsync(CancellationToken cancellationToken)
    {
        _client = new ViGEmClient();
        var duration = _options.Duration is { } configuredDuration
            ? $"{configuredDuration.TotalSeconds:0.###}s"
            : "until Ctrl+C";
        Console.WriteLine($"ViGEm client connected; mode={_options.Mode}, duration={duration}.");

        CreateTargets();
        foreach (var target in _targets)
        {
            target.ConnectAndNeutralize();
        }

        Console.WriteLine($"Created {_targets.Count} target(s). Initial state is neutral.");
        if (_options.StartNeutral)
        {
            Console.WriteLine("All targets remain neutral.");
        }
        else
        {
            ApplyDeterministicStates();
            Console.WriteLine("Deterministic test states submitted.");
        }

        var joinTask = _options.JoinAfter is { } joinAfter
            ? PulseJoinAfterDelayAsync(joinAfter, cancellationToken)
            : Task.CompletedTask;
        var exerciseTask = _options.ExerciseAfter is { } exerciseAfter
            ? ApplyDeterministicStatesAfterDelayAsync(exerciseAfter, cancellationToken)
            : Task.CompletedTask;
        Console.WriteLine(_options.Duration is null
            ? "Press Ctrl+C to neutralize and disconnect targets."
            : "Press Ctrl+C to stop early.");

        try
        {
            await Task.Delay(_options.Duration ?? Timeout.InfiniteTimeSpan, cancellationToken);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            Console.WriteLine("Cancellation requested; neutralizing targets.");
        }

        await Task.WhenAll(joinTask, exerciseTask);
        NeutralizeTargets();
        Console.WriteLine("All targets neutralized.");
        return 0;
    }

    private void CreateTargets()
    {
        if (_client is null)
        {
            throw new InvalidOperationException("ViGEm client is not initialized.");
        }

        var targetCount = _options.Mode == DiagnosticMode.EightTargets ? 8 : 1;
        for (var index = 0; index < targetCount; index++)
        {
            var kind = _options.Mode switch
            {
                DiagnosticMode.OneX360 => DiagnosticTargetKind.X360,
                DiagnosticMode.OneDs4 => DiagnosticTargetKind.Ds4,
                DiagnosticMode.EightTargets when index < 4 => DiagnosticTargetKind.X360,
                DiagnosticMode.EightTargets => DiagnosticTargetKind.Ds4,
                _ => throw new InvalidOperationException("Unknown diagnostic mode.")
            };

            var target = kind == DiagnosticTargetKind.X360
                ? new DiagnosticTarget($"X360-{index + 1}", _client.CreateXbox360Controller(), kind, index)
                : new DiagnosticTarget(
                    $"DS4-{(_options.Mode == DiagnosticMode.OneDs4 ? 1 : index - 3)}",
                    _client.CreateDualShock4Controller(),
                    kind,
                    _options.Mode == DiagnosticMode.OneDs4 ? 0 : index - 4);
            _targets.Add(target);
        }
    }

    private void ApplyDeterministicStates()
    {
        foreach (var target in _targets)
        {
            target.ApplyDeterministicState();
        }
    }

    private void NeutralizeTargets()
    {
        foreach (var target in _targets)
        {
            target.Neutralize();
        }
    }

    private async Task PulseJoinAfterDelayAsync(TimeSpan delay, CancellationToken cancellationToken)
    {
        try
        {
            Console.WriteLine($"Join pulse scheduled in {delay.TotalSeconds:0.###}s.");
            await Task.Delay(delay, cancellationToken);
            foreach (var target in _targets)
            {
                target.ApplyJoinState();
            }

            Console.WriteLine("Join pulse submitted to all targets.");
            await Task.Delay(TimeSpan.FromMilliseconds(500), cancellationToken);
            NeutralizeTargets();
            Console.WriteLine("Join pulse released; all targets returned to neutral.");
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            // The caller awaits this task before cleanup so no target receives concurrent reports.
        }
    }

    private async Task ApplyDeterministicStatesAfterDelayAsync(TimeSpan delay, CancellationToken cancellationToken)
    {
        try
        {
            Console.WriteLine($"Distinct-state exercise scheduled in {delay.TotalSeconds:0.###}s.");
            await Task.Delay(delay, cancellationToken);
            ApplyDeterministicStates();
            Console.WriteLine("Distinct test states submitted; inspect independent in-game input, then press Ctrl+C.");
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            // The caller awaits this task before cleanup so no target receives concurrent reports.
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        for (var index = _targets.Count - 1; index >= 0; index--)
        {
            try
            {
                _targets[index].Dispose();
            }
            catch (Exception exception)
            {
                Console.Error.WriteLine($"Cleanup failed for target {index + 1}: {exception.Message}");
            }
        }

        _targets.Clear();
        try
        {
            _client?.Dispose();
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine($"Could not dispose the ViGEm client: {exception.Message}");
        }

        _client = null;
    }
}

internal enum DiagnosticTargetKind
{
    X360,
    Ds4
}

internal sealed class DiagnosticTarget : IDisposable
{
    private readonly string _label;
    private readonly IVirtualGamepad _controller;
    private readonly IDisposable? _disposable;
    private readonly DiagnosticTargetKind _kind;
    private readonly int _stateIndex;
    private bool _disposed;

    public DiagnosticTarget(string label, IVirtualGamepad controller, DiagnosticTargetKind kind, int stateIndex)
    {
        _label = label;
        _controller = controller;
        _disposable = controller as IDisposable;
        _kind = kind;
        _stateIndex = stateIndex;
        _controller.AutoSubmitReport = false;
    }

    public void ConnectAndNeutralize()
    {
        _controller.Connect();
        Neutralize();
        Console.WriteLine($"Connected {_label}.");
    }

    public void ApplyDeterministicState()
    {
        _controller.ResetReport();
        if (_kind == DiagnosticTargetKind.X360)
        {
            var controller = (IXbox360Controller)_controller;
            controller.SetButtonsFull((ushort)(0x1000 << _stateIndex));
            controller.LeftThumbX = (short)(12000 + (_stateIndex * 6000));
            controller.LeftThumbY = (short)(-10000 - (_stateIndex * 5000));
            controller.RightThumbX = (short)(-14000 - (_stateIndex * 4000));
            controller.RightThumbY = (short)(9000 + (_stateIndex * 5000));
            controller.LeftTrigger = (byte)(64 + (_stateIndex * 48));
            controller.RightTrigger = (byte)(192 - (_stateIndex * 32));
        }
        else
        {
            var controller = (IDualShock4Controller)_controller;
            controller.SetButtonsFull((ushort)(0x10 << _stateIndex));
            controller.SetSpecialButtonsFull((byte)(_stateIndex == 0 ? 1 : 0));
            controller.SetDPadDirection(CreateDpadDirection(_stateIndex));
            controller.LeftThumbX = (byte)(48 + (_stateIndex * 48));
            controller.LeftThumbY = (byte)(208 - (_stateIndex * 32));
            controller.RightThumbX = (byte)(224 - (_stateIndex * 48));
            controller.RightThumbY = (byte)(32 + (_stateIndex * 48));
            controller.LeftTrigger = (byte)(64 + (_stateIndex * 48));
            controller.RightTrigger = (byte)(192 - (_stateIndex * 32));
            controller.SetButtonsFull((ushort)((0x10 << _stateIndex) | 0x0C00));
        }

        _controller.SubmitReport();
        Console.WriteLine($"Submitted deterministic state for {_label}.");
    }

    public void ApplyJoinState()
    {
        _controller.ResetReport();
        if (_kind == DiagnosticTargetKind.X360)
        {
            ((IXbox360Controller)_controller).SetButtonsFull(0x1000);
        }
        else
        {
            ((IDualShock4Controller)_controller).SetButtonsFull(0x0020);
        }

        _controller.SubmitReport();
    }

    private static DualShock4DPadDirection CreateDpadDirection(int stateIndex)
    {
        var name = stateIndex switch
        {
            0 => "NorthDPadDirection",
            1 => "EastDPadDirection",
            2 => "SouthDPadDirection",
            3 => "WestDPadDirection",
            _ => "NoneDPadDirection"
        };
        var type = typeof(DualShock4DPadDirection).GetNestedType(
            name,
            System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.NonPublic)
            ?? throw new InvalidOperationException($"ViGEm client does not expose DS4 D-pad direction '{name}'.");
        return (DualShock4DPadDirection)(Activator.CreateInstance(type)
            ?? throw new InvalidOperationException($"Could not create DS4 D-pad direction '{name}'."));
    }

    public void Neutralize()
    {
        if (_disposed)
        {
            return;
        }

        _controller.ResetReport();
        _controller.SubmitReport();
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        try
        {
            _controller.ResetReport();
            _controller.SubmitReport();
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine($"Could not neutralize {_label} during cleanup: {exception.Message}");
        }
        finally
        {
            try
            {
                _controller.Disconnect();
            }
            catch (Exception exception)
            {
                Console.Error.WriteLine($"Could not disconnect {_label}: {exception.Message}");
            }
            finally
            {
                try
                {
                    _disposable?.Dispose();
                    Console.WriteLine($"Disposed {_label}.");
                }
                catch (Exception exception)
                {
                    Console.Error.WriteLine($"Could not dispose {_label}: {exception.Message}");
                }
            }
        }
    }
}
