<#
.SYNOPSIS
    Collects all logs and system information that are needed to analyze a failed Autopilot /
    ESP deployment, a failed app (e.g. Install-DeviceLanguage) or a device problem, and merges
    them into ONE text file.

.DESCRIPTION
    Read-only: the script changes nothing on the device (no installation, no registry or
    task change, no hive is loaded, no restart). Run it on the affected notebook, elevated
    (administrator or SYSTEM, e.g. Shift+F10 during the ESP, or an elevated PowerShell after
    the ESP). Without elevation some machine logs are not readable; the report says so.
    Send the single output file for analysis. The file contains computer, user and tenant
    names and log content of this device only; the script sends nothing anywhere.

    Sections of the report:
      0  Automatic findings (at the END of the file and on the console): failed ESP apps with name,
         phase and decoded error, AppX volume problems, disk space, image language vs. profile
         language, failed language app runs
      1  Context: OS build, uptime, all drives and volumes, time, sessions, join state (dsregcmd)
      2  Windows setup / ESP state, Autopilot and Enrollment Status Page registry; ESP result per
         app for the device phase AND every user phase (app name from the IME logs, error decoded),
         ESP categories and subcategories with their state text
      3  Processes and services that compete with Install-Language (TiWorker, DISM, Windows Update ...)
      4  Pending restart indicators, servicing and Windows Update policies, proxy, time sync,
         network tests to the Windows Update / language pack download hosts
      5  Language state: current user, signed-in users, sign-in screen (.DEFAULT), system,
         installed languages and language packs (registry and file based; -Deep adds DISM queries)
      6  Swisscom deployment: markers, scheduled tasks with last result, files, version of the
         keyboard script
      7  Swisscom logs (complete; limited by -MaxLinesPerLog), including the first sign-in Store update log and state
      8  Intune Management Extension: log files, lines about the language apps and every app the
         ESP marked as failed or still running (found by name and by app ID), the AppWorkload.log
         context before each failure (download, install command, exit code), Win32Apps registry
         state of those apps (error codes), IMECache
      9  Windows servicing logs: CBS.log, DISM.log, setupact.log, ReportingEvents.txt
     10  Event logs of the last -Days days (setup, servicing, Windows Update, MDM, Autopilot, MUI,
         application and system errors)
     11  Crash reports (WER) of DISM / TiWorker / PowerShell
     12  AppX / MSIX deployment (e.g. new Teams, error 0x80073D3F "drive not found"): AppX volumes and
         default volume, package root, AppX policies (registry and Intune), Teams packages
         (installed and provisioned), Teams bootstrapper logs, AppX deployment event logs

.PARAMETER Days
    Days of event log history (default 7).

.PARAMETER MaxLinesPerLog
    Maximum number of lines per Swisscom log file (default 2500, the end of the file is used).

.PARAMETER Deep
    Also runs Get-WindowsCapability / Get-WindowsPackage / Get-AppxProvisionedPackage (DISM). They
    can take minutes and compete with a running installation. Use it only on an idle device.

.PARAMETER OutputPath
    Target file or folder. Default: as SYSTEM (Intune Win32 app or remediation) the fixed file
    C:\Windows\Temp\<computer>-DeviceLogs.log (uploaded by the Intune action "Collect diagnostics",
    overwritten by every run); otherwise DeviceLogs-<computer>-<time>.txt in C:\Windows\Temp
    (elevated) or %TEMP%.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Collect-DeviceLogs.ps1

.NOTES
    The same file is used as Intune Win32 app (Collect-DeviceLogs.intunewin) and as remediation script
    (on demand: device > Run remediation); detection for both: Detect-DeviceLogs.ps1.

.VERSION HISTORY
    Version  Author                    Comment
    -------  ------------------------  ------------------------------------------
    1.0.0    Wolfgang Baeck (Swisscom) Initial version
    1.0.1    Wolfgang Baeck (Swisscom) Does not read its own report; app IDs from the ESP tracking and the
                                       install log; AppWorkload.log lines about the language apps
    1.0.2    Wolfgang Baeck (Swisscom) Installed languages are listed per language (was System.Object[])
    1.0.3    Wolfgang Baeck (Swisscom) Lists the CBS folder and reads the rotated CBS logs (the failing session can be in an older file)
    1.1.0    Wolfgang Baeck (Swisscom) Holistic ESP analysis: result per app for the device and all user phases
                                       (name, decoded error), ESP categories, IME context before every failure,
                                       all drives/volumes, AppX/MSIX section (volumes, policies, Teams, event
                                       logs) and automatic findings at the end of the report
    1.1.1    Wolfgang Baeck (Swisscom) Checks the policy "Remove default Microsoft Store packages" (blocked apps, event 762;
                                       new Teams blocked -> 0x80073D3F, LAEAPTEST10); failure context anchored on the ESP failure line
    1.1.2    Wolfgang Baeck (Swisscom) Autopilot profile name also read from the policy cache (no false "No Autopilot profile" warning after the ESP)
    1.1.3    Wolfgang Baeck (Swisscom) Collects %windir%\Temp\Swisscom-FirstLogonStoreUpdate.log and the state of the one-time
                                       first sign-in Store update (Start-FirstLogonStoreUpdate.ps1)
    1.1.4    Wolfgang Baeck (Swisscom) Relaunches itself in 64-bit PowerShell (Intune Win32 app starts a 32-bit PowerShell)
    1.2.0    Wolfgang Baeck (Swisscom) Renamed from Collect-DeviceLanguageLogs.ps1 to Collect-DeviceLogs.ps1 (collects all logs
                                       relevant for an analysis, not only the language deployment); report DeviceLogs-<PC>-<time>.txt
    1.2.1    Wolfgang Baeck (Swisscom) As SYSTEM without -OutputPath the report is C:\Windows\Temp\<PC>-DeviceLogs.log, so the
                                       script runs unchanged as Win32 app and as on-demand remediation script
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 60)][int]$Days = 7,
    [ValidateRange(100, 20000)][int]$MaxLinesPerLog = 2500,
    [switch]$Deep,
    [string]$OutputPath
)

# Intune starts a 32-bit PowerShell; it would read the redirected registry and System32. Relaunch in 64-bit.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $ps64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $ps64) {
        $relaunchArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
        foreach ($name in $PSBoundParameters.Keys) {
            $value = $PSBoundParameters[$name]
            if ($value -is [switch]) { if ($value.IsPresent) { $relaunchArguments += "-$name" } }
            else { $relaunchArguments += "-$name"; $relaunchArguments += [string]$value }
        }
        & $ps64 @relaunchArguments
        exit $LASTEXITCODE
    }
}

$ScriptVersion = '1.2.1'
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$startedAt = Get-Date

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$isSystem = ($identity.User.Value -eq 'S-1-5-18')

