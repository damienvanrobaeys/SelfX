<#
.SYNOPSIS
    Shared logging of the SelfX Service scripts in ProgramData\SelfX\Logs.

.DESCRIPTION
    Dot-sourced by every SelfX Service script (window, status icon, health checks, action and repair
    scripts). Initialize-SelfXLog selects the log file once; Write-SelfXLog appends one line per call.
    Logging never stops a script: all errors of the logger are ignored.

    Log files (one file per script and day, so the housekeeping can delete whole days):
      - SYSTEM and elevated administrators: %ProgramData%\SelfX\Logs\<Component>_<yyyy-MM-dd>.log
        (only SYSTEM and administrators can read this folder).
      - Users (SelfX window, status icon, user actions): %ProgramData%\SelfX\Logs\Users\<SID>\...
        Install.ps1 lets users create only their own folder (CREATOR OWNER) and not read the folders
        of other users. A folder that is a reparse point or belongs to another account is never used;
        then, and on installations without the Users folder, %LOCALAPPDATA%\SelfX\Logs is used.
    Line format: yyyy-MM-dd HH:mm:ss.fff | Level | PID | Message (local time of the device).

    Housekeeping: log files older than Log_Retention_Days of Tool_Config.xml (1-3650, default 90)
    are deleted. The SelfX service deletes old files in ProgramData\SelfX\Logs once a day. Each user
    deletes the old files of the own user log folder at most once a day when a SelfX script starts
    (with the rights of the user, so a manipulated user folder can never make SYSTEM delete files).

.NOTES
    Name    : SelfXLog.ps1
    Package : SelfX Service
    Context : User and System (dot-sourced)
    Version : 2.6.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.6.0    2026-11-06  Wolfgang Baeck       Initial version: shared logging and user-side log housekeeping
#>

$Script:SelfXLogState = $null

