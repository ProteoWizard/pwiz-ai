# TODO-20261123_score_type_detection_race.md

## Branch Information
- **Branch**: `Skyline/work/20261123_score_type_detection_race`
- **Base**: `master`
- **Created**: 2026-11-23
- **Status**: In Progress
- **Module**: `skyline`
- **PR**: (pending)
- **Related**: nightly failures of TestDiannSearch1_9_1 on BRENDANX-UW6 (10 in pass 2 since 2026-10-20,
  e.g. run 86929)

## Objective

Fix Import Peptide Search losing its score-type detection result when the search wizards (DIA-NN,
EncyclopeDIA, Osprey) add their results before showing the dialog. Detection then finishes before
the grid has a window handle, `BeginInvoke` throws, the result is swallowed, and the score types
never load: the wizard cannot advance, and TestDiannSearch1_9_1 times out after 360 seconds.

## Done

- [x] `BuildLibraryGridView`: a result that arrives before the handle exists (or after it is
      destroyed) is held and posted from `OnHandleCreated`, under a lock that orders the two
- [x] `BlibIrtTest`: constructs Import Peptide Search unshown, adds search results, waits for
      detection to finish, then shows it and requires the score types to load (red: 360 s
      timeout before the fix; green: 8 s)
- [x] `DiannSearchTest`: the score-type wait fails at once with the grid's `ScoreTypeError` text,
      and a timeout lists each file's score type, instead of a bare 360 s timeout

## Progress Log

### 2026-11-23 - Root cause and fix

Nightly run 86929 (BRENDANX-UW6): TestDiannSearch1_9_1 timed out at the `ScoreTypesLoaded` wait
with no detection thread left in the dump. Forcing a score-type error locally reproduced the exact
symptom with the error never reaching the grid; `DiannSearchDlg.ImportDiannLibrary` adds the
parquet (starting detection) before `ShowDialog`, and the `catch (InvalidOperationException)`
around `BeginInvoke` dropped the result. Why it shows on UW6 in pass 2 only was not established;
it needs detection to beat dialog creation, which is timing-dependent.
