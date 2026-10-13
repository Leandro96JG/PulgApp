namespace Pulgapp.Server.App.Settings;

public sealed class AppSettings
{
    public bool StartWithWindows { get; set; } = false;
    public bool StartMinimized { get; set; } = true;
    public bool MinimizeToTrayOnClose { get; set; } = true;
    public bool AutoStartServer { get; set; } = false;
}
