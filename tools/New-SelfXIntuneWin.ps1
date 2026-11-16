<#
.SYNOPSIS
    Build the Intune Win32 app packages (.intunewin) of SelfX Admin, SelfX Service and SelfX User.

.DESCRIPTION
    Wraps each product folder into one .intunewin file in the build folder of the repository:

      Product  Source folder    Setup file     Output file
      -------  ---------------  -------------  ---------------------------------
      Admin    SelfX Admin      Run_SelX.ps1   build\SelfX-Admin-<version>.intunewin
      Service  SelfX Service    Install.ps1    build\SelfX-Service-<version>.intunewin
      User     SelfX Standard   Install.ps1    build\SelfX-User-<version>.intunewin

    The packages are created with New-IntuneWinPackage of the PowerShell module
    SvRooij.ContentPrep.Cmdlet (open source, GPL-3.0, Stephan van Rooij, PowerShell Gallery).
    If the module is missing, the script installs it for the current user (Install-Module
    -Scope CurrentUser, no administrator rights). No packaging tool is kept in the repository.
    With -ToolPath the script uses the Microsoft Win32 Content Prep Tool (IntuneWinAppUtil.exe)
    instead; download it yourself from https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool.

    Each product folder is first copied to a temporary staging folder, so that packaging-only
    files (Test-*.ps1) are not shipped and the source folders stay unchanged. Before
    packaging, the script checks that the setup file exists, that all XML files are valid and,
    for SelfX Service, that $ExpectedVersion in Detection.ps1 matches Tool_Version in
    Sources\Tool_Config.xml (otherwise the Intune detection would fail after installation).
    The version in the file name comes from Tool_Version (Admin: Issues_List.xml).

    The script only reads the product folders, writes the staging folder (deleted at the end)
    and the build folder; if needed it installs the module for the current user. It uploads
    nothing to Intune.
    Exit code 0 = all requested packages created, 1 = at least one package failed.

.PARAMETER Product
    Products to build: Admin, Service, User. Default: all three.

.PARAMETER OutputFolder
    Target folder of the .intunewin files. Default: <repository>\build.

.PARAMETER ToolPath
    Optional path of the Microsoft IntuneWinAppUtil.exe. Without it the module
    SvRooij.ContentPrep.Cmdlet is used.

.PARAMETER NoModuleInstall
    Do not install SvRooij.ContentPrep.Cmdlet if it is missing; stop with an error instead.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-SelfXIntuneWin.ps1

.EXAMPLE
    .\tools\New-SelfXIntuneWin.ps1 -Product Service

.EXAMPLE
    .\tools\New-SelfXIntuneWin.ps1 -Product Service -ToolPath C:\Tools\IntuneWinAppUtil.exe

.NOTES
    Name    : New-SelfXIntuneWin.ps1
    Package : SelfX (repository tool, not installed)
    Context : Packaging, run by the administrator; no administrator rights needed
    Version : 1.1.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    1.0.0    2026-11-04  Wolfgang Baeck       Initial version
    1.1.0    2026-11-16  Wolfgang Baeck       Module SvRooij.ContentPrep.Cmdlet instead of the IntuneWinAppUtil.exe in the
                                              repository (license); the Microsoft tool is optional (-ToolPath)
#>

[CmdletBinding()]
param(
    [ValidateSet('Admin', 'Service', 'User')]
    [string[]]$Product = @('Admin', 'Service', 'User'),
    [string]$OutputFolder,
    [string]$ToolPath,
    [switch]$NoModuleInstall
)

$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 does not set $PSScriptRoot for parameter defaults, so they are resolved here.
$ScriptFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepositoryRoot = Split-Path -Parent $ScriptFolder
if (-not $OutputFolder) { $OutputFolder = Join-Path $RepositoryRoot 'build' }
$ModuleName = 'SvRooij.ContentPrep.Cmdlet'
$ModuleMinimumVersion = '0.4.0'

