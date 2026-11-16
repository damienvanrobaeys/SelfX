<#
.SYNOPSIS
    Language support for the SelfX GUI: loads the language file that matches the Windows display language.

.DESCRIPTION
    The texts of the user interface, the action catalogue and the System information tab are stored in
    Sources\Languages\<culture>.xml (for example de.xml, fr.xml, zh-Hans.xml). This script selects the file
    that fits the Windows display language of the signed-in user and returns the texts.

    Selection of the language:
      1. The language chosen by the user in SelfX > Settings (HKCU\Software\SelfX\Language, see
         Resolve-SelfXLanguageSetting), unless the administrator hides the choice (Show_Language_Setting).
      2. Otherwise Tool_Language in Tool_Config.xml. "Auto" (default) uses the Windows display language
         (CurrentUICulture), any other value is used as culture name, for example "de" or "fr-CH".
      3. The culture and its parent cultures are tried in order, for example
         de-CH -> de, zh-TW -> zh-Hant -> zh, pt-BR -> pt.
         Swiss German (gsw, including gsw-CH) also falls back to German (de).
      4. If no file matches, English (en.xml) is used.

    Every text is looked up in the selected language first and then in English. Catalogue texts that are
    missing in both files fall back to the English base text in Issues_List.xml. A new language therefore
    only needs a new file in the Languages folder; no code change is required.

    The script only reads local files. It does not need a network connection.

.NOTES
    Name    : Localization.ps1
    Package : SelfX Service
    Context : GUI helper (dot-sourced by Self_X.ps1 as the signed-in user)
    Version : 2.5.9

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.2.0    2026-10-28  Wolfgang Baeck       Initial version: multilingual user interface
    2.2.0    2026-10-28  Wolfgang Baeck       Use German for Swiss German cultures
    2.4.0    2026-11-02  Wolfgang Baeck       Pass the Post_Action field of catalogue actions
    2.5.9    2026-11-05  Wolfgang Baeck       Language chosen by the user: Get-SelfXLanguageList, Resolve-SelfXLanguageSetting,
                                              Get-SelfXLanguageFileCulture
#>

$Script:SelfX_Language = $null
$Script:SelfX_LanguageFallback = $null

