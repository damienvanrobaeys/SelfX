<#
.SYNOPSIS
    SelfX status icon in the notification area (tray) of the signed-in user.

.DESCRIPTION
    Started at sign-in for every user (HKLM Run entry "SelfXTray", created by Install.ps1 when Show_Tray_Icon
    is True in Tool_Config.xml). The icon shows the device status of the background checks of the local SelfX
    service: a green, yellow or red dot (gray = not available yet) and a tooltip with the number of problems.
    When a check changes to Error (for example "Disk capacity" when the disk is almost full), a Windows
    notification is shown once; clicking it opens SelfX on the Device status page.

    The icon only reads the status cache of the service (STATUS request) and runs no check by itself, so it
    needs no administrator rights and hardly uses resources. "Check status now" asks the service for a full
    check (HEALTH), the same as the button in SelfX. Shortly after the start it also collects the system
    information of the user in the background (SystemInfo.ps1, read-only) and stores it in the user cache,
    so SelfX shows it immediately.

    The user can hide the icon (menu "Hide this icon" or SelfX > Settings). This is stored per user in
    HKCU\Software\SelfX\TrayIcon = 0; SelfX > Settings shows it again. Only one icon runs per user session.
    After an update of SelfX the icon restarts itself with the new version; after an uninstall it closes.
    The texts use the same language as SelfX (choice of the user in SelfX > Settings, otherwise
    Tool_Language or the Windows display language); after a change of the language the icon restarts.
    Nothing is changed on the device, nothing is sent and Windows is never restarted.

.NOTES
    Name    : SelfX_Tray.ps1
    Package : SelfX Service
    Context : User (started at sign-in, HKLM Run entry)
    Version : 2.6.5

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.5.0    2026-11-04  Wolfgang Baeck       Initial version: status icon, notifications, menu
    2.5.2    2026-11-04  Wolfgang Baeck       Working directory outside the install folder (did block updates)
    2.5.3    2026-11-04  Wolfgang Baeck       SelfX and the icon are started without a console window (SelfX.exe / CreateNoWindow)
    2.5.9    2026-11-05  Wolfgang Baeck       Language chosen by the user; restart after a change of the language
    2.6.0    2026-11-06  Wolfgang Baeck       Logging (SelfXLog.ps1): start, status changes, notifications, stop reason
    2.6.5    2026-11-06  Wolfgang Baeck       Notifications per user (HKCU TrayNotifications): menu item "Show notifications" and
                                              switch in SelfX > Settings; problems are remembered also while they are off
#>

$Global:Tray_Folder = Split-Path $MyInvocation.MyCommand.Path
$Global:Tray_Script = $MyInvocation.MyCommand.Path
$Global:Tray_UserKey = 'HKCU:\Software\SelfX'
# The icon runs for the whole session: it must not use the install folder as working directory, otherwise
# Windows refuses to replace or delete the folder during an update or uninstallation (all paths are absolute).
Set-Location -LiteralPath $env:SystemRoot
[Environment]::CurrentDirectory = $env:SystemRoot

Function Get-TrayUserSetting
	{
		param([string]$Name, $Default = $null)
		Try { $Value = (Get-ItemProperty -LiteralPath $Global:Tray_UserKey -Name $Name -ErrorAction Stop).$Name; If($null -ne $Value) { return $Value } } Catch {}
		return $Default
	}

Function Set-TrayUserSetting
	{
		param([string]$Name, $Value)
		Try
			{
				If(-not (Test-Path -LiteralPath $Global:Tray_UserKey)) { New-Item -Path $Global:Tray_UserKey -Force | Out-Null }
				Set-ItemProperty -LiteralPath $Global:Tray_UserKey -Name $Name -Value $Value
			}
		Catch {}
	}

# Settings of the administrator (Tool_Config.xml) and the user (HKCU)
$Config = New-Object System.Xml.XmlDocument
$Config.Load((Join-Path $Global:Tray_Folder 'Tool_Config.xml'))
$GUI_Config = $Config.GUI_Config
Function Get-TrayConfig($Name, $Default)
	{
		$Value = $GUI_Config.$Name
		If([string]::IsNullOrWhiteSpace($Value)) { return $Default }
		return "$Value".Trim()
	}
