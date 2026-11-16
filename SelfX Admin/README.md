# SelfX Admin

SelfX Admin is a separately launched SelfX interface for actions that may need
an administrative execution context. It does not install a Windows service.
`Run_SelX.ps1` invokes PowerShell through `ServiceUI.exe` to display the
interface in the signed-in user's session.

## Documentation

- [Installation and launch](../docs/Installation.md#selfx-admin)
- [Configuration](../docs/Configuration.md#selfx-admin)
- [User manual](../docs/User-Manual.md#selfx-admin)

The action scripts inherit the security token of the process that launches
SelfX. `ServiceUI.exe` does not elevate the process. When deploying from
Intune/SCCM, verify the deployment context and test actions on non-production
devices first.
