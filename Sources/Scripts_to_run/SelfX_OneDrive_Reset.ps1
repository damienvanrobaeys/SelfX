$Get_Current_user = (gwmi win32_computersystem).username
$Get_Current_user_Name = $Get_Current_user.Split("\")[1]
$User_Profil_Path = "C:\Users\$Get_Current_user_Name\AppData\Local\Microsoft\OneDrive\OneDrive.exe"	
Start-Process -FilePath $User_Profil_Path /reset
sleep 30	
Start-Process -FilePath $User_Profil_Path /background	
