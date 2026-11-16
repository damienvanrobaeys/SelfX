<#
.SYNOPSIS
    Collects read-only information about the device for the "System information" tab of SelfX.

.DESCRIPTION
    Gathers device, Windows, user/management and network details that the support desk usually asks for
    (computer name, serial number, OS build, Entra ID / Intune state, IP addresses, VPN, internet access, ...).
    The result is a list of objects with Category, Property and Value that the GUI shows grouped by category
    and that can be copied or exported as TXT, HTML, CSV or JSON.

    Labels are passed in with -Text (a hashtable built from the language file by Get-SelfXSystemInfoTexts).
    Missing labels fall back to the English defaults defined in this script, so the collector also works
    on its own.

    Based on the idea and data points of the "System Information Tool" by Jannik Reinhard
    (https://github.com/JayRHa/windows-system-information, MIT License, Copyright (c) 2026 Jannik Reinhard).

    This script only reads information. It does not change, restart or sign out anything.
    -IncludeHealth also requests the local service health report. Administrators may configure
    extension scripts for this report; they must be read-only. The built-in collector does not
    query Intune online. The only built-in network access is the optional TCP internet test.

.NOTES
    Name    : SystemInfo.ps1
    Package : SelfX Service
    Context : User (dot-sourced by Self_X.ps1 and SelfX_Tray.ps1, run in a background runspace)
    Version : 2.6.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.0.0    2026-10-28  Wolfgang Baeck       Initial version: System information tab
    2.2.0    2026-10-28  Wolfgang Baeck       Localized labels (-Text), header and comments
    2.3.0    2026-10-28  Wolfgang Baeck       Optional health report from the local service
    2.3.1    2026-10-28  Wolfgang Baeck       Preserve remediation mapping on appended status rows
    2.3.2    2026-10-28  Wolfgang Baeck       Check identity on status rows and single-check recheck
    2.3.3    2026-10-29  Wolfgang Baeck       Labels for pending reboot and updates to install
    2.3.4    2026-10-29  Wolfgang Baeck       Label for the Pending (warning) status
    2.5.0    2026-11-04  Wolfgang Baeck       Detail on status rows; per-user cache (Save/Read-SelfXSystemInfoCache)
                                              so the information is shown immediately
    2.5.3    2026-11-04  Wolfgang Baeck       Times in the time zone of the user: UTC markers of the health details
                                              are converted, status times are kept in UTC, time zone cache is cleared
    2.5.10   2026-11-06  Wolfgang Baeck       "LAN connected" also for virtual network adapters of virtual machines
                                              (Hyper-V, VMware): adapters with a default route count (Get-SelfXConnectionTypes);
                                              fix: last Intune sync was shown one hour (UTC offset) too late, the OMA-DM
                                              time is local time despite its "Z" (ConvertFrom-SelfXOmaDmTime)
    2.6.0    2026-11-06  Wolfgang Baeck       Label "Company apps (Intune)" instead of "Applications (local IME cache)"
#>

# English default labels. Keys are identical to the <SystemInfo> section of Languages\en.xml.
$Script:SelfXInfoDefaultText = @{
	Category_Device = 'Device'; Category_Windows = 'Windows'; Category_User = 'User and management'
	Category_Network = 'Network'; Category_Report = 'Report'
	Computer_Name = 'Computer name'; Manufacturer = 'Manufacturer'; Model = 'Model'; Serial_Number = 'Serial number'
	BIOS_Version = 'BIOS version'; Processor = 'Processor'; Memory = 'Memory (RAM)'; Free_Space = 'Free space {0}'
	Free_Space_Value = '{0} of {1} ({2}%)'; Battery = 'Battery'
	Windows_Version = 'Windows version'; OS_Build = 'OS build'; Last_Boot = 'Last boot'; Uptime = 'Uptime'
	Uptime_Value = '{0} day(s) {1:D2}:{2:D2} h'; Last_Update = 'Last update installed'; Time_Zone = 'Time zone'
	Current_User = 'Current user'; User_Principal_Name = 'User principal name'; Domain = 'Domain / workgroup'
	Entra_Joined = 'Entra ID joined'; Domain_Joined = 'Domain joined'; Tenant = 'Tenant'; Entra_Device_Id = 'Entra device ID'
	Intune_User = 'Intune enrolled user'; Intune_Last_Sync = 'Last Intune sync'
	LAN_Connected = 'LAN connected'; WiFi_Connected = 'Wi-Fi connected'; WWAN_Connected = 'Mobile broadband connected'
	WiFi_SSID = 'Wi-Fi network (SSID)'; VPN_Connected = 'VPN connected'; Internet_Reachable = 'Internet reachable'
	IPv4 = 'IPv4 address(es)'; IPv6 = 'IPv6 address(es)'; Gateway = 'Default gateway'; DNS = 'DNS server(s)'; MAC = 'MAC address(es)'
	Collected_At = 'Collected at'; Error = 'Error'; Yes = 'Yes'; No = 'No'; Not_Available = 'n/a'
	Not_Enrolled = 'Not enrolled / unknown'; No_WiFi = 'No Wi-Fi connection'
	Category_Health = 'Health status'; Health_IME = 'IME service'; Health_Defender = 'Microsoft Defender'
	Health_Compliance = 'Compliance'; Health_Applications = 'Company apps (Intune)'
	Health_Disk = 'Disk capacity'; Health_BitLocker = 'BitLocker'; Health_PendingReboot = 'Pending reboot'
	Health_Updates = 'Updates to install'; Health_Service = 'Service'
	Health_Custom = 'Custom check'; Health_Collection = 'Health collection'
	Health_OK = 'OK'; Health_Pending = 'Pending'; Health_Error = 'Error'; Health_Unknown = 'Unknown'
	Health_Unavailable = 'Local health report unavailable: {0}'
}
# Labels used by the current collection (defaults overlaid with the -Text hashtable of Get-SelfXSystemInfo).
$Script:SelfXInfoText = $Script:SelfXInfoDefaultText.Clone()

function Get-SelfXInfoText {
	# Returns the label for Key; extra arguments are inserted into {0}, {1}, ... placeholders.
	param(
		[string]$Key,
		[Parameter(ValueFromRemainingArguments = $true)]
		[object[]]$Arguments
	)
	$value = $Script:SelfXInfoText[$Key]
	if ([string]::IsNullOrEmpty($value)) { $value = $Script:SelfXInfoDefaultText[$Key] }
	if ([string]::IsNullOrEmpty($value)) { $value = $Key }
	if ($Arguments -and $Arguments.Count) {
		try { return [string]::Format($value, $Arguments) }
		catch { return [string]::Format($Script:SelfXInfoDefaultText[$Key], $Arguments) }
	}
	return $value
}

function New-SelfXInfoItem {
	param(
		[string]$Category,
		[string]$Property,
		$Value,
		[string]$Status = ''
	)
	# Empty values are shown as "n/a" (localized).
	if ($null -eq $Value -or "$Value" -eq '') { $Value = Get-SelfXInfoText 'Not_Available' }
	[pscustomobject]@{
		Category = $Category
		Property = $Property
		Value    = ($Value -join ', ')
		Status   = $Status
	}
}

function Update-SelfXTimeZone {
    # .NET caches the time zone per process. SelfX and the tray icon run for a long time (for example
    # across the automatic time zone change after the OOBE), so the cache is cleared before times are shown.
    [TimeZoneInfo]::ClearCachedData()
}

function ConvertTo-SelfXUserTime {
    # Converts a time to the current time zone of the user. Utc and Local kinds are converted exactly;
    # Unspecified is treated as UTC (all times of the service are transported in UTC).
    param([datetime]$Time)
    Update-SelfXTimeZone
    if ($Time.Kind -eq [DateTimeKind]::Local) { $Time = $Time.ToUniversalTime() }
    return [TimeZoneInfo]::ConvertTimeFromUtc([datetime]::SpecifyKind($Time, [DateTimeKind]::Utc), [TimeZoneInfo]::Local)
}

function Format-SelfXUserTimeText {
    # Replaces the UTC markers {utc:yyyy-MM-ddTHH:mm:ssZ} that HealthStatus.ps1 (SYSTEM) writes into
    # the detail texts with the time in the time zone and date format of the user.
    param([string]$Text)
    if ($Text -notmatch '\{utc:') { return $Text }
    return [regex]::Replace($Text, '\{utc:(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ)\}', {
        param($match)
        try {
            $utc = [datetime]::ParseExact($match.Groups[1].Value, "yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]'AssumeUniversal,AdjustToUniversal')
            (ConvertTo-SelfXUserTime $utc).ToString('g')
        } catch { $match.Value }
    })
}

function ConvertTo-SelfXHealthInfo {
    param([object[]]$Results)
    foreach ($result in $Results) {
        $property = Get-SelfXInfoText "Health_$($result.Id)"
        if ($result.Name) { $property += " ($($result.Name))" }
        $detailText = Format-SelfXUserTimeText "$($result.Detail)"
        $value = (Get-SelfXInfoText "Health_$($result.Status)") + ' - ' + $detailText
        $item = New-SelfXInfoItem (Get-SelfXInfoText 'Category_Health') $property $value $result.Status
        $item | Add-Member -NotePropertyName Remediation -NotePropertyValue "$($result.Remediation)"
        # Technical identity of the check, used by the per-row recheck button.
        $item | Add-Member -NotePropertyName HealthId -NotePropertyValue "$($result.Id)"
        $item | Add-Member -NotePropertyName HealthName -NotePropertyValue "$($result.Name)"
        # Detail without the status prefix, shown on the status cards.
        $item | Add-Member -NotePropertyName Detail -NotePropertyValue $detailText
        $item
    }
}

function Set-SelfXInfoText {
    # Overlays the localized labels on the English defaults.
    param([hashtable]$Text = @{})
    $Script:SelfXInfoText = $Script:SelfXInfoDefaultText.Clone()
    foreach ($key in $Text.Keys) { if (-not [string]::IsNullOrEmpty($Text[$key])) { $Script:SelfXInfoText[$key] = $Text[$key] } }
}

function Get-SelfXHealthCheckInfo {
    # Re-runs one health check through the local service and returns its row(s).
    # A failure returns one Unknown row that keeps the check identity so it can be retried.
    param([string]$Id, [string]$Name = '', [hashtable]$Text = @{})
    Set-SelfXInfoText $Text
    try {
        ConvertTo-SelfXHealthInfo -Results @(Get-SelfXServiceHealthReport -Id $Id -Name $Name)
    } catch {
        $property = Get-SelfXInfoText "Health_$Id"
        if ($Name) { $property += " ($Name)" }
        $item = New-SelfXInfoItem (Get-SelfXInfoText 'Category_Health') $property (Get-SelfXInfoText 'Health_Unavailable' $_.Exception.Message) 'Unknown'
        $item | Add-Member -NotePropertyName Remediation -NotePropertyValue ''
        $item | Add-Member -NotePropertyName HealthId -NotePropertyValue $Id
        $item | Add-Member -NotePropertyName HealthName -NotePropertyValue $Name
        $item | Add-Member -NotePropertyName Detail -NotePropertyValue (Get-SelfXInfoText 'Health_Unavailable' $_.Exception.Message)
        $item
    }
}

function Get-SelfXStatusData {
    # Device status for the GUI and the tray icon (runs in a background runspace):
    #   Cached = status cache of the background checks (STATUS, immediate), Full = all checks now (HEALTH),
    #   Single = one check now. Returns Mode, Ok, Items (status rows), CollectedAt, IntervalMinutes,
    #   State, Id, Name and Message (error text when Ok is false).
    param([ValidateSet('Cached', 'Full', 'Single')][string]$Mode, [string]$Id = '', [string]$Name = '', [hashtable]$Text = @{})
    Set-SelfXInfoText $Text
    $data = [pscustomobject]@{ Mode = $Mode; Ok = $true; Items = @(); CollectedAt = $null; IntervalMinutes = 0; State = ''; Id = $Id; Name = $Name; Message = '' }
    try {
        switch ($Mode) {
            'Cached' {
                $status = Get-SelfXServiceStatusCache
                $data.CollectedAt = $status.CollectedAt
                $data.IntervalMinutes = $status.IntervalMinutes
                $data.State = $status.State
                if (@($status.Results).Count) { $data.Items = @(ConvertTo-SelfXHealthInfo -Results @($status.Results)) }
            }
            'Full' {
                $data.Items = @(ConvertTo-SelfXHealthInfo -Results @(Get-SelfXServiceHealthReport))
                $data.CollectedAt = [datetime]::UtcNow
            }
            'Single' {
                $data.Items = @(Get-SelfXHealthCheckInfo -Id $Id -Name $Name -Text $Text)
                $data.CollectedAt = [datetime]::UtcNow
            }
        }
    } catch {
        $data.Ok = $false
        $data.Message = $_.Exception.Message
    }
    return $data
}

function Get-SelfXSystemInfoCachePath {
    # Per-user cache of the last collected system information (no administrator data).
    return (Join-Path $env:LOCALAPPDATA 'SelfX\SystemInfo.json')
}

function Save-SelfXSystemInfoCache {
    # Stores the information rows (not the status rows) so the next start can show them immediately.
    param([object[]]$Items, [string]$Culture = '', [string]$Path = (Get-SelfXSystemInfoCachePath))
    $rows = @($Items | Where-Object { $_ -and -not "$($_.Status)" } | ForEach-Object {
        [pscustomobject]@{ Category = "$($_.Category)"; Property = "$($_.Property)"; Value = "$($_.Value)" } })
    if (-not $rows.Count) { return }
    $folder = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    $data = [pscustomobject]@{ CollectedAt = [datetime]::UtcNow.ToString('o'); Culture = $Culture; Items = $rows }
    $temp = "$Path.tmp"
    [IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject $data -Depth 4 -Compress), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

function Read-SelfXSystemInfoCache {
    # Returns CollectedAt and Items of the cache, or $null when it is missing, invalid or in another language.
    param([string]$Culture = '', [string]$Path = (Get-SelfXSystemInfoCachePath))
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
        $data = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Path)) -ErrorAction Stop
        if ("$($data.Culture)" -ne $Culture) { return $null }
        $items = @($data.Items | Where-Object { $_.Category -and $_.Property } | ForEach-Object {
            New-SelfXInfoItem "$($_.Category)" "$($_.Property)" "$($_.Value)" })
        if (-not $items.Count) { return $null }
        return [pscustomobject]@{ CollectedAt = [datetime]::Parse("$($data.CollectedAt)", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind); Items = $items }
    } catch { return $null }
}

