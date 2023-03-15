#***************************************************************************************************************
# Tool: SelfX
# Author: Damien VAN ROBAEYS
# Website: http://www.systanddeploy.com
# Twitter: https://twitter.com/syst_and_deploy
#***************************************************************************************************************

$Global:Current_Folder = split-path $MyInvocation.MyCommand.Path

[System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')  				| out-null
[System.Reflection.Assembly]::LoadWithPartialName('presentationframework') 				| out-null
[System.Reflection.Assembly]::LoadFrom('assembly\MahApps.Metro.dll')       				| out-null
[System.Reflection.Assembly]::LoadFrom('assembly\MahApps.Metro.IconPacks.dll')      | out-null  
[System.Reflection.Assembly]::LoadFrom('assembly\LoadingIndicators.WPF.dll')       				| out-null

#*************************************************************************************************************************************
#													PROGRESS BAR PART
#*************************************************************************************************************************************

$syncProgress = [hashtable]::Synchronized(@{})
$childRunspace = [runspacefactory]::CreateRunspace()
$childRunspace.ApartmentState = "STA"
$childRunspace.ThreadOptions = "ReuseThread"         
$childRunspace.Open()
$childRunspace.SessionStateProxy.SetVariable("syncProgress",$syncProgress)          
$PsChildCmd = [PowerShell]::Create().AddScript({   
    [xml]$xaml = @"
	<Controls:MetroWindow 
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
		xmlns:i="http://schemas.microsoft.com/expression/2010/interactivity"				
		xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro"	
		xmlns:loadin="clr-namespace:LoadingIndicators.WPF;assembly=LoadingIndicators.WPF"				
        Name="WindowProgress" 
		WindowStyle="None" AllowsTransparency="True" UseNoneWindowStyle="True"	
		Width="600" Height="300" 
		WindowStartupLocation ="CenterScreen" Topmost="true"
		BorderBrush="Gray" ResizeMode="NoResize"
		>

<Window.Resources>
	<ResourceDictionary>
		<ResourceDictionary.MergedDictionaries>
			<!-- LoadingIndicators resources -->
			<ResourceDictionary Source="pack://application:,,,/LoadingIndicators.WPF;component/Styles.xaml"/>	
			<!-- Mahapps resources -->
			<ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Controls.xaml" />
			<ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Fonts.xaml" />
			<ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Colors.xaml" />
			<ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Accents/Cobalt.xaml" />
			<ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Accents/BaseDark.xaml" />		
		</ResourceDictionary.MergedDictionaries>
	</ResourceDictionary>
</Window.Resources>			

	<Window.Background>
		<SolidColorBrush Opacity="0.7" Color="#0077D6"/>
	</Window.Background>	
		
	<Grid>	
		<StackPanel Orientation="Vertical" VerticalAlignment="Center" HorizontalAlignment="Center">		
			<StackPanel Orientation="Vertical" HorizontalAlignment="Center" Margin="0,0,0,0">	
				<loadin:LoadingIndicator Margin="0,5,0,0" Name="ArcsRing" SpeedRatio="1" Foreground="White" IsActive="True" Style="{DynamicResource LoadingIndicatorArcsRingStyle}"/>
			</StackPanel>								
			
			<StackPanel Orientation="Vertical" HorizontalAlignment="Center" Margin="0,20,0,0">				
				<Label Name="ProgressStep" Content="Getting latest XML content" FontSize="17" Margin="0,0,0,0" Foreground="White"/>	
				<Label HorizontalAlignment="Center" Content="Please wait ..." FontSize="17" Margin="0,0,0,0" Foreground="White"/>	

			</StackPanel>			
		</StackPanel>				
	</Grid>
</Controls:MetroWindow>
"@
  
    $reader=(New-Object System.Xml.XmlNodeReader $xaml)
    $syncProgress.Window=[Windows.Markup.XamlReader]::Load( $reader )
    $syncProgress.Label = $syncProgress.window.FindName("ProgressStep")	

    $syncProgress.Window.ShowDialog() #| Out-Null
    $syncProgress.Error = $Error
})


################ Launch Progress Bar  ########################  
Function Launch_modal_progress{    
    $PsChildCmd.Runspace = $childRunspace
    $Script:Childproc = $PsChildCmd.BeginInvoke()
	
}

################ Close Progress Bar  ########################  
Function Close_modal_progress{
    $syncProgress.Window.Dispatcher.Invoke([action]{$syncProgress.Window.close()})
    $PsChildCmd.EndInvoke($Script:Childproc) | Out-Null
}	

$GUI_Config = [xml](get-content ".\Issues_List.xml")
$Current_XML_Version = $GUI_Config.Actions.XML_Version

$List_config_XML = [xml](get-content ".\List_config.xml")
$Config_Type = $List_config_XML.Issues_XML_Config.Type
If($Config_Type -eq "Download")
	{
		Launch_modal_progress
		$Config_Link = $List_config_XML.Issues_XML_Config.Link_XML
		$Issues_List_File = "$env:temp\Issues_List.xml"		
		Invoke-WebRequest -Uri $Config_Link -OutFile $Issues_List_File -UseBasicParsing | out-null			
		$New_XML = [xml](get-content $Issues_List_File)		
		$New_XML_Version = $New_XML.Actions.XML_Version
		If($Current_XML_Version -ne $New_XML_Version)
			{
				Add-Type -AssemblyName PresentationCore,PresentationFramework

				copy-item $Issues_List_File "$env:LOCALAPPDATA\SelfX"				

				$GUI_Config = [xml](get-content "$env:LOCALAPPDATA\SelfX\Issues_List.xml")
				$Scripts_Link = $GUI_Config.Actions.GUI_Config.Link_Scripts
				
				$Scripts_ZIP_File = "$env:temp\Scripts_to_run.zip"		
				$Extracted_Scripts = "$env:temp\Scripts_to_run"
				Invoke-WebRequest -Uri $Scripts_Link -OutFile $Scripts_ZIP_File -UseBasicParsing | out-null			
				Expand-Archive -Path $Scripts_ZIP_File -DestinationPath $Extracted_Scripts -Force	
				copy-item "$Extracted_Scripts\*" "$env:LOCALAPPDATA\SelfX\Scripts_to_run"
				copy-item $Issues_List_File "$env:LOCALAPPDATA\SelfX"				
			}
		Close_modal_progress
	}	
			
[xml]$XamlMainWindow = @'
<Controls:MetroWindow 
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
		xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro"
		xmlns:loadin="clr-namespace:LoadingIndicators.WPF;assembly=LoadingIndicators.WPF"
		xmlns:iconPacks="http://metro.mahapps.com/winfx/xaml/iconpacks"
        Title="Self-X (Self-fix)" Height="460" Width="660" 
		TitleCaps="False" Topmost="True" ResizeMode="CanMinimize" BorderBrush="Teal"
		BorderThickness="1"	WindowStartupLocation ="CenterScreen" GlowBrush="{DynamicResource AccentColorBrush}">

		<Window.TaskbarItemInfo>
			<TaskbarItemInfo/>
		</Window.TaskbarItemInfo>

		<Window.Resources>
			<ResourceDictionary>
				<ResourceDictionary.MergedDictionaries>
					<!-- LoadingIndicators resources -->
					<ResourceDictionary Source="pack://application:,,,/LoadingIndicators.WPF;component/Styles.xaml"/>
					<!-- Mahapps resources -->
					<ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Controls.xaml" />
					<ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Fonts.xaml" />
					<ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Colors.xaml" />
					<ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Accents/Teal.xaml" />
					<ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Accents/BaseDark.xaml" />
				</ResourceDictionary.MergedDictionaries>
			</ResourceDictionary>
		</Window.Resources>
		
	<Controls:MetroWindow.LeftWindowCommands>
		<Controls:WindowCommands>
		   <Button Name="SubMenu_Home">
				<iconPacks:PackIconMaterial Kind="medicalbag"/>				
			</Button>
		</Controls:WindowCommands>	
	</Controls:MetroWindow.LeftWindowCommands>	

	<Controls:MetroWindow.RightWindowCommands>
		<Controls:WindowCommands>	
		   <Button Name="Support_Info">
				<iconPacks:PackIconFontAwesome Kind="phone"/>				
			</Button>		

		   <Button Name="About">
				<iconPacks:PackIconMaterial Kind="help"/>				
			</Button>		
		</Controls:WindowCommands>	
	</Controls:MetroWindow.RightWindowCommands>			
		
    <Grid>
		<StackPanel Orientation="Vertical" HorizontalAlignment="Center" Margin="0,10,0,0">

			<StackPanel Orientation="Vertical" HorizontalAlignment="Center">
				<Label Name="Main_Title" HorizontalAlignment="Center" FontSize="18" FontWeight="Bold" Content="Un problème avec votre poste ?"/>	
				<Label Name="Subtitle" HorizontalAlignment="Center" FontWeight="Bold" Content="Vous trouverez peut-être un moyen de le résoudre ici au travers d'une liste de problèmes résoluble en un clic"/>	
					
				<StackPanel Margin="0,10,0,0" Orientation="Horizontal" HorizontalAlignment="Center">								
					<Button  Background="#2d89ef" Style="{DynamicResource MetroCircleButtonStyle}" 
						Height="29" Width="29" Cursor="Hand" HorizontalContentAlignment="Stretch" 
						VerticalContentAlignment="Stretch" HorizontalAlignment="Center" VerticalAlignment="Center" 
						BorderThickness="0" Margin="0,0,0,0">
						<iconPacks:PackIconMaterial Margin="3,0,0,0" Kind="play" Foreground="White" Height="11" Width="11" HorizontalAlignment="Center" VerticalAlignment="Center"/>                                                                                         										
					</Button> 
					<Label Name="Run_solution_label" Content="Permet de lancer une action"/>
					
					<Button Margin="5,0,0,0" Background="green" Style="{DynamicResource MetroCircleButtonStyle}" 
						Height="29" Width="29" Cursor="Hand" HorizontalContentAlignment="Stretch" 
						VerticalContentAlignment="Stretch" HorizontalAlignment="Center" VerticalAlignment="Center" 
						BorderThickness="0" >
						<iconPacks:PackIconMaterial Kind="help" Foreground="White" Height="11" Width="11" HorizontalAlignment="Center" VerticalAlignment="Center"/>                                                                                         
					</Button> 
					<Label Name="Run_explanation_label" Content="Permet d'obtenir plus d'informations"/>										
				</StackPanel>
			</StackPanel>

			<StackPanel Orientation="Horizontal" Margin="5,10,0,0" HorizontalAlignment="Center">
				<ComboBox Name="Category_to_choose" SelectedIndex="0" Text="Choose a category" Height="25" Width="180" Margin="0,0,0,0">
					<ComboBoxItem Name="Combo_filter_Title_Text">Trier par fonctionnalité</ComboBoxItem>
				</ComboBox>		
				<TextBox Name="FilterTextBox" HorizontalAlignment="Left" Height="26" Margin="5,0,0,0" TextWrapping="Wrap" 
				Text="" VerticalAlignment="Top" Width="172" Controls:TextBoxHelper.Watermark="Saisissez des mots clés ici"/>
				<Label Name="Actions_Count" Margin="5,0,0,0" FontWeight="Bold"/>
			</StackPanel>
	
			<StackPanel Margin="0,10,0,0">
				<DataGrid Name="DataGrid1" Height="250" VerticalAlignment="Top" Width="500" Margin="5,10,0,0"
				BorderBrush="{DynamicResource AccentColorBrush}" GridLinesVisibility="None"
				HeadersVisibility="None" BorderThickness="0" AutoGenerateColumns="True" SelectionMode="Single" IsReadOnly="True">	

					<DataGrid.Columns>							
						<DataGridTemplateColumn Width="auto" Header="+" >
							<DataGridTemplateColumn.CellTemplate>
								<DataTemplate>
									<StackPanel Orientation="Horizontal">
										<Button Name="Run_Remediation" Background="#2d89ef" Style="{DynamicResource MetroCircleButtonStyle}" 
											Height="23" Width="23" Cursor="Hand" HorizontalContentAlignment="Stretch" 
											VerticalContentAlignment="Stretch" HorizontalAlignment="Center" VerticalAlignment="Center" 
											BorderThickness="0" Margin="0,0,0,0">
											<iconPacks:PackIconMaterial Margin="3,0,0,0" Kind="play" Foreground="White" Height="10" Width="10" HorizontalAlignment="Center" VerticalAlignment="Center"/>                                                                                         
										</Button>    

										<Button Name="See_Issue_Info" Background="green" Style="{DynamicResource MetroCircleButtonStyle}" 
											Height="23" Width="23" Cursor="Hand" HorizontalContentAlignment="Stretch" 
											VerticalContentAlignment="Stretch" HorizontalAlignment="Center" VerticalAlignment="Center" 
											BorderThickness="0" Margin="0,0,0,0">
											<iconPacks:PackIconMaterial Kind="help" Foreground="White" Height="10" Width="10" HorizontalAlignment="Center" VerticalAlignment="Center"/>                                                                                         
										</Button>
									</StackPanel>
								</DataTemplate>
							</DataGridTemplateColumn.CellTemplate>
						</DataGridTemplateColumn>				
					</DataGrid.Columns>	

				</DataGrid>
			</StackPanel>
		</StackPanel>
	</Grid>
</Controls:MetroWindow>
'@

$reader=(New-Object System.Xml.XmlNodeReader $XamlMainWindow)  
$Form=[Windows.Markup.XamlReader]::Load($reader) 

$XamlMainWindow.SelectNodes("//*[@Name]") | %{
    try {Set-Variable -Name "$($_.Name)" -Value $Form.FindName($_.Name) -ErrorAction Stop}
    catch{throw}
}

$Fields = @(
    'Name'
    'Category'
	'Explanation'
	'Buttons'
	'Script'
	'Alerte_MSG'	
)

$List_Issues_XML = [xml](get-content ".\Issues_List.xml")
[array]$All_Actions = $List_Issues_XML.Actions.Action
$Actions = $All_Actions | Select-object $Fields

$Config_XML = [xml](get-content ".\Tool_Config.xml")
$GUI_Config = $Config_XML.GUI_Config

# $GUI_Config = $List_Issues_XML.Actions.GUI_Config
$Subtitle.Content = $GUI_Config.Subtitle_Text
$Run_solution_label.Content = $GUI_Config.Run_solution_Text
$Run_explanation_label.Content = $GUI_Config.Run_explanation_Text
$Run_Solution_Text = $GUI_Config.Warning_Click_Run_Solution_Text
$Run_Explanation_Text = $GUI_Config.Warning_Click_Run_Explanation_Text
$Tool_Version = $GUI_Config.Tool_Version
$Tool_Color = $GUI_Config.Tool_Color
# $Category_Text_Part1 = $GUI_Config.Expander_Category_Text_Part1
$Available_Actions_Count = $GUI_Config.Available_Actions_Count
$Show_Computer_Name = $GUI_Config.Show_Computer_Name
$Show_Support_Button = $GUI_Config.Show_Support_Button
$Window_Title = $GUI_Config.Window_Title
$Support_Phone_number = $GUI_Config.Support_Phone_number
$Support_Mail = $GUI_Config.Support_Mail
$Support_Phone_Label = $GUI_Config.Support_Phone_Label
$Support_Mail_Label = $GUI_Config.Support_Mail_Label
$Close_Button_Text = $GUI_Config.Close_Button_Text
$Issue_filter_KeyWord_Text = $GUI_Config.Issue_filter_KeyWord_Text
$Issue_filter_Title_Text = $GUI_Config.Issue_filter_Title_Text
$Combo_filter_Title_Text.Content = $Issue_filter_Title_Text

[MahApps.Metro.Controls.TextBoxHelper]::SetWatermark($FilterTextBox,$Issue_filter_KeyWord_Text)

# $About.Add_Click({
	# start-process -WindowStyle hidden powershell.exe "$current_folder\About.ps1"	
# })

If($Show_Computer_Name -eq $True)
	{
		# $Main_Title.Content = $GUI_Config.Main_Title_Text + " " + "($env:computername)"	+ " ?"
		$Main_Title.Content = $GUI_Config.Main_Title_Text + " " + "DEVICE1"	+ " ?"		
	}
Else
	{
		$Main_Title.Content = $GUI_Config.Main_Title_Text	
	}

$Theme = [MahApps.Metro.ThemeManager]::DetectAppStyle($form)	
[MahApps.Metro.ThemeManager]::ChangeAppStyle($form, [MahApps.Metro.ThemeManager]::GetAccent("$Tool_Color"), $Theme.Item1);	

Function Populate_Datagrid
	{
		param(
		[string]$Issue_Cat
		)		
		$Global:Datatable = New-Object System.Data.DataTable
		[void]$Datatable.Columns.AddRange($Fields)
		
		If($Issue_Cat -ne "All")
			{
				$Actions = $Actions | where {$_.category -eq "$Issue_Cat"}				
			}
		
		$Count = $Actions.Name.Count	
		$Actions_Count.Content = "$Count $Available_Actions_Count"				

		foreach($Action in $Actions)
		{
			$Array = @()
			Foreach($Field in $Fields)
			{
				$array += $Action.$Field
			}
			[void]$Datatable.Rows.Add($array)
		}		
		$DataGrid1.ItemsSource = $Datatable.DefaultView	
				
		$DataGrid1.columns[2].Visibility = "Collapsed"
		$DataGrid1.columns[3].Visibility = "Collapsed"
		$DataGrid1.columns[4].Visibility = "Collapsed"
		$DataGrid1.columns[5].Visibility = "Collapsed"
		$DataGrid1.columns[6].Visibility = "Collapsed"
		$DataGrid1.columns[0].DisplayIndex="2"
		$DataGrid1.columns[1].Width = "400"
		
		$FilterTextBox.Add_TextChanged({		
			$InputText = $FilterTextBox.Text
			$filter = "Name LIKE '%$InputText%'"
			$Datatable.DefaultView.RowFilter = $filter
		})
	}
	
	
$All_Categories = $List_Issues_XML.Actions.Action.Category | Sort-Object -Unique
foreach($Category in $All_Categories)
	{
		$Category_to_choose.Items.Add($Category)
		$Global:Selected_Category = $Category_to_choose.SelectedItem
	}

$Category_to_choose.add_SelectionChanged({
	$Script:Selected_Category = $Category_to_choose.SelectedItem
	Populate_Datagrid -Issue_Cat $Selected_Category	
	
	If($Category_to_choose.SelectedIndex -eq 0)
		{
			Populate_Datagrid -Issue_Cat "All"
		}
})

$DataGrid1.CanUserAddRows = $False
Populate_Datagrid -Issue_Cat "All"

$DataGrid1.Add_Loaded({
	$DataGrid1.columns[2].Visibility = "Collapsed"
	$DataGrid1.columns[3].Visibility = "Collapsed"
	$DataGrid1.columns[4].Visibility = "Collapsed"
	$DataGrid1.columns[5].Visibility = "Collapsed"
	$DataGrid1.columns[6].Visibility = "Collapsed"
	$DataGrid1.columns[0].DisplayIndex="2"
	$DataGrid1.columns[1].Width = "400"		
})


Function Run_Remediation($rowObj)
	{       	
		$Global:Reason = $rowObj.Explanation    
		$Global:Script_Name = $rowObj.Script    
		$Global:AlerteWarning = $rowObj.Alerte_MSG    
		$Global:AlerteButtons = $rowObj.Buttons    		

		If($AlerteButtons -eq "OK")
			{
				$MSG_Buttons = [MahApps.Metro.Controls.Dialogs.MessageDialogStyle]::Affirmative 
				$Button_Style = [MahApps.Metro.Controls.Dialogs.MetroDialogSettings]::new()
				$Button_Style.DialogTitleFontSize = "22"
				$Button_Style.DialogMessageFontSize = "14"								
				$Button_Style.AffirmativeButtonText = "Ok"
			}
		Else
			{
				$BTN_Split = $AlerteButtons.Split("_")
				$First_Button = $BTN_Split[0]
				$Second_Button = $BTN_Split[1]
				
				$MSG_Buttons = [MahApps.Metro.Controls.Dialogs.MessageDialogStyle]::AffirmativeAndNegative  
				$Button_Style = [MahApps.Metro.Controls.Dialogs.MetroDialogSettings]::new()
				$Button_Style.DialogTitleFontSize = "22"
				$Button_Style.DialogMessageFontSize = "14"								
				$Button_Style.AffirmativeButtonText = "$First_Button"
				$Button_Style.NegativeButtonText = "$Second_Button"				
			}	


		
		# If($AlerteButtons -eq "Ok")
			# {
				# $MSG_Buttons = [MahApps.Metro.Controls.Dialogs.MessageDialogStyle]::Affirmative 
				# $Button_Style = [MahApps.Metro.Controls.Dialogs.MetroDialogSettings]::new()
				# $Button_Style.DialogTitleFontSize = "22"
				# $Button_Style.DialogMessageFontSize = "14"								
				# $Button_Style.AffirmativeButtonText = "Ok"
			# }
		# Else
			# {				
				# $MSG_Buttons = [MahApps.Metro.Controls.Dialogs.MessageDialogStyle]::AffirmativeAndNegative  
				# $Button_Style = [MahApps.Metro.Controls.Dialogs.MetroDialogSettings]::new()
				# $Button_Style.DialogTitleFontSize = "22"
				# $Button_Style.DialogMessageFontSize = "14"								
				# $Button_Style.AffirmativeButtonText = "OK"
				# $Button_Style.NegativeButtonText = "Annuler"				
			# }				

		If($Script_Name -ne $null)
			{
				$result = [MahApps.Metro.Controls.Dialogs.DialogManager]::ShowModalMessageExternal($Form,"$Run_Solution_Text","$AlerteWarning",$MSG_Buttons, $Button_Style)   										
				If($result -eq "Affirmative")
					{
						start-process -WindowStyle hidden powershell.exe "$current_folder\Scripts_to_run\$Script_Name"	
					}							
			}
	}     

Function See_Details($rowObj)
	{             
		$Global:Reason = $rowObj.Explanation    		
		$MSG_Buttons = [MahApps.Metro.Controls.Dialogs.MessageDialogStyle]::Affirmative 
		$Button_Style = [MahApps.Metro.Controls.Dialogs.MetroDialogSettings]::new()
		$Button_Style.DialogTitleFontSize = "22"				
		$Button_Style.DialogMessageFontSize = "14"				
		$Button_Style.AffirmativeButtonText = "OK"									
		$result = [MahApps.Metro.Controls.Dialogs.DialogManager]::ShowModalMessageExternal($Form,"$Run_Explanation_Text","$Reason",$MSG_Buttons, $Button_Style)   					
	}   	

$DataGrid1.AddHandler(
	[System.Windows.Controls.Button]::ClickEvent, 
	[System.Windows.RoutedEventHandler]({
		$button =  $_.OriginalSource.Name
		$Script:resultObj = $this.CurrentItem
		If ($button -match "Run_Remediation" ){   
			Run_Remediation -rowObj $resultObj
		}
		ElseIf ($button -match "See_Issue_Info" ){
			See_Details -rowObj $resultObj
		}
	})
)	

#******************************************************************************
# Support contact dialog part
#******************************************************************************
If($Show_Support_Button -eq $True)
	{
		$Support_Info.Visibility = "Visible"
		$Support_Info.add_Click({
			[MahApps.Metro.Controls.Dialogs.DialogManager]::ShowMetroDialogAsync($form, $Dialog_Support)		
		})		
	}
Else
	{
		$Support_Info.Visibility = "Collapsed"
	}

function LoadXml ($global:filename)
{
	$XamlLoader=(New-Object System.Xml.XmlDocument)
	$XamlLoader.Load($filename)
	return $XamlLoader
}
$xamlDialog  = LoadXml(".\Dialog_Support.xaml")

$read=(New-Object System.Xml.XmlNodeReader $xamlDialog)
$DialogForm=[Windows.Markup.XamlReader]::Load($read)

$Dialog_Support = [MahApps.Metro.Controls.Dialogs.CustomDialog]::new($form)
$Dialog_Support.AddChild($DialogForm)

$Title_Label = $DialogForm.FindName("Title_Label")
$Phone_Number_Label = $DialogForm.FindName("Phone_Number_Label")
$Phone_Number = $DialogForm.FindName("Phone_Number")
$Mail_Label = $DialogForm.FindName("Mail_Label")
$Mail = $DialogForm.FindName("Mail")
$Close_Dialog = $DialogForm.FindName("Close_Dialog")
$Border = $DialogForm.FindName("Border")

$Title_Label.Content = $Window_Title
$Phone_Number_Label.Content = $Support_Phone_Label
$Phone_Number.Content = $Support_Phone_number
$Mail_Label.Content = $Support_Mail_Label
$Mail.Content = $Support_Mail
$Close_Dialog.Content = $Close_Button_Text

$Close_Dialog.Width = $Border.Width 

$Close_Dialog.add_Click({
	$Dialog_Support.RequestCloseAsync()
})

#******************************************************************************
# Filter on issues part end












#******************************************************************************
# Support contact dialog part
#******************************************************************************
# If($Show_Support_Button -eq $True)
	# {
		# $Support_Info.Visibility = "Visible"
		# $Support_Info.add_Click({
			# [MahApps.Metro.Controls.Dialogs.DialogManager]::ShowMetroDialogAsync($form, $Dialog_Support)		
		# })		
	# }
# Else
	# {
		# $Support_Info.Visibility = "Collapsed"
	# }
	
$About.add_Click({
	[MahApps.Metro.Controls.Dialogs.DialogManager]::ShowMetroDialogAsync($form, $Dialog_About)		
})			

function LoadXml ($global:filename)
{
	$XamlLoader=(New-Object System.Xml.XmlDocument)
	$XamlLoader.Load($filename)
	return $XamlLoader
}
$About_xamlDialog  = LoadXml(".\Dialog_About.xaml")

$About_read=(New-Object System.Xml.XmlNodeReader $About_xamlDialog)
$About_DialogForm=[Windows.Markup.XamlReader]::Load($About_read)

$Dialog_About = [MahApps.Metro.Controls.Dialogs.CustomDialog]::new($form)
$Dialog_About.AddChild($About_DialogForm)

$Close_Dialog = $About_DialogForm.FindName("Close_Dialog")
$Tool_Logo = $About_DialogForm.FindName("Tool_Logo")
$SelfX_Version = $About_DialogForm.FindName("SelfX_Version")

$Tool_Logo.Source = "logo.png"

$Issues_List_XML = [xml](get-content ".\Issues_List.xml")
$Current_XML_Version = $Issues_List_XML.Actions.XML_Version

$Tool_Config_XML = [xml](get-content ".\Tool_Config.xml")
$Tool_Version = $Tool_Config_XML.GUI_Config.Tool_Version

$Form.Title = "About SelfX"
$SelfX_Version.Content = "SelfX: v$Tool_Version - XML: $Current_XML_Version"

$Close_Dialog.add_Click({
	$Dialog_About.RequestCloseAsync()
})

#******************************************************************************
# Filter on issues part end


$Form.ShowDialog() | Out-Null 