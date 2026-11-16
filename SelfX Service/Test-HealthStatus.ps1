<#
.SYNOPSIS
    Run isolated health-check regression tests without querying or changing this computer.
.DESCRIPTION
    All system data and external process calls are mocked. No service is installed, no task
    is registered and no extension script is executed. Module autoloading is disabled.
.NOTES
    Version: 2.5.6
    History:
    2.3.0  2026-10-28  Wolfgang Baeck  Initial isolated health-check tests.
    2.3.1  2026-10-28  Wolfgang Baeck  Test remediation mapping, service allowlist and recheck callbacks.
    2.3.2  2026-10-28  Wolfgang Baeck  Test single-check filter, HEALTH request validation and OK button.
    2.3.3  2026-10-29  Wolfgang Baeck  Test pending reboot and updates-to-install checks (registry/WUA mocked).
    2.3.4  2026-10-29  Wolfgang Baeck  Test Pending status, Defender details and When="NotOK" remediations.
    2.5.0  2026-11-04  Wolfgang Baeck  Test status cache, STATUS request, background settings and status cards.
        2.5.3  2026-11-04  Wolfgang Baeck  Test UTC time markers and conversion into the time zone of the user.
        2.5.5  2026-11-05  Wolfgang Baeck  Test the last output line of script checks as detail text.
        2.5.6  2026-11-05  Wolfgang Baeck  Test the Updates remediation and the remediation TimeoutSeconds of the service.
    #>
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerShell.Utility
Import-Module Microsoft.PowerShell.Management
$PSModuleAutoLoadingPreference = 'None'
$sources = Join-Path $PSScriptRoot 'Sources'
. "$sources\HealthStatus.ps1"
. "$sources\SelfXServiceClient.ps1"
. "$sources\SystemInfo.ps1"
. "$sources\Localization.ps1"
# Logger functions without Initialize-SelfXLog: they write nothing during the tests.
. "$sources\SelfXLog.ps1"
$appReader = (Get-Command Get-SelfXAppReports).ScriptBlock
$rebootReader = (Get-Command Get-SelfXPendingRebootMarkers).ScriptBlock

$script:assertions = 0
function Assert-Equal($Actual, $Expected, $Message) {
    $script:assertions++
    if ($Actual -ne $Expected) { throw "$Message : expected '$Expected', got '$Actual'." }
}
function Assert-Throws([scriptblock]$Action, $Message) {
    $threw = $false
    try { & $Action | Out-Null } catch { $threw = $true }
    Assert-Equal $threw $true $Message
}

