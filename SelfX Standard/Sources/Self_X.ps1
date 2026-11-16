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
[System.Reflection.Assembly]::LoadFrom('assembly\AlertBarWpf.dll')       				| out-null

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

<Controls:MetroWindow.RightWindowCommands>
	<Controls:WindowCommands>
	   <Button x:Name="MonBouton" >
			<iconPacks:PackIconOcticons Kind="Paintcan" Margin="0,5,0,0" ToolTip="Change the main theme of the tool"/>													
		</Button>	
	</Controls:WindowCommands>	
</Controls:MetroWindow.RightWindowCommands>	

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
		xmlns:mbar="clr-namespace:AlertBarWpf;assembly=AlertBarWpf"		
        Title="Je me dépanne tout seul" Height="540" Width="700"
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
		   <Button Name="ChangeTheme" >
				<iconPacks:PackIconOcticons Kind="Paintcan" Margin="0,5,0,0" ToolTip="Change the main theme of the tool"/>													
			</Button>		
		
		   <Button Name="Support_Info">
				<iconPacks:PackIconFontAwesome Kind="phone"/>				
			</Button>		

		   <Button Name="About">
				<iconPacks:PackIconMaterial Kind="help"/>				
			</Button>		
		</Controls:WindowCommands>	
	</Controls:MetroWindow.RightWindowCommands>	

    <Grid>
		<Grid.RowDefinitions>
			<RowDefinition Height="*"/>
			<RowDefinition Height="Auto"/>
		</Grid.RowDefinitions>
		<TabControl Name="Main_Tabs" Grid.Row="0" Margin="5,0,5,0">
		<TabItem Name="Tab_Troubleshooting" Header="Troubleshooting" Controls:ControlsHelper.HeaderFontSize="15">
		<StackPanel Orientation="Vertical" HorizontalAlignment="Center" Margin="0,0,0,0">

			<StackPanel Orientation="Vertical" HorizontalAlignment="Center">
				<Label Name="Main_Title" HorizontalAlignment="Center" FontSize="18" FontWeight="Bold" Content="Un problème avec votre poste ?"/>	
				<Label Name="Subtitle" HorizontalAlignment="Center" FontWeight="Bold" Content="Vous trouverez peut-être un moyen de le résoudre ici au travers d'une liste de problèmes résoluble en un clic"/>						
								
				<StackPanel Margin="0,10,0,0" Orientation="Horizontal" HorizontalAlignment="Center">								
					<Button Background="#2d89ef" Style="{DynamicResource MetroCircleButtonStyle}" 
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
				<ComboBox Name="Solution_Mode" SelectedIndex="0" Text="Choose a category" Height="25" Width="115" Margin="0,0,0,0">
					<ComboBoxItem Name="Solution_Mode_Simple">Vue simplifiée</ComboBoxItem> 
					<ComboBoxItem Name="Solution_Mode_Detailed">Vue détaillée</ComboBoxItem> 					
				</ComboBox>		
				
				<Button Name="View" Margin="0,0,0,0" Background="gray" Style="{DynamicResource MetroCircleButtonStyle}" 
					Height="25" Width="25" Cursor="Hand" HorizontalContentAlignment="Stretch" 
					VerticalContentAlignment="Stretch" HorizontalAlignment="Center" VerticalAlignment="Center" 
					BorderThickness="0" >
					<iconPacks:PackIconMaterial Kind="help" Foreground="White" Height="11" Width="11" HorizontalAlignment="Center" VerticalAlignment="Center"/>                                                                                         
				</Button> 	

				<ComboBox Name="Category_to_choose" SelectedIndex="0" Text="Choose a category" Height="25" Width="160" Margin="3,0,0,0">
					<ComboBoxItem Name="Combo_filter_Title_Text">Trier par fonctionnalité</ComboBoxItem>
				</ComboBox>		
				
				<TextBox Name="FilterTextBox" HorizontalAlignment="Left" Height="26" Margin="5,0,0,0" TextWrapping="Wrap" 
				Text="" VerticalAlignment="Top" Width="152" Controls:TextBoxHelper.Watermark="Saisissez des mots clés ici"/>
				<Label Name="Actions_Count" Margin="5,0,0,0" FontWeight="Bold"/>
			</StackPanel>
	
			<StackPanel Margin="0,0,0,0">
				<DataGrid Name="DataGrid1" Height="250" VerticalAlignment="Top" Width="500" Margin="5,10,0,0"
				VirtualizingPanel.IsVirtualizingWhenGrouping="True" BorderBrush="{DynamicResource AccentColorBrush}" GridLinesVisibility="None"
				HeadersVisibility="None" BorderThickness="0" AutoGenerateColumns="True" SelectionMode="Single" IsReadOnly="True">	

				<DataGrid.Columns>								
					<DataGridTemplateColumn Width="auto" Header="+" DisplayIndex="2">
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
		</TabItem>

		<TabItem Name="Tab_SystemInfo" Header="System information" Controls:ControlsHelper.HeaderFontSize="15">
			<Grid Margin="10,5,10,0">
				<Grid.RowDefinitions>
					<RowDefinition Height="Auto"/>
					<RowDefinition Height="*"/>
					<RowDefinition Height="Auto"/>
					<RowDefinition Height="Auto"/>
				</Grid.RowDefinitions>

				<DockPanel Grid.Row="0" LastChildFill="True">
					<StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
						<Button Name="SysInfo_Refresh" Margin="3,0,0,0" Padding="8,2" Cursor="Hand">
							<StackPanel Orientation="Horizontal">
								<iconPacks:PackIconMaterial Kind="refresh" Height="12" Width="12" VerticalAlignment="Center"/>
								<TextBlock Name="SysInfo_Refresh_Label" Text="Refresh" Margin="5,0,0,0" VerticalAlignment="Center"/>
							</StackPanel>
						</Button>
						<Button Name="SysInfo_Copy" Margin="3,0,0,0" Padding="8,2" Cursor="Hand">
							<StackPanel Orientation="Horizontal">
								<iconPacks:PackIconMaterial Kind="contentcopy" Height="12" Width="12" VerticalAlignment="Center"/>
								<TextBlock Name="SysInfo_Copy_Label" Text="Copy all" Margin="5,0,0,0" VerticalAlignment="Center"/>
							</StackPanel>
						</Button>
						<Button Name="SysInfo_Export" Margin="3,0,0,0" Padding="8,2" Cursor="Hand">
							<StackPanel Orientation="Horizontal">
								<iconPacks:PackIconMaterial Kind="export" Height="12" Width="12" VerticalAlignment="Center"/>
								<TextBlock Name="SysInfo_Export_Label" Text="Export" Margin="5,0,0,0" VerticalAlignment="Center"/>
							</StackPanel>
						</Button>
					</StackPanel>
					<Label Name="SysInfo_Title" FontWeight="Bold" VerticalAlignment="Center" Content="Information about your device"/>
				</DockPanel>

				<Grid Grid.Row="1" Margin="0,5,0,0">
					<DataGrid Name="SysInfo_Grid" AutoGenerateColumns="False" IsReadOnly="True" SelectionMode="Single"
						HeadersVisibility="None" GridLinesVisibility="None" BorderThickness="0" CanUserSortColumns="False"
						BorderBrush="{DynamicResource AccentColorBrush}">
						<DataGrid.GroupStyle>
							<GroupStyle>
								<GroupStyle.HeaderTemplate>
									<DataTemplate>
										<TextBlock Text="{Binding Name}" FontWeight="Bold" Margin="3,8,0,2" Foreground="{DynamicResource AccentColorBrush}"/>
									</DataTemplate>
								</GroupStyle.HeaderTemplate>
							</GroupStyle>
						</DataGrid.GroupStyle>
						<DataGrid.Columns>
							<DataGridTextColumn Binding="{Binding Property}" Width="190"/>
							<DataGridTextColumn Binding="{Binding Value}" Width="*">
								<DataGridTextColumn.ElementStyle>
									<Style TargetType="TextBlock">
										<Setter Property="TextWrapping" Value="Wrap"/>
									</Style>
								</DataGridTextColumn.ElementStyle>
							</DataGridTextColumn>
						</DataGrid.Columns>
					</DataGrid>
					<loadin:LoadingIndicator Name="SysInfo_Loading" SpeedRatio="1" IsActive="False" Foreground="{DynamicResource AccentColorBrush}" HorizontalAlignment="Center" VerticalAlignment="Center" Style="{DynamicResource LoadingIndicatorArcsRingStyle}"/>
				</Grid>

				<Label Name="SysInfo_Status" Grid.Row="2" FontStyle="Italic" Content="Double-click a line to copy its value."/>

				<WrapPanel Name="SysInfo_Actions" Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,0,0,5">
					<Button Name="SysInfo_SyncApps" Content="Sync Intune apps" Margin="3" Padding="8,2" Cursor="Hand"/>
					<Button Name="SysInfo_SyncCompliance" Content="Check compliance" Margin="3" Padding="8,2" Cursor="Hand"/>
					<Button Name="SysInfo_CompanyPortal" Content="Company Portal" Margin="3" Padding="8,2" Cursor="Hand"/>
					<Button Name="SysInfo_QuickAssist" Content="Quick Assist" Margin="3" Padding="8,2" Cursor="Hand"/>
					<Button Name="SysInfo_MdmDiagnostics" Content="Collect MDM logs" Margin="3" Padding="8,2" Cursor="Hand"/>
				</WrapPanel>
			</Grid>
		</TabItem>
		</TabControl>

		<StackPanel Grid.Row="1" Margin="0,5,0,0">
			<mbar:AlertBarWpf Name="msgbar"/>
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

