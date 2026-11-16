<#
.SYNOPSIS
    Run isolated tests of the SelfX user interface, the tray icon and the theme without showing a window.
.DESCRIPTION
    Loads the XAML of the main window and the dialogs (without showing them), checks the theme colors of the
    branding, the notification logic of the tray icon, the per-user cache of the system information and that
    every text used by Self_X.ps1 and SelfX_Tray.ps1 exists in Languages\en.xml.
    No window is shown, no process is started, no service is contacted and no setting of the user is changed;
    files are written only to a temporary folder. Start-Process and the scheduled task cmdlets are mocked.
    Run in Windows PowerShell 5.1 (STA): powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-UI.ps1
.NOTES
    Version: 2.6.7
    History:
    2.5.0  2026-11-04  Wolfgang Baeck  Initial UI tests (modern UI, tray icon, theme, caches).
    2.5.3  2026-11-04  Wolfgang Baeck  Test that SelfX and the status icon start without a console window.
    2.5.9  2026-11-05  Wolfgang Baeck  Test the language selection of the user (settings, restart, status icon).
    2.5.10 2026-11-06  Wolfgang Baeck  Test the connection types of the network section (virtual machines, VPN) and the
                                       local time of the last Intune sync.
    2.6.1  2026-11-06  Wolfgang Baeck  Test the running state of the start buttons (user actions watched until they end).
    2.6.2  2026-11-06  Wolfgang Baeck  Test the own taskbar identity (SelfX icon instead of PowerShell).
    2.6.5  2026-11-06  Wolfgang Baeck  Test the notifications switch of the user (status icon).
    2.6.6  2026-11-06  Wolfgang Baeck  Test the appearance Automatic (app mode of Windows).
    2.6.7  2026-11-16  Wolfgang Baeck  Test the default appearance Automatic.
#>
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerShell.Utility
Import-Module Microsoft.PowerShell.Management
$PSModuleAutoLoadingPreference = 'None'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing, System.Windows.Forms
$sources = Join-Path $PSScriptRoot 'Sources'

$script:assertions = 0
function Assert-Equal($Actual, $Expected, $Message) {
    $script:assertions++
    if ($Actual -ne $Expected) { throw "$Message : expected '$Expected', got '$Actual'." }
}

function Start-Process { throw 'Start-Process is not allowed in tests' }
function Register-ScheduledTask { throw 'Forbidden in tests' }
function New-ScheduledTask { throw 'Forbidden in tests' }
foreach ($name in 'Start-Process', 'Register-ScheduledTask', 'New-ScheduledTask') { Assert-Equal (Get-Command $name).CommandType Function "Mock resolution: $name" }

. "$sources\Branding.ps1"
. "$sources\Localization.ps1"
. "$sources\SelfXServiceClient.ps1"
. "$sources\SystemInfo.ps1"
# Logger functions without Initialize-SelfXLog: they write nothing during the tests.
. "$sources\SelfXLog.ps1"
[void](Initialize-SelfXLanguage -LanguageFolder "$sources\Languages" -Language 'en')

