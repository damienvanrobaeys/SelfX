<#
.SYNOPSIS
    Empty the recycle bin and remove files from the user temporary folder.

.DESCRIPTION
    Runs as the signed-in user from the SelfX GUI. Empties the recycle bin of the user without
    confirmation, then removes the items under the current TEMP directory. Deleted files cannot
    be restored from the recycle bin; temporary files still needed by running applications may
    be lost. Files in use or inaccessible to the user remain (normal for TEMP) and are only
    counted in the log. Does not close applications or restart Windows.
    Logs to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1).
    Exit 0 = done (also when files in use remain).

.NOTES
    Name    : SelfX_Device_DeviceSlow.ps1
    Package : SelfX Service
    Context : User
    Version : 2.6.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2022-10-04  Damien Van Robaeys   Initial version (SelfX Standard / SelfX Admin)
    2.0.0    2026-10-28  Wolfgang Baeck       Moved to SelfX Service, no functional change
    2.2.0    2026-10-28  Wolfgang Baeck       Added description, history and comments
    2.6.0    2026-11-06  Wolfgang Baeck       Logging (SelfXLog.ps1); an empty recycle bin is no error any more
                                              (Clear-RecycleBin failed then); freed space is logged
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }
trap { Write-SelfXLog "Failed: $($_.Exception.Message)" Error; break }

# Recycle-bin removal is permanent and intentionally skips interactive confirmation. Windows PowerShell
# reports an error for an empty recycle bin, which is not a failure of this action.
try {
	Clear-RecycleBin -Force -Confirm:$false -ErrorAction Stop
	Write-SelfXLog 'Recycle bin emptied.'
} catch {
	Write-SelfXLog "Recycle bin: $($_.Exception.Message) (empty or not accessible)."
}

# Locked or inaccessible temporary files remain; this is expected while applications are running.
$removed = 0; $kept = 0; $bytes = 0
foreach ($item in @(Get-ChildItem -LiteralPath $env:TEMP -Force -ErrorAction SilentlyContinue)) {
	$size = 0
	if (-not $item.PSIsContainer) { $size = $item.Length }
	try {
		Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
		$removed++
		$bytes += $size
	} catch { $kept++ }
}
Write-SelfXLog ("TEMP: {0} item(s) removed (files at the top level: {1:N1} MB), {2} item(s) in use or not accessible." -f $removed, ($bytes / 1MB), $kept)
exit 0
