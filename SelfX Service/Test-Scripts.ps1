<#
.SYNOPSIS
    Run the SelfX Service action, repair and check scripts in a sandbox and verify their result and log.
.DESCRIPTION
    Every script of Sources\Scripts_to_run is executed (or, for the scripts with dangerous effects, its
    functions are called) with mocked commands: no process is closed, nothing is started, no service,
    network adapter, volume, registry value or Windows Update is touched and Windows is never restarted.
    APPDATA, LOCALAPPDATA, TEMP and ProgramData point to a temporary sandbox, so the cache scripts delete
    only sandbox files and all logs (SelfXLog.ps1) are written to the sandbox, where they are checked.
    The read-only scripts Check-Compliance.ps1, Detection.ps1 and HealthStatus.ps1 -Collect run for real
    in a child process (with the sandbox ProgramData), to verify their output and log.
    Also checks the headers, the logging and the catalog / Health_Config references of all scripts.
    Run in Windows PowerShell 5.1: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Scripts.ps1
.NOTES
    Version: 2.6.3
    History:
    2.6.0  2026-11-06  Wolfgang Baeck  Initial version: sandbox tests of all action, repair and check scripts.
    2.6.3  2026-11-06  Wolfgang Baeck  Updates: Windows Update Agent flow with a simulated session.
#>
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerShell.Utility
Import-Module Microsoft.PowerShell.Management
Import-Module Microsoft.PowerShell.Security
$sources = Join-Path $PSScriptRoot 'Sources'
$scripts = Join-Path $sources 'Scripts_to_run'

$script:assertions = 0
function Assert-Equal($Actual, $Expected, $Message) {
	$script:assertions++
	if ($Actual -ne $Expected) { throw "$Message : expected '$Expected', got '$Actual'." }
}

#----------------------------------------------------------------------------------------------------
# Mocks: everything that could change this device. Functions take precedence over cmdlets; module
# autoloading is disabled, so no real module can replace a mock.
#----------------------------------------------------------------------------------------------------
# Global: inside the mocks "$script:" would be the scope of the tested script.
$global:SelfXTestCalls = New-Object System.Collections.Generic.List[string]
$script:calls = $global:SelfXTestCalls
$global:FakeProcesses = New-Object System.Collections.Generic.List[object]
function global:New-FakeProcess([string]$Name, [string]$Path) {
	$process = [pscustomobject]@{ ProcessName = $Name; Name = $Name; Path = $Path; SessionId = 1; Id = (Get-Random -Minimum 10000 -Maximum 99999) }
	$global:FakeProcesses.Add($process)
}
function global:Get-Process {
	param([Parameter(Position = 0)][string[]]$Name, [int]$Id)
	if ($PSBoundParameters.ContainsKey('Id')) { return [pscustomobject]@{ Id = $Id; SessionId = 1 } }
	@($global:FakeProcesses | Where-Object { $p = $_; -not $Name -or ($Name | Where-Object { $p.ProcessName -like $_ }) })
}
function global:Stop-Process {
	param([Parameter(ValueFromPipeline = $true)]$InputObject, [switch]$Force)
	process { foreach ($item in @($InputObject)) { if ($item) { $global:SelfXTestCalls.Add("Stop-Process $($item.ProcessName)"); [void]$global:FakeProcesses.Remove($item) } } }
}
function global:Start-Process {
	param([Parameter(Position = 0)][string]$FilePath, [Parameter(Position = 1)]$ArgumentList, [switch]$PassThru, [switch]$Wait, $WindowStyle)
	$global:SelfXTestCalls.Add("Start-Process $FilePath $(@($ArgumentList) -join ' ')".Trim())
	if ($PassThru) { $fake = [pscustomobject]@{ ExitCode = 0 }; $fake | Add-Member ScriptMethod WaitForExit { param($ms) $true }; return $fake }
}
function global:Start-Sleep { param([int]$Seconds, [int]$Milliseconds) }
function global:Restart-Service { param($Name, [switch]$Force, $ErrorAction) $global:SelfXTestCalls.Add("Restart-Service $Name") }
function global:Get-Service { param($Name, $ErrorAction) [pscustomobject]@{ Name = $Name; Status = 'Running' } }
function global:Restart-NetAdapter { param($Name, $Confirm, $ErrorAction) $global:SelfXTestCalls.Add("Restart-NetAdapter $Name") }
function global:Get-NetAdapter { param($ErrorAction) $global:FakeAdapters }
function global:Get-NetRoute { param($DestinationPrefix, $ErrorAction) $global:FakeRoutes }
function global:Repair-Volume { param($DriveLetter, [switch]$OfflineScanAndFix, [switch]$Scan, [switch]$SpotFix, $ErrorAction) $global:SelfXTestCalls.Add("Repair-Volume $DriveLetter offline=$OfflineScanAndFix"); 'ScanScheduled' }
function global:Clear-RecycleBin { param([switch]$Force, $Confirm, $ErrorAction) $global:SelfXTestCalls.Add('Clear-RecycleBin'); throw 'The system cannot find the path specified.' }
function global:Clear-DnsClientCache { param($ErrorAction) $global:SelfXTestCalls.Add('Clear-DnsClientCache'); if ($global:DnsFails) { throw 'Access denied' } }
function global:Get-MpComputerStatus { param($ErrorAction) [pscustomobject]@{ AntivirusSignatureVersion = $global:SignatureVersion; AntivirusSignatureLastUpdated = [datetime]'2026-11-06 10:00' } }
function global:Update-MpSignature { param($ErrorAction) $global:SelfXTestCalls.Add('Update-MpSignature'); if ($global:UpdateFails) { throw 'No connection' }; $global:SignatureVersion = '1.441.99.0' }
function global:Get-CimInstance { param($Namespace, $ClassName, $Filter, $ErrorAction) throw "Get-CimInstance is not allowed in tests ($ClassName)" }
function global:Invoke-CimMethod { throw 'Invoke-CimMethod is not allowed in tests' }
function global:Register-ScheduledTask { throw 'Forbidden in tests' }
function global:New-ScheduledTask { throw 'Forbidden in tests' }
function global:New-ScheduledTaskAction { throw 'Forbidden in tests' }
function global:Start-ScheduledTask { throw 'Forbidden in tests' }
# Registry: HKCU / HKLM writes are only recorded; file system calls go to the real cmdlets (sandbox).
function global:Set-ItemProperty {
	param([string]$LiteralPath, [string]$Path, $Name, $Value, $Type, [switch]$Force)
	$target = "$LiteralPath$Path"
	if ($target -like 'HK*') { $global:SelfXTestCalls.Add("Set-ItemProperty $target $Name=$Value"); return }
	Microsoft.PowerShell.Management\Set-ItemProperty @PSBoundParameters
}
function global:New-Item {
	param([string]$Path, [string]$ItemType, [switch]$Force, $Value)
	if ($Path -like 'HK*') { $global:SelfXTestCalls.Add("New-Item $Path"); return }
	Microsoft.PowerShell.Management\New-Item @PSBoundParameters
}
$PSModuleAutoLoadingPreference = 'None'
foreach ($name in 'Get-Process', 'Stop-Process', 'Start-Process', 'Restart-Service', 'Get-Service', 'Restart-NetAdapter', 'Get-NetAdapter', 'Get-NetRoute',
	'Repair-Volume', 'Clear-RecycleBin', 'Clear-DnsClientCache', 'Update-MpSignature', 'Get-MpComputerStatus', 'Get-CimInstance', 'Invoke-CimMethod',
	'Register-ScheduledTask', 'New-ScheduledTask', 'Start-ScheduledTask', 'Set-ItemProperty', 'New-Item', 'Start-Sleep') {
	Assert-Equal (Get-Command $name).CommandType Function "Mock resolution: $name"
}

