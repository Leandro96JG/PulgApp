using Pulgapp.Server.Core;
using Pulgapp.Server.Protocol;

namespace Pulgapp.Server.Core.Tests;

public sealed class SessionCoordinatorTests
{
    private static readonly byte[] Token = Convert.FromHexString("00112233445566778899AABBCCDDEEFF");

    [Fact]
    public void Neutral_is_a_single_immutable_zero_state()
    {
        Assert.Same(GamepadState.Neutral, GamepadState.Neutral);
        Assert.Equal(new GamepadState(0, 0, 0, 0, 0, 0, 0), GamepadState.Neutral);
    }

    [Fact]
    public void Start_creates_and_connects_one_x360_controller()
    {
        var controller = new FakeController(ControllerKind.X360);
        var coordinator = CreateCoordinator(controller, out _);

        coordinator.Start(1, Token);

        Assert.True(coordinator.IsActive);
        Assert.Equal(1, controller.ConnectCount);
    }

    [Fact]
    public void Accepts_only_authenticated_newer_snapshots()
    {
        var controller = new FakeController(ControllerKind.X360);
        var coordinator = CreateCoordinator(controller, out _);
        coordinator.Start(1, Token);

        Assert.True(coordinator.TryAccept(Snapshot(sequence: 10)));
        Assert.False(coordinator.TryAccept(Snapshot(sequence: 10)));
        Assert.False(coordinator.TryAccept(Snapshot(sequence: 9)));
        Assert.False(coordinator.TryAccept(Snapshot(sessionId: 2, sequence: 11)));
        Assert.False(coordinator.TryAccept(Snapshot(token: new byte[16], sequence: 11)));
        Assert.Single(controller.AppliedStates);
        Assert.Equal(new GamepadState((uint)CanonicalButtons.A, 1, 2, 3, 4, 5, 6), controller.AppliedStates[0]);
    }

    [Fact]
    public void Watchdog_neutralizes_once_at_250_ms_and_a_valid_packet_restores_input()
    {
        var controller = new FakeController(ControllerKind.X360);
        var coordinator = CreateCoordinator(controller, out var clock);
        coordinator.Start(1, Token);
        clock.Advance(TimeSpan.FromMilliseconds(249));

        Assert.False(coordinator.CheckInputTimeout());
        clock.Advance(TimeSpan.FromMilliseconds(1));
        Assert.True(coordinator.CheckInputTimeout());
        Assert.True(coordinator.IsInputTimedOut);
        Assert.False(coordinator.CheckInputTimeout());
        Assert.Equal(1, controller.NeutralizeCount);

        Assert.True(coordinator.TryAccept(Snapshot(sequence: 1)));
        Assert.False(coordinator.IsInputTimedOut);
    }

    [Theory]
    [InlineData("control-loss", 0)]
    [InlineData("leave", 1)]
    [InlineData("shutdown", 1)]
    [InlineData("cancellation", 1)]
    public void Ownership_loss_paths_always_neutralize(string action, int expectedDisconnects)
    {
        var controller = new FakeController(ControllerKind.X360);
        var coordinator = CreateCoordinator(controller, out _);
        coordinator.Start(1, Token);

        switch (action)
        {
            case "control-loss":
                coordinator.HandleControlLoss();
                break;
            case "leave":
                coordinator.Leave();
                break;
            case "shutdown":
                coordinator.Shutdown();
                break;
            case "cancellation":
                coordinator.Cancel();
                break;
            default:
                throw new InvalidOperationException();
        }

        Assert.Equal(1, controller.NeutralizeCount);
        Assert.Equal(expectedDisconnects, controller.DisconnectCount);
    }

    private static SessionCoordinator CreateCoordinator(FakeController controller, out FakeTimeProvider clock)
    {
        clock = new FakeTimeProvider();
        return new SessionCoordinator(new FakeFactory(controller), clock);
    }

    private static InputSnapshot Snapshot(ulong sessionId = 1, byte[]? token = null, uint sequence = 1) => new(
        sessionId,
        token ?? Token,
        sequence,
        0,
        CanonicalButtons.A,
        1,
        2,
        3,
        4,
        5,
        6);

    private sealed class FakeFactory(FakeController controller) : VirtualControllerFactory
    {
        public VirtualController Create(ControllerKind kind)
        {
            Assert.Equal(ControllerKind.X360, kind);
            return controller;
        }
    }

    private sealed class FakeController(ControllerKind kind) : VirtualController
    {
        public ControllerKind Kind { get; } = kind;

        public int ConnectCount { get; private set; }

        public int NeutralizeCount { get; private set; }

        public int DisconnectCount { get; private set; }

        public List<GamepadState> AppliedStates { get; } = [];

        public void Connect() => ConnectCount++;

        public void Apply(GamepadState state) => AppliedStates.Add(state);

        public void Neutralize() => NeutralizeCount++;

        public void Disconnect() => DisconnectCount++;
    }

    private sealed class FakeTimeProvider : TimeProvider
    {
        private DateTimeOffset _utcNow = DateTimeOffset.UnixEpoch;

        public override DateTimeOffset GetUtcNow() => _utcNow;

        public void Advance(TimeSpan elapsed) => _utcNow += elapsed;
    }
}