# Days to keep log files: Log_Retention_Days of Tool_Config.xml (1-3650), default 90.
function Get-SelfXLogRetentionDays {
	param([string]$ConfigPath = '')
	$days = 90
	try {
		if ($ConfigPath -and (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
			$xml = New-Object System.Xml.XmlDocument
			$xml.XmlResolver = $null
			$xml.Load($ConfigPath)
			$node = $xml.SelectSingleNode('/GUI_Config/Log_Retention_Days')
			$value = 0
			if ($node -and [int]::TryParse($node.InnerText.Trim(), [ref]$value) -and $value -ge 1 -and $value -le 3650) { $days = $value }
		}
	} catch { }
	return $days
}

# True for LOCAL SYSTEM and for elevated administrators (they may write to ProgramData\SelfX\Logs).
function Test-SelfXLogElevated {
	$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
	if ($identity.User.Value -eq 'S-1-5-18') { return $true }
	return ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Returns the user log folder Logs\Users\<SID> when it can be used safely, otherwise $null.
function Get-SelfXUserLogFolder {
	param([string]$UsersFolder, [string]$Sid)
	try {
		if (-not (Test-Path -LiteralPath $UsersFolder -PathType Container)) { return $null }
		$folder = Join-Path $UsersFolder $Sid
		if (-not (Test-Path -LiteralPath $folder -PathType Container)) { [void][IO.Directory]::CreateDirectory($folder) }
		$item = Get-Item -LiteralPath $folder -Force
		if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $null }
		# Another account could have created a folder with this name in advance: never write into it.
		$owner = (Get-Acl -LiteralPath $folder).GetOwner([Security.Principal.SecurityIdentifier]).Value
		if ($owner -ne $Sid) { return $null }
		return $folder
	} catch { return $null }
}

# Deletes *.log / *.old files older than RetentionDays in one folder (not recursive), at most once a day.
function Invoke-SelfXLogHousekeeping {
	param([string]$Folder, [int]$RetentionDays = 90, [switch]$Force)
	$deleted = 0
	try {
		if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { return 0 }
		$marker = Join-Path $Folder '.housekeeping'
		if (-not $Force -and (Test-Path -LiteralPath $marker -PathType Leaf) -and (Get-Item -LiteralPath $marker -Force).LastWriteTime.Date -eq [datetime]::Today) { return 0 }
		$limit = [datetime]::Now.AddDays(-$RetentionDays)
		foreach ($file in @(Get-ChildItem -LiteralPath $Folder -File -Force -ErrorAction Stop)) {
			if ($file.Extension -notin @('.log', '.old')) { continue }
			if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
			if ($file.LastWriteTime -ge $limit) { continue }
			try { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop; $deleted++ } catch { }
		}
		[IO.File]::WriteAllText($marker, [datetime]::Now.ToString('o'))
	} catch { }
	return $deleted
}

<#
.SYNOPSIS
    Selects the log file of the script. Call once at the start; Write-SelfXLog does nothing before.
.PARAMETER Component
    Name of the script (file name without extension), used in the log file name.
.PARAMETER DataRoot
    ProgramData\SelfX (tests use a temporary folder).
.PARAMETER ConfigPath
    Tool_Config.xml for Log_Retention_Days. Default: Tool_Config.xml in the folder of this file.
.PARAMETER Mode
    Auto (default) = by account. User / System force the folder (tests).
#>
function Initialize-SelfXLog {
	param(
		[Parameter(Mandatory = $true)][string]$Component,
		[string]$DataRoot = (Join-Path $env:ProgramData 'SelfX'),
		[string]$ConfigPath = '',
		[ValidateSet('Auto', 'User', 'System')][string]$Mode = 'Auto'
	)
	$Script:SelfXLogState = $null
	try {
		if (-not $ConfigPath -and $PSScriptRoot) { $ConfigPath = Join-Path $PSScriptRoot 'Tool_Config.xml' }
		$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
		$sid = $identity.User.Value
		$name = ($Component -replace '[^A-Za-z0-9_.-]', '_')
		if (-not $name) { $name = 'SelfX' }
		$logs = Join-Path $DataRoot 'Logs'
		$system = $(if ($Mode -eq 'Auto') { Test-SelfXLogElevated } else { $Mode -eq 'System' })
		$folder = $null
		$userFolder = $false
		if ($system) {
			[void][IO.Directory]::CreateDirectory($logs)
			$folder = $logs
		} else {
			$folder = Get-SelfXUserLogFolder -UsersFolder (Join-Path $logs 'Users') -Sid $sid
			if (-not $folder) {
				$folder = Join-Path $env:LOCALAPPDATA 'SelfX\Logs'
				[void][IO.Directory]::CreateDirectory($folder)
			}
			$userFolder = $true
		}
		$Script:SelfXLogState = [pscustomobject]@{ Folder = $folder; Component = $name; User = $identity.Name; Sid = $sid }
		$retention = Get-SelfXLogRetentionDays -ConfigPath $ConfigPath
		# The SYSTEM log folder is cleaned by the SelfX service; users clean only their own folder.
		if ($userFolder) { [void](Invoke-SelfXLogHousekeeping -Folder $folder -RetentionDays $retention) }
		$caller = ''
		if ($env:SELFX_CALLER_SID) { $caller = " for $($env:SELFX_CALLER_SID)" }
		Write-SelfXLog ("Start {0} as {1}{2} (PowerShell {3})." -f $name, $identity.Name, $caller, $PSVersionTable.PSVersion)
	} catch {
		$Script:SelfXLogState = $null
	}
}

# Path of the current log file (empty when logging is not initialized).
function Get-SelfXLogPath {
	$state = $Script:SelfXLogState
	if (-not $state) { return '' }
	return (Join-Path $state.Folder ('{0}_{1:yyyy-MM-dd}.log' -f $state.Component, [datetime]::Now))
}

<#
.SYNOPSIS
    Appends one line to the log file. Never throws.
#>
function Write-SelfXLog {
	param(
		[Parameter(Position = 0)][AllowEmptyString()][string]$Message = '',
		[Parameter(Position = 1)][ValidateSet('Info', 'Warning', 'Error')][string]$Level = 'Info'
	)
	$state = $Script:SelfXLogState
	if (-not $state) { return }
	try {
		$now = [datetime]::Now
		$path = Join-Path $state.Folder ('{0}_{1:yyyy-MM-dd}.log' -f $state.Component, $now)
		# Continuation lines of multi-line messages are indented, so every entry starts with its time.
		$text = ("$Message" -replace "`r", '') -replace "`n", "`r`n                                                 "
		$line = '{0} | {1,-7} | {2,6} | {3}' -f $now.ToString('yyyy-MM-dd HH:mm:ss.fff'), $Level, $PID, $text
		$bytes = [Text.Encoding]::UTF8.GetBytes($line + "`r`n")
		# Several SelfX processes can write at the same time: retry briefly while another one appends.
		for ($attempt = 0; $attempt -lt 10; $attempt++) {
			try {
				$stream = [IO.FileStream]::new($path, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::Read)
				try {
					# A new file starts with the UTF-8 byte order mark, so every viewer shows umlauts correctly.
					if ($stream.Length -eq 0) { $stream.Write([byte[]](0xEF, 0xBB, 0xBF), 0, 3) }
					$stream.Write($bytes, 0, $bytes.Length)
				} finally { $stream.Dispose() }
				return
			} catch {
				# PowerShell wraps .NET exceptions: only a sharing violation (IOException) is worth a retry.
				$exception = $_.Exception
				while ($exception.InnerException -and -not ($exception -is [IO.IOException])) { $exception = $exception.InnerException }
				if (-not ($exception -is [IO.IOException]) -or ($exception -is [IO.DirectoryNotFoundException])) { return }
				Start-Sleep -Milliseconds (20 + 20 * $attempt)
			}
		}
	} catch { }
}
