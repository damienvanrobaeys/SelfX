<#
.SYNOPSIS
    Force-restart the Intune Management Extension service.

.DESCRIPTION
    Runs non-interactively as LOCAL SYSTEM through the local SelfX service and named pipe
    "SelfX.Service". Force-restarts IntuneManagementExtension; dependent services can be
    affected by the forced stop. After the start the extension checks in with Intune again
    (Win32 apps, scripts, remediations). Running app installations and scripts handled by the
    extension may be interrupted. Does not restart Windows or the SelfX service.
    Logs to ProgramData\SelfX\Logs (SelfXLog.ps1).
    Exit 0 = the service runs again; exit 1 = missing service or restart failure.

.NOTES
    Name    : SelfX_Intune_RestartService.ps1
    Package : SelfX Service
    Context : System
    Version : 2.6.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2022-10-04  Damien Van Robaeys   Initial version (SelfX Standard / SelfX Admin)
    2.0.0    2026-10-28  Wolfgang Baeck       Runs as SYSTEM through the SelfX service
    2.2.0    2026-10-28  Wolfgang Baeck       Added description, history and comments
    2.6.0    2026-11-06  Wolfgang Baeck       Logging (SelfXLog.ps1); checks that the service runs again
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }
trap { Write-SelfXLog "Failed: $($_.Exception.Message)" Error; break }

Write-SelfXLog "IntuneManagementExtension before the restart: $((Get-Service -Name IntuneManagementExtension -ErrorAction Stop).Status)"
# Force permits stopping dependent services; failures must reach the service caller.
Restart-Service -Name IntuneManagementExtension -Force -ErrorAction Stop
$status = (Get-Service -Name IntuneManagementExtension -ErrorAction Stop).Status
Write-SelfXLog "IntuneManagementExtension after the restart: $status"
Write-Output "IntuneManagementExtension: $status"
if ("$status" -ne 'Running') { exit 1 }
exit 0