# Runs a script block and returns $null instead of throwing, so one failing source does not stop the report.
function Invoke-SelfXSafe {
	param([scriptblock]$ScriptBlock)
	try { & $ScriptBlock } catch { $null }
}

function Format-SelfXBytes {
	param([double]$Bytes)
	if ($Bytes -ge 1TB) { return '{0:N1} TB' -f ($Bytes / 1TB) }
	return '{0:N1} GB' -f ($Bytes / 1GB)
}

# Parses "dsregcmd /status" into a hashtable (for example AzureAdJoined = YES).
function Get-SelfXDsregStatus {
	$result = @{}
	$output = Invoke-SelfXSafe { & "$env:SystemRoot\System32\dsregcmd.exe" /status 2>$null }
	foreach ($line in $output) {
		if ($line -match '^\s*([A-Za-z]+)\s*:\s*(.+?)\s*$') {
			if (-not $result.ContainsKey($Matches[1])) { $result[$Matches[1]] = $Matches[2] }
		}
	}
	return $result
}

# Returns the most recent Intune (OMA-DM) server contact of all MDM accounts.
# ServerLastAccessTime of the OMA-DM account (ConnInfo) is written in the local time of the device, although
# the value ends with "Z" (for example 20261106T123322Z at 12:33 CET = 11:33 UTC). Converting it from UTC would
# show a time in the future, so it is read as local time.
function ConvertFrom-SelfXOmaDmTime {
	param([string]$Value)
	$parsed = [datetime]::MinValue
	if ([datetime]::TryParseExact("$Value".Trim(), "yyyyMMdd'T'HHmmss'Z'", [Globalization.CultureInfo]::InvariantCulture,
		[Globalization.DateTimeStyles]::AssumeLocal, [ref]$parsed)) { return $parsed }
	return $null
}

