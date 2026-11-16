#***************************************************************************************************************
# Tool: SelfX - System information collector
# Read-only collection of device details shown in the "System information" tab.
# Based on the idea and data points of the "System Information Tool" by Jannik Reinhard
# (https://github.com/JayRHa/windows-system-information, MIT License, Copyright (c) 2026 Jannik Reinhard).
# This script only reads information. It does not change, restart or sign out anything.
#***************************************************************************************************************

function New-SelfXInfoItem {
	param(
		[string]$Category,
		[string]$Property,
		$Value
	)
	if ($null -eq $Value -or "$Value" -eq '') { $Value = 'n/a' }
	[pscustomobject]@{
		Category = $Category
		Property = $Property
		Value    = ($Value -join ', ')
	}
}

function Invoke-SelfXSafe {
	param([scriptblock]$ScriptBlock)
	try { & $ScriptBlock } catch { $null }
}

function Format-SelfXBytes {
	param([double]$Bytes)
	if ($Bytes -ge 1TB) { return '{0:N1} TB' -f ($Bytes / 1TB) }
	return '{0:N1} GB' -f ($Bytes / 1GB)
}

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

function Get-SelfXIntuneLastSync {
	# ServerLastAccessTime is written in the local time of the device, although it ends with "Z": read it as
	# local time (converting it from UTC showed the sync one UTC offset too late, in the future).
	$accountsPath = 'HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts'
	$dates = foreach ($account in (Get-ChildItem -Path $accountsPath -ErrorAction SilentlyContinue)) {
		$time = (Get-ItemProperty -Path "$($account.PSPath)\Protected\ConnInfo" -ErrorAction SilentlyContinue).ServerLastAccessTime
		$parsed = [datetime]::MinValue
		if ($time -and [datetime]::TryParseExact("$time".Trim(), "yyyyMMdd'T'HHmmss'Z'", [Globalization.CultureInfo]::InvariantCulture,
			[Globalization.DateTimeStyles]::AssumeLocal, [ref]$parsed)) { $parsed }
	}
	$last = $dates | Sort-Object -Descending | Select-Object -First 1
	if ($last) { return $last.ToString('yyyy-MM-dd HH:mm:ss') }
	return 'Not enrolled / unknown'
}

function Get-SelfXMdmEnrollmentUpn {
	foreach ($enrollment in (Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue)) {
		$props = Get-ItemProperty -Path $enrollment.PSPath -ErrorAction SilentlyContinue
		if ($props.ProviderID -eq 'MS DM Server' -and $props.UPN) { return $props.UPN }
	}
	return $null
}

function Get-SelfXWifiSsid {
	$output = Invoke-SelfXSafe { & "$env:SystemRoot\System32\netsh.exe" wlan show interfaces 2>$null }
	foreach ($line in $output) {
		if ($line -match '^\s*SSID\s*:\s*(.+?)\s*$') { return $Matches[1] }
	}
	return $null
}

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

function Test-SelfXVpnConnection {
	$vpn = @(Invoke-SelfXSafe { Get-VpnConnection -ErrorAction Stop }) + @(Invoke-SelfXSafe { Get-VpnConnection -AllUserConnection -ErrorAction Stop })
	if ($vpn | Where-Object { $_.ConnectionStatus -eq 'Connected' }) { return $true }
	$vpnAdapters = Invoke-SelfXSafe {
		Get-NetAdapter -ErrorAction Stop | Where-Object {
			$_.Status -eq 'Up' -and $_.InterfaceDescription -match 'VPN|AnyConnect|GlobalProtect|Fortinet|WireGuard|Pulse|Zscaler|PANGP|TAP-Windows'
		}
	}
	return [bool]$vpnAdapters
}

# LAN / Wi-Fi / mobile broadband of the connected adapters. An adapter counts when it is Up and either a hardware
# adapter or carries a default route: virtual network adapters of virtual machines (Hyper-V, VMware) report the
# physical medium "Unspecified" and were not detected as LAN before. Hyper-V host switches (vEthernet), VPN
# tunnels and Bluetooth never count as LAN.
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
		if ("$($adapter.InterfaceDescription)" -match 'VPN|AnyConnect|GlobalProtect|Fortinet|WireGuard|Pulse|Zscaler|PANGP|TAP-Windows|Hyper-V Virtual Ethernet Adapter') { continue }
		if (("$($adapter.MediaType)" -eq '802.3') -and (($hardware -and $physicalMedium -eq '802.3') -or $routed)) { $result.Lan = $true }
	}
	return $result
}

