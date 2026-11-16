<#
.SYNOPSIS
    Provide GUI helpers for requests to the local SelfX Windows service.

.DESCRIPTION
    Loaded by the SelfX GUI and the tray icon in the signed-in user session; defining these
    functions alone performs no action. Uses the local named pipe "SelfX.Service" for PING,
    RUN, HEALTH and STATUS requests. STATUS returns the status cache of the background checks
    without running anything.
    RUN asks the service to launch a catalog-approved System script as LOCAL SYSTEM; its
    side effects depend on the selected script. The client itself does not elevate or edit
    files. A connection timeout limits connection attempts, not the synchronous response
    read; execution timeouts are enforced by the service. Maps DONE 0 to Success and other
    DONE codes to Failed, preserving the child exit code; Busy, Timeout, Unavailable and
    Error results have no child exit code. Test-SelfXService returns a Boolean.

.NOTES
    Name    : SelfXServiceClient.ps1
    Package : SelfX Service
    Context : GUI helper
    Version : 2.6.1

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.0.0    2026-10-28  Wolfgang Baeck       Initial version for SelfX Service
    2.2.0    2026-10-28  Wolfgang Baeck       Added description, history and comments
    2.3.0    2026-10-28  Wolfgang Baeck       Validate and decode fixed HEALTH responses
    2.3.1    2026-10-28  Wolfgang Baeck       Reject invalid remediation filenames in status responses
    2.3.2    2026-10-28  Wolfgang Baeck       Optional single-check health request
    2.3.3    2026-10-29  Wolfgang Baeck       Accept PendingReboot and Updates results
    2.3.4    2026-10-29  Wolfgang Baeck       Accept the Pending (warning) status
    2.5.0    2026-11-04  Wolfgang Baeck       STATUS request (status cache of the background checks); fix: a HEALTH
                                              answer was rejected in Windows PowerShell 5.1 ($Matches after -notmatch
                                              and a JSON array returned as one object)
    2.5.3    2026-11-04  Wolfgang Baeck       STATUS time is returned in UTC; the GUI converts it to the time zone of the user;
                                              Start-SelfXHiddenPowerShell starts scripts without any console window
    2.6.1    2026-11-06  Wolfgang Baeck       Start-SelfXHiddenPowerShell -PassThru returns the process (running state of
                                              user actions in the window)
#>

$Script:SelfXDefaultPipeName = 'SelfX.Service'

function Start-SelfXHiddenPowerShell {
	# Starts a PowerShell script in the user context without a console window. CREATE_NO_WINDOW
	# (CreateNoWindow) creates no console at all, so nothing flashes and Windows Terminal (default
	# terminal on Windows 11) is not opened; -WindowStyle Hidden alone shows the console briefly.
	# -PassThru returns the process (the caller watches HasExited / ExitCode and disposes it).
	param(
		[Parameter(Mandatory = $true)][string]$Path,
		[string]$Arguments = '',
		[string]$WorkingDirectory = $env:SystemRoot,
		[switch]$PassThru
	)
	$start = New-Object System.Diagnostics.ProcessStartInfo
	$start.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
	$start.Arguments = ("-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Path`" $Arguments").TrimEnd()
	$start.WorkingDirectory = $WorkingDirectory
	$start.UseShellExecute = $false
	$start.CreateNoWindow = $true
	$start.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
	$process = [System.Diagnostics.Process]::Start($start)
	if ($PassThru) { return $process }
	if ($process) { $process.Dispose() }
}

function Invoke-SelfXServiceRequest {
	param(
		[Parameter(Mandatory = $true)][string]$Request,
		[string]$PipeName = $Script:SelfXDefaultPipeName,
		[int]$ConnectTimeoutMs = 3000
	)
	# Identification lets the service identify the caller without granting impersonation rights.
	$pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', $PipeName, [System.IO.Pipes.PipeDirection]::InOut,
		[System.IO.Pipes.PipeOptions]::None, [System.Security.Principal.TokenImpersonationLevel]::Identification)
	try {
		$pipe.Connect($ConnectTimeoutMs)
		# A BOM-free UTF-8 line matches the service protocol; flush before waiting for a reply.
		$encoding = New-Object System.Text.UTF8Encoding($false)
		$writer = New-Object System.IO.StreamWriter($pipe, $encoding, 1024, $true)
		$writer.AutoFlush = $true
		$reader = New-Object System.IO.StreamReader($pipe, $encoding, $false, 1024, $true)
		$writer.WriteLine($Request)
		# ConnectTimeoutMs does not limit this blocking read; RUN is bounded by the service.
		return $reader.ReadLine()
	}
	finally {
		$pipe.Dispose()
	}
}

function Test-SelfXService {
	param([string]$PipeName = $Script:SelfXDefaultPipeName)
	try {
		return ((Invoke-SelfXServiceRequest -Request 'PING' -PipeName $PipeName -ConnectTimeoutMs 1000) -like 'PONG*')
	}
	catch {
		return $false
	}
}