function Get-SelfXIntuneLastSync {
	$accountsPath = 'HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts'
	$dates = foreach ($account in (Get-ChildItem -Path $accountsPath -ErrorAction SilentlyContinue)) {
		$time = (Get-ItemProperty -Path "$($account.PSPath)\Protected\ConnInfo" -ErrorAction SilentlyContinue).ServerLastAccessTime
		if ($time) { ConvertFrom-SelfXOmaDmTime $time }
	}
	$last = $dates | Sort-Object -Descending | Select-Object -First 1
	if ($last) { return $last.ToString('yyyy-MM-dd HH:mm:ss') }
	return Get-SelfXInfoText 'Not_Enrolled'
}

# Returns the UPN of the user that enrolled the device in Intune.
function Get-SelfXMdmEnrollmentUpn {
	foreach ($enrollment in (Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue)) {
		$props = Get-ItemProperty -Path $enrollment.PSPath -ErrorAction SilentlyContinue
		if ($props.ProviderID -eq 'MS DM Server' -and $props.UPN) { return $props.UPN }
	}
	return $null
}

# Returns the SSID of the connected Wi-Fi network (netsh), or $null.
function Get-SelfXWifiSsid {
	$output = Invoke-SelfXSafe { & "$env:SystemRoot\System32\netsh.exe" wlan show interfaces 2>$null }
	foreach ($line in $output) {
		if ($line -match '^\s*SSID\s*:\s*(.+?)\s*$') { return $Matches[1] }
	}
	return $null
}

