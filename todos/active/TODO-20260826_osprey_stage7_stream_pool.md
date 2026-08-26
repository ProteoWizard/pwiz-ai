# Osprey Stage 7: make the survivor pool non-resident through pass-2 scoring and protein FDR

## Branch Information
- **Branch**: `Skyline/work/20260826_osprey_stage7_stream_pool`
- **Base**: `master` (2a0b0069f6, i.e. after #4615)
- **Worktree**: `C:\proj\pwiz-work1` — `C:\proj\pwiz` is held by the open PR #4616
  (cache-only inputs), which a CHS plate run is field-validating
- **Created**: 2026-08-26
- **Status**: In Progress
- **GitHub Issue**: [#4486](https://github.com/ProteoWizard/pwiz/issues/4486)
- **Module**: `osprey`
- **PR**: (pending)

## Objective

Stage 7 holds the whole-run survivor pool (`RescoredEntries` =
`List<KeyValuePair<string, List<FdrEntry>>>`) resident from pool construction through
pass-2 scoring, protein FDR and the blib write. Measured post-GC on **257 CHS files**
(2026-08-25, `OSPREY_LOG_MEMORY=1`, `--task SecondPassFDR`):

| post-GC probe | live managed |
|---|---|
| `library-resident` | 4.19 GB (6,175,389 entries) |
| `stage7-inherited` / `stage7-pool` | **41.97 GB** |
| `stage7-fragments-released` → `stage7-blib-written` | 39.62 GB, **flat** |

**4.19 GB library + ~147 MB/file live** → ~78 GB at 500 files, ~152 GB at 1,000. Over any
64 GB box, and it is the last structural wall between here and the 500-file target.

## Read the issue's correction chain before planning — it has reversed twice

This issue is nine comments long and has been rescoped four times. Two reversals matter:

1. **"Stage 7 costs nothing per file" (2026-08-08) was wrong and was retracted the next
   morning.** It came from post-GC probes at substep BOUNDARIES; the pass-2 competition
   allocated and released its state *between* two boundaries, so both probes read the same
   number and the phase looked free. ~2.5 GB at 16 files (hidden), ~13 GB at 82 (dominant).
2. **The concrete lever named in that retraction is already fixed.** The three
   `Dictionary<(string, uint), double>` + `HashSet<(string,uint)>` returned by
   `StreamingFdr.ComputeFullPopulationPrecursorFdrStreaming` — 86.6 M observations, ~13 GB
   at 82 files — are gone: **#4554 ("Bounded and instrumented the Stage 7 join")** replaced
   them with `StreamedCompetitionState`, O(distinct base_id / entry_id), and moved the
   per-survivor loop into the caller's per-file emit pass. Verified in the tree today.
   `Pass2FdrSidecar` is therefore **not** the target; the pool itself is.

**Methodological consequence, which applies to my own measurements on this branch**: the
2026-08-25 table showing a flat 39.62 GB live floor is boundary-sampled too. It is evidence
that nothing *accumulates* after pool construction — not evidence that no phase allocates a
large transient inside itself. Anything I measure at a boundary inherits that blind spot.

## What is actually left

The pool is built before pass-2 scoring and released after the blib write, and **the peak is
set at construction**. So releasing it earlier buys nothing; the fix has to make it
non-resident *through* the two phases that assume a global view:

1. **`RunProteinFdr` → `ProteinFdrEngine.RunSecondPass`** — parsimony + picked-protein TDC
   over a global stratum. Genuinely whole-run, but the open question is whether it needs
   every observation or an O(distinct peptide/protein) aggregate.
2. **`Pass2FdrSidecar.ComputeAndPersist`** — its cross-file state is already bounded by
   #4554, but it still receives `perFileEntries` and writes per-file sidecars. Question is
   what it reads off the pool beyond what `StreamedCompetitionState` already answers.
3. **`WriteBlibOutput`** — already aggregate-shaped (`BuildBestExpPrecursorQ`,
   `BuildSharedBoundaries`, `BuildCrossFileObservations`) and it emits per file, so it is
   the natural second streamed pass. The issue notes it "could run on aggregates alone".

Target shape (and the standing constraint on FDR memory): **per-file compute → O(entries)
aggregate → per-file emit, with emission a SECOND streamed pass.** No `O(files × entries)`
structure in either direction.

**Documented trap — do not start here.** `entriesByPrecursor` holds
`List<KeyValuePair<string, FdrEntry>>`, references that PIN the pool, while its consumers
read only `observations.Count`, `obs.Key`, `EffectiveRunQvalue` and `ApexRt/StartRt/EndRt`
(~40 B). Converting it to a value struct unpins the pool but, while the pool is held anyway,
makes memory WORSE (16 → 40 B per observation). Step two, not step one.

## What each consumer actually needs (read 2026-08-26)

**Protein FDR is the EASY half — which inverts the issue's assumption.**
`ProteinFdrEngine.RunSecondPass` already decomposes into the target shape:

| step | over | keyspace |
|---|---|---|
| `ProteinFdr.CollectBestPeptideScores` | pool | O(distinct peptides) |
| `detectedPeptides` (experiment-q gate at `config.FdrLevel`) | pool | O(distinct peptides) |
| `BuildProteinParsimony(fullLibrary, sharedPeptides, detectedPeptides)` | **no pool** | — |
| `ComputeProteinFdr(parsimony, bestScores, RunFdr)` | **no pool** | — |
| `ProteinFdr.PropagateProteinQvalues` | pool | per-entry WRITE-BACK |

Two streamed folds, a pool-free middle, and a write-back. Nothing here needs a global view
of observations — only of peptides. The issue's "protein FDR (parsimony + picked-protein
TDC) ... are all whole-run consumers" is true of the PEPTIDE aggregate, not of the pool.

**The blib is the hard half, and the difficulty is emission ORDER, not data volume.**
`WriteRetentionTimes` reads only `obs.Key` (file), `EffectiveRunQvalue(Both)`,
`ModifiedSequence`, and `ApexRt/StartRt/EndRt` — ~36 B as a value record against a pinned
`FdrEntry`. But it writes **one RetentionTimes row per observation**, and it writes them
PRECURSOR-major: a RefSpectra row, then that precursor's rows across all files. Streaming
per file means inverting that to FILE-major, which needs the refIds assigned first — i.e.
exactly the "emission is a SECOND streamed pass" rule.

**`sharedBounds` is a second accumulator, keyed `(modseq, fileName)` -> `double[5]`** — one
entry per passing (peptide, file) observed, so O(observations), not O(distinct). At 257 files
that is tens of millions of entries and several GB, and it is built in the aggregate phase and
read in the emit phase, so it cannot simply be dropped between them. **It can be made sparse**:
it only matters where a peptide has more than one charge in that run AND the winning charge's
boundaries differ from the entry's own. Every other key is the entry's own boundaries, i.e.
recoverable in the emit pass. Same trick #4554 used for `survivorPep` (store non-defaults,
default the rest).

