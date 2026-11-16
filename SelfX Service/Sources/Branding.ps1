<#
.SYNOPSIS
    Branding and themes of the SelfX window and the tray icon: company logo, icon and colors.

.DESCRIPTION
    Helper functions used by Self_X.ps1 and SelfX_Tray.ps1 to apply the Branding section of Tool_Config.xml:
      - Brand_Accent_Color      : company color (#RRGGBB) for buttons, selections, links and icons.
                                  Empty = Tool_Color (named color, e.g. Cyan)
      - Brand_TitleBar_Color    : background of the title bar (text color is chosen automatically)
      - Brand_Run_Button_Color  : color of the "run" and "fix" buttons
      - Brand_Info_Button_Color : color of the "more information" icons
      - Brand_Logo, Brand_Icon  : images loaded from the local install folder
    New-SelfXThemeColors builds all colors of the dark or light theme from these settings;
    Set-SelfXThemeResources puts them as brushes into a WPF resource dictionary, so every window
    that uses the dictionary changes its colors at once (for example when the user switches the theme).
    Invalid values are ignored, so a wrong setting never prevents the window from opening.
    All files are read from the local install folder; nothing is downloaded.

.NOTES
    Name    : Branding.ps1
    Package : SelfX Service
    Context : GUI helper (dot-sourced by Self_X.ps1 and SelfX_Tray.ps1 as the signed-in user)
    Version : 2.5.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.1.0    2026-10-28  Wolfgang Baeck       Initial version: company logo, icon and colors
    2.2.0    2026-10-28  Wolfgang Baeck       Comment-based header and function comments
    2.5.0    2026-11-04  Wolfgang Baeck       Modern UI: theme colors without MahApps (dark/light), named
                                              accent colors, readable accent text, title bar text color
#>

# Named accent colors of the former MahApps themes (Tool_Color), so existing configurations keep their color.
$Script:SelfXNamedAccents = @{
	Red = '#E51400'; Green = '#60A917'; Blue = '#0050EF'; Purple = '#6459DF'; Orange = '#FA6800'; Lime = '#A4C400'
	Emerald = '#008A00'; Teal = '#00ABA9'; Cyan = '#1BA1E2'; Cobalt = '#0050EF'; Indigo = '#6A00FF'; Violet = '#AA00FF'
	Pink = '#F472D0'; Magenta = '#D80073'; Crimson = '#A20025'; Amber = '#F0A30A'; Yellow = '#FEDE06'; Brown = '#825A2C'
	Olive = '#6D8764'; Steel = '#647687'; Mauve = '#76608A'; Taupe = '#87794E'; Sienna = '#A0522D'
}

# Base colors of the two themes (Windows 11 style). Status colors are fixed so that OK/warning/error look the same everywhere.
$Script:SelfXThemeBase = @{
	Dark = @{
		WindowBg = '#202020'; ContentBg = '#272727'; Surface = '#2D2D2D'; SurfaceAlt = '#343434'; Stroke = '#3D3D3D'
		HoverBg = '#3A3A3A'; SelectedBg = '#383838'; TextPrimary = '#FFFFFF'; TextSecondary = '#B4B4B4'; ScrollThumb = '#5A5A5A'
		OkBg = '#1F3A26'; OkFg = '#6CCB5F'; OkSolid = '#6CCB5F'; WarnBg = '#3D3320'; WarnFg = '#FCD34D'; WarnSolid = '#F7B500'
		ErrBg = '#442726'; ErrFg = '#FF99A4'; ErrSolid = '#D13438'; NeutralBg = '#333333'; NeutralFg = '#C8C8C8'; InfoBg = '#2B3440'
	}
	Light = @{
		WindowBg = '#F3F3F3'; ContentBg = '#F9F9F9'; Surface = '#FFFFFF'; SurfaceAlt = '#F5F5F5'; Stroke = '#E3E3E3'
		HoverBg = '#EDEDED'; SelectedBg = '#EAEAEA'; TextPrimary = '#1B1B1B'; TextSecondary = '#5F5F5F'; ScrollThumb = '#C2C2C2'
		OkBg = '#DFF6DD'; OkFg = '#107C10'; OkSolid = '#13A10E'; WarnBg = '#FFF4CE'; WarnFg = '#8A5300'; WarnSolid = '#F7B500'
		ErrBg = '#FDE7E9'; ErrFg = '#C42B1C'; ErrSolid = '#C42B1C'; NeutralBg = '#EBEBEB'; NeutralFg = '#5F5F5F'; InfoBg = '#EEF5FB'
	}
}

# Converts "#RRGGBB" or "#AARRGGBB" into a WPF color; returns $null for empty or invalid values.
Function ConvertTo-SelfXColor
{
	param([string]$Value)
	If([string]::IsNullOrWhiteSpace($Value)) { return $null }
	$Value = $Value.Trim()
	If($Value -notmatch '^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$') { return $null }
	return [System.Windows.Media.ColorConverter]::ConvertFromString($Value)
}

# Returns Color with another alpha value and brightness factor (used for the accent color variants).
Function New-SelfXColor
{
	param([System.Windows.Media.Color]$Color, [byte]$Alpha = 255, [double]$Factor = 1)
	return [System.Windows.Media.Color]::FromArgb($Alpha,
		[byte][Math]::Min(255, [Math]::Round($Color.R * $Factor)),
		[byte][Math]::Min(255, [Math]::Round($Color.G * $Factor)),
		[byte][Math]::Min(255, [Math]::Round($Color.B * $Factor)))
}

# Mixes two colors: Amount 0 = First, 1 = Second.
Function Join-SelfXColor
{
	param([System.Windows.Media.Color]$First, [System.Windows.Media.Color]$Second, [double]$Amount)
	return [System.Windows.Media.Color]::FromRgb(
		[byte][Math]::Round($First.R + ($Second.R - $First.R) * $Amount),
		[byte][Math]::Round($First.G + ($Second.G - $First.G) * $Amount),
		[byte][Math]::Round($First.B + ($Second.B - $First.B) * $Amount))
}

# Relative luminance (ITU-R BT.709) between 0 (black) and 1 (white).
Function Get-SelfXLuminance
{
	param([System.Windows.Media.Color]$Color)
	return (0.2126 * $Color.R + 0.7152 * $Color.G + 0.0722 * $Color.B) / 255
}

# Returns black or white, whichever is better readable on the given background color.
Function Get-SelfXIdealForeground
{
	param([System.Windows.Media.Color]$Color)
	If((Get-SelfXLuminance $Color) -gt 0.6) { return [System.Windows.Media.Colors]::Black }
	return [System.Windows.Media.Colors]::White
}

# Returns the accent color: Brand_Accent_Color, else the named Tool_Color, else Cyan.
Function Get-SelfXAccentColor
{
	param([string]$BrandColor, [string]$ToolColor)
	$Color = ConvertTo-SelfXColor $BrandColor
	If($Color -ne $null) { return $Color }
	$Named = $Script:SelfXNamedAccents["$ToolColor".Trim()]
	If(-not $Named) { $Named = $Script:SelfXNamedAccents['Cyan'] }
	return [System.Windows.Media.ColorConverter]::ConvertFromString($Named)
}

# Builds all theme colors (name -> Color) from the theme and the branding colors.
Function New-SelfXThemeColors
{
	param(
		[ValidateSet('Dark', 'Light')][string]$Theme = 'Dark',
		[System.Windows.Media.Color]$Accent,
		[string]$TitleBarColor = '',
		[string]$RunButtonColor = '',
		[string]$InfoButtonColor = ''
	)
	$Colors = @{}
	foreach($Key in $Script:SelfXThemeBase[$Theme].Keys) { $Colors[$Key] = [System.Windows.Media.ColorConverter]::ConvertFromString($Script:SelfXThemeBase[$Theme][$Key]) }
	$White = [System.Windows.Media.Colors]::White
	$Black = [System.Windows.Media.Colors]::Black

	$Colors['Accent'] = $Accent
	$Colors['AccentFg'] = Get-SelfXIdealForeground $Accent
	$Colors['AccentHover'] = $(If((Get-SelfXLuminance $Accent) -gt 0.5) { Join-SelfXColor $Accent $Black 0.12 } Else { Join-SelfXColor $Accent $White 0.15 })
	# Accent used for text and icons on the window background: a very dark or very light company color is adjusted to stay readable.
	$AccentText = $Accent
	If($Theme -eq 'Dark' -and (Get-SelfXLuminance $Accent) -lt 0.35) { $AccentText = Join-SelfXColor $Accent $White 0.45 }
	If($Theme -eq 'Light' -and (Get-SelfXLuminance $Accent) -gt 0.6) { $AccentText = Join-SelfXColor $Accent $Black 0.45 }
	$Colors['AccentText'] = $AccentText
	$Colors['AccentSoft'] = Join-SelfXColor $Colors['Surface'] $Accent $(If($Theme -eq 'Dark') { 0.22 } Else { 0.12 })

	$Run = ConvertTo-SelfXColor $RunButtonColor
	If($Run -eq $null) { $Run = $Accent }
	$Colors['RunButton'] = $Run
	$Colors['RunButtonFg'] = Get-SelfXIdealForeground $Run

	$Info = ConvertTo-SelfXColor $InfoButtonColor
	If($Info -eq $null) { $Info = $AccentText }
	$Colors['InfoIcon'] = $Info

	$Title = ConvertTo-SelfXColor $TitleBarColor
	If($Title -eq $null)
		{
			$Colors['TitleBarBg'] = $Colors['WindowBg']
			$Colors['TitleBarFg'] = $Colors['TextPrimary']
		}
	Else
		{
			$Colors['TitleBarBg'] = $Title
			$Colors['TitleBarFg'] = Get-SelfXIdealForeground $Title
		}
	return $Colors
}

# Puts the theme colors as frozen brushes into a resource dictionary (DynamicResource updates all windows).
Function Set-SelfXThemeResources
{
	param([System.Windows.ResourceDictionary]$Dictionary, [hashtable]$Colors)
	foreach($Key in $Colors.Keys)
		{
			$Brush = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]$Colors[$Key])
			$Brush.Freeze()
			# The cast passes the WPF object itself, not its PowerShell wrapper.
			$Dictionary[$Key] = [System.Windows.Media.Brush]$Brush
		}
}

