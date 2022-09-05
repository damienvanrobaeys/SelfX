#***************************************************************************************************************
# Tool: SelfX
# Author: Damien VAN ROBAEYS
# Website: http://www.systanddeploy.com
# Twitter: https://twitter.com/syst_and_deploy
#***************************************************************************************************************
param(
[string]$XML_Link
)

[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | out-null

$Current_Folder = split-path $MyInvocation.MyCommand.Path
$Sources = $Current_Folder + "\" + "Sources\*"
$Destination_folder = "$env:LOCALAPPDATA\SelfX"

$GUI_Config = [xml](get-content ".\Sources\Issues_List.xml")
$Shortcut_Desktop = $GUI_Config.Actions.GUI_Config.Shortcut_Desktop
$Shortcut_StartMenu = $GUI_Config.Actions.GUI_Config.Shortcut_StartMenu
$Show_Install_Toast = $GUI_Config.Actions.GUI_Config.Show_Install_Toast
$Toast_Header_Picture = $GUI_Config.Actions.GUI_Config.Toast_Header_Picture
$Toast_Company_Name = $GUI_Config.Actions.GUI_Config.Toast_Company_Name
$Toast_Title = $GUI_Config.Actions.GUI_Config.Toast_Title
$Toast_Text = $GUI_Config.Actions.GUI_Config.Toast_Text
$Toast_Button_Text = $GUI_Config.Actions.GUI_Config.Toast_Button_Text

If(!(test-path $Destination_folder)){new-item $Destination_folder -type directory -force | out-null}
copy-item $Sources $Destination_folder -force -recurse
Get-Childitem -Recurse $Destination_folder | Unblock-file	

If($XML_Link -ne "")
	{
		$XML_Content = @"
<Issues_XML_Config>
	<Type>Download</Type> <!-- Manual or Download --> 
	<Link_XML>$XML_Link</Link_XML> <!-- If Type = Download, type the path where to find Issues_List.xml--> 
</Issues_XML_Config>		
"@	

		$Issues_List_File = "$Destination_folder\Issues_List.xml"		
		Invoke-WebRequest -Uri $XML_Link -OutFile $Issues_List_File -UseBasicParsing | out-null	
	}
ElseIf($XML_Link -eq "")
	{
		$XML_Content = @"
		<Issues_XML_Config>
			<Type>Manual</Type> <!-- Manual or Download --> 
			<Link_XML>$XML_Link</Link_XML> <!-- If Type = Download, type the path where to find Issues_List.xml--> 
		</Issues_XML_Config>		
"@	
	}
$XML_Content | out-file "$Destination_folder\List_config.xml"	

# Creating desktop shortcut
If($Shortcut_Desktop -eq $True)
	{
		$Get_Tool_Shortcut = "$Destination_folder\SelfX.lnk"		
		$Get_Desktop_Profile = [environment]::GetFolderPath('Desktop')
		$Desktop_LNK = "$Get_Desktop_Profile\SelfX.lnk"
		copy-item $Get_Tool_Shortcut $Get_Desktop_Profile -Force
		$Shell = New-Object -ComObject ("WScript.Shell")
		$Shortcut = $Shell.CreateShortcut($Desktop_LNK)
		$shortcut.IconLocation = "$Destination_folder\logo.ico"
		$Shortcut.Save()		
	}
	
# Creating Start menu shortcut	
If($Shortcut_StartMenu -eq $True)
	{
		$Start_Menu = "$env:appdata\Microsoft\Windows\Start Menu\Programs"
		$Get_Tool_Shortcut = "$Destination_folder\SelfX.lnk"		
		copy-item $Get_Tool_Shortcut $Start_Menu -Force		
		$Shell = New-Object -ComObject ("WScript.Shell")
		$Shortcut = $Shell.CreateShortcut("$Start_Menu\SelfX.lnk")
		$shortcut.IconLocation = "$Destination_folder\logo.ico"
		$Shortcut.Save()			
	}


If($Show_Install_Toast -eq $True)
{
	$Current_Folder = split-path $MyInvocation.MyCommand.Path
	$HeroImage = "$Current_Folder\$Toast_Header_Picture"
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