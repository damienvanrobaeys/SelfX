<#
.SYNOPSIS
    Reset OneDrive and start its synchronization client again in the background.

.DESCRIPTION
    Runs as the signed-in user from the SelfX GUI. Finds OneDrive.exe: the path of the running
    process of the user's session, otherwise LOCALAPPDATA\Microsoft\OneDrive (per-user install)
    or the machine-wide install under Program Files. Closes the OneDrive processes of the user's
    session and runs "OneDrive.exe /reset", which closes OneDrive and rebuilds its local
    synchronization state. Waits thirty seconds and starts OneDrive with /background.
    The reset can cause a full resynchronization; it does not delete cloud files. Files that
    were not yet uploaded stay in the OneDrive folder.
    Logs to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1).
    Exit 0 = reset done and OneDrive started; exit 1 = OneDrive not found.

.NOTES
    Name    : SelfX_OneDrive_Reset.ps1
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
                                              (was C:\Users\<name>); several processes no longer break the start;
                                              exit 1 when OneDrive is not found (before: start without path); logging
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
	Write-SelfXLog 'OneDrive.exe was not found; nothing was reset.' Error
	exit 1
}
Write-SelfXLog "OneDrive: $oneDrive; $($running.Count) running process(es)."
if ($running.Count) { $running | Stop-Process -Force -ErrorAction SilentlyContinue }
$reset = Start-Process -FilePath $oneDrive -ArgumentList '/reset' -PassThru
# Wait only for the reset process (Start-Process -Wait would also wait for a OneDrive it starts again).
if ($reset.WaitForExit(120000)) { Write-SelfXLog 'OneDrive /reset finished.' } else { Write-SelfXLog 'OneDrive /reset still runs after 2 minutes.' Warning }
# Give the reset time to rebuild local state before starting background synchronization.
Start-Sleep -Seconds 30
if (-not (Get-Process -Name OneDrive -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session })) {
	Start-Process -FilePath $oneDrive -ArgumentList '/background'
	Write-SelfXLog 'OneDrive started again (/background).'
} else {
	Write-SelfXLog 'OneDrive was already started again by the reset.'
}
exit 0