# Loads an image file of the install folder (relative path) as BitmapImage; returns $null if it is missing or invalid.
Function Get-SelfXImage
{
	# Loads a local image (png, jpg, bmp, gif or ico) relative to the install folder; returns $null if not usable.
	param([string]$FileName, [string]$BaseFolder)
	If([string]::IsNullOrWhiteSpace($FileName)) { return $null }
	$Path = $FileName.Trim()
	If(-not [IO.Path]::IsPathRooted($Path)) { $Path = Join-Path $BaseFolder $Path }
	If(-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
	If([IO.Path]::GetExtension($Path) -notin '.png', '.jpg', '.jpeg', '.bmp', '.gif', '.ico') { return $null }
	Try
	{
		$Image = New-Object System.Windows.Media.Imaging.BitmapImage
		$Image.BeginInit()
		$Image.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
		$Image.UriSource = New-Object Uri((Resolve-Path -LiteralPath $Path).ProviderPath)
		$Image.EndInit()
		$Image.Freeze()
		return $Image
	}
	Catch
	{
		return $null
	}
}

# Returns a SolidColorBrush for "#RRGGBB", or $null when the value is empty or invalid.
Function Get-SelfXBrush
{
	param([string]$HexColor)
	$Color = ConvertTo-SelfXColor $HexColor
	If($Color -eq $null) { return $null }
	$Brush = New-Object System.Windows.Media.SolidColorBrush($Color)
	$Brush.Freeze()
	return $Brush
}