if (-not $OutputPath -and $isSystem) {
    # Run by Intune (Win32 app or remediation): fixed name that "Collect diagnostics" uploads (%windir%\temp\%computername%*.log).
    $OutputPath = Join-Path $env:SystemRoot ('Temp\{0}-DeviceLogs.log' -f $env:COMPUTERNAME)
}
if (-not $OutputPath) { $OutputPath = if ($isAdmin) { Join-Path $env:SystemRoot 'Temp' } else { $env:TEMP } }
if (Test-Path -LiteralPath $OutputPath -PathType Container) {
    $outFile = Join-Path $OutputPath ('DeviceLogs-{0}-{1}.txt' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
else {
    $outFile = $OutputPath
}
$writer = New-Object System.IO.StreamWriter($outFile, $false, (New-Object System.Text.UTF8Encoding($true)))
$script:Problems = New-Object System.Collections.Generic.List[string]

function Add-Line { param([string]$Text) $writer.WriteLine($Text) }
function Add-Section {
    param([string]$Title)
    Add-Line ''
    Add-Line ('=' * 110)
    Add-Line $Title
    Add-Line ('=' * 110)
    Write-Host "  $Title"
}
function Invoke-Safe {
    param([string]$Label, [scriptblock]$Script)
    try {
        foreach ($line in @(& $Script)) { if ($null -ne $line) { Add-Line "$line" } }
    }
    catch {
        Add-Line "[collector] $Label failed: $($_.Exception.Message)"
        $script:Problems.Add("$Label : $($_.Exception.Message)")
    }
}
function Get-RegistryValues {
    param([string]$Path, [int]$MaxValueLength = 600)
    $item = Get-ItemProperty -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $item) { return "$Path : (key not found)" }
    foreach ($property in @($item.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS(Path|ParentPath|ChildName|Drive|Provider)$' })) {
        $text = (@($property.Value) -join ', ')
        if ($text.Length -gt $MaxValueLength) { $text = $text.Substring(0, $MaxValueLength) + '...' }
        '{0} : {1} = {2}' -f $Path, $property.Name, $text
    }
}
function Get-RegistryTree {
    param([string]$Path, [int]$MaxLines = 400, [int]$MaxValueLength = 600)
    if (-not (Test-Path -LiteralPath $Path)) { return "$Path : (key not found)" }
    $count = 0
    $keys = @(Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue) + @(Get-ChildItem -LiteralPath $Path -Recurse -ErrorAction SilentlyContinue)
    foreach ($key in $keys) {
        foreach ($line in @(Get-RegistryValues -Path $key.PSPath -MaxValueLength $MaxValueLength)) {
            if ($count -ge $MaxLines) { return "... truncated after $MaxLines lines" }
            $count++
            $line -replace '^Microsoft\.PowerShell\.Core\\Registry::', ''
        }
    }
}
function Get-FileText {
    param([string]$Path, [int]$Tail)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    $header = '--- {0}  (size {1} bytes, last write {2})' -f $item.FullName, $item.Length, $item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
    $header
    @(Get-Content -LiteralPath $Path -Tail $Tail -ErrorAction Stop | ForEach-Object { "    $_" })
}
function Add-FileTail {
    param([string]$Path, [int]$Tail = 200)
    Add-Line ''
    try { foreach ($line in @(Get-FileText -Path $Path -Tail $Tail)) { Add-Line $line } }
    catch { Add-Line "--- $Path : not readable: $($_.Exception.Message)" }
}
function Add-FilteredLines {
    param([string]$Path, [string]$Pattern, [int]$Last = 150, [string]$Title)
    try {
        $matches = @(Select-String -LiteralPath $Path -Pattern $Pattern -ErrorAction Stop | Select-Object -Last $Last)
        Add-Line ''
        Add-Line "--- $Title (last $Last lines matching; file $Path)"
        if (-not $matches.Count) { Add-Line '    (none)' }
        foreach ($match in $matches) {
            $text = $match.Line
            if ($text.Length -gt 600) { $text = $text.Substring(0, 600) + '...' }
            Add-Line "    [$($match.LineNumber)] $text"
        }
    }
    catch { Add-Line "--- $Title : $Path not readable: $($_.Exception.Message)" }
}
function Get-EventSummary {
    param([string]$LogName, [int[]]$Level, [int]$Max = 60, [string]$ProviderLike, [string]$MessageLike)
    $filter = @{ LogName = $LogName; StartTime = (Get-Date).AddDays(-$Days) }
    if ($Level) { $filter['Level'] = $Level }
    $events = @(Get-WinEvent -FilterHashtable $filter -MaxEvents $(if ($MessageLike) { 10000 } else { 2000 }) -ErrorAction SilentlyContinue)
    if ($ProviderLike) { $events = @($events | Where-Object { $_.ProviderName -match $ProviderLike }) }
    if ($MessageLike) { $events = @($events | Where-Object { "$($_.Message)" -match $MessageLike }) }
    $events = @($events | Select-Object -First $Max)
    $levelText = if ($Level) { "levels $($Level -join ',')" } else { 'all levels' }
    if ($MessageLike) { $levelText += "; message matches '$MessageLike'" }
    "--- $LogName ($levelText; $($events.Count) events, newest first, last $Days days)"
    foreach ($event in $events) {
        $message = ("$($event.Message)" -replace '\s+', ' ').Trim()
        if ($message.Length -gt 450) { $message = $message.Substring(0, 450) + '...' }
        '    {0} id={1} lvl={2} {3}: {4}' -f $event.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'), $event.Id, $event.LevelDisplayName, $event.ProviderName, $message
    }
}
function Test-Port {
    param([string]$HostName, [int]$Port, [int]$TimeoutMs = 4000)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $ips = @([System.Net.Dns]::GetHostAddresses($HostName) | Select-Object -First 3 | ForEach-Object { $_.ToString() })
        $task = $client.ConnectAsync($HostName, $Port)
        $ok = $task.Wait($TimeoutMs) -and $client.Connected
        '{0}:{1} dns={2} tcp={3}' -f $HostName, $Port, ($ips -join ','), $(if ($ok) { 'OK' } else { 'FAILED/timeout' })
    }
    catch {
        '{0}:{1} FAILED: {2}' -f $HostName, $Port, $_.Exception.GetBaseException().Message
    }
    finally { $client.Dispose() }
}
function Get-ProfileSettings {
    param([string]$Root)
    Get-RegistryValues -Path "$Root\Control Panel\Desktop" | Where-Object { $_ -match 'PreferredUILanguages|WinUILanguageOverride|MachinePreferredUILanguages|key not found' }
    Get-RegistryValues -Path "$Root\Control Panel\Desktop\MuiCached"
    Get-RegistryValues -Path "$Root\Control Panel\International\User Profile"
    Get-RegistryValues -Path "$Root\Control Panel\International" | Where-Object { $_ -match 'LocaleName|\bLocale\b|sLanguage|sShortDate|sLongDate|sShortTime|sTimeFormat|key not found' }
    Get-RegistryValues -Path "$Root\Control Panel\International\Geo"
    Get-RegistryValues -Path "$Root\Keyboard Layout\Preload"
    Get-RegistryValues -Path "$Root\Keyboard Layout\Substitutes"
    $profileKey = Get-Item -LiteralPath "$Root\Control Panel\International\User Profile" -ErrorAction SilentlyContinue
    if ($profileKey) {
        foreach ($subKey in @($profileKey.GetSubKeyNames())) {
            $values = Get-ItemProperty -LiteralPath "$Root\Control Panel\International\User Profile\$subKey" -ErrorAction SilentlyContinue
            $names = @($values.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value })
            "$Root\...\User Profile\$subKey : $($names -join '; ')"
        }
    }
}

$script:Findings = New-Object System.Collections.Generic.List[string]
function Add-Finding {
    param([ValidateSet('ERROR', 'WARN', 'INFO')][string]$Level, [string]$Text)
    $script:Findings.Add("[$Level] $Text")
}

# HRESULT as 0xXXXXXXXX with a description: known Intune / servicing / AppX codes first, then the Windows
# text of FACILITY_WIN32 codes (0x8007xxxx, includes the AppX deployment errors 0x80073Cxx / 0x80073Dxx).
function Get-HResultText {
    param($Code)
    if ($null -eq $Code -or "$Code" -eq '') { return '' }
    $value = [int64]$Code
    if ($value -lt 0) { $value += 4294967296 }
    $hex = '0x{0:X8}' -f $value
    $known = @{
        '0x80070001' = 'Win32 app returned exit code 1 (the ESP shows the exit code as 0x8007xxxx); see the log of the app'
        '0x80073D3F' = 'ERROR_INSTALL_DRIVE_NOT_FOUND: the drive referenced during package (AppX/MSIX) deployment was not found - also reported when the policy "Remove default Microsoft Store packages" blocks the package (AppXDeploymentServer event 762); check section 12'
        '0x87D1041C' = 'Intune: the application was not detected after the installation finished (detection rule)'
        '0x800F0922' = 'CBS_E_INSTALLERS_FAILED: servicing could not apply the package (see CBS.log at that time)'
    }
    if ($known.ContainsKey($hex)) { return "$hex ($($known[$hex]))" }
    if ((($value -shr 16) -band 0x1FFF) -eq 7) {
        $win32 = [int]($value -band 0xFFFF)
        $text = (New-Object System.ComponentModel.Win32Exception($win32)).Message
        if ($win32 -lt 256) { $text += " - for a Win32 app this can also be the exit code $win32 of the installer" }
        return "$hex (Win32 $win32 : $text)"
    }
    return $hex
}

