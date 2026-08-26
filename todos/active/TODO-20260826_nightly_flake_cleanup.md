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
- [ ] **4. `ConsoleMethodTest`: find the unclosed handle** on the save-temp, on the
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
