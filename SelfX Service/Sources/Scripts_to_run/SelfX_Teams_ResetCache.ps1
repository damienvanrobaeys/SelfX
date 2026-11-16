<#
.SYNOPSIS
    Close Teams, remove the classic and new Teams cache data and start Teams again.

.DESCRIPTION
    Runs as the signed-in user from the SelfX GUI. Closes the Teams processes of the user's
    session (new Teams ms-teams.exe and classic Teams.exe), waits until they have closed (at most
    15 seconds), removes selected cache folders under APPDATA\Microsoft\Teams (classic Teams) and
    the content of LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams (new
    Teams). Starts Teams again: the new Teams through its app ID, the classic Teams through its
    executable. Active calls and unsaved work end; caches are rebuilt and signing in again may be
    required. Items that cannot be removed are logged; the action continues.
    Logs to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1).
    Exit 0 = done; exit 1 = at least one cache item could not be removed.

.NOTES
    Name    : SelfX_Teams_ResetCache.ps1
    Package : SelfX Service
    Context : User
    Version : 2.6.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2022-10-04  Damien Van Robaeys   Initial version (SelfX Standard / SelfX Admin)
    2.0.0    2026-10-28  Wolfgang Baeck       New Teams cache, moved to SelfX Service
    2.2.0    2026-10-28  Wolfgang Baeck       Added description, history and comments
    2.6.0    2026-11-06  Wolfgang Baeck       Only Teams processes of the user (was every process named *teams*); new
                                              Teams is started through its app ID (several processes made the start
                                              fail) and also when it was not running; logging
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }
trap { Write-SelfXLog "Failed: $($_.Exception.Message)" Error; break }

$teamsClassicPath = Join-Path $env:APPDATA 'Microsoft\Teams'
$newTeamsCachePath = Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams'
$session = (Get-Process -Id $PID).SessionId
function Get-SelfXTeamsProcesses { @(Get-Process -Name 'ms-teams', 'msteams', 'Teams' -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session }) }

# Stop Teams before cleanup to reduce locked cache files and immediate cache rewrites.
$teams = Get-SelfXTeamsProcesses
$newTeams = [bool]($teams | Where-Object { $_.ProcessName -in @('ms-teams', 'msteams') })
$classicExe = $teams | Where-Object { $_.ProcessName -eq 'Teams' -and $_.Path } | Select-Object -First 1 -ExpandProperty Path
Write-SelfXLog "Closing $($teams.Count) Teams process(es)."
$teams | Stop-Process -Force -ErrorAction SilentlyContinue
for ($i = 0; $i -lt 15 -and (Get-SelfXTeamsProcesses).Count; $i++) { Start-Sleep -Seconds 1 }

$failed = 0
$items = @()
if (Test-Path -LiteralPath $teamsClassicPath) {
	$items += @(Get-ChildItem -LiteralPath $teamsClassicPath -Directory -Force |
		Where-Object { $_.Name -in @('application cache', 'blob storage', 'databases', 'GPUcache', 'IndexedDB', 'Local Storage', 'tmp') })
}
# New Teams stores its disposable cache separately from the classic desktop client.
if (Test-Path -LiteralPath $newTeamsCachePath) { $items += @(Get-ChildItem -LiteralPath $newTeamsCachePath -Force) }
foreach ($item in $items) {
	try { Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop }
	catch { $failed++; Write-SelfXLog "Could not remove $($item.FullName): $($_.Exception.Message)" Warning }
}
Write-SelfXLog "Cache: $($items.Count - $failed) of $($items.Count) item(s) removed."

if ($classicExe -and -not $newTeams) {
	Start-Process -FilePath $classicExe
	Write-SelfXLog "Classic Teams started again ($classicExe)."
} elseif ($newTeams -or (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Packages\MSTeams_8wekyb3d8bbwe'))) {
	# The new Teams is a packaged app: it is started through its app ID, not through its executable.
	Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList 'shell:AppsFolder\MSTeams_8wekyb3d8bbwe!MSTeams'
	Write-SelfXLog 'New Teams started again.'
}
if ($failed) { exit 1 }
exit 0