# App ID -> app name from the IME logs (content info requests and ESP manager lines).
function Get-ImeAppNames {
    if ($script:AppNames) { return $script:AppNames }
    $script:AppNames = @{}
    $files = @(Get-ChildItem -LiteralPath $imeFolder -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(AppWorkload|IntuneManagementExtension).*\.log$' })
    foreach ($file in $files) {
        foreach ($match in @(Select-String -LiteralPath $file.FullName -Pattern '"ApplicationName":"[^"]+"|with name: ' -ErrorAction SilentlyContinue)) {
            foreach ($m in [regex]::Matches($match.Line, '"ApplicationId":"([0-9a-fA-F-]{36})","ApplicationVersion":"[^"]*","ApplicationName":"([^"]+)"')) {
                $script:AppNames[$m.Groups[1].Value.ToLowerInvariant()] = $m.Groups[2].Value
            }
            $m = [regex]::Match($match.Line, 'application ([0-9a-fA-F-]{36}) with name: (.+?)\.?\]LOG\]')
            if ($m.Success) { $script:AppNames[$m.Groups[1].Value.ToLowerInvariant()] = $m.Groups[2].Value }
        }
    }
    return $script:AppNames
}

$imeFolder = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
# Apps to analyze in the IME logs: the language apps and every app the ESP marked as failed / running.
$languageAppIds = New-Object System.Collections.Generic.HashSet[string]
$script:FailedEspApps = New-Object System.Collections.Generic.List[object]

Write-Host "Collect-DeviceLogs $ScriptVersion - read-only. Output: $outFile"
if (-not $isAdmin) { Write-Host 'WARNING: not elevated. Machine logs may not be readable. Run as administrator for a complete report.' -ForegroundColor Yellow }

try {
Add-Line "Collect-DeviceLogs $ScriptVersion (read-only device log collector: Autopilot / ESP, apps, Swisscom language deployment)"
Add-Line "Started: $($startedAt.ToString('yyyy-MM-dd HH:mm:ss')); parameters: Days=$Days; MaxLinesPerLog=$MaxLinesPerLog; Deep=$($Deep.IsPresent)"

# ------------------------------------------------------------------------------------------------
Add-Section '1. Context'
Add-Line "Computer         : $env:COMPUTERNAME"
Add-Line "Identity         : $($identity.Name) ($($identity.User.Value)); elevated=$isAdmin; SYSTEM=$isSystem; 64-bit process=$([Environment]::Is64BitProcess); PowerShell $($PSVersionTable.PSVersion)"
Invoke-Safe 'OS' {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $ubr = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue)
    "OS               : $($os.Caption) $($os.Version) (UBR $($ubr.UBR)); DisplayVersion=$($ubr.DisplayVersion); edition=$($ubr.EditionID); build lab=$($ubr.BuildLabEx)"
    "OS language      : MUILanguages=$($os.MUILanguages -join ','); OSLanguage=$($os.OSLanguage); CountryCode=$($os.CountryCode); Locale=$($os.Locale)"
    "Boot / uptime    : last boot $($os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss')); uptime $([int]((Get-Date) - $os.LastBootUpTime).TotalMinutes) minutes; now $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) (UTC offset $([TimeZoneInfo]::Local.GetUtcOffset((Get-Date))))"
    "Memory (MB)      : total $([int]($os.TotalVisibleMemorySize / 1024)); free $([int]($os.FreePhysicalMemory / 1024))"
    "OS install date  : $($os.InstallDate.ToString('yyyy-MM-dd HH:mm:ss'))"
}
Invoke-Safe 'Computer' {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue
    "Hardware         : $($cs.Manufacturer) $($cs.Model); serial $($bios.SerialNumber); console user '$($cs.UserName)'; domain/workgroup '$($cs.Domain)'"
}
Invoke-Safe 'Disk' {
    $types = @{ 0 = 'unknown'; 1 = 'no root'; 2 = 'removable'; 3 = 'local'; 4 = 'network'; 5 = 'CD/DVD/ISO'; 6 = 'RAM disk' }
    foreach ($disk in @(Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction Stop)) {
        $free = if ($disk.Size) { '{0} GB free of {1} GB' -f [math]::Round($disk.FreeSpace / 1GB, 1), [math]::Round($disk.Size / 1GB, 1) } else { 'no media / size unknown' }
        'Drive {0,-3}        : {1}; type {2}; file system {3}; label "{4}"' -f $disk.DeviceID, $free, $types[[int]$disk.DriveType], $disk.FileSystem, $disk.VolumeName
        if ($disk.DeviceID -eq $env:SystemDrive -and $disk.Size -and ($disk.FreeSpace / 1GB) -lt 6) {
            Add-Finding -Level ERROR -Text ('System drive {0} has only {1} GB free; language packs and app installations need several GB (0x80070070 = disk full).' -f $disk.DeviceID, [math]::Round($disk.FreeSpace / 1GB, 1))
        }
    }
    'Volumes without drive letter:'
    foreach ($volume in @(Get-CimInstance -ClassName Win32_Volume -ErrorAction SilentlyContinue | Where-Object { -not $_.DriveLetter })) {
        '    {0} label "{1}" {2} GB, {3} GB free, {4}' -f $volume.DeviceID, $volume.Label, [math]::Round($volume.Capacity / 1GB, 2), [math]::Round($volume.FreeSpace / 1GB, 2), $volume.FileSystem
    }
}
Invoke-Safe 'Time zone' { "Time zone        : $((Get-TimeZone).Id)" }
Invoke-Safe 'Sessions' {
    'Sessions (query user / quser):'
    @(& "$env:SystemRoot\System32\quser.exe" 2>&1) | ForEach-Object { "    $_" }
}
Invoke-Safe 'dsregcmd' {
    'dsregcmd /status (join state, tenant, MDM):'
    @(& "$env:SystemRoot\System32\dsregcmd.exe" /status 2>&1) | Where-Object { $_ -match ':' } | ForEach-Object { "    $_" } | Select-Object -First 120
}
Invoke-Safe 'Loaded profiles' {
    'ProfileList:'
    foreach ($key in @(Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -ErrorAction SilentlyContinue)) {
        $path = [string](Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue).ProfileImagePath
        $created = ''
        if ($path -and (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue)) { $created = (Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue).CreationTime.ToString('yyyy-MM-dd HH:mm:ss') }
        '    {0}  {1}  folder created {2}; hive loaded={3}' -f $key.PSChildName, $path, $created, (Test-Path -LiteralPath "Registry::HKEY_USERS\$($key.PSChildName)")
    }
}

# ------------------------------------------------------------------------------------------------
Add-Section '2. Windows setup / ESP / Autopilot state'
Invoke-Safe 'OOBE API' {
    if (-not ('Swisscom.LanguageDeployment.Collector' -as [type])) {
        Add-Type -Namespace Swisscom.LanguageDeployment -Name Collector -MemberDefinition '[DllImport("kernel32.dll", SetLastError = true)] public static extern bool OOBEComplete(out int isOOBEComplete);'
    }
    $completed = 0
    $ok = [Swisscom.LanguageDeployment.Collector]::OOBEComplete([ref]$completed)
    "OOBEComplete API : ok=$ok completed=$completed"
}
Invoke-Safe 'Setup registry' {
    $setup = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\Setup' -ErrorAction Stop
    "HKLM\SYSTEM\Setup: OOBEInProgress=$($setup.OOBEInProgress); SystemSetupInProgress=$($setup.SystemSetupInProgress); SetupType=$($setup.SetupType); CmdLine='$($setup.CmdLine)'"
}
Invoke-Safe 'Setup processes' {
    $names = 'CloudExperienceHost', 'CloudExperienceHostBroker', 'oobe', 'msoobe', 'wwahost', 'SetupHost', 'WWAHost'
    $found = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -in $names })
    'Setup/ESP processes: ' + $(if ($found.Count) { ($found | ForEach-Object { "$($_.Name)($($_.Id))" }) -join ', ' } else { '(none)' })
}
Invoke-Safe 'Autopilot registry' {
    Get-RegistryTree -Path 'HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\Autopilot' -MaxLines 150
    Get-RegistryTree -Path 'HKLM:\SOFTWARE\Microsoft\Provisioning\AutopilotSettings' -MaxLines 80
    Get-RegistryTree -Path 'HKLM:\SOFTWARE\Microsoft\Provisioning\AutopilotPolicyCache' -MaxLines 80
}
Invoke-Safe 'ESP tracking' {
    Get-RegistryTree -Path 'HKLM:\SOFTWARE\Microsoft\Windows\Autopilot\EnrollmentStatusTracking' -MaxLines 400 -MaxValueLength 300
}
Invoke-Safe 'Enrollments' {
    foreach ($key in @(Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue)) {
        $values = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
        if ($values.ProviderID -eq 'MS DM Server' -or $values.EnrollmentType) {
            'Enrollment {0}: ProviderID={1}; EnrollmentType={2}; EnrollmentState={3}; UPN={4}' -f $key.PSChildName, $values.ProviderID, $values.EnrollmentType, $values.EnrollmentState, $values.UPN
            Get-RegistryTree -Path "$($key.PSPath)\FirstSync" -MaxLines 20
        }
    }
}
# The ESP pages as stored by Windows (JSON): state and text of every category / subcategory.
Invoke-Safe 'ESP categories' {
    ''
    '--- ESP categories (AutopilotSettings *Category.Status*, as shown on the ESP screen)'
    $settings = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Provisioning\AutopilotSettings' -ErrorAction Stop
    foreach ($property in @($settings.PSObject.Properties | Where-Object { $_.Name -like '*Category.Status*' } | Sort-Object Name)) {
        try { $json = "$($property.Value)" | ConvertFrom-Json -ErrorAction Stop }
        catch { "    $($property.Name): not readable as JSON"; continue }
        '    {0}: {1}' -f $property.Name, $json.categoryState
        foreach ($sub in @($json.PSObject.Properties | Where-Object { $_.Value -is [System.Management.Automation.PSCustomObject] })) {
            '        {0}: {1} - {2}' -f $sub.Name, $sub.Value.subcategoryState, $sub.Value.subcategoryStatusText
            if ("$($sub.Value.subcategoryState)" -eq 'failed') {
                Add-Finding -Level ERROR -Text "ESP $($property.Name) / $($sub.Name) failed: $($sub.Value.subcategoryStatusText)"
            }
        }
    }
}
# Every tracked app of the device phase (Device) and of each user phase (user SID), with name and error.
Invoke-Safe 'ESP app results' {
    ''
    '--- ESP app results (InstallationState: 1=not installed, 2=in progress, 3=completed, 4=failed)'
    $names = Get-ImeAppNames
    $guidPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
    $espRoot = 'HKLM:\SOFTWARE\Microsoft\Windows\Autopilot\EnrollmentStatusTracking'
    $count = 0
    foreach ($phase in @(Get-ChildItem -LiteralPath $espRoot -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -ne 'ESPTrackingInfo' })) {
        $phaseName = if ($phase.PSChildName -eq 'Device') { 'device setup' } else { "account setup ($($phase.PSChildName))" }
        foreach ($provider in @(Get-ChildItem -LiteralPath "$($phase.PSPath)\Setup\Apps\Tracking" -ErrorAction SilentlyContinue)) {
            foreach ($app in @(Get-ChildItem -LiteralPath $provider.PSPath -ErrorAction SilentlyContinue)) {
                $count++
                $values = Get-ItemProperty -LiteralPath $app.PSPath -ErrorAction SilentlyContinue
                $id = ([regex]::Match($app.PSChildName, $guidPattern)).Value.ToLowerInvariant()
                $name = if ($id -and $names.ContainsKey($id)) { $names[$id] } else { '(name not in the IME logs)' }
                $errorText = Get-HResultText $values.ErrorHresult
                '    [{0}] {1} {2}: state={3}{4}' -f $phaseName, $app.PSChildName, $name, $values.InstallationState, $(if ($errorText) { "; error $errorText" } else { '' })
                if ($values.InstallationState -in 2, 4 -and $id) {
                    $null = $languageAppIds.Add($id)
                }
                if ($values.InstallationState -eq 4) {
                    $script:FailedEspApps.Add([pscustomobject]@{ Id = $id; Name = $name; Phase = $phaseName; Error = $errorText })
                    Add-Finding -Level ERROR -Text "ESP app failed in $phaseName : $name ($($app.PSChildName)), error $errorText"
                }
            }
        }
    }
    if (-not $count) { '    (no tracked apps; the ESP did not track apps on this device or the keys were removed)' }
}
# The Autopilot profile language can only be used in OOBE if its language pack is in the image.
Invoke-Safe 'Profile language vs image' {
    $profileLanguage = [string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\Autopilot' -ErrorAction SilentlyContinue).CloudAssignedLanguage
    $profileName = [string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\Autopilot' -ErrorAction SilentlyContinue).DeploymentProfileName
    if (-not $profileName) {
        # After the ESP the name can be only in the policy cache (JSON).
        $cache = [string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Provisioning\AutopilotPolicyCache' -ErrorAction SilentlyContinue).PolicyJsonCache
        $match = [regex]::Match($cache, '"DeploymentProfileName"\s*:\s*"([^"]+)"')
        if ($match.Success) { $profileName = $match.Groups[1].Value }
    }
    $imageLanguages = @((Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).MUILanguages)
    ''
    "Autopilot profile '$profileName': language '$profileLanguage'; language packs in the image (MUILanguages): $($imageLanguages -join ', ')"
    if (-not $profileName) {
        Add-Finding -Level WARN -Text 'No Autopilot profile downloaded (DeploymentProfileName missing): check the profile assignment / group tag and the network during OOBE.'
    }
    if ($profileLanguage -and $profileLanguage -notin '', 'os-default', 'user-select') {
        $pack = switch -Regex ($profileLanguage) { '^de-' { 'de-DE' } '^fr-' { 'fr-FR' } '^it-' { 'it-IT' } default { $profileLanguage } }
        if ($pack -notin $imageLanguages) {
            Add-Finding -Level WARN -Text "Autopilot profile language $profileLanguage needs the language pack $pack, which is not in the image ($($imageLanguages -join ', ')): OOBE stays in the image language and the pack must be downloaded during the ESP (about 30 minutes, needs Windows Update)."
        }
    }
}

# ------------------------------------------------------------------------------------------------
Add-Section '3. Processes and services that compete with Install-Language'
Invoke-Safe 'Processes' {
    $pattern = 'TiWorker|TrustedInstaller|dism|wusa|msiexec|wuauclt|usocoreworker|UpdateAssistant|MoUsoCoreWorker|SetupHost|IntuneManagementExtension|AgentExecutor|powershell|pwsh|CloudExperienceHost|InstallAgent|musnotification|sihclient|MusNotificationUx'
    $processes = @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop | Where-Object { $_.Name -match $pattern })
    foreach ($process in $processes) {
        $cmd = "$($process.CommandLine)"
        if ($cmd.Length -gt 300) { $cmd = $cmd.Substring(0, 300) + '...' }
        $started = if ($process.CreationDate) { $process.CreationDate.ToString('HH:mm:ss') } else { '' }
        '{0} pid={1} started={2} ws={3}MB cmd={4}' -f $process.Name, $process.ProcessId, $started, [int]($process.WorkingSetSize / 1MB), $cmd
    }
    if (-not $processes.Count) { '(no matching process)' }
}
Invoke-Safe 'CPU' {
    $samples = @(Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop)
    "CPU load now     : $($samples[0].PercentProcessorTime) %"
}
Invoke-Safe 'Services' {
    $names = 'wuauserv', 'TrustedInstaller', 'BITS', 'UsoSvc', 'InstallService', 'CryptSvc', 'DoSvc', 'IntuneManagementExtension', 'Schedule', 'W32Time', 'AppXSvc', 'ClipSVC', 'AppReadiness', 'StateRepository', 'WaaSMedicSvc', 'sppsvc'
    foreach ($name in $names) {
        $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$name'" -ErrorAction SilentlyContinue
        if ($service) { '{0,-26} state={1}; start mode={2}; account={3}' -f $name, $service.State, $service.StartMode, $service.StartName }
        else { '{0,-26} (not installed)' -f $name }
    }
}

# ------------------------------------------------------------------------------------------------
Add-Section '4. Restart indicators, servicing / Windows Update policy, proxy, time, network'
Invoke-Safe 'Pending restart' {
    $indicators = [ordered]@{
        'CBS RebootPending'            = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
        'CBS RebootInProgress'         = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress'
        'CBS PackagesPending'          = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending'
        'CBS SessionsPending'          = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\SessionsPending'
        'WU RebootRequired'            = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        'WU PostRebootReporting'       = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\PostRebootReporting'
        'Updates UpdateExeVolatile'    = 'HKLM:\SOFTWARE\Microsoft\Updates\UpdateExeVolatile'
    }
    foreach ($name in $indicators.Keys) { '{0,-28}: {1}' -f $name, $(if (Test-Path -LiteralPath $indicators[$name]) { 'PRESENT' } else { 'no' }) }
    $session = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue
    'PendingFileRenameOperations : ' + $(if ($session.PendingFileRenameOperations) { (@($session.PendingFileRenameOperations | Where-Object { $_ }) | Select-Object -First 10) -join ' | ' } else { 'no' })
    foreach ($file in 'C:\Windows\WinSxS\pending.xml', 'C:\Windows\WinSxS\poqexec.log') { if (Test-Path -LiteralPath $file) { "File present: $file" } }
}
Invoke-Safe 'Servicing policy' {
    Get-RegistryValues -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Servicing'
    Get-RegistryTree -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -MaxLines 60
    Get-RegistryTree -Path 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update' -MaxLines 80 -MaxValueLength 200
    Get-RegistryValues -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'
    Get-RegistryValues -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers' | Select-Object -First 0
    Get-RegistryTree -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanguagePackManagement' -MaxLines 20
    Get-RegistryTree -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Control Panel\International' -MaxLines 20
    Get-RegistryTree -Path 'HKLM:\SOFTWARE\Policies\Microsoft\MUI' -MaxLines 20
    Get-RegistryTree -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -MaxLines 40 | Where-Object { $_ -match 'Language|Locale|Update|Store|Block' }
    Get-RegistryTree -Path 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore' -MaxLines 20
}
Invoke-Safe 'Proxy' {
    'netsh winhttp show proxy:'
    @(& "$env:SystemRoot\System32\netsh.exe" winhttp show proxy 2>&1) | Where-Object { $_ } | ForEach-Object { "    $_" }
    Get-RegistryValues -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\Internet Settings'
    Get-RegistryValues -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' | Where-Object { $_ -match 'Proxy|AutoConfig' }
}
Invoke-Safe 'Time sync' {
    'w32tm /query /status:'
    @(& "$env:SystemRoot\System32\w32tm.exe" /query /status 2>&1) | Where-Object { $_ } | Select-Object -First 12 | ForEach-Object { "    $_" }
}
Invoke-Safe 'Network' {
    'TCP tests (hosts used by Windows Update / language pack download):'
    foreach ($target in @(
            @('download.windowsupdate.com', 80), @('fe2cr.update.microsoft.com', 443), @('fe3cr.delivery.mp.microsoft.com', 443),
            @('dl.delivery.mp.microsoft.com', 80), @('tsfe.trafficshaping.dsp.mp.microsoft.com', 443), @('slscr.update.microsoft.com', 443),
            @('sls.update.microsoft.com', 443), @('login.microsoftonline.com', 443), @('manage.microsoft.com', 443)
        )) { '    ' + (Test-Port -HostName $target[0] -Port $target[1]) }
    'Network adapters up:'
    Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=true' -ErrorAction SilentlyContinue | ForEach-Object { '    {0}: IP {1}; DNS {2}' -f $_.Description, ($_.IPAddress -join ','), ($_.DNSServerSearchOrder -join ',') }
}

# ------------------------------------------------------------------------------------------------
Add-Section '5. Language state'
Invoke-Safe 'International current' {
    Import-Module International -ErrorAction Stop
    "Context of this report: $($identity.Name)"
    "Get-WinUILanguageOverride          : '$(Get-WinUILanguageOverride)'"
    "Get-Culture                        : $((Get-Culture).Name)"
    "Get-WinDefaultInputMethodOverride  : '$((Get-WinDefaultInputMethodOverride).InputMethodTip)'"
    "Get-WinHomeLocation                : GeoId $((Get-WinHomeLocation).GeoId)"
    $languageList = Get-WinUserLanguageList
    'Get-WinUserLanguageList            : ' + (($languageList | ForEach-Object { '{0}[{1}]' -f $_.LanguageTag, ($_.InputMethodTips -join ',') }) -join '; ')
    "Get-SystemPreferredUILanguage      : $(Get-SystemPreferredUILanguage)"
    "Get-WinSystemLocale                : $((Get-WinSystemLocale).Name)"
}
Invoke-Safe 'HKCU' {
    'Current user hive (HKCU):'
    Get-ProfileSettings -Root 'HKCU:'
    Get-RegistryValues -Path 'HKCU:\Software\Swisscom\LanguageDeployment'
}
Invoke-Safe 'Loaded user hives' {
    foreach ($key in @(Get-ChildItem -LiteralPath 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^S-1-(5-21|12-1)-[\d-]+$' })) {
        "Loaded user hive $($key.PSChildName):"
        Get-ProfileSettings -Root "Registry::HKEY_USERS\$($key.PSChildName)"
    }
}
Invoke-Safe 'HKU .DEFAULT' {
    'Sign-in screen / SYSTEM profile (HKEY_USERS\.DEFAULT):'
    Get-ProfileSettings -Root 'Registry::HKEY_USERS\.DEFAULT'
}
Invoke-Safe 'Installed languages' {
    Import-Module LanguagePackManagement -ErrorAction Stop
    'Get-InstalledLanguage:'
    # Get-InstalledLanguage returns its list as ONE object; enumerate it per language.
    foreach ($item in (Get-InstalledLanguage)) { foreach ($language in @($item)) { '    {0}: packs={1}; features={2}' -f $language.LanguageId, (@($language.LanguagePacks) -join ','), (@($language.LanguageFeatures) -join ',') } }
}
Invoke-Safe 'File based language check' {
    'MUI language folders in C:\Windows\System32 (xx-XX with a *.mui file):'
    foreach ($folder in @(Get-ChildItem -LiteralPath "$env:SystemRoot\System32" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^[a-z]{2,3}-[A-Za-z0-9-]+$' })) {
        '    {0}  created {1}' -f $folder.Name, $folder.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')
    }
    'C:\Windows\LanguagePacks: ' + $(if (Test-Path "$env:SystemRoot\LanguagePacks") { ((Get-ChildItem "$env:SystemRoot\LanguagePacks" -ErrorAction SilentlyContinue | ForEach-Object Name) -join ', ') } else { '(not present)' })
    Get-RegistryValues -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\MUI\Settings'
    Get-RegistryValues -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language'
}
Invoke-Safe 'CBS language packages' {
    $packages = @(Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match 'LanguagePack|Language-Pack|LanguageFeatures|Client-LanguagePack' })
    'CBS packages with language pack / features (registry, name | state | install time):'
    foreach ($package in ($packages | Sort-Object PSChildName)) {
        $values = Get-ItemProperty -LiteralPath $package.PSPath -ErrorAction SilentlyContinue
        $time = ''
        if ($values.InstallTimeHigh -ne $null -and $values.InstallTimeLow -ne $null) {
            try { $time = [DateTime]::FromFileTime([int64]$values.InstallTimeHigh * 4294967296 + [uint32]$values.InstallTimeLow).ToString('yyyy-MM-dd HH:mm:ss') } catch { }
        }
        '    {0} | CurrentState={1} | LastError={2} | {3}' -f $package.PSChildName, $values.CurrentState, $values.LastError, $time
    }
    if (-not $packages.Count) { '    (none found)' }
}
if ($Deep) {
    Invoke-Safe 'Get-WindowsCapability' {
        'Get-WindowsCapability -Online -Name Language.* (Deep):'
        Get-WindowsCapability -Online -Name 'Language.*' -ErrorAction Stop | Where-Object { $_.State -ne 'NotPresent' } | ForEach-Object { '    {0} : {1}' -f $_.Name, $_.State }
    }
    Invoke-Safe 'Get-WindowsPackage' {
        'Get-WindowsPackage -Online (language packs, Deep):'
        Get-WindowsPackage -Online -ErrorAction Stop | Where-Object { $_.PackageName -match 'LanguagePack|Language-Pack' } | ForEach-Object { '    {0} : {1}' -f $_.PackageName, $_.PackageState }
    }
}
else {
    Add-Line 'DISM based queries (Get-WindowsCapability / Get-WindowsPackage) skipped; use -Deep on an idle device.'
}

# ------------------------------------------------------------------------------------------------
Add-Section '6. Swisscom deployment: markers, tasks, files'
Invoke-Safe 'HKLM markers' { Get-RegistryTree -Path 'HKLM:\SOFTWARE\Swisscom\LanguageDeployment' -MaxLines 150 }
Invoke-Safe 'Tasks' {
    $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -like '*Swisscom*' -or $_.TaskName -match 'Language|Keyboard' })
    if (-not $tasks.Count) { 'no deployment tasks found' }
    foreach ($task in $tasks) {
        $info = Get-ScheduledTaskInfo -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue
        $triggers = (@($task.Triggers | ForEach-Object { $_.CimClass.CimClassName -replace '^MSFT_Task', '' -replace 'Trigger$', '' }) -join '/')
        '{0}{1}: state={2}; last run={3}; last result=0x{4:X}; next run={5}; triggers={6}; principal={7}' -f $task.TaskPath, $task.TaskName, $task.State, $info.LastRunTime, $info.LastTaskResult, $info.NextRunTime, $triggers, $(if ($task.Principal.UserId) { $task.Principal.UserId } else { $task.Principal.GroupId })
        '    arguments: ' + (@($task.Actions | ForEach-Object { $_.Arguments }) -join ' ')
    }
}
Invoke-Safe 'Program files' {
    foreach ($folder in (Join-Path $env:ProgramFiles 'Swisscom\LanguageDeployment'), (Join-Path $env:ProgramData 'Swisscom\LanguageDeployment')) {
        "Folder $folder :"
        if (Test-Path -LiteralPath $folder) {
            Get-ChildItem -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { '    {0}  {1} bytes  {2}' -f $_.FullName.Substring($folder.Length), $_.Length, $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') }
        }
        else { '    (not found)' }
    }
    $keyboardScript = Join-Path $env:ProgramFiles 'Swisscom\LanguageDeployment\Set-SwissKeyboard.ps1'
    if (Test-Path -LiteralPath $keyboardScript) {
        'Set-SwissKeyboard.ps1: ' + ((Select-String -LiteralPath $keyboardScript -Pattern "^\`$ScriptVersion" | Select-Object -First 1).Line)
    }
}

# ------------------------------------------------------------------------------------------------
Add-Section '7. Swisscom logs (end of each file, up to MaxLinesPerLog lines)'
$logFiles = New-Object System.Collections.Generic.List[string]
foreach ($folder in (Join-Path $env:ProgramData 'Swisscom\LanguageDeployment\Logs'), (Join-Path $env:LOCALAPPDATA 'Swisscom\LanguageDeployment\Logs')) {
    if (Test-Path -LiteralPath $folder) { foreach ($file in @(Get-ChildItem -LiteralPath $folder -File -Force -ErrorAction SilentlyContinue | Sort-Object Name)) { $logFiles.Add($file.FullName) } }
    else { Add-Line "Folder not found: $folder" }
}
foreach ($pattern in '*DeviceLanguage*.log*', '*UserLanguage*.log*', '*LanguagePack*.log*', '*SwissKeyboard*.log*', '*FirstLogonStoreUpdate*.log*') {
    foreach ($file in @(Get-ChildItem -LiteralPath "$env:SystemRoot\Temp" -Filter $pattern -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.FullName -ne $outFile })) {
        if (-not $logFiles.Contains($file.FullName)) { $logFiles.Add($file.FullName) }
    }
}
if (-not $logFiles.Count) { Add-Line 'No Swisscom logs found (the app did not start, or the logs are not readable: run elevated).' }
foreach ($logFile in $logFiles) { Add-FileTail -Path $logFile -Tail $MaxLinesPerLog }
# Last run of every language install log: exit code and error message.
Invoke-Safe 'Language app last run' {
    foreach ($logFile in @($logFiles | Where-Object { $_ -match 'Install-(Device|User)Language' })) {
        $exit = @(Select-String -LiteralPath $logFile -Pattern 'Final exit code: (\d+)' -ErrorAction SilentlyContinue) | Select-Object -Last 1
        if ($exit -and $exit.Matches[0].Groups[1].Value -ne '0') {
            $message = @(Select-String -LiteralPath $logFile -Pattern '\[ERROR\] (Exception message|Failed step): (.+)' -ErrorAction SilentlyContinue) | Select-Object -Last 2 | ForEach-Object { $_.Matches[0].Groups[2].Value }
            Add-Finding -Level ERROR -Text "$(Split-Path $logFile -Leaf): last run ended with exit code $($exit.Matches[0].Groups[1].Value): $($message -join ' / ')"
        }
    }
    # One-time Store app update at the first sign-in (Start-FirstLogonStoreUpdate.ps1): state and result.
    $status = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Swisscom\LanguageDeployment' -ErrorAction SilentlyContinue
    $task = Get-ScheduledTask -TaskPath '\Swisscom\LanguageDeployment\' -TaskName 'Start-FirstLogonStoreUpdate' -ErrorAction SilentlyContinue
    ''
    '--- First sign-in Store update (inbox app names in the user language)'
    '    registered {0}; attempts {1}; done {2}; result {3}; task present {4}' -f $status.FirstLogonStoreUpdateRegisteredAt, $status.FirstLogonStoreUpdateAttempts, $status.FirstLogonStoreUpdateDoneAt, $status.FirstLogonStoreUpdateResult, [bool]$task
    if ("$($status.FirstLogonStoreUpdateResult)" -like 'failed*') {
        Add-Finding -Level WARN -Text "First sign-in Store update: $($status.FirstLogonStoreUpdateResult); the inbox apps get their language through the regular Store updates. See Swisscom-FirstLogonStoreUpdate.log."
    }
    elseif ($status.FirstLogonStoreUpdateRegisteredAt -and -not $status.FirstLogonStoreUpdateDoneAt -and -not $task) {
        Add-Finding -Level WARN -Text 'First sign-in Store update was registered, but neither the task nor a result exists (task removed by someone else?).'
    }
}

# ------------------------------------------------------------------------------------------------
Add-Section '8. Intune Management Extension'
Invoke-Safe 'IME log files' {
    "IME log folder: $imeFolder"
    if (Test-Path -LiteralPath $imeFolder) {
        Get-ChildItem -LiteralPath $imeFolder -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | ForEach-Object { '    {0}  {1} bytes  {2}' -f $_.Name, $_.Length, $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') }
    }
    else { '    (not found: the Intune Management Extension is not installed yet, or the folder is not readable)' }
}
Invoke-Safe 'IME app ids' {
    $guidPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
    # Apps of the Swisscom deployment: the install log names the IMECache folder <app id>_<version>.
    foreach ($logFile in $logFiles) {
        foreach ($match in @(Select-String -LiteralPath $logFile -Pattern 'IMECache\\' -ErrorAction SilentlyContinue | Select-Object -First 5)) {
            foreach ($guid in [regex]::Matches($match.Line, $guidPattern)) { $null = $languageAppIds.Add($guid.Value.ToLowerInvariant()) }
        }
    }
    # Apps that the ESP marked as failed (InstallationState 4) or that are still running (2) were added in section 2
    # (device and user phases).
    foreach ($file in @(Get-ChildItem -LiteralPath $imeFolder -Filter 'IntuneManagementExtension*.log' -File -ErrorAction SilentlyContinue)) {
        foreach ($match in @(Select-String -LiteralPath $file.FullName -Pattern 'DeviceLanguage|UserLanguage|Install-Language' -ErrorAction SilentlyContinue | Select-Object -First 300)) {
            foreach ($guid in [regex]::Matches($match.Line, $guidPattern)) { $null = $languageAppIds.Add($guid.Value.ToLowerInvariant()) }
        }
    }
    'App IDs analyzed (language apps and apps the ESP marked as failed / running): ' + $(if ($languageAppIds.Count) { ($languageAppIds -join ', ') } else { '(none)' })
}
# For every failed ESP app: the AppWorkload.log lines BEFORE the failure (download, hash check, install command,
# installer exit code, detection) - the installer lines often do not contain the app ID themselves.
Invoke-Safe 'Failed app context' {
    $files = @(Get-ChildItem -LiteralPath $imeFolder -Filter 'AppWorkload*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
    foreach ($app in $script:FailedEspApps) {
        ''
        "--- Failed ESP app $($app.Name) ($($app.Id)), $($app.Phase), error $($app.Error)"
        if (-not $app.Id) { continue }
        $hit = $null
        # Prefer the ESP failure lines (closest to the installer run); later reporting lines also contain the app ID.
        foreach ($pattern in @("(Setting ErrorHresult .* for application $($app.Id))|(to Error for application $($app.Id))", "(EnforcementErrorCode.*$($app.Id))|($($app.Id).*EnforcementErrorCode)")) {
            foreach ($file in $files) {
                $last = @(Select-String -LiteralPath $file.FullName -Pattern $pattern -Context 120, 3 -ErrorAction SilentlyContinue) | Select-Object -Last 1
                if ($last) { $hit = $last; $hitFile = $file.Name }
            }
            if ($hit) { break }
        }
        if (-not $hit) {
            '    (no failure line for this app in AppWorkload*.log; lines with the app ID:)'
            foreach ($file in $files) {
                @(Select-String -LiteralPath $file.FullName -Pattern $app.Id -ErrorAction SilentlyContinue) | Select-Object -Last 40 | ForEach-Object {
                    $text = $_.Line; if ($text.Length -gt 400) { $text = $text.Substring(0, 400) + '...' }; "    [$($file.Name):$($_.LineNumber)] $text"
                }
            }
            continue
        }
        "    (120 lines before the failure in $hitFile, line $($hit.LineNumber))"
        foreach ($line in @($hit.Context.PreContext) + @($hit.Line) + @($hit.Context.PostContext)) {
            $text = ($line -replace '<!\[LOG\[', '' -replace '\]LOG\]!><time="([^"]+)" date="([^"]+)".*$', ' | $2 $1')
            if ($text.Length -gt 450) { $text = $text.Substring(0, 450) + '...' }
            "    $text"
        }
    }
    if (-not $script:FailedEspApps.Count) { '(no app failed in the ESP)' }
}
Invoke-Safe 'IME filtered' {
    $files = @(Get-ChildItem -LiteralPath $imeFolder -Filter 'IntuneManagementExtension*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
    $idPattern = if ($languageAppIds.Count) { ($languageAppIds -join '|') + '|' } else { '' }
    foreach ($file in $files) {
        Add-FilteredLines -Path $file.FullName -Pattern ($idPattern + 'DeviceLanguage|UserLanguage|0x87D1041C|0x87D1041D|0x80070005') -Last 300 -Title "IME lines about the language apps ($($file.Name))"
    }
    $latest = $files | Select-Object -Last 1
    if ($latest) { Add-FileTail -Path $latest.FullName -Tail 150 }
    # The Win32 app workload (download, detection, install command, exit code) is logged in AppWorkload.log.
    foreach ($name in 'AppWorkload*.log', 'AppActionProcessor*.log') {
        foreach ($file in @(Get-ChildItem -LiteralPath $imeFolder -Filter $name -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 2)) {
            if ($idPattern) { Add-FilteredLines -Path $file.FullName -Pattern $idPattern.TrimEnd('|') -Last 500 -Title "$($file.Name): lines about the language apps (by app ID)" }
            Add-FilteredLines -Path $file.FullName -Pattern 'exit code|ExitCode|Install failed|install error|Error|0x8' -Last 80 -Title "$($file.Name): errors and exit codes"
        }
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $imeFolder -Filter 'AgentExecutor*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 2)) {
        Add-FilteredLines -Path $file.FullName -Pattern ($idPattern + 'DeviceLanguage|UserLanguage|exit|timeout|error') -Last 120 -Title "AgentExecutor ($($file.Name))"
    }
}
Invoke-Safe 'Win32Apps registry' {
    $root = 'HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps'
    'Win32Apps state of the analyzed apps (ComplianceStateMessage / EnforcementStateMessage contain the error code):'
    $dumped = 0
    foreach ($key in @(Get-ChildItem -LiteralPath $root -Recurse -ErrorAction SilentlyContinue)) {
        $isLanguageApp = $false
        foreach ($id in $languageAppIds) { if ($key.PSChildName -like "*$id*" -or $key.Name -like "*$id*") { $isLanguageApp = $true } }
        if ($isLanguageApp) {
            $dumped++
            Get-RegistryValues -Path $key.PSPath -MaxValueLength 1500 | ForEach-Object { $_ -replace '^Microsoft\.PowerShell\.Core\\Registry::', '' }
        }
    }
    if (-not $dumped) { '(no Win32Apps key for a language app found; apps in the registry: ' + (@(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue).Count) + ' user/device keys)' }
}
Invoke-Safe 'IMECache' {
    foreach ($folder in "$env:SystemRoot\IMECache", "${env:ProgramFiles(x86)}\Microsoft Intune Management Extension\Content\Incoming") {
        "Folder $folder :"
        if (Test-Path -LiteralPath $folder) { Get-ChildItem -LiteralPath $folder -ErrorAction SilentlyContinue | ForEach-Object { '    {0}  {1}' -f $_.Name, $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') } }
        else { '    (not found)' }
    }
}

# ------------------------------------------------------------------------------------------------
Add-Section '9. Windows servicing logs'
$cbs = "$env:SystemRoot\Logs\CBS\CBS.log"
$dism = "$env:SystemRoot\Logs\DISM\dism.log"
if (Test-Path -LiteralPath $cbs) {
    Add-FilteredLines -Path $cbs -Pattern 'Error\s|Failed|HRESULT = 0x8|CBS_E_|\[HRESULT\]' -Last 120 -Title 'CBS.log: errors'
    Add-FilteredLines -Path $cbs -Pattern 'Language-Pack|LanguagePack|Microsoft-Windows-Client-Language' -Last 60 -Title 'CBS.log: language pack lines'
    Add-FileTail -Path $cbs -Tail 200
}
else { Add-Line "Not found: $cbs" }
# CBS.log is rotated into CbsPersist_*.log / .cab after a few MB (the failing session can be in an older file).
Invoke-Safe 'CBS folder' {
    '--- C:\Windows\Logs\CBS (all files; CbsPersist_*.cab are compressed older CBS logs, expand them with: expand -F:* <file>.cab <folder>)'
    Get-ChildItem -LiteralPath "$env:SystemRoot\Logs\CBS" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | ForEach-Object { '    {0}  {1} bytes  {2}' -f $_.Name, $_.Length, $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') }
}
foreach ($file in @(Get-ChildItem -LiteralPath "$env:SystemRoot\Logs\CBS" -Filter '*.log' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'CBS.log' } | Sort-Object LastWriteTime | Select-Object -Last 3)) {
    Add-FilteredLines -Path $file.FullName -Pattern 'Error\s|0x800f|0x8007|CBS_E_|Failed to perform operation' -Last 80 -Title "$($file.Name): errors"
}
if (Test-Path -LiteralPath $dism) {
    Add-FilteredLines -Path $dism -Pattern 'Error|Failed|0x8' -Last 80 -Title 'dism.log: errors'
    Add-FileTail -Path $dism -Tail 120
}
else { Add-Line "Not found: $dism" }
foreach ($file in "$env:SystemRoot\Panther\setupact.log", "$env:SystemRoot\Panther\UnattendGC\setupact.log", "$env:SystemRoot\SoftwareDistribution\ReportingEvents.txt", "$env:SystemRoot\Logs\WindowsUpdate\WindowsUpdate.log") {
    if (Test-Path -LiteralPath $file) { Add-FileTail -Path $file -Tail 80 } else { Add-Line "Not found: $file" }
}
Add-Line ''
Add-Line "Other servicing logs present: $((@(Get-ChildItem -LiteralPath "$env:SystemRoot\Logs" -Directory -ErrorAction SilentlyContinue | ForEach-Object Name)) -join ', ')"

# ------------------------------------------------------------------------------------------------
Add-Section "10. Event logs (last $Days days)"
foreach ($spec in @(
        @{ Log = 'Setup'; Level = $null; Max = 80 },
        @{ Log = 'Microsoft-Windows-MUI/Admin'; Level = $null; Max = 40 },
        @{ Log = 'Microsoft-Windows-MUI/Operational'; Level = $null; Max = 40 },
        @{ Log = 'Microsoft-Windows-LanguagePackSetup/Operational'; Level = $null; Max = 40 },
        @{ Log = 'Microsoft-Windows-WindowsUpdateClient/Operational'; Level = $null; Max = 80 },
        @{ Log = 'Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin'; Level = (1, 2, 3); Max = 80 },
        @{ Log = 'Microsoft-Windows-ModernDeployment-Diagnostics-Provider/Autopilot'; Level = $null; Max = 80 },
        @{ Log = 'Microsoft-Windows-ModernDeployment-Diagnostics-Provider/ManagementService'; Level = $null; Max = 60 },
        @{ Log = 'Microsoft-Windows-TaskScheduler/Operational'; Level = (1, 2, 3); Max = 40 },
        @{ Log = 'Microsoft-Windows-International-RegionalOptionsControlPanel/Operational'; Level = $null; Max = 30 },
        @{ Log = 'Application'; Level = (1, 2); Max = 60 },
        @{ Log = 'System'; Level = (1, 2); Max = 60 },
        @{ Log = 'Microsoft-Windows-Kernel-Power/Thermal-Operational'; Level = $null; Max = 0 }
    )) {
    if ($spec.Max -le 0) { continue }
    Invoke-Safe "Event log $($spec.Log)" { Get-EventSummary -LogName $spec.Log -Level $spec.Level -Max $spec.Max }
}
Invoke-Safe 'Event log: servicing providers' {
    Get-EventSummary -LogName 'System' -Level $null -Max 40 -ProviderLike 'TrustedInstaller|Servicing|WindowsUpdateClient|Microsoft-Windows-Kernel-General|User32|Microsoft-Windows-Kernel-Power|EventLog'
}

# ------------------------------------------------------------------------------------------------
Add-Section '11. Crash reports (WER) of servicing / PowerShell processes'
Invoke-Safe 'WER' {
    $limit = (Get-Date).AddDays(-$Days)
    $reports = @()
    foreach ($folder in "$env:ProgramData\Microsoft\Windows\WER\ReportArchive", "$env:ProgramData\Microsoft\Windows\WER\ReportQueue") {
        if (Test-Path -LiteralPath $folder) { $reports += @(Get-ChildItem -LiteralPath $folder -Directory -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt $limit }) }
    }
    "WER reports in the last $Days days: $($reports.Count)"
    foreach ($report in @($reports | Sort-Object LastWriteTime -Descending | Select-Object -First 25)) { '    {0}  {1}' -f $report.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'), $report.Name }
    foreach ($report in @($reports | Where-Object { $_.Name -match 'dism|TiWorker|powershell|TrustedInstaller|LanguagePack|CloudExperienceHost|AppCrash' } | Sort-Object LastWriteTime -Descending | Select-Object -First 4)) {
        $wer = Join-Path $report.FullName 'Report.wer'
        if (Test-Path -LiteralPath $wer) {
            ''
            "--- $wer"
            Get-Content -LiteralPath $wer -TotalCount 60 -ErrorAction SilentlyContinue | ForEach-Object { "    $_" }
        }
    }
}

# ------------------------------------------------------------------------------------------------
# MSIX / AppX apps (e.g. the new Teams installed by teamsbootstrapper.exe as a Win32 app) are deployed to the
# AppX default volume. 0x80073D3F (ERROR_INSTALL_DRIVE_NOT_FOUND) means that this volume or a drive used by the
# deployment does not exist (e.g. "Change where new content is saved" or a policy points to a removed drive).
Add-Section '12. AppX / MSIX deployment (Store and MSIX apps, new Teams)'
$failedAppx = @($script:FailedEspApps | Where-Object { $_.Error -match '0x80073[CD]' }).Count -gt 0
Invoke-Safe 'AppX volumes' {
    Import-Module Appx -ErrorAction Stop
    $default = Get-AppxDefaultVolume -ErrorAction Stop
    $volumes = @(Get-AppxVolume -ErrorAction Stop)
    'AppX volumes (Get-AppxVolume):'
    foreach ($volume in $volumes) {
        '    {0}  PackageStorePath={1}  IsOffline={2}  IsSystemVolume={3}  SupportsHardLinks={4}' -f $volume.Name, $volume.PackageStorePath, $volume.IsOffline, $volume.IsSystemVolume, $volume.SupportsHardLinks
        if ($volume.IsOffline) { Add-Finding -Level ERROR -Text "AppX volume $($volume.PackageStorePath) is offline: MSIX/AppX installations to it fail (0x80073D3F). Remove it (Remove-AppxVolume) or reconnect the drive." }
    }
    "AppX default volume (Get-AppxDefaultVolume): $($default.PackageStorePath)  IsOffline=$($default.IsOffline)  IsSystemVolume=$($default.IsSystemVolume)"
    $root = [System.IO.Path]::GetPathRoot([string]$default.PackageStorePath)
    if ($root -and -not (Test-Path -LiteralPath $root)) {
        Add-Finding -Level ERROR -Text "AppX default volume points to $($default.PackageStorePath), but drive $root does not exist: MSIX/AppX installations fail with 0x80073D3F. Fix: Set-AppxDefaultVolume -Volume (Get-AppxVolume | Where-Object IsSystemVolume)."
    }
    elseif (-not $default.IsSystemVolume) {
        Add-Finding -Level WARN -Text "AppX default volume is not the system volume ($($default.PackageStorePath)); new apps are installed there."
    }
    elseif ($failedAppx) {
        Add-Finding -Level INFO -Text 'An app failed with an AppX deployment error and the AppX default volume is the system volume and online: the volume is not the cause. See the in-box app removal policy and the AppX event logs (section 12).'
    }
}
Invoke-Safe 'AppX registry and policies' {
    ''
    '--- AppX package root and volumes (registry)'
    Get-RegistryValues -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx' | Where-Object { $_ -match 'PackageRoot|PackageRepositoryRoot|key not found' }
    Get-RegistryTree -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\PackageVolumes' -MaxLines 30
    ''
    '--- AppX policies (GPO / ADMX registry and Intune PolicyManager)'
    Get-RegistryTree -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx' -MaxLines 40
    Get-RegistryTree -Path 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore' -MaxLines 20
    Get-RegistryTree -Path 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\ApplicationManagement' -MaxLines 60 -MaxValueLength 300
    Get-RegistryTree -Path 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Storage' -MaxLines 60 -MaxValueLength 300
    ''
    "WindowsApps folders on the drives (where AppX packages are stored):"
    foreach ($disk in @(Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction SilentlyContinue)) {
        foreach ($folder in "$($disk.DeviceID)\Program Files\WindowsApps", "$($disk.DeviceID)\WindowsApps") {
            if (Test-Path -LiteralPath $folder -ErrorAction SilentlyContinue) { "    $folder" }
        }
    }
}
Invoke-Safe 'Teams packages' {
    ''
    '--- New Teams (MSTeams) and other packages of failed AppX apps'
    Import-Module Appx -ErrorAction Stop
    if ($isAdmin) {
        $packages = @(Get-AppxPackage -AllUsers -Name '*MSTeams*' -ErrorAction Stop)
        $scope = 'any user (Get-AppxPackage -AllUsers)'
    }
    else {
        $packages = @(Get-AppxPackage -Name '*MSTeams*' -ErrorAction Stop)
        $scope = 'the current user (not elevated: other users are not visible)'
    }
    if (-not $packages.Count) { "    MSTeams is not installed for $scope." }
    foreach ($package in $packages) {
        '    {0} {1} ({2}); status {3}; location {4}' -f $package.Name, $package.Version, $package.Architecture, $package.Status, $package.InstallLocation
        foreach ($user in @($package.PackageUserInformation)) { "        user $($user.UserSecurityId.Username) ($($user.UserSecurityId.Sid)): $($user.InstallState)" }
    }
    'Provisioned for new users (AppxAllUserStore, registry):'
    $provisioned = @(Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Applications' -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match 'Teams' })
    if ($provisioned.Count) { $provisioned | ForEach-Object { "    $($_.PSChildName)" } } else { '    (MSTeams is not provisioned)' }
    if ($Deep) {
        'Get-AppxProvisionedPackage -Online (Deep):'
        Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -match 'Teams' } | ForEach-Object { "    $($_.PackageName) $($_.Version)" }
    }
}
Invoke-Safe 'Teams bootstrapper logs' {
    ''
    '--- Teams installer logs (teamsbootstrapper, MSTeams), newest first'
    $folders = @("$env:SystemRoot\Temp", "$env:SystemRoot\SystemTemp", "$env:ProgramData\Microsoft\Teams", $env:TEMP, "$env:SystemRoot\IMECache") | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
    $logs = @(foreach ($folder in $folders) { Get-ChildItem -LiteralPath $folder -Recurse -Depth 2 -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'teams' -and $_.Extension -in '.log', '.txt', '.json' -and $_.FullName -ne $outFile } }) | Sort-Object LastWriteTime -Descending
    if (-not $logs.Count) { '    (no Teams installer log found in ' + ($folders -join ', ') + ')' }
    foreach ($log in @($logs | Select-Object -First 15)) { '    {0}  {1} bytes  {2}' -f $log.FullName, $log.Length, $log.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') }
    foreach ($log in @($logs | Select-Object -First 2)) {
        ''
        try { Get-FileText -Path $log.FullName -Tail 120 } catch { "--- $($log.FullName) : not readable: $($_.Exception.Message)" }
    }
}
Invoke-Safe 'IMECache of failed apps' {
    foreach ($app in $script:FailedEspApps) {
        if (-not $app.Id) { continue }
        foreach ($folder in @(Get-ChildItem -LiteralPath "$env:SystemRoot\IMECache" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$($app.Id)*" })) {
            "IMECache of $($app.Name): $($folder.FullName)"
            Get-ChildItem -LiteralPath $folder.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Select-Object -First 30 | ForEach-Object { '    {0}  {1} bytes' -f $_.FullName.Substring($folder.FullName.Length), $_.Length }
        }
    }
}
foreach ($spec in @(
        @{ Log = 'Microsoft-Windows-AppXDeploymentServer/Operational'; Level = (1, 2, 3); Max = 100 },
        @{ Log = 'Microsoft-Windows-AppXDeployment/Operational'; Level = (1, 2, 3); Max = 40 },
        @{ Log = 'Microsoft-Windows-AppxPackaging/Operational'; Level = (1, 2, 3); Max = 40 }
    )) {
    Invoke-Safe "Event log $($spec.Log)" { Get-EventSummary -LogName $spec.Log -Level $spec.Level -Max $spec.Max }
}
Invoke-Safe 'AppX events about Teams' {
    Get-EventSummary -LogName 'Microsoft-Windows-AppXDeploymentServer/Operational' -Level $null -Max 60 -MessageLike 'MSTeams|0x80073D3F'
}
# Policy "Remove default Microsoft Store packages from the system" (RemoveDefaultMicrosoftStorePackages, Windows 11
# Enterprise/Education): selected apps are removed AND blocked from reinstallation while they stay selected. A blocked
# installation fails with 0x80073D3F and AppXDeploymentServer event 762 "RemoveDefaultPackages uninstall override
# policy successfully blocked package <family>".
Invoke-Safe 'In-box app removal policy' {
    ''
    '--- Policy "Remove default Microsoft Store packages" (RemoveDefaultMicrosoftStorePackages)'
    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx\RemoveDefaultMicrosoftStorePackages'
    $policy = Get-ItemProperty -LiteralPath $policyPath -ErrorAction SilentlyContinue
    $removed = New-Object System.Collections.Generic.List[string]
    if (-not $policy) { '    not configured' }
    else {
        "    Enabled=$($policy.Enabled); DynamicRemovalList='$($policy.DynamicRemovalList)'"
        foreach ($key in @(Get-ChildItem -LiteralPath $policyPath -ErrorAction SilentlyContinue)) {
            $remove = (Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue).RemovePackage
            if ("$remove" -eq '1') { $removed.Add($key.PSChildName) }
        }
        foreach ($family in @("$($policy.DynamicRemovalList)" -split '[;,\s]+' | Where-Object { $_ })) { $removed.Add($family) }
        '    Removed and blocked from (re)installation: ' + $(if ($removed.Count) { $removed -join ', ' } else { '(none)' })
        if ("$($policy.Enabled)" -eq '1' -and ($removed -match '^MSTeams_')) {
            Add-Finding -Level ERROR -Text 'Policy "Remove default Microsoft Store packages" removes MSTeams_8wekyb3d8bbwe (new Teams for work or school) and blocks its installation: a Teams app deployment fails with 0x80073D3F. Fix in Intune: set MSTeams to false / deselect "Microsoft Teams" in that policy (Settings catalog: Windows Components > App Package Deployment), sync, then reinstall Teams.'
        }
    }
    $blocked = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-AppXDeploymentServer/Operational'; Id = 762; StartTime = (Get-Date).AddDays(-$Days) } -MaxEvents 500 -ErrorAction SilentlyContinue)
    $families = @($blocked | ForEach-Object { ([regex]::Match("$($_.Message)".Trim(), 'blocked package (\S+?)\.?$')).Groups[1].Value } | Where-Object { $_ } | Select-Object -Unique)
    "    Event 762 (installation blocked by this policy) in the last $Days days: $($blocked.Count)" + $(if ($families.Count) { " - packages: $($families -join ', ')" } else { '' })
    foreach ($family in $families) {
        if ($family -notmatch '^MSTeams_' -or -not ($removed -match '^MSTeams_')) {
            Add-Finding -Level ERROR -Text "Installation of $family was blocked by the policy ""Remove default Microsoft Store packages"" (AppXDeploymentServer event 762, error 0x80073D3F). Deselect the app in that policy, sync, then reinstall."
        }
    }
}
}
catch {
    Add-Line "[collector] aborted: $($_.Exception.Message)"
    $script:Problems.Add("aborted: $($_.Exception.Message)")
}
finally {
    # Findings at the end of the report (the report is written while it is collected) and on the console.
    Add-Line ''
    Add-Line ('=' * 110)
    Add-Line 'AUTOMATIC FINDINGS (summary of the sections above; not exhaustive - read the sections for details)'
    Add-Line ('=' * 110)
    if (-not $script:Findings.Count) { Add-Line '(no automatic finding)' }
    foreach ($finding in $script:Findings) { Add-Line $finding }
    Add-Line ''
    Add-Line ('=' * 110)
    Add-Line "End of report. Duration $([int]((Get-Date) - $startedAt).TotalSeconds) seconds. Collector problems: $($script:Problems.Count)"
    foreach ($problem in $script:Problems) { Add-Line "    $problem" }
    $writer.Flush()
    $writer.Dispose()
}

Write-Host ''
if ($script:Findings.Count) {
    Write-Host 'Automatic findings:' -ForegroundColor Cyan
    foreach ($finding in $script:Findings) {
        $color = if ($finding -like '`[ERROR`]*') { 'Red' } elseif ($finding -like '`[WARN`]*') { 'Yellow' } else { 'Gray' }
        Write-Host "  $finding" -ForegroundColor $color
    }
}
Write-Host "Done. Send this file for analysis: $outFile ($([math]::Round((Get-Item -LiteralPath $outFile).Length / 1KB)) KB)" -ForegroundColor Green
if (-not $isAdmin) { Write-Host 'The report is incomplete because the script did not run elevated.' -ForegroundColor Yellow }
