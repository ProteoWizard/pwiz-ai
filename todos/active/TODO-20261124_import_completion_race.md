# Fix multi-file imports that never finish when files complete together

## Branch Information
- **Branch**: `Skyline/work/20261124_import_completion_race` (cmdline)
- **Base**: `master`
- **Created**: 2026-11-24
- **Status**: In Progress
- **Module**: `skyline`
- **PR**: [#5074](https://github.com/ProteoWizard/pwiz/pull/5074)

## Objective

SkylineCmd imports of several files at once intermittently never finished: the process sat at
zero CPU in `MemoryDocumentContainer.WaitForComplete()` (CommandLine.ImportDataFiles) forever.
Found while timing PR #5057/#5062 (thermo-dda set: 4 .raw files); master hangs too.

## Root cause

`FileLoadCompletionAccumulator.Complete()` (MultiFileLoader.cs) counted a completion with
`Interlocked.Increment` before queuing it for the commit thread, and the thread whose count reached
the file count called `QueueWorker.DoneAdding()`. `DoneAdding` does not close the queue: it queues a
null end marker per consumer. A thread that counted earlier but queued later put its completion
behind the marker; the single commit thread stopped at the marker, the batch never reached its
commit count (file count, or the loading thread count), the caches were never added to the
document, and `WaitForComplete` never saw a loaded document or a final status.

Dump evidence (hang-soak and merge5062/dda-hang2.dmp in the session folder): all 4 files
`ChromatogramLoadingStatus` complete at 100%; accumulator `_completedCount` 3, `_consumedCount` 2;
commit QueueWorker `_itemsWaiting` 1 with its thread gone; `MultiFileLoader._loadingPaths` still
held all 4 files. Introduced with batched commits (8ba3a0d0b6, 2019-11); faster readers make files
finish within the race window more often.

## Tasks

- [x] Root cause from two hang dumps
- [x] Failing test first: `UtilTest.FileLoadCompletionAccumulatorConcurrentCompleteTest`
      (4 threads released by a Barrier, 2000 iterations) - failed at iteration 25 before the fix
- [x] Fix: queue the completion, then count; the last counter then knows every completion is
      ahead of the end marker
- [x] Test passes (2000 iterations, 1.4 s)
- [x] thermo-dda soak, master vs fixed, 40 each: master 1 hang, fixed 0 (earlier master soak 3/29)
- [x] Related tests: OptimalThreadCountTest, the ConsoleImport* same-name/make-unique tests,
      TestCommandLineNoJoin, ThermoFormatsTest, WatersMultiFileTest, TestWiffCommandLineImport,
      TestImportResultsCancel, TestImportResultsFilesRestore - all pass
- [x] CodeInspection and Skyline tcinspect: clean
- [x] Commit (f22dcdd8d9), push, open PR #5074
- [ ] CI green, review, merge

## Notes

- Run-Tests.ps1 with `-TestName` holding many names plus `-UpdateTestList` builds the log file
  name from the whole list and TestRunner crashes on it; `-UseTestList` works. Shared script left
  as is.

## Progress Log

### 2026-11-24 - Root cause, fix and verification

- Root cause, failing test, fix and verification as above, all in one session.
