# TODO-20260901_osprey_stage5_reload_materialization.md - Stage 5 collects all survivors into one O(files) buffer

**Found**: 2026-09-01, by the 446-file CHS join that this was supposed to be the baseline for.
The join ran 5h14m and was killed thrashing. See
`ai/.tmp/handoff-20260901_chs_446file_night_session.md` for the full session.

> **CORRECTION (same day).** This file first said the step "materialises 1.34 B entries before
> compacting to 289 M". That was wrong and the distinction matters. The 1.34 B entries are
> **streamed** - ingest, Percolator and q-value assignment all run between 5 and 21 GB, which is
> #4438/#4486 working exactly as designed. What blows up is the step AFTER: collecting the
> **289 M survivors** into one all-files buffer at ~274 B/entry.

## The defect

`FirstPassFdrTask.ReloadFirstPassSurvivors` loads each file's survivors through
`FirstPassSurvivorLoader` - which already filters during the parquet read, so the per-file load
is lean - and then collects every file's list into one buffer. Its own comment names the
problem:

> *"The per-file load is the reusable half and lives on the loader; the collection into one list
> is the O(files) half this method still performs. Keeping them separate is what lets a consumer
> take the loader alone and never build the buffer - the direction issue #4526 is headed."*

So this is **#4526**, measured at the size where it stops being survivable.

```
03:37:51  Streaming first-pass ingest from 446 file(s)      man  5.7 GB
03:41:24  streaming ingest: 1,342,686,095 rows              man  7.3 GB   <- streamed, 3.5 min
04:03:10  Running First-pass Percolator on 1,342,686,095    man 13.4 GB
04:58:30  Assigning q-values to 1,342,686,095 entries       man 11.4 GB
06:56:13  first-pass protein FDR done                       man 19.2 GB
07:13:56  Reloading first-pass survivors from 446 file(s)   man 21.4 GB
08:17:15  compaction 1.34 B -> 289 M reported               man 100.0 GB  <- the only blowup
```

289 M x 274 B = 79 GB of live data; measured peak 102.2 GB, so ~1.35x that with GC overhead.
The same ratio holds at 257 files (133 M x 274 B = 36.4 GB live, 49.1 GB measured), which is
what makes the model trustworthy.

## Why it looks superlinear in FILES

Survivors per file **rise with cohort size** - 0.517 M/file at 257, 0.648 M/file at 446 -
because cross-run reconciliation transfers detections into files where they were not
independently found. That is the effect `ai/scripts/Osprey/CHS/README.md` already documents for
observations (0.410 M/file at 86 -> 0.533 M/file at 257). Entries in scale linearly; the buffer
scales with survivors, and survivors scale faster than files.

## Measurements

| files | entries in | entries out | total heap at compaction | reload+compact wall |
|---|---|---|---|---|
| 257 (`chs-257files-...-s57base257`) | 764,427,887 | 132,912,754 | 49.1 GB | 14m49s |
| 446 (`chs-446files-...-baseline-phase3`) | 1,342,686,095 | 288,920,200 | 102.2 GB | 63m19s |

* Entries INGESTED scale linearly: 2.974 M/file at 257, 3.011 M/file at 446 - and they stream.
* SURVIVORS scale superlinearly: 0.517 M/file at 257 -> 0.648 M/file at 446.
* Heap tracks survivors, giving **N^1.33** overall - x2.08 heap for x1.74 files.
* The rest of FirstPassFDR is lean: **p10 7.9 GB, p50 10.5 GB**. This is one spike, not a pool.

The 446 peak was reached while paging and Server GC behaves differently under pressure, so
treat 1.33 as an upper bound on the exponent rather than a fitted law. The optimistic
linear-in-files bracket still puts 446 at 85 GB.

## Why hardware is not the answer

Peak proportional to N^1.33 means max cohort proportional to RAM^0.75:

| RAM | max files (compaction peak inside RAM) |
|---|---|
| 63.7 GB (current box) | ~280 |
| 128 GB | ~470 |
| 256 GB | ~800 |

Quadrupling RAM buys 2.8x the files. 446 barely fits in 128 GB with nothing to spare.

## The fix

