$Teams_Classic_Path = "C:\Users\$env:username\AppData\Roaming\Microsoft\Teams\*"
$New_Teams_Path = "C:\Users\$env:username\AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\*"

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
	
Sleep 5

If(test-path $Teams_Classic_Path)
	{
		Get-ChildItem $Teams_Classic_Path -Directory | Where name -in ('application cache','blob storage','databases','GPUcache','IndexedDB','Local Storage','tmp') | ForEach{Remove-Item $_.FullName -Recurse -Force}
	}

If(test-path $New_Teams_Path)
	{
		Get-ChildItem $New_Teams_Path -Directory | ForEach{Remove-Item $_.FullName -Recurse -Force}
	}

Sleep 5

Start-Process -FilePath $Teams_Path	

$Global:Current_Folder = split-path $MyInvocation.MyCommand.Path
$Args = "$Current_Folder\AutoDepannage_Notification.ps1", "-Category 'Teams'"
Start-Process -WindowStyle hidden "powershell.exe" -ArgumentList $Args