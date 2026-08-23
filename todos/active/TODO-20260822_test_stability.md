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

**Root cause of the first, traced 2026-08-22.** Two earlier guesses in this file were wrong;
both are kept below so nobody repeats them. The evidence is the full failure block in
`SkylineTester.log` - read it before theorising further.

What actually happens, from the log:

1. The crux tool zip is extracted into the per-test-per-culture tools directory and fails:
   `UnauthorizedAccessException: Access to the path
   '...\Tools_DSDE29_en-US\crux-4.3\...\bin\msvcp140.dll<random>.PendingOverwrite' is denied`,
   thrown from `Ionic.Zip.ZipEntry.ReallyDelete` under
   `SimpleFileDownloader.DownloadRequiredFiles` (`UtilInstall.cs:335`). `.PendingOverwrite` is
   the rename-on-locked-file artifact: some live process has `msvcp140.dll` loaded. Transient
   contention, not a poisoned directory - the en sequence over the night reads
   `pass pass FAIL FAIL FAIL FAIL pass FAIL FAIL pass FAIL ...`
2. Skyline handles that correctly and shows a `MessageDlg`.
3. Nothing dismisses it. `CommonAlertDlg.ShowDialog` (`CommonBaseUI/GUI/CommonAlertDlg.cs:470`)
   in `TestMode` starts a UI timer, runs a NESTED modal loop, and on timeout closes the dialog
   and **throws** `TimeoutException("... not closed for 10 seconds ...")`.
4. That exception is then reported THROUGH THE UI, which shows a second `MessageDlg` carrying
   the timeout text - the log shows the nesting literally, one "not closed for 10 seconds"
   message quoted inside another.
5. The second dialog is also unattended and times out the same way. A throw escaping while the
   error-reporting path is already on the stack is the one case WinForms cannot route, so it
   falls through to the default `ThreadExceptionDialog` - which is what the test framework then
   reports as "ThreadExceptionDialog appeared while waiting for UI action".

**So the defect to fix is step 4, not the locked DLL.** The watchdog's `TimeoutException` must
fail the test directly rather than being reported through UI that can itself time out. Fixing
that converts this whole family from "hang plus a mystery dialog" into the clean failure a
reader expects - "MessageDlg sat unattended, message was ..." - and it applies to every
unattended-dialog failure, not just this test. The locked-DLL contention is a separate, lesser
question worth measuring afterwards.

Verify before changing: which handler shows the second dialog (`ReportExceptionUI` is the
candidate - it displays an alert, and in `TestMode` that alert carries the same watchdog), and
whether `Program.AddTestException` is reached at all on this path.

**Wrong guess 1, kept as a warning.** `RunOnStaThread` was blamed first. It cannot be the
cause: that path only runs when the thread is MTA, which is Visual Studio and ReSharper. The
console harness is STA already, and `RunTests.cs` creates no thread per test, so `Init`'s
once-per-process `ThreadException` subscription stays valid for every test in the process. The
gap was real for IDE runs and is fixed in PR #4605 (`5aa3ae4052`), but it is not this.

**Wrong guess 2, kept as a warning.** `BuildLibraryGridView`'s `BeginInvoke` of
`GridUpdateScoreInfo` was the next suspect, on the theory that a thread ran without the cover
`CommonActionUtil.RunAsync` confers. Plausible in general - and that heuristic is worth keeping
- but the log shows the exception was handled correctly at every step. Nothing here ran
unprotected; the cascade came from the handling itself.

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

- [x] **Start here.** Stop the unattended-dialog watchdog's `TimeoutException` being
      reported through UI that can itself time out (see "Root cause of the first").
      Confirm which handler shows the second dialog, then make `TestMode` fail the test
      directly. Expect this to fix a whole family of hangs, not one test
- [x] Re-measure `TestDdaSearchDependencyErrors` by soak afterwards - before rate was
      27 failures in 45 (60%); a serial pass proves nothing at that rate
- [ ] Then, separately, the locked `msvcp140.dll` contention during crux extraction:
      measure how often it happens and whether the parallel queue's
      `QueuedTestInfo.RequiredToolsDirectories` guard (issue 4447) covers a test that
      runs concurrently in two passes
