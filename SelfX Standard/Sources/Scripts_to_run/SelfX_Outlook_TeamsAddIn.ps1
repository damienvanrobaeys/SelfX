Set-ItemProperty 'HKCU:\Software\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect' -Name "LoadBehavior" -Value 3 -Force

get-process outlook | kill

While (Get-Process outlook)
{
	Start-Sleep -Seconds 5
}

start-process outlook

$Global:Current_Folder = split-path $MyInvocation.MyCommand.Path
$Args = "$Current_Folder\AutoDepannage_Notification.ps1", "-Category 'Outlook'"
Start-Process -WindowStyle hidden "powershell.exe" -ArgumentList $Args

