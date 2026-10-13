using System.Windows;
using Pulgapp.Server.App.SingleInstance;

namespace Pulgapp.Server.App;

/// <summary>
/// Interaction logic for App.xaml
/// </summary>
public partial class App : System.Windows.Application
{
    private IDisposable? _singleInstanceRegistration;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        var isFirstInstance = SingleInstanceManager.TryAcquire(
            onActivateRequested: () =>
            {
                Dispatcher.Invoke(() =>
                {
                    if (MainWindow is MainWindow win)
                    {
                        win.RestoreFromTray();
                    }
                });
            },
            out _singleInstanceRegistration);

        if (!isFirstInstance)
        {
            Shutdown();
            return;
        }

        var startMinimized = e.Args.Any(arg =>
            arg.Equals("--minimized", StringComparison.OrdinalIgnoreCase) ||
            arg.Equals("--tray", StringComparison.OrdinalIgnoreCase));

        var mainWindow = new MainWindow(startMinimized);
        MainWindow = mainWindow;

        if (!startMinimized)
        {
            mainWindow.Show();
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _singleInstanceRegistration?.Dispose();
        _singleInstanceRegistration = null;
        base.OnExit(e);
    }
}
