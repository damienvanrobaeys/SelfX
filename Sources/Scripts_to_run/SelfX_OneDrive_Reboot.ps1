$Get_Current_user = (gwmi win32_computersystem).username
$Get_Current_user_Name = $Get_Current_user.Split("\")[1]
$OneDrive_Kill_Status = $False

$OneDrive_Process_Status = gwmi win32_process | where {$_.Name -eq "onedrive.exe"}
If($OneDrive_Process_Status -ne $null)
	{
		try
			{
				$OneDrive_Process_Status.Terminate() | out-null	
				$OneDrive_Kill_Status = $True
			}
		catch
			{
				$OneDrive_Kill_Status = $False			
			}
	}
	
Sleep 10

If($OneDrive_Kill_Status -eq $True)
	{
		$User_Profil_Path = "C:\Users\$Get_Current_user_Name\AppData\Local\Microsoft\OneDrive\OneDrive.exe"	
		Start-Process -FilePath $User_Profil_Path /background	
	}