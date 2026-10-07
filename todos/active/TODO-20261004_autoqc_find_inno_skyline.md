# TODO-20261004_autoqc_find_inno_skyline.md

## Branch Information
- **Branch**: `Skyline/work/20261004_autoqc_find_inno_skyline`
- **Base**: `master`
- **Created**: 2026-10-04
- **Status**: In Progress
- **Module**: `skyline`
- **PR**: [#4771](https://github.com/ProteoWizard/pwiz/pull/4771)

## Objective

Release AutoQC Loader from `master` (.NET Framework, ClickOnce) so that it finds a Skyline installed by the new
Inno Setup installer and runs that install's `SkylineCmd.exe`. Skyline Batch shares the code and gets the change too.

It was decided to ship this as a ClickOnce update from `master`, before AutoQC itself moves to an Inno Setup
installer. It has to ship before the first .NET 10 Skyline, because a ClickOnce AutoQC takes an update only when it
restarts.

## Decisions

- Look up `InstallDir` under `Software\MacCossLabUW\<Skyline|Skyline-daily>` in HKCU, then in HKLM (64-bit view).
  This is the record the Inno Setup installer writes (PR #4676, `Setup.iss` `[Registry]`)
- Registry only. The `%LocalAppData%\Programs\<channel>` fallback was dropped. The installer
  always writes `InstallDir`, so a folder without a record is not an install it made
- Order for the Skyline and Skyline-daily options is Inno Setup, then ClickOnce, then administrative. An
  administrative-first order was considered and rejected. The administrative path is also where the old WiX MSI
  installs, and it can sit next to a per-user Inno Setup install
- Configurations record only the Skyline type, so saved and shared configurations move to the Inno Setup install
  with no edit

## Task Checklist

### Completed
- [x] `SkylineInstallations.FindSkyline` finds an Inno Setup install, ignoring an empty, relative or invalid
      `InstallDir`
- [x] `SkylineSettings` uses the Inno Setup install before ClickOnce and administrative installs
- [x] New SharedBatch settings `SkylineInnoCmdPath` and `SkylineDailyInnoCmdPath`
- [x] AutoQC logs the Skyline each option uses
- [x] `SkylineInstallationsTest.TestFindInnoSkyline`, plus a test seam `TestInnoRegistryKey`. Both test suites point
      it at an empty key so a developer's own Inno Setup install does not change which Skyline the tests run
- [x] Committed as `0075a8822d` (Inno Setup discovery) and pushed
- [x] Reordered AutoQC startup like Skyline Batch, committed as `cdb95f602b` and pushed. `Settings.Upgrade()` runs
      first, then `InitSkylineSettings()`, then the configuration migration (`MigrateConfigsIfRequired`). Fixes a
      pre-existing bug. After an AutoQC update, a user with no installed Skyline was asked for the Skyline folder
      again, and `Upgrade()` then copied the previous version's `SkylineCustomCmdPath` over the answer.
      `InitSkylineSettings()` now saves the folder chosen in the Find Skyline dialog
- [x] Tested an AutoQC upgrade by hand on the developer machine (fake 26.1.1.273 `user.config` with stale runner,
      Inno Setup and custom paths). Discovery replaced the stale runner and Inno Setup paths, the custom folder was
      kept, and `InstalledVersion` became 26.1.1.274
- [x] AutoQC 18 of 18, SkylineBatch 39 of 39 (with R installed), ReSharper inspection clean for both solutions
- [x] Opened PR #4771
- [x] Added the `SkylineInstallations.TestReadInnoInstallDir` seam, which replaces the registry read and takes the
      hive. `TestFindInnoSkyline` checks that an install recorded only in HKLM is found and that HKCU comes first.
      The 64-bit registry view is covered only by the VM all-users install test. Answers Copilot comment 4187104391
- [x] AutoQC 18 of 18, SkylineBatch 39 of 39 (`DataDownloadTest` on re-run), ReSharper inspection clean for both
      solutions
- [x] Tested on the `AutoQC-Test` VM (2026-10-06) with Nick's Skyline-daily builds from PR #4773: the ClickOnce
      handoff build 26.1.1.278 and the Inno Setup build 26.1.1.280. AutoQC was published as ClickOnce to
      `software/AutoQC-test24`, signed with a self-signed test certificate: master `0c7a9167a6` as 26.1.1.278, then
      this branch `2262ccfc66` as 26.1.1.279

  | Test | Skyline-daily installed | AutoQC 26.1.1.279 used |
  |---|---|---|
  | AutoQC update | ClickOnce, AutoQC 26.1.1.278 updated by ClickOnce | `SkylineDailyRunner.exe`. Settings carried over, no Find Skyline dialog |
  | Skyline-daily handoff | ClickOnce upgraded through the handoff, leaving per-user Inno only | Inno `SkylineCmd.exe` after an AutoQC restart |
  | Both installed | ClickOnce and per-user Inno | Inno `SkylineCmd.exe` (HKCU) |
  | All-users install | All-users Inno in `C:\Apps\Skyline-daily`, nothing in `Program Files` | `C:\Apps\Skyline-daily\SkylineCmd.exe` (HKLM, 64-bit view) |

  Imports and Panorama uploads worked in every case. While AutoQC ran during the handoff, its imports failed and
  were retried until it restarted, and the configuration stayed `Running`
- [x] AutoQC logs the folder set with "Specify Skyline installation directory" at startup, as it does for the
      Skyline and Skyline-daily options
- [x] Tested an AutoQC update on the VM with no Skyline AutoQC could find. AutoQC 26.1.1.279 showed the Find Skyline
      dialog, and `C:\SkylineCustom` was chosen. After the ClickOnce update to 26.1.1.280 the dialog did not appear,
      and the log and the configuration still used `C:\SkylineCustom\SkylineCmd.exe`

### Remaining

## Key Files

- `pwiz_tools/Skyline/Executables/SharedBatch/SharedBatch/SkylineInstallations.cs` - discovery
- `pwiz_tools/Skyline/Executables/SharedBatch/SharedBatch/SkylineSettings.cs` - order of installs
- `pwiz_tools/Skyline/Executables/AutoQC/AutoQC/Program.cs` - startup, settings upgrade, log line
- `pwiz_tools/Skyline/Executables/SkylineBatch/SkylineBatchTest/SkylineInstallationsTest.cs` - new test

