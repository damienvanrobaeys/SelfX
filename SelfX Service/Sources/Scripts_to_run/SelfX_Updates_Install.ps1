<#
.SYNOPSIS
    Install the pending Windows updates now and start the update of the Microsoft Store apps.

.DESCRIPTION
    Runs non-interactively as LOCAL SYSTEM through the local SelfX service and named pipe
    "SelfX.Service" when the user clicks the remediation button of the "Updates to install" status
    row (Health_Config.xml, Remediation Id="Updates"). While it runs, the button in SelfX shows
    "Running..."; afterwards SelfX checks the whole device status again (updates, pending restart).

    1. Microsoft Store apps: starts the Store app update scan of the MDM bridge
       (MDM_EnterpriseModernAppManagement_AppManagement01.UpdateScanMethod) as SYSTEM. This also
       works when the Store app is blocked for users. The Store updates the apps in the background.
    2. Windows Update through the documented Windows Update Agent API: searches online at the update
       source configured by policy (Windows Update for Business / Intune update rings, WSUS or
       Microsoft Update), accepts the EULAs, downloads and installs all not-installed, not-hidden
       updates. Browse-only (optional) updates and updates that need user input are skipped, the same
       selection as the status check. When Windows Update itself is installing right now, the script
       waits for it (at most 10 minutes) and searches afterwards. Every update is logged with its
       result; the restart requirement comes from the installation result.

    Before 2.6.3 the installation was started with "UsoClient StartDownload / StartInstall". Windows 11
    24H2 no longer accepts these commands (error 0x80070057), so only a scan ran and nothing was
    installed; a restart that was already pending was even reported as "updates installed".

    Never restarts Windows and never signs out the user. When an update needs a restart, the
    "Restart pending" status row shows it; the user restarts with its button or himself.
    Logs to ProgramData\SelfX\Logs (SelfXLog.ps1).
    Output: one summary line. Exit 0 = all selected updates installed (or nothing to install);
    exit 1 = search, download or installation failed for at least one update.

.NOTES
    Name    : SelfX_Updates_Install.ps1
    Package : SelfX Service
    Context : System
    Version : 2.6.3

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.5.6    2026-11-05  Wolfgang Baeck       Initial version: install pending Windows updates, Store app update scan
    2.6.0    2026-11-06  Wolfgang Baeck       Windows Update orchestrator (UsoClient); logging
    2.6.3    2026-11-06  Wolfgang Baeck       Installation through the Windows Update Agent API again: UsoClient
                                              StartDownload / StartInstall fail on Windows 11 24H2 (0x80070057) and a
                                              pending restart was reported as installed; result logged per update
#>

# Microsoft Store apps: update scan of the MDM bridge (asynchronous).
function Start-SelfXStoreUpdate {
	try {
		$storeClass = Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' -ClassName 'MDM_EnterpriseModernAppManagement_AppManagement01' -ErrorAction Stop
		$scan = Invoke-CimMethod -InputObject $storeClass -MethodName 'UpdateScanMethod' -ErrorAction Stop
		if ($scan.ReturnValue -in @($null, 0)) { return [pscustomobject]@{ Ok = $true; Text = 'Store apps: update started' } }
		return [pscustomobject]@{ Ok = $false; Text = "Store apps: update scan returned $($scan.ReturnValue)" }
	} catch {
		return [pscustomobject]@{ Ok = $false; Text = "Store apps: not started ($($_.Exception.Message))" }
	}
}

# Empty update collection of the Windows Update Agent (replaced in tests).
function New-SelfXUpdateCollection { New-Object -ComObject Microsoft.Update.UpdateColl }

# Text of an OperationResultCode of the Windows Update Agent.
function Get-SelfXResultText {
	param([int]$Code)
	switch ($Code) { 0 { 'not started' } 1 { 'in progress' } 2 { 'installed' } 3 { 'installed with errors' } 4 { 'failed' } 5 { 'aborted' } default { "result $Code" } }
}

# Short name of an update for the log and the summary: KB number, otherwise the title.
function Get-SelfXUpdateName {
	param($Update)
	$kb = @($Update.KBArticleIDs) | Where-Object { $_ } | Select-Object -First 1
	if ($kb) { return "KB$kb" }
	return "$($Update.Title)"
}

