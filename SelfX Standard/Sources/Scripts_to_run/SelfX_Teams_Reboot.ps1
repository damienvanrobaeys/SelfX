$Teams_Process_Status = gwmi win32_process | where {$_.Name -like "*teams*"}
If($Teams_Process_Status -ne $null)	
	{
		$Teams_Path = $Teams_Process_Status.Path
		try
			{
				$Teams_Process_Status.Terminate() | out-null	
				$Teams_Kill_Status = $True
			}
		catch
			{
				$Teams_Kill_Status = $False			
			}		
	}
	
If($Teams_Kill_Status -eq $True)
	{
		Start-Process -FilePath $Teams_Path	
	}	

$Global:Current_Folder = split-path $MyInvocation.MyCommand.Path
$Args = "$Current_Folder\AutoDepannage_Notification.ps1", "-Category 'Teams'"
Start-Process -WindowStyle hidden "powershell.exe" -ArgumentList $Args	