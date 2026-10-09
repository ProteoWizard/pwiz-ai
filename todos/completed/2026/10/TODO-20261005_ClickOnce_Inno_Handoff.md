# TODO-20261005_ClickOnce_Inno_Handoff.md

## Branch Information
- **Branch**: `Skyline/work/20261005_ClickOnce_Inno_Handoff`
- **Base**: `Skyline/skyline_26_1_1` (branched from master)
- **Created**: 2026-10-05
- **Status**: Completed
- **GitHub Issue**: (none)
- **Module**: `skyline`
- **PR**: [#4773](https://github.com/ProteoWizard/pwiz/pull/4773) (merged 2026-10-09 into `Skyline/skyline_26_1_1`)
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
- On accept (`AppDeploymentWrapper.InstallInnoVersion`, was InstallPublishedVersion): download
  `<ProductName>-Setup-<version>.exe` to %TEMP% with progress, then `InstallerHandoff.Record`:
  - saves the ClickOnce uninstall command (HKCU Uninstall entry whose UninstallString is a
    dfshim ShArpMaintain of `<assembly>.application`) as the `UninstallCommand` user setting;
  - writes `ConfigurationManager.OpenExeConfiguration(PerUserRoamingAndLocal).FilePath` to
    `HKCU\Software\MacCossLabUW\ImportSettingsFrom`, value named for the assembly
    (Skyline / Skyline-daily).
  Then runs the installer with `/SILENT /SUPPRESSMSGBOXES /NORESTART /CURRENTUSER /LAUNCH`
  (progress only, "for me", and the new Skyline launched) and calls `Application.Exit()`.
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
- [x] 2026-10-06 (0a65582e3c): installer runs with /SILENT /SUPPRESSMSGBOXES /NORESTART
      /CURRENTUSER /LAUNCH; /LAUNCH is #4755's Setup.iss switch (08fe79e1ab), and Inno ignores
      unknown switches, so an older installer still installs, just without launching
- [x] 2026-10-07 (3f1592c28b): re-stored the new InstallerHandoff.cs as CRLF for a Copilot
      thread. Against CRITICAL-RULES.md (stored endings stay as autocrlf leaves them); left in
      place since the file is new and the squash shows it as added either way. Not a precedent.
- [x] #4773 retargeted to `Skyline/skyline_26_1_1` and out of draft; description updated 2026-10-06
- [x] Tried end to end from a test folder (proteome.gs.washington.edu ...InstallTest/NewVersion):
      a ClickOnce Skyline-daily from this branch offered the published installer, ran it, and the
      new Skyline took its settings and removed it (interactive install; the silent /LAUNCH run
      is still to be repeated)
- [x] 2026-10-08 (f6e629c3fe): renamed GetPublishedInstallerVersion / InstallPublishedVersion to
      GetAvailableInnoInstallerVersion / InstallInnoVersion; documented IDeployment

### 2026-10-09 - Merged

PR #4773 merged into `Skyline/skyline_26_1_1` as 4d2c8c5493 (admin override, no approvals).
Every release-branch TeamCity build was marked failed by "Failed to load build settings from
VCS" (the release branch has no .teamcity settings; #4796 adds them), although the builds and
tests themselves passed apart from two long-muted msconvert Wine tests and a
TestDiaNnPeakImputation timeout that #4771 hit too. Shipped: the Inno manifest check before the
ClickOnce update, the handoff (UninstallCommand setting + HKCU ImportSettingsFrom value), and the
silent /LAUNCH install. Deferred: repeating the end-to-end run with the silent install, and
verifying release-branch CI once #4796 is in.
