# TODO-20261004_autoqc_find_inno_skyline.md

## Branch Information
- **Branch**: `Skyline/work/20261004_autoqc_find_inno_skyline`
- **Base**: `master`
- **Created**: 2026-10-04
- **Status**: In Progress
- **Module**: `skyline`
- **PR**: (pending)

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
- [x] AutoQC finds the installs again after `Settings.Upgrade()`, and logs the Skyline each option uses
- [x] `SkylineInstallationsTest.TestFindInnoSkyline`, plus a test seam `TestInnoRegistryKey`. Both test suites point
      it at an empty key so a developer's own Inno Setup install does not change which Skyline the tests run
- [x] `/code-review max`. Fixed findings 1, 2, 6, 7, 8, 10, 13, 14, 15. Dropped 3, 5, 11, 12. Applied 4 (registry
      only)

### Remaining
- [ ] Commit the change (local only)
- [ ] Reorder AutoQC startup like Skyline Batch. Run `Settings.Upgrade()` first, then `InitSkylineSettings()`, then
      the configuration migration (`UpdateIfNecessary`). Fixes a pre-existing bug. After an AutoQC update, a user with
      no installed Skyline is asked for the Skyline folder again, and `Upgrade()` then copies the previous version's
      `SkylineCustomCmdPath` over the answer. Replaces the second `FindSkyline()` call
- [ ] Check how `LocalFileSettingsProvider.Upgrade` treats a setting missing from the previous `user.config`
- [ ] Test an AutoQC upgrade by hand (run the Debug `AutoQC.exe`, raise its version, run again)
- [ ] Test on the `AutoQC-Test` VM with a real Inno Setup install from the port branch. Q3 cases C and E from
      `ClickOnce baseline`, case D (all-users, HKLM) from `MSI baseline`
- [ ] Open the PR

## Key Files

- `pwiz_tools/Skyline/Executables/SharedBatch/SharedBatch/SkylineInstallations.cs` - discovery
- `pwiz_tools/Skyline/Executables/SharedBatch/SharedBatch/SkylineSettings.cs` - order of installs
- `pwiz_tools/Skyline/Executables/AutoQC/AutoQC/Program.cs` - startup, settings upgrade, log line
- `pwiz_tools/Skyline/Executables/SkylineBatch/SkylineBatchTest/SkylineInstallationsTest.cs` - new test

