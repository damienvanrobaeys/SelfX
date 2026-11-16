<#
.SYNOPSIS
    Close Firefox and remove selected cache and site data from its profiles.

.DESCRIPTION
    Force-stops accessible firefox processes and waits two seconds, then visits every profile
    directory under LOCALAPPDATA\Mozilla\Firefox\Profiles and APPDATA\Mozilla\Firefox\Profiles.
    Removes selected cache folders, cookies.sqlite and web-storage databases as the signed-in
    user from the SelfX GUI. Firefox windows close and unsaved browser work may be lost;
    deleted cookies and site data can require signing in again. Items that cannot be removed
    are logged; the action continues with the next item.
    Logs to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1).
    Exit 0 = done (also when Firefox is not installed); exit 1 = at least one item could not be removed.

.NOTES
    Name    : SelfX_Browser_ClearFirefoxCache.ps1
    Package : SelfX Service
    Context : User
    Version : 2.6.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2022-10-04  Damien Van Robaeys   Initial version (SelfX Standard / SelfX Admin)
    2.0.0    2026-10-28  Wolfgang Baeck       Checks all Firefox profiles under LOCALAPPDATA and APPDATA
    2.2.0    2026-10-28  Wolfgang Baeck       Added description, history and comments
    2.6.0    2026-11-06  Wolfgang Baeck       Logging (SelfXLog.ps1); failed removals are reported (exit 1)
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }
trap { Write-SelfXLog "Failed: $($_.Exception.Message)" Error; break }

# Release Firefox file handles before removing profile databases and caches.
$processes = @(Get-Process -Name firefox -ErrorAction SilentlyContinue)
$processes | Stop-Process -Force -ErrorAction SilentlyContinue
Write-SelfXLog "Closed $($processes.Count) Firefox process(es)."
Start-Sleep -Seconds 2

$possibleCachePaths = @('cache', 'cache2\entries', 'startupCache', 'thumbnails', 'cookies.sqlite', 'webappsstore.sqlite', 'chromeappstore.sqlite')
# Firefox separates local caches and roaming profile data, so inspect both roots.
$profileRoots = @(
	(Join-Path $env:LOCALAPPDATA 'Mozilla\Firefox\Profiles'),
	(Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles')
)
$failed = 0
$profiles = 0
foreach ($profileRoot in $profileRoots) {
	if (-not (Test-Path -LiteralPath $profileRoot)) { continue }
	foreach ($firefoxProfile in (Get-ChildItem -LiteralPath $profileRoot -Directory -ErrorAction SilentlyContinue)) {
		$profiles++
		foreach ($cachePath in $possibleCachePaths) {
			$path = Join-Path $firefoxProfile.FullName $cachePath
			if (-not (Test-Path -LiteralPath $path)) { continue }
			try {
				Remove-Item -LiteralPath $path -Force -Recurse -ErrorAction Stop
				Write-SelfXLog "Removed $($firefoxProfile.Name)\$cachePath."
			} catch {
				$failed++
				Write-SelfXLog "Could not remove $($firefoxProfile.Name)\$cachePath : $($_.Exception.Message)" Warning
			}
		}
	}
}
Write-SelfXLog "Finished: $profiles profile folder(s), $failed item(s) not removed."
if ($failed) { exit 1 }
exit 0