### Proposed shape — to be reviewed before writing

* **Pass 1, streamed per file** — fold into: `bestScores`, `detectedPeptides`,
  `passingPeptides` / `passingPrecursors`, `bestByPrecursor` (a COPY, not a reference),
  `bestExpPrecursorQ`, per-precursor observation COUNT, sparse `sharedBounds`, and the
  already-bounded `StreamedCompetitionState`. Drop each file's entries as it goes.
* **Middle, pool-free** — parsimony + picked-protein FDR; assign blib refIds from
  `bestByPrecursor`.
* **Pass 2, streamed per file** — reload one file, apply `ExperimentProteinQvalue`, write its
  `.2nd-pass.fdr_scores.bin`, write its RetentionTimes rows against the refIds from the middle.

**The front end is already per-file, which makes pass 1 a restructuring rather than a
rewrite.** `PerFileRescoreTask.MaterializeAllSurvivors` is a clean loop —
`loader.Load(fileKey)` returns ONE file's survivor stubs and the only thing making it
accumulate is `kv.Value.AddRange(stubs)` into the shared buffer. Hand each loaded list to a
fold and drop it and the ramp is gone; the loader needs no change. `ResetRescoredTargets`
is likewise per-file and positional within a file, so it applies inside the same loop.

**The cost — an earlier version of this file said "a second pass costs another 19 min,
+21% on Stage 7". That was wrong**: it assumed pass 2 re-reads what pass 1 read. It does not.

What the 19 min 10 s (22:21:57 -> 22:41:07, 257 files) actually buys, per
`FirstPassSurvivorLoader.Load`:

1. `LoadFdrStubsFromParquet` on the **`.scores.parquet`** — the FULL pre-compaction stub set,
   ~2.99 M stubs/file, 768.5 M across the cohort, from **1,060 MB/file / 266 GB total**
2. overlay the 1st-pass sidecar (113.7 MB/file, 29 GB) onto that full set — superset contract
3. `RemoveAll` down to survivors: ~533 K/file, 137 M total — a **5.6x overshoot**
4. `TrimExcess` + `Sort`

Pass 2 needs none of it. Per surviving observation it needs `file`, `modseq`, `charge`,
`runQ`, `apex/start/end` — ~36 B — plus the protein-q write into the sidecar. Spilled by
pass 1 as it goes, that is **~4.9 GB total (~19 MB/file)** against 266 GB of parquet:
**~55x less I/O than pass 1**. No measured number for it yet, and none should be quoted until
there is one.

