# TODO-20261021_alphapeptdeep_newdoc_load_race.md

## Branch Information
- **Branch**: `Skyline/work/20261021_alphapeptdeep_newdoc_load_race`
- **Base**: `master`
- **Module**: `skyline`
- **Created**: 2026-10-21
- **Status**: Completed
- **PR**: [#4890](https://github.com/ProteoWizard/pwiz/pull/4890) (merged 2026-10-21)
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
Passed on TeamCity build #15671 (88e2ca3).

`/code-review medium` then found that `LibraryManager.LoadBackground` closes each library's read
stream in its `finally`, after `CompleteProcessing` has published the loaded document
(Library.cs ~290-301), so `WaitForDocumentLoaded` alone leaves a short window with the .blib open.
Added `WaitForBackgroundLoaders()` after it (`EndProcessing` runs after the streams close) and made
that helper protected (it was private in AbstractFunctionalTest).

## Audit of similar tests

Reviewed every mid-test Directory/File Move/Delete and SafeDelete in TestFunctional, TestPerf,
TestTutorial and TestConnected (~130 hits). The framework's end-of-test cleanup is safe: `EndTest`
switches to an empty document and waits for background loaders before checking for locks.

- Fixed: `KoinaSkylineIntegrationTest.TestKoinaLibraryBuild(newDocument: true)` deleted Koina.blib
  right after `NewDocument(true)`; the earlier library build stored Koina.blib in the last-used
  settings, so the new document loads it. That path uses an empty document, whose library build is
  refused, so the delete was pointless: it now runs only when `newDocument` is false. No failure
  history.
- Left as is (judged unlikely, no failure history):
  - `BackgroundProteomeTest.cs:121-129` renames the .protdb after waiting only for
    ProteinMetadataManager; another reader of the file might still be busy.
  - `ArdiaImportResultsTest.cs:174-183` deletes the downloaded .raw before its wait; the loader
    reads the .skyd and the replicate points at the remote URI.

## Tasks
- [x] Reproduce locally and confirm root cause
- [x] Fix AlphapeptdeepBuildLibraryTest and verify locally
- [x] Search other tests for the same race, and fix TestKoinaSkylineIntegration
- [ ] TeamCity PR Perf and Tutorial tests green on the final commit (see Merged entry)
- [x] PR merged

## Progress Log

### 2026-10-21 - Merged

PR #4890 merged as commit 8b31ddfb44. Shipped: TestAlphaPeptDeepBuildLibrary waits for the document
and the background loaders before `CheckForFileLocks`; `AbstractFunctionalTest.WaitForBackgroundLoaders`
is now protected; TestKoinaSkylineIntegration no longer deletes Koina.blib in its empty-document
path. TeamCity PR Perf and Tutorial build #15671 passed TestAlphaPeptDeepBuildLibrary with the first
version of the fix (88e2ca3); the PR was merged while the checks on the final commit (a2ac86f) were
still running, so confirm on the next nightly / PR Perf runs. A second `/code-review medium` pass
left four findings, all dropped with reasons (no defects in the committed change). Not done:
BackgroundProteomeTest and ArdiaImportResultsTest borderline cases (above); `LibraryManager`
closing only `ReadStream` (not `ReadStreams`) after load, harmless today because the redundant
connection opens lazily.
