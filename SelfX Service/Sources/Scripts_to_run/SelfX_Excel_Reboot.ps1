<#
.SYNOPSIS
    Close running Excel processes and reopen the discovered Excel executable.

.DESCRIPTION
    Runs as the signed-in user from the SelfX GUI. Finds the EXCEL.EXE processes of the user's
    session, retains the first executable path and terminates them. Unsaved workbook changes
    can be lost. Waits up to 15 seconds until Excel has stopped before launching the retained
    executable; workbooks are not explicitly reopened.
    Exits 0 when no Excel process exists. A missing path, failed termination or a surviving
    Excel process raise an error (exit 1) instead of starting another instance.
    Logs to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1).

.NOTES
    Name    : SelfX_Excel_Reboot.ps1
    Package : SelfX Service
    Context : User
    Version : 2.6.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2026-10-28  Wolfgang Baeck       Initial version (based on SelfX_Word_Reboot.ps1)
    2.2.0    2026-10-28  Wolfgang Baeck       Added description, history and comments
    2.6.0    2026-11-06  Wolfgang Baeck       Logging (SelfXLog.ps1); only processes of the user's session; waits up
                                              to 15 seconds for Excel to close
#>

# Logging to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder); the action also works without it.
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component ([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) }
else { function Write-SelfXLog { param($Message, $Level) } }
trap { Write-SelfXLog "Failed: $($_.Exception.Message)" Error; break }

$session = (Get-Process -Id $PID).SessionId
$excel = @(Get-Process -Name EXCEL -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session })
if ($excel.Count -eq 0) {
	Write-SelfXLog 'Excel is not running; nothing to restart.'
	Write-Output 'Excel is not running.'
	exit 0
}
# Capture the executable location before terminating the processes that expose it.
$excelPath = $excel | Where-Object { $_.Path } | Select-Object -First 1 -ExpandProperty Path
if (-not $excelPath) { throw 'Could not determine the Excel executable path.' }
Write-SelfXLog "Closing $($excel.Count) Excel process(es) ($excelPath)."
# Forced termination does not offer a save prompt for unsaved workbooks.
$excel | Stop-Process -Force -ErrorAction Stop
for ($i = 0; $i -lt 15 -and (Get-Process -Name EXCEL -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session }); $i++) { Start-Sleep -Seconds 1 }
# Do not start another instance while a previous Excel process still holds files.
if (Get-Process -Name EXCEL -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session }) {
	throw 'Excel is still running; it was not restarted.'
}
Start-Process -FilePath $excelPath
Write-SelfXLog 'Excel started again.'
exit 0