# Tests a TCP connection with a timeout. Used for the "Internet reachable" line.
function Test-SelfXTcpConnection {
	param(
		[string]$HostName,
		[int]$Port = 80,
		[int]$TimeoutMs = 3000
	)
	if (-not $HostName) { return $false }
	$client = New-Object System.Net.Sockets.TcpClient
	try {
		$async = $client.BeginConnect($HostName, $Port, $null, $null)
		if ($async.AsyncWaitHandle.WaitOne($TimeoutMs, $false) -and $client.Connected) {
			$client.EndConnect($async)
			return $true
		}
		return $false
	}
	catch { return $false }
	finally { $client.Close() }
}

# Adapters of common VPN clients (also used to keep VPN tunnels out of the LAN detection).
$Script:SelfXVpnAdapterPattern = 'VPN|AnyConnect|GlobalProtect|Fortinet|WireGuard|Pulse|Zscaler|PANGP|TAP-Windows'

# Detects an active VPN: Windows VPN profiles first, then adapters of common VPN clients.
function Test-SelfXVpnConnection {
	$vpn = @(Invoke-SelfXSafe { Get-VpnConnection -ErrorAction Stop }) + @(Invoke-SelfXSafe { Get-VpnConnection -AllUserConnection -ErrorAction Stop })
	if ($vpn | Where-Object { $_.ConnectionStatus -eq 'Connected' }) { return $true }
	$vpnAdapters = Invoke-SelfXSafe {
		Get-NetAdapter -ErrorAction Stop | Where-Object {
			$_.Status -eq 'Up' -and $_.InterfaceDescription -match $Script:SelfXVpnAdapterPattern
		}
	}
	return [bool]$vpnAdapters
}

