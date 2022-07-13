Set-ItemProperty 'HKCU:\Software\Microsoft\Office\Outlook\Addins\TeamsAddin.FastConnect' -Name "LoadBehavior" -Value 3 -Force

get-process outlook | kill

While (Get-Process outlook)
{
	Start-Sleep -Seconds 5
}

start-process outlook

