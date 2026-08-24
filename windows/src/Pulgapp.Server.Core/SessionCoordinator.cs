using System.Buffers.Binary;
using System.Security.Cryptography;
using Pulgapp.Server.Protocol;

namespace Pulgapp.Server.Core;

public enum LobbyStartStatus
{
    Success,
    ServerFull,
    ClientAlreadyConnected,
    ResumeRejected,
    ControllerCreateFailed,
}

public enum LobbySlotState
{
    Free,
    Active,
    Reserved,
    InputTimedOut,
}

public sealed record SessionCredentials(ulong SessionId, byte[] UdpToken, byte[] ResumeToken);

public sealed record LobbyStartResult(LobbyStartStatus Status, int? Slot = null, SessionCredentials? Credentials = null)
{
    public bool Succeeded => Status == LobbyStartStatus.Success;
}

public sealed record LobbySlotStatus(int Slot, LobbySlotState State, string? ClientId, uint? LastSequence);

public sealed class SessionCoordinator : IDisposable
{
    private static readonly TimeSpan InputTimeout = TimeSpan.FromMilliseconds(250);
    private static readonly TimeSpan SlotLease = TimeSpan.FromSeconds(15);
    private const int SlotCount = 4;

    private readonly object _gate = new();
    private readonly VirtualControllerFactory _controllerFactory;
    private readonly TimeProvider _timeProvider;
    private readonly Slot[] _slots = Enumerable.Range(1, SlotCount).Select(slot => new Slot(slot)).ToArray();

    public SessionCoordinator(VirtualControllerFactory controllerFactory, TimeProvider timeProvider)
    {
        _controllerFactory = controllerFactory ?? throw new ArgumentNullException(nameof(controllerFactory));
        _timeProvider = timeProvider ?? throw new ArgumentNullException(nameof(timeProvider));
    }

    public bool IsActive
    {
        get
        {
            lock (_gate)
            {
                return _slots.Any(slot => slot.State is LobbySlotState.Active or LobbySlotState.InputTimedOut);
            }
        }
    }

    public bool IsInputTimedOut
    {
        get
        {
            lock (_gate)
            {
                var activeSlots = ActiveSlots().ToArray();
                return activeSlots.Length > 0 && activeSlots.All(slot => slot.State == LobbySlotState.InputTimedOut);
            }
        }
    }

    public uint? LastSequence
    {
        get
        {
            lock (_gate)
            {
                return ActiveSlots().SingleOrDefault()?.LastSequence;
            }
        }
    }

    public LobbyStartResult StartNew(string clientId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(clientId);

        lock (_gate)
        {
            if (_slots.Any(slot => slot.ClientId == clientId && slot.State != LobbySlotState.Free))
            {
                return new LobbyStartResult(LobbyStartStatus.ClientAlreadyConnected);
            }

            var slot = _slots.FirstOrDefault(slot => slot.State == LobbySlotState.Free);
            if (slot is null)
            {
                return new LobbyStartResult(LobbyStartStatus.ServerFull);
            }

            return StartInSlot(slot, clientId, CreateCredentials(), resumed: false);
        }
    }

    public LobbyStartResult Resume(string clientId, ReadOnlySpan<byte> resumeToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(clientId);
        if (resumeToken.Length != 32)
        {
            return new LobbyStartResult(LobbyStartStatus.ResumeRejected);
        }

        var suppliedToken = resumeToken.ToArray();

        lock (_gate)
        {
            var slot = _slots.SingleOrDefault(slot =>
                slot.State == LobbySlotState.Reserved &&
                slot.ClientId == clientId &&
                slot.ResumeToken is not null &&
                CryptographicOperations.FixedTimeEquals(suppliedToken, slot.ResumeToken));
            if (slot is null)
            {
                return new LobbyStartResult(LobbyStartStatus.ResumeRejected);
            }

            return StartInSlot(slot, clientId, CreateCredentials(), resumed: true);
        }
    }

