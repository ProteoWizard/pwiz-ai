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

## (d) Resume is a FORWARD SCAN, not a sparse-matrix fill (developer, 2026-09-01)

> *"any need to run a prior stage invalidates the next stage. It is not supposed to be like
> filling in a sparse matrix with the assumption that everything in the matrix must be valid.
> It is really supposed to be moving forward looking for completed work until you find a gap and
> then resuming from there."*

Two different granularities, and only one of them is a scatter:

* **Within a stage, per-file scatter is correct.** Given a fixed model, files score
  independently, so adopting 77 of 86 in any order is sound and strictly better than resuming
  from the first gap - the guard implemented on this branch does that.
* **Across stages it is NOT.** If FirstPassFDR Runs at all, PerFileRescoring's and
  SecondPassFDR's outputs describe a first pass that may no longer be the one on disk.

**Nothing enforces the second today.** Validity is keyed on INPUT IDENTITY, not on upstream
freshness, so a downstream marker stays current even when its upstream has just been
regenerated. That is only safe because the artifacts are deterministic - same key implies same
content - which makes the invariant emergent rather than constructed, and emergent invariants
stop holding quietly.

Note the blanket wipe removed in `4bf0df0683` did not provide this either: it deleted only
FirstPassFDR's OWN declared outputs, never a downstream stage's. The cross-stage rule has never
been implemented.

### The rule to implement

A task that **Runs** (rather than Skips or Rehydrates) invalidates the validity markers of every
stage AFTER it. Resume then becomes a forward scan: walk the stages in order, take completed
work until the first gap, run from there, and treat everything beyond as invalid by
construction.

Two things that makes correct which are currently only conventionally correct:

1. A stage whose output changes cannot leave a downstream stage claiming validity against the
   old output, whatever the key does or does not cover.
2. The `ValidityKey` no longer has to be exhaustive to be safe. Today a key that forgets an
   input is a silent-wrong-answer bug; under a forward scan it is at worst a redundant recompute.

Sequence it with the per-file guard - the guard makes partial work adoptable, and this makes
adopting it safe past the stage boundary.

## Measured on the branch, 86-file plate (2026-09-01)

Staged with `ai/scripts/Osprey/New-OspreyResumeStage.ps1` into a DISPOSABLE hard-linked
directory - never in the run that took 44 minutes to produce, after a blanket-wipe bug in this
very branch destroyed that run's resume state and cost a re-run.

| case | gate | wall | baseline |
|---|---|---|---|
| full (`guard-100pct`) | `86 of 86 ... (0 to score)`, 86 skip lines | **29.2 min** | 43.9 min from scratch |
| partial (`guard-90pct`) | `77 of 86 ... (9 to score)`, 77 skip lines | running | - |

**33%, not the "far less" claimed before running it.** The guard removes the feature loads and
dot products (~14.7 min at 86 files). It does NOT remove the row walk: both passes still
traverse all 260 M rows - 18.5 of the remaining 29 minutes - because scoring is only one of
three things they do. Pass 1 feeds the experiment competition; pass 2 feeds `projections`, the
`--model-diagnostics` accumulator, and the sidecar write.

### What that means for the 446 target

| term at 446 | min | status |
|---|---|---|
| per-file score reuse | -137 | done, verified |
| model reuse (`.1st-pass.model.json`) | -21 | built (`a00d45912e`), not yet measured |
| row walk in both passes | ~90 | REMAINS |
| protein FDR + protein q | ~33 | REMAINS |
| survivor reload | ~32 | REMAINS (and is the memory peak) |

Sub-hour is therefore **not** reachable with the guard alone, contrary to the earlier estimate.
It needs the protein-FDR guard (its answers are already in the experiment sidecar) AND a way to
skip pass 2 for a file whose sink output is already on disk - which means relocating what
`projections` and the diagnostics accumulator consume, a design question rather than a flag.

## Progress log - 2026-09-01 (end of session)

Committed on `Skyline/work/20260901_osprey_firstpass_resume` (tip `db5a8b696d`, not pushed):
write-time stamping on the production path, the per-file resume gate, removal of the blanket
marker wipe, persisted-model reuse, compaction-gate entry, and a named reason when that entry
refuses.

Measured on the 86-file plate, all real runs:

