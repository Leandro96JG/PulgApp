using System.IO;
using System.IO.Pipes;

namespace Pulgapp.Server.App.SingleInstance;

public static class SingleInstanceManager
{
    private const string MutexName = "Pulgapp_Server_SingleInstance_Mutex";
    private const string PipeName = "Pulgapp_Server_Activation_Pipe";

    public static bool TryAcquire(Action onActivateRequested, out IDisposable? registration)
    {
        registration = null;
        Mutex? mutex = null;
        var createdNew = false;

        try
        {
            mutex = new Mutex(initiallyOwned: true, MutexName, out createdNew);
        }
        catch
        {
            // If mutex creation fails, assume first instance
            createdNew = true;
        }

        if (!createdNew)
        {
            mutex?.Dispose();
            // Signal the existing instance to activate
            SignalExistingInstance();
            return false;
        }

        var instanceHolder = new SingleInstanceHolder(mutex, onActivateRequested);
        instanceHolder.StartPipeServer();
        registration = instanceHolder;
        return true;
    }

    private static void SignalExistingInstance()
    {
        try
        {
            using var client = new NamedPipeClientStream(".", PipeName, PipeDirection.Out);
            client.Connect(1000);
            using var writer = new StreamWriter(client);
            writer.WriteLine("activate");
            writer.Flush();
        }
        catch
        {
            // Transient connection failure if existing instance is terminating
        }
    }

    private sealed class SingleInstanceHolder : IDisposable
    {
        private readonly Mutex? _mutex;
        private readonly Action _onActivateRequested;
        private readonly CancellationTokenSource _cts = new();
        private bool _disposed;

        public SingleInstanceHolder(Mutex? mutex, Action onActivateRequested)
        {
            _mutex = mutex;
            _onActivateRequested = onActivateRequested;
        }

        public void StartPipeServer()
        {
            Task.Run(async () =>
            {
                while (!_cts.IsCancellationRequested)
                {
                    try
                    {
                        NamedPipeServerStream? server = null;
                        try
                        {
                            server = new NamedPipeServerStream(
                                PipeName,
                                PipeDirection.In,
                                1,
                                PipeTransmissionMode.Byte,
                                PipeOptions.Asynchronous);

                            await server.WaitForConnectionAsync(_cts.Token);
                            using var reader = new StreamReader(server);
                            var message = await reader.ReadLineAsync(_cts.Token);
                            if (string.Equals(message, "activate", StringComparison.OrdinalIgnoreCase))
                            {
                                _onActivateRequested();
                            }
                        }
                        finally
                        {
                            if (server is not null)
                            {
                                await server.DisposeAsync();
                            }
                        }
                    }
                    catch (OperationCanceledException)
                    {
                        break;
                    }
                    catch
                    {
                        // Small delay before retrying pipe server
                        try
                        {
                            await Task.Delay(100, _cts.Token);
                        }
                        catch (OperationCanceledException)
                        {
                            break;
                        }
                    }
                }
            });
        }

        public void Dispose()
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            _cts.Cancel();
            _cts.Dispose();

            if (_mutex is not null)
            {
                try
                {
                    _mutex.ReleaseMutex();
                }
                catch
                {
                    // Mutex might not be owned if abnormal termination
                }

                _mutex.Dispose();
            }
        }
    }
}
