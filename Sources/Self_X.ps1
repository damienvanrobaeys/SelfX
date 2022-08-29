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
$Current_XML_Version = $GUI_Config.Actions.GUI_Config.XML_Version

$List_config_XML = [xml](get-content ".\List_config.xml")
$Config_Type = $List_config_XML.Issues_XML_Config.Type
If($Config_Type -eq "Download")
	{
		Launch_modal_progress
		$Config_Link = $List_config_XML.Issues_XML_Config.Link_XML
		$Issues_List_File = "$env:temp\Issues_List.xml"		
		Invoke-WebRequest -Uri $Config_Link -OutFile $Issues_List_File -UseBasicParsing | out-null			
		$New_XML = [xml](get-content $Issues_List_File)		
		$New_XML_Version = $New_XML.Actions.GUI_Config.XML_Version
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
				
$XML_Content = @()
$Depannage_Actions_XML = [xml](get-content ".\Issues_List.xml")
$All_Categories = $Depannage_Actions_XML.Actions.Action.Category | Sort-Object -Unique
ForEach($Category in $All_Categories)
	{	
		$Expander_Content = @"
		<Expander Name="Expander_$Category" Background="Transparent" IsExpanded="True" Width="550" BorderThickness="0" Margin="0,10,0,0" HorizontalAlignment="Center">
			<Expander.Resources>
				<Style TargetType="{x:Type Expander}">
				<Setter Property="BorderThickness" Value="1"/>
				<Setter Property="BorderBrush" Value="DarkGray"/>
				<Setter Property="Foreground" Value="#202020"/>
				<Setter Property="Background" Value="#D0D0D0"/>
				</Style>
			</Expander.Resources>

			<Expander.Header>
			 <BulletDecorator>
				<TextBlock Name="Title_$Category" FontSize="15" FontWeight="Bold" Foreground="#C9C6D3" Text="Dépanner $Category" HorizontalAlignment="Stretch" />							   
			 </BulletDecorator>																	
			</Expander.Header>
						
			<DataGrid HeadersVisibility="None" GridLinesVisibility="None"  BorderBrush="{DynamicResource AccentColorBrush}"	
			Margin="-3,0,0,0" Height="auto" Width="500" BorderThickness="0" AutoGenerateColumns="True" SelectionMode="Extended"  
			Name="DataGrid_$Category"  ItemsSource="{Binding}"   >										
				<DataGrid.Columns>	
					<DataGridTextColumn FontSize="12" Width="400" Header="Action" Binding="{Binding Action, Mode=OneWay}"/>	
					
					<DataGridTemplateColumn Width="auto" Header="+">
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
		</Expander>			
"@   	
$XML_Content += $Expander_Content	
	}	



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
Width="700" 
Height="400"  
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
	   <Button Name="Search_Issue">
			<iconPacks:PackIconMaterial Kind="magnify"/>				
		</Button>		
	   <Button Name="About">
			<iconPacks:PackIconMaterial Kind="help"/>				
		</Button>		
	</Controls:WindowCommands>	
</Controls:MetroWindow.RightWindowCommands>		

    <Grid>		
		<StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">	
			<StackPanel Margin="0,0,0,0"  HorizontalAlignment="Center" VerticalAlignment="Center">

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
				
				<ScrollViewer CanContentScroll="True" Height="230" HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto">  						
					<StackPanel Orientation="Horizontal" HorizontalAlignment="Center"  Margin="0,10,0,0">		
						<StackPanel Orientation="Vertical"  Margin="70,0,0,0" HorizontalAlignment="Center">
							<StackPanel Margin="0,-10,0,0" HorizontalAlignment="Center">						
								$XML_Content
							</StackPanel>							
						</StackPanel>  					
					</StackPanel>							
				</ScrollViewer>							
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

$About.Add_Click({
	start-process -WindowStyle hidden powershell.exe "$current_folder\About.ps1"	
})

$GUI_Config = $Depannage_Actions_XML.Actions.GUI_Config
$Main_Title.Content = $GUI_Config.Main_Title_Text
$Subtitle.Content = $GUI_Config.Subtitle_Text
$Run_solution_label.Content = $GUI_Config.Run_solution_Text
$Run_explanation_label.Content = $GUI_Config.Run_explanation_Text
$Run_Solution_Text = $GUI_Config.Warning_Click_Run_Solution_Text
$Run_Explanation_Text = $GUI_Config.Warning_Click_Run_Explanation_Text
$Tool_Version = $GUI_Config.Tool_Version
$Tool_Color = $GUI_Config.Tool_Color
$Category_Text_Part1 = $GUI_Config.Expander_Category_Text_Part1
$Category_Text_Part2 = $GUI_Config.Expander_Category_Text_Part2

$Theme = [MahApps.Metro.ThemeManager]::DetectAppStyle($form)	
[MahApps.Metro.ThemeManager]::ChangeAppStyle($form, [MahApps.Metro.ThemeManager]::GetAccent("$Tool_Color"), $Theme.Item1);	

$Form.Title = "SelfX (Self fix)"

$All_Categories = $Depannage_Actions_XML.Actions.Action.Category | Sort-Object -Unique
ForEach($Category in $All_Categories)
	{
		$Actions = $Depannage_Actions_XML.Actions.Action | where {$_.category -eq "$Category"}	
		$Actions_count = $Actions.Name.Count
		
		If($Actions_count -eq 0)
			{	
				$Form.FindName("Expander_$Category").Visibility = 'Collapsed'
			}
		Else
			{
				$Form.FindName("Expander_$Category").Visibility = 'Visible'
			}			

		$Form.FindName("Title_$Category").Text = "$Category_Text_Part1 $Category ($Actions_count $Category_Text_Part2"

		ForEach($Action_Value in $Actions)
			{
				$Name = $Action_Value.Name
				$Explanation = $Action_Value.Explanation
				$Script = $Action_Value.Script						
				$RemediationType = $Action_Value.Remediation_Type    
				$Alerte_warning = $Action_Value.Alerte_MSG    
				$Alerte_Buttons = $Action_Value.Buttons    				

				$Obj = New-Object PSObject
				$Obj = $Obj | Add-Member NoteProperty Action $Name -passthru   
				$Obj = $Obj | Add-Member NoteProperty Explanation $Explanation -passthru
				$Obj = $Obj | Add-Member NoteProperty Script $Script -passthru	
				$Obj = $Obj | Add-Member NoteProperty Remediation_Type $RemediationType -passthru				
				$Obj = $Obj | Add-Member NoteProperty Alerte_warning $Alerte_warning -passthru				
				$Obj = $Obj | Add-Member NoteProperty Alerte_Buttons $Alerte_Buttons -passthru								
				$Form.FindName("DataGrid_$Category").Items.Add($Obj) > $null
			}

		$Form.FindName("DataGrid_$Category").AddHandler(
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
	}	

Function Run_Remediation($rowObj)
	{       	
		$Global:Reason = $rowObj.Explanation    
		$Global:Script_Name = $rowObj.Script    
		$Global:AlerteWarning = $rowObj.Alerte_Warning    
		$Global:AlerteButtons = $rowObj.Alerte_Buttons    		
		
		If($AlerteButtons -eq "Ok")
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


function LoadXml ($global:filename)
{
	$XamlLoader=(New-Object System.Xml.XmlDocument)
	$XamlLoader.Load($filename)
	return $XamlLoader
}
$xamlDialog  = LoadXml(".\Dialog_Search.xaml")

$read=(New-Object System.Xml.XmlNodeReader $xamlDialog)
$DialogForm=[Windows.Markup.XamlReader]::Load($read)

$Dialog_Search = [MahApps.Metro.Controls.Dialogs.CustomDialog]::new($form)
$Dialog_Search.AddChild($DialogForm)

$Category_to_choose = $DialogForm.FindName("Category_to_choose")
$Issue_KeyWord = $DialogForm.FindName("Issue_KeyWord")
$Category_Label = $DialogForm.FindName("Category_Label")
$Title_Label = $DialogForm.FindName("Title_Label")
$KeyWord_Label = $DialogForm.FindName("KeyWord_Label")
$Search = $DialogForm.FindName("Search")
$Close_Dialog = $DialogForm.FindName("Close_Dialog")
$Border = $DialogForm.FindName("Border")

$Title_Label.Content = $GUI_Config.Issue_filter_Title_Text
$Category_Label.Content = $GUI_Config.Issue_filter_Category_Text
$KeyWord_Label.Content = $GUI_Config.Issue_filter_KeyWord_Text
$Search.Content = $GUI_Config.Issue_filter_SearchButton_Text
$Close_Dialog.Content = $GUI_Config.Issue_filter_CloseButton_Text

# $Close_Dialog.Background = "$Tool_Color"
# $Search.Background = "$Tool_Color"
# $Border.BorderBrush = "$Tool_Color"

$Dir_Sources_Folder = get-childitem $Sources_Folder -recurse
$List_All_Files = $Dir_Sources_Folder | where { ! $_.PSIsContainer }		

$All_Categories = $Depannage_Actions_XML.Actions.Action.Category | Sort-Object -Unique
foreach($Category in $All_Categories)
	{
		$Category_to_choose.Items.Add($Category)	
		$Global:Selected_Category = $Category_to_choose.SelectedItem	

		$Category_to_choose.add_SelectionChanged({
			$Script:Selected_Category = $Category_to_choose.SelectedItem
		})			
	}	

$Close_Dialog.add_Click({
	$Dialog_Search.RequestCloseAsync()
})

$Search_Issue.add_Click({
	[MahApps.Metro.Controls.Dialogs.DialogManager]::ShowMetroDialogAsync($form, $Dialog_Search)		
})

	  	  
$Search.Add_Click({
$All_Categories = $Depannage_Actions_XML.Actions.Action.Category | Sort-Object -Unique
Add-Type -AssemblyName PresentationCore,PresentationFramework

foreach($Category in $All_Categories)
	{
		$Form.FindName("DataGrid_$Category").UnSelectAll()
		$Get_TextBox_Value = $Issue_KeyWord.Text.ToString()	
		$Datagrid_Log_Count = $Form.FindName("DataGrid_$Category").Items.Count	
		
		ForEach($Log in $Form.FindName("DataGrid_$Category").Items)
			{
				# For ($i = 0; $i -lt $Datagrid_Log_Count; $i++)
				# {				
					If($Log.Action -like "*$Get_TextBox_Value*")
						{	
							$Form.FindName("DataGrid_$Category").SelectedItem = $Log#[$i]	
							# break
						}
					
				# }
			}
		$Dialog_Search.RequestCloseAsync()	
	}	
})		  

$Form.ShowDialog() | Out-Null 