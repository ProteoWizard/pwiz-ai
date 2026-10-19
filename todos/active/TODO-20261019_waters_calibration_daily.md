# TODO-20261019_waters_calibration_daily.md - Backport waters_connect lockmass fix to the .NET 4.7.2 daily branch

## Branch Information
- **Branch**: `Skyline/work/20261019_waters_calibration_daily` (checkout `C:\Dev\Backport`)
- **Base**: `Skyline/skyline_26_1_1` (.NET 4.7.2 Skyline-daily)
- **Module**: `skyline`
- **Created**: 2026-10-19
- **Status**: In progress
- **Source**: master commit `e7b02632bb` (#4782, the pwiz-sharp port) - but applied from its C++
  original, PR #4498 (`Skyline/work/20260727_Waters_dataconvert_mzml_import`, closed unmerged
  2026-10-06 when development moved to .NET 10). See TODO-20260727_Waters_dataconvert_mzml_import.md
  and TODO-20260930_net10_waters_calibration_port.md.

## Approach
- e7b02632bb cannot be cherry-picked here: 21 of its 26 files are pwiz-sharp, and its wrapper edits
  went to `ProteowizardWrapper.PwizSharp/MsDataFileImpl.cs`, which this branch does not have.
- #4498's final head `c7a6dc27e8` already carries the fixes the port fed back. Its last master merge
  `699dd48953` is an ancestor of `skyline_26_1_1`, so `git merge --squash c7a6dc27e8` brings in
  exactly its 33 files, conflict-free.
- Skyline files match e7b02632bb (ignoring whitespace) apart from unrelated master drift.
- chambm's last review on #4498 was CHANGES_REQUESTED (2026-09-24, replied 2026-09-25); the
  developer is adding reviewers.

## Tasks
- [x] Squash-merge `c7a6dc27e8` onto the work branch (33 files)
- [x] Full `bs.bat` build incl. pwiz C++ unit tests
- [x] Skyline: TestWatersCalibrationSpectrum, TestTicChromatogram, WatersLockmassCmdlinePerfTest
- [x] CodeInspectionTest
- [ ] Commit, push, PR against `Skyline/skyline_26_1_1`

## Progress Log
### 2026-10-19
- Investigated; squash-merged #4498's head onto the work branch.
- `bs.bat` (release): SpectrumList_IgnoreCalibrationScansTest, SpectrumList_FilterTest,
  Reader_UIMF_Test, Reader_Waters_Test passed; Skyline unit pass incl. TestTicChromatogram and
  TestWatersCalibrationSpectrum 0 failures (build64.log in checkout root).
- WatersLockmassCmdlinePerfTest passed via Run-Tests.ps1 (data cached under SKYLINE_DOWNLOAD_PATH,
  raw touched by the run). CodeInspection passed.
- Committed `a2e361057a`.
