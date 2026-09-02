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

## Bench at plate scale (2026-09-01) - 31.8x

A single-plate `--task FirstPassFDR` run on the branch build (86 files, 43m53s, exit 0)
produced the first CURRENT-FORMAT directory carrying `.reconciliation.json`, hence base_ids:
`chs-86files-libdecoy-r1.0-protein-compact-p0059-fpfdr`. Bench against it:

```
files 86   passing base ids 373,487   survivors 34,524,236
COLLECT peak 15.14 GB      STREAM peak 0.48 GB      470 B/entry      reduction 31.8x
```

Against 3.6x on 12 files - **the ratio grows with the cohort exactly as predicted**, because
COLLECT is O(files) and STREAM is O(one file). Extrapolated to 446: COLLECT ~136 GB at this
bench's 470 B/entry (the real run measured ~100 GB with a seeded pool, consistent), STREAM
~0.7 GB.

**Timing in that report is NOT a valid comparison.** STREAM runs first by design so COLLECT
cannot benefit from a file cache STREAM warmed - which protects the memory number and ruins the
time one (402 s vs 181 s here; 21 s vs 22 s at 12 files, where everything fit in cache). The
per-file load cost is identical for both shapes; only retention differs. A cache-cold A/B in
both orders would be needed to say anything about wall time.

## Three-point scaling confirms the MECHANISM

| files | survivors | per file |
|---|---:|---:|
| 86 | 34,524,236 | 401,444 |
| 257 | 132,912,754 | 517,170 |
| 446 | 288,920,200 | 647,803 |

