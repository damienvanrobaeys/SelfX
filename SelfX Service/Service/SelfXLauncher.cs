/*
Summary:
    Start SelfX or the SelfX status icon without any console window.

Description:
    Compiled by Install.ps1 as SelfX.exe (Windows application, no console) into the install
    folder. The desktop and Start Menu shortcuts start "SelfX.exe"; the HKLM Run entry
    "SelfXTray" starts "SelfX.exe /tray" at every sign-in.
    A shortcut or Run entry that starts powershell.exe directly always creates a console
    window first: "-WindowStyle Hidden" hides it only after PowerShell has started (the
    window flashes), and on Windows 11 with Windows Terminal as default terminal a terminal
    window can even stay open. SelfX.exe starts the Windows PowerShell 5.1 of the system
    with CREATE_NO_WINDOW, so no console is created at all, and exits immediately.
    Only the two scripts next to SelfX.exe can be started: Self_X.ps1 (default, optional
    /page:<Troubleshooting|Status|SystemInfo|SendLogs>) and SelfX_Tray.ps1 (/tray). Other
    arguments are ignored. Runs with the rights of the signed-in user; nothing is elevated.
    The status icon gets the Windows folder as working directory so that it does not lock
    the install folder during updates. Exit code 0 when PowerShell was started, otherwise 1.
    Compiled locally using the .NET Framework compiler (C# 5); no remote API is used.

Notes:
    Name    : SelfXLauncher.cs
    Package : SelfX Service
    Context : User (shortcut, HKLM Run entry)
    Version : 2.5.3

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.5.3    2026-11-04  Wolfgang Baeck       Initial version: start SelfX and the status icon without console window
    */

using System;
using System.Diagnostics;
using System.IO;

namespace SelfX
{
    /// <summary>
    /// Start Self_X.ps1 or SelfX_Tray.ps1 with a hidden Windows PowerShell and no console.
    /// </summary>
    public static class Launcher
    {
        static readonly string[] Pages = { "Troubleshooting", "Status", "SystemInfo", "SendLogs" };

        [STAThread]
        public static int Main(string[] args)
        {
            try
            {
                string folder = AppDomain.CurrentDomain.BaseDirectory;
                bool tray = false;
                string page = "";
                foreach (string arg in args)
                {
                    string value = (arg ?? "").Trim();
                    if (value.Equals("/tray", StringComparison.OrdinalIgnoreCase))
                    {
                        tray = true;
                    }
                    else if (value.StartsWith("/page:", StringComparison.OrdinalIgnoreCase))
                    {
                        // Only known page names are passed on, nothing else reaches the command line.
                        string requested = value.Substring(6);
                        foreach (string known in Pages)
                        {
                            if (known.Equals(requested, StringComparison.OrdinalIgnoreCase)) { page = known; }
                        }
                    }
                }

                string script = Path.Combine(folder, tray ? "SelfX_Tray.ps1" : "Self_X.ps1");
                if (!File.Exists(script)) { return 1; }

                string windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
                ProcessStartInfo start = new ProcessStartInfo();
                start.FileName = Path.Combine(windows, @"System32\WindowsPowerShell\v1.0\powershell.exe");
                start.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + script + "\"" +
                    (page.Length > 0 ? " -Page " + page : "");
                start.WorkingDirectory = tray ? windows : folder;
                start.UseShellExecute = false;
                start.CreateNoWindow = true;
                start.WindowStyle = ProcessWindowStyle.Hidden;
                using (Process process = Process.Start(start)) { }
                return 0;
            }
            catch
            {
                return 1;
            }
        }
    }
}