- [x] Fix `RunOnStaThread` exception routing - done in PR #4605 (`5aa3ae4052`), and note
      it was NOT the cause of the overnight failures
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

### 2026-08-22 - Phase 1 item 1 fixed, and the soak method has a blind spot

Landed on `Skyline/work/20260821_net8_test_reliability` (PR #4605) at the developer's
direction, rather than a new branch off master.

**The fix.** Two files:

* `CommonBaseUI/GUI/CommonAlertDlg.cs` - adds `DialogTimeoutException`, a `TimeoutException`
  subclass meaning "a functional test left this dialog unattended". The distinct type is the
  whole mechanism: it is what lets the display path recognise the failure and refuse to
  re-display it. The watchdog throws it, and `ShowWithTimeout` rethrows it (via
  `ExceptionDispatchInfo`, preserving the original stack) instead of showing a dialog when the
  alert it is asked to display carries one. `Exception` gained a getter; it was set-only,
  discarding the object into `DetailMessage`. The type lives at the end of this file rather
  than in one of its own: it is test-only support code with a single use, sitting next to the
  throw site and the guard that reads it.
* `TestFunctional/UnattendedDialogTimeoutTest.cs` (new) - the permanent verifier.

**Verifier, both directions.** Time a dialog out, then hand the failure back to the UI the way
a catch handler does, and assert the same exception instance comes straight back:

| tree | result | wall clock |
|---|---|---|
| fix shelved (`git stash`) | FAIL on `Assert.AreSame` | **21.1 sec** - two stacked 10-sec timeouts |
| fix applied | PASS | **11.2 sec** - one timeout, immediate rethrow |

The 10-second gap between the two runs is the cascade, measured.

**Two corrections to the root cause above.**

*Step 4 named the wrong handler.* `ReportExceptionUI` cannot be it. Both `ReportException` and
`ThreadExceptionEventHandler` short-circuit to `AddTestException` when `TestExceptions != null`
(`Program.cs:887` and `910`), so under the harness neither ever reaches a dialog. The second
dialog came from an ordinary catch-and-display handler -
`SearchSettingsControl.cs:221`, `MessageDlg.ShowWithException(this, exception.Message, exception)` -
catching the timeout thrown out of the first dialog, which `SimpleFileDownloaderDlg.cs:74`
had shown. So the answer to "is `Program.AddTestException` reached at all on this path": no,
not on the first hop. The cascade runs entirely through catch handlers that display what they
caught, which is why the fix had to go at the display choke point and not in `Program`.

*Step 5 was right about the symptom, vague about the mechanism.* It is not that "WinForms
cannot route a throw while the error-reporting path is on the stack". It is specifically a
**reentrant WndProc**: the second dialog's nested modal loop is inside one, and WinForms
catching an exception there bypasses the `Application.ThreadException` subscription and pops
its own dialog. This is already documented in `HangDetection.cs:131-139`, and `HangDetection`
is also what detects the stray dialog and produces the
"ThreadExceptionDialog appeared while waiting for UI action" text (`HangDetection.cs:192`).

**Coverage.** The guard keys off the exception object, so it covers the 208 call sites that
pass one (`ShowWithException` / `ShowException` / `DisplayOrReportException`). Twelve sites
display `e.Message` without the object; only 3 of those are a broad `catch (Exception)`. Those
3 could still add one dialog layer - bounded, not a cascade. Worth closing later, not now.

**The soak did not measure what it looks like it measured.** `TestDdaSearchDependencyErrors`
after the fix: **0 failures in 100 executions**, 20 per language, 4 workers (1 host + 3 Docker),
git `5aa3ae4052` plus the working tree above.

That number does **not** clear the test, and the reason matters for Phase 3. TestRunner's
parallel queue reserves tools directories: `QueuedTestInfo.RequiredToolsDirectories`
(`TestRunner/Program.cs:1216`) and `TryCheckOutTest` (`:1412`) claim every required directory
all-at-once, so no two workers ever hold `Tools_DSDE29_<culture>` at the same time. The crux
extraction collision therefore **cannot occur** in a soak run this way. A soak of one test
through `parallelmode=server` is structurally blind to tool-directory contention, and 0/100
here is a measurement of a configuration in which the flake is impossible - not evidence about
the flake.

Consequences:

* **Phase 3's ledger needs a harness-configuration column.** "1,000 executions across 5
  languages at production parallel width" is not sufficient to describe a clearance, because
  two harnesses at the same width exercise different contention. Record the runner and mode.
* **The locked-DLL item now has a sharper question.** The queue guard should have prevented
  the overnight collision too. The most likely explanation left is a crux child process
  outliving the test that spawned it, still holding `msvcp140.dll` when the directory is
  released and the next entry extracts over it. That would also explain the clustering
  (`pass pass FAIL FAIL FAIL FAIL pass ...`) better than random contention does. Verify by
  watching for surviving crux processes at test teardown before changing the guard.

**Regression checks.** Solution builds clean (net8, Debug). `CodeInspection` green.
`TestAlertDlg, TestAlertDlgIcons, TestAlertWatch, TestReportErrorDlg, TestDocumentSizeError,
TestLiveReportsError, UpgradeErrorsFunctionalTest, TestDdaSearchDependencyErrors,
TestUnattendedDialogTimeout` across en + ja: 18/18 passed. The guard cannot affect a passing
test - its precondition is that a dialog timeout already happened, which already meant failure -
and no code checks `TimeoutException` by exact type, so the subclass is safe at the 5 existing
`catch (TimeoutException)` sites.

**Not committed.** Working tree only, awaiting review.

### 2026-08-22 - TestWatersConnectExportMethodDlg solved; it was never a timeout

Branch `Skyline/work/20260822_test_stability`, cut from the #4605 branch tip rather than master.
Master is 539 commits behind it and has no `Stage-Net8Tests.ps1`, so the overnight failures are
not reproducible from master at all. The "branch off master" plan in this file assumed #4605 and
#4587 had already merged; rebase when they do.

**The hypothesis in this file was wrong.** "A fixed 2-second `WaitForConditionUI` budget is
marginal at 8-way parallelism" is not what happens. The failure is deterministic, not timing:

| pass in the same process | result |
|---|---|
| first | passes |
| second and after | **always** fails |

No timeout would ever help - the awaited condition cannot become true. The overnight 45% is
simply the share of executions that were not first in their worker process.

**Root cause, proven by instrumenting instance identity.** The improved message (below) said
`Expected 11 items, found 13`, and named the two extra: `NewTestFolder` and `RefreshedFolder` -
folders the test itself creates later in its own run. Logging the test-instance hash at `DoTest`
and inside the mock's folder-listing handler showed why:

| pass | DoTest instance | instance serving folder requests | createdFolders |
|---|---|---|---|
| 2 | 44307394 | 44307394 | 0 -> 1 -> 2 |
| 3 | **50107580** (fresh) | **44307394** (previous test's) | **2** |

`WatersConnectAccount`'s static constructor builds an `IHttpClientFactory` once per process and
calls `HttpMessageHandlerFactory.getMessageHandler` inside
`ConfigurePrimaryHttpMessageHandler`. That resolves the mock **once**, and the factory then pools
the primary handler (two-minute default lifetime, far longer than a test). So
`CreateReplaceHandler` swapped the dictionary entry and changed nothing: every later pass in the
process was still served by the first test instance's mock, carrying the folders that instance
had accumulated.

**Fix** - `CommonUtil/Mock/HttpMessageHandlerFactory.cs`: `getMessageHandler` now returns a proxy
that resolves the registration on every request instead of binding once. A pooled primary handler
can no longer pin one test's state. When nothing is registered the proxy creates the real handler
once and reuses it, so production traffic still goes through a single handler.

| | rate |
|---|---|
| overnight, before | 18 / 40 = 45% |
| local repro, before | ~50% (deterministic from the 2nd pass per process) |
| after | **0 / 100**, 20 per language, 8 workers |

Plus 5/5 consecutive passes in a single process, which is the exact condition that failed.

**Kept:** both `WaitForConditionUI` calls in the test now report the actual count and the item
names. That change alone produced the root cause on the first failing run, after this flake had
gone undiagnosed through a whole overnight suite. It is the clearest case yet for the
"fix the message first" rule.

**Separate systemic finding: the parallel-width wait scaling is dead code.**
`GetWaitCycles` multiplies every timed wait by `Program.UnitTestTimeoutMultiplier`
(`TestFunctional.cs:896`), which is only ever set from TestRunner's `multi` argument - whose
default is `multi=1` (`TestRunner/Program.cs:261`). Nothing passes it: the observed host- and
Docker-worker command lines carry no `multi=`, and SkylineTester never adds one. So every test
runs single-process wait budgets no matter how many processes compete. That answers the
"should UI wait timeouts scale with parallel width" checklist item - the mechanism exists and is
simply unfed - though it is NOT what broke this test.

### 2026-08-22 - TestDdaSearchDependencyErrors narrowed, not yet solved

Hard evidence from the overnight log, replacing guesswork:

* **27 distinct `.PendingOverwrite` artifacts = exactly the 27 failures.** Each has a fresh
  random suffix, so this file confirms the existing note: transient contention, not a poisoned
  directory. The 420 raw matches are one event repeated 16 times by the nested message quoting.
* **Only `Tools_DSDE29_*` appears** - no other test's tools directory is involved, in any culture.
* **`DSDE29` is unique to this test** across all 1,116 tests, so the queue's directory reservation
  fully serialises access and no second test can be in there.
* **The "files it has open may still be locked" warning never fired** (0 occurrences), which rules
  out `ProcessRunner.KillAndWaitForExit` leaving a killed-but-not-exited child holding the DLLs.
* The locked files are the MSVC runtime DLLs - `msvcp140`, `vcruntime140`, `vcruntime140_1`,
  `vcomp140` - which is what any process built against that runtime loads out of `crux-4.3\...\bin`.

**Next step is a diagnostic, not a fix:** when the extraction fails with
`UnauthorizedAccessException`, report **which process holds the file** (Restart Manager,
`RmGetList`) before anything else. Every remaining theory is about the identity of that holder,
and one occurrence with the holder named settles it. This is the same "fix the message first"
move that solved the Waters test in minutes.

Note the soak instrument cannot reach this one: 0 failures in 100 executions locally, because the
queue guard removes exactly the contention being hunted (see the previous entry).

**Side finding - 11 tools-directory name collisions.** `PathEx.GetTestDirectoryName` shortens to
capitals plus length, and these groups share one directory and therefore serialise against each
other in the parallel queue: `TestAddSubfolder`/`TestAccessServer`,
`ConsoleRefineResultsTest`/`ConsoleRemoveResultsTest`, `TestDdaSearch`/`TestDiaSearch`,
`IrtFunctionalTest`/`TestImportFailure`, `TestManageResults`/`TestMetadataRules`,
`TestPeptides`/`TestPanorama`, `TestPeakIntegrator`/`TestPeakImputation`,
`RefineDocumentTest`/`TestReintegrateDlg`, `TestReportSharing`/`TestReportSummary`,
`SpecialFragmentTest`/`TestSubstringFinder`/`ShimadzuFormatsTest`,
`TestShareSettings`/`TestSynchSiblings`. The DS13 case is called out in the code as intended;
the rest are incidental throughput cost.

### 2026-08-22 - PeakAreaDotpGraphTest: message fixed, characterisation pending

Overnight signature is `Assert.AreEqual failed. Expected:<0.93>. Actual:<0.99>.` at
`TestPeakAreaDotpGraph.VerifyDotpLine` line 232 - a dotp value, not a timing failure, and the
assertion carried no message at all: not the replicate, the label, the pane, or the unrounded
value. Added all of those plus the point/label counts, so the next occurrence is diagnosable.
At 2.2% a characterising soak needs ~500 executions; not yet run.

### 2026-08-22 - The parallel harness leaks Docker workers, and that is a lead for item 3

Observed directly, not inferred: a soak reported success and exited 0, and **four
`docker_worker_*` containers were still running three hours later**. They wedged the next run -
its staging step blocked for three hours on files the leaked containers held open through the
`C:\proj\pwiz-work1` -> `c:\pwiz` mount, with no error, just silence.

Confirmed in the code: `TestRunner` has no `docker stop`, `docker kill` or `docker rm` anywhere.
Workers are started with `--rm`, so a container only disappears when its client process exits,
and `waitforworkers` defaults to `off` (`TestRunner/Program.cs:262`) - the server can finish and
report success while clients are still alive.

**Why this matters for `TestDdaSearchDependencyErrors`.** A leaked worker is a live process with
the checkout mounted, and any DLL it loaded out of
`Tools_DSDE29_<culture>\crux-4.3\...\bin` stays locked for as long as it runs. That matches every
piece of evidence at once: a live process holding `msvcp140.dll`; no
`KillAndWaitForExit` warning, because nobody killed it; the clustering
(`pass pass FAIL FAIL FAIL FAIL pass ...`), because one leaked worker spans many later runs; and
the overnight paths being `c:\pwiz\...`, which is the container's view. It is a hypothesis, not a
proven cause - the diagnostic below is what will settle it.

Two things worth doing regardless of whether it turns out to be the cause: stop the workers when
a run ends, and treat a wedged staging step as a symptom of leftovers rather than a hang.

### 2026-08-22 - Diagnostic added so a locked file names its holder

Committed on `Skyline/work/20260822_test_stability`:

* `CommonUtil/SystemUtil/PInvoke/RstrtMgr.cs` - Restart Manager (`RmGetList`) wrapper. Windows
  reports a locked file as nothing but "access to the path is denied"; this answers the question
  that message refuses to.
* `UtilInstall.cs` - the tool unzip path catches `UnauthorizedAccessException`/`IOException` and
  appends the holders, keyed off the `.PendingOverwrite` files the zip library leaves behind,
  which are exactly the files it could not replace. Falls back to rethrowing untouched if the
  diagnostic cannot add anything, so it can never replace the failure it exists to explain.
* `CommonTest/RstrtMgrTest.cs` - verifier. This one earns a test because wrong P/Invoke struct
  marshaling still compiles, still runs, and quietly reports **no holder** for a plainly locked
  file, which is indistinguishable from the good case. Test locks a real file and requires its
  own process to be named.
* `CodeInspectionTest.cs` - registered `RstrtMgr` in the P/Invoke allowlist (4 imports).

The next occurrence in a nightly will name the process. If it is a `docker_worker_*` container or
a stray `crux.exe`, item 3 is settled without another guessing round.

### 2026-08-22 - Correction: the lock-holder helper already existed

The previous entry described a new `RstrtMgr` P/Invoke class. **That was a duplicate and has been
removed.** `CommonUtil/SystemUtil/FileLockingProcessFinder.cs` already wraps the Restart Manager
and is already used by `TestFunctional`, `TestFilesDir` and `RunTests`. It is also better than
what was written to replace it: it pulls the path out of the exception message, resolves it,
distinguishes "locked but since deleted", and never throws.

The real gap was narrower than a missing helper. `ToFileLockingException` only acted on
`IOException` with `ERROR_SHARING_VIOLATION`, which is how a lock surfaces when a file is
**opened**. A lock surfaces as `UnauthorizedAccessException` when the file is **deleted or
replaced** - which is what an overwriting unzip does, and exactly how the crux extraction fails.
So the helper was returning the tool-extraction failure unchanged. It now accepts both.
Access-denied has innocent causes too, but those name no locking process and fall through with the
original exception intact.

Method note worth keeping: the duplicate came from searching for API names (`RmGetList`,
`RestartManager`) and for one guessed helper name, rather than for the CONCEPT. A search for
"GetProcessesUsingFile" or "FileLocking" would have found it immediately. Search the vocabulary a
teammate would have used, not just the vocabulary of the implementation.

### 2026-08-22 - PeakAreaDotpGraphTest characterised

Soak on the new message: **1 failure in 460 executions** (en/fr/ja/tr/zh, 8 workers). Too few for
a rate - the 95% interval spans roughly 0.006% to 1.2%, so this neither confirms nor contradicts
the overnight 1/45. The one failure carries everything needed anyway:

```
idotp line value for replicate '1-A' (label index 1) in pane 0.
Unrounded 0.9881126880645752. Line has 7 points, x axis 7 labels.  Expected 0.93
```

What that rules out: 7 points against 7 labels, index 1 valid, so this is **not** a
label/index misalignment. The value itself is wrong, and 0.988 is a plausible idotp for a
different precursor - not a corrupt number.

Where it comes from (`TestPeakAreaDotpGraph.cs:156-159`):

```csharp
FindNode((873.9438).ToString(LocalizationHelper.CurrentCulture) + "++");
WaitForGraphs();
RunUI(() => VerifyDotpLine(replicates, expectedIDotp, @"idotp"));
```

`FindNode` changes the selected precursor and the graph is expected to follow. Reading a value
that belongs to a different precursor means the graph still held the previous selection when
`WaitForGraphs` returned - so `WaitForGraphs` is not sufficient to know a selection-driven update
has been applied. Next step is to wait on the selection actually reaching the graph rather than on
graph idleness, then re-soak. Not yet fixed.

Note this failure appeared under `tr`, but with n=1 that says nothing about localization.

### 2026-08-23 (night session) - worker leak fixed; method written up

**Docker worker leak - FIXED.** `RunTests.KillParallelWorkers` already existed and worked,
but had exactly one caller: `SetConsoleCtrlHandler`, which fires only on termination from
OUTSIDE. Nothing tore workers down when a run simply finished, so every successful parallel
run leaked its containers, and they then held the mounted checkout open - which is what
wedged a later run's staging step in silence for three hours earlier that day.

Fixed with `RunTests.ParallelWorkerTeardown`, an IDisposable in the socket `using` of
`PushToTestQueue`, so teardown happens on every exit path. It reads the worker names through
a closure because workers are still being launched when the scope opens. Made quiet on the
normal path too: the host worker is killed only if it has not exited, and `docker kill` goes
only to containers still running, so a clean run prints nothing instead of spurious errors.

Verified against the configuration that leaked: 100 executions at 8 workers previously left
4 containers up after exit 0; now `containers after: 0`, 100/100 passing.

**PeakAreaDotpGraphTest - test fixed, PRODUCT DEFECT LEFT ALONE DELIBERATELY.** The chain is
now known exactly: `IsGraphUpdatePending` derives from `_timerGraphs.Enabled`
(`SkylineGraphs.cs:896-909`); the timer tick pops a pane and removes it from the pending list
unconditionally (`:879-880`); but `GraphSummary.UpdateGraph` returns early when
`DocumentUIContainer.Document` and `StateProvider.SelectionDocument` are momentarily out of
sync (`GraphSummary.cs:359-361`). So a pane can leave the queue WITHOUT updating, the timer
stops, and the pending flag goes false while the pane still draws the previous precursor.
A user can see a stale graph this way too.

I did not change graph-update scheduling overnight without review: that guard exists to avoid
drawing inconsistent state, and a naive retry could spin. Recommended direction is to have
the sync-mismatch path re-request an update rather than be dropped. The test now waits on
`pane.ParentGroupNode.TransitionGroup` matching the selection instead of on graph idleness,
at all three FindNode sites. Precedent for distrusting `WaitForGraphs` this way already
exists at `TestFunctional/AreaNormalizeOptionTest.cs:81-86`.

**TestDdaSearchDependencyErrors - mitigated.** Ruled out tonight: the duplicate crux entries
in `CometSearchEngine.FilesToDownload` do NOT double-extract, because `DownloadRequiredFiles`
groups by `Filename` and takes `.First()`. Why only this test hits it: it calls
`CleanupDownloadedFiles`, forcing a real re-extraction every run, over archives carrying the
MSVC runtime DLLs that comet/crux load. Added a bounded retry (4 x 1s) around the extraction
since the lock is transient by construction, falling through to the holder-naming exception.
The holder itself is still unproven; the diagnostic will name it on the next real occurrence.

**Method written up** at `ai/docs/test-flakiness-method.md`: three classes of flake, each
needing a different instrument, and a clearance claim that records the configuration that
produced it or it means nothing. The recommended first sweep is the whole suite at `loop=2`,
serial, one language - it makes every class-1 state leak deterministic for about the cost of
two suite runs, and would have caught the Waters failure with no soak and no statistics.

### 2026-08-23 - candidate list, and a course correction

Static risk ranking checked in at `ai/docs/test-flake-candidates.md`: 7 class-1 files (static
mutable state or `Settings.Default` writes with no restore), 4 class-2 files, and 19 files with
explicit timeouts <= 5s. Standouts: `UpgradeTest` waits 100 ms for a condition and 200 ms for a
dialog; `ChromGraphTransformTest` repeats the selection-then-WaitForGraphs-then-assert shape six
times, which is exactly what made PeakAreaDotpGraphTest flake.

**Course correction from the developer, mid-session**: parallel testing is the focus, and the
serial class-1 sweep was competing for the same machine. It is a complement to the overnight
parallel run, not a substitute, and it costs minutes on 7 named tests - it does not deserve a
night of hardware. Machine handed back.

**Observation worth checking**: two long single-test soaks stalled mid-run (frozen log, workers
still alive) at ~461 and ~385 executions. The first predates tonight's changes, so it is not
something introduced here, and the 2026-08-21 full-suite run plainly did not stall (48,272
executions). May be specific to `loop=N` single-test soaks.

**Note on scale**: the 2026-08-21 overnight run's 46 failures were ENTIRELY these three tests -
27 + 18 + 1 = 46. All three now have fixes on this branch.

### 2026-08-23 - stale staging dependencies: the warning was real signal

The developer hit failures that a Visual Studio Clean + Build Solution fixed. Root cause is
structural, and the evidence was printed on every staging run tonight and ignored:

```
WARNING: TestTutorial output looks stale: TestTutorial.csproj changed 08-21 18:02 but the
newest built assembly is 08-20 12:18. Staging it first so freshly built projects win any
shared file - rebuild TestTutorial if that is not intended.
WARNING: TestPerf output looks stale: ...
```

`Build-Skyline.ps1` builds Skyline, CommonTest, Test, TestData, TestFunctional, TestConnected
and TestRunner. It does NOT build TestTutorial or TestPerf. So whenever those two projects
change, their assemblies rot while everything else is rebuilt, and `Stage-Net8Tests.ps1` then
mixes versions into one staging directory. Staging the stale projects FIRST so fresher output
overwrites shared files is a mitigation that only holds when a fresher copy of every shared
file actually exists.

Consequences:
* a wrapper-script build can produce a staging directory that Visual Studio's Clean + Build
  would not, which is a nasty class of "works in the IDE" difference
* the warning is not noise - it names the exact projects and dates. Treat it as a build error
  in an autonomous session, not a log line to scroll past

Worth deciding: either add TestTutorial and TestPerf to `Build-Skyline.ps1`, or make
`Stage-Net8Tests.ps1` fail rather than warn when a project's output is older than its csproj.
The second is the stronger gate, since it cannot be defeated by adding yet another project.

### 2026-08-23 - the 10,945-execution run, and four fixes from it

**The measurement that matters.** A 105-minute parallel run produced 10,945 executions and
24 failures across just 3 tests. `TestWatersConnectExportMethodDlg` (45% overnight) and
`PeakAreaDotpGraphTest` (2.2%) did not appear at all. Both fixes hold at scale.

| test | rate | status |
|---|---|---|
| TestLibraryBuild | 15/15 = 100% | Debug-only, MascotShim; fixed below |
| TestDdaSearchDependencyErrors | 7/19 = 37% | root cause found; fixed below |
| TestMidas | 2/15 = 13% | diagnosed, not fixed |

Excluding the Debug-only breakage that is ~0.08% against 0.095% on 08-21, with the two worst
offenders eliminated.

**Every failure now reports a legible cause.** The watchdog change earned itself on a test
nobody touched: TestMidas surfaced as
`DialogTimeoutException: MessageDlg not closed ... FileModifiedException` instead of a
ThreadExceptionDialog. That is the whole point of fixing the message first.

**TestDdaSearchDependencyErrors - actual root cause, after two wrong theories.**
Wrong theory 1: a lingering killed process. Ruled out - the "may still be locked" warning
never fired. Wrong theory 2: the queue reserving a differently-named directory. Ruled out by
the data - the four cultures that FAILED (en-US, fr-FR, ja, tr-TR) are the ones whose names
match, and zh, the only one that diverges, did not fail.

What actually happens: overwriting renames the existing file aside and deletes it, and Windows
lets a DLL some process has LOADED be renamed but never deleted. A tool process launched out of
that directory - crux or comet, which load their neighbours - makes the delete fail. Restart
Manager reported no holder because it reports processes holding HANDLES, not DLLs mapped as
images, and cannot see into another worker's container at all.

The archive is version-pinned, so those DLLs are byte-identical every run and never needed
replacing. Extraction now skips any entry whose destination already matches the archive's size,
which removes the collision instead of racing it.

**Separate real bug found on the way:** .NET silently normalizes deprecated culture names, so a
queued `zh-CHS` becomes `zh-Hans`. The queue reserved `Tools_DSDE29_zh-CHS` while the test wrote
`Tools_DSDE29_zh-Hans` - both spellings were sitting in the staging directory. Chinese runs of
any tool-using test had no protection at all. The reservation now uses the resolved name, still
falling back to the raw string for a name CultureInfo rejects.

**TestLibraryBuild - Debug-only, and pre-existing.** `MascotShim.dll` is built per configuration
but imports msparser by name, while Debug shipped only `msparserD.dll`, so the import could not
resolve: `Unable to load DLL 'MascotShim' or one of its dependencies (0x8007007E)`, 100% of the
time. Never seen before because the harness always ran Release staging - a bug the
configuration-preference fix exposed rather than caused.

Per the developer, msparserD is dropped. NOT by pointing a Debug shim at release msparser, which
is the mirror of the mismatch the CMakeLists records as having "silently corrupted std::string".
Instead MascotShim is pinned to the release CRT and release msparser in EVERY configuration.
That is safe only because `MascotShim.h` is a pure `extern "C"` surface - const char*,
caller-supplied buffers, callbacks - so nothing STL or heap-owned crosses to the caller and a
/MDd BiblioSpec can call a /MD shim. The Jam rules are deliberately left alone: pwiz's own C++
calls msparser's C++ API directly, with no such boundary, and there the pairing is real.

**TestMidas - diagnosed only.** `FileModifiedException` in `PooledFileStream.Connect()`: a .skyd
chromatogram cache changed while a pooled stream held it open. 2 in 15. Good candidate for the
targeted soak now that it fails legibly.

### 2026-08-23 - the day's real lesson: the build/test handoff

Four separate defects, all with the same symptom - code that was fixed appeared to keep failing:

1. SkylineTester preferred Release staging whenever it existed, so a Debug build ran stale
   Release binaries. Fixed; it now prefers its own configuration.
2. A Visual Studio build never reached the tests at all, because only the staging script copies
   into the staged directory. Fixed; staging now runs at test launch.
3. `Build-Skyline.ps1 -Target Solution` builds 7 projects while staging stages 9, so TestTutorial
   and TestPerf were permanently stale. Not yet fixed - the two lists should be one list.
4. Staging itself shelled out to PowerShell, which brought ANSI escape codes into the log,
   robocopy retrying a locked file a million times at 30-second intervals, and a pipe-read
   deadlock that froze the UI. Rewritten in C# in TestRunnerLib: one implementation,about 1 second,
   fails immediately naming the process holding a file, and serialized on a machine-wide lock
   because two concurrent stagings block each other.

The through-line: nothing told anyone which binaries were actually running. Every one of these
was invisible until someone compared timestamps by hand.