# Sandbox for the profile folders, TEMP and ProgramData (logs).
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('SelfXScriptTests-' + [guid]::NewGuid().ToString('N'))
$saved = @{ LOCALAPPDATA = $env:LOCALAPPDATA; APPDATA = $env:APPDATA; TEMP = $env:TEMP; TMP = $env:TMP; ProgramData = $env:ProgramData }
function New-SandboxFile([string]$Path) { [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path)); [IO.File]::WriteAllText($Path, 'x') }
function Get-SandboxLog([string]$Component) {
	$files = @(Get-ChildItem -LiteralPath $sandbox -Recurse -File -Filter "$($Component)_*.log" -ErrorAction SilentlyContinue)
	return (($files | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n")
}
function Invoke-TestScript([string]$Name, [hashtable]$Arguments = @{}) {
	$script:calls.Clear()
	$global:LASTEXITCODE = $null
	$result = [pscustomobject]@{ ExitCode = $null; Output = @(); Error = '' }
	try { $result.Output = @(& (Join-Path $scripts $Name) @Arguments 2>&1); $result.ExitCode = $global:LASTEXITCODE }
	catch { $result.Error = "$($_.Exception.Message) @ $($_.ScriptStackTrace -replace '\r?\n', ' <- ')"; $result.ExitCode = 1 }
	return $result
}

try {
	[void][IO.Directory]::CreateDirectory($sandbox)
	$env:LOCALAPPDATA = Join-Path $sandbox 'Local'
	$env:APPDATA = Join-Path $sandbox 'Roaming'
	$env:TEMP = Join-Path $sandbox 'Temp'
	$env:TMP = $env:TEMP
	$env:ProgramData = Join-Path $sandbox 'ProgramData'
	foreach ($folder in $env:LOCALAPPDATA, $env:APPDATA, $env:TEMP, $env:ProgramData) { [void][IO.Directory]::CreateDirectory($folder) }

	#------------------------------------------------------------------------------------------------
	# Static checks: header, logging, references
	#------------------------------------------------------------------------------------------------
	$catalog = [xml][IO.File]::ReadAllText("$sources\Issues_List.xml")
	$health = [xml][IO.File]::ReadAllText("$sources\Health_Config.xml")
	$referenced = @($catalog.SelectNodes('//Action/Script') | ForEach-Object { $_.InnerText.Trim() }) + @($health.SelectNodes('//Remediation') | ForEach-Object { $_.GetAttribute('Script') })
	$script:unused = @()
	foreach ($name in ($referenced | Sort-Object -Unique)) { Assert-Equal (Test-Path -LiteralPath (Join-Path $scripts $name)) $true "Referenced script exists: $name" }
	foreach ($file in Get-ChildItem -LiteralPath $scripts -Filter '*.ps1') {
		if ($file.Name -eq 'Collect-DeviceLogs.ps1') { continue }   # external collector, logged by SelfX_Device_CollectLogs.ps1
		$text = [IO.File]::ReadAllText($file.FullName)
		# Code checks only after the header (its history describes the former behaviour).
		$code = $text.Substring($text.IndexOf('#>') + 2)
		$errors = $null
		[void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$errors)
		Assert-Equal @($errors).Count 0 "$($file.Name) parses"
		Assert-Equal ($text -match 'Version\s*:\s*2\.6\.\d+') $true "$($file.Name) header version 2.6.x"
		Assert-Equal ($code.Contains('Initialize-SelfXLog')) $true "$($file.Name) initializes the logging"
		Assert-Equal ($code -match '(?i)-like\s+"\*(word|teams)\*"') $false "$($file.Name) uses no *word* / *teams* wildcards"
		Assert-Equal ($code.Contains('echo Y|')) $false "$($file.Name) does not answer prompts in English only"
		Assert-Equal ($code -match '(?i)C:\\Users\\') $false "$($file.Name) uses no fixed C:\Users path"
		if ($referenced -notcontains $file.Name) { $script:unused += $file.Name }
	}
	foreach ($action in $catalog.SelectNodes('//Action')) {
		$text = [IO.File]::ReadAllText((Join-Path $scripts $action.Script.Trim()))
		Assert-Equal ($text -match "Context\s*:\s*$($action.Context.Trim())") $true "$($action.Script) header context matches the catalog ($($action.GetAttribute('Id')))"
	}
	foreach ($remediation in $health.SelectNodes('//Remediation')) {
		Assert-Equal ([IO.File]::ReadAllText((Join-Path $scripts $remediation.GetAttribute('Script'))) -match 'Context\s*:\s*System') $true "$($remediation.GetAttribute('Script')) runs as System"
	}

	#------------------------------------------------------------------------------------------------
	# User actions
	#------------------------------------------------------------------------------------------------
	$chrome = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default'
	foreach ($item in 'Cache\data_0', 'Code Cache\js\a', 'Cookies', 'Network\Cookies', 'History', 'Bookmarks') { New-SandboxFile (Join-Path $chrome $item) }
	New-FakeProcess 'chrome' 'C:\Program Files\Google\Chrome\Application\chrome.exe'
	$run = Invoke-TestScript 'SelfX_Browser_ClearChromeCache.ps1'
	Assert-Equal $run.ExitCode 0 "Chrome cache: exit code ($($run.Error) $($run.Output -join ' '))"
	Assert-Equal "$(Test-Path (Join-Path $chrome 'Cache'))/$(Test-Path (Join-Path $chrome 'Cookies'))/$(Test-Path (Join-Path $chrome 'Bookmarks'))" 'False/False/True' 'Chrome cache: caches removed, bookmarks kept'
	Assert-Equal ($script:calls -contains 'Stop-Process chrome') $true 'Chrome cache: Chrome closed'
	Assert-Equal ((Get-SandboxLog 'SelfX_Browser_ClearChromeCache') -match 'Removed Cache') $true 'Chrome cache: logged'

	foreach ($root in $env:LOCALAPPDATA, $env:APPDATA) { New-SandboxFile (Join-Path $root 'Mozilla\Firefox\Profiles\abc.default\cache2\entries\x'); New-SandboxFile (Join-Path $root 'Mozilla\Firefox\Profiles\abc.default\cookies.sqlite'); New-SandboxFile (Join-Path $root 'Mozilla\Firefox\Profiles\abc.default\places.sqlite') }
	$run = Invoke-TestScript 'SelfX_Browser_ClearFirefoxCache.ps1'
	Assert-Equal $run.ExitCode 0 'Firefox cache: exit code'
	Assert-Equal "$(Test-Path (Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles\abc.default\cookies.sqlite'))/$(Test-Path (Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles\abc.default\places.sqlite'))" 'False/True' 'Firefox cache: cookies removed, places kept'
	Assert-Equal ((Get-SandboxLog 'SelfX_Browser_ClearFirefoxCache') -match '2 profile folder') $true 'Firefox cache: both profile roots logged'

	$global:DnsFails = $false
	Assert-Equal (Invoke-TestScript 'SelfX_Device_ClearCache.ps1').ExitCode 0 'DNS cache: exit code'
	$global:DnsFails = $true
	Assert-Equal (Invoke-TestScript 'SelfX_Device_ClearCache.ps1').ExitCode 1 'DNS cache: failure is exit 1'
	Assert-Equal ((Get-SandboxLog 'SelfX_Device_ClearCache') -match 'Error.*Access denied') $true 'DNS cache: failure logged'

	New-SandboxFile (Join-Path $env:TEMP 'a.tmp'); New-SandboxFile (Join-Path $env:TEMP 'sub\b.tmp')
	$run = Invoke-TestScript 'SelfX_Device_DeviceSlow.ps1'
	Assert-Equal $run.ExitCode 0 'Device slow: an empty recycle bin is no error'
	Assert-Equal @(Get-ChildItem -LiteralPath $env:TEMP -Force | Where-Object { $_.Name -ne 'SelfX' }).Count 0 'Device slow: TEMP emptied'
	Assert-Equal ((Get-SandboxLog 'SelfX_Device_DeviceSlow') -match 'TEMP: 2 item\(s\) removed') $true 'Device slow: logged'

	New-FakeProcess 'EXCEL' 'C:\Office\EXCEL.EXE'
	$run = Invoke-TestScript 'SelfX_Excel_Reboot.ps1'
	Assert-Equal "$($run.ExitCode)|$($script:calls -join ';')" '0|Stop-Process EXCEL;Start-Process C:\Office\EXCEL.EXE' 'Excel: closed and started again'
	$run = Invoke-TestScript 'SelfX_Excel_Reboot.ps1'
	Assert-Equal "$($run.ExitCode)|$($script:calls.Count)" '0|0' 'Excel: nothing to do when not running'

	New-FakeProcess 'WINWORD' 'C:\Office\WINWORD.EXE'
	New-FakeProcess '1Password' 'C:\Apps\1Password.exe'
	New-FakeProcess 'wordpad' 'C:\Windows\wordpad.exe'
	$run = Invoke-TestScript 'SelfX_Word_Reboot.ps1'
	Assert-Equal "$($run.ExitCode)|$($script:calls -join ';')" '0|Stop-Process WINWORD;Start-Process C:\Office\WINWORD.EXE' 'Word: only WINWORD is closed and started again'
	Assert-Equal @($global:FakeProcesses | Where-Object { $_.ProcessName -in '1Password', 'wordpad' }).Count 2 'Word: 1Password and WordPad keep running'
	$global:FakeProcesses.Clear()

	New-FakeProcess 'ms-teams' 'C:\Program Files\WindowsApps\MSTeams_1_x64__8wekyb3d8bbwe\ms-teams.exe'
	New-FakeProcess 'ms-teams' 'C:\Program Files\WindowsApps\MSTeams_1_x64__8wekyb3d8bbwe\ms-teams.exe'
	New-FakeProcess 'TeamViewer' 'C:\Apps\TeamViewer.exe'
	$run = Invoke-TestScript 'SelfX_Teams_Reboot.ps1'
	Assert-Equal $run.ExitCode 0 'Teams restart: exit code'
	Assert-Equal @($script:calls | Where-Object { $_ -like 'Stop-Process*' }).Count 2 'Teams restart: both Teams processes closed'
	Assert-Equal ($script:calls[-1] -like '*explorer.exe shell:AppsFolder\MSTeams_8wekyb3d8bbwe!MSTeams') $true 'Teams restart: new Teams started through its app ID'
	Assert-Equal @($global:FakeProcesses | Where-Object ProcessName -eq 'TeamViewer').Count 1 'Teams restart: TeamViewer keeps running'

	$newTeamsCache = Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams'
	New-SandboxFile (Join-Path $newTeamsCache 'EBWebView\a'); New-SandboxFile (Join-Path $newTeamsCache 'settings.json')
	New-SandboxFile (Join-Path $env:APPDATA 'Microsoft\Teams\IndexedDB\x'); New-SandboxFile (Join-Path $env:APPDATA 'Microsoft\Teams\desktop-config.json')
	$run = Invoke-TestScript 'SelfX_Teams_ResetCache.ps1'
	Assert-Equal $run.ExitCode 0 'Teams cache: exit code'
	Assert-Equal "$(@(Get-ChildItem -LiteralPath $newTeamsCache -Force).Count)/$(Test-Path (Join-Path $env:APPDATA 'Microsoft\Teams\IndexedDB'))/$(Test-Path (Join-Path $env:APPDATA 'Microsoft\Teams\desktop-config.json'))" '0/False/True' 'Teams cache: caches removed, configuration kept'
	Assert-Equal ($script:calls[-1] -like '*shell:AppsFolder\MSTeams_8wekyb3d8bbwe!MSTeams') $true 'Teams cache: new Teams started again'
	$global:FakeProcesses.Clear()

	$oneDrive = Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'
	New-SandboxFile $oneDrive
	New-FakeProcess 'OneDrive' $oneDrive
	$run = Invoke-TestScript 'SelfX_OneDrive_Reboot.ps1'
	Assert-Equal "$($run.ExitCode)|$($script:calls -join ';')" "0|Stop-Process OneDrive;Start-Process $oneDrive /background" 'OneDrive restart: closed and started in the background'
	New-FakeProcess 'OneDrive' $oneDrive
	$run = Invoke-TestScript 'SelfX_OneDrive_Reset.ps1'
	Assert-Equal "$($run.ExitCode)|$($script:calls -join ';')" "0|Stop-Process OneDrive;Start-Process $oneDrive /reset;Start-Process $oneDrive /background" 'OneDrive reset: reset and background start'
	$run = Invoke-TestScript 'SelfX_OneDrive_Run.ps1'
	Assert-Equal "$($run.ExitCode)|$($script:calls -join ';')" "0|Start-Process $oneDrive" 'OneDrive start: started from LOCALAPPDATA'
	New-FakeProcess 'OneDrive' $oneDrive
	$run = Invoke-TestScript 'SelfX_OneDrive_Run.ps1'
	Assert-Equal "$($run.ExitCode)|$($script:calls.Count)" '0|0' 'OneDrive start: no second start when running'
	$global:FakeProcesses.Clear()

	New-FakeProcess 'OUTLOOK' 'C:\Office\OUTLOOK.EXE'
	$run = Invoke-TestScript 'SelfX_Outlook_TeamsAddIn.ps1'
	Assert-Equal $run.ExitCode 0 'Outlook add-in: exit code'
	Assert-Equal (@($script:calls | Where-Object { $_ -like 'Set-ItemProperty HKCU:*TeamsAddin.FastConnect LoadBehavior=3' }).Count) 1 'Outlook add-in: LoadBehavior 3'
	Assert-Equal (@($script:calls | Where-Object { $_ -like 'Set-ItemProperty HKCU:*DoNotDisableAddinList TeamsAddin.FastConnect=1' }).Count) 1 'Outlook add-in: not disabled again'
	Assert-Equal "$($script:calls[-2])|$($script:calls[-1])" 'Stop-Process OUTLOOK|Start-Process C:\Office\OUTLOOK.EXE' 'Outlook add-in: Outlook restarted'

	$run = Invoke-TestScript 'SelfX_Poste_WSReset.ps1'
	Assert-Equal "$($run.ExitCode)|$($script:calls[0])" "0|Start-Process $(Join-Path $env:SystemRoot 'System32\wsreset.exe')" 'Store reset: wsreset started'

	#------------------------------------------------------------------------------------------------
	# System actions and repairs (through the service as SYSTEM)
	#------------------------------------------------------------------------------------------------
	$global:SignatureVersion = '1.441.85.0'
	$global:UpdateFails = $false
	$run = Invoke-TestScript 'SelfX_Defender_UpdateSignature.ps1'
	Assert-Equal ($run.ExitCode -eq 0 -and "$($run.Output[0])" -like 'Defender signatures: 1.441.85.0 -> 1.441.99.0 (last update *)') $true 'Defender: signatures updated'
	$global:UpdateFails = $true
	Assert-Equal (Invoke-TestScript 'SelfX_Defender_UpdateSignature.ps1').ExitCode 1 'Defender: failure is exit 1'

	$run = Invoke-TestScript 'SelfX_Intune_RestartService.ps1'
	Assert-Equal "$($run.ExitCode)|$($script:calls -join ';')" '0|Restart-Service IntuneManagementExtension' 'IME restart'

	$run = Invoke-TestScript 'SelfX_OneDrive_CHKDSK.ps1'
	Assert-Equal "$($run.ExitCode)|$($script:calls -join ';')" "0|Repair-Volume $("$env:SystemDrive".TrimEnd(':')) offline=True" 'Disk check: offline scan and fix scheduled (language independent)'

	# Network adapters: host with cable, Wi-Fi, hidden cellular profiles and a Hyper-V switch; then a virtual machine.
	$global:FakeAdapters = @(
		[pscustomobject]@{ Name = 'Ethernet'; InterfaceDescription = 'Realtek USB GbE'; Status = 'Up'; HardwareInterface = $true; ConnectorPresent = $true; Virtual = $false; ifIndex = 11 }
		[pscustomobject]@{ Name = 'Wi-Fi'; InterfaceDescription = 'Intel Wi-Fi 6E'; Status = 'Disconnected'; HardwareInterface = $true; ConnectorPresent = $true; Virtual = $false; ifIndex = 5 }
		[pscustomobject]@{ Name = 'Cellular 7'; InterfaceDescription = 'Fibocom L860'; Status = 'Not Present'; HardwareInterface = $true; ConnectorPresent = $true; Virtual = $false; ifIndex = 41 }
		[pscustomobject]@{ Name = 'vEthernet (Default Switch)'; InterfaceDescription = 'Hyper-V Virtual Ethernet Adapter'; Status = 'Up'; HardwareInterface = $false; ConnectorPresent = $false; Virtual = $true; ifIndex = 60 }
		[pscustomobject]@{ Name = 'Ethernet 2'; InterfaceDescription = 'Disabled NIC'; Status = 'Disabled'; HardwareInterface = $true; ConnectorPresent = $true; Virtual = $false; ifIndex = 12 })
	$global:FakeRoutes = @([pscustomobject]@{ ifIndex = 11; NextHop = '192.168.10.1' })
	$run = Invoke-TestScript 'SelfX_Device_AirePlaneMode.ps1'
	Assert-Equal "$($run.ExitCode)|$($script:calls -join ';')" '0|Restart-NetAdapter Ethernet;Restart-NetAdapter Wi-Fi' 'Network restart: physical present adapters only'
	$global:FakeAdapters = @([pscustomobject]@{ Name = 'Ethernet'; InterfaceDescription = 'Microsoft Hyper-V Network Adapter'; Status = 'Up'; HardwareInterface = $false; ConnectorPresent = $false; Virtual = $false; ifIndex = 4 })
	$global:FakeRoutes = @([pscustomobject]@{ ifIndex = 4; NextHop = '192.168.250.1' })
	$run = Invoke-TestScript 'SelfX_Device_AirePlaneMode.ps1'
	Assert-Equal "$($run.ExitCode)|$($script:calls -join ';')" '0|Restart-NetAdapter Ethernet' 'Network restart: virtual machine adapter with default route'
	$global:FakeRoutes = @()
	Assert-Equal (Invoke-TestScript 'SelfX_Device_AirePlaneMode.ps1').ExitCode 1 'Network restart: no adapter is exit 1'

	# Restart: only the function is called, with a non-existent shutdown.exe; the script body never runs.
	. (Join-Path $scripts 'SelfX_Device_Restart.ps1')
	$restartText = [IO.File]::ReadAllText((Join-Path $scripts 'SelfX_Device_Restart.ps1'))
	Assert-Equal ($restartText.Contains('& $ShutdownExe /r /t $DelaySeconds /d p:4:1')) $true 'Restart: shutdown /r with delay and planned reason'
	Assert-Equal ($restartText -match '/l\b|/s\b|/p\b|/h\b|logoff|LockWorkStation') $false 'Restart: no sign-out, shutdown or hibernate'
	$dummy = Join-Path $sandbox 'does-not-exist\shutdown.exe'
	Assert-Equal (Test-Path -LiteralPath $dummy) $false 'Restart: dummy shutdown.exe does not exist'
	$failed = $false
	try { [void](Invoke-SelfXRestart -ShutdownExe $dummy -DelaySeconds 30) } catch { $failed = $_.Exception.Message -like 'shutdown.exe not found*' }
	Assert-Equal $failed $true 'Restart: missing shutdown.exe is reported'

	# Updates: Windows Update Agent flow with a simulated session (search, download, install, per-update result).
	. (Join-Path $scripts 'SelfX_Updates_Install.ps1')
	function Write-SelfXLog { param($Message, $Level) $script:updateLog.Add("$Level|$Message") }
	function New-SelfXUpdateCollection {
		$list = New-Object System.Collections.Generic.List[object]
		$coll = [pscustomobject]@{ List = $list }
		$coll | Add-Member ScriptMethod Add { param($u) $this.List.Add($u); $this.List.Count - 1 }
		$coll | Add-Member ScriptMethod Item { param($i) $this.List[$i] }
		$coll | Add-Member ScriptProperty Count { $this.List.Count }
		$coll
	}
	function New-FakeUpdate([string]$Title, [string]$Kb, [bool]$Optional = $false, [bool]$Download = $true, [int]$InstallCode = 2, [bool]$Reboot = $false) {
		$u = [pscustomobject]@{ Title = $Title; KBArticleIDs = @($Kb); BrowseOnly = $Optional; InstallationBehavior = [pscustomobject]@{ CanRequestUserInput = $false }
			EulaAccepted = $false; IsDownloaded = $false; Download = $Download; InstallCode = $InstallCode; Reboot = $Reboot }
		$u | Add-Member ScriptMethod AcceptEula { $this.EulaAccepted = $true }
		$u
	}
	function New-FakeSession([object[]]$Updates, [bool]$Busy = $false) {
		$state = [pscustomobject]@{ Updates = $Updates; Busy = $Busy; Calls = (New-Object System.Collections.Generic.List[string]) }
		$session = [pscustomobject]@{ State = $state }
		$session | Add-Member ScriptMethod CreateUpdateSearcher {
			$searcher = [pscustomobject]@{ Online = $false; State = $this.State }
			$searcher | Add-Member ScriptMethod Search { param($q) $this.State.Calls.Add("Search online=$($this.Online)"); [pscustomobject]@{ ResultCode = 2; Updates = $this.State.Updates } }
			$searcher }
		$session | Add-Member ScriptMethod CreateUpdateDownloader {
			$downloader = [pscustomobject]@{ Updates = $null; State = $this.State }
			$downloader | Add-Member ScriptMethod Download {
				$this.State.Calls.Add("Download $($this.Updates.Count)")
				foreach ($u in $this.Updates.List) { $u.IsDownloaded = $u.Download }
				$r = [pscustomobject]@{ ResultCode = 2 }; $r | Add-Member ScriptMethod GetUpdateResult { param($i) [pscustomobject]@{ HResult = -2145107924 } }; $r }
			$downloader }
		$session | Add-Member ScriptMethod CreateUpdateInstaller {
			$installer = [pscustomobject]@{ Updates = $null; ForceQuiet = $false; State = $this.State }
			$installer | Add-Member ScriptProperty IsBusy { $b = $this.State.Busy; $this.State.Busy = $false; $b }
			$installer | Add-Member ScriptMethod Install {
				$this.State.Calls.Add("Install $($this.Updates.Count) quiet=$($this.ForceQuiet)")
				$list = $this.Updates.List
				$r = [pscustomobject]@{ RebootRequired = [bool]($list | Where-Object { $_.Reboot -and $_.InstallCode -eq 2 }); List = $list }
				$r | Add-Member ScriptMethod GetUpdateResult { param($i) [pscustomobject]@{ ResultCode = $this.List[$i].InstallCode; HResult = 0; RebootRequired = $this.List[$i].Reboot } }
				$r }
			$installer }
		$session
	}
	$script:updateLog = New-Object System.Collections.Generic.List[string]
	$session = New-FakeSession @((New-FakeUpdate '2026-10 .NET Framework Security Update' '5127690' -Reboot $true), (New-FakeUpdate 'Audio driver' ''), (New-FakeUpdate 'Optional preview' '5099999' -Optional $true))
	$result = Install-SelfXWindowsUpdates -Session $session -PollSeconds 1
	Assert-Equal ($session.State.Calls -join ';') 'Search online=True;Download 2;Install 2 quiet=True' 'Updates: online search, download and quiet install through the Windows Update Agent'
	Assert-Equal "$($result.Ok)|$($result.Text)" 'True|Windows Update: 2 of 2 update(s) installed (KB5127690, Audio driver); restart required to complete' 'Updates: installed updates and restart reported'
	Assert-Equal (@($script:updateLog | Where-Object { $_ -like '*Skipped (optional*Optional preview' }).Count) 1 'Updates: optional update skipped and logged'
	Assert-Equal (@($script:updateLog | Where-Object { $_ -like '*Installed: 2026-10 .NET Framework Security Update (restart required)' }).Count) 1 'Updates: each installed update logged'
	# A restart that was pending before is not reported as an installation (fault of 2.6.0).
	$result = Install-SelfXWindowsUpdates -Session (New-FakeSession @()) -PollSeconds 1
	Assert-Equal "$($result.Ok)|$($result.Text)" 'True|Windows Update: no updates to install' 'Updates: nothing to install is not reported as installed'
	$session = New-FakeSession @((New-FakeUpdate 'Cumulative update' '5070001' -InstallCode 4), (New-FakeUpdate 'Defender platform' '5007651' -Download $false), (New-FakeUpdate 'Malicious software removal tool' '890830'))
	$result = Install-SelfXWindowsUpdates -Session $session -PollSeconds 1
	Assert-Equal "$($result.Ok)|$($result.Text)" 'False|Windows Update: 1 of 3 update(s) installed (KB890830); failed: KB5070001; not downloaded: KB5007651' 'Updates: failed and not downloaded updates are reported (exit 1)'
	$session = New-FakeSession @((New-FakeUpdate 'Update' '1')) $true
	$script:updateLog.Clear()
	[void](Install-SelfXWindowsUpdates -Session $session -PollSeconds 1)
	Assert-Equal (@($script:updateLog | Where-Object { $_ -like '*installing right now; waiting*' }).Count) 1 'Updates: waits while Windows Update is busy'
	$updatesText = [IO.File]::ReadAllText((Join-Path $scripts 'SelfX_Updates_Install.ps1'))
	$updatesCode = $updatesText.Substring($updatesText.IndexOf('#>') + 2)
	Assert-Equal ($updatesCode -match '(?i)UsoClient|shutdown|Restart-Computer|RebootRequired\\') $false 'Updates: no UsoClient (fails on Windows 11 24H2), never restarts, no registry restart markers'

	# App retry: reset of the cached error and the retry schedule of failed apps (registry mocked).
	. "$sources\HealthStatus.ps1"
	. (Join-Path $scripts 'SelfX_Apps_RetryInstall.ps1')
	$userKey = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\57f4b2f0-0ef4-4927-ab53-d91d54f4a5fd'
	$appId = '046f98d8-667e-4463-b776-d69d48a632d3'
	$script:removed = New-Object System.Collections.Generic.List[string]
	function Test-Path { param([string]$LiteralPath, $PathType) $true }
	function Remove-Item { param([string]$LiteralPath, [switch]$Recurse, [switch]$Force, $ErrorAction) $script:removed.Add($LiteralPath) }
	function Get-ChildItem { param([string]$LiteralPath, $ErrorAction) @([pscustomobject]@{ PSPath = "$LiteralPath\hash1" }, [pscustomobject]@{ PSPath = "$LiteralPath\hash2" }) }
	function Get-ItemProperty { param([string]$LiteralPath, $ErrorAction) if ($LiteralPath -like '*hash1') { [pscustomobject]@{ "$($appId)_1" = 'x' } } else { [pscustomobject]@{ 'ffffffff-0000-0000-0000-000000000000' = 'x' } } }
	$report = [pscustomobject]@{ Id = $appId; AppKey = "$userKey\$($appId)_7"; UserKey = $userKey }
	Assert-Equal (Reset-SelfXFailedApp -Report $report) 2 'App retry: app result and its retry schedule removed'
	Assert-Equal ($script:removed -join ';') "$userKey\$($appId)_7;$userKey\GRS\hash1" 'App retry: only the keys of the failed app'
	$outside = $false
	try { [void](Reset-SelfXFailedApp -Report ([pscustomobject]@{ Id = $appId; AppKey = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Other\$appId"; UserKey = $userKey })) } catch { $outside = $true }
	Assert-Equal $outside $true 'App retry: nothing outside the IME cache is deleted'
	Microsoft.PowerShell.Management\Remove-Item Function:\Test-Path, Function:\Remove-Item, Function:\Get-ChildItem, Function:\Get-ItemProperty

	# App status: app id from the key <app id>_<revision> (not the user id), names from the IME logs, error codes.
	function Get-ChildItem { param([string]$LiteralPath, [switch]$Recurse, $ErrorAction, [switch]$File)
		if ($LiteralPath -like 'HKLM:*') {
			@([pscustomobject]@{ PSPath = 'app1'; Name = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\57f4b2f0-0ef4-4927-ab53-d91d54f4a5fd\$($appId)_7" }
			  [pscustomobject]@{ PSPath = 'app2'; Name = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\57f4b2f0-0ef4-4927-ab53-d91d54f4a5fd\0675cabb-3d3d-4c3f-abfd-349fb022d5cc_2' }
			  [pscustomobject]@{ PSPath = 'app3'; Name = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\00000000-0000-0000-0000-000000000000\11111111-2222-3333-4444-555555555555_1' })
		} else { Microsoft.PowerShell.Management\Get-ChildItem @PSBoundParameters } }
	function Get-ItemProperty { param([string]$LiteralPath, $ErrorAction)
		switch ($LiteralPath) {
			'app1' { [pscustomobject]@{ EnforcementStateMessage = '{"EnforcementState":5000,"ErrorCode":-2016345060}' } }
			'app2' { [pscustomobject]@{ EnforcementStateMessage = '{"EnforcementState":1000,"ErrorCode":0}' } }
			'app3' { [pscustomobject]@{ EnforcementStateMessage = '{"EnforcementState":3000,"ErrorCode":null}' } }
		} }
	function Test-Path { param([string]$LiteralPath, $PathType) if ($LiteralPath -like 'HKLM:*') { return $true }; Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath }
	$reports = @(Get-SelfXAppReports)
	Assert-Equal $reports[0].Id $appId 'App status: app id from <app id>_<revision>, not the user id'
	Assert-Equal $reports[0].UserKey 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\57f4b2f0-0ef4-4927-ab53-d91d54f4a5fd' 'App status: user key'
	Assert-Equal (Format-SelfXAppError -2016345060) '0x87D1041C' 'App status: error code in hex'
	$imeLogs = Join-Path $sandbox 'ImeLogs'
	New-SandboxFile (Join-Path $imeLogs 'AppWorkload.log')
	[IO.File]::WriteAllText((Join-Path $imeLogs 'AppWorkload.log'), "Get policies [{`"Id`":`"$appId`",`"Name`":`"Monitoring \`"Agent\`"`",`"Version`":7}]")
	$names = Get-SelfXImeAppNames -Ids @($appId) -LogFolder $imeLogs
	Assert-Equal $names[$appId] 'Monitoring "Agent"' 'App status: name from the IME log (JSON unescaped)'
	function Get-SelfXImeAppNames { param($Ids, $LogFolder) @{ $appId = 'Monitoring Agent'; '0675cabb-3d3d-4c3f-abfd-349fb022d5cc' = 'Vantage Service' } }
	[xml]$appConfig = '<Applications/>'
	$appHealth = Get-SelfXApplicationHealth -Configuration $appConfig.DocumentElement
	Assert-Equal $appHealth.Status 'Error' 'App status: failed app is an error'
	Assert-Equal $appHealth.Detail '1 of 2 app(s) could not be installed: Monitoring Agent (error 0x87D1041C).' 'App status: clear detail with name and error (not applicable app not counted)'
	Microsoft.PowerShell.Management\Remove-Item Function:\Get-ChildItem, Function:\Get-ItemProperty, Function:\Test-Path, Function:\Get-SelfXImeAppNames

	#------------------------------------------------------------------------------------------------
	# Read-only scripts, run for real in a child process (sandbox ProgramData for their logs)
	#------------------------------------------------------------------------------------------------
	$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
	[void][IO.Directory]::CreateDirectory((Join-Path $env:ProgramData 'SelfX\Logs'))
	$output = @(& $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sources 'HealthChecks\Check-Compliance.ps1') 2>&1)
	Assert-Equal ($LASTEXITCODE -in 0, 1) $true 'Check-Compliance runs (exit 0 or 1)'
	Assert-Equal ("$($output[-1])" -match '^(Not met|Local compliance criteria met):') $true 'Check-Compliance: result is the last output line'
	Assert-Equal ((Get-SandboxLog 'Check-Compliance') -match '(Not met|criteria met)') $true 'Check-Compliance: result logged'

	$output = @(& $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Detection.ps1') 2>&1)
	Assert-Equal "$LASTEXITCODE|$(@($output).Count)" '1|0' 'Detection: not installed here, exit 1 without output'
	Assert-Equal ((Get-SandboxLog 'Detection') -match 'SelfX \d+\.\d+\.\d+: not detected') $true 'Detection: result logged'

	$cache = Join-Path $sandbox 'Health.json'
	$json = (& $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sources 'HealthStatus.ps1') -Collect -OnlyId Disk -CacheFile $cache 2>&1) -join ''
	$parsed = ConvertFrom-Json $json
	Assert-Equal (@($parsed)[0].Id) 'Disk' 'HealthStatus -Collect: stdout is still pure JSON with logging'
	Assert-Equal ((Get-SandboxLog 'HealthStatus') -match 'Health check Disk finished') $true 'HealthStatus: run logged'

	# Logs of the scripts: user actions fall back to LOCALAPPDATA without the installed Logs\Users folder.
	Assert-Equal (@(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'SelfX\Logs') -Filter '*.log').Count -ge 10) $true 'Logs of the user actions written'
} finally {
	foreach ($key in $saved.Keys) { Set-Item -Path "Env:$key" -Value $saved[$key] }
	Microsoft.PowerShell.Management\Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:unused.Count) { Write-Output "Note: not used by the catalog or Health_Config (available for administrators): $($script:unused -join ', ')" }
Write-Output "PASS: $script:assertions assertions. All commands with effects mocked; files only in a temporary sandbox."
