#***************************************************************************************************************
# Tool: SelfX
# Author: Damien VAN ROBAEYS
# Website: http://www.systanddeploy.com
# Twitter: https://twitter.com/syst_and_deploy
#***************************************************************************************************************
[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | out-null

$Current_Folder = split-path $MyInvocation.MyCommand.Path
$Sources = $Current_Folder + "\" + "Sources\*"
$Destination_folder = "$env:LOCALAPPDATA\SelfX"
$Tool_Config = "$Destination_folder\Tool_Config.xml"
$GUI_Config = [xml](get-content ".\Sources\Tool_Config.xml")
$Shortcut_Name = $GUI_Config.GUI_Config.Shortcut_Name

$Get_Desktop_Profile = [environment]::GetFolderPath('Desktop')
$SelfX_Desktop_Shortcut = "$Get_Desktop_Profile\$Shortcut_Name.lnk"

$Start_Menu = "$env:appdata\Microsoft\Windows\Start Menu\Programs"
$SelfX_StartMenu_Shortcut = "$Start_Menu\$Shortcut_Name.lnk"

Remove-Item $SelfX_Desktop_Shortcut -Force -Recurse
Remove-Item $SelfX_StartMenu_Shortcut -Force -Recurse
Remove-Item $Destination_folder -Force -Recurse
