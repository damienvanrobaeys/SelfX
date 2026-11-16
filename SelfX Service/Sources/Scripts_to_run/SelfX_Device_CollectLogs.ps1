<#
.SYNOPSIS
    Collect the device logs with administrator rights and hand the report to the requesting user.

.DESCRIPTION
    Runs non-interactively as LOCAL SYSTEM through the local SelfX service and named pipe
    "SelfX.Service" when the user runs the action "Send device logs to the support" (catalog
    Post_Action MailReport). Starts the read-only collector Collect-DeviceLogs.ps1 from the same
    folder in a separate 64-bit Windows PowerShell and writes its single report to
    ProgramData\SelfX\Reports\<SID of the requesting user>\DeviceLogs-<computer>-<time>.txt.
    The report is compressed to a .zip file with the same name unless DeviceLogs_Compress is False
    in Tool_Config.xml. DeviceLogs_Days (1-60, default 7) sets the event log history.

    The logs of SelfX itself are added (2.6.4): the logs of the SelfX service and scripts in
    ProgramData\SelfX\Logs (SelfXService.log, Install.log and Uninstall.log always, the other
    *.log files of the last DeviceLogs_Days days) and the own logs of the requesting user in
    Logs\Users\<SID> (never those of other users). In the .zip they are separate files in the folder
    SelfX-Logs (SelfX-Logs\User for the user logs); in a .txt report they are appended as the last
    section. At most the last 2 MB of each file and 30 MB in total are added. Users can create their
    folder under Logs\Users, so the script reads there only from a normal folder (no junction) and
    only files the user owns, so no protected file of another account can get into the report.

    The SID comes from the service (SELFX_CALLER_SID, read from the pipe client token). The
    report folder gets a protected ACL: SYSTEM and administrators full control, the requesting
    user read only; no other user can read the report. Previous reports of that user are
    deleted before each run; reports of any user older than 7 days are deleted. The SelfX GUI
    then attaches the report to a new e-mail to the support (the GUI never runs as SYSTEM).

    The collector only reads the device (logs, registry, event logs, settings) and sends nothing.
    The report contains computer, user and tenant names and log content of this device.
    Does not restart Windows, sign out the user or change device settings.
    Exit 0 = report created; 1 = collection or compression failed;
    2 = requesting user unknown (no SELFX_CALLER_SID, e.g. SelfX service older than 2.4.0).

.PARAMETER ReportRoot
    Folder for the reports. Default: ProgramData\SelfX\Reports. Only for tests; the service
    starts the script without arguments.

.PARAMETER CollectorPath
    Path of Collect-DeviceLogs.ps1. Default: the same folder. Only for tests.

.PARAMETER ConfigPath
    Path of Tool_Config.xml. Default: the install folder. Only for tests.

.PARAMETER LogRoot
    Folder of the SelfX logs. Default: ProgramData\SelfX\Logs. Only for tests.

.NOTES
    Name    : SelfX_Device_CollectLogs.ps1
    Package : SelfX Service
    Context : System
    Version : 2.6.4

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.4.0    2026-11-02  Wolfgang Baeck       Initial version: device logs for the support by e-mail
    2.5.1    2026-11-04  Wolfgang Baeck       Fix: script paths resolved in the body ($PSScriptRoot is empty
                                              in parameter defaults of Windows PowerShell 5.1)
    2.6.0    2026-11-06  Wolfgang Baeck       Logging to ProgramData\SelfX\Logs (SelfXLog.ps1)
    2.6.4    2026-11-06  Wolfgang Baeck       The SelfX logs (service, scripts, own logs of the user) are added to the report
#>

[CmdletBinding()]
param(
    [string]$ReportRoot = (Join-Path $env:ProgramData 'SelfX\Reports'),
    [string]$CollectorPath,
    [string]$ConfigPath,
    [string]$LogRoot = (Join-Path $env:ProgramData 'SelfX\Logs')
)

