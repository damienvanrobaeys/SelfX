$Teams_Path = "C:\Users\$env:username\AppData\Roaming\Microsoft\Teams\*"
$User_Profil_Path = "C:\Users\$env:username\AppData\Local\Microsoft\Teams\current\Teams.exe"	

$Teams_Process_Status = gwmi win32_process | where {$_.Name -eq "Teams.exe"}
If($Teams_Process_Status -ne $null)	
	{
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
	
Sleep 10

Get-ChildItem $Teams_Path -Directory | Where name -in ('application cache','blob storage','databases','GPUcache','IndexedDB','Local Storage','tmp') | ForEach{Remove-Item $_.FullName -Recurse -Force}

Sleep 10

Start-Process -FilePath $User_Profil_Path	

