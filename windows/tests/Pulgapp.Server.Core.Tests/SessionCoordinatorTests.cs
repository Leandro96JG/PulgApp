using Pulgapp.Server.Core;
using Pulgapp.Server.Protocol;

namespace Pulgapp.Server.Core.Tests;

public sealed class SessionCoordinatorTests
{
    [Fact]
    public void Start_new_allocates_lowest_free_slot_only_after_connecting_target()
    {
        var factory = new FakeFactory();
        var coordinator = CreateCoordinator(factory, out _);

        var first = coordinator.StartNew("one");
        var second = coordinator.StartNew("two");

        Assert.Equal(LobbyStartStatus.Success, first.Status);
        Assert.Equal(1, first.Slot);
        Assert.Equal(1, factory.Controllers[0].ConnectCount);
        Assert.Equal(2, second.Slot);

        factory.FailNextConnect = true;
        var failed = coordinator.StartNew("three");

        Assert.Equal(LobbyStartStatus.ControllerCreateFailed, failed.Status);
        Assert.Equal(LobbySlotState.Free, coordinator.GetSlotStatuses()[2].State);
        Assert.Equal(3, coordinator.StartNew("four").Slot);
    }

    [Fact]
    public void New_sessions_fill_four_slots_and_reject_fifth_and_duplicate_client()
    {
        var coordinator = CreateCoordinator(new FakeFactory(), out _);

        var sessions = Enumerable.Range(1, 4).Select(number => coordinator.StartNew($"client-{number}")).ToArray();

        Assert.Equal([1, 2, 3, 4], sessions.Select(result => result.Slot));
        Assert.Equal(LobbyStartStatus.ServerFull, coordinator.StartNew("client-5").Status);
        Assert.Equal(LobbyStartStatus.ClientAlreadyConnected, coordinator.StartNew("client-1").Status);
    }

    [Fact]
    public void Control_loss_leases_neutralized_target_and_resume_reuses_slot_with_fresh_credentials()
    {
        var factory = new FakeFactory();
        var coordinator = CreateCoordinator(factory, out _);
        var original = coordinator.StartNew("client-1");

        Assert.True(coordinator.HandleControlLoss(original.Credentials!.SessionId));
        Assert.Equal(1, factory.Controllers[0].NeutralizeCount);
        Assert.Equal(LobbySlotState.Reserved, coordinator.GetSlotStatuses()[0].State);
        Assert.False(coordinator.TryAccept(Snapshot(original.Credentials, 1)));
        Assert.Equal(LobbyStartStatus.ResumeRejected, coordinator.Resume("other-client", original.Credentials.ResumeToken).Status);

        var resumed = coordinator.Resume("client-1", original.Credentials.ResumeToken);

        Assert.Equal(LobbyStartStatus.Success, resumed.Status);
        Assert.Equal(original.Slot, resumed.Slot);
        Assert.Same(factory.Controllers[0], factory.Controllers.Single());
        Assert.NotEqual(original.Credentials.SessionId, resumed.Credentials!.SessionId);
        Assert.False(original.Credentials.UdpToken.SequenceEqual(resumed.Credentials.UdpToken));
        Assert.False(original.Credentials.ResumeToken.SequenceEqual(resumed.Credentials.ResumeToken));
        Assert.True(coordinator.TryAccept(Snapshot(resumed.Credentials, 1)));
    }

    [Fact]
    public void Lease_expiry_disconnects_and_frees_slot()
    {
        var factory = new FakeFactory();
        var coordinator = CreateCoordinator(factory, out var clock);
        var session = coordinator.StartNew("client-1");
        coordinator.HandleControlLoss(session.Credentials!.SessionId);

        clock.Advance(TimeSpan.FromSeconds(15));

        Assert.Equal(1, coordinator.ExpireLeases());
        Assert.Equal(1, factory.Controllers[0].DisconnectCount);
        Assert.Equal(LobbySlotState.Free, coordinator.GetSlotStatuses()[0].State);
        Assert.Equal(1, coordinator.StartNew("client-2").Slot);
    }

    [Theory]
    [InlineData("release")]
    [InlineData("shutdown")]
    public void Release_paths_immediately_neutralize_disconnect_and_free_allocation(string action)
    {
        var factory = new FakeFactory();
        var coordinator = CreateCoordinator(factory, out _);
        var session = coordinator.StartNew("client-1");

        if (action == "release")
        {
            Assert.True(coordinator.Release(session.Credentials!.SessionId));
        }
        else
        {
            coordinator.Shutdown();
        }

        Assert.Equal(1, factory.Controllers[0].NeutralizeCount);
        Assert.Equal(1, factory.Controllers[0].DisconnectCount);
        Assert.Equal(1, coordinator.StartNew("client-2").Slot);
    }

    [Fact]
    public void Authenticated_newer_snapshots_remain_isolated_per_session_and_timeout_independently()
    {
        var factory = new FakeFactory();
        var coordinator = CreateCoordinator(factory, out var clock);
        var first = coordinator.StartNew("client-1").Credentials!;
        var second = coordinator.StartNew("client-2").Credentials!;

        Assert.True(coordinator.TryAccept(Snapshot(first, 10)));
        Assert.False(coordinator.TryAccept(Snapshot(first, 10)));
        Assert.False(coordinator.TryAccept(Snapshot(first, 9)));
        Assert.False(coordinator.TryAccept(Snapshot(first with { SessionId = second.SessionId }, 11)));
        Assert.True(coordinator.TryAccept(Snapshot(second, 1)));
        clock.Advance(TimeSpan.FromMilliseconds(250));

        Assert.True(coordinator.CheckInputTimeout());
        Assert.Equal(1, factory.Controllers[0].NeutralizeCount);
        Assert.Equal(1, factory.Controllers[1].NeutralizeCount);
        Assert.True(coordinator.TryAccept(Snapshot(first, 11)));
        Assert.Equal(LobbySlotState.Active, coordinator.GetSlotStatuses()[0].State);
    }

    private static SessionCoordinator CreateCoordinator(FakeFactory factory, out FakeTimeProvider clock)
    {
        clock = new FakeTimeProvider();
        return new SessionCoordinator(factory, clock);
    }

    private static InputSnapshot Snapshot(SessionCredentials credentials, uint sequence) => new(
        credentials.SessionId,
        credentials.UdpToken,
        sequence,
        0,
        CanonicalButtons.A,
        1,
        2,
        3,
        4,
        5,
        6);

    private sealed class FakeFactory : VirtualControllerFactory
    {
        public List<FakeController> Controllers { get; } = [];
        public bool FailNextConnect { get; set; }

        public VirtualController Create(ControllerKind kind)
        {
            Assert.Equal(ControllerKind.X360, kind);
            var controller = new FakeController(kind, FailNextConnect);
            FailNextConnect = false;
            Controllers.Add(controller);
            return controller;
        }
    }

    private sealed class FakeController(ControllerKind kind, bool failConnect) : VirtualController
    {
        public ControllerKind Kind { get; } = kind;
        public int ConnectCount { get; private set; }
        public int NeutralizeCount { get; private set; }
        public int DisconnectCount { get; private set; }

        public void Connect()
        {
            ConnectCount++;
            if (failConnect)
            {
                throw new InvalidOperationException("Connect failed.");
            }
        }

        public void Apply(GamepadState state) { }
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