# Windows PowerShell 5.1 leaves $PSScriptRoot empty in parameter defaults, so the paths are resolved here.
if (-not $CollectorPath) { $CollectorPath = Join-Path $PSScriptRoot 'Collect-DeviceLogs.ps1' }
if (-not $ConfigPath) { $ConfigPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Tool_Config.xml' }

# Returns a setting of Tool_Config.xml, or Default when the file or the value is missing.
function Get-ConfigValue {
    param([string]$ConfigPath, [string]$Name, [string]$Default)
    try {
        $config = New-Object System.Xml.XmlDocument
        $config.XmlResolver = $null
        $config.Load($ConfigPath)
        $node = $config.SelectSingleNode("/GUI_Config/$Name")
        if ($node -and -not [string]::IsNullOrWhiteSpace($node.InnerText)) { return $node.InnerText.Trim() }
    } catch { }
    return $Default
}

# Creates a folder and refuses junctions or symbolic links, so SYSTEM never writes through a link.
function New-SafeFolder {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -Force
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "'$Path' is not a normal folder."
        }
    } else {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# Replaces the ACL of a folder: SYSTEM and administrators full control, optional reader SID read only.
function Set-ReportAcl {
    param([string]$Path, [string]$ReaderSid)
    $grants = @('*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F')
    if ($ReaderSid) { $grants += "*$($ReaderSid):(OI)(CI)RX" }
    $icacls = Join-Path $env:SystemRoot 'System32\icacls.exe'
    $null = & $icacls $Path /inheritance:r /grant:r @grants
    if ($LASTEXITCODE -ne 0) { throw "icacls failed for '$Path' (exit code $LASTEXITCODE)." }
}

# Runs the collector in a separate 64-bit process, which keeps its settings and exit away from this script.
function Invoke-DeviceLogCollector {
    param([string]$CollectorPath, [string]$OutputPath, [int]$Days)
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    return @(& $powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $CollectorPath -OutputPath $OutputPath -Days $Days 2>&1)
}

# SelfX logs for the report: the logs of the SelfX service and scripts (ProgramData\SelfX\Logs, written by SYSTEM)
# and the own logs of the requesting user (Logs\Users\<caller SID>). Logs of other users are never added.
# Only *.log / *.log.old files changed in the last Days days; SelfXService.log, Install.log and Uninstall.log
# are always added. Users can create their folder under Logs\Users, so SYSTEM reads there only from a normal
# folder (no junction) and only files that the user owns (no hard link to a protected file of another account).
function Get-SelfXOwnLogFiles {
    param([string]$LogRoot, [string]$CallerSid, [int]$Days = 7)
    $files = New-Object System.Collections.Generic.List[object]
    if (-not $LogRoot -or -not (Test-Path -LiteralPath $LogRoot -PathType Container)) { return $files }
    $root = Get-Item -LiteralPath $LogRoot -Force
    if ($root.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $files }
    $limit = (Get-Date).AddDays(-$Days)
    $always = @('SelfXService.log', 'SelfXService.log.old', 'Install.log', 'Uninstall.log')
    foreach ($file in @(Get-ChildItem -LiteralPath $LogRoot -File -Force -ErrorAction SilentlyContinue | Sort-Object Name)) {
        if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if ($file.Name -notlike '*.log' -and $file.Name -notlike '*.log.old') { continue }
        if ($always -notcontains $file.Name -and $file.LastWriteTime -lt $limit) { continue }
        $files.Add([pscustomobject]@{ Path = $file.FullName; Entry = "SelfX-Logs\$($file.Name)" })
    }
    if ($CallerSid) {
        $userFolder = Join-Path (Join-Path $LogRoot 'Users') $CallerSid
        if (Test-Path -LiteralPath $userFolder -PathType Container) {
            $folder = Get-Item -LiteralPath $userFolder -Force
            if (-not ($folder.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                foreach ($file in @(Get-ChildItem -LiteralPath $userFolder -File -Force -ErrorAction SilentlyContinue | Sort-Object Name)) {
                    if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                    if ($file.Name -notlike '*.log' -or $file.LastWriteTime -lt $limit) { continue }
                    $owner = $null
                    try { $owner = [IO.File]::GetAccessControl($file.FullName, [Security.AccessControl.AccessControlSections]::Owner).GetOwner([Security.Principal.SecurityIdentifier]).Value } catch { }
                    if ($owner -ne $CallerSid) { continue }
                    $files.Add([pscustomobject]@{ Path = $file.FullName; Entry = "SelfX-Logs\User\$($file.Name)" })
                }
            }
        }
    }
    return $files
}

# Reads a log file that may still be written (shared read), at most the last MaxBytes bytes, as text.
function Read-SelfXLogText {
    param([string]$Path, [long]$MaxBytes = 2MB)
    $stream = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    try {
        $start = [Math]::Max(0, $stream.Length - $MaxBytes)
        [void]$stream.Seek($start, [IO.SeekOrigin]::Begin)
        $buffer = [byte[]]::new($stream.Length - $start)
        $read = 0
        while ($read -lt $buffer.Length) { $n = $stream.Read($buffer, $read, $buffer.Length - $read); if ($n -le 0) { break }; $read += $n }
        $text = [Text.Encoding]::UTF8.GetString($buffer, 0, $read).TrimStart([char]0xFEFF)
        if ($start -gt 0) { $text = "[... only the last $([Math]::Round($MaxBytes / 1MB)) MB of this file ...]`r`n" + $text }
        return $text
    } finally { $stream.Dispose() }
}

# Collects the report for the caller in SELFX_CALLER_SID and returns the exit code of the action.
function Invoke-SelfXCollectLogs {
    param([string]$ReportRoot, [string]$CollectorPath, [string]$ConfigPath, [int]$KeepDays = 7, [string]$LogRoot = '')
    $ErrorActionPreference = 'Stop'

    # The SID is set by the service from the client token; it is validated before it is used in a path.
    try {
        $callerSid = ([Security.Principal.SecurityIdentifier]::new("$env:SELFX_CALLER_SID")).Value
    } catch {
        Write-Output 'Requesting user unknown (SELFX_CALLER_SID missing or invalid). The SelfX service must be version 2.4.0 or later.'
        return 2
    }

    try {
        $days = 7
        $configuredDays = 0
        if ([int]::TryParse((Get-ConfigValue $ConfigPath 'DeviceLogs_Days' '7'), [ref]$configuredDays) -and $configuredDays -ge 1 -and $configuredDays -le 60) {
            $days = $configuredDays
        }
        $compress = (Get-ConfigValue $ConfigPath 'DeviceLogs_Compress' 'True') -ne 'False'

        if (-not (Test-Path -LiteralPath $CollectorPath -PathType Leaf)) { throw "Collector not found: $CollectorPath" }

        New-SafeFolder -Path $ReportRoot
        Set-ReportAcl -Path $ReportRoot
        $userFolder = Join-Path $ReportRoot $callerSid
        New-SafeFolder -Path $userFolder
        Set-ReportAcl -Path $userFolder -ReaderSid $callerSid

        # Only the latest report of a user is kept; old reports of all users are removed (privacy).
        Get-ChildItem -LiteralPath $userFolder -File -Force | Remove-Item -Force
        $limit = (Get-Date).AddDays(-$KeepDays)
        foreach ($folder in @(Get-ChildItem -LiteralPath $ReportRoot -Directory -Force |
                Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })) {
            Get-ChildItem -LiteralPath $folder.FullName -File -Force | Where-Object { $_.LastWriteTime -lt $limit } | Remove-Item -Force
            if ($folder.FullName -ne $userFolder -and -not (Get-ChildItem -LiteralPath $folder.FullName -Force)) {
                Remove-Item -LiteralPath $folder.FullName -Force
            }
        }

        $baseName = 'DeviceLogs-{0}-{1}' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmmss')
        $textFile = Join-Path $userFolder "$baseName.txt"

        $collectorOutput = @(Invoke-DeviceLogCollector -CollectorPath $CollectorPath -OutputPath $textFile -Days $days)
        # Only the summary (findings and the final line) goes to the bounded service log.
        $collectorOutput | Select-Object -Last 15 | ForEach-Object { Write-Output "$_" }

        if (-not (Test-Path -LiteralPath $textFile -PathType Leaf) -or (Get-Item -LiteralPath $textFile).Length -eq 0) {
            throw 'The collector did not create a report.'
        }

        $report = $textFile
        # SelfX logs (service, scripts, the own logs of the user); a problem here never fails the report.
        $ownLogs = @()
        try { $ownLogs = @(Get-SelfXOwnLogFiles -LogRoot $LogRoot -CallerSid $callerSid -Days $days) } catch { Write-Output "SelfX logs not added: $($_.Exception.Message)" }
        $logTotal = 0L
        $logLimit = 30MB
        if ($compress) {
            $zipFile = Join-Path $userFolder "$baseName.zip"
            Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
            $archive = [IO.Compression.ZipFile]::Open($zipFile, [IO.Compression.ZipArchiveMode]::Create)
            try {
                $null = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $textFile, "$baseName.txt", [IO.Compression.CompressionLevel]::Optimal)
                foreach ($log in $ownLogs) {
                    if ($logTotal -ge $logLimit) { Write-Output "SelfX logs: limit of 30 MB reached, $($log.Entry) and further files not added."; break }
                    try {
                        $bytes = [Text.Encoding]::UTF8.GetBytes((Read-SelfXLogText -Path $log.Path))
                        $entry = $archive.CreateEntry($log.Entry, [IO.Compression.CompressionLevel]::Optimal)
                        $stream = $entry.Open()
                        try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
                        $logTotal += $bytes.Length
                    } catch { Write-Output "SelfX log not added ($($log.Entry)): $($_.Exception.Message)" }
                }
            } finally {
                $archive.Dispose()
            }
            Remove-Item -LiteralPath $textFile -Force
            $report = $zipFile
        } elseif ($ownLogs.Count) {
            # Text report: the SelfX logs are appended as a last section.
            $section = [Text.StringBuilder]::new()
            [void]$section.AppendLine().AppendLine('=' * 100).AppendLine('SelfX logs (ProgramData\SelfX\Logs)').AppendLine('=' * 100)
            foreach ($log in $ownLogs) {
                if ($logTotal -ge $logLimit) { [void]$section.AppendLine('[limit of 30 MB reached, further SelfX logs not added]'); break }
                try {
                    $text = Read-SelfXLogText -Path $log.Path
                    [void]$section.AppendLine().AppendLine("----- $($log.Entry) -----").AppendLine($text)
                    $logTotal += $text.Length
                } catch { [void]$section.AppendLine("----- $($log.Entry): not readable ($($_.Exception.Message)) -----") }
            }
            [IO.File]::AppendAllText($textFile, $section.ToString(), [Text.UTF8Encoding]::new($false))
        }
        Write-Output ('SelfX logs added: {0} file(s)' -f $ownLogs.Count)

        Write-Output ('Report: {0} ({1} KB)' -f $report, [math]::Round((Get-Item -LiteralPath $report).Length / 1KB))
        return 0
    } catch {
        Write-Output "Collecting the device logs failed: $($_.Exception.Message)"
        return 1
    }
}

# Dot-sourcing (tests) only defines the functions; the service runs the script with -File.
if ($MyInvocation.InvocationName -ne '.') {
    # Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
    $SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
    if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
    else { function Write-SelfXLog { param($Message, $Level) } }
    $output = @(Invoke-SelfXCollectLogs -ReportRoot $ReportRoot -CollectorPath $CollectorPath -ConfigPath $ConfigPath -LogRoot $LogRoot)
    $exitCode = [int]($output | Select-Object -Last 1)
    $output | Select-Object -SkipLast 1 | ForEach-Object { Write-Output $_; Write-SelfXLog "$_" }
    Write-SelfXLog "Finished with exit code $exitCode." $(if ($exitCode) { 'Error' } else { 'Info' })
    exit $exitCode
}