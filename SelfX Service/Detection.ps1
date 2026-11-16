<#
.SYNOPSIS
    Detect the expected locally installed SelfX Service package version.

.DESCRIPTION
    Read-only Intune/SCCM detection for ProgramFiles\SelfX. Requires SelfXService.exe, SelfX.exe,
    Tool_Config.xml, a registered SelfXService and an exact Tool_Version match of 2.6.8.
    Does not start the service, contact the pipe, verify that it is running or execute
    remediation scripts. Writes an installed message and exits 0 when checks pass; exits
    1 for a missing prerequisite or version mismatch. XML read/parse errors are not caught.
    Logs the result to ProgramData\SelfX\Logs\Detection_<date>.log when that folder exists.

.NOTES
    Name    : Detection.ps1
    Package : SelfX Service
    Context : Detection
    Version : 2.6.8

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.0.0    2026-10-28  Wolfgang Baeck       Initial version for SelfX Service
    2.2.0    2026-10-28  Wolfgang Baeck       Added description, history and comments
    2.3.0    2026-10-28  Wolfgang Baeck       Detect the health-reporting package version
    2.3.1    2026-10-28  Wolfgang Baeck       Detect the health remediation package version
    2.3.2    2026-10-28  Wolfgang Baeck       Detect the per-status recheck package version
    2.3.3    2026-10-29  Wolfgang Baeck       Detect the pending reboot / updates status package version
    2.3.4    2026-10-29  Wolfgang Baeck       Detect the Pending status / Defender signature update package version
    2.4.0    2026-11-02  Wolfgang Baeck       Detect the device logs (send to support) package version
    2.5.0    2026-11-04  Wolfgang Baeck       Detect the modern UI / background checks package version
    2.5.1    2026-11-04  Wolfgang Baeck       Detect the branding package version
    2.5.2    2026-11-04  Wolfgang Baeck       Detect the package version with the update fix (exit code 1)
    2.5.3    2026-11-04  Wolfgang Baeck       Detect the version with user time zone, "Fix all problems" and SelfX.exe
    2.5.4    2026-11-05  Wolfgang Baeck       Detect version 2.5.4 (Defender Fix button only while not OK)
    2.5.5    2026-11-05  Wolfgang Baeck       Detect version 2.5.5 (local compliance criteria check)
    2.5.6    2026-11-05  Wolfgang Baeck       Detect version 2.5.6 (Fix button for pending Windows and Store updates)
    2.5.7    2026-11-05  Wolfgang Baeck       Detect version 2.5.7 (uninstallation closes open SelfX windows)
    2.5.8    2026-11-05  Wolfgang Baeck       Detect version 2.5.8 (status icon starts right after the installation)
    2.5.9    2026-11-05  Wolfgang Baeck       Detect version 2.5.9 (language selection for the user)
    2.5.10   2026-11-06  Wolfgang Baeck       Detect version 2.5.10 (LAN detection in virtual machines, last Intune sync time)
    2.6.0    2026-11-06  Wolfgang Baeck       Detect version 2.6.0 (logging, restart / app retry repairs); logs the result
    2.6.1    2026-11-06  Wolfgang Baeck       Detect version 2.6.1 (running state of the start buttons)
    2.6.2    2026-11-06  Wolfgang Baeck       Detect version 2.6.2 (SelfX icon in the taskbar)
    2.6.3    2026-11-06  Wolfgang Baeck       Detect version 2.6.3 (update installation fixed)
    2.6.4    2026-11-06  Wolfgang Baeck       Detect version 2.6.4 (SelfX logs in the device logs report)
    2.6.5    2026-11-06  Wolfgang Baeck       Detect version 2.6.5 (notifications per user)
    2.6.6    2026-11-06  Wolfgang Baeck       Detect version 2.6.6 (appearance Automatic)
    2.6.7    2026-11-16  Wolfgang Baeck       Detect version 2.6.7 (default appearance Automatic)
    2.6.8    2026-11-16  Wolfgang Baeck       Detect version 2.6.8 (neutral branding placeholders)
#>

$ExpectedVersion = '2.6.8'
$InstallFolder = Join-Path $env:ProgramFiles 'SelfX'
$ToolConfigFile = Join-Path $InstallFolder 'Tool_Config.xml'
$LogFolder = Join-Path $env:ProgramData 'SelfX\Logs'

# Detection runs standalone (without the package files): small own logger, only when SelfX was installed
# (the Logs folder exists and is protected by Install.ps1). Never creates folders, never fails detection.
function Write-DetectionLog {
	param([string]$Message)
	try {
		if (-not (Test-Path -LiteralPath $LogFolder -PathType Container)) { return }
		$path = Join-Path $LogFolder ('Detection_{0:yyyy-MM-dd}.log' -f [datetime]::Now)
		$line = '{0} | {1,-7} | {2,6} | {3}' -f [datetime]::Now.ToString('yyyy-MM-dd HH:mm:ss.fff'), 'Info', $PID, $Message
		[IO.File]::AppendAllText($path, $line + "`r`n", [Text.Encoding]::UTF8)
	} catch { }
}

function Exit-Detection {
	param([int]$Code, [string]$Reason)
	Write-DetectionLog ("SelfX {0}: {1}" -f $ExpectedVersion, $Reason)
	if ($Code -eq 0) { Write-Output "SelfX $ExpectedVersion is installed" }
	exit $Code
}

If(-not (Test-Path -LiteralPath (Join-Path $InstallFolder 'SelfXService.exe'))) { Exit-Detection 1 'not detected (SelfXService.exe missing)' }
If(-not (Test-Path -LiteralPath (Join-Path $InstallFolder 'SelfX.exe'))) { Exit-Detection 1 'not detected (SelfX.exe missing)' }
If(-not (Test-Path -LiteralPath $ToolConfigFile)) { Exit-Detection 1 'not detected (Tool_Config.xml missing)' }
# Registration is sufficient here; detection does not require the service to be running.
If(-not (Get-Service -Name 'SelfXService' -ErrorAction SilentlyContinue)) { Exit-Detection 1 'not detected (service SelfXService not registered)' }

# Compare the package catalog version, not the service protocol version.
$InstalledVersion = ([xml](Get-Content -LiteralPath $ToolConfigFile -Raw)).GUI_Config.Tool_Version
If("$InstalledVersion".Trim() -ne $ExpectedVersion) { Exit-Detection 1 "not detected (installed version $("$InstalledVersion".Trim()))" }

Exit-Detection 0 'detected'
