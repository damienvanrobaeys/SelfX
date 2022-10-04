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

If($Teams_Kill_Status -eq $True)
	{
		Start-Process -FilePath $User_Profil_Path #/background	
	}	