Artifact sizes measured in the 257-file run dir, for whoever costs this next:

| artifact | count | total | per file |
|---|---|---|---|
| `scores.parquet` (what the loader reads) | 257 | 266.04 GB | 1,060 MB |
| `scores-reconciled.parquet` | 257 | 266.23 GB | 1,061 MB |
| `fdr_scores.bin` (1st + 2nd pass) | 514 | 57.09 GB | 113.7 MB |
| `reconciliation.json` | 257 | 4.68 GB | 18.6 MB |

**Separate finding, not the memory problem but most of the front end's TIME**: the load
overshoots 5.6x per file — decoding 2.99 M stubs to keep 533 K. Bounded rather than
accumulating, so it does not affect the peak, but pushing the survivor filter into the
parquet read (a base_id predicate) would make pass 1 cheaper independent of this work.

Against it, #4615's review found the blib phase already makes SIX full passes over the
137 M-row pool in memory (`ComputePassingPeptides`, `ComputePassingPrecursors`,
`CollectPassingEntries`, `BuildBestExpPrecursorQ`, `BuildSharedBoundaries`,
`BuildCrossFileObservations`), so the in-memory work being replaced is not one pass either.

## Tasks

- [x] **Split inherited-vs-built on the straight-through path** — DONE 2026-08-26, no run
      needed: the full 5-7 run's log already carries the probes. Stage 7 **builds** the pool
      itself in-process (see the progress log). The work is inside Stage 7, not upstream.
- [x] Establish, per consumer, exactly which `FdrEntry` fields are read and whether that is
      expressible as an O(distinct) aggregate — DONE, see "What each consumer actually needs"
- [ ] Record the two-pass design here BEFORE writing it
- [ ] Implement, gated on byte-identical output
- [ ] Post-GC memory A/B at ≥100 files, plus an in-phase sample so a transient cannot hide
      between two boundary probes (the 2026-08-08 error)

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: Osprey.Test / `regression.ps1` modes 1+3
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

