/*
Summary:
    Start the SelfX status icon in the sessions of the users who are signed in right now.

Description:
    Compiled in memory by Install.ps1 (Add-Type, no file is written to the install folder).
    The HKLM Run entry "SelfXTray" starts the status icon only at the next sign-in. So that
    the icon appears right after the installation, Install.ps1 (SYSTEM via Intune/SCCM)
    calls StartInActiveSessions: for every active session (console or remote desktop, also
    when locked) the token of the signed-in user is queried with WTSQueryUserToken and
    "SelfX.exe /tray" is started with CreateProcessAsUser on the user's desktop
    (winsta0\default) with the user's environment and the Windows folder as working
    directory. The process runs with the normal (not elevated) rights of the user: for
    administrators with UAC, WTSQueryUserToken returns the filtered token. Nothing else is
    started and the started process is not waited for. The status icon itself checks
    Show_Tray_Icon and the user setting TrayIcon and closes when the icon is switched off
    or already runs.
    WTSQueryUserToken needs the SeTcbPrivilege, which only LocalSystem has. In any other
    context (e.g. a manual installation as administrator) no process is started and the
    result says so; the icon then starts at the next sign-in.
    Compiled locally using the .NET Framework compiler (C# 5); no remote API is used.

Notes:
    Name    : SelfXSessionStarter.cs
    Package : SelfX Service
    Context : Installer (SYSTEM via Intune/SCCM)
    Version : 2.5.8

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.5.8    2026-11-05  Wolfgang Baeck       Initial version: start the status icon right after the installation
*/

