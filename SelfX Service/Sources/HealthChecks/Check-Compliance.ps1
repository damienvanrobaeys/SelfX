<#
.SYNOPSIS
    Local check of the Intune compliance criteria for the SelfX "Compliance" row.
.DESCRIPTION
    Intune evaluates device compliance in the cloud; Windows stores no local compliance state
    that SelfX could read. This script checks the same device criteria that a typical Intune
    Windows compliance policy requires, so the user sees which local setting would make the
    device non-compliant. The authoritative status remains the one in the Company Portal.

    Runs read-only as SYSTEM through the SelfX service (HealthStatus.ps1, <Compliance> element in
    Health_Config.xml). It changes nothing, does not prompt and starts no other process.
    Align the $Require settings below with the Intune compliance policy of the organization.

    Output : one line (the last line is shown as detail on the status card).
    Exit   : 0 = all criteria met (OK); 1 = at least one criterion not met (shown as a warning).
    Logs the result to ProgramData\SelfX\Logs (SelfXLog.ps1 in the install folder).
.NOTES
    Name    : Check-Compliance.ps1
    Package : SelfX Service
    Context : SYSTEM (SelfX service, health check)
    Version : 2.6.0
    Author  : Wolfgang Baeck (Swisscom)

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.5.5    2026-11-05  Wolfgang Baeck       Initial local compliance criteria check
    2.6.0    2026-11-06  Wolfgang Baeck       Logging (SelfXLog.ps1); the output line is unchanged
#>

$ErrorActionPreference = 'Stop'

# Logging to ProgramData\SelfX\Logs (writes no output, so the result line stays the last line of stdout).
$SelfXLogScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'SelfXLog.ps1'
if (Test-Path -LiteralPath $SelfXLogScript) { . $SelfXLogScript; Initialize-SelfXLog -Component 'Check-Compliance' }
else { function Write-SelfXLog { param($Message, $Level) } }

# Criteria of the Intune compliance policy. $false = not checked.
$Require = @{
    Enrollment = $true    # Device is enrolled in Intune (MDM)
    BitLocker  = $true    # Device Health: BitLocker (system drive protected)
    SecureBoot = $true    # Device Health: Secure Boot enabled
    Tpm        = $true    # System Security: Trusted Platform Module
    Firewall   = $true    # System Security: Firewall (all profiles)
    Defender   = $true    # System Security: Antivirus, Antispyware, Defender, real-time protection
    Signatures = $true    # System Security: Defender security intelligence up to date
}
# Minimum OS version, for example '10.0.22631'; empty = not checked.
$MinimumOSVersion = ''

$Failed = New-Object System.Collections.Generic.List[string]
$Passed = New-Object System.Collections.Generic.List[string]

function Test-Criterion {
    param([string]$Name, [scriptblock]$Test)
    try {
        $problem = & $Test
        if ($problem) { $Failed.Add("$Name ($problem)") } else { $Passed.Add($Name) }
    } catch { $Failed.Add("$Name (not readable: $($_.Exception.Message))") }
}

if ($Require.Enrollment) {
    Test-Criterion 'Intune enrollment' {
        $enrolled = @(Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction Stop | ForEach-Object {
            $values = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
            if ($values.ProviderID -eq 'MS DM Server' -and "$($values.EnrollmentState)" -eq '1') { $_ }
        })
        if (-not $enrolled.Count) { 'not enrolled' }
    }
}

if ($Require.BitLocker) {
    Test-Criterion 'BitLocker' {
        $volume = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
        if ("$($volume.ProtectionStatus)" -ne 'On') { "$env:SystemDrive protection $($volume.ProtectionStatus)" }
    }
}

if ($Require.SecureBoot) {
    Test-Criterion 'Secure Boot' {
        $secureBoot = $false
        try { $secureBoot = Confirm-SecureBootUEFI -ErrorAction Stop }
        catch [System.PlatformNotSupportedException] { return 'not supported (legacy BIOS)' }
        if (-not $secureBoot) { 'off' }
    }
}

if ($Require.Tpm) {
    Test-Criterion 'TPM' {
        $tpm = Get-Tpm -ErrorAction Stop
        if (-not $tpm.TpmPresent) { 'not present' } elseif (-not $tpm.TpmReady) { 'not ready' }
    }
}

if ($Require.Firewall) {
    Test-Criterion 'Firewall' {
        $off = @(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop | Where-Object { "$($_.Enabled)" -ne 'True' })
        if ($off.Count) { 'off: ' + (($off | ForEach-Object { $_.Name }) -join ', ') }
    }
}

if ($Require.Defender -or $Require.Signatures) {
    $mp = $null
    try { $mp = Get-MpComputerStatus -ErrorAction Stop } catch { $Failed.Add("Defender (not readable: $($_.Exception.Message))") }
    if ($mp -and $Require.Defender) {
        Test-Criterion 'Defender' {
            $off = @()
            if (-not $mp.AMServiceEnabled) { $off += 'service' }
            if (-not $mp.AntivirusEnabled) { $off += 'antivirus' }
            if (-not $mp.AntispywareEnabled) { $off += 'antispyware' }
            if (-not $mp.RealTimeProtectionEnabled) { $off += 'real-time protection' }
            if ($off.Count) { 'off: ' + ($off -join ', ') }
        }
    }
    if ($mp -and $Require.Signatures) {
        Test-Criterion 'Defender signatures' {
            if ($mp.DefenderSignaturesOutOfDate) { "out of date, $($mp.AntivirusSignatureAge) day(s) old" }
        }
    }
}

if ($MinimumOSVersion) {
    Test-Criterion 'OS version' {
        $current = [Environment]::OSVersion.Version
        $build = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuildNumber -ErrorAction Stop).CurrentBuildNumber
        $os = [version]('{0}.{1}.{2}' -f $current.Major, $current.Minor, $build)
        if ($os -lt [version]$MinimumOSVersion) { "$os is lower than $MinimumOSVersion" }
    }
}

if ($Failed.Count) {
    $text = 'Not met: ' + ($Failed -join '; ') + '. Status in Intune: see Company Portal.'
    Write-SelfXLog $text Warning
    Write-Output $text
    exit 1
}
$text = 'Local compliance criteria met: ' + ($Passed -join ', ') + '. Authoritative status: Company Portal.'
Write-SelfXLog $text
Write-Output $text
exit 0
