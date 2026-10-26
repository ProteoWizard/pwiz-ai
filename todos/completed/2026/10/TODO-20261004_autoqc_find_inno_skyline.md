# TODO-20261004_autoqc_find_inno_skyline.md

## Branch Information
- **Branch**: `Skyline/work/20261004_autoqc_find_inno_skyline`
- **Base**: `Skyline/skyline_26_1_1`
- **Created**: 2026-10-04
- **Status**: Completed
- **Module**: `skyline`
- **PR**: [#4771](https://github.com/ProteoWizard/pwiz/pull/4771) (merged 2026-10-10)

## Objective

Release AutoQC Loader from `Skyline/skyline_26_1_1` (.NET Framework, ClickOnce) so that it finds a Skyline installed by the new
Inno Setup installer and runs that install's `SkylineCmd.exe`. Skyline Batch shares the code and gets the change too.

It was decided to ship this as a ClickOnce update from `Skyline/skyline_26_1_1`, before AutoQC itself moves to an Inno Setup
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
- [x] Tested Skyline Batch on the `AutoQC-Test` VM (2026-10-08), at Brendan's request. The branch's Debug build
      (`SkylineBatch\bin\Debug`, current with `50cbbba2df`) was copied to the VM and run from its folder. One
      configuration imported two `QEP_2015_0424_RJ_*_prtc.raw` files into `QEP_2015_0424_RJ.sky`. Skyline Batch does
      not log which Skyline it uses, so the running processes were listed during each run, and the `--version` line
      in the Skyline Batch log identified the build

  | Case | Skyline-daily installed | Skyline Batch used |
  |---|---|---|
  | ClickOnce only | ClickOnce 26.1.1.278 (checkpoint `AutoQC 279 + ClickOnce daily`) | `SkylineDailyRunner.exe`, then the ClickOnce `Skyline-daily.exe` (`--version` 26.1.1.278) |
  | Both installed | Per-user Inno 26.1.2.280 installed directly over the ClickOnce one | Inno `SkylineCmd.exe` in `%LOCALAPPDATA%\Programs\Skyline-daily` (`--version` 26.1.2.280), after restarting Skyline Batch |
  | Inno only | The ClickOnce one uninstalled from Settings | Inno `SkylineCmd.exe` (`--version` 26.1.2.280) |
  | All-users install | All-users Inno 26.1.1.280 in `C:\Apps\Skyline-daily` (checkpoint `Case D`) | `C:\Apps\Skyline-daily\SkylineCmd.exe` (`--version` 26.1.1.280) |

  Only the Skyline-daily option was enabled in every case, and every import finished. Nick's 26.1.2.280 build, from
  his test folder `InstallTest/NewVersion`, offered at first start to import the ClickOnce Skyline-daily
  26.1.1.278's settings, with the uninstall box enabled and unchecked. The import was accepted without uninstalling

### Remaining

- [x] Add a Skyline Batch VM line to the PR description's Test plan (2026-10-08)

## Key Files

- `pwiz_tools/Skyline/Executables/SharedBatch/SharedBatch/SkylineInstallations.cs` - discovery
- `pwiz_tools/Skyline/Executables/SharedBatch/SharedBatch/SkylineSettings.cs` - order of installs
- `pwiz_tools/Skyline/Executables/AutoQC/AutoQC/Program.cs` - startup, settings upgrade, log line
- `pwiz_tools/Skyline/Executables/SkylineBatch/SkylineBatchTest/SkylineInstallationsTest.cs` - new test

## Progress Log

### 2026-10-10 - Merged

PR #4771 merged into `Skyline/skyline_26_1_1` as commit `77d7b55f08`. AutoQC and Skyline Batch find a Skyline or
Skyline-daily installed by the Inno Setup installer through its `InstallDir` registry record (HKCU, then HKLM), and
use it before a ClickOnce or administrative install. AutoQC also runs its settings upgrade before asking for a
Skyline folder, so a folder chosen after an update is no longer overwritten. Nothing was deferred.

