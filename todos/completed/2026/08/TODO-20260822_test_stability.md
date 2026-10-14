# Test stability: fix the known flakes, then clear tests methodically

## Branch Information
- **Checkout**: `C:\proj\pwiz-work1` (the team's Integration checkout)
- **Module**: `skyline`
- **Status**: Completed
- **PR**: [#4610](https://github.com/ProteoWizard/pwiz/pull/4610) (merged 2026-08-26 as `79e50e83a6`)
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

### 2026-08-24 - session end: one failure left, and the question to answer next

Last measured run: 8,000 executions in 80 minutes, ONE failure (TestMidas). For comparison the
2026-08-21 baseline was 46 failures in 48,272. TestAuditLogTutorial is gone after the ordering
fix; Waters, dotp, DDA extraction and the Debug library build all stayed clean.

**The goal to hold the next session to**: parallel testing that survives a full night. The bar is
what SkylineNightly already achieves SERIALLY - about 20 sessions of 9-12 hours with nothing
failing. Nobody has held parallel testing to 9 hours. 80 minutes is the current high-water mark.

**TestMidas is a product defect, not a test bug**, traced to the line:
`SrmDocument.ChangeSettings` -> `UpdateResultsSummaries` (parallel) -> `CalcResultsForReplicate`
-> `ChromatogramGroupInfo.GetTransitionPeak` -> `ReadPeaks` -> `ChromatogramCache.CallWithStream`
-> `PooledFileStream.Connect`, where the per-file partial cache `...testing 2_1.wiff.skyd` no
longer exists. A `ChromatogramCache` reachable from the document still points at a partial that
was joined and deleted. It needs the pooled stream to have been EVICTED (otherwise it uses its
open handle and never revalidates) AND a settings change to recalculate at that moment, which is
why only parallel load surfaces it.

**The question that should drive the next session, from the developer:** why does TestMidas hit
this when so much other results-loading test code does not? Lead: MIDAS imports three samples
(MIDAS1/2/3) out of ONE multi-sample WIFF, so several per-file partial caches come from a single
source file, where most tests import one file per replicate. Establish whether partial-cache
lifetime differs for multi-sample sources BEFORE editing cache code. This is load-bearing code
where a mistake loses data rather than failing a test. Rejected approaches: making the cache fail
soft (hides real corruption) and pinning the stream in the pool (treats the symptom).

Both remaining product defects - this one and the graph update queue dropping a pane without
updating it (`SkylineGraphs.cs:879-880` with `GraphSummary.cs:359-361`) - were deliberately left
for review rather than changed unattended.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260822_test_stability.md` before starting work.

### 2026-08-24 - TestMidas fixed by scheduling, not by touching cache lifetime

The last remaining failure, and the developer's question drove it: *why does TestMidas hit this
when so much other results-loading code does not?* Answer: because MIDAS makes the library loader
a results listener, and no other loader is one.

**The chain, verified end to end in the code.**

1. `LibraryManager.StateChanged` (`Library.cs:75-76`) is the ONLY `BackgroundLoader` whose state
   check includes `MeasuredResults`. All seven others - `IrtDbManager`, `OptimizationDbManager`,
   `IonMobilityLibraryManager`, `BackgroundProteomeManager`, `ProteinMetadataManager`,
   `AutoTrainManager`, `RetentionTimeManager` - key on their own settings object. That clause
   exists only because MIDAS libraries are built from results
   (`MidasLibrary.GetMissingFiles` reads `MSDataFileInfos.Where(f => f.HasMidasSpectra)`).
2. So during import the library loader wakes on every partial-cache join.
3. `MidasLibrary.UnflagFiles` clears `HasMidasSpectra`. `ChromFileInfo.Equals` compares that field
   (`Chromatogram.cs:1248`) and `SrmSettingsDiff.EqualExceptAnnotations` does NOT normalise it away,
   so `DiffResults` goes true.
4. The `ChangeSettings` at `Library.cs:241` therefore recalculates ALL results, reading
   chromatogram caches - `UpdateResultsSummaries` (ParallelEx) -> `CalcResultsForReplicate` ->
   `GetTransitionPeak` -> `CallWithStream` -> `PooledFileStream.Connect`.
5. `MeasuredResults.FinishCacheJoin` (`:1925`) deletes each partial `.skyd` BEFORE `Complete()`
   publishes the document that stops referencing them. That window cannot be closed by ordering -
   delete and publish are not atomic.
6. A read landing in the window throws `FileModifiedException`. `CalcResultsForReplicate` already
   catches it (`TransitionGroupDocNode.cs:1405`) but its only recovery is "reuse old results",
   which does not exist for a replicate mid-import (`iResultOld == -1`), so it rethrows into
   `CallWithSettingsChangeMonitor`'s generic handler and is reported to the user.

An ordinary library load never reaches step 4: it leaves `MeasuredResults` untouched, `DiffResults`
stays false, and no cache is read. That is why this is MIDAS-only. The multi-sample WIFF is an
amplifier, not the cause - three samples out of one file give three partials, hence three
join/delete events. All three appear in the control log (`_0`, `_1`, `_2`), with `_1` dominant.

**The fix - scheduling, per the developer.** A background loader gets to decide when its work is
appropriate, and this one was firing too early and too often. Two changes, both in `Library.cs`,
37 lines added:

* `LoadBackground` treats the missing-file list as empty until `MeasuredResults.IsLoaded`. MIDAS
  spectra are read from the RAW files (`MidasLibrary.cs:644`), never from the `.skyd`, so waiting
  costs nothing functionally - and what it did before was repeated and thrown away once per join.
  `IsJoiningDisabled` documents keep today's behaviour for free, which is correct because nothing
  joins or deletes partials in that mode.
* `StateChanged` only consults `MeasuredResults` for documents that actually have MIDAS spectra.
  Provably cannot lose work: with no flagged file, `GetMissingFiles` is empty and the MIDAS block
  is already a no-op. This takes the fringe case's cost off every ordinary import - including the
  annotation-only changes that `MeasuredResults.RequiresCacheUpdate` and
  `SrmSettingsDiff.EqualExceptAnnotations` both work to keep cheap (pasting replicate names into
  the Document Grid was waking this loader and walking the library specs).

**Verified in both directions**, same configuration, `parallelmode=server`, 8 workers
(1 host + 7 Docker), 5 languages, `loop=40`, Debug/net8:

| tree | executions | TestMidas failures | rate |
|---|---|---|---|
| fix stashed (control) | 400 (200 + 200) | **14** | **7.0%** |
| fix applied | 400 (200 + 200) | **0** | - |

All 14 control failures carry the identical signature - `DialogTimeoutException` wrapping
`FileModifiedException` on `...MIDAS testing 2_N.wiff.skyd`. `TestMidasModifications` never failed
in either tree. `CodeInspection` green, solution builds clean, no Docker workers leaked after
either run.

Note the 7% here versus 2/15 and ~1/8,000 recorded earlier: a MIDAS-only soak concentrates the
contention, so this rate describes THIS configuration and is not comparable to a suite rate. It is
strong evidence the mechanism is gone, not a clearance claim - 0/200 clears only a rate above
~1.5% by the rule of three.

**Deliberately NOT changed.** `CallWithStream`, `PooledFileStream` and `FinishCacheJoin` are
untouched. The delete-before-publish window is real and structural, but no loader other than this
one is exposed to it, and cache-lifetime surgery is not worth the risk for a vendor-funded fringe
case that we are committed to keeping working rather than to optimising. Recorded here as a known
hazard for any future code that reads results off the document during import.

Two asymmetries found on the way, worth knowing but not acted on:
* `ChromatogramCache` has two read paths. `ReadPeaksAndScores` (`:1966`) takes
  `ReadStream.ReaderWriterLock.GetReadLock()` and honours the cancellation token, so
  `DisconnectWhile`'s `CancelAndGetWriteLock()` cancels it and it surfaces as
  `OperationCanceledException` - which `CallWithSettingsChangeMonitor` already handles correctly.
  `CallWithStream` (`:1852`) takes only `lock (ReadStream)` and ignores the QueryLock entirely.
* `CallWithSettingsChangeMonitor` builds `new LoadMonitor(this, container, null)` - a null tag - so
  `LibraryManager.IsCanceled`'s MIDAS-aware check (`Library.cs:106-113`) never runs on that path.
  The only live check is the document-reference comparison polled in
  `SrmSettingsChangeMonitor.UpdateProgress`, which by construction cannot see a delete that
  precedes its own publication.

**Not committed.** Working tree only, awaiting review. Soak logs kept at
`ai/.tmp/sessions/20260823-929f7187/`.

### 2026-08-24 - TestMultiInjectRescore: a finished file dragged back to 99%

The last failing test on the master branch, and the only one failing in a 6,576-execution run.
Root cause is in the progress DISPLAY, not in results loading - which is why nine other theories
died on contact with the evidence.

**What actually happens**, logged directly on the UI thread:

```
50.700  009  pct=100  final=True   ->  control = 100    correct, import complete
50.809  009  pct=99   final=False  ->  control = 99     stale snapshot, 109 ms late
        (nothing further, ever)
```

Progress statuses are immutable snapshots handed to the UI through the message queue, so an older
one can be delivered after a newer one. `FileProgressControl.SetStatus` accepted it and moved a
finished file backwards. `AllChromatogramsGraph.Finished` requires every file to be complete,
cancelled or in error, so one file pinned at 99% held it false permanently. The import, the caches
and the join had all succeeded; only the display disagreed.

**Fix** - `FileProgressControl.SetStatus` ignores a status that would move the file out of a final
state, comparing `Status.Id` so a Retry (a NEW progress chain) can still restart a finished file.
Without the Id comparison the obvious guard silently breaks the Retry button, and nothing else in
the suite covers that.

| | rate |
|---|---|
| before | 24 / 149 = 16% (also 10/85 and 6/50 in other runs) |
| after | **0 / 200**, 5 languages, 5 workers |

Run time for 50 executions went 160-320s -> 61s, because the 120-second stalls are gone.
`FileProgressStaleStatusTest` is the permanent verifier: it FAILS without the guard
(`Expected:<100>. Actual:<99>`) and pins the Retry direction too.

**Nine refuted hypotheses**, kept so nobody repeats them: shared `_chromDataSets` race (one builder
per file); un-reset accumulator counters (fresh accumulator per round); "009 stalls at 99%" (it
completes - the 99% was the SYMPTOM, and dismissing it cost hours); queue-generation mixing (all
`gen=1`); success-with-null-cache (`resultNull=False statusComplete=True`); `EnsurePathsMatch`
(`pathsMatch=True`, `CACHESTOADD count=1`); publish ordering resurrecting the failed file (a
control run showed passing imports do exactly the same); lost completion (buffer truncation, not
loss); the `OperationCanceledException` retry (named from ONE failing trace; the next failure had
no retry at all).

**Two of those came from defects in the DIAGNOSTIC, not the product**, and both times an absence
looked like a finding:

* **`Console.WriteLine` from Skyline product code never reaches the test log** - not even serially.
  The harness discards it. Printf debugging has to ride out on the failure message instead.
* **A capped diagnostic buffer truncated exactly the lines being reasoned from.** Raising the cap
  turned "the completion was lost" into "everything worked". Verify a diagnostic fires before
  trusting a run that used it.

**Method note**: the control - forcing PASSING runs to print their trace for comparison - is what
killed the publish-ordering theory one step before a wrong fix was written. Compare pass against
fail; do not reason about what a passing run "must" do.

**Also changed**: the wait in this test was 12 minutes in Debug (`WAIT_TIME` 180s x4 from
`GetWaitCycles`) for an operation that takes 2-5 seconds when it works. Now 30s base - 2 min Debug,
30s Release - and it names each file and its percent instead of relying on the graph's form text.

### 2026-08-24 - session end: the master PR, and the next failure in line

**PR [#4610](https://github.com/ProteoWizard/pwiz/pull/4610)** is open against master with the
test-stability work that is not net8-specific, in checkout `C:\proj\daily` on branch
`Skyline/work/20260824_test_stability_master`. It was fully green on TeamCity (1,736 Skyline tests)
before the last two pushes; CI on the final push had not reported when the session ended.

**What is on it**: the MIDAS loader gate, the Docker worker teardown fixes, tool-extraction
lock-holder naming and CRC skipping, PooledFileStream diagnostics, two stale-state test waits, the
re-authored unattended-dialog watchdog with its verifier, the wait-timeout thread dump with its
verifier, and the stale-progress fix below. The Waters mock fix was deliberately left out in favour
of rita-gwen's [#4603](https://github.com/ProteoWizard/pwiz/pull/4603), which is now merged.

**Checkout note that cost time**: this work is in `C:\proj\daily`, NOT `pwiz-work1`. Master's
`ProteowizardWrapper` needs the native `pwiz_data_cli.dll`, and `daily` was the only checkout that
was both master-based and already had it. `pwiz-work1` stays on the net8 branch.

**Issue [#4609](https://github.com/ProteoWizard/pwiz/issues/4609)** filed and assigned to
rita-gwen: replace the waters_connect HttpClient wrappers with `HttpClientWithProgress`. It lists
what gets deleted when that lands, so the #4603 workaround does not outlive its reason.

### 2026-08-24 - the thread dump cost 17 minutes on every agent, now 5 seconds

PR #4610 went red on its own new verifier, `TestThreadDumpNamesRunningFrames` - the only failure
in the run, and it ended the pass at 599 tests where the green run reported 1,736.

```
*** Thread dump unavailable: Array dimensions exceeded supported range.
```

**The duration was the real finding, not the assert.** That one test took **1,035s of the pass's
1,186s** - 87% of the entire unit-test pass. `TryGetThreadDump()` is called from both wait-timeout
sites in `TestFunctional.cs`, so the same cost was waiting for every functional timeout on CI.

| Where | Result |
|---|---|
| AWS agent `i-0a48914a6d4a636c1` | fail, 1029.7s |
| AWS agent `i-03b2e3f486a9f7987` | fail, 1035.9s |
| MacCoss TeamCity Agent 1 | fail, 744.6s |
| This developer machine | **pass, 1.0s** |

**Four theories refuted by measurement**, kept so nobody repeats them:

* **AWS agents are not provisioned for it.** The control on the physical MacCoss agent failed
  identically. Not an AWS problem, and nothing to raise with Matt on that basis.
* **Large heap on CI.** The log records **181 MB** at the moment of failure - no bigger than local.
* **Busy process / test position.** Running the full `Test.dll` locally put it at position **157,
  the same slot CI reports**, where it passed in 0 sec.
* **Release vs Debug.** CI's exact invocation (`test=Test.dll`) passes locally in BOTH
  configurations, no failures.

What is left is the agent runtime environment. A ClrMD probe on this machine
(`ai/.tmp/sessions/20260824-cbc60582/DacProbe.cs`) shows why it works here: CLR v4.8.9337.00 with
`LocalMatchingDac` resolving in-box to `Framework64\v4.0.30319\mscordacwks.dll`, `CreateRuntime`
in 11 ms, `_NT_SYMBOL_PATH` unset - so no symbol server is contacted at all. Where that DAC does
NOT resolve, ClrMD downloads one instead, which is slow when the server is unreachable and reads
garbage when the version does not match. That is the shape of both the stall and the exception.

**Changes** (`HangDetection.cs`, `HangDetectionThreadDumpTest.cs`):

1. **Bounded** - the dump runs on a background thread with `Join(5s)`, the same idiom
   `JsonToolServerTest.GetCallStacks` already uses. ClrMD has no cancellation, so the thread is
   abandoned rather than waited on; it is `IsBackground`, so it cannot hold up process exit.
   Measured: healthy path **49 ms** (93-line dump); a simulated 60s hang returns in **5,011 ms**.
2. **Cheap precondition** - `GetAllThreadsCallstacks` now refuses when `LocalMatchingDac` is null,
   naming the exact `mscordacwks` build the machine lacks, and calls `CreateRuntime(localDac)`
   explicitly so a symbol server can never become the fallback.
3. **Graceful degradation** - `TryGetThreadDump` falls back to the calling thread's own stack,
   which needs no attach, plus a line naming the agent's CLR and DAC. **The next CI run therefore
   reports what the agents actually have** rather than leaving it to be guessed.
4. **The test pins the degraded form and the DURATION** - nothing measured the cost of an
   unavailable dump, which is exactly how 17 minutes reached CI looking like an ordinary failure.
   The full dump is asserted only where the machine can take one, under a `TODO(chambm)` recording
   what an agent needs.

**Brendan's framing**, worth keeping: diagnostics and profiling support (thread dumps, memory and
performance profiling) is expected to work on a properly set up developer machine, and is
knowingly not well tested on TeamCity - if it malfunctions, it malfunctions for a developer who is
already debugging. That is why the full dump is aspirational rather than gating. It does NOT
excuse the cost: a test may not add 17 minutes to a run whether it passes or fails.

### 2026-08-25 - the 26,012-execution nightly: three failures, all far more common than the one being chased

Brendan ran the full suite for 8.5 hours on `Skyline/work/20260824_test_stability_master`.
**26,012 executions, 7 failures across 3 tests.** The run was cut off mid-test at the 8.5-hour
mark, so the last entry is truncated rather than failed.

**Logs rolled out of the way of the next run** (both were about to be overwritten by it):
`D:\test\nightly-logs\TestRunner-20260825-0620.log` and
`D:\test\nightly-logs\SkylineTester-20260825-0620.log`.

| Test | Executions | Failures | Rate |
|---|---|---|---|
| `PeakAreaDotpGraphTest` | 32 | 3 | **9.4%** |
| `ConsoleMethodTest` | 30 | 3 | **10%** |
| `ConsoleImportNonSRMFile` | 30 | 1 | 3.3% |

**The rates are the headline.** These are one-in-ten failures, not the 1-in-5,868 of
`TestMultiInjectionReplicates`. Each needs tens of executions to reproduce, not thousands - so
all three are cheap to chase, and none should be worked with the soak-and-wait method that
`TestMultiInjectRescore` needed. Reproducing any of them is minutes of machine time.

#### 1. `PeakAreaDotpGraphTest` - 3/32, and NOT new to this branch

Already characterised on 2026-08-22, so this is a recurrence rather than a discovery.

```
Timeout 720 seconds exceeded in WaitForConditionUI (Peak area pane 0 did not catch up to the
selected precursor.). Open forms: SkylineWindow (Skyline - DIA-QE-tutorial.sky), ...
```

**The thread dump added on this branch fired, and it is informative on the first occurrence.**
The UI thread is parked in `WaitMessage` inside `Application.RunMessageLoop` - *idle, waiting for
messages*, not stuck doing work. No other thread is in Skyline code either; the rest are the test
harness and NetMQ plumbing. So the pane update was never triggered or never posted, rather than
being slow or deadlocked. That narrows this from "the graph is slow" to "the notification that
should have updated pane 0 did not arrive", which is a different search entirely.

Note the cost: 791 seconds per failing occurrence, because this test still has the default
720-second wait. Cutting it, the way `TestMultiInjectionReplicates` was cut, is worth doing
before chasing it - at 3 failures in 32 executions the wait dominates the cycle time.

#### 2. `ConsoleMethodTest` - 3/30, a file lock in teardown

```
CleanupFiles failed:
Directory.Move("c:\AlwaysUpCLT\TestResults_2\CommandLineTest", "...\135a8e7c-...") failed,
attempt to delete instead resulted in "The process cannot access the file '~SKD0BE.tmp' because
it is being used by another process."
(c:\AlwaysUpCLT\TestResults_2\CommandLineTest\~SKD0BE.tmp is locked by <the test host process>)
```

**The lock-holder naming added on this branch is what identified the holder**, and the answer is
pointed: the holder is **the test host process itself** - the same process running the test - not
an external scanner and not a leftover Skyline. So this is a handle the test or the code under
test left open on its own temp file, not outside interference. `~SKD*.tmp` is a Skyline
save-temp name, which puts the suspect on the document-save path rather than on the results cache.

On parallel client 2, under `c:\AlwaysUpCLT\TestResults_2` - the AlwaysUp CLT worker area.

#### 3. `ConsoleImportNonSRMFile` - 1/30, a status code with nothing to explain it

```
No error reported but exit status was 2.
```

The command's output ends with **warnings only** - no `Error:` line - yet the command-line
Skyline exited 2. The warnings themselves are all EXPECTED by this test: `bad_file.raw` is
deliberately corrupt (`[RawFileImpl::ctor()] Corrupt RAW file`), and
`FullScan_folder\FullScan.RAW` deliberately has no SRM/MRM chromatograms
(`NoFullScanFilteringException`), both reported as `Warning: Failed importing ... Ignoring...`.
The run reached `100% - Updating peak statistics`.

So the question is why the exit status disagreed with the output on 1 run in 30, when the same
warnings are produced every run. Either a warning is intermittently escalated to an error exit
code, or an error occurred after the last printed line and never reached the output. The
assertion cannot say which, which makes **the message the first thing to fix**: it should report
what the exit code was derived from.

#### What this run also settled

* **The 17-minute thread dump is gone.** `TestThreadDumpNamesRunningFrames` does not appear in
  the failure list at all, and the dumps that DID fire (above) came back complete with frames -
  so on this machine the full-dump path works, which is what the bound and the explicit
  `CreateRuntime(localMatchingDac)` were meant to preserve.
* **A Docker worker still leaked** - `docker_worker_20260825045845_5` was found up afterwards and
  wedged the next build exactly as this TODO predicts, MSBuild naming `vmwp.exe` as the holder of
  `System.Threading.Tasks.Extensions.dll`. (An earlier draft of this entry claimed teardown held;
  that was read off the absence of leak FAILURES in the log, which is not the same thing.) It fits
  the third teardown defect still open above: the nightly was terminated externally at the
  8.5-hour mark, and that path bypasses the teardown scope. Killing the container cleared the
  build immediately.

### 2026-08-26 - Merged

PR #4610 merged as commit `79e50e83a6`, approved by bspratt and nickshulman, 19/19 checks green.

**What shipped**: the MIDAS loader gate; the unattended-dialog watchdog with its verifier; the
stale-progress fix that pinned a finished file below 100 (`FileProgressStaleStatusTest`); parallel
worker teardown on every exit path plus the SkylineTester prompt that surfaces leftover containers;
tool-extraction lock-holder naming and CRC skipping; `PooledFileStream` size/missing-file detail;
`IExplainDiff` / `EqualityExplainer`; the bounded thread dump; and two waits cut from minutes to
seconds (`TestMultiInjectionReplicates`, `TestMultiInjectRescore`).

**The thread dump question is closed.** `TestThreadDumpNamesRunningFrames` failed at 745-1035
seconds on three agents, which looked like missing debugging support on the TeamCity boxes and was
written up as a `TODO(chambm)`. It was not: ClrMD resolving its own DAC was the slow, failing path,
and calling `CreateRuntime(localMatchingDac)` explicitly fixed it. Measured afterwards at **0 sec on
this developer box, MacCoss TeamCity Agent 1, and an AWS agent** - all three - so the TODO was
removed rather than softened, and there is nothing to raise with Matt.

**Three rounds of `/code-review max` ran, and the third is the useful lesson.** Round 1 fixed the
teardown cluster and introduced four defects (a modal dialog on the nightly's unattended path,
unbounded `docker ps`, a ProcessExit handler over .NET Framework's ~2s budget, a kill call with no
run tag). Round 2 fixed those and introduced one more: switching to a bounded read returned raw
stdout where the old path normalised through `ReadLine`, so `Split(Environment.NewLine)` on docker
output - which is LF - collapsed every container name into one string and **teardown would have
silently killed nothing**. Round 3 caught it. Verified by probe against live containers
(`RUNNING_COUNT=3`, three distinct names), not by "0 containers afterwards", which is true either
way because workers self-exit on heartbeat loss.

That is the shape to remember: three consecutive rounds each left this area worse in a new way, and
two of the verifications proved the change did what was intended rather than that nothing else
broke. See [[rising-triage-bar-near-ship]].

**Deferred, deliberately**: `AllChromatogramsGraph:469` (a stale retry snapshot can `RemoveFailedFile`
mid-import), `FileProgressControl.Reset()` leaving `IsCanceled`/`Status` stale, and the
`PauseSeconds = -1` leak that can disable the dialog watchdog process-wide. All pre-existing, none
made worse here, and no issues filed - per Brendan, a pre-existing finding without a near-term path
to being fixed becomes noise rather than signal.

**One issue filed**: [#4614](https://github.com/ProteoWizard/pwiz/issues/4614) -
`TransitionGroupChromInfo.Equals` compares `Annotations` twice and never compares `MassError`.
Probably benign in this type, filed because it is an instance of a class Brendan wants zero examples
of: a property missing from `Equals` means Skyline cannot tell the change was made, discards the new
object, and creates no Undo record.

**Still open in this TODO**: `TestMultiInjectionReplicates` (1 in 5,868; ~8,159 executions on this
branch produced no reproduction, which excludes the higher-frequency reading), and the three
failures from the 26,012-execution nightly - `PeakAreaDotpGraphTest` 3/32, `ConsoleMethodTest` 3/30,
`ConsoleImportNonSRMFile` 1/30. Those rates are one-in-ten, so each is minutes of machine time to
reproduce rather than hours. The nightly logs are preserved at `D:\test\nightly-logs\`.

## The next failure in line: TestMultiInjectionReplicates

Found by Brendan in a 5,868-execution run of 4 tests x 5 languages: **1 failure**, a different test
and a different subsystem from the one fixed today.

```
Total complete: 100%   <- all four files, so the progress display is now correct
Settings.MeasuredResults Not all chromatogram sets are loaded -
  No ChromFileInfo.FileWriteTime for ...Std_6\SP_Std6_01.mzML, ...SP_Std6_02.mzML
```

The import COMPLETES, but two of four `ChromFileInfo` entries never receive a `FileWriteTime`, so
`ChromatogramSet.IsLoaded` (`Chromatogram.cs:529`) stays false forever and `WaitForDocumentLoaded`
times out. The two are both injections of the SAME replicate, which points at the multi-injection
path rather than random file loss.

**Not caused by this branch, established rather than assumed:**

* the progress fix is display-only and cannot set `FileWriteTime`
* the `FileWriteTime` path is `ChromCacheBuilder.cs` / `ChromHeaderInfo.cs` / `Chromatogram.cs`,
  none of which this branch changes
* the one plausible link - the `LibraryManager.StateChanged` narrowing - is a no-op for this
  document: it has NO libraries and NO MIDAS, so `LoadBackground` hits
  `!changed && !newMidasLibSpec && !failedMidasFiles.Any()` and returns without touching the
  document. The removed wake-up only ever started a thread that did nothing

Nor is it "unmasked" by the fix - unmasking would need the same test or code path. Rate is 1 in
5,868 against the 12-16% fixed today, a different order of magnitude.

**Recommended approach, NOT the one used today.** At ~15 minutes per occurrence (default 720s
wait) and 1 in 5,868, do not soak-and-instrument this the way TestMultiInjectRescore was chased.
Cut the wait first, then run a control on `origin/master` at equal scale to settle causation by
measurement instead of by argument.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260824_test_stability_master.md` before starting work.
