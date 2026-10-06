# TODO-20261005_ClickOnce_Inno_Handoff.md

## Branch Information
- **Branch**: `Skyline/work/20261005_ClickOnce_Inno_Handoff`
- **Base**: `master`
- **Created**: 2026-10-05
- **Status**: In Progress
- **GitHub Issue**: (none)
- **Module**: `skyline`
- **PR**: [#4773](https://github.com/ProteoWizard/pwiz/pull/4773) (draft; to be merged into the
  "Release 26.1.1" branch once it is created from master, not into master)
- **Checkout**: I:\git_i\sky_26_1_1

## Objective

The .NET Framework (ClickOnce) side of moving users to the .NET 10 Inno Setup installer. The
other side, which reads what this leaves, is PR #4755 (`Skyline/work/20260901_Net10ImportSettings`,
`ToolsUI/FirstLaunchImport.cs`; see TODO-20260901_Net10ImportSettings.md).

## Design (decided with Nick 2026-10-05)

- `UpgradeManager` checks the Inno manifest first: `<InstallUrl>/<ProductName>.json`
  (`{ "version": "..." }`), the same file the .NET 10 Skyline checks. If it names a version newer
  than the ClickOnce one, the usual UpgradeDlg offers it; otherwise (not published, unreadable,
  not newer) the ClickOnce update runs as before.
- `InstallUrl` and `ProductName` are application settings with the .NET 10 branch's values
  (`https://skyline.ms/_webdav/home/software/Skyline/daily/@files/`, Skyline-daily), so the
  manifest is `.../@files/Skyline-daily.json`.
- On accept (`AppDeploymentWrapper.InstallPublishedVersion`): download
  `<ProductName>-Setup-<version>.exe` to %TEMP% with progress, then `InstallerHandoff.Record`:
  - saves the ClickOnce uninstall command (HKCU Uninstall entry whose UninstallString is a
    dfshim ShArpMaintain of `<assembly>.application`) as the `UninstallCommand` user setting;
  - writes `ConfigurationManager.OpenExeConfiguration(PerUserRoamingAndLocal).FilePath` to
    `HKCU\Software\MacCossLabUW\ImportSettingsFrom`, value named for the assembly
    (Skyline / Skyline-daily).
  Then runs the installer with `/CURRENTUSER` (interactive, "for me" without asking; its finish
  page launches the new Skyline) and calls `Application.Exit()`.
- The key, value name and setting name must match `FirstLaunchImport` /
  `SettingsImporter.UNINSTALL_COMMAND_SETTING` on the .NET 10 side.

## Tests

- UpgradeToInstallerFunctionalTest (new): offered and installed instead of ClickOnce;
  InstallerHandoff.Record writes the setting and the registry value (test-only key).
- UpgradeBasic/Cancel/Errors FunctionalTest unchanged (TestDeployment publishes nothing).

## Progress

- [x] 2026-10-05 (93381d6b0b): built and tested on net472; Upgrade*FunctionalTest and
      CodeInspection pass, quick inspection clean
- [x] 2026-10-05: pushed, draft PR #4773 opened against master
- [ ] Retarget #4773 to the Release 26.1.1 branch once it exists
- [ ] Try against a real ClickOnce Skyline-daily once an installer and manifest are published
