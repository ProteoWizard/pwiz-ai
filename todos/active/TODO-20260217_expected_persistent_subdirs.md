# TestFeatureDetectionTutorialFuture fails on first run with clean downloads directory

## Branch Information
- **Branch**: `Skyline/work/20260217_expected_persistent_subdirs`
- **Base**: `master`
- **Created**: 2026-02-17
- **Status**: In Progress
- **GitHub Issue**: [#3993](https://github.com/ProteoWizard/pwiz/issues/3993)
- **PR**: (pending)

## Objective

Add an `ExpectedPersistentSubdirectories` property to `TestFilesDir` so tests can declare
subdirectory names where new files are expected to be created. The modification check at
cleanup filters these out before deciding whether to throw, allowing tests like
`TestFeatureDetectionTutorialFuture` to cache converted mzML files across runs.

## Tasks

- [x] Add `PotentialAdditionalPersistentFileSet` property to `TestFilesDir` (renamed from `ExpectedPersistentSubdirectories`)
- [x] Modify `CheckForModifiedPersistentFilesDir()` to filter expected new files (also tracks file sizes via `PersistentFilesDirFileSizes`)
- [ ] Set `PotentialAdditionalPersistentFileSet` in `FeatureDetectionTest.DoTest()`
- [ ] Verify fix works (test passes on first run with clean converted dir)
- [x] Add `PotentialMissingPersistentFileSet` so tests can declare files they will delete (implemented, size-adjusted)
- [x] Add `DeleteScreenshotFiles` helper to `DiaSwathTutorialTest` — registers+deletes in one call; used for diaumpire and DIANN cleanup

## Files to Modify

- `pwiz_tools/Skyline/TestUtil/TestFilesDir.cs`
- `pwiz_tools/Skyline/TestPerf/FeatureDetectionTest.cs`

## Progress Log

### 2026-02-17 - Session Start

Starting work on this issue. Problem analyzed, plan approved.

### 2026-03-02 - Session

* Added `PotentialMissingPersistentFileSet` and per-file size tracking to `TestFilesDir`
* Added `DeleteScreenshotFiles` helper to `DiaSwathTutorialTest`; refactored diaumpire and DIANN cleanup to use it
* Demonstrated bug (TestDiaQeTutorial fails with screenshots after TestDiaQeDiaNnTutorialDraft) and verified fix passes
* Committed: `f76b304d61`