**Not** "filter during the reload" - `FirstPassSurvivorLoader` already does that (#4486), and
that is why the per-file load is cheap. The fix is #4526: **stop building the all-files buffer
at all.** Stage 6 and Stage 7 both consume it one file at a time, and the loader is already
published as a byproduct precisely so they can call it per file instead. Removing the
collection removes the O(files) term outright rather than shrinking its coefficient.

The Phase 3 lean row is complementary, not superseded: it shrinks the 274 B/entry that this
buffer is 289 M copies of, and it also shrinks whatever a per-file consumer holds. Do #4526
first - it removes the term; the lean row then makes what remains cheaper.

Validate at 446 directly on the 63.7 GB box: a fix that clears 446 there is self-proving, and
one that does not is caught by the same `--timestamp --memstamp` instrumentation that caught
this. Do not measure success by wall time on a run that paged.

## Relationship to the Phase 3 lean row

They act on the **same** buffer from two directions, so they are complementary rather than
alternatives. This one removes the O(files) collection; the lean row shrinks the 274 B/entry it
is built from. Sequence this first - a 446-file run never reaches Stage 7 today, so the lean row
cannot even be measured at 446 until the Stage 5 buffer is gone.

## State on disk

* `chs-446files-libdecoy-r1.0-protein-compact-baseline-phase3` — the killed run. `run.log`
  carries a `KILLED BY OPERATOR` line recording that everything after 07:13:56 is page-fault
  bound and must not be read as a baseline.
* It holds 446 `.1st-pass.fdr_scores.bin` (35.0 GB) — the per-file half, complete — but **no
  `.FirstPassFDR.osprey.task` markers**, because the stage never finished. Do not hand-write
  those markers to reuse the work: that manufactures a completion record for a stage that did
  not complete. A re-measurement pays the ~2.7 h per-file pass again.
* All 446 Stage 1-4 parquets are staged and joinable at 26.1.1.243 via
  `runs\_linksrc\{p0059,p0060,p0061,p0062,p0063_0064}` — a fix can be tested immediately
  without redoing any scoring.

## DEFERRED: single-node per-file parallelism in the two Percolator passes

Measured on the 446-file run, pass 1 (score + per-file run q) is 55.3 min and pass 2 (re-score
+ q assignment) is 82.1 min - 137 min, ~53% of the task. Both are plain sequential
`for (int f = 0; f < nFiles; f++)` loops in `PercolatorScorer`, and **nothing algorithmic keeps
them sequential**:

| shared across the file loop | nature |
|---|---|
| `featureBuf`, `buffer` | reusable scratch - per-thread |
| `streamingQ` | accumulator, commutative, mergeable |
| `minRunBothByEntryId` / `ByPeptide` | min-reductions, commutative |
| `contribAcc` | feature contributions, commutative |
| `nonEmptyFiles`, `g1` | counters - interlocked |

`ComputePerFileRunQvalues` is already called per file on that file's own arrays; run-level FDR
is per-file by definition. So this needs **no task split** - a `Parallel.For` with per-thread
scratch and per-thread accumulators merged at the end would do it, and would take those 137 min
to roughly 10-20 at 8-16 way.

**Deferred deliberately (2026-09-01, developer's call).** Concurrency multiplies the per-file
working set inside a task whose memory is already the thing that killed the 446-file run, and
these two passes are NOT where the memory problem is - they held 11-13 GB throughout. Adding
concurrency here before the Stage 5 buffer is fixed would spend memory headroom exactly where
there is none to spare.

Revisit AFTER the buffer is gone, and price it then on a measured per-file resident cost during
the passes rather than the estimate above.

The related three-task split (ModelTraining / PerFileFDR / FirstPassFDR) is a different
question: it buys per-file memory on SEPARATE nodes and independent restart granularity, not
parallelism. It also inherits the cross-node reduce at the pass-1/pass-2 barrier and makes every
worker repay the 9.5 min library load. Only worth it if single-node parallelism proves
memory-bound.

## REFINED (2026-09-01, after reading the code): #4526 fixed the HOLD, not the BUILD

`OspreyEnvironment.Stage6StreamSurvivors` is **already DEFAULT ON**, and its own doc names this
issue: *"That buffer is 88.9 M entries / 28 GB live at 163 files, held for the 5.5 hours of
Stage 6, and it grows super-linearly in file count because the passing base_id set grows too
(issue #4526)."*

But look at the order in `FirstPassFdrTask`:

```
line 2654   ReloadFirstPassSurvivors(...)         <- BUILDS all 446 files' survivors ** PEAK **
line 2660   count, log "compaction: 1.34 B -> 289 M"
line  552   kvp.Value.Clear() / TrimExcess()      <- releases them, post-planning
```

So Stage 6 no longer *holds* the buffer for hours - that is fixed and shipping. Stage 5 still
*builds* it, pays the 100 GB peak, runs `PlanStage6` while it is resident, and only then clears
it. **The 446-file wall is the build, not the hold**, which is why the run died precisely at
`Reconciliation planning`.

## The fix has a precedent in the very file that needs it

`Stage6Planner` already had this exact defect for CWT candidates and already fixed it:

```csharp
// ... the former eager all-files load was the buffer that OOM'd the 82-file Stage-6 planning.
// The planner then streams each file's candidates on demand (LoadOneFile ...)
    fileName => CwtCandidateLoader.LoadOneFile(fileName, perFileParquetPaths),
```

The survivor buffer is the same shape one layer out: `PlanStage6` still receives a materialised
`perFileEntries` and wraps it as `perFileForPlan`. The replacement delegate already exists -
`FirstPassSurvivorLoader.Load(fileName, out error)` - is already published as
`FirstPassSurvivorSource`, and is already what Stage 6 streams from.

**Shape of the work**: give the planner a `Func<string, IReadOnlyList<FdrEntry>>` instead of the
list, exactly as `CwtCandidateLoader.LoadOneFile` is passed today, and stop calling
`ReloadFirstPassSurvivors` on the streaming path.

**The open question to answer first**: the planner's cross-file phases (multi-charge consensus,
cross-run consensus RT) need evidence from all files at once. Determine whether consensus is
built from a PROJECTION of the entries (peptide -> per-file RT + score, order 20 B/row) or from
whole `FdrEntry` rows (274 B). If a projection, the lean row is what makes planning fit and the
two efforts meet here. If whole rows, consensus needs its own streaming pass before the
per-file reconciliation planning can stream.

## Iterating without re-running the 3h45m per-file half

Everything the reload + planning consumes is already on disk in
`chs-446files-...-baseline-phase3`: 446 `.scores.parquet`, 446 `.1st-pass.fdr_scores.bin`
(35 GB), and `out.1st-pass.fdr_experiment.bin`. Only `firstPassBaseIds` is not persisted, and
the compaction gate that computes it took 4.6 min.

Three options, cheapest first:

1. **Harness over the on-disk artifacts** - drive the loader + planner directly against that
   directory. ~15 min/iteration (9.5 min library load + ~5 min gate). No pipeline changes.
2. **Finer-grained resume** - let FirstPassFDR skip its per-file passes when the sidecars are
   valid and re-enter at the compaction gate. Principled, doubles as the feature
   `TODO-20260901_osprey_firstpassfdr_resume.md` wants, but blocked on defect (b) there.
3. **Smaller cohort** - 86 or 171 files exercises the same code at ~45-90 min/iteration and a
   15-30 GB buffer. Useful as a correctness check, useless for the 446-file memory question.

Recommend (1) to develop against and (3) to gate correctness, with (2) as the shipping form.

## The contained reproduction EXISTS (2026-09-01)

`Osprey.Test/Stage5SurvivorBufferBenchTest.cs`, opt-in via `OSPREY_BENCH_RUNDIR`. No pipeline
run, no first pass, no Percolator. It works because **the passing base_id set is already
persisted** - `FirstPassFdrTask` writes it into every `.reconciliation.json` as
`first_pass_base_ids` (format v3), and `RescoreHydration` already reads it back. An earlier plan
to add a new artifact for this was unnecessary.

First measurement, 12-file cohort:

```
passing base ids : 264,209        survivors : 4,101,007
COLLECT peak     : 1.50 GB (22 s)   <- what Stage 5 does today
STREAM  peak     : 0.41 GB (21 s)   <- what the fix does
bytes per entry  : 392 (collect)    reduction : 3.6x
```

**The 3.6x understates the win.** COLLECT is O(files); STREAM is O(one file). At 12 files the
buffer is only 12x one file so fixed overhead dominates the ratio; at 446 files STREAM stays at
roughly one file's survivors (~648 K x 392 B = ~250 MB) against COLLECT's ~100 GB. Streaming
also costs nothing in wall time - the loader already reads per file, collecting merely retains.

392 B/entry against the 274 B production figure is the empty sequence pool (~72 B/entry of
unshared modified-sequence strings plus overhead), which cross-checks the harness against the
real run. Set `OSPREY_BENCH_LIBRARY` to seed it if absolute numbers are wanted.

### Which directories can drive it

| directory | parquets | 1st-pass sidecars | experiment sidecar | base_ids | usable |
|---|---|---|---|---|---|
| `clean-full-12files` | 12 | 12 | 1 | yes | **yes** |
| `resume-test-12files` | 12 | 12 | 1 | yes | **yes** |
| plate `p0059` (86) | 86 | 86 | **0** | yes | **no** |
| 446 `baseline-phase3` | 446 | 446 | 1 | **no** | **no** |

The 2026-08-23/26 plate runs predate #4486's sidecar format and the reader refuses them
("failed to overlay .1st-pass.fdr_scores.bin"), which is also why they carry no experiment
sidecar. The 446 directory has the current format but died before `PlanStage6` wrote any
`.reconciliation.json`, so it has no base_ids.

**To bench at a scale that matters, one current-build run must reach Stage 5 planning.** A
single plate (86 files, ~43 min of first pass) would produce a directory good for every
subsequent iteration.

## Implementation plan (settled 2026-09-01, all four phases inspected)

`Stage6Planner.Plan` runs four phases over `perFileEntries`. Three of them never needed the
buffer:

| phase | shape | needs |
|---|---|---|
| 1 `ComputeMultiChargeConsensus` | `foreach` file -> `SelectRescoreTargets(kvp.Value)` | one file; keeps only small per-file targets |
| 2 `ComputeConsensusRts` | hands ALL files to `ConsensusRts.Compute` | **cross-file, but only 5 fields** |
| 3 `RefitCalibrations` | `foreach` file -> `CalibrationRefit.Refit(consensus, kvp.Value)` | one file + consensus |
| 4 `ReconciliationPlanner.Plan` | already takes `fileName => CwtCandidateLoader.LoadOneFile(...)` | one file at a time |

**Phase 2 is the only genuine cross-file hold, and it reads a projection.** Measured field usage
in `Osprey.FDR/Reconciliation/ConsensusRts.cs`: `ModifiedSequence` (pooled reference),
`IsDecoy`, `Score`, `EntryId`, `RunPrecursorQvalue` - about **37 B/row** against 274 B in
production. (Verify whether an RT field is reached through another accessor before fixing the
record layout.)

### Two passes, no buffer

```
Pass A, per file:  phase 1 targets  +  append the ~37 B consensus projection   -> DROP entries
Barrier:           ConsensusRts.Compute over the projection
Pass B, per file:  phase 3 refit  +  phase 4 reconciliation planning           -> DROP entries
```

Projected peak at 446 files: 289 M x 37 B = **~10.7 GB** for the projection, plus one file's
full entries (~648 K x 392 B = ~250 MB), so **~11 GB against the measured ~100 GB**. Fits 63.7 GB
with room, and the peak stops growing with file count except through the projection.

Cost: each file's survivors are loaded **twice** rather than once. The reload is ~32 min clean at
446 files, so ~64 min - against a run that currently cannot finish at all.

**This is where the Phase 3 lean row and #4526 meet.** The lean row shrinks the projection's
37 B and the per-file 392 B; this change removes the O(files) multiplier on the larger of them.
Neither subsumes the other.

### Validate with

`Stage5SurvivorBufferBenchTest` for the memory shape (seconds), then a full plate run for
byte-identity - only output equality counts, not structure.
