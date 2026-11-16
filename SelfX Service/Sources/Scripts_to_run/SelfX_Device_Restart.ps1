<#
.SYNOPSIS
    Restart Windows after the user confirmed it, to complete a pending restart.

.DESCRIPTION
    Runs non-interactively as LOCAL SYSTEM through the local SelfX service and named pipe
    "SelfX.Service" when the user clicks the remediation button of the "Restart pending" status
    row (Health_Config.xml, Remediation Id="PendingReboot") and confirms the restart in SelfX.
    SelfX asks for the confirmation with its own warning (save your work) and never includes this
    repair in "Fix all problems".
    Starts "shutdown.exe /r /t <DelaySeconds>" (default 30 seconds) with the reason "Application:
    Maintenance (Planned)" and a comment; Windows shows a notification and then restarts. Open
    applications are closed, unsaved work is lost. When a shutdown or restart is already scheduled
    (exit code 1190), this is reported as success. The script itself returns at once.
    Logs to ProgramData\SelfX\Logs (SelfXLog.ps1).
    Exit 0 = restart scheduled; exit 1 = shutdown.exe failed.

.PARAMETER DelaySeconds
    Seconds until the restart (10-600, default 30).

.NOTES
    Name    : SelfX_Device_Restart.ps1
    Package : SelfX Service
    Context : System
    Version : 2.6.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.6.0    2026-11-06  Wolfgang Baeck       Initial version: restart for the "Restart pending" status row
#>

[CmdletBinding()]
param([ValidateRange(10, 600)][int]$DelaySeconds = 30)

# Schedules the restart with shutdown.exe. ShutdownExe can be replaced (tests use a non-existent path).
function Invoke-SelfXRestart {
	param(
		[string]$ShutdownExe = (Join-Path $env:SystemRoot 'System32\shutdown.exe'),
		[int]$DelaySeconds = 30
	)
	if (-not (Test-Path -LiteralPath $ShutdownExe -PathType Leaf)) { throw "shutdown.exe not found: $ShutdownExe" }
	$output = & $ShutdownExe /r /t $DelaySeconds /d p:4:1 /c 'SelfX: restart requested by the user to complete pending updates and changes.' 2>&1
	$code = $LASTEXITCODE
	# 1190 = ERROR_SHUTDOWN_IS_SCHEDULED: a restart or shutdown is already on its way.
	if ($code -eq 1190) { return 'A restart or shutdown is already scheduled.' }
	if ($code -ne 0) { throw "shutdown.exe returned $code. $output" }
	return "Windows restarts in $DelaySeconds seconds."
}

# Dot-sourcing (tests) only defines the function; the service runs the script with -File.
if ($MyInvocation.InvocationName -ne '.') {
	# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
	$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
	if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
	else { function Write-SelfXLog { param($Message, $Level) } }
	try {
		$text = Invoke-SelfXRestart -DelaySeconds $DelaySeconds
		Write-SelfXLog "Restart confirmed by the user: $text"
		Write-Output $text
		exit 0
	} catch {
		Write-SelfXLog "Restart failed: $($_.Exception.Message)" Error
		Write-Output "Restart failed: $($_.Exception.Message)"
		exit 1
	}
}
