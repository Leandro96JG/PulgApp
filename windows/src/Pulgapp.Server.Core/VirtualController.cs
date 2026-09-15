namespace Pulgapp.Server.Core;

public enum ControllerKind
{
    X360,
    Ds4,
}

public interface VirtualController
{
    ControllerKind Kind { get; }

    void Connect();

    void Apply(GamepadState state);

    void Neutralize();

    void Disconnect();

    Action<byte, byte>? FeedbackReceived { get; set; }
}

public interface VirtualControllerFactory
{
    VirtualController Create(ControllerKind kind);
}
