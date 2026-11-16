<#
.SYNOPSIS
    Start OneDrive when it is not running.

.DESCRIPTION
    Runs as the signed-in user from the SelfX GUI. Finds OneDrive.exe in LOCALAPPDATA\Microsoft\
    OneDrive (per-user install) or under Program Files (machine-wide install) and starts it when
    no OneDrive process of the user's session is running. Starting OneDrive resumes syncing and
    network traffic. Does not reset its state or delete files.
    Logs to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1).
    Exit 0 = OneDrive runs; exit 1 = OneDrive not found.

.NOTES
    Name    : SelfX_OneDrive_Run.ps1
    Package : SelfX Service
    Context : User
    Version : 2.6.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2022-10-04  Damien Van Robaeys   Initial version (SelfX Standard / SelfX Admin)
    2.0.0    2026-10-28  Wolfgang Baeck       Moved to SelfX Service
    2.2.0    2026-10-28  Wolfgang Baeck       Added description, history and comments
    2.6.0    2026-11-06  Wolfgang Baeck       Path from LOCALAPPDATA or Program Files (was C:\Users\<USERNAME>, wrong for
                                              Entra ID profiles); no second start when OneDrive runs; logging
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }
trap { Write-SelfXLog "Failed: $($_.Exception.Message)" Error; break }

$session = (Get-Process -Id $PID).SessionId
if (Get-Process -Name OneDrive -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session }) {
	Write-SelfXLog 'OneDrive is already running.'
	exit 0
}
$oneDrive = @(
	(Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'),
	(Join-Path $env:ProgramFiles 'Microsoft OneDrive\OneDrive.exe'),
	(Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive\OneDrive.exe')) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $oneDrive) {
	Write-SelfXLog 'OneDrive.exe was not found.' Error
	exit 1
}
Start-Process -FilePath $oneDrive
Write-SelfXLog "OneDrive started ($oneDrive)."
exit 0