# Searches, downloads and installs the updates. Session can be replaced (tests). Returns the summary.
function Install-SelfXWindowsUpdates {
	param(
		$Session = $null,
		[int]$BusyWaitSeconds = 600,
		[int]$PollSeconds = 15
	)
	if (-not $Session) {
		$Session = New-Object -ComObject Microsoft.Update.Session
		$Session.ClientApplicationID = 'SelfX'
	}
	$installer = $Session.CreateUpdateInstaller()
	# Windows Update (or another tool) installs right now: wait for it, then search again.
	for ($waited = 0; $installer.IsBusy -and $waited -lt $BusyWaitSeconds; $waited += $PollSeconds) {
		if ($waited -eq 0) { Write-SelfXLog 'Windows Update is installing right now; waiting until it has finished.' }
		Start-Sleep -Seconds $PollSeconds
	}
	if ($installer.IsBusy) { throw "Windows Update is still busy after $BusyWaitSeconds seconds; try again later." }

	$searcher = $Session.CreateUpdateSearcher()
	$searcher.Online = $true
	Write-SelfXLog 'Searching for updates (online, update source of the device policy).'
	$result = $searcher.Search('IsInstalled=0 and IsHidden=0')
	# OperationResultCode: 2 = Succeeded, 3 = SucceededWithErrors.
	if ($result.ResultCode -notin @(2, 3)) { throw "search failed ($(Get-SelfXResultText $result.ResultCode))" }

	$updates = New-SelfXUpdateCollection
	$skipped = 0
	foreach ($update in @($result.Updates)) {
		if ($update.BrowseOnly -or $update.InstallationBehavior.CanRequestUserInput) {
			$skipped++
			Write-SelfXLog "Skipped (optional or needs user input): $($update.Title)"
			continue
		}
		if (-not $update.EulaAccepted) { $update.AcceptEula() }
		[void]$updates.Add($update)
		Write-SelfXLog "To install: $($update.Title)"
	}
	if ($updates.Count -eq 0) {
		$text = 'Windows Update: no updates to install'
		if ($skipped) { $text += " ($skipped optional update(s) skipped)" }
		return [pscustomobject]@{ Ok = $true; Text = $text }
	}

	$downloader = $Session.CreateUpdateDownloader()
	$downloader.Updates = $updates
	$download = $downloader.Download()
	Write-SelfXLog "Download: $(Get-SelfXResultText $download.ResultCode)."
	$toInstall = New-SelfXUpdateCollection
	$notDownloaded = @()
	for ($i = 0; $i -lt $updates.Count; $i++) {
		$update = $updates.Item($i)
		if ($update.IsDownloaded) { [void]$toInstall.Add($update) }
		else {
			$notDownloaded += Get-SelfXUpdateName $update
			Write-SelfXLog ("Not downloaded: {0} (HRESULT 0x{1:X8})" -f $update.Title, $download.GetUpdateResult($i).HResult) Warning
		}
	}
	if ($toInstall.Count -eq 0) { throw 'no update could be downloaded' }

	$installer = $Session.CreateUpdateInstaller()
	$installer.Updates = $toInstall
	# No user interface; a needed restart is only reported (RebootRequired), never started.
	try { $installer.ForceQuiet = $true } catch { }
	$install = $installer.Install()
	$installed = @(); $failed = @()
	for ($i = 0; $i -lt $toInstall.Count; $i++) {
		$update = $toInstall.Item($i)
		$updateResult = $install.GetUpdateResult($i)
		if ($updateResult.ResultCode -in @(2, 3)) {
			$installed += Get-SelfXUpdateName $update
			Write-SelfXLog ("Installed: {0}{1}" -f $update.Title, $(if ($updateResult.RebootRequired) { ' (restart required)' } else { '' }))
		} else {
			$failed += Get-SelfXUpdateName $update
			Write-SelfXLog ("Failed: {0} ({1}, HRESULT 0x{2:X8})" -f $update.Title, (Get-SelfXResultText $updateResult.ResultCode), $updateResult.HResult) Error
		}
	}
	$text = "Windows Update: $($installed.Count) of $($updates.Count) update(s) installed"
	if ($installed.Count) { $text += ' (' + ($installed -join ', ') + ')' }
	if ($failed.Count) { $text += '; failed: ' + ($failed -join ', ') }
	if ($notDownloaded.Count) { $text += '; not downloaded: ' + ($notDownloaded -join ', ') }
	if ($install.RebootRequired) { $text += '; restart required to complete' }
	return [pscustomobject]@{ Ok = (-not $failed.Count -and -not $notDownloaded.Count); Text = $text }
}

# Dot-sourcing (tests) only defines the functions; the service runs the script with -File.
if ($MyInvocation.InvocationName -ne '.') {
	# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
	$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
	if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
	else { function Write-SelfXLog { param($Message, $Level) } }

	$summary = New-Object System.Collections.Generic.List[string]
	$failed = $false
	$store = Start-SelfXStoreUpdate
	$summary.Add($store.Text)
	Write-SelfXLog $store.Text $(if ($store.Ok) { 'Info' } else { 'Warning' })
	try {
		$windows = Install-SelfXWindowsUpdates
		$summary.Add($windows.Text)
		Write-SelfXLog $windows.Text $(if ($windows.Ok) { 'Info' } else { 'Error' })
		if (-not $windows.Ok) { $failed = $true }
	} catch {
		$summary.Add("Windows Update failed: $($_.Exception.Message)")
		Write-SelfXLog "Windows Update failed: $($_.Exception.Message)" Error
		$failed = $true
	}
	Write-Output ($summary -join '. ')
	# The Store scan is optional (blocked Store, no MDM bridge): only Windows Update decides the result.
	if ($failed) { exit 1 }
	exit 0
}
