/*
Summary:
    Host the local named-pipe endpoint for approved SelfX System actions.

Description:
    Installed by Install.ps1 as SelfXService running as LOCAL SYSTEM. Accepts local
    authenticated users through the default named pipe "SelfX.Service"; network clients
    are denied and users cannot create additional server instances through its ACL.
    PING returns PONG with the service protocol version. RUN accepts only a validated
    script filename listed with Context=System in the installed Issues_List.xml and
    present under the installed Scripts_to_run folder; user actions are not elevated.
    RUN children receive the SID of the requesting pipe client in SELFX_CALLER_SID, read
    from the client token (identification level), so scripts can deliver results only to
    that user. The variable is absent when the caller cannot be identified.
    HEALTH accepts no arguments and invokes only the installed HealthStatus.ps1 collector,
    returning bounded JSON as UTF-8/base64. It shares the repair lock and has a 240-second
    limit. Optional checks are configured in the administrator-protected Health_Config.xml.
    Every health run also updates the status cache ProgramData\SelfX\Cache\Health.json
    (readable by SYSTEM and administrators only). A background thread runs the full health
    collection at the interval of <Background> in Health_Config.xml (default every 15 minutes,
    first run 120 seconds after the start). It pauses on battery power, postpones while the
    processor load is above MaxCpuPercent or a repair is running, and runs PowerShell with
    below-normal priority. STATUS returns the cached result with its time, the interval and
    the background state without running anything, so the GUI and the tray icon show the
    status immediately.
    Starts non-interactive Windows PowerShell with the service identity and captures
    bounded output in ProgramData\SelfX\Logs by default, rotating SelfXService.log.
    Once a day (also while the background checks are disabled) the log housekeeping deletes
    *.log and *.old files in that folder that are older than Log_Retention_Days of
    Tool_Config.xml (1-3650, default 90). Subfolders such as Logs\Users are never cleaned by
    the service: users can create folders there, and SYSTEM must not follow links they could
    create (the users clean their own log folder, SelfXLog.ps1).
    Runs one action at a time; concurrent requests return BUSY. The default timeout is
    900 seconds, with positive catalog overrides (and TimeoutSeconds on a Health_Config
    Remediation) capped at 7200 seconds. A timeout
    attempts to kill the child process tree and returns TIMEOUT; completed actions
    return DONE with their exit code. ERROR reports request/authorization failures.
    Action side effects may include application closure, network/service interruption
    or disk-check scheduling; termination cannot undo completed changes. The service
    does not itself restart Windows. /console runs with the invoking user's rights;
    /pipe: and /logdir: override the endpoint and log location for troubleshooting.
    Program.Main returns 0 after normal service/console completion, not an action code.
    Compiled locally using the .NET Framework compiler (C# 5); no remote API is used.

Notes:
    Name    : SelfXService.cs
    Package : SelfX Service
    Context : System (LOCAL SYSTEM service; current user in /console mode)
    Version : 2.6.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.0.0    2026-10-28  Wolfgang Baeck       Initial version for SelfX Service
    2.2.0    2026-10-28  Wolfgang Baeck       Added description, history and comments
    2.3.0    2026-10-28  Wolfgang Baeck       Fixed HEALTH endpoint for protected local status checks
    2.3.1    2026-10-28  Wolfgang Baeck       Allow installed remediation scripts from protected health config
    2.3.2    2026-10-28  Wolfgang Baeck       Validated single-check HEALTH <Id> [base64 name] request
    2.3.3    2026-10-29  Wolfgang Baeck       Allow PendingReboot and Updates check Ids
    2.4.0    2026-11-02  Wolfgang Baeck       Pass the caller SID to RUN scripts (SELFX_CALLER_SID)
    2.5.0    2026-11-04  Wolfgang Baeck       Background health checks, status cache and STATUS request
    2.5.3    2026-11-04  Wolfgang Baeck       Log uses the current time zone (cache cleared after time zone changes)
    2.5.6    2026-11-05  Wolfgang Baeck       Optional TimeoutSeconds on Health_Config remediations (max. 7200)
    2.6.0    2026-11-06  Wolfgang Baeck       Daily log housekeeping (Log_Retention_Days in Tool_Config.xml, default 90)
*/

using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.ServiceProcess;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Xml;

namespace SelfX
{
    /// <summary>
    /// Host local requests and serialize execution of catalog-approved System scripts.
    /// </summary>
    public class SelfXService : ServiceBase
    {
        public const string DefaultServiceName = "SelfXService";
        public const string DefaultPipeName = "SelfX.Service";
        public const string Version = "1.1.0";

