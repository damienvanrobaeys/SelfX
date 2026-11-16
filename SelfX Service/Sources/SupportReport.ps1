<#
.SYNOPSIS
    Open a new e-mail to the support with the device logs report attached (GUI helper).

.DESCRIPTION
    Loaded by the SelfX GUI in the signed-in user session; defining these functions alone
    performs no action. After the System action SelfX_Device_CollectLogs.ps1 (catalog
    Post_Action MailReport) has written the report to ProgramData\SelfX\Reports\<SID of the
    user>, Send-SelfXSupportReport:
      1. takes the newest DeviceLogs-* file of the current user (only that user can read it),
      2. copies it to %LOCALAPPDATA%\SelfX\Reports (older copies there are deleted),
      3. opens a new e-mail with the copy attached:
         - classic Outlook through COM (recipient, subject and text filled in), else
         - outlook.exe /a <file> (Outlook fills in nothing, the user adds the recipient), else
         - the default mail app through mailto: and an Explorer window with the file selected,
           so the user can attach the file (for example new Outlook, which has no COM interface).
    The e-mail is only displayed, never sent: the user describes the issue and sends it.
    Nothing runs elevated and nothing is sent automatically.

.NOTES
    Name    : SupportReport.ps1
    Package : SelfX Service
    Context : GUI helper (signed-in user)
    Version : 2.4.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.4.0    2026-11-02  Wolfgang Baeck       Initial version: device logs report by e-mail
#>

function Get-SelfXReportFolder {
    # Report folder of the current user, written by the System action and readable only by this user.
    param([string]$Root = (Join-Path $env:ProgramData 'SelfX\Reports'))
    return (Join-Path $Root ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
}

function Get-SelfXLatestReport {
    param([Parameter(Mandatory = $true)][string]$Folder)
    if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { return $null }
    return (Get-ChildItem -LiteralPath $Folder -File -Filter 'DeviceLogs-*' -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.zip', '.txt' } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1)
}

function Copy-SelfXReport {
    # A copy in the user profile stays available after the next run replaces the System copy.
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Destination = (Join-Path $env:LOCALAPPDATA 'SelfX\Reports')
    )
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Get-ChildItem -LiteralPath $Destination -File -Filter 'DeviceLogs-*' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    $target = Join-Path $Destination (Split-Path -Leaf $Path)
    Copy-Item -LiteralPath $Path -Destination $target -Force
    return $target
}

function Test-SelfXClassicOutlook {
    # New Outlook registers no COM ProgID; only classic Outlook can be automated.
    return [bool][type]::GetTypeFromProgID('Outlook.Application')
}

function New-SelfXOutlookMail {
    # Classic Outlook only; new Outlook has no COM interface and fails here.
    param([string]$To, [string]$Subject, [string]$Body, [string]$Attachment)
    if (-not (Test-SelfXClassicOutlook)) { throw 'Classic Outlook is not installed.' }
    $outlook = $null
    $mail = $null
    try {
        $outlook = New-Object -ComObject Outlook.Application
        $mail = $outlook.CreateItem(0)
        if ($To) { $mail.To = $To }
        $mail.Subject = $Subject
        $mail.Body = $Body
        $null = $mail.Attachments.Add($Attachment)
        # Not modal: the SelfX window stays usable while the e-mail is open.
        $mail.Display($false)
    } finally {
        foreach ($comObject in @($mail, $outlook)) {
            if ($comObject -and [Runtime.InteropServices.Marshal]::IsComObject($comObject)) {
                $null = [Runtime.InteropServices.Marshal]::ReleaseComObject($comObject)
            }
        }
    }
}

function Get-SelfXOutlookPath {
    foreach ($key in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE',
                     'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE') {
        $path = (Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).'(default)'
        if ($path -and (Test-Path -LiteralPath $path.Trim('"') -PathType Leaf)) { return $path.Trim('"') }
    }
    return $null
}

function Start-SelfXOutlookCommandLine {
    param([string]$Attachment)
    $outlookExe = Get-SelfXOutlookPath
    if (-not $outlookExe) { throw 'outlook.exe was not found.' }
    Start-Process -FilePath $outlookExe -ArgumentList '/a', "`"$Attachment`""
}

function Start-SelfXManualMail {
    # Default mail app with recipient, subject and text, plus the file selected in Explorer.
    param([string]$To, [string]$Subject, [string]$Body, [string]$Attachment)
    try {
        # The address keeps its @ readable; some mail apps do not decode %40 in the recipient.
        $mailto = 'mailto:{0}?subject={1}&body={2}' -f ([uri]::EscapeDataString("$To") -replace '%40', '@'),
            [uri]::EscapeDataString("$Subject"), [uri]::EscapeDataString("$Body")
        Start-Process -FilePath $mailto
    } catch { }
    Start-Process -FilePath ([IO.Path]::Combine($env:SystemRoot, 'explorer.exe')) -ArgumentList "/select,`"$Attachment`""
}

function Send-SelfXSupportReport {
    <#
    .SYNOPSIS
        Opens a new e-mail with the latest report attached. Returns Status (Outlook,
        OutlookCommandLine, Manual, NotFound or Error), Path (attached copy) and Message.
    #>
    param(
        [string]$To,
        [string]$Subject,
        [string]$Body,
        [string]$ReportFolder = (Get-SelfXReportFolder),
        [string]$Destination = (Join-Path $env:LOCALAPPDATA 'SelfX\Reports')
    )
    $report = Get-SelfXLatestReport -Folder $ReportFolder
    if (-not $report) { return [pscustomobject]@{ Status = 'NotFound'; Path = $null; Message = $ReportFolder } }
    try {
        $copy = Copy-SelfXReport -Path $report.FullName -Destination $Destination
    } catch {
        return [pscustomobject]@{ Status = 'Error'; Path = $report.FullName; Message = $_.Exception.Message }
    }

    $errors = @()
    try {
        New-SelfXOutlookMail -To $To -Subject $Subject -Body $Body -Attachment $copy
        return [pscustomobject]@{ Status = 'Outlook'; Path = $copy; Message = '' }
    } catch { $errors += "Outlook: $($_.Exception.Message)" }
    try {
        Start-SelfXOutlookCommandLine -Attachment $copy
        return [pscustomobject]@{ Status = 'OutlookCommandLine'; Path = $copy; Message = ($errors -join ' / ') }
    } catch { $errors += "outlook.exe: $($_.Exception.Message)" }
    try {
        Start-SelfXManualMail -To $To -Subject $Subject -Body $Body -Attachment $copy
        return [pscustomobject]@{ Status = 'Manual'; Path = $copy; Message = ($errors -join ' / ') }
    } catch {
        $errors += "Explorer: $($_.Exception.Message)"
        return [pscustomobject]@{ Status = 'Error'; Path = $copy; Message = ($errors -join ' / ') }
    }
}
