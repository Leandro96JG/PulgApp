using System.ComponentModel;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Pulgapp.Server.App.Settings;
using Pulgapp.Server.App.Startup;
using Pulgapp.Server.App.Tray;
using Pulgapp.Server.Core;
using Pulgapp.Server.Infrastructure;
using Pulgapp.Server.Protocol;
using QRCoder;
using Brush = System.Windows.Media.Brush;
using Color = System.Windows.Media.Color;

namespace Pulgapp.Server.App;

public partial class MainWindow : Window
{
    private readonly DispatcherTimer _refreshTimer;
    private readonly AppSettings _settings;
    private readonly SystemTrayManager _trayManager;
    private PulgappServer? _server;
    private X360VirtualControllerFactory? _controllerFactory;
    private string _driverStatus = "No verificado";
    private bool _isClosing;
    private bool _isExplicitExit;
    private string? _lastQrPin;
    private string? _lastQrIp;
    private string? _lastGeneratedUri;

    public MainWindow(bool startMinimized = false)
    {
        InitializeComponent();

        _settings = SettingsManager.Load();
        StartWithWindowsCheckBox.IsChecked = _settings.StartWithWindows;
        MinimizeToTrayCheckBox.IsChecked = _settings.MinimizeToTrayOnClose;
        AutoStartServerCheckBox.IsChecked = _settings.AutoStartServer;

        _trayManager = new SystemTrayManager(
            onOpenRequested: () => Dispatcher.Invoke(RestoreFromTray),
            onExitRequested: () => Dispatcher.Invoke(ExitApplication));

        var ips = GetCandidateIpv4Addresses().ToList();
        AddressesText.Text = string.Join(" • ", ips);
        IpSelectorComboBox.ItemsSource = ips;
        if (ips.Count > 0)
        {
            IpSelectorComboBox.SelectedIndex = 0;
        }

        _refreshTimer = new DispatcherTimer(TimeSpan.FromMilliseconds(500), DispatcherPriority.Background, RefreshDashboard, Dispatcher);
        _refreshTimer.Start();
        RefreshDashboard(this, EventArgs.Empty);

        if (startMinimized)
        {
            WindowState = WindowState.Minimized;
            Hide();
        }

        if (_settings.AutoStartServer || startMinimized)
        {
            _ = StartServerCoreAsync();
        }
    }

    public void RestoreFromTray()
    {
        Show();
        if (WindowState == WindowState.Minimized)
        {
            WindowState = WindowState.Normal;
        }
        Activate();
        Focus();
    }

    private void ExitApplication()
    {
        _isExplicitExit = true;
        Close();
    }

    private async void StartButton_Click(object sender, RoutedEventArgs e)
    {
        await StartServerCoreAsync();
    }

