<#
.SYNOPSIS
    Close Chrome and remove selected browsing data from its Default profile.

.DESCRIPTION
    Force-stops accessible chrome processes and waits two seconds before deleting selected cache,
    cookies, history and web-data files under LOCALAPPDATA\Google\Chrome\User Data\Default.
    Runs as the signed-in user from the SelfX GUI; other Chrome profiles are not cleared.
    Open Chrome windows close without saving session state; cookies and local browsing data
    are permanently removed, which can sign the user out of websites. Items that cannot be
    removed (for example still locked) are logged; the action continues with the next item.
    Logs to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1).
    Exit 0 = done (also when Chrome is not installed); exit 1 = at least one item could not be removed.

.NOTES
    Name    : SelfX_Browser_ClearChromeCache.ps1
    Package : SelfX Service
    Context : User
    Version : 2.6.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2022-10-04  Damien Van Robaeys   Initial version (SelfX Standard / SelfX Admin)
    2.0.0    2026-10-28  Wolfgang Baeck       Uses LOCALAPPDATA, closes Chrome and clears additional Default-profile data
    2.2.0    2026-10-28  Wolfgang Baeck       Added description, history and comments
    2.6.0    2026-11-06  Wolfgang Baeck       Logging (SelfXLog.ps1); failed removals are reported (exit 1)
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }
trap { Write-SelfXLog "Failed: $($_.Exception.Message)" Error; break }

# Close Chrome first so open database and cache handles can be released.
$processes = @(Get-Process -Name chrome -ErrorAction SilentlyContinue)
$processes | Stop-Process -Force -ErrorAction SilentlyContinue
Write-SelfXLog "Closed $($processes.Count) Chrome process(es)."
Start-Sleep -Seconds 2

$chromeAppData = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default'
$failed = 0
if (Test-Path -LiteralPath $chromeAppData) {
	$possibleCachePaths = @('Cache', 'Cache2\entries', 'Code Cache', 'GPUCache', 'Cookies', 'Network\Cookies', 'History', 'Top Sites',
		'Visited Links', 'Web Data', 'Media Cache', 'Cookies-Journal', 'ChromeDWriteFontCache')
	foreach ($cachePath in $possibleCachePaths) {
		$path = Join-Path $chromeAppData $cachePath
		if (-not (Test-Path -LiteralPath $path)) { continue }
		try {
			Remove-Item -LiteralPath $path -Force -Recurse -ErrorAction Stop
			Write-SelfXLog "Removed $cachePath."
		} catch {
			$failed++
			Write-SelfXLog "Could not remove $cachePath : $($_.Exception.Message)" Warning
		}
	}
} else {
	Write-SelfXLog "No Chrome Default profile found ($chromeAppData)."
}
Write-SelfXLog "Finished, $failed item(s) not removed."
if ($failed) { exit 1 }
exit 0
