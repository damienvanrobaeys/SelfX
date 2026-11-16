<#
.SYNOPSIS
    Run isolated regression tests for the device logs feature (send logs to support).
.DESCRIPTION
    Tests SelfX_Device_CollectLogs.ps1 (System wrapper), SupportReport.ps1 (e-mail helper),
    the Post_Action field of the catalogue and the MailReport step of the GUI. All external
    commands are mocked: the collector, icacls, Outlook (COM and outlook.exe), Start-Process,
    Explorer and the scheduled task cmdlets. Nothing is sent, no e-mail or window is opened,
    no ACL is changed and no service is contacted. Files are created only in a temporary folder.
    Module autoloading is disabled and SystemRoot points to a non-existent folder.
    Run in Windows PowerShell 5.1: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-DeviceLogs.ps1
.NOTES
    Version: 2.6.4
    History:
    2.4.0  2026-11-02  Wolfgang Baeck  Initial device logs tests.
    2.6.4  2026-11-06  Wolfgang Baeck  SelfX logs in the report (selection, own user logs only, no junctions, size limit).
#>
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerShell.Utility
Import-Module Microsoft.PowerShell.Management
# Start-SelfXSystemAction sets a WPF cursor; the assembly is loaded without opening a window.
Add-Type -AssemblyName PresentationCore
$PSModuleAutoLoadingPreference = 'None'
$sources = Join-Path $PSScriptRoot 'Sources'

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

# Function definitions of the code under test (dot-sourcing the wrapper only defines functions).
. "$sources\Scripts_to_run\SelfX_Device_CollectLogs.ps1"
. "$sources\SupportReport.ps1"
. "$sources\Localization.ps1"
# Logger functions without Initialize-SelfXLog: they write nothing during the tests.
. "$sources\SelfXLog.ps1"
$realSetReportAcl = (Get-Command Set-ReportAcl).ScriptBlock
$realStartManualMail = (Get-Command Start-SelfXManualMail).ScriptBlock

# Mocks, defined after dot-sourcing so that they replace the real functions.
function Set-ReportAcl { param([string]$Path, [string]$ReaderSid) $script:aclCalls += ,@($Path, $ReaderSid) }
function Invoke-DeviceLogCollector {
    param([string]$CollectorPath, [string]$OutputPath, [int]$Days)
    $script:collectorDays = $Days
    if ($script:collectorContent -ne $null) { [IO.File]::WriteAllText($OutputPath, $script:collectorContent) }
    'Collector line 1'
    'Done. Mock report'
}
function Test-SelfXClassicOutlook { $script:classicOutlook }
function Get-SelfXOutlookPath { $script:outlookPath }
function New-Object {
    param([Parameter(Position = 0)][string]$TypeName, [Parameter(Position = 1)][object[]]$ArgumentList, [string]$ComObject)
    if ($ComObject) {
        if ($script:comFails) { throw 'Mock COM failure' }
        $script:fakeMail = [pscustomobject]@{ To = $null; Subject = $null; Body = $null; Attached = @(); Shown = $null }
        $script:fakeMail | Add-Member -MemberType ScriptMethod -Name Display -Value { param($Modal) $this.Shown = "Modal=$Modal" }
        $attachments = [pscustomobject]@{ Mail = $script:fakeMail }
        $attachments | Add-Member -MemberType ScriptMethod -Name Add -Value { param($Path) $this.Mail.Attached += $Path; 'attachment' }
        $script:fakeMail | Add-Member -MemberType NoteProperty -Name Attachments -Value $attachments
        $outlook = [pscustomobject]@{ Mail = $script:fakeMail }
        $outlook | Add-Member -MemberType ScriptMethod -Name CreateItem -Value { param($Type) $this.Mail }
        return $outlook
    }
    if ($ArgumentList) { return Microsoft.PowerShell.Utility\New-Object -TypeName $TypeName -ArgumentList $ArgumentList }
    return Microsoft.PowerShell.Utility\New-Object -TypeName $TypeName
}
function Start-Process {
    param([string]$FilePath, [object[]]$ArgumentList)
    if ($script:startFails -contains ($FilePath -replace '^(mailto):.*$', '$1')) { throw "Mock start failure $FilePath" }
    $script:started += ,@($FilePath, ($ArgumentList -join ' '))
}
function Invoke-CimMethod { throw 'Forbidden in tests' }
function Register-ScheduledTask { throw 'Forbidden in tests' }
function New-ScheduledTask { throw 'Forbidden in tests' }
function New-ScheduledTaskAction { throw 'Forbidden in tests' }
function New-ScheduledTaskTrigger { throw 'Forbidden in tests' }
function New-ScheduledTaskPrincipal { throw 'Forbidden in tests' }
function New-ScheduledTaskSettingsSet { throw 'Forbidden in tests' }
foreach ($name in @('Set-ReportAcl', 'Invoke-DeviceLogCollector', 'Test-SelfXClassicOutlook', 'Get-SelfXOutlookPath',
    'New-Object', 'Start-Process', 'Invoke-CimMethod', 'Register-ScheduledTask', 'New-ScheduledTask',
    'New-ScheduledTaskAction', 'New-ScheduledTaskTrigger', 'New-ScheduledTaskPrincipal', 'New-ScheduledTaskSettingsSet')) {
    Assert-Equal (Get-Command $name).CommandType Function "Mock resolution: $name"
}

