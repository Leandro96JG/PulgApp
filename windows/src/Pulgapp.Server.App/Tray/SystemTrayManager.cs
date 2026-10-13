using System.Drawing;
using System.Windows.Forms;

namespace Pulgapp.Server.App.Tray;

public sealed class SystemTrayManager : IDisposable
{
    private readonly NotifyIcon _notifyIcon;
    private readonly ToolStripMenuItem _statusMenuItem;
    private bool _disposed;

    public SystemTrayManager(Action onOpenRequested, Action onExitRequested)
    {
        var contextMenu = new ContextMenuStrip();

        var openMenuItem = new ToolStripMenuItem("Open Pulgapp", null, (s, e) => onOpenRequested())
        {
            Font = new Font(Control.DefaultFont, System.Drawing.FontStyle.Bold)
        };
        contextMenu.Items.Add(openMenuItem);

        contextMenu.Items.Add(new ToolStripSeparator());

        _statusMenuItem = new ToolStripMenuItem("Status: Stopped")
        {
            Enabled = false
        };
        contextMenu.Items.Add(_statusMenuItem);

        contextMenu.Items.Add(new ToolStripSeparator());

        var exitMenuItem = new ToolStripMenuItem("Exit", null, (s, e) => onExitRequested());
        contextMenu.Items.Add(exitMenuItem);

        Icon? icon = null;
        try
        {
            if (!string.IsNullOrEmpty(Environment.ProcessPath))
            {
                icon = Icon.ExtractAssociatedIcon(Environment.ProcessPath);
            }
        }
        catch
        {
            // Fall back
        }

        icon ??= SystemIcons.Application;

        _notifyIcon = new NotifyIcon
        {
            Text = "Pulgapp Server",
            Icon = icon,
            ContextMenuStrip = contextMenu,
            Visible = true
        };

        _notifyIcon.DoubleClick += (s, e) => onOpenRequested();
    }

    public void UpdateStatus(string statusText)
    {
        if (_disposed) return;
        _statusMenuItem.Text = $"Status: {statusText}";
        var tooltip = $"Pulgapp - {statusText}";
        if (tooltip.Length > 63)
        {
            tooltip = tooltip[..63];
        }
        _notifyIcon.Text = tooltip;
    }

    public void ShowNotification(string title, string message)
    {
        if (_disposed) return;
        _notifyIcon.ShowBalloonTip(2000, title, message, ToolTipIcon.Info);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _notifyIcon.Visible = false;
        _notifyIcon.ContextMenuStrip?.Dispose();
        _notifyIcon.Dispose();
    }
}
