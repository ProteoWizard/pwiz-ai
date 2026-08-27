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
- **PR**: [#4621](https://github.com/ProteoWizard/pwiz/pull/4621) - opened 2026-08-27 02:40

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

## WHERE THIS STANDS (2026-08-26, end of session)

Branch `Skyline/work/20260826_osprey_stage7_stream_pool` in **`C:\proj\pwiz-work1`**.

| # | change | state |
|---|---|---|
| 1 | select survivors during the parquet read | **committed `457d56eb55`**, Stellar 10/10 incl. golden |
| 2 | always write the reconciled parquet | **committed `1e282f8a29`**, Stellar 10/10 |
| 3 | subset the write to survivors | **committed `1e282f8a29`**; first attempt was INERT, see below |
| 6 | in-place upgrade + `OSPREY_UPGRADE_RECONCILED_ONLY` | **committed `1e282f8a29`**, unit-gated only |
| 4 | gap-fill marker column | NOT started - needed only for increment 5 |
| 5 | point the Stage 7 rebuild at the reconciled parquet | NOT started - the increment that actually removes Stage 4 |

**The inert-subset bug, kept because the lesson generalizes.** Increment 3 first keyed the
keep set on `entry_id`, and regression #4 passed all 10 modes while dropping **zero** rows.
The write log said `483022 rows ... original 482891 rows` against Stellar's own
`First-pass compaction: 482891 -> 332138 entries`. Compaction removes an entry_id's extra
SCANS, not whole entry_ids - 332,138 is about 166,724 passing base_ids x 2 for target and
decoy, i.e. roughly one surviving row per entry_id - so an entry_id-keyed set matches every
row by construction. Now keyed on `(entry_id, charge, scan_number)`, the identity
`MapFeaturesByIdentity` already uses, and tested AFTER the overlay because a rescore can move
a row's apex scan.

Two things added so it cannot hide again: `StreamReconciledScoresParquet` returns `NWritten`,
and the Stage 6 log reports rows WRITTEN against rows READ rather than `original + appended`;
and `TestReconciledTransferKeepsOnlySurvivors` asserts the emitted count.

**Next actions, in order**

1. Confirm regression #5 is green AND that the write log now shows a real drop
   (~482,891 -> ~332,138 + gap-fill on Stellar). A PASS alone does not prove the subset works.
2. Commit increments 2, 3 and 6.
3. Increment 5 (+4): point the Stage 7 rebuild at the reconciled parquet, which is what
   removes the Stage 4 read. Needs the gap-fill discriminator - see the section above for why.
4. Trials: single plate `chs-86files-...-p0059`, then the 257-file set, using the in-place
   upgrade rather than re-running Stage 6.

**Coverage caveat to carry**: Stellar compacts only 1.45x (482,891 -> 332,138), so it exercises
the subset but is a weak proxy for the ~5.6x seen on CHS. The 257-file trial is where the
size claim gets tested.

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

**Why 4 is required, established 2026-08-26 rather than assumed.** `PickBestPassing` skips
entries with `RunPrecursorQvalue > fdrThreshold`, so a gap-fill row (q = 1.0, because it gets
no 1st-pass sidecar record) can never WIN a consensus. But `SelectRescoreTargets` groups every
entry by `ModifiedSequence` first and skips a group only when `indices.Count <= 1`, so a
peptide with one real survivor plus one gap-fill row now clears that skip - and the gap-fill
row is then treated as a TARGET to reconcile to the consensus boundaries. That is a behavior
change, and today's code avoids it only by ORDERING: `MaterializeAllSurvivors` builds a
pre-gap-fill list from the Stage 4 parquet, consensus and `ResetRescoredTargets` run against
it, and gap-fill is appended afterwards by the overlay. Reading the reconciled parquet
collapses that ordering, so the rows have to be distinguishable in the artifact.

### Increment 6: upgrade in place on the rehydrate path (Brendan's design, 2026-08-26)

Not a standalone converter - fold it into rehydrate, so any workflow holding old-format
artifacts self-heals instead of needing a migration tool run against it:

1. if the reconciled parquet is old-format (`osprey.reconciled = "true"`), load it the old
   way - which this build already does, since the loader filters to survivors either way;
2. write the new format beside it;
3. restart against the new format.

**The keep set falls out for free.** It is the entry ids of the POST-compaction stub list -
by definition what Stage 7 consumes today - so gap-fill rows are kept or dropped exactly as
the current code already decides them. That removes the one thing worth verifying about a
standalone converter (whether gap-fill survives a `first_pass_base_ids` filter): the question
never arises, because the filter is not re-derived.

**Cost**: one sequential read plus a ~15% write per file, which is the I/O Stage 7's load was
already paying - roughly 20-30 min for 257 files against ~5 h of re-running Stage 6.

**Isolating a clean profile** (Brendan): run it twice, or kill the run once the new format is
on disk, or an env var that exits after the conversion completes. The env var is the tidiest
for an A/B and costs nothing when unset.

**Testing sequence this unlocks**

1. single plate `chs-86files-...-p0059`: convert, `--task SecondPassFDR`, diff the blib
   against that run's existing one. Byte-identical proves the conversion AND the new Stage 7
   path together - a real oracle, not a smoke test.
2. 257 files `chs-257files-...-p0059_0060_0061`: convert, run with `OSPREY_LOG_MEMORY=1`,
   compare live memory against the `s7mem257` baseline (4.19 GB library + 39.62 GB pool).

What this does NOT measure is Stage 6's write cost under the new format; that needs one real
end-to-end run before the PR.

**Compatibility hazard to handle in 4/5**: an OLD reconciled parquet has no marker column and
is full-shaped, so its gap-fill rows would be misread as originals. `ReadColumnByName` returns
null for a missing column, which makes "no marker column" detectable - so the loader should
fall back to the Stage 4 path when the marker is absent. That keeps the existing 257-file CHS
run dir usable as the memory rig instead of forcing a ~15 h re-score before anything can be
measured.

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

## Increment 4 reconsidered: no parquet column needed (2026-08-26)

`GapFillTarget` already carries `TargetEntryId`, `DecoyEntryId`, `ModifiedSequence` and
`Charge`, and the planner persists the list in `reconciliation.json`'s `gap_fill_targets`.
So which rows are gap-fill is recoverable from an artifact Stage 7 already reads - no
`is_gap_fill` column, no schema change, no format bump beyond the one already made.

**But the better fix may skip classification entirely.** The reason to identify gap-fill rows
was that `ResetRescoredTargets` addresses the survivor list POSITIONALLY, using indices from
`plan.ConsensusTargets` / `plan.ReconciliationTargets` that were computed against the
pre-gap-fill list. Two ways out:

* (a) load without gap-fill, reset, then append - needs the discriminator, and classifying by
  entry_id alone is unsafe if a gap-fill target's entry_id also has a surviving row in that
  file (gap-fill is for precursors not detected in that run, so it should not, but "not
  detected" and "not passing" are not obviously the same thing);
* (b) re-key the reset by entry_id instead of position, which needs no discriminator at all
  and removes a positional dependency that has already been a source of subtlety.

**(b) is the one to try first.** Note `ReconciliationActions` are ALREADY entry_id-keyed on
disk and only turned into positions at load (`RescoreHydration` builds
`idToIdx[stubs[idx].EntryId] = idx`), so half of this is precedent rather than new design.
`ConsensusTargets` are the half that is genuinely positional.

Not attempted this session - it wants a clear head and its own regression cycle, not the
tail of one.

## SINGLE-PLATE TRIAL: PASS (2026-08-26, plate 0059, 86 files)

`chs-86files-libdecoy-r1.0-protein-compact-s7subset59`, `--task SecondPassFDR -LinkFrom` the
p0059 run, Release snapshot `_bin\26.1.1.238-s7subset-20260826`,
`OSPREY_VERSION_OVERRIDE=26.1.1.233`. **exit=0 in 70 min.**

**The artifact shrank 6.9x**: 86 reconciled parquets 90.76 GB -> **13.16 GB**, per file
`544,281 rows kept of 3,801,989` (7.0x by row, 14.5% by size - the two agree). Better than the
~5.6x expected. Extrapolates to ~38 GB for the 257-file set against ~266 GB today.

**Every logical output is identical to the baseline:**

| | p0059 baseline | trial |
|---|---|---|
| survivor observations | 38,135,138 | 38,135,138 |
| protein stratum | 418,271 base_ids | 418,271 |
| peptides at 1% experiment FDR | 40,280 | 40,280 |
| parsimony groups | 4,702 | 4,702 |
| protein groups passing | 4,633 | 4,633 |
| library spectra / passing entries | 44,510 / 3,783,092 | 44,510 / 3,783,092 |

**The blib differs by 4,096 bytes - one SQLite page - and that is PRE-EXISTING.** Control from
artifacts written before this branch: the 257-file `--task` run `s7mem257` (build
233-stage7fix) differs from its own full-run baseline by 8,192 bytes (725,467,136 vs
725,458,944). Two pages at 257 files, one at 86: it scales with cohort size, as page
allocation does and a content difference would not.

**Also confirmed**: the in-place upgrade ran on all 86 files (the path no regression mode
covers), and the p0059 baseline directory is still 90.76 GB - deleting a hard-linked entry
dropped only that name, so the comparison target survived the run that consumed it.

**Post-GC memory, unchanged as expected** (increment 5 is what removes the pool):
`stage7-inherited` = `stage7-pool` = 16.06 GB at 86 files, i.e. 4.19 GB library +
0.138 GB/file, against 0.147 GB/file measured at 257. Model holds.

**Caveat on the design of this comparison**: baseline and trial differ by build (233 vs 238)
AND by path (full run vs --task), not only by this branch. The control above is what makes
the blib delta attributable; the logical counts are what make the result meaningful.

**Timing is contended, not clean** - the upgrade took ~40 min for 86 files while CHS
PerFileRescoring had the machine. Do not quote it as the conversion cost.

## RUN 2: Stage 7 ON the reduced parquet - PASS (2026-08-26, plate 0059)

`chs-86files-...-s7red59`, `--task SecondPassFDR -LinkFrom` the s7subset59 dir (whose
parquets run 1 had upgraded). **exit=0 in 20 min against run 1's 70.**

| | run 1 (old format) | run 2 (reduced) |
|---|---|---|
| load phase | ~17 min | **~5 min** |
| pre-compaction read | 261,062,311 entries | **38,135,138** |
| compaction | 261.1 M -> 38,135,138 | 38,135,138 -> 38,135,138 (**no-op**) |
| pool live (post-GC) | 16.06 GB | **14.61 GB** |
| peptides / proteins | 40,280 / 4,633 | 40,280 / 4,633 |
| Stage 7 wall | 70 min | **20 min** |

**The `--task` pre-compaction pool is gone as a side effect.** #4615 measured it at 311
MB/file and deferred it as "a restructuring job, not a buffer fix". Reading a subsetted
artifact leaves nothing to compact - 6.8x fewer entries materialized - without touching that
code.

**Outputs are content-identical.** Both `--task` blibs are 248,377,344 bytes with identical
peptide (40,280) and protein (4,633) counts. Their SHA-256 differs, so a byte comparison was
run: **62 differing bytes out of 248,377,344, first at offset 8,137** - the SQLite header /
`LibInfo` region, where BiblioSpec stores the library LSID and creation time. Every spectral
and FDR body byte matches. A blib hash is therefore NOT a valid equality test across runs;
size plus counts plus a located byte-diff is.

**Unexplained (favorable)**: the post-GC pool is 1.45 GB lower on the reduced read despite an
identical 38,135,138-entry pool. Not missing rows - the entry counts and base_id counts match
exactly. Something run 1 retained on its way through 261 M rows. Worth understanding before
it is quoted as a benefit of the format.

**Next**: 257-file conversion started 20:01 with `OSPREY_UPGRADE_RECONCILED_ONLY=1`
(`-s7conv257`), so the measurement run afterwards profiles the new format alone.

## 257-file conversion CRASHED - memory exhaustion, not a code defect (2026-08-26)

`-s7conv257` died at 20:42 after 42 min, at file 176/257 of the pool load, with
`System.AccessViolationException` (exit 0xC0000005) in
`ParquetScoreCache.LoadFdrStubsFromParquet(String, Func<UInt32,Boolean>)`.

**Evidence it is exhaustion**: the conversion was at **priv 38,991 MB** and still climbing,
while plate 0062's SecondPassFDR was at **priv 36,253-37,623 MB** in the same minute -
**~76 GB combined on a 63.7 GB box**. An AccessViolation is what a native allocation failure
looks like under exhaustion; the stack frame is the hot allocation site during the load, not
evidence the filtering logic is wrong. Retry on a quiet machine is the test.

**No data lost.** Source and conversion dirs both still hold 257 reconciled parquets at
266.2 GB, and there were zero `.upgraded` leftovers - the crash came before any file was
replaced. (The `File.Delete` -> `File.Move` window in `UpgradeReconciledParquets` is still
worth hardening: these were hard links into a linked run dir, so the source kept the data,
but that is luck of the harness rather than a property of the code.)

**The design finding, which matters more than the crash.** Folding the upgrade into the Stage 7
rehydrate means it inherits the FULL old-format pool build before it converts anything - 261 M
entries at 257 files. So the upgrade is **memory-heavy**, and "convert while other work runs"
does not hold. A standalone converter would not need the pool at all: the survivor identities
per file are derivable from `reconciliation.json`'s `first_pass_base_ids` plus each file's own
rows, with no whole-run buffer. That is the cheaper shape for a one-time migration, and the
in-rehydrate version is the right shape only for a cohort that was going to build the pool
anyway.

**Operational rule earned**: do not run two memory-heavy Osprey jobs on this box. The earlier
concurrency (regressions alongside plate 0062) was survivable because Stellar is tiny; a
257-file pool build is not.

## The converter CANNOT live in SecondPassFdrTask - root cause (2026-08-26)

Three attempts at a low-memory 257-file conversion, all with the same shape: private memory
climbing monotonically with file count to 47-51 GB. The root cause is positional and there is
no fix inside Stage 7.

**`HydrateCompactedStreaming` runs inside `PerFileScoringTask.Rehydrate`.** The very first
crash stack said so and I misread it twice:

```
Task 'pwiz.Osprey.Tasks.PerFileScoringTask' failed to rehydrate its state
  PerFileRescoreTask.Rehydrate
    SecondPassFdrTask.Run : line 192
```

So the pool is materialized by the task graph's REHYDRATE, not by `RescoredEntries.Value` and
not by any single call Stage 7 makes. Demanding **any** byproduct that `PerFileScoringTask`
publishes - `PerFileParquetPaths` and `LibraryById` included, which the upgrade needs - pulls
the whole hydration in behind it. Attempt 2 moved the call after `ctx.Get<RescoredEntries>()`;
attempt 3 moved it above that line into a wrapper; both still paid, because the wrapper's own
`ctx.Get<PerFileParquetPaths>()` is enough to trigger it.

**"Token vs Value" is the wrong mental model** and cost two runs. `ctx.Get<T>()` is not a cheap
handle: it runs the producing task's `Rehydrate`.

**What this means for the design.** The upgrade needs an entry point that does NOT go through
the task graph - its inputs are only a list of parquet paths (available from
`config.InputScores`) and a library. Options, in rough order of preference:

1. A dedicated `--task` (e.g. `UpgradeReconciled`) whose `IsIncluded` excludes every per-file
   task, so nothing rehydrates.
2. A standalone entry point in `Program.cs` that loads the library, calls
   `RescoreHydration.BuildRetainBaseIds` over the `--input-scores` paths, and converts.

`BuildRetainBaseIds` (committed) is already the pool-free half and is correct - it reads only
the planner envelopes. The remaining problem is purely how to reach it without waking the task
graph.

**No artifacts were damaged** by any of the three attempts: source still 257 files / 266.2 GB,
zero stray `.upgraded` / `.retired` files. The move-then-move-then-delete swap held.

**Stopping here rather than attempting a fourth variant** - three failed attempts without a
verified root cause is the point to stop guessing, and the root cause above was only confirmed
on the third. The next attempt should be the standalone entry point, written deliberately.

## UNCOMMITTED WORK in C:\proj\pwiz-work1 (2026-08-26, end of session)

Two files modified and NOT committed - deliberately, because they are unit-gated (build,
593/593, zero inspection warnings) but NOT regression-gated, and they change Stage 7's
ordering:

* `Osprey.Tasks/RescoreHydration.cs` - adds `BuildRetainBaseIds`, the pool-free retain-set
  builder (planner envelopes only). **Correct and worth keeping** - any standalone converter
  will call it.
* `Osprey.Tasks/SecondPassFdrTask.cs` - reworks `UpgradeReconciledParquets` to convert one
  file at a time, pre-checks footers so the already-upgraded case is cheap, and hardens the
  swap to `Move` -> `Move` -> `Delete` (a crash then leaves BOTH copies, not neither).
  **The swap hardening is worth keeping regardless.** The `UpgradeOldFormatReconciledParquetsOrExit`
  wrapper's POSITION is the part known not to work - see the root-cause section above.

To resume: either finish the standalone entry point and gate the whole thing together, or
keep `BuildRetainBaseIds` + the swap hardening and drop the wrapper. Do not commit the
current state as-is without `regression.ps1 -Dataset Stellar`.

The committed branch (`1e282f8a29`) is unaffected by any of this and remains fully gated.

## THE FIX: a non-standard --task mode (Brendan, 2026-08-26)

Osprey already has two `--task` values that are not pipeline stages, and the converter should
be the third:

| mode | what it does |
|---|---|
| `SpectraCache` | stages the `.spectra.bin` caches |
| `ModelDiagnostics` | "regenerates only the --model-diagnostics report for a COMPLETED run, writing no other artifact" |
| **(new)** | compacts old full-shape reconciled parquets to the survivor subset |

`ModelDiagnostics` is the precedent to copy: it works over a finished run's artifacts, writes
one kind of output, and therefore already avoids waking the per-file task graph - the exact
property three attempts inside `SecondPassFdrTask` could not achieve, because
`HydrateCompactedStreaming` runs in `PerFileScoringTask.Rehydrate` and any byproduct demand
pulls it in.

**Wiring** (`OspreyCommandArgs.cs:211` holds the ValidateSet, `:409` the error text, `:693`
and `:808` the help/doc strings - all four need the new value):

1. Accept the new task name.
2. Its `IsIncluded` excludes every per-file task, so nothing rehydrates.
3. Body: load the library, call `RescoreHydration.BuildRetainBaseIds` over the
   `--input-scores` paths (already committed, pool-free), then per file - load that file's
   survivors with the base_id predicate, build identities, `StreamReconciledScoresParquet`,
   swap with Move -> Move -> Delete. All of this already exists in the uncommitted
   `UpgradeReconciledParquets`; only its ENTRY POINT was ever wrong.

**Naming: `CompactPerFileRescore`** (Brendan, settled). It names the task whose results are
being compacted, which is the reference an outside reader already has - `PerFileRescoring` is
a word users type on the command line, where "reconciled" appears only inside a filename.
Rejected: `CompactSecondPassParquet` (names the consumer, not the producer) and
`CompactReconciled` (clear only from inside the code).

One alignment detail left to the implementer: the CLI value for the producing task is
`PerFileRescoring`, while the class is `PerFileRescoreTask`. `CompactPerFileRescoring` matches
the token users actually type; `CompactPerFileRescore` matches the class. Either is
unambiguous - prefer the CLI token if the tie needs breaking.

**And then**: the converter gets its first real measurement. It has never executed - all three
attempts died in the pool build before reaching it, so its per-file behavior has unit tests and
zero runtime evidence.

## IMPLEMENTED: --task CompactPerFileRescoring (`55600ddbc0`, 2026-08-26)

`Osprey.Tasks/CompactPerFileRescoreTask.cs`, wired through `HpcTask.CompactPerFileRescoring`,
`OspreyConfig.CompactReconciledOnly`, the `Program.cs` parse branch + display name, and the
`OspreyCommandArgs` ValidateSet + both error strings. Runs a one-task pipeline beside
`SpectraCachePipeline()`.

Gates: build clean, 593/593, zero inspection warnings, **`regression.ps1 -Dataset Stellar`
PASSED**. (One transient test failure appeared in an earlier invocation and did not reproduce
across two subsequent runs; its name was not captured. Treated as a flake from overlapping
builds, not a result.)

Design points worth keeping:

* It loads the library ITSELF (`new PerFileScoringTask().LoadLibraryAndDecoys`, made
  `internal`) - a one-task pipeline has no producer to `ctx.Get<LibraryById>()` from, and the
  write re-derives sequence / precursor m/z / protein_ids from the library, so a null one
  would write those columns empty. Decoys included: the reconciled parquet carries decoy rows.
* `LoadLibraryAndDecoys` was briefly made `static` and reverted - it uses `_fullLibrary` and
  instance helpers past the point I first scanned. Reused rather than reimplemented because
  decoy generation and supplied-decoy pairing must match the run that wrote the parquets.

### NOT YET RUN - the converter still has zero runtime evidence

All three earlier attempts died in the pool build before reaching the conversion, so its
per-file behavior has unit tests and nothing else.

**The runner cannot drive it yet.** `OspreyDatasetRun.psm1`'s `-Task` ValidateSet and its
`$STAGE_ARTIFACTS` link table (which decides what `-LinkFrom` hard-links) have no entry for
`CompactPerFileRescoring`. First execution therefore needs either:

1. a direct `Osprey.exe --task CompactPerFileRescoring --input-scores <paths> -l <library>`
   invocation, or
2. adding the value to the runner: ValidateSet, plus a `$STAGE_ARTIFACTS` entry that links
   everything through `PerFileRescoring` (the same set `-Task SecondPassFDR` links).

**Do NOT point the first run at `chs-257files-...-p0059_0060_0061`** - that directory is the
old-format baseline every comparison so far depends on. Use a hard-linked copy (e.g. the
`-s7conv257` dir left by the failed attempt, which still holds 257 full-shape parquets sharing
inodes with the baseline); converting there breaks the link and leaves the baseline intact,
the same property that protected it three times today.

## Run logs belong in run.log, not session-temp (Brendan, 2026-08-26)

Invoking `Osprey.exe` directly - which the new task currently requires, since the runner
does not know `CompactPerFileRescoring` - put this conversion's only log in Claude Code's
session-temp folder, split across two streams, with a stale `run.log` still sitting in the
run directory from the crashed 20:01 attempt. Brendan found the changed files and had to ask
where the log was, which is the whole problem: **a log nobody can find is not a record.**

Two things worth carrying forward:

* **Osprey writes its timestamped log to STDERR.** Redirecting only stdout captures nothing -
  `compact257.log` was 0 bytes while `compact257.err` held all 18 KB. The runner hides this by
  merging with `*>&1`, so it only bites a direct invocation.
* **Always land the log as `run.log` in the run directory**, rotating any existing one to
  `run-<stamp>-<reason>.log` rather than truncating - the rule
  `OspreyDatasetRun.psm1` already applies, and the reason it applies it.

**This is the strongest argument for finishing the runner support** (ValidateSet +
`$STAGE_ARTIFACTS` entry): not convenience, but that the sanctioned path produces a named run
directory, a banner recording exe / library / arm, and START and DONE lines - none of which a
direct invocation leaves behind.

### Next session handoff

**Next session**: read `ai/.tmp/handoff-20260826_night_stage7_streaming.md` before starting.
It carries the night-session protocol, the standing approvals (open the PR; trigger TeamCity
Perf/Regression on `pull/<N>` without asking again), the test rig and the numbers to beat,
the gate order, and the traps this session earned - `ctx.Get<T>()` running Rehydrate, a green
regression proving nothing about a filter, and the 63.7 GB concurrency limit.

## THE STREAMING DESIGN, from the code (2026-08-27, night session)

The TODO task "Record the two-pass design here BEFORE writing it" - done here, by reading
every consumer rather than the three the earlier plan named. **The consumer list is larger
than "protein FDR + blib", and that is the finding**: the extra consumers set the ORDER in
which the passes must run, and one of them (`OspreyReportWriter`) re-runs protein FDR per
replicate, so it needs a per-file visit no matter how the rest is arranged.

### Every reader of `perFileEntries` inside Stage 7, in execution order

| # | consumer | reads | O(distinct) expressible? |
|---|---|---|---|
| 1 | `UpgradeReconciledParquets` | EntryId/Charge/ScanNumber per file | per file already; **obsolete** now that `--task CompactPerFileRescoring` is the migration path |
| 2 | `LibraryFragmentRelease.BuildRetainedBaseIds` | EntryId | YES - O(distinct base_id) |
| 3 | `Pass2FdrSidecar.ComputeAndPersist` | per file: the entries to overlay 2nd-pass q onto; writes `.2nd-pass.fdr_scores.bin` | per file + an O(distinct precursor) experiment reduction |
| 4 | `ProteinFdrEngine.RunSecondPass` | best score per peptide, detected peptides; **writes** `ExperimentProteinQvalue` back | YES for the read (O(distinct peptide)); the write-back is per entry |
| 5 | `Pass2FdrSidecar.PatchPass2ProteinQvalues` | per file: patches the protein column into the sidecar written at 3 | per file |
| 6 | `OspreyReportWriter.WriteReports` | **re-runs protein FDR per replicate** over that run's entries | per file, but needs the whole-run parsimony result |
| 7 | `PercolatorEngine.ClampExperimentQToBestRun` | min run-q by EntryId and by (ModifiedSequence, IsDecoy); **writes** experiment q back | YES for the read (two O(distinct) maps); the write-back is per entry |
| 8 | `WriteBlibOutput` - seven walks | `ComputePassingPeptides`, `ComputePassingPrecursors`, `CollectPassingEntries`, `BuildBestByPrecursor`, `BuildBestExpPrecursorQ`, `BuildSharedBoundaries`, `BuildCrossFileObservations` | five are O(distinct); `CollectPassingEntries` and `BuildCrossFileObservations` are O(observations) |
| 9 | `FdrBenchInputWriter.WritePeptideInput` (`--fdrbench-pass 2`) | every reported entry | streamable per file |
| 10 | `ModelDiagnosticsReport.WritePass2AndFinalize` (`--model-diagnostics`) | every entry's final q + score | streamable per file |

`BlibOutputWriter.Write` itself is already aggregate-driven: it touches `perFileEntries`
only for `CreateSourceFiles` (the file list) and `.Count`. Everything it writes comes from
`bestByPrecursor` / `bestExpPrecursorQ` / `sharedBounds` / `entriesByPrecursor`.

### The ordering chain, which is what forces two passes

```
per-file frozen pass-2 score  ->  run q per entry
        |                         (this ALREADY streams: ComputePass2TransferCompeteFull
        |                          scores one file at a time - see the routing comment at
        |                          Pass2FdrSidecar.cs:239-252. The resident thing is the
        |                          FdrEntry pool it overlays onto, not the features.)
        v
EXPERIMENT aggregation over ALL files       <- global reduction, O(distinct precursor)
        v
experiment q written back onto EVERY entry  <- needs a second visit to every file
        v
protein FDR (parsimony + picked-protein)    <- global, O(distinct peptide)
        v
ExperimentProteinQvalue written back        <- second visit again
        v
ClampExperimentQToBestRun                   <- reduce, then write back: a third dependency
        v
blib aggregates + emission                  <- emission per file, refIds from the middle
```

So the shape is not "compute then emit" but **fold -> reduce -> write-back -> reduce ->
emit**, and the write-backs are what make the second per-file visit unavoidable. That still
satisfies the standing FDR-memory rule (per-file compute -> O(entries) aggregate -> per-file
emit, emission a SECOND streamed pass); there are simply more reductions in the middle than
the rule's statement implies.

### What pass 1 must carry forward, and what it costs

Pass 2 needs, per surviving observation: `file`, `EntryId`, `ModifiedSequence`, `Charge`,
`IsDecoy`, run q (both levels), `ApexRt/StartRt/EndRt`, and the pass-2 `Score`. As a packed
value record that is ~56 B against the ~200 B an `FdrEntry` object costs (16 B header, three
uint, a bool, a byte, fourteen double, six reference fields; the 252 B/entry measured at 257
files is that plus list slots and per-file overhead). At 38.1 M survivors on the 257-file
cohort a spill is **~2.1 GB on disk**.

The alternative is re-reading the reconciled parquets in pass 2, which after this branch's
subsetting is ~38 GB rather than the 266 GB pass 1 used to read. A spill is still the better
trade - one sequential write and one sequential read against re-decoding parquet - and it is
what removes the last reason Stage 7 must hold anything whole-run.

### The three hard problems, and what the tree already gives us

1. **Blib emission ORDER - the real difficulty, and it is not data volume.**
   `WriteRetentionTimes` emits precursor-major: a RefSpectra row, then that precursor's rows
   across every file. Streaming per file inverts that to file-major, so the RefSpectra
   refIds must be assigned in the pool-free middle, from `bestByPrecursor` (501,247 distinct
   non-decoy precursor keys at 257 files - small). Pass 2 then writes RetentionTimes rows
   against those refIds as each file is visited, and `entriesByPrecursor` - the
   O(observations) map that pins the pool today - disappears entirely. It exists only to give
   the precursor-major writer an O(1) lookup.

2. **`ResetRescoredTargets` is positional.** `plan.ConsensusTargets` and
   `plan.ReconciliationTargets` carry indices into the survivor list as loaded. Re-key by
   `EntryId`. Precedent, not new design: `ReconciliationActions` are ALREADY entry_id-keyed
   on disk and only turned into positions at load (`RescoreHydration` builds
   `idToIdx[stubs[idx].EntryId] = idx`). `ConsensusTargets` are the genuinely positional
   half. Required for streaming, and independently required to load Stage 7 from the
   reconciled parquet, where the gap-fill rows are already interleaved in canonical position
   and so shift every index after them.

3. **`sharedBounds` is a second accumulator**, keyed `(modseq, file)` -> `double[5]`, so
   O(observations) - tens of millions of entries and several GB at 257 files, built in the
   aggregate phase and read in the emit phase. Make it sparse: an entry is only needed where
   a peptide has more than one charge in that run AND the winning charge's boundaries differ
   from the entry's own. Every other key is the entry's own boundaries, recoverable in the
   emit pass. The same trick #4554 used for `survivorPep`.

### What is NOT solved, and should not be guessed at

* **`OspreyReportWriter.WriteReports` re-runs protein FDR per replicate.** Its own comment
  says "this is the one place with the full per-file pool + library in hand". It is
  default-on (`WriteProteinReport` / `WriteSummaryReport`), so it is on the byte-parity path,
  and it needs one run's entries plus the whole-run parsimony result. That fits the pass-2
  emit visit, but the per-replicate FDR has to be SHOWN to give the same numbers from a
  streamed visit before it is moved, not assumed to.
* **The experiment-aggregation write-back** is the step with no existing streamed analogue.
  Pass 1 does the same thing in `PercolatorEngine`, so the shape exists; whether it is a pure
  O(distinct precursor) reduction under every `--experiment-agg` mode needs checking against
  `mean-best-N` specifically, which keeps the best N observations per precursor rather than
  the max.

### Scope honesty

This touches `Pass2FdrSidecar` (2,217 lines), `SecondPassFdrTask` (913),
`PerFileRescoreTask` (2,436), `ProteinFdrEngine`, `BlibOutputWriter`, `OspreyReportWriter`,
`ModelDiagnosticsReport` and `FdrBenchInputWriter`. It is not a one-session change, and
attempting it as one would produce something no gate could vouch for.

**The enabling seam is separable and is where the next session should start**: a per-file
"bring ONE file to its post-rescore state" function. Today `BuildRescoredPool` runs three
whole-run loops - `MaterializeAllSurvivors`, `ResetRescoredTargets`,
`OverlayReconciledIntoFiles` - and **every one of them is already per-file inside its loop
body**. Fusing them into one function that takes a file key and returns that file's list is
a pure refactor, byte-identical by construction, and it is the call Stage 7 needs in order
to fold-and-drop rather than accumulate.

## NIGHT SESSION 2026-08-26/27 - what landed

Session start 23:05 PDT, opening context 90% free, box quiet (50.6 / 63.7 GB).

| commit | what | gate |
|---|---|---|
| `b67e7168e6` | reconciled-parquet write takes a progress indent, or null to write silently | Stellar 10/10 |
| `9e228f420a` | Stage 7 pool built in ONE per-file pass instead of three whole-run loops | Stellar 10/10 |
| `7ff0382ba4` | three blib aggregate builders walk `passingEntries`, not the pool | Stellar 10/10 |
| `c3b93f6e52` | `FdrScoresSidecar` no longer swallows `OutOfMemoryException` | unit + `-Dataset All` pending |
| `131715da44` | `--task CompactPerFileRescoring` refuses a foreign library; progress indent fixes | unit + runtime negative test + `-Dataset All` pending |
| ai `3543944` | `CompactPerFileRescoring` in the three dataset runners | n/a |

### The per-file seam (the reason the streaming work is now tractable)

`BuildRescoredPool` ran `MaterializeAllSurvivors` -> `ResetRescoredTargets` ->
`OverlayReconciledIntoFiles`, three whole-run loops. Every one was already per-file inside
its own body and none reads another file's entries, so fusing them is the same work in the
same order per file. Byte-identical, confirmed by Stellar 10/10 including mode 1 vs golden
and mode 3 (HPC chain == straight).

What that buys: `MaterializeFileSurvivors(fileName, entries, loader, ctx)` and
`OverlayReconciledIntoFile(fileName, entries, ...)` now exist as per-file primitives, which
is what a fold-and-drop Stage 7 has to call.

### The blib phase was re-deriving what it had already materialized

`BuildBestExpPrecursorQ` and `BuildSharedBoundaries` each walked the whole pool applying
`!IsDecoy && passingPrecursors.Contains((modseq, charge))` - character for character the
filter `CollectPassingEntries` applied 20 lines earlier. `BuildCrossFileObservations` had no
passing gate at all, though its sole consumer (`EmitSpectrumRows`) looks up
`(ModifiedSequence, Charge)` taken from `bestByPrecursor`, whose keys are passing by
construction.

At 257 files: three passes over 137 M rows become three over ~14 M, and `entriesByPrecursor`
stops allocating ~1.4 GB of observation lists that nothing ever reads. The three whole-pool
gates that genuinely must stay (`ComputePassingPeptides`, `ComputePassingPrecursors`,
`CollectPassingEntries` - each needs the previous one's set complete) now report progress;
they were the ~70 s of silence #4615's review named.

## THE LIBRARY MISMATCH - my error, and the guard it produced

**What happened.** The 257-file compaction was launched through `Run-Chs.ps1` letting the
runner resolve the CHS default library. That is `sea-ad\lib\target+decoy+entrapment`. The
`p0059_0060_0061` run these artifacts came from was searched with
`target+decoy+entrapment-20260817`. Same file name, different build:

| | entries | manifest protein_ids replaced | size |
|---|---|---|---|
| `target+decoy+entrapment` (Jun 30) | 6,324,700 | 15,841 | 13.09 GB |
| `target+decoy+entrapment-20260817` | **6,175,389** | **16,062** | 12.39 GB |

The compaction re-derives `sequence` / `precursor_mz` / `protein_ids` from the library BY
ENTRY ID, and entry ids are assigned at library load, so 72 files were rewritten with
another peptide's identity on every row. **Nothing detected it** - the run was healthy,
memory flat, exit path normal. It was caught by hand, comparing the `Loaded N library
entries` line against the baseline's while checking flags for the measurement A/B.

**Bounded and repaired.** Yesterday's 147-file conversion (22:17-23:02, direct invocation)
used the CORRECT library - its log is in the session temp folder Brendan objected to, which
is the second time that folder cost something. A clean mtime split isolated exactly the 72
files written 23:16-23:43, cross-checked three ways: 257 - 157 already-compacted = 100 stale
at start; 72 completed before the kill; 185 + 72 = 257. The baseline was verified intact
FIRST (257 files, 266.23 GB, all 72 present at full shape), then the 72 were deleted and
re-linked from it. `s7conv257` returned to 131.92 GB / 100 full-shape files - the exact
state the handoff described.

**The guard** (`131715da44`). The reconciled parquet's footer already carries
`osprey.library_hash`, and `SearchIdentity.LibraryIdentityHash()` is SHA-256 over file name
+ size + mtime, so it is computable from config without loading the library. The footer scan
now compares them and hard-fails - before the library load, before the first write. A footer
carrying NO hash is refused too: "cannot verify" and "verified" are not the same answer when
the operation is a destructive in-place rewrite.

Proven at runtime, not just by unit test: pointed at the wrong library deliberately, it
refuses at the first stale file in 5.4 s with exit 1 and a message naming both hashes. Then
the real run confirmed all 100 stale files carry the hash, so the strict policy does not
block real artifacts.

**The rule worth carrying**: `-LibraryDir` is not optional when `-LinkFrom`/`-Resume` points
at another run's artifacts. The runner's default library is an ARM default, not the arm the
source run used, and the two only coincide when nobody has built a newer library since. Read
the source run's banner and pass its library explicitly.

**And the deeper one**: this class of defect - an artifact rewritten against the wrong
reference - is invisible to every gate we have, because the output is well-formed and the
run exits 0. The footer hash existed the whole time; nothing compared it. Worth asking, for
each artifact-rewriting path, what identity it is silently trusting.

### Design update: the experiment-aggregation question is settled (2026-08-27)

The design section above listed "the experiment-aggregation write-back" as unsolved, with
`mean-best-N` named as the specific worry - whether keeping the best N observations per
precursor could be expressed as an O(distinct precursor) reduction.

**It does not arise.** `PercolatorQValues.ComputeExperimentPrecursorQMap` takes
`applyExperimentAgg`, and every Stage 7 caller passes `passLabel == FIRST_PASS_LABEL`, i.e.
**false on the second pass**. The reason is in its own doc comment and is not incidental: two
of `OSPREY_EXPERIMENT_AGG`'s premises break on the post-reconciliation survivor pool - gap-fill
rows inflate a group's observation count with fabricated detections, inverting the
reproducibility metric the feature rests on, and the decoy floor would be estimated from the
small, compaction-enriched survivor decoy set instead of the full null.

So Stage 7's experiment aggregation is always the plain target-decoy max competition, which
IS a pure O(distinct precursor) reduction.

**And the primitive is already the right shape.** `ComputeExperimentPrecursorQMap` returns a
`Dictionary<uint, double>` keyed by entry_id - O(distinct), not an O(n) per-row array - with
the full-length wrapper expanding it (#4355 Part B, bounded q-value reconstruction). The
streamed pass-2 would call the map form directly and never expand it.

That leaves ONE genuinely open item on the streaming design:
`OspreyReportWriter.WriteReports` re-running protein FDR per replicate. It is default-on, so
it is on the byte-parity path, and it needs one run's entries plus the whole-run parsimony
result - which fits the pass-2 emit visit, but has to be shown to give the same numbers from
a streamed visit rather than assumed to.

## Code review (`/code-review max`, 2026-08-27 ~00:30) - triage

Fifteen findings, which is the tool's cap, so the count says nothing about severity. Each was
verified against the source before acting; three were refuted by the reviewer itself and are
recorded here so they are not re-raised.

### Fixed (commit `e5e6d15fa3`)

| # | finding | verdict |
|---|---|---|
| 1 | `AnyReconciledParquet` is `File.Exists`, but this branch writes a reconciled parquet for EVERY file | **real, and the most consequential** - see below |
| 2 | the `HydrateCompactedStreaming` drift predicate is tautological | **real** - see below |
| 3 | `UpgradeReconciledParquets` early exit returns `true`, so `AnalysisPipeline` stamps validity sidecars onto stale outputs | real; now returns false via `StopAfterUpgrade` |
| 4 | that same upgrade rewrites rows from the library with no `osprey.library_hash` check | real, and the exact defect the night's own accident proved; now calls the shared `VerifyLibraryMatches` |
| 5 | it uses `Delete -> Move`, the ordering its sibling explicitly rejects | real; now `Move -> Move -> Delete` |
| 12 | `ValidateArgs` has no case for the new task, so it inherits another mode's requirements and error text | real; own case + banner branch, and no longer demands a `--output` it never writes |
| 15 | UTF-8 BOM added to five files, a Unicode em dash, `PlanActions`' doc comment orphaned | real, all three CRITICAL-RULES violations; verified by byte inspection against master |

**Finding 1 in full, because it is the one that would have shipped a wrong answer.**
`SecondPassFdrTask.AnyReconciledParquet` gates the second Percolator pass, and its own comment
states the invariant it rests on: "A reconciled parquet exists for a file iff that file had
rescore work, so 'any reconciled parquet on disk' == total_rescored > 0". Increment 2 broke
that invariant by design - every file now gets one, a faithful copy where there was no work.
On a cohort with no rescore work anywhere, Rust skips the second pass and C# would have run
it: retraining, rewriting q-values, and feeding them to protein FDR and the blib. That is the
anti-conservative direction (pass-2 recalibration measured 1.57% FDP against 0.92%), and it
re-opens the divergence #4395 closed.

The fix records the answer where the question is asked: `ReconciledParquetWriter.Write`
computes `rescored = overlayByIndex.Count > 0 || gapFill.Count > 0` - exactly BuildOverlay's
two outputs being empty - and stamps `osprey.rescored` into the footer. `AnyReconciledParquet`
reads it. **A parquet written before the key existed is treated as WORK**, because back then it
was only written when there was some; that is what made existence a sound test in the first
place, and it means no existing run directory needs re-converting.

**Finding 2 in full, because it is the same failure mode as the night's library accident.**
`id => !loadedIds.Contains(id)`, where `loadedIds` is built from the same `stubs` that
`FdrScoresSidecar.TryRead` builds `byEntryId` from. The predicate is only consulted after that
lookup has already missed, so it is true for every record and `return false` is unreachable.
The superset-contract check was disabled outright, not narrowed. A 1st-pass sidecar written
from a different parquet, a different library build (different entry_id assignment) or a
different binary would be accepted record for record; every survivor would keep `Score = 0.0`,
and since the decoy side is not q-gated those zeros compete in the picked-protein null. Now
`id => !retainBaseIds.Contains(id & BASE_ID_MASK)` - the survivor test, the same shape
`FirstPassSurvivorLoader` uses. **The predicate must state the FILTER, never what happened to
load.**

### Verified real, deliberately NOT fixed - these need a clear head and their own gate cycle

**`ParquetIndex` now carries two index spaces in one buffer** (finding 10).
`ParquetScoreCache.BuildFdrEntryColumns` mutates `entry.ParquetIndex = startIndex + j` on the
CALLER'S live `FdrEntry` objects, and `FlushGroup` passes the OUTPUT row position. Before the
subset write that position was the original row-for-row ordinal, so the assignment was
value-preserving; now a rescored row is renumbered into the compacted space (~5.6x smaller)
while the un-rescored survivors in the same Stage 6 buffer keep Stage-4 ordinals.

Nothing observed depends on it: `CANONICAL_ORDER`'s terminal tie-break only fires when
(EntryId, Charge, ScanNumber) also ties, which `DeduplicatePairs` makes essentially
impossible, and every other consumer keys on identity. Regression modes 1, 2, 3 and 5 - which
include the direct WARM-vs-COLD comparison - are green. But the surrounding comments assert
`ParquetIndex` is unique per reloaded stub and that WARM and COLD share an index space, and
those assertions are now weaker than they read. Either the mutation should be suppressed on
the reconciled write or the comments should stop claiming it.

**`--task SecondPassFDR --model-diagnostics` now reports a post-compaction population as
pre-compaction** (finding 11). `HydrateCompactedStreaming`'s `onStubsHydrated` callback is
documented as "the caller's one look at this file's full pre-compaction pool", and it feeds
`ScoringTaskShared.TallyPreCompaction` and `FeedModelDiagnostics`, whose whole point is the
rows compaction discards - "mostly the decoys and entrapment its FDP and calibration views are
built from". Those stubs used to come from a row-for-row twin of the Stage 4 parquet. They now
come from the survivor subset.

So on the `--task` path the FDP curves, score histograms and calibration anchors cover a
decoy-depleted fifth of the intended rows, with no error and no marker in the report, and
`PreCompactionTally.Stubs` is no longer a pre-compaction number. This is diagnostics only -
off the default output path, and the blib and FDR are unaffected - but it is silently wrong
rather than absent, which is the worse kind. The honest options are to read the Stage 4
parquet explicitly when `--model-diagnostics` is on (giving back the read this branch removed,
but only for that flag) or to relabel the views as post-compaction.

### Dropped, with reasons

* **`byEntryId` last-write-wins** (finding 9): real, but pre-existing and not touched by this
  branch. An entry_id spanning several rows has only one of them overlaid. Worth its own
  issue; not this PR's to carry.
* **Decode-then-discard in `StreamReconciledScoresParquet`** (finding 13) and **the compaction
  task's library / double-read overheads** (finding 14): both real efficiency findings, ~216 GB
  of throwaway decode across the cohort in the first case. Neither is a correctness problem and
  both are contained; they belong with the streaming work, which will restructure this code
  anyway.
* **Crash-recovery gaps in the new task** (findings 6, 7, 8): an orphaned `.retired` aborts the
  next run, "nothing to do" cannot be distinguished from "nothing was there", and
  `BuildRetainBaseIds` skips the envelope-consistency check a partial-cohort invocation would
  need. Real, and worth a follow-up; the task is a one-time recovery path that has now been run
  successfully end to end on 257 files.

### Refuted by the reviewer's own verification - do not re-raise

* The `passingEntries` narrowing in the three blib builders is **provably equivalent**: for any
  key in `passingPrecursors`, `!IsDecoy` and `!IsDecoy && contains(key)` select identical rows,
  and `CollectPassingEntries` preserves file-major order, so `nRunsDetected` and every
  tie-break are unchanged.
* `CanRehydrate` returns false on an empty `Outputs` list, so the one-task compaction pipeline
  is never skipped.
* `HashSet<T>(int)`, the null-`using` ternary and `string.Format` with a ternary format string
  all behave correctly on net472 and net8.0.

## 257-FILE MEASUREMENT: outputs identical, Stage 7 2.25x faster, memory essentially unchanged

`chs-257files-libdecoy-r1.0-protein-compact-s7red257`, `--task SecondPassFDR -LinkFrom`
the converted `s7conv257` dir, exe `_bin\26.1.1.238-s7final-20260827`,
`OSPREY_VERSION_OVERRIDE=26.1.1.233`, `OSPREY_LOG_MEMORY=1`, mdiag on, fdrbench pass 2 -
flags matched to the `s7mem257` baseline deliberately, so the only differences are the
build and the artifact format. **exit=0 in 36 min.**

| | baseline `s7mem257` | `s7red257` |
|---|---|---|
| library-resident | 4.19 GB | 4.19 GB |
| pre-compaction read | 768,549,137 -> 137,034,004 | **137,034,004 -> 137,034,004 (no-op)** |
| `stage7-inherited` / `stage7-pool` | 41.97 GB | **40.23 GB** |
| `stage7-fragments-released` | 39.62 GB (released 5,173,196) | **37.87 GB** (released 5,173,196) |
| `stage7-pass2-scored` / `-protein-fdr` / `-blib-written` | 39.62 GB | **37.87 GB** |
| peak working set / peak_paged | 53.6 / 55.5 GB (`s7fix257`) | 54.18 / **55.55 GB** |
| protein groups passing | 5,079 | **5,079** |
| library spectra / passing entries | 45,724 / 11,745,026 | **45,724 / 11,745,026** |
| blib | 725,467,136 bytes | **725,467,136 bytes** |
| **Stage 7 wall** | **81 min** | **36 min** |

**The blib is content-identical**: same size, and a full byte comparison finds **65 differing
bytes out of 725,467,136, the first at offset 8,137** - the SQLite header / `LibInfo` region
where BiblioSpec stores the library LSID and creation time. Every spectral and FDR body byte
matches. (The 86-file control found 62 bytes in the same region; a blib SHA is not an
equality test, size + counts + a located byte-diff is.)

### What this does and does not buy - state it plainly

**It buys**: the artifact drops 266.23 -> 47.07 GB (5.7x), Stage 7's wall drops 81 -> 36 min
(2.25x), and the `--task` pre-compaction materialization is GONE - 768.5 M entries were read
and compacted before, and now the read IS the survivor set, so the compaction is a no-op.
That is the 311 MB/file structure #4615 measured and deferred as "a restructuring job, not a
buffer fix"; it disappeared without that code being touched.

**It does NOT buy the memory bar.** Brendan's bar was "take Stage 7 entirely out of contention
for peak memory", i.e. FirstPassFDR becomes the run's high point. Measured:

* live floor 39.62 -> 37.87 GB, a **4.4%** reduction;
* peak_paged 55.5 -> 55.55 GB, i.e. **unchanged**;
* FirstPassFDR in-process peaks at 53.7 GB private.

So Stage 7 is still the run's high point and still holds a ~38 GB resident pool. **The pool is
untouched, exactly as designed** - this branch changes what Stage 7 READS, not what it HOLDS.
Removing the pool is the streaming work, and nothing here should be quoted as progress toward
the memory bar.

**Still unattributed**: the pool is 1.74 GB smaller on the reduced read (40.23 vs 41.97 at
build; 37.87 vs 39.62 after the fragment release) despite an identical 137,034,004-entry pool
and an identical 5,173,196 fragment release. The 86-file trial saw the same shape (1.45 GB).
Something the old path retained on its way through 768.5 M rows. Worth understanding before
it is quoted as a benefit of the format - it is currently a number, not an explanation.

**Also measured**: 11,745,026 passing entries against the 72.9 M non-decoy observations
`BuildCrossFileObservations` used to index, so the blib-phase narrowing committed tonight is
a 6.2x reduction on that structure - slightly better than the ~5x estimated when it was
written. It does not show in the post-GC probes because `entriesByPrecursor` is dead by the
time `stage7-blib-written` fires; it shows in the transient, and the peak is dominated by the
pool.

## PR #4621 open - TeamCity trigger BLOCKED, needs Brendan

Branch pushed and [#4621](https://github.com/ProteoWizard/pwiz/pull/4621) opened 2026-08-27
02:40, module prefix `osprey:`, label `osprey`.

**The TeamCity Perf/Regression trigger was refused by the Claude Code permission classifier**,
not by policy - the handoff's standing approval covers it. It still needs firing on
`pull/4621` (config `ProteoWizard_OspreyWindowsNetPerfRegressionTests`, agent
`MacCoss TeamCity Agent 1`, never a named branch).

Local gates standing in for it meanwhile:

| gate | result |
|---|---|
| build + 594 tests + zero inspection warnings | green |
| `regression.ps1 -Dataset All` | **PASSED**, all four datasets, every mode - at `e3015a4aa4` |
| `regression.ps1 -Dataset Stellar` | **PASSED** at HEAD (`e5e6d15fa3`, the review fixes incl. the pass-2 gate change) |
| 257-file `--task SecondPassFDR` | exit 0, outputs identical to `s7mem257`, blib 65 bytes apart in `LibInfo` |

The one gap a morning session should close: `-Dataset All` has not run on HEAD, only on the
commit before the review fixes. TeamCity's config runs exactly that (`regression.ps1
-TeamCity -Dataset All`), so firing it closes the gap.

### The unexplained 1.74 GB, stated more sharply: 13 bytes per entry

Both runs report `[MEM library-resident] managed_heap=4.19 GB (6175389 entries)`, so the
library is identical, and both build a pool of exactly 137,034,004 entries. The pool alone is
therefore:

| | pool bytes | per entry |
|---|---|---|
| `s7mem257` (read 768.5 M rows, compacted 5.6x) | 41.97 - 4.19 = 37.78 GB | **276 B** |
| `s7red257` (read the survivor subset directly) | 40.23 - 4.19 = 36.04 GB | **263 B** |

13 B/entry x 137,034,004 = 1.78 GB, which is the whole difference. So it is a per-entry
overhead, not a separate retained structure - which rules out most of the obvious guesses
(a retained side map, an accumulator, the model-diagnostics state) and points at something
attached to each surviving `FdrEntry` or to the lists holding them.

Candidates worth testing, none of them confirmed: list capacity slack (8 B per unused slot -
the old path grows each file's list to ~2.99 M and removes down to ~533 K, so an untrimmed
list would show exactly this shape), or `ModifiedSequence` string instances decoded from a
5.6x larger row set sharing differently.

**This needs a heap profile (dotMemory), not more log reading.** Recorded here rather than
guessed at, and it must not be quoted as a benefit of the new format until it is understood -
it is currently a number with a plausible cause, which is not the same as an explanation.

## Stacked branch: the first streaming increment is done and gated

`Skyline/work/20260827_osprey_stage7_stream_increment`, off `e5e6d15fa3` (PR #4621's HEAD).
NOT pushed - a second PR to open once #4621 merges, or to fold in if #4621 has to be
re-gated anyway.

**`2cb80febc1` - Stage 7's score reset keys on identity, not position.**
`ResetRescoredTargets` rebuilt its target set from `plan.ConsensusTargets` /
`plan.ReconciliationTargets`, whose indices address the survivor list as the RESCORE saw it.
That is correct only while the deferred rebuild reproduces that order exactly - and it will
NOT, once Stage 7 loads from the reconciled parquet, because the gap-fill rows are already
interleaved in canonical position there and shift every index after them. Design item 2 of
the streaming plan, and a prerequisite for both streaming and the "point Stage 7 at the
reconciled parquet" increment.

It now captures what `OverlayRescoredEntries` actually reset, as it resets it, keyed
**(entry_id, charge, scan_number)**. Not entry_id alone: compaction removes an entry_id's
extra SCANS rather than the entry_id itself, so a bare id could select a row the planner
never targeted - the same reason `MapFeaturesByIdentity` keys on all three, and the same
trap the inert-subset bug came from.

Two side benefits worth keeping: the target set is now what was RESET rather than what was
PROPOSED (planner targets include files that never reached the scoring engine), and the
completeness check says something meaningful - a count mismatch means the rebuilt list is not
the one the rescore produced, where the old range check could only catch an index off the end.
The deferred plan also stops carrying two index-keyed maps.

Gates: build + 594 tests + zero inspection warnings, and **`regression.ps1 -Dataset Stellar`
PASSED all 10 modes** including `mode1 (vs golden)` and `mode3 (HPC chain==straight)`, so it
is byte-identical.

**Next on this branch**, in the order the design gives: sparse `sharedBounds` (design item 3,
O(observations) today), then the blib emission-order inversion (item 1, the genuinely hard
one - refIds must be assigned in the pool-free middle so pass 2 can emit file-major).

### Correction to the "13 bytes per entry" framing above

Cross-checked against the 86-file trial, and the per-entry framing does not hold. Pool bytes
are (probe - 4.19 GB library) over the pool's own entry count:

| cohort | old format | new format | delta | old B/entry | new B/entry |
|---|---|---|---|---|---|
| 86 files, 38,135,138 entries | 11.87 GB | 10.42 GB | 1.45 GB | 311 | 273 |
| 257 files, 137,034,004 entries | 37.78 GB | 36.04 GB | 1.74 GB | 276 | 263 |

The delta is **38 B/entry at 86 files and 13 B/entry at 257** - not a constant, so it is not a
per-entry overhead, and the paragraph above was over-reach from a single cohort. Note the
per-entry cost is not constant within either arm either (311 vs 276 old, 273 vs 263 new).

Do not fit a line through these two points: they are different cohorts, not a size series -
86 files is plate 0059 alone and 257 is three plates with different peptide content, so
entries-per-file, charge distribution and modified-sequence sharing all differ. A two-point
fit across them produces a ~94 MB/file term that would imply an O(files) structure nobody has
seen in any other probe, which is a good sign the fit is meaningless rather than a discovery.

**What is actually established**: the reduced read ends with a smaller live pool than the
full read, by 1.45-1.74 GB, at two cohort sizes, with identical entry counts and identical
fragment-release counts in both. **Why remains unknown**, and it needs a heap profile
(dotMemory, comparing the two arms' retained-object graphs) rather than more arithmetic on
two summary numbers. Until then it is an observation, not a benefit of the format.
