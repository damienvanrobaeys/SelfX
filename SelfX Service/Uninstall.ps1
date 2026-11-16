<#
.SYNOPSIS
    Remove the SelfX service, installed payload, shortcuts, and uninstall registration.

.DESCRIPTION
    Runs elevated, normally as SYSTEM via Intune/SCCM. Stops and deletes SelfXService,
    waits up to thirty seconds for removal, deletes configured shortcuts from the public
    desktop and machine Start Menu, and removes the HKLM Apps & Features entry. Deletes
    the entire InstallFolder (default ProgramFiles\SelfX), including local customizations.
    ProgramData\SelfX logs are retained unless -RemoveLogs deletes that directory too.
    Device logs reports (ProgramData\SelfX\Reports) and the status cache (ProgramData\SelfX\Cache)
    are always deleted. The HKLM Run entry of the status icon is removed. Open SelfX windows
    and status icons of all signed-in users (powershell.exe running Self_X.ps1 or
    SelfX_Tray.ps1 from InstallFolder) are closed first, because they keep the install
    folder in use. Per-user settings and caches (HKCU\Software\SelfX,
    LOCALAPPDATA\SelfX) are not removed.
    Install files locked by other programs are retried for up to 90 seconds;
    an empty install folder that is still in use is left behind and
    does not count as failure. A service that is only marked for deletion (still opened by
    another program such as the Services console) does not count as failure either.
    Writes ProgramData\SelfX\Logs\Uninstall.log when the Logs folder exists.
    Service availability is interrupted; Windows is not restarted. Exits 1 for missing
    administrator rights or remaining files/service, and 0 otherwise. Several deletion
    errors are suppressed, so exit 0 does not verify every shortcut or registry removal.

.NOTES
    Name    : Uninstall.ps1
    Package : SelfX Service
    Context : Installer (SYSTEM via Intune/SCCM)
    Version : 2.5.7

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.0.0    2026-10-28  Wolfgang Baeck       Initial version for SelfX Service
    2.2.0    2026-10-28  Wolfgang Baeck       Added description, history and comments
    2.4.0    2026-11-02  Wolfgang Baeck       Always delete the device logs reports
    2.5.0    2026-11-04  Wolfgang Baeck       Remove the status icon autostart and the status cache
    2.5.2    2026-11-04  Wolfgang Baeck       Retry locked install files (open SelfX window or status icon); a remaining
                                              empty folder in use is no failure
    2.5.7    2026-11-05  Wolfgang Baeck       Close open SelfX windows and status icons of all users before removal; a
                                              service marked for deletion is no failure; log Logs\Uninstall.log
#>

[CmdletBinding()]
param(
	[string]$InstallFolder = (Join-Path $env:ProgramFiles 'SelfX'),
	[switch]$RemoveLogs
)

$ServiceName = 'SelfXService'
$UninstallKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\SelfX'
$DataFolder = Join-Path $env:ProgramData 'SelfX'

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
If(-not $IsAdmin) { Write-Output 'Uninstall.ps1 must run with administrator rights.'; exit 1 }

# This script may run from the install folder, which is deleted below
Set-Location -LiteralPath $env:SystemRoot
[Environment]::CurrentDirectory = $env:SystemRoot

# Log next to Install.log (the folder exists after an installation and is readable only by administrators)
$Transcript = $false
If(Test-Path -LiteralPath (Join-Path $DataFolder 'Logs'))
{
	Try { Start-Transcript -Path (Join-Path $DataFolder 'Logs\Uninstall.log') -Append | Out-Null; $Transcript = $true } Catch {}
}

$ShortcutName = 'SelfX (Self fix)'
$ToolConfigFile = Join-Path $InstallFolder 'Tool_Config.xml'
If(Test-Path -LiteralPath $ToolConfigFile)
{
	$Name = ([xml](Get-Content -LiteralPath $ToolConfigFile -Raw)).GUI_Config.Shortcut_Name
	If(-not [string]::IsNullOrWhiteSpace($Name)) { $ShortcutName = $Name.Trim() }
}