# Classifies the connected adapters (Get-NetAdapter objects) into LAN, Wi-Fi and mobile broadband.
# An adapter counts when it is Up and either a hardware adapter or carries a default route (GatewayIndexes).
# Virtual network adapters of virtual machines (Hyper-V, VMware, VirtualBox guests) report the physical
# medium "Unspecified" and are no hardware adapters, so the default route identifies them as LAN connection.
# The virtual switch adapters of a Hyper-V host (vEthernet), VPN tunnels and Bluetooth never count as LAN.
function Get-SelfXConnectionTypes {
	param(
		[object[]]$Adapters = @(),
		[int[]]$GatewayIndexes = @()
	)
	$result = [pscustomobject]@{ Lan = $false; WiFi = $false; Wwan = $false }
	foreach ($adapter in @($Adapters | Where-Object { $_ -and "$($_.Status)" -eq 'Up' })) {
		$physicalMedium = "$($adapter.PhysicalMediaType)"
		$ndisMedium = "$($adapter.NdisPhysicalMedium)"
		$hardware = ($adapter.HardwareInterface -eq $true) -or ($adapter.ConnectorPresent -eq $true)
		$routed = $GatewayIndexes -contains [int]$adapter.ifIndex
		if (-not ($hardware -or $routed)) { continue }
		if ($physicalMedium -match '802\.11' -or $ndisMedium -eq '9') { $result.WiFi = $true; continue }
		if ($physicalMedium -eq 'Wireless WAN' -or $ndisMedium -eq '8') { $result.Wwan = $true; continue }
		if ($physicalMedium -match 'Bluetooth' -or $ndisMedium -eq '10') { continue }
		if ("$($adapter.InterfaceDescription)" -match $Script:SelfXVpnAdapterPattern -or "$($adapter.InterfaceDescription)" -match 'Hyper-V Virtual Ethernet Adapter') { continue }
		if (("$($adapter.MediaType)" -eq '802.3') -and (($hardware -and $physicalMedium -eq '802.3') -or $routed)) { $result.Lan = $true }
	}
	return $result
}

