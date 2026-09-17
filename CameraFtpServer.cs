using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Collections.Generic;
using System.Collections.Concurrent;

namespace GrandStores.Camera
{
    public class CameraFileReceivedEventArgs : EventArgs
    {
        public string FilePath { get; set; }
        public string FileName { get; set; }
        public long FileSize { get; set; }
        public DateTime Timestamp { get; set; }
    }

    public class CameraFtpServer : IDisposable
    {
        private TcpListener _listener;
        private bool _isRunning;
        private int _port;
        private string _targetFolder;
        private Thread _listenThread;
        private readonly ConcurrentQueue<CameraFileReceivedEventArgs> _recentFiles = new ConcurrentQueue<CameraFileReceivedEventArgs>();
        private int _totalReceived = 0;
        private string _lastFileName = "";
        private DateTime _lastFileTime = DateTime.MinValue;
        private int _connectedClients = 0;

        public event EventHandler<CameraFileReceivedEventArgs> FileReceived;

        public bool IsRunning { get { return _isRunning; } }
        public int Port { get { return _port; } }
        public string TargetFolder { get { return _targetFolder; } }
        public int TotalReceived { get { return _totalReceived; } }
        public string LastFileName { get { return _lastFileName; } }
        public DateTime LastFileTime { get { return _lastFileTime; } }
        public int ConnectedClients { get { return _connectedClients; } }

        public CameraFtpServer(string targetFolder, int port)
        {
            _targetFolder = string.IsNullOrEmpty(targetFolder) ? Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Camera_Incoming") : targetFolder;
            _port = (port > 0) ? port : 2121;
        }

        public CameraFtpServer(string targetFolder) : this(targetFolder, 2121)
        {
        }

        public void SetTargetFolder(string folder)
        {
            if (!string.IsNullOrEmpty(folder))
            {
                if (!Directory.Exists(folder))
                {
                    try { Directory.CreateDirectory(folder); } catch { }
                }
                _targetFolder = folder;
            }
        }

        public bool Start()
        {
            if (_isRunning) return true;

            try
            {
                if (!Directory.Exists(_targetFolder))
                {
                    Directory.CreateDirectory(_targetFolder);
                }

                _listener = new TcpListener(IPAddress.Any, _port);
                _listener.Start();
                _isRunning = true;

                _listenThread = new Thread(ListenLoop);
                _listenThread.IsBackground = true;
                _listenThread.Name = "CameraFtpListener";
                _listenThread.Start();
                return true;
            }
            catch (Exception ex)
            {
                Console.WriteLine("[Camera FTP] Failed to start: " + ex.Message);
                _isRunning = false;
                return false;
            }
        }

        public void Stop()
        {
            _isRunning = false;
            try
            {
                if (_listener != null)
                {
                    _listener.Stop();
                }
            }
            catch { }
        }

        private void ListenLoop()
        {
            while (_isRunning)
            {
                try
                {
                    TcpClient client = _listener.AcceptTcpClient();
                    Interlocked.Increment(ref _connectedClients);
                    ThreadPool.QueueUserWorkItem(HandleClient, client);
                }
                catch
                {
                    if (!_isRunning) break;
                }
            }
        }