        const int DefaultTimeoutSeconds = 900;
        const int MaxTimeoutSeconds = 7200;
        const int MaxRequestLength = 512;
        const int MaxOutputLength = 20000;
        const int MaxCacheLength = 60000;
        const int HealthTimeoutSeconds = 240;
        const long MaxLogBytes = 5 * 1024 * 1024;
        const int DefaultLogRetentionDays = 90;

        static readonly Regex ScriptNamePattern = new Regex(@"^[A-Za-z0-9_\-\.]{1,100}\.ps1$", RegexOptions.IgnoreCase);
        static readonly Regex HealthRequestPattern = new Regex(
            @"^HEALTH(?: (IME|Defender|Compliance|Applications|Disk|BitLocker|PendingReboot|Updates|Service|Custom)(?: ([A-Za-z0-9+/]{2,400}={0,2}))?)?$",
            RegexOptions.CultureInvariant);

        readonly string installRoot;
        readonly string scriptsRoot;
        readonly string catalogPath;
        readonly string logDirectory;
        readonly string cacheFile;
        readonly string pipeName;
        readonly object logLock = new object();
        readonly SemaphoreSlim runLock = new SemaphoreSlim(1, 1);
        // Serializes all health runs, because each of them writes the status cache.
        readonly SemaphoreSlim healthLock = new SemaphoreSlim(1, 1);
        readonly ManualResetEvent stopEvent = new ManualResetEvent(false);
        volatile bool stopping;
        volatile string backgroundState = "Active";
        volatile int backgroundInterval = 15;
        volatile int backgroundProcessId;
        DateTime lastBackgroundAttempt = DateTime.MinValue;
        DateTime lastHousekeeping = DateTime.MinValue;
        string lastBackgroundNote = "";
        Thread listener;
        Thread background;

        /// <summary>
        /// Settings of the background health check (Health_Config.xml, element Background).
        /// </summary>
        sealed class BackgroundSettings
        {
            public bool Enabled = true;
            public int IntervalMinutes = 15;
            public bool PauseOnBattery = true;
            public int MaxCpuPercent = 75;
            public int StartDelaySeconds = 120;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct SystemPowerStatus
        {
            public byte ACLineStatus;
            public byte BatteryFlag;
            public byte BatteryLifePercent;
            public byte SystemStatusFlag;
            public int BatteryLifeTime;
            public int BatteryFullLifeTime;
        }

        [DllImport("kernel32.dll")]
        static extern bool GetSystemPowerStatus(out SystemPowerStatus status);

        [DllImport("kernel32.dll")]
        static extern bool GetSystemTimes(out long idleTime, out long kernelTime, out long userTime);

        /// <summary>
        /// Resolve installed payload paths and configure the service endpoint and logging.
        /// </summary>
        public SelfXService(string pipeName, string logDirectory)
        {
            ServiceName = DefaultServiceName;
            CanStop = true;
            CanShutdown = true;
            AutoLog = true;

            installRoot = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
            scriptsRoot = Path.Combine(installRoot, "Scripts_to_run");
            catalogPath = Path.Combine(installRoot, "Issues_List.xml");
            this.pipeName = pipeName;
            this.logDirectory = logDirectory;
            // The cache folder is a sibling of the log folder (default ProgramData\SelfX\Cache).
            string dataRoot = Path.GetDirectoryName(logDirectory.TrimEnd('\\'));
            cacheFile = Path.Combine(Path.Combine(string.IsNullOrEmpty(dataRoot) ? logDirectory : dataRoot, "Cache"), "Health.json");
        }

        /// <summary>
        /// Start the pipe listener when the Service Control Manager starts the service.
        /// </summary>
        protected override void OnStart(string[] args)
        {
            StartListening();
        }

        /// <summary>
        /// Stop accepting connections when the Service Control Manager stops the service.
        /// </summary>
        protected override void OnStop()
        {
            StopListening();
        }

        /// <summary>
        /// Stop accepting connections when Windows notifies the service of shutdown.
        /// </summary>
        protected override void OnShutdown()
        {
            StopListening();
        }

        /// <summary>
        /// Start a background listener without blocking the service start callback.
        /// </summary>
        public void StartListening()
        {
            stopping = false;
            stopEvent.Reset();
            try { Directory.CreateDirectory(Path.GetDirectoryName(cacheFile)); } catch { }
            listener = new Thread(ListenLoop);
            listener.IsBackground = true;
            listener.Name = "SelfXPipeListener";
            listener.Start();
            background = new Thread(BackgroundLoop);
            background.IsBackground = true;
            background.Name = "SelfXBackgroundHealth";
            background.Start();
            Log("Service started. Version " + Version + ", pipe '" + pipeName + "', root '" + installRoot + "'.");
        }

