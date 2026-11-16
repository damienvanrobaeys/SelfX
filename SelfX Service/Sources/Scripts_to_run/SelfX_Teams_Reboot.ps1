<#
.SYNOPSIS
    Close Microsoft Teams and start it again.

.DESCRIPTION
    Runs as the signed-in user from the SelfX GUI. Closes the Teams processes of the user's
    session: the new Teams (ms-teams.exe, Microsoft Store app MSTeams_8wekyb3d8bbwe) and the
    classic Teams (Teams.exe). Calls and unsaved Teams work end. Waits until Teams has closed
    (at most 15 seconds) and starts it again: the new Teams through its app ID (shell:AppsFolder),
    the classic Teams through its executable. Starts the new Teams also when Teams was not
    running. Does not clear Teams caches or restart Windows.
    Logs to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1).
    Exit 0 = Teams started again; exit 1 = error.

.NOTES
    Name    : SelfX_Teams_Reboot.ps1
    Package : SelfX Service
    Context : User
    Version : 2.6.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2022-10-04  Damien Van Robaeys   Initial version (SelfX Standard / SelfX Admin)
    2.0.0    2026-10-28  Wolfgang Baeck       Moved to SelfX Service
    2.2.0    2026-10-28  Wolfgang Baeck       Added description, history and comments
    2.6.0    2026-11-06  Wolfgang Baeck       Only Teams processes of the user (was every process named *teams*);
                                              new Teams is started through its app ID (several processes made the start
                                              fail); logging
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }
trap { Write-SelfXLog "Failed: $($_.Exception.Message)" Error; break }

$session = (Get-Process -Id $PID).SessionId
function Get-SelfXTeamsProcesses { @(Get-Process -Name 'ms-teams', 'msteams', 'Teams' -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session }) }

$teams = Get-SelfXTeamsProcesses
$newTeams = [bool]($teams | Where-Object { $_.ProcessName -in @('ms-teams', 'msteams') })
$classicPath = $teams | Where-Object { $_.ProcessName -eq 'Teams' -and $_.Path } | Select-Object -First 1 -ExpandProperty Path
Write-SelfXLog "Closing $($teams.Count) Teams process(es) (new Teams: $newTeams; classic: $([bool]$classicPath))."
$teams | Stop-Process -Force -ErrorAction SilentlyContinue
for ($i = 0; $i -lt 15 -and (Get-SelfXTeamsProcesses).Count; $i++) { Start-Sleep -Seconds 1 }

if ($classicPath -and -not $newTeams) {
	Start-Process -FilePath $classicPath
	Write-SelfXLog "Classic Teams started again ($classicPath)."
} else {
	# The new Teams is a packaged app: it is started through its app ID, not through its executable.
	Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList 'shell:AppsFolder\MSTeams_8wekyb3d8bbwe!MSTeams'
	Write-SelfXLog 'New Teams started again.'
}
exit 0