Stage 7 feeds the blib, so `regression.ps1 -Dataset All` byte-identical is the correctness
oracle, and **mode 3 (HPC chain == straight) is the direct one** because the chain runs
`--task SecondPassFDR`. Byte-parity alone cannot catch a pool that is still resident, so the
memory property additionally wants a `ResidentPoolGuardTest` entry — the ratchet that
retired `mdiag-full-resume` (#4505), `resume-survivor-handoff` (#4536) and `hpc-merge`
(#4554-era) from `ResidentPaths.KNOWN_UNFIXED`.

## The bar: Stage 7 out of contention, not merely smaller (Brendan, 2026-08-26)

The goal is **to take Stage 7 entirely out of contention for the whole-run peak**, not to
shave the pool. At 257 CHS files the other stages measured (working set, from the CHS
large-scale TODO): FirstPassFDR **53.7 GB**, PerFileRescoring 16.5 GB flat, SecondPassFDR
**69.0 GB** — the peak, and past the 63.7 GB box, so it paged.

Live at Stage 7 today is 4.19 GB library + 0.147 GB/file = **41.97 GB at 257**. Out of
contention means landing below FirstPassFDR with margin, i.e. **library + aggregates only**.
The aggregates are small: 501,247 distinct non-decoy precursor keys, ~5,000 protein groups,
~500 K peptides at 257 files — single-digit GB. So the target shape is ~4.2 GB library plus
a few GB, and the success criterion is that **FirstPassFDR becomes the run's high point.**

## Test target and baselines (named by Brendan, 2026-08-26)

| purpose | run directory under `D:\test\osprey-runs\chs-seer\runs\` |
|---|---|
| **`-LinkFrom` source** (per-file artifacts, 257 files, 596.5 GB) | `chs-257files-libdecoy-r1.0-protein-compact-p0059_0060_0061` |
| **working-set baseline** (`logmem=off`, no stage7 probes) | `...-p0059_0060_0061-s7base` |
| **post-GC live baseline** — the A/B number to beat | `chs-257files-libdecoy-r1.0-protein-compact-s7mem257` |

`s7mem257` is the run the 2026-08-25 issue comment quotes: `--task SecondPassFDR`,
`-LinkFrom` the p0059_0060_0061 dir, exe `_bin\26.1.1.233-stage7fix-20260825`, `logmem=on`,
81 min, exit 0. Its probe series is the baseline column:

```
[MEM library-resident]            4.19 GB (6175389 entries)
[MEM stage7-inherited]           41.97 GB (post-GC, entering Stage 7, files=257)
[MEM stage7-pool]                41.97 GB (post-GC, survivor pool built, files=257)
[MEM stage7-fragments-released]  39.62 GB (released=5173196)
[MEM stage7-pass2-scored]        39.62 GB
[MEM stage7-protein-fdr]         39.62 GB
[MEM stage7-blib-written]        39.62 GB
```

Note `-s7base` carries `logmem=off` and **zero** stage7 probes, so it is the working-set /
`--memstamp` baseline, not the live one. Do not quote it as a live figure.

## Measurement harness

Stage 7 alone against a completed run, ~70 min at 257 files / ~25 min at 100, without
re-running the ~15 h of per-file work:

```powershell
pwsh -File ai\scripts\Osprey\CHS\Run-Chs.ps1 -IncludePattern 'us(0059|0060|0061)' `
  -Task SecondPassFDR -LinkFrom '<completed 257-file run dir>' `
  -Tag '-s7probe' -LogMemory -DecoyMode libdecoy -Ratio 1.0 -Pass2Mode protein-compact `
  -Threads 30 -FdrBenchPass 2 -LibraryDir '<lib>' -Exe '<snapshot>\Osprey.exe'
```

Traps carried from the issue: a repeat run against a directory that still holds
`*.2nd-pass.fdr_scores.bin` self-gates to a no-op, exits 0 and measures nothing; and never
point `Measure-Stage6Rescore.ps1 -PhaseDir` at a real run directory — it begins by deleting
`*.2nd-pass.fdr_scores.bin` and `*.scores-reconciled.parquet` inside it.

## Sequencing note

An 8 h CHS plate-0062 search (PR #4616 field validation) holds the machine until roughly
19:30 on 2026-08-26, and a second ~9.5 h run follows it. Measurement contends with those for
disk and threads; reading and design do not.

## Related

- [#4486](https://github.com/ProteoWizard/pwiz/issues/4486) — nine comments, read the
  2026-08-09 correction and the 2026-08-25 measurement before planning
- #4554 — bounded the pass-2 competition's cross-file state (the previously-named lever)
- #4597 — the deferred pool build Stage 7 now pays for
- #4615 / `ai/todos/completed/TODO-20260825_osprey_stage7_memory.md` — the transient noise
  around this peak (LOH churn in `RestorePass1Scalars`, heartbeat, pre-sized lists)
- #4526 / #4530 / #4536 / #4545 — the O(files) work upstream; this is the O(survivors) residue
- `ai/docs/memory-band-guide.md` — post-GC probes vs `--memstamp`

## Why Stage 7 reads the Stage 4 parquet at all - it is residue (2026-08-26)

Brendan's question: Stage 6 originally OVERWROTE the Stage 4 parquet, and he asked for the
two to exist separately. It was never intended that Stage 4's output become a Stage 7
requirement. Answered from the code rather than the history:

**Columns: nothing is missing from the Stage 6 parquet.** `StreamReconciledScoresParquet`
streams the original group-by-group, replaces re-scored rows and merges gap-fill into
canonical position, so the reconciled file holds EVERY original row plus the gap-fill rows in
the same schema. Every column the front end loads is there - with better values, the
reconciled boundaries, which is exactly what the second read currently overlays back on.

**`ParquetIndex` is the one real difference, and Stage 7 already treats it as unusable.**
From `Pass2FdrSidecar.LoadReconciledFeaturesByIdentity`'s own doc: a stub's `ParquetIndex`
"(assigned against the ORIGINAL Stage 4 parquet ...) no longer addresses that stub's own row
in the reconciled parquet. Identity is invariant across the reindex, so
`MapFeaturesByIdentity` keys on it." So Stage 7's feature reload is already by
(entry_id, charge, scan_number); within Stage 7 `ParquetIndex` survives only as the terminal
tie-break of `CANONICAL_ORDER`, which the same doc notes essentially never fires because
`DeduplicatePairs` makes entry_id unique per file.

**The one genuine dependence is per-file**: a file with no reconciliation work has NO
`.scores-reconciled.parquet` ("no-work files (none on disk) keep their 1st-pass boundaries"),
so Stage 4's is its only copy. That is a fallback for a minority of files, not a reason to
read 266 GB of Stage 4 data for all of them. On the 257-file CHS run all 257 files have a
reconciled parquet, so the fallback would never fire there.

**Conclusion**: the read was never re-pointed when the two files were separated. The
resulting index mismatch was worked around by keying on identity, and a second read
(`OverlayReconciledIntoFiles`) was added to restore what the in-place rewrite gave for free.

### The reconciled parquet is NOT a subset - measured, against expectation

Brendan expected the Stage 6 parquet to hold only the Stage 5 survivors (per-run q < 1%,
plus every peptide of a protein with >= 2 peptides detected) and to show the 5.6x reduction.
**It does not.** Three independent confirmations:

* Writer's own log: `3533417 rows (59660 replaced + 7441 appended; original 3525976 rows)` -
  written = every original row plus gap-fill, nothing dropped.
* Disk: 266.23 GB of `.scores-reconciled.parquet` against 266.04 GB of `.scores.parquet`
  over the same 257 files.
* Code: `StreamReconciledScoresParquet(originalPath, ...)` streams the ORIGINAL group by
  group; there is no filter in that path.

The 5.6x is real and lives in exactly two places: the in-memory compacted buffer, and the
**2nd-pass sidecar** (622,414 records against the 1st-pass sidecar's 3,525,976 for the same
file). The parquet never had it applied. That also resolves where the ID-not-position design
landed - `FdrScoresSidecar` records carry `entry_id` at [0..4] and `TryRead` matches on it,
with a comment recording the correction from the older strict positional check.

**Consequence**: because the reconciled parquet is a row-superset with an identical schema,
nothing forced a choice between the two files, and the second read was added to recover the
reconciled values rather than the first read being re-pointed.

## THE PLAN: rearchitect Stage 7 onto a subsetted Stage 6 parquet (Brendan, 2026-08-26)

Sanctioned explicitly: "Now is the time to rearchitect for optimal Stage 7 performance and
leave prior implementation baggage behind."

**The history that explains the shape.** Stage 6 originally OVERWROTE the Stage 4 parquet.
Brendan rejected that - space is a workflow-engine or flag decision, not a reason to destroy
an input - and asked for two files. What was not noticed at the time is that the overwrite
had never been purely additive: it changed values, and it preserved the ORIGINAL ROW SHAPE.
Splitting the file carried that row shape over to the sibling, where it had no reason to
exist. So the reconciled parquet became "a complete artifact covering pass 1 and pass 2"
instead of what Stage 7 needs, and Stage 7 got slower for it.

**Target state**

* `.scores-reconciled.parquet` holds the Stage 5 SURVIVOR set for its file - per-run
  q < 1%, plus every peptide of a protein with >= 2 peptides detected - carrying Stage 6's
  re-scored values, with gap-fill rows merged in. ~533 K rows/file, not 3.53 M.
* It is written for EVERY file, including no-work files.
* Stage 7 reads ONLY it, plus the 1st-pass sidecar for scores / q-values.
* `.scores.parquet` is never read after Stage 5.

**Increments, each gated byte-identical on Stellar**

1. **DONE `a3e20dfbd1`** - select survivors during the parquet read, not after.
2. **DONE, gate pending** - always write the reconciled parquet (no-work files included).
3. **Subset the write.** `ParquetScoreCache.StreamReconciledScoresParquet` already walks the
   original row group by row group and decides per row; give it the survivor base_id set and
   emit only those rows (plus gap-fill). File drops to ~15-19% of its size: 266 GB -> ~45 GB
   at 257 files.
4. **Mark gap-fill rows explicitly** rather than inferring them from absence in the 1st-pass
   sidecar. This is Brendan's point (1) in its useful form: the consumer that must exclude
   them is `MultiChargeConsensus.SelectRescoreTargets`, which is computed on demand from the
   list, and a gap-fill row carrying default q=1 can otherwise join the per-peptide charge
   competition and change which charge wins.
5. **Point the Stage 7 rebuild at the reconciled parquet** and delete the second read
   (`OverlayReconciledIntoFiles`) from the pool build.

**A fall-out worth naming**: subsetting the artifact also removes the `--task SecondPassFDR`
pre-compaction pool - the 311 MB/file structure #4615 measured and deferred as "a
restructuring job, not a buffer fix". That path reads the reconciled parquets and compacts
768.5 M entries down to 137.0 M; against a subsetted artifact there is nothing to compact.

**Compatibility**: keep the survivor filter on the LOAD path even after the write is
subsetted, so an old full-shaped reconciled parquet still yields the same list. That keeps
the existing 257-file CHS run dir usable as the test rig instead of forcing a 15 h re-score
before anything can be measured.

### Superseded next-increment note

Load survivors from `.scores-reconciled.parquet` when present, Stage 4's only as the per-file
fallback. That deletes the entire second read - ~266 GB at 257 files - and
`OverlayReconciledIntoFiles` with it. The work is `ResetRescoredTargets`, which addresses the
survivor list POSITIONALLY in pre-gap-fill order; it has to key on EntryId instead, because
the reconciled parquet has the gap-fill rows already interleaved.

## Progress Log

### 2026-08-26 - Session start

### 2026-08-26 - Increments 2 and 3 written

**Increment 2 - always write the reconciled parquet.** `TryAssembleRescoreTargets` bails on
`combinedTargets.Count == 0 && gapFillTargets.Count == 0`, and that bail was the ONLY reason a
file could lack the artifact. It now writes one anyway (`WriteUnchangedReconciled`), which is
faithful by construction: `BuildOverlay` selects gap-fill by `ParquetIndex == uint.MaxValue`
and re-scored rows by non-null `Features`, and a no-work file has neither. Also updates the
`Outputs()` comment, which documented the gap as deliberate, and re-enables the task-level
`IsTaskAlreadyDone` short-circuit that a single no-work file used to block.

**Increment 3 - subset the write.** `StreamReconciledScoresParquet` takes the survivor id set
and skips original rows outside it. The set is built in `ReconciledParquetWriter.Write` from
the in-memory buffer's own entry ids, so the artifact cannot disagree with what the run
computed. Gap-fill rows are always emitted. Two details worth keeping:

* the gap-fill interleave stays correct across drops - skipping a row only defers the
  `KeyLess` test to the next emitted row, whose key is >= the skipped one's;
* progress now reports rows CONSUMED, not written, or the bar would stall at ~18% of its
  total for the whole write.

Checked, not assumed, before relying on it: `OverlayReconciledIntoBuffer` already matches by
`EntryId` and already skips "non-passing reconciled rows (compacted out of the buffer)", so a
subsetted artifact is strictly easier for it. `Pass2FdrSidecar` keys features by identity for
the same reason. Neither needed changing.

Gates so far: build + 593/593 tests + zero inspection warnings (593 includes the new
`TestReconciledTransferKeepsOnlySurvivors`, which asserts survivors-plus-gap-fill in canonical
order and that the reported original-row count still describes the INPUT). Stellar regression
for increments 2 and 3 still to run - increment 2's is in flight.

### 2026-08-26 - Increment 1 committed: survivors selected during the read

`a3e20dfbd1` in `C:\proj\pwiz-work1`. The front end built every file's full stub list and
then dropped 81% of it; the gate now runs per row as the parquet decodes.

Two invariants had to hold, both checked rather than assumed:

* **`ParquetIndex` stays the FILE row ordinal.** It was `stubs.Count`, which only
  coincidentally equalled the row index. It indexes that file's feature rows
  (`PercolatorScorer.ResolveFeatureRow` does `rows[idx]`) and is `CANONICAL_ORDER`'s terminal
  tie-break, so a dense renumber would mis-resolve features AND reorder the sort. Now an
  explicit counter that advances whether or not the row is kept.
* **The sidecar overlay had to be told about the filter.** `FdrScoresSidecar.TryRead` rejects
  the whole read when a record's entry_id is missing - the superset contract. Measured: one
  CHS file's 1st-pass sidecar holds **3,525,976 records** against ~533 K survivors, so
  filtering first would have hard-failed. It now takes the same predicate inverted, so an
  absence the caller asked for is skipped and any other missing entry_id still fails.

Gates: `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection` clean (592/592, zero
warnings, after qualifying ten `<see cref>` references the new overloads made ambiguous), and
**`regression.ps1 -Dataset Stellar` PASSED all 10 modes** including `mode1 (vs golden)` and
`mode3 (HPC chain==straight)` - so the change is byte-identical in output.

Not yet done: this does NOT remove the resident pool. The gate still prints the #4486 token
notice ("~4.4 GB library + 0.197 GB/file live post-GC"), as expected.

Ran concurrently with the CHS plate-0062 search, so that run's wall time is not cleanly
comparable with plates 0059-0061. Its purpose is the cache-only proof and the disk reclaim,
not timing.

### 2026-08-26 - The memory landscape, Stages 5-7 at 257 files

`perfviz.py --files 257` over the full run and the Stage-7-alone runs.

**Full 5-7 run** (`...-p0059_0060_0061`, 10:14:28, managed peak 65.2 GB / private 69.0 GB,
floor drift **+138 MB/file RISING**):

| phase | managed p10 / p50 / peak | private peak | wall |
|---|---|---|---|
| FirstPassFDR | 7.0 / 13.2 / 49.5 GB | 53.7 GB | 160:34 |
| PerFileRescoring | 4.9 / 7.3 / 24.4 GB | 44.9 GB | 362:27 |
| **SecondPassFDR** | **24.3 / 43.2 / 65.2 GB** | **69.0 GB** | 91:23 |

**Stage 7 is the only stage with a high FLOOR.** `p10` approximates what the GC cannot
reclaim: 7.0 and 4.9 GB for the two per-file stages against **24.3 GB** for Stage 7, whose
median (43.2 GB) sits above FirstPassFDR's peak. The other two stages spike and release;
this one holds. That is the difference between a transient and a resident pool, visible
without any probe.

**The in-process split the issue called "the obvious next measurement" is already in that
log** — no run required:

| post-GC probe | `--task` (`s7mem257`) | **in-process (full run)** |
|---|---|---|
| `library-resident` | 4.19 GB | 4.19 GB |
| `stage7-inherited` | 41.97 GB | **4.26 GB** |
| `stage7-pool` | 41.97 GB | **38.75 GB** |
| `stage7-fragments-released` | 39.62 GB (released 5,173,196) | 38.76 GB (**released 0**) |
| `stage7-pass2-scored` / `-protein-fdr` / `-blib-written` | 39.62 GB | 38.75 GB |

In-process Stage 7 **inherits essentially nothing** (4.26 GB, i.e. the library) and **builds
34.5 GB itself** on the `.Value` read that #4597 deferred to it — **134 MB/file of pool**.
So the whole target is inside `SecondPassFdrTask`'s own build; no upstream stage has to
change. The `--task` path only differs in WHO built it, and its fragment release frees
2.35 GB where the in-process path frees nothing (`released=0`).

**Reading Stage 7 alone understates it.** Standalone `--task` peaks at 53.6 GB managed /
55.5 GB private (`s7fix257`, 69:47); the same stage in-process peaks at 65.2 / 69.0 GB. An
A/B measured only on the `--task` path is ~12 GB optimistic about the in-process peak.

**The 69.0 GB in that log is a PRE-#4615 number — read the plot, not the summary.** The PNG
shows the Stage 7 window as a ~50 GB private plateau with one narrow spike to 70 GB at
~23:05. That spike is `RestorePass1Scalars`' LOH churn, which #4615 fixed (131 -> 1 MB/file).
Quoting 69.0 GB as today's Stage 7 peak would be quoting a defect that is already gone.

What is left after #4615, at 257 files:

| | managed peak | private peak | live floor (post-GC) |
|---|---|---|---|
| FirstPassFDR (in-process) | 49.5 GB | **53.7 GB** | 7.0 GB (p10) |
| SecondPassFDR, `--task` alone (`s7fix257`) | 53.6 GB | **55.5 GB** | 39.62 GB |

So the two stages are **neck and neck on peak, and 5x apart on floor**. Stage 7 is still in
contention, and it is in contention because of what it HOLDS, not what it spikes. That is
the whole remaining issue.

**The prize**: with the pool streamed, Stage 7's live becomes library + aggregates (single-
digit GB), the run's high point becomes FirstPassFDR, and the whole-run floor drift
(+138 MB/file) should collapse — 134 of those 138 MB are this pool.

## #4615 did NOT lower the live pool — proven by its own A/B

Worth pinning, because the plot invites the opposite reading: the pre-#4615 in-process run
tops 70 GB in Stage 7, #4615 removed that, and it is tempting to conclude the whole elevated
Stage 7 band was the defect. It was not. #4615's own 100-file A/B, same cohort, one binary
difference:

| post-GC probe | `s7ab-base` | `s7ab-fix` |
|---|---|---|
| `stage7-inherited` / `stage7-pool` | 20.27 GB | **20.25 GB** |
| `stage7-fragments-released` .. `-blib-written` | 17.89 GB | **17.89 GB** |

Identical. What moved is the transient half — `peak_paged` 52.98 -> 46.29 GB,
pass-2-scored working set 46.62 -> 43.53 GB, `gc_fragmented_last_gc` 10.31 -> 2.94 GB. That
is the signature of removing dead LOH buffers: the working set falls, the live set does not.

After #4615 the pool is still 17.89 GB live at 100 files (20.25 at build, of which 4.19 is
the library -> ~160 MB/file) and 39.62 GB at 257, and `s7fix257` still plateaus at 43-52 GB
managed / ~50 GB private for its whole 70 minutes. **The 70 GB top was the defect; the ~50 GB
plateau under it is the pool, and it stayed.**

**Caveat**: every probe series above is the `--task` / reload path. There is no post-#4615
IN-PROCESS run yet — the full 5-7 log predates the fix. Since the A/B shows #4615 does not
touch the live pool, the in-process pool should still be ~38.75 GB live at 257 files, but
that is inference, not measurement. Settling it needs a straight-through Stage 5-7 run with
`OSPREY_LOG_MEMORY=1`.

## Nothing is INHERITED — it is all Stage 7's own load (corrected 2026-08-26)

An earlier version of this file said `--task` "enters Stage 7 at 41.97 GB" against 4.26 GB
in-process, and read that as an upstream cost on one path. **Wrong, and Brendan caught it:
Stage 6 ends low on both paths; the 41.97 GB is what the `--task` process loaded moments
before the probe fired.** From the logs:

In-process, the Stage 6 -> 7 boundary (managed / private per memstamp column):

```
22:21:48  mgd=4360MB priv=20102MB  [MEM reconciliation-resident] managed_heap=4.26 GB
22:21:51  mgd=5427MB priv=19686MB  [TASK] PerFileRescoring:done (21747.6s)
22:21:52  mgd=4360MB priv=19582MB  [MEM stage7-inherited] managed_heap=4.26 GB
22:21:57  mgd=6174MB priv=19330MB  Rebuilding first-pass survivors from 257 file(s)...
22:22:24  mgd=12105MB priv=18444MB    3%
```

Stage 6 hands over the LIBRARY and process overhead - 4.26 GB managed, ~19.6 GB private -
and the next line is Stage 7 beginning its own rebuild.

On `--task`, the same load happens one minute earlier in the same process:

```
12:18:29  mgd=46549MB priv=54615MB  Coelution analysis complete. 768549137 total scored entries across 257 files
12:19:08  mgd=47439MB priv=55529MB  --task SecondPassFDR compaction: 768549137 -> 137034004 entries
12:19:15  mgd=42982MB priv=53558MB  [MEM stage7-inherited] managed_heap=41.97 GB
```

So there is **one** target, not one per path: the ~137 M-entry survivor pool - 137,034,004
entries, ~34.5 GB, **~252 B/entry** - reached by two different loaders:

| path | loader | note |
|---|---|---|
| in-process | `RescoredEntries` rebuild from the reconciled parquets (#4597 defers it to the `.Value` read) | climbs 4.26 -> 38.75 GB inside Stage 7 |
| `--task SecondPassFDR` | `LoadJoinOnlyScores` | materializes all **768.5 M** pre-compaction entries, THEN compacts 5.6x to 137.0 M |

The `--task` side therefore carries a strictly ADDITIONAL defect: the pre-compaction
materialization (#4615's TODO measured 311 MB/file to file 81), where
`RescoreHydration.HydrateCompactedStreaming` already compacts each file as it loads and
serves every other reconciled-bundle path. #4615 stripped features out of that reload
(~800 MB/file) and deliberately left the stubs - "a restructuring job, not a buffer fix".

**Consequence for measurement**: the `-LinkFrom` / `--task` harness measures the pool PLUS
the pre-compaction read; a straight-through run measures the pool alone. Both must end up
bounded, and neither number substitutes for the other.

## Deferred findings from #4615 that belong to this branch

Verified by `/code-review max` on that PR, left out of it by scope. All three reduce work
over the pool, so they compose with streaming rather than competing with it:

1. `BuildBestExpPrecursorQ` / `BuildSharedBoundaries` re-walk the whole pool to re-derive
   what `CollectPassingEntries` materialized 22 lines earlier — two of six full passes over
   the 137 M-row pool. `BuildSharedBoundaries` is `internal` and bound by
   `MultiChargeConsensusTest.cs:118`, so the signature change needs its own test pass.
2. `BuildCrossFileObservations` has **no `passingPrecursors` gate** — it filters on `IsDecoy`
   alone while its only consumer looks up passing keys exclusively, so every non-passing
   precursor's observation list is built and never read.
3. Three more whole-pool walks at the head of the blib phase (`ComputePassingPeptides`,
   `ComputePassingPrecursors`, `CollectPassingEntries`), ~70 s at 257 files, still silent.

A fourth is a correctness hazard, not memory, and #4615 says it deserves its own issue:
`FdrScoresSidecar`'s bare `catch { return false; }` reports an OutOfMemoryException as a
missing sidecar; those entries then reach picked-protein FDR at `Score == 0.0`, the decoy
side is not q-gated, so zeros compete in the null and the run exits 0 with corrupted protein
numbers. Cheap durable fix: `catch (Exception ex) when (!(ex is OutOfMemoryException))`.
**Flagged here, not silently adopted** — file it unless told otherwise.

**Correction on the baseline named for me**: `...-p0059_0060_0061-s7base` is not the
post-spike-fix run. Its exe is `_bin\26.1.1.233-20260821` (pre-#4615) and it **stopped at
file 93 of 257** with no DONE line, mid-load. Its perfviz numbers (30.6 GB managed peak,
+44 MB/file) describe a truncated load ramp, not the stage. The completed Stage-7-alone runs
on the fixed binary are `s7fix257` (logmem off, 69:47) and `s7mem257` (logmem on, 80:45).

### 2026-08-26 - Session start

Branch created in `C:\proj\pwiz-work1` off master 2a0b0069f6. Read the issue body and all
nine comments in full. Two things that a short read would have got wrong, recorded above:
the "Stage 7 costs nothing per file" finding was retracted, and the concrete lever its
retraction named (the per-observation dictionaries in `ComputeFullPopulationPrecursorFdrStreaming`)
has since been fixed by #4554 — confirmed in the tree, `StreamedCompetitionState` is O(distinct).
What remains is the live survivor pool itself.