using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace SelfXInstall
{
    /// <summary>
    /// Start a program in every active user session with the token of the signed-in user.
    /// </summary>
    public static class SessionStarter
    {
        const int WTSActive = 0;
        const int ERROR_NO_TOKEN = 1008;
        const int ERROR_PRIVILEGE_NOT_HELD = 1314;
        const int CREATE_UNICODE_ENVIRONMENT = 0x00000400;
        const int CREATE_NEW_PROCESS_GROUP = 0x00000200;
        const int STARTF_USESHOWWINDOW = 0x00000001;
        const short SW_HIDE = 0;

        [StructLayout(LayoutKind.Sequential)]
        struct WTS_SESSION_INFO
        {
            public int SessionId;
            public IntPtr WinStationName;
            public int State;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct STARTUPINFO
        {
            public int cb;
            public string lpReserved;
            public string lpDesktop;
            public string lpTitle;
            public int dwX;
            public int dwY;
            public int dwXSize;
            public int dwYSize;
            public int dwXCountChars;
            public int dwYCountChars;
            public int dwFillAttribute;
            public int dwFlags;
            public short wShowWindow;
            public short cbReserved2;
            public IntPtr lpReserved2;
            public IntPtr hStdInput;
            public IntPtr hStdOutput;
            public IntPtr hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct PROCESS_INFORMATION
        {
            public IntPtr hProcess;
            public IntPtr hThread;
            public int dwProcessId;
            public int dwThreadId;
        }

        [DllImport("wtsapi32.dll", SetLastError = true)]
        static extern bool WTSEnumerateSessions(IntPtr hServer, int reserved, int version, out IntPtr sessionInfo, out int count);

        [DllImport("wtsapi32.dll")]
        static extern void WTSFreeMemory(IntPtr memory);

        [DllImport("wtsapi32.dll", SetLastError = true)]
        static extern bool WTSQueryUserToken(int sessionId, out IntPtr token);

        [DllImport("userenv.dll", SetLastError = true)]
        static extern bool CreateEnvironmentBlock(out IntPtr environment, IntPtr token, bool inherit);

        [DllImport("userenv.dll", SetLastError = true)]
        static extern bool DestroyEnvironmentBlock(IntPtr environment);

        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool CreateProcessAsUser(IntPtr token, string applicationName, StringBuilder commandLine,
            IntPtr processAttributes, IntPtr threadAttributes, bool inheritHandles, int creationFlags,
            IntPtr environment, string currentDirectory, ref STARTUPINFO startupInfo, out PROCESS_INFORMATION processInformation);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool CloseHandle(IntPtr handle);

        /// <summary>
        /// Returns the ids of the active user sessions (session 0 of the services is never included).
        /// </summary>
        public static int[] GetActiveSessionIds()
        {
            List<int> ids = new List<int>();
            IntPtr buffer;
            int count;
            if (!WTSEnumerateSessions(IntPtr.Zero, 0, 1, out buffer, out count)) { return ids.ToArray(); }
            try
            {
                int size = Marshal.SizeOf(typeof(WTS_SESSION_INFO));
                for (int i = 0; i < count; i++)
                {
                    WTS_SESSION_INFO info = (WTS_SESSION_INFO)Marshal.PtrToStructure(new IntPtr(buffer.ToInt64() + (long)i * size), typeof(WTS_SESSION_INFO));
                    if (info.SessionId != 0 && info.State == WTSActive) { ids.Add(info.SessionId); }
                }
            }
            finally
            {
                WTSFreeMemory(buffer);
            }
            return ids.ToArray();
        }

        /// <summary>
        /// Starts "applicationPath arguments" in every active user session. Returns one line per session.
        /// </summary>
        public static string[] StartInActiveSessions(string applicationPath, string arguments, string workingDirectory)
        {
            List<string> results = new List<string>();
            foreach (int sessionId in GetActiveSessionIds())
            {
                results.Add(StartInSession(sessionId, applicationPath, arguments, workingDirectory));
            }
            if (results.Count == 0) { results.Add("No active user session."); }
            return results.ToArray();
        }

        static string StartInSession(int sessionId, string applicationPath, string arguments, string workingDirectory)
        {
            IntPtr token = IntPtr.Zero;
            IntPtr environment = IntPtr.Zero;
            try
            {
                if (!WTSQueryUserToken(sessionId, out token))
                {
                    int error = Marshal.GetLastWin32Error();
                    if (error == ERROR_PRIVILEGE_NOT_HELD) { return "Session " + sessionId + ": not started (only possible as SYSTEM)."; }
                    if (error == ERROR_NO_TOKEN) { return "Session " + sessionId + ": not started (no signed-in user)."; }
                    return "Session " + sessionId + ": not started (WTSQueryUserToken error " + error + ").";
                }
                if (!CreateEnvironmentBlock(out environment, token, false)) { environment = IntPtr.Zero; }

                STARTUPINFO startup = new STARTUPINFO();
                startup.cb = Marshal.SizeOf(typeof(STARTUPINFO));
                startup.lpDesktop = @"winsta0\default";
                startup.dwFlags = STARTF_USESHOWWINDOW;
                startup.wShowWindow = SW_HIDE;
                StringBuilder commandLine = new StringBuilder("\"" + applicationPath + "\"" + (string.IsNullOrEmpty(arguments) ? "" : " " + arguments));
                PROCESS_INFORMATION process;
                int flags = CREATE_NEW_PROCESS_GROUP | (environment != IntPtr.Zero ? CREATE_UNICODE_ENVIRONMENT : 0);
                if (!CreateProcessAsUser(token, applicationPath, commandLine, IntPtr.Zero, IntPtr.Zero, false, flags,
                    environment, workingDirectory, ref startup, out process))
                {
                    return "Session " + sessionId + ": not started (CreateProcessAsUser error " + Marshal.GetLastWin32Error() + ").";
                }
                CloseHandle(process.hThread);
                CloseHandle(process.hProcess);
                return "Session " + sessionId + ": started (process " + process.dwProcessId + ").";
            }
            finally
            {
                if (environment != IntPtr.Zero) { DestroyEnvironmentBlock(environment); }
                if (token != IntPtr.Zero) { CloseHandle(token); }
            }
        }
    }
}