$originalRoot = $env:SystemRoot
$originalSid = $env:SELFX_CALLER_SID
$env:SystemRoot = 'Z:\SelfX-Nonexistent-Test-Windows'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('SelfXDeviceLogsTests-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$junction = $null
try {
    $sid = 'S-1-12-1-1111111111-2222222222-333333333-444444444'
    $root = Join-Path $temp 'Reports'
    $collector = Join-Path $temp 'Collect-DeviceLogs.ps1'
    Set-Content -LiteralPath $collector -Value '# mock collector, never started'
    $config = Join-Path $temp 'Tool_Config.xml'
    function Set-TestConfig($Days, $Compress) {
        Set-Content -LiteralPath $config -Value "<GUI_Config><DeviceLogs_Days>$Days</DeviceLogs_Days><DeviceLogs_Compress>$Compress</DeviceLogs_Compress></GUI_Config>"
    }
    function Invoke-Wrapper([string]$Collector = $collector) {
        $script:aclCalls = @()
        $output = @(Invoke-SelfXCollectLogs -ReportRoot $root -CollectorPath $Collector -ConfigPath $config)
        $script:wrapperOutput = $output | Select-Object -SkipLast 1
        return ($output | Select-Object -Last 1)
    }

    # --- Caller SID validation -------------------------------------------------------------
    Remove-Item Env:\SELFX_CALLER_SID -ErrorAction SilentlyContinue
    $script:collectorContent = 'report'
    Set-TestConfig 7 True
    Assert-Equal (Invoke-Wrapper) 2 'Missing caller SID'
    Assert-Equal (Test-Path $root) $false 'No folder without caller SID'
    foreach ($bad in @('abc', '..\..\Windows', 'S-1-5-18\..\x', ' ')) {
        $env:SELFX_CALLER_SID = $bad
        Assert-Equal (Invoke-Wrapper) 2 "Invalid caller SID '$bad'"
    }

    # --- Success with compression ----------------------------------------------------------
    $env:SELFX_CALLER_SID = $sid
    Set-TestConfig 14 True
    $userFolder = Join-Path $root $sid
    [void][IO.Directory]::CreateDirectory($userFolder)
    Set-Content -LiteralPath (Join-Path $userFolder 'DeviceLogs-OLD-1.zip') -Value 'previous'
    $otherOld = Join-Path $root 'S-1-5-21-1-2-3-1001'
    $otherNew = Join-Path $root 'S-1-5-21-1-2-3-1002'
    [void][IO.Directory]::CreateDirectory($otherOld)
    [void][IO.Directory]::CreateDirectory($otherNew)
    Set-Content -LiteralPath (Join-Path $otherOld 'DeviceLogs-A.zip') -Value 'old'
    (Get-Item -LiteralPath (Join-Path $otherOld 'DeviceLogs-A.zip')).LastWriteTime = (Get-Date).AddDays(-8)
    Set-Content -LiteralPath (Join-Path $otherNew 'DeviceLogs-B.zip') -Value 'new'
    $script:collectorContent = "Collect-DeviceLogs mock report`r`nline 2"
    Assert-Equal (Invoke-Wrapper) 0 'Report created'
    Assert-Equal $script:collectorDays 14 'DeviceLogs_Days passed to the collector'
    Assert-Equal $script:aclCalls.Count 2 'ACL set for root and user folder'
    Assert-Equal $script:aclCalls[0][0] $root 'Root ACL path'
    Assert-Equal $script:aclCalls[0][1] '' 'Root ACL without reader'
    Assert-Equal $script:aclCalls[1][0] $userFolder 'User folder ACL path'
    Assert-Equal $script:aclCalls[1][1] $sid 'User folder reader is the caller'
    $files = @(Get-ChildItem -LiteralPath $userFolder -File)
    Assert-Equal $files.Count 1 'Only the new report is kept'
    Assert-Equal $files[0].Extension '.zip' 'Report is compressed'
    Assert-Equal ($files[0].Name -like "DeviceLogs-$env:COMPUTERNAME-*.zip") $true 'Report name'
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($files[0].FullName)
    try {
        Assert-Equal $zip.Entries.Count 1 'One entry in the zip'
        Assert-Equal $zip.Entries[0].Name ($files[0].BaseName + '.txt') 'Zip entry name'
        $reader = New-Object System.IO.StreamReader($zip.Entries[0].Open())
        Assert-Equal $reader.ReadToEnd() $script:collectorContent 'Zip content'
        $reader.Dispose()
    } finally { $zip.Dispose() }
    Assert-Equal (Test-Path -LiteralPath $otherOld) $false 'Old report of another user removed'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $otherNew 'DeviceLogs-B.zip')) $true 'Recent report of another user kept'
    Assert-Equal (@($script:wrapperOutput) -match '^Report: ').Count 1 'Report path written to the service log'
    Assert-Equal (@($script:wrapperOutput) -contains 'Done. Mock report') $true 'Collector summary in the service log'

    # --- Settings ----------------------------------------------------------------------------
    Set-TestConfig 7 False
    Assert-Equal (Invoke-Wrapper) 0 'Report without compression'
    $files = @(Get-ChildItem -LiteralPath $userFolder -File)
    Assert-Equal $files.Count 1 'Previous zip replaced'
    Assert-Equal $files[0].Extension '.txt' 'DeviceLogs_Compress False keeps the text file'
    foreach ($days in @('99', '0', 'abc', '')) {
        Set-TestConfig $days True
        Assert-Equal (Invoke-Wrapper) 0 "Days '$days' accepted"
        Assert-Equal $script:collectorDays 7 "Days '$days' falls back to 7"
    }
    Remove-Item -LiteralPath $config
    Assert-Equal (Invoke-Wrapper) 0 'Missing Tool_Config.xml'
    Assert-Equal @(Get-ChildItem -LiteralPath $userFolder -File)[0].Extension '.zip' 'Compression is the default'
    Set-TestConfig 7 True

    # --- SelfX logs in the report (2.6.4) ------------------------------------------------------
    $logRoot = Join-Path $temp 'SelfXLogs'
    function New-LogFile([string]$Name, [int]$AgeDays, [string]$Content = 'line') {
        $path = Join-Path $logRoot $Name
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
        [IO.File]::WriteAllText($path, $Content)
        (Get-Item -LiteralPath $path).LastWriteTime = (Get-Date).AddDays(-$AgeDays)
    }
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    New-LogFile 'SelfXService.log' 40 'service log'
    New-LogFile 'Install.log' 60 'install log'
    New-LogFile 'HealthStatus_2026-11-06.log' 0 'health today'
    New-LogFile 'HealthStatus_2026-09-01.log' 30 'health old'
    New-LogFile 'notes.txt' 0 'not a log'
    New-LogFile "Users\$me\SelfX_2026-11-06.log" 0 'my gui log'
    New-LogFile 'Users\S-1-5-21-9-9-9-1001\SelfX_2026-11-06.log' 0 'other user'
    $bigContent = (('x' * 1023) + "`n") * 2600
    New-LogFile 'Big_2026-11-06.log' 0 $bigContent
    $selected = @(Get-SelfXOwnLogFiles -LogRoot $logRoot -CallerSid $me -Days 7 | ForEach-Object { $_.Entry })
    Assert-Equal ($selected -join ';') "SelfX-Logs\Big_2026-11-06.log;SelfX-Logs\HealthStatus_2026-11-06.log;SelfX-Logs\Install.log;SelfX-Logs\SelfXService.log;SelfX-Logs\User\SelfX_2026-11-06.log" 'SelfX logs: service/install always, others of the last days, own user logs only'
    # Files in the user folder that belong to another account (for example a hard link) are never read.
    Assert-Equal (@(Get-SelfXOwnLogFiles -LogRoot $logRoot -CallerSid 'S-1-5-21-9-9-9-1001' -Days 7 | Where-Object { $_.Entry -like '*\User\*' }).Count) 0 'SelfX logs: user files not owned by the caller are skipped'
    $outside = Join-Path $temp 'Outside'; [void][IO.Directory]::CreateDirectory($outside); [IO.File]::WriteAllText((Join-Path $outside 'secret.log'), 'secret')
    $linkSid = 'S-1-5-21-9-9-9-1002'
    New-Item -ItemType Junction -Path (Join-Path $logRoot "Users\$linkSid") -Value $outside | Out-Null
    Assert-Equal (@(Get-SelfXOwnLogFiles -LogRoot $logRoot -CallerSid $linkSid -Days 7 | Where-Object { $_.Entry -like '*\User\*' }).Count) 0 'SelfX logs: a junction as user folder is not followed'
    [IO.Directory]::Delete((Join-Path $logRoot "Users\$linkSid"))
    $tail = Read-SelfXLogText -Path (Join-Path $logRoot 'Big_2026-11-06.log')
    Assert-Equal ($tail.StartsWith('[... only the last 2 MB') -and $tail.Length -lt 2.2MB) $true 'SelfX logs: only the last 2 MB of a large file'
    $env:SELFX_CALLER_SID = $me
    $meFolder = Join-Path $root $me
    $script:aclCalls = @()
    $output = @(Invoke-SelfXCollectLogs -ReportRoot $root -CollectorPath $collector -ConfigPath $config -LogRoot $logRoot)
    Assert-Equal ($output | Select-Object -Last 1) 0 'Report with SelfX logs created'
    Assert-Equal (@($output) -contains 'SelfX logs added: 5 file(s)') $true 'Number of SelfX logs reported'
    $zipPath = @(Get-ChildItem -LiteralPath $meFolder -Filter '*.zip')[0].FullName
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $names = @($zip.Entries | ForEach-Object { $_.FullName })
        Assert-Equal $names.Count 6 'Zip: report and 5 SelfX logs'
        Assert-Equal ($names -contains 'SelfX-Logs\User\SelfX_2026-11-06.log') $true 'Zip: own user log in SelfX-Logs\User'
        $reader = New-Object System.IO.StreamReader($zip.GetEntry('SelfX-Logs\SelfXService.log').Open())
        Assert-Equal $reader.ReadToEnd() 'service log' 'Zip: content of the service log'
        $reader.Dispose()
    } finally { $zip.Dispose() }
    Set-TestConfig 7 False
    $output = @(Invoke-SelfXCollectLogs -ReportRoot $root -CollectorPath $collector -ConfigPath $config -LogRoot $logRoot)
    $text = [IO.File]::ReadAllText(@(Get-ChildItem -LiteralPath $meFolder -Filter '*.txt')[0].FullName)
    Assert-Equal ($text.StartsWith($script:collectorContent) -and $text.Contains('SelfX logs (ProgramData\SelfX\Logs)') -and $text.Contains("----- SelfX-Logs\User\SelfX_2026-11-06.log -----`r`nmy gui log")) $true 'Text report: SelfX logs appended as last section'
    Assert-Equal ($text.Contains('other user') -or $text.Contains('not a log') -or $text.Contains('health old')) $false 'Text report: no logs of other users, no other files, no old logs'
    Remove-Item -LiteralPath $meFolder -Recurse -Force
    $env:SELFX_CALLER_SID = $sid
    Set-TestConfig 7 True

    # --- Failures ------------------------------------------------------------------------------
    $script:collectorContent = $null
    Assert-Equal (Invoke-Wrapper) 1 'Collector without report'
    $script:collectorContent = ''
    Assert-Equal (Invoke-Wrapper) 1 'Empty report'
    $script:collectorContent = 'report'
    Assert-Equal (Invoke-Wrapper (Join-Path $temp 'missing.ps1')) 1 'Collector missing'
    Remove-Item -LiteralPath $userFolder -Recurse -Force
    $target = Join-Path $temp 'JunctionTarget'
    [void][IO.Directory]::CreateDirectory($target)
    Set-Content -LiteralPath (Join-Path $target 'keep.txt') -Value 'must survive'
    $junction = $userFolder
    New-Item -ItemType Junction -Path $junction -Value $target | Out-Null
    Assert-Equal (Invoke-Wrapper) 1 'Junction as user folder refused'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $target 'keep.txt')) $true 'Junction target untouched'
    Assert-Equal @(Get-ChildItem -LiteralPath $target).Count 1 'Nothing written through the junction'
    [IO.Directory]::Delete($junction)
    $junction = $null
    Assert-Throws { & $realSetReportAcl -Path $temp -ReaderSid $sid } 'Real icacls is not reachable in tests'

    # --- Report lookup and copy (SupportReport.ps1) ----------------------------------------------
    Assert-Equal (Get-SelfXReportFolder -Root 'C:\R') ('C:\R\' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) 'Report folder of the current user'
    $reports = Join-Path $temp 'UserReports'
    Assert-Equal (Get-SelfXLatestReport -Folder $reports) $null 'Missing report folder'
    [void][IO.Directory]::CreateDirectory($reports)
    $dest = Join-Path $temp 'Copies'
    $result = Send-SelfXSupportReport -To 'help@contoso.com' -Subject 'S' -Body 'B' -ReportFolder $reports -Destination $dest
    Assert-Equal $result.Status 'NotFound' 'No report'
    Set-Content -LiteralPath (Join-Path $reports 'DeviceLogs-PC-1.zip') -Value 'older'
    (Get-Item -LiteralPath (Join-Path $reports 'DeviceLogs-PC-1.zip')).LastWriteTime = (Get-Date).AddMinutes(-5)
    Set-Content -LiteralPath (Join-Path $reports 'DeviceLogs-PC-2.zip') -Value 'newest'
    Set-Content -LiteralPath (Join-Path $reports 'DeviceLogs-PC-3.log') -Value 'other type'
    (Get-Item -LiteralPath (Join-Path $reports 'DeviceLogs-PC-3.log')).LastWriteTime = (Get-Date).AddMinutes(5)
    Set-Content -LiteralPath (Join-Path $reports 'Other.zip') -Value 'other name'
    (Get-Item -LiteralPath (Join-Path $reports 'Other.zip')).LastWriteTime = (Get-Date).AddMinutes(5)
    Assert-Equal (Get-SelfXLatestReport -Folder $reports).Name 'DeviceLogs-PC-2.zip' 'Newest DeviceLogs zip/txt selected'
    [void][IO.Directory]::CreateDirectory($dest)
    Set-Content -LiteralPath (Join-Path $dest 'DeviceLogs-OLD.zip') -Value 'old copy'
    Set-Content -LiteralPath (Join-Path $dest 'notes.txt') -Value 'user file'

    # --- Classic Outlook through COM -------------------------------------------------------------
    $script:classicOutlook = $true
    $script:comFails = $false
    $script:started = @()
    $result = Send-SelfXSupportReport -To 'help@contoso.com' -Subject 'Device logs from PC' -Body "Hello`r`n`r`nIssue:" -ReportFolder $reports -Destination $dest
    $copy = Join-Path $dest 'DeviceLogs-PC-2.zip'
    Assert-Equal $result.Status 'Outlook' 'Outlook COM used'
    Assert-Equal $result.Path $copy 'Attached copy path'
    Assert-Equal (Get-Content -LiteralPath $copy -Raw).Trim() 'newest' 'Copy content'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $dest 'DeviceLogs-OLD.zip')) $false 'Older copy removed'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $dest 'notes.txt')) $true 'Other user files kept'
    Assert-Equal $script:fakeMail.To 'help@contoso.com' 'Recipient'
    Assert-Equal $script:fakeMail.Subject 'Device logs from PC' 'Subject'
    Assert-Equal $script:fakeMail.Body "Hello`r`n`r`nIssue:" 'Body'
    Assert-Equal ($script:fakeMail.Attached -join '|') $copy 'Attachment'
    Assert-Equal $script:fakeMail.Shown 'Modal=False' 'E-mail displayed, not modal and not sent'
    Assert-Equal $script:started.Count 0 'No process started with Outlook COM'
    $result = Send-SelfXSupportReport -To '' -Subject 'S' -Body 'B' -ReportFolder $reports -Destination $dest
    Assert-Equal $result.Status 'Outlook' 'Outlook without support address'
    Assert-Equal $script:fakeMail.To $null 'Empty recipient is not set'

    # --- outlook.exe /a ---------------------------------------------------------------------------
    $script:classicOutlook = $false
    $script:outlookPath = 'Z:\Office\OUTLOOK.EXE'
    $script:started = @()
    $result = Send-SelfXSupportReport -To 'help@contoso.com' -Subject 'S' -Body 'B' -ReportFolder $reports -Destination $dest
    Assert-Equal $result.Status 'OutlookCommandLine' 'outlook.exe fallback'
    Assert-Equal $script:started.Count 1 'One process'
    Assert-Equal $script:started[0][0] 'Z:\Office\OUTLOOK.EXE' 'outlook.exe path'
    Assert-Equal $script:started[0][1] "/a `"$copy`"" 'outlook.exe /a argument'
    Assert-Equal ($result.Message -like 'Outlook: Classic Outlook is not installed*') $true 'COM failure reported'
    $script:classicOutlook = $true
    $script:comFails = $true
    $script:started = @()
    $result = Send-SelfXSupportReport -To 'help@contoso.com' -Subject 'S' -Body 'B' -ReportFolder $reports -Destination $dest
    Assert-Equal $result.Status 'OutlookCommandLine' 'COM error falls back to outlook.exe'

    # --- Default mail app (mailto) and Explorer ---------------------------------------------------------
    $script:outlookPath = $null
    $script:started = @()
    $result = Send-SelfXSupportReport -To 'help@contoso.com' -Subject 'Device logs from PC' -Body "Hello & bye`r`nLine 2" -ReportFolder $reports -Destination $dest
    Assert-Equal $result.Status 'Manual' 'Manual fallback'
    Assert-Equal $script:started.Count 2 'mailto and Explorer'
    Assert-Equal $script:started[0][0] 'mailto:help@contoso.com?subject=Device%20logs%20from%20PC&body=Hello%20%26%20bye%0D%0ALine%202' 'mailto URI is encoded'
    Assert-Equal $script:started[1][0] 'Z:\SelfX-Nonexistent-Test-Windows\explorer.exe' 'Explorer from SystemRoot'
    Assert-Equal $script:started[1][1] "/select,`"$copy`"" 'Explorer selects the report'
    $script:startFails = @('mailto')
    $script:started = @()
    $result = Send-SelfXSupportReport -To 'help@contoso.com' -Subject 'S' -Body 'B' -ReportFolder $reports -Destination $dest
    Assert-Equal $result.Status 'Manual' 'Missing mail app still shows the file'
    Assert-Equal $script:started.Count 1 'Explorer only'
    $script:startFails = @('mailto', 'Z:\SelfX-Nonexistent-Test-Windows\explorer.exe')
    $result = Send-SelfXSupportReport -To 'help@contoso.com' -Subject 'S' -Body 'B' -ReportFolder $reports -Destination $dest
    Assert-Equal $result.Status 'Error' 'All methods failed'
    $script:startFails = @()
    $blocked = Join-Path $temp 'blocked'
    Set-Content -LiteralPath $blocked -Value 'a file, not a folder'
    $result = Send-SelfXSupportReport -To 'x' -Subject 'S' -Body 'B' -ReportFolder $reports -Destination $blocked
    Assert-Equal $result.Status 'Error' 'Copy failure'

    # --- Catalogue: Post_Action and translations ---------------------------------------------------------
    $catalog = New-Object System.Xml.XmlDocument
    $catalog.Load("$sources\Issues_List.xml")
    [void](Initialize-SelfXLanguage -LanguageFolder "$sources\Languages" -Language 'de')
    $quick = @(Get-SelfXLocalizedActions -Catalog $catalog -Section 'Quick_Solution')
    $detailed = @(Get-SelfXLocalizedActions -Catalog $catalog -Section 'Detailed_Solution')
    $mailActions = @($quick + $detailed | Where-Object { $_.Post_Action -eq 'MailReport' })
    Assert-Equal $mailActions.Count 2 'Two MailReport actions'
    foreach ($action in $mailActions) {
        Assert-Equal $action.Context 'System' "$($action.Id) runs as System"
        Assert-Equal $action.Script 'SelfX_Device_CollectLogs.ps1' "$($action.Id) script"
        Assert-Equal (Test-Path -LiteralPath (Join-Path "$sources\Scripts_to_run" $action.Script)) $true "$($action.Id) script exists"
    }
    Assert-Equal (Test-Path -LiteralPath "$sources\Scripts_to_run\Collect-DeviceLogs.ps1") $true 'Collector is packaged'
    Assert-Equal ($quick | Where-Object Id -eq 'Q_Device_SendLogs').Name 'Geräteprotokolle an den Support senden' 'German action name'
    Assert-Equal (($quick | Where-Object Id -eq 'Q_Device_SendLogs').Alerte_MSG -like 'SelfX sammelt jetzt*') $true 'German confirmation text'
    Assert-Equal @($quick + $detailed | Where-Object { $_.Id -notlike '*_SendLogs' -and $_.Post_Action -ne '' }).Count 0 'Other actions have no Post_Action'
    Assert-Equal (Get-SelfXString 'Report_Mail_Subject' 'PC1') 'Geräteprotokolle von PC1' 'German subject'
    $timeout = $catalog.SelectSingleNode("//Action[@Id='Q_Device_SendLogs']/TimeoutSeconds").InnerText
    Assert-Equal $timeout '1800' 'Timeout of the collection'

    # --- GUI: MailReport step in the background runspace (functions taken from Self_X.ps1) ---------------
    $ast = [System.Management.Automation.Language.Parser]::ParseFile("$sources\Self_X.ps1", [ref]$null, [ref]$null)
    foreach ($fn in @('Start-SelfXSystemAction', 'Show-SelfXReportMailResult')) {
        $def = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $fn }, $true)
        Assert-Equal ($def -ne $null) $true "$fn found in Self_X.ps1"
        . ([scriptblock]::Create($def.Extent.Text))
    }
    function Update-SelfXFixAllButton {}
    function Update-SelfXStatusView {}
    function Set-SelfXActionRunning { param($Row, $Running) if ($Row) { $Row.Running = $Running } }
    function ConvertTo-SelfXUserTime { param([datetime]$Time) $Time.ToLocalTime() }
    $script:alerts = @()
    $msgbar = [pscustomobject]@{}
    foreach ($kind in 'Clear', 'SetSuccessAlert', 'SetWarningAlert', 'SetDangerAlert', 'SetInformationAlert') {
        $msgbar | Add-Member -MemberType ScriptMethod -Name $kind -Value ([scriptblock]::Create("param(`$t) `$script:alerts += ,@('$kind', `$t)"))
    }
    $Form = [pscustomobject]@{ Cursor = $null }
    $SvcAction_Timer = [pscustomobject]@{}
    $SvcAction_Timer | Add-Member -MemberType ScriptMethod -Name Start -Value { }
    $Support_Mail = 'help@contoso.com'
    $Global:SvcAction_Running = $false
    # Stubs instead of the real pipe client and e-mail helper: they only echo what they receive.
    $Global:SelfXClient_Script = 'function Invoke-SelfXSystemAction { param($Script) [pscustomobject]@{ Status = "Success"; ExitCode = 0; Message = "DONE 0"; Script = $Script } }'
    $Global:SelfXSupportReport_Script = 'function Send-SelfXSupportReport { param($To, $Subject, $Body) [pscustomobject]@{ Status = "Outlook"; To = $To; Subject = $Subject; Body = $Body; Apartment = [Threading.Thread]::CurrentThread.GetApartmentState().ToString() } }'
    Start-SelfXSystemAction -Script "Selfx_O'Test.ps1" -ActionName 'Send logs' -PostAction 'MailReport'
    $result = @($Global:SvcAction_PS.EndInvoke($Global:SvcAction_Handle)) | Select-Object -Last 1
    $Global:SvcAction_PS.Dispose(); $Global:SvcAction_Runspace.Dispose(); $Global:SvcAction_Running = $false
    Assert-Equal $result.Script "Selfx_O'Test.ps1" 'Script name with quote passed unchanged'
    Assert-Equal $result.Report.Status 'Outlook' 'MailReport step runs after success'
    Assert-Equal $result.Report.To 'help@contoso.com' 'Recipient from Support_Mail'
    Assert-Equal $result.Report.Subject ("Geräteprotokolle von $env:COMPUTERNAME") 'Localized subject with computer name'
    Assert-Equal ($result.Report.Body -like "Guten Tag*$env:COMPUTERNAME*Beschreibung des Problems:`r`n`r`n") $true 'Localized body ends with an empty line for the user'
    Assert-Equal $result.Report.Apartment 'STA' 'Background runspace is STA for Outlook COM'
    Assert-Equal $Global:SvcAction_PostAction 'MailReport' 'Post action remembered for the result message'

    $Global:SelfXClient_Script = 'function Invoke-SelfXSystemAction { param($Script) [pscustomobject]@{ Status = "Failed"; ExitCode = 2; Message = "DONE 2" } }'
    Start-SelfXSystemAction -Script 'SelfX_Device_CollectLogs.ps1' -ActionName 'Send logs' -PostAction 'MailReport'
    $result = @($Global:SvcAction_PS.EndInvoke($Global:SvcAction_Handle)) | Select-Object -Last 1
    $Global:SvcAction_PS.Dispose(); $Global:SvcAction_Runspace.Dispose(); $Global:SvcAction_Running = $false
    Assert-Equal ($result.PSObject.Properties.Name -contains 'Report') $false 'No e-mail after a failed collection'
    Start-SelfXSystemAction -Script 'SelfX_Teams_Reboot.ps1' -ActionName 'Teams'
    $result = @($Global:SvcAction_PS.EndInvoke($Global:SvcAction_Handle)) | Select-Object -Last 1
    $Global:SvcAction_PS.Dispose(); $Global:SvcAction_Runspace.Dispose(); $Global:SvcAction_Running = $false
    Assert-Equal $Global:SvcAction_PostAction '' 'Normal actions have no post action'
    # The start button of the action shows that it runs (Running) until the result has arrived.
    $row = [pscustomobject]@{ Name = 'Intune'; Running = $false }
    Start-SelfXSystemAction -Script 'SelfX_Intune_RestartService.ps1' -ActionName 'Intune' -Row $row
    Assert-Equal "$($row.Running)/$([object]::ReferenceEquals($Global:SvcAction_Row, $row))" 'True/True' 'System action marks its row as running'
    [void]$Global:SvcAction_PS.EndInvoke($Global:SvcAction_Handle)
    $Global:SvcAction_PS.Dispose(); $Global:SvcAction_Runspace.Dispose(); $Global:SvcAction_Running = $false; $Global:SvcAction_Row = $null

    foreach ($case in @(
        @('Outlook', 'SetSuccessAlert', 'Eine E-Mail mit den Geräteprotokollen im Anhang wurde geöffnet*'),
        @('OutlookCommandLine', 'SetSuccessAlert', '*Empfänger ein (help@contoso.com)*'),
        @('Manual', 'SetWarningAlert', 'Die Geräteprotokolle wurden unter C:\x.zip gespeichert*(Empfänger: help@contoso.com)*'),
        @('NotFound', 'SetDangerAlert', '*nicht vorbereitet werden: C:\r'),
        @('Error', 'SetDangerAlert', '*nicht vorbereitet werden: C:\r'))) {
        $script:alerts = @()
        Show-SelfXReportMailResult -Report ([pscustomobject]@{ Status = $case[0]; Path = 'C:\x.zip'; Message = 'C:\r' })
        Assert-Equal $script:alerts[0][0] $case[1] "Alert type for $($case[0])"
        Assert-Equal ($script:alerts[0][1] -like $case[2]) $true "Alert text for $($case[0]): $($script:alerts[0][1])"
    }
    $Support_Mail = ''
    $script:alerts = @()
    Show-SelfXReportMailResult -Report ([pscustomobject]@{ Status = 'OutlookCommandLine' })
    Assert-Equal ($script:alerts[0][1] -like '*(Ihr Support)*') $true 'Fallback recipient text without Support_Mail'
} finally {
    if ($junction -and (Test-Path -LiteralPath $junction)) { [IO.Directory]::Delete($junction) }
    $env:SystemRoot = $originalRoot
    if ($originalSid) { $env:SELFX_CALLER_SID = $originalSid } else { Remove-Item Env:\SELFX_CALLER_SID -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output "Device logs tests passed: $script:assertions assertions."