If((Get-TrayConfig 'Show_Tray_Icon' 'True') -ne 'True') { exit }
If([int](Get-TrayUserSetting 'TrayIcon' 1) -eq 0) { exit }

# Only one icon per user session
$Global:Tray_Mutex = New-Object System.Threading.Mutex($false, 'Local\SelfX.Tray')
$Owned = $false
Try { $Owned = $Global:Tray_Mutex.WaitOne(0) } Catch [System.Threading.AbandonedMutexException] { $Owned = $true }
If(-not $Owned) { exit }
# SelfX > Settings signals this event after the user switched the icon off.
$Global:Tray_Command = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, 'Local\SelfX.Tray.Command')

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Namespace SelfXTray -Name Native -MemberDefinition '[DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr handle);'

. (Join-Path $Global:Tray_Folder 'SelfXServiceClient.ps1')
. (Join-Path $Global:Tray_Folder 'Localization.ps1')
. (Join-Path $Global:Tray_Folder 'SystemInfo.ps1')
# Logging to ProgramData\SelfX\Logs\Users\<SID> (SelfXLog.ps1)
. (Join-Path $Global:Tray_Folder 'SelfXLog.ps1')
Initialize-SelfXLog -Component 'SelfX_Tray'
# Same language as SelfX: choice of the user (SelfX > Settings) or Tool_Language / Windows display language.
Function Get-TrayLanguageSetting
	{
		return (Resolve-SelfXLanguageSetting -ConfigLanguage (Get-TrayConfig 'Tool_Language' 'Auto') -UserLanguage ([string](Get-TrayUserSetting 'Language' '')) `
			-AllowUserChoice ((Get-TrayConfig 'Show_Language_Setting' 'True') -eq 'True') -LanguageFolder (Join-Path $Global:Tray_Folder 'Languages'))
	}
$Global:Tray_Language_Setting = Get-TrayLanguageSetting
$Language = Initialize-SelfXLanguage -LanguageFolder (Join-Path $Global:Tray_Folder 'Languages') -Language $Global:Tray_Language_Setting
$Global:Tray_Texts = Get-SelfXSystemInfoTexts
$Global:Tray_Job_Script = (Get-Content -LiteralPath (Join-Path $Global:Tray_Folder 'SelfXServiceClient.ps1') -Raw) + "`r`n" + (Get-Content -LiteralPath (Join-Path $Global:Tray_Folder 'SystemInfo.ps1') -Raw)
$Global:Tray_Tool_Name = Get-TrayConfig 'Tool_Name' 'SelfX'
$Global:Tray_Notify = (Get-TrayConfig 'Tray_Notifications' 'True') -eq 'True'
# Windows notifications about new problems: allowed by the administrator (Tray_Notifications) and switched on by
# the user (HKCU TrayNotifications, SelfX > Settings or the menu of the icon). Read at every use, so a change in
# SelfX applies at once.
Function Test-TrayNotificationsOn
	{
		return ($Global:Tray_Notify -and ([int](Get-TrayUserSetting 'TrayNotifications' 1) -ne 0))
	}
$Global:Tray_Poll_Seconds = 60
$Poll = 0
If([int]::TryParse((Get-TrayConfig 'Tray_Poll_Seconds' '60'), [ref]$Poll) -and $Poll -ge 15 -and $Poll -le 3600) { $Global:Tray_Poll_Seconds = $Poll }
$Global:Tray_Config_Time = (Get-Item -LiteralPath (Join-Path $Global:Tray_Folder 'Tool_Config.xml')).LastWriteTimeUtc

#******************************************************************************
# Icon with a colored status dot
#******************************************************************************
$Global:Tray_Base_Icon = $null
foreach($Candidate in @((Get-TrayConfig 'Brand_Icon' ''), 'icon_systray.ico', 'Repair.ico'))
	{
		If("$Candidate" -notlike '*.ico') { continue }
		$Path = $(If([IO.Path]::IsPathRooted($Candidate)) { $Candidate } Else { Join-Path $Global:Tray_Folder $Candidate })
		If(Test-Path -LiteralPath $Path -PathType Leaf)
			{
				Try { $Global:Tray_Base_Icon = New-Object System.Drawing.Icon($Path, 32, 32); break } Catch {}
			}
	}
$Global:Tray_Icon_Handle = [IntPtr]::Zero

Function New-TrayIcon
	{
		param([ValidateSet('OK', 'Warning', 'Error', 'Unknown')][string]$State)
		$Colors = @{ OK = @(19, 161, 14); Warning = @(247, 181, 0); Error = @(209, 52, 56); Unknown = @(138, 138, 138) }[$State]
		$Bitmap = New-Object System.Drawing.Bitmap(32, 32)
		$Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
		$Graphics.SmoothingMode = 'AntiAlias'
		If($Global:Tray_Base_Icon) { $Graphics.DrawIcon($Global:Tray_Base_Icon, (New-Object System.Drawing.Rectangle(0, 0, 32, 32))) }
		$Graphics.FillEllipse([System.Drawing.Brushes]::White, 16, 16, 16, 16)
		$Graphics.FillEllipse((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($Colors[0], $Colors[1], $Colors[2]))), 18, 18, 12, 12)
		$Graphics.Dispose()
		$Handle = $Bitmap.GetHicon()
		$Bitmap.Dispose()
		$Icon = [System.Drawing.Icon]::FromHandle($Handle)
		# The previous icon handle is released, so a long running session does not leak handles.
		If($Global:Tray_Icon_Handle -ne [IntPtr]::Zero) { [void][SelfXTray.Native]::DestroyIcon($Global:Tray_Icon_Handle) }
		$Global:Tray_Icon_Handle = $Handle
		return $Icon
	}

# Tooltip text of a NotifyIcon is limited to 63 characters.
Function Set-TrayText
	{
		param([string]$Text)
		If($Text.Length -gt 63) { $Text = $Text.Substring(0, 60) + '...' }
		$Global:Tray.Text = $Text
	}

#******************************************************************************
# Opening SelfX (one window per user; a running window is brought to the front)
#******************************************************************************
Function Open-SelfX
	{
		param([string]$Page = '')
		$Gui = Join-Path $Global:Tray_Folder 'Self_X.ps1'
		$Arguments = ''
		If($Page) { $Arguments = "-Page $Page" }
		# Working directory outside the install folder (see above); no console window is created.
		Write-SelfXLog "Open SelfX (page '$Page')."
		Try { Start-SelfXHiddenPowerShell -Path $Gui -Arguments $Arguments } Catch { Write-SelfXLog "SelfX not started: $($_.Exception.Message)" Error }
	}

Function Stop-Tray
	{
		param([string]$Reason = 'closed')
		Write-SelfXLog "Status icon stops: $Reason."
		$Global:Tray_Timer.Stop()
		$Global:Tray.Visible = $false
		$Global:Tray.Dispose()
		Try { $Global:Tray_Mutex.ReleaseMutex() } Catch {}
		[System.Windows.Forms.Application]::Exit()
	}

#******************************************************************************
# Status: read the cache of the service in a background runspace
#******************************************************************************
$Global:Tray_Job = $null
$Global:Tray_Job_Mode = ''
$Global:Tray_Show_Result = $false

Function Start-TrayStatusJob
	{
		param([ValidateSet('Cached', 'Full')][string]$Mode)
		If($Global:Tray_Job) { return }
		$Global:Tray_Job_Mode = $Mode
		$Global:Tray_PS = [PowerShell]::Create()
		[void]$Global:Tray_PS.AddScript($Global:Tray_Job_Script).AddStatement().AddCommand('Get-SelfXStatusData').AddParameter('Mode', $Mode).AddParameter('Text', $Global:Tray_Texts)
		$Global:Tray_Job = $Global:Tray_PS.BeginInvoke()
	}

# Shows the status in the icon and notifies once about each check that changed to Error.
Function Update-TrayStatus
	{
		param($Data)
		$Items = @($Data.Items)
		If(-not $Data.Ok -or -not $Items.Count)
			{
				If($Global:Tray_LastState -ne 'Unknown') { Write-SelfXLog "Status not available: $($Data.Message)" Warning; $Global:Tray_LastState = 'Unknown' }
				$Global:Tray.Icon = New-TrayIcon Unknown
				Set-TrayText (Get-SelfXString 'Tray_Tooltip_Unknown')
				$Global:Tray_Status_Item.Text = Get-SelfXString 'Tray_Tooltip_Unknown'
				return
			}
		$Errors = @($Items | Where-Object { $_.Status -eq 'Error' })
		$Warnings = @($Items | Where-Object { $_.Status -eq 'Pending' })
		If($Errors.Count) { $State = 'Error' } ElseIf($Warnings.Count) { $State = 'Warning' } Else { $State = 'OK' }
		# Only changes are logged (the status is read every minute).
		$Signature = "$State|" + (($Errors + $Warnings | ForEach-Object { "$($_.HealthId) $($_.HealthName)".Trim() }) -join ', ')
		If($Signature -ne $Global:Tray_LastState)
			{
				Write-SelfXLog ("Status {0}: {1} error(s), {2} warning(s) {3}" -f $State, $Errors.Count, $Warnings.Count, $(If($Errors.Count + $Warnings.Count) { '(' + (($Errors + $Warnings | ForEach-Object { "$($_.Property)" }) -join ', ') + ')' } Else { '' }))
				$Global:Tray_LastState = $Signature
			}
		$Global:Tray.Icon = New-TrayIcon $State
		If($State -eq 'OK') { $Summary = Get-SelfXString 'Tray_Tooltip_OK' } Else { $Summary = Get-SelfXString 'Tray_Tooltip_Issues' $Errors.Count $Warnings.Count }
		Set-TrayText $Summary
		$Global:Tray_Status_Item.Text = $Summary

		If($Global:Tray_Show_Result)
			{
				$Global:Tray_Show_Result = $false
				$Global:Tray.ShowBalloonTip(5000, $Global:Tray_Tool_Name, $Summary, [System.Windows.Forms.ToolTipIcon]::Info)
				return
			}
		If(-not $Global:Tray_Notify) { return }
		$Known = @("$(Get-TrayUserSetting 'TrayNotified' '')" -split ';' | Where-Object { $_ })
		$Current = @($Errors | ForEach-Object { "$($_.HealthId)|$($_.HealthName)" })
		$New = @($Errors | Where-Object { $Known -notcontains "$($_.HealthId)|$($_.HealthName)" })
		# Only the errors that are still present are remembered, so a problem that comes back is notified again.
		# They are remembered also while the user has switched the notifications off, so switching them on
		# again does not announce old problems.
		Set-TrayUserSetting 'TrayNotified' ($Current -join ';')
		If($New.Count -and -not (Test-TrayNotificationsOn))
			{
				Write-SelfXLog "No notification (switched off by the user): $(($New | ForEach-Object { $_.Property }) -join ', ')"
				return
			}
		If($New.Count)
			{
				$Detail = "$($New[0].Detail)"
				If($Detail.Length -gt 180) { $Detail = $Detail.Substring(0, 177) + '...' }
				$Title = $(If($New.Count -gt 1) { Get-SelfXString 'Tray_Tooltip_Issues' $Errors.Count $Warnings.Count } Else { "$($New[0].Property)" })
				$Global:Tray.ShowBalloonTip(10000, $Title, ($Detail + "`r`n" + (Get-SelfXString 'Tray_Notify_Click')), [System.Windows.Forms.ToolTipIcon]::Warning)
				Write-SelfXLog "Notification shown: $Title - $Detail"
			}
	}

# Collects the system information of the user once in the background, so SelfX shows it immediately.
Function Start-TraySystemInfoCache
	{
		$Global:Tray_Info_PS = [PowerShell]::Create()
		[void]$Global:Tray_Info_PS.AddScript($Global:Tray_Job_Script).AddStatement().AddScript(
			'param($TestHost, $TestPort, $Text, $Culture) $Items = @(Get-SelfXSystemInfo -InternetTestHost $TestHost -InternetTestPort $TestPort -Text $Text); Save-SelfXSystemInfoCache -Items $Items -Culture $Culture'
		).AddArgument((Get-TrayConfig 'SystemInfo_Internet_Test_Host' 'www.msftconnecttest.com')).AddArgument([int](Get-TrayConfig 'SystemInfo_Internet_Test_Port' '80')).AddArgument($Global:Tray_Texts).AddArgument($Language.Culture)
		$Global:Tray_Info_Job = $Global:Tray_Info_PS.BeginInvoke()
	}

#******************************************************************************
# Icon and menu
#******************************************************************************
$Global:Tray = New-Object System.Windows.Forms.NotifyIcon
$Global:Tray.Icon = New-TrayIcon Unknown
Set-TrayText (Get-SelfXString 'Tray_Tooltip_Unknown')
$Menu = New-Object System.Windows.Forms.ContextMenuStrip
$Open_Item = $Menu.Items.Add((Get-SelfXString 'Tray_Menu_Open'), $null, { Open-SelfX })
$Open_Item.Font = New-Object System.Drawing.Font($Open_Item.Font, [System.Drawing.FontStyle]::Bold)
$Global:Tray_Status_Item = $Menu.Items.Add((Get-SelfXString 'Tray_Tooltip_Unknown'), $null, { Open-SelfX 'Status' })
[void]$Menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$Menu.Items.Add((Get-SelfXString 'Tray_Menu_Status'), $null, { Open-SelfX 'Status' })
[void]$Menu.Items.Add((Get-SelfXString 'Tray_Menu_Check'), $null, {
	$Global:Tray_Show_Result = $true
	$Global:Tray.ShowBalloonTip(3000, $Global:Tray_Tool_Name, (Get-SelfXString 'Tray_Checking_Text'), [System.Windows.Forms.ToolTipIcon]::Info)
	Start-TrayStatusJob Full
})
$Catalog = New-Object System.Xml.XmlDocument
$Catalog.Load((Join-Path $Global:Tray_Folder 'Issues_List.xml'))
If($Catalog.SelectSingleNode("//Action[normalize-space(Post_Action)='MailReport' and normalize-space(Context)='System']"))
	{
		[void]$Menu.Items.Add((Get-SelfXString 'SystemInfo_SendLogs_Text'), $null, { Open-SelfX 'SendLogs' })
	}
[void]$Menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
# Notifications on / off for this user (only when the administrator allows notifications).
If($Global:Tray_Notify)
	{
		$Global:Tray_Notify_Item = New-Object System.Windows.Forms.ToolStripMenuItem((Get-SelfXString 'Tray_Menu_Notify'))
		$Global:Tray_Notify_Item.CheckOnClick = $true
		$Global:Tray_Notify_Item.Add_Click({
			Set-TrayUserSetting 'TrayNotifications' ([int]$Global:Tray_Notify_Item.Checked)
			Write-SelfXLog "Notifications switched $(If($Global:Tray_Notify_Item.Checked) { 'on' } Else { 'off' }) in the menu of the icon."
		})
		[void]$Menu.Items.Add($Global:Tray_Notify_Item)
		# The setting can also be changed in SelfX > Settings: show the current state when the menu opens.
		$Menu.Add_Opening({ $Global:Tray_Notify_Item.Checked = Test-TrayNotificationsOn })
	}
[void]$Menu.Items.Add((Get-SelfXString 'Tray_Menu_Hide'), $null, {
	Set-TrayUserSetting 'TrayIcon' 0
	$Global:Tray.ShowBalloonTip(4000, $Global:Tray_Tool_Name, (Get-SelfXString 'Tray_Hidden_Text'), [System.Windows.Forms.ToolTipIcon]::Info)
	$Global:Tray_Exit_At = (Get-Date).AddSeconds(5)
})
$Global:Tray.ContextMenuStrip = $Menu
$Global:Tray.Add_MouseDoubleClick({ Open-SelfX 'Status' })
$Global:Tray.Add_BalloonTipClicked({ Open-SelfX 'Status' })
$Global:Tray.Visible = $true

#******************************************************************************
# Timer: user switch, update/uninstall detection, status polling
#******************************************************************************
$Global:Tray_Ticks = 0
$Global:Tray_Missing = 0
$Global:Tray_Exit_At = $null
$Global:Tray_Timer = New-Object System.Windows.Forms.Timer
$Global:Tray_Timer.Interval = 1000
$Global:Tray_Timer.Add_Tick({
	$Global:Tray_Ticks++
	If($Global:Tray_Exit_At -and ((Get-Date) -ge $Global:Tray_Exit_At)) { Stop-Tray 'hidden by the user'; return }
	If($Global:Tray_Command.WaitOne(0))
		{
			# SelfX > Settings: the icon was switched off, or the language was changed (restart in the new language).
			If([int](Get-TrayUserSetting 'TrayIcon' 1) -eq 0) { Stop-Tray 'switched off in SelfX > Settings'; return }
			If((Get-TrayLanguageSetting) -ne $Global:Tray_Language_Setting)
				{
					Stop-Tray 'restart in the new language'
					Try { Start-SelfXHiddenPowerShell -Path $Global:Tray_Script } Catch {}
					return
				}
		}

	If(($Global:Tray_Ticks % 10) -eq 0)
		{
			$Config_File = Join-Path $Global:Tray_Folder 'Tool_Config.xml'
			If(-not (Test-Path -LiteralPath $Global:Tray_Script) -or -not (Test-Path -LiteralPath $Config_File))
				{
					# Uninstalled (or replaced right now): close after one minute without the files.
					$Global:Tray_Missing++
					If($Global:Tray_Missing -ge 6) { Stop-Tray 'SelfX was uninstalled' }
					return
				}
			$Global:Tray_Missing = 0
			$Config_Time = (Get-Item -LiteralPath $Config_File).LastWriteTimeUtc
			If(($Config_Time -ne $Global:Tray_Config_Time) -and (((Get-Date).ToUniversalTime() - $Config_Time).TotalSeconds -gt 30))
				{
					# SelfX was updated: start the new version of the icon and close this one.
					Stop-Tray 'SelfX was updated, the new version starts'
					Try { Start-SelfXHiddenPowerShell -Path $Global:Tray_Script } Catch {}
					return
				}
		}

	If($Global:Tray_Job -and $Global:Tray_Job.IsCompleted)
		{
			Try { $Data = @($Global:Tray_PS.EndInvoke($Global:Tray_Job)) | Select-Object -Last 1 } Catch { $Data = [pscustomobject]@{ Ok = $false; Items = @() } }
			$Global:Tray_PS.Dispose()
			$Global:Tray_Job = $null
			Update-TrayStatus $Data
		}
	If($Global:Tray_Info_Job -and $Global:Tray_Info_Job.IsCompleted)
		{
			Try { [void]$Global:Tray_Info_PS.EndInvoke($Global:Tray_Info_Job) } Catch {}
			$Global:Tray_Info_PS.Dispose()
			$Global:Tray_Info_Job = $null
		}
	# Status every Tray_Poll_Seconds (first after 5 seconds); system information 30 seconds after the start and every hour.
	If(($Global:Tray_Ticks % $Global:Tray_Poll_Seconds) -eq 5) { Start-TrayStatusJob Cached }
	If(($Global:Tray_Ticks % 3600) -eq 30 -and -not $Global:Tray_Info_Job) { Start-TraySystemInfoCache }
})
$Global:Tray_Timer.Start()
[System.Windows.Forms.Application]::Run()
