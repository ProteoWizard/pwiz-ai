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

### THE GUARD IS NARROWER THAN THE PATH IT GUARDS (developer's question, answered)

*"Unless those switches are on it is not supposed to be possible to trigger an O(files) memory
request... Any run, even 3 files, should have been refused."* Correct - and it was not, for a
specific reason.

There are TWO predicates and they diverged:

```csharp
// REFUSE predicate - what GuardResidentPool actually throws on (PerFileScoringTask ~1975)
return !useFdrProjection                                   // OSPREY_FDR_PROJECTION=0
    || !config.FdrMethod.UsesPercolatorFramework()         // non-Percolator
    || (!string.IsNullOrEmpty(config.OutputFdrBench) && config.FdrBenchPass == 1);
```

vs the BUILD decision (`CanUseLeanProjection` / `PreCompactionPoolReason`), which ALSO covers
"no reconciled bundle on the --input-scores inputs" and `FirstPassFdrTask.IsIncludedFor`.

The source documents the split as intentional:

> "This one KEEPS NeedsResidentPool deliberately, where the fat/lean choice above moved to the
> builder. They answer different questions and **the predicates diverged when
> ExpectReconciledInput left NeedsResidentPool (#4486)**"

**Consequence**: a run that builds the resident O(files) pool for either of the extra reasons is
never REFUSED - it only gets `WarnPreCompactionPool`, a warning it proceeds past. The invariant
"an O(files) path is impossible unless the operator names a token" is enforced by a predicate
that no longer covers the paths that take it. `ResidentPaths.KNOWN_UNFIXED` has four tokens
(`FDRBENCH_PASS1`, `NON_PERCOLATOR_FDR`, `PROJECTION_OFF`, `COMPACTED_ENTRIES_BUFFER`) and none
of them names this case.

That is why a 3-file run warned and continued, and why the 446 run reached ~110 GB without any
refusal. **The primary fix is to make the refuse predicate cover every path that can build the
pool** - i.e. guard on the same reason `PreCompactionPoolReason` reports, with a token per
reason - and only then fix the trigger itself. Doing the trigger without the guard leaves the
next divergence just as silent.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260902_osprey_perfilerescore_resident.md` before starting work.

### RETRACTION + the directive (2026-09-02)

`Program.cs:132` sets `config.NoJoin = true` for `--task PerFileRescoring`, so
`FirstPassFdrTask.IsIncludedFor` is FALSE there. **The "IsIncludedFor forces the pool under
--task PerFileRescoring" claim two sections up is WRONG and is retracted.** The trigger on that
446 run remains unidentified; instrument `PreCompactionPoolReason`, `NeedsResidentPool` and
`residentStubs` rather than guessing a fourth time.

It also means the HPC route is safe **by design** - under `--task` FirstPassFDR is not a
pipeline member, so nothing expects an O(files) structure from it - not merely because a node
holds one file.

**Developer's directive**: *"get rid of the fat path altogether and just no longer support it.
We stream one file at a time."* Implement that rather than continuing to guard the resident
pool. It dissolves the `NeedsResidentPool` / `PreCompactionPoolReason` divergence recorded above,
and `ResidentPaths.KNOWN_UNFIXED` (documented as "may only shrink") reaches zero.

**Cheap test for whether THIS branch caused the 446 behaviour**: the completed July TODO measured
33.9 GB at 82 files for `--task PerFileRescoring`. Re-run 82 files on the branch tip and compare.

## ROOT CAUSE, 2026-09-02: the 446 run NEVER took the fat path

Read off `D:\test\osprey-runs\chs-seer\runs\chs-446files-libdecoy-r1.0-protein-compact-secondpass\run.log`,
not inferred. This supersedes every earlier hypothesis in this file about which trigger armed
the resident pre-compaction pool: **none did.**

### The three discriminators in the log

1. **The progress denominator is 892 = 2 x 446.** `HydrateCompactedStreaming` reports over
   `2L * nFiles` (RescoreHydration.cs:431); the batch twin `HydrateReconciliationOverlay`
   reports over `perFileEntries.Count` (:294). The log shows `50.22% (448/892)`, i.e. the
   **STREAMING** hydrate ran.
2. **The per-file log lines are the streaming loader's.** `LoadJoinOnlyScoresForFile` emits
   `    Loading file N/446` (4 spaces) and `      Loaded N FDR stubs (features not loaded ...)`
   (6 spaces); `LoadJoinOnlyScores`'s resident loop emits the same text at 0 and 2 spaces.
   The log has 4 and 6.
3. **`grep -c RESIDENT run.log` = 0.** No `WarnPreCompactionPool`, no `GuardResidentPool`
   refusal - correctly, because the run never asked for the pool.

So `--task PerFileRescoring` over 446 files streams its pre-compaction pool exactly as
designed. `NeedsResidentPool` was false, `PreCompactionPoolReason` returned null,
`ShouldStreamCompaction` was true. The fat path is not involved and removing it would not
have changed this run by one byte.

### What IS O(files): the bundle and the survivor buffer that the BOUNDED hydrate builds

`HydrateCompactedStreaming` bounds the *pre-compaction* pool to one file at a time. It does
not bound what it accumulates across files, and there are two such terms.

**Pass 1 (envelopes, 446 files, 3m22s)** holds, for every file at once:
`plannedByFile` (`List<List<PlannedAction>>`, **30,841,614** actions), `perFileGapFill`
(**8,849,111** targets), `retainBaseIds`, `refinedCalibrations`. Its own comment says
*"Everything kept here is small"* - true per file, false at 446.

**Pass 2 (per-file stub load + compact + append, 2h51m)** appends every file's survivors into
the single `perFileEntries` buffer, and fills `reconciliationActions` with all 30.8 M entries.

Measured slope, from the memstamp columns (managed MB / working-set MB):

| point | managed | WS |
|---|---|---|
| hydrate start 03:37:19 | 4.7 GB | 14.4 GB |
| 448/892 - pass 1 done 03:40:41 | 17.6 GB | 23.8 GB |
| 892/892 - pass 2 done 06:31:23 | 92.1 GB | 107.3 GB |

Pass 1 costs **~12.9 GB / 446 files = ~29 MB per file**. Pass 2 costs **~74.5 GB / 446 files
= ~167 MB per file**. Total **~196 MB managed / ~206 MB WS per file**, plus a fixed ~14.4 GB
(6.18 M-entry library + runtime).

### The 446 result is NOT a regression - it is what the 82-file number always implied

`todos/completed/TODO-20260727_osprey_stage6_rescore_streaming.md` measured **33.9 GB at 82
files** and recorded the acceptance criterion as *"the PerFileRescoring band slope goes to ~0
in file count"*. Apply the slope above to 82 files: `14.4 + 82 x 0.206 = 31.3 GB` - the July
measurement, reproduced. **The slope was never ~0; it was asserted from a single point, and a
single measurement cannot show a slope.** The 500-file projection the same TODO said to
confirm (`14.4 + 500 x 0.206 = 117 GB`) was never run.

So: nothing regressed, the loop was never "already written and demonstrated bounded" in the
sense this file claimed, and the earlier framing of 446 as *"a REGRESSION, not a gap"* is
withdrawn. The July work bounded the PRE-compaction pool - which it did, and which holds - and
left the post-compaction survivor buffer and the experiment-wide bundle O(files).

### Why no guard fired, and what that says about the invariant

`GuardResidentPool` guards the PRE-compaction pool. `Stage6ResidentHandoffGuardError` guards
the post-compaction survivor handoff, but only when `OSPREY_STAGE6_STREAM_SURVIVORS=0`; here
streaming was ENABLED and the buffer was built anyway, by the hydrate rather than by Stage 5.
The reconciliation bundle (30.8 M actions + 8.85 M gap-fill targets) has no guard at all and
no token in `ResidentPaths.KNOWN_UNFIXED`.

**The developer's invariant - "an O(files) memory request is impossible unless a token names
it" - is not violated by a divergence between two predicates. It is violated because both
predicates only ever described the fat pre-compaction pool, and this run's O(files) request is
somewhere else entirely.** Widening the REFUSE predicate to match `PreCompactionPoolReason`,
which this file proposed as the primary fix, would still not have refused this run.

### Consequences for the plan

* The "delete the fat path" directive is orthogonal to unblocking the 446-file run. It is
  still worth doing on its own merits (it dissolves the guard divergence), but it does not
  enable this processing goal.
* What blocks the goal is two unbounded accumulations inside a hydrate documented as bounded:
  `plannedByFile` / `reconciliationActions` (~29 MB/file) and the all-files survivor buffer
  (~167 MB/file).
* The survivor-buffer half is the same #4526 term this TODO opened with, one stage later:
  commit 46a239393b took it out of Stage 6 PLANNING, and the hydrate still builds it.

## THE TARGET SHAPE for --task PerFileRescoring (developer, 2026-09-02)

> *"I want PerFileRescoring to loop once over each run and act as if it were performing its job
> on separate computers with access only to a limited set of per-run and experiment-wide summary
> files. It should have no pre-processing loop over all files. It is not a join task and should
> act as if each iteration is completely bounded and it should be written to be parallelizable
> on a computer with enough resources with no multiple passes over the files and only shared
> experiment-wide summary resources, no resources built from all runs during the task."*

Per iteration the task may read: that run's `.scores.parquet`, `.1st-pass.fdr_scores.bin`,
`.reconciliation.json`, `.calibration.json`; plus experiment-wide summary artifacts that some
EARLIER phase wrote. It may build nothing that spans runs.

### What violates it today, exhaustively

Everything below is inside `RescoreHydration.HydrateCompactedStreaming`, which bounds the
per-file PRE-compaction pool and nothing else.

| # | Cross-run resource built during the task | Where | Size at 446 |
|---|---|---|---|
| 1 | `retainBaseIds` = global set UNION **every file's** action targets | pass 1 | forces the pre-pass |
| 2 | `plannedByFile` - all files' planned actions, held pass 1 -> pass 2 | pass 1 | 30,841,614 |
| 3 | `perFileGapFill` - all files | pass 1 | 8,849,111 |
| 4 | `refinedCalibrations` - all files | pass 1 | 446 |
| 5 | `EnvelopeConsistency` - checks each envelope against its SIBLINGS | pass 1 | O(files) by nature |
| 6 | `perFileEntries` - every file's survivors in one buffer | pass 2 | ~167 MB/file |
| 7 | `reconciliationActions` - one map keyed (file, vec_idx) across all files | pass 2 | 30,841,614 |

Items 2, 3, 4, 6 and 7 are mechanical: each is a per-run quantity accumulated into an
all-runs container for no reason except that the task was written as a join. They move inside
the loop and die with the iteration.

Item 5 is impossible under the spec by definition - a node with one run cannot compare its
envelope against siblings it does not have - and becomes a check against the experiment-wide
summary instead.

**Item 1 is the only structural blocker**, and it is why the pre-pass exists at all.

### Why item 1 cannot be read from the run's own envelope

The retained set is `first_pass_base_ids` UNION `{base_id of every planner action target,
across all files}` (`RescoreCompaction.Apply` step 2). The first term is already an
experiment-wide summary: `EnvelopeConsistency` documents it as *"identical in every file's
envelope by construction"*, so one envelope supplies it.

The second term is not in any envelope, and cannot be, because of an ordering fact this branch
introduced: `WriteReconciliationFiles` writes each file's envelope **the moment that file's
planning finishes** (`onFilePlanned`), specifically so the planner can release that file's
entries. At that instant the actions for the files planned later do not exist yet. So no
envelope can carry the completed union, and every consumer has had to re-derive it by reading
all 446 envelopes.

### The fix: the planner writes the union as an experiment-wide artifact

The planner is the one component that legitimately holds the whole experiment - that is its
job. When planning ends it knows the completed union. Write it there, once:

```
<blib-stem>.1st-pass.retained_base_ids.bin   (sorted uint32, same determinism rules
                                              as the envelope's base_id array)
```

Same pattern as the existing experiment-scope `<blib-stem>.1st-pass.fdr_experiment.bin`
(#4486): written once at experiment scope by the phase that owns it, read by per-run workers.

Then:

* `RescoreCompaction.Apply` consumes the set instead of re-deriving it by iterating
  `inputs.ReconciliationActions` over every file - which is what forces the all-files action
  map to exist in the first place. Re-keying `vec_idx` stays per file and is unaffected.
* `--task PerFileRescoring` reads the artifact once at task start, then loops: load one run's
  stubs, overlay its sidecar, read its own envelope, compact to the shared set, rescore, write
  its `.scores-reconciled.parquet`, release. Bounded, single-pass, parallelizable.

### KNOWN RISK: this can move mode 3's output, and that would be a fix, not a break

Today a single-run node (regression mode 3) computes `retainBaseIds` from its OWN envelope
only, so its retained set is `global UNION (that run's actions)` - a strict SUBSET of the
join-wide union a straight-through run applies. `RescoreCompaction`'s own comment says using
the local subset is what produced *"stale Stage 4 apex_rt / bounds for ~200 rows per Stellar
file (0.04%)"*, and the union step exists to prevent exactly that.

Mode 3 is green today, so on Stellar/Astral the subset and the union must agree, or the
difference does not reach the output. That is a property of three-file test data, not a
guarantee - at 446 CHS files the two sets are not likely to agree.

So: making every node consume the same experiment-wide set is a correctness improvement, and
if it moves any golden, the moved golden is the correct one. Gate `-Dataset All` and read a
mode 3 diff as a finding to investigate, not as a regression to revert.

### MEASURED: what the 446-file envelopes actually contain

`ls` + a field-by-field size breakdown of
`D:\test\osprey-runs\chs-seer\runs\chs-446files-libdecoy-r1.0-protein-compact-secondpass\*.reconciliation.json`:
**446 envelopes, 24.6 MB each, 10.7 GB total** - all of which pass 1 parses.

One envelope (23.2 MB on disk):

| field | size | n | scope |
|---|---|---|---|
| `first_pass_base_ids` | 6.26 MB | 744,943 | **experiment-wide, byte-identical in all 446** |
| `forced_integration_actions` | 4.45 MB | 49,429 | this run |
| `use_cwt_peak_actions` | 2.94 MB | 25,096 | this run |
| `refined_rt_calibration` | 2.10 MB | 4 arrays | this run |
| `gap_fill_targets` | 1.37 MB | 7,854 | this run |
| `file_stems` | 0.01 MB | 446 | experiment-wide, duplicated |
| hashes, format_version | <0.01 MB | - | experiment-wide, duplicated |

Two things fall out.

**The action arithmetic checks.** 49,429 + 25,096 = **74,525** actions in one run's envelope -
exactly the "74,525 reconciliation actions hydrated" a 1-file node reported, and
74,525 x 446 = 33.2 M against the 30,841,614 the 446-file run hydrated. The count was always
per-run; only the container was experiment-wide.

**The join-wide array is replicated 446 times.** 744,943 base_ids at 6.26 MB of JSON per copy
is **2.79 GB of pure duplication** across the cohort. As a sorted `uint32` array written once
it is **2.98 MB**.

### The summaries PFR needs are bounded by the LIBRARY, not by files

This is the answer to "they need to be fast and as low memory as possible, especially when
they are truly O(files*entries)":

* **retained base_ids** - `first_pass_base_ids` (744,943) UNION the action targets. Both terms
  are sets of base_ids, so the union is bounded by the 6,175,389-entry library, not by file
  count. Binary sorted `uint32`: **3-24 MB**, read once, held for the whole task exactly like
  the library. No O(files x entries) term.
* **experiment-scope 1st-pass FDR** - `<blib-stem>.1st-pass.fdr_experiment.bin` already exists
  (#4486), same shape, keyed by entry_id, also library-bounded.

**No all-run retention-time table is needed.** The planner does compute cross-run consensus
RTs, but it resolves them into per-run products before writing: `gap_fill_targets` (7,854 for
this run) and the refined calibration land in that run's OWN envelope. So the O(files x
entries) RT structure the developer flagged exists only inside the planner, during FirstPassFDR,
where the whole experiment is legitimately in hand - it never has to be rebuilt or re-read at
PFR time.

### Follow-on, separable and pure saving

Once the retained set is an experiment-wide artifact, `first_pass_base_ids` no longer belongs
in a per-run envelope: dropping it (format v4) stops writing 2.79 GB and stops parsing 6.26 MB
per iteration that PFR immediately discards, and retires `EnvelopeConsistency` outright. Held
back from the first cut only to keep the behaviour change and the format change separately
bisectable - the cross-impl envelope comparison against Rust is the one thing a v4 bump breaks,
and `regression.ps1` does not cover it.

### Where the lean row does and does not apply to this work

`TODO-20260826_osprey_stage7_stream_pool.md` (merged as `091d79a98b`, PR #4621) specs the
Phase 3 lean row - an 88 B packed row (interned `PeptideId` replacing the per-row
`ModifiedSequence` string) against `FdrEntry`'s ~274 B - and lists it under *"Owed,
deliberately not done here: Phase 3 / lean row - its own PR. Measure it on DRIFT PER FILE, not
peak or wall time."* It is spec'd, signed off, and NOT implemented.

Two cases, and they need different things:

**`--task PerFileRescoring` (the 446-file CHS case) needs NO lean row.** Once the retained
base_id set is an experiment-wide artifact, nothing that crosses an iteration is O(files x
entries): the summaries are library-bounded (<= 6.18 M base_ids), and each run's survivors are
rescored, written to that run's `.scores-reconciled.parquet`, and released. The task ends
holding what it started with. This is the case the developer specified and it can be made
fully bounded now.

**Straight-through needs it.** There PFR is followed in-process by Stage 7, which does have to
hold a whole-experiment pool. That pool is exactly the Phase 3 target, and the drift numbers
say it is the SAME pool this TODO measured from the other side:

| measurement | source | per file |
|---|---|---|
| Stage 7 resident pool drift | `TODO-20260826` at merge | 215 -> 216 MB/file private |
| PFR hydrate pass 2 accumulation | this TODO, 446-file log | ~167 MB/file managed, ~206 MB/file WS |

Same order, same object: the all-runs survivor pool at ~274 B/entry, seen at two stages.

**Consequence for how to write the loop.** Shape the per-run iteration so the thing it hands
forward is already the lean-row seam: each iteration ends by emitting its run's contribution
and dropping the fat `FdrEntry` objects, rather than appending them to a shared buffer. In
`--task` mode the contribution is the reconciled parquet and nothing is retained; in
straight-through it is whatever Stage 7 needs. Phase 3 then lands as a change of ROW TYPE at
one seam, not another restructure - and it is measured the way its own TODO says, on drift per
file.

## Progress log - 2026-09-02 (implementation session)

Branch `Skyline/work/20260901_osprey_firstpass_resume` in `C:\proj\pwiz-work1`, on top of the 12
commits already in PR #4633. NOT yet committed at the time of writing.

### Implemented: the analysis-wide retained base_id summary

New `pwiz_tools/Osprey/Osprey.IO/RetainedBaseIdSidecar.cs` -
`<blib-stem>.1st-pass.retained_base_ids.bin`, a sorted `uint32` array behind the same 32-byte
header shape `FdrExperimentSidecar` uses (magic `OSPRYRET`, so neither file can decode as the
other). `PathFor` resolves through `ArtifactPaths.ResolveOutputDir` off a sibling artifact, not
off the blib's own directory, for the reason `FdrExperimentSidecar.PathFor` documents.

**Producer** - `FirstPassFdrTask.PlanStage6`. The union is accumulated as each run is planned
(`AccumulateActionTargetBaseIds`, plus the join-wide term seeded once from the first plan) and
written by `WriteRetainedBaseIdSummary` when planning ends, BEFORE the `StopAfterStage5` return
so `--task FirstPassFDR` produces it. A write failure is fatal, not a warning - see the method's
doc for why the asymmetry with the per-run envelope writes is deliberate.

**Consumer** - `RescoreHydration.HydrateCompactedStreaming` now takes the set as a required
parameter and runs ONE pass. Deleted: the pre-pass over every envelope, `plannedByFile`,
`syntheticInputs`, `reconPaths`, and the cross-run `retainBaseIds` union. Each run's envelope is
read, used, and released inside its own iteration. `ScoringTaskShared.ReadRetainedBaseIds` is the
shared reader and hard-fails with an operator-facing message naming FirstPassFDR as producer -
deliberately NOT falling back to rebuilding the union, which is the O(files) pre-pass being
deleted.

`EnvelopeConsistency` no longer compares each envelope's `first_pass_base_ids` against its
siblings (446 x 744,943 inserts + probes to re-confirm a field compaction no longer reads).
Provenance is now checked on `library_hash` / `search_hash` / `file_stems`, which are O(1) and
O(stems) and stay meaningful for a worker holding one run.

`regression.ps1` stages the new artifact on both existing relays (phase 2 -> 3, phase 3 -> 4),
deliberately WITHOUT `Test-Path` guards so a missing copy surfaces as the worker's failure rather
than a skipped hop.

### State

* `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`: **601 passed, 1 skipped**
  (`Stage5SurvivorBuffer_CollectVsStream`, a bench that is normally skipped), inspection clean.
* `regression.ps1 -Dataset Stellar`: RUNNING at the time of writing, result not yet known.
* Files touched: `RetainedBaseIdSidecar.cs` (new), `FirstPassFdrTask.cs`,
  `PerFileScoringTask.cs`, `RescoreHydration.cs`, `ScoringTaskShared.cs`, `IOTest.cs`,
  `regression.ps1`. +260 / -54.

### What this does and does NOT fix

Removes items 1-5 of the violation table: the envelope pre-pass (10.7 GB of JSON at 446 runs)
and the ~29 MB/run pass-1 accumulation.

**Items 6 and 7 are still there** - `perFileEntries` still accumulates every run's survivors
(~167 MB/run, the dominant term) and `reconciliationActions` is still one all-runs map. Removing
those is the second half: the per-run iteration has to end by emitting its run's reconciled
parquet and releasing, which means restructuring `PerFileRescoreTask`'s relationship to the
hydrate rather than the hydrate alone. Not started.

### Watch this on the gate

Mode 3 gives each node ONE run, so before this change a node's retained set was
`global UNION (that run's actions)` - a strict subset of the join-wide union. It now reads the
complete union from the summary. If mode 3's output moves, that is the latent divergence
`RescoreCompaction`'s union step exists to prevent (~200 rows/Stellar file per its own comment)
being fixed, not a regression - see "KNOWN RISK" above before rebaselining anything.

### GATE RESULT: `regression.ps1 -Dataset Stellar` PASSED (2026-09-02)

All 12 checks, blib byte-identical at 23,662,592 bytes across straight-through, the HPC 4-task
chain, resume and Stage-5 rehydrate. Tokens required by the gate: 0.

**The mode 3 risk did not materialize on Stellar**, as the "KNOWN RISK" section predicted it
would not: on 3-file data the per-run subset and the join-wide union agree, so no golden moved.
That is NOT evidence the two agree at 446 - it is evidence Stellar cannot tell them apart, which
is the same blindness that let the original defect through. The discriminating test is a
multi-run `--task PerFileRescoring`, which still does not exist (see the missing-test item).

**The gate's own footer independently confirms the remaining term**, and names it as untokened:

```
=== Known O(files) resident paths this gate still traverses ===
  #4486  token: NONE
      SecondPassFDR pulling RescoredEntries rebuilds the whole-run survivor buffer it reads
      (#4597 moved the build off the end of Stage 6, which does not shrink it); resident for
      the whole of Stage 7.
      ~4.4 GB library + 0.197 GB/file live post-GC: ~20 GB at 82 files, ~103 GB projected at 500.
```

**0.197 GB/file** against the 0.167 GB/file managed / 0.206 GB/file WS this TODO measured from
the 446-run hydrate. Same object, three independent measurements: the gate's post-GC probe, the
Stage 7 TODO's 215-216 MB/file drift, and the CHS log. That is items 6 + 7 of the violation
table, it is the Phase 3 lean-row target, and the gate already tracks it as carrying no token.

### CORRECTION 2026-09-02: the 446 PerFileRescoring run was KILLED, it did not complete

An earlier claim in this session - that the run "completed the hydrate ... and exited 1 on the
missing experiment-scope sidecar" and "was never killed" - is **WRONG and withdrawn**. The
developer killed `Osprey.exe` from Task Manager while the box was thrashing.

What the log actually shows, in
`D:\test\osprey-runs\chs-seer\runs\chs-446files-libdecoy-r1.0-protein-compact-secondpass\run.log`:

* **Zero** completion markers - no `PerFileRescoring:done`, no `Analysis complete`, no
  `[TIMING] Total pipeline`.
* No `Pipeline failed:` line either, which is what `AnalysisPipeline`'s catch-all emits on a
  graceful failure. Neither outcome was reached.
* Last Osprey output `06:40:04 100%`; the runner's `DONE ... exit=1 elapsed=194min` at
  `06:49:51`. **A 9m47s silent gap**, then a non-zero exit observed by the runner.

The reasoning error worth not repeating: `exit=1` was read as caused by the
experiment-scope-sidecar `[ERROR]` at 06:31:25. That error is documented in this very file as
**non-fatal - it logs and the run continues** - and it is nine minutes upstream of the exit. An
externally killed process produces the identical `DONE ... exit=1` line, because the runner only
observes the exit code of `& $ospreyExe`. **The runner's DONE line cannot distinguish a kill
from a failure**, and no `KILLED BY OPERATOR` annotation was added to this log the way one was
for `baseline-phase3`.

**And the framing was wrong independently of the exit code.** A run at 111.9 GB working set on a
63.7 GB box is a failure whether or not it eventually returns: the developer reported the machine
was barely able to accept keystrokes and that reaching Task Manager to kill it took real
patience. "It thrashed but survived" is not a defensible reading of that. Peak private bytes
past physical RAM is the failure condition, not a caveat on one.

Consequences for what this file claims:
* The "2h54m of bundle hydration" figure stands (it is bracketed by log timestamps), but nothing
  downstream of `06:40:04` can be claimed at all.
* "0 reconciled parquets" stands as an observation, but it does NOT establish that the rescore
  self-gated - the run never got there.

## THE ACTUAL DEFECT, 2026-09-02: the startup work is DISCARDED AND REDONE

Measured on the 86-run plate (`chs-86files-...-retainedset-pfr2\run.log`), `--task
PerFileRescoring` spends **14m17s / 24.7 GB managed / 46.3 GB WS before rescoring one run**,
then drops to ~4.6 GB and stays flat. Of that startup, **11m24s and ~20.5 GB is O(runs)**:

| segment | time | managed at end | scaling |
|---|---|---|---|
| library load (6.18 M entries) | 2m07s | 4.19 GB | fixed |
| mdiag classification | 0m22s | - | fixed |
| hydrate - all 86 runs' parquets | **8m42s** | **21.4 GB** | **O(runs)** |
| `CompactFirstPass` over all runs | **2m42s** | **24.7 GB** | **O(runs)** |
| release, enter loop | 0m22s | 4.4 GB | - |

### The entries the startup loads are never read

`RescoreOneFileStreamed` (`PerFileRescoreTask.cs:1015-1028`) opens each iteration with
`survivorLoader.Load(file.Key)` - re-reading that run's `.scores.parquet` and
`.1st-pass.fdr_scores.bin` - then `file.Value.Clear(); file.Value.AddRange(stubs)`. **It
overwrites what the hydrate put there.** The all-runs buffer serves only as a list of run KEYS
and a transient per-iteration slot.

So this is not "an expensive way to get what the loop needs". It is work whose entire product is
thrown away, paid for solely because the process was handed a list of N parquets instead of one.
At N=1 (regression mode 3) it costs nothing and the gate is green; at N=446 it is the wall.

`PipelineByproducts.cs:457-471` already said so: *"Every artifact the rebuild needs ... is on disk
by the time Stage 5 compacts, **so holding the survivors is a choice rather than a
requirement.**"*

### Nothing needs all runs resident for correctness

Mode 3 hands a node ONE run - 5 per-run files plus 4 analysis-wide summaries and the library -
and produces byte-identical output to straight-through, every gate run. The genuinely whole-run
computations are O(distinct) folds needing every run VISITED, not RESIDENT
(`PercolatorEngine.cs:1019`: *"Both maps are O(distinct) ... nothing here needs a whole-run
view"*). Under `--task PerFileRescoring`, `NoJoin` excludes `SecondPassFdrTask`, so nothing pulls
`RescoredEntries` and the global pool is never built - which is why the loop is already flat.

### The invariant, and why it must be a signature and not a rule

> **The hydrate for rescoring a single run cannot have the parquet files for all runs.**

`HydrateCompactedStreaming(perFileEntries, IList<string> parquetPaths, ...)` takes every run's
parquet; only the loop's discipline bounded the cost, and that discipline is what failed. The
replacement takes ONE path, so O(runs) cannot be reintroduced by a later refactor -
CRITICAL-RULES' "strengthen the verifier rather than the wording".

### Correct startup, for comparison

Library 4.19 GB / 2m07s + `1st-pass.fdr_experiment.bin` (255 MB, library-bounded) +
`1st-pass.retained_base_ids.bin` (3 MB) + the run-name list. **~2.5 min, ~5 GB, flat in run
count.** Everything above that line is the defect.

Plan: `~/.claude/plans/i-am-going-a-mossy-marble.md` (approved 2026-09-02).

## Progress - 2026-09-02 (per-run hydrate, implementation)

### Landed, gate green (601 tests, inspection clean)

* **`RescoreHydration.HydrateOneRun(string parquetPath, ...)`** - the per-run hydrate. Takes ONE
  parquet path, so the O(runs) startup cannot be reintroduced by a later refactor. Returns a new
  `RunRescoreInputs` (survivors, this run's actions keyed `(file,vec_idx)`, gap-fill, refined
  calibration, join stems, global base_ids, tally). `HydrateCompactedStreaming` keeps its
  `IList<string>` signature and stays for the straight-through pipeline, now labelled as the
  ALL-RUNS builder.
* **`PerFileRescoreTask`** - `RescorePassInputs.HydrateRun` (a `Func<string, RunRescoreInputs>`),
  built by `BuildPerRunHydrate` and non-null only for an `--input-scores` run that can read the
  retained-set summary. `RescoreOneFileStreamed` takes the fan-out path first: hydrate under
  `_survivorLoadLock`, rescore, release. `TryAssembleRescoreTargets` and the RT-calibration pick
  read the per-run slice when it is present and the join dictionaries otherwise.
* **Consensus targets are DERIVED per run**, not carried:
  `MultiChargeConsensus.SelectRescoreTargets(run.Survivors, RunFdr)` - it only ever read one
  run's entries, which is why building it for every run up front was pure waste.
* `ReconTargetsForRun` projects through the SAME `GroupReconciliationActionsByFile` the join path
  uses, so the two cannot interpret a `ReconcileAction` differently.

**Trap avoided, recorded because it is easy to repeat**: the per-run `loadStubs` must read RAW
pre-compaction stubs from `.scores.parquet`, NOT `FirstPassSurvivorLoader.Load` - that loader has
already overlaid the 1st-pass sidecar and filtered, so feeding its output to `HydrateOneRun`
would overlay a second time onto a list that is no longer the sidecar's superset.

### Migration tool for pre-artifact run directories

`ai/scripts/Osprey/retained_base_ids_migrate.py` builds
`<stem>.1st-pass.retained_base_ids.bin` from a run directory's envelopes. Deliberately a
separate, named, run-once tool rather than a fallback inside Osprey: the hard-fail on a missing
summary is what stops a silent return to the O(files) pre-pass, and that refusal must not be
weakened just because an already-successful FirstPassFDR predates the artifact.

**Validated against ground truth**: run over the 86-run leg-1 directory, which has both the
envelopes and the artifact Osprey itself wrote, it produced a **byte-identical** file (373,487
base_ids, 1,493,980 bytes) in 17 s. That is what makes it usable on the 446-run
`chs-446files-...-stage5stream` directory, whose FirstPassFDR completed in 5h13m and must not be
re-run.

### Still to do

1. Stop `LoadJoinOnlyScores` hydrating all runs (the 8m42s / 17.2 GB), and move the
   `--model-diagnostics` pre-compaction fold onto `HydrateOneRun`'s per-run hook at the same
   time - it currently folds every run's rows during the all-runs hydrate, and would silently
   degrade to a survivors-only report if the stubs stopped being loaded there.
2. `FirstPassFdrTask.Rehydrate` - `CompactFirstPass` over empty lists once (1) lands.
3. The failing-first multi-run test.
4. `-Dataset All`, then the 86-run plate leg, then 446 via `-LinkFrom` + the migration tool.

Until (1) lands the startup cost is UNCHANGED - the per-run path is correct but redundant, which
is the deliberate sequencing: make the loop self-sufficient while the old path still runs, prove
it byte-identical, then delete the old path.

### The all-runs pre-load has TWO consumers, not one (found by the gate, 2026-09-02)

Skipping the all-runs hydrate in `LoadJoinOnlyScores` was not sufficient: mode 3 phase 3 went
red with

```
[ERROR] --input-scores hydration failed: HydrateReconciliationOverlay: failed to overlay
        .1st-pass.fdr_scores.bin for <stem> (expected at <stem>.1st-pass.fdr_scores.bin)
[ERROR] Pipeline failed: Task 'PerFileScoringTask' failed to rehydrate its state
```

`HydrateRescoreBundleIfPresent` runs AFTER the load and independently builds the batch overlay
whenever `hasReconSidecars` is true. Handed the per-run publish's EMPTY stub lists, it fails -
`FdrScoresSidecar.TryRead` binds each record to a stub by `entry_id` and refuses a file whose
records have nowhere to land. That is the same empty-list precondition `FirstPassFdrTask`
already documents for choosing its streaming arm; the value of the failure is that it is LOUD
rather than silent - an overlay that quietly accepted an empty list would have produced a run
with no first-pass q-values at all.

Fixed by gating that call on the same `ScoringTaskShared.CanHydratePerRun` predicate.

**Worth generalising for the architecture doc**: "stop building X" is not one edit per producer.
Every consumer that independently reconstructs X has to be found, because the ones that fail
loudly are the lucky case. The stack that named it was
`PerFileRescoreTask.Run -> Get<CompactedEntries> -> DemandByType(FirstPassFdrTask) ->
FirstPassFdrTask.Rehydrate -> Get<ScoredEntries> -> DemandByType(PerFileScoringTask) ->
Rehydrate` - three tasks materialised by one Get, which is exactly the lazy-Demand chain that
makes an in-process run's dataflow invisible at the call site.

### Removing an O(runs) pre-load from one producer only MOVES it (2026-09-02)

Gating the `--input-scores` load did not remove the all-runs work; it relocated it. With no
bundle published, `FirstPassFdrTask.Rehydrate` took its OWN bundle-building route -
`LoadOwnReconciliationBundle` sees empty stub lists, reads that as the lean signature, and calls
`StreamOwnReconciliationBundle`, which walks every run's envelope and parquet. Same cost, second
producer.

Two edits were needed, not one:

1. `PerFileScoringTask.LoadJoinOnlyScores` - publish run names, paths and calibrations only.
2. `FirstPassFdrTask.Rehydrate` - a `RehydrateForPerRunRescore` branch that publishes the
   survivor loader plus EMPTY planning slots and builds nothing. Its retained set comes from the
   analysis-wide summary rather than from a bundle assembled by reading every run, which is what
   the summary is for.

Plus a third, in the rescore's self-gate: `!didPlan && (rescoreBundle == null || anyPass2Present)`
fired, because the per-run plan is not held anywhere at that moment - it is read per run inside
the loop - so both existing "is there a plan" signals were legitimately false and a fully-
equipped run self-gated to a no-op, writing no `.scores-reconciled.parquet`. `CanHydratePerRun`
is now a third source of "there is a plan to execute". `anyPass2Present` deliberately stays
outside that term: a completed run must still no-op.

**Generalisation for the architecture doc**: "stop building X" is one edit PER PRODUCER, and the
producers are not co-located - one was in the upstream load, one in a downstream task's rehydrate,
and the gate that noticed was a missing output file rather than a wrong number. Every consumer
that can independently RECONSTRUCT X has to be found; the ones that fail loudly are the lucky
case.

### KNOWN remaining O(runs) term on the per-run path, stated rather than assumed away

`PerFileCalibrations` retains one `RTCalibration` per run (the anchor arrays `AbsResiduals`,
`FittedRts`, `LibraryRts`). A CHS run's refined calibration is ~2 MB, so 446 runs is order-1 GB -
invisible at plate scale, and NOT O(1).

It is left in place deliberately and **must be measured at 446 rather than assumed**, because
reading a single-point measurement as a slope is the exact mistake this whole change exists to
correct (the July "slope goes to ~0" claim). If it matters, the fix is to move the calibration
read inside the iteration like everything else.

## THE FPFDR RETENTION TERM IS SEPARATE FROM STAGE 7, AND WAS RELEASED (2026-09-02)

An earlier claim in this session - "we cannot reduce FirstPassFDR without implementing the lean
row for SecondPassFDR" - is **WRONG and withdrawn**. Two independent O(runs) structures were
collapsed into one:

| structure | size at 446 | lives from | read by Stage 7? |
|---|---|---|---|
| FirstPassFDR planning products | ~13 GB | end of planning -> process exit | **no** (3 of 4) |
| Stage 7 survivor pool | ~0.197 GB/file, ~103 GB at 500 | Stage 7 | it IS Stage 7's input |

Grepping every `Get`/`Consume`/`TryGet` reader: `ReconciliationActions` (30.8 M entries at 446),
`PerFileConsensusTargets` and `RefinedCalibrations` are read ONLY by `PerFileRescoreTask.Run`.
`PerFileGapFillForRescore` is the sole one Stage 7 touches, via the pool rebuild
(`Rehydrate -> OverlayReconciledIntoFiles`).

**Both references had to go.** Consuming the byproduct alone frees nothing: `FirstPassFdrTask`
holds all four as FIELDS (`:167-171`) and the task instance lives in the pipeline array for the
life of the process, so the field outlives every consumer. That is precisely how these came to
be held from the end of planning through the whole rescore with no reader - not a decision,
an omission with no mechanism to catch it. Fixed by nulling the fields at the publish site (the
byproducts hold them now, and every field is read only by `Rehydrate`, which is mutually
exclusive with the `Run` that just published) plus `Consume` at the single reader.

**Unit gate caught a real weakening on the way**: relaxing `Publish` from `Add` to upsert for the
drop diagnostic turned `TestPublishOnceThenTryGetReads` red - "Expected publish-once violation to
throw". Correct: an invariant relaxed for one experiment must not be relaxed for the default
path. The upsert is now conditional on `OSPREY_DROP_BETWEEN_TASKS`.

## THE STAGE 7 HANDOFF SHOULD BE A LEAN SIDECAR, NOT A LEAN STRUCT (developer, 2026-09-02)

> *"lean row implementation will involve a more efficient sidecar between FPFDR and SPFDR which
> will reduce the read time and the memory peak in SPFDR."*

The drop experiment MEASURED the cost this would remove. Forcing Stage 7 to rebuild its pool from
disk instead of inheriting it in memory, on 10 CHS files:

| | pool inherited | pool rebuilt |
|---|---|---|
| SecondPassFDR peak | 7.2 GB | **17.8 GB** |
| SecondPassFDR wall | 0:32 | **1:19** |
| every other phase | unchanged | unchanged |

That +10.6 GB and +47 s is entirely `BuildRescoredPool` re-reading each run's
`.scores-reconciled.parquet` and `.1st-pass.fdr_scores.bin` and allocating fat `FdrEntry`
objects. It is the price of the handoff being a PARQUET RE-READ rather than a purpose-built
artifact.

**Why the sidecar beats the in-memory lean row.** `TODO-20260826` specced the lean row as an
88 B struct against `FdrEntry`'s ~274 B - a 3.1x cut, in memory, in one process. Writing those
same 88 B as a per-run sidecar instead gets the same reduction AND:

* **crosses the process boundary**, so an HPC Stage 7 node reads it directly - the in-memory
  struct helps only the single-process case, which is the one that already works;
* **removes the parquet decode**, not just the object allocation - the rebuild's cost is
  columnar decode plus interning plus allocation, and a flat binary is a read plus a cast;
* **is streamable** - Stage 7's consumers are already O(distinct) folds over `rescored.Files()`,
  so they can fold a file at a time and never hold the pool at all, which the struct alone does
  not achieve;
* **matches the artifact the pipeline already writes** - `PerFileRescoring` emits
  `.2nd-pass.fdr_scores.bin` at exactly the moment the code says all three inputs are
  simultaneously true (`PerFileRescoreTask.cs:1250-1256`: survivors in hand, reconciled parquet
  on disk, heavy payload not yet dropped). The lean row is the same write, widened.

**What it must carry** is the lean-row audit's field list (`TODO-20260826`): `EntryId`,
`PeptideId` (interned), `Charge`, `IsDecoy`, `Score`, both run q-values, both experiment
q-values, `ApexRt`/`StartRt`/`EndRt`, `BoundsArea` = 88 B padded. Check it against the existing
`.2nd-pass.fdr_scores.bin` schema first: if that already carries the q-values and score, the
delta is the four spectral doubles plus the interned peptide id, and this becomes a format
extension rather than a new artifact.

**Sequencing note**: this also retires the last coupling found today. `PerFileGapFillForRescore`
is held only because the pool rebuild needs it; a Stage 7 that folds per-run sidecars reads each
run's gap-fill from that run's envelope instead, and the last of FirstPassFDR's planning products
can be released with the other three.

### REFINEMENT: the rebuild's cost is RE-DERIVATION, not just I/O (developer, 2026-09-02)

> *"You said it has to recalculate from scratch, but that may indicate only that FPFDR could be
> writing a more efficient sidecar for SPFDR that would involve less calculation."*

Correct, and it reframes the fix. Framing the +10.6 GB / +47 s as a read cost misses that most
of those steps are re-deriving state the upstream phase already had. Per run, the rebuild does:

1. parquet decode -> `List<FdrEntry>` (allocation + interning)
2. sidecar read + `entry_id` binding, **discarding most records**
3. filter to survivors
4. overlay reconciled scalars (a second parquet pass)
5. append gap-fill
6. canonical sort

Only (1) is reading. (2) exists **purely because the sidecar is written at the wrong
granularity** - `RescoreHydration` says so: *"The 1st-pass sidecar is written over the WHOLE
pre-compaction row set, but these stubs come from the reconciled parquet, which now holds only
the Stage 5 survivors (#4486) - so most of its records have no entry to land on."* At CHS that is
1.34 B rows written to serve 289 M survivors: a ~4.6x overwrite paid on every write AND every
read.

**So the first fix is granularity, not format**: FirstPassFDR should write its per-run sidecar
over the survivors it just selected. It knows the retained set at that instant - it is the same
set it writes into `retained_base_ids.bin`, in the same phase. The downstream overlay then
becomes a positional read with no binding and no discard, and the artifact shrinks ~4.6x.

This is SMALLER than the lean row and composes with it: the lean sidecar cuts bytes per row
(274 B -> 88 B), the survivors-only write cuts rows (~4.6x). Neither needs the other.

**VERIFIED CONSTRAINT - it must be TWO artifacts, not one narrowed one.**
`ModelDiagnostics/PeakCoAssignmentSource.cs:341,449` reads `FdrScoresSidecar.Pass1Path`
directly, and needs the PRE-compaction rows (compaction discards ~52x of them, mostly the decoys
and entrapment its FDP and calibration views are built from). Narrowing the sidecar would
silently degrade that report rather than fail it. `--fdrbench-pass 1` wants the same population.

So: a survivors-only sidecar on the default path, and the full pre-compaction one written only
when `--model-diagnostics` / `--fdrbench-pass 1` ask. That is the SAME policy `ResidentPaths`
already applies to those two modes in the memory layer, expressed in the artifact layer - which
is where it belongs, since the cost is now paid in bytes on disk rather than bytes in RAM.

### THIRD AXIS: a FIXED-WIDTH struct removes per-record work entirely (developer, 2026-09-02)

> *"Fixed byte structs can be read extremely quickly also"*

Three independent axes on the Stage 7 handoff, and they compose:

| axis | change | effect at CHS 446 |
|---|---|---|
| granularity | write survivors, not the pre-compaction pool | ~4.6x fewer rows |
| width | 88 B lean row, not ~274 B `FdrEntry` | ~3.1x fewer bytes/row |
| **layout** | **fixed-width struct, bulk read + cast** | **no per-record work, no allocation** |

The third is the one that also removes GC pressure rather than merely reducing it. A run's
contribution is read as one buffer and reinterpreted in place -
`MemoryMarshal.Cast<byte, LeanRow>` - and Stage 7's consumers, which are already O(distinct)
folds over `rescored.Files()`, fold a `ReadOnlySpan<LeanRow>`. **No managed objects are created,
so the collector never sees the pool at all.** That is the difference between shrinking the heap
and not putting it on the heap.

Scale: ~648 K survivors/run x 88 B = **~57 MB per run**. A bulk read plus a cast on 57 MB is
milliseconds. The current path decodes parquet columns, allocates ~648 K `FdrEntry` objects,
interns their sequences, binds them against a sidecar 4.6x larger than needed, and sorts.

**The pattern is already proven in this codebase** and documented as the fix for this exact
shape - `SpectraCache.ReadIndex`: *"Read the acquisition-order index in one compact contiguous
EOF read - no record walk ... touching only ~40 B/record instead of seeking across the whole
6 GB body."* So this is applying an established technique at a new boundary, not introducing one.

Two mechanics for the implementer:

* **The existing sidecars are already fixed-width** (`FdrExperimentSidecar` 44 B/record,
  `RetainedBaseIdSidecar` 4 B) but are read field-by-field through `BinaryReader`, which
  reintroduces the per-record cost the layout was chosen to avoid. **The layout is right; the
  READER is what changes.** Worth fixing on the existing sidecars independently of the new one.
* **`System.Memory` is already referenced for net472** (conditional ItemGroup in
  `Osprey.IO.csproj`), so `Span`/`MemoryMarshal` build on both TFMs with no new dependency.
  Mind endianness and explicit `[StructLayout(LayoutKind.Sequential, Pack = 1)]` so the on-disk
  form is a contract rather than whatever the JIT chose - the parity gate compares these files
  byte for byte across net472 and net8.0.

## Progress log - 2026-09-02 (end of session)

### Landed and gated

* **`--task PerFileRescoring` startup is O(1) in run count.** 86-run plate: 14m17s / 24.7 GB
  managed -> **38 s / 5.25 GB**, O(runs) portion zero. Completed 86/86 reconciled parquets, exit
  0, 1h30m, floor LEVEL. Committed `91a2b0919f`.
* `retained_base_ids.bin` + `retained_base_ids_migrate.py` (byte-validated against Osprey's own
  writer), single-pass hydrate, typed `SpectraCacheException`, `--cache-dir` for task legs, the
  analysis-wide relay in the runner, and a mode 3 assertion that the per-run PATH ran.

### Uncommitted, and it is two separable changes

Fix A (FirstPassFDR releases ~13 GB of planning products; per-run extends to straight-through)
and diagnostic B (`OSPREY_DROP_BETWEEN_TASKS`). Stellar 13/13 PASS with both. Astral was
re-running at session end - `ai/.tmp/sessions/20260902-retainedset/gate-astral2.log`.

### Two capability losses found late, both silent

* **`--model-diagnostics` produced NO report** on the per-run path - the fold reads
  pre-compaction rows during a hydrate that no longer happens. The 86-run plate run exited 0 with
  86/86 parquets, `mdiag=True`, and no HTML. `CanHydratePerRun` now excludes it; the real fix is
  a per-run fold written after the loop.
* **`--task ModelDiagnostics`** was routed down the per-run path because the predicate listed
  what to EXCLUDE and admitted anything unlisted. It now names what it admits, so an unlisted
  task fails closed.

### The three-axis Stage 7 plan

Granularity (survivors-only sidecar, ~4.6x fewer rows) / width (88 B vs 274 B) / layout
(fixed struct read as a span, nothing on the heap). Independent, composing, granularity first.
Constraint verified: two artifacts, because `PeakCoAssignmentSource` needs the pre-compaction
rows. Rebuild cost measured at +10.6 GB / +47 s on 10 files, isolated to SecondPassFDR.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260902_osprey_perrun_446.md` before starting work.

### THE ACCEPTANCE CRITERION for Stage 7, stated relationally (developer, 2026-09-02)

> *"I would like to see both FDR tasks lower memory and SecondPass lower than FirstPass, because
> it is dealing with a much smaller bounded set of entries."*

This is a better target than an absolute ceiling, because it is box-independent and cannot be
satisfied by adding RAM:

* FirstPassFDR processes the full PRE-compaction pool - 1,342,686,095 entries at 446 runs.
* SecondPassFDR processes only the survivors - 288,920,200. About **4.6x smaller**, and bounded.
* **A stage doing strictly less work must not peak higher.**

The 2026-08-24 257-file plot shows the inversion: SecondPassFDR ~70 GB (past the 63.7 GB box)
against FirstPassFDR's ~55 GB. That inversion IS the diagnosis - Stage 7's cost is its
REPRESENTATION, not its workload. It holds ~274 B `FdrEntry` objects rebuilt from parquet where
88 B of fixed-width row would serve, which is exactly what the three-axis plan above addresses.

**Use this as the pass/fail test on any future plot**: if Stage 7 is the tallest region, the goal
is not met even when the run completes. The middle (PerFileRescoring) was never the problem - it
was already flat at ~20 GB across 5.5 h at 257 files, before any of this work.

## Progress log - 2026-09-02/03 (night session)

### Gated and committed on `Skyline/work/20260901_osprey_firstpass_resume`

* `550cb2a153` **Stopped FirstPassFDR holding its planning products past their reader** - the
  fix A of the handoff: `Consume` the three planning products at their single reader on every
  path, null the matching `FirstPassFdrTask` fields at the publish site, admit-list
  `CanHydratePerRun`, exclude `--model-diagnostics`, and read the resume path's gap-fill and
  refined calibrations from each run's envelope.
* `c955943146` **Added an off-by-default drop-between-tasks diagnostic** (`OSPREY_DROP_BETWEEN_TASKS`).

**Astral gate**: `gate-astral4` (`ai/.tmp/sessions/20260902-retainedset/gate-astral4.log`) ran
18/19 PASS - including `mode3 (HPC chain==straight)`, `mode5 (rehydrate diagnostics vs golden)`
and `mode7 (diagnostics regeneration)`, which closes both capability losses found earlier that
day. `gate-astral5`
(`ai/.tmp/sessions/20260903-stages567/gate-astral5.log`) then ran **Osprey regression PASSED**.

### The one red was in the GATE, and it had never read anything

`mode3 (per-run hydrate)` failed on Astral for doing the right thing. The skip added for
`--model-diagnostics` was written `$Spec.ModelDiagnostics`, but in that loop the dataset spec is
`$cfg` (`regression.ps1:1593`); `$Spec` is a parameter of the helper FUNCTIONS. The read returned
`$null` on every dataset, `-not $null` is true, and the assertion ran regardless. Fixed to `$cfg`
with a comment recording it.

Worth keeping as a shape: the handoff's "a green check next to a missing thing" has a twin - a
RED check for the right behaviour, from a predicate that was never evaluating the thing it named.
Both come from an assertion whose subject is not what its text says.

### Minted the retained set for the completed 446 FirstPassFDR

`retained_base_ids_migrate.py` over
`chs-446files-libdecoy-r1.0-protein-compact-stage5stream`: 446/446 envelopes, **744,943
base_ids**, 2,979,804 bytes (= 32 + 744943 x 4, exact), 170 s. Action targets not already in the
join-wide set: **0**.

### THE STAGE 7 SIDECAR READ, and two corrections to the three-axis plan

Full working notes: `ai/.tmp/sessions/20260903-stages567/stage7-read-path-findings.md`.

**Correction 1 - the granularity axis cannot be a narrowing of the existing write.**
`FirstPassFdrTask.FlushPartialSidecar` (`:2689`) is called by the StoringSink DURING the Stage 5
score pass, so the four streamed q-values are never resident; the retained set does not exist
until `PlanStage6` ends, hours later. Moving either to meet the other breaks P7 (persist at phase
end, as close to the work it safeguards). The existing write is already right: `FileSaver`-atomic,
stamped per file at write time, write-once.

**Correction 2 - deriving a narrowed sidecar in FirstPassFDR would violate P3.** That is a 47 GB
read / 8 GB write of `O(runs x entries)` work placed in a JOIN. If a narrowed per-run artifact is
wanted, `PerFileRescoring` is where it belongs - the fan-out task already holds exactly that run's
survivors and already writes `.2nd-pass.fdr_scores.bin` at that moment. Granularity then is not an
axis; it is a consequence of writing in the task whose state is already narrow.

**The finding underneath both**: the workflow banner (`Osprey-workflow.html:507-512`) and doc 00's
Boundary 3 -> 4 both say `<stem>.1st-pass.fdr_scores.bin` is **not needed on the default path** for
`SecondPassFDR`. But the in-process Stage 7 rebuild reads all 446 of them:
`BuildRescoredPool` (`PerFileRescoreTask.cs:2310`) -> `MaterializeFileSurvivors` (`:2438`) ->
`FirstPassSurvivorLoader.Load` (`:153`) -> `FdrScoresSidecar.TryRead`. That is P10's corollary
inverted - *the in-process path should read the same artifact the distributed path does* - and it
means the granularity problem is already solved on one route. It reads it because
`.scores-reconciled.parquet` carries boundaries, area and features but not Score / q-values.

**Open, and to be settled by comparison rather than reasoning**: whether the distributed route's
per-run `.2nd-pass.fdr_scores.bin` is a like-for-like substitute. `BuildRescoredPool` is rebuilding
the FIRST-pass survivor pool that Stage 7 then rescores, and `ResetRescoredTargetsForFile` exists
because rescore targets must return to Score 0 / q 1, so overlaying 2nd-pass values there would
pre-apply pass 2.

### Landed: chunked sidecar reads (branch `Skyline/work/20260903_osprey_sidecar_chunked_read`)

`571fb86edd` replaces the two `File.ReadAllBytes` call sites - the only two in all of Osprey, both
in `FdrScoresSidecar` - with `TryWalkRecords`, a shared header validation plus a 2,048-record
buffered walk (57,344 B, under the 85,000-byte LOH threshold). No format change, no consumer
change, byte-identical result.

Measured basis: `EXP25033_2025us0059aX10_A.1st-pass.fdr_scores.bin` is 106,327,120 bytes =
3,796,682 records at 28 B (v6 - the class XML doc still says v5 / 36 B and is stale), against a
survivor share of ~648 K. **~5.9x more records read than land; 47 GB and 1.69 B records walked at
446 files to place 289 M.** Stage 7's band is Server-GC retained COMMITTED memory
(`project_osprey_pipeline_peak_is_servergc_retained_committed`), so a parade of 106 MB LOH arrays
inflates it directly even though none is reachable for long.

New test `TestFdrScoresSidecarChunkBoundaries` covers counts 0, 1, 1023, 1024, 1025, 2047, 2048,
2049, 4096, 4103. Every other sidecar test in `IOTest.cs` writes a handful of records and would
pass against a reader that dropped or misaligned everything past the first buffer.

**NOT GATED.** Build + 603 unit tests + zero-warning inspection only; `regression.ps1` cannot run
while the 446 measurement holds the box. Run `-Dataset Stellar` then `-Dataset All` before merging.

**Why this one is exempt from "no intermediate the next step deletes"**: it is an IO-layer fix on
a read every route performs, including a fan-out worker reading its OWN run's sidecar. The
width/layout axis is NOT exempt - it introduces a new on-disk struct, and doc 00 "In flight" item 3
says `RescoredEntries` is a materialised whole-run pool that P3 forbids outright. Do not start it
before the 446 measurement says the pool is still the binding term.

### CORRECTION (same session, 23:05): "already solved on one route" is withdrawn

The paragraph above concluded that the distributed route does not read the pre-compaction
1st-pass sidecar while the in-process one does - P10's corollary inverted. **That went one
inference past the evidence and is withdrawn.**

Established: `SecondPassFdrTask.cs:88-100` no longer DECLARES the per-run 1st-pass sidecars
(only under `OSPREY_PASS2_VERIFY_WORKER`), and its own comment says in the past tense that they
"were never DECLARED here, but they were READ every run". Not established: that no read remains.
`RescoreHydration.OverlayFirstPassSidecar` (`:755-770`) still resolves `Pass1Path` and calls
`TryRead`, and on `--task SecondPassFDR` the `ExpectReconciledInput` branch of
`PerFileRescoreTask.Rehydrate` (`:600`) pulls `RescoreBundle`, which `PerFileScoringTask`
materialises through that hydrate - gated at `PerFileScoringTask.cs:604` on
`!CanHydratePerRun(config) && hasReconSidecars`, which I did not evaluate for that node.

**Settle it the way this codebase settles this class of question** (P10: an in-memory belief
cannot answer a question about a file that outlives the process): emit one `ctx.LogInfo` at
`OverlayFirstPassSidecar` naming the artifact, then assert its presence or absence in every
`phase4_*.log` from `regression.ps1 -Dataset Astral` mode 3 - the same shape as the existing
mode 3 per-run hydrate marker.

If the distributed route reads it too, granularity is solved NOWHERE and the axis is fully open.
The chunked read is unaffected either way: it is the same reader on both routes, which is the
other reason it was the right thing to land first.

## DEFECT FOUND BY THE RESUME TEST, 2026-09-03: a PARTIAL rescore resumes as COMPLETE

The developer asked for a kill-and-restart test of the resume design. It found this.

**Evidence, from the resumed 446-file run** (`chs-446files-...-stages567`, restarted 05:57:22
after a kill at 141/446 rescored):

* `[TASK] FirstPassFDR:skipping (outputs valid)` - correct, 4h46m not redone.
* `Per-run rescore: FirstPassFDR publishes the survivor loader only; no experiment-wide bundle
  is built for 446 run(s).`
* **`grep -c "Re-scoring file" run.log` = 0.** Not one file was rescored.
* Reconciled parquets stayed at **141 of 446** for the life of the run.
* It went straight to the survivor-pool rebuild: total memory 20.5 GB at 4%, 27.1 GB at 16%,
  35.5 GB at 26% - **0.68 GB per percentage point, projecting ~86 GB** on a 63.7 GB box. Killed
  at 06:19 with WS 37.5 GB / private 38.6 GB.

### Root cause

`PerFileRescoreTask.cs:350-366` computes `anyPass2Present` with a **first-match `break`**: one
input file with a current `.2nd-pass.fdr_scores.bin` sets it true. With 141 of 446 present it is
true. Then `:381`:

```csharp
if (!didPlan && ((rescoreBundle == null && !perRunPlanAvailable) || anyPass2Present))
{
    _poolPlan = RescoredPoolPlan.RefillOnly(_perFileEntries, survivorLoader);
    return true;   // "No rescore to run"
}
```

`didPlan` is false because FirstPassFDR was skipped, so `anyPass2Present` alone decides. The
gate's own comment says it exists so "a completed run must still no-op" - but **"any" is not
"complete"**, and a partially-completed rescore is indistinguishable from a finished one under
this test.

### Two consequences, and the first is worse

1. **Correctness.** 305 of 446 runs are silently left un-rescored. Had Stage 7 survived, the blib
   would carry 1st-pass q-values for those runs - a wrong answer that finishes success-shaped.
   The comment at `:355-358` documents this EXACT outcome from an earlier trigger of the same
   gate: "made the WHOLE Stage 6 rescore a no-op - the run then finished green carrying 1st-pass
   q-values into the picked-protein FDR and the .blib." Same defect, new trigger: partial
   completion instead of a stale format version.
2. **Memory.** Having decided there is no rescore, it takes `RefillOnly` and rebuilds the whole
   446-run survivor pool - the O(runs) path - and heads for ~86 GB.

### Fix

The gate must ask whether **every** input has a current pass-2 sidecar, not whether any does, and
it should LOG the count so a partial state is visible rather than inferred. A run that is 141/446
done has work to do, and that is the common case for every resume - which is the shape this
project keeps rediscovering: a check that passes while the thing it names is not happening.

Worth a regression assertion of its own: kill a rescore mid-cohort, resume, and assert the
reconciled-parquet count reaches the full cohort. Nothing in mode 2 or mode 4 covers a PARTIAL
per-file state today.

## THE FAN-OUT STARTUP FIX DOES NOT HOLD ON A RESUME (measured 2026-09-03)

Startup time on a resume is a test in its own right, and it fails. Same build
(`245-allpass2-resume`), same 446-file cohort, same task, two paths:

| `[TASK] PerFileRescoring:starting` -> `Re-scoring file 1/446` | |
|---|---|
| fresh straight-through (FirstPassFDR ran in-process), 03:30:15 -> 03:30:25 | **10 s** |
| resume (FirstPassFDR skipped, outputs valid), 08:53:35 -> not reached by 09:02:54 | **> 9m19s** |

Decomposed, because only part of it is legitimate:

* **36 s** (08:53:35 -> 08:54:11) library cache + decoy pairing manifest, 4.19 GB resident. This
  is P5's memory baseline and is ALLOWED - on the fresh path FirstPassFDR had already loaded it,
  which is why the fresh number is not comparable without this split.
* **8m41s and counting** (08:54:13 -> ) `Loading scored entries...` - a sequential pass over all
  446 `config.InputFiles`. This is **forbidden**.

### Where, and why the earlier fix missed it

`PerFileScoringTask.Rehydrate:703`, the straight-through RESUME arm. It never consults
`ScoringTaskShared.CanHydratePerRun`. Its `--input-scores` sibling at `:1343` does, and takes
`LoadJoinOnlyPerRunNames` instead - which is why the fresh and `--task PerFileRescoring` paths
are fast and this one is not. One more instance of "stop building X is one edit PER PRODUCER,
and the producers are not co-located".

Doc 00 P6, second term, is the rule broken:

> **no fan-out task may have a loading phase whose cost grows with the number of runs it was
> handed.** Where such a task needs a cohort-wide fact, an earlier phase computes it once and
> writes it (P12) and the fan-out reads that bounded summary - it never conducts its own survey
> of the batch.

The doc's own example of the previous instance: "it shipped, as 8m42s and 17.2 GB of startup on
an 86-run plate." This one is 8m41s at 446 - lighter per run, same class, same shape.

### What a rescore node is allowed to load (Boundary 2 -> 3)

Experiment-wide, to every node, all bounded:
`<blib-stem>.1st-pass.fdr_experiment.bin` (O(distinct entry_ids)),
`<stem>.1st-pass.model.json` (any one copy), `<blib-stem>.1st-pass.retained_base_ids.bin`
(library-bounded, 2.98 MB at 446). Everything else - `.scores.parquet`,
`.1st-pass.fdr_scores.bin`, `.reconciliation.json`, `.calibration.json`, `.spectra.bin` - is
per-run and belongs INSIDE that run's iteration.

**Also not clean**: `LoadJoinOnlyPerRunNames` still loops every run to read its
`.calibration.json`. Small per file, but it is still a survey of the batch and violates the same
term more mildly. Both arms want the same treatment.

### The assertion this earns

Startup is measurable from the log with no instrumentation, so the gate can assert it directly:

    time(PerFileRescoring:starting -> first "Re-scoring file") MINUS library-load time
    must not grow with run count, on EVERY path - fresh, resume, and --task.

That is stronger than the existing mode 3 per-run-hydrate MARKER assertion, which only proves
which path was taken, not that the path was cheap. A resume that takes the right arm and still
surveys the batch would pass the marker check and fail this one.

### PROVEN on the real failing case, 2026-09-03 09:06-09:20

The 446-file cohort left at 141/446 was the test bed. Same directory, same cohort, build
`245-allpass2-resume`:

```
09:06:07  Rescore resume: 141 of 446 run(s) already carry a current 2nd-pass sidecar;
          re-scoring the remaining 305.
09:06:09  Per-run rescore: hydrating each of 446 run(s) from its own artifacts
          (no all-runs pre-load; 625620 retained base_id(s) read once).
09:06:10  [MEM reconciliation-floor] managed_heap=5.19 GB (post-GC, entering rescore)
09:06:15  [file] 1/446 ... skipping (outputs valid)      <- 141 of these
09:19:58  Re-scoring file 142/446: EXP25033_2025us0060bX53_A
```

All three properties hold: it DETECTS the partial state, REPORTS it so the reuse is auditable,
and RESUMES at exactly the first un-rescored run. The broken build, at the same point in the same
directory, printed nothing, took `RefillOnly`, and rebuilt the whole 446-run survivor pool toward
~86 GB without rescoring a single file.

**One more O(runs) cost on the resume path, found here**: each SKIP of an already-complete file
costs ~5.8 s (141 skips, 09:06:15 -> 09:19:58 = 13m43s). Bounded and far cheaper than rescoring,
but it means resuming near the end of a 446-run cohort spends ~43 min walking completed files.
Same shape as the `PerFileScoringTask.Rehydrate:703` survey, different site.

Total resume overhead before useful work at 446: **26m23s** (08:53:35 -> 09:19:58) =
36 s library (allowed, P5) + 9m46s all-files survey (`:703`, forbidden) + 2m08s per-run setup +
13m43s skipping completed runs.

## RESUME STARTUP: 26m23s -> 2m53s at 446 files (measured 2026-09-03)

Three fixes, each measured separately on the same 141-of-446 bed, same cohort, same build chain.

| phase | before | after | fix |
|---|---|---|---|
| library load | 36 s | ~39 s | unchanged (P5 baseline, legitimate) |
| `Loading scored entries` | **9m46s** | **10 s** | `FdrProjections` published as a lazy factory |
| library-fragment release | 2m07s | 1m54s | unchanged - **now 66% of the remainder** |
| skip 141 completed runs | **13m43s** | **5 s** | resume check hoisted ABOVE the per-run hydrate |
| **total to first real rescore** | **26m23s** | **2m53s** | |

### 1. The projection nobody read

`PerFileScoringTask.Rehydrate` streamed every row of every parquet - 1,342,686,095 at 446 files -
into a counts-only `FdrProjectionSet`. Its ONLY consumer is `FirstPassFdrTask.Run`
(`ctx.Consume<FdrProjections>()`), and a resume whose 1st-pass outputs are valid SKIPS that Run.
Built and discarded, every time.

`FdrProjections` now takes a `Func<FdrProjectionSet>` and builds on first read - the same shape
as the `RescoredEntries` milestone. The row total the log line and the no-scored-entries guard
need comes from `ParquetScoreCache.ProbeResumeSchemaAndRows`, which returns the PIN-schema flag
AND the declared `NumRows` from ONE footer open - the open the lean branch was already doing for
`HasPinFeatureColumns`. 446 opens, not 892, and no scan.

### 2. The decision that followed the load

`ExecuteRescore` called `inputs.HydrateRun(file.Key)` - that run's `.scores.parquet`, its ~106 MB
1st-pass sidecar overlaid, compaction - and THEN called `RescoreOneFile`, whose first act is
`TryResumeRescoredFile` -> "skipping (outputs valid)". Every already-complete file was fully
loaded and thrown away, ~4.7 s each, serialized under `_survivorLoadLock`.

The check is a stamp read. Hoisting it above the hydrate took 141 skips from 11m14s to **5 s**.

### 3. The skip arm was also building the all-runs buffer

`TryResumeRescoredFile` overlaid the reconciled parquet back into the in-memory entries so a
downstream SecondPassFDR would not read 1st-pass RTs. That was target-shape violation item 6 in
the one place it survived. It now CLEARS, exactly as the rescore arm does once its reconciled
parquet is written - and for the reason that arm gives: "that parquet is what the deferred pool
build restores them from." Stage 7 loads its own via `BuildRescoredPool`'s `loadedReconciled`
branch. (Worth ~2.5 min on its own; fix 2 subsumed most of it.)

### What is left, and it is one thing

**`LibraryFragmentRelease`: ~1m54s**, walking 6,175,389 library entries to release fragments for
the 4,924,513 not in the retained set. O(library), CONSTANT in run count - so it is ~2 minutes at
3 files or 4,000, and it is now 66% of the resume overhead.

**The developer's fix (2026-09-03): prebuild the set and drop fragments during the READ.** The
retained set is a 2.98 MB artifact already on disk before the library load on the rescore and
SecondPassFDR paths - the two that pay this - and the two counts already agree (the release
reports 625,620 retained; the per-run hydrate reports 625,620 read once). `LibraryCache` already
has an `omitFragments` overload and a `SkipFragment(r)` that "reads past one fragment record
without materializing it, advancing the reader exactly as the full fragment read would". What is
missing is only that it is all-or-nothing rather than per entry: pass the set, decide per entry
on `id & BASE_ID_MASK`. That never allocates the 4.9 M fragment arrays, removes the release pass
entirely, and lowers the peak - which today is 25.50 GB *including* fragments about to be
discarded. A fresh run keeps the current behaviour, correctly: it needs the fragments, and the
retained set does not exist yet.

### Fragment-drop-during-read: IO half DONE, wiring BLOCKED on one predicate

Landed (inert - the default retains everything, so no behaviour changes yet):

* `LibraryCache.LoadCache(..., HashSet<uint> retainFragmentsFor = null)` - the fragment decision
  is now PER ENTRY (`!omitFragments && (set == null || set.Contains(id & 0x7FFFFFFFu))`) rather
  than all-or-nothing, reusing the `SkipFragment(r)` that already advances the stream without
  materialising. base_id, not Id, so a target and its paired decoy stay together.
* `LibraryLoadOptions.RetainFragmentsFor`, threaded through `LibraryLoader`.

**NOT wired, and this is the open question.** The caller would be
`PerFileScoringTask.LoadLibraryAndDecoys` (`:978`), which has `config` in scope and could read
`retained_base_ids.bin`. But:

`LibraryFragmentRelease` drops non-retained fragments AFTER Stage 5, when the retained set is
known in-process and is definitionally THIS run's. Dropping at library-load time trusts the set on
DISK, which is only equivalent when FirstPassFDR will not run and produce a different one. Neither
available predicate says that:

* `CanHydratePerRun` tests task selection, `StopAfterStage5`, `ExpectReconciledInput`,
  `ModelDiagnostics` and the sidecar FORMAT - not whether FirstPassFDR's outputs are valid.
* `RetainedBaseIdSidecar.IsCurrentFormat` tests the format version, not the validity key.

Getting it wrong drops fragments for entries the run still needs, and the symptom is missing peaks
in the .blib rather than an error - a wrong answer that looks like a right one, in the artifact
used to judge correctness. **Settle it by finding (or adding) a predicate that answers "FirstPassFDR
will rehydrate, not run, under this run's validity key", not by assuming the on-disk set matches.**

Second decision needed: mode 6 asserts "library-fragment release engaged on every leg that holds
the library". A leg that drops during the read has nothing left to release, so mode 6 must accept
that as satisfying the same goal, or it fails a leg for doing the better thing.

**RESOLUTION PATH for that predicate** (found 2026-09-03): do not write a new one.
`PipelineContext.CanRehydrate(OspreyTask task)` is public (`PipelineContext.cs:486`) and already
answers exactly the question - it reads the task's own `Outputs(this)` and `ValidityKey(this)` and
tests every declared output against the stamp. Asking it about the FirstPassFDR task instance says
"FirstPassFDR will rehydrate, not run", which is the condition under which the on-disk retained set
is THIS run's.

Re-deriving FirstPassFDR's six key components at the library-load site instead would be the drift
doc 00 warns about: "re-deriving the rule at one call site and importing it at the other is
precisely the drift this change exists to remove."

Remaining mechanical question: how `PerFileScoringTask` reaches the FirstPassFdrTask INSTANCE from
the pipeline array (the driver owns it). If nothing exposes tasks by type, that accessor is the
change - not a new predicate.

## MODE 8 FOUND A SECOND PARTIAL-RESUME FAILURE, ON THE MDIAG PATH (2026-09-03, Astral)

`regression.ps1 -Dataset Astral` on the full fix set: **18 PASS, 1 SKIP, mode8 FAIL (33 issues)**.
Every product change is clean - mode1/1b/1c, mode2, all four mode3 checks, mode4, all four mode5
checks INCLUDING `mode5 (rehydrate diagnostics vs golden)`, mode6, mode7. Stellar was fully green
including mode8.

**The first issue explains the other 32:**

    only 2 of 3 reconciled parquet(s) after the resume; the rescore did not finish the cohort

The amputated run was never rescored; the 236 RefSpectra keys only in golden, 2,647 missing
RetentionTimes keys and every RT/score delta are downstream of that one fact. COUNT caught it and
VALUE confirmed the consequence - which is the pair working as designed, and is why the mode
asserts both.

**Leading hypothesis, NOT established**: Astral carries `--model-diagnostics`, so
`CanHydratePerRun` is false and the resume runs through the ALL-RUNS BUNDLE path rather than the
per-run path where `allPass2Present` was proven on the 446 cohort. That would make this the same
shape as everything else found today - the mdiag path routing around the code that was fixed, like
the over-broad exclusion and like `PerFileScoringTask.Rehydrate:703` being the arm four earlier
removals never reached.

**The alternative, which must be ruled out first**: `Invoke-PartialRescoreInvalidation` removes
something that makes a file un-rescorable specifically on the bundle path, making this the
harness rather than the product.

**How to tell them apart**: read which arm `PerFileRescoreTask.Run` takes with
`rescoreBundle != null`, `didPlan == false` (FirstPassFDR rehydrates - mode 8 does not invalidate
it) and `allPass2Present == false` (2 of 3). The gate at `:410` is where the no-rescore decision
is made; if that is not the arm, follow where the amputated file's rescore is dropped.

**DO NOT COMMIT the fix set until this is resolved.** A partial resume that silently fails to
finish the cohort is the ORIGINAL defect, on a different path - and on the mdiag path it would
produce exactly the blib corruption above while reporting success.

## Progress log - 2026-09-03 (end of session)

### Landed in the working tree, UNCOMMITTED and deliberately so

`allPass2Present` (a partial rescore no longer reports done), the resume check hoisted above the
per-run hydrate, `FdrProjections` as a lazy factory, the skip arm clearing instead of overlaying,
`ProbeResumeSchemaAndRows`, `regression.ps1` mode 8 + `Invoke-PartialRescoreInvalidation`, the
inert `LibraryCache` per-entry fragment retention, and three corrected stale comments.

Build: **0 errors, 0 warnings, 602 tests / 601 passed**. Stellar **fully green** including mode 8's
first execution. Astral **18 PASS, 1 SKIP, mode8 FAIL** - every product change clean, including
`mode5 (rehydrate diagnostics vs golden)`.

**Resume startup at 446 files: 26m23s -> 2m53s**, in three separately attributed steps.

### What the session actually demonstrated

The straight-through result was real but incomplete - it ran without diagnostics, and that
limitation is what motivated treating RECOVERY as the problem rather than "re-run the whole
analysis once the happy path finishes". That reframing is why the resume work matters: the
developer's diagnostics design (FPFDR/SPFDR declaring the JSONs as outputs, so a run with
`--model-diagnostics` repairs the missing one) is only usable if a resume is cheap AND correct.
At 26m23s and silently skipping 305 files it would have been neither - and worse, a
diagnostics-repair run would have corrupted the analysis it was describing while producing the
report used to judge it.

### The gate suite is shaped like the happy path

Mode 2 resumes from a COMPLETE directory, mode 4 re-runs fully cached, mode 3 hands a node one
file. None presented a PARTIAL cohort, which is why the defect shipped. Mode 8 - added this
session - caught a second instance of the same class on its second dataset. The assertions that
work here are NEGATIVE and PROPERTY-shaped, not mechanism-shaped: "the cohort came back whole",
"the resumed blib is byte-identical", "the log does NOT contain the all-runs load". Mode 3's
per-run marker and mode 6's "release engaged" both check that a MECHANISM ran, which is what
breaks when the mechanism improves.

### Three fixes today all routed around `--model-diagnostics`

The over-broad `CanHydratePerRun` exclusion, `PerFileScoringTask.Rehydrate:703` being the arm four
earlier removals never reached, and now the mode 8 Astral red. One structural fact, not three
coincidences: mdiag takes a different route through the rescore, and every fix aimed at the
per-run path leaves it behind. This is why mdiag is merge-blocking and why it keeps turning out to
be the same work rather than adjacent work.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260901_osprey_firstpass_resume.md` before starting work.

### ROOT CAUSE of the Astral mode 8 red (2026-09-03, from kept scratch)

`regression-20260903_141713/Astral/straight/partial-resume.log`:

```
14:37:13  Rescore resume: 2 of 3 run(s) already carry a current 2nd-pass sidecar; re-scoring the remaining 1.
14:37:13  [TASK] PerFileRescoring:done (21.0s)
```

The marker announces the intent and the task ends in the SAME SECOND - no `Re-scoring file` line,
no per-file skip lines. The rescore never ran. So this is NOT the hoisted resume check and NOT the
skip-arm clear (my hypothesis, now withdrawn); it is the gate at `PerFileRescoreTask.cs:410`:

```csharp
if (!didPlan && ((rescoreBundle == null && !perRunPlanAvailable) || allPass2Present))
```

On Astral, `--model-diagnostics` makes `perRunPlanAvailable` FALSE, and the bundle is null on this
resume, so the FIRST disjunct is true and the arm fires regardless of `allPass2Present`. The
`anyPass2Present -> allPass2Present` fix corrected the SECOND disjunct only. The first self-gates
the same way, on the mdiag path.

The comment at `:368-379` already names this hazard - "both older signals are legitimately false
and the gate below would self-gate a run that has every input it needs" - but the third signal it
added (`perRunPlanAvailable`) does not exist under mdiag, so the hazard returns there untouched.

**The fix is NOT to widen the arm.** The two cases it serves are different:

* "no rescore NEEDED because the outputs exist" - `allPass2Present`. A completed run must no-op.
* "no rescore POSSIBLE because nobody supplied a bundle" - the first disjunct. With a PARTIAL
  set that means work is outstanding AND there is no way to do it, which must be an ERROR with a
  non-zero exit, not a silent success. `feedback_hard_fail_over_warn_proceed`: when proceeding
  risks silently-invalid output a user might trust, abort with a clear error.

So: when the first disjunct fires while `pass2Present < pass2Expected`, log and fail rather than
return true. That converts a blib silently missing a run into a named failure - which is the whole
defect class this session has been chasing.

**Note the diagnostic that made this findable**: the VISIBILITY assertion. The log line printed the
correct intent and was then contradicted by the very next line. Without it the symptom was only a
missing parquet three layers downstream.

### VERIFIED 2026-09-03 15:11: the gate fix works, and the capability gap is real

`regression-20260903_145138/Astral/straight/partial-resume.log`:

```
15:11:38  Rescore resume: 2 of 3 run(s) already carry a current 2nd-pass sidecar; re-scoring the remaining 1.
15:11:38  [ERROR] Rescore resume: 1 of 3 run(s) still need re-scoring, but this process has no plan
          to do it - FirstPassFDR did not plan here, no worker bundle was supplied, and the per-run
          hydrate is unavailable because --model-diagnostics keeps the all-runs hydrate.
15:11:38  [TASK] PerFileRescoring:done (20.9s)
```

**Both halves confirmed.** The silent wrong answer is now a named failure with a non-zero exit -
the 33-issue blib corruption is gone, replaced by one line saying what is missing and why. AND the
underlying gap is genuine: under mdiag a partial resume has no plan source, which no amount of
counting reaches. Closing it is the mdiag work, which is already merge-blocking.

Everything else on Astral stayed green: mode1, mode1c, mode1b x2, mode2 x2, mode6, mode7.

### Two consequences, one of them a separate defect

1. **Mode 8 now ABORTS the gate rather than reporting FAIL.** Osprey exits 1, and `regression.ps1`
   treats a non-zero Osprey exit as an abort, so the legs after it never run. Until the bundle path
   can rescore, mode 8 should EXPECT this on a dataset with `ModelDiagnostics = $true` - assert the
   error line and the non-zero exit, rather than crashing the run. That is the same shape as mode
   3's `SKIP (--model-diagnostics keeps the all-runs hydrate)`: a leg that cannot apply should say
   so, not fail.
2. **`[TASK] PerFileRescoring:done (20.9s)` prints AFTER the task returned false.** A task that
   failed should not log "done" - a reader scanning for task boundaries sees a successful
   completion one line below an ERROR. Small, but it is precisely the "green check next to a
   missing thing" shape this session keeps finding. Worth fixing in `AnalysisPipeline` where the
   done line is emitted.

### PROVEN PRE-EXISTING ON MASTER (2026-09-03 16:01)

The developer's test: mode 8 is NEW on this branch (0 occurrences at `c955943146`), so it has
never run on master and a pre-existing failure is possible. Settled by reverting ONLY the product
code to `c955943146` while keeping mode 8, and running Stellar - the non-mdiag dataset, so it
takes the COUNT/VISIBILITY/VALUE branch rather than the mdiag one.

**Stellar mode 8 on pre-change product code: FAIL (35 issues)**

```
only 2 of 3 reconciled parquet(s) after the resume; the rescore did not finish the cohort
partial-resume.log: no line containing 'Rescore resume:'
RefSpectra: 242 key(s) only in golden, 1836 key(s) only in run
```

With this branch's changes the same leg **PASSES**. That is the before/after on one assertion,
same dataset, same amputation.

**Conclusion: the partial-resume defect is on MASTER.** A user who kills a run and resumes it gets
a blib silently missing a run's data. It was invisible because mode 2 resumes from a COMPLETE
directory and mode 4 re-runs fully cached - no gate had ever presented a partial cohort, on any
dataset. Sessions clearing Stellar-only would not have caught it either; the assertion did not
exist to clear.

This also settles the scope question: the branch FIXES a shipped correctness bug rather than
introducing one. Still open and NOT settled by this: whether the skip-arm clear is a SECOND
defect on the mdiag/bundle path, which cannot surface until the gate stops short-circuiting there.

### Refinement to the cleanup rule, learned the hard way

"Clean up before" deleted a FAILED run's kept scratch: `-KeepRunDirs 0` prunes orphan
`regression-*` dirs at startup, and the next run removed the very evidence `-KeepOutput` had
preserved. The rule needs both halves - **the pre-run prune must also spare failed runs**, or
step 1 undoes step 3 on the next invocation.

### Session close, 2026-09-03 16:10

Committed on the branch: `804af25e53` (the resume fix set + mode 8) and `ac0fedf165` (the
no-rescore gate failing loudly instead of silently dropping runs). Uncommitted and unverified:
`regression.ps1` - `Invoke-OspreyRun -AllowNonZeroExit` plus mode 8's mdiag branch REPORTING the
capability gap as a FAIL rather than passing on it.

The mdiag branch was briefly written to PASS by asserting a well-worded refusal. The developer
pushed back - "I wasn't necessarily expecting the changes in this branch to change tests" - and he
was right: a green gate over a real gap encodes the limitation, which is the same trap mode 6 is
in with "release engaged". It now fails, and it will go green on its own when the bundle path
gains a plan source, with no test edit. That property - a leg that turns green when the product is
fixed rather than when the test is edited - is the test for whether an assertion is about
behaviour or about the current implementation.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260901_osprey_firstpass_resume.md` before starting work.

## FRAGMENT-DROP STAGE 1: the blocker is resolved, and a SILENT hazard is in its way (2026-09-03 evening)

Read-only investigation while the mode 8 verification gate ran. Three findings, and the middle
one changes the plan rather than adding to it.

### 1. The "remaining mechanical question" is already answered - no new accessor design needed

The previous entry closes on *"how `PerFileScoringTask` reaches the FirstPassFdrTask INSTANCE from
the pipeline array (the driver owns it). If nothing exposes tasks by type, that accessor is the
change - not a new predicate."*

It does expose them. `PipelineContext` holds `_tasksByType` (`PipelineContext.cs:53`, filled at
`:194-199` from the pipeline array), and the private `DemandByType(Type, bool materialize)`
(`:236`) already takes the flag that separates "resolve it" from "resolve AND drive Rehydrate".
**Every one of its two callers passes `materialize: true`** (`:294`, `:415`), so the
non-materializing half is written and unused.

So Stage 1's accessor is a public wrapper, not new plumbing:

```csharp
public bool WillRehydrate<T>() where T : OspreyTask
{
    return _tasksByType.TryGetValue(typeof(T), out var task) && CanRehydrate(task);
}
```

`TryGetValue`, deliberately, NOT `DemandByType`: the latter throws `UnknownTaskException` for a
task the current pipeline does not contain (`SpectraCachePipeline` has one task), and the right
answer there is "do not drop". That is the fail-closed direction `ScoringTaskShared`'s own
admitted-list comment argues for - "a task added later is excluded until someone decides
otherwise, which is the direction a predicate guarding a memory shape should fail in."

### 2. THE HAZARD: the `!omitFragments` short-circuit that made the all-or-nothing case safe is WRONG per entry

`DecoyGenerator.GenerateAllWithCollisionDetection` gates each target on:

```csharp
if (target.IsDecoy ||
    (!omitFragments && (target.Fragments == null || target.Fragments.Count == 0)))
{
    results[i] = (null, null, 0);   // EXCLUDED - no decoy, and dropped from validTargets
    return;
}
```

and its caller does `library = validTargets` (`PerFileScoringTask.cs:1055-1056`). The gate is
correct today for both existing cases: a full load has fragments everywhere, and an
`OmitFragments` load sets the flag so the gate is skipped wholesale - the comment says exactly
why, "every real entry had >= 1 fragment before the drop, so the gate could not have excluded
any."

**Per-entry retention breaks the assumption that makes that safe.** The read-time drop runs with
`omitFragments == false` (it is not a StopAfterStage5 load), so the gate is LIVE, and every one of
the ~4.9 M non-retained entries now presents `Fragments.Count == 0`. They are excluded from decoy
generation AND removed from the target library.

This is the failure shape the entry above warned about in the abstract - "the symptom is missing
peaks in the .blib rather than an error, a wrong answer that looks like a right one" - reached by
a route it did not name. It does not throw. `[COUNT] Library targets loaded` is emitted BEFORE the
gate, so it still reads 6,175,389; the excluded count lands only in `nExcluded`.

**So Stage 1 is two changes, not one**: wire `RetainFragmentsFor`, AND make the decoy gate ask
"were this entry's fragments dropped deliberately?" rather than "is this entry empty?". The bool
cannot answer that - the retained set has to reach the gate, or the load has to mark the entries
it emptied on purpose.

Second, cosmetic, same root: the `<3 fragments` diagnostic at `PerFileScoringTask.cs:1078` is
skipped under `omitFragments` for the identical reason ("every count would read 0 and the line
would misreport the whole library as sub-3-fragment"). Per-entry, it would report ~4.9 M
zero-fragment entries as a library-quality problem. Log noise, not a wrong answer, but it is the
same missed generalization and should move in the same change.

### 3. The predicate is necessary but NOT sufficient - the CALL SITE is half the gate

`LoadLibraryAndDecoys` has three callers, and only two may drop:

| site | path | may drop? |
|---|---|---|
| `PerFileScoringTask.cs:204` | `Run` - Stage 1-4 compute from spectra | **NO** |
| `:515` | `Rehydrate`, `--input-scores` worker mode | yes |
| `:637` | `RehydrateFromOwnOutputs` | yes |

`ctx.WillRehydrate<FirstPassFdrTask>()` cannot see the difference, and the combination is
reachable: FirstPassFDR's outputs are the per-file `.1st-pass.fdr_scores.bin` + reconciliation
files, so deleting a `.scores.parquet` leaves the 1st-pass sidecar beside it valid. FirstPassFDR
would rehydrate while `Run` re-scores that file from spectra - which scores against EVERY library
entry, not the retained ones. The drop has to be refused at the `Run` call site as a separate
condition, not inferred from the predicate.

### 4. `RetainFragmentsFor` is honoured on the CACHE-READ path ONLY

`LibraryCache.LoadCache` applies the per-entry decision (`LibraryCache.cs:330-331`). The
source-parse path in `LibraryLoader` applies only `OmitFragments`, in the tail block at
`LibraryLoader.cs:205`. With no `.libcache` present, `RetainFragmentsFor` is silently inert and
the run retains everything.

That fails SAFE - the release pass still runs and the answer is right - but it makes the win
contingent on a cache hit and leaves the two load paths behaviourally different. Worth closing in
the same change: the tail block already has the entries in hand and every fragment-count
dependency satisfied.

### What did NOT turn out to be a hazard

Dedup's fragment-count tie-break (`LibraryDeduplicator.cs:121`, `b.Fragments.Count`) and the
min-fragment / peak-less guard both run on the SOURCE-PARSE path only, BEFORE the cache save. A
cache read returns entries already deduplicated, so per-entry skipping there cannot perturb which
entry became a group's representative. `nFrags` is also read unconditionally before the
keep/skip branch (`LibraryCache.cs:299`), so the peak-less fail-fast still fires on a skipped
entry.

### Stage 2 has a clean home

`LibraryCache` carries `MAGIC = "OSPRLBR\0"` and a `VERSION` checked at `:228-229`, and an
unsupported version already returns null -> "rebuild from source". So the per-entry
fragment-block byte length + version bump needs no new invalidation mechanism, which is what
makes the "rebuild deliberately once" plan cheap.

### 5. The VALIDITY KEY is keyed on the release MECHANISM, so Stage 1 must not switch the release off

`LibraryFragmentRelease.ValidityKeySuffix(ctx)` is a term in THREE tasks' validity keys -
`FirstPassFdrTask.cs:273`, `PerFileRescoreTask.cs:267`, `SecondPassFdrTask.cs:241`. It is empty
when `RunsOnThisLeg(ctx)` is true and `;libfrag=0` when the leg COULD have released and did not
(`LibraryFragmentRelease.cs:82-87`).

The release itself is invoked from `FirstPassFdrTask.cs:2519` and `SecondPassFdrTask.cs:509` -
not from the rescore, which only carries the suffix.

So if Stage 1 makes the read-time drop replace the release and turns `RunsOnThisLeg` false, every
one of those three keys gains `;libfrag=0` and **every existing output directory is invalidated** -
a resume against one re-runs the pipeline it was supposed to adopt. That is the opposite of what
this branch exists to do.

The cheap correct answer: leave the release call in place. With the fragments already dropped at
read time it releases nothing, `RunsOnThisLeg` stays true, the suffix stays empty, and no
directory is invalidated. The suffix's stated purpose survives too - it records "this run's
library is not carrying non-retained fragments", and under the drop that is MORE true, not less.

This is the same "assert the PROPERTY, not the MECHANISM" problem already noted for mode 6, on a
higher-stakes surface: mode 6 going vacuous costs a blind test, but a suffix flip silently
invalidates or silently adopts. Both should move together, and the release's own count going to
zero is exactly what makes mode 6's non-zero-count assertion fail - so the two are one change.

## MODE 8 VERIFICATION: Stellar green, and TWO process traps that invalidated the first attempt

Session dir: `ai/.tmp/sessions/20260903-fragload/`.

### The change verified

`regression.ps1`: `Invoke-OspreyRun -AllowNonZeroExit` plus mode 8's if/else split, with the
`else` arm re-indented into the block (the previous session left it flush-left, so the committed
text was not the text anyone would read). `fix-crlf.ps1` STRIPS THE UTF-8 BOM from files it
converts - `regression.ps1` has one, and it came back BOM-less; restored by hand, and worth a
separate look since that script runs before commits across the repo.

### RESULT - Stellar, all legs

```
  Stellar mode1 (vs golden): PASS
  Stellar mode1c (2nd-pass protein q is pass-2): PASS
  Stellar mode2 (resume cache hits): PASS
  Stellar mode2 (resume==straight): PASS
  Stellar mode6 (library-fragment release engaged): PASS
  Stellar mode8 (partial rescore resume): PASS (1 of 3 run(s) re-scored)
```

`ai/.tmp/sessions/20260903-fragload/verify-stellar.log`. The restructured else arm executes and
the branch fixes the partial-resume defect on the non-mdiag path.

### TRAP 1: the Release tree is not a function of HEAD, and a timestamp does not say it is

The first attempt used `-NoBuild` on the reasoning that the Release binaries (15:54) postdated the
last commit (`ac0fedf165`, 15:12), so they had to be current. **They were the deliberately-REVERTED
`c955943146` build** from the previous session's "is this defect on master?" experiment -
`sessions/20260903-stages567/build-prechange.log`, same 15:54 stamp.

So the gate ran the pre-change product code and Stellar mode 8 returned the pre-change signature
exactly - 35 issues, `only 2 of 3 reconciled parquet(s)`, `no line containing 'Rescore resume:'`,
`242 RefSpectra key(s) only in golden`. A confident red for a branch that fixes it. The logs are
kept as `stale-binary-verify-*.log` rather than deleted, because they are the before half of the
comparison.

The general form, now added to `ai/docs/osprey-development-guide.md` as a third entry in its
"traps that cost real runs" list: any experiment that builds a DIFFERENT tree into the same path -
a revert, a baseline checkout, a sibling worktree - leaves a binary NEWER than HEAD without being
HEAD. Drop `-NoBuild` unless you built Release yourself this session and nothing has run since;
the rebuild is 9.4 s.

### TRAP 2: `regression.ps1` cannot be CHAINED in one pwsh process, only serialized across processes

Both attempts' Astral leg died in seconds at `Regression\BlibGolden.ps1:213`
`Copy-Item $nativeSrc $nativeDst -Force`, on
`Release\net8.0\SQLite.Interop.dll ... being used by another process`.

Nothing was running concurrently. The FIRST dataset's blib comparisons load System.Data.SQLite
into the hosting pwsh process, and a native DLL stays loaded for that process's lifetime - so the
holder is the launcher script itself. A wait-for-the-handle-to-drop loop (which the second attempt
added) waits on itself and times out.

`sessions/20260903-stages567/gate-partialresume.ps1` chose chaining deliberately, with the comment
"Chained, not launched separately: regression.ps1 cannot run concurrently with itself (shared
Release dir + SQLite lock)". The premise is right and the conclusion is wrong: serial is necessary
but must be serial ACROSS PROCESSES. Its `gate-partialresume-astral.log` is 39 bytes - the same
death, unnoticed at the time.

**How to run two datasets:** one `pwsh -NoProfile -File .../regression.ps1 -Dataset <one>` per
dataset, sequentially - or `-Dataset All`, which is a single process that never re-copies. The
tell for this failure is a dataset log only a few dozen bytes long.

### Cost of the prune, stated rather than discovered later

`-KeepRunDirs 2` on the Astral leg pruned `regression-20260903_155437`, the kept scratch behind the
"pre-existing on master" proof. Its logs were already copied into
`sessions/20260903-stages567/stellar-prechange.log` and the result is recorded above, so nothing
unrecoverable went with it - but it is the same startup-prune-deletes-failed-evidence behaviour the
previous session flagged, firing again on a dir that was being kept on purpose.

### RESULT - Astral, all legs

```
  Astral mode1 (vs golden): PASS
  Astral mode1c (2nd-pass protein q is pass-2): PASS
  Astral mode1b (diagnostics vs golden): PASS
  Astral mode1b (FDR sanity bounds): PASS
  Astral mode2 (resume cache hits): PASS
  Astral mode2 (resume==straight): PASS
  Astral mode6 (library-fragment release engaged): PASS
  Astral mode7 (diagnostics regeneration: report only, vs golden): PASS
  Astral mode8 (partial rescore resume): FAIL (1 issues)
```

`ai/.tmp/sessions/20260903-fragload/verify-astral.log`. Exactly ONE issue - the canned
capability-gap line. The log-marker guard produced no issue of its own, so the error naming how
many runs cannot be finished and why WAS present. And the run reached its summary instead of
throwing, which is the whole point of `-AllowNonZeroExit`.

Both arms of the restructure are therefore executed and correct: the else arm on Stellar, the
mdiag arm on Astral. Committed as `447fb59bd8`.

**The Astral gate is now red until the mdiag work lands**, by design, and `-Dataset All` will be
red with it. That is the developer's call from the previous session - a green gate over a real gap
encodes the limitation - and the leg turns green when the bundle path gains a plan source, with no
test edit. Anyone reading a red Astral before then should check that mode 8 is the ONLY failing
leg and that its issue count is 1.

## FRAGMENT DROP: shipped as a UNIFORM POST-PAIRING drop, and the 1m54s was never the freeing

Supersedes the "Fragment-drop-during-read" plan above. The IO half that plan landed
(`LibraryCache`'s per-entry `retainFragmentsFor`, `LibraryLoadOptions.RetainFragmentsFor`) is
still inert and is NOT used by what shipped - see "why the read-time skip cannot work" below.

### The design is the developer's, and it is better than the one this TODO proposed

The plan here was for the PRODUCER to infer that the on-disk retained set was this run's, by
asking `CanRehydrate` about the FirstPassFdrTask instance. The developer's instead has the
CONSUMER declare it:

> *"the context having an optional set of entries for which spectra are needed. When that set is
> not present on the context, then the library loads as normal, but PerFileRescoring would
> provide the set on the context before asking for the rehydrated library."*

That removes the inference. The rescore ALREADY reads `retained_base_ids.bin` to decide what to
compact, so declaring the same set trusts nothing new: if that summary were the wrong run's, the
compaction is already wrong and the fragments are the lesser problem. The compute path is safe
for free - `Run` never declares, so it always gets a whole library.

Landed:

* `PipelineContext.DeclareFragmentsNeededFor` / `FragmentsNeededFor` /
  `FragmentNeedStillDeclarable`.
* `ScoringTaskShared.TryDeclareFragmentNeed(ctx)` - ONE function for both callers, per the
  developer: *"Both should use the same function to obtain a library in the presence of an
  in-stratum subset that has been written to disk."* Called first thing in
  `PerFileRescoreTask.Run`/`.Rehydrate` and `SecondPassFdrTask.Run`.
* The drop itself in `PerFileScoringTask.LoadLibraryAndDecoys`, AFTER decoy pairing/generation,
  reusing `LibraryFragmentRelease.ReleaseFragments`.
* `LibraryFragmentRelease.AlreadyLeanAtLoad(ctx)` + `LEAN_AT_LOAD_MESSAGE`; both post-Stage-5
  release sites skip when it holds.

### WHY THE READ-TIME SKIP CANNOT WORK, in either decoy mode

**libdecoy.** `DecoyPairingManifest` pairs by bucketing and matching SORTED SEQUENCE LISTS
(`:395-419`) and then renumbers the decoy - `library[decoyIdx].Id = targetId | DECOY_ID_BIT`.
Targets are never renumbered. So a supplied decoy's post-pairing base_id is knowable only from
the whole identity table, never from one streamed entry.

Worse than "some decoys wrong": the `.libcache` is written inside `LibraryLoader.Load`, BEFORE
`MarkSuppliedDecoys` and pairing run in `LoadLibraryAndDecoys`, so every cached entry carries a
plain post-dedup id with the decoy bit clear. A retained base_id is always a TARGET's id, and ids
are unique - therefore **no supplied decoy's cache id can ever be in the retained set, and a
read-time filter skips ALL of them**. On the 446-run CHS resume that meant materialising ~625 K
entries where the rescore needed ~1.25 M.

**gendecoy.** `BuildDecoyFromSequence` -> `RecalculateFragmentsStatic(target, ...)` builds each
decoy's peaks FROM ITS TARGET'S peaks, so every target's spectrum is needed whatever the retained
set says. (The developer: *"I had forgotten about the decoy generator filtering on spectral
similarity library-wide."*)

So the library is always READ whole and dropped ONCE, after pairing. That also deleted the
`DecoyGenerator` exclusion-gate change this TODO's earlier entry called for: with the drop after
generation, every entry still has its peaks when the gate runs.

### THE TRIPWIRE IS WHY THIS WAS A CRASH AND NOT A WRONG ANSWER

The developer chose to install the RELEASED tripwire at drop time rather than an empty array.
That decision is what surfaced the libdecoy defect: the run died at
`ScoringPipeline.RunCoelutionScoring` on file 146 of the 446-run resume. With `Array.Empty` the
scorers' `Fragments == null || Fragments.Count == 0` guard would have absorbed it as "no
spectrum" and written degenerate zeros into the .blib - a silent wrong answer in the artifact
used to judge correctness.

Also note which gate would have caught it: `StellarLibDecoy`. The generated-decoy `Stellar` leg
was fully green THROUGH the defect, because ids are final at cache time there. That is the
`-Dataset All` step this branch already owed.

### MEASURED AT 446 FILES - and the premise this TODO recorded was wrong

`PerFileRescoring:starting` -> the first missing file entering per-file mode:

| | library load | release block | total |
|---|---|---|---|
| baseline | ~39 s | ~1 m 54 s | **2 m 53 s** |
| read-time skip only (incorrect, see above) | 11 s | 1 m 53 s | **2 m 36 s** |
| + release skipped (incorrect skip set) | 10 s | skipped | **1 m 36 s** |
| uniform post-pairing drop (shipped) | ~39 s | skipped | **~2 m 08 s est.** |

**The ~1m54s was never the cost of freeing fragment arrays.** With the arrays never built it
still cost 1m53s. Differencing the second and third rows isolates the release block at **45 s**;
the remaining **68 s** is upstream of it and neither change touches it.

The release also reported `Released library fragments for 4924513 of 6175389 entries` while
freeing zero bytes - `LibraryEntry` distinguishes the released SENTINEL from everything else and
`Array.Empty` is deliberately "a readable empty spectrum rather than a released one". That is the
fabricated-saving shape mode 6 exists to catch, emitted by the feature itself and hidden inside
mode 6's green. `ReleaseFragments` now counts only entries that actually held a spectrum.

### THE REMAINING 68 s, diagnosed

`FirstPassFdrTask.cs:930` `RescoreHydration.ReadGapFillAndCalibrations(perFileParquetPaths.Values,
...)` - a loop over ALL 446 runs' `reconciliation.json` envelopes (10.7 GB of JSON at this
cohort), sitting exactly between the two log lines that bracket the gap.

**The per-run rescore path then does not use the result.** `PerFileRescoreTask.cs:1686` takes
`run.GapFill` and `:1333` takes `run?.RefinedCalibration` - each run's OWN envelope - and only
falls back to the all-runs dictionaries (`:1697`, `:1333`) on the other path. The all-runs form is
needed solely by Stage 7's pool rebuild (`Rehydrate -> OverlayReconciledIntoFiles`), which runs
far later, and never at all on a `--task PerFileRescoring` worker.

The comment at `:917-927` already prescribes "it should become LAZY". **That is necessary but not
sufficient**: `PerFileRescoreTask.Run` dereferences all four byproducts at `:513-516` before
`ExecuteRescore`, so a lazy byproduct would build there instead - the 68 s moves ten lines and
stays ahead of the first file. The fix has to pass the lazy HOLDERS into `RescorePassInputs` so
`.Value` is touched only on the fallback branches the per-run path never takes.

This is now the largest term in the rescore startup - bigger than everything the fragment work
removed - and it is the next thing to do.

### Mode 6 asserts the property, in its new form

A lean leg emits a release line at LOAD (scope `needed by this process`) and the skip message
downstream. Mode 6 asserts all three: the declaration, a load-time drop that freed a non-zero
count, and that NO post-Stage-5 release ran afterwards - the last being the one that matters,
since paying for both walks is exactly what this change removes.
