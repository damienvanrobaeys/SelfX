<#
.SYNOPSIS
    Close OneDrive and start it again in the background.

.DESCRIPTION
    Runs as the signed-in user from the SelfX GUI. Finds OneDrive.exe: the path of the running
    process of the user's session, otherwise LOCALAPPDATA\Microsoft\OneDrive (per-user install)
    or the machine-wide install under Program Files. Closes the OneDrive processes of the user's
    session, waits ten seconds and starts OneDrive again with /background. Synchronization is
    interrupted for a short time; no reset or deletion of files occurs.
    Logs to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1).
    Exit 0 = OneDrive started again; exit 1 = OneDrive not found or could not be closed.

.NOTES
    Name    : SelfX_OneDrive_Reboot.ps1
    Package : SelfX Service
    Context : User
    Version : 2.6.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2022-10-04  Damien Van Robaeys   Initial version (SelfX Standard / SelfX Admin)
    2.0.0    2026-10-28  Wolfgang Baeck       Moved to SelfX Service
    2.2.0    2026-10-28  Wolfgang Baeck       Added description, history and comments
    2.6.0    2026-11-06  Wolfgang Baeck       OneDrive path from the running process, LOCALAPPDATA or Program Files
                                              (was C:\Users\<name>, wrong for Entra ID profiles and machine-wide
                                              installs); also starts OneDrive when it was not running; logging
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }
trap { Write-SelfXLog "Failed: $($_.Exception.Message)" Error; break }

$session = (Get-Process -Id $PID).SessionId
$running = @(Get-Process -Name OneDrive -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session })
$candidates = @($running | ForEach-Object { $_.Path }) + @(
	(Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'),
	(Join-Path $env:ProgramFiles 'Microsoft OneDrive\OneDrive.exe'),
	(Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive\OneDrive.exe'))
$oneDrive = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
if (-not $oneDrive) {
	Write-SelfXLog 'OneDrive.exe was not found.' Error
	exit 1
}
Write-SelfXLog "OneDrive: $oneDrive; $($running.Count) running process(es)."
if ($running.Count) {
	$running | Stop-Process -Force -ErrorAction Stop
	# Allow OneDrive time to release sync files before the background start.
	Start-Sleep -Seconds 10
}
Start-Process -FilePath $oneDrive -ArgumentList '/background'
Write-SelfXLog 'OneDrive started again (/background).'
exit 0