    private async Task StartServerCoreAsync()
    {
        if (_server is not null)
        {
            return;
        }

        try
        {
            _controllerFactory = new X360VirtualControllerFactory();
            _driverStatus = "Disponible";
            var coordinator = new SessionCoordinator(_controllerFactory, TimeProvider.System);
            _server = new PulgappServer(new PulgappServerOptions(), coordinator);
            await _server.StartAsync();
        }
        catch (Exception exception)
        {
            _server = null;
            _controllerFactory?.Dispose();
            _controllerFactory = null;
            _driverStatus = "No disponible";
            if (IsVisible)
            {
                System.Windows.MessageBox.Show(this, exception.Message, "Error al iniciar Pulgapp", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        await RefreshDashboardAsync();
    }

    private async void StopButton_Click(object sender, RoutedEventArgs e)
    {
        await StopServerAsync();
    }

    private async void RegeneratePinButton_Click(object sender, RoutedEventArgs e)
    {
        if (_server is not null)
        {
            await _server.RegeneratePinAsync();
        }

        await RefreshDashboardAsync();
    }

    private async void KickSlotButton_Click(object sender, RoutedEventArgs e)
    {
        if (_server is not null && sender is FrameworkElement { Tag: int slot })
        {
            await _server.KickAsync(slot);
        }

        await RefreshDashboardAsync();
    }

    private async void RefreshDashboard(object? sender, EventArgs e) => await RefreshDashboardAsync();

    private async Task RefreshDashboardAsync()
    {
        var status = _server is null ? null : await _server.GetStatusAsync();
        var isOnline = status is not null;

        HeaderStatusText.Text = isOnline ? "ONLINE" : "OFFLINE";
        HeaderStatusBadge.Background = new SolidColorBrush(isOnline ? Color.FromRgb(0x16, 0x38, 0x24) : Color.FromRgb(0x28, 0x2C, 0x36));
        HeaderStatusBadge.BorderBrush = new SolidColorBrush(isOnline ? Color.FromRgb(0x4A, 0xDE, 0x80) : Color.FromRgb(0x64, 0x74, 0x8B));
        HeaderStatusDot.Fill = new SolidColorBrush(isOnline ? Color.FromRgb(0x4A, 0xDE, 0x80) : Color.FromRgb(0x64, 0x74, 0x8B));
        HeaderStatusText.Foreground = new SolidColorBrush(isOnline ? Color.FromRgb(0x4A, 0xDE, 0x80) : Color.FromRgb(0x94, 0xA3, 0xB8));

        DriverStatusText.Text = _driverStatus;
        DriverStatusText.Foreground = new SolidColorBrush(_driverStatus == "Disponible" ? Color.FromRgb(0x4A, 0xDE, 0x80) : Color.FromRgb(0xF8, 0x71, 0x71));

        PortsText.Text = status is null ? "TCP 26760 • UDP 26761" : $"TCP {status.TcpPort} • UDP {status.UdpPort}";
        PinText.Text = status?.Pin ?? "------";

        var activeSlotsCount = status?.Slots.Count(s => s.ConnectionState.Equals("Connected", StringComparison.OrdinalIgnoreCase)) ?? 0;
        ActivePlayersCounterText.Text = $"{activeSlotsCount} / 8 jugadores";

        SlotsItemsControl.ItemsSource = status?.Slots.Select(slot => new SlotDashboardRow(slot)).ToArray() ?? [];
        StartButton.IsEnabled = status is null;
        StopButton.IsEnabled = status is not null;
        RegeneratePinButton.IsEnabled = status is not null;

        _trayManager.UpdateStatus(isOnline ? $"En ejecución ({activeSlotsCount}/8)" : "Detenido");

        UpdateQrCode(status);
    }

    private void UpdateQrCode(PulgappServerStatus? status)
    {
        if (status?.Pin is not { } pin || IpSelectorComboBox.SelectedItem is not string selectedIp ||
            string.IsNullOrWhiteSpace(selectedIp) || selectedIp.Contains("No active", StringComparison.OrdinalIgnoreCase))
        {
            QrCodeImage.Source = null;
            QrCodeImage.Visibility = Visibility.Collapsed;
            QrPlaceholderText.Visibility = Visibility.Visible;
            _lastQrPin = null;
            _lastQrIp = null;
            _lastGeneratedUri = null;
            return;
        }

        if (pin == _lastQrPin && selectedIp == _lastQrIp && QrCodeImage.Source is not null)
        {
            return;
        }

        _lastQrPin = pin;
        _lastQrIp = selectedIp;

        try
        {
            _lastGeneratedUri = QrPairingPayload.Format(selectedIp, status.TcpPort, pin);
            using var qrGenerator = new QRCodeGenerator();
            using var qrCodeData = qrGenerator.CreateQrCode(_lastGeneratedUri, QRCodeGenerator.ECCLevel.M);
            using var qrCode = new PngByteQRCode(qrCodeData);
            var qrCodeBytes = qrCode.GetGraphic(20);

            using var ms = new MemoryStream(qrCodeBytes);
            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.StreamSource = ms;
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.EndInit();
            bitmap.Freeze();

            QrCodeImage.Source = bitmap;
            QrCodeImage.Visibility = Visibility.Visible;
            QrPlaceholderText.Visibility = Visibility.Collapsed;
        }
        catch
        {
            QrCodeImage.Source = null;
            QrCodeImage.Visibility = Visibility.Collapsed;
            QrPlaceholderText.Visibility = Visibility.Visible;
            _lastGeneratedUri = null;
        }
    }

    private void CopyPin_Click(object sender, RoutedEventArgs e)
    {
        if (!string.IsNullOrWhiteSpace(PinText.Text) && PinText.Text != "------")
        {
            System.Windows.Clipboard.SetText(PinText.Text);
            ShowCopyFeedback(CopyPinButton, "¡Copiado!");
        }
    }

    private void CopyUri_Click(object sender, RoutedEventArgs e)
    {
        if (!string.IsNullOrWhiteSpace(_lastGeneratedUri))
        {
            System.Windows.Clipboard.SetText(_lastGeneratedUri);
            ShowCopyFeedback(CopyUriButton, "¡Copiado!");
        }
    }

    private static void ShowCopyFeedback(System.Windows.Controls.Button button, string feedbackText)
    {
        var originalContent = button.Content;
        button.Content = feedbackText;
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
        timer.Tick += (s, ev) =>
        {
            button.Content = originalContent;
            timer.Stop();
        };
        timer.Start();
    }

    private void IpSelectorComboBox_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
    {
        _lastQrIp = null;
        _ = RefreshDashboardAsync();
    }

    private void StartWithWindows_Changed(object sender, RoutedEventArgs e)
    {
        _settings.StartWithWindows = StartWithWindowsCheckBox.IsChecked == true;
        WindowsStartupManager.SetStartup(_settings.StartWithWindows, _settings.StartMinimized);
        SettingsManager.Save(_settings);
    }

    private void MinimizeToTray_Changed(object sender, RoutedEventArgs e)
    {
        _settings.MinimizeToTrayOnClose = MinimizeToTrayCheckBox.IsChecked == true;
        SettingsManager.Save(_settings);
    }

    private void AutoStartServer_Changed(object sender, RoutedEventArgs e)
    {
        _settings.AutoStartServer = AutoStartServerCheckBox.IsChecked == true;
        SettingsManager.Save(_settings);
    }

    private void Window_StateChanged(object? sender, EventArgs e)
    {
        if (WindowState == WindowState.Minimized && _settings.MinimizeToTrayOnClose)
        {
            Hide();
        }
    }

    private async void Window_Closing(object? sender, CancelEventArgs e)
    {
        if (_isClosing)
        {
            return;
        }

        if (!_isExplicitExit && _settings.MinimizeToTrayOnClose)
        {
            e.Cancel = true;
            Hide();
            _trayManager.ShowNotification("Pulgapp", "Pulgapp continúa ejecutándose en la bandeja del sistema. Clic derecho para salir.");
            return;
        }

        e.Cancel = true;
        _isClosing = true;
        _refreshTimer.Stop();
        _trayManager.Dispose();
        await StopServerAsync();
        Close();
    }

    private async Task StopServerAsync()
    {
        if (_server is not null)
        {
            await _server.DisposeAsync();
            _server = null;
        }

        _controllerFactory?.Dispose();
        _controllerFactory = null;
        await RefreshDashboardAsync();
    }

    private static IEnumerable<string> GetCandidateIpv4Addresses() =>
        NetworkInterface.GetAllNetworkInterfaces()
            .Where(networkInterface => networkInterface.OperationalStatus == OperationalStatus.Up && networkInterface.NetworkInterfaceType != NetworkInterfaceType.Loopback)
            .SelectMany(networkInterface => networkInterface.GetIPProperties().UnicastAddresses)
            .Select(address => address.Address)
            .Where(address => address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork && !IPAddress.IsLoopback(address))
            .Select(address => address.ToString())
            .Distinct(StringComparer.Ordinal)
            .DefaultIfEmpty("No se encontró dirección LAN IPv4.");

    private sealed record SlotDashboardRow(PulgappSlotStatus Status)
    {
        public int SlotNumber => Status.Slot;
        public bool IsXbox => Status.Slot <= 4;
        public bool IsDs4 => Status.Slot > 4;

        public string PlayerBadge => $"P{Status.Slot} • {(IsXbox ? "X360" : "DS4")}";

        public Brush BadgeBackground => IsXbox
            ? new SolidColorBrush(Color.FromRgb(0x13, 0x36, 0x1F))
            : new SolidColorBrush(Color.FromRgb(0x10, 0x2A, 0x46));

        public Brush BadgeForeground => IsXbox
            ? new SolidColorBrush(Color.FromRgb(0x4A, 0xDE, 0x80))
            : new SolidColorBrush(Color.FromRgb(0x38, 0xBD, 0xF8));

        public bool IsConnected => string.Equals(Status.ConnectionState, "Connected", StringComparison.OrdinalIgnoreCase);
        public bool IsLeased => string.Equals(Status.ConnectionState, "Leased", StringComparison.OrdinalIgnoreCase);

        public string ClientNameDisplay => IsConnected || IsLeased
            ? Status.ClientName
            : "Ranura disponible";

        public string IpAddressDisplay => IsConnected || IsLeased
            ? Status.SourceIpAddress
            : "Esperando conexión...";

        public Brush ClientForeground => IsConnected
            ? new SolidColorBrush(Color.FromRgb(0xF8, 0xFA, 0xFC))
            : new SolidColorBrush(Color.FromRgb(0x64, 0x74, 0x8B));

        public string ConnectionStateDisplay => IsConnected
            ? "Conectado"
            : (IsLeased ? "En espera" : "Libre");

        public Brush StatusBackground => IsConnected
            ? new SolidColorBrush(Color.FromRgb(0x13, 0x38, 0x20))
            : (IsLeased
                ? new SolidColorBrush(Color.FromRgb(0x3A, 0x2A, 0x10))
                : new SolidColorBrush(Color.FromRgb(0x1A, 0x1F, 0x29)));

        public Brush StatusBorder => IsConnected
            ? new SolidColorBrush(Color.FromRgb(0x22, 0xC5, 0x5E))
            : (IsLeased
                ? new SolidColorBrush(Color.FromRgb(0xF5, 0x9E, 0x0B))
                : new SolidColorBrush(Color.FromRgb(0x2D, 0x34, 0x45)));

        public Brush StatusForeground => IsConnected
            ? new SolidColorBrush(Color.FromRgb(0x4A, 0xDE, 0x80))
            : (IsLeased
                ? new SolidColorBrush(Color.FromRgb(0xFB, 0xBF, 0x24))
                : new SolidColorBrush(Color.FromRgb(0x64, 0x74, 0x8B)));

        public string MetricsDisplay => IsConnected
            ? $"{Status.PacketRate:0} Hz • {Status.Rtt} ms"
            : "-";

        public string XInputIndexDisplay => IsXbox
            ? $"XInput #{Status.XInputUserIndex}"
            : "DirectInput / HID";

        public Brush CardBackground => IsConnected
            ? new SolidColorBrush(Color.FromRgb(0x18, 0x22, 0x1D))
            : (IsLeased
                ? new SolidColorBrush(Color.FromRgb(0x22, 0x1E, 0x18))
                : new SolidColorBrush(Color.FromRgb(0x17, 0x1B, 0x24)));

        public Brush CardBorder => IsConnected
            ? new SolidColorBrush(Color.FromRgb(0x23, 0x45, 0x30))
            : (IsLeased
                ? new SolidColorBrush(Color.FromRgb(0x4A, 0x38, 0x1A))
                : new SolidColorBrush(Color.FromRgb(0x24, 0x2C, 0x3A)));

        public bool CanKick => Status.CanKick;
    }
}