function Get-SelfXGatewayInterfaceIndexes {
	$routes = @(Invoke-SelfXSafe { Get-NetRoute -DestinationPrefix '0.0.0.0/0', '::/0' -ErrorAction Stop })
	return @($routes | Where-Object { "$($_.NextHop)" -notin @('0.0.0.0', '::', '') } | ForEach-Object { [int]$_.ifIndex } | Sort-Object -Unique)
}

function Get-SelfXSystemInfo {
	param(
		[string]$InternetTestHost = 'www.msftconnecttest.com',
		[int]$InternetTestPort = 80
	)

	$items = New-Object System.Collections.Generic.List[object]
	$yesNo = { param($v) if ($v) { 'Yes' } else { 'No' } }

	$cs   = Invoke-SelfXSafe { Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop }
	$os   = Invoke-SelfXSafe { Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop }
	$bios = Invoke-SelfXSafe { Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop }
	$cpu  = Invoke-SelfXSafe { Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1 }
	$cv   = Invoke-SelfXSafe { Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop }

	# Device
	$items.Add((New-SelfXInfoItem 'Device' 'Computer name' $env:COMPUTERNAME))
	$items.Add((New-SelfXInfoItem 'Device' 'Manufacturer' $cs.Manufacturer))
	$items.Add((New-SelfXInfoItem 'Device' 'Model' $cs.Model))
	$items.Add((New-SelfXInfoItem 'Device' 'Serial number' $bios.SerialNumber))
	$items.Add((New-SelfXInfoItem 'Device' 'BIOS version' $bios.SMBIOSBIOSVersion))
	$items.Add((New-SelfXInfoItem 'Device' 'Processor' ("$($cpu.Name)".Trim())))
	if ($cs.TotalPhysicalMemory) {
		$items.Add((New-SelfXInfoItem 'Device' 'Memory (RAM)' (Format-SelfXBytes $cs.TotalPhysicalMemory)))
	}
	$systemDrive = Invoke-SelfXSafe { Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -ErrorAction Stop }
	if ($systemDrive.Size) {
		$freePercent = [math]::Round(($systemDrive.FreeSpace / $systemDrive.Size) * 100)
		$items.Add((New-SelfXInfoItem 'Device' "Free space $env:SystemDrive" ("{0} of {1} ({2}%)" -f (Format-SelfXBytes $systemDrive.FreeSpace), (Format-SelfXBytes $systemDrive.Size), $freePercent)))
	}
	$battery = Invoke-SelfXSafe { Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop | Select-Object -First 1 }
	if ($battery) {
		$items.Add((New-SelfXInfoItem 'Device' 'Battery' ("$($battery.EstimatedChargeRemaining)%")))
	}

	# Windows
	$osName = "$($os.Caption)".Replace('Microsoft ', '')
	$items.Add((New-SelfXInfoItem 'Windows' 'Windows version' ("$osName $($cv.DisplayVersion)".Trim())))
	if ($cv.CurrentBuild) {
		$build = $cv.CurrentBuild
		if ($null -ne $cv.UBR) { $build = "$build.$($cv.UBR)" }
		$items.Add((New-SelfXInfoItem 'Windows' 'OS build' $build))
	}
	if ($os.LastBootUpTime) {
		$uptime = (Get-Date) - $os.LastBootUpTime
		$items.Add((New-SelfXInfoItem 'Windows' 'Last boot' $os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss')))
		$items.Add((New-SelfXInfoItem 'Windows' 'Uptime' ('{0} day(s) {1:D2}:{2:D2} h' -f $uptime.Days, $uptime.Hours, $uptime.Minutes)))
	}
	$lastUpdate = Invoke-SelfXSafe { Get-HotFix -ErrorAction Stop | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending | Select-Object -First 1 }
	if ($lastUpdate) {
		$items.Add((New-SelfXInfoItem 'Windows' 'Last update installed' ('{0} ({1})' -f $lastUpdate.InstalledOn.ToString('yyyy-MM-dd'), $lastUpdate.HotFixID)))
	}
	$items.Add((New-SelfXInfoItem 'Windows' 'Time zone' (Invoke-SelfXSafe { (Get-TimeZone).DisplayName })))

	# User and management
	$dsreg = Get-SelfXDsregStatus
	$upn = Invoke-SelfXSafe { & "$env:SystemRoot\System32\whoami.exe" /upn 2>$null }
	$items.Add((New-SelfXInfoItem 'User and management' 'Current user' "$env:USERDOMAIN\$env:USERNAME"))
	if ("$upn" -match '@') { $items.Add((New-SelfXInfoItem 'User and management' 'User principal name' "$upn".Trim())) }
	$items.Add((New-SelfXInfoItem 'User and management' 'Domain / workgroup' $cs.Domain))
	$items.Add((New-SelfXInfoItem 'User and management' 'Entra ID joined' $dsreg['AzureAdJoined']))
	$items.Add((New-SelfXInfoItem 'User and management' 'Domain joined' $dsreg['DomainJoined']))
	if ($dsreg['TenantName']) { $items.Add((New-SelfXInfoItem 'User and management' 'Tenant' $dsreg['TenantName'])) }
	if ($dsreg['DeviceId']) { $items.Add((New-SelfXInfoItem 'User and management' 'Entra device ID' $dsreg['DeviceId'])) }
	$mdmUpn = Get-SelfXMdmEnrollmentUpn
	if ($mdmUpn) { $items.Add((New-SelfXInfoItem 'User and management' 'Intune enrolled user' $mdmUpn)) }
	$items.Add((New-SelfXInfoItem 'User and management' 'Last Intune sync' (Get-SelfXIntuneLastSync)))

	# Network
	$connections = Get-SelfXConnectionTypes -Adapters @(Invoke-SelfXSafe { Get-NetAdapter -ErrorAction Stop }) -GatewayIndexes (Get-SelfXGatewayInterfaceIndexes)
	$lanUp  = $connections.Lan
	$wifiUp = $connections.WiFi
	$wwanUp = $connections.Wwan
	$ssid = Get-SelfXWifiSsid
	$items.Add((New-SelfXInfoItem 'Network' 'LAN connected' (& $yesNo $lanUp)))
	$items.Add((New-SelfXInfoItem 'Network' 'Wi-Fi connected' (& $yesNo $wifiUp)))
	$items.Add((New-SelfXInfoItem 'Network' 'Mobile broadband connected' (& $yesNo $wwanUp)))
	$items.Add((New-SelfXInfoItem 'Network' 'Wi-Fi network (SSID)' $(if ($ssid) { $ssid } else { 'No Wi-Fi connection' })))
	$items.Add((New-SelfXInfoItem 'Network' 'VPN connected' (& $yesNo (Test-SelfXVpnConnection))))
	$items.Add((New-SelfXInfoItem 'Network' 'Internet reachable' (& $yesNo (Test-SelfXTcpConnection -HostName $InternetTestHost -Port $InternetTestPort))))

	$nics = @(Invoke-SelfXSafe { Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = True' -ErrorAction Stop })
	$ipv4 = @($nics | ForEach-Object { $_.IPAddress } | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' } | Sort-Object -Unique)
	$ipv6 = @($nics | ForEach-Object { $_.IPAddress } | Where-Object { $_ -match ':' -and $_ -notmatch '^fe80' } | Sort-Object -Unique)
	$gateways = @($nics | ForEach-Object { $_.DefaultIPGateway } | Where-Object { $_ } | Sort-Object -Unique)
	$dns = @($nics | ForEach-Object { $_.DNSServerSearchOrder } | Where-Object { $_ } | Select-Object -Unique)
	$items.Add((New-SelfXInfoItem 'Network' 'IPv4 address(es)' $ipv4))
	if ($ipv6.Count) { $items.Add((New-SelfXInfoItem 'Network' 'IPv6 address(es)' $ipv6)) }
	$items.Add((New-SelfXInfoItem 'Network' 'Default gateway' $gateways))
	$items.Add((New-SelfXInfoItem 'Network' 'DNS server(s)' $dns))
	$items.Add((New-SelfXInfoItem 'Network' 'MAC address(es)' (@($nics | ForEach-Object { $_.MACAddress } | Where-Object { $_ } | Sort-Object -Unique))))

	$items.Add((New-SelfXInfoItem 'Report' 'Collected at' (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))
	return $items
}

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

function Export-SelfXSystemInfo {
	param(
		[object[]]$Items,
		[string]$Path
	)
	switch ([IO.Path]::GetExtension($Path).ToLowerInvariant()) {
		'.csv'  { $Items | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8 }
		'.json' { $Items | ConvertTo-Json -Depth 3 | Set-Content -Path $Path -Encoding UTF8 }
		'.html' {
			$Items | ConvertTo-Html -Title "System information - $env:COMPUTERNAME" -PreContent "<h2>System information - $env:COMPUTERNAME</h2>" |
				Set-Content -Path $Path -Encoding UTF8
		}
		default { ConvertTo-SelfXSystemInfoText -Items $Items | Set-Content -Path $Path -Encoding UTF8 }
	}
}
