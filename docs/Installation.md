# Installation

SelfX consists of three independent Windows packages. **SelfX Service** replaces
Standard and Admin for devices that must support users without a network
connection. Choose the package that matches the intended user experience and
execution context.

## Requirements

- A supported Windows desktop with Windows PowerShell and WPF.
- The complete package directory, including its `assembly` and
  `Scripts_to_run` content.
- For SelfX Admin, `ServiceUI.exe` and a signed-in interactive user session if
  the UI is to be displayed to that user.
- For SelfX Service, 64-bit Windows PowerShell 5.1 and .NET Framework 4.x. The
  installer compiles the service with the C# compiler that ships with the .NET
  Framework, so no internet access or SDK is needed.

## SelfX Service

SelfX Service installs machine-wide and runs fully offline. Run the installer
as administrator, either manually or from Intune/SCCM in SYSTEM context:

```powershell
Set-Location 'C:\Path\To\SelfX Service'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

From a 32-bit agent, use
`%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe`. The installer:

1. Stops and removes an existing `SelfXService`.
2. Empties `%ProgramFiles%\SelfX` and copies `Sources` and `Uninstall.ps1`
   into it. The folder itself is kept, because an open SelfX window or status
   icon may use it as working directory. Files that are briefly in use are
   retried for 20 seconds. The installer then
   replaces inherited permissions so that SYSTEM and Administrators have full
   control and Users can only read and execute.
3. Compiles `Service\SelfXService.cs` to `%ProgramFiles%\SelfX\SelfXService.exe`
   and `Service\SelfXLauncher.cs` to `%ProgramFiles%\SelfX\SelfX.exe` (2.5.3).
   `SelfX.exe` is a small starter without a console: it starts SelfX
   (`/page:<Page>` optional) or the status icon (`/tray`) with a hidden Windows
   PowerShell, so no command window appears, also not with Windows Terminal as
   default terminal.
4. Registers and starts the **SelfX Service** (`SelfXService`). It runs as
   LocalSystem, starts automatically, and restarts after a failure.
5. Creates shortcuts for all users on the public desktop and in the Start
   menu (target `SelfX.exe`), according to `Tool_Config.xml`.
6. Adds an Apps & Features entry.
7. When `Show_Tray_Icon` is `True` (default), adds the HKLM Run entry
   `SelfXTray` (`SelfX.exe /tray`), so the status icon (`SelfX_Tray.ps1`) starts at every sign-in
   for all users. Since 2.5.8 the icon also appears right after the
   installation. Running status icons are closed before the files are
   replaced. When the installer runs as SYSTEM (Intune/SCCM), it starts
   `SelfX.exe /tray` in every active user session, with the normal rights of
   the signed-in user, not elevated. The result is written to `Install.log`
   (`Status icon: Session <n>: started`). When you run the installer manually
   as administrator, Windows does not allow this: the icon appears at the next
   sign-in or when the user opens SelfX. Open SelfX windows are not closed.

The installation log is `%ProgramData%\SelfX\Logs\Install.log`. The service log
is `%ProgramData%\SelfX\Logs\SelfXService.log`. It rotates to `.old` at 5 MB.
Both logs can be read only by administrators and SYSTEM. Since 2.6.0 every
SelfX script logs to `%ProgramData%\SelfX\Logs` (one file per script and day);
the window, the status icon and the user actions log to
`%ProgramData%\SelfX\Logs\Users\<SID>`, which the installer creates so that
each user can only create and read the own folder. Log files older than
`Log_Retention_Days` (default 90) are deleted automatically; see
[Logging](Configuration.md#logging-and-log-housekeeping-selfx-service-260).

The installer exits with code 0 on success and 1 on an error. The reason is
the last line of `Install.log` (`Installation failed: ...`). Up to version
2.5.1, an update failed with exit code 1 while a user had SelfX or the status
icon open. Windows refuses to delete a folder that a running program uses as
working directory, so the installer stopped after it had already removed the
service and the files. Version 2.5.2 empties the folder instead of deleting
it. The status icon no longer uses the install folder as working directory.
To repair a device on which an older update failed, deploy 2.5.2. A sign-out
is not needed.

For Intune Win32 apps:

| Setting | Value |
|---|---|
| Install command | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1` |
| Uninstall command | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1` |
| Install behavior | System |
| Detection | Custom script `Detection.ps1`. Set `$ExpectedVersion` to the `Tool_Version` of the release. |

`Uninstall.ps1` removes the service, `%ProgramFiles%\SelfX`, the shortcuts,
the Apps & Features entry, the status icon autostart (`SelfXTray`), the status
cache (`%ProgramData%\SelfX\Cache`) and the device logs reports
(`%ProgramData%\SelfX\Reports`). Before it deletes files, it closes open
SelfX windows and status icons of all signed-in users, because they keep the
install folder in use. Before version 2.5.7, the uninstallation failed in
that case. If another program still uses a file, for example an Explorer
window opened in the install folder, the uninstaller retries for up to 90
seconds. Two leftovers are not reported as errors:

- an empty install folder that is still in use,
- a service that is only marked for deletion, for example because the
  Services console is open.

The result is logged in `%ProgramData%\SelfX\Logs\Uninstall.log`. Logs are
kept; add `-RemoveLogs` to delete `%ProgramData%\SelfX` as
well. Per-user settings and caches (`HKCU\Software\SelfX`,
`%LOCALAPPDATA%\SelfX`) are not removed.

> If a Group Policy enforces the PowerShell execution policy `AllSigned`, the
> `-ExecutionPolicy Bypass` switch has no effect. In that case, sign
> `Self_X.ps1`, `SelfXServiceClient.ps1`, `Branding.ps1`, `Localization.ps1`,
> `SystemInfo.ps1`, `HealthStatus.ps1`, `SupportReport.ps1`, `SelfX_Tray.ps1`, `SelfXLog.ps1`, all health extension scripts and all action scripts
> (including `Collect-DeviceLogs.ps1`) with a trusted code-signing
> certificate.

Before you build the package after changing or adding a language file, check
the language files. The script exits with code 1 if a file has errors:

```powershell
& '.\SelfX Service\Test-LanguageFiles.ps1'
powershell.exe -NoProfile -File '.\SelfX Service\Test-HealthStatus.ps1'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\SelfX Service\Test-DeviceLogs.ps1'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\SelfX Service\Test-UI.ps1'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\SelfX Service\Test-Scripts.ps1'
```

For version 2.3.0 health reporting, redeploy the **entire package**: the service
binary is rebuilt by the installer and must support `HEALTH`. Copying only the
new GUI to a 2.2.0 installation is not sufficient. Version 2.3.1 remediation
allowlisting, the 2.3.2 single-status recheck (`HEALTH <Id> [name]`) and the
2.3.3 `PendingReboot`/`Updates` check Ids also
require redeploying the service, not just the GUI. Version 2.3.4 (Pending
status, Defender signature update script
`Scripts_to_run\SelfX_Defender_UpdateSignature.ps1` and default remediations)
also requires redeploying the entire package. Version 2.4.0 (device logs for
the support) also requires redeploying the entire package: the service passes
the requesting user to the script (`SELFX_CALLER_SID`); with an older service
the action fails with exit code 2. Set `Support_Mail` in `Tool_Config.xml` to
the helpdesk address that receives the device logs. Version 2.5.0 (modern user
interface, background checks with status cache and the `STATUS` request, tray
icon) also requires redeploying the entire package: SelfX 2.5.0 reads the
status with `STATUS`, which older services do not know. Before packaging, set
the support contacts of the help dialog (`Support_Hours`,
`Support_Phone_number`, `Support_Mail`, `Support_Teams`, `Support_Website`)
and check the `Background` element of `Health_Config.xml`; see
[User interface](Configuration.md#user-interface-selfx-service-250) and
[Background checks](Configuration.md#background-checks-and-status-cache-selfx-service-250).
SelfX Service no longer needs the MahApps.Metro assemblies. Version 2.6.0
(logging, restart and app retry repairs, updates installed by SelfX) also requires redeploying the entire package: the installer
creates `Logs\Users` and the service compiles the log housekeeping. Configure
`Sources\Health_Config.xml` and optionally add reviewed read-only scripts under
`Sources\HealthChecks` before packaging; see
[Health status](Configuration.md#health-status-selfx-service-230).
Do not grant users write access to the install folder or check scripts.

Check the installation:

```powershell
Get-Service SelfXService
Get-Content "$env:ProgramData\SelfX\Logs\SelfXService.log" -Tail 20   # as administrator
```

## SelfX Standard

SelfX Standard installs for the current user. Run the installer from its
directory, using the account whose profile should contain SelfX:

```powershell
Set-Location 'C:\Path\To\SelfX Standard'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

