# Test stability: fix the known flakes, then clear tests methodically

## Branch Information
- **Checkout**: `C:\proj\pwiz-work1` (the team's Integration checkout)
- **Module**: `skyline`
- **Intended for**: autonomous sessions, long soaks, minimal supervision

### Which branch - read this before starting

`RunOnStaThread` exception routing was fixed in PR #4605 on 2026-08-22 (commit `5aa3ae4052`).
It is a real defect in code that branch introduced, but note the correction below: it does
NOT explain the overnight failures. Everything in this TODO starts on a **new branch off
master** once #4605 and #4587 merge; nothing here should gate that PR.

## Why

The 2026-08-21 overnight run is the baseline: **48,272 executions across 1,116 distinct
tests**, 8 parallel threads, all 5 languages, started 21:54. It found **46 failures - about
0.095%, or 1 in 1,050 executions**.

That run is also the argument for a different method. A whole-suite overnight pass is an
expensive and coarse instrument: a test that fails 2% of the time appears once in ~50
executions, so the suite finds it by luck, and cannot prove it fixed. The goal here is to
stop needing the all-night run to discover what a targeted soak can find in minutes.

## Phase 1 - the three failures this run actually found

Start here. Rates, not counts, from `SkylineTester.log`:

| test | ran | failed | rate | signature |
|---|---|---|---|---|
| `TestDdaSearchDependencyErrors` | 45 | 27 | **60%** | `ThreadExceptionDialog appeared while waiting for UI action` |
| `TestWatersConnectExportMethodDlg` | 40 | 18 | **45%** | `Timeout 2 seconds exceeded in WaitForConditionUI (Template selection dialog is not populated)` |
| `PeakAreaDotpGraphTest` | 45 | 1 | 2.2% | rare - needs Phase 2 to characterise |

All three fail evenly across en/fr/ja/tr, so none is a localization bug.

**Hypothesis for the first - CORRECTED 2026-08-22.** An earlier draft of this TODO blamed
`RunOnStaThread`. That was wrong and the reasoning is worth keeping so nobody repeats it:
`RunOnStaThread` only runs when the current thread is MTA, which is Visual Studio and
ReSharper. The console harness is STA already and never enters it, and `RunTests.cs` creates
no thread per test, so `Program.Init`'s once-per-process `Application.ThreadException`
subscription stays valid for every test in a harness process. The overnight run used the
harness. The `RunOnStaThread` gap was still real and is fixed in #4605, but it is not this.

The live hypothesis instead, from Brendan: **a `ThreadExceptionDialog` means some thread ran
unprotected by the handling `CommonActionUtil` confers.** `CommonActionUtil.RunAsync` runs the
action through `RunNow`, which try/catches and routes to `ExceptionReporter` (set by
`Program.Init` to `ReportException`, which feeds `TestExceptions` under a harness). A raw
`new Thread(...)`, a `Task.Run`, or a `BeginInvoke`d callback that throws has no such cover.

First place to look: `BuildLibraryGridView.cs:154` starts a tracked raw thread whose body is
carefully guarded, but which ends by `BeginInvoke`ing `GridUpdateScoreInfo(scoreTypes,
getScoreTypesException)` onto the UI thread. An exception thrown inside that callback surfaces
in the message loop rather than in the guarded body. `TestDdaSearchDependencyErrors` exists to
provoke dependency errors, so it is the test most likely to drive that callback down its error
path - which fits a 60% rate under load and a clean pass when run serially.

Confirm by soak before fixing, and get a before rate: it passed first try serially here, which
at 60% means nothing.

**Hypothesis for the second.** A fixed 2-second `WaitForConditionUI` budget is marginal at
8-way parallelism. Check whether the timeout scales with parallel width anywhere; if not,
that is a systemic issue worth solving once rather than per test.

## Phase 2 - the soak method

Proven on the net8 branch: soak ONE test across 5 languages in parallel containers with
`loop=0` - roughly 500 executions in a few minutes. It turned a flake that six full runs
could not reproduce into a root cause in about ten minutes. Two rules made it pay:

1. **Measure the rate before theorising, in EXECUTIONS not runs.** The Refine flake looked
   like "1 in 6 runs" (rare, hopeless) but was ~6% of executions (very tractable).
2. **When a failure message carries no information, fix the message first.** Both root causes
   on that branch fell out of the FIRST occurrence after the diagnostic existed. Before that,
   years of occurrences had been discarded as undiagnosable.

Template: `ai/.tmp/run-refine-soak.ps1` from the prior session (recreate under
`ai/scripts/Skyline/` if it is worth keeping - it is a runner, not a session artifact).

## Phase 3 - clearance, so a test can be pronounced low-risk

The point of the exercise: stop re-testing everything all night. Use the **rule of three** -
zero failures in N executions gives 95% confidence the true failure rate is below `3/N`:

| executions, 0 failures | clears a rate above |
|---|---|
| 300 | 1% |
| 1,000 | 0.3% |
| 3,000 | 0.1% |

Suggested bar: **1,000 clean executions spread across all 5 languages at production parallel
width** clears a test to "< 0.3%", which is well under the 0.095% aggregate the suite shows
today. Record each clearance in a checked-in ledger - test name, date, executions, languages,
parallel width, git sha of what was tested - so it survives sessions and so a later reader can
tell what the claim was based on. Re-clear when the test or the code under it changes.

The ledger is the deliverable that makes the next overnight run optional rather than
mandatory.

## Phase 4 - walking the suites

Order: `TestFunctional` first (largest and most UI-timing-sensitive), then `TestTutorial`,
then `TestPerf` once the method is cheap enough.

**Do not walk alphabetically.** Seed the priority from data that already exists:

* `mcp__labkey__query_test_history` holds years of nightly results - tests with historical
  intermittent failures are the ones to soak first
* tests that use `WaitForConditionUI`, `WaitForCondition` or explicit timeouts are the
  UI-timing-sensitive population
* tests never observed failing anywhere are the lowest priority and can be cleared in bulk

## Gotchas that cost time on the previous branch

* **Build, then stage, then test.** `Run-Tests.ps1` executes from `bin\staging-net8\Debug`, so
  a test runs STAGED binaries. A `CodeInspection` run silently tested pre-change code until
  the tree was re-staged. `Stage-Net8Tests.ps1` now stages stale projects first so freshly
  built output wins a shared file, but it still cannot stage what was never built.
* **`SKYLINE_FORCE_SYSEVENTS_LEAK` produced no output** through `Run-Tests.ps1` in either
  `hook` or `real` mode on 2026-08-22, though the variable reaches pwsh correctly. The GC-LEAK
  truth table is unverified since. Repair this before trusting changes in that area - a
  verifier that silently does nothing is worse than none.
* **The GC-LEAK classification does work in production**: the overnight run hit the framework
  `SystemEvents` condition 3 times in 48,272 executions and warned rather than failed each
  time.
* **Denominators or it did not happen.** Report every flake as failures over executions.

## Task checklist

- [ ] Fix `RunOnStaThread` exception routing; re-measure `TestDdaSearchDependencyErrors` rate
- [ ] Decide whether UI wait timeouts should scale with parallel width; fix
      `TestWatersConnectExportMethodDlg` accordingly
- [ ] Characterise `PeakAreaDotpGraphTest` by soak
- [ ] Recreate the soak runner under `ai/scripts/Skyline/` with a documented interface
- [ ] Define the clearance ledger format and check it in
- [ ] Clear the first batch of `TestFunctional` tests, prioritised from LabKey history
- [ ] Repair `SKYLINE_FORCE_SYSEVENTS_LEAK`

## Progress Log

### 2026-08-22 - Created
Seeded from the 2026-08-21 overnight run and from the `/code-review max` findings on PR #4605
that were not fixed there. The seven outstanding review findings are listed in
TODO-20260821_net8_test_reliability.md; the `RunOnStaThread` one is Phase 1 here because the
overnight run supplies its evidence.
