# Configuration

SelfX uses XML files for its UI and action catalogues. The Standard and Admin
packages have different schemas; do not copy an issue list from one package to
the other. SelfX Service uses the Standard schema with two extra action
elements.

## SelfX Service

SelfX Service is configured with the same files as SelfX Standard, in
`SelfX Service\Sources`. Edit them in the package before installation. After
installation, the files in `%ProgramFiles%\SelfX` can be changed only by
administrators. Deploy changes by publishing a new package version. There is no
remote update and no download at launch.

### Action catalogue

`Issues_List.xml` uses the Standard structure (`XML_Version`, `Quick_Solution`,
`Detailed_Solution`, `Action`) with English base texts. SelfX Service adds:

- An `Id` attribute on every action, for example `<Action Id="D_Teams_SoundCuts">`.
  It must be unique. The language files use it to translate the action.
- An optional `Messages` section with texts shared by several actions.
  `Explanation` and `Alerte_MSG` can point to one of them with
  `Ref="<message Id>"` instead of their own text, for example
  `<Alerte_MSG Ref="Msg_Teams_Restart"/>`.
- `Category` contains a category Id (`Browser`, `Device`, `Intune`, `Office`,
  `OneDrive`, `Outlook`, `Teams`). The displayed name comes from the language
  file.

Each action has these additional elements:

