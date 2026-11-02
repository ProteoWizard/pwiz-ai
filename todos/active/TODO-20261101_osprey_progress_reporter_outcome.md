# TODO-20261101_osprey_progress_reporter_outcome.md

## Branch Information
- **Branch**: `Skyline/work/20261101_osprey_progress_reporter_outcome`
- **Base**: `master`
- **Created**: 2026-11-01
- **Status**: In Progress
- **GitHub Issue**: [#4583](https://github.com/ProteoWizard/pwiz/issues/4583)
- **Module**: `osprey`
- **PR**: [#4955](https://github.com/ProteoWizard/pwiz/pull/4955)

## Objective

`ProgressReporter.Dispose` forced a final 100% whether the scope finished, threw or returned
early, so a failed step logged completion. Make success explicit.

## Design

Option 1 of the issue: `Complete()` declares success and prints the closing 100% (same
MinPercentTime rule as before; idempotent; banks the segment at 100 inside a
MultiProgressReporter file scope). `Dispose()` now prints nothing. `using` stays for scope.

Rejected: option 2 (action-taking API) - 48 sites, several report from inside lanes and
helpers where the work is not one delegate. Option 3 (exception sniffing) - rejected in the
issue itself.

Known cost, accepted: a forgotten `Complete()` is silent (no 100% on a successful step). The
class doc and the CommonTest cover it; no enforcement added (socialize first).

## Tasks

- [x] `ProgressReporter.Complete()`; `Dispose()` silent; class doc updated
- [x] Every construction site in Osprey and CarafeSharp ends its success path with `Complete()`
      (42 `using` sites, the `QProgress` usings, the 6 non-using sites)
- [x] Sites that record an error and return after the scope complete only when no error
      (FirstPassFdrTask x3); Stage6Planner's invalid-file throw moved inside the scope
- [x] Workaround removed: LibraryDeduplicator, ModelDiagnosticsData.BuildPass2 and the
      DiannTsvLoader phase-2 reporter are `using`d again; DiannTsvLoader's read reporter too
- [x] CommonTest: ProgressReporterTest gains TestOnlySuccessCompletes (left early, threw
      after 50%, Complete twice); MultiProgressReporterTest completes its segment reporter
- [x] Build-Osprey -RunTests -RunInspection: 646/646, inspection 0 warnings
- [x] CarafeSharp Debug build succeeded; its inspection reports one PRE-EXISTING warning in an
      untouched file (`CarafeSharp.Models\PeptdeepConstants.cs:25` RedundantUsingDirective)
- [x] regression.ps1 -Dataset Stellar: PASSED (mode1, 1c, 4, streamed join, 6); the
      straight-through log still carries 30 completion lines
- [x] Review (see below)
- [x] CommonTest: no Skyline build in this worktree, so ProgressReporterTest.cs was linked
      temporarily into Osprey.Test with a stub AssertEx (reverted): TestProgressReporter passed.
      MultiProgressReporterTest (needs CommonTest internals) only gained one Complete() call; CI runs it
- [x] PR #4955 opened

## Review (medium)

`/code-review` could not run from this unattended session: the agent's cwd is pinned to
`C:\proj\ai` and `Deny-CodeReviewInAiRepo.ps1` (correctly) blocks it there. Substituted an
independent general-purpose reviewer over the saved diff with the same brief (correctness only,
verified findings). Result: no defects; it re-checked all 50 sites, early exits, the re-indented
blocks, segment banking and the tests. Two notes, both dropped:
- `Report` after `Complete` could print a percent after 100%: no caller does this, and the old
  `Dispose` had the same property - not this issue's concern.
- Some sites print 100% before a final commit (ParquetScoreCache `saver.Commit`, LibraryBlibWriter
  decoy pairs, DiannTsvLoader's refusal of bad lines): the reporter measures the row/byte work,
  which did finish; unchanged from before.

## Progress Log

### 2026-11-01
- Implemented as above. Commit 49af0db202.
