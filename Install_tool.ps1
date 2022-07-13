#***************************************************************************************************************
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

$ProgData = $env:ProgramData
$Destination_folder = "$env:LOCALAPPDATA\SelfX"

If(test-path $Destination_folder){remove-item $Destination_folder -recurse -force | out-null}
new-item $Destination_folder -type directory -force | out-null
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
$Get_Tool_Shortcut = "$Destination_folder\SelfX.lnk"		
$Get_Desktop_Profile = [environment]::GetFolderPath('Desktop')
$Desktop_LNK = "$Get_Desktop_Profile\SelfX.lnk"
copy-item $Get_Tool_Shortcut $Get_Desktop_Profile -Force
$Shell = New-Object -ComObject ("WScript.Shell")
$Shortcut = $Shell.CreateShortcut($Desktop_LNK)
$shortcut.IconLocation = "$Destination_folder\logo.ico"
# $shortcut.IconLocation = "$Destination_folder\icon_systray.ico"

# Creating Start menu shortcut
$Start_Menu = "$env:appdata\Microsoft\Windows\Start Menu\Programs"
copy-item $Desktop_LNK $Start_Menu -Force

$Shortcut.Save()		






