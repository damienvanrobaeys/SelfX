<#
.SYNOPSIS
    Checks the SelfX language files for completeness and errors.

.DESCRIPTION
    Compares every file in Sources\Languages (or only the files given with -Culture) with the English
    reference en.xml and the action catalogue Issues_List.xml and reports:
      - files that are not valid XML or have a wrong root element / Culture attribute
      - missing or unknown texts in the UI and SystemInfo sections
      - missing or unknown categories, shared messages and actions of the catalogue
      - placeholders ({0}, {1:D2} ...) that differ from the English text
      - a different number of "|" separators in SystemInfo_Export_Filter

    Missing texts are warnings (SelfX shows the English text instead). Wrong placeholders, unknown
    Ids and invalid files are errors. The script only reads files; it changes nothing.

.PARAMETER SourcesFolder
    Sources folder of the package. Default: the Sources folder next to this script.

.PARAMETER Culture
    Optional list of cultures to check, for example de, fr. Default: all files.

.EXAMPLE
    .\Test-LanguageFiles.ps1
    .\Test-LanguageFiles.ps1 -Culture de, it

.NOTES
    Name    : Test-LanguageFiles.ps1
    Package : SelfX Service
    Context : Packaging tool (run by the administrator before building the package; not installed)
    Version : 2.2.0
    Exit code: 0 = no errors, 1 = errors found

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.2.0    2026-10-28  Wolfgang Baeck       Initial version
#>
param(
	[string]$SourcesFolder = (Join-Path $PSScriptRoot 'Sources'),
	[string[]]$Culture
)

$LanguageFolder = Join-Path $SourcesFolder 'Languages'

Function Read-Xml([string]$Path)
{
	$Document = New-Object System.Xml.XmlDocument
	$Document.Load($Path)
	return $Document
}

Function Get-Placeholders([string]$Text)
{
	# Sorted list of {n} / {n:format} placeholders, used to compare a translation with the English text
	return (([regex]::Matches("$Text", '\{\d+(:[^}]*)?\}') | ForEach-Object { $_.Value } | Sort-Object) -join ' ')
}

Function Get-Section([System.Xml.XmlDocument]$Document, [string]$XPath)
{
	# Element name -> text of all child elements of a section
	$Table = @{}
	$Node = $Document.SelectSingleNode($XPath)
	If($Node -ne $null)
		{
			foreach($Child in $Node.ChildNodes)
				{
					If($Child.NodeType -eq 'Element') { $Table[$Child.LocalName] = $Child.InnerText }
				}
		}
	return $Table
}

Function Get-IdTable([System.Xml.XmlDocument]$Document, [string]$XPath)
{
	# Id attribute -> element, for categories, messages and actions
	$Table = @{}
	foreach($Node in $Document.SelectNodes($XPath)) { $Table[$Node.GetAttribute('Id')] = $Node }
	return $Table
}

$Reference = Read-Xml (Join-Path $LanguageFolder 'en.xml')
$Catalog = Read-Xml (Join-Path $SourcesFolder 'Issues_List.xml')

$Reference_UI = Get-Section $Reference '/SelfX_Language/UI'
$Reference_SystemInfo = Get-Section $Reference '/SelfX_Language/SystemInfo'
$Reference_Categories = Get-IdTable $Reference '/SelfX_Language/Catalog/Categories/Category'
$Catalog_Messages = Get-IdTable $Catalog '/Actions/Messages/Message'
$Catalog_Actions = Get-IdTable $Catalog '/Actions/*/Action'

$Files = Get-ChildItem -LiteralPath $LanguageFolder -Filter '*.xml' | Sort-Object Name
If($Culture) { $Files = $Files | Where-Object { $Culture -contains $_.BaseName } }

