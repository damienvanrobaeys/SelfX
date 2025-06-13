#***************************************************************************************************************
# Tool: SelfX
# Author: Damien VAN ROBAEYS
# Website: http://www.systanddeploy.com
# Twitter: https://twitter.com/syst_and_deploy
#***************************************************************************************************************
param(
[string]$XML_Link,
[string]$ZIP_Link
)

[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | out-null

$Current_Folder = split-path $MyInvocation.MyCommand.Path
$Sources = $Current_Folder + "\" + "Sources\*"
$Destination_folder = "$env:LOCALAPPDATA\SelfX"

$GUI_Config = [xml](get-content ".\Sources\Tool_Config.xml")
$Shortcut_Desktop = $GUI_Config.GUI_Config.Shortcut_Desktop
$Shortcut_StartMenu = $GUI_Config.GUI_Config.Shortcut_StartMenu
$Shortcut_Name = $GUI_Config.GUI_Config.Shortcut_Name
$Show_Install_Toast = $GUI_Config.GUI_Config.Show_Install_Toast
$Toast_Header_Picture = $GUI_Config.GUI_Config.Toast_Header_Picture
$Toast_Company_Name = $GUI_Config.GUI_Config.Toast_Company_Name
$Toast_Title = $GUI_Config.GUI_Config.Toast_Title
$Toast_Text = $GUI_Config.GUI_Config.Toast_Text
$Toast_Button_Text = $GUI_Config.GUI_Config.Toast_Button_Text

If(!(test-path $Destination_folder)){new-item $Destination_folder -type directory -force | out-null}
copy-item $Sources $Destination_folder -force -recurse
Get-Childitem -Recurse $Destination_folder | Unblock-file	

If($XML_Link -ne "")
	{
$XML_Content = @"
<Issues_XML_Config>
	<Type>Download</Type> <!-- Manual or Download --> 
	<Link_XML>$XML_Link</Link_XML> <!-- If Type = Download, type the path where to find Issues_List.xml--> 
	<Link_Scripts>$ZIP_Link</Link_Scripts> Path of Script_to_run.zip file
</Issues_XML_Config>		
"@	

		$Issues_List_File = "$Destination_folder\Issues_List.xml"		
		Invoke-WebRequest -Uri $XML_Link -OutFile $Issues_List_File -UseBasicParsing | out-null	
		
		Invoke-WebRequest -Uri $ZIP_Link -OutFile $ZIP_File -UseBasicParsing | out-null		

		$Scripts_to_run_Folder = "$Destination_folder\Scripts_to_run"
		If(!(test-path $Scripts_to_run_Folder)){new-item $Scripts_to_run_Folder -Type Directory -Force}

		$ZIP_File = "$env:temp\Scripts_to_run.zip"		
		$Extracted_Scripts = "$env:temp\Scripts_to_run"
		Invoke-WebRequest -Uri $ZIP_Link -OutFile $ZIP_File -UseBasicParsing | out-null			
		Expand-Archive -Path $ZIP_File -DestinationPath $Scripts_to_run_Folder -Force	
		Remove-Item $ZIP_File -Force
	}
ElseIf($XML_Link -eq "")
	{
		$XML_Content = @"
		<Issues_XML_Config>
			<Type>Manual</Type> <!-- Manual or Download --> 
			<Link_XML></Link_XML> <!-- If Type = Download, type the path where to find Issues_List.xml--> 
		</Issues_XML_Config>		
"@	
	}
$XML_Content | out-file "$Destination_folder\List_config.xml"	

# Creatre the LNK file
$SelfX_Folder = "$env:LOCALAPPDATA\SelfX"
$SelfX_LNK = "$SelfX_Folder\$Shortcut_Name.lnk"
$WshShell = New-Object -comObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$SelfX_LNK")
$Target_Path = "C:\Windows\System32\cmd.exe"
$Target_Arguments = "/c start /min powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File %LOCALAPPDATA%\SelfX\Self_X.ps1"
$Shortcut.TargetPath = $Target_Path
$Shortcut.Arguments = $Target_Arguments
$shortcut.IconLocation = "$SelfX_Folder\Repair.ico"
$shortcut.WorkingDirectory = "%LOCALAPPDATA%\SelfX"
$Shortcut.Save()

# Copy LNK to desktop
If($Shortcut_Desktop -eq $True)
	{
		$Get_Desktop_Profile = [environment]::GetFolderPath('Desktop')
		copy-item $SelfX_LNK $Get_Desktop_Profile	
	}

# Copy LNK to Start menu 
If($Shortcut_StartMenu -eq $True)
	{
		$Start_Menu = "$env:appdata\Microsoft\Windows\Start Menu\Programs"
		copy-item $SelfX_LNK $Start_Menu		
	}

If($Show_Install_Toast -eq $True)
{
	$Current_Folder = split-path $MyInvocation.MyCommand.Path
	$HeroImage = "$Destination_folder\$Toast_Header_Picture"
	$Title = $Toast_Title
	$Message = $Toast_Text
	$Text_AppName = $Toast_Company_Name

	Function Register-NotificationApp($AppID,$AppDisplayName) {
		[int]$ShowInSettings = 0

		[int]$IconBackgroundColor = 0
		$IconUri = "C:\Windows\ImmersiveControlPanel\images\logo.png"
		
		$AppRegPath = "HKCU:\Software\Classes\AppUserModelId"
		$RegPath = "$AppRegPath\$AppID"
		
		$Notifications_Reg = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings'
		If(!(Test-Path -Path "$Notifications_Reg\$AppID")) 
			{
				New-Item -Path "$Notifications_Reg\$AppID" -Force
				New-ItemProperty -Path "$Notifications_Reg\$AppID" -Name 'ShowInActionCenter' -Value 1 -PropertyType 'DWORD' -Force
			}

		If((Get-ItemProperty -Path "$Notifications_Reg\$AppID" -Name 'ShowInActionCenter' -ErrorAction SilentlyContinue).ShowInActionCenter -ne '1') 
			{
				New-ItemProperty -Path "$Notifications_Reg\$AppID" -Name 'ShowInActionCenter' -Value 1 -PropertyType 'DWORD' -Force
			}	
			
		try {
			if (-NOT(Test-Path $RegPath)) {
				New-Item -Path $AppRegPath -Name $AppID -Force | Out-Null
			}
			$DisplayName = Get-ItemProperty -Path $RegPath -Name DisplayName -ErrorAction SilentlyContinue | Select -ExpandProperty DisplayName -ErrorAction SilentlyContinue
			if ($DisplayName -ne $AppDisplayName) {
				New-ItemProperty -Path $RegPath -Name DisplayName -Value $AppDisplayName -PropertyType String -Force | Out-Null
			}
			$ShowInSettingsValue = Get-ItemProperty -Path $RegPath -Name ShowInSettings -ErrorAction SilentlyContinue | Select -ExpandProperty ShowInSettings -ErrorAction SilentlyContinue
			if ($ShowInSettingsValue -ne $ShowInSettings) {
				New-ItemProperty -Path $RegPath -Name ShowInSettings -Value $ShowInSettings -PropertyType DWORD -Force | Out-Null
			}
			
			New-ItemProperty -Path $RegPath -Name IconUri -Value $IconUri -PropertyType ExpandString -Force | Out-Null	
			New-ItemProperty -Path $RegPath -Name IconBackgroundColor -Value $IconBackgroundColor -PropertyType ExpandString -Force | Out-Null		
			
		}
		catch {}
	}

	[xml]$Toast = @"
<toast scenario="reminder">
	<visual>
	<binding template="ToastGeneric">
		<image placement="hero" src="$HeroImage"/>
		<text>$Title</text>
		<group>
			<subgroup>     
				<text hint-style="body" hint-wrap="true" >$Message</text>
			</subgroup>
		</group>			
	</binding>
	</visual>
  <actions>
		<action arguments="" content="$Toast_Button_Text" activationType="protocol" />		  
   </actions>	
</toast>
"@	

	$AppID = $Text_AppName
	$AppDisplayName = $Text_AppName
	Register-NotificationApp -AppID $Text_AppName -AppDisplayName $Text_AppName

	# Notification area
	# This part allows you to let the notification in the notification area
	$Notifications_Reg = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings'
	If(!(Test-Path -Path "$Notifications_Reg\$AppID")) 
		{
			New-Item -Path "$Notifications_Reg\$AppID" -Force
			New-ItemProperty -Path "$Notifications_Reg\$AppID" -Name 'ShowInActionCenter' -Value 1 -PropertyType 'DWORD' -Force
		}

	If((Get-ItemProperty -Path "$Notifications_Reg\$AppID" -Name 'ShowInActionCenter' -ErrorAction SilentlyContinue).ShowInActionCenter -ne '1') 
		{
			New-ItemProperty -Path "$Notifications_Reg\$AppID" -Name 'ShowInActionCenter' -Value 1 -PropertyType 'DWORD' -Force
		}


	# Toast creation and display
	$Load = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
	$Load = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
	$ToastXml = New-Object -TypeName Windows.Data.Xml.Dom.XmlDocument
	$ToastXml.LoadXml($Toast.OuterXml)	
	# Display the Toast
	[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppID).Show($ToastXml)
}