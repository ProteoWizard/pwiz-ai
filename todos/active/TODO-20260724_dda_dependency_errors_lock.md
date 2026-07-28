# TODO: TestDdaSearchDependencyErrors flaky under parallel testing (#4447)

**Branch**: `Skyline/work/20260724_dda_dependency_errors_lock`
**PR**: [#4481](https://github.com/ProteoWizard/pwiz/pull/4481) (open, 9 commits)
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
* **Tools directory lock** - exclusive `FileShare.None` handle per (test, culture), taken in
  `RunTests.RunTestInstance` under a `using` so it releases whether the test passes or fails.
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

**Cross-container file locking works** - verified both host-to-container and
container-to-container across the Docker bind mount. This is what makes the lock viable.

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

## Remaining

1. **TeamCity has never been checked** on any of the nine commits. All verification was local,
   one machine, one test.
2. **Passes 0 and 1 have not been run on the current head** - the review fixes (split in-flight
   counters, `Retired` flag, requeue-on-cancel, shared lock key, repeat-pass rewrite) were only
   verified with pass 2.
3. The `loop=-1` repeat-pass fix is reasoned, not reproduced: `Run-Tests.ps1` coerces
   non-positive `-Loop` to 1 and a hook blocks invoking TestRunner directly.

## Progress log

**2026-07-27/28** - Reproduced, root-caused, fixed, and hardened over three `/code-review`
rounds (each found real defects, including two hangs; the queue restructure itself came back
clean all three times). PR #4481 open with 9 commits. `-Pass` parameter added to
`Run-Tests.ps1` and pushed to pwiz-ai master as `bd9d484`, without which passes 0 and 1 are
unreachable through the wrapper.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260724_dda_dependency_errors_lock.md` before starting work.