    public bool TryAccept(InputSnapshot snapshot)
    {
        lock (_gate)
        {
            var slot = _slots.SingleOrDefault(slot =>
                (slot.State is LobbySlotState.Active or LobbySlotState.InputTimedOut) &&
                slot.SessionId == snapshot.SessionId &&
                snapshot.UdpToken is not null &&
                slot.UdpToken is not null &&
                CryptographicOperations.FixedTimeEquals(snapshot.UdpToken, slot.UdpToken));
            if (slot is null || (slot.LastSequence.HasValue && !UdpInputDecoder.IsNewerSequence(snapshot.Sequence, slot.LastSequence.Value)))
            {
                return false;
            }

            slot.Controller!.Apply(new GamepadState(
                (uint)snapshot.Buttons,
                snapshot.LeftX,
                snapshot.LeftY,
                snapshot.RightX,
                snapshot.RightY,
                snapshot.LeftTrigger,
                snapshot.RightTrigger));
            slot.LastSequence = snapshot.Sequence;
            slot.LastAcceptedInput = _timeProvider.GetUtcNow();
            slot.State = LobbySlotState.Active;
            return true;
        }
    }

    public bool CheckInputTimeout()
    {
        var changed = false;
        lock (_gate)
        {
            foreach (var slot in ActiveSlots().Where(slot =>
                         slot.State == LobbySlotState.Active && _timeProvider.GetUtcNow() - slot.LastAcceptedInput >= InputTimeout))
            {
                slot.Controller!.Neutralize();
                slot.State = LobbySlotState.InputTimedOut;
                changed = true;
            }
        }

        return changed;
    }

    public bool HandleControlLoss(ulong sessionId)
    {
        lock (_gate)
        {
            var slot = ActiveSlots().SingleOrDefault(slot => slot.SessionId == sessionId);
            if (slot is null)
            {
                return false;
            }

            slot.Controller!.Neutralize();
            slot.State = LobbySlotState.Reserved;
            slot.LeaseExpiresAt = _timeProvider.GetUtcNow() + SlotLease;
            InvalidateSession(slot);
            return true;
        }
    }

    public bool Release(ulong sessionId)
    {
        lock (_gate)
        {
            var slot = _slots.SingleOrDefault(slot => slot.State != LobbySlotState.Free && slot.SessionId == sessionId);
            if (slot is null)
            {
                return false;
            }

            Free(slot);
            return true;
        }
    }

    public bool ReleaseSlot(int slotNumber)
    {
        lock (_gate)
        {
            var slot = _slots.SingleOrDefault(slot => slot.Number == slotNumber && slot.State != LobbySlotState.Free);
            if (slot is null)
            {
                return false;
            }

            Free(slot);
            return true;
        }
    }

    public int ExpireLeases()
    {
        var expired = 0;
        lock (_gate)
        {
            var now = _timeProvider.GetUtcNow();
            foreach (var slot in _slots.Where(slot => slot.State == LobbySlotState.Reserved && slot.LeaseExpiresAt <= now).ToArray())
            {
                Free(slot);
                expired++;
            }
        }

        return expired;
    }

    public IReadOnlyList<LobbySlotStatus> GetSlotStatuses()
    {
        lock (_gate)
        {
            return _slots.Select(slot => new LobbySlotStatus(slot.Number, slot.State, slot.ClientId, slot.LastSequence)).ToArray();
        }
    }

    public bool TryGetSlotStatus(ulong sessionId, out LobbySlotStatus? status)
    {
        lock (_gate)
        {
            var slot = _slots.SingleOrDefault(slot => slot.State != LobbySlotState.Free && slot.SessionId == sessionId);
            status = slot is null ? null : new LobbySlotStatus(slot.Number, slot.State, slot.ClientId, slot.LastSequence);
            return status is not null;
        }
    }

    // Compatibility shims for the P1 transport, which has not yet been migrated to client-scoped calls.
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