# Each involved command resolves to a function mock, never to an autoloaded system module.
function Get-Service { param($Name, $ErrorAction) if ($script:serviceMissing) { throw 'Mock service missing' }; [pscustomobject]@{ Status = $script:serviceState } }
function Get-CimInstance { param($ClassName, $Filter, $ErrorAction) $script:disks }
function Get-MpComputerStatus { param($ErrorAction) if ($script:defenderMissing) { throw 'Mock access denied' }; $script:defender }
function Get-BitLockerVolume { param($ErrorAction) $script:volumes }
function Get-SelfXAppReports { $script:reports }
function Get-SelfXPendingRebootMarkers { if ($script:rebootFails) { throw 'Mock registry denied' }; $script:rebootMarkers }
function Get-SelfXUpdateSearchResult { if ($script:updateFails) { throw 'Mock WUA unavailable' }; $script:updateSearch }
function Invoke-SelfXHealthScript { param($Path, $TimeoutSeconds) if ($script:timeout) { throw 'Mock timeout' }; [pscustomobject]@{ ExitCode = $script:exitCode; Output = $script:checkOutput } }
function Start-Process { throw 'Forbidden in tests' }
function Invoke-CimMethod { throw 'Forbidden in tests' }
function Register-ScheduledTask { throw 'Forbidden in tests' }
function New-ScheduledTask { throw 'Forbidden in tests' }
function New-ScheduledTaskAction { throw 'Forbidden in tests' }
function New-ScheduledTaskTrigger { throw 'Forbidden in tests' }
function New-ScheduledTaskPrincipal { throw 'Forbidden in tests' }
function New-ScheduledTaskSettingsSet { throw 'Forbidden in tests' }
foreach ($name in @('Get-Service','Get-CimInstance','Get-MpComputerStatus','Get-BitLockerVolume',
    'Get-SelfXAppReports','Get-SelfXPendingRebootMarkers','Get-SelfXUpdateSearchResult',
    'Invoke-SelfXHealthScript','Start-Process','Invoke-CimMethod',
    'Register-ScheduledTask','New-ScheduledTask','New-ScheduledTaskAction','New-ScheduledTaskTrigger',
    'New-ScheduledTaskPrincipal','New-ScheduledTaskSettingsSet')) {
    Assert-Equal (Get-Command $name).CommandType Function "Mock resolution: $name"
}
$originalRoot = $env:SystemRoot
$env:SystemRoot = 'Z:\SelfX-Nonexistent-Test-Windows'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('SelfXHealthTests-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
try {
    $script:serviceState = 'Running'
    Assert-Equal (Get-SelfXServiceHealth IME).Status OK 'Running service'
    $script:serviceState = 'Stopped'
    Assert-Equal (Get-SelfXServiceHealth IME).Status Error 'Stopped service'
    Assert-Equal (Get-SelfXServiceHealth IME Stopped).Status OK 'Expected stopped'
    $script:serviceMissing = $true
    Assert-Equal (Get-SelfXServiceHealth IME).Status Error 'Missing service'
    $script:serviceMissing = $false

    foreach ($case in @(@(1000,100,'Error'), @(1000,101,'OK'), @(100,19.999,'Error'), @(100,20,'OK'), @(100,21,'OK'))) {
        $script:disks = @([pscustomobject]@{ DeviceID='C:'; Size=$case[0]*1GB; FreeSpace=$case[1]*1GB })
        Assert-Equal (Get-SelfXDiskHealth 90 20).Status $case[2] "Disk boundary $($case[0])/$($case[1])"
    }
    $script:disks = @()
    Assert-Equal (Get-SelfXDiskHealth 90 20).Status Unknown 'No disks'
    $script:disks = @([pscustomobject]@{ DeviceID='C:'; Size=0; FreeSpace=0 })
    Assert-Equal (Get-SelfXDiskHealth 90 20).Status Unknown 'Invalid disk size'
    $script:disks = @([pscustomobject]@{ DeviceID='C:'; Size=500GB; FreeSpace=100GB })

    $script:defender = [pscustomobject]@{ AMServiceEnabled=$true; AntivirusEnabled=$true; RealTimeProtectionEnabled=$true; DefenderSignaturesOutOfDate=$false; AntivirusSignatureAge=1; AMRunningMode='Normal'
        AntivirusSignatureVersion='1.419.123.0';         AntivirusSignatureLastUpdated=[datetime]::SpecifyKind([datetime]'2026-10-28 07:15', 'Utc').ToLocalTime(); AMProductVersion='4.18.25090.1'; AMEngineVersion='1.1.25090.3' }
    Assert-Equal (Get-SelfXDefenderHealth).Status OK 'Defender healthy'
    $defenderDetail = (Get-SelfXDefenderHealth).Detail
            Assert-Equal $defenderDetail.StartsWith('Signature version 1.419.123.0; last update {utc:2026-10-28T07:15:00Z}') $true 'Defender last update written as UTC marker'
            # The GUI converts the marker into the time zone of the user.
            $userDetail = Format-SelfXUserTimeText $defenderDetail
            $expectedLocal = [datetime]::SpecifyKind([datetime]'2026-10-28 07:15', 'Utc').ToLocalTime().ToString('g')
            Assert-Equal $userDetail.StartsWith("Signature version 1.419.123.0; last update $expectedLocal") $true 'Defender last update shown in user time zone'
            Assert-Equal (ConvertTo-SelfXUserTime ([datetime]::SpecifyKind([datetime]'2026-11-04 10:15', 'Unspecified'))).ToString('yyyy-MM-dd HH:mm') ([datetime]::SpecifyKind([datetime]'2026-11-04 10:15', 'Utc').ToLocalTime().ToString('yyyy-MM-dd HH:mm')) 'Unspecified time treated as UTC'
            Assert-Equal (Format-SelfXUserTimeText 'no time here') 'no time here' 'Text without marker unchanged'
    Assert-Equal $defenderDetail.Contains('Product=4.18.25090.1') $true 'Defender product version shown'
    $script:defender.RealTimeProtectionEnabled = $false
    Assert-Equal (Get-SelfXDefenderHealth).Status Error 'Defender realtime disabled'
    $script:defender.RealTimeProtectionEnabled = $true
    $script:defender.AntivirusSignatureAge = 8
    Assert-Equal (Get-SelfXDefenderHealth).Status Error 'Defender stale signatures'
    $script:defender.AntivirusSignatureAge = 1
    $script:defenderMissing = $true
    Assert-Equal (Get-SelfXDefenderHealth).Status Unknown 'Defender access denied'
    $script:defenderMissing = $false

    $script:volumes = @([pscustomobject]@{ VolumeType='OperatingSystem'; MountPoint='C:'; ProtectionStatus='On'; VolumeStatus='FullyEncrypted' })
    Assert-Equal (Get-SelfXBitLockerHealth).Status OK 'BitLocker protected'
    $script:volumes[0].ProtectionStatus = 'Off'
    Assert-Equal (Get-SelfXBitLockerHealth).Status Error 'BitLocker suspended'
    $script:volumes[0].ProtectionStatus = 'On'
    $script:volumes[0].VolumeStatus = 'EncryptionInProgress'
    Assert-Equal (Get-SelfXBitLockerHealth).Status Error 'BitLocker not fully encrypted'
    $script:volumes = @()
    Assert-Equal (Get-SelfXBitLockerHealth).Status Unknown 'BitLocker unavailable'

    $script:rebootMarkers = @()
    Assert-Equal (Get-SelfXPendingRebootHealth).Status OK 'No pending reboot'
    $script:rebootMarkers = @('Windows Update')
    $reboot = Get-SelfXPendingRebootHealth
    Assert-Equal "$($reboot.Id)/$($reboot.Status)" 'PendingReboot/Error' 'Pending reboot is Error'
    Assert-Equal $reboot.Detail.Contains('Windows Update') $true 'Pending reboot source in detail'
    $script:rebootFails = $true
    Assert-Equal (Get-SelfXPendingRebootHealth).Status Unknown 'Unreadable reboot markers are Unknown'
    $script:rebootFails = $false
    $script:rebootMarkers = @()
    & {
        # Registry reader with mocked registry access only.
        function Test-Path { param($LiteralPath) $script:regKeys -contains (Split-Path $LiteralPath -Leaf) }
        function Get-ItemProperty { param($LiteralPath, $Name, $ErrorAction)
            if ($LiteralPath -like '*ActiveComputerName') { [pscustomobject]@{ ComputerName = 'PC1' } }
            else { [pscustomobject]@{ ComputerName = $script:newName } }
        }
        function Get-SelfXPendingRebootMarkers { & $rebootReader }
        foreach ($command in @('Test-Path','Get-ItemProperty')) {
            Assert-Equal (Get-Command $command).CommandType Function "Reboot registry mock: $command"
        }
        $script:regKeys = @(); $script:newName = 'PC1'
        Assert-Equal @(Get-SelfXPendingRebootMarkers).Count 0 'No reboot markers'
        $script:regKeys = @('RebootPending','RebootRequired')
        Assert-Equal (@(Get-SelfXPendingRebootMarkers) -join ',') 'Component Based Servicing,Windows Update' 'CBS and WU markers'
        $script:regKeys = @(); $script:newName = 'PC2'
        Assert-Equal (@(Get-SelfXPendingRebootMarkers) -join ',') 'Computer rename' 'Rename marker'
        $script:newName = ''
        Assert-Equal (Get-SelfXPendingRebootHealth).Status Unknown 'Missing computer name is Unknown'
    }

    $script:updateSearch = [pscustomobject]@{ Titles = @(); LastSearch = [datetime]::Now.AddDays(-1) }
    Assert-Equal (Get-SelfXUpdateHealth).Status OK 'No updates with recent scan'
    $script:updateSearch.Titles = @('2026-10 Cumulative Update', 'Definition Update')
    $update = Get-SelfXUpdateHealth
    Assert-Equal "$($update.Id)/$($update.Status)" 'Updates/Pending' 'Updates to install are Pending (warning)'
    Assert-Equal $update.Detail.StartsWith('2 update(s) to install') $true 'Update count in detail'
    $script:updateSearch.LastSearch = $null
    Assert-Equal (Get-SelfXUpdateHealth).Status Pending 'Pending updates without scan date stay Pending'
    $script:updateSearch.Titles = @()
    Assert-Equal (Get-SelfXUpdateHealth).Status Unknown 'Empty cache without scan date is Unknown'
    $script:updateSearch.LastSearch = [datetime]::Now.AddDays(-20)
    Assert-Equal (Get-SelfXUpdateHealth).Status Unknown 'Empty stale cache is Unknown'
    Assert-Equal (Get-SelfXUpdateHealth -MaxSearchAgeDays 30).Status OK 'Configured scan age accepted'
    $script:updateFails = $true
    Assert-Equal (Get-SelfXUpdateHealth).Status Unknown 'Update search failure is Unknown'
    $script:updateFails = $false
    $script:updateSearch = [pscustomobject]@{ Titles = @(); LastSearch = [datetime]::Now.AddDays(-1) }

    [xml]$apps = '<Applications><Exclude Name="Ignored*"/><Application Id="id-2" Name="Ignored broken app"/></Applications>'
    $script:reports = @([pscustomobject]@{ Id='id-1'; Name='Good app'; State=1000 }, [pscustomobject]@{ Id='id-2'; Name=''; State=5000 })
    Assert-Equal (Get-SelfXApplicationHealth $apps.DocumentElement).Status OK 'Exclude by mapped name'
    $apps.DocumentElement.RemoveChild($apps.Applications.Exclude) | Out-Null
    Assert-Equal (Get-SelfXApplicationHealth $apps.DocumentElement).Status Error 'Failed app included'
    $script:reports[1].State = 2000
    Assert-Equal (Get-SelfXApplicationHealth $apps.DocumentElement).Status Unknown 'Pending app is not OK'
    $script:reports = @()
    Assert-Equal (Get-SelfXApplicationHealth $apps.DocumentElement).Status Unknown 'No cache is not OK'
    & {
        function Test-Path { param($LiteralPath) $true }
        function Get-ChildItem { param($LiteralPath, [switch]$Recurse, $ErrorAction)
            [pscustomobject]@{
                PSPath='MockRegistry'
                Name='HKLM\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps\user\11111111-1111-1111-1111-111111111111\Reporting'
            }
        }
        function Get-ItemProperty { param($LiteralPath, $ErrorAction)
            [pscustomobject]@{ EnforcementStateMessage=$script:cacheMessage; DisplayName='Test application' }
        }
        function Get-SelfXAppReports { & $appReader }
        foreach ($command in @('Test-Path','Get-ChildItem','Get-ItemProperty')) {
            Assert-Equal (Get-Command $command).CommandType Function "Registry mock: $command"
        }
        $script:cacheMessage = '{"EnforcementState":1000}'
        $read = @(Get-SelfXAppReports)
        Assert-Equal $read[0].State 1000 'IME cache parser state'
        Assert-Equal $read[0].Id '11111111-1111-1111-1111-111111111111' 'IME cache parser ID'
        Assert-Equal $read[0].Name 'Test application' 'IME cache parser name'
        $script:cacheMessage = 'invalid JSON'
        Assert-Equal (Get-SelfXApplicationHealth $apps.DocumentElement).Status Unknown 'Malformed IME cache is explicit unknown'
    }

    # The shipped configuration uses the packaged local compliance criteria check.
    [xml]$shipped = [IO.File]::ReadAllText("$sources\Health_Config.xml")
    Assert-Equal $shipped.HealthConfig.Compliance.Script 'Check-Compliance.ps1' 'Shipped compliance check configured'
    Assert-Equal ([IO.File]::Exists("$sources\HealthChecks\Check-Compliance.ps1")) $true 'Shipped compliance check packaged'
    # Without a compliance check, no cloud compliance is fabricated.
    [void]$shipped.HealthConfig.RemoveChild($shipped.HealthConfig.SelectSingleNode('Compliance'))
    $shipped.Save("$temp\Health_Config.xml")
    $all = @(Get-SelfXHealth -Root $temp)
    Assert-Equal (@($all | Where-Object Id -eq Compliance)[0].Status) Unknown 'No fabricated cloud compliance'
    Assert-Equal (@($all | Where-Object Id -eq IME).Count) 1 'Built-in IME wired'
    Assert-Equal (@($all | Where-Object Id -eq Applications).Count) 1 'Application aggregation wired'
    Assert-Equal (@($all | Where-Object Id -eq Collection).Count) 0 'Default configuration accepted'
    Assert-Equal (@($all | Where-Object Id -eq PendingReboot).Count) 1 'Built-in pending reboot wired'
    Assert-Equal (@($all | Where-Object Id -eq Updates).Count) 1 'Built-in updates wired'
    $only = @(Get-SelfXHealth -Root $temp -OnlyId Updates)
    Assert-Equal "$($only.Count)/$($only[0].Id)" '1/Updates' 'Single updates recheck'
    $only = @(Get-SelfXHealth -Root $temp -OnlyId PendingReboot)
    Assert-Equal "$($only.Count)/$($only[0].Id)" '1/PendingReboot' 'Single pending reboot recheck'
    $only = @(Get-SelfXHealth -Root $temp -OnlyId IME)
    Assert-Equal $only.Count 1 'Single check returns only the requested check'
    Assert-Equal $only[0].Id IME 'Single check Id'
    $script:disks = @([pscustomobject]@{ DeviceID='C:'; Size=500GB; FreeSpace=100GB }, [pscustomobject]@{ DeviceID='D:'; Size=500GB; FreeSpace=1GB })
    $only = @(Get-SelfXHealth -Root $temp -OnlyId Disk -OnlyName 'D:')
    Assert-Equal $only.Count 1 'Single disk recheck narrowed to the drive'
    Assert-Equal "$($only[0].Name)/$($only[0].Status)" 'D:/Error' 'Single disk recheck result'
    $script:disks = @([pscustomobject]@{ DeviceID='C:'; Size=500GB; FreeSpace=100GB })
    Assert-Equal @(Get-SelfXHealth -Root $temp -OnlyId Service -OnlyName 'NotConfigured').Count 0 'Unconfigured service is never probed'
    Assert-Equal @(Get-SelfXHealth -Root $temp -OnlyId Custom -OnlyName 'NotConfigured').Count 0 'Unconfigured custom check is never run'
    [xml]$remConfig = [IO.File]::ReadAllText("$sources\Health_Config.xml")
    $repair = $remConfig.CreateElement('Remediation')
    $repair.SetAttribute('Id','IME')
    $repair.SetAttribute('Script','Repair-IME.ps1')
    [void]$remConfig.HealthConfig.Remediations.AppendChild($repair)
    $remConfig.Save("$temp\Health_Config.xml")
    $withRepair = @(Get-SelfXHealth -Root $temp)
    Assert-Equal (@($withRepair | Where-Object Id -eq IME)[0].Remediation) 'Repair-IME.ps1' 'Configured remediation returned'
    Assert-Equal (@($withRepair | Where-Object Id -eq Disk)[0].Remediation) '' 'No remediation for unconfigured row'
    Assert-Equal (@($withRepair | Where-Object Id -eq Defender)[0].Status) OK 'Default Defender is OK'
    Assert-Equal (@($withRepair | Where-Object Id -eq Defender)[0].Remediation) '' 'Default Defender signature update hidden while OK'
    Assert-Equal ((@($withRepair | Where-Object Id -eq Compliance)[0].Status) -ne 'OK') $true 'Compliance without a readable check is not OK'
    Assert-Equal (@($withRepair | Where-Object Id -eq Compliance)[0].Remediation) 'SelfX_Defender_UpdateSignature.ps1' 'Signature update offered while compliance is not OK'
    Assert-Equal (@($withRepair | Where-Object Id -eq Updates)[0].Remediation) '' 'Update install hidden while no updates are pending'
    $script:updateSearch.Titles = @('2026-10 Cumulative Update')
    Assert-Equal (@(Get-SelfXHealth -Root $temp -OnlyId Updates)[0].Remediation) 'SelfX_Updates_Install.ps1' 'Update install offered while updates are pending'
    $script:updateSearch.Titles = @()
    # The install script is only parsed, never executed (it would install updates on this machine).
    $tokens = $null; $parseErrors = $null
    $installAst = [Management.Automation.Language.Parser]::ParseFile("$sources\Scripts_to_run\SelfX_Updates_Install.ps1",[ref]$tokens,[ref]$parseErrors)
    Assert-Equal $parseErrors.Count 0 'Update install script parses'
    $installText = $installAst.Extent.Text
    Assert-Equal ($installText -match '(?i)Restart-Computer|shutdown|Stop-Computer|logoff|ExitWindowsEx') $false 'Update install script never restarts or signs out'
    Assert-Equal $installText.Contains('UpdateScanMethod') $true 'Update install script starts the Store app updates'
    foreach ($node in $remConfig.SelectNodes('/HealthConfig/Remediations/Remediation')) {
        Assert-Equal ([IO.File]::Exists((Join-Path "$sources\Scripts_to_run" $node.GetAttribute('Script'))) -or $node.GetAttribute('Script') -eq 'Repair-IME.ps1') $true "Default remediation script shipped: $($node.GetAttribute('Script'))"
    }
    # When="NotOK": the remediation disappears as soon as the status is OK.
    $script:defender.RealTimeProtectionEnabled = $false
    $notOk = $remConfig.SelectSingleNode("/HealthConfig/Remediations/Remediation[@Id='Defender']")
    $notOk.SetAttribute('When','NotOK')
    $remConfig.Save("$temp\Health_Config.xml")
    Assert-Equal (@(Get-SelfXHealth -Root $temp -OnlyId Defender)[0].Remediation) 'SelfX_Defender_UpdateSignature.ps1' 'NotOK remediation offered on Error'
    $script:defender.RealTimeProtectionEnabled = $true
    Assert-Equal (@(Get-SelfXHealth -Root $temp -OnlyId Defender)[0].Remediation) '' 'NotOK remediation hidden on OK'
    $notOk.SetAttribute('When','Sometimes')
    $remConfig.Save("$temp\Health_Config.xml")
    Assert-Equal (@(Get-SelfXHealth -Root $temp)[0].Detail.Contains('When')) $true 'Invalid When value rejected'
    $notOk.RemoveAttribute('When')
    $repair.SetAttribute('Name','Another service')
    $remConfig.Save("$temp\Health_Config.xml")
    Assert-Equal (@(Get-SelfXHealth -Root $temp | Where-Object Id -eq IME)[0].Remediation) '' 'Remediation exact name matching'
    $repair.RemoveAttribute('Name')
    $repair.SetAttribute('Script','..\outside.ps1')
    $remConfig.Save("$temp\Health_Config.xml")
    Assert-Equal (@(Get-SelfXHealth -Root $temp)[0].Status) Error 'Reject remediation traversal'
    [IO.File]::WriteAllText("$temp\Health_Config.xml", '<HealthConfig><Disk UsedPercentError="NaN" MinimumFreeGB="20"/><Applications/></HealthConfig>')
    Assert-Equal (@(Get-SelfXHealth -Root $temp)[0].Detail.Contains('UsedPercentError')) $true 'Reject NaN threshold'
    [IO.File]::WriteAllText("$temp\Health_Config.xml", '<HealthConfig><Disk UsedPercentError="90" MinimumFreeGB="-1"/><Applications/></HealthConfig>')
    Assert-Equal (@(Get-SelfXHealth -Root $temp)[0].Detail.Contains('MinimumFreeGB')) $true 'Reject negative free space'
    [IO.File]::WriteAllText("$temp\Health_Config.xml", '<HealthConfig><Disk UsedPercentError="90" MinimumFreeGB="20"/><Applications/><Updates MaxSearchAgeDays="0"/></HealthConfig>')
    Assert-Equal (@(Get-SelfXHealth -Root $temp)[0].Detail.Contains('MaxSearchAgeDays')) $true 'Reject invalid update scan age'
    [IO.File]::WriteAllText("$temp\Health_Config.xml", '<HealthConfig><Disk UsedPercentError="90" MinimumFreeGB="20"/><Applications/><Updates MaxSearchAgeDays="30"/></HealthConfig>')
    Assert-Equal (@(Get-SelfXHealth -Root $temp -OnlyId Updates)[0].Status) OK 'Valid update scan age accepted'
    $many = '<HealthConfig><Disk UsedPercentError="90" MinimumFreeGB="20"/><Applications/><CustomChecks>' +
        ('<Check Name="Mock" Script="Check-Mock.ps1"/>' * 6) + '</CustomChecks></HealthConfig>'
    [IO.File]::WriteAllText("$temp\Health_Config.xml", $many)
    Assert-Equal (@(Get-SelfXHealth -Root $temp)[0].Detail.Contains('At most 5')) $true 'Bound total extension count'

    # No real files or process calls are allowed along the extension-check path.
    function Test-Path { param($LiteralPath, $PathType) -not $script:checkMissing }
    function Get-Item { param($LiteralPath, [switch]$Force)
        $attributes = if ($script:reparse) { [IO.FileAttributes]::ReparsePoint } else { [IO.FileAttributes]::Normal }
        [pscustomobject]@{ Attributes=$attributes }
    }
    Assert-Equal (Get-Command Test-Path).CommandType Function 'Path mock'
    Assert-Equal (Get-Command Get-Item).CommandType Function 'Item mock'
    [xml]$custom = '<Check Name="Mock check" Script="Check-Mock.ps1" TimeoutSeconds="1"/>'
    $script:exitCode = 0
    Assert-Equal (Get-SelfXCustomHealth $custom.DocumentElement $temp).Status OK 'Custom exit 0'
    $script:exitCode = 1
    Assert-Equal (Get-SelfXCustomHealth $custom.DocumentElement $temp).Status Error 'Custom exit 1'
    $script:exitCode = 2
    Assert-Equal (Get-SelfXCustomHealth $custom.DocumentElement $temp).Status Error 'Unexpected exit is error'
    $script:exitCode = 1
    Assert-Equal (Get-SelfXCustomHealth $custom.DocumentElement $temp Compliance -FailStatus Pending).Status Pending 'Non-compliant is Pending (warning)'
    $script:exitCode = 0
    Assert-Equal (Get-SelfXCustomHealth $custom.DocumentElement $temp Compliance -FailStatus Pending).Status OK 'Compliant is OK'
    Assert-Equal (Get-SelfXCustomHealth $custom.DocumentElement $temp).Detail 'Exit code: 0' 'Without output the exit code is the detail'
    $script:checkOutput = "Progress`r`n`r`nNot met: BitLocker (C: protection Off)" + [char]7 + "  `r`n"
    $script:exitCode = 1
    $result = Get-SelfXCustomHealth $custom.DocumentElement $temp Compliance -FailStatus Pending
    Assert-Equal $result.Status Pending 'Output does not change the status'
    Assert-Equal $result.Detail 'Not met: BitLocker (C: protection Off)' 'Last output line is the detail'
    $script:checkOutput = 'x' * 900
    Assert-Equal (Get-SelfXCustomHealth $custom.DocumentElement $temp).Detail.Length 400 'Output detail is bounded'
    $script:checkOutput = ''
    $script:exitCode = 2
    $script:timeout = $true
    Assert-Equal (Get-SelfXCustomHealth $custom.DocumentElement $temp).Status Error 'Custom timeout'
    $script:timeout = $false
    [xml]$appProbe = '<Applications><Application Name="Business client" Script="Check-Mock.ps1"/></Applications>'
    $script:exitCode = 0
    Assert-Equal (Get-SelfXApplicationHealth $appProbe.DocumentElement $temp).Status OK 'Configured app probe passes'
    $script:exitCode = 1
    Assert-Equal (Get-SelfXApplicationHealth $appProbe.DocumentElement $temp).Status Error 'Configured app probe fails'
    $exclude = $appProbe.CreateElement('Exclude')
    $exclude.SetAttribute('Name', 'Business*')
    [void]$appProbe.DocumentElement.AppendChild($exclude)
    Assert-Equal (Get-SelfXApplicationHealth $appProbe.DocumentElement $temp).Status Unknown 'Excluded probe does not run or imply success'
    $custom.Check.Script = '..\outside.ps1'
    Assert-Equal (Get-SelfXCustomHealth $custom.DocumentElement $temp).Status Error 'Reject traversal'
    $custom.Check.Script = 'Check-Mock.ps1'
    $custom.Check.TimeoutSeconds = '31'
    Assert-Equal (Get-SelfXCustomHealth $custom.DocumentElement $temp).Status Error 'Reject excessive timeout'
    $custom.Check.TimeoutSeconds = '1'
    $script:checkMissing = $true
    Assert-Equal (Get-SelfXCustomHealth $custom.DocumentElement $temp).Detail.StartsWith('Health script not found') $true 'Missing script reported'
    $script:checkMissing = $false
    $script:reparse = $true
    Assert-Equal (Get-SelfXCustomHealth $custom.DocumentElement $temp).Detail.Contains('reparse') $true 'Reject script links'
    $script:reparse = $false

    function Invoke-SelfXServiceRequest { param($Request) $script:lastRequest = $Request; $script:response }
    $script:response = 'HEALTH ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('[{"Id":"IME","Name":"","Status":"OK","Detail":"Running"}]'))
    Assert-Equal (@(Get-SelfXServiceHealthReport)[0].Status) OK 'Protocol roundtrip'
    Assert-Equal $script:lastRequest HEALTH 'Full HEALTH request'
    [void](Get-SelfXServiceHealthReport -Id IME)
    Assert-Equal $script:lastRequest 'HEALTH IME' 'Single-check request without name'
    [void](Get-SelfXServiceHealthReport -Id Disk -Name 'C:')
    Assert-Equal $script:lastRequest 'HEALTH Disk Qzo=' 'Single-check name is base64 encoded'
    [void](Get-SelfXServiceHealthReport -Id PendingReboot)
    Assert-Equal $script:lastRequest 'HEALTH PendingReboot' 'Pending reboot recheck request'
    [void](Get-SelfXServiceHealthReport -Id Updates)
    Assert-Equal $script:lastRequest 'HEALTH Updates' 'Updates recheck request'
    $script:response = 'HEALTH ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('[{"Id":"Updates","Name":"","Status":"Error","Detail":"1 update(s)"}]'))
    Assert-Equal (@(Get-SelfXServiceHealthReport)[0].Id) Updates 'Updates result accepted by the client'
    $script:response = 'HEALTH ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('[{"Id":"Updates","Name":"","Status":"Pending","Detail":"1 update(s)"}]'))
    Assert-Equal (@(Get-SelfXServiceHealthReport)[0].Status) Pending 'Pending status accepted by the client'
    Assert-Throws { Get-SelfXServiceHealthReport -Id Collection } 'Collection is not re-checkable'
    Assert-Throws { Get-SelfXServiceHealthReport -Id 'IME; calc' } 'Unknown check Id rejected'
    Assert-Throws { Get-SelfXServiceHealthReport -Id Service -Name ('ä' * 150) } 'Overlong check name rejected'
    $script:response = 'BUSY'
    Assert-Throws { Get-SelfXServiceHealthReport } 'Busy is explicit'
    $script:response = 'HEALTH ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('[{"Id":"IME","Status":"Green","Detail":""}]'))
    Assert-Throws { Get-SelfXServiceHealthReport } 'Invalid status rejected'
    $script:response = 'HEALTH ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('not json'))
    Assert-Throws { Get-SelfXServiceHealthReport } 'Invalid JSON rejected'

    $language = Initialize-SelfXLanguage -LanguageFolder "$sources\Languages" -Language de-CH
    $script:SelfXInfoText = Get-SelfXSystemInfoTexts
    $info = @(ConvertTo-SelfXHealthInfo @([pscustomobject]@{Id='Disk'; Name='C:'; Status='Error'; Detail='90%'; Remediation='Repair-Disk.ps1'}))
    Assert-Equal $info[0].Remediation 'Repair-Disk.ps1' 'Remediation preserved for UI binding'
    Assert-Equal "$($info[0].HealthId)/$($info[0].HealthName)" 'Disk/C:' 'Check identity preserved for recheck'
    & {
        function Get-SelfXServiceHealthReport { param($Id, $Name)
            if ($script:recheckFails) { throw 'Mock busy' }
            [pscustomobject]@{ Id=$Id; Name=$Name; Status='OK'; Detail='Fixed'; Remediation='' }
        }
        $recheck = @(Get-SelfXHealthCheckInfo -Id Disk -Name 'C:' -Text $script:SelfXInfoText)
        Assert-Equal "$($recheck.Count)/$($recheck[0].Status)/$($recheck[0].HealthName)" '1/OK/C:' 'Single recheck row'
        $script:recheckFails = $true
        $recheck = @(Get-SelfXHealthCheckInfo -Id Disk -Name 'C:' -Text $script:SelfXInfoText)
        Assert-Equal "$($recheck[0].Status)/$($recheck[0].HealthId)/$($recheck[0].HealthName)" 'Unknown/Disk/C:' 'Failed recheck keeps identity'
        $script:recheckFails = $false
    }
    Assert-Equal $info[0].Status Error 'Status preserved for row styling'
    Assert-Equal $info[0].Category $script:SelfXInfoText.Category_Health 'Localized health category'
    Assert-Equal $info[0].Value.StartsWith($script:SelfXInfoText.Health_Error) $true 'Localized error text'
    Assert-Equal (ConvertTo-SelfXSystemInfoText $info).Contains('90%') $true 'Text export includes health'
    Export-SelfXSystemInfo -Items $info -Path "$temp\report.json"
    $exported = ConvertFrom-Json ([IO.File]::ReadAllText("$temp\report.json"))
    Assert-Equal $exported.Status Error 'JSON export preserves state'
    & {
        function Invoke-SelfXSafe { param([scriptblock]$ScriptBlock) $null }
        function Get-SelfXDsregStatus { @{} }
        function Get-SelfXMdmEnrollmentUpn { $null }
        function Get-SelfXIntuneLastSync { 'Mock sync' }
        function Get-SelfXWifiSsid { $null }
        function Test-SelfXVpnConnection { $false }
        function Test-SelfXTcpConnection { param($HostName, $Port) $false }
        function Get-SelfXServiceHealthReport {
            if ($script:healthUnavailable) { throw 'Mock service unavailable' }
            [pscustomobject]@{ Id='IME'; Name=''; Status='OK'; Detail='Running' }
        }
        $labels = Get-SelfXSystemInfoTexts
        $baseline = @(Get-SelfXSystemInfo -Text $labels)
        $combined = @(Get-SelfXSystemInfo -Text $labels -IncludeHealth)
        Assert-Equal $combined.Count ($baseline.Count + 1) 'Health appended without losing existing rows'
        foreach ($key in @('Category_Device','Category_Windows','Category_User','Category_Network','Category_Report')) {
            Assert-Equal (@($combined | Where-Object Category -eq $labels[$key]).Count -gt 0) $true "Existing section retained: $key"
        }
        for ($i = 0; $i -lt $baseline.Count; $i++) {
            Assert-Equal $combined[$i].Category $baseline[$i].Category "Existing category order $i"
            Assert-Equal $combined[$i].Property $baseline[$i].Property "Existing property order $i"
        }
        Assert-Equal $combined[-1].Category $labels.Category_Health 'Health section is last'
        $script:healthUnavailable = $true
        $unavailable = @(Get-SelfXSystemInfo -Text $labels -IncludeHealth)
        Assert-Equal $unavailable.Count ($baseline.Count + 1) 'Service failure preserves existing information'
        Assert-Equal $unavailable[0].Category $labels.Category_Device 'Device still first on service failure'
        Assert-Equal $unavailable[-1].Status Unknown 'Unavailable health appended as Unknown'
    }
    & {
        # Execute only the completion callback with fake runspaces/timers, never the action launcher.
        $tokens=$null; $parseErrors=$null
        $ast = [Management.Automation.Language.Parser]::ParseFile("$sources\Self_X.ps1",[ref]$tokens,[ref]$parseErrors)
        $tick = $ast.Find({
            param($node)
            $node -is [Management.Automation.Language.InvokeMemberExpressionAst] -and
            $node.Expression.Extent.Text -eq '$SvcAction_Timer' -and $node.Member.Value -eq 'Add_Tick'
        }, $true)
        if (-not $tick) { throw 'Repair completion callback not found.' }
        $callback = $tick.Arguments[0].ScriptBlock.GetScriptBlock()
        $SvcAction_Timer = New-Object PSObject
        $SvcAction_Timer | Add-Member ScriptMethod Stop {}
        $Form = [pscustomobject]@{Cursor=$null}
        $msgbar = New-Object PSObject
        foreach ($method in @('Clear','SetSuccessAlert','SetDangerAlert','SetWarningAlert')) {
            $msgbar | Add-Member ScriptMethod $method {}
        }
        function Update-SelfXServiceStatus {}
        function Update-SelfXFixAllButton {}
        function Update-SelfXStatusView {}
        function Set-SelfXActionRunning { param($Row, $Running) if ($Row) { $Row.Running = $Running } }
        $Global:FixAll_Active = $false
        function Start-SysInfoHealthCheck { param($Id, $Name) $script:refreshCalls++; $script:refreshTarget = "$Id/$Name" }
        $Global:SvcAction_Handle = [pscustomobject]@{IsCompleted=$true}
        $Global:SvcAction_PS = New-Object PSObject
        $Global:SvcAction_PS | Add-Member ScriptMethod EndInvoke { $script:repairResult }
        $Global:SvcAction_PS | Add-Member ScriptMethod Dispose {}
        foreach ($state in @('Success','Failed','Timeout','Unavailable','Busy')) {
            $script:repairResult = [pscustomobject]@{Status=$state;ExitCode=1;Message='Mock repair'}
            $Global:SvcAction_RefreshHealth = $true
            $Global:SvcAction_HealthId = 'Disk'
            $Global:SvcAction_HealthName = 'C:'
            $Global:SvcAction_Running = $true
            $script:refreshCalls = 0
            & $callback
            Assert-Equal $script:refreshCalls 1 "Recheck after repair: $state"
            Assert-Equal $script:refreshTarget 'Disk/C:' "Recheck targets the repaired row: $state"
            Assert-Equal $Global:SvcAction_Running $false "Repair lock released: $state"
            Assert-Equal $Global:SvcAction_RefreshHealth $false "Refresh flag cleared: $state"
        }
        $Global:SvcAction_RefreshHealth = $false
        $script:refreshCalls = 0
        & $callback
        Assert-Equal $script:refreshCalls 0 'Ordinary troubleshooting action does not force health refresh'
        # The start button of the finished action is no longer shown as running.
        $runningRow = [pscustomobject]@{ Running = $true }
        $Global:SvcAction_Row = $runningRow
        $Global:SvcAction_Running = $true
        & $callback
        Assert-Equal "$($runningRow.Running)/$($null -eq $Global:SvcAction_Row)" 'False/True' 'Finished action: running state cleared'

        # "Fix all problems": repairs run one after another, results are counted, then a full recheck.
        foreach ($fn in 'Start-SelfXNextFixAll', 'Update-SelfXFixAllButton') {
            $def = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $fn }, $true)
            if (-not $def) { throw "$fn not found." }
            . ([scriptblock]::Create($def.Extent.Text))
        }
        $Btn_FixAll = [pscustomobject]@{ Visibility = 'Collapsed'; IsEnabled = $true }
        $script:fixAlerts = @()
        foreach ($method in @('SetSuccessAlert','SetWarningAlert')) {
            $msgbar | Add-Member -Force ScriptMethod $method ([scriptblock]::Create("param(`$t) `$script:fixAlerts += '$method'"))
        }
        function Get-SelfXString { param($Key) "$Key|$($args -join '|')" }
        function Start-SelfXSystemAction { param($Script, $ActionName) $script:started += ,"$Script/$ActionName"; $Global:SvcAction_Running = $true }
        $Global:Health_Busy = $false; $Global:SvcAction_Running = $false
        $Global:Health_FixAll_Cards = @([pscustomobject]@{Property='Disk C:';Remediation='A.ps1'}, [pscustomobject]@{Property='Defender';Remediation='B.ps1'})
        Update-SelfXFixAllButton
        Assert-Equal "$($Btn_FixAll.Visibility)/$($Btn_FixAll.IsEnabled)" 'Visible/True' 'Fix all shown when problems can be fixed'
        $Global:FixAll_Queue = New-Object System.Collections.Queue
        foreach ($card in $Global:Health_FixAll_Cards) { $Global:FixAll_Queue.Enqueue($card) }
        $Global:FixAll_Total = 2; $Global:FixAll_Success = 0
        $Global:FixAll_Failed = New-Object System.Collections.Generic.List[string]
        $Global:FixAll_Active = $true
        $script:started = @(); $script:refreshCalls = 0
        Start-SelfXNextFixAll
        Assert-Equal ($script:started -join ',') 'A.ps1/Disk C: (1/2)' 'First repair started'
        $script:repairResult = [pscustomobject]@{Status='Success';ExitCode=0;Message=''}
        & $callback
        Assert-Equal ($script:started -join ',') 'A.ps1/Disk C: (1/2),B.ps1/Defender (2/2)' 'Second repair started after the first'
        Assert-Equal $script:refreshCalls 0 'No recheck between the repairs'
        Assert-Equal $Btn_FixAll.IsEnabled $false 'Fix all disabled while running'
        $script:repairResult = [pscustomobject]@{Status='Failed';ExitCode=1;Message=''}
        & $callback
        Assert-Equal "$Global:FixAll_Active/$Global:FixAll_Success/$($Global:FixAll_Failed -join ',')" 'False/1/Defender' 'Fix all result counted'
        Assert-Equal $script:refreshTarget '/' 'Full recheck after fix all'
        Assert-Equal $script:fixAlerts[-1] 'SetWarningAlert' 'Failed repairs reported as warning at the end'
        # Service unavailable: the remaining repairs are not started.
        foreach ($card in $Global:Health_FixAll_Cards) { $Global:FixAll_Queue.Enqueue($card) }
        $Global:FixAll_Success = 0; $Global:FixAll_Failed.Clear(); $Global:FixAll_Active = $true; $script:started = @()
        Start-SelfXNextFixAll
        $script:repairResult = [pscustomobject]@{Status='Unavailable';ExitCode=1;Message=''}
        & $callback
        Assert-Equal "$(@($script:started).Count)/$($Global:FixAll_Failed -join ',')/$Global:FixAll_Active" '1/Disk C:,Defender/False' 'Fix all stops when the service is unavailable'
        $Global:Health_FixAll_Cards = @()
        Update-SelfXFixAllButton
        Assert-Equal $Btn_FixAll.Visibility 'Collapsed' 'Fix all hidden without fixable problems'
        $Global:SvcAction_Running = $false
        # Row merge: only the rechecked row is replaced, order and all other rows are kept.
        $merge = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Merge-SysInfoHealthItems' }, $true)
        if (-not $merge) { throw 'Merge-SysInfoHealthItems not found.' }
        . ([scriptblock]::Create($merge.Extent.Text))
        $rows = @(
            [pscustomobject]@{ Property='Device'; Status=''; HealthId=''; HealthName='' }
            [pscustomobject]@{ Property='Disk C'; Status='Error'; HealthId='Disk'; HealthName='C:' }
            [pscustomobject]@{ Property='Disk D'; Status='OK'; HealthId='Disk'; HealthName='D:' }
        )
        $new = [pscustomobject]@{ Property='Disk C'; Status='OK'; HealthId='Disk'; HealthName='C:' }
        $merged = @(Merge-SysInfoHealthItems -Items $rows -Id Disk -Name 'C:' -Results @($new))
        Assert-Equal ($merged.Property -join ',') 'Device,Disk C,Disk D' 'Merge keeps order and other rows'
        Assert-Equal $merged[1].Status OK 'Merge updates the rechecked row'
        Assert-Equal $merged[2].Status OK 'Merge leaves other checks untouched'
        $kept = @(Merge-SysInfoHealthItems -Items $rows -Id Disk -Name 'C:' -Results @([pscustomobject]@{ Property='Error' }))
        Assert-Equal $kept[1].Status Error 'Invalid recheck result does not remove the row'
    }
    & {
        # Compile and call only the read-only whitelist lookup, never ProcessRequest/RunScript.
        $env:SystemRoot = $originalRoot
        Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Service\SelfXService.cs'))) `
            -ReferencedAssemblies @('System.ServiceProcess.dll','System.Xml.dll','System.Core.dll')
        $type = [SelfX.SelfXService]
        $instance = New-Object SelfX.SelfXService('SelfX.Test.NotStarted', $temp)
        try {
            $flags = [Reflection.BindingFlags]'Instance,NonPublic'
            $type.GetField('installRoot',$flags).SetValue($instance,$temp)
            $type.GetField('catalogPath',$flags).SetValue($instance,"$temp\Issues_List.xml")
            [IO.File]::WriteAllText("$temp\Issues_List.xml", '<Actions><Detailed_Solution><Action><Script>Catalog.ps1</Script><Context>System</Context></Action></Detailed_Solution></Actions>')
            [IO.File]::WriteAllText("$temp\Health_Config.xml", '<HealthConfig><Remediations><Remediation Id="IME" Script="Repair-IME.ps1"/></Remediations></HealthConfig>')
            $method = $type.GetMethod('TryGetSystemAction',$flags)
            foreach ($case in @(@('Repair-IME.ps1',$true), @('Catalog.ps1',$true), @('NotAllowed.ps1',$false))) {
                $arguments = [object[]]@($case[0],0)
                $allowed = $method.Invoke($instance,$arguments)
                Assert-Equal $allowed $case[1] "Service whitelist: $($case[0])"
                if ($case[1]) { Assert-Equal $arguments[1] 900 "Service default timeout: $($case[0])" }
            }
            foreach ($case in @(@('3600',3600), @('99999',7200), @('0',900), @('abc',900))) {
                [IO.File]::WriteAllText("$temp\Health_Config.xml", "<HealthConfig><Remediations><Remediation Id=`"Updates`" Script=`"Upd.ps1`" TimeoutSeconds=`"$($case[0])`"/></Remediations></HealthConfig>")
                $arguments = [object[]]@('Upd.ps1',0)
                Assert-Equal $method.Invoke($instance,$arguments) $true "Service remediation with TimeoutSeconds=$($case[0]) allowed"
                Assert-Equal $arguments[1] $case[1] "Service remediation timeout TimeoutSeconds=$($case[0])"
            }
            $pattern = $type.GetField('HealthRequestPattern',[Reflection.BindingFlags]'Static,NonPublic').GetValue($null)
            foreach ($case in @(@('HEALTH',$true), @('HEALTH IME',$true), @('HEALTH Disk Qzo=',$true), @('HEALTH Custom TXkgY2hlY2s=',$true), @('HEALTH PendingReboot',$true), @('HEALTH Updates',$true),
                @('HEALTH Collection',$false), @('HEALTH IME "x" -Command y',$false), @('HEALTH Disk C:\x',$false), @('HEALTH  IME',$false),
                @('HEALTH Disk Qzo= extra',$false), @('HEALTHX',$false))) {
                Assert-Equal $pattern.IsMatch($case[0]) $case[1] "Service HEALTH request validation: $($case[0])"
            }
        } finally { $instance.Dispose() }
    }
    & {
        # Static checks for the Fix/Ok/Error button labels; nothing is executed.
        foreach ($file in Get-ChildItem (Join-Path $PSScriptRoot 'Sources\Languages') -Filter *.xml) {
            [xml]$lang = [IO.File]::ReadAllText($file.FullName)
            foreach ($key in 'Health_Fix','Health_Check_Button','Health_Error_Button','Health_Pending_Button','Health_Pending','Health_PendingReboot','Health_Updates') {
                $node = $lang.DocumentElement.SelectSingleNode("//*[local-name()='$key']")
                Assert-Equal ([bool]($node -and $node.InnerText.Trim())) $true "$($file.Name) has $key"
            }
        }
        $ui = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Sources\Self_X.ps1'))
        Assert-Equal $ui.Contains('Str_Health_Error') $true 'UI defines the Error status text'
        Assert-Equal $ui.Contains('Str_Health_Pending') $true 'UI defines the Pending status text'
        Assert-Equal $ui.Contains('<DataTrigger Binding="{Binding HasFix}" Value="True">') $true 'UI shows Fix only with a remediation'
        Assert-Equal $ui.Contains('Tag="Check"') $true 'UI offers a recheck button on every status card'
        Assert-Equal $ui.Contains('Binding="{Binding Status}" Value="Pending"') $true 'UI colors Pending rows as warning'
        $info = @(ConvertTo-SelfXHealthInfo @([pscustomobject]@{Id='Updates'; Name=''; Status='Pending'; Detail='1 update(s)'; Remediation=''}))
        Assert-Equal "$($info[0].Status)/$($info[0].Value.StartsWith($script:SelfXInfoText.Health_Pending))" 'Pending/True' 'Pending row label localized'
        Assert-Equal $info[0].Detail '1 update(s)' 'Status row keeps the detail for the cards'
    }
    & {
        # Status cache of the background checks (HealthStatus.ps1 -CacheFile); only files in the temp folder are written.
        function Test-Path { param($LiteralPath, $PathType = 'Any') Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath -PathType $PathType }
        $cache = Join-Path $temp 'Health.json'
        function Read-TestCache([string]$Path) { $parsed = ConvertFrom-Json ([IO.File]::ReadAllText($Path)); return @($parsed) }
        $full = @(
            [pscustomobject]@{ Id='IME'; Name=''; Status='OK'; Detail='a'; Remediation='' }
            [pscustomobject]@{ Id='Disk'; Name='C:'; Status='Error'; Detail='b'; Remediation='' }
            [pscustomobject]@{ Id='Disk'; Name='D:'; Status='OK'; Detail='c'; Remediation='' }
            [pscustomobject]@{ Id='Updates'; Name=''; Status='Pending'; Detail='d'; Remediation='' }
        )
        Update-SelfXHealthCache -Path $cache -Results @([pscustomobject]@{ Id='Disk'; Name='C:'; Status='OK'; Detail='x'; Remediation='' }) -OnlyId Disk -OnlyName 'C:'
        Assert-Equal (Test-Path $cache) $false 'A single check without a full cache writes nothing'
        Update-SelfXHealthCache -Path $cache -Results $full
        Assert-Equal (Test-Path "$cache.tmp") $false 'Cache is written through a temporary file'
        Assert-Equal ((Read-TestCache $cache).Count) 4 'Full collection replaces the cache'
        Update-SelfXHealthCache -Path $cache -Results @([pscustomobject]@{ Id='Disk'; Name='C:'; Status='OK'; Detail='fixed'; Remediation='' }) -OnlyId Disk -OnlyName 'C:'
        $after = (Read-TestCache $cache)
        Assert-Equal (($after | ForEach-Object { "$($_.Id)$($_.Name)" }) -join ',') 'IME,DiskC:,DiskD:,Updates' 'Single check keeps the order'
        Assert-Equal "$($after[1].Status)/$($after[1].Detail)" 'OK/fixed' 'Single check replaces its row'
        Assert-Equal $after[2].Detail 'c' 'Other drive untouched'
        Update-SelfXHealthCache -Path $cache -Results @([pscustomobject]@{ Id='Disk'; Name='C:'; Status='OK'; Detail='e'; Remediation='' }) -OnlyId Disk
        Assert-Equal ((Read-TestCache $cache).Count) 3 'Check without name replaces all rows of that check'
        Update-SelfXHealthCache -Path $cache -Results @([pscustomobject]@{ Id='Service'; Name='Spooler'; Status='OK'; Detail='f'; Remediation='' }) -OnlyId Service -OnlyName Spooler
        Assert-Equal ((Read-TestCache $cache)[-1].Name) 'Spooler' 'New check is appended'
        [IO.File]::Delete($cache)

        # STATUS client: validated cache answer of the service, no request reaches a real pipe.
        $json = ConvertTo-Json -InputObject @($full) -Compress
        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
        function Invoke-SelfXServiceRequest { param($Request, $PipeName, $ConnectTimeoutMs) $script:statusRequest = $Request; $script:statusResponse }
        # HEALTH with several results: the JSON array must be unrolled (Windows PowerShell 5.1).
        $script:statusResponse = "HEALTH $b64"
        $report = @(Get-SelfXServiceHealthReport)
        Assert-Equal $script:statusRequest 'HEALTH' 'Client sends HEALTH'
        Assert-Equal $report.Count 4 'HEALTH answer with several results is accepted'
        Assert-Equal $report[1].Name 'C:' 'HEALTH results keep their fields'
        $script:statusResponse = "STATUS 2026-11-04T10:15:00Z 15 Active $b64"
        $status = Get-SelfXServiceStatusCache
        Assert-Equal $script:statusRequest 'STATUS' 'Client sends STATUS'
        Assert-Equal $status.Results.Count 4 'Cached results returned'
        Assert-Equal "$($status.IntervalMinutes)/$($status.State)" '15/Active' 'Interval and state returned'
        Assert-Equal $status.CollectedAt.ToUniversalTime().ToString('yyyy-MM-dd HH:mm') '2026-11-04 10:15' 'Cache time returned as UTC'
        Assert-Equal $status.CollectedAt.Kind ([DateTimeKind]::Utc) 'Cache time kind is UTC (converted in the GUI)'
        $script:statusResponse = 'STATUS NONE 15 Battery -'
        $status = Get-SelfXServiceStatusCache
        Assert-Equal "$($status.CollectedAt)/$($status.Results.Count)/$($status.State)" '/0/Battery' 'No cache yet'
        foreach ($bad in @('STATUS', 'BUSY', 'STATUS 2026-11-04T10:15:00Z 15 Unknown x', "STATUS NONE 15 Active $b64 extra", 'ERROR Status cache not readable')) {
            $script:statusResponse = $bad
            Assert-Throws { Get-SelfXServiceStatusCache } "Invalid STATUS answer rejected: $bad"
        }
        $script:statusResponse = 'STATUS 2026-11-04T10:15:00Z 15 Active ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('[{"Id":"Evil","Status":"OK","Detail":"x"}]'))
        Assert-Equal (Get-SelfXStatusData -Mode Cached -Text @{}).Ok $false 'Unknown check id in the cache is rejected'
        $script:statusResponse = "STATUS 2026-11-04T10:15:00Z 30 Active $b64"
        $data = Get-SelfXStatusData -Mode Cached -Text @{}
        Assert-Equal "$($data.Ok)/$(@($data.Items).Count)/$($data.IntervalMinutes)/$($data.Items[1].HealthName)" 'True/4/30/C:' 'Status data for GUI and tray from the cache'
    }
    & {
        # Background settings and STATUS answer of the service: reflection only, the service is never started.
        $env:SystemRoot = $originalRoot
        $type = [SelfX.SelfXService]
        $instance = New-Object SelfX.SelfXService('SelfX.Test.NotStarted', (Join-Path $temp 'Logs'))
        try {
            $flags = [Reflection.BindingFlags]'Instance,NonPublic'
            $type.GetField('installRoot', $flags).SetValue($instance, $temp)
            Assert-Equal $type.GetField('cacheFile', $flags).GetValue($instance) (Join-Path $temp 'Cache\Health.json') 'Cache file is next to the log folder'
            $read = $type.GetMethod('ReadBackgroundSettings', $flags)
            [IO.File]::WriteAllText("$temp\Health_Config.xml", '<HealthConfig/>')
            $settings = $read.Invoke($instance, @())
            Assert-Equal "$($settings.Enabled)/$($settings.IntervalMinutes)/$($settings.PauseOnBattery)/$($settings.MaxCpuPercent)/$($settings.StartDelaySeconds)" 'True/15/True/75/120' 'Background defaults'
            [IO.File]::WriteAllText("$temp\Health_Config.xml", '<HealthConfig><Background Enabled="false" IntervalMinutes="30" PauseOnBattery="false" MaxCpuPercent="50" StartDelaySeconds="0"/></HealthConfig>')
            $settings = $read.Invoke($instance, @())
            Assert-Equal "$($settings.Enabled)/$($settings.IntervalMinutes)/$($settings.PauseOnBattery)/$($settings.MaxCpuPercent)/$($settings.StartDelaySeconds)" 'False/30/False/50/0' 'Background settings read'
            [IO.File]::WriteAllText("$temp\Health_Config.xml", '<HealthConfig><Background IntervalMinutes="1" MaxCpuPercent="500" StartDelaySeconds="-5"/></HealthConfig>')
            $settings = $read.Invoke($instance, @())
            Assert-Equal "$($settings.IntervalMinutes)/$($settings.MaxCpuPercent)/$($settings.StartDelaySeconds)" '15/75/120' 'Out-of-range background values use the defaults'
            $statusMethod = $type.GetMethod('GetStatusResponse', $flags)
            $cacheFile = $type.GetField('cacheFile', $flags).GetValue($instance)
            Assert-Equal $statusMethod.Invoke($instance, @()) 'STATUS NONE 15 Active -' 'STATUS without cache'
            [void][IO.Directory]::CreateDirectory((Split-Path $cacheFile))
            [IO.File]::WriteAllText($cacheFile, '[{"Id":"IME","Name":"","Status":"OK","Detail":"a","Remediation":""}]')
            [IO.File]::SetLastWriteTimeUtc($cacheFile, [datetime]::new(2026, 11, 4, 9, 30, 5, [DateTimeKind]::Utc))
            $answer = $statusMethod.Invoke($instance, @())
            Assert-Equal ($answer -match '^STATUS 2026-11-04T09:30:05Z 15 Active ([A-Za-z0-9+/=]+)$') $true 'STATUS with cache time and data'
            Assert-Equal ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Matches[1])).Contains('"IME"')) $true 'STATUS carries the cache content'
            Assert-Equal ($type.GetMethod('ProcessRequest', $flags).Invoke($instance, @('STATUS', 'test', $null)) -like 'STATUS 2026-11-04T09:30:05Z*') $true 'STATUS request is answered without running a script'
            [IO.Directory]::Delete((Split-Path $cacheFile), $true)
        } finally { $instance.Dispose() }
    }
    Write-Output "PASS: $script:assertions assertions. System probes and script execution mocked; service whitelist tested without starting the service."
} finally {
    $env:SystemRoot = $originalRoot
    foreach ($file in @('Health_Config.xml','report.json','Issues_List.xml')) {
        $path = Join-Path $temp $file
        if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) }
    }
    [IO.Directory]::Delete($temp, $true)
}