# Source folder, setup file and version source of every product.
$Definitions = @{
    Admin   = @{ Folder = 'SelfX Admin';    Setup = 'Run_SelX.ps1'; VersionFile = 'Issues_List.xml';         VersionXPath = '/Actions/GUI_Config/Tool_Version' }
    Service = @{ Folder = 'SelfX Service';  Setup = 'Install.ps1';  VersionFile = 'Sources\Tool_Config.xml'; VersionXPath = '/GUI_Config/Tool_Version' }
    User    = @{ Folder = 'SelfX Standard'; Setup = 'Install.ps1';  VersionFile = 'Sources\Tool_Config.xml'; VersionXPath = '/GUI_Config/Tool_Version' }
}
# Files used only to build or test a package; they are never shipped.
$ExcludedFiles = @('Test-*.ps1')

function Read-XmlFile {
    param([string]$Path)
    $document = New-Object System.Xml.XmlDocument
    $document.XmlResolver = $null
    $document.Load($Path)
    return $document
}

function Get-ProductVersion {
    param([string]$Folder, [hashtable]$Definition)
    $node = (Read-XmlFile (Join-Path $Folder $Definition.VersionFile)).SelectSingleNode($Definition.VersionXPath)
    if (-not $node -or [string]::IsNullOrWhiteSpace($node.InnerText)) { throw "No version found in $($Definition.VersionFile) ($($Definition.VersionXPath))." }
    $version = $node.InnerText.Trim()
    # The version becomes part of a file name.
    if ($version -notmatch '^[0-9A-Za-z.\-]{1,30}$') { throw "Invalid version '$version' in $($Definition.VersionFile)." }
    return $version
}

function Test-StagedPackage {
    param([string]$Stage, [string]$Name, [hashtable]$Definition, [string]$Version)
    if (-not (Test-Path -LiteralPath (Join-Path $Stage $Definition.Setup) -PathType Leaf)) { throw "Setup file '$($Definition.Setup)' is missing." }
    foreach ($xml in @(Get-ChildItem -LiteralPath $Stage -Recurse -File -Filter '*.xml')) {
        try { $null = Read-XmlFile $xml.FullName }
        catch { throw "Invalid XML '$($xml.FullName.Substring($Stage.Length + 1))': $($_.Exception.Message)" }
    }
    if ($Name -eq 'Service') {
        $detection = Get-Content -LiteralPath (Join-Path $Stage 'Detection.ps1') -Raw
        if ($detection -notmatch "\`$ExpectedVersion\s*=\s*'([^']+)'") { throw 'No $ExpectedVersion found in Detection.ps1.' }
        if ($Matches[1] -ne $Version) { throw "Detection.ps1 expects version $($Matches[1]), Tool_Config.xml has $Version. Set both to the same value." }
    }
}

function Initialize-ContentPrepModule {
    $available = Get-Module -ListAvailable -Name $ModuleName | Where-Object { $_.Version -ge [version]$ModuleMinimumVersion } |
        Sort-Object Version -Descending | Select-Object -First 1
    if (-not $available) {
        if ($NoModuleInstall) { throw "Module $ModuleName $ModuleMinimumVersion or newer is missing. Install it: Install-Module $ModuleName -Scope CurrentUser" }
        Write-Host "Installing module $ModuleName for the current user from the PowerShell Gallery ..."
        # TLS 1.2 is needed by the PowerShell Gallery; Windows PowerShell 5.1 may not use it by default.
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Install-Module -Name $ModuleName -MinimumVersion $ModuleMinimumVersion -Repository PSGallery -Scope CurrentUser -Force -AllowClobber
        $available = Get-Module -ListAvailable -Name $ModuleName | Sort-Object Version -Descending | Select-Object -First 1
        if (-not $available) { throw "Module $ModuleName could not be installed." }
    }
    Import-Module -Name $available.Path -Force
    Write-Host "Packaging with $ModuleName $($available.Version)"
}