# Interface indexes with a default route (IPv4 or IPv6), i.e. adapters that connect to other networks.
function Get-SelfXGatewayInterfaceIndexes {
	$routes = @(Invoke-SelfXSafe { Get-NetRoute -DestinationPrefix '0.0.0.0/0', '::/0' -ErrorAction Stop })
	return @($routes | Where-Object { "$($_.NextHop)" -notin @('0.0.0.0', '::', '') } | ForEach-Object { [int]$_.ifIndex } | Sort-Object -Unique)
}

# Collects all information and returns a list of Category/Property/Value objects.
function Get-SelfXSystemInfo {
	param(
		[string]$InternetTestHost = 'www.msftconnecttest.com',
		[int]$InternetTestPort = 80,
		[hashtable]$Text = @{},
		[switch]$IncludeHealth
	)

	# Overlay the localized labels on the English defaults.
	Set-SelfXInfoText $Text
	$L = { param($k) Get-SelfXInfoText $k }
	# All local times below (boot, Intune sync, collected at) use the current time zone of the user.
	Update-SelfXTimeZone

	$items = New-Object System.Collections.Generic.List[object]
	$yesNo = { param($v) if ($v) { Get-SelfXInfoText 'Yes' } else { Get-SelfXInfoText 'No' } }
	# dsregcmd reports YES/NO in English; show them in the UI language.
	$dsregYesNo = { param($v) switch ("$v") { 'YES' { Get-SelfXInfoText 'Yes' } 'NO' { Get-SelfXInfoText 'No' } default { $v } } }

	$catDevice = Get-SelfXInfoText 'Category_Device'
	$catWindows = Get-SelfXInfoText 'Category_Windows'
	$catUser = Get-SelfXInfoText 'Category_User'
	$catNetwork = Get-SelfXInfoText 'Category_Network'
	$catReport = Get-SelfXInfoText 'Category_Report'

	# CIM and registry sources; each one may fail on its own without stopping the report.
	$cs   = Invoke-SelfXSafe { Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop }
	$os   = Invoke-SelfXSafe { Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop }
	$bios = Invoke-SelfXSafe { Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop }
	$cpu  = Invoke-SelfXSafe { Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1 }
	$cv   = Invoke-SelfXSafe { Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop }

	# Device
	$items.Add((New-SelfXInfoItem $catDevice (& $L 'Computer_Name') $env:COMPUTERNAME))
	$items.Add((New-SelfXInfoItem $catDevice (& $L 'Manufacturer') $cs.Manufacturer))
	$items.Add((New-SelfXInfoItem $catDevice (& $L 'Model') $cs.Model))
	$items.Add((New-SelfXInfoItem $catDevice (& $L 'Serial_Number') $bios.SerialNumber))
	$items.Add((New-SelfXInfoItem $catDevice (& $L 'BIOS_Version') $bios.SMBIOSBIOSVersion))
	$items.Add((New-SelfXInfoItem $catDevice (& $L 'Processor') ("$($cpu.Name)".Trim())))
	if ($cs.TotalPhysicalMemory) {
		$items.Add((New-SelfXInfoItem $catDevice (& $L 'Memory') (Format-SelfXBytes $cs.TotalPhysicalMemory)))
	}
	$systemDrive = Invoke-SelfXSafe { Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -ErrorAction Stop }
	if ($systemDrive.Size) {
		$freePercent = [math]::Round(($systemDrive.FreeSpace / $systemDrive.Size) * 100)
		$items.Add((New-SelfXInfoItem $catDevice (Get-SelfXInfoText 'Free_Space' $env:SystemDrive) (Get-SelfXInfoText 'Free_Space_Value' (Format-SelfXBytes $systemDrive.FreeSpace) (Format-SelfXBytes $systemDrive.Size) $freePercent)))
	}
	$battery = Invoke-SelfXSafe { Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop | Select-Object -First 1 }
	if ($battery) {
		$items.Add((New-SelfXInfoItem $catDevice (& $L 'Battery') ("$($battery.EstimatedChargeRemaining)%")))
	}

	# Windows
	$osName = "$($os.Caption)".Replace('Microsoft ', '')
	$items.Add((New-SelfXInfoItem $catWindows (& $L 'Windows_Version') ("$osName $($cv.DisplayVersion)".Trim())))
	if ($cv.CurrentBuild) {
		$build = $cv.CurrentBuild
		if ($null -ne $cv.UBR) { $build = "$build.$($cv.UBR)" }
		$items.Add((New-SelfXInfoItem $catWindows (& $L 'OS_Build') $build))
	}
	if ($os.LastBootUpTime) {
		$uptime = (Get-Date) - $os.LastBootUpTime
		$items.Add((New-SelfXInfoItem $catWindows (& $L 'Last_Boot') $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss')))
		$items.Add((New-SelfXInfoItem $catWindows (& $L 'Uptime') (Get-SelfXInfoText 'Uptime_Value' $uptime.Days $uptime.Hours $uptime.Minutes)))
	}
	$lastUpdate = Invoke-SelfXSafe { Get-HotFix -ErrorAction Stop | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending | Select-Object -First 1 }
	if ($lastUpdate) {
		$items.Add((New-SelfXInfoItem $catWindows (& $L 'Last_Update') ('{0} ({1})' -f $lastUpdate.InstalledOn.ToString('yyyy-MM-dd'), $lastUpdate.HotFixID)))
	}
	$items.Add((New-SelfXInfoItem $catWindows (& $L 'Time_Zone') (Invoke-SelfXSafe { (Get-TimeZone).DisplayName })))

	# User and management
	$dsreg = Get-SelfXDsregStatus
	$upn = Invoke-SelfXSafe { & "$env:SystemRoot\System32\whoami.exe" /upn 2>$null }
	$items.Add((New-SelfXInfoItem $catUser (& $L 'Current_User') "$env:USERDOMAIN\$env:USERNAME"))
	if ("$upn" -match '@') { $items.Add((New-SelfXInfoItem $catUser (& $L 'User_Principal_Name') "$upn".Trim())) }
	$items.Add((New-SelfXInfoItem $catUser (& $L 'Domain') $cs.Domain))
	$items.Add((New-SelfXInfoItem $catUser (& $L 'Entra_Joined') (& $dsregYesNo $dsreg['AzureAdJoined'])))
	$items.Add((New-SelfXInfoItem $catUser (& $L 'Domain_Joined') (& $dsregYesNo $dsreg['DomainJoined'])))
	if ($dsreg['TenantName']) { $items.Add((New-SelfXInfoItem $catUser (& $L 'Tenant') $dsreg['TenantName'])) }
	if ($dsreg['DeviceId']) { $items.Add((New-SelfXInfoItem $catUser (& $L 'Entra_Device_Id') $dsreg['DeviceId'])) }
	$mdmUpn = Get-SelfXMdmEnrollmentUpn
	if ($mdmUpn) { $items.Add((New-SelfXInfoItem $catUser (& $L 'Intune_User') $mdmUpn)) }
	$items.Add((New-SelfXInfoItem $catUser (& $L 'Intune_Last_Sync') (Get-SelfXIntuneLastSync)))

	# Network: connection types, VPN, internet test and addresses of all IP-enabled adapters
	$connections = Get-SelfXConnectionTypes -Adapters @(Invoke-SelfXSafe { Get-NetAdapter -ErrorAction Stop }) -GatewayIndexes (Get-SelfXGatewayInterfaceIndexes)
	$lanUp  = $connections.Lan
	$wifiUp = $connections.WiFi
	$wwanUp = $connections.Wwan
	$ssid = Get-SelfXWifiSsid
	$items.Add((New-SelfXInfoItem $catNetwork (& $L 'LAN_Connected') (& $yesNo $lanUp)))
	$items.Add((New-SelfXInfoItem $catNetwork (& $L 'WiFi_Connected') (& $yesNo $wifiUp)))
	$items.Add((New-SelfXInfoItem $catNetwork (& $L 'WWAN_Connected') (& $yesNo $wwanUp)))
	$items.Add((New-SelfXInfoItem $catNetwork (& $L 'WiFi_SSID') $(if ($ssid) { $ssid } else { Get-SelfXInfoText 'No_WiFi' })))
	$items.Add((New-SelfXInfoItem $catNetwork (& $L 'VPN_Connected') (& $yesNo (Test-SelfXVpnConnection))))
	$items.Add((New-SelfXInfoItem $catNetwork (& $L 'Internet_Reachable') (& $yesNo (Test-SelfXTcpConnection -HostName $InternetTestHost -Port $InternetTestPort))))

	$nics = @(Invoke-SelfXSafe { Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = True' -ErrorAction Stop })
	$ipv4 = @($nics | ForEach-Object { $_.IPAddress } | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' } | Sort-Object -Unique)
	$ipv6 = @($nics | ForEach-Object { $_.IPAddress } | Where-Object { $_ -match ':' -and $_ -notmatch '^fe80' } | Sort-Object -Unique)
	$gateways = @($nics | ForEach-Object { $_.DefaultIPGateway } | Where-Object { $_ } | Sort-Object -Unique)
	$dns = @($nics | ForEach-Object { $_.DNSServerSearchOrder } | Where-Object { $_ } | Select-Object -Unique)
	$items.Add((New-SelfXInfoItem $catNetwork (& $L 'IPv4') $ipv4))
	if ($ipv6.Count) { $items.Add((New-SelfXInfoItem $catNetwork (& $L 'IPv6') $ipv6)) }
	$items.Add((New-SelfXInfoItem $catNetwork (& $L 'Gateway') $gateways))
	$items.Add((New-SelfXInfoItem $catNetwork (& $L 'DNS') $dns))
	$items.Add((New-SelfXInfoItem $catNetwork (& $L 'MAC') (@($nics | ForEach-Object { $_.MACAddress } | Where-Object { $_ } | Sort-Object -Unique))))

	$items.Add((New-SelfXInfoItem $catReport (& $L 'Collected_At') (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))
	if ($IncludeHealth) {
		try {
			foreach ($health in (ConvertTo-SelfXHealthInfo -Results @(Get-SelfXServiceHealthReport))) { $items.Add($health) }
		} catch {
			$detail = Get-SelfXInfoText 'Health_Unavailable' $_.Exception.Message
			$items.Add((New-SelfXInfoItem (Get-SelfXInfoText 'Category_Health') (Get-SelfXInfoText 'Health_Collection') $detail 'Unknown'))
		}
	}
	return $items
}

# Formats the items as plain text with one [Category] block per group (used for copy and TXT export).
function ConvertTo-SelfXSystemInfoText {
	param([object[]]$Items)
	$lines = New-Object System.Collections.Generic.List[string]
	foreach ($group in ($Items | Group-Object Category)) {
		$lines.Add("[$($group.Name)]")
		foreach ($item in $group.Group) { $lines.Add(('{0,-28}: {1}' -f $item.Property, $item.Value)) }
		$lines.Add('')
	}
	return ($lines -join [Environment]::NewLine)
}

# Saves the items to Path. The format follows the file extension: .csv, .json, .html, anything else = text.
function Export-SelfXSystemInfo {
	param(
		[object[]]$Items,
		[string]$Path,
		[string]$Title = 'System information'
	)
	switch ([IO.Path]::GetExtension($Path).ToLowerInvariant()) {
		'.csv'  { $Items | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8 }
		'.json' { $Items | ConvertTo-Json -Depth 3 | Set-Content -Path $Path -Encoding UTF8 }
		'.html' {
			$Items | ConvertTo-Html -Title "$Title - $env:COMPUTERNAME" -PreContent ("<h2>{0} - {1}</h2>" -f [System.Net.WebUtility]::HtmlEncode($Title), $env:COMPUTERNAME) |
				Set-Content -Path $Path -Encoding UTF8
		}
		default { ConvertTo-SelfXSystemInfoText -Items $Items | Set-Content -Path $Path -Encoding UTF8 }
	}
}
