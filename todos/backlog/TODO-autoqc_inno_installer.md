# TODO-autoqc_inno_installer.md

## Branch Information
- **Branch**: (not created) one `Skyline/work/YYYYMMDD_autoqc_inno_*` branch per PR below
- **Base**: `master` (.NET 10). PR 4 targets `Skyline/skyline_26_1_1`
- **Created**: 2026-10-05, plan rewritten 2026-10-31
- **Status**: Backlog
- **Module**: `skyline`
- **PR**: (pending)

## Objective

Ship AutoQC Loader on .NET 10 with an Inno Setup installer in place of ClickOnce, as #4755 does for Skyline.

Existing users do not need it to keep working. The ClickOnce AutoQC 26.1.1 finds an Inno Setup Skyline (#4771), and
stops a configuration with a restart message when its Skyline is uninstalled (#4939).

## Decisions (2026-10-31)

- **Per-user install only**, to `%LOCALAPPDATA%\Programs\AutoQC`, with no administrator prompt. AutoQC runs under the
  user's account, AutoQCStarter is a per-user startup item, and the Panorama password is encrypted for one Windows
  user
- **One product, `AutoQC`.** No AutoQC-daily. The installer is `AutoQC-Setup-<version>.exe` and the manifest
  `AutoQC.json`. A test build is pointed at a test folder by editing `InstallUrl` in `AutoQC.dll.config`
- **Published to a new folder on skyline.ms**, apart from the ClickOnce AutoQC files. The folder is agreed with
  Brendan and becomes the `InstallUrl` default
- **Copy `UpdateChecker` into AutoQC.** Ask Nick whether `ClickOnceInstallations`, `SettingsImporter` and
  `ClickOnceMaintenanceDialog` should move to a shared library before PR 3. Copy them only if not
- **Updates are a notice with a download link**, as Skyline's `UpdateChecker` does. AutoQC does not download or run
  the installer. The notice does not block AutoQC, which usually runs unattended
- **The .NET 10 AutoQC imports the ClickOnce AutoQC's configurations on first start**, then offers to uninstall it.
  No export and import by hand
- **The last ClickOnce AutoQC shows a notice** when `AutoQC.json` names a newer version. No handoff like #4773, where
  a prompt on an unattended instrument computer would leave QC stopped until someone answers it

## Plan

### PR 1 (`master`). The installer

- `AutoQC/Installer/Setup.iss` and `build.ps1`, modeled on Skyline's in `Executables/Installer/`, with AutoQC's own
  AppId
- Installs AutoQC and AutoQCStarter, a Start menu shortcut, the `.qcfg` file association, and `InstallDir` under
  `HKCU\Software\MacCossLabUW\AutoQC`. The association moves from `Program.AddFileTypesToRegistry`, which registers
  nothing without `AutoQC.appref-ms`
- Closes a running AutoQC and AutoQCStarter, from a ClickOnce or an earlier Inno Setup install, before copying files.
  AutoQCStarter restarts AutoQC when `KeepAutoQcRunning` is set
- `build.ps1` reads `InstallUrl` and `ProductName` from AutoQC's `App.config`, writes `AutoQC.json` and names the
  installer
- Does not detect or import ClickOnce settings. That is AutoQC's job (PR 3), where tests cover it
- Check that a double-clicked `.qcfg` reaches AutoQC through `Program.GetFirstArg`

### PR 2 (`master`). Update notice and AutoQCStarter

- At startup, the copied `UpdateChecker` reads `AutoQC.json`. A newer version shows a message in the main window
  with a link to the installer. No message when the manifest is missing, unreadable or not newer
- AutoQCStarter finds the installed AutoQC instead of `AutoQC.appref-ms` (`AutoQCStarter/Program.cs:151`)
- `StartupManager` points `AutoQCStarter.lnk` at the installed AutoQCStarter. `UpdateAutoQcStarter` runs only when
  `IsNetworkDeployed`, which is fixed at `false` on `master`
- Check what happens to running configurations when the installer closes AutoQC for an update, and whether they
  start again

### PR 3 (`master`). Import from the ClickOnce AutoQC

- On first start, find the ClickOnce AutoQC's `user.config` in the ClickOnce data folder (layout below), ask once,
  and import the configurations and the two checkboxes
- First check that the ClickOnce AutoQC is not running. Two AutoQCs would run the same configurations and upload
  twice
- Then offer to uninstall it through its Programs and Features uninstall command. `ClickOnceMaintenanceDialog`
  answers the ClickOnce dialog with Remove
- Rewrite `AutoQCStarter.lnk`, which points at `AutoQCStarter.exe` inside the removed ClickOnce install
- Check that the .NET 10 AutoQC reads the .NET Framework `user.config` as is, as Skyline's does. Not verified
- Check how Nick's `ClickOnceInstallations` picks among a ClickOnce app's version folders before reusing it

### PR 4 (`Skyline/skyline_26_1_1`). Notice in the last ClickOnce AutoQC

- At startup, read `AutoQC.json` from the new folder. A newer version shows a message that does not block AutoQC,
  with a link to the installer. No message when the manifest is missing, unreadable or not newer
- Ship it before the installer is published. A ClickOnce AutoQC takes an update only when it restarts, so an early
  release reaches more users by the time the manifest appears

## What AutoQC's user.config holds

AutoQC (`AutoQC/Properties/Settings.cs`) and SharedBatch (`SharedBatch/Properties/Settings.cs`)

- `ConfigList` - the configurations, with each one's enabled state. The Panorama password is encrypted with
  `ProtectedData` for the current Windows user (`PanoramaSettings.EncryptPassword`)
- `KeepAutoQcRunning`, `MinimizeToSystemTray` - two checkboxes
- Skyline paths (`SkylineRunnerPath`, `SkylineAdminCmdPath`, `SkylineCustomCmdPath` and others) - found again at
  startup, except a custom Skyline folder
- `InstallationId`, `RDir` - nothing in AutoQC or SharedBatch reads them
- `SettingsUpgradeRequired`, `InstalledVersion` - ClickOnce upgrade bookkeeping

Configurations imported with the Import button arrive disabled (`MainForm.btnImport_Click` passes
`setConfigsDisabled`). PR 3 decides whether the first-start import keeps each one's enabled state.

## Where a ClickOnce app keeps user.config

```
%LOCALAPPDATA%\Apps\2.0\Data\<random>\<random>\<name>_<key token>_<major.minor in hex>_<hash>\Data\<version>\user.config
```

- `<name>` is the deployment name shortened by ClickOnce. `auto..tion` is `autoqc.application`. `0018.0001` is 24.1
- The two random names differ on each machine. `Apps\2.0\Data` holds one folder at each of those levels
- Each installed version has its own `<name>_..._<hash>` folder. ClickOnce keeps the current and the previous version,
  and an update copies the previous folder forward, so a folder holds stale copies of older versions'
  `Data\<version>\user.config`. Take the folder of the version that Programs and Features lists (`DisplayVersion` in
  the `HKCU\...\Uninstall` entry), and in it `Data\<version>`
- An `.exe` started directly from a folder, such as a Visual Studio build, keeps its settings in
  `%LOCALAPPDATA%\<company>\<exe name>_Url_<hash>\<version>\user.config` instead

## Task Checklist

- [ ] Agree the skyline.ms folder with Brendan
- [ ] Ask Nick whether the ClickOnce and settings import code should move to a shared library
- [ ] PR 1. The installer
- [ ] PR 2. Update notice and AutoQCStarter
- [ ] PR 3. Import from the ClickOnce AutoQC, and its uninstall
- [ ] PR 4. Notice in the last ClickOnce AutoQC, released before the installer is published
- [ ] VM tests
  - Install over a running ClickOnce AutoQC with `KeepAutoQcRunning` set
  - The configurations and Panorama password come across, AutoQCStarter restarts the new AutoQC, `.qcfg` files open
  - The ClickOnce AutoQC is uninstalled, and whether its `user.config` is deleted
  - A ClickOnce AutoQC updated at least once, so its data folder holds a previous version's folder
  - An update from one Inno Setup AutoQC to a newer one
- [ ] Publish the installer and `AutoQC.json` to skyline.ms

## Key Files

- `pwiz_tools/Skyline/Executables/Installer/Setup.iss`, `build.ps1` - Skyline's installer, the model
- `pwiz_tools/Skyline/Util/UpdateChecker.cs` - Skyline's manifest check
- `pwiz_tools/Skyline/Util/ClickOnceInstallations.cs` - finds a ClickOnce `user.config`
- `pwiz_tools/Skyline/Util/SettingsImporter.cs`, `pwiz_tools/Skyline/ToolsUI/FirstLaunchImport.cs` - settings import
- `pwiz_tools/Skyline/Util/ClickOnceMaintenanceDialog.cs` - answers the ClickOnce uninstall dialog with Remove
- `pwiz_tools/Skyline/Executables/AutoQC/AutoQC/Program.cs` - startup, `AddFileTypesToRegistry`, `IsNetworkDeployed`
- `pwiz_tools/Skyline/Executables/AutoQC/AutoQC/StartupManager.cs` - the `AutoQCStarter.lnk` Startup shortcut
- `pwiz_tools/Skyline/Executables/AutoQC/AutoQCStarter/Program.cs` - finds AutoQC through `AutoQC.appref-ms`
- `pwiz_tools/Skyline/Executables/AutoQC/AutoQC/MainForm.cs`, `AutoQcConfigManager.cs` - configuration import
