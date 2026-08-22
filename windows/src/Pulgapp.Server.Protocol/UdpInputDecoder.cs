using System.Buffers.Binary;

namespace Pulgapp.Server.Protocol;

public static class UdpInputDecoder
{
    public const int DatagramLength = 60;
    private const uint KnownButtonMask = 0x0000FFFF;
    private const uint DpadUp = (uint)CanonicalButtons.DpadUp;
    private const uint DpadDown = (uint)CanonicalButtons.DpadDown;
    private const uint DpadLeft = (uint)CanonicalButtons.DpadLeft;
    private const uint DpadRight = (uint)CanonicalButtons.DpadRight;

    public static bool TryDecode(ReadOnlySpan<byte> datagram, out InputSnapshot? snapshot)
    {
        snapshot = null;
        if (datagram.Length != DatagramLength ||
            datagram[0] != (byte)'P' || datagram[1] != (byte)'U' || datagram[2] != (byte)'L' || datagram[3] != (byte)'G' ||
            datagram[4] != 1 || datagram[5] != 1 ||
            BinaryPrimitives.ReadUInt16LittleEndian(datagram[6..8]) != 0)
        {
            return false;
        }

        var buttons = NormalizeButtons(BinaryPrimitives.ReadUInt32LittleEndian(datagram[44..48]));
        snapshot = new InputSnapshot(
            BinaryPrimitives.ReadUInt64LittleEndian(datagram[8..16]),
            datagram[16..32].ToArray(),
            BinaryPrimitives.ReadUInt32LittleEndian(datagram[32..36]),
            BinaryPrimitives.ReadUInt64LittleEndian(datagram[36..44]),
            (CanonicalButtons)buttons,
            BinaryPrimitives.ReadInt16LittleEndian(datagram[48..50]),
            BinaryPrimitives.ReadInt16LittleEndian(datagram[50..52]),
            BinaryPrimitives.ReadInt16LittleEndian(datagram[52..54]),
            BinaryPrimitives.ReadInt16LittleEndian(datagram[54..56]),
            BinaryPrimitives.ReadUInt16LittleEndian(datagram[56..58]),
            BinaryPrimitives.ReadUInt16LittleEndian(datagram[58..60]));
        return true;
    }

    public static bool IsNewerSequence(uint candidate, uint previous) => unchecked((int)(candidate - previous)) > 0;

    private static uint NormalizeButtons(uint buttons)
    {
        buttons &= KnownButtonMask;
        if ((buttons & (DpadUp | DpadDown)) == (DpadUp | DpadDown))
        {
            buttons &= ~(DpadUp | DpadDown);
        }

        if ((buttons & (DpadLeft | DpadRight)) == (DpadLeft | DpadRight))
        {
            buttons &= ~(DpadLeft | DpadRight);
        }

        return buttons;
    }
}
