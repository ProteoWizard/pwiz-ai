# Clear the three tests still failing intermittently on master

## Branch Information
- **Checkout**: TBD - `C:\proj\daily` has the built master and the archived logs
- **Branch**: not created yet; branch off `master` at or after `79e50e83a6`
- **Base**: `master`
- **Created**: 2026-08-26
- **Status**: Not started
- **Module**: `skyline`
- **PR**: (pending)
- **Related**: `todos/completed/TODO-20260822_test_stability.md` (PR #4610, the work that
  cleared everything else), [#4614](https://github.com/ProteoWizard/pwiz/issues/4614)

## Why

Two full-suite overnight runs on master now agree on which tests are left, and they are cheap
to reproduce. Nothing here is a soak problem - every rate is around one in ten, so each of
these reproduces in tens of executions rather than thousands. That is a different job from
`TestMultiInjectRescore` or `TestMultiInjectionReplicates` and should not be worked the same way.

## Measured

| Test | 2026-08-25 (Debug) | 2026-08-26 (Release) |
|---|---|---|
| `PeakAreaDotpGraphTest` | 3 / 32 = 9.4% | 6 / 67 = 9.0% |
| `ConsoleMethodTest` | 3 / 30 = 10% | 7 / 70 = 10% |
| `ConsoleImportNonSRMFile` | 1 / 30 = 3.3% | 0 / 70 |
| run totals | 7 failures / 26,012 executions, 8.5 h | 13 failures / ~43,793 executions, 9 h |

Both runs were the full suite (TestData, TestFunctional, TestTutorial) at 8 workers across 5
languages. The 08-26 run was a **Release** build, taken so these runs can be compared against
the .NET 8.0 branch for performance.

The two surviving tests fail at **the same rate in Debug and in Release**, which says these are
not timing artifacts of one configuration. Either build is a valid baseline.

**Logs, preserved** (the next run overwrites the originals):

```
D:\test\nightly-logs\SkylineTester-20260826-0553.log     <- complete record, 13 failures
D:\test\nightly-logs\TestRunner-20260826-0553-Release.log <- captured only 12; missed the last
D:\test\nightly-logs\SkylineTester-20260825-0620.log
D:\test\nightly-logs\TestRunner-20260825-0620.log
```

Note the discrepancy: `TestRunner.log` dropped the final failure of the 08-26 run (05:43, near
the end). **Count failures from the SkylineTester log**, not the TestRunner log.

## The three

### 1. `PeakAreaDotpGraphTest` - 9% and expensive, do this one first

```
Timeout 720 seconds exceeded in WaitForConditionUI (Peak area pane 0 did not catch up to the
selected precursor.). Open forms: SkylineWindow (Skyline - DIA-QE-tutorial.sky), ...
```

**Cut the wait before investigating.** At ~788 s per occurrence and 6 occurrences, this one test
spent about **79 minutes** of the 9-hour run inside its own timeout. That is wall clock off every
future comparison run, and it dominates the cycle time of any attempt to reproduce it. The import
it waits on takes seconds when it works. Same change as `TestMultiInjectionReplicates` got.

**The thread dump from PR #4610 already fired on this and is informative.** On the 08-25 failure
the UI thread was parked in `WaitMessage` inside `Application.RunMessageLoop` - *idle, waiting for
messages*, not stuck doing work - and no other thread was in Skyline code. So the pane update was
never triggered or never posted, rather than being slow or deadlocked. That narrows it from "the
graph is slow" to "the notification that should have updated pane 0 did not arrive."

Characterised once already on 2026-08-22; see the completed TODO. This is a recurrence, not a
discovery.

### 2. `ConsoleMethodTest` - 10%, and the holder is us

```
CleanupFiles failed:
Directory.Move("c:\AlwaysUpCLT\TestResults_5\CommandLineTest", "...") failed, attempt to delete
instead resulted in "The process cannot access the file '~SK712A.tmp' because it is being used
by another process." (c:\AlwaysUpCLT\TestResults_5\CommandLineTest\~SK712A.tmp is locked by
<the test host process>)
```

Identical shape both nights, different temp file (`~SKD0BE.tmp` on 08-25) and different parallel
client (2 then 5), so it is not worker-specific.

**The lock-holder naming added in #4610 already answered the first question**: the holder is the
test host process itself, not an external scanner and not a leftover Skyline. So this is a handle
the test or the code under test left open on its own file. `~SK*.tmp` is a Skyline save-temp name,
which points at the document-save path rather than the results cache.

Next step is to find which save leaves the handle open - instrument `FileSaver`/`FileStreamManager`
on the `CommandLineTest` path rather than guessing.

### 3. `ConsoleImportNonSRMFile` - the one worth the most

```
No error reported but exit status was 2.
```

**Brendan has looked into this one himself; it is a longtime thorn.** It did not recur last night,
but 0/70 is consistent with its 3.3% rate (about a 9% chance of seeing none), so it is quiet, not
fixed. Fixing it would be a real step for test stability.

From the 08-25 occurrence: the command's output ends with **warnings only** - no `Error:` line -
yet the command-line Skyline exited 2. Every warning is EXPECTED by the test: `bad_file.raw` is
deliberately corrupt (`[RawFileImpl::ctor()] Corrupt RAW file`) and `FullScan_folder\FullScan.RAW`
deliberately has no SRM/MRM chromatograms (`NoFullScanFilteringException`), both reported as
`Warning: Failed importing ... Ignoring...`. The run reached `100% - Updating peak statistics`.

So on 1 run in 30 the exit status disagreed with the output, while the same warnings are produced
every run. Either a warning is intermittently escalated to an error exit code, or an error occurred
after the last printed line and never reached the output.

**Fix the message first.** The assertion cannot say which of those it is, and at 3% the next
occurrence is expensive to wait for. Make the failure report what the exit code was derived from -
which `CommandStatusWriter`/error-count path set it - before chasing the cause.

## Plan

- [ ] **1. Cut `PeakAreaDotpGraphTest`'s 720 s wait** to something proportionate, so the test
      fails in seconds and the suite stops paying 13 minutes per occurrence.
- [ ] **2. Reproduce each in isolation** and record the per-execution rate at that scale. Tens of
      executions, not thousands. Do NOT soak these.
- [ ] **3. `ConsoleImportNonSRMFile`: make the exit-status failure self-explaining**, then get one
      occurrence with the better message.
- [x] **4. `ConsoleMethodTest`: find the unclosed handle** on the save-temp, on the
      `CommandLineTest` path.
- [ ] **5. `PeakAreaDotpGraphTest`: find why the pane update never arrives**, starting from the
      idle-UI-thread evidence above rather than from graph timing.
- [ ] **6. Write the permanent verifier for each** before calling it fixed, per the debugging
      skill: a test that fails on the current code and passes after.
- [ ] **7. Re-run the full suite** and confirm the rates went to zero rather than got quieter.

## Watch for

- **Rates are per-execution, not per-run.** A test that runs 70 times in a 9-hour suite and fails
  7 times is a 10% test, not "7 failures". The denominator decides whether something looks
  hopeless or trivially reproducible.
- **A quiet run is not a fix.** `ConsoleImportNonSRMFile` at 0/70 proves nothing at a 3% rate.
  Only a rate measured at scale after a change means anything.
- **Verify the negative, not the intent.** The lesson from #4610: check that the thing you did not
  intend to change still works, not only that the change did what you meant. Two verifications
  there passed while proving nothing - one against a stale binary, one against a condition that
  was true either way.

---

## Postscript 2026-08-27: the net8 line changes two of these three

Pooled across all three net8 runs of 2026-08-26/27 (same machine, same suite, 8 workers),
against the net472 9-hour baseline:

| Test | net8 | net472 |
|---|---|---|
| `ConsoleMethodTest` | **0 / 90 (0%)** | 7 / 70 (10.0%) |
| `PeakAreaDotpGraphTest` | **1 / 90 (1.1%)** | 6 / 67 (9.0%) |
| `ConsoleImportNonSRMFile` | 0 / 90 | 0 / 70 |
| `TestAuditLogTutorial` | **2 / 75 (2.7%)** | 0 / 65 |

`ConsoleMethodTest` at 0/90 against a 10% baseline has probability 0.9^90 = 0.008%. That is
not luck - something in the port fixed it. `PeakAreaDotpGraphTest` is reduced roughly
eight-fold rather than eliminated.

Two consequences for this TODO:

1. **Fix these on master anyway.** The net8 port is not the delivery vehicle for master's
   nightly, and master will be the release branch until #4619 merges.
2. **Find out WHAT fixed them before assuming it holds.** A flake that vanishes without a
   named cause can come back. Whatever the port changed - the WinForms SystemEvents hook
   rework, the unattended-dialog timeout handling, or the STA thread exception routing, all
   touched during the port - is worth identifying and considering for master directly. That
   is likely cheaper than debugging the flakes from scratch.

New on the net8 line, not present on master:

- `TestAuditLogTutorial` - **root cause found and fixed 2026-08-27.** A stale databound
  grid row, not audit-log ordering and not a document race. Rate 7 / 1,695 executions
  (0.41%), in en/fr/tr/zh/ja - the earlier "Japanese only, ~18%" reading here was wrong,
  drawn from 3 failures that happened to land in `ja` out of 17 (a 4% coincidence).

  The test sets the Reason on audit log grid rows 0-3 to mark the four excluded standards.
  The grid is filled by a background query, so after the four exclusions its rows can still
  describe the document as it was before them. A row holds the `AuditLogEntry` it was built
  from (`AuditLogRow._entry`) and writes the Reason back to that entry **by `LogIndex`**
  (`AuditLogRow.ChangeEntry`), so a stale row 0 puts the reason on the peak-bounds entry
  instead of the `Standard_8` exclusion. That predicts the signature exactly: line 128 is the
  *first* of the four "Reason Changed" entries, and the actual text is precisely the entry
  that sat at row 0 before the exclusions. Nothing sorts by localized text, hence all
  languages.

  Two earlier attempts missed it because both waited on the *document*, never the grid:
  PR #4610 wrapped the peak-bounds change in `WaitDocumentChange`; the follow-up split the
  four-row loop so each row was its own waited document change. The failure happens on
  iteration 0, before either wait exists. The follow-up's stated premise - that setting a
  Reason "re-sorts the grid" - is also false; instrumented runs show rows 0-3 hold the same
  `LogIndex` before and after each reason edit.

  Fix: wait for each row to actually hold the entry it is meant to edit, and name the entry
  found there if it never does, so a recurrence fails immediately instead of surfacing as an
  opaque audit-log text diff 100 lines later. `AuditLogTutorialTest` was the only audit-log
  test touching the grid without such a wait - `AuditLogTest.cs` and `AuditLogSavingTest.cs`
  call `AuditLogUtil.WaitForAuditLogForm` before every grid access, 12 call sites.

  Verified: 2,500 executions (8 workers, all 5 languages, 94 min), 0 failures. At the
  pre-fix rate that predicts ~10.3 failures; P(0 | unfixed) = 0.003%.

### Two traps found while verifying this

Both would have produced a false "verified" and are worth knowing before the next soak:

- **`Run-Tests.ps1 -Loop 0` runs ONCE, it does not run forever.** Line 570 prints
  `Loop: Forever`, line 655 does `$loopValue = if ($Loop -gt 0) { $Loop } else { 1 }` and
  passes `loop=1`. A soak invoked that way exits in 46 s reporting `All tests PASSED`. Pass
  an explicit count.
- **Test console output is discarded in parallel mode** - in the aggregate log *and* in
  SkylineTester's log. `found audit log`, printed by every tutorial execution, appears 0
  times in both. Any `Console.WriteLine` diagnostic is invisible under `-ParallelWorkers`;
  route it to a file beside the test assembly (the Docker workers mount the checkout, so the
  writes land on the host).

## Progress Log

### 2026-08-27 - PR #4623 merged; ConsoleMethodTest root cause found

PR [#4623](https://github.com/ProteoWizard/pwiz/pull/4623) merged as `baac9d4a07`. It carried the
worker-loss reporting work and the `TestAuditLogTutorial` fix. **This TODO is not complete** - it
covers three tests and only one is closed.

- **`TestAuditLogTutorial` - fixed and shipped.** A stale databound grid row, not audit-log
  ordering and not a document race, in all languages rather than Japanese only. See the corrected
  postscript above. Verified over 3,650 executions with 0 failures against ~15 predicted, plus 9
  recorded activations of the new wait, every one on row 0 and exactly 4 LogIndex behind.

- **`ConsoleMethodTest` - root cause found, fix verified, NOT yet merged.** `CommandLine.Dispose()`
  closes the `CommandStatusWriter` and nulls its `_writer`, while `MultiFileLoader` threads can
  still be importing. The next progress line throws `NullReferenceException`, which escapes
  `BuildCache`; `ChromatogramCache.Build`'s catch calls the `complete` *callback* rather than the
  builder's `Complete()`, so the builder's four `FileSaver`s - three holding open `FileStream`s -
  are never disposed and the `~SK*.tmp` stays locked for the life of the process. Three fixes
  (dispose the builder on any throw; make the writer null-safe; make `ChromCacheWriter`'s
  constructor exception-safe), plus `FileSaver` undisposed-tracking folded into the existing
  `FileStreamManager.StartTrackingHistory` switch so `CleanupFiles` names the leaker instead of
  only reporting a locked file. 300 executions, 0 failures. **Stashed** in `C:\proj\daily` as
  `stash@{0}`, headed for its own PR - three of the five files are product code.

- **`ConsoleImportNonSRMFile` - narrowed, not fixed.** Only 1 failure in ~215 local executions, so
  the 3.3% here is one event. The full output shows the fourth warning arriving *after*
  `100% - Updating peak statistics`, so it is an out-of-order completion, not an escalated warning.
  `ImportDataFiles` waits ~2 s for a final status and then falls through with a non-final one, and
  two `return false` paths (`CommandLine.cs:2051`, `CommandLine.cs:2094`) write nothing to `_out`,
  which is why the exit status disagrees with the output. Item 3 above is still the right next step.

- `PeakAreaDotpGraphTest` untouched at that point; fixed the next day, see below.

### 2026-08-28 - ConsoleMethodTest fixed and merged (#4626)

PR [#4626](https://github.com/ProteoWizard/pwiz/pull/4626) merged as `0e99111bfa`. Two of this
TODO's three tests are now closed.

- **`ConsoleMethodTest` - fixed.** `CommandLine.Dispose()` closes the `CommandStatusWriter` and
  nulls `_writer` while `MultiFileLoader` threads may still be importing. The next progress line
  threw `NullReferenceException`, which escaped `BuildCache`; `ChromatogramCache.Build`'s catch
  calls the `complete` *callback*, not the builder's `Complete()`, so the builder's four
  `FileSaver`s - three with open `FileStream`s - were never disposed and their `~SK*.tmp` stayed
  locked for the life of the process. Three fixes plus `FileSaver` undisposed-tracking folded into
  the existing `FileStreamManager.StartTrackingHistory` switch. Verified 300 executions / 0
  failures locally, then **0 / 55 in the 2026-08-28 net472 nightly against a 7 / 70 baseline**.

- **`PeakAreaDotpGraphTest` - fixed, awaiting merge in [#4628](https://github.com/ProteoWizard/pwiz/pull/4628).**
  Not a graph-timing problem at all: `ShowSplitChromatogramGraph` was called straight from the test
  thread, so the WinForms graph timer was started off the UI thread where its `WM_TIMER` is never
  dispatched - `Enabled` true forever, queue never drained, UI idle. One missing `RunUI`. 213
  executions / 0 failures against 13 / 305 (4.3%) on the same configuration.

- **`ConsoleImportNonSRMFile` - still open.** See the 2026-08-27 entry; item 3 remains the next step.

### Two notes for whoever picks this up

- **`TestRunner` throttles workers to tests x languages.** A single test reaches only 5 workers, not
  8, so "reproduce in isolation" (item 2 above) silently changes the load as well as the neighbours.
  Always run at least two tests to get nightly-like load.
- **CodeQL on this repo cannot be read as a merge gate.** #4626 was failed by two alerts on a line
  it merely moved; one is present on master already, and the other traces `PanoramaUserEmail` from
  AutoQC, a separate executable with no reference path to the flagged code. Analysis runs with
  `build-mode: none`, so cross-application flows get over-approximated. Merged with `--admin`.