$Subtitle.Content = $GUI_Config.Subtitle_Text
$Run_solution_label.Content = $GUI_Config.Run_solution_Text
$Run_explanation_label.Content = $GUI_Config.Run_explanation_Text
$Run_Solution_Text = $GUI_Config.Warning_Click_Run_Solution_Text
$Run_Explanation_Text = $GUI_Config.Warning_Click_Run_Explanation_Text
$Tool_Version = $GUI_Config.Tool_Version
$Tool_Color = $GUI_Config.Tool_Color
$Tool_Theme = $GUI_Config.Tool_Theme
$Available_Actions_Count = $GUI_Config.Available_Actions_Count
$Show_Computer_Name_MainGUI = $GUI_Config.Show_Computer_Name_MainGUI
$Show_Computer_Name_title_bar = $GUI_Config.Show_Computer_Name_title_bar
$Show_Support_Button = $GUI_Config.Show_Support_Button
$Show_Theme_Button = $GUI_Config.Show_Theme_Button
$Show_About_Button = $GUI_Config.Show_About_Button
$Window_Title = $GUI_Config.Window_Title
$Support_Phone_number = $GUI_Config.Support_Phone_number
$Support_Mail = $GUI_Config.Support_Mail
$Support_Phone_Label = $GUI_Config.Support_Phone_Label
$Support_Mail_Label = $GUI_Config.Support_Mail_Label
$Close_Button_Text = $GUI_Config.Close_Button_Text
$Issue_filter_KeyWord_Text = $GUI_Config.Issue_filter_KeyWord_Text
$Issue_filter_Title_Text = $GUI_Config.Issue_filter_Title_Text
$Combo_filter_Title_Text.Content = $Issue_filter_Title_Text

