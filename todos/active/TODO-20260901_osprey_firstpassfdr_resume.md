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
* ~~`ValidityKey` carries no cohort identity~~ - **WRONG, retracted 2026-09-01.** Asserted four
  times without checking. `FirstPassFdrTask.ValidityKey` appends
  `;reconciliation=` + `SearchIdentity.ReconciliationParameterHash()`, which is SHA-256 of
  (search hash + reconciliation parameters + run FDR + **sorted, deduped input file stems**).
  Cohort identity is therefore already in the key, unconditionally - the stems are hashed even
  when reconciliation is disabled.

  Verified against two real runs differing only in cohort:

  ```
  86-file : ...pick=lda;pickmodel=none;reconciliation=4b988704...;fdrsidecar=6;pass2=protein-compact
  12-file : ...pick=lda;pickmodel=none;reconciliation=69954401...;fdrsidecar=6;pass2=protein-compact
  ```

  So "score 82 files, drop another 82 into the directory, start over" is already refused: the
  stem set changes, the hash changes, the old sidecars are not adopted.

  The granularity is also already correct. `PerFileScoring`'s key has NO stems, which is right -
  its output is cohort-INDEPENDENT, proven bitwise on 2026-09-01 (a 1-file run reproduced an
  86-file run's parquet exactly). Adding a cohort term to the base `OspreyTask.ValidityKey`
  would have invalidated every `.scores.parquet` - 468 GB - to fix a bug that does not exist.

  Stems, not paths, matters here: `LibraryIdentityHash` documents the same choice, and a
  path-hashed key is what broke `-LinkFrom` when the SEA-AD data moved.

## (c) The real requirement: PER-FILE guards, not per-phase (developer, 2026-09-01)

> *"the task gets started. Upon starting, the task recognizes that it has valid completed work
> on disk and skips repeating it. There should be both task-wide guards to repeating work and
> internal guards to repeating work. When a single task can take over 3 hours this is critical."*
>
> *"Breaking it into phases risks forcing a 1 hour phase. You really want to be able to skip any
> individual file for which you have a first-pass FDR sidecar. Think of this as the computer
> blue-screens during processing."*

Phase-level guards are the wrong granularity - a 99%-complete hour still redoes the hour. The
unit is the file.

### How badly it recovers today: completely

Measured on the 86-file plate run:

```
sidecars written : 12:45:35 -> 12:59:55   (86 files, incrementally, over 14.3 min)
markers written  : 13:13:27               (all 86, one second, at TASK END)
```

A machine lost at 12:55 leaves ~60 complete sidecars and zero markers, so the restart re-scores
all 86. At 446 files that window is 137 minutes. **Recovery is proportional to nothing.**

Commit `73e44461d7` fixes the write half: `FlushPartialSidecar` - the production write path,
which the earlier commit missed in favour of the resident-path `WriteFdrScoresSidecars` - now
stamps each sidecar at write time.

### The read half, still to do

The score pass is two passes over files in `PercolatorScorer`:

* **pass 1** per file: score, per-file run q, feed `streamingQ` + clamp floors + `contribAcc`
* **barrier**: build the experiment maps
* **pass 2** per file: re-score, apply the maps, `sink.Accept` -> sink flush -> sidecar write

For a file whose sidecar is already current, **feed both passes FROM THE SIDECAR** rather than
skipping the file:

* pass 1 - `streamingQ.Add(score, entryId, isDecoy, peptide)` and the clamp floors all come off
  the sidecar records;
* pass 2 - feed `sink.Accept` from the sidecar's final q-values and skip the re-write.

Feeding rather than skipping is what keeps the run byte-identical: `sink.Accept` is also what
populates `projections` and the `--model-diagnostics` accumulator, so a skipped file would
silently shrink both the diagnostics report and the `First-pass compaction: X -> Y` counts.
Reading a sidecar (~78 MB/file) is far cheaper than loading features and scoring.

**Seam**: the task already hands the scorer `Func<string, IReadOnlyList<double[]>> loadFileFeatures`.
Add the same shape - a predicate plus a record loader - so `Osprey.FDR` never learns about
markers or tasks; it just asks "do you already have this file's results?"

**Gate**: byte-identical output against the existing plate run, which is a 44-minute check.

### Why the marker still earns its place

`FdrScoresSidecar.Write` commits through `FileSaver`, an atomic rename, so a sidecar is absent or
complete - **presence already proves completeness**. The marker carries only what presence
cannot: which task, which build, which validity key. Without it a sidecar from another library or
pass-2 arm is present, complete, and silently adopted.

The parquets solve the same problem the better way, by self-describing in the footer
(`osprey.version`, `osprey.search_hash`, `osprey.library_hash`). The `.bin` sidecars should
eventually do the same and drop the companion file - the header has only 14 reserved bytes, so it
needs a length-prefixed field and a `FormatVersion` bump, which would invalidate the 446 and 86
sidecars currently in use. Right thing to do at the next natural format bump, not today.
