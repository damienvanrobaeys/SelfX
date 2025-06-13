$OneDrive_Process_Status = gwmi win32_process | where {$_.Name -eq "onedrive.exe"}
If($OneDrive_Process_Status -ne $null)
	{
		$OD_EXE_Path = $OneDrive_Process_Status.path
		try
			{
				$OneDrive_Process_Status.Terminate() | out-null	
				$OneDrive_Kill_Status = $True
			}
		catch
			{
				$OneDrive_Kill_Status = $False
			}
			
		$Reset = Start-Process -FilePath $OD_EXE_Path -ArgumentList "/reset" -NoNewWindow -PassThru
	}
else
	{
		$Get_Current_user = (gwmi win32_computersystem).username
		$Get_Current_user_Name = $Get_Current_user.Split("\")[1]
		If(test-path "C:\Users\$Get_Current_user_Name\AppData\Local\Microsoft\OneDrive\OneDrive.exe")
			{
				$OD_EXE_Path = "C:\Users\$Get_Current_user_Name\AppData\Local\Microsoft\OneDrive\OneDrive.exe"
				Start-Process -FilePath $OD_EXE_Path -ArgumentList "/reset" -NoNewWindow -PassThru
			}
		ElseIf(test-path 'C:\Program Files\Microsoft OneDrive\onedrive.exe')
			{
				$OD_EXE_Path = "C:\Program Files\Microsoft OneDrive\onedrive.exe"
				Start-Process -FilePath $OD_EXE_Path -ArgumentList "/reset" -NoNewWindow -PassThru
			}
		ElseIf(test-path "C:\Program Files (x86)\Microsoft OneDrive\onedrive.exe")
			{
				$OD_EXE_Path = "C:\Program Files (x86)\Microsoft OneDrive\onedrive.exe"
				Start-Process -FilePath $OD_EXE_Path -ArgumentList "/reset" -NoNewWindow -PassThru
			}
	}

sleep 30
Start-Process -FilePath $OD_EXE_Path /background

$Global:Current_Folder = split-path $MyInvocation.MyCommand.Path
$Args = "$Current_Folder\AutoDepannage_Notification.ps1", "-Category 'OneDrive'"
Start-Process -WindowStyle hidden "powershell.exe" -ArgumentList $Args
