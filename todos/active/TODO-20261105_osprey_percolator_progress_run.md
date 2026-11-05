# TODO-20261105_osprey_percolator_progress_run.md

## Branch Information
- **Branch**: `Skyline/work/20261105_osprey_percolator_progress_run`
- **Base**: `Skyline/work/20261028_osprey_diann_fdr_gap` (#4950) - the PR targets #4950's branch and merges there before #4950 merges to master
- **Created**: 2026-11-05
- **Status**: In Review - gates green, PR open against #4950's branch; TeamCity Perf/Regression not triggered (parent session queues it). Decisions below are the conservative options taken without Brendan.
- **GitHub Issue**: [#4979](https://github.com/ProteoWizard/pwiz/issues/4979)
- **Module**: `osprey`
- **PR**: [#5000](https://github.com/ProteoWizard/pwiz/pull/5000) (base: #4950's branch)
- **Worktree**: `C:\proj\wt-percolator` (agent P1)

## Objective

Finish #4979 after #4984 (merged as 3f7788ac62): convert the ProgressReporter scopes #4984 could
not touch (PercolatorEngine x5, PercolatorScorer x2, PercolatorQValues.QProgress, the
PipelineByproducts iterator), then make the ProgressReporter constructor and Complete()
non-public so a forgotten completion cannot be written. Pure refactor: log output identical.

## Decisions (conservative options, for Brendan to revisit)

- #4950's branch (1d2a65c684) did not have #4984's wrappers. Merged origin/master (e941a2ab39,
  #4984 + #4982) into this branch with a plain merge (aa7c0b19e3, no conflicts) before starting.
  The PR therefore also carries those two master commits into #4950's branch.
- Constructor and Complete() are PRIVATE, not internal: the only callers are TryRun (which Run
  and Run<T> delegate to) and Begin / its Scope. The CommonTest tests go through the wrappers and
  Begin; no InternalsVisibleTo seam was needed.
- `ProgressReporter.Begin(...)` returns a nested `ProgressReporter.Scope` (Report, MarkComplete,
  Dispose). Dispose completes only after MarkComplete, so the completion line prints at the
  same point in the log it did when the iterator called Complete() at the end of its try (the
  finally between them prints nothing).
- PercolatorQValues.QProgress removed; its one caller (PercolatorScorer floors) now uses QRun.
- PercolatorEngine ingest reporter was not a `using` scope (a local function captured it): the
  local function `DedupFile` now takes the reporter as a parameter and the lanes call runs in
  `ProgressReporter.Run`. The heading still prints before any work starts.
- RunStreamingIntoProjection's training-feature load moved into a private static
  `LoadTrainingSubsetFeatures`: as an inline lambda it captured `subsetByFile` / `subsetEntries`,
  which the method nulls before its score pass to release them (AccessToModifiedClosure x2).
  The helper captures its own parameters instead, so the caller's release still works. (A local
  copy for the lambda would have pinned the lists; `[InstantHandle]` on the wrapper does not
  reach Osprey's inspection, since JetBrains attributes are conditional and absent from the
  CommonUtil DLL.)
- #4950 did not move the regression goldens (no change under `osprey-regression.data` or
  regression.ps1 against master), so the gates compare against master's goldens.

## Tasks

- [x] Merge origin/master (wrappers missing on #4950's branch)
- [x] Convert PercolatorEngine (5), PercolatorScorer (2), drop QProgress
- [x] Add ProgressReporter.Begin / Scope; use it in PipelineByproducts.StreamSourcedFiles
- [x] Constructor and Complete() private; tests moved to wrappers / Begin
- [x] Build-Osprey -RunTests -RunInspection - 671/671, inspection zero
- [x] CarafeSharp -RunTests -RunInspection - 109/109, inspection zero
- [x] CommonTest TestProgressReporter + TestMultiProgressReporter - 2/2
- [x] regression.ps1 Stellar + StellarLibDecoy - both PASSED against the committed goldens
- [x] Code review (medium), triage (below)
- [x] PR #5000 opened against #4950's branch (not merged; TeamCity not triggered)

## Code review (2026-11-05)

`/code-review` was refused by the session hook (`Deny-CodeReviewInAiRepo.ps1`: the agent
session's working directory is `C:\proj\ai`, so the skill would not have reviewed the worktree).
Per the brief, a fresh general-purpose reviewer agent reviewed `git diff aa7c0b19e3 d8afade3a5`
instead. No correctness bugs: output order, exception paths, lambda returns, overload resolution,
captured / released locals, thread-safety and remaining callers all checked. Two cleanups:
- FIXED: the public `Run` doc said "Parameters as for the constructor", now private. The
  parameters are described on `Run` itself; `Begin` points at `Run`.
- DROPPED: remove `IDisposable` from `ProgressReporter` (its Dispose is empty and outside code
  can no longer own one). Harmless as is, and outside this change's scope.

## Progress Log

### 2026-11-05 - Session 1 (agent P1)
- Converted all remaining sites; see Decisions. Commit d8afade3a5, doc fix in a second commit.
- Gate logs in `C:\proj\ai\.tmp\sessions\20261105-agentP1\`: `osprey-gate4.log` (and
  `osprey-gate5.log` after the doc fix), `carafe-gate.log`, `commontest-dotnettest.log`
  (built with `Build-Skyline.ps1 -Target CommonTest`, run with `dotnet test` on CommonTest.dll),
  `regress-Stellar.log`, `regress-StellarLibDecoy.log`.
- gate3 aborted in inspectcode with "Internal CLR error (0x80131506)"; an unchanged re-run passed.

### 2026-11-05 - Inspection fix (parent session)
- Skyline code inspection on the PR flagged `DisposeOnUsingVariable` at ProgressReporterTest.cs:179
  (the double-Dispose case disposed a using variable by hand). Fixed by creating that scope without
  `using`; CommonTest builds clean. Core code inspection fails only on NU1903 (ILCompiler advisory),
  which PR #4999 fixes on master; this branch picks it up at its next master merge.