$Service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
If($Service)
{
	If($Service.Status -ne 'Stopped') { Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue }
	& sc.exe delete $ServiceName | Out-Null
	For($i = 0; ($i -lt 30) -and (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Seconds 1 }
}

# Check both shared shortcut locations even if installation created only one shortcut.
ForEach($Folder in @((Join-Path $env:PUBLIC 'Desktop'), (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs')))
{
	Remove-Item -LiteralPath (Join-Path $Folder "$ShortcutName.lnk") -Force -ErrorAction SilentlyContinue
}

Remove-Item -Path $UninstallKey -Recurse -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Name 'SelfXTray' -ErrorAction SilentlyContinue

# Close open SelfX windows and status icons of all signed-in users: they use the install folder (working
# directory, scripts) and would otherwise make the uninstallation fail.
$SelfXPattern = [regex]::Escape($InstallFolder.TrimEnd('\')) + '\\(Self_X|SelfX_Tray)\.ps1'
$SelfXProcesses = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
	Where-Object { ($_.ProcessId -ne $PID) -and ("$($_.CommandLine)" -match $SelfXPattern) })
ForEach($Process in $SelfXProcesses)
{
	Stop-Process -Id $Process.ProcessId -Force -ErrorAction SilentlyContinue
	Write-Output "Closed SelfX process $($Process.ProcessId)."
}
If($SelfXProcesses.Count -gt 0) { Start-Sleep -Seconds 2 }

# Other programs (e.g. an Explorer window) can still lock the folder or single files, so removal is retried
# for up to 90 seconds.
For($Attempt = 1; ($Attempt -le 45) -and (Test-Path -LiteralPath $InstallFolder); $Attempt++)
{
	Remove-Item -LiteralPath $InstallFolder -Recurse -Force -ErrorAction SilentlyContinue
	If(Test-Path -LiteralPath $InstallFolder) { Start-Sleep -Seconds 2 }
}
$RemainingFiles = @(Get-ChildItem -LiteralPath $InstallFolder -Recurse -Force -File -ErrorAction SilentlyContinue)
If((Test-Path -LiteralPath $InstallFolder) -and ($RemainingFiles.Count -eq 0))
{
	# Only empty folders are left (still in use by another program): nothing of SelfX remains.
	Write-Output "The empty folder '$InstallFolder' is still in use and remains until the next sign-out or restart."
}
# Reports contain user and device data; they are never kept after uninstall.
Remove-Item -LiteralPath (Join-Path $DataFolder 'Reports') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $DataFolder 'Cache') -Recurse -Force -ErrorAction SilentlyContinue

# A service that another program still has open (e.g. the Services console) is only marked for deletion. It
# can no longer start (its file is gone) and disappears when that program closes it, so this is no failure.
$ServiceLeft = $false
If(Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)
{
	& sc.exe delete $ServiceName | Out-Null
	If($LASTEXITCODE -eq 1072) { Write-Output "Service '$ServiceName' is marked for deletion and disappears when the last program closes it." }
	ElseIf(@(0, 1060) -notcontains $LASTEXITCODE) { $ServiceLeft = $true; Write-Output "Service '$ServiceName' could not be deleted (sc.exe exit code $LASTEXITCODE)." }
}

$ExitCode = 0
If(($RemainingFiles.Count -gt 0) -or $ServiceLeft)
{
	If($RemainingFiles.Count -gt 0) { Write-Output "Files in use: $(($RemainingFiles | Select-Object -ExpandProperty FullName) -join ', ')" }
	Write-Output 'SelfX could not be removed completely.'
	$ExitCode = 1
}
Else { Write-Output 'SelfX removed.' }
If($Transcript) { Stop-Transcript | Out-Null }
If($RemoveLogs) { Remove-Item -LiteralPath $DataFolder -Recurse -Force -ErrorAction SilentlyContinue }
exit $ExitCode
