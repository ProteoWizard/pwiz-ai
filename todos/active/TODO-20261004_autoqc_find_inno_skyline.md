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

This is the `master` release planned in `TODO-20260929_autoqc_net10_readiness.md`. It has to ship before the first
.NET 10 Skyline, because a ClickOnce AutoQC takes an update only when it restarts.

## Decisions

- Look up `InstallDir` under `Software\MacCossLabUW\<Skyline|Skyline-daily>` in HKCU, then in HKLM (64-bit view).
  This is the record the Inno Setup installer writes (PR #4676, `Setup.iss` `[Registry]`)
- Registry only. The `%LocalAppData%\Programs\<channel>` fallback was dropped after the code review. The installer
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
- [x] `/code-review max`. Fixed findings 1, 2, 6, 7, 8, 10, 13, 14, 15. Dropped 3, 5, 11, 12. Applied 4 (registry
      only)
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

### Remaining
- [ ] Add the `skyline` label to PR #4771
- [ ] `/code-review max` on the branch (both commits). Running
- [ ] Test on the `AutoQC-Test` VM with a real Inno Setup install from the port branch. Q3 cases C and E from
      `ClickOnce baseline`, case D (all-users, HKLM) from `MSI baseline`
- [ ] On the VM `clean` checkpoint (no Skyline), check the Find Skyline dialog is not shown again after an AutoQC
      version bump, and the chosen folder is kept
- [ ] Copilot review of PR #4771

## Key Files

- `pwiz_tools/Skyline/Executables/SharedBatch/SharedBatch/SkylineInstallations.cs` - discovery
- `pwiz_tools/Skyline/Executables/SharedBatch/SharedBatch/SkylineSettings.cs` - order of installs
- `pwiz_tools/Skyline/Executables/AutoQC/AutoQC/Program.cs` - startup, settings upgrade, log line
- `pwiz_tools/Skyline/Executables/SkylineBatch/SkylineBatchTest/SkylineInstallationsTest.cs` - new test