$Tool_Name = $GUI_Config.Tool_Name

$Solution_Mode_Simple = $GUI_Config.Solution_Mode_Simple
$Solution_Mode_Detailed = $GUI_Config.Solution_Mode_Detailed
$Solution_Mode_Title = $GUI_Config.Solution_Mode_Info_Title
$Solution_Mode_Text = $GUI_Config.Solution_Mode_Info_Text
$Reboot_Alert_Warning = $GUI_Config.Reboot_Alert
$Display_Reboot_Alert = $GUI_Config.Show_Reboot_Warning
$Default_Solution_Mode = $GUI_Config.Default_Solution_Mode

$Solution_Mode.Items[0] = $Solution_Mode_Simple
$Solution_Mode.Items[1] = $Solution_Mode_Detailed

If($Default_Solution_Mode -eq "Simplified")
{
	$Solution_Mode.SelectedIndex="0"	
}
ElseIf($Default_Solution_Mode -eq "Detailed")
{
	$Solution_Mode.SelectedIndex="1"
}
Else
{
	$Solution_Mode.SelectedIndex="0"	
}

[MahApps.Metro.Controls.TextBoxHelper]::SetWatermark($FilterTextBox,$Issue_filter_KeyWord_Text)

$Theme = [MahApps.Metro.ThemeManager]::DetectAppStyle($form)	

If($Tool_Theme -eq "Dark")
	{
		[MahApps.Metro.ThemeManager]::ChangeAppStyle($form, $Theme.Item2, [MahApps.Metro.ThemeManager]::GetAppTheme("BaseDark")); 	
	}
