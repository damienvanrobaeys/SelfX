$Get_Current_user_Name = $env:username
$User_Profil_Path = "C:\Users\$Get_Current_user_Name\AppData\Local\Microsoft\OneDrive\OneDrive.exe"              
Start-Process -FilePath $User_Profil_Path			