| case | wall | to the memory peak |
|---|---:|---:|
| from scratch | 43.9 min | 24m53s |
| partial resume (9 of 86 sidecars missing) | 31.4 min | - |
| full resume, score guard only | 29.2 min | - |
| **full resume, enter at gate** | **9.4 min** | **4m39s** |

Compaction boundary identical either way (`259953530 -> 34524236, 373487 passing base_ids`),
which is the correctness check; the timing is secondary.

**Blocking finding for the 446 baseline**: that directory has neither `.reconciliation.json` nor
`.1st-pass.model.json` - both are `PlanStage6` outputs and the run died before reaching it. So
the fast path refuses (no stratum) AND the bench cannot run (no `first_pass_base_ids`). Develop
the Stage 5 fix at plate scale, then spend ONE 446 run carrying it; that run both completes and
leaves the directory resumable for every iteration after.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260901_osprey_firstpass_resume.md` before starting work.

## (e) The underlying flaw: phase products are persisted at TASK end, not PHASE end

The developer's objection - that three hours of running with files on disk should not be
unrecoverable - is well founded, and the cause is specific rather than general.

FirstPassFDR has three long phases at 446 files and only ONE writes anything while it runs:

| phase | min | durable output DURING the phase |
|---|---:|---|
| train (subset load + SVM) | 21 | **nothing** |
| pass 1 (score + build experiment competition) | 55 | **nothing** |
| pass 2 (re-score + emit) | 82 | per-file sidecars |
| protein FDR | 33 | experiment sidecar, at the end |
| gate + reload + planning | 40 | reconciliation.json + model.json, at the end |

Die halfway through pass 2 and ~220 valid sidecars are on disk and **unusable**: resuming needs
the experiment competition maps, which live only in memory and require all of pass 1, which
requires the model, which requires training. 117 minutes of completed, correct work is lost.

The sharpest form: **the model is trained at minute ~22 and persisted at minute ~250.** For 228
minutes a few hundred KB of fully-computed state exists only in RAM.

### The fix: persist each phase's product when that phase ends

1. **after training** - persist the model. The artifact already exists
   (`.1st-pass.model.json`, `FirstPassModelIO.Save`); it is simply called from `PlanStage6`
   instead of from the end of training.
2. **after the pass-1 barrier** - persist the experiment maps. Also close to an existing
   artifact: `out.1st-pass.fdr_experiment.bin` holds the analysis-wide experiment-scope records,
   but is written after protein FDR. Needs either a two-stage write or a separate maps artifact,
   because protein q is filled in later.
3. **during pass 2** - per-file sidecars. Already correct.
4. **after protein FDR** - experiment sidecar with protein q. Already correct.

With 1 and 2, a death at file 300 of 446 resumes by loading the model and the maps and running
pass 2 for the remaining 146 files. That is proportional recovery, and it is the forward-scan
model applied INSIDE a task rather than only across tasks.

What this branch delivered gets partial credit only: model REUSE works, but reads the sidecar
written at `PlanStage6`, so it helps a completed run and not an interrupted one - which is why
partial resume reached just 28% (31.4 min against 43.9).

**This is the change that answers the original goal** (a machine lost to a Windows Update
recovers proportionally). The per-file score guard was necessary but is not sufficient on its
own.

### (e2) Pass 1 already computes the whole per-file sidecar - write it there

`FdrScoreRecord` is four fields: `EntryId`, `Score`, `RunPrecursorQvalue`, `RunPeptideQvalue`.
Nothing experiment-scoped - that was split to `out.1st-pass.fdr_experiment.bin` in #4486. And
**pass 1 computes all four, per file**:

```
score = ComputeStreamedScore(...)                           -> Score
ComputePerFileRunQvalues(fScores, fLabels, fEntryIds, ...)  -> RunPrec/RunPeptQvalue
buffer.EntryIds[r]                                          -> EntryId
```

So pass 1 builds each file's sidecar, throws it away, and pass 2 recomputes it 82 minutes later
in order to write it. Moving the write into pass 1 gives:

1. **Proportional recovery.** With the model persisted after training, every file's work is
   durable as it completes through pass 1. Die anywhere after minute 21 and one file is lost,
   not two hours - and that does not grow with cohort size. At 1000 files the exposure is still
   one file, where today it would be a ~4:30 gap.
2. **Pass 2 stops re-scoring even on a cold run.** The earlier note called this "55 min of pure
   recomputation" and dismissed retaining the scores as ~11 GB at 446. Wrong framing: they do
   not need retaining, they need WRITING - to a file that must be written anyway. Pass 2 reads
   them back through the path `tryStreamCompletedScores` already implements.

| die during | lost today | lost with this |
|---|---|---|
| training (0-21 min) | 21 min | 21 min |
| pass 1 (21-76) | everything | one file |
| pass 2 (76-158) | everything | one file |

The per-file sidecars were the right shape all along; they are written one whole phase too late.
Today's run survived only because it died after pass 2 had written all 446.

**Verify before implementing**: that the score pass 1 computes is bit-identical to pass 2's.
Both call `ComputeStreamedScore` with the same averaged fold weights, so it should be, but the
regression gate is byte-identical output and this is the assumption it rests on.

### (e3) THE TARGET DESIGN: one immutable artifact per phase, written when that phase ends

Settled with the developer 2026-09-01. Every phase's product becomes durable at the moment it
exists, nothing is ever rewritten, and the only work at risk anywhere is a single in-flight file.

```
after training      -> .1st-pass.model.json          guards 21 min   (exists; called from PlanStage6 today)
during pass 1       -> per-file .1st-pass.fdr_scores.bin, per file   (exists; written in pass 2 today)
after pass 2        -> experiment-scope file          guards 82 min  (exists, but written after protein FDR)
after protein FDR   -> protein-q file                 guards 33 min  (NEW - see below)
during planning     -> .reconciliation.json, per file                (already correct)
```

**No new formats and no new concepts** - three of the five artifacts already exist and are simply
written later than the phase that produced them. The immutable + atomic (`FileSaver`) design is
what makes moving the writes earlier safe: a reader can trust whatever it finds, so there is no
reason to defer a write until "everything is certain".

#### The protein-q split, and the rule behind it

`out.1st-pass.fdr_experiment.bin` currently carries precursor q, peptide q, PEP, aggregate score
AND protein q, and is written once after protein FDR - complete, never mutated, so the existing
code is NOT guilty of placeholder columns. It is guilty of the other half: pass 2's 82 minutes
of experiment-scope work sits in an `FdrExperimentAccumulator` in RAM while protein FDR runs, and
dying in protein FDR discards all of it.

Split into TWO immutable files joined on entry_id at read time - **not** one file revisited:

| written by | when | contents |
|---|---|---|
| pass 2 | pass 2 ends | entry_id -> precursor q, peptide q, PEP, aggregate score |
| protein FDR | protein FDR ends | entry_id -> protein q |

> **The rule: a column lives in the file written by the phase that computes it.**

That is the rule that dissolves the recurring "where should PEP live" question, and it is why
"add the column in a second stage" must never mean write-then-update. `FdrExperimentSidecar.ReadMap`
becomes two reads merged, which is cheap.

#### Why pass 2 does not collapse

Pass 1 computes all four fields the per-file sidecar stores (`EntryId`, `Score`,
`RunPrecursorQvalue`, `RunPeptideQvalue`), so pass 1 can write it. But pass 2 is NOT redundant:
its unique product is the experiment-scope values, which cannot exist before the barrier turns
`streamingQ` into `pepByEntryId` / `expPrecByWinnerId` / `expPeptByPeptide` / `expAggByEntryId`,
and the barrier needs every file's pass-1 contribution.

What pass 2 loses is only the expensive half - reloading features and re-running
`ComputeStreamedScore`. It reads the score from pass 1's sidecar instead, through the path
`tryStreamCompletedScores` already implements. It keeps the row walk, the map lookups and the
sink feed.

#### Resulting recovery profile

| die during | today | with this |
|---|---|---|
| training | 21 min | 21 min |
| pass 1 | everything before it | one file |
| pass 2 | everything before it | one file |
| protein FDR | pass 2 as well (82 min) | nothing |
| planning | reload + planning | one file |

Exposure stops growing with cohort size: at 1000 files it is still one file, where today the
unguarded window would be roughly 4h30m.

#### Assumption to verify first

Pass 1 and pass 2 must produce a **bit-identical** score - both call `ComputeStreamedScore` with
the same averaged fold weights, so they should, but the regression gate is byte-identical output
and this is the claim it rests on. Check it before moving the sidecar write.

## Progress log - 2026-09-01 (evening session): (e3) implemented, phases 1, 2 and 4

Goal set by the developer for this session: **(1) stage sidecar writes that protect completed
work and allow within-task resuming; (2) once proven and committed on the single plate, solve
the reconciliation memory spike; (3) prove it on 446 files, all through `--task FirstPassFDR`.**
The first 446 attempt is expected to take ~4 h, and iterating after a failure under an hour,
because the sidecar staging makes the re-entry cheap.

### Committed on `Skyline/work/20260901_osprey_firstpass_resume`

| commit | what |
|---|---|
| `4142c313c1` | model persisted when TRAINING ends; stratum split into its own file, persisted when PROTEIN FDR ends |
| `e74dfff48d` | per-file 1st-pass sidecar written during PASS 1, and read back by pass 2 |

Both green on `regression.ps1 -Dataset Stellar` - all twelve checks, including mode 1
byte-identity against the golden and mode 3's `per-file FDR sidecars==straight (3,445,490
records)`, which is the direct proof that a sidecar written in pass 1 is byte-identical to the
one pass 2 used to write.

### (e3) status against its own five artifacts

| phase ends | artifact | before | now |
|---|---|---|---|
| training | `.1st-pass.model.json` | PlanStage6, 228 min later at 446 | **as training returns it** |
| pass 1, per file | `.1st-pass.fdr_scores.bin` | pass 2, one phase late | **pass 1** |
| pass 2 | experiment-scope q + PEP + aggregate | after protein FDR | unchanged - see below |
| protein FDR | protein q | after protein FDR | unchanged |
| protein FDR | protein-compact stratum | PlanStage6 | **`.1st-pass.stratum.json` at protein FDR's end** |
| planning, per file | `.reconciliation.json` | after ALL files planned | **as each file is planned** |

**The experiment-scope split (the protein-q file) is DEFERRED, deliberately.** It guards the
smallest of the phases (protein FDR, 33 min at 446) and it is the only item that needs a format
change - which would have to enter `FirstPassFdrTask.ValidityKey` to be safe, invalidating every
1st-pass sidecar in the plate and 446 directories and forcing a fresh multi-hour run before the
memory work could iterate. Sequenced after the memory fix, when a fresh 446 directory exists
anyway. Nothing else in (e3) is outstanding.

### What this changes about recovery

A run interrupted anywhere from minute ~21 (training's end) now keeps: the model, every file
whose pass-1 scoring completed, and - once protein FDR has run - the experiment sidecar and the
stratum. That is exactly the set `canEnterAtGate` needs, so a run killed at the survivor reload
(the memory spike, which is AFTER protein FDR) re-enters at the compaction gate instead of
repeating the score passes. That was the blocking finding of the previous session: the 446
directory had neither `.reconciliation.json` nor `.1st-pass.model.json` because both were
PlanStage6 outputs and the run died before it.

### Side effects worth knowing

* **Pass 2 no longer reloads features on a cold run.** It reads the score back from the sidecar
  pass 1 just wrote, through the path `tryStreamCompletedScores` already implemented. At 446
  files pass 2 was 82 min, most of it feature loading and dot products.
* **A resumed run no longer rewrites the sidecars it adopted.** It used to rewrite every one
  (~35 GB at 446), which also meant re-stamping artifacts a marker already attested.
* **The model is reused on a PARTIAL resume**, not only when every file is already scored. It is
  a function of the cohort, arm and seed, all of which the validity key covers - and the model
  file is now stamped, which is what makes adopting it safe without the all-sidecars corroboration.
* **The HPC relay carries one more artifact.** `regression.ps1`'s phase2 -> phase3 -> phase4 hops
  now copy `.1st-pass.stratum.json` beside `.1st-pass.model.json`. An orchestrator that copies
  the model and not the stratum hits `Pass2FdrSidecar`'s fail-fast under the default
  protein-compact mode. Documented in `docs/12-second-pass-fdr.md`.
* One pre-existing red was cleared on the way: a `RunStreamingFirstPass` doc comment stranded
  above `TryLoadCompletedScores` had been failing the zero-warning inspection gate on this
  branch (3 `InvalidXmlDocComment`).
