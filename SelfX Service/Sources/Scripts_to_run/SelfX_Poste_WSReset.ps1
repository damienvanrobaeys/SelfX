<#
.SYNOPSIS
    Start the Windows Microsoft Store cache-reset utility.

.DESCRIPTION
    Runs as the signed-in user from the SelfX GUI and launches wsreset.exe to reset the
    Microsoft Store cache. The utility may display a console window and opens Microsoft Store
    when it is finished. The script does not wait for the reset. Does not uninstall Store
    applications or restart Windows.
    Logs to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1).
    Exit 0 = wsreset started; exit 1 = wsreset.exe not found or not started.

.NOTES
    Name    : SelfX_Poste_WSReset.ps1
    Package : SelfX Service
    Context : User
    Version : 2.6.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2022-10-04  Damien Van Robaeys   Initial version (SelfX Standard / SelfX Admin)
    2.0.0    2026-10-28  Wolfgang Baeck       Moved to SelfX Service
    2.2.0    2026-10-28  Wolfgang Baeck       Added description, history and comments
    2.6.0    2026-11-06  Wolfgang Baeck       Full path of wsreset.exe; logging (SelfXLog.ps1)
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }

try {
	# Launch asynchronously; the utility window belongs to the interactive user session.
	Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\wsreset.exe') -ErrorAction Stop
	Write-SelfXLog 'wsreset.exe started.'
	exit 0
} catch {
	Write-SelfXLog "wsreset.exe could not be started: $($_.Exception.Message)" Error
	exit 1
}
