# SelfX Service

SelfX Service combines SelfX Standard and SelfX Admin into one package that is
installed locally and works without any network connection.

- One modern, resizable user interface for users without technical knowledge
  (2.5.0): navigation bar with **Troubleshooting**, **Device status** and
  **System information**, icon buttons with explaining tooltips, dark and
  light theme, help dialog with the support contacts (hours, phone, mail,
  Teams chat, website / ticket system). See
  [User interface](../docs/Configuration.md#user-interface-selfx-service-250).
- Background checks (2.5.0): the service checks the device status regularly
  (default every 15 minutes, paused on battery, postponed under high processor
  load) and keeps the result, so SelfX shows status and system information
  immediately. See
  [Background checks](../docs/Configuration.md#background-checks-and-status-cache-selfx-service-250).
- Tray icon (2.5.0): a status icon next to the clock for every user (green,
  yellow, red) with a notification when a problem is found, for example low
  disk space. Each user can hide it. See
  [Tray icon](../docs/Configuration.md#tray-icon-selfx-service-250).
- **Fix all problems** and user time zone (2.5.3): one button on the Device
  status page runs all prepared repairs one after another; all times are shown
  in the current time zone of the user. SelfX and the status icon start
  without any command window (`SelfX.exe`).
- One action catalogue (`Sources\Issues_List.xml`). Each action has a
  `Context`:
  - `User` actions run in the signed-in user's session, as in SelfX Standard.
  - `System` actions are sent to the local **SelfXService** Windows service,
    which runs them with SYSTEM rights. In the list these actions are marked
    with a shield icon.
- No downloads, no remote configuration and no central server are needed. The
  catalogue, scripts and service are all on the device. Some individual actions
  still need the network to have an effect, for example Intune sync.
- Branding: you can set a company logo, an icon and the colors in
  `Tool_Config.xml`. See
  [Configuration](../docs/Configuration.md#branding).
- Multilingual user interface: SelfX uses the Windows display language of the
  user and falls back to English. Users can choose another language in the
  settings (saved per user, 2.5.9). 24 languages are included in
  `Sources\Languages`. To add a language, add one XML file. See
  [Configuration](../docs/Configuration.md#languages).
- Every script starts with a description and a version history.
- Status cards with an administrator-configured remediation offer a localized
  **Fix** button. Repairs run through the local service after confirmation,
  then re-check that status. Every card has a **check again** button that only
  re-checks that status. By default
  Defender (always) and Compliance (when not OK) offer a signature update
  (`Update-MpSignature`); the Defender row shows signature version and last update. See [Health remediation](../docs/Configuration.md#health-remediation).
- Local health results on the Device status page: IME, Defender, disk space,
  BitLocker, pending reboot, updates to install (offline Windows Update cache),
  a best-effort cached app summary with exclusions, configurable
  services and script probes. Cloud compliance is not inferred offline.
  See [Health status](../docs/Configuration.md#health-status-selfx-service-230).
- **Send logs to support** (2.4.0): the action *Send the device logs to the
  support* and a button in System information run `Collect-DeviceLogs.ps1`
  with administrator rights through the service. Then they open a new e-mail
  (Outlook) to `Support_Mail` with the report attached; the user describes the
  issue and sends it. See
  [Device logs for the support](../docs/Configuration.md#device-logs-for-the-support-selfx-service-240).
- Logging and repairs (2.6.0): every script logs to `%ProgramData%\SelfX\Logs`
  (users to `Logs\Users\<SID>`), old logs are deleted after `Log_Retention_Days`
  (default 90). **Restart now** on *Restart pending* (with a restart warning),
  **Try again** for failed company apps, and the update repair installs the pending Windows updates
  (2.6.3). All action scripts were checked and
  fixed (for example Word, Teams, OneDrive and the disk check). See
  [Logging](../docs/Configuration.md#logging-and-log-housekeeping-selfx-service-260)
  and [Health remediation](../docs/Configuration.md#health-remediation).

## Package layout

| Path | Contents |
|---|---|
| `Install.ps1` | Machine-wide installer. Run it as administrator. |
| `Uninstall.ps1` | Closes open SelfX windows and status icons, then removes the service, files, shortcuts and Apps & Features entry. |
| `Detection.ps1` | Detection script for Intune or SCCM. Update `$ExpectedVersion` for each release. |
| `Test-LanguageFiles.ps1` | Checks the language files against `en.xml` and the catalogue. Run it before you build the package. |
| `Test-HealthStatus.ps1` | Isolated health tests; system data and extension execution are mocked. |
| `Test-DeviceLogs.ps1` | Isolated tests of the device logs feature (wrapper, e-mail helper, catalogue, GUI step); collector, ACLs, Outlook and processes are mocked. |
| `Test-UI.ps1` | Isolated tests of the user interface (XAML, theme, texts), the tray icon notifications and the information cache; no window is shown. |
| `Test-Scripts.ps1` | Runs every action and repair script in a temporary sandbox with mocked commands and checks result and log (2.6.0); nothing on the device is changed. |
| `Sources\SelfXLog.ps1` | Shared logging of all scripts to `%ProgramData%\SelfX\Logs` and the user-side log housekeeping (2.6.0). |
| `Sources\Scripts_to_run\SelfX_Device_Restart.ps1`, `SelfX_Apps_RetryInstall.ps1`, `SelfX_Updates_Install.ps1` | Repairs of the Device status page: restart after confirmation, retry failed app installations, install Windows updates through the Windows Update Agent (2.6.0 / 2.6.3). |
| `Sources\SelfX_Tray.ps1` | Status icon in the notification area (started at sign-in through the HKLM Run entry `SelfXTray`, and right after the installation for signed-in users). |
| `Sources\Scripts_to_run\Collect-DeviceLogs.ps1`, `Sources\Scripts_to_run\SelfX_Device_CollectLogs.ps1`, `Sources\SupportReport.ps1` | Device logs: read-only collector, System wrapper and the GUI e-mail helper. |
| `Sources\HealthStatus.ps1`, `Sources\Health_Config.xml` | Service-side collector and administrator-controlled health settings. Optional scripts go in `Sources\HealthChecks`. |
| `Service\SelfXService.cs` | Source of the Windows service. It is compiled on the device during installation. |
| `Service\SelfXLauncher.cs` | Source of `SelfX.exe` (2.5.3), the starter without console window used by the shortcuts and the status icon autostart. Compiled on the device during installation. |
| `Service\SelfXSessionStarter.cs` | Used by `Install.ps1` (2.5.8, compiled in memory): starts the status icon right after the installation in the sessions of the signed-in users, with their normal rights. |
| `Sources\` | GUI (`Self_X.ps1`, plain WPF without additional assemblies), service client (`SelfXServiceClient.ps1`), branding and themes (`Branding.ps1`), languages (`Localization.ps1`, `Languages\`), catalogue, configuration and `Scripts_to_run`. |

## How it works

```text
User ──► Self_X.ps1 (user session)
            │  User action ──► powershell.exe -File Scripts_to_run\<script>.ps1   (user rights)
            │  System action
            ▼
         named pipe \\.\pipe\SelfX.Service  (local only)
            ▼
         SelfXService (LocalSystem) ──► checks catalogue ──► powershell.exe -File <script>.ps1 (SYSTEM)
```

The service accepts `PING` for availability, `HEALTH [<Id> [<base64 name>]]` for the fixed local status
collector (optionally one validated check), `STATUS` for the cached result of the background checks
(answers immediately, runs nothing) and `RUN <script>.ps1` for repairs. A repair is accepted only when:

- the script name is a plain file name with no path,
- the installed `Issues_List.xml` contains an action with that script and
  `<Context>System</Context>`,
- the file exists in `%ProgramFiles%\SelfX\Scripts_to_run`.

Users cannot send parameters, script content or paths. Only one System action
runs at a time, and other requests get a *busy* answer. Each action is stopped
after its `TimeoutSeconds`: the default is 900 and the maximum is 7200. The
service passes the SID of the requesting user (from the pipe client token) to
the script in `SELFX_CALLER_SID`, so a script can hand results only to that
user, for example the device logs report.

## Security model

- `%ProgramFiles%\SelfX` is writable only by SYSTEM and administrators, and
  users get read and execute rights. The scripts that run as SYSTEM therefore
  cannot be changed by users.
- The pipe denies network access, so only local, authenticated users can
  connect.
- All requests and script output are logged to
  `%ProgramData%\SelfX\Logs\SelfXService.log`, together with the requesting
  user; every script also writes its own log (2.6.0). Only SYSTEM and
  administrators can read the logs; users can read only their own folder under
  `Logs\Users`.
- Every System action can be started by any signed-in user. Add only scripts to
  the catalogue that are safe for everyone to run.
- The status cache of the background checks (`%ProgramData%\SelfX\Cache`) can
  be read only by SYSTEM and administrators; users and the tray icon get the
  validated result through the `STATUS` request of the pipe.
- Device logs reports are stored in `%ProgramData%\SelfX\Reports\<user SID>`.
  Only SYSTEM, administrators and that user can read them; they are replaced at
  the next run and deleted after 7 days. The report contains device, user and
  tenant names; it is sent only when the user sends the e-mail.

## Quick start

```powershell
# elevated, 64-bit Windows PowerShell 5.1
Set-Location 'C:\Path\To\SelfX Service'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

See [Installation](../docs/Installation.md#selfx-service),
[Configuration](../docs/Configuration.md#selfx-service) and the
[User manual](../docs/User-Manual.md#selfx-service).