Function Read-SelfXLanguageFile
{
	<#
	.SYNOPSIS
		Loads one language file. Returns $null if the file is missing or not valid XML.
	#>
	param([string]$Path)
	If(-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
	Try
		{
			# XmlDocument.Load honours the encoding declaration, so UTF-8 files without BOM are read correctly
			$Document = New-Object System.Xml.XmlDocument
			$Document.Load($Path)
			If($Document.DocumentElement.LocalName -ne 'SelfX_Language') { return $null }
			return $Document
		}
	Catch
		{
			return $null
		}
}

Function Get-SelfXCultureCandidates
{
	<#
	.SYNOPSIS
		Returns the culture name and all parent culture names, for example de-CH, de.
	#>
	param([System.Globalization.CultureInfo]$Culture)
	$Names = New-Object System.Collections.Generic.List[string]
	$Current = $Culture
	While(($Current -ne $null) -and ($Current.Name -ne ''))
		{
			If(-not $Names.Contains($Current.Name)) { $Names.Add($Current.Name) }
			$Current = $Current.Parent
		}
	If(($Culture -ne $null) -and ($Culture.TwoLetterISOLanguageName -eq 'gsw') -and (-not $Names.Contains('de')))
		{
			$Names.Add('de')
		}
	return $Names
}

Function Test-SelfXLanguageName
{
	<#
	.SYNOPSIS
		True for a culture name such as "de", "fr-CH" or "zh-Hans" (no path characters).
	#>
	param([string]$Name)
	return ("$Name" -match '^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8}){0,2}$')
}

Function Resolve-SelfXLanguageSetting
{
	<#
	.SYNOPSIS
		Returns the language setting for Initialize-SelfXLanguage: the choice of the user or Tool_Language.
	.DESCRIPTION
		The user choice (HKCU\Software\SelfX\Language) wins when the administrator allows it
		(Show_Language_Setting), it is a valid culture name and its language file exists. "Auto" or an
		empty user value means "use the default", that is Tool_Language (normally "Auto" = Windows language).
	#>
	param(
		[string]$ConfigLanguage = 'Auto',
		[string]$UserLanguage = '',
		[bool]$AllowUserChoice = $true,
		[string]$LanguageFolder = ''
	)
	$User = "$UserLanguage".Trim()
	If($AllowUserChoice -and ($User -ne '') -and ($User -ne 'Auto') -and (Test-SelfXLanguageName $User))
		{
			If(($LanguageFolder -eq '') -or (Test-Path -LiteralPath (Join-Path $LanguageFolder "$User.xml") -PathType Leaf)) { return $User }
		}
	$Config = "$ConfigLanguage".Trim()
	If($Config -eq '') { return 'Auto' }
	return $Config
}

Function Get-SelfXLanguageFileCulture
{
	<#
	.SYNOPSIS
		Returns the culture of the language file that Initialize-SelfXLanguage selects for a setting, without loading it.
	#>
	param(
		[string]$LanguageFolder,
		[string]$Language = 'Auto'
	)
	$Culture = [System.Globalization.CultureInfo]::CurrentUICulture
	If((-not [string]::IsNullOrWhiteSpace($Language)) -and ($Language.Trim() -ne 'Auto'))
		{
			Try { $Culture = [System.Globalization.CultureInfo]::GetCultureInfo($Language.Trim()) } Catch {}
		}
	foreach($Name in (Get-SelfXCultureCandidates -Culture $Culture))
		{
			If(Test-Path -LiteralPath (Join-Path $LanguageFolder "$Name.xml") -PathType Leaf) { return $Name }
		}
	return 'en'
}

Function Get-SelfXLanguageList
{
	<#
	.SYNOPSIS
		Returns the available languages (Culture, Name in the language itself, FlowDirection), sorted by name.
	.DESCRIPTION
		Only the root element of each file is read, so the list is fast. Files whose name differs from their
		Culture attribute or that are no SelfX language file are skipped.
	#>
	param([string]$LanguageFolder)
	$List = New-Object System.Collections.Generic.List[object]
	foreach($File in @(Get-ChildItem -LiteralPath $LanguageFolder -Filter '*.xml' -File -ErrorAction SilentlyContinue))
		{
			$Reader = $null
			Try
				{
					$Settings = New-Object System.Xml.XmlReaderSettings
					$Settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
					$Reader = [System.Xml.XmlReader]::Create($File.FullName, $Settings)
					[void]$Reader.MoveToContent()
					If($Reader.LocalName -ne 'SelfX_Language') { continue }
					$Culture = $Reader.GetAttribute('Culture')
					If(($Culture -ne $File.BaseName) -or -not (Test-SelfXLanguageName $Culture)) { continue }
					$Name = $Reader.GetAttribute('NativeName')
					If([string]::IsNullOrWhiteSpace($Name)) { $Name = $Culture }
					$Flow = $(If($Reader.GetAttribute('FlowDirection') -eq 'RightToLeft') { 'RightToLeft' } Else { 'LeftToRight' })
					$List.Add([pscustomobject]@{ Culture = $Culture; Name = $Name; FlowDirection = $Flow })
				}
			Catch {}
			Finally
				{
					If($Reader -ne $null) { $Reader.Dispose() }
				}
		}
	return @($List | Sort-Object -Property @{ Expression = { $_.Name.ToLowerInvariant() } })
}

Function Initialize-SelfXLanguage
{
	<#
	.SYNOPSIS
		Selects and loads the language file. Returns an object with Culture, Name, FlowDirection and File.
	.PARAMETER LanguageFolder
		Folder with the language files (Sources\Languages).
	.PARAMETER Language
		"Auto" or empty = Windows display language, otherwise a culture name such as "de" or "fr-CH".
	#>
	param(
		[string]$LanguageFolder,
		[string]$Language = 'Auto'
	)

	$Culture = [System.Globalization.CultureInfo]::CurrentUICulture
	If((-not [string]::IsNullOrWhiteSpace($Language)) -and ($Language.Trim() -ne 'Auto'))
		{
			Try { $Culture = [System.Globalization.CultureInfo]::GetCultureInfo($Language.Trim()) }
			Catch { $Culture = [System.Globalization.CultureInfo]::CurrentUICulture }
		}

	$Script:SelfX_LanguageFallback = Read-SelfXLanguageFile -Path (Join-Path $LanguageFolder 'en.xml')
	$Script:SelfX_Language = $null
	$Selected_File = $null

	foreach($Name in (Get-SelfXCultureCandidates -Culture $Culture))
		{
			$Path = Join-Path $LanguageFolder "$Name.xml"
			$Document = Read-SelfXLanguageFile -Path $Path
			If($Document -ne $null)
				{
					$Script:SelfX_Language = $Document
					$Selected_File = $Path
					break
				}
		}

	If($Script:SelfX_Language -eq $null)
		{
			$Script:SelfX_Language = $Script:SelfX_LanguageFallback
			$Selected_File = Join-Path $LanguageFolder 'en.xml'
		}

	$Root = $null
	If($Script:SelfX_Language -ne $null) { $Root = $Script:SelfX_Language.DocumentElement }

	$Flow = 'LeftToRight'
	If(($Root -ne $null) -and ($Root.GetAttribute('FlowDirection') -eq 'RightToLeft')) { $Flow = 'RightToLeft' }

	$Culture_Name = 'en'
	If(($Root -ne $null) -and $Root.GetAttribute('Culture')) { $Culture_Name = $Root.GetAttribute('Culture') }

	return [pscustomobject]@{
		Culture       = $Culture_Name
		Name          = $(If($Root -ne $null){ $Root.GetAttribute('NativeName') } Else { 'English' })
		FlowDirection = $Flow
		File          = $Selected_File
		WindowsCulture = $Culture.Name
	}
}

Function Get-SelfXLanguageNode
{
	<#
	.SYNOPSIS
		Returns the text of a node in the selected language, then in English, else $null.
	#>
	param([string]$XPath)
	foreach($Document in @($Script:SelfX_Language, $Script:SelfX_LanguageFallback))
		{
			If($Document -eq $null) { continue }
			$Node = $Document.SelectSingleNode($XPath)
			If(($Node -ne $null) -and (-not [string]::IsNullOrWhiteSpace($Node.InnerText)))
				{
					return (Format-SelfXText $Node.InnerText)
				}
		}
	return $null
}

Function Format-SelfXText
{
	<#
	.SYNOPSIS
		Removes the indentation that XML formatting adds to multi-line texts and trims the text.
	#>
	param([string]$Text)
	If($Text -eq $null) { return $null }
	$Lines = $Text -split "\r?\n" | ForEach-Object { $_.Trim() }
	return (($Lines -join "`r`n").Trim())
}

Function Get-SelfXString
{
	<#
	.SYNOPSIS
		Returns a user interface text (UI section). {0}, {1} ... are replaced by the arguments.
	.EXAMPLE
		Get-SelfXString 'Action_Success_Text' 'Restart Teams'
	#>
	param(
		[string]$Id,
		[Parameter(ValueFromRemainingArguments = $true)]
		[object[]]$Arguments
	)
	$Text = Get-SelfXLanguageNode -XPath "/SelfX_Language/UI/$Id"
	If($Text -eq $null) { $Text = $Id }
	If(($Arguments -ne $null) -and ($Arguments.Count -gt 0))
		{
			# A broken placeholder in a translation must not stop the GUI: show the text without formatting
			Try { $Text = [string]::Format($Text, [object[]]$Arguments) } Catch {}
		}
	return $Text
}

Function Get-SelfXSystemInfoTexts
{
	<#
	.SYNOPSIS
		Returns all texts of the SystemInfo section as hashtable (English values completed by the selected language).
	#>
	$Texts = @{}
	foreach($Document in @($Script:SelfX_LanguageFallback, $Script:SelfX_Language))
		{
			If($Document -eq $null) { continue }
			$Section = $Document.SelectSingleNode('/SelfX_Language/SystemInfo')
			If($Section -eq $null) { continue }
			foreach($Node in $Section.ChildNodes)
				{
					If(($Node.NodeType -eq 'Element') -and (-not [string]::IsNullOrWhiteSpace($Node.InnerText)))
						{
							$Texts[$Node.LocalName] = Format-SelfXText $Node.InnerText
						}
				}
		}
	return $Texts
}

Function Get-SelfXCategoryName
{
	<#
	.SYNOPSIS
		Returns the display name of a category Id, or the Id itself if no translation exists.
	#>
	param([string]$Id)
	$Text = Get-SelfXLanguageNode -XPath "/SelfX_Language/Catalog/Categories/Category[@Id='$Id']"
	If($Text -eq $null) { return $Id }
	return $Text
}

Function Get-SelfXCatalogField
{
	<#
	.SYNOPSIS
		Returns the localized text of one field (Name, Explanation, Alerte_MSG) of a catalogue action.
	.DESCRIPTION
		Order: translation of the action, translation of the referenced message (Ref attribute),
		English base text of the message in Issues_List.xml, English base text of the action.
	#>
	param(
		[System.Xml.XmlElement]$Action,
		[string]$Field,
		[System.Xml.XmlDocument]$Catalog
	)
	$Id = $Action.GetAttribute('Id')
	$Node = $Action.SelectSingleNode($Field)
	$Ref = $null
	If($Node -ne $null) { $Ref = $Node.GetAttribute('Ref') }

	If($Id)
		{
			$Text = Get-SelfXLanguageNode -XPath "/SelfX_Language/Catalog/Actions/Action[@Id='$Id']/$Field"
			If($Text -ne $null) { return $Text }
		}
	If($Ref)
		{
			$Text = Get-SelfXLanguageNode -XPath "/SelfX_Language/Catalog/Messages/Message[@Id='$Ref']"
			If($Text -ne $null) { return $Text }
			$Base = $Catalog.SelectSingleNode("/Actions/Messages/Message[@Id='$Ref']")
			If($Base -ne $null) { return (Format-SelfXText $Base.InnerText) }
			return $null
		}
	If($Node -ne $null) { return (Format-SelfXText $Node.InnerText) }
	return $null
}

Function Get-SelfXLocalizedActions
{
	<#
	.SYNOPSIS
		Converts the actions of one catalogue section into objects with localized texts.
	.DESCRIPTION
		Category contains the localized display name (used in the list and the filter), CategoryId the
		original Id. Script, Context, Post_Action and Buttons are taken unchanged from the catalogue.
	.PARAMETER Section
		Quick_Solution (simplified view) or Detailed_Solution (detailed view).
	#>
	param(
		[System.Xml.XmlDocument]$Catalog,
		[ValidateSet('Quick_Solution', 'Detailed_Solution')]
		[string]$Section
	)
	$Result = New-Object System.Collections.Generic.List[object]
	foreach($Action in $Catalog.SelectNodes("/Actions/$Section/Action"))
		{
			$Category_Id = ([string]$Action.Category).Trim()
			$Result.Add([pscustomobject]@{
				Name        = Get-SelfXCatalogField -Action $Action -Field 'Name' -Catalog $Catalog
				Category    = Get-SelfXCategoryName -Id $Category_Id
				Explanation = Get-SelfXCatalogField -Action $Action -Field 'Explanation' -Catalog $Catalog
				Buttons     = ([string]$Action.Buttons).Trim()
				Script      = ([string]$Action.Script).Trim()
				Alerte_MSG  = Get-SelfXCatalogField -Action $Action -Field 'Alerte_MSG' -Catalog $Catalog
				Context     = ([string]$Action.Context).Trim()
				Post_Action = ([string]$Action.Post_Action).Trim()
				CategoryId  = $Category_Id
				Id          = $Action.GetAttribute('Id')
			})
		}
	return $Result
}

Function Get-SelfXButtonText
{
	<#
	.SYNOPSIS
		Translates a button token of the catalogue (Ok, Cancel, Yes, No) into the selected language.
	#>
	param([string]$Token)
	$Token = "$Token".Trim()
	If($Token -eq '') { return $Token }
	$Key = 'Button_' + $Token.Substring(0, 1).ToUpperInvariant() + $Token.Substring(1).ToLowerInvariant()
	$Text = Get-SelfXLanguageNode -XPath "/SelfX_Language/UI/$Key"
	If($Text -eq $null) { return $Token }
	return $Text
}