        lock (_gate)
        {
            if (_slots.Any(slot => slot.State != LobbySlotState.Free))
            {
                throw new InvalidOperationException("A session is already active.");
            }

            var result = StartInSlot(_slots[0], "p1-transport", new SessionCredentials(sessionId, udpToken.ToArray(), RandomNumberGenerator.GetBytes(32)), resumed: false);
            if (!result.Succeeded)
            {
                throw new InvalidOperationException("The controller could not be created.");
            }
        }
    }

    public void HandleControlLoss()
    {
        lock (_gate)
        {
            var slot = ActiveSlots().SingleOrDefault();
            if (slot is not null)
            {
                HandleControlLoss(slot.SessionId);
            }
        }
    }

    public void Leave() => ReleaseAll();

    public void Cancel() => ReleaseAll();

    public void Shutdown() => ReleaseAll();

    public void Dispose() => ReleaseAll();

    private LobbyStartResult StartInSlot(Slot slot, string clientId, SessionCredentials credentials, bool resumed)
    {
        VirtualController? controller = slot.Controller;
        try
        {
            if (!resumed)
            {
                controller = _controllerFactory.Create(ControllerKind.X360);
                if (controller.Kind != ControllerKind.X360)
                {
                    throw new InvalidOperationException("Slots 1-4 require X360 controllers.");
                }

                controller.Connect();
            }

            slot.Controller = controller;
            slot.ClientId = clientId;
            slot.SessionId = credentials.SessionId;
            slot.UdpToken = credentials.UdpToken.ToArray();
            slot.ResumeToken = credentials.ResumeToken.ToArray();
            slot.LastSequence = null;
            slot.LastAcceptedInput = _timeProvider.GetUtcNow();
            slot.LeaseExpiresAt = null;
            slot.State = LobbySlotState.Active;
            return new LobbyStartResult(LobbyStartStatus.Success, slot.Number, credentials);
        }
        catch
        {
            if (!resumed)
            {
                controller?.Disconnect();
                Clear(slot);
            }

            return new LobbyStartResult(LobbyStartStatus.ControllerCreateFailed);
        }
    }

    private void ReleaseAll()
    {
        lock (_gate)
        {
            foreach (var slot in _slots.Where(slot => slot.State != LobbySlotState.Free).ToArray())
            {
                Free(slot);
            }
        }
    }

    private void Free(Slot slot)
    {
        try
        {
            slot.Controller?.Neutralize();
        }
        finally
        {
            slot.Controller?.Disconnect();
            Clear(slot);
        }
    }

    private static void InvalidateSession(Slot slot)
    {
        slot.SessionId = 0;
        slot.UdpToken = null;
        slot.LastSequence = null;
    }

    private static void Clear(Slot slot)
    {
        slot.Controller = null;
        slot.ClientId = null;
        slot.ResumeToken = null;
        slot.LastAcceptedInput = default;
        slot.LeaseExpiresAt = null;
        slot.State = LobbySlotState.Free;
        InvalidateSession(slot);
    }

    private IEnumerable<Slot> ActiveSlots() => _slots.Where(slot => slot.State is LobbySlotState.Active or LobbySlotState.InputTimedOut);

    private SessionCredentials CreateCredentials()
    {
        ulong sessionId;
        do
        {
            sessionId = BinaryPrimitives.ReadUInt64LittleEndian(RandomNumberGenerator.GetBytes(sizeof(ulong)));
        }
        while (sessionId == 0 || _slots.Any(slot => slot.State != LobbySlotState.Free && slot.SessionId == sessionId));

        return new SessionCredentials(sessionId, RandomNumberGenerator.GetBytes(16), RandomNumberGenerator.GetBytes(32));
    }

    private sealed class Slot(int number)
    {
        public int Number { get; } = number;
        public LobbySlotState State { get; set; }
        public VirtualController? Controller { get; set; }
        public string? ClientId { get; set; }
        public ulong SessionId { get; set; }
        public byte[]? UdpToken { get; set; }
        public byte[]? ResumeToken { get; set; }
        public uint? LastSequence { get; set; }
        public DateTimeOffset LastAcceptedInput { get; set; }
        public DateTimeOffset? LeaseExpiresAt { get; set; }
    }
}
