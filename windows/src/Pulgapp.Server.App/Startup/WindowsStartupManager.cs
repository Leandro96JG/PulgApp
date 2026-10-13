using Microsoft.Win32;

namespace Pulgapp.Server.App.Startup;

public static class WindowsStartupManager
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string AppName = "Pulgapp";

    public static bool IsStartupEnabled()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: false);
            return key?.GetValue(AppName) is not null;
        }
        catch
        {
            return false;
        }
    }

    public static void SetStartup(bool enable, bool startMinimized = true)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: true);
            if (key is null)
            {
                return;
            }

            if (enable)
            {
                var processPath = Environment.ProcessPath;
                if (string.IsNullOrWhiteSpace(processPath))
                {
                    return;
                }

                var argument = startMinimized ? " --minimized" : string.Empty;
                var command = $"\"{processPath}\"{argument}";
                key.SetValue(AppName, command);
            }
            else
            {
                key.DeleteValue(AppName, throwOnMissingValue: false);
            }
        }
        catch
        {
            // Do not crash on restricted environments
        }
    }
}