| Element | Values | Purpose |
|---|---|---|
| `Context` | `User` or `System` | `User` runs the script as the signed-in user, as in SelfX Standard. `System` sends the script name to the SelfXService, which runs it as SYSTEM. If the element is missing or has another value, the action is treated as `User`. |
| `TimeoutSeconds` | 1–7200, default 900 | Only for `System` actions. The service stops the script and its child processes after this time and reports a timeout. |
| `Post_Action` | empty or `MailReport` | Optional, only for `System` actions. `MailReport`: after a successful run the GUI attaches the newest report of the user to a new support e-mail. See [Device logs for the support](#device-logs-for-the-support-selfx-service-240). |

Example:

```xml
<Action Id="D_Intune_RestartService">
	<Name>Restart Intune service</Name>
	<Buttons>Ok_Cancel</Buttons>
	<Explanation>You want to force a synchronization between your device and Intune.</Explanation>
	<Script>SelfX_Intune_RestartService.ps1</Script>
	<Context>System</Context>
	<TimeoutSeconds>300</TimeoutSeconds>
	<Category>Intune</Category>
	<Alerte_MSG>The Intune Management Extension service will be restarted.

Do you want to continue?</Alerte_MSG>
</Action>
```

Rules for `System` actions:

- `Script` must be a plain file name made of letters, digits, `_`, `-` and `.`,
  ending in `.ps1`. The file must be in `Scripts_to_run`. The service rejects
  all other names.
- The same script may appear in several actions, for example in the simplified
  and the detailed view. The first `System` entry for a script sets its
  `TimeoutSeconds`.
- The script runs non-interactively as SYSTEM: there is no user profile, no
  desktop and no prompts. Use non-interactive commands, return a meaningful
  exit code (`0` = success), and write diagnostic output to stdout or stderr.
  The output is logged.
- Any signed-in user can start any `System` action. Only add actions that are
  safe for every user.
- The service passes the SID of the requesting user in the environment
  variable `SELFX_CALLER_SID` (read from the pipe client token, SelfX Service
  2.4.0 and later). Use it only to deliver results to that user, never to
  decide whether an action is allowed.

When you add an action, give it a new `Id` and add its translations to the
language files (see [Languages](#languages)). Without a translation, the English
text from `Issues_List.xml` is shown.

The included `System` actions, adopted from SelfX Admin, are:

| Script | Purpose |
|---|---|
| `SelfX_Intune_RestartService.ps1` | Restart the Intune Management Extension service |
| `SelfX_Device_AirePlaneMode.ps1` | Restart all enabled physical network adapters |
| `SelfX_OneDrive_CHKDSK.ps1` | Schedule `chkdsk /r /f` of the system drive for the next restart |
| `SelfX_Device_CollectLogs.ps1` | Collect the device logs with `Collect-DeviceLogs.ps1` and open a support e-mail with the report (`Post_Action` `MailReport`) |

### UI settings

`Tool_Config.xml` contains only settings. All texts of the window are in the
language files (see [Languages](#languages)), so the text keys of SelfX Standard
(`Main_Title_Text`, `Subtitle_Text`, `SystemInfo_*_Text` and so on) are not used.
The keys `Link_Scripts` and the install toast keys are not used either.

| Key | Purpose |
|---|---|
| `Tool_Language` | Default language. `Auto` (default) uses the Windows display language of the user. A culture name such as `de`, `fr-CH` or `zh-Hans` sets the language. Users can choose another language in the settings unless `Show_Language_Setting` is `False`; see [Languages](#languages). |
| `Tool_Name` | Text in the title bar and the About dialog |
| `Shortcut_Desktop`, `Shortcut_StartMenu`, `Shortcut_Name` | Shortcuts for all users created by `Install.ps1` |
| `Show_Computer_Name_MainGUI`, `Show_Computer_Name_title_bar` | Show the computer name beside the title |
| `Default_Solution_Mode` | `Simplified` or `Detailed` |
| `Show_Reboot_Warning`, `Show_About_Button` | Show or hide the reboot reminder and the About button (i) |
| `Show_Theme_Button` | `True`: users can choose the appearance (Automatic as Windows, Dark or Light) in the settings dialog (gear) |
| `Show_Language_Setting` | `True` (default, 2.5.9): users can choose the language of SelfX in the settings dialog. `False` hides the choice and always uses `Tool_Language`; a language saved earlier by a user is then ignored. |
| `Show_Support_Button`, `Support_Hours`, `Support_Phone_number`, `Support_Mail`, `Support_Teams`, `Support_Website` | Help button (?) and the contacts of the help dialog, see [User interface](#user-interface-selfx-service-250). `Support_Mail` is also the recipient of the device logs e-mail. |
| `DeviceLogs_Days`, `DeviceLogs_Compress` | Device logs report: days of event log history (1–60, default 7) and `.zip` (`True`, default) or `.txt` attachment |
| `Log_Retention_Days` | Log files older than this number of days are deleted (1–3650, default 90, 2.6.0); see [Logging](#logging-and-log-housekeeping-selfx-service-260) |
| `Show_Status_Page` | `True` (default): show the Device status page |
| `Show_SystemInfo_Tab`, `Show_SystemInfo_Intune_Actions`, `SystemInfo_Internet_Test_Host`, `SystemInfo_Internet_Test_Port` | System information page and its tools |
| `Show_Tray_Icon`, `Tray_Notifications`, `Tray_Poll_Seconds` | Tray icon, see [Tray icon](#tray-icon-selfx-service-250) |

Increase `Tool_Version` for each release and set the same value in
`Detection.ps1`.

### User interface (SelfX Service 2.5.0)

The window is designed for users without technical knowledge. It can be
resized and maximized (minimum 640 × 480); below 900 pixels the navigation bar
shows only icons and the cards rearrange in one to three columns. Size,
position, theme, language and the tray icon choice are stored per user in
`HKCU\Software\SelfX`. Only one SelfX window runs per user: a second start
(shortcut or tray icon) brings the open window to the front.

- **Navigation bar** (left): *Troubleshooting*, *Device status* (with a counter
  of problems and warnings), *System information*, the company logo
  (`Brand_Logo`) at the top, **Send logs to support** and the state of the local
  service at the bottom.
- **Troubleshooting**: search field, category buttons, switch between the
  simplified and the detailed view (the info icon explains the difference) and
  one card per action with an info icon (explanation), a play button (run, with
  confirmation) and a shield for actions with administrator rights. While an
  action runs (2.6.1), its play button shows a rotating icon and *Running…* and
  is locked; it returns to normal as soon as the action has ended. System actions
  end when the service has answered; user actions are watched until their script
  process has ended, then the result (exit code 0 = success) is shown in the
  message bar and logged. The **Fix** button of a status card does the same while
  its repair runs.
- **Device status**: one card per check, problems first. The color and the
  label show OK, Pending (warning), Error or Unknown. **Fix** (wrench) runs the
  configured repair after confirmation; the arrow button checks only this
  status again; the arrow button at the top checks everything. **Fix all
  problems** (2.5.3) appears when at least one Error or Pending card has a
  repair; after one confirmation it runs each configured repair once (one per
  script, one after another through the service) and then checks everything
  again. If the service is unavailable or busy, the remaining repairs are
  skipped and reported. Times are collected as UTC (`{utc:...}` markers in
  health details) and shown in the current time zone of the user, also after
  an automatic time zone change during the OOBE. The status of
  the background checks of the service is shown immediately, see
  [Background checks](#background-checks-and-status-cache-selfx-service-250).
- **System information**: one card per section (device, Windows, user and
  management, network, report); double-click a line to copy its value. The last
  collected values are shown immediately from `%LOCALAPPDATA%\SelfX\SystemInfo.json`
  and updated in the background. Refresh, copy and export (TXT, HTML, CSV, JSON)
  are icon buttons; copy and export include the device status. The *Tools*
  (Intune sync, compliance check, Company Portal, Quick Assist, MDM logs, send
  logs) are tiles below the information.
- **Title bar**: help (?), settings (gear: language, theme, tray icon) and About (i).
- **Help dialog**: shows only the configured contacts: `Support_Hours`,
  `Support_Phone_number`, `Support_Mail` (button *Write e-mail*),
  `Support_Teams` (button *Start chat*: a user or shared mailbox address opens a
  Teams chat, a full `https://` Teams link is opened as is) and
  `Support_Website` (button *Open*, only `http://` or `https://`). Without any
  contact the dialog asks the user to contact the IT department.

Every icon button has a tooltip that explains what happens. Confirmations,
explanations and messages use dialogs in the same style; results of actions
and the reboot reminder appear in the message bar at the bottom.

### Background checks and status cache (SelfX Service 2.5.0)

The service runs all health checks regularly in the background and keeps the
result in `%ProgramData%\SelfX\Cache\Health.json` (readable by SYSTEM and
administrators only). SelfX and the tray icon read it with the request
`STATUS`, which answers immediately and runs nothing. Every check that SelfX
starts (all, or a single status) also updates the cache.

Settings in `Health_Config.xml`:

```xml
<Background Enabled="true" IntervalMinutes="15" PauseOnBattery="true" MaxCpuPercent="75" StartDelaySeconds="120" />
```

| Attribute | Default | Purpose |
|---|---|---|
| `Enabled` | `true` | `false` = no background checks; SelfX then checks when it is opened. |
| `IntervalMinutes` | `15` | 5–1440. Time between two background checks. |
| `PauseOnBattery` | `true` | No background check while the device runs on battery. SelfX shows the last result and the note that the checks are paused. |
| `MaxCpuPercent` | `75` | 10–100. A check is postponed (retry after 2 minutes) while the processor load is higher; `100` = no limit. |
| `StartDelaySeconds` | `120` | 0–3600. First check after the start of the service, so the sign-in is not slowed down. |

Missing or invalid values use the default. A background check is also
postponed while a repair is running. It runs PowerShell with below-normal
priority and the 240-second limit of the health collection; only a summary
line is written to `SelfXService.log`. Changes of the settings apply without a
restart of the service.

### Tray icon (SelfX Service 2.5.0)

`SelfX_Tray.ps1` shows a SelfX icon in the notification area with a colored
dot: green (OK), yellow (warning), red (problem) or gray (status not available
yet). The tooltip shows the number of problems and warnings. When a check
changes to Error, for example *Disk capacity*, a Windows notification is shown
once; clicking it opens the Device status page. On Windows 10 and 11 these
notifications are shown as Windows toast notifications (and kept in the
notification center). The right-click menu opens SelfX, the device status,
checks the status now, sends the logs to the support, switches the
notifications on or off (2.6.5) or hides the icon.

| Key in `Tool_Config.xml` | Default | Purpose |
|---|---|---|
| `Show_Tray_Icon` | `True` | `Install.ps1` creates the HKLM Run entry `SelfXTray`, so the icon starts at every sign-in for all users, and (as SYSTEM, since 2.5.8) starts it right away for the signed-in users. `False` removes the entry. |
| `Tray_Notifications` | `True` | Show a notification when a check changes to Error. Each user can switch the notifications off (2.6.5). `False` switches them off for all users and hides the user switch. |
| `Tray_Poll_Seconds` | `60` | 15–3600. How often the icon reads the cached status (no check is run). |

**Notifications per user (2.6.5):** each user decides whether Windows
notifications are shown in addition to the colored icon: switch *Show
notifications about problems* in SelfX > Settings, or *Show notifications* in
the menu of the icon. The choice is stored in `HKCU\Software\SelfX\TrayNotifications`
(1 = on, default; 0 = off) and applies at once without a restart of the icon.
While they are off, the icon still shows the problem (red dot, tooltip) and
problems are still remembered, so switching the notifications on again does not
announce problems that were already known. Answers to actions of the user
(*Check status now*, *Hide this icon*) are always shown.

SelfX Service has no notification after the installation: the
`Show_Install_Toast` setting exists only in SelfX Standard.

Each user can hide the icon (menu *Hide this icon* or SelfX > Settings) and
show it again in SelfX > Settings; the choice is stored in
`HKCU\Software\SelfX\TrayIcon`. The icon needs no administrator rights: it
only reads the status cache through the pipe of the service. Shortly after the
start it collects the system information of the user once in the background,
so SelfX shows it immediately. An installation or update through Intune/SCCM
(SYSTEM) closes the running icons and starts the new version right away in
the sessions of the signed-in users (2.5.8); users who switched the icon off
do not get it back. After an uninstall the icons are closed.
Opening SelfX also starts the icon when it is not running yet (for example
after a manual installation).

### Device logs for the support (SelfX Service 2.4.0)

The action **Send the device logs to the support** (`Q_Device_SendLogs` in the
simplified view, `D_Device_SendLogs` in the detailed view, category `Device`)
and the buttons **Send logs to support** (navigation bar, System information page and tray icon) collect
all logs that are needed to analyze a device problem and open a new e-mail to
the support with the report attached. The user describes the issue and sends
the e-mail; nothing is sent automatically.

How it works:

1. The user confirms the action. The GUI sends `RUN SelfX_Device_CollectLogs.ps1`
   to the local service (shield action, timeout 1800 seconds).
2. The service runs the wrapper as SYSTEM and passes the SID of the requesting
   user in `SELFX_CALLER_SID`. The wrapper starts the read-only collector
   `Scripts_to_run\Collect-DeviceLogs.ps1` with administrator rights. It writes
   one report to `%ProgramData%\SelfX\Reports\<user SID>\DeviceLogs-<computer>-<time>.txt`
   and compresses it to a `.zip` file (unless `DeviceLogs_Compress` is `False`).
3. The report folder of the user has a protected ACL: SYSTEM and
   Administrators have full control, only the requesting user can read. No
   other user can read the report. The previous report of the user is deleted
   at each run; reports older than 7 days are deleted for all users.
4. After a successful run the GUI copies the report to
   `%LOCALAPPDATA%\SelfX\Reports` and opens a new e-mail with the copy attached:
   - classic Outlook through COM: recipient `Support_Mail`, localized subject
     (`Report_Mail_Subject`) and text (`Report_Mail_Body`) are filled in;
   - otherwise `outlook.exe /a <file>` (the user enters the recipient);
   - otherwise (for example new Outlook, which has no COM interface) the
     default mail app through `mailto:` and an Explorer window with the file
     selected, so the user can attach it.

The collector only reads the device: it changes nothing, loads no hive, starts
no installation and sends nothing. The report contains the computer name, user
and tenant names and log content of the device (Autopilot/ESP state, IME and
Win32 app logs, servicing logs, event logs, AppX, Windows Update, network and
language state). It runs in about one to a few minutes. The section list and
the parameters are described in the header of `Collect-DeviceLogs.ps1`; replace
the file to update the collector.

**SelfX logs in the report (2.6.4):** the wrapper adds the logs of SelfX itself
(see [Logging](#logging-and-log-housekeeping-selfx-service-260)):

- from `%ProgramData%\SelfX\Logs`: `SelfXService.log`, `Install.log` and
  `Uninstall.log` always, all other `*.log` files (scripts, health checks,
  detection) of the last `DeviceLogs_Days` days;
- from `%ProgramData%\SelfX\Logs\Users\<SID>`: the logs of the **requesting
  user** (window, status icon, user actions) of the last `DeviceLogs_Days` days.
  Logs of other users are never added.

In the `.zip` they are separate files in the folder `SelfX-Logs` (`SelfX-Logs\User`
for the user logs); in a `.txt` report they are appended as the last section.
At most the last 2 MB of each file and 30 MB in total are added. Users can
create their own folder under `Logs\Users`, so the wrapper (running as SYSTEM)
reads there only from a normal folder (no junction) and only files owned by the
user; no protected file of another account can get into the report. Note that
`SelfXService.log` names the users who started actions on this device.

Exit codes of `SelfX_Device_CollectLogs.ps1`: `0` report created, `1`
collection or compression failed, `2` requesting user unknown (service older
than 2.4.0). The wrapper writes the collector summary and the report path to
`SelfXService.log` and (2.6.0) to its own log.

To use the feature with another report script, keep `Post_Action` `MailReport`
and write the report as `DeviceLogs-*.zip` or `DeviceLogs-*.txt` to
`%ProgramData%\SelfX\Reports\<SELFX_CALLER_SID>` with the same ACL. Remove both
catalogue actions to hide the feature; the System information button is shown
only when a `System` action with `MailReport` exists.

### Logging and log housekeeping (SelfX Service 2.6.0)

All SelfX Service scripts log to `%ProgramData%\SelfX\Logs` through the shared
module `Sources\SelfXLog.ps1`: the window, the status icon, the health checks,
the compliance check, the detection script and every action and repair script.
One file per script and day, `<Script>_<yyyy-MM-dd>.log`, UTF-8 with BOM, one line
per entry in the local time of the device:

```text
2026-11-06 13:29:56.522 | Info    |  52068 | SelfX 2.6.0 opened: language de (setting de), page ''.
2026-11-06 13:30:04.426 | Warning |  52068 | Message (Warning): Windows restarts in about 30 seconds. ...
```

| Folder | Content | Readable by |
|---|---|---|
| `Logs` | Scripts that run as SYSTEM (repairs and System actions started through the service, `HealthStatus`, `Check-Compliance`, `Detection`), `SelfXService.log`, `Install.log`, `Uninstall.log` | SYSTEM and administrators |
| `Logs\Users\<SID>` | Scripts of the user: the window (`SelfX_*`), the status icon (`SelfX_Tray_*`) and the user actions | The user, SYSTEM and administrators |

The window logs its start, every action with the answer of the user, the result
of every service action (status and exit code), the status checks started by the
user, the language changes and **every message shown to the user**. The status
icon logs status changes, notifications and why it stops. Each action script logs
its steps and its result; unexpected errors are logged before the script ends.
`HealthStatus` logs every check result of the background checks (one line per
check every 15 minutes).

`Install.ps1` creates `Logs\Users` so that users can only create their own
folder (CREATOR OWNER = full control on it) and cannot list or read the folders
of other users. A folder that is a link or belongs to another account is never
used. Without that folder (installations before 2.6.0, or when it cannot be
used) the user logs go to `%LOCALAPPDATA%\SelfX\Logs`.

**Housekeeping:** log files older than `Log_Retention_Days` in `Tool_Config.xml`
(1–3650, default **90**) are deleted:

- The SelfX service deletes old `*.log` and `*.old` files in `Logs` once a day
  (first time after the start delay of the background checks), also while the
  background checks are disabled, and logs the number of deleted files in
  `SelfXService.log`.
- Each user deletes the old files of the own `Logs\Users\<SID>` folder, at most
  once a day, when a SelfX script starts. The service never deletes inside
  `Logs\Users`: users can create folders there, and a deletion as SYSTEM must not
  follow a link that a user could create.

`Uninstall.ps1` keeps the logs; `-RemoveLogs` deletes `%ProgramData%\SelfX`.

### Health status (SelfX Service 2.3.0)

The Device status page (since 2.5.0; before in the System information tab)
shows the result of the local health checks of the service. It reads the
status cache of the background checks when SelfX opens and requests `HEALTH`
when the user checks again. It displays **OK** (green), **Pending** (yellow warning),
**Error** (red), or **Unknown** (gray). Pending means an outstanding action
(updates to install, device not compliant yet); it is a warning, not an error.
Unknown means missing data, an unsupported source, or an unavailable
service; it is not a successful check. Technical details remain in English;
labels and status words follow the UI language. Copy and all exports include
the results. Existing device, Windows, user/management, network and report
sections remain first; health status is appended below them in the same list.
The report is a snapshot, not continuous monitoring.

Configure `Sources\Health_Config.xml` before packaging. The installer copies it
alongside `HealthStatus.ps1`, with write access only for administrators/SYSTEM.
The client cannot supply a path or code to the service.

| Check | Interpretation |
|---|---|
| IME | `IntuneManagementExtension` must be running; missing or stopped is Error. |
| Defender | Service, antivirus and real-time protection must be enabled; signatures must not be reported outdated and must be at most 7 days old. Passive mode/third-party antivirus can therefore produce Error. A failed query is Unknown. The detail starts with the signature version and the time of the last signature update, followed by product and engine version. By default the row offers **Fix**, which runs `Update-MpSignature` (see [Health remediation](#health-remediation)). |
| Compliance | Intune evaluates compliance in the cloud; Windows stores no local compliance state, so SelfX cannot read the Company Portal status. Since 2.5.5 the package ships `HealthChecks\Check-Compliance.ps1`, enabled with `<Compliance Script="Check-Compliance.ps1" />`: it checks the local criteria of a typical Intune Windows compliance policy (Intune enrollment, BitLocker on the system drive, Secure Boot, TPM, firewall for all profiles, Defender antivirus/antispyware/real-time protection, up-to-date signatures, optional minimum OS version) and shows the criteria that are not met. Align `$Require` in the script with your compliance policy; the Company Portal stays authoritative. Exit `0` = OK, any other exit code = **Pending** (warning). Missing script, exception or timeout are Error. Without the `Compliance` element the row is Unknown. While the row is not OK, it offers **Fix** to update the Defender signatures, the most frequent cause after a longer absence. |
| Applications | Best-effort **local IME Win32 app reporting cache**, plus configured application probes. Known cached success (`1000`) is OK; failure states (`5000` through `5999`) are Error; other states are Unknown. Error takes precedence over Unknown, which takes precedence over OK. With no included results, the overall result is Unknown. |
| Disk | Every fixed logical disk: Error when used space is **at least 90% OR free space is below 20 GiB** (displayed as GB, PowerShell `1GB`). Exactly 20 GiB is sufficient only if usage is below 90%. Thresholds are configurable. |
| BitLocker | Every returned OS/fixed-data volume must be fully encrypted with protection On; suspended, unencrypted or partially encrypted volumes are Error. Unsupported/unreadable data is Unknown. No keys or recovery secrets are collected. |
| Pending reboot | Error when Windows reports a pending restart: the Component Based Servicing `RebootPending` key, the Windows Update `RebootRequired` key, or a pending computer rename. `PendingFileRenameOperations` is deliberately ignored because installers and security products often leave it set permanently. Unreadable registry data is Unknown. |
| Updates to install | Searches only the **local Windows Update Agent cache** (offline, no scan, download or installation). Any not-installed, not-hidden update (except browse-only/optional ones) is **Pending** (warning) and listed in the detail. An empty cache is OK only if the last successful Windows Update scan is at most `MaxSearchAgeDays` old (default 14); otherwise, or when the scan date is unknown, the result is Unknown. Updates deployed only through ConfigMgr are not part of this cache view. While the row is Pending, **Fix** installs the pending Windows updates and starts the Microsoft Store app updates as SYSTEM, without a restart (since 2.5.6, see [Health remediation](#health-remediation)). |
| Additional services | Exact service name and expected state (`Running` or `Stopped`). |
| Script checks | Exit `0` = OK; exit `1` = Error. Other exit codes, missing files, exceptions and timeouts are also Error. |

**Application limitations:** the IME registry cache is an implementation detail,
not a stable Microsoft API, installed-software inventory, or live Intune report.
It can be stale and can contain several user/device records for the same app.
All available included records are considered (a failed record is not discarded
because another record succeeded). Cache format changes or unreadable data
produce Unknown. A successful installation does not prove that the application
works. Use explicit probes for non-IME apps or functional checks; SelfX cannot
automatically diagnose every installed application.

```xml
<HealthConfig>
  <Disk UsedPercentError="90" MinimumFreeGB="20" />
  <Updates MaxSearchAgeDays="14" />
  <Applications>
    <Exclude Name="Test application*" />
    <Exclude Name="00000000-0000-0000-0000-000000000001" />
    <Application Id="00000000-0000-0000-0000-000000000002"
                 Name="Business client" />
    <Application Name="Business client"
                 Script="Check-BusinessClient.ps1" TimeoutSeconds="15" />
  </Applications>
  <Services>
    <Service Name="Spooler" Expected="Running" />
  </Services>
  <Compliance Script="Check-Compliance.ps1" TimeoutSeconds="30" />
  <CustomChecks>
    <Check Name="Local support data"
           Script="Check-SupportData.ps1" TimeoutSeconds="10" />
  </CustomChecks>
</HealthConfig>
```

Exclusions match names **case-insensitively with PowerShell wildcards**
(`*`, `?`, bracket expressions); app IDs can also be excluded. IME cache names
are used if available; otherwise SelfX takes the name from the app policies in
the IME logs (`AppWorkload.log`, since 2.6.0) and only then shows the app ID.
Supply an `Application Id="..." Name="..."` mapping when you need name-based
exclusions but no name is found. Excluded probes are not executed. Excluding all apps
does not manufacture an OK result. Since 2.6.0 the row is labelled **Company apps
(Intune)**; its detail names the apps that failed with their error code (for
example `Monitoring Agent (error 0x87D1041C)`), and apps that do not apply to the
device (EnforcementState 3000-3999, requirements not met) are not counted. The
app ID is read from the key `Win32Apps\<user>\<app id>_<revision>`; before 2.6.0
the user ID could be shown instead of the app.

Create `Sources\HealthChecks` and put extension `.ps1` files there. Only simple
filenames are accepted (no subdirectories, absolute paths or `..`); reparse
points in that folder or the script are rejected. The default package contains
only `Check-Compliance.ps1` (see the Compliance row above). Example read-only application probe:

```powershell
<#
.SYNOPSIS
    Check whether the installed business client executable is present.
.NOTES
    Version: 1.0.0
    History:
    1.0.0  2026-10-28  Your company  Initial presence check.
#>
$ErrorActionPreference = 'Stop'
try {
    if (Test-Path -LiteralPath 'C:\Program Files\BusinessClient\Client.exe' -PathType Leaf) {
        exit 0
    }
    exit 1
} catch { exit 1 }
```

**Security and runtime contract:** checks execute non-interactively as SYSTEM
on each refresh, without a confirmation prompt. They must be read-only,
idempotent and must never reboot, sign out, modify settings, prompt for input
or launch detached work. Review/sign them before deployment; arbitrary
administrator-supplied scripts cannot be proven read-only by SelfX. No
credentials should be stored in scripts. Exit codes define their status; the
last non-empty stdout line (at most 400 characters) is shown as detail text,
otherwise `Exit code: N`. stderr is drained but not included in the report.
Timeout is 1-30 seconds per script, default 30; at most 5 script checks total
(compliance, app probes and custom combined), and 16 additional services.
On timeout SelfX attempts to terminate that process tree. The entire service
request is capped at 240 seconds and 20,000 characters; oversize results are
rejected explicitly, not shown as OK. Repair actions and checks requested by
SelfX share a lock: a concurrent request returns Busy; retry after it finishes.
A check requested while a background check runs waits until it has finished.

Run the isolated tests before packaging:

```powershell
powershell.exe -NoProfile -File '.\SelfX Service\Test-HealthStatus.ps1'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\SelfX Service\Test-UI.ps1'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\SelfX Service\Test-Scripts.ps1'
```

Tests mock all system probes and script execution. They do not install a
service or execute real custom scripts. `Test-Scripts.ps1` (2.6.0) runs every
action and repair script in a temporary sandbox with mocked commands (no
process is closed, nothing is started or restarted) and checks its result and
its log; only the read-only scripts `Check-Compliance.ps1`, `Detection.ps1`
and `HealthStatus.ps1` run for real.

### Health remediation

Health checks remain read-only. To offer a user-triggered **Fix** button on a
status row, install a repair script under `Sources\Scripts_to_run` and add it
to `Health_Config.xml`:

```xml
<Remediations>
  <Remediation Id="IME" Script="SelfX_Intune_RestartService.ps1" />
  <Remediation Id="Service" Name="Spooler" Script="Repair-Spooler.ps1" />
  <Remediation Id="Disk" Name="C:" Script="Repair-Disk.ps1" />
  <Remediation Id="Custom" Name="Business check" Script="Repair-BusinessCheck.ps1" />
  <Remediation Id="Compliance" Script="SelfX_Defender_UpdateSignature.ps1" When="NotOK" />
</Remediations>
```

`Id` matches a result type (`IME`, `Defender`, `Compliance`, `Applications`,
`Disk`, `BitLocker`, `PendingReboot`, `Updates`, `Service`, `Custom`). Optional `Name` matches the exact
technical name, not the translated label. With no Name, the mapping applies
to every row of that type. Do not configure overlapping mappings for a row:
ambiguous mappings are reported as configuration errors. Optional
`When="NotOK"` offers the repair only while the row is not OK (Pending, Error
or Unknown); the default `Always` offers it on every status.

**Default remediation (2.3.4):** the package ships
`Scripts_to_run\SelfX_Defender_UpdateSignature.ps1`, which runs
`Update-MpSignature` as SYSTEM with the update sources defined by Defender
policy, and enables it in the default `Health_Config.xml`:

```xml
<Remediation Id="Defender" Script="SelfX_Defender_UpdateSignature.ps1" When="NotOK" />
<Remediation Id="Compliance" Script="SelfX_Defender_UpdateSignature.ps1" When="NotOK" />
```

Since 2.5.4 the Defender and Compliance rows show **Fix** only while they are
not OK, because outdated signatures after a longer absence
are a frequent cause of non-compliance. To offer the signature update on an OK
Defender row as well, remove `When="NotOK"` from the Defender line. The update needs a reachable update
source; offline it fails (exit 1) and the status stays unchanged. Remove the
two lines to disable this.

**Updates remediation (2.5.6, fixed in 2.6.3):** the package ships
`Scripts_to_run\SelfX_Updates_Install.ps1` and enables it in the default `Health_Config.xml`:

```xml
<Remediation Id="Updates" Script="SelfX_Updates_Install.ps1" When="NotOK" TimeoutSeconds="3600" />
```

While updates are pending, the **Updates to install** row offers **Fix**. While the installation
runs, the button shows **Running…** and the message bar says that the updates are being searched,
downloaded and installed; afterwards SelfX reports that Windows Update has finished and checks the
whole device status again (updates, restart pending, compliance). The script runs as SYSTEM and

1. starts the Microsoft Store app update scan of the MDM bridge
   (`MDM_EnterpriseModernAppManagement_AppManagement01.UpdateScanMethod`). This also works when the
   Store is blocked for users. The Store updates the apps asynchronously in the background.
2. installs the updates through the documented **Windows Update Agent API**: online search at the
   update source of the device policy (Intune update rings / Windows Update for Business, WSUS or
   Microsoft Update), EULAs accepted, download and quiet installation of every not-installed,
   not-hidden update. Optional (browse-only) updates and updates that need user input are skipped,
   the same selection as the status check. If Windows Update is installing right now, the script
   waits for it (at most 10 minutes). Every update is logged in
   `%ProgramData%\SelfX\Logs\SelfX_Updates_Install_<date>.log` with its title and result, for example
   `Installed: 2026-10 .NET Framework Security Update (restart required)`, and the summary names the
   KB numbers (`Windows Update: 2 of 2 update(s) installed (KB5127690, KB890830); restart required to
   complete`).

2.6.0 to 2.6.2 used `UsoClient.exe StartDownload` / `StartInstall`. Windows 11 24H2 rejects these
commands (exit code `-2147024809` / `0x80070057` in the log), so only a scan ran and nothing was
installed; a restart that was already pending was even reported as installed. 2.6.3 no longer uses
`UsoClient.exe`.

The script **never restarts** Windows. If an update needs a restart, the **Restart pending** row
shows it. Exit `0` = all selected updates installed (or nothing to install); exit `1` = search,
download or installation failed for at least one update (the failed KB numbers are in the log). A
Store scan that cannot be started (for example without the MDM bridge) is logged but does not fail
the repair. Remove the line to disable it.

**Restart remediation (2.6.0):** the **Restart pending** row offers **Restart now**:

```xml
<Remediation Id="PendingReboot" Script="SelfX_Device_Restart.ps1" When="NotOK" />
```

SelfX recognises this script and asks with its own warning: Windows restarts to complete the
pending updates and changes, the user should save the work and close all programs, the restart
begins about 30 seconds after the confirmation (**Restart now** / **Cancel**). After the
confirmation the service runs `shutdown.exe /r /t 30 /d p:4:1` as SYSTEM; Windows shows its restart
notification. The restart is **never** part of **Fix all problems**. Remove the line to hide the
button.

**App retry remediation (2.6.0):** the **Company apps (Intune)** row offers **Try again** while an app
installation failed:

```xml
<Remediation Id="Applications" Script="SelfX_Apps_RetryInstall.ps1" When="NotOK" TimeoutSeconds="300" />
```

The Intune Management Extension retries a failed Win32 app only after its retry schedule (by default
24 hours). `SelfX_Apps_RetryInstall.ps1` removes, for every app whose last result in the local IME
cache is an error, this cached result and the retry schedule entries (GRS) of the app, and restarts
the IntuneManagementExtension service. The IME then checks in with Intune and installs the app again
within a few minutes; the user sees the progress in the Company Portal. No app is uninstalled and
only the IME cache under `HKLM\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps` is changed.
When the installation fails again, the problem is in the app or its assignment; the user can send
the device logs to the support, and the support team sees the error code in Intune.

Optional `TimeoutSeconds` on a `Remediation` (since 2.5.6) sets the run time limit of the service
for this repair: a positive number, capped at 7200 seconds; the default is 900 seconds.

The **Fix** button is shown only on cards with a configured repair (including OK and
Unknown cards unless `When="NotOK"`). It is labelled **Beheben** in German and **Fix** in English;
the restart and the app retry use **Neu starten** / **Restart now** and **Erneut versuchen** /
**Try again**. Button and confirmation texts are included in all 24 UI languages. Every card also has a
**check again** button (arrows) that re-checks only that status
without confirmation and without running any repair (see
[Single-status recheck](#single-status-recheck)). Before 2.5.0 rows without a
repair showed a button labelled Ok, Pending or Error instead.
The user must confirm before execution. The local service validates the script
against the protected remediation allowlist (or existing System action
catalogue), then runs it as SYSTEM with the existing repair timeout and logging.
No arbitrary paths, command arguments or user-supplied scripts are accepted.
Remediation scripts do not need an additional troubleshooting catalogue entry.
Any local signed-in user can request these approved repairs, just like
existing System actions.

The window prevents a second repair while one is running. On completion,
including failure or timeout, it re-checks the repaired status only (rows of
the collection itself fall back to a full refresh). The action result stays in
the message bar; the fresh check result,
not the script exit code, determines the displayed health status. A repair
that returns 0 can therefore still leave a red status. If the check or service
is unavailable, the refreshed result is Unknown rather than fabricated OK.

### Single-status recheck

Since 2.3.2 the client can request one check with
`HEALTH <Id> [<base64 UTF-8 name>]`, for example `HEALTH Disk Qzo=` for drive
`C:`. The service accepts only the known Ids (`IME`, `Defender`, `Compliance`,
`Applications`, `Disk`, `BitLocker`, `PendingReboot`, `Updates`, `Service`, `Custom`) and a strictly
base64-encoded name; anything else is rejected. `HealthStatus.ps1` then runs
only that check from the protected `Health_Config.xml`: a name that is not
configured there is never probed and returns an Unknown row. The UI replaces
only the affected card and the service updates only these rows in the status
cache; all other information is kept. Rows of
type `Collection` (collector errors) trigger a full refresh instead.

Repairs must be suitable for execution without user interaction. Never use
sign-out, restart, shutdown, sleep or detached actions in these scripts. This
also applies to `PendingReboot`: the recheck only shows whether a restart is
still pending; the user restarts the device themselves.
Administrators must review, deploy and, where required, sign them. Since
2.3.4 only the Defender signature update (Defender always, Compliance when
not OK) is enabled by default.

### Branding

Company logo, icon and colors are set in the `Branding` section of
`Tool_Config.xml`. Copy the image files into `SelfX Service\Sources`, or into a
subfolder such as `Sources\Branding`, before you build the package. Paths are
relative to the install folder. All keys are optional; if a value is empty,
invalid or the file is missing, SelfX uses the default.

The delivered `Tool_Config.xml` contains placeholders (2.6.8): the logo
`Branding\company_logo.png` ("YOUR LOGO"), the blue of the SelfX logo
(`#0072BC`) and the support contacts `Mon-Fri 08:00-17:00`, `+1 555 0100`,
`support@example.com` and `https://support.example.com`. Replace them with the
values of your company before you build the package, or empty them to hide them.

| Key | Default | Purpose |
|---|---|---|
| `Brand_Logo` | empty (no logo) | Company logo at the top of the navigation bar and in the About dialog. PNG, JPG, BMP, GIF or ICO, at most 196 pixels wide in the navigation. A transparent PNG works best on both themes. If empty, the About dialog shows `About_Logo`. |
| `Brand_Logo_Height` | `40` | Height of the logo in the navigation bar, in pixels (16–120). The width is scaled to fit. |
| `Brand_Icon` | `Repair.ico` | Icon of the window, the taskbar and the tray icon. If it is an `.ico` file, `Install.ps1` also uses it for the shortcuts and the Apps & Features entry. Since 2.6.2 SelfX has its own taskbar button (AppUserModelID `SelfX.SelfService`) with this icon instead of the PowerShell icon; a SelfX pinned to the taskbar starts `SelfX.exe`. Use an `.ico` with 256 × 256 pixels for a sharp taskbar icon. |
| `Brand_Accent_Color` | empty (uses `Tool_Color`) | Company color as `#RRGGBB` for buttons, selections, the navigation marker, links and icons. The text color on the accent (white or black) is chosen automatically; a very dark or very light color is lightened or darkened for text and icons so it stays readable on both themes. |
| `Brand_TitleBar_Color` | window background | Title bar background as `#RRGGBB`, for example the corporate color. The text color is chosen automatically. |
| `Brand_Run_Button_Color` | accent color | Run (play) and **Fix** buttons. |
| `Brand_Info_Button_Color` | accent color | "More information" icons. |

Example:

```xml
<Brand_Logo>Branding\contoso.png</Brand_Logo>
<Brand_Logo_Height>48</Brand_Logo_Height>
<Brand_Icon>Branding\contoso.ico</Brand_Icon>
<Brand_Accent_Color>#E20074</Brand_Accent_Color>
<Brand_TitleBar_Color>#3A0021</Brand_TitleBar_Color>
<Brand_Run_Button_Color>#E20074</Brand_Run_Button_Color>
<Brand_Info_Button_Color>#6C6C6C</Brand_Info_Button_Color>
```

`Tool_Theme` (`Auto`, `Dark` or `Light`) selects the default theme; since 2.6.7
the default is `Auto` (also when the value is missing or unknown). Each user
can change it in the settings dialog (if `Show_Theme_Button` is `True`): *Automatic*,
*Dark* or *Light*. *Automatic* (`Auto`, 2.6.6) uses the app mode of Windows
(Settings > Personalization > Colors, `AppsUseLightTheme` in
`HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize`; light if
the value is missing) and follows a change while SelfX is open. The choice of
the user is stored in `HKCU\Software\SelfX\Theme` and wins over `Tool_Theme`;
users who chose *Dark* or *Light* before keep their choice. The
branding colors apply to both themes. `Tool_Color` accepts the former MahApps
color names (`Cyan`, `Teal`, `Blue` ...). Since 2.5.0 SelfX Service no longer
uses MahApps.Metro; no file is written for the colors and no network access
is used.

### Languages

By default the user interface follows the Windows display language of the
signed-in user. Users can choose another language themselves in SelfX >
Settings (gear). The texts are in `Sources\Languages\<culture>.xml`. Included languages:

| File | Language | File | Language | File | Language |
|---|---|---|---|---|---|
| `en.xml` | English (reference) | `pl.xml` | Polish | `hi.xml` | Hindi |
| `de.xml` | German | `ru.xml` | Russian | `bn.xml` | Bengali |
| `fr.xml` | French | `uk.xml` | Ukrainian | `zh-Hans.xml` | Chinese (Simplified) |
| `es.xml` | Spanish | `tr.xml` | Turkish | `zh-Hant.xml` | Chinese (Traditional) |
| `it.xml` | Italian | `ar.xml` | Arabic (right to left) | `ja.xml` | Japanese |
| `pt.xml` | Portuguese | `fa.xml` | Persian (right to left) | `ko.xml` | Korean |
| `nl.xml` | Dutch | `ur.xml` | Urdu (right to left) | `vi.xml` | Vietnamese |
| `id.xml` | Indonesian | `th.xml` | Thai | `sw.xml` | Swahili |

English is the reference; the other files were machine translated. Have them
reviewed by native speakers before a rollout.

How the language is selected (`Localization.ps1`):

1. The language chosen by the user (2.5.9). The settings dialog lists
   **Automatic (<language>)** and every language file, each by its own name,
   for example *Deutsch*, *français*, *日本語*. The choice is stored per user
   in `HKCU\Software\SelfX\Language`. *Automatic* stores `Auto`, which
   means "use step 2". After a change, SelfX restarts on the same page in the
   new language, and the status icon follows. If a repair is still running,
   the new language is used the next time SelfX is opened. The choice is
   ignored when `Show_Language_Setting` is `False`, when the value is not a
   culture name, or when its language file no longer exists.
2. `Tool_Language` in `Tool_Config.xml`: `Auto` uses the Windows display
   language, any other value is used as the culture name.
3. The culture and its parent cultures are tried in order. For example
   `de-CH` uses `de.xml`, `pt-BR` uses `pt.xml`, `zh-CN` uses `zh-Hans.xml` and
   `zh-TW` uses `zh-Hant.xml`. Swiss German (`gsw`, including `gsw-CH`)
   also uses `de.xml` when no Swiss German language file is available.
4. If no file matches, `en.xml` is used.

Each text is looked up in the selected language first and then in English, so a
missing entry never leaves an empty label. Catalogue texts fall back to the
English base text in `Issues_List.xml`.

A language file has four parts:

| Section | Content |
|---|---|
| `UI` | Texts of the main window, dialogs, tooltips, message bar, Device status and System information pages and the tray icon. `{0}`, `{1}` are placeholders, for example the action name. |
| `SystemInfo` | Labels and values of the System information page and the status checks |
| `Catalog/Categories` | Display names of the category Ids |
| `Catalog/Messages`, `Catalog/Actions` | Translations of the shared messages and of `Name`, `Explanation` and `Alerte_MSG` per action `Id`. Fields that use `Ref` take the translated message. |

To add a language:

1. Copy `en.xml` (or a complete translation such as `de.xml`) to
   `<culture>.xml`. Use the neutral culture name, for example `cs.xml` for
   Czech, so that all regional variants use it.
2. Set `Culture`, `Name` and `NativeName` on the root element. Set
   `FlowDirection="RightToLeft"` for right-to-left scripts.
3. Translate the texts. Keep the element names, Ids and placeholders. Keep the
   `|*.txt|` pattern in `SystemInfo_Export_Filter`.
4. Check the file, then build the package:

   ```powershell
   & '.\SelfX Service\Test-LanguageFiles.ps1' -Culture cs
   ```

   The check reports missing or unknown keys, broken placeholders and
   catalogue entries that do not exist. Run it without `-Culture` to check all
   files.

No code change is needed. To change a text for your company, for example the
main title, edit it in the language files.

## SelfX Standard

### UI settings

Edit `SelfX Standard\Sources\Tool_Config.xml` before installation. It controls
the application name, shortcut name and locations, theme, colors, labels,
support details, optional install toast, default solution view, and reboot
warning. `Install.ps1` copies the contents of `Sources` to the current user's
`%LOCALAPPDATA%\SelfX`.

### System information tab

The System information tab is configured in `Tool_Config.xml`. All keys are
optional; when a key is missing, SelfX uses the English default shown below.

| Key | Default | Purpose |
|---|---|---|
| `Show_SystemInfo_Tab` | `True` | Show or hide the tab |
| `Troubleshooting_Tab_Text` | `Troubleshooting` | Header of the actions tab |
| `SystemInfo_Tab_Text` | `System information` | Header of the tab |
| `SystemInfo_Title_Text` | `Information about your device` | Title inside the tab |
| `SystemInfo_Hint_Text`, `SystemInfo_Loading_Text`, `SystemInfo_Copied_Text` | English texts | Status line texts |
| `SystemInfo_Refresh_Text`, `SystemInfo_Copy_Text`, `SystemInfo_Export_Text` | `Refresh`, `Copy all`, `Export` | Button labels |
| `SystemInfo_Internet_Test_Host` | `www.msftconnecttest.com` | Host for the "Internet reachable" TCP check |
| `SystemInfo_Internet_Test_Port` | `80` | Port for the "Internet reachable" TCP check |
| `Show_SystemInfo_Intune_Actions` | `True` | Show or hide the Intune and support buttons |
| `SystemInfo_SyncApps_Text`, `SystemInfo_SyncCompliance_Text`, `SystemInfo_CompanyPortal_Text`, `SystemInfo_QuickAssist_Text`, `SystemInfo_MdmDiagnostics_Text` | English labels | Labels of the Intune and support buttons |

The information is collected by `Sources\SystemInfo.ps1` in a background
runspace when the tab is first opened. The collector only reads CIM/WMI classes,
registry values, `dsregcmd /status`, `whoami /upn` and `netsh wlan show
interfaces`, and opens one TCP connection for the Internet check. To change the
collected data, edit `Get-SelfXSystemInfo` in that file; each entry is a
`Category`, `Property` and `Value` object, and entries are grouped by category in
the tab. The Intune buttons use the `intunemanagementextension://` protocol, the
Company Portal app, Quick Assist and `MdmDiagnosticsTool.exe`; hide them with
`Show_SystemInfo_Intune_Actions` if these are not used in your organization.

### Action catalogue

Edit `SelfX Standard\Sources\Issues_List.xml`. The file contains:

- `XML_Version` at the `Actions` root.
- `Quick_Solution` and `Detailed_Solution` groups.
- Each `Action`'s `Name`, `Buttons`, `Explanation`, `Script`, `Category` and
  `Alerte_MSG`.

The `Script` value must match a file in
`SelfX Standard\Sources\Scripts_to_run`. The interface starts the selected
script from the installed `Scripts_to_run` directory. Keep user-facing
confirmation text aligned with the actual script behavior, including any
possibility of unsaved work or data loss.

### Remote updates

When `Install.ps1` receives `XML_Link`, it writes a download-mode
`List_config.xml` and downloads the issue list and script archive. At launch,
SelfX compares the installed `Actions.XML_Version` with the remote
`Actions.XML_Version`. When the versions differ, it downloads the archive
referenced by `Actions.GUI_Config.Link_Scripts` in the remote issue list and
updates the local catalogue and scripts.

Ensure that the remote issue list's `GUI_Config.Link_Scripts` value points to
the current ZIP archive. The installer parameter `ZIP_Link` is used for the
initial package download; subsequent update runs use the URL in the XML.

Use monotonically changing version values when publishing updates. The current
mechanism downloads and expands remote XML/ZIP content without a package
signature check. Protect the hosting location and use HTTPS; only publish
content you intend clients to execute.

## SelfX Admin

### Runtime configuration

`SelfX Admin\List_config.xml` selects manual or download mode. The supplied
configuration uses manual mode and the app uses the bundled `Issues_List.xml`.
For Admin, deploy catalogue or script changes by publishing an updated package;
the existing download-mode code writes into the user's `%LOCALAPPDATA%\SelfX`
directory and is not a supported package-update path for this separately
launched Admin folder.

The Admin action list uses a different schema:

- UI settings and version values are inside `Actions.GUI_Config`.
- Action entries are direct children of `Actions`.
- Each action uses `Name`, `Buttons`, `Explanation`, `Script`, `Category` and
  `Alerte_MSG`.

The `Script` value must match a file under
`SelfX Admin\Scripts_to_run`. The action list's `GUI_Config.Link_Scripts` value is used by the legacy
download-mode code, but package replacement is the supported Admin update
method described above.

### Execution context

Admin actions inherit the token of the PowerShell process started by
`Run_SelX.ps1`. The package does not create a service, scheduled task or
independent privilege mechanism. Confirm deployment context separately from
the XML configuration.

## Editing and publishing safely

1. Back up the current XML and scripts.
2. Validate that the XML remains well-formed.
3. Confirm each referenced script exists in the corresponding package.
4. Test action behavior and user confirmation text on a test device.
5. For remote updates, publish the XML and ZIP from a trusted HTTPS location
   and update the XML version.