        /// <summary>
        /// Wake the blocked listener and wait briefly for it to stop accepting connections.
        /// </summary>
        public void StopListening()
        {
            stopping = true;
            stopEvent.Set();
            // A running background collection is only reading; stop it with the service.
            int pid = backgroundProcessId;
            if (pid != 0)
            {
                KillProcessTree(pid);
            }
            // Unblock WaitForConnection.
            try
            {
                using (NamedPipeClientStream client = new NamedPipeClientStream(".", pipeName, PipeDirection.InOut))
                {
                    client.Connect(1000);
                }
            }
            catch { }
            if (listener != null)
            {
                listener.Join(5000);
            }
            if (background != null)
            {
                background.Join(5000);
            }
            Log("Service stopped.");
        }

        /// <summary>
        /// Allow local requests while denying network clients and user-owned pipe instances.
        /// </summary>
        PipeSecurity CreatePipeSecurity()
        {
            PipeSecurity security = new PipeSecurity();
            // Remote clients are never allowed.
            security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.NetworkSid, null), PipeAccessRights.FullControl, AccessControlType.Deny));
            security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null), PipeAccessRights.FullControl, AccessControlType.Allow));
            security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null), PipeAccessRights.FullControl, AccessControlType.Allow));
            security.AddAccessRule(new PipeAccessRule(WindowsIdentity.GetCurrent().User, PipeAccessRights.FullControl, AccessControlType.Allow));
            // ReadWrite does not include CreateNewInstance, so users cannot add their own server instance.
            security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.AuthenticatedUserSid, null), PipeAccessRights.ReadWrite, AccessControlType.Allow));
            return security;
        }

        /// <summary>
        /// Accept pipe connections and dispatch each connection to the thread pool.
        /// </summary>
        void ListenLoop()
        {
            PipeSecurity security = CreatePipeSecurity();
            while (!stopping)
            {
                NamedPipeServerStream server = null;
                try
                {
                    server = new NamedPipeServerStream(pipeName, PipeDirection.InOut, NamedPipeServerStream.MaxAllowedServerInstances,
                        PipeTransmissionMode.Byte, PipeOptions.None, 4096, 4096, security);
                    server.WaitForConnection();
                    if (stopping)
                    {
                        server.Dispose();
                        break;
                    }
                    NamedPipeServerStream connection = server;
                    server = null;
                    ThreadPool.QueueUserWorkItem(delegate { HandleConnection(connection); });
                }
                catch (Exception ex)
                {
                    if (server != null)
                    {
                        server.Dispose();
                    }
                    if (!stopping)
                    {
                        Log("Listener error: " + ex.Message);
                        Thread.Sleep(1000);
                    }
                }
            }
        }

        /// <summary>
        /// Read one UTF-8 request, identify its caller and return one protocol response.
        /// </summary>
        void HandleConnection(NamedPipeServerStream pipe)
        {
            string user = "unknown";
            try
            {
                using (pipe)
                {
                    UTF8Encoding encoding = new UTF8Encoding(false);
                    StreamReader reader = new StreamReader(pipe, encoding, false, 1024, true);
                    StreamWriter writer = new StreamWriter(pipe, encoding, 1024, true);
                    writer.AutoFlush = true;

                    string request = ReadLine(reader, MaxRequestLength);
                    try { user = pipe.GetImpersonationUserName(); } catch { }
                    string callerSid = GetCallerSid(pipe);

                    string response = ProcessRequest(request, user, callerSid);
                    writer.WriteLine(response);
                    try { pipe.WaitForPipeDrain(); } catch { }
                }
            }
            catch (Exception ex)
            {
                Log("Connection error (" + user + "): " + ex.Message);
            }
        }

        /// <summary>
        /// Return the SID of the pipe client, or null when it cannot be read.
        /// </summary>
        static string GetCallerSid(NamedPipeServerStream pipe)
        {
            string sid = null;
            try
            {
                // Identification-level impersonation is enough to query the client token.
                // GetCurrent(true) returns null without a thread token, never the service identity.
                pipe.RunAsClient(delegate
                {
                    using (WindowsIdentity client = WindowsIdentity.GetCurrent(true))
                    {
                        if (client != null && client.User != null)
                        {
                            sid = client.User.Value;
                        }
                    }
                });
            }
            catch
            {
                return null;
            }
            return sid;
        }

        /// <summary>
        /// Read a bounded request line and remove surrounding whitespace.
        /// </summary>
        static string ReadLine(StreamReader reader, int maxLength)
        {
            StringBuilder line = new StringBuilder();
            while (line.Length < maxLength)
            {
                int c = reader.Read();
                if (c < 0 || c == '\n')
                {
                    break;
                }
                if (c != '\r')
                {
                    line.Append((char)c);
                }
            }
            return line.ToString().Trim();
        }

        /// <summary>
        /// Validate a request and run one approved action, or return a protocol rejection.
        /// </summary>
        string ProcessRequest(string request, string user, string callerSid)
        {
            if (string.IsNullOrEmpty(request))
            {
                return "ERROR Empty request";
            }
            if (request == "PING")
            {
                return "PONG " + Version;
            }
            if (request == "STATUS")
            {
                return GetStatusResponse();
            }
            Match healthMatch = HealthRequestPattern.Match(request);
            if (healthMatch.Success)
            {
                string healthScript = Path.Combine(installRoot, "HealthStatus.ps1");
                if (!File.Exists(healthScript)) return "ERROR Health collector not installed";
                // Single-check filter: Id is whitelisted, Name is base64 so no quoting reaches the command line.
                string filter = "";
                if (healthMatch.Groups[1].Success)
                {
                    filter = " -OnlyId " + healthMatch.Groups[1].Value;
                    if (healthMatch.Groups[2].Success)
                    {
                        try { Convert.FromBase64String(healthMatch.Groups[2].Value); }
                        catch (FormatException) { return "ERROR Invalid health check name"; }
                        filter += " -OnlyName " + healthMatch.Groups[2].Value;
                    }
                }
                if (!runLock.Wait(0)) return "BUSY";
                try
                {
                    // A running background collection finishes first (at most HealthTimeoutSeconds).
                    if (!healthLock.Wait(TimeSpan.FromSeconds(HealthTimeoutSeconds + 10))) return "BUSY";
                    try
                    {
                        return RunScript(healthScript, "HealthStatus.ps1", HealthTimeoutSeconds, user, true, filter);
                    }
                    finally { healthLock.Release(); }
                }
                finally { runLock.Release(); }
            }
            if (request.StartsWith("HEALTH", StringComparison.Ordinal))
            {
                return "ERROR Invalid health request";
            }
            if (!request.StartsWith("RUN ", StringComparison.Ordinal))
            {
                return "ERROR Unknown command";
            }

            string scriptName = request.Substring(4).Trim();
            if (!ScriptNamePattern.IsMatch(scriptName) || scriptName.Contains(".."))
            {
                Log("Rejected invalid request from " + user + ": '" + scriptName + "'.");
                return "ERROR Invalid action";
            }

            int timeoutSeconds;
            // Elevation is granted only to System entries, never arbitrary client-supplied scripts.
            if (!TryGetSystemAction(scriptName, out timeoutSeconds))
            {
                Log("Rejected request from " + user + ": '" + scriptName + "' is not a System action in the catalog.");
                return "ERROR Action is not allowed";
            }

            string scriptPath = Path.GetFullPath(Path.Combine(scriptsRoot, scriptName));
            if (!scriptPath.StartsWith(scriptsRoot + "\\", StringComparison.OrdinalIgnoreCase) || !File.Exists(scriptPath))
            {
                Log("Rejected request from " + user + ": script '" + scriptName + "' not found.");
                return "ERROR Script not found";
            }

            // Refuse concurrent repairs rather than queueing potentially conflicting changes.
            if (!runLock.Wait(0))
            {
                Log("Busy: request from " + user + " for '" + scriptName + "' refused.");
                return "BUSY";
            }
            try
            {
                return RunScript(scriptPath, scriptName, timeoutSeconds, user, false, "", callerSid);
            }
            finally
            {
                runLock.Release();
            }
        }

        /// <summary>
        /// Check the installed System-action whitelist and resolve a bounded execution timeout.
        /// </summary>
        bool TryGetSystemAction(string scriptName, out int timeoutSeconds)
        {
            timeoutSeconds = DefaultTimeoutSeconds;
            XmlReaderSettings settings = new XmlReaderSettings();
            // Catalog loading must not resolve external entities or fetch network resources.
            settings.DtdProcessing = DtdProcessing.Prohibit;
            settings.XmlResolver = null;

            XmlDocument catalog = new XmlDocument();
            catalog.XmlResolver = null;
            using (XmlReader reader = XmlReader.Create(catalogPath, settings))
            {
                catalog.Load(reader);
            }

            // scriptName is validated by ScriptNamePattern, so it contains no quotes.
            XmlNode action = catalog.SelectSingleNode(
                "//Action[normalize-space(Context)='System' and normalize-space(Script)='" + scriptName + "']");
            if (action == null)
            {
                string healthConfig = Path.Combine(installRoot, "Health_Config.xml");
                if (!File.Exists(healthConfig)) return false;
                XmlDocument health = new XmlDocument();
                health.XmlResolver = null;
                using (XmlReader reader = XmlReader.Create(healthConfig, settings)) { health.Load(reader); }
                XmlNode remediation = health.SelectSingleNode("/HealthConfig/Remediations/Remediation[@Script='" + scriptName + "']");
                if (remediation == null) return false;
                // Optional TimeoutSeconds attribute (long repairs such as installing updates), bounded like catalog actions.
                XmlAttribute remediationTimeout = remediation.Attributes["TimeoutSeconds"];
                int remediationConfigured;
                if (remediationTimeout != null && int.TryParse(remediationTimeout.Value.Trim(), out remediationConfigured) && remediationConfigured > 0)
                {
                    timeoutSeconds = Math.Min(remediationConfigured, MaxTimeoutSeconds);
                }
                return true;
            }

            XmlNode timeoutNode = action.SelectSingleNode("TimeoutSeconds");
            int configured;
            if (timeoutNode != null && int.TryParse(timeoutNode.InnerText.Trim(), out configured) && configured > 0)
            {
                timeoutSeconds = Math.Min(configured, MaxTimeoutSeconds);
            }
            return true;
        }

        /// <summary>
        /// Run PowerShell under the service identity and log bounded output and completion.
        /// </summary>
        string RunScript(string scriptPath, string scriptName, int timeoutSeconds, string user, bool health = false, string healthFilter = "", string callerSid = null, bool background = false)
        {
            string powershell = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
            // Health runs also update the status cache; the path contains no quotes.
            ProcessStartInfo startInfo = new ProcessStartInfo(powershell,
                "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + scriptPath + "\"" +
                (health ? " -Collect" + healthFilter + " -CacheFile \"" + cacheFile + "\"" : ""));
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = true;
            startInfo.RedirectStandardOutput = true;
            startInfo.RedirectStandardError = true;
            if (health)
            {
                startInfo.StandardOutputEncoding = Encoding.UTF8;
                startInfo.StandardErrorEncoding = Encoding.UTF8;
            }
            startInfo.WorkingDirectory = health ? installRoot : scriptsRoot;
            // Remove any inherited value so only a SID read from the client token reaches the script.
            startInfo.EnvironmentVariables.Remove("SELFX_CALLER_SID");
            if (!health && callerSid != null)
            {
                startInfo.EnvironmentVariables["SELFX_CALLER_SID"] = callerSid;
            }

            StringBuilder output = new StringBuilder();
            bool outputOverflow = false;
            object outputLock = new object();
            DataReceivedEventHandler collect = delegate(object sender, DataReceivedEventArgs e)
            {
                if (e.Data == null) return;
                lock (outputLock)
                {
                    if (output.Length + e.Data.Length + Environment.NewLine.Length <= MaxOutputLength)
                    {
                        output.AppendLine(e.Data);
                    }
                    else { outputOverflow = true; }
                }
            };

            if (!background)
            {
                Log("Start '" + scriptName + "' requested by " + user + " (timeout " + timeoutSeconds + " s).");
            }
            Stopwatch watch = Stopwatch.StartNew();
            string result;
            using (Process process = new Process())
            {
                process.StartInfo = startInfo;
                process.OutputDataReceived += collect;
                process.ErrorDataReceived += collect;
                process.Start();
                if (background)
                {
                    backgroundProcessId = process.Id;
                    // Background checks must not slow down the user's work.
                    try { process.PriorityClass = ProcessPriorityClass.BelowNormal; } catch { }
                }
                // Drain both redirected streams asynchronously to avoid pipe-buffer deadlocks.
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();

                if (!process.WaitForExit(timeoutSeconds * 1000))
                {
                    // Descendants may outlive PowerShell; attempt tree termination on timeout.
                    KillProcessTree(process.Id);
                    result = "TIMEOUT";
                }
                else
                {
                    // Finish asynchronous output callbacks before reading the captured output.
                    process.WaitForExit();
                    result = "DONE " + process.ExitCode;
                }
                if (background)
                {
                    backgroundProcessId = 0;
                }
            }

            string text;
            lock (outputLock)
            {
                text = output.ToString().Trim();
            }
            if (background)
            {
                // Only a summary: the result is in the status cache and would fill the log every interval.
                Log("Background health check: " + result + " after " + (int)watch.Elapsed.TotalSeconds + " s.");
                return result;
            }
            Log("End '" + scriptName + "' requested by " + user + ": " + result + " after " + (int)watch.Elapsed.TotalSeconds + " s." +
                (text.Length > 0 ? Environment.NewLine + "    " + text.Replace(Environment.NewLine, Environment.NewLine + "    ") : ""));
            if (health && result == "DONE 0")
            {
                if (outputOverflow) return "ERROR Health response exceeds size limit";
                return "HEALTH " + Convert.ToBase64String(Encoding.UTF8.GetBytes(text));
            }
            return result;
        }

        /// <summary>
        /// Return the cached health result: STATUS &lt;time UTC|NONE&gt; &lt;interval minutes&gt; &lt;state&gt; &lt;base64 JSON|-&gt;.
        /// </summary>
        string GetStatusResponse()
        {
            string state = backgroundState;
            string prefix = "STATUS ";
            string suffix = " " + backgroundInterval.ToString(CultureInfo.InvariantCulture) + " " + state + " ";
            for (int attempt = 0; attempt < 3; attempt++)
            {
                try
                {
                    if (!File.Exists(cacheFile)) return prefix + "NONE" + suffix + "-";
                    DateTime written = File.GetLastWriteTimeUtc(cacheFile);
                    byte[] bytes = File.ReadAllBytes(cacheFile);
                    if (bytes.Length == 0 || bytes.Length > MaxCacheLength) return prefix + "NONE" + suffix + "-";
                    return prefix + written.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture) + suffix + Convert.ToBase64String(bytes);
                }
                catch (IOException)
                {
                    // The cache is replaced by a rename; retry once it is complete.
                    Thread.Sleep(100);
                }
            }
            return "ERROR Status cache not readable";
        }

        /// <summary>
        /// Read the Background element of Health_Config.xml; missing or invalid values use the defaults.
        /// </summary>
        BackgroundSettings ReadBackgroundSettings()
        {
            BackgroundSettings result = new BackgroundSettings();
            try
            {
                string healthConfig = Path.Combine(installRoot, "Health_Config.xml");
                if (!File.Exists(healthConfig)) return result;
                XmlReaderSettings settings = new XmlReaderSettings();
                settings.DtdProcessing = DtdProcessing.Prohibit;
                settings.XmlResolver = null;
                XmlDocument document = new XmlDocument();
                document.XmlResolver = null;
                using (XmlReader reader = XmlReader.Create(healthConfig, settings)) { document.Load(reader); }
                XmlElement node = document.SelectSingleNode("/HealthConfig/Background") as XmlElement;
                if (node == null) return result;
                int value;
                if (node.HasAttribute("Enabled")) result.Enabled = !string.Equals(node.GetAttribute("Enabled"), "false", StringComparison.OrdinalIgnoreCase);
                if (node.HasAttribute("PauseOnBattery")) result.PauseOnBattery = !string.Equals(node.GetAttribute("PauseOnBattery"), "false", StringComparison.OrdinalIgnoreCase);
                if (int.TryParse(node.GetAttribute("IntervalMinutes"), NumberStyles.Integer, CultureInfo.InvariantCulture, out value) && value >= 5 && value <= 1440) result.IntervalMinutes = value;
                if (int.TryParse(node.GetAttribute("MaxCpuPercent"), NumberStyles.Integer, CultureInfo.InvariantCulture, out value) && value >= 10 && value <= 100) result.MaxCpuPercent = value;
                if (int.TryParse(node.GetAttribute("StartDelaySeconds"), NumberStyles.Integer, CultureInfo.InvariantCulture, out value) && value >= 0 && value <= 3600) result.StartDelaySeconds = value;
            }
            catch (Exception ex)
            {
                LogBackgroundNote("Background settings not readable, defaults are used: " + ex.Message);
            }
            return result;
        }

        /// <summary>
        /// True when the device runs on battery (AC line offline).
        /// </summary>
        static bool IsOnBattery()
        {
            SystemPowerStatus status;
            return GetSystemPowerStatus(out status) && status.ACLineStatus == 0;
        }

        /// <summary>
        /// Processor load in percent over one second, or 0 when it cannot be measured.
        /// </summary>
        int GetCpuPercent()
        {
            long idle1, kernel1, user1, idle2, kernel2, user2;
            if (!GetSystemTimes(out idle1, out kernel1, out user1)) return 0;
            if (stopEvent.WaitOne(1000)) return 0;
            if (!GetSystemTimes(out idle2, out kernel2, out user2)) return 0;
            // Kernel time includes idle time.
            long total = (kernel2 - kernel1) + (user2 - user1);
            if (total <= 0) return 0;
            return (int)Math.Round(100.0 * (total - (idle2 - idle1)) / total);
        }

        /// <summary>
        /// Log a background note only when it differs from the previous one (no repeated lines every minute).
        /// </summary>
        void LogBackgroundNote(string note)
        {
            if (note == lastBackgroundNote) return;
            lastBackgroundNote = note;
            Log(note);
        }

        /// <summary>
        /// Run the full health collection at the configured interval while the device is idle enough.
        /// </summary>
        void BackgroundLoop()
        {
            BackgroundSettings settings = ReadBackgroundSettings();
            // STATUS reports the configured interval and state already before the first run.
            backgroundInterval = settings.Enabled ? settings.IntervalMinutes : 0;
            backgroundState = !settings.Enabled ? "Disabled" : (settings.PauseOnBattery && IsOnBattery() ? "Battery" : "Active");
            if (stopEvent.WaitOne(TimeSpan.FromSeconds(settings.StartDelaySeconds))) return;
            while (!stopping)
            {
                TimeSpan wait = TimeSpan.FromSeconds(60);
                // Log housekeeping once a day, also when the background checks are disabled or paused.
                if (DateTime.UtcNow - lastHousekeeping >= TimeSpan.FromHours(24))
                {
                    lastHousekeeping = DateTime.UtcNow;
                    CleanupLogs();
                }
                try
                {
                    settings = ReadBackgroundSettings();
                    backgroundInterval = settings.Enabled ? settings.IntervalMinutes : 0;
                    if (!settings.Enabled)
                    {
                        backgroundState = "Disabled";
                        LogBackgroundNote("Background health checks are disabled in Health_Config.xml.");
                    }
                    else if (settings.PauseOnBattery && IsOnBattery())
                    {
                        backgroundState = "Battery";
                        LogBackgroundNote("Background health checks paused: the device runs on battery.");
                    }
                    else
                    {
                        backgroundState = "Active";
                        DateTime last = lastBackgroundAttempt;
                        if (File.Exists(cacheFile))
                        {
                            DateTime written = File.GetLastWriteTimeUtc(cacheFile);
                            if (written > last) last = written;
                        }
                        if (DateTime.UtcNow - last >= TimeSpan.FromMinutes(settings.IntervalMinutes))
                        {
                            string postpone = null;
                            int cpu = settings.MaxCpuPercent < 100 ? GetCpuPercent() : 0;
                            if (stopping) return;
                            if (cpu > settings.MaxCpuPercent) postpone = "processor load " + cpu + " %";
                            else if (runLock.CurrentCount == 0) postpone = "a repair is running";
                            else if (!healthLock.Wait(0)) postpone = "a health check is running";
                            if (postpone == null)
                            {
                                try
                                {
                                    lastBackgroundAttempt = DateTime.UtcNow;
                                    string healthScript = Path.Combine(installRoot, "HealthStatus.ps1");
                                    if (File.Exists(healthScript))
                                    {
                                        LogBackgroundNote("Background health checks active (every " + settings.IntervalMinutes + " minutes).");
                                        RunScript(healthScript, "HealthStatus.ps1", HealthTimeoutSeconds, "background", true, "", null, true);
                                    }
                                }
                                finally { healthLock.Release(); }
                            }
                            else
                            {
                                LogBackgroundNote("Background health check postponed: " + postpone + ".");
                                wait = TimeSpan.FromSeconds(120);
                            }
                        }
                    }
                }
                catch (Exception ex)
                {
                    Log("Background health check error: " + ex.Message);
                }
                if (stopEvent.WaitOne(wait)) return;
            }
        }

        /// <summary>
        /// Days to keep log files: Log_Retention_Days of Tool_Config.xml (1-3650), default 90.
        /// </summary>
        int ReadLogRetentionDays()
        {
            try
            {
                string toolConfig = Path.Combine(installRoot, "Tool_Config.xml");
                if (!File.Exists(toolConfig)) return DefaultLogRetentionDays;
                XmlReaderSettings settings = new XmlReaderSettings();
                settings.DtdProcessing = DtdProcessing.Prohibit;
                settings.XmlResolver = null;
                XmlDocument document = new XmlDocument();
                document.XmlResolver = null;
                using (XmlReader reader = XmlReader.Create(toolConfig, settings)) { document.Load(reader); }
                XmlNode node = document.SelectSingleNode("/GUI_Config/Log_Retention_Days");
                int value;
                if (node != null && int.TryParse(node.InnerText.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out value) && value >= 1 && value <= 3650) return value;
            }
            catch (Exception ex)
            {
                Log("Log retention not readable, " + DefaultLogRetentionDays + " days are used: " + ex.Message);
            }
            return DefaultLogRetentionDays;
        }

        /// <summary>
        /// Delete *.log and *.old files older than the retention in the log folder (not in subfolders).
        /// The user folders under Logs\Users are cleaned by the users themselves (SelfXLog.ps1): users can
        /// create folders there, so SYSTEM never deletes in them (no junction or link can redirect a deletion).
        /// </summary>
        public int CleanupLogs()
        {
            int days = ReadLogRetentionDays();
            DateTime limit = DateTime.UtcNow.AddDays(-days);
            int deleted = 0;
            try
            {
                DirectoryInfo root = new DirectoryInfo(logDirectory);
                if (!root.Exists || (root.Attributes & FileAttributes.ReparsePoint) != 0) return 0;
                foreach (FileInfo file in root.GetFiles())
                {
                    string extension = file.Extension.ToLowerInvariant();
                    if (extension != ".log" && extension != ".old") continue;
                    if ((file.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                    if (file.LastWriteTimeUtc >= limit) continue;
                    try
                    {
                        file.Delete();
                        deleted++;
                    }
                    catch { }
                }
                if (deleted > 0) Log("Log housekeeping: " + deleted + " log file(s) older than " + days + " days deleted.");
            }
            catch (Exception ex)
            {
                Log("Log housekeeping error: " + ex.Message);
            }
            return deleted;
        }

        /// <summary>
        /// Attempt to terminate the timed-out action and its descendants by process ID.
        /// </summary>
        static void KillProcessTree(int processId)
        {
            try
            {
                ProcessStartInfo kill = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "taskkill.exe"), "/PID " + processId + " /T /F");
                kill.UseShellExecute = false;
                kill.CreateNoWindow = true;
                using (Process killer = Process.Start(kill))
                {
                    killer.WaitForExit(10000);
                }
            }
            catch { }
        }

        /// <summary>
        /// Append a timestamped entry with serialized size-based log rotation.
        /// </summary>
        void Log(string message)
        {
            try
            {
                lock (logLock)
                {
                    Directory.CreateDirectory(logDirectory);
                    string path = Path.Combine(logDirectory, "SelfXService.log");
                    FileInfo info = new FileInfo(path);
                    if (info.Exists && info.Length > MaxLogBytes)
                    {
                        string old = path + ".old";
                        if (File.Exists(old))
                        {
                            File.Delete(old);
                        }
                        File.Move(path, old);
                    }
                    // The service runs for days: refresh the cached time zone (for example after the automatic
                    // time zone change during the OOBE) so the log shows the current local time of the device.
                    TimeZoneInfo.ClearCachedData();
                    File.AppendAllText(path, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + message + Environment.NewLine, Encoding.UTF8);
                }
            }
            catch { }
        }
    }

    /// <summary>
    /// Provide service-host and interactive troubleshooting entry points.
    /// </summary>
    public static class Program
    {
        /// <summary>
        /// Run under the Service Control Manager or wait for Ctrl+C in console mode.
        /// </summary>
        public static int Main(string[] args)
        {
            string pipeName = SelfXService.DefaultPipeName;
            string logDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), @"SelfX\Logs");
            bool console = false;

            foreach (string arg in args)
            {
                if (arg.Equals("/console", StringComparison.OrdinalIgnoreCase))
                {
                    console = true;
                }
                else if (arg.StartsWith("/pipe:", StringComparison.OrdinalIgnoreCase))
                {
                    pipeName = arg.Substring(6);
                }
                else if (arg.StartsWith("/logdir:", StringComparison.OrdinalIgnoreCase))
                {
                    logDirectory = arg.Substring(8);
                }
            }

            SelfXService service = new SelfXService(pipeName, logDirectory);
            if (!console)
            {
                ServiceBase.Run(service);
                return 0;
            }

            // Console mode for troubleshooting: runs with the rights of the current user.
            ManualResetEvent done = new ManualResetEvent(false);
            Console.CancelKeyPress += delegate(object sender, ConsoleCancelEventArgs e)
            {
                e.Cancel = true;
                done.Set();
            };
            service.StartListening();
            Console.WriteLine("SelfX service " + SelfXService.Version + " listening on pipe '" + pipeName + "'. Press Ctrl+C to stop.");
            done.WaitOne();
            service.StopListening();
            return 0;
        }
    }
}