Survivors grow as N^1.23-1.40 while bytes-per-entry stays flat (~218 B managed measured in the
86-file run's reload, ~274 B documented). So the earlier "heap scales N^1.33" is not the step
getting more expensive per entry - it is reconciliation transferring detections into files where
they were not independently found, so there are simply more survivors per file in a bigger
cohort. Removing the O(files) multiplier is therefore the whole fix, and does not depend on
shrinking bytes-per-entry first.

## CORRECTION to the projection size (2026-09-01, after reading Qualifies + the detection loop)

The plan above said consensus reads five fields, ~37 B/row. **That was from an incomplete scan.**
The full set is ten:

| source | fields |
|---|---|
| `Qualifies` | `IsDecoy`, `RunPrecursorQvalue`, `RunPeptideQvalue`, `ExperimentProteinQvalue` |
| collection loops | `EntryId`, `ModifiedSequence` (pooled ref), `Score` |
| detection tuple | `apexRt`, `peakWidth`, `coelutionSum` |

About **72 B/row** with padding, so at 446 files the projection is **~21 GB**, not ~11 GB.
A packed layout (float for RT / width / coelution, byte for the flag) would reach ~48 B and
~14 GB, which is worth doing but should be measured rather than assumed.

Still decisive against the ~100 GB measured buffer, and still inside 63.7 GB - but the honest
projected peak is **~21 GB plus one file's entries**, not ~11 GB.

## And the lazy shortcut is ruled out

`ConsensusRts.Compute` iterates its input **three times** (ConsensusRts.cs lines 95, 111, 125):
targets, then decoy pairing, then detections. Handing the planner a lazy per-file collection
that reloads on access would therefore reload every file three times inside `Compute` alone,
plus once each for phases 1 and 3. The projection is REQUIRED, not an optimisation.

## SECOND CORRECTION to the projection (2026-09-01, after reading ReconciliationPlanner)

The ten-field list above is still short, and it is short because both scans stopped at
`ConsensusRts`. **`ReconciliationPlanner.Plan` has its OWN cross-file loop over every entry of
every file** (`ReconciliationPlanner.cs:169`), before the per-file planning loop, building
`passingBaseIds`:

```csharp
foreach (var fileKvp in perFileEntries)
    foreach (var entry in fileKvp.Value) {
        if (entry.IsDecoy) continue;
        double bestQ = Math.Min(Math.Min(entry.RunPrecursorQvalue, entry.RunPeptideQvalue),
                                Math.Min(entry.ExperimentPrecursorQvalue, entry.ExperimentPeptideQvalue));
        if (bestQ <= experimentFdr) passingBaseIds.Add((entry.EntryId & 0x7FFFFFFFu, entry.Charge));
    }
```

So "phase 4 already takes a per-file delegate" is true only of the CWT CANDIDATES
(`LoadOneFile`); the ENTRIES are still handed to it as one all-files list, and it reads them
cross-file before it plans. Three more fields, none of them in the list above:

| source | additional fields |
|---|---|
| `ReconciliationPlanner` passingBaseIds | `ExperimentPrecursorQvalue`, `ExperimentPeptideQvalue`, `Charge` |

**Thirteen fields, not ten**: 4 + 8 (string ref) + 1 + 1 + 8x8 = 86 B, ~88 B padded. At 446
files and 289 M survivors the projection is **~25 GB**, not ~21 GB. Still decisive against the
~100 GB measured buffer and still inside 63.7 GB, but the margin is smaller than the last
estimate claimed and this is now the third time the field count has grown on a closer read - so
treat 88 B as a floor to VERIFY with the bench, not a number to quote.

Float-packing the three RT-ish fields is still available (~72 B, ~21 GB), but the q-values must
stay `double`: every one of them is compared against a threshold, and a float-rounded value can
flip a borderline comparison, which is exactly the byte-identity the gate checks.

`passingBaseIds` costs no extra pass - it is a reduction over the same projection the consensus
barrier already walks, so it belongs in that barrier.

## Why the three consensus iterations cannot simply be merged

Worth recording, because "just do it in one pass over files" is the obvious first idea and it
does not work. Step 3's TARGET inclusion test is
`targetPeptides.Contains(modseq) && Qualifies(entry)`, and any target that qualifies had its
modseq added to `targetPeptides` in step 1 - so for targets the test reduces to `Qualifies`
alone and target detections CAN be collected in the first pass.

Decoys cannot. The test is `decoyPeptides.Contains(entry.ModifiedSequence)`, and
`decoyPeptides` is closed over MODIFIED SEQUENCE while the linkage that builds it is over
BASE ID. Those differ: charge 2 and charge 3 of one peptide share a `ModifiedSequence` but have
different base ids. If the charge-2 decoy pairs to a qualifying target and the charge-3 decoy
does not, the sequence-level test admits BOTH detections and a per-entry base-id test would
admit only one. So the per-entry shortcut is not equivalent, and collecting decoy detections
needs `decoyPeptides` already complete - a second pass over all files, or the projection.

Streaming instead of projecting therefore costs FOUR reloads (targets+sets, decoyPeptides,
decoy detections, then phases 3+4), not two. At ~32 min per reload at 446 files that is ~128
min against the projection's ~64. The projection stays the plan.

## THE PROJECTION IS THE WRONG FIX (2026-09-01, with numbers from the 257-file run)

Retracting the settled plan above. A 289 M x 88 B projection is **still an
O(files x entries) structure** - it shrinks the coefficient from 274 B to 88 B and leaves the
shape alone. This file's own "The fix" section already says why that is not the fix
(*"Removing the collection removes the O(files) term outright rather than shrinking its
coefficient"*), and the governing rule is blunter: **any O(files x entries) structure is the
defect, not the baseline** - per-file compute, O(entries)/O(distinct) aggregate, streamed emit.
The projection was reached by asking "what is the smallest row that satisfies the consumers"
instead of "what does the barrier actually have to hold".

### What the barrier actually has to hold, measured

From `chs-257files-libdecoy-r1.0-protein-compact-s57base257/run.log`:

```
First-pass compaction: 764427887 -> 132912754 entries (501247 passing base_ids)
Reconciliation multi-charge consensus: 293362 entries need re-scoring across 257 files
Reconciliation consensus: 48039 target peptides, 47524 decoy peptides
Reconciliation: 13950738 per-(file, entry) actions planned
```

Classifying every structure the four planning phases build:

| structure | order | at 257 | at 446 (est) |
|---|---|---|---|
| `perFileEntries` survivor buffer | **O(files x entries)** | 132.9 M rows, 49 GB | 289 M, ~100 GB |
| 13-field projection of the same | **O(files x entries)** | ~11 GB | ~25 GB |
| `targetPeptides` / `decoyPeptides` | O(distinct peptides) | 95.6 K | ~0.1 M |
| `targetBaseIds`, `passingBaseIds` | O(distinct base ids) | 501 K | ~0.9 M |
| `detections` | O(distinct peptides x files) | ~24 M x 40 B = ~1 GB | ~42 M, **~1.7 GB** |
| `consensus` | O(distinct peptides) | 95.6 K | ~0.1 M |
| `perFileConsensusTargets` | O(rescore targets) | 293 K | ~0.5 M |
| `reconciliationActions` | O(files x actions) | 13.9 M | ~24 M, ~2 GB |

**The consensus barrier is ~2 GB, not 25.** 95.6 K peptides survive the consensus gate, and a
peptide is detected roughly once per file, so the cross-file evidence is bounded by
`distinct peptides x files` - three orders of magnitude below the survivor count. Everything
else at the barrier is O(distinct). Holding a projection of all 289 M survivors to compute a
median over 42 M detections is the whole defect in miniature.

### The design: stream, keep only the reductions

**Two passes over files, ~2 GB resident at the barrier:**

```
Pass A, per file (load -> use -> DROP):
    phase 1  MultiChargeConsensus.SelectRescoreTargets        -> per-file targets (small)
    consensus step 1  targetPeptides, targetBaseIds, and TARGET detections
    consensus step 3 (decoy half)  ALL decoy detections, plus decoy modseq -> base ids seen
    ReconciliationPlanner passingBaseIds
Barrier (no file I/O):
    decoyPeptides = { modseq : seen(modseq) intersects targetBaseIds }
    prune decoy detections whose modseq is not in decoyPeptides
    per-peptide weighted-median consensus
Pass B, per file (load -> use -> DROP):
    phase 3  CalibrationRefit.Refit(consensus, entries)
    phase 4  ReconciliationPlanner per-file planning + WriteReconciliationFiles
```

Target detections can be collected in pass A because step 3's target test reduces to
`Qualifies(entry)` - any target that qualifies had its modseq added to `targetPeptides` in step
1, so the `targetPeptides.Contains` half is always true for them. Decoy detections cannot be
filtered during pass A (that needs `decoyPeptides`, which needs all of `targetBaseIds`), so they
are all collected and pruned at the barrier. That is what buys the SECOND pass back: the naive
streaming reading of `Compute`'s three loops costs four reloads, this costs two - the same as
the projection - at a twelfth of the memory.

The unpruned decoy detections are the transient peak. Bounded by decoy survivor observations of
peptides that reach the collection at all, not by all 289 M survivors; measure it, do not assume
it. If it turns out large, the fallback is a third pass, not a projection.

### Shape of the code change

`ConsensusRts.Compute` becomes a thin wrapper over a new accumulator (`AddFile` per file,
`Build` at the barrier) so the resident path, `FdrTest` and the streaming path cannot drift.
`ReconciliationPlanner.Plan` splits the same way: its `passingBaseIds` loop becomes an
accumulator fed in pass A, and its planning loop takes one file at a time.
`FirstPassFdrTask.ReloadFirstPassSurvivors` then has no caller and goes, along with the
`perFileEntries` contents - `CompactFromSidecars` returns the per-file shape with empty lists
and the compaction count line takes its `afterCount` from the pass-A tally.

## IMPLEMENTED 2026-09-01 (evening), and what is left after it

The streaming decomposition above is on `Skyline/work/20260901_osprey_firstpass_resume`.
`FirstPassFdrTask.ReloadFirstPassSurvivors` no longer runs on the default path: the compaction
gate publishes the loader and per-file EMPTY lists, and `Stage6Planner` drives two per-file
passes over that loader. `ConsensusRts.Compute`, `ReconciliationPlanner.Plan` and
`GapFillTargetIdentifier.Identify` each keep their all-at-once entry point as a thin wrapper
over the new per-file form, so the resident paths and the tests cannot drift from the streamed
one. Green on `regression.ps1 -Dataset Stellar`, all twelve checks, byte-identical to the
golden.

Two things fell out of the design that are worth recording:

* **The compaction survivor count is now arithmetic.** Nothing materializes the survivors, so
  `First-pass compaction: X -> Y` takes Y from rows-per-base_id summed over the passing set -
  free, because the gate pass already visits every record and computes every base_id. The
  `OSPREY_STAGE6_STREAM_SURVIVORS=0` path still materializes, and now ASSERTS the two agree, so
  a wrong count cannot hide on the streamed path where nothing else could notice.
* **`OSPREY_STAGE6_STREAM_SURVIVORS=0` still builds the buffer.** It is documented as the A/B
  byte-identity oracle for the streamed default and it can only be that if it still produces
  what the streamed path replaced. Deleting it would have been the cheaper diff and the wrong
  one.

### The next O(files x entries) term, not this one

`reconciliationActions` - `Dictionary<(string File, int Index), ReconcileAction>` - is 13.95 M
entries at 257 files and ~24 M at 446, roughly 2 GB. It is built during pass B and published for
the IN-PROCESS Stage 6 rescore.

**Under `--task FirstPassFDR` it is built and then thrown away**: that path returns right after
planning and never publishes it. The per-file envelope is written from the per-file action list,
not from the join-wide map, so the map has no reader at all on the boundary run. Skipping its
construction there (keeping only the count for the log line) is ~10 lines and ~2 GB on exactly
the run the 446 baseline is. Not folded into the change above so that the plate and 446
measurements are of one thing; do it next if the 446 run wants the headroom.

## MEASURED at plate scale, 2026-09-01 evening: 2.4x less memory, boundary identical

`chs-86files-libdecoy-r1.0-protein-compact-p0059-stage5stream` (streamed) against
`chs-86files-...-p0059-fpfdr/run-20260901_131329.log` (the materialized 43m53s baseline). Same
86 files, same library, same arm, same `--task FirstPassFDR`.

| | baseline (materialized) | streamed |
|---|---|---|
| compaction boundary | `259953530 -> 34524236 entries (373487 passing base_ids)` | **identical** |
| peak managed heap, planning window | **30.89 GB** | **12.91 GB** |
| peak working set, planning window | **38.56 GB** | **20.16 GB** |
| `[MEM after Stage-5 CompactFirstPass]` WS | 24.72 GB (peak 26.24) | 19.60 GB (peak 23.80) |
| survivor reload | 2m21s | **no reload at all** |
| planning | 5m42s | 9m32s (2m37s scan + 6m55s plan) |
| wall | 43m53s | 44m58s |

**The boundary being byte-identical is the load-bearing result** - not the memory. Nothing at
3 files could check it: the survivor count is now summed from rows-per-base_id rather than
counted off a materialized buffer, and the Stellar gate compares blibs, not that arithmetic.
Reproducing `34524236` exactly on 86 files is what says the sum is right.

**Wall time is 2.5% WORSE, and that is the honest trade.** The second planning pass costs more
than the removed reload gives back. This change buys memory and recoverability, not speed; do
not quote it as a speedup.

### Correction to the (e3) claim about pass 2

The resume TODO projected that moving the sidecar write into pass 1 would stop pass 2
re-scoring and save ~55 min at 446. Measured on this plate, per phase:

| phase | baseline | with the pass-1 write |
|---|---|---|
| training-subset load | 3m54s | 3m51s |
| pass 1 | 8m35s | **12m07s** |
| pass 2 | 14m27s | **11m32s** |
| both | 23m02s | 23m39s |

Pass 2 did get faster by 2m55s - the feature reload really is gone - but pass 1 absorbed the
sidecar write and paid it back. **Net +37s on 23 minutes, one run each: neutral within noise.**
The write MOVED, it did not disappear. So the 446 run is still a ~4 h job, and the value of the
pass-1 write is that an interruption costs one file instead of two phases.

### What the numbers say about 446

The removed term is the O(files) one, so the gap widens with cohort size rather than staying at
2.4x. The materialized path measured 102.2 GB at 446 and could not finish on a 63.7 GB box. The
streamed path holds, at the barrier, only the consensus reductions (~96 K peptides, ~24 M
detections at 257 files) plus one file's entries - and the decoy detections collected before
pruning, which is the one term still to watch at scale.

## 446-FILE RESULT, 2026-09-02: the spike is gone

`chs-446files-libdecoy-r1.0-protein-compact-stage5stream`, `--task FirstPassFDR`, branch tip
`46a239393b`. Same 446 files, same library, same arm as the killed baseline.

| | baseline-phase3 (build 243-20260831-1639) | branch tip |
|---|---|---|
| entries in | 1,342,686,095 | 1,342,686,095 |
| **peak at compaction** | **102.2 GB, paging, killed** | **31.81 GB (WS 25.47, managed 13.37)** |
| survivors held | 288,920,200 | **342,715,751** |
| survivor reload | 63m19s, page-fault bound | **none - no buffer is built** |

**The larger survivor set makes the result stronger, not weaker**: 342.7 M survivors carried in
31.8 GB where 288.9 M cost 102.2 GB - about 3.9x less memory per survivor, and no paging.

### An unexplained discovery-set delta, NOT attributable to this change

The two runs disagree upstream of the buffer:

| | baseline-phase3 | branch tip |
|---|---|---|
| precursors passing run-level FDR | 4,376,266 | 4,599,744 |
| protein-compact stratum | 630,655 base_ids | (pending) |
| passing base_ids | 625,620 | 744,943 |

Same inputs (entries in are identical to the row), same library, same arm, same peak-pick model,
same train-set policy. **The builds differ**: baseline-phase3 ran `26.1.1.243-20260831-1639`,
which PREDATES this branch.

It is not this branch's Stage 6 work:

* the 86-file plate on the branch tip reproduced the immediately-prior build's boundary
  EXACTLY - `259953530 -> 34524236 entries (373487 passing base_ids)`;
* `regression.ps1 -Dataset Stellar` is byte-identical to the committed golden across all
  twelve checks.

So the delta entered somewhere between the 08-31 build and the branch tip - the earlier
commits on this branch, or master. **Queued a change-immune anchor rather than a guess**: the
same 86-file plate run on the `26.1.1.243-20260831-1639` snapshot. Boundary equal to
`34524236 / 373487` means the pre-branch build agrees and the delta entered during the branch;
unequal means it predates the branch. `bisect-plate-prebranch.launch.log` records the verdict.

**Do not read the 446 boundary as a regression until that anchor reports.** Note also that
288.9 M was measured on a run that was killed while paging; nothing else has ever reproduced it.

### ANCHOR RESULT 2026-09-02 03:29: all three builds AGREE at 86 files

```
pre-branch build 26.1.1.243-20260831-1639, 86 files:
  First-pass compaction: 259953530 -> 34524236 entries (373487 passing base_ids)
```

Identical to the plate baseline AND to the branch tip. So pre-branch, mid-branch and branch tip
all agree at plate scale.

**The verdict line the anchor script printed ("the delta entered DURING the branch") is WRONG**
and should be ignored - it assumed the plate baseline came from a mid-branch build only. What the
result actually establishes is the opposite: **no build difference is visible at 86 files at
all**, so the 446 delta is not explained by anything the plate cohort exercises.

The open question is therefore sharper, not answered:

| | baseline-phase3 (446) | branch tip (446) | all builds (86) |
|---|---|---|---|
| entries in | 1,342,686,095 | 1,342,686,095 | 259,953,530 |
| precursors passing run-level FDR | 4,376,266 | 4,599,744 | agree |
| passing base_ids | 625,620 | 744,943 | 373,487 (agree) |

**Hypothesis, NOT a finding**: the trained model differs. The SVM training subsample is drawn
cohort-wide (`MaxTrainSize` 300 K out of 1.34 B rows at 446, out of 260 M at 86), so a
selection difference that is invisible when the pool is 5x smaller would move the model, and a
different model moves run-level q and therefore the passing set. Two ways to test it cheaply
before spending another 446 run:

1. Compare the two runs' `[COUNT] First-pass Percolator streaming subsample` lines and the
   trained fold weights - the 446 baseline's log still exists, and `.1st-pass.model.json` is now
   persisted by the branch tip, so the models can be diffed directly.
2. If the subsample sizes match but the weights differ, the difference is in training, not
   selection.

Until that is settled, **do not describe the 446 boundary as either a regression or an
improvement.** Note also that 288,920,200 was measured on a run that was killed while paging and
has never been reproduced.

## THE NEXT WALL, MEASURED 2026-09-02: Stage 6/7 rescore at ~110 GB on 446 files

The extra-credit second-pass run (`chs-446files-...-secondpass`, `--task PerFileRescoring` over
the completed FirstPassFDR directory) reached:

```
05:18:23   92.26% (823/892, 1h41m elapsed)   managed 109,989 MB   working set 112,031 MB
```

**~110 GB on a 63.7 GB box** - paging, at 378 of 446 files.

This is NOT a regression from the Stage 5 work; it is the term the regression gate already names
in its own "Known O(files) resident paths" block:

> **#4486** - SecondPassFDR pulling `RescoredEntries` rebuilds the whole-run survivor buffer it
> reads (#4597 moved the build off the end of Stage 6, which does not shrink it); resident for
> the whole of Stage 7. ~4.4 GB library + 0.197 GB/file live post-GC: ~20 GB at 82 files,
> **~103 GB projected at 500**.

**Projected ~103 GB at 500 files; measured ~110 GB at 446.** The estimate was good, and it is now
a measurement.

It is the SAME SHAPE this change just removed from Stage 5 - one whole-run buffer over every
file's survivors - one stage downstream. Removing the Stage 5 buffer is what let a 446-file run
get far enough to hit it. The fix is the same in kind: Stage 7's input is a per-file stream, not
a pool, and #4486 is the issue that owns it.

Sequencing note: this is now the binding constraint on a 446-file end-to-end run. The Stage 5
work is done; the next cohort-scale blocker is #4486, and it has a measured number to aim at.

### CORRECTION 2026-09-02 06:40: that ~110 GB is NOT #4486, and the run is not a clean measurement

Two errors in the entry above.

**1. Wrong term named.** The peak was attributed to #4486's whole-run `RescoredEntries` buffer
from the memory number alone. The log says otherwise:

```
03:36:15  [TASK] PerFileRescoring:starting
03:37:19  Hydrating reconciliation bundle...
06:31:23  Hydrated rescore bundle for 446 file(s) (30,841,614 reconciliation actions, ...)
```

**2h54m to hydrate ONE whole-cohort rescore bundle** - every file's entries plus 30.8 M
reconciliation actions, resident together. That is `PerFileRescoreTask`'s bundle hydration, and
Stage 7 / #4486 has not been reached yet. It IS the `reconciliationActions` term this file
already flagged as "the next O(files) term" - estimated ~24 M actions / ~2 GB, measured
**30.8 M actions** and far more than 2 GB once it coexists with the entries.

**2. The run is degraded, so its numbers are indicative only.** `-LinkFrom` did NOT stage the
analysis-wide `out.1st-pass.fdr_experiment.bin` (verified absent), so:

```
[ERROR] First-pass compaction: failed to read the experiment-scope FDR sidecar
[MODEL-DIAGNOSTICS] peak co-assignment skipped: no 1st-pass experiment-scope FDR records
```

and the run CONTINUED rather than stopping. The protein-rescue half of the compaction predicate
reads that file, so the retained set this run computed is not the one the completed FirstPassFDR
run produced. **Do not quote this run's identifications.** Re-stage with the experiment sidecar
(the hand-rolled `stage-446-secondpass.ps1` includes it; `Run-Chs.ps1 -LinkFrom` does not).

Worth an issue on its own: a missing experiment sidecar sets ExitCode=1 in
`LoadFirstPassExperimentRecords` and the run keeps going and reports success-shaped output. That
is the "hard fail over warn-and-proceed" rule being violated on a path that silently changes the
result.

### What this says about the HPC direction (the developer's question)

*"If the task were sent to 1 computer per file would it produce valid results? Would each
computer go through such an expensive preamble?"*

**Valid: yes, and it is already proven** - regression mode 3 runs `--task PerFileRescoring` with
ONE file per phase-3 directory and asserts the final blib is byte-identical to straight-through.
That leg passed on all four datasets in TeamCity 4161271.

**Expensive preamble: no.** A per-file node hydrates only its own file's bundle and takes the
join-wide passing base_id set from `first_pass_base_ids` in its relayed `.reconciliation.json` -
the field exists exactly so a node holding one file compacts to the join's set. It still repays
the ~9.5 min library load per node, which is the known per-node cost.

So the O(files) hydration measured here is a property of running 446 files in ONE process, not of
the rescore task itself. The single-process route is what needs the fix; the farmed route already
has the right shape.

## THE PerFileRescoring EXPERIMENT-WIDE JOIN - root-caused 2026-09-02, NOT yet fixed

**Developer's requirement**: entering PerFileRescoring must truly iterate over the files it was
handed, holding only per-run data. In HPC a node assigned one run would not even HAVE the files
to build an experiment-wide buffer.

### It is pre-existing, not moved by this branch

Verified: `git diff master...HEAD` shows **zero non-comment changes** in `PerFileRescoreTask.cs`
and **no changes** to `Rehydrate`, `LoadOwnReconciliationBundle`,
`StreamOwnReconciliationBundle` or `HydrateRescore`. This branch did not reconfigure it. It
became visible because nobody had ever run PerFileRescoring on 446 files - FirstPassFDR could
not finish at that scale until now.

### Root cause: the pool is forced by task MEMBERSHIP, not task EXECUTION

`PerFileScoringTask.PreCompactionPoolReason` forces the RESIDENT pre-compaction pool when
`FirstPassFdrTask.IsIncludedFor(config)` is true, on the reasoning "FirstPassFDR is IN this
pipeline, so it will Run and train first-pass Percolator off ScoredEntries - which has to be the
full pre-compaction pool".

Under `--task PerFileRescoring`, `IsIncludedFor` returns TRUE:

```csharp
return (!inputs && !c.NoJoin)
    || (inputs && c.StopAfterStage5)                      // --task FirstPassFDR
    || (inputs && !c.NoJoin && !c.ExpectReconciledInput); // <- TRUE here
```

But FirstPassFDR does not RUN there - its outputs are valid, so it **Rehydrates**, and the
pre-compaction pool it was reserved for is never used. With fat stubs published,
`leanStubs == false` in `FirstPassFdrTask`, so the batch
`RescoreHydration.HydrateReconciliationOverlay` runs instead of the per-file
`StreamOwnReconciliationBundle`.

**The per-file machinery already exists and works** - a 3-file test emitted
`Resume rehydrate: streaming the first-pass bundle from 3 file(s) (one file's pre-compaction
pool resident at a time)`. The 446 run never reached it.

Measured cost of getting it wrong:

| | 1 file (node shape) | 446 files (one process) |
|---|---|---|
| reconciliation actions hydrated | 74,525 | 30,841,614 |
| bundle hydration | instant | **2h54m** |
| peak working set | 19.32 GB | **~110 GB** (thrashed, killed) |

74,525 x 446 = 33.2 M, so it is linear in files - O(files) exactly as the developer suspected.

### Why the regression gate passes anyway

Mode 3 phase 3 gives each node **ONE file**, so the O(files) buffer is O(1). Mode 1 runs all
files in one process but only THREE of them. **No test puts many files through PerFileRescoring
in a single process**, which is the only configuration where this hurts. The suite is complete
over the per-node shape and structurally blind to the multi-file one - the same shape of gap
that let defect (b) survive.

### The fix, and what it needs to be safe

1. Decide the resident pool on whether FirstPassFDR will actually RUN, not on membership - i.e.
   consult the same validity check that makes it Rehydrate. `PreCompactionPoolReason` governs
   several consumers, so the change needs care.
2. **Add a test that fails today**: a multi-file (>= 8) `--task PerFileRescoring` run asserting
   the hydrate takes the streaming arm (the log line above) and that peak memory does not scale
   with file count. Without it this regresses silently, because nothing covers it - CRITICAL-RULES
   "strengthen the verifier rather than the wording".
3. Re-gate `-Dataset All` plus the new test.

Not attempted on 2026-09-02 at ~14% context: a half-finished change to a wide-blast-radius
decision, on a branch that is green, proven at 446 files and already in PR #4633, is worse than
sequencing it.

### THIS WAS ALREADY BUILT AND MEASURED - so 446 is a REGRESSION, not a gap

`todos/completed/TODO-20260727_osprey_stage6_rescore_streaming.md` did this work. It owns
`PreCompactionPoolReason` (restructured so "the helper now owns the whole predicate and reports
a 'no reconciled bundle' reason of its own"), and it states the acceptance criterion:

> **Memory A/B**: the PerFileRescoring band slope goes to ~0 in file count, as the FirstPassFDR
> band now is. Confirm the 500-file projection clears 64 GB.
>
> Measured at 82 files (SEA-AD Astral, `--task PerFileRescoring`): peak **33.9 GB** with
> `--model-diagnostics` against a **~197 GB** projection for the unbounded path.

It even names the trap that hides this from the gate:

> **Pass N files in ONE invocation.** The HPC chain (`regression.ps1:644`) calls this task [per
> file].

**So the 446 measurement of ~110 GB contradicts completed, measured work.** Slope ~0 would put
446 near 34 GB. Reframe accordingly: this is not a missing architecture to design, it is a
regression or an uncovered trigger in a loop that already exists and was demonstrated bounded.
The developer's read - "it seems like restructuring a loop to me" - is correct, and the loop is
already written.

**Discriminator already in hand**: the 3-file straight-through resume emitted

```
[WARN] No reconciled bundle on the --input-scores inputs requires the RESIDENT pre-compaction
first-pass pool: every --input-scores file's full stub list is held in memory at once...
```

but the **446 `--task PerFileRescoring` run emitted NO such warning** - so it took the resident
path WITHOUT the reason-reporting the July work added. Start there: instrument which branch sets
`residentStubs > 0` on that run, and compare against the July harness, which passed N files in
one invocation and stayed bounded.

Prime suspects, in order: (1) a trigger added after 2026-07-27 that forces the pool without
going through `PreCompactionPoolReason`; (2) `FirstPassFdrTask.IsIncludedFor` being true under
`--task PerFileRescoring` (see the section above) reaching the pool decision by a different
route; (3) something scale-dependent between 82 and 446 files.

**Process finding**: the previous session diagrammed the per-run loop for the developer, and
that diagram is in NO todo - not this one, not the completed sidecar-scope work. If it exists it
is in a handoff under `ai/.tmp/`, which CRITICAL-RULES defines as temporal and never committed.
The design rationale for a loop shape is exactly the kind of thing that must live in a TODO;
losing it is why this had to be re-derived from logs tonight.
