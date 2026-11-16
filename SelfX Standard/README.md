# SelfX Standard

SelfX Standard is the per-user SelfX package. It installs the WPF interface and
its troubleshooting scripts under `%LOCALAPPDATA%\SelfX`, then optionally
creates Desktop and Start menu shortcuts. The interface has a
**Troubleshooting** tab with the action list and a **System information** tab
(`Sources\SystemInfo.ps1`) with read-only device details that users can copy or
export for the support team.

## Documentation

- [Installation](../docs/Installation.md#selfx-standard)
- [Configuration](../docs/Configuration.md#selfx-standard)
- [User manual](../docs/User-Manual.md#selfx-standard)

Run the installer in the `SelfX Standard` directory and in the intended user's
context. It is not a Windows service and should not be installed as SYSTEM when
it is expected to appear in an end user's profile.