function Get-ScriptAst([string]$Path) { [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null) }
function Get-FunctionText($Ast, [string]$Name) {
    $node = $Ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name }, $true)
    if (-not $node) { throw "Function $Name not found" }
    return $node.Extent.Text
}
function Get-AssignedText($Ast, [string]$Variable) {
    $node = $Ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq $Variable -and
        $n.Right.Extent.Text.StartsWith("@'") }, $true)
    if (-not $node) { throw "Assignment $Variable not found" }
    return $node.Right.Expression.Value
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ('SelfXUiTests-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
try {
    # --- Theme and branding ---------------------------------------------------------------------
    Assert-Equal (Get-SelfXAccentColor -BrandColor '' -ToolColor 'Teal').ToString() '#FF00ABA9' 'Named Tool_Color'
    Assert-Equal (Get-SelfXAccentColor -BrandColor '' -ToolColor 'Unknown').ToString() '#FF1BA1E2' 'Unknown Tool_Color uses Cyan'
    Assert-Equal (Get-SelfXAccentColor -BrandColor '#E20074' -ToolColor 'Teal').ToString() '#FFE20074' 'Brand_Accent_Color wins'
    $dark = New-SelfXThemeColors -Theme Dark -Accent ([System.Windows.Media.ColorConverter]::ConvertFromString('#003366'))
    Assert-Equal ((Get-SelfXLuminance $dark.AccentText) -gt (Get-SelfXLuminance $dark.Accent)) $true 'Dark accent is lightened for text on the dark theme'
    Assert-Equal $dark.RunButton.ToString() '#FF003366' 'Run button uses the accent by default'
    Assert-Equal $dark.AccentFg.ToString() '#FFFFFFFF' 'White text on a dark accent'
    $light = New-SelfXThemeColors -Theme Light -Accent ([System.Windows.Media.ColorConverter]::ConvertFromString('#FEDE06')) -TitleBarColor '#E20074' -RunButtonColor '#107C10' -InfoButtonColor 'bad'
    Assert-Equal ((Get-SelfXLuminance $light.AccentText) -lt (Get-SelfXLuminance $light.Accent)) $true 'Light accent is darkened for text on the light theme'
    Assert-Equal $light.AccentFg.ToString() '#FF000000' 'Black text on a yellow accent'
    Assert-Equal "$($light.TitleBarBg)/$($light.TitleBarFg)" '#FFE20074/#FFFFFFFF' 'Title bar color with readable text'
    Assert-Equal $light.RunButton.ToString() '#FF107C10' 'Brand_Run_Button_Color'
    Assert-Equal $light.InfoIcon.ToString() $light.AccentText.ToString() 'Invalid info color falls back to the accent text'
    $dictionary = New-Object System.Windows.ResourceDictionary
    Set-SelfXThemeResources -Dictionary $dictionary -Colors $dark
    Assert-Equal ($dictionary['Surface'] -is [System.Windows.Media.SolidColorBrush]) $true 'Theme brushes are WPF brushes'
    Assert-Equal $dictionary['Surface'].IsFrozen $true 'Theme brushes are frozen'

    # --- No console window at start ---------------------------------------------------------------
    # Shortcuts and the Run entry use SelfX.exe; scripts never start powershell.exe or cmd.exe with a console.
    $installText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Install.ps1'))
    Assert-Equal ($installText -match '\$Shortcut\.TargetPath = \$LauncherExe') $true 'Shortcut starts SelfX.exe'
    Assert-Equal ($installText.Contains('''SelfXTray'' -Value "`"$LauncherExe`" /tray"')) $true 'Run entry starts SelfX.exe /tray'
    Assert-Equal ($installText -match '-OutputType WindowsApplication') $true 'SelfX.exe is a Windows application (no console)'
    foreach ($file in 'Self_X.ps1', 'SelfX_Tray.ps1') {
        $text = [IO.File]::ReadAllText("$sources\$file")
        Assert-Equal ($text -match '(?i)Start-Process[^\r\n]*(powershell|cmd)\.exe') $false "$file starts no console process with Start-Process"
    }
    $launcherSource = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Service\SelfXLauncher.cs'))
    Assert-Equal ($launcherSource.Contains('start.CreateNoWindow = true;')) $true 'Launcher creates no console'
    Add-Type -TypeDefinition $launcherSource
    Assert-Equal ([SelfX.Launcher].GetMethod('Main').ReturnType) ([int]) 'Launcher compiles'
    $hidden = (Get-Command Start-SelfXHiddenPowerShell).ScriptBlock.ToString()
    Assert-Equal ($hidden.Contains('$start.CreateNoWindow = $true')) $true 'Start-SelfXHiddenPowerShell creates no console'

    # --- XAML of the main window, the templates and the dialogs (loaded, never shown) -------------
    $gui = Get-ScriptAst "$sources\Self_X.ps1"
    $Global:SelfX_StylesXaml = Get-AssignedText $gui '$Global:SelfX_StylesXaml'
    $Global:SelfX_TemplatesXaml = Get-AssignedText $gui '$Global:SelfX_TemplatesXaml'
    . ([scriptblock]::Create((Get-FunctionText $gui 'Get-SelfXSpinnerXaml')))
    $main = (Get-AssignedText $gui '$MainXaml').Replace('__STYLES__', $Global:SelfX_StylesXaml).Replace('__TEMPLATES__', $Global:SelfX_TemplatesXaml)
    $main = $main.Replace('__SPIN_STATUS__', (Get-SelfXSpinnerXaml 'Status_Spinner')).Replace('__SPIN_INFO__', (Get-SelfXSpinnerXaml 'SysInfo_Spinner'))
    [xml]$mainXml = $main
    $window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $mainXml))
    $window.Resources.MergedDictionaries.Add($dictionary)
    foreach ($name in 'Nav_Actions', 'Nav_Status', 'Nav_Info', 'ActionsList', 'StatusCards', 'InfoCards', 'FilterTextBox', 'Mode_Simple', 'Mode_Detailed',
        'Btn_Help', 'Btn_Settings', 'Btn_About', 'Btn_CheckAll', 'SysInfo_Refresh', 'SysInfo_Copy', 'SysInfo_Export', 'SysInfo_SendLogs', 'Btn_SendLogs',
        'InfoBar', 'Status_Banner', 'Status_Spinner', 'SysInfo_Spinner', 'Brand_Logo', 'ServiceDot', 'NavBadge') {
        Assert-Equal ($window.FindName($name) -ne $null) $true "Main window control $name"
    }
    foreach ($key in 'ActionTemplate', 'StatusTemplate', 'InfoTemplate', 'PrimaryButton', 'IconButton', 'AccentIconButton', 'Switch', 'Pill', 'NavItem') {
        Assert-Equal ($window.TryFindResource($key) -ne $null) $true "Resource $key"
    }
    Assert-Equal $window.ResizeMode 'CanResize' 'Window is resizable'
    Assert-Equal "$($window.MinWidth)x$($window.MinHeight)" '640x480' 'Minimum window size'
    $window.Close()
    $Form = [pscustomobject]@{ IsLoaded = $false; FlowDirection = 'LeftToRight'; Language = [System.Windows.Markup.XmlLanguage]::GetLanguage('en') }
    $Global:SelfX_Theme = $dictionary
    . ([scriptblock]::Create((Get-FunctionText $gui 'New-SelfXDialog')))
    $dialog = New-SelfXDialog -Title 'Test' -ContentXaml '<TextBlock Name="Probe" Text="x"/>'
    Assert-Equal $dialog.FindName('DialogTitle').Text 'Test' 'Dialog title'
    Assert-Equal ($dialog.FindName('Probe') -ne $null) $true 'Dialog content'
    $dialog.Close()

    # --- Language of the user (SelfX > Settings) --------------------------------------------------
    $languages = "$sources\Languages"
    Assert-Equal (Resolve-SelfXLanguageSetting -ConfigLanguage 'Auto' -UserLanguage 'fr' -LanguageFolder $languages) 'fr' 'User language wins'
    Assert-Equal (Resolve-SelfXLanguageSetting -ConfigLanguage 'it' -UserLanguage 'Auto' -LanguageFolder $languages) 'it' 'Auto uses Tool_Language'
    Assert-Equal (Resolve-SelfXLanguageSetting -ConfigLanguage 'it' -UserLanguage '' -LanguageFolder $languages) 'it' 'No user choice uses Tool_Language'
    Assert-Equal (Resolve-SelfXLanguageSetting -ConfigLanguage '' -UserLanguage '' -LanguageFolder $languages) 'Auto' 'Empty Tool_Language means Auto'
    Assert-Equal (Resolve-SelfXLanguageSetting -ConfigLanguage 'it' -UserLanguage 'fr' -AllowUserChoice $false -LanguageFolder $languages) 'it' 'Show_Language_Setting False ignores the user choice'
    Assert-Equal (Resolve-SelfXLanguageSetting -ConfigLanguage 'Auto' -UserLanguage 'xx' -LanguageFolder $languages) 'Auto' 'Language without file is ignored'
    Assert-Equal (Resolve-SelfXLanguageSetting -ConfigLanguage 'Auto' -UserLanguage '..\..\x' -LanguageFolder $languages) 'Auto' 'Path in the user value is ignored'
    Assert-Equal (Get-SelfXLanguageFileCulture -LanguageFolder $languages -Language 'de-CH') 'de' 'de-CH uses de.xml'
    Assert-Equal (Get-SelfXLanguageFileCulture -LanguageFolder $languages -Language 'gsw-CH') 'de' 'Swiss German uses de.xml'
    Assert-Equal (Get-SelfXLanguageFileCulture -LanguageFolder $languages -Language 'zh-TW') 'zh-Hant' 'zh-TW uses zh-Hant.xml'
    Assert-Equal (Get-SelfXLanguageFileCulture -LanguageFolder $languages -Language 'fr') 'fr' 'Exact language file'
    $list = @(Get-SelfXLanguageList -LanguageFolder $languages)
    Assert-Equal $list.Count @(Get-ChildItem -LiteralPath $languages -Filter '*.xml').Count 'Every language file is listed'
    Assert-Equal (($list | Where-Object Culture -eq 'de').Name) 'Deutsch' 'Languages are listed by their own name'
    Assert-Equal (($list | Where-Object Culture -eq 'ar').FlowDirection) 'RightToLeft' 'Right-to-left language'
    Assert-Equal (($list | ForEach-Object { $_.Name.ToLowerInvariant() }) -join '|') (($list | ForEach-Object { $_.Name.ToLowerInvariant() } | Sort-Object) -join '|') 'Languages are sorted by name'

    $Global:SelfX_LanguageFolder = $languages
    $Show_Language_Setting = $true
    $SelfX_UI_Language = [pscustomobject]@{ Culture = 'en' }
    $script:userSettings = @{}
    function Get-SelfXText($Name, $Default) { $Default }
    function Get-SelfXUserSetting { param($Name, $Default) if ($script:userSettings.ContainsKey($Name)) { $script:userSettings[$Name] } else { $Default } }
    function Set-SelfXUserSetting { param($Name, $Value) $script:userSettings[$Name] = $Value }
    . ([scriptblock]::Create((Get-FunctionText $gui 'Get-SelfXLanguageChoices')))
    # The test never signals a running status icon of the user.
    . ([scriptblock]::Create((Get-FunctionText $gui 'Set-SelfXUserLanguage').Replace('Local\SelfX.Tray.Command', 'Local\SelfX.Test.' + [guid]::NewGuid().ToString('N'))))
    $choices = @(Get-SelfXLanguageChoices)
    Assert-Equal $choices[0].Culture 'Auto' 'Automatic is the first choice'
    $defaultCulture = Get-SelfXLanguageFileCulture -LanguageFolder $languages -Language 'Auto'
    Assert-Equal $choices[0].Text (Get-SelfXString 'Settings_Language_Auto' (($list | Where-Object Culture -eq $defaultCulture).Name)) 'Automatic shows the default language'
    Assert-Equal $choices.Count ($list.Count + 1) 'All languages can be chosen'
    $Nav_Status = [pscustomobject]@{ IsChecked = $true }
    $Nav_Info = [pscustomobject]@{ IsChecked = $false }
    $Global:SvcAction_Running = $false
    $Global:FixAll_Active = $false
    $Global:SelfX_RestartPage = ''
    Assert-Equal (Set-SelfXUserLanguage 'en') $false 'Same language: no restart'
    Assert-Equal "$($script:userSettings['Language'])/$Global:SelfX_RestartPage" 'en/' 'Language is saved for the user'
    $Global:SvcAction_Running = $true
    Assert-Equal (Set-SelfXUserLanguage 'de') $false 'No restart while a repair runs'
    Assert-Equal "$($script:userSettings['Language'])/$Global:SelfX_RestartPage" 'de/' 'Language is saved for the next start'
    $Global:SvcAction_Running = $false
    Assert-Equal (Set-SelfXUserLanguage 'fr') $true 'Other language restarts SelfX'
    Assert-Equal $Global:SelfX_RestartPage 'Status' 'Restart on the same page'
    $Global:SelfX_RestartPage = ''
    $guiText = [IO.File]::ReadAllText("$sources\Self_X.ps1")
    Assert-Equal ($guiText.Contains('$Global:SelfX_GuiMutex.ReleaseMutex()') -and $guiText.Contains('-Arguments "-Page $Global:SelfX_RestartPage"')) $true 'SelfX starts again after a change of the language'

    $settingsXaml = $gui.Find({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $n.Value.Contains('Name="LanguageList"') }, $true).Value
    $dialog = New-SelfXDialog -Title 'Settings' -ContentXaml $settingsXaml
    foreach ($name in 'LanguagePanel', 'LanguageList', 'LanguageHint', 'ThemePanel', 'TrayPanel', 'SettingsClose') { Assert-Equal ($dialog.FindName($name) -ne $null) $true "Settings dialog control $name" }
    $listBox = $dialog.FindName('LanguageList')
    $listBox.ItemsSource = $choices
    $listBox.SelectedItem = $choices[1]
    Assert-Equal $listBox.SelectedItem.Culture $choices[1].Culture 'Language list selection'
    Assert-Equal (@('ThemeAuto', 'ThemeDark', 'ThemeLight' | Where-Object { $dialog.FindName($_) -ne $null }).Count) 3 'Theme choices Automatic, Dark and Light'
    $dialog.Close()

    # --- Theme Automatic: follows the app mode of Windows ------------------------------------------
    & {
        $script:appsLight = $null
        function Get-ItemProperty {
            param($Path, $Name, $ErrorAction)
            if ($Path -ne 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -or $Name -ne 'AppsUseLightTheme') { throw "Unexpected registry read $Path $Name" }
            if ($null -eq $script:appsLight) { throw 'Value not found' }
            [pscustomobject]@{ AppsUseLightTheme = $script:appsLight }
        }
        foreach ($name in 'Get-SelfXSystemTheme', 'Resolve-SelfXTheme', 'Set-SelfXTheme', 'Update-SelfXAutoTheme') { . ([scriptblock]::Create((Get-FunctionText $gui $name))) }
        $Global:SelfX_Accent = [System.Windows.Media.ColorConverter]::ConvertFromString('#003366')
        $script:appsLight = 0
        Assert-Equal (Resolve-SelfXTheme 'Auto') 'Dark' 'Automatic: Windows app mode dark'
        $script:appsLight = 1
        Assert-Equal (Resolve-SelfXTheme 'Auto') 'Light' 'Automatic: Windows app mode light'
        $script:appsLight = $null
        Assert-Equal (Resolve-SelfXTheme 'Auto') 'Light' 'Automatic without the Windows value uses light (Windows default)'
        Assert-Equal "$(Resolve-SelfXTheme 'Dark')/$(Resolve-SelfXTheme 'Light')/$(Resolve-SelfXTheme 'bad')" 'Dark/Light/Light' 'Fixed themes; unknown value follows Windows (Automatic)'
        $script:appsLight = 0
        Set-SelfXTheme 'Auto'
        Assert-Equal "$Global:SelfX_ThemeChoice/$Global:SelfX_CurrentTheme" 'Auto/Dark' 'Automatic applies the theme of Windows'
        $darkSurface = $Global:SelfX_Theme['Surface'].Color.ToString()
        $script:appsLight = 1
        Update-SelfXAutoTheme
        Assert-Equal "$Global:SelfX_ThemeChoice/$Global:SelfX_CurrentTheme" 'Auto/Light' 'Automatic follows a change of Windows while SelfX is open'
        Assert-Equal ($Global:SelfX_Theme['Surface'].Color.ToString() -ne $darkSurface) $true 'Colors change with the Windows app mode'
        Set-SelfXTheme 'Dark'
        Update-SelfXAutoTheme
        Assert-Equal "$Global:SelfX_ThemeChoice/$Global:SelfX_CurrentTheme" 'Dark/Dark' 'A fixed theme ignores the Windows app mode'
        Set-SelfXTheme 'bad'
        Assert-Equal "$Global:SelfX_ThemeChoice/$Global:SelfX_CurrentTheme" 'Auto/Light' 'Unknown theme value uses Automatic'
    }
    $guiText = [IO.File]::ReadAllText("$sources\Self_X.ps1")
    $toolConfig = [xml][IO.File]::ReadAllText("$sources\Tool_Config.xml")
    Assert-Equal "$($toolConfig.SelectSingleNode('//Tool_Theme').InnerText)/$($guiText.Contains('(Get-SelfXText "Tool_Theme" "Auto")'))" 'Auto/True' 'Default appearance is Automatic (Tool_Config and fallback)'
    Assert-Equal ($guiText.Contains("Set-SelfXUserSetting 'Theme' 'Auto'") -and $guiText.Contains('$Theme_Timer.Stop()')) $true 'Automatic is saved for the user; the theme timer stops when SelfX closes'
    Assert-Equal ((Get-SelfXString 'Settings_Theme_Auto') -ne 'Settings_Theme_Auto' -and (Get-SelfXString 'Settings_Theme_Auto_ToolTip') -ne 'Settings_Theme_Auto_ToolTip') $true 'Texts of Automatic'

    $trayText = [IO.File]::ReadAllText("$sources\SelfX_Tray.ps1")
    Assert-Equal ($trayText.Contains('-Language $Global:Tray_Language_Setting')) $true 'Status icon uses the language of the user'
    Assert-Equal ($trayText -match '\(Get-TrayLanguageSetting\) -ne \$Global:Tray_Language_Setting') $true 'Status icon restarts after a change of the language'

    # --- Running actions: start button animated only while the action runs ------------------------
    # Taskbar: own AppUserModelID before the first window, so Windows shows the SelfX icon (not PowerShell).
    $guiSource = [IO.File]::ReadAllText("$sources\Self_X.ps1")
    Assert-Equal ($guiSource.IndexOf('SetCurrentProcessExplicitAppUserModelID($Global:SelfX_AppId)') -gt 0 -and
        $guiSource.IndexOf('SetCurrentProcessExplicitAppUserModelID($Global:SelfX_AppId)') -lt $guiSource.IndexOf('[Windows.Markup.XamlReader]::Load')) $true 'Own taskbar identity before the window is created'
    Assert-Equal ($guiSource.Contains('[SelfXGui.Taskbar]::SetWindowIdentity(')) $true 'Pinned SelfX starts SelfX.exe (relaunch properties)'
    $taskbarDef = [regex]::Match($guiSource, "-MemberDefinition @'\r?\n(.*?)\r?\n'@", 'Singleline').Groups[1].Value
    Add-Type -Namespace SelfXGuiTest -Name Taskbar -MemberDefinition $taskbarDef
    Assert-Equal ([SelfXGuiTest.Taskbar].GetMethod('SetWindowIdentity') -ne $null) $true 'Taskbar helper compiles'
    Assert-Equal ($Global:SelfX_TemplatesXaml.Contains('<DataTrigger Binding="{Binding Running}" Value="True">')) $true 'Templates react on Running'
    Assert-Equal ($Global:SelfX_TemplatesXaml.Contains('Name="RunSpin"') -and $Global:SelfX_TemplatesXaml.Contains('Name="FixSpin"')) $true 'Start and Fix buttons have a rotating icon'
    . ([scriptblock]::Create((Get-FunctionText $gui 'Set-SelfXActionRunning')))
    $script:refreshes = 0
    $ActionsList = [pscustomobject]@{ Items = (New-Object PSObject) }
    $ActionsList.Items | Add-Member ScriptMethod Refresh { $script:refreshes++ }
    $script:alerts = New-Object System.Collections.Generic.List[string]
    $msgbar = New-Object PSObject
    foreach ($method in 'Clear', 'SetSuccessAlert', 'SetDangerAlert', 'SetInformationAlert', 'SetWarningAlert') {
        $msgbar | Add-Member ScriptMethod $method ([scriptblock]::Create("param(`$t) if ('$method' -ne 'Clear') { `$script:alerts.Add('$method') }"))
    }
    $script:timerStopped = $false
    $UserRun_Timer = New-Object PSObject
    $UserRun_Timer | Add-Member ScriptMethod Stop { $script:timerStopped = $true }
    $tick = $gui.Find({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Expression.Extent.Text -eq '$UserRun_Timer' -and $n.Member.Value -eq 'Add_Tick' }, $true)
    $userTick = $tick.Arguments[0].ScriptBlock.GetScriptBlock()
    function New-FakeProcess([bool]$Exited, [int]$Code) { $p = [pscustomobject]@{ HasExited = $Exited; ExitCode = $Code; Id = 1 }; $p | Add-Member ScriptMethod Dispose { }; $p }
    $rowA = [pscustomobject]@{ Name = 'Teams'; Running = $false }
    $rowB = [pscustomobject]@{ Name = 'OneDrive'; Running = $false }
    $Global:SelfX_UserRuns = New-Object System.Collections.Generic.List[object]
    $runA = [pscustomobject]@{ Row = $rowA; Process = (New-FakeProcess $false 0); Name = 'Teams'; Script = 'a.ps1' }
    $runB = [pscustomobject]@{ Row = $rowB; Process = (New-FakeProcess $false 1); Name = 'OneDrive'; Script = 'b.ps1' }
    $Global:SelfX_UserRuns.Add($runA); $Global:SelfX_UserRuns.Add($runB)
    Set-SelfXActionRunning $rowA $true; Set-SelfXActionRunning $rowB $true
    Assert-Equal "$($rowA.Running)/$($rowB.Running)/$script:refreshes" 'True/True/2' 'Started actions are shown as running'
    & $userTick
    Assert-Equal "$($rowA.Running)/$($rowB.Running)/$($script:alerts.Count)" 'True/True/0' 'Actions stay running while their scripts run'
    $runA.Process.HasExited = $true
    & $userTick
    Assert-Equal "$($rowA.Running)/$($rowB.Running)/$($script:alerts -join ',')/$script:timerStopped" 'False/True/SetSuccessAlert/False' 'Finished action (exit 0): button normal, success shown'
    $runB.Process.HasExited = $true
    & $userTick
    Assert-Equal "$($rowB.Running)/$($script:alerts[-1])/$script:timerStopped/$($Global:SelfX_UserRuns.Count)" 'False/SetDangerAlert/True/0' 'Failed action (exit 1): button normal, error shown, watching stops'

    # --- Every text used by the GUI and the tray icon exists in en.xml ----------------------------
    $en = New-Object System.Xml.XmlDocument
    $en.Load("$sources\Languages\en.xml")
    $keys = New-Object System.Collections.Generic.HashSet[string]
    foreach ($file in 'Self_X.ps1', 'SelfX_Tray.ps1') {
        $text = [IO.File]::ReadAllText("$sources\$file")
        foreach ($m in [regex]::Matches($text, "Get-SelfXString '([A-Za-z_]+)'")) { [void]$keys.Add($m.Groups[1].Value) }
        foreach ($m in [regex]::Matches($text, "@\('Str_[A-Za-z_]+', '([A-Za-z_]+)'\)")) { [void]$keys.Add($m.Groups[1].Value) }
    }
    foreach ($tool in 'SyncApps', 'SyncCompliance', 'CompanyPortal', 'QuickAssist', 'MdmDiagnostics', 'SendLogs') { [void]$keys.Add("SystemInfo_$($tool)_Text"); [void]$keys.Add("Tooltip_$tool") }
    Assert-Equal ($keys.Count -gt 60) $true 'Texts found in the scripts'
    foreach ($key in $keys) { Assert-Equal ($en.SelectSingleNode("/SelfX_Language/UI/$key") -ne $null) $true "en.xml contains $key" }

    # --- Per-user cache of the system information -------------------------------------------------
    $cachePath = Join-Path $temp 'SystemInfo.json'
    $items = @(
        New-SelfXInfoItem 'Device' 'Computer name' 'PC1'
        New-SelfXInfoItem 'Network' 'IPv4' @('10.0.0.1', '10.0.0.2')
        New-SelfXInfoItem 'Health status' 'Disk' 'Error - full' 'Error'
    )
    Save-SelfXSystemInfoCache -Items $items -Culture 'de' -Path $cachePath
    Assert-Equal (Test-Path "$cachePath.tmp") $false 'Cache written through a temporary file'
    $read = Read-SelfXSystemInfoCache -Culture 'de' -Path $cachePath
    Assert-Equal @($read.Items).Count 2 'Status rows are not cached'
    Assert-Equal $read.Items[1].Value '10.0.0.1, 10.0.0.2' 'Cached values'
    Assert-Equal (([datetime]::UtcNow - $read.CollectedAt.ToUniversalTime()).TotalMinutes -lt 5) $true 'Cache time'
    Assert-Equal $read.CollectedAt.Kind ([DateTimeKind]::Utc) 'Cache time is stored as UTC'
    Assert-Equal (Read-SelfXSystemInfoCache -Culture 'fr' -Path $cachePath) $null 'Cache of another language is ignored'
    [IO.File]::WriteAllText($cachePath, 'not json')
    Assert-Equal (Read-SelfXSystemInfoCache -Culture 'de' -Path $cachePath) $null 'Broken cache is ignored'

    # --- Connection types of the network section (adapters simulated, nothing is queried) --------
    function New-TestAdapter($Index, $Description, $Status, $Media, $Physical, $Ndis, [bool]$Hardware) {
        [pscustomobject]@{ ifIndex = $Index; InterfaceDescription = $Description; Status = $Status; MediaType = $Media; PhysicalMediaType = $Physical
            NdisPhysicalMedium = $Ndis; HardwareInterface = $Hardware; ConnectorPresent = $Hardware }
    }
    $vmNic = New-TestAdapter 4 'Microsoft Hyper-V Network Adapter' 'Up' '802.3' 'Unspecified' 0 $false
    $c = Get-SelfXConnectionTypes -Adapters @($vmNic) -GatewayIndexes @(4)
    Assert-Equal "$($c.Lan)/$($c.WiFi)/$($c.Wwan)" 'True/False/False' 'Virtual machine network adapter with default route is LAN'
    $c = Get-SelfXConnectionTypes -Adapters @($vmNic) -GatewayIndexes @()
    Assert-Equal $c.Lan $false 'Virtual adapter without default route is no LAN'
    $hostSwitch = New-TestAdapter 7 'Hyper-V Virtual Ethernet Adapter #2' 'Up' '802.3' 'Unspecified' 0 $false
    $wifi = New-TestAdapter 5 'Intel(R) Wi-Fi 6E AX211 160MHz' 'Up' 'Native 802.11' 'Native 802.11' 9 $true
    $c = Get-SelfXConnectionTypes -Adapters @($hostSwitch, $wifi) -GatewayIndexes @(7, 5)
    Assert-Equal "$($c.Lan)/$($c.WiFi)" 'False/True' 'Hyper-V host switch over Wi-Fi is no LAN'
    $cable = New-TestAdapter 11 'Realtek USB GbE Family Controller' 'Up' '802.3' '802.3' 14 $true
    Assert-Equal (Get-SelfXConnectionTypes -Adapters @($cable) -GatewayIndexes @()).Lan $true 'Network cable without default route is LAN'
    $cable.Status = 'Disconnected'
    Assert-Equal (Get-SelfXConnectionTypes -Adapters @($cable) -GatewayIndexes @(11)).Lan $false 'Disconnected cable is no LAN'
    $vpnNic = New-TestAdapter 20 'Cisco AnyConnect Secure Mobility Client Virtual Miniport Adapter' 'Up' '802.3' 'Unspecified' 0 $false
    $bluetooth = New-TestAdapter 10 'Bluetooth Device (Personal Area Network)' 'Up' '802.3' 'BlueTooth' 10 $false
    $c = Get-SelfXConnectionTypes -Adapters @($vpnNic, $bluetooth) -GatewayIndexes @(20, 10)
    Assert-Equal "$($c.Lan)/$($c.WiFi)/$($c.Wwan)" 'False/False/False' 'VPN tunnel and Bluetooth are no LAN'
    $wifiDirect = New-TestAdapter 30 'Microsoft Wi-Fi Direct Virtual Adapter' 'Up' 'Native 802.11' 'Native 802.11' 9 $false
    Assert-Equal (Get-SelfXConnectionTypes -Adapters @($wifiDirect) -GatewayIndexes @()).WiFi $false 'Wi-Fi Direct adapter is no Wi-Fi connection'
    $cellular = New-TestAdapter 42 'Fibocom L860-GL' 'Up' 'Wireless WAN' 'Wireless WAN' 8 $true
    Assert-Equal (Get-SelfXConnectionTypes -Adapters @($cellular) -GatewayIndexes @(42)).Wwan $true 'Mobile broadband'
    Assert-Equal (Get-SelfXConnectionTypes -Adapters @() -GatewayIndexes @()).Lan $false 'No adapters'

    # --- Last Intune sync: the OMA-DM time is local time despite its "Z" ---------------------------
    $sync = ConvertFrom-SelfXOmaDmTime '20261106T123322Z'
    Assert-Equal $sync.ToString('yyyy-MM-dd HH:mm:ss') '2026-11-06 12:33:22' 'OMA-DM time is not shifted by the UTC offset'
    Assert-Equal $sync.Kind ([DateTimeKind]::Local) 'OMA-DM time is local time'
    Assert-Equal (ConvertFrom-SelfXOmaDmTime 'garbage') $null 'Invalid OMA-DM time'
    Assert-Equal (ConvertFrom-SelfXOmaDmTime '') $null 'Empty OMA-DM time'
    $standardText = [IO.File]::ReadAllText((Join-Path (Split-Path $PSScriptRoot) 'SelfX Standard\Sources\SystemInfo.ps1'))
    Assert-Equal ($standardText.Contains('.ToLocalTime()')) $false 'SelfX Standard does not shift the OMA-DM time either'

    # --- Tray icon: status, tooltip and notifications (no icon is shown, nothing is started) -------
    $tray = Get-ScriptAst "$sources\SelfX_Tray.ps1"
    Add-Type -Namespace SelfXTray -Name Native -MemberDefinition '[DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr handle);'
    foreach ($name in 'New-TrayIcon', 'Set-TrayText', 'Update-TrayStatus', 'Test-TrayNotificationsOn') { . ([scriptblock]::Create((Get-FunctionText $tray $name))) }
    $script:settings = @{}
    function Get-TrayUserSetting { param($Name, $Default) if ($script:settings.ContainsKey($Name)) { $script:settings[$Name] } else { $Default } }
    function Set-TrayUserSetting { param($Name, $Value) $script:settings[$Name] = $Value }
    $script:balloons = New-Object System.Collections.Generic.List[string]
    $Global:Tray = New-Object PSObject -Property @{ Icon = $null; Text = '' }
    $Global:Tray | Add-Member ScriptMethod ShowBalloonTip { param($Timeout, $Title, $Text, $Kind) $script:balloons.Add("$Kind|$Title") }
    $Global:Tray_Status_Item = New-Object PSObject -Property @{ Text = '' }
    $Global:Tray_Base_Icon = $null
    $Global:Tray_Icon_Handle = [IntPtr]::Zero
    $Global:Tray_Tool_Name = 'SelfX'
    $Global:Tray_Notify = $true
    $Global:Tray_Show_Result = $false
    function New-TestData([string]$DiskStatus) {
        [pscustomobject]@{ Ok = $true; Items = @(
            [pscustomobject]@{ Property = 'Disk capacity (C:)'; Status = $DiskStatus; HealthId = 'Disk'; HealthName = 'C:'; Detail = 'C: 8 GB free' }
            [pscustomobject]@{ Property = 'Updates'; Status = 'Pending'; HealthId = 'Updates'; HealthName = ''; Detail = '2 updates' }) }
    }
    Update-TrayStatus ([pscustomobject]@{ Ok = $false; Items = @() })
    Assert-Equal $Global:Tray.Text (Get-SelfXString 'Tray_Tooltip_Unknown') 'Unknown status without service'
    Assert-Equal $script:balloons.Count 0 'No notification without status'
    $firstHandle = $Global:Tray_Icon_Handle
    Update-TrayStatus (New-TestData Error)
    Assert-Equal $Global:Tray.Text (Get-SelfXString 'Tray_Tooltip_Issues' 1 1) 'Tooltip counts problems and warnings'
    Assert-Equal ($Global:Tray.Text.Length -le 63) $true 'Tooltip within the NotifyIcon limit'
    Assert-Equal $script:balloons[0] 'Warning|Disk capacity (C:)' 'New error is notified'
    Assert-Equal $script:settings['TrayNotified'] 'Disk|C:' 'Notified error is remembered'
    Assert-Equal ($Global:Tray_Icon_Handle -ne $firstHandle) $true 'Icon is replaced on a status change'
    Update-TrayStatus (New-TestData Error)
    Assert-Equal $script:balloons.Count 1 'The same error is not notified again'
    Update-TrayStatus (New-TestData OK)
    Assert-Equal "$($script:balloons.Count)/$($script:settings['TrayNotified'])" '1/' 'Resolved error is forgotten'
    Update-TrayStatus (New-TestData Error)
    Assert-Equal $script:balloons.Count 2 'An error that comes back is notified again'
    # The user switches the notifications off (SelfX > Settings or the menu of the icon).
    $script:settings['TrayNotifications'] = 0
    Update-TrayStatus (New-TestData OK)
    Update-TrayStatus (New-TestData Error)
    Assert-Equal "$($script:balloons.Count)/$($script:settings['TrayNotified'])" '2/Disk|C:' 'Notifications off for the user: no message, error still remembered'
    Assert-Equal $Global:Tray.Text (Get-SelfXString 'Tray_Tooltip_Issues' 1 1) 'Notifications off: the icon still shows the problem'
    $script:settings['TrayNotifications'] = 1
    Update-TrayStatus (New-TestData Error)
    Assert-Equal $script:balloons.Count 2 'Notifications on again: a problem known before is not announced afterwards'
    Update-TrayStatus (New-TestData OK)
    Update-TrayStatus (New-TestData Error)
    Assert-Equal $script:balloons.Count 3 'Notifications on again: a new problem is announced'
    $Global:Tray_Notify = $false
    Assert-Equal (Test-TrayNotificationsOn) $false 'Tray_Notifications False switches the notifications off for all users'
    $script:settings['TrayNotified'] = ''
    Update-TrayStatus (New-TestData Error)
    Assert-Equal $script:balloons.Count 3 'Tray_Notifications False shows no notification'
    $guiText = [IO.File]::ReadAllText("$sources\Self_X.ps1")
    Assert-Equal ($guiText.Contains("Set-SelfXUserSetting 'TrayNotifications'") -and $trayText.Contains("Set-TrayUserSetting 'TrayNotifications'")) $true 'Notifications switch in SelfX > Settings and in the menu of the icon'
    $Global:Tray_Show_Result = $true
    Update-TrayStatus (New-TestData OK)
    Assert-Equal $script:balloons[-1] 'Info|SelfX' '"Check status now" shows the result'
    Assert-Equal $Global:Tray_Show_Result $false 'Result notification is shown once'
    Set-TrayText ('x' * 100)
    Assert-Equal $Global:Tray.Text.Length 63 'Long tooltip is shortened'
    [void][SelfXTray.Native]::DestroyIcon($Global:Tray_Icon_Handle)
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output "PASS: $script:assertions assertions. No window shown, no process started."
