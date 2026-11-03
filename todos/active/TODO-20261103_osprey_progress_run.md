# TODO-20261103_osprey_progress_run.md

## Branch Information
- **Branch**: `Skyline/work/20261103_osprey_progress_run`
- **Base**: `master`
- **Created**: 2026-11-03
- **Status**: In Progress
- **GitHub Issue**: [#4979](https://github.com/ProteoWizard/pwiz/issues/4979)
- **Module**: `osprey`
- **PR**: (pending)
- **Worktree**: `C:\proj\wt-progress` (night-session agent worktree, round 2 wave A)

## Objective

Replace the `using (var progress = new ProgressReporter(...)) { ...; progress.Complete(); }`
scopes in Osprey and CarafeSharp with execute-around wrappers, so completion is decided by how
the body ended and a forgotten `Complete()` cannot be written. Pure refactor: log output
identical (Stellar golden; `ProgressReporterTest` / `MultiProgressReporterTest`).

## Design (as built)

- `ProgressReporter.Run(activity, total, Action<ProgressReporter> body, indent, interval, ...)`
  and `Run<T>(..., Func<ProgressReporter, T> body, ...)`: construct, run body, `Complete()`
  when the body returns (early return included), dispose in a `finally` (the `using`). No catch.
- `ProgressReporter.TryRun(..., Func<ProgressReporter, bool> body, ...)`: added because six
  sites end a soft failure (log the error, set ExitCode, return false/null) WITHOUT throwing and
  deliberately skip `Complete()` on that path (`if (error == null) progress.Complete();`).
  `Run` would print 100% on those failure paths; `TryRun` completes only when the body returns
  true. Sites: FirstPassFdrTask x3, PeakCoAssignmentSource x2, PerFileScoringTask (rehydrate).
- `PercolatorQValues.QRun` / `QRun<T>`: the "reporter or null by population size" helper, on
  top of `Run`. `QProgress` kept for the one PercolatorScorer caller (off-limits this round).
- Body shapes that a lambda cannot hold: `out` parameters captured (SecondPassFdrTask
  CollectPassingEntries - local alias `bestMap`); out locals assigned in the body (PercolatorQValues
  competitions, Pass2FdrSidecar `competition`) - returned through `Run<T>` as tuples/values.
- `DiannTsvLoader`: the read reporter used to be completed mid-method inside `ParseReader`;
  split into `ReadRows` (phase 1, inside the read `Run`) and `BuildEntries` (phase 2), so the
  read completes at the same point in the log as before.
- `ParquetScoreCache.StreamReconciledScoresParquet`: optional reporter (null indent = silent)
  -> local function `WriteRows(ProgressReporter)` called directly or through `Run`.

## Not converted (and why)

- `PercolatorEngine.cs` (5 sites) and `PercolatorScorer.cs` (2 sites): owned by Brendan's open
  PRs this round; left on explicit `Complete()`. Convert after those PRs merge.
- `PipelineByproducts.StreamSourcedFiles`: an iterator that `yield return`s inside the scope; a
  lambda cannot yield. Stays on the constructor + explicit `Complete()`.
- Constructor and `Complete()` stay PUBLIC: the sites above still need them (Percolator files
  are in Osprey.FDR, a different assembly from CommonUtil). Making them non-public is the
  follow-up once Percolator is converted; the iterator site would then need its own answer
  (e.g. a small explicit-scope API in CommonUtil, or restructuring the iterator).

## Tasks

- [x] Add Run / Run<T> / TryRun to `pwiz_tools/Shared/CommonUtil/SystemUtil/ProgressReporter.cs`
- [x] Convert Osprey + CarafeSharp scopes (all but the sites listed above)
- [x] Move ProgressReporterTest / MultiProgressReporterTest onto the wrappers; add early-return,
      Run<T> value and TryRun cases
- [x] Osprey gate: Build-Osprey -RunTests -RunInspection - 649/649, inspection zero
      (`ai/.tmp/sessions/20261103-agentA/gate2.log`)
- [x] CarafeSharp Debug build + tests - 116/116 (`.../carafe1.log`)
- [x] Skyline CommonTest: ProgressReporterTest, MultiProgressReporterTest - 2/2 passed. Built with
      `Build-Skyline.ps1 -Target CommonTest`; Run-Tests.ps1 needs TestRunner (full solution), so
      run with `dotnet test` on the built CommonTest.dll (`.../skyline-commontest-dotnettest.log`).
      Skyline CI runs both on the PR.
- [x] regression.ps1 -Dataset Stellar - PASSED before review fixes (`.../regress-stellar-item1.log`);
      re-run on the final code PASSED too (`.../regress-stellar-item1b.log`)
- [x] /code-review medium, triage (below)
- [ ] PR

## Code review (/code-review medium, 2026-11-03)

No correctness bugs found. Seven findings, triaged:
- FIXED: `Run<bool>` has TryRun's shape, so a mis-picked overload would declare a failed step
  complete. `Run<T>` now throws for `T == bool` (tested in ProgressReporterTest).
- FIXED: constructor doc said "becomes non-public" once Percolator is converted, ignoring the
  iterator site in another assembly. Reworded.
- FIXED: class doc said a lambda cannot "use" a ref local / Span; it cannot CAPTURE one. Reworded.
- FIXED: Run / Run<T> / TryRun repeated the construct-body-Complete block; Run and Run<T> now
  delegate to TryRun.
- FIXED: QRun(Action) now delegates to QRun<T>.
- FIXED: MultiProgressReporterTest.ValidateInertWhenNoScope reverted to direct construction - it
  pins the construct/Report/Dispose path the unconverted sites still use.
- DROPPED: captured locals in hot loops (DiannTsvLoader phase 2, LibraryDeduplicator,
  PercolatorQValues per-run loops) now live in a closure. Each iteration is dominated by
  dictionary lookups / allocations, not by the local's load. Not worth splitting every body into
  a helper method; no perf A/B was run (Test-PerfGate.ps1 is the check if Brendan wants one).

## Progress Log

### 2026-11-03 - Session 1 (night agent A)
- Converted 41 sites, added TryRun after finding the seven soft-failure paths. Debug build green.
