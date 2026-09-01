# TODO-20260901_osprey_firstpassfdr_resume.md - a resumed run skips FirstPassFDR and then produces nothing

**Branch**: `Skyline/work/20260901_osprey_firstpass_resume` (in `C:\proj\pwiz-work1`)
**Found**: 2026-09-01, while making FirstPassFDR's outputs resumable at all.

## Two separate defects, and the second is the blocker

### (a) FIXED on the branch: markers were written too late to survive a kill

The pipeline driver stamps a task's declared outputs only **after `Run` returns**. FirstPassFDR
writes 446 durable artifacts on a full CHS cohort and then keeps working for another hour, so a
run killed in that window left every one unmarked.

Measured: the 446-file join wrote all 446 `.1st-pass.fdr_scores.bin` at 07:09 and was killed at
08:41 in the survivor reload. 3h45m of streaming ingest, Percolator and protein FDR was
unrecoverable, though nothing about it was wrong.

Fixed by stamping all three declared output kinds through `PerFileResumeDriver` as each lands
(commit `0c947396d0`). Sound **only because Phase 2 made these artifacts write-once and
immutable** - present therefore implies complete. Verified on 12 files: markers now appear while
the task is still running, and a re-run reports `FirstPassFDR:skipping (outputs valid)` in 17 ms
against 388.9 s of task time.

### (b) NOT FIXED, and it makes (a) worthless on its own: a skipped FirstPassFDR breaks Stage 6

With FirstPassFDR skipped, `PerFileRescoring` **silently does almost nothing** and
`SecondPassFdrTask` then fail-fasts.

| | clean full run | resumed (Stage-5 dir, continued) |
|---|---|---|
| exit | **0**, 18m44s | **1** |
| out.blib | **41.8 MB** | ABSENT |
| PerFileRescoring | **737.0 s** | **108.5 s** |
| `.scores-reconciled.parquet` | **12** | **0** |
| 2nd-pass experiment sidecar | 1 | 0 |

```
[ERROR] Pipeline failed: No second-pass experiment-scope records were published, so the
analysis-wide 2nd-pass FDR sidecar cannot be written. ... See issue #4486.
   at Pass2FdrSidecar.WritePass2ExperimentSidecar (Pass2FdrSidecar.cs:1323)
   at SecondPassFdrTask.RunProteinFdr (SecondPassFdrTask.cs:576)
```

That throw is a deliberate gate added in #4486 (`"ABSENCE IS A STOP"`), after `transfer` mode
silently wrote no experiment sidecar. It is doing its job. The defect is upstream: Stage 6 gets
as far as `"reconciliation bundle..."` and stops, writing no reconciled parquet, so nothing
competes and no `Pass2ExperimentScope` is ever published.

**Hypothesis to test first:** `FirstPassFdrTask.Rehydrate` does not reconstitute everything
`PerFileRescoreTask` demands - the reconciliation plan / gap-fill targets that `Run` publishes.
Compare what `Run` publishes against what `Rehydrate` does.

## This is PRE-EXISTING, not caused by (a)

Proven, not argued. The pre-change 243 snapshot
(`_bin\26.1.1.243-20260831-1639`) run over a fresh directory:

* wrote **25 markers of its own** at the end of its successful Stage-5-only `Run` - so the skip
  path was **already reachable** without any of (a);
* then failed **identically** on continuation - same error, same stack, exit 1, no blib.

So resuming a FirstPassFDR was already possible before this branch, and already produced
nothing. (a) widens *when* you can resume; it does not fix *that* a resume produces no result.

## Reproduction: 19 minutes on 12 files, not 5 hours on 446

```powershell
# 1. Stage-5-only, ~6.5 min   2. continue the same dir, fails in ~2 min
#    control: the same 12 files clean in one run, ~19 min, exit 0
ai\.tmp\test-resume.ps1 ; ai\.tmp\test-resume3.ps1 ; ai\.tmp\test-clean-full.ps1
```

Dirs: `resume-test-12files` (fails), `clean-full-12files` (works),
`resume-control-12files` (pre-change build, fails identically).

## Why this matters beyond recovery

The stated goal is that a user whose machine takes a Windows Update mid-analysis can restart
without repeating hours of work. Today they cannot: the restart is fast and the result is
absent. A fast skip that yields no output is worse than no resume at all, because it *looks*
like recovery.

It also blocks the HPC direction in
`TODO-20260901_osprey_stage5_reload_materialization.md`: any orchestrator that runs
`--task FirstPassFDR` on one node and continues elsewhere is this exact shape.

## Not yet done

* Fix (b).
* `ValidityKey` carries no cohort identity, so sidecars from a 446-file run would be adopted by
  a 257-file run in the same directory, even though first-pass q-values come from a
  cohort-trained model. Pre-existing for completed runs; (a) widens the window. Deliberately
  NOT changed on 2026-09-01, because adding cohort identity would invalidate the 446 sidecars
  currently on disk and destroy the recovery they represent. Decide once those are consumed.
