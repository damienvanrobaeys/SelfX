<#
.SYNOPSIS
    Clear the local Windows DNS client cache.

.DESCRIPTION
    Calls Clear-DnsClientCache as the signed-in user from the SelfX GUI (works without
    administrator rights). Clears the machine DNS client resolver cache, not browser caches or
    DNS server records. Subsequent name lookups must be resolved again; existing network
    adapters and applications are not restarted.
    Logs to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1).
    Exit 0 = cache cleared; exit 1 = the cmdlet failed.

.NOTES
    Name    : SelfX_Device_ClearCache.ps1
    Package : SelfX Service
    Context : User
    Version : 2.6.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2022-10-04  Damien Van Robaeys   Initial version (SelfX Standard / SelfX Admin)
    2.0.0    2026-10-28  Wolfgang Baeck       Moved to SelfX Service, no functional change
    2.2.0    2026-10-28  Wolfgang Baeck       Added description, history and comments
    2.6.0    2026-11-06  Wolfgang Baeck       Logging (SelfXLog.ps1) and exit code
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }

try {
	# Remove cached DNS answers so subsequent lookups can retrieve current records.
	Clear-DnsClientCache -ErrorAction Stop
	Write-SelfXLog 'DNS client cache cleared.'
	exit 0
} catch {
	Write-SelfXLog "Could not clear the DNS client cache: $($_.Exception.Message)" Error
	exit 1
}
