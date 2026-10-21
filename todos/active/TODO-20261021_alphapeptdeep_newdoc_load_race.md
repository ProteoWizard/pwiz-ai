# TODO-20261021_alphapeptdeep_newdoc_load_race.md

## Branch Information
- **Branch**: `Skyline/work/20261021_alphapeptdeep_newdoc_load_race`
- **Base**: `master`
- **Module**: `skyline`
- **Created**: 2026-10-21
- **PR**: (pending)
- **Objective**: Fix TestAlphaPeptDeepBuildLibrary failing on every TeamCity "PR Perf and Tutorial
  tests" run since 2026-10-11 with "Failed loading library ...rat_consensus_final_true_lib.blib"
  (SQLite CantOpen), then find other tests with the same race.

## Root cause

The test ends with `SkylineWindow.NewDocument()` followed immediately by
`TestFilesDir.CheckForFileLocks(TestFilesDir.FullPath)`. `NewDocument` builds the new document from
`Settings.Default.SrmSettingsList[0]` (last-used settings), so it starts background loads of the
libraries those settings hold (rat_consensus_final_true_lib.blib, rat_cmp_20.blib,
LibraryWithIrt.blib). `CheckForFileLocks` tests for locks by renaming the whole test directory to a
GUID and back; a library open that lands in that window fails with SQLite CantOpen, and the
resulting MessageDlg times out at test end.

Reproduced locally with a diagnostic printed just before `CheckForFileLocks`:
`IsLoaded=False; IsDocumentLoaded=False` and the exact CI failure. With `WaitForDocumentLoaded()`
added: `IsLoaded=True`, test passes, and the lock check stays clean (loaded libraries do not hold
their files open). Plain local runs usually pass: the GC.Collect/WaitForPendingFinalizers at the top
of `CheckForFileLocks` gives a fast machine time to finish the loads.

Onset: last full-suite pass was build #15519 (426785bd, 2026-10-09); first failure #15553
(14b1ebff, 2026-10-11). No Skyline commit in that range plausibly affects this test (#4819 import
settings dialog, #4802 build.bat submodule update), so the onset is likely CI timing, unconfirmed.

## Fix

Added `WaitForDocumentLoaded()` after the save-changes `ClickNo` and before `CheckForFileLocks`.

## Tasks
- [x] Reproduce locally and confirm root cause
- [x] Fix AlphapeptdeepBuildLibraryTest and verify locally
- [ ] TeamCity PR Perf and Tutorial tests green
- [ ] Search other tests for NewDocument (or other library-loading actions) followed by
      CheckForFileLocks without a wait, and fix them on this branch
- [ ] PR merged
