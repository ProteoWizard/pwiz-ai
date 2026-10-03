# TODO-20260901_Net10ImportSettings.md

## Branch Information
- **Branch**: `Skyline/work/20260901_Net10ImportSettings`
- **Base**: `Skyline/work/20260612_net8_port`
- **Created**: 2026-09-01
- **Status**: In Progress
- **GitHub Issue**: (none)
- **Module**: `skyline`
- **PR**: [#4755](https://github.com/ProteoWizard/pwiz/pull/4755)

## Objective

Skyline is moving from ClickOnce to Inno Setup installs on .NET 10. This branch covers three
things that move needs:

1. **Checking for upgrades** against a published `<ProductName>.json` version manifest.
2. **Importing settings from older versions**, both the ClickOnce .NET Framework Skylines and
   earlier installer builds.
3. **External tools in an All Users install.** Older Skylines had a long-standing problem with
   the "Administrator Install": only an administrator could install external tools, but ordinary
   users never saw the menu items for those tools, because each user had their own user.config
   and the tool list lived there.

## Design

### Settings location (`Util/UserConfigSettingsProvider.cs`)

- user.config lives beside the exe only when the current user OWNS the install folder (owner
  SID is the user, or an enabled group such as an elevated admin's Administrators). Ownership,
  not writability, is the rule (Nick's call): a non-admin given write access to Program Files
  still gets a personal file.
- Everyone else gets a personal user.config and Tools folder under
  `%LOCALAPPDATA%\ProteoWizard\<install folder leaf>`.
- For a non-owned install, the user.config beside the exe is the administrator's shared file.
  `ImportedSettingsUpdater.ForSharedSettings()` three-way merges it into the personal one at
  startup (base = `shared.base.user.config`). That is how admin-installed tools reach ordinary
  users. The first run merges against a missing base rather than copying, so InstallationId and
  ImportedSettingsPath are never taken over.
- `ToolDescriptionHelpers.GetToolsDirectory` follows the settings folder.

### Three-way merge (`Properties/Settings.cs`, `Util/Xml.cs`)

- `Settings.MergeChanges` works per user-scoped setting: a setting changed only in the source
  takes the source's value, and one also changed locally keeps the local value.
- `XmlMappedList.MergeChanges` merges settings lists item by item on their key, comparing items
  by their WriteXml output (ToolDescription has no `Equals(object)` override). Enzyme keys are
  `ToString()` including cleavage, so do not use enzymes to test keyed merges.
- The base copy is refreshed after each merge.

### Import Settings (`ToolsUI/ImportSettingsDlg.cs`, `Util/SettingsImporter.cs`)

- Options > Import Settings lists other Skylines (`SkylineInstallations`: both products, both
  ClickOnce via `ClickOnceInstallations` and installer via `RegisteredInstallations`).
- `SettingsImporter` saves and backs up user.config before replacing it, and `RevertImport`
  restores it on cancel or failure. `CopyTools` returns false when canceled, and then
  FinishImport (and the uninstall) never runs.
- "Keep these settings up to date" records the source; `ImportedSettingsUpdater` merges its
  changes at startup.
- ClickOnce settings folders are matched to installations by file version. Two `*.exe_*`
  folders holding user.config for the same version (a dev build stamped with a shipped version)
  would be ambiguous; accepted as not worth handling.

### Update check (`Util/UpdateChecker.cs`, `UpgradeManager.cs`, `Alerts/UpgradeDlg.cs`)

- `Settings.InstallUrl` is a FOLDER URL and `Settings.ProductName` names the product (empty =
  the channel, Skyline or Skyline-daily). Both are application-scoped, and app.config is the one
  place they are set, so every build has them.
- The folder holds `<ProductName>.json` (`{ "version": "..." }`), `<ProductName>-Setup-<version>.exe`,
  a portable `<ProductName>-<version>.zip`, and `<ProductName>.html` (from `DownloadPage.html`).
  File names are escaped as one URI path segment.
- UpgradeDlg's Download opens the versioned installer URL in the browser. There is no silent
  install on this branch. The sibling checkout sky_netinstaller
  (TODO-20260903_Net10Installer) has a silent-install variant; do not merge the two blindly.
- The startup check runs only when the exe folder is a registered Inno install, so dev builds
  and tests never hit the network. Help > Check for Updates always works.

### Installer (`Executables/Installer/Setup.iss`, `build.ps1`)

- build.ps1 reads ProductName and InstallUrl from the staged `<Product>.dll.config` and passes
  `/DProductName` to ISCC, so the manifest and installer names agree with the app by
  construction.
- A non-channel product gets its own AppId and `{autopf}\<name>` folder. ProgIds are always the
  channel's (Skyline / SkylineDaily), whatever the product is called (Nick's call).
- A `{` in a product name breaks ISCC (it starts an Inno constant). Accepted: we pick the
  names, and the failure can only happen at build time.

## Planned: automatic upgrade from .NET Framework Skyline (not written yet)

- The old .NET Framework Skyline (or Skyline-daily) downloads the installer, records a handoff
  (maybe in the registry) saying where it is installed, then runs the installer.
- The new Skyline sees that it was launched by the old one, imports the old Skyline's settings
  automatically, and uninstalls the old Skyline without asking.
- The Import Settings dialog is only for the unusual case, such as a user who downloaded the
  installer directly from the website. Then we ask where to import settings from.
- Suggestion: have the handoff record the old Skyline's exact user.config path
  (`ConfigurationManager.OpenExeConfiguration(ConfigurationUserLevel.PerUserRoamingAndLocal).FilePath`),
  not just its install folder. The new Skyline then imports from a known file, and the
  version-matching guess in `Program.MigrateSettingsFromClickOnceInstallation` (which today
  picks a ClickOnce installation on first run without asking) becomes only a fallback.

## Tests

- Unit: TestUserConfigSettingsProvider, TestSettingsListMerge, TestClickOnceInstallations,
  TestRegisteredInstallations
- Functional: TestImportSettings, TestManagingSearchTools, Upgrade*FunctionalTest,
  TestInstallTools, TestConfigureToolsDlg, TestToolStore

## Progress

- [x] UserConfigSettingsProvider, ClickOnceInstallations, Import Settings dialog
- [x] Startup update check against the JSON manifest; InstallUrl as a folder plus ProductName
- [x] Installer: channel ProgIds, any file name characters in the product name, portable zip,
      download page
- [x] Copilot review (f5d12e6): cancel reverts the import, three-way merge implemented,
      ownership rule for per-machine installs, URL escaping, stale ja/zh-Hans UpgradeDlg text
      removed. All 8 threads resolved (the `{` and ClickOnce same-version threads were declined).
- [x] 2026-10-02: merged `Skyline/work/20260612_net8_port` (f1f1a0e96f). The two conflicts were
      line endings only; the base branch keeps those files CRLF in the index, so they were
      re-staged with autocrlf off.
- [ ] Verify in a real per-machine install with a standard user
- [ ] PR test plan: build.ps1 output, download page links, Import Settings from an installed
      Skyline, startup update check finds a newer version
- [ ] Automatic upgrade handoff from .NET Framework Skyline (above), probably a separate branch