        private void HandleClient(object state)
        {
            TcpClient client = (TcpClient)state;
            client.NoDelay = true;

            try
            {
                using (NetworkStream stream = client.GetStream())
                using (StreamReader reader = new StreamReader(stream, Encoding.ASCII))
                using (StreamWriter writer = new StreamWriter(stream, Encoding.ASCII))
                {
                    writer.AutoFlush = true;
                    writer.WriteLine("220 GrandStores Camera Ingest Server Ready");

                    string user = "";
                    string currentDir = "/";
                    TcpListener pasvListener = null;
                    IPEndPoint activeDataEp = null;

                    string line;
                    while (_isRunning && (line = reader.ReadLine()) != null)
                    {
                        line = line.Trim();
                        if (string.IsNullOrEmpty(line)) continue;

                        string cmd = line;
                        string arg = "";
                        int spaceIdx = line.IndexOf(' ');
                        if (spaceIdx > 0)
                        {
                            cmd = line.Substring(0, spaceIdx).ToUpperInvariant();
                            arg = line.Substring(spaceIdx + 1).Trim();
                        }
                        else
                        {
                            cmd = cmd.ToUpperInvariant();
                        }

                        switch (cmd)
                        {
                            case "USER":
                                user = arg;
                                writer.WriteLine("331 Password required for " + user);
                                break;

                            case "PASS":
                                writer.WriteLine("230 User logged in, proceed.");
                                break;

                            case "SYST":
                                writer.WriteLine("215 UNIX Type: L8");
                                break;

                            case "FEAT":
                                writer.WriteLine("211-Features:");
                                writer.WriteLine(" PASV");
                                writer.WriteLine(" EPSV");
                                writer.WriteLine(" UTF8");
                                writer.WriteLine(" SIZE");
                                writer.WriteLine("211 End");
                                break;

                            case "PWD":
                            case "XPWD":
                                writer.WriteLine("257 \"" + currentDir + "\" is current directory");
                                break;

                            case "CWD":
                            case "XCWD":
                                if (string.IsNullOrEmpty(arg) || arg == "/" || arg == ".")
                                    currentDir = "/";
                                else
                                    currentDir = "/" + arg.TrimStart('/');
                                writer.WriteLine("250 Directory successfully changed.");
                                break;

                            case "CDUP":
                            case "XCUP":
                                currentDir = "/";
                                writer.WriteLine("250 Directory changed to /");
                                break;

                            case "TYPE":
                                writer.WriteLine("200 Type set to " + arg);
                                break;

                            case "PASV":
                                {
                                    if (pasvListener != null)
                                    {
                                        try { pasvListener.Stop(); } catch { }
                                    }
                                    pasvListener = new TcpListener(IPAddress.Any, 0);
                                    pasvListener.Start();
                                    int pasvPort = ((IPEndPoint)pasvListener.LocalEndpoint).Port;

                                    IPAddress localIp = ((IPEndPoint)client.Client.LocalEndPoint).Address;
                                    if (localIp.Equals(IPAddress.Any) || localIp.Equals(IPAddress.IPv6Any) || localIp.Equals(IPAddress.Loopback))
                                    {
                                        localIp = GetPrimaryLocalIP();
                                    }

                                    byte[] ipBytes = localIp.GetAddressBytes();
                                    int p1 = pasvPort / 256;
                                    int p2 = pasvPort % 256;
                                    writer.WriteLine(string.Format("227 Entering Passive Mode ({0},{1},{2},{3},{4},{5})",
                                        ipBytes[0], ipBytes[1], ipBytes[2], ipBytes[3], p1, p2));
                                    break;
                                }

                            case "EPSV":
                                {
                                    if (pasvListener != null)
                                    {
                                        try { pasvListener.Stop(); } catch { }
                                    }
                                    pasvListener = new TcpListener(IPAddress.Any, 0);
                                    pasvListener.Start();
                                    int epsvPort = ((IPEndPoint)pasvListener.LocalEndpoint).Port;
                                    writer.WriteLine(string.Format("229 Entering Extended Passive Mode (|||{0}|)", epsvPort));
                                    break;
                                }

                            case "PORT":
                                {
                                    // Active mode data connection
                                    string[] parts = arg.Split(',');
                                    if (parts.Length == 6)
                                    {
                                        string ip = string.Format("{0}.{1}.{2}.{3}", parts[0], parts[1], parts[2], parts[3]);
                                        int p = (int.Parse(parts[4]) << 8) + int.Parse(parts[5]);
                                        activeDataEp = new IPEndPoint(IPAddress.Parse(ip), p);
                                        writer.WriteLine("200 PORT command successful.");
                                    }
                                    else
                                    {
                                        writer.WriteLine("501 Syntax error in parameters.");
                                    }
                                    break;
                                }

                            case "STOR":
                                {
                                    string rawFileName = Path.GetFileName(arg.Replace('/', '\\'));
                                    if (string.IsNullOrEmpty(rawFileName))
                                    {
                                        rawFileName = string.Format("PHOTO_{0:yyyyMMdd_HHmmss}.JPG", DateTime.Now);
                                    }

                                    string savePath = Path.Combine(_targetFolder, rawFileName);

                                    // If file exists, add timestamp suffix to avoid overwrite
                                    if (File.Exists(savePath))
                                    {
                                        string stem = Path.GetFileNameWithoutExtension(rawFileName);
                                        string ext = Path.GetExtension(rawFileName);
                                        savePath = Path.Combine(_targetFolder, string.Format("{0}_{1:HHmmssfff}{2}", stem, DateTime.Now, ext));
                                    }

                                    writer.WriteLine("150 Opening binary data connection for " + rawFileName);

                                    long bytesReadTotal = 0;
                                    TcpClient dataClient = null;

                                    try
                                    {
                                        if (pasvListener != null)
                                        {
                                            dataClient = pasvListener.AcceptTcpClient();
                                        }
                                        else if (activeDataEp != null)
                                        {
                                            dataClient = new TcpClient();
                                            dataClient.Connect(activeDataEp);
                                        }

                                        if (dataClient != null)
                                        {
                                            using (dataClient)
                                            using (NetworkStream dataStream = dataClient.GetStream())
                                            using (FileStream fs = new FileStream(savePath, FileMode.Create, FileAccess.Write, FileShare.ReadWrite))
                                            {
                                                byte[] buffer = new byte[65536];
                                                int count;
                                                while ((count = dataStream.Read(buffer, 0, buffer.Length)) > 0)
                                                {
                                                    fs.Write(buffer, 0, count);
                                                    bytesReadTotal += count;
                                                }
                                                fs.Flush();
                                            }

                                            writer.WriteLine("226 Transfer complete. File successfully saved.");

                                            CameraFileReceivedEventArgs ev = new CameraFileReceivedEventArgs();
                                            ev.FilePath = savePath;
                                            ev.FileName = Path.GetFileName(savePath);
                                            ev.FileSize = bytesReadTotal;
                                            ev.Timestamp = DateTime.Now;

                                            _recentFiles.Enqueue(ev);
                                            CameraFileReceivedEventArgs dummy;
                                            while (_recentFiles.Count > 100) { _recentFiles.TryDequeue(out dummy); }

                                            Interlocked.Increment(ref _totalReceived);
                                            _lastFileName = Path.GetFileName(savePath);
                                            _lastFileTime = DateTime.Now;

                                            try
                                            {
                                                if (FileReceived != null)
                                                {
                                                    FileReceived(this, ev);
                                                }
                                            }
                                            catch { }
                                        }
                                        else
                                        {
                                            writer.WriteLine("425 Can't open data connection.");
                                        }
                                    }
                                    catch (Exception ex)
                                    {
                                        writer.WriteLine("451 Requested action aborted: " + ex.Message);
                                    }
                                    finally
                                    {
                                        if (pasvListener != null)
                                        {
                                            try { pasvListener.Stop(); } catch { }
                                            pasvListener = null;
                                        }
                                    }
                                    break;
                                }

                            case "NOOP":
                                writer.WriteLine("200 NOOP ok.");
                                break;

                            case "QUIT":
                                writer.WriteLine("221 Service closing control connection.");
                                return;

                            default:
                                writer.WriteLine("502 Command not implemented.");
                                break;
                        }
                    }
                }
            }
            catch
            {
                // Client disconnect
            }
            finally
            {
                Interlocked.Decrement(ref _connectedClients);
                try { client.Close(); } catch { }
            }
        }

        public List<CameraFileReceivedEventArgs> GetRecentFiles(int limit)
        {
            List<CameraFileReceivedEventArgs> list = new List<CameraFileReceivedEventArgs>(_recentFiles);
            if (list.Count > limit)
            {
                return list.GetRange(list.Count - limit, limit);
            }
            return list;
        }

        public static IPAddress GetPrimaryLocalIP()
        {
            try
            {
                using (Socket socket = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, 0))
                {
                    socket.Connect("8.8.8.8", 65530);
                    IPEndPoint endPoint = socket.LocalEndPoint as IPEndPoint;
                    if (endPoint != null) return endPoint.Address;
                }
            }
            catch { }

            foreach (IPAddress ip in Dns.GetHostAddresses(Dns.GetHostName()))
            {
                if (ip.AddressFamily == AddressFamily.InterNetwork && !IPAddress.IsLoopback(ip))
                {
                    return ip;
                }
            }
            return IPAddress.Loopback;
        }

        public void Dispose()
        {
            Stop();
        }
    }
}
