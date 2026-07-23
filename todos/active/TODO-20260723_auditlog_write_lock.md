# TODO-20260723_auditlog_write_lock.md

## Branch Information
- **Branch**: `Skyline/work/20260723_auditlog_write_lock`
- **Base**: `master`
- **Created**: 2026-07-23
- **Status**: In Progress
- **GitHub Issue**: none
- **PR**: [#4450](https://github.com/ProteoWizard/pwiz/pull/4450) (labeled `Cherry pick to release`)

## Motivation

`TestMassErrorGraphs` failed in the Release Branch nightly on BRENDANX-UW8
(run 84445, 2026-07-22, git 7f21f4737, zh locale) with the familiar
"MessageDlg not closed for 10 seconds" symptom. The dialog was Skyline's
"Failure attempting to modify the document", raised because the test harness's
own audit log recorder could not append to
`...\SkylineTester Results\TestMassErrorGraphs\AuditLog\zh\TestMassErrorGraphs.log` —
the file was "being used by another process".

Chain: `EditMenu.EditDelete` -> `SkylineWindow.ModifyDocument` -> `SetDocument` ->
`DocumentChangedEvent` -> `AbstractFunctionalTest.WriteEntryToFile`. Two problems:

1. `File.Open(filePath, FileMode.Append)` implies `FileShare.None`, so any
   transient outside handle (realtime AV scanning the file it just saw closed,
   Search indexer, backup agent) causes a sharing violation. The recorder opens
   and closes the file once per logged entry, which invites exactly that.
2. The `ERROR_SHARING_VIOLATION` diagnostic in `WaitForSkyline` — which names the
   locking process via `FileLockingProcessFinder` — could never fire for this case,
   because `SkylineWindow.ModifyDocument` catches `IOException` and turns it into a
   message box before it can reach that handler. So the nightly failure told us the
   file was locked but not by whom.

The test is incidental; it just writes many audit entries in quick succession.
The recorder runs for every functional test, so the exposure is universal. The
code is identical on master and on the release branch. One occurrence in 90 days
on this test, one machine.

## Scope

`pwiz_tools/Skyline/TestUtil/TestFunctional.cs`:

- New `AppendToLogFile`, used by both `WriteEntryToFile` and `WriteDiffEntryToFile`:
  opens with `FileShare.ReadWrite` and retries via `TryHelper.TryTwice` (4 tries,
  500 ms apart). Output bytes are unchanged (`WriteEntryToFile` appends
  `Environment.NewLine` where it previously used `sw.WriteLine`).
- Extracted the lock diagnostic from `WaitForSkyline` into `DescribeFileLocks`, and
  applied it at the throw site in `AppendToLogFile`. A recurrence now names the
  holding process in the message box text instead of just reporting a locked file.
- New `protected RecordedAuditLogFilePath` so a test can get at the recorded log.

`pwiz_tools/Skyline/TestFunctional/AuditLogTest.cs`:

- Added `VerifyLoggingSurvivesLockedLogFile` at the end of `DoTest`: holds the
  recorded log open with `FileShare.ReadWrite` the way a scanner would, changes an
  audit log entry reason, and asserts the entry was still recorded.

Related but separate: `Skyline/work/20260507_indexer_exclusion_test` (PR #4191)
warns when the machine's AV/indexer configuration invites this class of failure.
That branch tells the operator their machine is misconfigured; this one makes the
harness survive it regardless.

## Self-review findings addressed

- `DescribeFileLocks` could throw out of a catch block: `FileLockingProcessFinder.GetProcessesUsingFile`
  throws a bare `Exception` when the restart manager is unavailable (`FileLockingProcessFinder.cs:122,136`),
  which would have destroyed the original `IOException` and escaped `ModifyDocument`'s `IOException`
  catch entirely. Now guarded, returning the original exception.
- Preserve the original stack trace when there is nothing to add (`throw;` rather than `throw x;`).
- Shortened the retry to 3 tries 100 ms apart. `TryHelper.ReportExceptionForRetry` adds up to 5 s per
  attempt under `SKYLINE_TESTER_PARALLEL_CLIENT_ID` or `JETBRAINS_DPA_AGENT_ENABLE`, and this runs on
  the UI thread inside `SetDocument`.
- Write the entry with a single `FileStream.Write` of UTF8 bytes instead of a buffered `StreamWriter`,
  so a retry cannot duplicate what a partial write already recorded.
- Strengthened the test oracle: read the appended tail and assert it contains the new reason, rather
  than only asserting the file grew.

Not adopted: reusing `FileLockingProcessFinder.ToFileLockingException`. That helper expects the
exception message to carry a bare file name to locate beneath a given directory
(`Directory.GetFiles(dirPath, lockedFileName, ...)`); ours carries an absolute path, which that call
would reject. Noted in a comment on `DescribeFileLocks`. Also unaddressed: nothing exercises the retry
path itself (the test's handle reproduces the `FileShare` case), since a deterministic test for it
needs a timed release from another thread.

## Regex choice (decided, do not revert)

`DescribeFileLocks` extracts the locked path with the non-greedy `'([^']+)'`, matching the
shared `FileLockingProcessFinder.ToFileLockingException`. Copilot asked for this over the
original greedy `'(.*)'`. A later self-review noted the non-greedy form misparses a path that
itself contains an apostrophe (e.g. a checkout under `C:\Users\O'Brien\...`), which the greedy
form handled because the IOException message has exactly one quoted span. Kept non-greedy
anyway: it is diagnostic-only (the true IOException is preserved as InnerException), LOW
severity, cannot occur on the build/nightly machines, and staying consistent with the shared
helper beats introducing a third regex variant. Do not revert to greedy.

## Verification

- Red/green confirmed both ways: with `FileShare.None` restored, `TestAuditLog`
  fails with the nightly's exact signature ("MessageDlg not closed for 10 seconds",
  now reading "locked by: TestRunner (this process)"); with the fix it passes.
- `TestAuditLog` - passes
- `TestAuditLogTutorial` - passes; this one diffs the recorded log against the
  committed expected file, so it proves the refactored writers produce identical output
- `CodeInspection` - passes

## Remaining

- Watch TeamCity on #4450.
- Optional: Copilot review (billed) if extra API/idiom scrutiny seems warranted.
- After merge, confirm the automatic cherry-pick PR to `Skyline/skyline_26_1` lands,
  since that is the branch where the failure was observed.
