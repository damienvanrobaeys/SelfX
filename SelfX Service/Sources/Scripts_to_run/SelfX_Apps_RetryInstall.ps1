<#
.SYNOPSIS
    Retry the failed Intune app installations now.

.DESCRIPTION
    Runs non-interactively as LOCAL SYSTEM through the local SelfX service and named pipe
    "SelfX.Service" when the user clicks the remediation button of the "Company apps" status row
    (Health_Config.xml, Remediation Id="Applications").

    The Intune Management Extension (IME) retries a failed Win32 app only after its retry
    schedule (by default after 24 hours). For every app whose last result in the local IME cache
    is an error (EnforcementState 5000-5999) the script removes this cached result and the retry
    schedule entries (GRS) of the app, then restarts the IntuneManagementExtension service. The
    IME then checks in with Intune and installs the app again within a few minutes (progress in
    the Company Portal under Downloads and updates). Without failed apps only the service is
    restarted, which also starts a new app check-in.
    Only the IME cache under HKLM\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps is
    changed; no app is uninstalled and Windows is not restarted. When the installation fails
    again, the error is a problem of the app or its assignment: the support team sees it in Intune.
    Logs to ProgramData\SelfX\Logs (SelfXLog.ps1).
    Exit 0 = IME restarted (retry started); exit 1 = error.

.NOTES
    Name    : SelfX_Apps_RetryInstall.ps1
    Package : SelfX Service
    Context : System
    Version : 2.6.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.6.0    2026-11-06  Wolfgang Baeck       Initial version: retry failed Win32 app installations (Applications row)
#>

# Removes the cached result and the retry schedule (GRS) of one failed app. Returns the number of removed keys.
function Reset-SelfXFailedApp {
	param([Parameter(Mandatory = $true)]$Report)
	$id = "$($Report.Id)"
	if ($id -notmatch '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') { throw "Invalid app id '$id'." }
	# Never delete anything outside the IME Win32Apps cache.
	foreach ($path in @($Report.AppKey, $Report.UserKey)) {
		if ("$path" -notmatch '\\SOFTWARE\\Microsoft\\IntuneManagementExtension\\Win32Apps\\') { throw "Unexpected registry path '$path'." }
	}
	if ("$($Report.AppKey)" -notmatch [regex]::Escape($id)) { throw "Registry path '$($Report.AppKey)' does not belong to app $id." }
	$removed = 0
	if (Test-Path -LiteralPath $Report.AppKey) { Remove-Item -LiteralPath $Report.AppKey -Recurse -Force -ErrorAction Stop; $removed++ }
	$grs = Join-Path $Report.UserKey 'GRS'
	if (Test-Path -LiteralPath $grs) {
		foreach ($entry in @(Get-ChildItem -LiteralPath $grs -ErrorAction Stop)) {
			$names = @((Get-ItemProperty -LiteralPath $entry.PSPath -ErrorAction SilentlyContinue).PSObject.Properties | ForEach-Object { $_.Name })
			if ($names | Where-Object { $_ -like "*$id*" }) { Remove-Item -LiteralPath $entry.PSPath -Recurse -Force -ErrorAction Stop; $removed++ }
		}
	}
	return $removed
}

# Dot-sourcing (tests) only defines the function; the service runs the script with -File.
if ($MyInvocation.InvocationName -ne '.') {
	$root = Split-Path -Parent $PSScriptRoot
	# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
	$SelfXLogScript = Join-Path $root 'SelfXLog.ps1'
	if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
	else { function Write-SelfXLog { param($Message, $Level) } }
	try {
		# The cache reader and the name lookup are the same as for the status row.
		. (Join-Path $root 'HealthStatus.ps1')
		$failed = @(Get-SelfXAppReports | Where-Object { $state = 0; [int]::TryParse("$($_.State)", [ref]$state) -and $state -ge 5000 -and $state -lt 6000 })
		$names = Get-SelfXImeAppNames -Ids @($failed | ForEach-Object { $_.Id })
		$reset = @()
		foreach ($report in $failed) {
			$name = $report.Name
			if (-not $name -and $names.ContainsKey("$($report.Id)".ToLowerInvariant())) { $name = $names["$($report.Id)".ToLowerInvariant()] }
			if (-not $name) { $name = $report.Id }
			$keys = Reset-SelfXFailedApp -Report $report
			Write-SelfXLog ("Reset failed app {0} ({1}, {2}): {3} registry key(s) removed." -f $name, $report.Id, (Format-SelfXAppError $report.ErrorCode), $keys)
			$reset += $name
		}
		Restart-Service -Name IntuneManagementExtension -Force -ErrorAction Stop
		$status = (Get-Service -Name IntuneManagementExtension -ErrorAction Stop).Status
		Write-SelfXLog "IntuneManagementExtension restarted: $status"
		if ($reset.Count) { $text = "Installation retried for $($reset.Count) app(s): $($reset -join ', '). The apps are installed again within a few minutes." }
		else { $text = 'No failed app installation in the local cache; the app check-in was started again.' }
		Write-SelfXLog $text
		Write-Output $text
		if ("$status" -ne 'Running') { exit 1 }
		exit 0
	} catch {
		Write-SelfXLog "Retry of the app installations failed: $($_.Exception.Message)" Error
		Write-Output "Retry of the app installations failed: $($_.Exception.Message)"
		exit 1
	}
}