ElseIf($Tool_Theme -eq "Light")
	{
		[MahApps.Metro.ThemeManager]::ChangeAppStyle($form, $Theme.Item2, [MahApps.Metro.ThemeManager]::GetAppTheme("BaseLight"));   	
	}
ElseIf($Tool_Theme -eq $null)
	{
		[MahApps.Metro.ThemeManager]::ChangeAppStyle($form, $Theme.Item2, [MahApps.Metro.ThemeManager]::GetAppTheme("BaseDark"));   	
	}	

$Theme = [MahApps.Metro.ThemeManager]::DetectAppStyle($form)	
[MahApps.Metro.ThemeManager]::ChangeAppStyle($form, [MahApps.Metro.ThemeManager]::GetAccent("$Tool_Color"), $Theme.Item1);	

Function Populate_Datagrid
	{
		param(
		[string]$Issue_Cat
		)		
		

		If($Solution_Mode.SelectedIndex -eq 0)
			{
				[array]$All_Actions = $List_Issues_XML.Actions.Quick_Solution.Action
				$Actions = $All_Actions | Select-object $Fields					
			}
		ElseIf($Solution_Mode.SelectedIndex -eq 1)
			{
				[array]$All_Actions = $List_Issues_XML.Actions.Detailed_Solution.Action
				$Actions = $All_Actions | Select-object $Fields						
			}

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

If($Solution_Mode.SelectedIndex -eq 0)
	{
		[array]$All_Actions = $List_Issues_XML.Actions.Quick_Solution.Action
		$Actions = $All_Actions | Select-object $Fields		
		
		$All_Categories = $List_Issues_XML.Actions.Quick_Solution.Action.Category | Sort-Object -Unique
		foreach($Category in $All_Categories)
			{
				$Category_to_choose.Items.Add($Category)
				$Global:Selected_Category = $Category_to_choose.SelectedItem
			}		
	}
ElseIf($Solution_Mode.SelectedIndex -eq 1)
	{
		[array]$All_Actions = $List_Issues_XML.Actions.Detailed_Solution.Action
		$Actions = $All_Actions | Select-object $Fields		
		
		$All_Categories = $List_Issues_XML.Actions.Detailed_Solution.Action.Category | Sort-Object -Unique
		foreach($Category in $All_Categories)
			{
				$Category_to_choose.Items.Add($Category)
				$Global:Selected_Category = $Category_to_choose.SelectedItem
			}		
	}

$View.add_Click({
	$MSG_Buttons = [MahApps.Metro.Controls.Dialogs.MessageDialogStyle]::Affirmative 
	$Button_Style = [MahApps.Metro.Controls.Dialogs.MetroDialogSettings]::new()
	$Button_Style.DialogTitleFontSize = "22"
	$Button_Style.DialogMessageFontSize = "14"								
	$Button_Style.AffirmativeButtonText = "Ok"	
	$result = [MahApps.Metro.Controls.Dialogs.DialogManager]::ShowModalMessageExternal($Form,$Solution_Mode_Title,$Solution_Mode_Text,$MSG_Buttons, $Button_Style) 	
})

$Solution_Mode.add_SelectionChanged({	
	If($Solution_Mode.SelectedIndex -eq 0)
		{			
			$Category_to_choose.Items.Clear()
			$Category_to_choose.Items.Add($Issue_filter_Title_Text)			
			$Category_to_choose.SelectedIndex = 0
						
			$All_Categories = $List_Issues_XML.Actions.Quick_Solution.Action.Category | Sort-Object -Unique
			foreach($Category in $All_Categories)
				{					
					$Category_to_choose.Items.Add($Category)
					$Global:Selected_Category = $Category_to_choose.SelectedItem
				}			
			
			[array]$All_Actions = $List_Issues_XML.Actions.Quick_Solution.Action
			$Actions = $All_Actions | Select-object $Fields	
			Populate_Datagrid -Issue_Cat "All"
		}	
	ElseIf($Solution_Mode.SelectedIndex -eq 1)
		{
			$Category_to_choose.Items.Clear()
			$Category_to_choose.Items.Add($Issue_filter_Title_Text)						
			$Category_to_choose.SelectedIndex = 0
			
			$All_Categories = $List_Issues_XML.Actions.Detailed_Solution.Action.Category | Sort-Object -Unique
			foreach($Category in $All_Categories)
				{
					$Category_to_choose.Items.Add($Category)
					$Global:Selected_Category = $Category_to_choose.SelectedItem
				}			
			
			[array]$All_Actions = $List_Issues_XML.Actions.Detailed_Solution.Action
			$Actions = $All_Actions | Select-object $Fields				
			Populate_Datagrid -Issue_Cat "All"
		}			
})

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

If($Display_Reboot_Alert -eq $True)
	{
		$msgbar.Clear();
		$msgbar.SetDangerAlert("$Reboot_Alert_Warning");
	}

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


If($Show_Theme_Button -eq $True)
	{		
		$ChangeTheme.Visibility = "Visible"
		$ChangeTheme.Add_Click({
		$Theme = [MahApps.Metro.ThemeManager]::DetectAppStyle($form) 
		$my_theme = ($Theme.Item1).name
		If($my_theme -eq "BaseLight")
			{ 
				[MahApps.Metro.ThemeManager]::ChangeAppStyle($form, $Theme.Item2, [MahApps.Metro.ThemeManager]::GetAppTheme("BaseDark"));  
			}
		ElseIf($my_theme -eq "BaseDark")
			{     
				[MahApps.Metro.ThemeManager]::ChangeAppStyle($form, $Theme.Item2, [MahApps.Metro.ThemeManager]::GetAppTheme("BaseLight"));   
			}  
		})

	}
Else
	{
		$ChangeTheme.Visibility = "Collapsed"	
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

$Tool_Config_XML = [xml](get-content ".\Tool_Config.xml")
$Tool_Version = $Tool_Config_XML.GUI_Config.Tool_Version
$Tool_Name = $Tool_Config_XML.GUI_Config.Tool_Name

#******************************************************************************
# About dialog part
#******************************************************************************
If($Show_About_Button -eq $True)
	{
		$About.Visibility = "Visible"

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
		# $Tool_Logo = $About_DialogForm.FindName("Tool_Logo")
		$SelfX_Version = $About_DialogForm.FindName("SelfX_Version")

		# $Tool_Logo.Source = "logo.png"

		$Issues_List_XML = [xml](get-content ".\Issues_List.xml")
		$Current_XML_Version = $Issues_List_XML.Actions.XML_Version
		$SelfX_Version.Content = $Tool_Name + ": v$Tool_Version - XML: $Current_XML_Version"

		$Close_Dialog.add_Click({
			$Dialog_About.RequestCloseAsync()
		})	
	}
Else
	{
		$About.Visibility = "Collapsed"
	}


$Config_XML = [xml](get-content ".\Tool_Config.xml")
$GUI_Config = $Config_XML.GUI_Config
$Show_Computer_Name_MainGUI = $GUI_Config.Show_Computer_Name_MainGUI
$Show_Computer_Name_title_bar = $GUI_Config.Show_Computer_Name_title_bar

If($Show_Computer_Name_MainGUI -eq $True)
	{
		$Main_Title.Content = $GUI_Config.Main_Title_Text + " " + "($env:computername)"	+ " ?"
	}
Else
	{
		$Main_Title.Content = $GUI_Config.Main_Title_Text	
	}

If($Show_Computer_Name_title_bar -eq $True)
	{
		$Main_Title.Content = $GUI_Config.Main_Title_Text + " " + "($env:computername)"	+ " ?"
		$Form.Title = $Tool_Name + " " + "($env:computername)"			
	}
Else
	{
		$Form.Title = $Tool_Name
	}

#******************************************************************************
# System information tab
# Idea and data points based on https://github.com/JayRHa/windows-system-information (MIT)
#******************************************************************************
Function Get-SelfXConfigValue
{
	param(
	[string]$Name,
	[string]$Default
	)
	$Value = $GUI_Config.$Name
	If([string]::IsNullOrWhiteSpace($Value)) { return $Default }
	return $Value.Trim()
}

$Show_SystemInfo_Tab = Get-SelfXConfigValue "Show_SystemInfo_Tab" "True"
$Tab_Troubleshooting.Header = Get-SelfXConfigValue "Troubleshooting_Tab_Text" "Troubleshooting"

If($Show_SystemInfo_Tab -ne $True)
{
	$Tab_SystemInfo.Visibility = "Collapsed"
}
Else
{
	. "$Current_Folder\SystemInfo.ps1"

	$Global:SysInfo_Items = @()
	$Global:SysInfo_Loaded = $False
	$SysInfo_Hint_Text = Get-SelfXConfigValue "SystemInfo_Hint_Text" "Double-click a line to copy its value."
	$SysInfo_Copied_Text = Get-SelfXConfigValue "SystemInfo_Copied_Text" "Copied to clipboard:"
	$SysInfo_Loading_Text = Get-SelfXConfigValue "SystemInfo_Loading_Text" "Collecting system information..."
	$SysInfo_Test_Host = Get-SelfXConfigValue "SystemInfo_Internet_Test_Host" "www.msftconnecttest.com"
	$SysInfo_Test_Port = [int](Get-SelfXConfigValue "SystemInfo_Internet_Test_Port" "80")

	$Tab_SystemInfo.Header = Get-SelfXConfigValue "SystemInfo_Tab_Text" "System information"
	$SysInfo_Title.Content = Get-SelfXConfigValue "SystemInfo_Title_Text" "Information about your device"
	$SysInfo_Refresh_Label.Text = Get-SelfXConfigValue "SystemInfo_Refresh_Text" "Refresh"
	$SysInfo_Copy_Label.Text = Get-SelfXConfigValue "SystemInfo_Copy_Text" "Copy all"
	$SysInfo_Export_Label.Text = Get-SelfXConfigValue "SystemInfo_Export_Text" "Export"
	$SysInfo_SyncApps.Content = Get-SelfXConfigValue "SystemInfo_SyncApps_Text" "Sync Intune apps"
	$SysInfo_SyncCompliance.Content = Get-SelfXConfigValue "SystemInfo_SyncCompliance_Text" "Check compliance"
	$SysInfo_CompanyPortal.Content = Get-SelfXConfigValue "SystemInfo_CompanyPortal_Text" "Company Portal"
	$SysInfo_QuickAssist.Content = Get-SelfXConfigValue "SystemInfo_QuickAssist_Text" "Quick Assist"
	$SysInfo_MdmDiagnostics.Content = Get-SelfXConfigValue "SystemInfo_MdmDiagnostics_Text" "Collect MDM logs"
	$SysInfo_Status.Content = $SysInfo_Hint_Text

	If((Get-SelfXConfigValue "Show_SystemInfo_Intune_Actions" "True") -ne $True)
		{
			$SysInfo_Actions.Visibility = "Collapsed"
		}

	Function Set-SysInfoBusy
		{
			param([bool]$Busy)
			$SysInfo_Loading.IsActive = $Busy
			$SysInfo_Loading.Visibility = $(If($Busy){"Visible"}Else{"Collapsed"})
			$SysInfo_Refresh.IsEnabled = -not $Busy
			$SysInfo_Copy.IsEnabled = -not $Busy
			$SysInfo_Export.IsEnabled = -not $Busy
			If($Busy){ $SysInfo_Status.Content = $SysInfo_Loading_Text } Else { $SysInfo_Status.Content = $SysInfo_Hint_Text }
		}

	Function Show-SysInfoItems
		{
			$SysInfo_Table = New-Object System.Data.DataTable
			[void]$SysInfo_Table.Columns.AddRange(@("Category","Property","Value"))
			foreach($Item in $Global:SysInfo_Items)
				{
					[void]$SysInfo_Table.Rows.Add($Item.Category, $Item.Property, $Item.Value)
				}
			$SysInfo_View = New-Object System.Windows.Data.BindingListCollectionView -ArgumentList (,$SysInfo_Table.DefaultView)
			$SysInfo_View.GroupDescriptions.Add((New-Object System.Windows.Data.PropertyGroupDescription("Category")))
			$SysInfo_Grid.ItemsSource = $SysInfo_View
		}

	# Collect in a background runspace so the window stays responsive.
	# The collector is passed as text, so it is not subject to the script execution policy of the new runspace.
	$Global:SysInfo_Script = Get-Content -Path "$Current_Folder\SystemInfo.ps1" -Raw
	$Global:SysInfo_Timer = New-Object System.Windows.Threading.DispatcherTimer
	$SysInfo_Timer.Interval = [TimeSpan]::FromMilliseconds(300)
	$SysInfo_Timer.Add_Tick({
		If($Global:SysInfo_Handle.IsCompleted)
			{
				$SysInfo_Timer.Stop()
				Try
					{
						$Global:SysInfo_Items = @($Global:SysInfo_PS.EndInvoke($Global:SysInfo_Handle))
					}
				Catch
					{
						$Global:SysInfo_Items = @([pscustomobject]@{Category="Report";Property="Error";Value=$_.Exception.Message})
					}
				$Global:SysInfo_PS.Dispose()
				Show-SysInfoItems
				Set-SysInfoBusy $False
			}
	})

	Function Start-SysInfoCollection
		{
			Set-SysInfoBusy $True
			$Global:SysInfo_PS = [PowerShell]::Create()
			[void]$Global:SysInfo_PS.AddScript($Global:SysInfo_Script + "`r`nGet-SelfXSystemInfo -InternetTestHost '$($SysInfo_Test_Host -replace "'", "''")' -InternetTestPort $SysInfo_Test_Port")
			$Global:SysInfo_Handle = $Global:SysInfo_PS.BeginInvoke()
			$SysInfo_Timer.Start()
			$Global:SysInfo_Loaded = $True
		}

	Set-SysInfoBusy $False

	$Main_Tabs.Add_SelectionChanged({
		If(($Main_Tabs.SelectedItem -eq $Tab_SystemInfo) -and (-not $Global:SysInfo_Loaded))
			{
				Start-SysInfoCollection
			}
	})

	$SysInfo_Refresh.Add_Click({ Start-SysInfoCollection })

	$SysInfo_Copy.Add_Click({
		If($Global:SysInfo_Items.Count -gt 0)
			{
				[System.Windows.Clipboard]::SetText((ConvertTo-SelfXSystemInfoText -Items $Global:SysInfo_Items))
				$SysInfo_Status.Content = $SysInfo_Copied_Text + " " + $Tab_SystemInfo.Header
			}
	})

	$SysInfo_Grid.Add_MouseDoubleClick({
		$Selected = $SysInfo_Grid.SelectedItem
		If($Selected -ne $null)
			{
				[System.Windows.Clipboard]::SetText([string]$Selected["Value"])
				$SysInfo_Status.Content = $SysInfo_Copied_Text + " " + $Selected["Property"]
			}
	})

	$SysInfo_Export.Add_Click({
		If($Global:SysInfo_Items.Count -eq 0) { return }
		$SaveDialog = New-Object Microsoft.Win32.SaveFileDialog
		$SaveDialog.FileName = "SystemInfo_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmm')"
		$SaveDialog.InitialDirectory = [Environment]::GetFolderPath("Desktop")
		$SaveDialog.Filter = "Text file (*.txt)|*.txt|HTML file (*.html)|*.html|CSV file (*.csv)|*.csv|JSON file (*.json)|*.json"
		If($SaveDialog.ShowDialog($Form))
			{
				Try
					{
						Export-SelfXSystemInfo -Items $Global:SysInfo_Items -Path $SaveDialog.FileName
						$SysInfo_Status.Content = $SaveDialog.FileName
					}
				Catch
					{
						$SysInfo_Status.Content = $_.Exception.Message
					}
			}
	})

	Function Invoke-SysInfoAction
		{
			param([scriptblock]$Action)
			Try { & $Action } Catch { $SysInfo_Status.Content = $_.Exception.Message }
		}

	$SysInfo_SyncApps.Add_Click({ Invoke-SysInfoAction { Start-Process "intunemanagementextension://syncapp" } })
	$SysInfo_SyncCompliance.Add_Click({ Invoke-SysInfoAction { Start-Process "intunemanagementextension://synccompliance" } })
	$SysInfo_CompanyPortal.Add_Click({ Invoke-SysInfoAction { Start-Process "explorer.exe" -ArgumentList "shell:AppsFolder\Microsoft.CompanyPortal_8wekyb3d8bbwe!App" } })
	$SysInfo_QuickAssist.Add_Click({
		Invoke-SysInfoAction {
			$QuickAssist_Exe = "$env:SystemRoot\System32\quickassist.exe"
			If(Test-Path $QuickAssist_Exe) { Start-Process $QuickAssist_Exe } Else { Start-Process "ms-quick-assist:" }
		}
	})
	$SysInfo_MdmDiagnostics.Add_Click({
		Invoke-SysInfoAction {
			$Mdm_Folder = Join-Path $env:TEMP "SelfX_MDMDiagnostics"
			Start-Process "cmd.exe" -ArgumentList "/c MdmDiagnosticsTool.exe -out `"$Mdm_Folder`" & explorer.exe `"$Mdm_Folder`"" -WindowStyle Hidden
			$SysInfo_Status.Content = $Mdm_Folder
		}
	})
}
	
$Form.ShowDialog() | Out-Null 