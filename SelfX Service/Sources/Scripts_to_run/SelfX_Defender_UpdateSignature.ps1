<#
.SYNOPSIS
    Update the Microsoft Defender security intelligence (signatures).

.DESCRIPTION
    Runs non-interactively as LOCAL SYSTEM through the local SelfX service and named pipe
    "SelfX.Service" when the user clicks the remediation button of the Defender or Compliance
    status row. Runs Update-MpSignature with the update sources configured by policy
    (WSUS / Microsoft Update / MMPC / file share). Outdated signatures after a longer absence
    are a frequent cause of a non-compliant device.
    Needs a connection to a configured update source; offline the update fails with exit 1.
    Does not restart Windows, sign out the user or change Defender settings.
    Logs to ProgramData\SelfX\Logs (SelfXLog.ps1).
    Exit 0 = signatures updated (or already current); exit 1 = update failed.

.NOTES
    Name    : SelfX_Defender_UpdateSignature.ps1
    Package : SelfX Service
    Context : System
    Version : 2.6.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.3.4    2026-10-29  Wolfgang Baeck       Initial version: Defender signature update remediation
    2.6.0    2026-11-06  Wolfgang Baeck       Logging (SelfXLog.ps1)
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }

$ErrorActionPreference = 'Stop'
try {
    $before = (Get-MpComputerStatus).AntivirusSignatureVersion
    Write-SelfXLog "Signature version before the update: $before"
    # Uses the sources and order defined by Defender policy; no source is forced here.
    Update-MpSignature
    $after = Get-MpComputerStatus
    $text = "Defender signatures: {0} -> {1} (last update {2})" -f $before, $after.AntivirusSignatureVersion, $after.AntivirusSignatureLastUpdated
    Write-SelfXLog $text
    Write-Output $text
    exit 0
} catch {
    Write-SelfXLog "Defender signature update failed: $($_.Exception.Message)" Error
    Write-Output "Defender signature update failed: $($_.Exception.Message)"
    exit 1
}