# Creates <OutputDir>\<setup file name>.intunewin, like IntuneWinAppUtil.exe.
function New-PackageFile {
    param([string]$Stage, [string]$SetupFile, [string]$OutputDir)
    $created = Join-Path $OutputDir ([IO.Path]::GetFileNameWithoutExtension($SetupFile) + '.intunewin')
    if ($ToolPath) {
        # -q: no prompts and overwrite.
        $toolLog = @(& $ToolPath -c $Stage -s $SetupFile -o $OutputDir -q 2>&1)
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $created -PathType Leaf)) {
            throw "IntuneWinAppUtil.exe failed (exit code $LASTEXITCODE): $(($toolLog | Select-Object -Last 5) -join ' / ')"
        }
    } else {
        $null = New-IntuneWinPackage -SourcePath $Stage -SetupFile $SetupFile -DestinationPath $OutputDir
        if (-not (Test-Path -LiteralPath $created -PathType Leaf)) { throw "New-IntuneWinPackage created no file $created." }
    }
    return $created
}

if ($ToolPath) {
    if (-not (Test-Path -LiteralPath $ToolPath -PathType Leaf)) { throw "IntuneWinAppUtil.exe not found: $ToolPath" }
    $signature = Get-AuthenticodeSignature -LiteralPath $ToolPath
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notlike 'CN=Microsoft Corporation,*') {
        throw "IntuneWinAppUtil.exe is not validly signed by Microsoft ($($signature.Status))."
    }
    Write-Host "Packaging with $ToolPath"
} else {
    Initialize-ContentPrepModule
}
New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
$OutputFolder = (Resolve-Path -LiteralPath $OutputFolder).Path

$workRoot = Join-Path ([IO.Path]::GetTempPath()) ('SelfX-IntuneWin-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$results = New-Object System.Collections.Generic.List[object]
try {
    foreach ($name in $Product) {
        $definition = $Definitions[$name]
        $sourceFolder = Join-Path $RepositoryRoot $definition.Folder
        $stage = Join-Path $workRoot "$name\source"
        $toolOutput = Join-Path $workRoot "$name\output"
        $version = $null
        try {
            if (-not (Test-Path -LiteralPath $sourceFolder -PathType Container)) { throw "Source folder not found: $sourceFolder" }
            $version = Get-ProductVersion -Folder $sourceFolder -Definition $definition
            Write-Host "Building SelfX $name $version from '$($definition.Folder)' ..."

            New-Item -ItemType Directory -Path $stage, $toolOutput -Force | Out-Null
            Copy-Item -Path (Join-Path $sourceFolder '*') -Destination $stage -Recurse -Force
            foreach ($pattern in $ExcludedFiles) {
                Get-ChildItem -LiteralPath $stage -Recurse -File -Filter $pattern | Remove-Item -Force
            }
            Test-StagedPackage -Stage $stage -Name $name -Definition $definition -Version $version

            $created = New-PackageFile -Stage $stage -SetupFile $definition.Setup -OutputDir $toolOutput

            $target = Join-Path $OutputFolder ('SelfX-{0}-{1}.intunewin' -f $name, $version)
            Move-Item -LiteralPath $created -Destination $target -Force
            $file = Get-Item -LiteralPath $target
            $results.Add([pscustomobject]@{
                Product   = $name
                Version   = $version
                SetupFile = $definition.Setup
                Files     = @(Get-ChildItem -LiteralPath $stage -Recurse -File).Count
                SizeKB    = [math]::Round($file.Length / 1KB)
                Package   = $file.FullName
                Status    = 'OK'
            })
        } catch {
            Write-Warning "SelfX $name failed: $($_.Exception.Message)"
            $results.Add([pscustomobject]@{ Product = $name; Version = $version; SetupFile = $definition.Setup; Files = $null; SizeKB = $null; Package = $null; Status = "Failed: $($_.Exception.Message)" })
        }
    }
} finally {
    Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$results | Format-Table Product, Version, SetupFile, Files, SizeKB, Status -AutoSize | Out-String -Width 200 | Write-Host
$results | Where-Object Status -eq 'OK' | ForEach-Object { Write-Host "  $($_.Package)" }
if (@($results | Where-Object Status -ne 'OK').Count) { exit 1 }
exit 0
