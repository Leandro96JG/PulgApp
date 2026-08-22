using System.ComponentModel;
using System.Net;
using System.Net.NetworkInformation;
using System.Windows;
using System.Windows.Threading;
using Pulgapp.Server.Core;
using Pulgapp.Server.Infrastructure;

namespace Pulgapp.Server.App;

public partial class MainWindow : Window
{
    private readonly DispatcherTimer _refreshTimer;
    private PulgappServer? _server;
    private X360VirtualControllerFactory? _controllerFactory;
    private string _driverStatus = "Not checked";
    private bool _isClosing;

    public MainWindow()
    {
        InitializeComponent();
        AddressesText.Text = string.Join(Environment.NewLine, GetCandidateIpv4Addresses());
        _refreshTimer = new DispatcherTimer(TimeSpan.FromMilliseconds(500), DispatcherPriority.Background, RefreshDashboard, Dispatcher);
        _refreshTimer.Start();
        RefreshDashboard(this, EventArgs.Empty);
    }

    private async void StartButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            _controllerFactory = new X360VirtualControllerFactory();
            _driverStatus = "Available";
            var coordinator = new SessionCoordinator(_controllerFactory, TimeProvider.System);
            _server = new PulgappServer(new PulgappServerOptions(), coordinator);
            await _server.StartAsync();
        }
        catch (Exception exception)
        {
            _server = null;
            _controllerFactory?.Dispose();
            _controllerFactory = null;
            _driverStatus = "Unavailable";
            MessageBox.Show(this, exception.Message, "Could not start Pulgapp", MessageBoxButton.OK, MessageBoxImage.Error);
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

    private async void KickButton_Click(object sender, RoutedEventArgs e)
    {
        if (_server is not null)
        {
            await _server.KickAsync();
        }

        await RefreshDashboardAsync();
    }

    private async void RefreshDashboard(object? sender, EventArgs e) => await RefreshDashboardAsync();

    private async Task RefreshDashboardAsync()
    {
        var status = _server is null ? null : await _server.GetStatusAsync();
        ServerStatusText.Text = status?.ConnectionState ?? "Stopped";
        DriverStatusText.Text = _driverStatus;
        PortsText.Text = status is null ? "TCP 26760 / UDP 26761" : $"TCP {status.TcpPort} / UDP {status.UdpPort}";
        PinText.Text = status?.Pin ?? "Start the server to generate a PIN";
        ClientNameText.Text = status?.ClientName ?? "No client connected";
        ConnectionStateText.Text = status?.ConnectionState ?? "Stopped";
        LastInputAgeText.Text = status?.LastInputAge is { } age ? $"{age.TotalMilliseconds:0} ms" : "-";
        MetricsText.Text = status is null ? "0 packets/s / -" : $"{status.PacketRate:0.0} packets/s / {status.Rtt}";
        StartButton.IsEnabled = status is null;
        StopButton.IsEnabled = status is not null;
        RegeneratePinButton.IsEnabled = status is not null;
        KickButton.IsEnabled = status?.ClientName is not null;
    }

    private async void Window_Closing(object? sender, CancelEventArgs e)
    {
        if (_isClosing)
        {
            return;
        }

        e.Cancel = true;
        _isClosing = true;
        _refreshTimer.Stop();
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
            .DefaultIfEmpty("No active LAN IPv4 address found.");
}