$Total_Errors = 0
$Results = foreach($File in $Files)
	{
		$Errors = New-Object System.Collections.Generic.List[string]
		$Warnings = New-Object System.Collections.Generic.List[string]
		Try
			{
				$Document = Read-Xml $File.FullName
			}
		Catch
			{
				$Errors.Add("Invalid XML: $($_.Exception.Message)")
				$Document = $null
			}

		If($Document -ne $null)
			{
				$Root = $Document.DocumentElement
				If($Root.LocalName -ne 'SelfX_Language') { $Errors.Add("Root element must be SelfX_Language") }
				If($Root.GetAttribute('Culture') -ne $File.BaseName) { $Errors.Add("Culture attribute '$($Root.GetAttribute('Culture'))' does not match the file name") }
				If(@('LeftToRight', 'RightToLeft') -notcontains $Root.GetAttribute('FlowDirection')) { $Errors.Add("FlowDirection must be LeftToRight or RightToLeft") }
				Try { [void][System.Globalization.CultureInfo]::GetCultureInfo($File.BaseName) } Catch { $Errors.Add("'$($File.BaseName)' is not a known culture name") }

				# UI and SystemInfo texts: same element names and placeholders as en.xml
				foreach($Pair in @(@('/SelfX_Language/UI', $Reference_UI), @('/SelfX_Language/SystemInfo', $Reference_SystemInfo)))
					{
						$Texts = Get-Section $Document $Pair[0]
						foreach($Key in $Pair[1].Keys)
							{
								If((-not $Texts.ContainsKey($Key)) -or [string]::IsNullOrWhiteSpace($Texts[$Key])) { $Warnings.Add("Missing text $($Pair[0])/$Key"); continue }
								If((Get-Placeholders $Texts[$Key]) -ne (Get-Placeholders $Pair[1][$Key])) { $Errors.Add("Placeholders differ in $Key") }
							}
						foreach($Key in $Texts.Keys) { If(-not $Pair[1].ContainsKey($Key)) { $Errors.Add("Unknown text $($Pair[0])/$Key") } }
					}
				$Filter = $Document.SelectSingleNode('/SelfX_Language/UI/SystemInfo_Export_Filter')
				If(($Filter -ne $null) -and (($Filter.InnerText.Split('|').Count) -ne ($Reference_UI['SystemInfo_Export_Filter'].Split('|').Count)))
					{
						$Errors.Add("SystemInfo_Export_Filter must keep the same number of '|' separators")
					}

				# Catalogue: categories, shared messages and actions
				$Categories = Get-IdTable $Document '/SelfX_Language/Catalog/Categories/Category'
				foreach($Id in $Reference_Categories.Keys) { If(-not $Categories.ContainsKey($Id)) { $Warnings.Add("Missing category $Id") } }
				foreach($Id in $Categories.Keys) { If(-not $Reference_Categories.ContainsKey($Id)) { $Errors.Add("Unknown category $Id") } }

				If($File.BaseName -ne 'en')
					{
						$Messages = Get-IdTable $Document '/SelfX_Language/Catalog/Messages/Message'
						foreach($Id in $Catalog_Messages.Keys) { If(-not $Messages.ContainsKey($Id)) { $Warnings.Add("Missing message $Id") } }
						foreach($Id in $Messages.Keys) { If(-not $Catalog_Messages.ContainsKey($Id)) { $Errors.Add("Unknown message $Id") } }

						$Actions = Get-IdTable $Document '/SelfX_Language/Catalog/Actions/Action'
						foreach($Id in $Catalog_Actions.Keys)
							{
								If(-not $Actions.ContainsKey($Id)) { $Warnings.Add("Missing action $Id"); continue }
								foreach($Field in 'Name', 'Explanation', 'Alerte_MSG')
									{
										# Fields that use a shared message (Ref) need no own translation
										$Base = $Catalog_Actions[$Id].SelectSingleNode($Field)
										If(($Base -eq $null) -or $Base.GetAttribute('Ref')) { continue }
										$Node = $Actions[$Id].SelectSingleNode($Field)
										If(($Node -eq $null) -or [string]::IsNullOrWhiteSpace($Node.InnerText)) { $Warnings.Add("Missing $Field of action $Id") }
									}
							}
						foreach($Id in $Actions.Keys) { If(-not $Catalog_Actions.ContainsKey($Id)) { $Errors.Add("Unknown action $Id") } }
					}
			}

		$Total_Errors += $Errors.Count
		foreach($Message in $Errors) { Write-Host "[$($File.BaseName)] ERROR   $Message" -ForegroundColor Red }
		foreach($Message in $Warnings) { Write-Host "[$($File.BaseName)] WARNING $Message" -ForegroundColor Yellow }

		[pscustomobject]@{
			Culture    = $File.BaseName
			NativeName = $(If($Document -ne $null) { $Document.DocumentElement.GetAttribute('NativeName') })
			Direction  = $(If($Document -ne $null) { $Document.DocumentElement.GetAttribute('FlowDirection') })
			Errors     = $Errors.Count
			Warnings   = $Warnings.Count
		}
	}

$Results | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
If($Total_Errors -gt 0) { exit 1 }
exit 0
