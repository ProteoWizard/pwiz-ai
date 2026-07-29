# TODO: TestDdaSearchDependencyErrors flaky under parallel testing (#4447)

**Branch**: `Skyline/work/20260724_dda_dependency_errors_lock`
**Module**: `skyline`
**PR**: [#4481](https://github.com/ProteoWizard/pwiz/pull/4481) (open, 10 commits)
**Issue**: [#4447](https://github.com/ProteoWizard/pwiz/issues/4447)
**Related**: [#4482](https://github.com/ProteoWizard/pwiz/issues/4482) closed as premature

## Objective

`TestDdaSearchDependencyErrors` failed intermittently under local parallel testing with
`UnauthorizedAccessException` deleting `msvcp140.dll<random>.PendingOverwrite` while
re-installing crux.

## Root cause

Not antivirus (the issue's theory) and not the asynchronous `Process.Kill` (the first theory
this work pursued). The parallel work queue held **one entry per (test, language, pass, loop
iteration)**, all queued up front. With `loop=40` the pair
`(TestDdaSearchDependencyErrors, fr-FR)` appeared 40 times, and every one of those entries
mapped to the same per-test state - most visibly the tools directory, whose name is just test
name + culture. A fast worker laps a slow one and starts iteration N+1 while another worker is
still in iteration N.

Proved from the baseline log using the global completion counter: fr iteration 0 returned its
result **26th** after running 106 s, while fr iterations 1-5 returned results 5th, 10th, 13th,
18th and 24th - five other runs of the same key completed inside its window.

## What was done

* **Queue serialization** - one entry per (test, language) carrying its remaining passes and
  loop iterations, re-queued only once its result returns. The entry object is the token: in
  the queue or checked out by one worker, never both, so the invariant holds by construction.
* **Worker keep-alive** - a `TestRunnerWait` message, because with one entry per pair the queue
  is legitimately empty whenever the workers between them hold every remaining test, and
  retiring on that was shrinking the pool to a single worker mid-run.
* **`ProcessRunner.KillAndWaitForExit`** - `Process.Kill` is asynchronous; until the process is
  gone Windows keeps its DLLs mapped and undeletable.
* **Checkout keyed on the tools directory** - a worker takes an entry only if every tools
  directory that entry's next pass will touch is free, claiming them all at once or taking
  nothing. Keyed by directory name rather than by test, because the directory is the resource:
  shortening is lossy, so `TestDdaSearch` and `TestDiaSearch` are both `DS13` (13 such
  collisions across 1136 tests). Replaces an earlier `FileShare.None` file lock, which blocked
  the worker, needed a 15-minute timeout and a give-up path, and relied on Windows share modes
  holding across the Docker mount.
* **Lead and follow-on entries** - passes 0 and 1 run once per test, not once per language, so
  they get an entry of their own and the per-language pass 2 entries are not created until it
  is done. Pass 1 cycles the culture itself, so this is what stops it reaching a language
  another worker holds - those entries do not exist yet.
* **`RedownloadTools` gated on `IsParallelClient`** - pass 0 was deleting archives from the
  shared download cache out from under whichever client was installing from them.
* **`AbstractUnitTest.IsParallelClient`** tested a TestContext property nothing sets, so it
  always read false. Three things on this branch depend on it.

## Measurements

| Configuration | Result |
|---|---|
| Baseline (unfixed), 5 workers x 5 languages, loop 40 | **7 failures / 32 runs** |
| After queue serialization, same parameters | **0 / 57** |
| Final, after all review fixes, loop 8 | **0 / 40**, monotonic and work-conserving |
| Killed process's DLL undeletable after `Kill` | 160-283 ms; `WaitForExit` closes it, 3/3 |
| Per-test tools-dir cleanup (rejected) | test duration 11 s -> 16 s median (+45%) |
| Per-client tools dirs (rejected) | 4.42 GB for ONE test x 5 cultures x 5 clients |
| TeamCity, head `ae513844` | **SUCCESS** on bt209 (#21689) and ReSharper checks (#18978) |
| Pass 0,1,2 before the queue keying, loop 4 | **1 collision / 1 run** (pass 1, tr-TR) |
| Pass 0,1,2 after it, loop 4 | **0 / 5 runs**, 33 runs each, composition identical |
| Pass 2 only, loop 8 | **0 / 40**, every language monotonic 2-9 |
| Tools-directory name collisions | 13 names, 27 tests, of 1136 (incl. DdaSearch/DiaSearch) |
| Two colliding pairs, parallel, loop 4 | **0 failures**, 156 s, all 4 tests got all 20 loop runs |

**Cross-container file locking works** - verified both host-to-container and
container-to-container across the Docker bind mount. This mattered while exclusion was a file
lock; the queue decides it in the server now, so nothing depends on it.

## Decisions and dead ends worth not repeating

* **Per-client tools directories were rejected.** Cheap in isolation (no time cost) but they
  force a cleanup policy at nightly scale, and cleanup measured +45% on test duration. The two
  are not separable.
* **`StopWorker` (killing an unresponsive worker) was written and then reverted.** It could
  hang the run on a wedged docker daemon, and killing the host worker orphans every
  `NoParallelTesting` test while the run still reports success.
* **A claim that `WaitForExit` "took failures from 5 to 1" is not supported.** Three runs of
  the same configuration gave 2, then 5, then 1 - variance, and the 5-to-1 pair differed only
  by a diagnostic. `WaitForExit` is justified by the direct 160-283 ms measurement instead.
* Passes 0 and 1 in parallel are much less exercised than pass 2, and one collision was seen
  there whose holder was in another container. Too noisy to characterize; #4482 was filed and
  then closed as premature.

## TeamCity

Checked 2026-07-28, having never been looked at before. The head `ae513844` is **SUCCESS** on
both configurations that run this branch: bt209 (Skyline master and PRs, Win x64) build #21689,
and ReSharper checks build #18978. bt210 has no builds for this PR.

Two of the six bt209 builds failed - `b0a2ed23` (#21687) and `f255cb42` (#21683) - and **neither
is this PR's doing.** Both ran on `MacCoss TeamCity Agent 1` and produced the same 25
`GC-LEAK Objects not garbage collected after test: SkylineWindow, SrmDocument` failures in
`Pass2_general`-en. Master build #21681 (`c1b64302`) on that same agent fails with an identical
list, so it is a pre-existing condition of that one agent. Every cloud agent (`pwiz-windows-i-*`)
is green on both master and this branch. Worth its own issue, but out of scope here.

## Passes 0 and 1 on the current head

Run 2026-07-28 on `ae513844`: `-Language all -ParallelWorkers 5 -Loop 4 -Pass 0,1,2
-EnableInternet -KeepWorkerLogs`. It **terminated cleanly in 315.7 s** and reported honestly.
None of the failure signals fired: no `were never run`, no `stopped responding`, no
`Gave up after` (nothing ever waited out the 15-minute tools-directory lock).

The schedule came out exactly as designed - 24 runs, nothing missing, nothing duplicated:

| Queue entry | Runs |
|---|---|
| French | pass 0 (fr), pass 1 (cycles en, fr, tr internally), passes 2-5 (fr) = 8 |
| en, tr, ja, zh | passes 2-5 each = 16 |

Passes 0 and 1 are queued only under French by `PassRunsInLanguage`, so the en/tr pass-1 lines
in the log belong to the **French** work item, not to the en/tr entries - reading them as
per-language runs makes it look like ja and zh lost their pass 1, and they did not. Every entry
is monotonic in pass number. Serialization held.

Two failures, neither of them a queueing defect:

1. **GC-LEAK**, host worker, first run (`2.0`, en): `Objects not garbage collected after test:
   SkylineWindow, SrmDocument`. Once only - the "1 failures" on later lines is the running
   total. Same signature as the TeamCity agent-1 failures above. Not established whether it
   predates this branch; a master comparison would settle it.
2. **The #4447 signature reproduced**, and this run localizes it. Worker
   `docker_worker_..._0` held the French entry; its pass 1 cycled into **tr-TR** and threw
   `UnauthorizedAccessException` deleting
   `Tools_DSDE29_tr-TR\crux-4.3\...\msvcp140.dll<random>.PendingOverwrite` from
   `SimpleFileDownloader.DownloadRequiredFiles`. This is the pass-1 hole the `ToolDescription`
   comment already names: pass 1 cycles the culture itself rather than using the one it was
   queued under. The lock is keyed correctly for the cycled culture (`Language.Name` is current
   when `RunTestInstance` takes it), and **no other tr test was running** - tr's passes 2-5
   finished at 13:30, the pass-1 tr iteration ran ~13:32:50. So the holder was not a concurrent
   test. A mapped `msvcp140.dll` outliving the test that loaded it, in another container, fits
   the evidence and the "Restart Manager only sees inside its own container" note. This is what
   #4482 was filed and closed over; it is now reproduced and narrowed, not yet root-caused.

## The fix for the pass-1 collision

Both properties the exclusion needs are now in the queue, and the file lock is gone:

* An entry declares `RequiredToolsDirectories` for the pass it is about to run - all languages
  for pass 1, its own otherwise - and a checkout claims them all or takes nothing. All-or-nothing
  under one lock means no worker ever holds a directory while waiting for another, so it cannot
  deadlock, and a blocked entry is passed over rather than waited on, which keeps the worker
  busy. Entries passed over hold their directories aside for the rest of the scan so a later
  entry cannot keep taking them.
* `runIsOver` now tests the queues rather than inferring emptiness from an empty checkout, which
  after this change can also mean "everything left is blocked". Without that a worker retires
  early and never comes back.
* Worker-pool sizing uses the eventual test/language count, not the queue depth, which now
  starts at one entry per test. Sizing off the queue would have left the pool at 2.
* Release uses the directories captured at checkout, not the ones the entry wants afterwards:
  advancing off pass 1 narrows that to one language and would leak the other four forever.

Verified with 5 pass-0/1/2 runs (0 failures, identical 33-run composition) against a 1-for-1
reproduction beforehand, plus 0/40 on pass 2 only. `PathExTest` pins the shortening rule and
asserts the DdaSearch/DiaSearch collision, so the reason the key is the directory survives.

## Remaining

1. **TeamCity has not seen any of this.** The green builds above are the pre-fix commits.
2. All verification is still one machine.
3. **The mixed-queue collision is untested.** Of the 13 colliding names, `DT15` is the only one
   whose two tests sit in different queues - `TestDdaTutorial` is `NoParallelTesting` and
   `TestDiaTutorial` is not - so the host worker can be in `DT15_<culture>` while a container is.
   That is the shape the `runIsOver` change exists for, and running it means running two
   tutorials. Note `DS13` (`TestDdaSearch`/`TestDiaSearch`) needs no such test: both are
   `NoParallelTesting`, so they serialize on the host worker whatever the queue does.
4. The `loop=-1` repeat-pass fix is reasoned, not reproduced: `Run-Tests.ps1` coerces
   non-positive `-Loop` to 1 and a hook blocks invoking TestRunner directly.

## Progress log

**2026-07-27/28** - Reproduced, root-caused, fixed, and hardened over three `/code-review`
rounds (each found real defects, including two hangs; the queue restructure itself came back
clean all three times). PR #4481 open with 9 commits. `-Pass` parameter added to
`Run-Tests.ps1` and pushed to pwiz-ai master as `bd9d484`, without which passes 0 and 1 are
unreachable through the wrapper.

**2026-07-28** - Checked TeamCity for the first time (head green; the two red builds are a
pre-existing agent-1 GC-leak condition that master shares) and ran passes 0,1,2 on the head. The
run terminates and serializes correctly; it also reproduced the #4447 signature inside pass 1's
culture cycling, which is now localized to a specific worker and iteration. See the two sections
above. Cleanup helper for parallel runs at `ai/.tmp/Clear-ParallelRunState.ps1`.

**2026-07-28 (later)** - Moved the exclusion into the queue: checkout keyed on tools directory
names, plus lead/follow-on entries so pass 1 owns its test. Deleted the file lock. Uncommitted,
awaiting review of the diff. One trap worth remembering: the first attempt at repeat runs
produced three failures that were the cleanup helper's fault, not the product's -
`Remove-Item -Recurse` deletes what it can and then throws on a still-mapped `msvcp140.dll`,
leaving a tools directory with no `crux.exe` in it, and the next run then fails with "system
cannot find the file specified". Cleanup retries now, and the repeat script aborts rather than
running on dirty state.

**2026-07-29** - Two `/code-review max` rounds. The first found the pass-1 collision was still
open and led to the queue rework; the second found that the wedged-worker watchdog I had just
added would hang the run outright, because a wedged worker's directories are never released and
`runIsOver` needs an empty queue, so an aliasing entry is passed over forever. Both rounds also
caught real bugs of their own: `loop=-1` (what nightly passes) was being turned into a single
pass, and culture names canonicalized case-sensitively so `fr-fr` and `fr-FR` were two keys for
one directory. Committed as `a946208bda` and pushed; PR description rewritten, since the old one
documented the file lock that is now gone.

Still not exercised by any run: the wedged-worker paths, the never-run `!!!` reporting, and the
big-worker relaunch, all of which need a worker to wedge or die. Making `WEDGED_TEST_TIMEOUT`
settable would let one short run drive that whole chain - it is the only knob of its kind that is
not settable, unlike `workertimeout` with `SKYLINE_TESTRUNNER_DOCKER_TIMEOUT_SEC`.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260724_dda_dependency_errors_lock.md` before starting work.
