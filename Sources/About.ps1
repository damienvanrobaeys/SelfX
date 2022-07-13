[System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')  				| out-null
[System.Reflection.Assembly]::LoadWithPartialName('presentationframework') 				| out-null
[System.Reflection.Assembly]::LoadFrom('assembly\MahApps.Metro.dll')       				| out-null
[System.Reflection.Assembly]::LoadFrom('assembly\MahApps.Metro.IconPacks.dll')      | out-null  
[System.Reflection.Assembly]::LoadFrom('assembly\LoadingIndicators.WPF.dll')       				| out-null

$Global:Current_Folder = split-path $MyInvocation.MyCommand.Path
	
$XML_Content = @()
$Depannage_Actions_XML = [xml](get-content ".\Issues_List.xml")
# $All_Categories = $Depannage_Actions_XML.Actions.Action.Category | Sort-Object -Unique

[xml]$XamlMainWindow = @"  
<Controls:MetroWindow 
xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
xmlns:i="http://schemas.microsoft.com/expression/2010/interactivity"		
xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro"
xmlns:lvc="clr-namespace:LiveCharts.Wpf;assembly=LiveCharts.Wpf"
xmlns:iconPacks="http://metro.mahapps.com/winfx/xaml/iconpacks" 						
Title="Self-X (Self-fix)" 
Topmost="True"
Width="280" 
Height="280"  
ResizeMode="CanMinimize"	
BorderBrush="Teal"
BorderThickness="1"
WindowStartupLocation ="CenterScreen"	
GlowBrush="{DynamicResource AccentColorBrush}"	
TitleCaps="False">

<Window.TaskbarItemInfo>
	<TaskbarItemInfo/>
</Window.TaskbarItemInfo>

<Window.Resources>
	<ResourceDictionary>
		<ResourceDictionary.MergedDictionaries>
			<ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Controls.xaml" />
			<ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Fonts.xaml" />
			<ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Colors.xaml" />
			<ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Accents/Cyan.xaml" />				
			<ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Accents/BaseLight.xaml" />
		</ResourceDictionary.MergedDictionaries>
	</ResourceDictionary>
</Window.Resources>

    <Grid >		
		<StackPanel HorizontalAlignment="Center"  Margin="0,20,0,0" Orientation="Vertical" >							
			<Image Name = "Tool_Logo"  Margin="0,0,0,0" Height="110" Source="logo.png" HorizontalAlignment="Center"></Image>
			<StackPanel Margin="0,10,0,0">							
				<Label Name="SelfX_Version" HorizontalAlignment="Center" FontSize="14" Content="Win32App - Build and Extract - v1.1"/>
				<Label HorizontalAlignment="Center" FontSize="14" Content="Author: Syst and Deploy"/>
				<Label HorizontalAlignment="Center" FontSize="14" Content="Web site: systanddeploy.com"/>				
				<Label HorizontalAlignment="Center" FontSize="14" Name="IntuneWinApp_Ver" Margin="0,3,0,0"/>								
			</StackPanel>							
		</StackPanel>				
    </Grid>
</Controls:MetroWindow>   
"@   
$reader=(New-Object System.Xml.XmlNodeReader $XamlMainWindow)  
$Form=[Windows.Markup.XamlReader]::Load($reader) 

$XamlMainWindow.SelectNodes("//*[@Name]") | %{
    try {Set-Variable -Name "$($_.Name)" -Value $Form.FindName($_.Name) -ErrorAction Stop}
    catch{throw}
}

$Form.TaskbarItemInfo.Overlay = ".\icon_systray.ico"

$Tool_Logo.Source = "logo.png"
$GUI_Config = $Depannage_Actions_XML.Actions.GUI_Config
$Current_XML_Version = $GUI_Config.XML_Version

$Tool_Version = $GUI_Config.Tool_Version
$Form.Title = "About SelfX"

$SelfX_Version.Content = "SelfX: v$Tool_Version - XML: $Current_XML_Version"

$Form.ShowDialog() | Out-Null 