The installer copies `Sources` to `%LOCALAPPDATA%\SelfX`, unblocks copied files,
and creates shortcuts according to `Sources\Tool_Config.xml`. The installer
does not require a machine-wide service. Because the destination is the current
user's profile, running it as SYSTEM installs into the SYSTEM profile rather
than the signed-in user's profile.

### Optional remote configuration

The installer accepts links to an issue-list XML and a ZIP of action scripts:

```powershell
Set-Location 'C:\Path\To\SelfX Standard'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 `
  -XML_Link 'https://example.invalid/selfx/Issues_List.xml' `
  -ZIP_Link 'https://example.invalid/selfx/Scripts_to_run.zip'
```

Use your organization's actual HTTPS URLs. The XML and scripts are executable
configuration; publish them only from a trusted, access-controlled location.
See [Configuration](Configuration.md#selfx-standard) for the update format.

### Uninstall

Close SelfX, then run `Uninstall.ps1` from the `SelfX Standard` directory in the
same user context:

```powershell
Set-Location 'C:\Path\To\SelfX Standard'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1
```

The script removes the configured Desktop and Start menu shortcuts and deletes
the current user's `%LOCALAPPDATA%\SelfX` directory recursively. Back up any
local configuration or downloaded content that must be retained.

## SelfX Admin

SelfX Admin has no installer or service-registration script in this repository.
Deploy or extract the complete `SelfX Admin` directory, then launch it from that
directory:

```powershell
Set-Location 'C:\Path\To\SelfX Admin'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Run_SelX.ps1
```

`Run_SelX.ps1` starts PowerShell through `ServiceUI.exe` and uses the current
process token. For a deployment running as SYSTEM, this can display the UI in
the interactive user's session while the actions retain the SYSTEM token. This
behavior depends on the deployment tool and the active session; it is not an
installed SelfX service and it does not elevate a standard-user process.

If running manually, use an appropriately elevated PowerShell process only
when the selected actions require it. Keep the working directory at
`SelfX Admin`, because the scripts use relative paths for XML, XAML and
assemblies.

## Building the Intune packages

`tools\New-SelfXIntuneWin.ps1` creates one `.intunewin` file per product in
the `build` folder of the repository (the folder is not committed, see
`.gitignore`). It uses `New-IntuneWinPackage` of the PowerShell module
[SvRooij.ContentPrep.Cmdlet](https://www.powershellgallery.com/packages/SvRooij.ContentPrep.Cmdlet)
(open source, GPL-3.0, by [Stephan van Rooij](https://github.com/svrooij/ContentPrep)),
an open-source re-implementation of the Microsoft Win32 Content Prep Tool.
No packaging tool is stored in the repository. If the module (0.4.0 or newer)
is missing, the script installs it for the current user from the PowerShell
Gallery (no administrator rights; `-NoModuleInstall` stops with an error
instead). To install it yourself:

```powershell
Install-Module SvRooij.ContentPrep.Cmdlet -Scope CurrentUser
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-SelfXIntuneWin.ps1
# only one product: -Product Service   (Admin, Service, User)
# with the Microsoft tool instead of the module (download it yourself from
# https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool):
#   -ToolPath C:\Tools\IntuneWinAppUtil.exe
```

| Product | Source folder | Setup file | Package |
|---|---|---|---|
| Admin | `SelfX Admin` | `Run_SelX.ps1` | `build\SelfX-Admin-<version>.intunewin` |
| Service | `SelfX Service` | `Install.ps1` | `build\SelfX-Service-<version>.intunewin` |
| User | `SelfX Standard` | `Install.ps1` | `build\SelfX-User-<version>.intunewin` |

The version is `Tool_Version` of the product (`Sources\Tool_Config.xml`; for
SelfX Admin `Issues_List.xml`). The script copies each product folder to a
temporary staging folder and leaves out the packaging tests (`Test-*.ps1`).
Before packaging it checks that the setup file exists and that every XML file
is valid. For SelfX Service it also checks that `$ExpectedVersion` in
`Detection.ps1` equals `Tool_Version`. With `-ToolPath` it verifies the
Microsoft signature of `IntuneWinAppUtil.exe`. It uploads nothing to Intune. Exit code
`0` means all packages were created; `1` means at least one failed. Run the
tests of SelfX Service before building.

The packages of the module have the same structure as those of the Microsoft
tool (`IntuneWinPackage\Contents\IntunePackage.intunewin` encrypted with
AES-256-CBC and HMAC-SHA256, `IntuneWinPackage\Metadata\Detection.xml`). The
author describes the module as a re-implementation without warranty; if
Intune rejects a package, build it again with `-ToolPath` and the Microsoft
tool.

Use the packages in Intune as follows:

| Product | Install command | Install behavior | Uninstall / detection |
|---|---|---|---|
| Service | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1` | System | `Uninstall.ps1`, custom script `Detection.ps1` (see [SelfX Service](#selfx-service)) |
| User | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1` | User | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1`, custom script `Detection.ps1` (checks `%LOCALAPPDATA%\SelfX`) |
| Admin | `%SystemRoot%\sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Run_SelX.ps1` | System | No installer and no detection script: the package only starts the UI through `ServiceUI.exe` while the app runs (see [SelfX Admin](#selfx-admin)). Choose a detection rule that fits how you offer it. |

## Deployment checklist

1. Review the XML action list and every referenced `.ps1` script.
2. Verify whether the package is launched in user or SYSTEM context.
3. Test the UI and each intended action on a non-production device.
4. Confirm the deployment tool presents the UI in the intended user session.
5. Keep the complete package together; do not omit `assembly`, icons, XML,
   XAML or action scripts.
