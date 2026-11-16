$Excel_Processes = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'EXCEL.EXE'")

if ($Excel_Processes.Count -eq 0) {
	Write-Output "Excel is not running."
	exit 0
}

$Excel_Path = $Excel_Processes |
	Where-Object { $_.ExecutablePath } |
	Select-Object -First 1 -ExpandProperty ExecutablePath

if (-not $Excel_Path) {
	throw "Could not determine the Excel executable path."
}

foreach ($Excel_Process in $Excel_Processes) {
	$Termination = Invoke-CimMethod -InputObject $Excel_Process -MethodName Terminate
	if ($Termination.ReturnValue -ne 0) {
		throw "Could not close Excel process $($Excel_Process.ProcessId); WMI returned $($Termination.ReturnValue)."
	}
}

Start-Sleep -Seconds 3

if (Get-Process -Name EXCEL -ErrorAction SilentlyContinue) {
	throw "Excel is still running; it was not restarted."
}

Start-Process -FilePath $Excel_Path