function Invoke-SelfXSystemAction {
	param(
		[Parameter(Mandatory = $true)][string]$Script,
		[string]$PipeName = $Script:SelfXDefaultPipeName
	)
	try {
		$response = Invoke-SelfXServiceRequest -Request "RUN $Script" -PipeName $PipeName
	}

	catch {
		return [pscustomobject]@{ Status = 'Unavailable'; ExitCode = $null; Message = $_.Exception.Message }
	}

	# Only DONE carries a process exit code; transport and scheduling failures do not.
	if ($response -match '^DONE (-?\d+)$') {
		$exitCode = [int]$Matches[1]
		$status = if ($exitCode -eq 0) { 'Success' } else { 'Failed' }
		return [pscustomobject]@{ Status = $status; ExitCode = $exitCode; Message = $response }
	}
	switch -Regex ($response) {
		'^BUSY'    { return [pscustomobject]@{ Status = 'Busy'; ExitCode = $null; Message = $response } }
		'^TIMEOUT' { return [pscustomobject]@{ Status = 'Timeout'; ExitCode = $null; Message = $response } }
		default    { return [pscustomobject]@{ Status = 'Error'; ExitCode = $null; Message = "$response" } }
	}
}

function Get-SelfXServiceHealthReport {
    # HEALTH accepts only an optional whitelisted check Id and a base64 result name;
    # all probes and scripts come from the protected installation.
    param(
        [ValidateSet('', 'IME', 'Defender', 'Compliance', 'Applications', 'Disk', 'BitLocker', 'PendingReboot', 'Updates', 'Service', 'Custom')]
        [string]$Id = '',
        [ValidateLength(0, 200)][string]$Name = ''
    )
    $request = 'HEALTH'
    if ($Id) {
        $request += " $Id"
        if ($Name) {
            $bytes = [Text.Encoding]::UTF8.GetBytes($Name)
            if ($bytes.Length -gt 297) { throw 'Health check name is too long.' }
            $request += ' ' + [Convert]::ToBase64String($bytes)
        }
    }
    $response = Invoke-SelfXServiceRequest -Request $request
    # -match (not -notmatch) fills $Matches with the base64 group used below.
    if (-not ($response -match '^HEALTH ([A-Za-z0-9+/=]+)$')) { throw "Health request failed: $response" }
    if ($response.Length -gt 30000) { throw 'Health response exceeds size limit.' }
    $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Matches[1]))
    return (ConvertFrom-SelfXHealthJson -Json $json)
}

function ConvertFrom-SelfXHealthJson {
    # Validates the health items of the service: known ids and states, bounded count and safe remediation names.
    param([Parameter(Mandatory = $true)][string]$Json)
    # Windows PowerShell 5.1 returns a JSON array as one object; assigning it first unrolls the items.
    $parsed = ConvertFrom-Json -InputObject $Json -ErrorAction Stop
    $items = @($parsed)
    if (-not $items.Count -or $items.Count -gt 128) { throw 'Invalid health result count.' }
    foreach ($item in $items) {
        if ($item.Status -notin @('OK','Pending','Error','Unknown') -or
            $item.Id -notin @('IME','Defender','Compliance','Applications','Disk','BitLocker','PendingReboot','Updates','Service','Custom','Collection') -or
            $null -eq $item.Detail) { throw 'Invalid health result.' }
        if ($item.Remediation -and ("$($item.Remediation)" -notmatch '^[A-Za-z0-9_-][A-Za-z0-9_.-]{0,90}\.ps1$' -or
            "$($item.Remediation)".Contains('..'))) { throw 'Invalid health remediation filename.' }
    }
    return $items
}

function Get-SelfXServiceStatusCache {
    # Reads the status cache of the service (STATUS): no check is run, so the answer is immediate.
    # Returns CollectedAt (UTC; the GUI shows it in the time zone of the user, or $null when no check
    # has finished yet), IntervalMinutes,
    # State (Active, Battery or Disabled) and the validated Results.
    param([string]$PipeName = $Script:SelfXDefaultPipeName, [int]$ConnectTimeoutMs = 2000)
    $response = Invoke-SelfXServiceRequest -Request 'STATUS' -PipeName $PipeName -ConnectTimeoutMs $ConnectTimeoutMs
    # -match (not -notmatch) fills $Matches with the groups used below.
    if ("$response".Length -gt 100000 -or
        -not ("$response" -match '^STATUS (NONE|\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ) (\d{1,4}) (Active|Battery|Disabled) ([A-Za-z0-9+/=]+|-)$')) {
        throw "Status request failed: $response"
    }
    # Groups: 1 = time (UTC) or NONE, 2 = interval, 3 = background state, 4 = base64 JSON or "-".
    $time = $Matches[1]; $interval = [int]$Matches[2]; $state = $Matches[3]; $data = $Matches[4]
    $collected = $null
    $results = @()
    if ($time -ne 'NONE' -and $data -ne '-') {
        $collected = [datetime]::ParseExact($time, "yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]'AssumeUniversal,AdjustToUniversal')
        $results = @(ConvertFrom-SelfXHealthJson -Json ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($data))))
    }
    return [pscustomobject]@{ CollectedAt = $collected; IntervalMinutes = $interval; State = $state; Results = $results }
}
