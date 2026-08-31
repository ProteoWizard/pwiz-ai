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

**`1096cb3d23` - the shared-boundary map stops storing its own fallback.** Design item 3, and
it turned out both easier and better-founded than the design assumed.

The design called `sharedBounds` "O(observations), several GB", which was written when it
walked the whole pool; it now walks `passingEntries`, so the real size is O(distinct
(modseq, file)) among passing entries. Measured shape at 257 CHS files: 11,745,026 passing
entries over 45,724 passing precursors is **256.9 observations per precursor**, i.e. nearly
every (precursor, file) pair exists, so the map is ~10 M keys, on the order of 1 GB.

The sparsity rule is simpler than "the winning charge's boundaries differ from the entry's
own", which is a per-entry test against a per-key map. All charge states of a peptide in a run
share the boundaries of the lowest-run-q charge - so a peptide with only ONE passing charge is
its own winner, and the value stored for it IS the entry's own boundaries. Both readers
(`EmitSpectrumRows`, `WriteRetentionTimes`) already initialize from the entry and overwrite
only on a hit, so those keys can simply be absent.

Multi-charge is a property of the PEPTIDE, so the gate is derivable from `passingPrecursors`
alone - 45,724 keys, nothing - and applies BEFORE insertion rather than pruning afterwards,
which is the difference between a smaller map and a smaller peak. At 45,724 precursors over
roughly 40,000 peptides, about six keys in seven are never built.

Using the GLOBAL multi-charge set rather than a per-run one is deliberate and conservative: it
is a superset, so it may keep a key that turns out single-charge in that particular run, and
that key stores the entry's own boundaries - identical to the fallback. Exact either way.

Gates: build + 594 tests + zero inspection warnings, `regression.ps1 -Dataset Stellar` PASSED
all 10 modes including `mode1 (vs golden)`.

## THE REAL DESIGN: ScoreIndex, a written row identity (Brendan, 2026-08-27)

Everything hard in this refactor traces to one absence: **the parquet has no row identity.**
It has a foreign key to the library (`entry_id` - low 31 bits are the base_id shared by a
target and its paired decoy, high bit is the decoy flag), a positional address
(`FdrEntry.ParquetIndex`, the row ordinal), and a compound disambiguator
(`entry_id, charge, scan_number`). None of those is a row id, and the symptoms all follow:

| symptom | root |
|---|---|
| the reconciled parquet had to be row-for-row identical to `scores.parquet` | features are addressed by ordinal - `PercolatorScorer.ResolveFeatureRow` does `rows[idx]` |
| `Pass2FdrSidecar.LoadReconciledFeaturesByIdentity` exists at all | the ordinal stopped addressing the right row once the two files diverged |
| `CANONICAL_ORDER` needs `ParquetIndex` as its terminal tie-break | no unique row key to sort on |
| gap-fill is identified by `ParquetIndex == uint.MaxValue` | a sentinel stuffed into an address field |
| the identity-keyed reset matched **0 of 37,098** targets on Stellar | the compound key is not invariant across a rescore |
| the `/code-review max` `ParquetIndex` finding | the ordinal means a different thing in each file |

Brendan's framing, and it is the point: *"we shouldn't need a complex compound key to match
things. We own the Parquet format and we should introduce a real RowID as in a database
schema. It feels like we are failing to use basic principles from relational databases."*

### The decision: persist the Stage 4 ordinal as `ScoreIndex`, in the RECONCILED parquet only

The Stage 4 row ordinal already IS a unique per-file row id. It does not need replacing with a
surrogate - it needs **writing down** instead of being inferred from row position. So the
reconciled parquet gains a `ScoreIndex` column carrying the ordinal of the `scores.parquet`
row it derives from, and every match keys on it.

**`scores.parquet` is NOT changed.** Brendan, explicitly: *"do not write ScoreIndex in
scores.parquet. It is redundant, and if we did that we would make it a true RowId for clarity.
We are using a trick to avoid having to change scores.parquet at all."* The trick is what keeps
the blast radius small - every Stage 4 parquet on disk stays valid, and there is no converter
for them, ever. The asymmetry is deliberate: the column states a correspondence, and the
correspondence only needs stating in the file that is no longer parallel.

Writing it is free going forward: `StreamReconciledScoresParquet` already tracks `origRead`,
the original row ordinal, as it streams the Stage 4 file group by group.

### What it retires

* `ParquetIndex` as an address - 100 non-doc uses across the tree, roughly half in tests.
* The `(entry_id, charge, scan_number)` compound key, and with it the distinction between
  "the key that survives a rescore" and "the key that disambiguates within one artifact".
* The gap-fill sentinel: a gap-fill row has no Stage 4 row, so its `ScoreIndex` sentinel IS
  the `is_gap_fill` discriminator - which was increment 4 of the original plan, reasoned away
  in "Increment 4 reconsidered: no parquet column needed".
* `LoadReconciledFeaturesByIdentity`'s workaround.

### THE HAZARD: three generations of reconciled parquet, and the middle one is dangerous

| generation | shape | `ScoreIndex` | readable by a new binary? |
|---|---|---|---|
| pre-#4486 | full, row-parallel with `scores.parquet` | absent | **YES** - row position IS the Stage 4 ordinal, so falling back to it is exactly correct |
| **this branch so far** | subset, `osprey.reconciled = survivors` | absent | **NO** - row position is no longer the ordinal and nothing records what is |
| with `ScoreIndex` | subset | present | yes, by construction |

The middle generation looks readable and would map rows to the WRONG Stage 4 features in
silence. It exists only on the test rigs (`...-s7conv257` at 47 GB, and the two 86-file sets)
because the branch is unmerged, so the practical blast radius is ours - but the detection
matters more than the conversion:

1. the loader must **REFUSE** a `survivors`-marked parquet with no `ScoreIndex` column, not
   fall back to row position - that fallback is correct only for the full-shape generation;
2. `--task CompactPerFileRescoring`'s "already survivors, skip" test must also require the
   column, so it RE-converts the middle generation instead of skipping it.

### Backfilling: exact, and it needs the gap-fill classification

The converter cannot use the old reconciled parquet's own row ordinal: that file is every
original row PLUS gap-fill merged into canonical position, so its ordinals shift past each
gap-fill row. It has to count only NON-gap-fill rows to recover the Stage 4 ordinal - and the
gap-fill rows are exactly `reconciliation.json`'s `gap_fill_targets`, keyed by `entry_id`.

That is precisely the classification "Increment 4 reconsidered" established was available, so
the two halves fit: the reasoning that killed the column is what makes backfilling it possible.

### Goldens

Approved to move (Brendan, 2026-08-27). A new column changes artifact bytes even where every
logical output is identical, so `osprey-regression.data` needs a deliberate refresh with
`-CreateGolden`.

### Where `--task ModelDiagnostics` lands

`Program.ResolveInputScores` treats the reconciled parquet as AUTHORITATIVE when present
(`// reconciled: authoritative`), so a diagnostics regeneration over a completed run reads
reconciled parquets, not Stage 4 ones. It therefore inherits the generation rules above and
needs no separate handling - which is the answer to "would we need a converter for all the
Stage 4 parquet we have on disk?": no, none.

### CORRECTIONS to the ScoreIndex design above (Brendan, 2026-08-27)

Two things in the section above are wrong. Both were mine.

**1. No golden regeneration is needed.** I claimed a new parquet column changes artifact bytes
and so requires refreshing `osprey-regression.data`, and asked for (and got) approval on that
basis. The golden set is **59 `.tsv` files and one `.md`** - the blib table dumps,
`blib_summary.tsv` and `protein_fdr.tsv`. No parquet is stored as a golden, and a
`score_index` column reaches neither the blib nor the protein-FDR dump. Nothing to regenerate.
Checkable in one `ls`, which I should have run before asserting it - the filenames were even
listed earlier in the same session while checking whether the golden pinned row order.

**2. Do not rename `ParquetIndex`.** I renamed it to `ScoreIndex` across 24 files and 244
identifiers to make the field "say what it identifies". Brendan: *"The code can just keep the
ParquetIndex naming, it just needs to populate it differently when reading a
reconciled-scores.parquet."* Correct - the semantics live in the population, not the name, and
the rename is review churn for no behavioural gain. Reverted.

### The change, in its actual (much smaller) form

1. Write **`score_index`** into the reconciled parquet: the Stage 4 row ordinal, which
   `StreamReconciledScoresParquet` already tracks as `origRead` while it streams the original
   group by group. Gap-fill rows take the `uint.MaxValue` sentinel they already carry in
   memory, so the column IS the `is_gap_fill` discriminator - increment 4, for free.
2. Populate `FdrEntry.ParquetIndex` **from that column** when reading a reconciled parquet
   rather than from the row position.
3. When the column is ABSENT, keep using the row position - which is exactly right for every
   pre-#4486 file, because those are row-parallel with `scores.parquet` by construction.
4. **Refuse** a parquet marked `osprey.reconciled = survivors` that has no `score_index`
   column: subset shape plus no written identity is the one combination where position lies.
   The same test makes `--task CompactPerFileRescoring` re-convert those rather than skip them.
5. Backfill in the converter by counting NON-gap-fill rows (classified from
   `reconciliation.json`'s `gap_fill_targets`) to recover the Stage 4 ordinal - the old
   reconciled file's own ordinals shift past each interleaved gap-fill row.

No rename, no sidecar format bump, no golden refresh. `ParquetIndex` keeps its name and becomes
TRUE on every path - so feature resolution, the `CANONICAL_ORDER` tie-break and the gap-fill
sentinel all start being correct without being touched, and `entry_id` stops having to stand in
as a row key it was never meant to be.

## ScoreIndex landed, and the rigs were reset (2026-08-27 morning)

Brendan held PR #4621 rather than merging it: the increment delivered the storage win without
the design win, and *"I can't tell if the Parquet format supports what we are targeting if you
haven't even delivered not reading scores.parquet."* Right on both counts.

### What landed on the stacked branch, each gated Stellar 10/10 incl. mode1 vs golden

| commit | what |
|---|---|
| `2cb80febc1` | score reset keyed on identity, not position |
| `1096cb3d23` | shared-boundary map stops storing its own fallback |
| `29145a2d60` | blib retention times written FILE-major; `BuildCrossFileObservations` deleted |
| `70934377a3` | **Stage 7 stopped reading `.scores.parquet`** |
| `f7cae59c9a` | `score_index`: the reconciled parquet gets a written row identity |
| `608e2dbd63` | both compound-key maps replaced by it |

### Two things the gate caught that argument would not have

**A sentinel is not an identity.** Gap-fill rows first got `score_index = uint.MaxValue`, so
every one of them collapsed to a single entry in the feature map and they all received the
SAME feature vector. On Stellar that moved 361 of 4,481 group q-values and two proteins'
best-peptide score. `mode1 (vs golden)` caught it while every self-consistency mode passed -
the run agreed with itself and disagreed with the truth. Gap-fill rows now number PAST the
source row count, which makes `score_index` a genuine per-file row id for every row.

**The `<= 1 group` skip stole ordinals.** The converter's first cut advanced the source cursor
while merely SEARCHING for a matching group, so a gap-fill group consumed the ordinals
belonging to the next real group. Caught by the new unit test, not by a run.

Both are the same lesson: this is a refactor whose invariants live in comments that contradict
each other, so every step wants an experiment rather than a reading.

### Corrections to my own earlier claims, recorded because they misled

* **No golden regeneration was ever needed.** The golden set is 59 `.tsv` files; no parquet is
  stored. I asserted otherwise and got approval on that basis. `score_index` landed
  byte-identical against the existing golden.
* **`ParquetIndex` should not be renamed.** I renamed it across 24 files and 244 identifiers;
  Brendan: the semantics are in the population, not the name. Reverted.
* **The converter is not unsafe.** I claimed converting a pre-#4486 file needs a gap-fill
  classification that cannot be made safely, and recommended deleting the task. Brendan:
  *"pairing the two parquet files ... doesn't require all 257 in memory."* Pairing
  `scores.parquet` with its reconciled sibling by `(entry_id, charge)` GROUPS resolves every
  row exactly - groups are invariant under a rescore where `scan_number` is not, and a
  gap-fill group has no rows on the Stage 4 side by definition. I had anchored on the
  `entry_id`-alone classification and never considered the obvious pairing.

### Rigs reset

The five interim-format directories (subset, no `score_index` - a shape that never merged and
is now refused by design) were deleted: `s7conv257`, `s7inc257`, `s7red257`, `s7red59`,
`s7subset59`. **85.3 GB reclaimed, not the 167 GB their sizes suggested** - hard links again.

Baseline verified intact (257 files, 266.2 GB). Reconversion running in `...-s7conv257b`,
whose parquets are 8-way hard links to the baseline, so `File.Replace` breaks the link rather
than the source. Correct library confirmed twice from its log (6,175,389 entries, 16,062
manifest replacements - both matching the baseline).

## 257-file validation of the score_index design - PASS (2026-08-27)

`...-s7si257`, `--task SecondPassFDR -LinkFrom` the reconverted `s7conv257b`, exe
`_bin\26.1.1.238-scoreindex-20260827`. **exit=0 in 34 min.**

Reconversion first: 257 files, 266.2 -> **47.4 GB**, `137,034,004 rows kept of 768,549,137`,
74 min, zero stray temps, baseline verified intact at 266.2 GB. The 0.3 GB over the previous
conversion is the `score_index` column, ~4 bytes x 137 M rows.

| | `s7mem257` baseline | `s7si257` |
|---|---|---|
| pre-compaction read | 768,549,137 -> 137,034,004 | **137,034,004 -> 137,034,004 (no-op)** |
| planner actions dropped | - | **0** |
| protein groups passing | 5,079 | **5,079** |
| library spectra / passing entries | 45,724 / 11,745,026 | **45,724 / 11,745,026** |
| Proteins / RefSpectraProteins | 5,757 / 50,566 | **5,757 / 50,566** |
| `SUM(bestSpectrum)` | 45,724 | **45,724** (one best per spectrum) |
| Stage 7 wall | 81 min | **34 min** |
| `stage7-pool` | 41.97 GB | 40.23 GB |
| peak_paged | 55.5 GB | 53.15 GB |

**The blib is content-identical but NOT byte-identical, and that is expected.** Size differs by
208,896 bytes (51 SQLite pages) because the file-major RetentionTimes emission changes physical
row order, so SQLite packs pages differently. A byte comparison is the wrong test - which is
why the gate compares tables by key.

Verified by content instead. Every count matches exactly. Two floating SUMs differed in their
last digits (`endTime` 1e-4, `score` 7e-6, on sums over 11.7 M rows, ~1e-10 relative) - the
signature of accumulation ORDER, not of different values. Confirmed by re-summing as scaled
INTEGERS, which is order-independent:

```
baseline    141265093448307|5615089607870263|35845665555838|138943034250552
score_index 141265093448307|5615089607870263|35845665555838|138943034250552
```

Identical to the last representable digit.

**`0 action(s) dropped` is the sharpest signal.** Every planner reconciliation action resolved
against rows loaded from the reconciled parquet through `score_index`. A wrong identity
mapping anywhere shows up here first - it is what moved the protein counts when the gap-fill
sentinel collided on Stellar.

**Two caveats to carry.** The peak improvement (55.5 -> 53.15 GB) is ONE run and peak working
set varies; it is not a result until repeated. And `stage7-pool` is still 40.23 GB - none of
this work touches the resident pool, which remains the whole of #4486.

## THE BAR FOR THE PR (Brendan, 2026-08-27)

*"Let's target one PR that delivers memory reduction and streaming, the ultimate proof that
the redesign has delivered and won't need immediate change as it would have if we had merged
earlier."* And: *"We also need to run the 257 file Stage 7 to prove the memory reduction."*

So the PR does not land on gates alone. **It lands on a 257-file `--task SecondPassFDR` run
showing the pool gone**, against the `s7mem257` baseline:

| probe | baseline | today (score_index) | REQUIRED |
|---|---|---|---|
| `stage7-inherited` / `stage7-pool` | 41.97 GB | 40.23 GB | **library + aggregates, single-digit GB** |
| `stage7-blib-written` | 39.62 GB | 37.87 GB | same |
| peak_paged | 55.5 GB | 53.15 GB | **below FirstPassFDR's 53.7 GB private** |

and with every logical output still reproducing exactly - 5,079 protein groups, 45,724
spectra, 11,745,026 passing entries, RetentionTimes values matching by integer sum.

Everything landed so far changes what Stage 7 READS. None of it touches what it HOLDS, so
`stage7-pool` has moved 41.97 -> 40.23 GB and that is all. The remaining work is the whole
point of #4486.

### The streamed design, now that the groundwork exists

The spill already exists and needs no new artifact: `.2nd-pass.fdr_scores.bin` is written per
file BEFORE the blib phase, carries Score and every q-value keyed by entry_id, and
`PatchPass2ProteinQvalues` fills its protein column after protein FDR. So a re-loaded file is
`reconciled parquet + 2nd-pass sidecar`.

1. **Pass 1**, per file, dropped after: fold the clamp maps (min run q by entry_id and by
   (peptide, isDecoy)), the experiment-q aggregate, and the peptide-level bests - all
   O(distinct). From those compute `passingPeptides` / `passingPrecursors`.
2. **Pass 2**, per file, dropped after: keep a compact record for PASSING observations only -
   file, score_index, charge, run q, apex/start/end. 11,745,026 x ~40 B = **~470 MB**, which
   is Brendan's O(files x precursors) and the only thing that stays resident.
3. **Middle**, pool-free: parsimony, picked-protein FDR, RefSpectra refIds from
   `bestByPrecursor`.
4. **Emit** from the compact records. Already file-major since `29145a2d60`, so no third pass
   over the artifacts.

Two passes rather than one because of the CLAMP: `ClampExperimentQToBestRun` runs after
protein FDR, only in memory, and its result decides which precursors pass - so it has to
become a fold in pass 1 and an application in pass 2.

## THE ANSWER: Stage 7 should use Stage 5's machinery (Brendan, 2026-08-27)

*"FirstPassFDR calculates FDR for the entire population. It must hold information on how to do
that in limited memory. It makes no sense that SecondPassFDR would be as large or larger on
1/6 the population."*

That is the whole diagnosis, and the numbers are damning:

| stage | population | live floor (post-GC) | bytes/entry |
|---|---|---|---|
| FirstPassFDR | 768,549,137 | **7.0 GB** (p10) | ~9 B |
| SecondPassFDR | 137,034,004 | **40.2 GB** | ~293 B |

Stage 5 does FDR over 5.6x the population in a fifth of the memory - **32x better per entry** -
because #4355 / #4397 moved it onto `FdrProjection`, a lean readonly struct streamed straight
out of the parquet, with q-values routed through `IFdrOutputSink` rather than stored on the
row. Its own commit note: *"rematerializing every file's FdrEntry stubs cost ~53 GB on an
82-file Astral run (191 M x ~280 B) purely so FirstPassFDR could convert them into 32 B
FdrProjection rows and drop them."*

Stage 7 holds `FdrEntry` at ~263 B/row where Stage 5 holds ~40 B. **That difference IS the
40 GB.** There is no new streaming design to invent; there is a machinery Stage 7 is not using.

| | today | on projections |
|---|---|---|
| survivor pool | 137 M x ~263 B = **40.2 GB** | 137 M x ~40 B = **5.5 GB** |
| + library | 4.19 GB | 4.19 GB |
| Stage 7 live | **~40 GB** | **~9.7 GB** |

which clears the bar: FirstPassFDR's 53.7 GB private becomes the run's peak.

### The single blocker, precisely located

A projection path for pass 2 ALREADY EXISTS - `ComputePass2Projection` - and the default arm
does not take it. `Pass2FdrSidecar.cs:239-252` says why:

> *The frozen-model modes (transfer, transfer-compete, protein-compact) also take the resident
> path ... transfer-compete / protein-compact re-score with the frozen 1st-pass model over the
> full pre-compaction population / protein stratum - a competition the projection engine does
> not do (it trains + competes over the survivor set only).*

So `protein-compact`, the DEFAULT, falls back to resident purely because the projection engine
cannot express its frozen-model competition over the protein stratum.
`ComputePass2TransferCompeteFull` (lines 841-1257) already STREAMS its scoring one file at a
time; what is resident is the `FdrEntry` pool it scores INTO.

### A dependency that was satisfied this morning

`FdrProjection.ParquetIndex` is documented as *"Row index in the source file's
`.scores.parquet`"*. Until `score_index` landed, a projection built from reconciled-parquet
stubs would have carried the row's position in the WRONG file. So today's identity work was a
prerequisite for putting Stage 7 on projections at all - which is why this could not have been
done first.

### How to do it, following this codebase's own convention

Add the projection-backed pass-2 path behind a flag defaulting OFF, A/B it against the
resident path for byte-identity, then flip the default - exactly how `OSPREY_FDR_PROJECTION`
and `OSPREY_STAGE6_STREAM_SURVIVORS` were introduced, each leaving a working oracle on the
other side of the switch.

**Stellar is a weak oracle here** - 1.45x compaction, 391 gap-fill rows - where the behaviour
that matters is a frozen competition over a protein stratum at 5.6x. The 257-file run is the
real proof, and it is a 34-minute loop, so this wants fewer and better-reasoned iterations
rather than fast ones.

### De-risked: pass 2's frozen competition is ALREADY bounded (2026-08-27)

The routing comment at `Pass2FdrSidecar.cs:239-252` reads as though `protein-compact` needs a
resident pool - *"a competition the projection engine does not do"*. Read against the code,
that describes where the ENTRIES live, not an algorithmic requirement.
`ComputePass2TransferCompeteFull` decomposes as:

| step | state it needs | bounded today? |
|---|---|---|
| `ReadFile` - frozen score for one file | that file's entry ids + scores; PIN features loaded AND RELEASED per file | **yes** |
| the competition | `StreamingFdr.StreamedCompetitionState`, O(distinct base_id) - #4554 | **yes** |
| step 4 - apply experiment q + PEP | O(distinct) maps plus `pass1ExpQByKey`, which holds only OFF-STRATUM changed peaks | **yes** |
| the `.2nd-pass` sidecar write | per file | **yes** |

Its own comments say so: *"no (file, entry_id)-keyed result map is ever built"* and *"Finish
each reported survivor from the bounded competition state, ONE FILE AT A TIME."*

So the only resident thing is `entriesByFile[fileKey]` - the `FdrEntry` list the scoring reads
from and the write-back writes to. Converting pass 2 means materializing per file in
`ReadFile` and making step 4 + the sidecar write a second per-file pass. Two materializations
per file, which is exactly the two-pass shape the design predicted.

**This was the piece most likely to make the plan infeasible, and it is not.** The remaining
work is mechanical rather than uncertain - the one genuinely unproven consumer left is
`OspreyReportWriter`'s per-replicate protein FDR.

## SESSION END 2026-08-27 12:40 - where the work stands

**Branches.** PR [#4621](https://github.com/ProteoWizard/pwiz/pull/4621) is OPEN but HELD at
`2978de7b37` on `Skyline/work/20260826_osprey_stage7_stream_pool`. Brendan chose to hold it
rather than merge: it delivered the storage win without the design win, and would have needed
immediate rework. All later work is on `Skyline/work/20260827_osprey_stage7_stream_increment`
(10 commits ahead, NOT pushed), to be folded into one PR that delivers memory reduction AND
streaming.

**Every commit below is gated Stellar 10/10 including `mode1 (vs golden)`.**

| commit | what |
|---|---|
| `2cb80febc1` | score reset keyed on identity, not position |
| `1096cb3d23` | shared-boundary map stops storing its own fallback |
| `29145a2d60` | blib retention times FILE-major; `BuildCrossFileObservations` deleted |
| `70934377a3` | Stage 7 stopped reading `.scores.parquet` |
| `f7cae59c9a` | `score_index` - the reconciled parquet gets a written row identity |
| `608e2dbd63` | both compound-key maps replaced by it |
| `3579d64d2a` | `RescoredEntries.FileNames` / `LoadFile` / `Files()` - the streaming seam |
| `d8b2ec5537` | experiment-q clamp split into fold + apply |
| `f41ece819c` | first three consumers moved onto the per-file walk |

**Validated at 257 files** (`s7si257`): every logical output reproduces exactly, artifact
266.2 -> 47.4 GB, Stage 7 81 -> 34 min. See the validation section above.

**NOT delivered: the memory bar.** `stage7-pool` is still 40.23 GB. Everything so far changes
what Stage 7 READS, not what it HOLDS.

### Next session: the remaining path, in order

1. **`Pass2FdrSidecar.ComputePass2TransferCompeteFull`** (lines 841-1257) - materialize per
   file in `ReadFile`; make step 4 + the sidecar write a second per-file pass. **De-risked**:
   the competition is already streamed and bounded (see the section above), so only
   `entriesByFile` is resident.
2. **`CollectPassingEntries`** - 11.7 M `FdrEntry` REFERENCES become compact records
   (file, peptideId, charge, runQ, expQ, apex/start/end ~56 B = ~650 MB). The first consumer
   that genuinely retains, and what pins the pool through the blib phase.
3. **`RunProteinFdr`** - reads fold to O(distinct peptide); the write-back is already the
   sidecar patch.
4. **`OspreyReportWriter`** - re-runs protein FDR per replicate, default-on, **the one
   genuinely unproven consumer**. If it needs a whole-run view it forces an extra pass or a
   reduced resident structure.
5. **The flip** - stop reading `.Value`, so the pool is never built. Then the 257-file run,
   which is the acceptance test.

Then two independently valuable follow-ons: **fuse the per-consumer folds** (each converted
consumer calls `Files()` separately, which is free while the buffer exists and becomes a
separate pass after the flip), and **drop the five blob columns** - measured at **54% of the
reconciled artifact** (`cwt_candidates` 88 B/row, `fragment_mzs` 47, `fragment_intensities`
36, the two XIC blobs 33) and never read back out of a reconciled parquet. That is 47 -> ~22 GB.

**Also still open**: `--task CompactPerFileRescoring`'s interim-format refusal now guards a
shape that exists nowhere (those rigs were deleted); the `--task SecondPassFDR
--model-diagnostics` pre-compaction views still report a decoy-depleted subset as
pre-compaction; and issue [#4622](https://github.com/ProteoWizard/pwiz/issues/4622) was filed
for the `Osprey*` blib tables and the missing protein-group q-value.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260827_osprey_stage7_streaming.md` before starting work.

## Step 1 DONE in the tree: the frozen second pass streams (2026-08-27 afternoon)

`Pass2FdrSidecar.ComputePass2TransferCompeteFull` - the DEFAULT arm, `protein-compact` - no
longer takes the pool. It takes the `RescoredEntries` seam and runs one file end to end:
materialize, seed its pass-1 scalars, load features, score with the frozen model, compete,
stamp run q, **write that file's `.2nd-pass.fdr_scores.bin`**, drop it.

### The correction to the handoff's plan, and why it matters

The handoff said "materialize per file in `ReadFile`; make step 4 + the sidecar write a second
per-file pass. **Two materializations per file**". That plan has a hole: step 4 needs each
entry's `Score` (frozen-model) and `RunPrecursorQvalue`, and BOTH are produced inside pass 1
and lost when the file is dropped. Re-materializing the entries does not bring them back - a
second pass would have to re-load the file's features AND re-run its run-level competition, or
carry an O(files x survivors) map, which is the thing being removed.

**The sidecar closes it.** The per-file write already happens in this stage; moving it into the
competition loop makes the sidecar the carrier of the run-scope columns, and the four
experiment-scope columns (`experiment_precursor_qvalue`, `experiment_peptide_qvalue`, `pep`,
`experiment_aggregate_score`) are patched into those same files afterwards, per file, from the
bounded competition state. **Step 4 needs no entries at all** - every field it reads
(`entry_id`, run q) and every field it writes is a sidecar column. So the second pass is a
streamed rewrite of ~68 B/record, not a second materialization.

New primitive: `FdrScoresSidecar.PatchExperimentValues`, the exact twin of the existing
`PatchProteinQvalues` - one record resident, atomic via `FileSaver`, only those four columns
overwritten. Its test asserts the contract that makes two phases substitutable for one: the
patched file is **byte-identical** to a single-phase write whose records already carried the
final values.

### What else landed with it

* **`Pass2SidecarWriter`** - the per-file write body (resume skip, validity sidecar, tallies)
  existed twice, which is how the projection path acquired the `--task ModelDiagnostics` skip
  and the resident one did not. One body now, so a path cannot quietly differ in what it writes
  or counts. **Behavior change**: the resident write block gains that diagnostics skip.
* **`Pass1ScalarSeeder`** - `RestorePass1Scalars`'s per-file body, so the streamed path can seed
  a file inside its own materialization. The whole-pool loop is skipped entirely for the frozen
  modes; running both would read every 1st-pass sidecar twice, and it can only walk a pool that
  is resident.
* **`ComputePass2FrozenCompetition`** - the frozen modes got their own entry point. They used to
  enter `ComputePass2Resident` and return early; nothing about them is resident any more.
* **Two behavior changes, both deliberate, both on already-broken inputs.** A duplicate
  `--input-scores` stem is now last-wins rather than merged (a streamed reader is handed one
  file's rows at a time; both dispositions apply ONE file's scalars to a name denoting two -
  #4555 is still the real fix). And a per-file key with no `config.InputFiles` entry now
  REFUSES rather than continuing: the sidecar is where this pass puts its results, so such a
  file would take a fresh run q with nowhere to record its experiment q, and protein FDR would
  gate it on a pass-1 value while every other file used a pass-2 one.
* Six pre-existing inspection warnings introduced by the `score_index` commits, fixed
  (`ParquetScoreCache` had a doc comment orphaned from `ReadFdrStubScalars` by an inserted
  method; `ReconciledParquetWriterTest` had redundant `(byte)` casts).

### The transition, and what it costs today

`Files()` yields from the resident buffer while anything still builds it, so with the pool still
resident this pass costs nothing extra and the entries it stamps ARE the pool's - the existing
reload loop then puts the sidecar back on the pool either way, so the two agree by construction.
Once nothing builds the buffer, this pass materializes each file **twice**: once for the
survivor-entry_id fold (needed before file 0, because the best-of-runs floor is global) and once
for the competition. That is the "fuse the per-consumer folds" follow-on, now with a concrete
second caller.

### Gate

Build + 596 tests + zero-warning inspection green, and `regression.ps1 -Dataset Stellar`
**10/10 including `mode1 (vs golden)` and `mode3`** on the second run (the first found the
`FileNames` hole below). Logs in `ai/.tmp/sessions/20260827-stage7-stream-pass2/`.
**Stellar remains a weak oracle for this** - 1.45x compaction, 391 gap-fill rows, 3 files -
where the behavior that matters is a frozen competition over a protein stratum at 5.6x. The
257-file run is the real proof.

### The seam had a null hole, and only the distributed leg found it

First Stellar gate: `mode1 (vs golden)` PASS, `mode1c` PASS, **`mode3` (HPC 4-task chain)
ABORTED** - `--task SecondPassFDR` exited 1.

`RescoredEntries.FileNames` was set ONLY by `WithStreaming`, and `WithStreaming` is called on
exactly one of the three construction sites (`3579d64d2a`). The straight-through rescore takes
it; the resident rescore and the `--task SecondPassFDR` **rehydrate** both publish
`new RescoredEntries(_perFileEntries)` with no streaming attached, so `FileNames` was null
there and the first consumer to read it died.

Nothing had read it yet, which is why the seam looked finished. `Files()` already had the
right fallback - yield from the buffer when nothing is deferred - and `FileNames` now makes the
same one (`_fileNames ?? Value.ConvertAll(...)`), which is free on those paths because they
defer nothing. **A streamed consumer must be able to pair `FileNames` with `Files()` without
knowing which side of the transition it is on**; returning null on one side made this pass work
straight-through and fail distributed.

Third time this branch has seen the same shape: a change that agrees with itself on the
in-process path and disagrees on the distributed one. `mode3` is the leg that catches it.

## Step 2 DONE in the tree: the blib phase stopped holding the pool (2026-08-27)

`CollectPassingEntries` returned `List<KeyValuePair<string, FdrEntry>>` - 16 B a row, but every
row PINNING a ~263 B `FdrEntry` and through it that file's whole survivor list. 11.7 M rows held
the 40 GB pool alive from the FDR gates through the last RefSpectra row.

**The whole phase now works on values.** New `PassingObservation` (internal readonly struct,
~64 B): file, modified sequence, charge, run q, experiment precursor q, apex/start/end. Those
eight fields are the ENTIRE set the four consumers read - checked one by one, not assumed.

* `CollectPassingEntries` walks `rescored.Files()` and builds the compact list AND
  `bestByPrecursor` in ONE pass. The best-per-precursor map could no longer be a second pass
  over the passing list, because RefSpectra needs the winner's `FdrEntry` itself. It is
  O(distinct precursor) - 45,724 entries, ~12 MB - so the entries it keeps pin themselves and
  nothing else.
* `ModifiedSequence` is INTERNED as the records are built. The parquet reader hands out a fresh
  string per row, so keeping each row's own instance would have retained 11.7 M strings - more
  than the records - against ~40,000 distinct sequences. **This is the trap a naive value-struct
  conversion walks into**: it looks like a pure win in the struct layout and is not.
* `BlibOutputWriter.Write` no longer takes the pool at all. `CreateSourceFiles` and the
  `perFileEntriesCount` argument needed only the run's file NAMES, so they take
  `rescored.FileNames`.

Net memory at 257 files: **~750 MB of records replacing 187 MB of references** - a straight
loss until the last pool consumer goes, which is exactly what the objective's "documented trap"
predicted, and why this lands with the conversions rather than before them.

Build + 596 tests + zero-warning inspection green; Stellar regression running
(`regression-stellar-3.log`).

### What still reads `rescored.Value` after step 2

| line | consumer | disposition |
|---|---|---|
| `UpgradeReconciledParquets` | the format converter | upgrade-mode only, not on the hot path |
| `ComputeAndPersist` | projection / resident arms + the 2nd-pass reload loop | the reload loop is what re-hydrates the pool for the consumers below |
| `RunProteinFdr` | step 3 - folds to O(distinct peptide); the write-back is the sidecar patch |
| `ClampExperimentQToBestRun` | already split fold/apply in `d8b2ec5537`, still takes the pool |
| `FdrBenchInputWriter` | `--fdrbench` only |
| `ModelDiagnosticsReport` | `--model-diagnostics` only |
| `OspreyReportWriter.WriteReports` | step 4, default-on, **still the one unproven consumer** |

## Steps 3 and 4 DONE in the tree (2026-08-27), each gated Stellar 10/10

**Step 3 - `RunProteinFdr`.** `RunSecondPass` folded its two whole-pool passes (per-peptide
bests, detected-peptide set) into ONE walk over `rescored.Files()` - a streamed caller would
otherwise materialize every file twice. New `ProteinFdr.SecondPassProteinFdrAccumulator`, a
separate type from `FirstPassProteinFdrAccumulator` because the gates genuinely differ (RUN
level at the run FDR there, EXPERIMENT level at the experiment FDR here).

**`PropagateProteinQvalues` is gone**, which is the part that mattered. Checked every reader of
`FdrEntry.ExperimentProteinQvalue` past that point: the only one is the 2nd-pass sidecar
(`WriteStage5PercolatorDump` and its Stage-6 twin run earlier; FDRBench, ModelDiagnostics and
OspreyReportWriter never touch the field). So the write-back is now a per-file patch off
`ProteinFdr.PeptideQvalues`, keyed by reading each entry's peptide from the RECONCILED parquet's
own `modified_sequence` column - the column the entry's `ModifiedSequence` came from, so the
lookup matches by construction. A whole-pool write followed by a whole-pool read became one
streamed pass. **This is the shape `RunFirstPassProteinFdrStreaming` has used since the first
pass moved onto projections** - the same "machinery Stage 7 is not using" theme.

**Step 4 - `OspreyReportWriter`, and it was NEVER the risk the issue thought.** Its per-replicate
loop already passes `new[] { kvp }` - one file - to both `CountPrecursorsPeptides` and
`CountPassingProteinGroups`. The only whole-run part was the experiment row, and
`CountPrecursorsPeptides` is a pure O(distinct) fold over an `IEnumerable`, so it now accumulates
inside the per-replicate walk instead of taking a second pass. **Retract the standing note that
this is "the one genuinely unproven consumer"; nothing about it forced an extra pass.**

## Step 5 - THE FLIP: what it actually needs (2026-08-27)

`MaterializeOneFile` loads a file from its reconciled parquet plus the **1st-pass** sidecar, so a
re-materialized file carries pass-1 q-values. Today the pool gets its pass-2 values from
`ComputeAndPersist`'s reload loop, which works only because the pool exists. **The flip has to
move that overlay into the materialization itself** - a file's post-rescore state must mean
"parquet + 2nd-pass sidecar when one is current, else 1st-pass". That is the last design
question in the chain, not a mechanical change, and it is the thing to get right first.

Still reading `rescored.Value` in `Run` after steps 1-4:

| line | consumer | note |
|---|---|---|
| `UpgradeReconciledParquets` | format converter | only when an old-format parquet is found |
| `ComputeAndPersist` | projection / resident arms + the 2nd-pass reload loop | the reload loop IS the thing the flip replaces |
| `ClampExperimentQToBestRun` | already split fold/apply in `d8b2ec5537` | needs the same fold-then-apply-per-file treatment |
| `FdrBenchInputWriter` | `--fdrbench` only | |
| `ModelDiagnosticsReport` | `--model-diagnostics` only | |

### Do not promise 1000 files on 64 GB from this work

Stage 7 stops being the wall - projected ~4.2 GB library + ~3.5 GB emit records = **~8 GB at
1000 files** against ~152 GB today. But the run peak then belongs to FirstPassFDR, whose live
floor is 7.0 GB at 257 files over a population that grows with file count (~27 GB at 1000 if
linear), and whose measured `peak_paged` is ~53 GB **at 257 files**. Most of that gap is
Server-GC committed-but-free rather than retained, so it is tunable - but tunable is a
hypothesis. Whether 1000 files fits in 64 GB is UNANSWERED and needs the 257-file run plus a
Stage-5 projection before anyone plans around it.

## Pass-2 files are now written unconditionally - COMMITTED `b9075eb99a`, `-Dataset All` 56/56

Gated on the FULL four-dataset set, not Stellar: the three `mode7` diagnostics-regeneration
legs are the only coverage the `--task ModelDiagnostics` work has, and they do not run on
Stellar. Every `-Dataset Stellar` gate in this session exercised ZERO `DiagnosticsOnly` paths.

## Pass-2 files are now written unconditionally (Brendan, 2026-08-27)

*"We need to stop conditionally writing second-pass files. Just write the same values again,
if need be... It is always an ambiguous signal. Is the file not there because it was
'unnecessary' or did processing fail during writing and the FileSaver just never got
committed?"* - and this had been said repeatedly before.

Rule written up team-wide in **ai/docs/osprey-development-guide.md**, "Never conditionally
write an output artifact" (loaded by `/osprey-development`). Precedents it now cites so the
argument is not had again: `.scores-reconciled.parquet` (`WriteUnchangedReconciled`), the
Stage 6 reconciliation dump, the 1st-pass `.fdr_scores.bin` (`FdrProjectionSinks.OnFinish`
writes a 0-record file), and now the 2nd-pass one.

### Producers - the file is written or the run failed

* `SecondPassFdrTask.Outputs()` declares the 2nd-pass sidecars **unconditionally**. Gating the
  declaration on `AnyReconciledParquet` had made absence a supported RESUME state.
* `ComputeAndPersist` always runs. `AnyReconciledParquet` (Rust's `total_rescored > 0`) moved
  inside it and now gates only the RECOMPUTE - what values go in the file, never whether the
  file exists. A cohort with no rescore work writes the standing values, which are its
  second-pass answer.
* `Pass2SidecarWriter` lost its "already on disk, skip" branch. Pass 2 is deterministic, so
  rewriting is writing the same bytes again.
* The frozen competition's experiment-q patch no longer skips files the writer skipped, and a
  write failure now lands in the same reported list as a patch failure.
* `PatchPass2ProteinQvalues` lost `if (!File.Exists) continue` ("legitimately has no 2nd-pass
  sidecar"). Absent and unusable are one reported fault.

**ORDERING TRAP, found before it bit.** On a resume the entries hold pass-1 values while the
on-disk sidecar holds a previous run's pass-2 ones, and the write block runs BEFORE the reload.
An unconditional rewrite there would have downgraded good output. Fixed by ordering, not by a
condition: `ReloadPass2Sidecars(..., "pre-write")` runs when this run did not recompute, so the
rewrite puts the same bytes back. mode2 + mode4 are the legs that prove it.

The ONE surviving skip is `--task ModelDiagnostics`, which creates no absence (it runs over a
completed run) and whose mtime side-effect mode 7 exists to catch. It now LOGS its count rather
than leaving an unexplained gap between the file count and the write count.

### Gates - the harness half of the same ambiguity

The producers were only half of it. Three gates had been taught to accept absence, which is how
the design survived review:

* **regression mode 1c** skipped when it found no 2nd-pass sidecars ("Stage 6 rescored
  nothing"), so a run that wrote NOTHING reported SKIPPED rather than red. Now asserts the real
  invariant: `$pass2Sidecars.Count -ne $inputs.Mzmls.Count` is a hard failure.
* **regression HPC phase 4 staging** had `if (Test-Path $pass2) { Copy-Item ... }`. Dead code -
  `--task PerFileRescoring` sets `NoJoin`, which excludes `SecondPassFdrTask`, so phase 3 never
  writes one; two comments claimed it did. Worse than dead: had it fired it would have handed
  phase 4 a current sidecar, phase 4 would have skipped computing its own, and mode 3 would have
  become a test of a file copy.
* **`Test-Snapshot.ps1` had FOUR `symmetric absence -> PASS` branches**, including one over
  `.2nd-pass.fdr_scores.bin` itself. All removed. That rule and the C# consensus-dump elision
  propped each other up: the writer skipped because the comparator complained, and the
  comparator accepted because the writer skipped.

### The consensus dump, and the decision that started this

`Stage6Planner` fired `cs_stage6_consensus.tsv` only on `consensus.Count > 0`, from
`TODO-20260508_osprey_sharp_audit.md` item 3. Now unconditional (header-only when empty), like
the reconciliation dump beside it. Checked before changing it: **no live cross-impl gate
compares this dump** - `Compare-EndToEnd-Crossimpl.ps1` does not, only the archived
`Compare/archive/Test-Regression*.ps1` did - and its one live consumer, `Test-Snapshot`, is
same-impl. The Rust-elision justification no longer applies.

That completed TODO now carries a SUPERSEDED note at item 3, because the wrong decision was
recorded as a fix and every later session reading it found the ambiguity endorsed.

### `--task ModelDiagnostics` was NOT read-only (found 2026-08-27 by Brendan's question)

Brendan asked whether that mode "may or may not write files that impact the 4-task
processing pipeline". It may. `SecondPassFdrTask.Run` calls `UpgradeReconciledParquets`
BEFORE every `DiagnosticsOnly` check in the method, and the upgrader had no guard of its own:

```csharp
if (UpgradeReconciledParquets(perFileEntries, perFileParquetPaths, libraryById, ctx))
    return StopAfterUpgrade(ctx);
```

On any directory whose reconciled parquets predate the survivors-subset format
(`osprey.reconciled != RECONCILED_SURVIVORS`), a diagnostics regeneration **rewrote every one
of them in place** via `File.Replace` - the 266 -> 47 GB conversion. And because the upgrade
returns true, `Run` then took `StopAfterUpgrade` and exited, so the run **also never produced
the report it was asked for**. The mode wrote what it promised not to and skipped what it
promised to.

Every other writer in that method was already guarded (blib, sidecars, protein-q patch, the
two report writers) and `Outputs()` returns nothing, so no validity sidecars are stamped. **The
upgrader is THIS PR's own bug** - introduced by `1e282f8a29` (2026-08-26, branch-only), so it
never shipped. `StopAfterUpgrade`'s message also stopped naming `--task SecondPassFDR`
specifically and now mentions the report.

**Resolution: BLOCK, not work around** (Brendan). `--task ModelDiagnostics` now REFUSES a
directory holding pre-survivor-subset reconciled parquets, naming the stale files and telling
the operator to re-run the analysis. `StaleReconciledParquets` is shared with the upgrader so
the refusal and the rewrite cannot drift on what "stale" means.

The tempting alternative was to skip the upgrade and produce the report anyway, because a
pre-#4486 parquet is full-shape and row-parallel - row position IS the Stage 4 ordinal - so the
report would have been correct. **That is the trap**: *"the true danger of the 'well, it works,
so might as well leave it enabled' call. If you want it to be guaranteed to stay working, then
you need to include it in your tests. So, while it seems free at that moment, it actually has a
non-zero cost for something that isn't important."* Reading old parquets is deliberately NOT
part of this mode's contract, so there is no second read path to test and keep working. The
code comment states the decision rather than explaining that the old path would have worked -
such a comment is an invitation to re-enable it.

**Why no gate caught it - worth keeping.** regression **mode 7** is exactly the right gate:
it fingerprints the run dir, re-enters with `--task ModelDiagnostics`, and fails on
*"regeneration touched an artifact other than the report"*. Two reasons it stayed green:

1. it cannot reach the condition - the harness's straight-through run always writes
   CURRENT-format reconciled parquets, so the upgrade is a no-op there; and
2. **mode 7 does not run on Stellar at all.** It is guarded on the dataset spec's
   `ModelDiagnostics` flag, which `Stellar` does not carry. Every `-Dataset Stellar` gate in
   this session - seven of them - exercised ZERO `DiagnosticsOnly` paths.

So a Stellar-only gate is not sufficient for a change that touches `DiagnosticsOnly`. Use
`-Dataset All` for those.

## ARTIFACT-LAYOUT FOLLOW-ONS, from Brendan's questions (2026-08-27)

Not for this PR - each changes what an earlier stage writes and wants its own byte-identity
gate - but bigger than anything left in it.

### The scalar sidecars are now the LARGEST artifact class

The 82% reconciled-parquet reduction inverted the ratio:

| artifact, 257-file CHS | size |
|---|---|
| 1st-pass `fdr_scores.bin` (all runs) | **52.3 GB** (768.5 M x 68 B) |
| reconciled parquet | **47.4 GB** (was 266.2) |
| 2nd-pass `fdr_scores.bin` (all runs) | 9.3 GB (137.0 M x 68 B) |

They were 20% of the parquet before the subset change and are 110% after it.

### `fdr_scores.bin` is uncompressed fixed-width, and the reason for that is expiring

32-byte header + N x 68-byte little-endian records, written with `BinaryWriter.Write(double)`.
No compression, and it CANNOT be compressed without a format change: readers validate
`fileLen == HeaderLength + count * RecordLength` as the integrity check. The format exists as a
**byte-parity mirror of Rust's** `write_fdr_scores_sidecar` (`OSPREY_CROSS_IMPL_FDR_SIDECAR_OUT`
hook). With Rust discontinued and the parity gate heading for removal, that constraint goes.
Checked and NOT an objection: the two-phase column patches stream source -> temp and promote
via `FileSaver`, so they never seek to fixed offsets and lose nothing to a different format.

### Split the sidecar BY SCOPE - the real win (Brendan)

Four of the eight doubles are per-entry constants, not per-run values: experiment precursor q,
experiment peptide q, protein q, and the experiment aggregate. `entry_id` is unique per file
(`DeduplicatePairs`), so they are stored once per run, in every run the precursor appears in -
O(files x entries) for data that is O(distinct entries).

**Parquet compression does NOT fix this** (a wrong claim I made and Brendan corrected): parquet
encodes WITHIN a file, and the replication is ACROSS the 257 per-run files. Within one file
experiment precursor q and the aggregate appear exactly once each - nothing to encode. Only the
peptide- and protein-level columns repeat intra-file, from multi-charge peptides and
multi-precursor proteins.

| file | contents | 257 files |
|---|---|---|
| per-run `fdr_scores.bin` | entry_id, score, run precursor q, run peptide q, PEP | 36 B x 768.5 M = **27.7 GB** |
| ONE experiment-wide `fdr_scores.bin` | entry_id, experiment precursor/peptide q, protein q, aggregate | 36 B x <=12.4 M = **~0.44 GB** |

~46% off the total, and the experiment-scope half stops scaling with file count.

### Consequence: move the run-scope work back into PerFileRescoring

With the split, `transfer` reads the RUN-level file in PerFileRescoring and only the
EXPERIMENT-wide file in SecondPassFDR. Checked: everything `TransferPerRunQ` needs is already
in a phase-3 worker - the frozen 1st-pass model rides the phase2 -> phase3 -> phase4 relay, the
reconciled features are computed there, and the file's own 1st-pass sidecar is staged. It sits
in Stage 7 by history, not structure. Then Stage 7 reads ~0.44 GB + the reconciled parquet and
nothing per-run.

Generalizes, though this part needs real thought rather than assertion: the run-level half of
`protein-compact`'s competition is also per-file work, and its stratum is a whole-run product
that already exists BEFORE Stage 6. If that moved too, Stage 7 would keep only what genuinely
needs every run at once - the experiment-scope roll-up, protein FDR, and the blib.

### The scope split retires BOTH patch passes - do not "patch back per file" (Brendan)

An earlier sketch in this file had `PerFileRescoring` write the run-scope columns and the join
PATCH the experiment-scope ones back into every per-run file. **Wrong shape**, for three
reasons, and the third is the one that decides it:

1. A placeholder column is a **written-but-not-finished** artifact - a record whose experiment
   columns are placeholders cannot be told from one whose patch failed. That is the same
   ambiguity we removed from these files' EXISTENCE, one level down, inside them.
2. It gives one artifact **two writers in two tasks**, which the resume model does not want -
   each task owns its outputs. It is why the patch has to re-validate the header at all.
3. It keeps the ~47% duplication permanently AND pays to rewrite it. The rewrite is expensive
   BECAUSE of the duplication: streaming 68 B records to update 32 B of per-entry constants
   that should not be in a per-run file.

**Both existing patch passes are full rewrites (`FileSaver` source -> temp -> replace) running
in JOIN stages**, and exist only because experiment-scope values live in per-run files:

| join-stage I/O to back-fill experiment-scope values | 257 files |
|---|---|
| `FirstPassFDR` rewrites every 1st-pass sidecar (`PatchProteinQvalues`) | 52.3 GB read + 52.3 GB written |
| `SecondPassFDR` rewrites every 2nd-pass sidecar (`PatchPass2ProteinQvalues`) | 9.3 + 9.3 GB |
| **total, serial, in the bottleneck** | **~123 GB** |

Storage, for comparison: 61.6 GB today vs **33.5 GB** split (1st-pass 27.7 + 0.44,
2nd-pass 4.9 + 0.44). So the split saves ~28 GB stored and ~123 GB of un-parallelizable I/O.

**The rule: experiment-scope values never live inside per-run files.** Four artifacts, each
with exactly ONE writer:

| file | scope | writer |
|---|---|---|
| `<stem>.1st-pass.fdr_scores.bin` | entry_id, score, run precursor q, run peptide q, PEP | `PerFileScoring` |
| `experiment.1st-pass.fdr_scores.bin` | entry_id, exp precursor/peptide q, protein q, aggregate | `FirstPassFDR` |
| `<stem>.2nd-pass.fdr_scores.bin` | same run-scope set | `PerFileRescoring` |
| `experiment.2nd-pass.fdr_scores.bin` | same experiment-scope set | `SecondPassFDR` |

`PatchProteinQvalues` and the `PatchExperimentValues` added on this branch both DISAPPEAR - the
join writes its own file instead of editing everyone else's. **`PatchExperimentValues` is
therefore transitional, not the intended end state**: it is the right shape while the per-run
file is the only place those values can go, and the wrong one after the split.

To check, not assume: the compaction protein-rescue gate reads `experiment_protein_qvalue`
during per-file hydration, so an HPC worker needs the experiment-wide file staged to it. The
pattern exists - the 1st-pass model sidecar is already relayed to every phase-3 worker.

### Also still open from the same thread

* Brendan's earlier idea: write the run-scope scalars as COLUMNS in the reconciled parquet
  during PerFileRescoring, so Stage 7 opens one file instead of two. Qualifications: serves
  `protein-compact` only (`transfer`/`transfer-compete` need pre-compaction rows); removes a
  READ, not a write (the compaction protein-rescue gate reads the 1st-pass sidecar
  pre-compaction, and HPC workers rehydrate from it); and the writer must emit PASS-1
  (pre-`ResetScores`) values.
* The frozen path streams the 1st-pass sidecar **2-3 times per file** (seeder, `ReadScalars`,
  `StashOffStratumPass1ExperimentQ`). All three want fields off the same records and the
  apparent ordering dependency is not real - `wanted` tests `ov != scs[i]` where `ov` comes
  from `fileScores`, which is built BEFORE the read - so one pass can do all three. 3x -> 1x on
  the largest artifact in the run.
* Drop the five blob columns: 54% of the reconciled artifact, never read back out of a
  reconciled parquet. 47 -> ~22 GB.

## SESSION END 2026-08-27 evening - where the work stands

**Branch** `Skyline/work/20260827_osprey_stage7_stream_increment` in `C:\proj\pwiz-work1`,
**14 commits ahead of the PR branch, NOT pushed.** PR [#4621](https://github.com/ProteoWizard/pwiz/pull/4621)
still OPEN and HELD at `2978de7b37`; the target is still ONE PR delivering memory reduction and
streaming. Working tree clean.

| commit | what | gate |
|---|---|---|
| `680bff65ac` | frozen second pass streams one file at a time | Stellar 10/10 |
| `782a92211f` | blib phase stopped holding the survivor pool | Stellar 10/10 |
| `f84dc1d458` | protein FDR and reports off the pool | Stellar 10/10 |
| `b9075eb99a` | stopped writing the second-pass files conditionally | **`-Dataset All` 56/56** |

**THE MEMORY BAR IS NOT MET AND NOTHING HAS MOVED IT.** `stage7-pool` is still 40.23 GB,
because the pool is still built until the flip. Every projected figure in this file is
arithmetic from the code, NOT a measurement. The 257-file run has not been re-run this session.

### Steps 1-4 of the plan are done; step 5 is the whole remainder

Step 4 (`OspreyReportWriter`) was **never the risk this file claimed** - its per-replicate loop
already worked one file at a time and the experiment row is an O(distinct) fold. That standing
note is retracted above.

### Read these before touching the flip

1. **"Step 5 - THE FLIP: what it actually needs"** - `MaterializeOneFile` overlays the
   **1st-pass** sidecar, so a re-materialized file carries pass-1 q-values. That overlay has to
   move into the materialization, and it has a PHASE problem: before pass 2 a file should look
   pass-1 (that is what the resident pool holds there), and on a resume the sidecar is already
   current from an earlier run, so "current" is not "this run wrote it".
2. **The two wrong turns recorded as wrong**, because both are the natural-seeming answer and a
   fresh session will reach for them: parquet cannot compress replication that lives ACROSS
   separate per-run files, and "patch the experiment columns back into every run file" is the
   wrong shape.
3. **`PatchExperimentValues` (added this session) is TRANSITIONAL, not the design.** It is
   correct while the per-run file is the only place those values can go, and it disappears with
   the scope split. Do not preserve it as intent.

### Sequence for the next sessions

1. **The flip**, folding in the 1st-pass sidecar read fusion (3x -> 1x per file) - same method,
   so gating them together avoids re-gating `ComputePass2TransferCompeteFull` twice.
2. **The 257-file run** - the acceptance test, ~34 min, and the number this PR exists to
   produce. Relaunch via `ai/.tmp/sessions/20260826-night-stage7/launch-measure-scoreindex.ps1`.
3. Then the architecture, in the order it was worked out: move run-scope work into
   `PerFileRescoring` (start with `transfer`, every input already staged), then the scope split.

### A judgement call left open for Brendan

The PR is now four commits including a bug fix and three gate hardenings, and still shows no
memory reduction. **`b9075eb99a` stands alone and is fully gated** - if the flip runs long,
splitting it into its own PR is reasonable.

### Gate lesson worth keeping

`-Dataset Stellar` does NOT cover `DiagnosticsOnly`: `mode7` is guarded on the dataset spec's
`ModelDiagnostics` flag, which Stellar does not carry. Seven Stellar gates this session
exercised zero of those paths. Use `-Dataset All` for anything touching that mode.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260827_osprey_stage7_stream_increment.md` before starting work.

## THE FLIP IS THE WRONG STEP 5 - it costs ~10 whole-run walks (2026-08-27 evening)

`RescoredEntries.Files()` re-materializes on EVERY call - it yields from the resident buffer
only while `IsMaterialized` is true (`PipelineByproducts.cs:363`). Today exactly one consumer
builds the pool, so all seven `Files()` walks are free. **Remove that build and each one
becomes a full re-read.** The step-5 plan, and the handoff that carried it, treat the flip as
the last mechanical piece; it is not.

Walks left on the default protein-compact path after the flip:

| # | walk | site |
|---|---|---|
| 1 | `BuildRetainedBaseIds` (fragment release) | `SecondPassFdrTask.cs:449` |
| 2 | survivor entry_id fold | `Pass2FdrSidecar.cs:1060` |
| 3-4 | the competition's `ReadFile` + its step-4 finish | `Pass2FdrSidecar.cs:1256` |
| 5 | `ProteinFdrEngine.RunSecondPass` | `SecondPassFdrTask.cs:482` |
| 6 | `OspreyReportWriter` per-replicate | `OspreyReportWriter.cs:266` |
| 7 | experiment-q clamp fold | `SecondPassFdrTask.cs:327` |
| 8-10 | `ComputePassingPeptides` -> `ComputePassingPrecursors` -> `CollectPassingEntries` | `SecondPassFdrTask.cs:752/755/768` |

One materialization is `FirstPassSurvivorLoader.Load` per file: read the reconciled parquet
(47.07 GB across 257 files) + overlay the WHOLE 1st-pass sidecar (52.3 GB) + allocate 137 M
`FdrEntry` + sort. **~100 GB of reads per walk**, against a Stage 7 that runs 36 min end to end
today. Ten walks is not a memory win, it is a wall-time catastrophe.

Fusion cannot rescue it either: the dependency chain (clamp -> passing peptides -> passing
precursors -> passing entries) forces 3-4 passes at minimum, each still ~100 GB.

The seed of this was already in the file, at `Pass2FdrSidecar.cs:1013` - *"Fusing this fold
with the other converted consumers' walks is a separate, run-wide question - it is free until
nothing builds the buffer."* It is now the whole question.

## DECIDED: shrink the pool, do not remove it (Brendan, 2026-08-27)

Back to the 2026-08-27 morning call - *"Stage 7 should use Stage 5's machinery"* - with the
numbers this time. ONE materialization walk converts each file's `FdrEntry` list into lean rows
and drops the fat objects; the other nine folds then walk a resident lean set instead of
re-reading 100 GB apiece. I/O stays at one walk. Steps 1-4 are not wasted: the streamed
consumers are exactly what lets the conversion pass consume the fat pool one file at a time.

### The lean row, from an audit of all ten consumers

The TODO's earlier ~40 B / 5.5 GB projection was `FdrProjection`'s 32 B shape. **That struct
cannot do Stage 7's job** - it carries no q-values, no RTs and no area. Audited against
`FdrEntry`'s 24 fields, what Stage 7 actually reads after the competition is:

| field | B | read by |
|---|---|---|
| `EntryId` | 4 | fragment release, blib RefSpectra, fdrbench |
| `PeptideId` (int into a ~40 K intern table) | 4 | replaces `ModifiedSequence` - every gate |
| `Charge`, `IsDecoy` | 2 | every gate |
| `Score` | 8 | protein-FDR best-per-peptide, fdrbench, model-diagnostics |
| `RunPrecursorQvalue`, `RunPeptideQvalue` | 16 | `EffectiveRunQvalue(Both)`, protein-FDR gate |
| `ExperimentPrecursorQvalue`, `ExperimentPeptideQvalue` | 16 | peptide/precursor gates, clamp, blib |
| `ApexRt` / `StartRt` / `EndRt` | 24 | `PassingObservation` + RefSpectra |
| `BoundsArea` | 8 | RefSpectra |
| | **82 -> 88 padded** | |

137,034,004 x 88 B = **12.1 GB**; + the 4.19 GB library = Stage 7 live **~16.3 GB**, against
37.87 GB today. FirstPassFDR's 53.7 GB private becomes the run's peak, which is the bar.

**NOT the 5.5 GB this file projected.** Every figure here is arithmetic from the code, like
every other projection in this file; the only measurement remains `stage7-pool` = 40.23 GB.

**Rejected variant** (offered, and Brendan chose against it): defer the four spectral doubles -
`ApexRt`/`StartRt`/`EndRt`/`BoundsArea` - to a targeted 4-column re-read over the 11.7 M
PASSING observations only. That gives a 56 B row and a 7.7 GB pool, but buys the extra headroom
with a second read path that then has to be kept working and tested forever. Keeping RT/area
resident is the simplest correct shape and already clears the bar.

**Not in the row**, dropped with each file inside the competition: `ParquetIndex`/score_index,
`ScanNumber`, `Pep`, `ExperimentAggregateScore`, `ExperimentProteinQvalue`, `Features[21]`, and
the five blob arrays. Those are exactly what the 2nd-pass sidecar already carries to disk - the
conclusion of `Pass2FdrSidecar.cs:1319`'s *"the sidecar, not the entry, is what carries this
pass's results forward"*.

### Two things to settle in the build, not asserted here

1. The experiment-q clamp MUTATES two q-values in place, so the row must be a mutable struct
   written back by index (`CollectionsMarshal.AsSpan`), not a readonly one like `FdrProjection`.
2. `--model-diagnostics` pass-2 feature histograms may still want `FdrEntry.Features`. That
   mode already forces the resident 2nd pass, so it can keep a fat path - but confirm before
   assuming it.

## 1st-pass sidecar read fusion: 3 traversals -> 1 (2026-08-27 evening)

Landed first, because it is worth doing under any direction. The frozen competition read each
file's `.1st-pass.fdr_scores.bin` three times, all over the same 68-byte records:

| was | now |
|---|---|
| `seeder.Seed` -> `ReadRecords` (whole file) | one `ReadScalars` at the top of `ReadFile` |
| `FdrScoresSidecar.ReadScalars` (whole file) | same call - it is the one that produces `eids`/`scs` |
| `StashOffStratumPass1ExperimentQ` -> `ReadRecords` (whole file) | reads the records already in hand |

* **`FdrScoresSidecar.ReadScalars` gained an overload** that also decodes the FULL record for a
  caller-selected subset, into a caller-owned list. The subset is the file's survivors (~533 K
  of ~2.99 M records on a CHS file), so the other ~82% still cost only their entry_id and score
  - decoding seven trailing doubles to discard them was what the separate passes paid for.
* **`Pass1ScalarSeeder` gained `Apply`**, the seed with no I/O, for a caller that has already
  read the records. It needs none of `Seed`'s stage-then-apply discard contract, because a
  caller holding decoded records has already had a clean read. `Seed` stays for
  `RestorePass1Scalars`; both funnel through one `ApplyRecord`.
* **The stash walks the survivor records** instead of scanning the full-population arrays to
  build a `wanted` set and then re-reading the file to fetch its two q-values. The apparent
  ordering dependency was not one: the test is against `fileScores`, which is built from the
  parquet features, not from the sidecar.

**One deliberate behaviour change, in a configuration that is broken today.** The fused read
uses `sidecarByKey[fileKey]` - the path the validation loop already checked with
`IsCurrentFormat` - where `Seed` used `FdrScoresSidecar.Pass1Path(writer.InputFor(fileKey))`.
Both resolve through `ArtifactPaths.ResolveOutputDir`, so they name the same file in every
configuration this method accepts. Where they could ever diverge, the old code warned
(`_unreadable`) and proceeded with reset defaults - which `LogSummary` itself calls "treat this
run's protein-level numbers as unreliable" - and the new code reads the validated file instead.
The refusal stays where the contract puts it: before any survivor is mutated.

Gate: build clean, **596/596**, zero inspection warnings, and **`regression.ps1 -Dataset
Stellar` 10/10** - modes 1, 1b, 1c, 2, 3, 4, 5, 6 all green with an identical 23,662,592-byte
blib. Committed `a700c1226a`.

### Sequence from here

1. The lean-row conversion, behind a flag defaulting OFF, A/B'd against the resident path for
   byte-identity, then flip the default - the way `OSPREY_FDR_PROJECTION` and
   `OSPREY_STAGE6_STREAM_SURVIVORS` were introduced.
2. The 257-file run, the acceptance test, ~36 min.
3. Then the architecture, in the order already worked out: move run-scope work into
   `PerFileRescoring` (start with `transfer`), then the scope split.

**Retract "Step 5 - THE FLIP" as the plan.** Its q-value overlay analysis still stands and the
lean-row conversion needs it - a converted file's rows must carry pass-2 values - but "stop
reading `rescored.Value`" is not the shape.

## The lean-row audit closed cleanly - and where the rows get filled (2026-08-27 evening)

Two things the decision left open are now answered from the code, not assumed.

### `--model-diagnostics` does NOT need `FdrEntry.Features`

Its six pass-2 cards walk the pool, but every `.Features` reference in
`ModelDiagnosticsData` is `contributions.Features` - the trained model's feature LIST - not a
per-entry vector (`ModelDiagnosticsData.cs:575,830`,
`ModelDiagnosticsData.Accumulator.cs:324`). So the mode runs on lean rows like everything else,
and there is no fat path to keep for it. `--fdrbench` likewise: `Score`, `ModifiedSequence`,
`Charge`, `EntryId`, `IsDecoy` and the two `Effective*Qvalue` accessors, all in the row.

Swept every `.Features` / `.CwtCandidates` / `.FragmentMzs` / `.FragmentIntensities` /
`.ReferenceXicRts` / `.ReferenceXicIntensities` / `.BoundsSnr` / `.CoelutionSum` /
`.ScanNumber` / `.ParquetIndex` read in `Osprey.Tasks` and `Osprey.FDR`. Everything that
survives the filter is either pre-Stage-7, inside the competition's own per-file cycle
(`Pass2FdrSidecar.cs:1352,1840,1910-1965`), or in `ComputePass2Resident` /
`ScoreWithFrozenModel` - all of which run BEFORE a lean row exists and drop the file after.

**Exactly one post-competition consumer reads a field outside the row**:
`UpgradeReconciledParquets` builds `keepIdentities` from `(EntryId, Charge, ScanNumber)`
(`SecondPassFdrTask.cs:665`). That is the in-Stage-7 legacy converter, which
`--task CompactPerFileRescoring` (`55600ddbc0`) now supersedes. Two ways out, and it is a
capability question rather than a technical one:

* add `ScanNumber` to the row (+4 B, ~0.55 GB at 257 files), or
* **remove the in-Stage-7 upgrade** and have Stage 7 REFUSE a stale-format directory in every
  mode, naming `--task CompactPerFileRescoring` - which is exactly what `--task
  ModelDiagnostics` was already changed to do on this branch, for the same reason.

The second is the shape this branch already chose once ("BLOCK, not work around"), and it
deletes a read path rather than paying to keep one working. It needs Brendan's sign-off because
it removes a capability, not because it is unclear.

### Interning `ModifiedSequence` is a large part of the win on its own

`SecondPassFdrTask.cs:925` already records that *"the parquet reader hands out a fresh instance
per row"*, which is why `CollectPassingEntries` canonicalizes. The resident pool does NOT
canonicalize: it holds **137 M separate string objects** where there are on the order of
thousands to millions of distinct sequences. At a .NET string's `26 + 2 x len` bytes, a 20-30
character modified sequence is ~66-86 B, so the pool carries roughly **9-12 GB of strings
alone** out of its 37.87 GB. Replacing the reference with a `PeptideId` int removes that before
the struct packing is counted. Arithmetic from the code, like everything else here.

### Where the two halves of a row get filled - no extra materialization

The competition already makes exactly ONE materialization per file, and its step 4 works over
the SIDECARS, not the entries (`"the file's entries have been dropped by now"`). So:

| phase | fills | why there |
|---|---|---|
| `ApplyFileRunQ` (per file, during the stream) | `EntryId`, `PeptideId`, `Charge`, `IsDecoy`, RTs, `BoundsArea`, `Score`, both RUN q | the file is materialized and its score / run q are final at that point |
| step 4's per-file sidecar patch | both EXPERIMENT q | the competition producing them is not complete until every file has been read |

The step-4 fill needs a per-file entry_id -> row index map, built transiently for the file being
patched (~533 K entries) and dropped - NOT a run-wide (file, entry_id) map, which is the 3.8 GB
structure `ReadFile` already removed once.

**Scope**: this covers the DEFAULT frozen-competition arm. `ComputePass2Resident` stays on the
fat pool deliberately - it is the byte-identity oracle, and the convention this codebase uses
for a change like this is to leave a working oracle on the other side of the switch. The
`!recomputed` resume path runs no competition, so it builds its lean pool from one plain
per-file materialization plus the 2nd-pass sidecar overlay - one walk, the same as today's pool
build.

### net472 rules out `CollectionsMarshal` - the rows are ARRAYS, not lists

Correcting a design detail stated earlier in this session: the clamp mutates two q-values in
place, and `CollectionsMarshal.AsSpan` is .NET 5+ while Osprey multi-targets `net472;net8.0`
(`pwiz_tools/Osprey/Directory.Build.props:4`). Store each file's rows as a `LeanRow[]`, not a
`List<LeanRow>` - array element access yields a direct ref for a struct, so
`rows[i].ExperimentPrecursorQvalue = floor;` mutates in place on both frameworks with no
interop helper. The per-file survivor count is known at materialization, so an array is the
natural shape anyway.

### The gates must be GENERIC, not duplicated

`ComputePass2Resident` stays on the fat pool as the byte-identity oracle, so the SAME gate code
has to run over both row types - two implementations would leave the oracle comparing two
different pieces of code, which is the failure mode
[[feedback_shared_defect_hides_from_parity]] describes from the other direction. Write the
Stage 7 gates as `where T : IFdrRow`: the JIT specializes the struct instantiation with no
boxing, and the class instantiation shares the reference-type body. Default interface members
are NOT available (net472 has no runtime support), so `EffectiveRunQvalue` /
`EffectiveExperimentQvalue` become generic extension methods on the interface - one
implementation, both row types, both frameworks.

Scope of the churn: 102 `KeyValuePair<string, List<FdrEntry>>` occurrences across 20 files, but
most are Stages 1-6 and stay. The Stage 7 set is `LibraryFragmentRelease`, `ProteinFdrEngine` /
`ProteinFdr`'s second-pass accumulator, `OspreyReportWriter`, `SecondPassFdrTask`'s blib gates,
`PercolatorEngine`'s clamp fold/apply, `FdrBenchInputWriter` and `ModelDiagnosticsData`'s
pass-2 cards.

## DECIDED: go straight at the architecture, drop the lean-row pool (Brendan, 2026-08-27)

Brendan, mid-session: *"are you still planning on moving per-run FDR calculation for Pass 2 into
the PerFileRescoring task? So that SecondPassFDR becomes only about calculating the
experiment-wide q values and writing the BLIB?"*

That question retires the lean-row pool decided earlier the same evening, and it is right to.
Follow the architecture through and Stage 7 needs no per-observation pool at all:

* **experiment q and protein FDR** are folds over `entry_id` - O(distinct), not O(observations).
* **the blib gates** do walk all 137 M observations, but everything they read is either in the
  68-byte sidecar record (both q's) or reachable from `libraryById` by `entry_id`
  (`ModifiedSequence`, `IsDecoy`). No parquet read, no `FdrEntry`.
* **only the ~11.7 M PASSING observations** need RTs and area, from a narrow second pass over
  the reconciled parquet.

| | Stage 7 live |
|---|---|
| today | 37.87 + 4.19 library = **42 GB** |
| lean 88 B row (retired) | 12.1 + 4.19 = 16.3 GB |
| architecture | ~0.6 GB passing records + folds + 4.19 library = **~5-6 GB** |

Building a 12.1 GB resident pool of 137 M rows was an intermediate whose entire purpose the next
PR deletes. **Retract the lean-row conversion**; keep only `IFdrRow` and the gate
genericization, which the architecture needs anyway because the gates end up running over
sidecar-derived rows.

## The run-level half IS per-file work - established from the code, not asserted

`StreamingFdr.ComputeFullPopulationPrecursorFdrStreaming` (`:191-290`) computes the run-level q
from ONE file's arrays:

```
TargetDecoyCompetition.CompeteFromIndices(scores, labels, entryIds, allIdx, out wi, out ws, out wd);
PercolatorQValues.ComputeConservativeQvalues(ws, wd, q);
```

`scores`, `labels`, `entryIds` and `allIdx` are all that file's. Exactly three inputs are global,
and each is already a relayable artifact:

| global input | what it is | staged today? |
|---|---|---|
| the frozen 1st-pass model | Stage 5 product | YES - rides the phase2 -> phase3 -> phase4 relay |
| `stratumBaseIds` | whole-run, and exists BEFORE Stage 6 | YES - in the model sidecar |
| `survivorEntryIds` | union of per-file survivors, ~12.4 M x 4 B = ~50 MB | derivable from Stage 5 compaction |

What is genuinely JOIN work is `minRunQ` (the best-of-runs floor) and the per-`base_id`
`bestTarget` / `bestDecoy` folds - all O(distinct).

**The trap, named before it bites**: a file can WIN a competition for an `entry_id` that is not
one of ITS survivors but is a survivor in another file, and that win still has to reach
`minRunQ`. So a worker cannot substitute its own survivor list for the global one - it needs the
50 MB relay. Filtering locally would silently drop cross-file floor contributions and lower
experiment q for exactly the precursors that appear in many runs.

## Artifact layout confirmed, with one correction (Brendan, 2026-08-27)

*"immutable 2nd pass side-car files per run, and then an experiment-wide FDR side-car file
(maybe the same base name as the BLIB?)"* - yes, and the same shape for the 1st pass, which is
where most of the win is.

**CORRECTION to the table earlier in this file**: the experiment-scope artifact takes the
**BLIB's base name**, not a literal `experiment.` prefix. A fixed prefix collides the moment two
analyses share an output directory, which is what the run layout does; `<blib-stem>.<pass>.fdr_scores.bin`
beside the blib names the file for the analysis that produced it. `config.OutputBlib` is a run
parameter every node already has, so a `--task SecondPassFDR` worker locates it with no new
plumbing.

| | today | split | |
|---|---|---|---|
| 1st-pass | 52.3 GB | 27.7 + 0.44 | **-46%** |
| 2nd-pass | 9.3 GB | 4.9 + 0.44 | -43% |
| total | 61.6 GB | **33.5 GB** | |

Both records are 36 B (entry_id + four doubles) against the fused 68 B, so per FILE it is not
quite half - the halving comes from the experiment-scope columns being written once per
EXPERIMENT instead of once per run.

**Immutability is what pays twice.** Both patch passes exist only to push experiment-scope
values into per-run files: `PatchProteinQvalues` rewrites all 52.3 GB of 1st-pass sidecars in
FirstPassFDR's join, `PatchPass2ProteinQvalues` another 18.6 GB in SecondPassFDR - ~123 GB of
serial, un-parallelizable rewrite in the two stages that ARE the bottleneck. Both disappear, and
a per-run file becomes write-once, which removes the written-but-not-finished ambiguity one
level down from the one `b9075eb99a` removed.

## `IFdrRow` landed - the one piece that survives the pivot

`Osprey.Core/IFdrRow.cs`: the thirteen members Stage 7 reads off a survivor after the second
pass, plus `FdrRowExtensions.EffectiveRunQvalue<T>` / `EffectiveExperimentQvalue<T>`.
`FdrEntry` implements it and its two instance selectors were REMOVED in favour of the generic
extensions - one implementation of the rule, and every call site compiles unchanged because an
extension method is called with the same syntax.

* **Generic, not `IFdrRow`-typed parameters.** A constraint compiles to a constrained call that
  neither boxes nor allocates; taking the interface directly would box every one of 137 M rows.
* **Extension methods, not default interface members** - net472 has no runtime support for those
  (`Directory.Build.props:4` targets `net472;net8.0`).
* The two experiment q-values are settable because the pre-blib re-clamp raises them in place.
  For a struct that means the caller must hold an ADDRESSABLE element - an array element or a
  `ref` local - since an `IReadOnlyList` indexer hands back a copy and the write is discarded.

Five inspection warnings came from `<see cref="FdrEntry.EffectiveRunQvalue"/>` doc references in
`FdrProjectionOutput`, `ModelDiagnosticsData` and `PeakCoAssignmentSource` that no longer
resolved; retargeted to `FdrRowExtensions`. Gate: build clean, 596/596, zero inspection
warnings.

### Sequence from here

1. Split the competition into a per-file half and a join fold **in place** in Stage 7 - the
   three global inputs above passed in explicitly, byte-identical, gateable. This is what makes
   the move mechanical rather than a rewrite.
2. Move the per-file half into `PerFileRescoreTask`, relaying model + stratum + survivor ids.
3. Split the sidecars by scope (1st pass first - it is 85% of the bytes), retiring both patch
   passes.
4. Stage 7's remaining consumers stream from the sidecars + library; the pool never exists.

## NIGHT SESSION 2026-08-27/28 - the move is fully decomposed, and needs NO new global relay

### The 257-file Stage 5-7 run is the night's headline

Launched 21:42:44, pid 25996, exe `_bin\26.1.1.239-stage57-20260827`, out dir
`chs-257files-libdecoy-r1.0-protein-compact-s57base257`, launcher
`ai/.tmp/sessions/20260827-stage7-leanrow/launch-stage57-257.ps1`.

**This is the first Stage 5-7 measurement at 257 files on this branch.** Every prior 257-file
number came from `--task SecondPassFDR` and is therefore blind to Stage 6 - which is precisely
the stage the architecture moves work INTO. The baseline `p0059_0060_0061` ran this exact shape
in 10h14m.

The rig, for the record, because it answers "how do we test this" durably:

* **`-LinkFrom` with NO `-Task`.** `$STAGE_ARTIFACTS`' `$upTo` defaults to `FirstPassFDR`, so it
  hard-links only the Stage 1-4 artifacts (`.scores.parquet`, `.calibration.json` + their task
  sidecars - 1028 files, 0 missing), then the pipeline runs normally with `-i` and per-file
  resume skips Stages 1-4 because their outputs are present and valid. Confirmed by
  `[TASK] FirstPassFDR:starting` as the first task line.
* **`-Task FirstPassFDR` would be WRONG** - it is a single-stage HPC exit point, not "start here
  and continue".
* **No conversion step is needed**, and none should be invented.
* The source `.raw` are GONE; only the 446 `.spectra.bin` remain. That is supported and
  deliberate: `OspreyDatasetRun` synthesizes the path the source WOULD have had, because Osprey
  never stats it and `SpectraCache` resolves from the input's DIRECTORY. Brendan: *"Keeping the
  .raw files is no longer necessary once you have spectra.bin"*. Stage 6 REQUIRES the cache and
  has no mzML fallback (`PerFileRescoreTask.cs:934-937`).
* `OSPREY_VERSION_OVERRIDE=26.1.1.233` and `-LibraryDir target+decoy+entrapment-20260817` are
  both mandatory - the first or the resume silently re-runs Stages 1-4 for hours, the second or
  the run uses a different build of the same library file name (6,324,700 vs 6,175,389 entries).
  Verified in the log: library loaded 6,175,389.

**Oracle**: 5,079 protein groups | 45,724 library spectra | 11,745,026 passing entries |
blib **725,458,944** bytes. NOTE the Stage-7-only reruns gave **725,467,136** - an 8,192-byte
SQLite page difference between the two RIGS that predates this branch. Compare like with like,
and treat the three counts as the robust oracle.

### The move needs NO new global relay - correcting this file's own earlier claim

The section above says a `PerFileRescoring` worker needs the global survivor entry-id set
relayed to it (~50 MB), because a file can win a competition for an `entry_id` that is not one
of ITS survivors but is a survivor elsewhere, and that win must still reach `minRunQ`.

**The premise is right and the conclusion is wrong.** The filter exists only to decide what goes
into `minRunQ`, which is a JOIN fold. So:

* the worker emits run q for **every winner**, filtering nothing;
* the join rebuilds the survivor id set by unioning `entry_id` over the run-scope 2nd-pass
  sidecars **it already has to read**, and filters there.

That leaves the worker's global inputs as the frozen 1st-pass model and `stratumBaseIds` - and
**both already ride the phase2 -> phase3 -> phase4 relay** (they share the model sidecar;
`Pass2FdrSidecar.ComputeAndPersist` reloads them together via `FirstPassModelIO.LoadFromAny`).
Nothing new has to be staged.

### The frozen scoring is FREE in the worker

`PerFileRescoreTask.cs:1058`, at `WriteReconciledAndStamp`, `fdrEntries` still holds this file's
post-rescore entries with `Features` populated - that is the writer's own "this row was
rescored" sentinel, and `ReleaseRescoredPayload` runs only AFTER the write. So the worker scores
with the frozen model straight from memory.

Stage 7 today re-reads the reconciled parquet for exactly those features
(`LoadReconciledFeaturesByScoreIndex`). The move deletes that read, per file, across the cohort.

### The contribution artifact, bounded by the STRATUM not the population

Measured, not estimated: the 257-file CHS run logs
`competition CONSTRAINED to the 508769-base_id protein stratum`.

| field | B |
|---|---|
| `base_id` | 4 |
| best TARGET score | 8 |
| best DECOY score | 8 |
| winner run q | 8 |
| presence flags | 4 |
| | **32** |

508,769 x 32 B = **16.3 MB/file**, **<=4.2 GB at 257 files**, and that is the hard ceiling - a
real file observes only a fraction of the stratum. Against ~28 GB of storage and ~123 GB of
join-stage rewrite that the scope split removes, this is not an argument against the move.

`entry_id` need NOT be stored: a target's `entry_id` IS its `base_id`
(`labels[i] = (eid & ~BASE_ID_MASK) != 0u`, so a target has no bits outside the mask) and a
decoy's is `base_id | ~BASE_ID_MASK` - which is exactly how the join already reconstructs winner
ids at `StreamingFdr.cs:392`.

**It only gets expensive under `transfer-compete`**, which is unstratified, so its contribution
is bounded by the file's whole pre-compaction population instead. protein-compact is the
default; transfer-compete would want measuring before it is promised anything.

### Enabling commits landed tonight, each gated Stellar 10/10

| commit | what |
|---|---|
| `a700c1226a` | frozen 2nd pass reads each 1st-pass sidecar ONCE, not three times |
| `f08059f824` | `IFdrRow` + generic q-value selectors - the contract Stage 7 reads a row through |
| `f7a6e6d103` | `StreamingFdr` competition split into `CompeteOneFile` + `FoldFileContribution` |

`f7a6e6d103` is the one that matters for the move: `CompeteOneFile`'s only inputs beyond one
file's arrays are the frozen-model survivor scores, the survivor id set and the stratum - and
per the correction above, two of those are already relayed and the third moves to the join.
Relocating it is now a relocation, not a rewrite.

## CORRECTION (night session, 22:05): the frozen scoring is NOT free in the worker

Earlier tonight this file recorded that `PerFileRescoreTask` can score with the frozen model
straight from memory at `WriteReconciledAndStamp`, because `fdrEntries` still carries
`Features`. **That is true only for the RESCORED subset.**

`ReconciledParquetWriter.cs:147-150` states the rule: re-scored rows are detected by
`FdrEntry.Features != null`, and *"hydration's LoadFdrStubsFromParquet does NOT populate
Features, so an unchanged post-compaction stub (Features == null) is skipped, leaving its
original parquet row (Features + CwtCandidates + the binary blob columns) to stream through"*.

So an UNCHANGED survivor has no features in the worker's memory. Stage 7 scores every survivor
present in the reconciled parquet, and the rescored fraction is small - Stellar mode 1c reports
70,614 of 996,439 shared records moved, about 7%. The worker would be missing ~93% of what
Stage 7 needs.

### What this does to phase 1

The "publish flat per-file frozen-score arrays, no new artifact" plan does NOT work as written.
Three options, and the first is the real one:

1. **Score inside the parquet STREAM** the worker already makes in `WriteReconciledAndStamp`.
   Every row - rescored or streamed-through - passes through `StreamReconciledScoresParquet`
   with its features in hand, so this is genuinely one pass and no extra I/O. It reaches into
   `ReconciledParquetWriter` rather than sitting beside it, so it is more invasive than the
   sketch it replaces.
2. Worker re-reads its own reconciled parquet after writing it. Correct but pointless: it is the
   same read Stage 7 makes, so nothing is saved, only relocated.
3. Leave the scoring in Stage 7. Then the move carries only the competition, and Stage 7 keeps
   the per-file feature read - which is the read the move exists to delete.

**Not implemented tonight, deliberately**: the premise was falsified while scoping it, and
writing the invasive version against a freshly-corrected design at 22:00, with no ability to
regression-gate while the 257-file run holds the machine, is how a plausible-but-wrong change
lands. Option 1 is the design; it wants a fresh session.

**The rest of the decomposition is unaffected** - the competition split (`f7a6e6d103`), the
no-new-relay finding, the stratum-bounded contribution sizing and the artifact layout all stand.
Only the "scoring is free from `fdrEntries`" step was wrong.

## Phase 1 reworked, and it IS bounded - the hook point is the row-group flush (22:20)

The 22:05 correction said scoring must move inside the parquet stream and called that "more
invasive". Checked, and it is a callback, not a restructuring.

`ParquetScoreCache.StreamReconciledScoresParquet` (`:1426`) does not copy columns through in
bulk. It buffers **`FdrEntry` objects** per row group - `var buffer = new List<FdrEntry>(rowsPerGroup)` -
and emits with `BuildFdrEntryColumns(buffer, written, libraryById, fileName, featureFields, ...)`.
That is the only write path, so EVERY emitted row is materialized as an `FdrEntry` with its
features at flush time, including the unchanged rows that "stream through" from the original
parquet.

So the hook is: at each row-group flush, score the buffered entries with the frozen model and
accumulate `(entry_id, score)`.

* **No extra I/O** - the stream is one the worker already makes.
* **No extra materialization** - the entries already exist to be written.
* **Bounded** - the buffer is `rowsPerGroup`; the accumulated scores are 12 B x this file's
  survivors, and they are the file's own output, not a whole-run structure.

That removes the last objection to phase 1. What it needs: the frozen model reachable in the
worker (it is - `FirstPassFdrTask` publishes `FirstPassPercolatorModel` at `:122`, and a
distributed worker reloads it from `.1st-pass.model.json`), plus a decision on where the scores
go - which is the artifact question, and the one thing still genuinely open.

**Still not implemented tonight**: the 257-file run holds the machine, so nothing here could be
regression-gated, and this is core artifact-writing code. But it is now a specified callback
rather than a direction.

## Follow-on candidate: the progress lines lose their phase (observed live, 2026-08-27)

Brendan checked the running 257-file job and read it as "only running SecondPassFDR". It was in
FirstPassFDR - the denominator gave it away (764,427,887 is the PRE-compaction population;
Stage 7 only ever sees the ~137 M survivors). But the log itself could not say so: `[TASK]` lines
are emitted only at task START, and `ProgressReporter` prints its heading once and then bare
percentages, so anything that tails the log loses which phase it is in.

This is the same trap as the standing note to read `file NN/NN:` lines rather than a tailed `%`.
It has now cost a real reader a wrong conclusion about a live 10-hour run.

**Fix candidate**: put a short phase tag on each percent line, or emit a periodic `[TASK]`
heartbeat. **Not folded into this PR**: it changes every progress line in every log, and
`ai/scripts/perfviz.py` parses those - so it wants its own change with the parser updated in the
same commit, not a drive-by at the end of a memory PR.

A second, cheaper half: the run directory is nearly empty until Stage 5 finishes (1,029 entries -
the 1,028 hard links plus run.log - against 3,350 in a completed run), because every stage writes
its artifacts at the END. That is also what made the run look idle. Worth knowing when watching
one, and worth a line in the run-layout doc.

## MEASURED: Stage 6 can absorb the pass-2 work for free (night session, 00:24)

The open question behind the whole move was whether `PerFileRescoring` has room for the run-scope
pass-2 work. First `perfile-rescore-peak` probe from the 257-file Stage 5-7 run:

| probe | value |
|---|---|
| `reconciliation-floor` (post-GC, entering rescore) | 4.12 GB |
| `perfile-rescore-loaded` (post-GC, streaming index resident) | 4.34 GB |
| `perfile-rescore-peak` (PRE-GC, per-file transient) | **15.43 GB** managed, 34.24 GB WS |

So a Stage 6 file already churns ~11 GB of collectable garbage above a ~4.3 GB floor - the
rescored entries carrying `Features` / `CwtCandidates` / `Fragment*` / `ReferenceXic*`.

What the move would add to that worker:

| addition | size |
|---|---|
| frozen-score accumulator, 12 B x ~533 K survivors/file | ~6 MB |
| the file's own 1st-pass sidecar scalars, ~2.99 M x 12 B | ~36 MB |
| **total** | **~40 MB, under 0.3% of the existing per-file transient** |

**The stage has room by three orders of magnitude.** That was the one measurement that could have
argued against moving the work into Stage 6, and it does not.

Stage 5 for context, same run: 9,578.3 s (2h 39m), peak_paged 53.59 GB, but handing off only
**5.97 GB** live - so Stage 5's cost is transient too, and the run's real problem was never it.
The baseline's run peak was ~69 GB at STAGE 7's pass-2 start, on a 64 GB box.

## 257-FILE STAGE 5-7 RUN: COMPLETE, exit=0, output identical (memory bar NOT met - see retraction) (2026-08-28 04:37)

`chs-257files-libdecoy-r1.0-protein-compact-s57base257`, exe `_bin\26.1.1.239-stage57-20260827`,
`-LinkFrom` the p0059_0060_0061 Stage 1-4 artifacts, no `-Task`, 30 threads,
`OSPREY_LOG_MEMORY=1`, mdiag on, fdrbench pass 2.

**The first full Stage 5-7 measurement at 257 files on this branch.** Every prior 257-file number
came from `--task SecondPassFDR` and was blind to Stage 6.

### Output: EXACT match on every count

| | oracle (baseline) | this run |
|---|---|---|
| protein groups at 1% | 5,079 | **5,079** |
| library spectra | 45,724 | **45,724** |
| passing entries | 11,745,026 | **11,745,026** |

Six commits of refactoring - the sidecar read fusion, `IFdrRow`, the competition split and the
review fixes - and the cohort-scale output is unchanged.

### The blib size difference is SQLite packing, verified not inferred

725,258,240 bytes against the baseline's 725,458,944 - **200,704 bytes = 49 x 4096-byte pages**.

| | baseline | s57base257 |
|---|---|---|
| `page_size` | 4096 | 4096 |
| `page_count` | 177,114 | **177,065** |
| `freelist_count` | 0 | 0 |

**Every table row count is identical** - RefSpectra 45,724, RetentionTimes 11,745,026, Proteins
5,757, RefSpectraProteins 50,566, Modifications 12,738, SpectrumSourceFiles 257, and the rest.
Eight content rollups also match exactly, including sums over all 11.7 M `RetentionTimes` rows
and the q-value sums in `OspreyExperimentScores` / `OspreyRunScores`. So the difference is
B-tree page fill, not content.

This is a THIRD blib size for the same content: 725,467,136 (`--task SecondPassFDR` rigs),
725,458,944 (baseline full run, build 26.1.1.233), 725,258,240 (this full run). A blib byte size
is not an equality test - row counts plus content rollups are.

### Wall time: 1.49x faster than the baseline

| stage | this run | |
|---|---|---|
| FirstPassFDR | 9,578.3 s | 2 h 39 m |
| PerFileRescoring | 13,455.6 s | 3 h 44 m |
| **SecondPassFDR** | **1,828.8 s** | **30.5 m** |
| **total** | **414 min** | **6 h 54 m** |

Baseline: **615 min (10 h 14 m)**. Stage 7 is the big mover - 30.5 min in a full run.

### [RETRACTED - see the 05:50 retraction] Claimed the memory bar was met

| | this run | baseline |
|---|---|---|
| run peak_paged | **53.59 GB** | - |
| process peak working set | 52.99 GB, **set in Stage 5** | **70,666 MB (~69 GB)** |
| Stage 7 pass-2 working set | 51.11 GB | - |

Brendan's bar was *"take Stage 7 entirely out of contention for peak memory, i.e. FirstPassFDR
becomes the run's high point."* **Met.** The peak is Stage 5's, Stage 7 came in under it, and the
run peak fell from ~69 GB - which PAGED on this 64 GB box - to ~53.6 GB, which fits in RAM.

**Two caveats, plainly.** It is met NARROWLY (51.11 vs 52.99 GB), and it is met by the
survivor-subset format rather than by removing the pool: `stage7-pool` is still **37.50 GB**. A
larger cohort or a survivor-richer arm puts Stage 7 back on top. The architecture work is what
turns a narrow pass into a comfortable one.

### Stage 7 probe sequence

| probe | managed heap (post-GC) |
|---|---|
| `stage7-inherited` | 3.96 GB |
| `stage7-pool` (after ~7.8 min rebuild) | **37.50 GB** |
| `stage7-fragments-released` | 37.51 GB (**released=0**) |
| `stage7-pass2-scored` | 37.50 GB |
| `stage7-protein-fdr` | 37.50 GB |
| `stage7-blib-written` | 37.50 GB |

`released=0` is a RIG difference, not a regression: the full run already released library
fragments at the end of Stage 5, where the `--task SecondPassFDR` rig reloads the library fresh
and releases 5,173,196 there. It may account for part of the gap below.

`stage7-pool` across the three 257-file measurements:

| run | rig | stage7-pool |
|---|---|---|
| `s7mem257` | `--task SecondPassFDR`, old full-shape parquets | 41.97 GB |
| `s7red257` | `--task SecondPassFDR`, survivor-subset | 40.23 GB |
| **`s57base257`** | **full Stage 5-7, in-process** | **37.50 GB** |

The in-process path builds the pool 2.73 GB leaner than the rehydrate path. Currently a number,
not an explanation - do not quote it as a benefit until it is understood.

### Stage 5 and Stage 6 characterized for the first time at 257 files

**Stage 5**: peak_paged 53.59 GB, but hands off only **5.97 GB** live
(`stage5-handoff-released`) - close to the 7.0 GB the TODO had estimated, now measured. Its cost
is transient.

**Stage 6 is BOUNDED**, and this is the finding that matters for the move. Post-GC floor across
all 257 files: 4.34, 4.52, 4.50, 4.53, 4.49, 4.50, 4.62, 4.60 GB - a flat sawtooth that never
drifts. O(1) in file count. Pace settled at ~50 s/file.

### Stage 6 has room for the pass-2 work by three orders of magnitude

`perfile-rescore-peak (pre-GC)` is **15.43 GB** managed against a 4.3 GB floor, i.e. ~11 GB of
collectable churn per file. What the move adds:

| addition | size |
|---|---|
| frozen-score accumulator, 12 B x ~533 K survivors/file | ~6 MB |
| the file's own 1st-pass sidecar scalars, ~2.99 M x 12 B | ~36 MB |
| **total** | **~40 MB, under 0.3% of the existing per-file transient** |

That was the one measurement that could have argued against moving run-scope pass-2 work into
`PerFileRescoring`. It does not.

### Artifacts written

| artifact | size |
|---|---|
| 1st-pass sidecars (257) | 48.4 GB |
| reconciled parquets (257) | **47.5 GB** |
| 2nd-pass sidecars (257) | 8.7 GB |

The reconciled set at 47.5 GB confirms the survivor-subset format in a FULL run - the old
full-shape format was 266 GB for the same cohort.

### perfviz per-phase breakdown - independent confirmation

`ai/scripts/perfviz.py run.log --files 257` (11,405 memstamp samples, duration 6:54:25):

| phase | managed p10 (floor) | p50 | peak | private peak | wall |
|---|---|---|---|---|---|
| FirstPassFDR | **7.1 GB** | 13.5 | 49.6 | **53.6 GB** | 159:38 |
| PerFileRescoring | **5.0 GB** | 7.0 | 18.4 | 44.2 GB | 224:15 |
| SecondPassFDR | 18.2 GB | 40.4 | 51.1 | **52.6 GB** | 30:29 |

* FirstPassFDR's p10 floor of **7.1 GB** independently confirms the 7.0 GB this file had been
  quoting for it - now from the sanctioned tooling rather than inherited.
* PerFileRescoring's p10 of **5.0 GB** confirms Stage 6 bounded, from a second measurement path.
* Stage 7's private peak (52.6 GB) sits just UNDER Stage 5's (53.6 GB) - the same narrow margin
  the `[MEM]` probes showed.

**Do not read the tool's whole-run "floor 17.8 -> 35.3 GB, +69 MB/file RISING" as an O(files)
leak.** It conflates stages: the run legitimately climbs from Stage 5's low floor to Stage 7's
pooled floor. The per-phase p10s are the honest view, and Stage 6's is flat.

One reporting gap over threshold: 36 s at 04:36:32, in the closing diagnostics phase. Minor, but
it is the kind of silence #4571 exists to remove.

## RETRACTION: the memory bar is NOT met, and no flip has happened (Brendan, 2026-08-28 05:50)

Earlier this session I wrote "THE MEMORY BAR IS MET (narrowly)". **That is wrong and is
retracted.** Brendan looked at the perfviz PNG and said so directly: *"We have not yet achieved
the 'flip' where I see a Stage 7 with radically reduced memory - the Stage 7 stable memory is
still as high or higher than Stage 5."*

He is right, and the plot shows it in one look. Stage 7 sits on a **flat ~48-53 GB plateau for
its entire 30 minutes**. Stage 5's 55 GB is a **spike near its end**. I compared Stage 7's
sustained level against Stage 5's transient peak, found a 1.5 GB margin on the max, and called
that the bar. It is not the comparison that matters.

### The honest numbers - total (private) MB, boundary contamination removed

| stage | all samples med / p90 / max | settled (first 5 min dropped) med / p90 / max |
|---|---|---|
| FirstPassFDR | 28,859 / 50,002 / 54,878 | 29,763 / 50,173 / 54,878 |
| PerFileRescoring | 15,194 / 17,660 / **45,298** | 15,171 / 17,491 / **21,133** |
| SecondPassFDR | 47,762 / 51,373 / 53,816 | **48,300** / 51,984 / 53,816 |

**Stage 7's sustained median is 48.3 GB against Stage 5's 29.8 GB.** Stage 7 is MORE
memory-dominant than Stage 5, not less. `stage7-pool` was **37.50 GB** in the same run - the pool
is untouched, exactly as this file already said of the earlier measurement: *"this branch changes
what Stage 7 READS, not what it HOLDS ... nothing here should be quoted as progress toward the
memory bar."* I wrote that, then quoted a max margin as the bar being met.

### PerFileRescoring is NOT broken - the 44 GB figure was boundary contamination

The per-phase table I posted showed `PerFileRescoring priv peak 44.2 GB`, which reasonably
worried Brendan that Stage 6 had regressed. It had not. Dropping the first 5 minutes after the
stage boundary takes Stage 6's max from **45,298 MB to 21,133 MB**, with a settled median of
**15.2 GB**. The high samples are Stage 5's memory still being released while Stage 6 had already
started - Brendan's own hypothesis, confirmed.

**Per-stage statistics computed over a window that includes the previous stage's teardown are
misleading.** Any future per-stage table must drop the boundary or it will keep producing this
false alarm.

### Instrumentation lesson

*"the memory instrumentation in the log (that you implemented) seems to often lead you into
feeling you have useful numbers that aren't really that useful or meaningful to me."*

Correct. Post-GC `[MEM]` probes measure what the GC could reclaim at an instant chosen by the
probe's author - not what an operator watching private bytes sees, and not the sustained level
that decides whether a cohort fits. Percentiles layered on top of that manufacture precision.

**Look at the PNG `perfviz.py` generates.** The plot answered in one glance what six probes and a
percentile table got wrong. The text summary is a supplement to the picture, not a substitute.

### What is actually true about this run

* Output is identical - all three counts exact, blib content verified equal (row counts across
  every table plus eight rollups over 11.7 M rows).
* Wall time 6h54m vs the baseline's 10h14m, with Stage 7 at 30.5 min.
* Stage 6 is genuinely bounded - settled median 15.2 GB, flat across 257 files.
* Stage 6 has room to absorb the pass-2 move (~40 MB against a per-file transient).
* **Stage 7 still holds a 37.50 GB pool and still dominates the run's sustained memory.** The
  flip is exactly the work that has NOT been done yet.

## WHY Stage 7 costs as much as Stage 5 for 1/6 the rows (Brendan's question, 2026-08-28)

*"It is still not clear to me why Stage 7 requires the same amount of memory to perform an FDR
calculation for 1/6th as many rows as Stage 5."*

It is not holding more information. It is holding the same information in a representation built
for Stages 1-6.

| | rows | per row | total |
|---|---|---|---|
| Stage 5 on `FdrProjection` (readonly struct, q routed through `IFdrOutputSink`) | 768,549,137 | **32 B** | ~24.6 GB |
| Stage 7 on `FdrEntry` (class) | 137,034,004 | **274 B** measured | **37.5 GB** |

5.6x fewer rows, 8.6x more bytes each. The 274 B comes from 37.5 GB / 137,034,004 and decomposes:

| | bytes | needed in Stage 7? |
|---|---|---|
| object header + `List<>` slot | 24 | no - the cost of being a class |
| `EntryId`, `ParquetIndex`, `IsDecoy`, `Charge`, `ScanNumber` | 16 | partly |
| 14 doubles | 112 | ~9; `Pep`, `ExperimentAggregateScore`, `ExperimentProteinQvalue`, `BoundsSnr`, `CoelutionSum` go to the sidecar and are never read back |
| 7 reference fields | 56 | **6 are ALWAYS null** - the stub loader logs "features not loaded - not read on this path" |
| `ModifiedSequence` string | ~72 | value yes, per-row instance no |

**~144 B of the 274 B is dead weight in this stage - about 19.7 GB of the 37.5 GB.** 48 B of null
blob pointers that exist because Stage 6 needs them, ~72 B of duplicated strings, 24 B of class
overhead.

So the lean row is not an invention: it is what Stage 5 already did, and what Brendan called for
on 2026-08-27 ("Stage 7 should use Stage 5's machinery").

## The pool is NOT FDR-counting memory (Brendan's merge-sort question)

*"FDR calculation is done by counting from the best scoring entry to the worst. Why does it all
need to be in memory at the same time? ... you could be streaming them in a 257 element
merge-sort."*

For **Stage 7 the counting is already bounded.**
`StreamingFdr.ComputeFullPopulationPrecursorFdrStreaming` reads one file at a time and keeps only
O(distinct base_id) state - `bestTarget`/`bestDecoy` (~508 K under protein-compact) and `minRunQ`
per survivor - and its own comment says *"no (file, entry_id)-keyed result map is ever built"*.
The frozen path also avoids per-record q storage already: `BuildScoreToQTable` bins score->q into
1,000 bins and `LookupQForScore` assigns from that.

**The 37.5 GB is held for the CONSUMERS after the competition** - the blib peptide gate, the
precursor gate, `CollectPassingEntries`, the second-pass protein FDR, and the per-replicate
report. Five or six independent folds, each walking all 137 M survivors. That is why naively
removing the pool costs ~10 whole-run walks.

**So sortedness is not Stage 7's blocker.** Those folds need IDENTITY, not score order:
`ModifiedSequence`, `IsDecoy`, charge, RTs, area. `libraryById` has sequence and decoy status by
entry_id, and RTs/area are needed only for the ~11.7 M PASSING rows - so the sidecars can be
streamed in stored order, joined against the library, and the pool never exists. No sort needed.

**Where the merge-sort idea DOES bite is Stage 5**, which genuinely holds 768 M rows for a global
score-ordered walk (24.6 GB). A 257-way heap merge over score-sorted sidecars would make that
O(k) instead of O(N). Costs: the sidecars are currently in canonical entry order, not score
order, and the q write-back would have to use the score->q table rather than per-record storage.
Worth its own investigation - it is the larger population.

## Brendan on the shape of the debt

*"We have created code that depends on whole set iteration 10 times in separate classes without
designing a way that the whole set doesn't need to be in memory for every consumer. I guess we
should consider ourselves lucky they rely on so little that we can construct a lean row that
works for all of them."*

Exactly the finding of the consumer audit: ten independent whole-set iterations, no seam for
feeding a consumer rows instead of handing it a collection. The genuinely maintainable fix is a
single-pass listener architecture; the lean row is the pragmatic path, and it only works because
the audit showed those ten consumers read thirteen fields between them.

## The lean row spec (designed, NOT implemented - no consumer yet)

A mutable `struct FdrRow : IFdrRow`, 88 B: `EntryId` (4) + `ModifiedSequence` ref (8) + `Charge`
(1) + `IsDecoy` (1) + 2 pad + 9 doubles (`Score`, both run q, both experiment q, `ApexRt`,
`StartRt`, `EndRt`, `BoundsArea`). 137 M x 88 B = **12.1 GB** against 37.5.

* **Mutable, and held as `FdrRow[]` per file, not `List<FdrRow>`** - the pre-blib re-clamp raises
  the two experiment q-values in place, an `IReadOnlyList` indexer returns a COPY and the write
  is silently discarded, and `CollectionsMarshal.AsSpan` is .NET 5+ while this assembly also
  targets net472.
* **`ModifiedSequence` must be a canonical instance**, or the 72 B/row goes straight back.

Not committed: a public type with no consumer is speculative API. Implement it with its
consumers in one change.

## Interning landed - and a RIG finding that matters more

Interning `ModifiedSequence` at the stub loaders should take ~9.9 GB off the pool (137 M x ~72 B
collapsed to a few million distinct). `ParquetScoreCache.LoadFdrStubsFromParquet` gained an
optional caller-owned `sequencePool`; `FirstPassSurvivorLoader` and
`RescoreHydration.HydrateForRescore` each own one spanning all their files. Caller-owned rather
than `string.Intern`, which never releases.

**The rig finding**: the first measurement showed `stage7-pool` = **40.23 GB, unchanged**, because
the change was on `FirstPassSurvivorLoader` and the `--task SecondPassFDR` path does not use it -
`stage7-inherited` was ALSO 40.23 GB, i.e. the pool was already built before Stage 7 started, by
`PerFileScoringTask.Rehydrate` -> `HydrateCompactedStreaming`.

**So the 30-minute `--task SecondPassFDR` loop only measures pool changes that cover the REHYDRATE
path.** The full in-process run builds its pool in `BuildRescoredPool` via
`FirstPassSurvivorLoader` instead. Any future pool work has to touch both, or be measured on the
matching rig. That is worth more than the interning itself.

## SESSION END 2026-08-28 06:45 - seven gated commits, and the architecture is settled

Night session 21:40 -> 06:45 (**9 h 05 m**), context 55% -> ~28%.

### Commits on `Skyline/work/20260827_osprey_stage7_stream_increment` (none pushed)

| commit | what | gate |
|---|---|---|
| `a700c1226a` | frozen 2nd pass reads each 1st-pass sidecar ONCE, not three times | Stellar 10/10 |
| `f08059f824` | `IFdrRow` + generic q-value selectors | Stellar 10/10 |
| `f7a6e6d103` | `StreamingFdr` split into `CompeteOneFile` + `FoldFileContribution` | Stellar 10/10 |
| `e5daaaf9a2` | tests pinning the two-stage reduction against a global pass | 601/601 |
| `fc5c3c7b40` | code-review fixes: lazy staging buffer, reverse arg guard, stratified tests | Stellar 10/10 |
| `21434cb1c9` | interned `ModifiedSequence` at BOTH stub-loading paths | Stellar 10/10 |

Plus `b9075eb99a` from the prior session. `-Dataset All` was green at 04:40 (55 assertions, 0
skipped, 0 failed) but PREDATES `21434cb1c9` - re-run before the PR.

### The acceptance run

`s57base257`, full Stage 5-7 at 257 files: **exit=0, 6 h 54 m** against the baseline's 10 h 14 m.
Output identical - 5,079 protein groups, 45,724 library spectra, 11,745,026 passing entries, and
the blib verified equal table-by-table plus eight content rollups. Stage 7 wall 30.5 min.

### What is NOT achieved, stated plainly

**The memory bar is not met.** `stage7-pool` is 37.50 GB; Stage 7's sustained private median is
48.3 GB against Stage 5's 29.8 GB. An earlier claim in this session that the bar WAS met compared
Stage 7's sustained plateau to Stage 5's transient spike and is retracted. The branch changed what
Stage 7 READS - 5.7x smaller reconciled parquets, wall 81 -> 30.5 min - and nothing about what it
HOLDS.

### The three findings the next session needs

1. **Why Stage 7 costs as much as Stage 5 for 1/6 the rows**: `FdrEntry` is 274 B/row measured
   against `FdrProjection`'s 32 B, and ~144 B of it is dead weight in this stage - 48 B of
   always-null blob refs, ~72 B of duplicated string, 24 B of class overhead.
2. **The pool is NOT FDR-counting memory.** The competition is already bounded
   (O(distinct base_id), no (file, entry_id) map). The pool is held for the five or six
   downstream folds. So sortedness is not Stage 7's blocker - identity is, and it is reachable
   from `libraryById` by entry_id.
3. **The rig trap.** `stage7-inherited` and `stage7-pool` were BOTH 40.23 GB on the
   `--task SecondPassFDR` loop: that rig builds the pool in `PerFileScoringTask.Rehydrate`,
   before Stage 7 starts, while the in-process run builds it in `BuildRescoredPool`. A pool
   change covering one path reads as "no effect" - which is exactly what the first interning
   attempt did.

### Claims retracted this session

* "The memory bar is met" - no.
* "The frozen scoring is free in the worker" - only for the ~7% of survivors it rescored;
  unchanged stubs are `Features == null` and stream through from the original parquet.
* "The worker needs the global survivor set relayed" - it does not; the join can filter.
* "The architecture deletes the lean row" - too firm; the lean row is plausibly the destination
  representation either way.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260828_osprey_stage7_architecture.md` before starting work.

### Interning confirmed output-correct at 257 files (06:45)

The `s7intern` run (`--task SecondPassFDR`, first interning snapshot) reproduced all three oracle
counts exactly: **5,079** protein groups, **45,724** library spectra, **11,745,026** passing
entries. So `21434cb1c9` is output-correct at cohort scale as well as on Stellar.

Its MEMORY number remains uninformative - that snapshot predates the rehydrate half, so it shows
the same 40.23 GB pool. The saving is still unmeasured; re-measure on a fresh snapshot.

## The interning did not reach production, and a pool of its own would have doubled the strings (2026-08-28)

Brendan's question - *"Is the new interning using the same interning mechanism at the library?
Can you review the entire codebase to make sure that modified sequence and protein names/ids are
always interned when they are read from any side-car file?"* - and then the point that settles
the design: *"You want to use the same interner as the library. If they use separate pools, you
will duplicate all of the strings."*

Both answers were no, and the review found a third problem neither question was asking about.

### `21434cb1c9`'s "rehydrate half" patched a method production never calls

`RescoreHydration.HydrateForRescore` has **no production caller** - only `Osprey.Test/IOTest.cs`
lines 4064 and 4180. The pool the `--task SecondPassFDR` rig builds comes from
`HydrateCompactedStreaming`, which takes `loadStubs` as an INJECTED DELEGATE, and both
production delegates were unpooled:

* `PerFileScoringTask.LoadJoinOnlyScoresForFile`
* `FirstPassFdrTask.LoadResumeStubs`

So the owed 30-minute re-measurement would have come back "no effect" a SECOND time, and this
time the rig would not have been the reason. The previous session's own rig-trap finding was
correct and it still missed this, because it identified the right rig and then patched the wrong
method inside it.

### Separate pools would have made it worse, not better

A pool of its own elects the FIRST PARQUET instance as canonical. The library already holds an
instance of every one of those sequences, so the run would end up holding two sets - the
library's and the sidecars' - which costs more than interning saves. The fix is to seed the pool
FROM the library and share it; then a sidecar value equal to a library sequence is answered with
the library's own instance and the rows cost no strings at all.

Verified rather than assumed: the parquet's `modified_sequence` is written from
`FdrEntry.ModifiedSequence`, which `CoelutionScorer.cs:179,464` copies off the `LibraryEntry` it
scored. Measured on Stellar: **360,376 sequences seeded from the library, 0 sidecar lookups
missed the pool.**

### A latent data race, introduced by the same commit

`21434cb1c9` gave `FirstPassSurvivorLoader` a `Dictionary<string, string>` field and documented
it "not synchronized - the survivor rebuild walks files sequentially". It does not:
`PerFileRescoreTask.cs:718` drives `RescoreOneFileStreamed` - and through it `loader.Load` -
from inside a `Parallel.For` over files. Concurrent writers on a plain dictionary.

Fixed by FREEZING rather than locking. `LibraryStringInterner.Freeze()` makes the pool
lookup-only, and a `Dictionary` tolerates any number of concurrent readers; it is a writer among
them that corrupts it. Locking was not an option - interning is called once per observation,
over 137 M times, and the class doc already records that a concurrent interner on the FDR path
was measured as a net loss. The cost of freezing is that a value absent from the library is not
pooled, which `FrozenMisses` counts: zero on Stellar.

### What the sweep found, and what needed nothing

**Protein names/ids need no sidecar interning at all.** `protein_ids`, `sequence` and
`file_name` are WRITTEN to the scores parquet and never read back - `modified_sequence` is the
only string column with a reader. Protein identity comes from `libraryById`, interned at library
load. The binary `.fdr` sidecar (`FdrScoreRecord`) is all-numeric, no strings.

Three ad-hoc mechanisms existed where there should have been one: `LibraryStringInterner`, the
`IDictionary<string,string>` + `Canonicalize` added by `21434cb1c9`, and an inline
TryGetValue/assign in `SecondPassFdrTask.CollectPassingEntries`. The last two are gone.

Pooled (retained across files): `PerFileScoringTask` 430/1415/1447/1611, its resume
`TryLoadStubsAndCalibration`, `FirstPassSurvivorLoader`, `FirstPassFdrTask.LoadResumeStubs`,
`CollectPassingEntries`, and the reconciliation-JSON gap-fill read in `RescoreHydration` (~2 M
targets at 257 files, retained for every file at once).

Left alone deliberately, because their strings are not retained: `CompactPerFileRescoreTask.cs:287`
(clears the survivors immediately), `Pass2FdrSidecar.cs:1909/1943` (build uint-keyed maps), and
`ScoreOrLoadForFile` (one file's own output on its way to its parquet).

Also fixed: `21434cb1c9` inserted `Canonicalize` BETWEEN `TryReadEntryIdsAndApexRts`' doc comment
and its signature, so the apex-RT reader's documentation had silently become the helper's.

### Commit

`79f63471bc` - "Shared one library-seeded sequence pool with the sidecar readers".
Gates: build clean, 601/601 tests, ReSharper 0 warnings / 0 errors,
`regression.ps1 -Dataset Stellar` **10/10 PASS** (output byte-identical).

### Still owed

* The 257-file memory re-measure, now genuinely measuring something -
  `chs-257files-libdecoy-r1.0-protein-compact-s7sharedpool`, launched 07:59 against the
  `s7intern` baseline of **40.23 GB / 36 min** on the identical rig.
* `-Dataset All` before the PR (the 04:40 green predates both `21434cb1c9` and `79f63471bc`).
* Open question for Brendan: `HydrateForRescore` is dead production code that already misled one
  session. Delete it with its two tests, or keep it?

## MEASURED: the shared library-seeded pool takes 7.17 GB off Stage 7 (2026-08-28 08:37)

`chs-257files-libdecoy-r1.0-protein-compact-s7sharedpool`, `--task SecondPassFDR -LinkFrom
s57base257`, exit=0. The same 30-minute rig as the `s7intern` baseline, so this is like-for-like.

| | baseline `s7intern` | shared pool | delta |
|---|---|---|---|
| `stage7-inherited` | 40.23 GB | **33.06 GB** | **-7.17 GB** |
| `stage7-pool` | 40.23 GB | **33.06 GB** | **-7.17 GB** |
| protein groups | 5,079 | **5,079** | - |
| library spectra | 45,724 | **45,724** | - |
| passing entries | 11,745,026 | **11,745,026** | - |
| `SecondPassFDR` wall | 2,172.6 s | 2,290.5 s | +117.9 s |

`Sequence pool: 4525056 distinct seeded from the library, 0 sidecar lookup(s) missed it`

**-17.8% off the pool with output unchanged**, and zero misses over ~137 M lookups - so the
seeding assumption (every sidecar sequence was written from a `LibraryEntry`) holds at cohort
scale, not just on Stellar. Run log:
`D:\test\osprey-runs\chs-seer\runs\chs-257files-libdecoy-r1.0-protein-compact-s7sharedpool\run.log`

**The wall number is NOT yet a regression, and must not be quoted as one.** +5.4% on single runs
two hours apart, on a machine that had just finished a 7-hour job. Worked through from first
principles the change's own mechanism accounts for under a tenth of it: ~137 M frozen-pool
lookups at ~50-80 ns is ~9 s, plus ~0.5 s of seeding. The rest is unexplained. Repeat both arms
before calling it anything.

## DECIDED: `ModifiedSequence` becomes a type (Brendan, 2026-08-28)

*"Seems like ModifiedSequence should become its own class with guarantees around how it works and
that it is unique process-wide. Time to stop using just bare strings for these."* ... *"Then we
have a typed marker enforcing correctness, not just a convention."*

Bare strings are what let three separate interning mechanisms coexist unnoticed, and what makes
the pool's guarantee a convention the next caller has to remember.

**Shape**: a `sealed class ModifiedSequence` in `Osprey.Core`, private constructor, a factory
that guarantees one instance per distinct value. Equality is **built into the type** -
`ReferenceEquals` + `RuntimeHelpers.GetHashCode`, per Brendan: *"We should just build this into
the ModifiedSequence class in this case to make it unnecessary to remember to wrap in the
template class."* So no call site has to wrap a key in `ReferenceValue<T>`.

**It must implement `IComparable`, not just equality.** `LibraryDeduplicator.cs:139` sorts with
`string.Compare(..., StringComparison.Ordinal)` and that sort is output-affecting. Delegating
`CompareTo` to `string.CompareOrdinal` on the text keeps it. (This is also why an int-id form was
NOT chosen lightly: ids only reproduce ordinal ordering if assigned in ordinal order of the
distinct set - the trap `FdrProjection.PeptideId` already documents as "risk #1".)

**Dependency-free, deliberately.** `pwiz.Common.Collections.ReferenceValue<T>`
(`pwiz_tools/Shared/CommonUtil/Collections/ReferenceValue.cs`) is the precedent for the pattern
and should be cited in the doc comment, but is not referenced:

* `Osprey.Core` has NO project references at all (one `System.Memory` package reference).
* `CommonUtil` is net472-only; Osprey multi-targets net472 + net8.0.
* Copying `ReferenceValue` into `PortableUtil` would COLLIDE - `CommonUtil.csproj` references
  PortableUtil, and both would then declare `pwiz.Common.Collections.ReferenceValue<T>`.
* `ReferenceValue<T>` is for types that cannot self-guarantee uniqueness. This one can.

PortableUtil's `RootNamespace` is already `pwiz.Common`, the same as CommonUtil's, so the
PortableUtil -> CommonUtil swap under the full .NET 8 port is transparent for anything that DOES
use the shared utilities. `ModifiedSequence` is unaffected either way (Brendan: *"It has
PortableUtil which goes away under the full .NET 8.0 port when it will get CommonUtil"*).

**Sequencing**: folded into the LEAN ROW PR, not its own. The type's payoff is realized in the
row, and doing them separately churns the same 48 files twice. Footprint: 167 production
references across 48 files, plus 110 in tests.

**Left open**: the class form keeps an 8-byte reference, so `FdrRow[]` stays GC-traced at 137 M
rows. An int id was the only form that made the row reference-free. That was a HYPOTHESIS about
why Stage 5's 32 B/row behaves better, never measured. The class form does not foreclose it - an
id can be added INSIDE `ModifiedSequence` later without changing the public type. First place to
look if the lean row's numbers come in short.

**Also open**: resolving the sequence from `libraryById` by `entry_id` instead of reading the
parquet's `modified_sequence` text at all. That removes the per-row string hash entirely (the
suspected part of the wall-time cost) and the typed `ModifiedSequence` is what makes the
resolution safe to rely on. `ParquetScoreCache.cs` already says the apex-RT panel does exactly
this: *"the modified sequence and charge behind the precursor identity are resolved from the
library by entry id instead."*

## Backlog: the perf A/B cannot see a regression that lives in master (2026-08-28)

`pwiz-perfbase` was pinned at `f4de686450` (#4378) and has been moved to master
`bd94e8a375` (#4616) - roughly two months of drift, closed so the gate measures this
branch rather than the interval.

The branch is **0 commits behind master**, so `Test-PerfGate` branch-vs-master now
attributes its delta to exactly these 37 commits. That is what we want, and it also
means the gate is BLIND by construction to a regression in master itself: both arms
carry it and it cancels.

Catching that needs an absolute reference, not an A/B. Two are available:

* **Rust osprey as a change-immune anchor** - same pipeline, untouched by C# commits,
  so a Stellar wall time that is up on BOTH sides indicts the machine or the
  environment while one-sided movement indicts C#. The cross-impl gate produces Rust
  wall times for free; record them rather than discarding them.
* Historical Stellar timings from prior `Test-PerfGate` runs and the TeamCity perf leg.

If a master-level regression is ever confirmed, the bisect range is **121 master
commits between #4378 and #4616, 60 of which touch `pwiz_tools/Osprey`** - about six
steps over the Osprey-touching subset, not a slog.

**This does not block #4621** (Brendan, 2026-08-28): a defect in master is a separate
track, and this PR's gate is the branch-attributable A/B, which is clean.

## OPEN: intermittent AccessViolation in the StellarLibDecoy phase3 rescue worker (2026-08-28)

**Do not merge #4621 without resolving or consciously accepting this.** An AV in the HPC
per-file rescore worker is a production-path crash on the distributed workflow, not a test
artifact.

### What happened

`regression.ps1 -Dataset All` at 09:32 aborted: `Osprey --task exited -1073741819`
(`0xC0000005`) in `StellarLibDecoy` mode 3, phase3 rescore of stem `..._22`. Everything
before it passed (Stellar 10/10, StellarLibDecoy modes 1, 1c, 1b).

Windows Application event log, `.NET Runtime`, 09:51:23:

```
Application: Osprey.exe
Exception Info: System.AccessViolationException: Attempted to read or write
protected memory. This is often an indication that other memory is corrupt.
Stack:
```

Empty stack - the damage surfaces at a dereference unrelated to the corruption site, which
is the signature of a corrupted managed collection rather than a bad pointer at the throw.

### It is INTERMITTENT - roughly 1 in 26

| evidence | phase3 executions | crashes |
|---|---|---|
| `-Dataset All` (aborted) | 3 | 1 |
| `-Dataset StellarLibDecoy` re-run, 15/15 PASS | 3 | 0 |
| sequential soak at HEAD (`08fbed8cfe`) | 20 | 0 |

**Consequence, and it invalidates an earlier claim in this file**: the `-Dataset All` PASS at
04:40 does NOT exonerate the pre-interning commits. At a ~4% rate a clean 20-run soak happens
44% of the time and a clean 3-execution gate run happens 88% of the time. No single green run
proves anything here, including that one.

### The repro rig - 29 s per execution

The isolated phase3 command, lifted from the retained chain log. Cycle time 29.2 s, so a soak
is cheap:

```
Osprey --task PerFileRescoring --input-scores <stem>.scores.parquet
  -l carafe_spectral_library.tsv -o output.blib --resolution unit --protein-fdr 0.01
  --threads 16 --decoys-in-library --decoy-pairing-manifest osprey_library_db_pairing.tsv
  --model-diagnostics --timestamp --memstamp
```

**`OSPREY_VERSION_OVERRIDE=26.1.1.0` is MANDATORY** (regression.ps1 pins it at its line 212).
Without it every run dies at 4 s with "osprey version mismatch" - exit 1, not the AV - and the
soak measures nothing. Cost me 20 wasted runs.

Reset between iterations: delete `<stem>.scores-reconciled.parquet`, its
`.PerFileRescoring.osprey.task` marker (this is what stops per-file resume skipping the work),
and `output.model-diagnostics.*`.

Harnesses: `ai/.tmp/sessions/20260828-interner/soak-phase3.ps1` (sequential) and
`soak-parallel.ps1` (3 stems concurrent, for amplification).

### Leading suspect - NOT proven, and not code this branch touched

`ModelDiagnosticsData.Accumulator` holds `Dictionary<string, Prec>`,
`Dictionary<string, FrontierPrec>` and `Dictionary<string, double>`, all keyed
`StringComparer.Ordinal` on modified sequence, with **no lock and no concurrent collection**.
It is fed from two independent sites: `ScoringTaskShared.FeedModelDiagnostics` and
`FdrProjectionSinks.cs:116`.

The arm asymmetry fits: `ModelDiagnostics = $true` for StellarLibDecoy, and plain `Stellar` -
the ONLY dataset without it - is the only one that passed.

If that is the site, the interning is a **timing trigger, not the cause**: interned keys make
`StringComparer.Ordinal` short-circuit on the reference check instead of walking ~30 chars,
which shifts the interleaving window. A latent race can start firing when the hot path gets
faster.

### Ruled out

* `DecoyGenerator`'s separate interner - never runs in the libdecoy arm (decoys come from the
  library as-is).
* `DecoyPairingManifest`'s separate interner - sequential, load-time, and mutates `ProteinIds`,
  a field disjoint from the `ModifiedSequence` the shared pool seeds.
* Cross-process phase3 contention - `regression.ps1:1290-1313` runs the three stems
  SEQUENTIALLY, so the isolated repro is faithful in that respect.

### What is needed next

A **positive control**. Until the crash can be produced at a measurable rate, a bisect compares
zeros and proves nothing. Options, in cost order:

1. Amplify (concurrent stems, more threads, memory pressure) to raise the rate.
2. Buy power - 100+ runs per arm, hours of machine time.
3. Fix the accumulator's synchronization on its own merits - it is wrong regardless - while
   being explicit that causation was never proven.

Brendan, 2026-08-28: re-run the gate once; if it does not reproduce, move on for now, there is
a lot left to validate.

## Review response: six findings DELETED, ParquetIndex made nullable (2026-08-28)

Brendan: *"We will work on the PR until there are no issues to post... We favor larger,
higher-quality steps forward over smaller steps with issues."* No findings are being filed;
each is fixed or dropped.

### Removal retired six findings (commit `870c3f4404`)

Deleting the reconciled-parquet upgrade path took #2, #3, #10, #11, #12 and #13 with it - they
were all defects inside the removed code. 835 lines deleted, 43 added. Gated: build clean,
599/599, ReSharper 0/0, `regression.ps1 -Dataset Stellar` 10/10.

### #1 FIXED - unsynchronized Dictionary in Parallel.For

`_resetEntryIdsByFile` took a `TryGetValue`-then-insert from inside `ExecuteRescore`'s
`Parallel.For`. Added `_resetEntryIdsLock` around the dictionary (not the inner sets - one
worker owns a file). The hand-off at line 401 now passes a SNAPSHOT taken under the lock:
ReSharper flagged `InconsistentlySynchronizedField`, and it was right - "the loop has joined"
protects the read but still lets shared mutable state escape by reference.

### #4 + #5 + a determinism bug: ONE root cause

`FdrEntry.ParquetIndex` carried two meanings: an in-memory `uint.MaxValue` sentinel for
"gap-fill, no Stage 4 row", and the on-disk `score_index` ordinal. That overload produced all
three findings, plus one nobody had reported:

**Both sort sites in `PerFileRescoreTask` justify an UNSTABLE sort by claiming
`ParquetIndex` is unique per row.** The resume overlay stamped every gap-fill row with the
same `uint.MaxValue`, so that invariant was false exactly there.

**Resolution (Brendan's design):** `uint? ParquetIndex`, null = "no Stage 4 row".

* `FdrEntry.CompareParquetIndex` states the rule ONCE: unresolved sorts **LAST**, matching the
  old sentinel. `Nullable<uint>`'s default puts null FIRST, so taking the default would have
  silently reversed exactly the rows being changed. Four comparators route through it, which is
  what keeps the conversion output-neutral by construction.
* `ReadFdrEntryGroup` now reads `score_index` like `LoadFdrStubsFromParquet` already did - the
  two readers of one file no longer disagree about what the field means.
* The resume overlay no longer re-stamps; rows keep the numbering they arrived with, so the
  sorts' uniqueness claim becomes TRUE.
* The reconciled-parquet writer HARD-FAILS on an unresolved row. Writing a stand-in would
  persist a `score_index` pointing at another row's features: well-formed, undetectable, wrong.
* `ReconciledParquetWriter.BuildOverlay` routes on `HasValue` instead of `== uint.MaxValue`.

**Deliberately NOT converted:** `FdrProjection` (32-byte struct, 768 M live) and
`PercolatorEntry` keep a local `uint` sentinel. The goal was to stop the ambiguity travelling
between subsystems on shared state, not to eliminate the value.
`PercolatorEntryBuilder` is the single documented boundary where the nullable becomes it.

**Size:** computed +8 B/`FdrEntry` (the small-field group goes 16 -> 24; `Nullable<uint>` is an
8-byte struct field that cannot pack into the 2 spare bytes). ~1.1 GB at 137 M, +3.3% of the
33.06 GB pool, and temporary - the lean row does not carry the field. NOT measured; confirm on
the `stage7-pool` probe before quoting it.

### New convention (Brendan, 2026-08-28)

**Use LINQ `OrderBy` where ties are expected; `Array.Sort`/`List.Sort` only where they are
provably absent.** An audit of every `// Array.Sort OK:` annotation found the codebase
disciplined - all but one either claim uniqueness or argue ties are byte-identical primitives.
The exception was `PerFileRescoreTask` gap-fill append, which applied the primitive argument to
`FdrEntry` OBJECTS carrying distinct features and blobs. Now `OrderBy` with the new
`FdrEntry.CANONICAL_COMPARER`.

### #8 CONFIRMED - our own streaming path is dead AND wrong

`SecondPassFdrTask.cs:218` (`rescored.Value`) sets `IsMaterialized`, and `Files()`
short-circuits on it, so `MaterializeOneFile` / the `LoadFile` branch **never execute in
production** - the streaming half of this PR ships unexercised. Worse,
`MaterializeFileSurvivors` -> `FirstPassSurvivorLoader` overlays only the **1st-pass** sidecar
(`FirstPassSurvivorLoader.cs:190-191`), so if it did run, five second-pass gates would silently
read first-pass q-values. Removing line 218 is the LEAN ROW's objective, so this is armed to
fire in the next sprint. **Unresolved - needs a decision:** make the streaming path apply the
2nd-pass sidecar plus a test that exercises `LoadFile`, or delete it and rebuild it with the
lean row.

### Still unverified

#6, #7, #9, #14, #15. Not examined; do not characterize them from the review summary.

### Gate infrastructure is broken (NOT ours)

* `Compare-EndToEnd-Crossimpl.ps1` defaults to `C:\proj\pwiz` (master) - only its staleness
  guard stopped it validating the wrong tree. Pass `PWIZ_ROOT`.
* Cross-impl AND `Test-PerfGate` both look for mzML at `<base>/<dataset>/` while the
  2026-08-22 run-layout migration moved them to `<base>/<dataset>/raw/`. `Dataset-Config.ps1`
  has ZERO references to `raw`. Astral is not staged under `OSPREY_TEST_BASE_DIR` at all.
  Worked around with a hard-linked base at `D:\test\osprey-runs\_crossimpl-base`; the durable
  fix touches shared ai/ tooling and was not taken.
* Cross-impl Stellar PASSED 4/4 legs at 1e-9 once pointed correctly, including the sidecar leg
  (1,448,698 + 996,830 records). **Parity is NOT broken by this PR.**

## SEQUENCING: stabilize this PR, THEN the lean row as the final piece (Brendan, 2026-08-28)

*"Stay focused on the objective of landing a fully stable PR that would otherwise be mergeable
if it contained the lean row and could prove it stays below 20 GB in Stage 7 for the 257 file
dataset. And then implement the lean row to do just that as the final piece to land before
actually merging the PR."*

Two phases, in this order:

1. **Make THIS PR stable** - every review finding fixed or dropped, nothing filed, all gates
   green. The bar is "mergeable except that it does not yet contain the lean row."
2. **Then the lean row**, as the last commit before merge, with a MEASURED acceptance
   criterion: **Stage 7 below 20 GB on the 257-file CHS dataset**.

The criterion is what makes the lean row done rather than written. Today's measured baseline on
the same rig is `stage7-pool` **33.06 GB** (down from 40.23 GB), so the lean row has to take
roughly another 13 GB off. The spec's 88-byte row projects a 12.1 GB pool against today's
37.5 GB fat-row equivalent, which clears 20 GB with margin - but the number to report is the
probe, not the projection.

Do NOT start the lean row on low context: it is a 48-file refactor that carries the
`ModifiedSequence` type with it, and a half-applied one leaves the tree neither shape.

**Remaining before phase 1 is done:**
* #8 - the streaming half is dead AND would read first-pass q-values (see above). Decide: make
  it correct with a test that exercises `LoadFile`, or remove it and rebuild it with the lean
  row, which is the only consumer that will make it live.
* #6, #7, #9, #14, #15 - unverified.
* Assertions at the two post-resolution sorts, now that the reader fix makes them hold.
* `Test-PerfGate` (needs `-TestBaseDir D:\test\osprey-runs\_crossimpl-base`), and cross-impl on
  Astral.

### Session end 2026-08-28 - four commits, all golden-gated

`79f63471bc` shared sequence pool | `08fbed8cfe` dead-code removal |
`870c3f4404` upgrade-path removal (-835 lines) | `9d74b79456` nullable ParquetIndex.
Each gated `regression.ps1 -Dataset Stellar` 10/10, output byte-identical. Plus
`-Dataset All` 56 assertions and cross-impl 4/4 legs at 1e-9.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260827_osprey_stage7_stream_increment.md` before starting work.

## #8 DELETED per Brendan's ruling; resolved-sort assertions added (2026-08-28 evening)

Brendan ruled on #8: **delete the dead streaming half**, rebuild it with the lean row
(its only future consumer). Commit `c7e44d67d0`, -118/+65 across 5 files.

**What went**: `RescoredEntries.WithStreaming` / `LoadFile` / `IsMaterialized`, the
streaming branch of `Files()`, and `PerFileRescoreTask.MaterializeOneFile`.
`Pass2FdrSidecar.residentByFile` simplified to the always-resident case. Verified before
cutting: the surface's only consumers (`Pass2FdrSidecar`, `OspreyReportWriter`) all run
after `SecondPassFdrTask.cs` reads `rescored.Value` at the top of Stage 7, and the
`--task PerFileRescoring` worker attaches but never consumes it - dead on every path.

**What stayed, deliberately**: the `Files()` / `FileNames` fold seam. Every Stage 7
consumer folds to an O(distinct) aggregate through it rather than indexing the pool,
which is the shape the lean row's streamed source re-enters through. Its doc now records
why the old source was wrong (1st-pass-only overlay) so phase 2 does not reacquire it.

**Assertions (handoff item 3)**: new `FdrEntry.SortCanonicalResolved(entries, fileName)`
verifies every row's `ParquetIndex.HasValue` before the unstable canonical sort and
throws `InvalidOperationException` on a null. Both post-resolution sort sites route
through it (`FirstPassSurvivorLoader` reload, `SortFileEntriesCanonical` - which had a
THIRD caller at the per-file resume skip arm, missed by the handoff's list of two).
`TestNoUnstableSort` enforces the `// Array.Sort OK:` annotation on the same line as any
`List.Sort` and caught the moved sort until the annotation moved with it.

**Gates**: build clean, ReSharper 0/0 both TFMs, 599/599, `regression.ps1 -Dataset
Stellar` 10/10 (log: `ai/.tmp/sessions/20260828-stage7-findings/regression-stellar.out`).

**#6/#7/#9/#14/#15 verification method**: the 2026-08-28 review's finding text was never
persisted - only the numbers in this file survive (Brendan confirmed). So verification is
a fresh `/code-review max` against the post-deletion tree: anything real among them
resurfaces, anything attached to deleted code cannot. Running now.

## The pass-2 sidecar is written THREE times per run - the designed split is not implemented (2026-08-28 night)

Brendan, on reading the write-then-patch trace: *"Sigh. Let's not do the lean row until we land
the parts I thought were done, but are not."* The lean row is DEFERRED behind the sidecar work.

### What the pipeline actually does today

`.2nd-pass.fdr_scores.bin` is a declared **output of SecondPassFDR**, not of PerFileRescoring
(`SecondPassFdrTask.Outputs()` yields `Pass2Path(input)` per input). Stage 6's only contact is a
PROBE (`PerFileRescoreTask.cs:319`) - a current 2nd-pass sidecar means a previous run finished
Stage 7, so don't re-rescore. What PerFileRescoring writes once and never revisits is the
reconciled parquet.

On the default frozen-competition path each file's sidecar is written **three times**:

1. `ApplyFileRunQ` writes it mid-stream (Score + run q final; experiment columns still seeds),
   then drops the file's entries - the early write is what avoids O(files x entries) retention.
2. `PatchExperimentValues` rewrites the four experiment columns after the stream, because the
   competition is not complete until every file has been read.
3. `PatchPass2ProteinQvalues` rewrites `ExperimentProteinQvalue` after protein FDR.

Each write is FileSaver-atomic; the ARTIFACT is mutable across its lifetime. That is the source
of the review's R1 (kill window between writes 1 and 3 leaves format-current files with
unfinished columns a rerun adopts), R4 (unconditional rewrite on resume degrades
duplicate-EntryId records) and R12 (double reload).

### The designed split, recorded at line ~2781 of this file, is ON PAPER ONLY

Brendan's own words: *"immutable 2nd pass side-car files per run, and then an experiment-wide FDR
side-car file (maybe the same base name as the BLIB?)"*. None of it is implemented. The night of
2026-08-27/28 landed the ENABLING work only (competition split `f7a6e6d103`, `IFdrRow`, read
fusion, interning) - which is why the 257-file run reproduced the oracle exactly.

### Division of labor, ruled 2026-08-28

**PerFileRescoring** owns what one file can do alone: composite scores + per-run q for that
file's survivors (blib candidates), by competition (`protein-compact`, `transfer-compete`) or
table interpolation (`transfer`). **SecondPassFDR** owns what needs all files: aggregating those
composite scores into experiment-wide precursor / peptide / protein scores and their q values,
by competition or table + interpolation.

**A join task cannot live in a per-file HPC worker** (Brendan). This killed a proposed per-file
"contribution" artifact of precomputed per-base_id bests: it is a partial join in the wrong
stage, and it would freeze the aggregation METHOD into Stage 6 - so switching to mean-best-N
(#4484) would require re-running every worker instead of changing one stage.

**Pipeline invariant** (Brendan): *"Candidate reduction between Pass 1 and Pass 2 is not
reversible."* Pass 2 never reaches back to rescue an entry that exists only in pass-1 parquet /
sidecars. This holds regardless of how the survivor set is computed - and Brendan expects the
survivor set itself to change to stem FDP inflation between passes.

### MEASURED: today's experiment fold DOES read pass-1 values, and it is a decoy-only residue

Today's experiment-level fold in `StreamingFdr.CompeteOneFile` ranges over the whole
PRE-COMPACTION population read from the 1st-pass sidecar (stratum-filtered), with frozen scores
swapped in by entry_id for reconciled survivors. So the architecture (Stage 7 reads only per-run
survivor-scoped artifacts) and the semantics (aggregate over survivors) are ONE decision, not
two - there is no version that keeps today's numbers and also stops reading 1st-pass files.

Temporary diagnostic (`OSPREY_DIAG_SURVIVOR_FOLD=1`, output-neutral, NOT committed) comparing the
population-scoped fold against a survivor-scoped one, Stellar 3-file straight-through:

```
[DIAG-FOLD] stratum bests=986450 | target: differs=0 population-only=0 | decoy: differs=0 population-only=305
```

* **Targets: perfectly clean.** 0 differ, 0 population-only. Brendan's prediction confirmed:
  gap-fill fills every missing run for a surviving precursor, so no target maximum needs a
  pass-1 value.
* **Decoys: 305 base_ids** (~0.06% of ~493K decoy bests) whose best decoy observation lives in a
  row that is not a survivor anywhere.

**The cause is documented design, not an accident.** `PerFileRescoreTask.cs:2243`: decoys are
deliberately excluded from gap-fill because *"the 1st-pass parquet already has a score for every
decoy at its own natural-but-best peak"* - forcing a decoy to be scored at the target's
consensus RT has no biological basis, and doing so previously produced duplicate reconciled rows
and a 1.1e-4 cross-impl group_qvalue drift on Astral. So the decoy side of the null is the one
place the pipeline leans on a pass-1 artifact.

Retention itself is symmetric: `RescoreCompaction` filters by BASE_ID with the decoy bit
stripped (`RemoveAll(e => !firstPassBaseIds.Contains(e.EntryId & BASE_ID_MASK))`), keeping a
target and its paired decoy alive together. The 305 are the residue where that does not hold.

**Direction**: survivor-scoping the fold as-is drops those decoy maxima, thinning the decoy side
of the null, which pushes experiment q OPTIMISTIC - the same direction as the FDP inflation
Brendan suspects. Small at 3 files; unmeasured at 257.

### The open decision this leaves

* **(a)** Worker writes, for every retained base_id, that file's best decoy score into the
  per-run sidecar (including decoy rows that are not blib candidates). Byte-identical numbers,
  nothing reaches back to pass 1, and it does not violate the invariant - decoys are never blib
  candidates, so the artifact is "what the join needs" and blib candidacy stays separate.
* **(b)** Change the survivor set so those decoys ARE survivors - the survivor-set change
  Brendan anticipated. Principled; needs FDRBench to establish its sign.
* **(c)** Accept the loss and judge it on entrapment FDP rather than the golden.

### Consequences of the split, whichever is chosen

* Both patch passes disappear (~123 GB of serial join-stage rewrite at 257 files), and with them
  the reload machinery that exists only to put experiment values back onto entries - so R1, R4
  and R12 are resolved by DELETION rather than by fixing them.
* Cross-impl parity breaks STRUCTURALLY: Rust fuses run-scope and experiment-scope columns into
  one per-run sidecar, so the FDR-sidecar leg either needs the comparator to reconstruct Rust's
  fused view from our two files, or it goes to SKIP. The blib and Stage-7 protein-FDR legs still
  compare.
* Storage 61.6 -> ~33.5 GB, per the layout table earlier in this file.

## The split, fully specified (2026-08-28 night) - ruling (a), ready to implement

Brendan ruled **(a)**: *"Make the invariant true, if it is not already. Simply write the very few
entries that are needed but get left behind into the Pass 2 files. The code is written assuming
it is okay to reach back to pass 1 files, and we want to make that not the case (at a very low
cost). Just because you can doesn't mean it is a good design! ... Allowing any stage to access
any sidecar left behind by any task is as bad as making everything in your class public."*

So this is an ENCAPSULATION fix, not a numbers fix: the pass-2 artifacts become self-sufficient,
Stage 7 stops reaching into Stage 5's, and the reported values do not move.

### Why the relocation is REQUIRED, not optional

Stage 7 cannot stop reading 1st-pass sidecars while it still runs the per-file competition,
because that competition needs the file's whole PRE-COMPACTION population (targets and decoys at
their scores) to compute a calibrated run q. The pass-2 sidecar is survivor-scoped and always
will be. So "Stage 7 reads no 1st-pass file" and "the per-file competition lives in the worker"
are the same statement. There is no smaller coherent step.

Stage 6 reading Stage 5's per-file sidecar is NOT a violation - that is ordinary
producer-to-consumer adjacency. The violation is Stage 7 reaching back past Stage 6.

### All three global inputs the worker needs are already on disk, per file

Verified, not assumed - `FirstPassFdrTask.cs:1560-1575` writes the frozen model, the experiment
agg arm AND the protein stratum into each file's `.1st-pass.model.json`, with the comment
*"protein-compact needs the stratum as well as the model, and SecondPassFDR cannot rebuild it
... It rides in the same sidecar, so it reaches SecondPassFDR by the relay that already carries
the model."* A distributed `--task PerFileRescoring` worker loads the same file the same way.
No new relay, exactly as the 2026-08-27/28 night session concluded.

The survivor-id set does not need relaying either: the worker's own `fdrEntries` ARE that file's
survivors at the hook point below.

### The hook point in the worker

`PerFileRescoreTask.RescoreOneFile`, between `WriteReconciledAndStamp` (line ~1082) and
`ReleaseRescoredPayload` (line ~1122). At that instant the worker holds this file's survivors,
its reconciled parquet is on disk, and the heavy per-entry payload has not yet been dropped.
The release is already gated on `wroteReconciled`, so the new step slots in ahead of it.

### What the worker does per file (a faithful relocation of today's inner loop)

1. Load `.1st-pass.model.json` -> frozen model + experiment-agg arm + `stratumBaseIds`.
2. ONE traversal of this file's `.1st-pass.fdr_scores.bin` for the three things it yields:
   the whole-population `(entry_id, score)` arrays, the survivor records to seed from, and the
   off-stratum pass-1 experiment q that must be carried forward.
3. `Pass1ScalarSeeder.Apply` - Score / Pep / ExperimentAggregateScore that `ResetScores` cleared.
4. `LoadReconciledFeaturesByScoreIndex` on the reconciled parquet + `FrozenModelScorer` ->
   frozen-model score per survivor.
5. `StreamingFdr.CompeteOneFile` -> this file's run q. (Already extracted by `f7a6e6d103`; this
   is the whole reason that split was done.)
6. Stamp run q + score onto the survivors.
7. Write the immutable per-run `.2nd-pass.fdr_scores.bin`.

### What "the few entries left behind" means, concretely

The sidecar must carry every observation the JOIN's fold ranges over, which is
`population INTERSECT stratum`. Targets are covered already: gap-fill gives a surviving
precursor an observation in every run, and the measurement showed 0 target bests missing.
The residue is decoys - 305 base_ids on Stellar 3-file - because decoys are deliberately never
gap-filled. For those, the worker writes the pass-1 record FORWARD into the pass-2 file: the
decoy's own natural-best-peak score, which is exactly the value `PerFileRescoreTask.cs:2243`
says the 1st-pass parquet is being relied on for.

Those carried records are NOT blib candidates and must never re-enter the survivor pool - they
exist so the null can be computed without opening a pass-1 file. Decoys are never blib
candidates, so this does not weaken Brendan's irreversibility invariant.

### What SecondPassFDR does after the move

Streams the per-run `.2nd-pass` sidecars and computes, itself:
per-base_id bests over the stratum -> experiment competition -> experiment precursor / peptide q
-> protein FDR -> the experiment-wide sidecar (`<blib-stem>.2nd-pass.fdr_scores.bin`) and the
blib. The aggregation METHOD lives here and only here, which is what makes mean-best-N (#4484) a
Stage 7 change rather than a re-run of every worker.

`FoldFileContribution` is replaced by a fold over sidecar records. The worker emits NO
precomputed bests: a per-file partial reduction is a join task in the wrong stage, and it would
freeze the aggregation method into Stage 6.

### What gets DELETED

* `PatchExperimentValues` and `PatchPass2ProteinQvalues` - experiment-scope values are computed
  in Stage 7 and written once to the experiment file, never patched back into per-run files.
  ~123 GB of serial join-stage rewrite at 257 files.
* `ReloadPass2Sidecars` in both directions - it exists only to put experiment values back onto
  entries; Stage 7 now holds them in memory where it computed them.
* With them go review findings R1 (kill window between write and patch), R4 (duplicate-EntryId
  degradation on resume) and R12 (redundant post-write reload) - resolved by deletion.

### Gates, and what is EXPECTED to move

* `regression.ps1 -Dataset Stellar` - the golden must NOT move. Mode 1c (2nd-pass protein q
  really is pass-2) and mode 3 (per-file FDR sidecars == straight) are the two that would catch
  a botched carry-forward.
* Cross-impl parity WILL break structurally on the FDR-sidecar leg: Rust fuses run-scope and
  experiment-scope columns into one per-run file, so there is no like-for-like comparison once
  ours are split. Either the comparator reconstructs Rust's fused view from our two files, or
  that leg goes to SKIP. The blib and Stage-7 protein-FDR legs still compare and must stay green.
* The 2nd-pass sidecar record set grows by the carried decoys (305 on Stellar). Any comparator
  that asserts record-count equality with Rust needs that allowance.

### Sequence

1. Worker-side per-file pass-2 (steps 1-7 above), still with Stage 7 unchanged behind an
   env-gated switch or a straight cutover - gate on Stellar, expect byte-identical.
2. Carried-forward decoy records into the per-run sidecar.
3. Stage 7 folds from the sidecars; delete both patch passes and the reload machinery.
4. Comparator/`regression.ps1` adjustments for the split artifact shape.
5. THEN the lean row (deferred by Brendan tonight: *"Let's not do the lean row until we land the
   parts I thought were done, but are not."*), and only then a 257-file validation run.

**No 257-file run until this lands** (Brendan, 2026-08-28): *"I don't want to launch a night run
without the code to support it resolved."* The rig is staged and ready - launcher at
`ai/.tmp/sessions/20260827-stage7-leanrow/launch-stage57-257.ps1`, base run dir
`chs-257files-libdecoy-r1.0-protein-compact-p0059_0060_0061`, exe snapshot
`D:\test\osprey-runs\_bin\26.1.1.240-splitbase-20260828`, oracle 5,079 / 45,724 / 11,745,026.

### Session end 2026-08-28 night - four gated commits, split specified, extraction landed

`c7e44d67d0` dead streaming path + sort assertions | `c2669870c6` blib absolute source path
(BlibBuild convention) | `88240243a0` verified review findings + nullable adoption completed |
`3e4d94ed58` extracted `ReadOneFilePass2Inputs` (the per-file half, explicitly parameterized).
Each gated build + 599/599 + ReSharper 0/0 + `regression.ps1 -Dataset Stellar` 10/10.

**TeamCity `pull/4621` build 4157122: SUCCESS** - all four datasets, every mode, plus the perf
leg. **Cross-impl Astral: PASS on all four legs at 1e-9**, with the RetentionTimes leg genuinely
comparing 351,756 rows for the first time (the blib-path fix un-vacuumed a 0-row join).

**Next session handoff**: read `ai/.tmp/handoff-20260829_osprey_pass2_scope_split.md` before
starting work.

## NIGHT SESSION 2026-08-29 - the sidecars are split by scope (format v5)

Commit 1 of the two the handoff asked for. Both passes now write two artifacts instead of one
mutable one, and the three patch passes are down to one. Commit 2 (the relocation) was NOT
attempted - see "What was not attempted" below.

### The layout as built

| artifact | scope | record | one per |
|---|---|---|---|
| `<input>.<pass>.fdr_scores.bin` (v5, magic `OSPRYFDR`) | RUN | 36 B: entry_id, svm_score, run_precursor_q, run_peptide_q, pep | OBSERVATION, per input file |
| `<blib-stem>.<pass>.fdr_experiment.bin` (v1, magic `OSPRYEXP`) | EXPERIMENT | 36 B: entry_id, experiment_precursor_q, experiment_peptide_q, experiment_protein_q, experiment_aggregate_score | DISTINCT entry_id, one file per pass per analysis |

New files: `Osprey.IO/FdrExperimentRecord.cs`, `FdrExperimentSidecar.cs`,
`FdrExperimentAccumulator.cs`.

**Two deviations from the handoff, both deliberate:**

1. **`fdr_experiment.bin`, not `fdr_scores.bin`.** The handoff named the experiment file
   `<blib-stem>.1st-pass.fdr_scores.bin` and flagged "blib-stem vs input-stem collision -
   check and guard". A distinct filename token IS that guard, and it is structural: the
   collision cannot happen, so there is no runtime check that can be wrong and no failure mode
   for a legitimate configuration (a blib named after an input file is real). Different magic
   backs it up - each reader rejects the other's file rather than decoding it.
2. **`FdrScoreRecord` lost its four experiment fields rather than only the byte layout
   changing.** The handoff warns "the compiler will not catch a byte-offset reader". Splitting
   the STRUCT makes every such reader a compile error, which is how the consumer list below was
   found rather than guessed.

### THE ONE PLACE THE SPEC DOES NOT WORK: `pep` - needs Brendan's ruling

The handoff's table puts `pep` in the per-file RUN-scope record for both passes and says all
three patch passes die. **`pep` cannot satisfy both.**

* Its VALUE is per-observation: `PercolatorQValues.ComputePepWinnerMap` fits the estimator over
  the target/decoy competition WINNERS and keys the result by the winner's flat row index, so
  exactly ONE observation per base_id carries a real PEP and every other observation of that
  precursor carries 1.0. `StreamingFdr.Pep(fileKey, entryId)` is the pass-2 twin and is
  explicit about it. An entry_id-keyed experiment record cannot express WHICH observation won,
  so `pep` genuinely does not belong in the experiment file.
* Its TIMING is experiment-wide: on pass 2 the frozen competition writes each file's sidecar
  mid-stream, before the competition that decides the winner has finished. So it also cannot be
  final in the per-file record at write time.

Per-observation value, experiment-scope timing: it fits neither artifact.

**What I did**: kept `pep` in the per-file record exactly as the handoff's table says, and kept
ONE streamed patch for that column alone - `FdrScoresSidecar.PatchPep`, replacing
`PatchExperimentValues`. `PatchProteinQvalues` and `PatchPass2ProteinQvalues` are DELETED, and
so is `ReloadPass2Sidecars`. Pass 1 never patches at all: its sidecars are written after the
whole first-pass competition, so they are write-once already.

**Why I did not improvise past it**: the alternative is to move pass-2 `pep` into the experiment
record, which is safe *today* only because pass-2 PEP has no consumer - the blib writes a 0.0
placeholder (`BlibOutputWriter.cs:313`), and the only reader was `ReloadPass2Sidecars`, which
this commit deletes. That is an argument for deleting the column, not for storing it wrong, and
it is a semantics change the handoff says to report rather than guess at.

**Options for Brendan**, cheapest first:

* **(a) keep `PatchPep`** (what is in the tree). One 4.9 GB rewrite survives at 257 files, down
  from ~123 GB. The per-file pass-2 artifact stays mutable, so review finding R1's kill window
  survives for that one column.
* **(b) drop `pep` from the pass-2 per-file record entirely.** It has no consumer. The two
  passes then have different run-scope record shapes, and the cross-impl comparator loses a
  column Rust writes.
* **(c) move pass-2 `pep` to the experiment record**, keyed by entry_id (the winner's value,
  1.0 elsewhere - representable exactly, since at most one entry_id per base_id wins). Loses
  which FILE the winner was in; nothing reads that today.

Pass-1 `pep` must stay per-observation whichever is chosen: it reaches the `--model-diagnostics`
report through the hydrate paths, and that report is golden-compared.

### The trap the handoff flagged DID fire, and the design absorbs it

*"Do not assume which q the Stage 6 survivor re-derivation reads."* It reads
`experiment_protein_qvalue` - an EXPERIMENT-scope column - in both compaction predicates (the
resident branch in `FirstPassFdrTask`, and the streamed `ComputeFirstPassBaseIds`). The v2->v3
sidecar note says so explicitly; the handoff's "that threshold is a RUN-scope q" is wrong.

This does NOT need a rethink. The 1st-pass experiment file is written by FirstPassFDR *after*
first-pass protein FDR and *before* compaction, so the gate reads it from there - two Stage 5
outputs consumed by Stage 6, which is ordinary producer-to-consumer adjacency, not the Stage 7
reach-back #4486 is about. `LoadFirstPassExperimentRecords` fails the run rather than defaulting
to 1.0 when the file is missing: a silently absent protein q turns the protein-rescue clause off
and reports a smaller result that still looks like a successful run.

### Two things got SIMPLER than expected

* **The off-stratum stash is gone.** `pass1ExpQByKey` + `StashOffStratumPass1ExperimentQ` existed
  to recover the pass-1 experiment q of off-stratum peaks Stage 6 had CHANGED, because
  `ResetScores` had zeroed the in-memory value - and `ResetScores` only touches peaks Stage 6
  touched, which is why unchanged ones needed no stash. With one analysis-wide record per
  entry_id both dispositions read the same place and the conditional disappears.
* **The cross-file experiment scan collapsed to one read.** `ComputePass2TransferCompeteFull`
  reduced `globalExpPrecQ` / `globalExpPepQ` / `globalExpAgg` by MIN/MAX across EVERY file's
  1st-pass sidecar. That reduction was over copies of one value, so it now reads the experiment
  file once. `AssignPerRunQ` lost three parameters as a result, and gap-fill stopped being a
  special case - every disposition takes the same record.

### Consumers found by the compiler (the reason the struct was split, not just the bytes)

`FdrProjectionSinks` (both sinks), `FirstPassFdrTask` (resident write, projection write, protein
FDR, compaction gate, both hydrate call sites), `FirstPassSurvivorLoader`, `RescoreHydration`
(both hydrate entry points), `PerFileScoringTask` (both hydrate call sites),
`PeakCoAssignmentSource` (both readers + `EffectiveQvalue`), `Pass2FdrSidecar`
(`Pass1ScalarSeeder`, the frozen competition, `AssignPerRunQ`, the streaming sink,
`WritePass2ExperimentSidecar`).

**The hydrate paths matter more than they look.** `FirstPassSurvivorLoader` and
`RescoreHydration` overlay experiment values onto stubs because those stubs feed
`ScoringTaskShared.FeedModelDiagnostics`, and the `--model-diagnostics` report is compared
against a committed golden (mode 1b, and mode 5 re-emits it from its own sidecars). A hydrated
stub that lost its experiment q would not fail at the read - it would fail as a wrong number in
a report two stages later. The loader reads the experiment map ONCE in its constructor because
`PerFileRescoreTask` drives it from inside a `Parallel.For`.

### The collapse is asserted, not trusted

`FdrExperimentAccumulator.Add` throws if two observations of one entry_id carry different
experiment values. The whole split rests on those four columns being a property of the
precursor; a first-wins collapse over values that had quietly diverged would report q-values no
run computed, and BOTH routes would collapse the same way, so no self-consistency gate could see
it. Bitwise equality, no tolerance - a tolerance would only decide how much of a wrong answer to
accept.

### Harness

`Regression/FdrSidecars.ps1`: per-file decoder moved to v5 / 36 B (4 fields); new
`ReadExperimentIfValid` + `ExperimentFields` for the `OSPRYEXP` file; `CheckPass2ProteinQ`
(`Test-Pass2ProteinQvalue`, issue #4559) now compares the two EXPERIMENT files, which is where
that column lives. `regression.ps1` mode 3 additionally byte-compares the two experiment
sidecars between routes - exact, because both routes write ascending entry_id order - and treats
absence as a FAILURE rather than a skip.

Test surface: `TestFdrScoresSidecarRoundTrip` trimmed to the run-scope columns and now asserts
the experiment fields come back UNTOUCHED (a reader still writing them would be decoding another
field). The three tests for the deleted patch methods were replaced by one consolidated
`TestFdrScopeSplitV5` covering the experiment round trip + canonical ordering, the collapse
assertion, mutual magic rejection, and `PatchPep` byte-identity against a single-phase write.

### Stellar 10/10 green — and the three defects the gate caught (2026-08-29 01:58)

```
mode1  (vs golden)                         PASS
mode1c (2nd-pass protein q is pass-2)      PASS  (23,618 of 333,404 shared records moved;
                                                  0 gap-fill records absent from pass 1)
mode3  (per-file FDR sidecars==straight)   PASS  (3,263,679 records)
mode3  (HPC chain==straight)               PASS
mode4  (warm re-run all cached)            PASS
mode2  (resume cache hits / ==straight)    PASS
mode5  (rehydrate entered / ==straight)    PASS
mode6  (library-fragment release engaged)  PASS
```

The golden did NOT move. Mode 1c is worth noting: it now runs against the two EXPERIMENT files
rather than the per-file ones and still detects that the pass-2 protein q is a genuine pass-2
value, so the #4559 guard survived the move instead of being quietly defeated by it.

The first three attempts were red. Every defect was in the new plumbing, none in the layout, and
each was found by the gate rather than by argument:

**Defect B - the golden moved** (mode 1: 32 precursors gained, 3 lost, experiment q
0.0099 -> 0.0053). The pass-2 experiment values reached the FILE but never got back onto the
resident entries the blib is written from. That round trip used to be implicit:
`PatchExperimentValues` wrote the finished values into the per-file sidecar and
`ReloadPass2Sidecars` pulled them back onto the entries. Deleting the patch and leaving the
reload standing broke it silently. Fixed by `ApplyPass2ExperimentValues`, stamping from the
in-memory accumulator - which is what "Stage 7 computes them and can hold them" actually
requires.

**Defect A - the HPC chain** (mode 3). `FdrExperimentSidecar.PathFor` took the file's DIRECTORY
from the output blib. Every chain phase runs in its own working directory with the same relative
`-o output.blib`, so phase 2 wrote the 1st-pass experiment file into its own phase directory and
phase 3 looked beside ITS blib and found nothing. The per-file sidecars are immune because they
route through `ArtifactPaths.ResolveOutputDir`. Fixed both halves: the blib now supplies the
STEM only (which is what answers the collision concern) with the directory resolved the way
`Pass1Path` resolves it, AND `regression.ps1` relays the run-level file phase2 -> phase3 ->
phase4 alongside `.1st-pass.model.json`, because the chain harness stages each Stage-5 artifact
explicitly and a new one is not carried forward for free.

**Defect B' - resume** (mode 2). A resume that adopts standing 2nd-pass sidecars recomputes
nothing, so there is no accumulator to stamp from. Before the split both cases were served by
the same mechanism because the values rode in the per-file sidecar the reload overlays. Fixed:
`ApplyPass2ExperimentValues` falls back to reading the 2nd-pass experiment sidecar from disk.

### The lesson worth keeping: the compiler-enforced split has a hole

Splitting `FdrScoreRecord` rather than only the byte layout made every CONSUMER of an experiment
column a compile error, and that is how the consumer list was found rather than guessed. It
worked exactly as intended - everywhere the compiler could see.

`FdrScoresSidecar.TryReadOverlay` is where it could not. That method WRITES fields onto a mutable
`FdrEntry`; dropping four assignments from it compiles cleanly and silently, and that is precisely
where defect B lived. **Anything that mutates `FdrEntry` rather than consuming `FdrScoreRecord`
is outside the net.** If this pattern is used again - and it should be, it earned its keep - the
mutating writers have to be enumerated by hand.

### Owed before merge

* **Tighten the tolerant readers.** `FirstPassSurvivorLoader` and
  `Pass2FdrSidecar.LoadExperimentRecords` treat a missing experiment sidecar as "no records" and
  proceed on defaults. That tolerance is what let defect A run the whole chain to completion on
  wrong inputs instead of stopping, and it is against this repo's hard-fail-over-warn-and-proceed
  rule. `FirstPassFdrTask.LoadFirstPassExperimentRecords` already fails hard and is the model.
* **The `pep` ruling** (three options above).
* **Cross-impl**: expected to break structurally - Rust still fuses both scopes into one 68-byte
  per-file record. Not run, not adjusted.

### Three more defects, all the same shape (2026-08-29 03:00-04:10)

Stellar green was not the end. `-Dataset All` and the diagnostics datasets found three more, and
they belong with the first three: **every one is absence being turned into a plausible value
instead of a stop.**

**C - the co-assignment panel's acceptance boundary collapsed to zero.**
`StellarLibDecoy mode1b`, 11 metrics. `pass1.coAssign.cutoff` 0.669 -> 0, decoys 272 ->
483,220. `experimentRecords.TryGetValue(id, out var exp)` leaves `exp` as
`default(FdrExperimentRecord)` on a miss, i.e. `ExperimentAggregateScore = 0.0`. The cutoff is a
MINIMUM over accepted precursors' aggregates, so fabricated zeros drag it to 0 and admit
everything. `StreamingFdr.ExperimentAggregateScore` chose `double?` over an in-band sentinel to
prevent exactly this, and its remarks name the same 542,368-decoy failure on astral. A struct
default walked straight back into it.

**C' - and the panel could never have read the file anyway.** `PeakCoAssignmentSource.Build` is
called from the score-pass path BEFORE first-pass protein FDR, and the experiment sidecar is not
written until after it. Reading the file there returned an empty map every time. Fixed by having
the CALLER supply the records: the score-pass path passes the in-memory accumulator (the three
columns the panel reads - experiment precursor q, peptide q, aggregate - are all final there;
only the protein q it does not use is still pending), and the rehydrate path passes a map read
off the sidecar an earlier run left. A missing/empty map now SKIPS the panel with a named
reason instead of silently zeroing it.

**D - over-application across files.** `Astral mode1b`, one metric:
`pass2.coAssign.experiment.target.nBetter` 13,270 -> 13,279. Nine records. My
`ApplyPass2ExperimentValues` stamped every resident entry whose entry_id appeared in the
analysis-wide map. The mechanism it replaced did not: `ReloadPass2Sidecars` overlays each file's
own 2nd-pass sidecar, so an entry got experiment values only where THAT FILE's second pass
actually covered it. An entry_id that survived in file A but not in file B was picking up A's
values on B's entry.

Fixed by restoring the original scoping rather than reproducing it: `TryReadOverlay` takes the
experiment map and applies it to the records it matches, which is by construction the file's own
set. `ApplyPass2ExperimentValues` is gone, replaced by `ResolvePass2ExperimentRecords` feeding
the overlay. That also re-unifies the recomputed and resume cases, which had needed separate
handling.

### The through-line, and what it means for review

Six defects tonight. Zero in the layout, the per-entry_id collapse, the collapse assertion or
the compaction gate. **All six were absence handling**:

| | absence of | became |
|---|---|---|
| B | values on entries (patch+reload pair broken) | stale experiment q |
| A | experiment file in a per-phase directory | empty map; chain ran on defaults |
| B' | accumulator on the resume path | pre-competition values |
| C | one entry's record | 0.0 aggregate -> cutoff 0 |
| C' | the file, read before it was written | empty map |
| D | the file-scoping the old mechanism had | values applied too widely |

Not one was found by reading the code; every one was found by a gate. That is the argument for
the two remaining tolerant readers being tightened before merge rather than after
(`FirstPassSurvivorLoader`, `Pass2FdrSidecar.LoadExperimentRecords`): they are on the
distributed path, they return an empty map on failure, and an empty map is the exact input that
produced A and C'.

`FdrExperimentAccumulator.Add`'s hard throw is the one place this was designed in from the
start, and it is the only invariant that never needed a fix.

# FINAL RESULT — `-Dataset All`: one assertion short

`regression.ps1 -Dataset All`, run 04:12-05:2x with every fix in:

**Everything passes except ONE metric.** Stellar, StellarLibDecoy and StellarGenDecoyEntrap are
clean across all modes. Astral is clean on mode 1 (the blib), mode 1b's FDR sanity bounds, and
modes 2/3/4/5/6. The single failure is:

```
ERROR: Astral mode1b (diagnostics vs golden): FAIL -- 1 issue(s)
    diagnostics: pass2.coAssign.experiment.target.nBetter golden=13270 run=13279 diff=9
```

Nine records out of 13,270 — 0.07% — on one panel of the model-diagnostics report. **Nothing
reported to a user moved**: not the blib, not the protein FDR, not the entrapment FDP bounds.
But the golden moved, so per the handoff's guardrail this is NOT committed.

## What I ruled out

* **Not defect D.** I fixed the over-application (experiment values applied to every entry
  sharing an entry_id rather than only where that file's pass-2 sidecar covered it) and this
  metric did not move by a single record — 13,279 before and after. That fix is still correct
  and stays in, but it is not this.
* **Not flaky.** Identical numbers on two independent `-Dataset All` runs.
* **Not the pass-1 panel.** `pass1.coAssign.*` all pass now, on all datasets.

## Where the 9 records come from — the panel reads entries, not artifacts

`ModelDiagnosticsData.BuildCoAssignment` drives its builder straight off the resident
`perFileEntries`, reading `e.ExperimentAggregateScore` and `e.EffectiveExperimentQvalue(...)`.
So the difference is nine entries whose experiment aggregate or experiment q differs from the
golden run's after pass 2 — not a difference in any file on disk.

## The best-supported remaining hypothesis (UNPROVEN)

**`ComputePass2Resident` never publishes a `Pass2ExperimentScope`.** Only
`ComputePass2TransferCompeteFull` (line ~1553) and `ComputePass2Projection` (line ~1935) do.
Consequences on the resident path:

* `ResolvePass2ExperimentRecords` finds no scope and falls back to reading the 2nd-pass
  experiment sidecar from disk, which on a fresh run does not exist yet at reload time — so the
  overlay applies no experiment values and entries keep whatever they hold.
* `WritePass2ExperimentSidecar` takes its early return, so **no 2nd-pass experiment file is
  written at all on that path.**

The second consequence is a definite defect regardless of whether it explains the 9. Whether the
first one changes numbers depends on whether the resident path's entries already hold correct
pass-2 values from `RunPercolatorFdr` scoring them in place — I believe they do, which is why I
could not close the argument.

**First thing to check**: does Astral's straight-through run directory contain
`output.2nd-pass.fdr_experiment.bin`? Stellar's does (333,404 ids), which means Stellar took the
projection path. If Astral's is missing, Astral is on the resident path and this hypothesis is
live; if it is present, the hypothesis is dead and the 9 are elsewhere.

## Suggested approach for whoever picks this up

The panel is deterministic and the delta is nine records, so the fast route is a dump rather
than more reasoning — I burned an hour of reasoning on this and got nowhere, having already been
wrong twice tonight about causes that looked obvious.

1. Answer the artifact question above (one `Get-ChildItem`).
2. If resident: publish the accumulator from `ComputePass2Resident` too, built from the entries
   after `RunPercolatorFdr` has scored them, and re-run `-Dataset Astral`.
3. If that is not it, dump the nine: the panel's `nBetter` inputs are `e.EntryId`,
   `e.ExperimentAggregateScore` and the effective experiment q, all off resident entries, so an
   env-gated dump of those three at the panel's entry compared between this branch and
   `3e4d94ed58` names the records directly.

## UPDATE on the 9 records — resident-path hypothesis is DEAD, and there is a better one

**Measured**: `Astral\straight\output.2nd-pass.fdr_experiment.bin` exists, 48,974,360 B =
1,360,398 records. So Astral takes the PROJECTION path, which does publish a
`Pass2ExperimentScope`. The "`ComputePass2Resident` never publishes" hypothesis cannot explain
the 9 and is eliminated.

(It is still a real defect on its own: a run that takes the resident pass-2 path writes no
2nd-pass experiment sidecar at all. Worth fixing regardless — just not this.)

### New leading hypothesis: the seeder leaves the aggregate at 0.0, and 0.0 ranks high

`Pass1ScalarSeeder.ApplyRecord` used to be unconditional:

```csharp
entry.ExperimentAggregateScore = rec.ExperimentAggregateScore;   // BEFORE - always set
```

The per-file record ALWAYS carried an aggregate, so every seeded entry got one. It is now
conditional on the analysis-wide map having the entry:

```csharp
if (_experimentRecords != null && _experimentRecords.TryGetValue(rec.EntryId, out var exp))
    entry.ExperimentAggregateScore = exp.ExperimentAggregateScore;   // AFTER - may not fire
```

An entry the map misses keeps `ResetScores`' **0.0**. And 0.0 is not a neutral value here — this
codebase has measured it twice: *"0.0 sits above 93-99% of measured aggregates"*
(`CoAssignmentAccumulator.ObserveCutoff`) and it is why
`StreamingFdr.ExperimentAggregateScore` returns `double?` rather than 0.0. A handful of entries
sitting at 0.0 instead of their real negative score would rank ABOVE almost everything and
inflate exactly the counter that moved.

**Direction, magnitude and metric all fit**: `nBetter` went UP by 9, on the EXPERIMENT scope
(the only scope that reads the aggregate), on the one dataset large enough for a 9-record tail
to exist.

What it needs is the answer to: *which 9 entry_ids are in a file's 1st-pass sidecar but not in
the 1st-pass experiment file, and why?* Both are written from the same score pass
(`FdrStoringSink.AcceptOutput` adds to the accumulator and buffers the record together), so in
principle the sets are identical — which is why this needs measuring rather than arguing. Prime
suspects: rows that reach the per-file buffer through a path other than `AcceptOutput`, and the
0-record sidecars `OnFinish` flushes for empty files.

### Concrete next step

Instrument `Pass1ScalarSeeder.ApplyRecord`'s else-branch — count and log the entry_ids the map
misses, run `-Dataset Astral`. If the count is 9, this is closed and the fix is to make the miss
impossible (or fatal) rather than silent. If it is 0, the hypothesis is dead too and the dump
described above is the route.

**Note the shape.** If this is right, it is the SEVENTH defect of the night and the seventh of
the same kind: an absence quietly becoming a plausible number. The recurring fix is not more
care at each site — it is refusing to let a lookup miss produce a value at all.

## UPDATE 2 — the seeder hypothesis is dead too, and the split itself is independently validated

Tested directly against the failing run's own artifacts (no rebuild, no re-run) by decoding
`Astral/straight/output.1st-pass.fdr_experiment.bin` and every per-file
`*.1st-pass.fdr_scores.bin` beside it and comparing entry_id sets
(`ai/.tmp/sessions/20260829-scope-split/checkids.py`):

```
experiment records: 2,498,773   distinct: 2,498,773
per-file rows:      6,226,744
rows whose entry_id is NOT in the experiment file: 0     distinct missing: 0
```

**Zero misses.** `Pass1ScalarSeeder.ApplyRecord`'s map lookup never fails, so no entry is left at
the 0.0 reset default and that hypothesis is eliminated.

Two things worth keeping from this measurement, independent of the open failure:

* **The per-entry_id collapse is lossless and duplicate-free on real data** - 2,498,773 records
  for 2,498,773 distinct entry_ids, covering all 6,226,744 per-file rows. That is the split's
  central premise, measured on Astral rather than argued.
* **6,226,744 rows collapse to 2,498,773 experiment records** - a 2.5x reduction on a 3-file
  analysis, and the ratio grows linearly with file count. This is the saving the whole change
  exists for, confirmed end to end.

### Where that leaves the 9 records

Both concrete hypotheses are now eliminated by measurement:

1. ~~`ComputePass2Resident` never publishes the accumulator~~ - Astral takes the projection path
   (its 2nd-pass experiment file exists, 1,360,398 records).
2. ~~The seeder leaves aggregates at 0.0 on a map miss~~ - there are no map misses.

What remains unexamined is the pass-2 side of the panel's inputs on the projection path. The
overlay applies experiment values only to records the file's own 2nd-pass sidecar carries, which
is what the pre-split code did, and the accumulator's hard equality check proves every
observation of an entry_id agreed - so by construction the values written back should be the
ones the old sidecar column held. I could not find the gap by reading, and I have been wrong
twice tonight about causes that looked obvious, so the next step should be a dump, not another
argument:

**Dump `(EntryId, ExperimentAggregateScore, EffectiveExperimentQvalue)` for every entry at the
point `BuildCoAssignment` runs, on this branch and on `3e4d94ed58`, and diff.** Nine rows will
name themselves, and the panel is deterministic so one run of each suffices. `-Dataset Astral`
is the only dataset that reproduces it.

Worth remembering that `ComputePass2Resident` not publishing is still a genuine defect - a run
on that path writes no 2nd-pass experiment sidecar at all. It just is not this one.

## `-Dataset All` FINAL TALLY (run 04:12-06:02)

**52 assertions PASS, 3 FAIL — and the 3 are ONE metric surfacing in three legs:**

```
Astral mode1b (diagnostics vs golden)            FAIL (1)
Astral mode5 (rehydrate diagnostics vs golden)   FAIL (1)
Astral mode7 (diagnostics regeneration)          FAIL (1)

  all three: pass2.coAssign.experiment.target.nBetter  golden=13270 run=13279 diff=9
```

Everything else is green: Stellar, StellarLibDecoy and StellarGenDecoyEntrap complete across
every mode, and on Astral itself mode 1 (the blib), mode 1b's FDR sanity bounds, mode 5's
`rehydrate==straight` and its sanity bounds, and modes 2/3/4/6.

Three facts that narrow it, all from this run:

* **One defect, not three.** Identical metric and identical numbers in all three legs. Mode 5
  re-emits the report from persisted sidecars and mode 7 regenerates it, and both reproduce the
  value exactly — so whatever causes the 9 is captured in the artifacts, not transient in-memory
  state.
* **The populations are identical.** `target.n`, `decoy.n`, `entrapment.n` and every other
  coAssign counter pass. Only `nBetter` moved. So no entry was added, dropped or reclassified —
  exactly 9 comparisons flipped, which is a small value difference near a comparison boundary.
* **Pass 1 is clean.** `pass1.coAssign.*` passes on every dataset including Astral. Only the
  PASS-2 panel moved.

Nothing a user reads has changed: not the blib, not the protein FDR, not the entrapment FDP
bounds. But the golden moved, so this is **NOT COMMITTED** per the handoff's guardrail. HEAD is
still `3e4d94ed58` and the work is in the working tree.

## THE 9 RECORDS, ROOT-CAUSED: the pass-2 experiment columns encode PARTICIPATION, not just value

Found by branch-vs-baseline dumping of the pass-2 co-assignment panel's own inputs
(`OSPREY_DIAG_COASSIGN_INPUT`, temporary instrumentation in
`ModelDiagnosticsData.BuildCoAssignment`, NOT committed).

### The measurement

360 target entries diverge at the panel's input, all in the same direction - baseline holds the
`ResetScores` DEFAULT, branch holds a real value:

```
agg[target]     360 differing    branch=-6.5414846737289745   base=0
exp_q[target]   153 differing    branch=0.12920411566147463   base=1
```

Tracing where the branch value came from, against the branch run's own artifacts:

```
branch agg matches the 2nd-pass EXPERIMENT sidecar value:  360 of 360
branch agg matches the 1st-pass experiment value:            0
has a record in its OWN file's 2nd-pass sidecar:           360 of 360
```

So the overlay is correctly scoped - every one of these entries IS in the file's own sidecar.
Reading the BASELINE's fused v4 record for the same entries settles it:

```
entry 11989   record_agg=0.0   record_exp_prec_q=1.0   score=-6.943183522208876
entry 45972   record_agg=0.0   record_exp_prec_q=1.0   score=-10.805635380008322
```

**The pre-split per-file record held 0.0 / 1.0 for an entry whose analysis-wide experiment value
is a real number.**

### What that means

The four experiment-scope columns are per-entry_id in their VALUE but per-(file, entry_id) in
their DEFAULTEDNESS. An observation that took no part in the experiment fold carries the
defaults; the same entry_id carries a real value elsewhere. The per-file record was therefore
encoding TWO things - the value, and whether this observation participated - and the v5 collapse
keeps the first and loses the second.

**Why the collapse assertion did not catch it.** `FdrExperimentAccumulator.Add` compares
observations and throws on disagreement, and it never fired. It is fed from the SCORE PASS, where
every observation supplies the computed value; the 0.0 does not exist at that point. It appears
later, when a record is written from an ENTRY still holding its reset defaults. The assertion is
still correct about what it checks - it just cannot see this, because the divergence is
introduced after the accumulator is done.

**Why scoping cannot fix it.** The overlay is genuinely required for participants: removing it is
what produced the original golden move (defect B), because on the projection path the entries do
not otherwise receive pass-2 experiment values. It must fire for participants and not for
non-participants - and post-split nothing on disk distinguishes them.

### This is the same class as the `pep` finding

Both are cases where a column that looks experiment-scope is not purely a function of entry_id:

* `pep` - real on ONE observation per base_id, 1.0 on the rest. Per-observation by construction.
* `experiment_aggregate_score` / experiment q - real on participating observations, defaulted on
  the rest. Per-observation in its defaultedness.

The scope split's premise holds for the 1st pass (Stage 6 is byte-identical after the gap-fill
fix, over 3,470,075 rows) and for the VALUES in the 2nd pass. It does not hold for 2nd-pass
participation.

### Options - this needs a ruling, it should not be improvised

* **(a) Restore participation to the per-file 2nd-pass record.** A 1-byte flag, or keep
  `experiment_aggregate_score` there as well. Cost: the pass-2 per-file record grows from 36 B to
  37 B (flag) or 44 B (aggregate), against 68 B before the split - so most of the saving survives.
  A flag is the smaller change and covers both agg and q; keeping the aggregate covers only agg
  and would still leave the 153 q rows wrong.
* **(b) Do not overlay experiment values onto non-participants**, deriving participation some
  other way (e.g. the entry's own run q still being 1.0). Cheap, but it INFERS a state that used
  to be recorded, and this session has already shown what inference costs here.
* **(c) Accept the change and rebaseline.** Forbidden by the session guardrail, and it should be:
  the branch value is arguably more informative, but it changes a reported diagnostic without a
  decision behind it.

**Recommendation: (a) with a flag.** It records the thing that is actually per-observation
instead of re-deriving it, it is one byte, and it keeps the collapse honest for the values -
which is the part of the design that measured out well.

### Note on the numbers

360 entries diverge at the panel input; only 9 change the reported `nBetter`. The other 351 shift
values that do not cross a comparison boundary. So the reported metric understates the divergence
by 40x - worth remembering when judging "how bad is a 9-record diff".

### The 360 are a SENTINEL READING, and v5 made it unreadable (Brendan, 2026-08-29)

Brendan's framing, and it is the right one: *"run_q = 1 and agg = 0 is a sentinel reading,
because agg = 0 should mean run_q = 0.01."* A genuine aggregate of 0.0 sits AT the acceptance
boundary - `project_osprey_zero_is_the_score_boundary` - so it should be accompanied by a run q
around the FDR threshold, not by 1.0. The pair is self-contradictory for real data, which is
exactly what makes it recognizable as "this observation carries no experiment result".

**Measured on the baseline Astral run, 3,470,075 rows:**

| predicate | count |
|---|---|
| `run_q == 1` | 1,374,571 |
| `run_q == 1` AND `agg == 0` | **360** |
| divergent rows (branch vs baseline) | **360** |
| divergent rows absent from their file's 1st-pass sidecar (gap-fill) | **360 of 360** |

So there are two equivalent characterizations of the same set:

* **Why they are defaulted**: they are GAP-FILL entries - appended by Stage 6, no 1st-pass record
  for that (file, entry_id), so `Pass1ScalarSeeder` never restored their Score/Pep/aggregate and
  they kept `ResetScores` defaults.
* **How you would detect it**: the contradictory pair `run_q == 1 && agg == 0`.

Note `run_q == 1` ALONE is nowhere near sufficient - 1,374,571 rows have it and 1,374,211 of them
carry a real aggregate. Any fix keyed on run q by itself would corrupt 1.37 M rows to repair 360.

### The decisive consequence: v5 removed the field the sentinel lives in

The sentinel reading needs the AGGREGATE, and the v5 per-file record is
`entry_id, score, run_precursor_q, run_peptide_q, pep` - the aggregate moved to the experiment
sidecar. **So the reading is unevaluable from the new record**, and "derive participation from
run-level information" cannot be implemented as a predicate over what v5 persists.

That collapses the options to one: the pass-2 per-file record has to carry per-observation state
again - the aggregate itself, or a flag standing in for it.

### And the sentinel itself should be fixed while the field comes back

`agg = 0.0` meaning "did not participate" is a LATENT HAZARD that predates the scope split. This
codebase has already paid for it twice and documented both:

* `CoAssignmentAccumulator.ObserveCutoff`: *"0.0 sits above 93-99% of measured aggregates, so a
  max would let a single default row outrank every real (negative) one."*
* `StreamingFdr.ExperimentAggregateScore` returns `double?` rather than 0.0 precisely so a
  consumer cannot mistake "not competed" for a mid-distribution score - and names the 542,368
  decoys vs 117,783 targets astral failure that resulted.

The in-memory API got this right; the PERSISTED form fell back to 0.0 anyway. If the column is
returning to the record, it should return with an unambiguous sentinel.

**`double.NegativeInfinity` is the natural choice**: `ExperimentBest` already uses it for
"missing", it can never win a max, and it round-trips through G17. NaN is not - this codebase
rejected it because the sidecar comparators test `Math.Abs(a - b) <= tolerance`, which is false
for NaN against NaN, turning byte-identical files into a red gate.

### Recommended shape

* Pass-2 per-file record: `entry_id, score, run_precursor_q, run_peptide_q, pep,
  experiment_aggregate_score` = 44 B (against 36 B now and 68 B before the split).
* `experiment_aggregate_score` = `NegativeInfinity` for an observation that took no part in the
  experiment fold, never 0.0.
* The experiment sidecar keeps the three q-values, which ARE per-entry_id.
* `TryReadOverlay` applies the experiment q only where the record shows participation, and takes
  the aggregate from the record.

This keeps the collapse where it measured out well (1st pass byte-identical over 3,470,075 rows;
2nd-pass VALUES agree), stops fabricating participation, and closes a hazard that was already
there. It also means the 2nd-pass experiment sidecar no longer needs the aggregate column at all -
worth deciding whether to drop it there rather than store it twice.

### The measurement chain for the 360, so nobody repeats it

Astral, straight-through, branch vs baseline `3e4d94ed58`. Every line below is measured, not
argued. Four candidate discriminators were eliminated; only the conjunction is exact.

| predicate | selects | verdict |
|---|---|---|
| `run_q == 1` | 1,374,571 of 3,470,075 | 3,800x over-selects |
| gap-fill (`ParquetIndex == null` / absent from the file's own 1st-pass sidecar) | 8,792 | 24x over-selects |
| entry has NO 1st-pass record in ANY file | 0 of 360 | eliminated outright |
| 2nd-pass sidecar coverage gap | 0 missing of 3,470,075 | eliminated outright |
| `run_q == 1 AND agg == 0` | **360** | **exact** |

Supporting counts:

* Gap-fill rows total **8,792** - matches mode 1c's "8,792 gap-fill record(s) absent from pass 1"
  independently.
* Of those, **360** carry the sentinel and **8,432** carry real experiment values.
* Both groups are entirely made of entries that DO have a 1st-pass record in another file
  (360 / 360 and 8,432 / 8,432). So the entry genuinely has an aggregate, and the `max()` over
  its rows is well defined - the 0.0 is NOT "this entry never competed".

**What that leaves.** The difference between the 360 and the 8,432 is at the OBSERVATION level
and is not reconstructible from any artifact tried so far. Both are gap-fill; both belong to
entries with real observations elsewhere; both are present in the file's 2nd-pass sidecar.
Something inside the pass-2 computation admitted 8,432 of them to the experiment fold and not the
other 360.

**Why this argues for stamping at computation time (option b).** Four attempts to reconstruct
participation downstream each over-selected by 24x-3800x, and a fix keyed on any of them would
have corrupted between 8,432 and 1.37 M rows to repair 360. The information is exact and free at
the moment the pass-2 competition runs; every attempt to recover it afterwards has been lossy.
That is the same shape as the other six defects in this phase - the difference between having the
information and having to infer it.

**What the 360 need, concretely.** They must reach `ModelDiagnosticsData.BuildCoAssignment` still
carrying their `ResetScores` defaults (`ExperimentAggregateScore = 0.0`,
`EffectiveExperimentQvalue = 1.0`), which is what the baseline overlay delivered by writing the
record's own values back. The v5 overlay hands them the entry's analysis-wide value instead, the
panel then counts them as detected at experiment scope, and 9 of them flip a `nBetter`
comparison. 360 diverge at the panel input; 9 reach the reported metric - so the gauge
understates the divergence by 40x.

**Reproduction, ~25 minutes**: the recipe is in the phase-2 handoff under "The technique that
actually worked". `OSPREY_DIAG_COASSIGN_INPUT` (temporary instrumentation in
`ModelDiagnosticsData.BuildCoAssignment`, NOT committed) dumps the panel's own inputs; the
comparison scripts are `diffco.py`, `trace360.py` and `diffdump.py` in
`ai/.tmp/sessions/20260829-scope-split/`.

## DECISIVE: the pass-2 "experiment-scope" columns are WINNER MARKERS, not per-entry values

Brendan's question - *"if you group the sidecar rows for these values in all 3 baseline sidecars
do the exp values match?"* - settles the whole investigation. They do NOT match.

Baseline (`3e4d94ed58`) Astral, one entry_id read from all three per-file 2nd-pass sidecars:

```
entry 11989   _49: score=-6.9432  agg=0.0      exp_pept_q=1
              _55: score=-6.5415  agg=-6.5415  exp_pept_q=0.003261
              _60: score=-4.4710  agg=0.0      exp_pept_q=1

entry 16350   _49: score=-1.4048  agg=0.0      exp_prec_q=1
              _55: score=-3.4112  agg=0.3602   exp_prec_q=0.01943
              _60: score= 0.3602  agg=0.3602   exp_prec_q=0.01943

entry 36228   _49: score=-1.1247  agg=0.0      exp_prec_q=1
              _55: score=-5.7408  agg=0.0      exp_prec_q=1
              _60: score= 1.2089  agg=1.2089   exp_prec_q=0.005957
```

**Read entry 36228**: `agg = 1.2089` is the entry's MAX score across the three runs, and it is
stamped only on the row that achieved it (`_60`). The other two rows carry `agg = 0.0,
exp_q = 1`. The columns do not hold "the entry's value, copied to every row" - they MARK WHICH
OBSERVATION REPRESENTS THE ENTRY at experiment scope.

That is deliberate, not accidental. `CoAssignmentPassBuilder.AddRow` admits a target when
`experimentQvalue <= runFdr`; under marker semantics exactly ONE row per entry is admitted, so an
entry cannot be counted once per run at experiment scope. Broadcasting the value admits all of
its rows.

### Consequences

1. **The v5 collapse premise is FALSE for the second pass.** None of the four columns
   (`experiment_precursor_qvalue`, `experiment_peptide_qvalue`, `experiment_protein_qvalue`,
   `experiment_aggregate_score`) is a function of entry_id alone in pass 2. The 1st pass is
   unaffected - Stage 6 is byte-identical over 3,470,075 rows after the gap-fill fix.
2. **The baseline is CORRECT and the branch is WRONG.** An earlier note in this file argued the
   opposite - that the 360 were a latent master bug and the branch had accidentally fixed it.
   That was wrong, and this measurement retracts it. The 360 are gap-fill rows correctly NOT
   marked as their entry's representative; the branch promotes all three rows of an entry to
   representatives, and 9 of the extra admissions flip a `nBetter` comparison.
3. **`pep` is the same phenomenon, already documented.** It is real on the single
   experiment-winner observation of each base_id and 1.0 elsewhere. So `pep`, the aggregate and
   both experiment q-values are ALL winner-marked per-observation columns. The `pep` finding was
   not a special case - it was the general rule, and it should have generalised the moment it
   was found.
4. **`FdrExperimentAccumulator.Add` could never have caught this.** It is fed from the score
   pass, where every observation supplies a computed value; the 0.0 / 1.0 marker state is applied
   later, when records are written. The assertion is sound about what it sees - it simply never
   sees the marker.

### What this means for the design

The 2nd-pass experiment sidecar as built stores one record per distinct entry_id, which cannot
represent "which observation is the representative". Options, for Brendan:

* **Keep the 2nd-pass experiment sidecar for genuinely per-entry data only** - if any of the four
  columns IS per-entry (protein q is assigned per PEPTIDE across all files by
  `ProteinFdr.PropagateProteinQvalues`, so it plausibly is) - and leave the winner-marked columns
  in the per-file record. That likely means the pass-2 per-file record keeps
  `experiment_precursor_qvalue`, `experiment_peptide_qvalue`, `pep` and the aggregate, and the
  2nd-pass experiment file carries only `experiment_protein_qvalue` - a much smaller saving than
  the design assumed, but an honest one.
* **Drop the 2nd-pass experiment sidecar entirely** and split only the 1st pass, where the
  premise is measured to hold. The 1st pass is 85% of the bytes (52.3 GB of 61.6 GB), so most of
  the win survives.

**The 1st-pass half of the split is unaffected by all of this** and remains verified: Stage 6
byte-identical over 3,470,075 rows, 2,498,773 experiment records for 2,498,773 distinct
entry_ids covering all 6,226,744 per-file rows.

### Method note

Four hypotheses were killed by measurement before this one landed, each having over-selected by
24x-3800x. The measurement that settled it was not more instrumentation - it was reading the SAME
entry across all three baseline sidecars, which took one script and no run. When a value looks
wrong on one row, read that row's siblings before theorising about the code that wrote it.

### CORRECTION to the marker-semantics note above (same session, measured after it)

The note above says the pass-2 experiment columns are "winner markers" where non-representative
rows carry 0.0 / 1.0. **That generalised from three sampled entries and is wrong about the
population.** The joint distribution over all 3,470,075 baseline pass-2 panel rows:

```
agg==0   run_q==1  exp_q==1        count
False    False     False        1,740,927
False    True      True         1,122,179
False    False     True           354,577
False    True      False          252,032
True     True      True                360      <- the ENTIRE agg==0 population

rows with agg == 0: 360   of which GAP-FILL: 360 (100.0%)
```

`agg == 0` is not common - it is exactly 360 rows, and every one is gap-fill. Most rows carry a
real aggregate, so "0.0 marks a non-representative row" is false.

**What still stands** (and is what actually breaks the split): the exp values DIFFER PER
OBSERVATION for the same entry_id. Entry 11989 carries `exp_pept_q = 1` in `_49` and `_60` but
`0.003261` in `_55`. One record per entry_id cannot represent that, so the v5 pass-2 collapse is
lossy regardless of how the 0.0 is interpreted.

**What the 0.0 actually means**: a gap-filled row that received NO experiment value at all -
360 of the 8,792 gap-fill rows, i.e. ~4% of them. Not "all gap-fill" and not "all
non-representative rows".

**Still unknown, and it is the remaining mechanism question**: what separates those 360 gap-fill
rows from the 8,432 gap-fill rows that DID receive experiment values. Nothing measured so far
separates them - same run_q (all 1), same decoy status (all targets), overlapping score ranges,
and all belong to entries with real observations in other files. Answering it needs instrumenting
master's pass-2 WRITE path (dump `(file, entry_id, ExperimentPrecursorQvalue,
ExperimentAggregateScore)` where the 2nd-pass record is written, on `3e4d94ed58`) and finding
where the two groups diverge. `pwiz-work2` is already at that commit with the diagnostic
scaffolding in place.

**Method note, again**: this correction exists because a three-entry sample was extrapolated to a
3.47 M-row population without counting the population. The count took one pass and would have
prevented the overreach.

**The predicate is the PAIR, `agg == 0 AND exp_q == 1`** (Brendan). In this dataset `agg == 0`
alone already selects exactly the same 360 rows, but that is luck, not safety: 0.0 is the score
cutoff, so a genuine aggregate of exactly 0.0 is possible, and such a row would carry a REAL
exp_q rather than 1. Meanwhile `exp_q == 1` alone selects 1,477,116 rows - it is common. Neither
column identifies the state by itself; only the conjunction does, and only the conjunction stays
correct if an entry ever lands exactly on the boundary.

### THE COLLAPSE INVARIANT, MEASURED ACROSS EVERY ENTRY (supersedes the two notes above)

Brendan asked whether any OTHER entries violate the invariant. Measured over all 3,470,075
baseline pass-2 panel rows, grouped by entry_id:

```
distinct entry_ids:                            1,360,398
with more than one row:                        1,176,712
entries whose agg   differs across their rows:       278
entries whose exp_q differs across their rows:       133
entries where EITHER differs:                        278   (0.024% of multi-row entries)
```

**The v5 collapse premise HOLDS for 99.976% of multi-row entries.** One record per entry_id is
lossless for 1,176,434 of 1,176,712. This RETRACTS the earlier claim in this file that "the
collapse premise is FALSE for the second pass" - that was extrapolated from three sampled
entries and is wrong, in the same way the "winner marker" claim was wrong.

The 278 violating entries account for exactly the 360 anomalous rows, and those rows are 100%
gap-fill, carrying `agg == 0 AND exp_q == 1` while their sibling rows carry the entry's real
values.

**Balance of evidence: this is a latent defect in master, not a designed marker.** A deliberate
rule would not fire on 0.024% of entries; a skipped assignment would. And it went unnoticed
because `exp_q = 1` excluded those rows from experiment scope, which made the bogus `agg = 0`
inert - it never reached `ObserveCutoff`'s minimum. The v5 collapse gives them the entry's value,
which is what the other 99.976% already receive, and 9 of the newly-admitted rows flip a
`nBetter` comparison.

**What is still missing** is the mechanism: why those 360 of 8,792 gap-fill rows were skipped
while 8,432 were not. Nothing measured separates the two groups - same run_q (all 1), same decoy
status (all targets), overlapping score ranges, all belonging to entries with real observations
in other files. Until that is known, "master bug" is the strongly-favoured reading rather than a
settled one, and the golden should NOT be regenerated on the strength of a strong reading alone.

**Next step, one instrument-and-run cycle**: dump `(file, entry_id, ExperimentPrecursorQvalue,
ExperimentAggregateScore)` at the point the 2nd-pass record is WRITTEN, on `3e4d94ed58`, and find
where the 360 diverge from the 8,432. `pwiz-work2` is already at that commit with the diagnostic
scaffolding in place.

**Method note.** Three claims in this investigation were overstated from small samples and then
retracted by a counting pass that took seconds: "winner markers", "premise is false for pass 2",
and "master is buggy, rebaseline". Count the population before characterising it.

## RESOLVED: "experiment-wide" must be per-entry, and master violates it (2026-08-29)

This supersedes every earlier note in this file about the 360 rows, the participation flag, the
1-byte marker, the `ParquetIndex` guard and the "restore parity" plan. Those were successive
wrong turns; this is the settled understanding, and Brendan's framing is what produced it.

### The definitional argument

*"Experiment-wide really is supposed to mean that. It is not supposed to be possible for runs for
the same entry to have different experiment-wide values. That is a violation of the definition,
and especially for Pass 2 where the values feed directly into a user-facing BLIB, which itself is
a relational database that should not allow this relationship violation."* (Brendan)

Master's own rule agrees: *"Off-stratum survivors keep their 1st-pass EXPERIMENT q. That q is a
pass-1 property anchored on the best-scoring peak."* A pass-1 experiment q is ONE value per
entry across the whole experiment, so the rule as stated is coherent.

### The implementation does not match the rule

Master implements "keep the 1st-pass experiment q" as **"keep whatever is in this observation's
record"** (`FinishRecord`'s off-stratum branch: `if (!pass1ExpQByKey.TryGetValue(...)) return
rec;`). For a row Stage 6 RESET - gap-fill rows, and moved peaks - the in-memory value at
mid-stream write time is the `ResetScores` default, not the pass-1 value. So the default is
silently substituted for "the entry's pass-1 experiment q" on exactly those rows.

Entry 11989, Astral, read from all three baseline per-file 2nd-pass sidecars:

| | `_49` | `_55` | `_60` |
|---|---|---|---|
| master | `exp_pept_q=1, agg=0` | `exp_pept_q=0.003261, agg=-6.5415` | `exp_pept_q=1, agg=0` |
| entry's true pass-1 value | -6.5415 | -6.5415 | -6.5415 |

One entry, three different "experiment-wide" values. `_55` carries the correct one.

### The v5 lookup implements the rule CORRECTLY

Reading the value from the analysis-wide 1st-pass experiment sidecar by entry_id gives all three
rows -6.5415. That is why `FdrExperimentAccumulator.Add` PASSED across all 1,360,398 entries with
the v5 code in place: with the lookup, every entry's observations agree.

**And it is why the accumulator REJECTED the "parity fix"**: reproducing master's per-observation
defaults immediately produced disagreeing values for entry 11989 and threw. The assertion encodes
the definition, so it accepts the correct implementation and rejects the incorrect one - working
in both directions, which is the strongest evidence available that the v5 behaviour is right.

### Scope of the correction - MEASURED, `-Dataset All`

```
Astral mode1  (vs golden)                    PASS   <- the BLIB does NOT move
Astral mode1b (FDR sanity bounds)            PASS   <- independent check, not regenerated
Astral mode3  (per-file sidecars==straight)  PASS   (13,555,990 records)
Astral mode3  (HPC chain==straight)          PASS
Astral mode2 / mode4 / mode5(==straight) / mode6   PASS
Astral mode1b / mode5 / mode7 (diagnostics)  FAIL   <- one metric, 9 rows
```

`pass2.coAssign.experiment.target.nBetter` 13,270 -> 13,279. Confined to the co-assignment
diagnostics panel: the blib is byte-identical, protein FDR unchanged, entrapment FDP bounds hold.
The relational violation never reached the BLIB in practice because the blib takes one row per
precursor and never picked a defaulted one - but it was expressible, which is the point.

360 rows diverge at the panel input and 9 reach the reported metric, so the gauge understates the
divergence by 40x.

### Consequence

The v5 pass-2 split is CORRECT and fixes a latent master defect. The golden move is the fix
becoming visible. `-CreateGolden` for the diagnostics golden is justified, with this reasoning
recorded - and it is narrower than it sounds, because the fixed FDR sanity bounds are
deliberately NOT regenerated by `-CreateGolden` and would still catch a bad blessing.

**The parity fix currently in the working tree must be REVERTED.** It faithfully reproduces the
master bug, which is exactly why the invariant rejected it.

### Why only the diagnostics datasets ever failed

`OSPREY_PASS2_QVALUE=protein-compact` is the DEFAULT, but the projection pass-2 path is gated on
`!config.ModelDiagnostics`. So a `--model-diagnostics` dataset takes the frozen-competition path
(`ComputePass2TransferCompeteFull`, where `FinishRecord` lives) and a plain one does not. Stellar
carries no `--model-diagnostics`, which is why it was 10/10 green throughout while
StellarLibDecoy and Astral failed. **Stellar green is not sufficient for any change touching
experiment-scope values.**

### Method notes worth keeping

* The mechanism came from the RUN LOG (`OSPREY_PASS2_QVALUE=protein-compact` in one line) after
  two code paths had been instrumented on the strength of reading source. The log knew which
  branch ran the whole time.
* An empty filtered dump is indistinguishable from an unexercised code path unless the diagnostic
  also emits a COUNT. `ea_zero=0` looked like "no zeros exist"; the accompanying
  `emitted=6226744` revealed it was the wrong population entirely (that is the pass-1 row count).
* Reading the SAME entry across its sibling rows in all three files is what settled the question,
  and it needed one script and no run. When a value looks wrong on one row, read its siblings
  before theorising about the code that wrote it.
* Four discriminators were eliminated by counting: `run_q == 1` (1,374,571 - 3,800x over),
  gap-fill (8,792 - 24x over), "entry never participated" (0 of 360), pass-2 coverage (0 missing).

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260829_osprey_stage7_stream_increment.md` before starting work.
It covers the parity-fix revert, instrumentation cleanup, the cross-impl parity run and how to
reproduce the impact in maccoss/osprey if its blib or protein-FDR legs fail.

## Phase 1 LANDED: reverted, gated, and committed in three trees (2026-08-29 afternoon)

The parity fix is gone, the temporary instrumentation is gone from both trees, `pwiz-work2` is
back at `5acc2dd24c`, and phase 1 is committed. `FinishRecord`'s `fileKey` parameter survives
the revert - it is still used by `competition.Pep(fileKey, ...)` on the on-stratum path.

| Repo | Commit | Branch |
|---|---|---|
| `pwiz-work1` | `9d75d01580` | `Skyline/work/20260827_osprey_stage7_stream_increment` (PR #4621) |
| `maccoss/osprey` | `90c8968` | `fix/experiment-q-per-entry-not-per-file` off `main` (`7343ffd`) |
| `pwiz-ai` | `f324b3e` | `master`, not pushed |

Local gate on the C# side before committing: build clean, ReSharper 0/0, **597/597** tests (599
before - `TestFdrScopeSplitV5` replaces three deleted patch tests).

### The cross-impl comparison had to be rebuilt, not loosened

The v5 split left the two sides with no like-for-like artifact: nine values, one 68-byte
per-file record on the Rust side, two files on ours. `Compare-FdrSidecarsFused` (in
`Regression/FdrSidecars.ps1`, where the layouts already live) reconstructs Rust's
per-observation view from the C# pair - run scope from the matched per-file record, experiment
scope joined by `entry_id` from the analysis-wide file.

* `FusedFields` carries name + Rust offset + C# offset + which artifact holds it in ONE row, for
  the same reason `Fields` is one array. Verified against `write_fdr_scores_sidecar`:
  `score@4, run_prec@12, run_pept@20, exp_prec@28, exp_pept@36, pep@44, exp_protein@52,
  exp_agg@60`.
* An `entry_id` the per-file sidecar carries but the analysis-wide file lacks is COUNTED
  (`MissingExperiment`), never skipped - skipping would hide a C#-side incompleteness behind a
  PASS. Distinct ids are tracked separately from the observation tally so the set arithmetic
  cannot go negative on a repeated miss.
* Both layouts share the OSPRYFDR magic, so the version byte is the only discriminator and a
  36-byte file read at a 68-byte stride yields plausible garbage. v5 is refused by name, saying
  which side of the comparison it belongs on.
* `Compare-FdrSidecars-Crossimpl.ps1`'s SKIP guard now tests for the FUNCTION, not just the
  file: a pre-v5 pwiz checkout has `FdrSidecars.ps1` without the fused comparison.

Smoke-tested against a live run dir: the pass-1 experiment map indexed **484,747 distinct
entry_ids**, and C#-on-both-sides produced the intended named version refusal.

### The same defect existed in Rust, and is now fixed there

`crates/osprey/src/pipeline.rs`, the protein-compact pass-2 map-back, read the entry's pass-1
experiment q from `sidecar_paths[file_idx]` - the file being mapped. An entry with no pass-1
record in THAT file missed and kept its `ResetScores` default, which is master-C#'s bug in
Rust's spelling.

`read_analysis_wide_experiment_q` unions every file's pass-1 values into one `entry_id`-keyed
map, built once ahead of the loop; residency stays O(distinct entries). Two departures from a
literal mirror, both deliberate:

* It carries `experiment_aggregate_score` with the two q-values. Rust left the aggregate at
  whatever the seed put there, so a record's q and the score that q was ranked on could come
  from different competitions.
* Two files disagreeing about one entry is REFUSED, not first-wins, and the caller falls back to
  the 2nd-pass retrain - its existing documented response to inputs it cannot trust. Bitwise
  comparison, same reasoning as `FdrExperimentAccumulator`.

Rust gate: `cargo fmt --check`, clippy `-D warnings`, **148 tests** (145 before). The three new
ones pin the resolve-across-files case (worked example entry 11989), the disagreement refusal
and the unreadable-sidecar refusal. Release-notes entry added to `RELEASE_NOTES_v26.7.0.md`.

### Two traps worth keeping

* **`Get-PwizRoot` defaults to `C:\proj\pwiz`** - master. Run bare, `Compare-EndToEnd-Crossimpl`
  would execute the MASTER C# binary against fixed Rust and report a divergence that is pure
  mis-targeting. Set `PWIZ_ROOT=C:\proj\pwiz-work1`. The new SKIP guard happens to catch this
  too, since master's `FdrSidecars.ps1` has no fused comparison.
* **`Start-Process` with `-RedirectStandardOutput`/`-RedirectStandardError` is NOT detached.**
  The redirects force `UseShellExecute=false`, so it calls `CreateProcess` directly and the
  child inherits the harness job object. The first `-Dataset All` was killed at ~18 minutes,
  mid-Percolator iteration 7, with an empty stderr and no crash event. Relaunched via
  `Invoke-CimMethod Win32_Process Create` with a launcher that writes its own log.

### Phase 1 SHIPPED, and the golden move is verified (2026-08-29 evening)

Commit `2d07cf48fd`, pushed to `Skyline/work/20260826_osprey_stage7_stream_pool` (PR #4621).
`pwiz-ai` at `f51b5c0`; `maccoss/osprey` branch `fix/experiment-q-per-entry-not-per-file`
pushed (no PR yet). TeamCity Perf/Regression build 4157715 triggered on `pull/4621`.

The golden diff is ONE line: `astral/diagnostics.tsv`,
`pass2.coAssign.experiment.target.nBetter 13270 -> 13279`.

`blib_summary.tsv` also moved on capture - 14 rows, ALL sums, every `<rows>`/min/max identical,
worst delta 1.2e-7 absolute. That is SQLite scan-order noise: `BlibGolden.ps1`'s
`Compare-Summary` compares at **relative 1e-6** (not the 1e-9 used for the per-row subset) for
exactly this reason, and its own comment says so. It was REVERTED rather than committed, and the
revert was PROVEN twice: `Compare-Summary` against the run's real blib gave worst relative delta
**5.05e-13** (1.98 M x headroom, control: the captured version also passes), and then a full
`regression.ps1 -Dataset Astral` on a fresh run - fresh scan-order noise - came back
**15/15 PASS, EXITCODE=0**, with modes 1b/5/7 going FAIL -> PASS against the new golden.

`protein_fdr.tsv` appeared in `git status` with zero content change - LF-only write from the
capture. `fix-crlf.ps1` normalised it out.

**Cross-impl parity is RESTORED** (this closes the "breaks structurally" item): all three legs
PASS on Stellar and Astral. The fused leg compared 1,448,698 + 996,830 records on Stellar and
**6,226,744 + 3,470,075** on Astral.

**A real defect was found and fixed while gating**: `regression.ps1` byte-compared the experiment
sidecars with `Compare-Object`, which boxes every byte into a PSObject. On Astral's 85.8 MB /
2,498,773-record sidecar that meant a **53 GB working set and ~19 minutes per pass**, which read
as a hung gate. Replaced with `OspreyFdrSidecarComparer.CompareBytes` (span equality): **96 ms**,
and it reports the first differing offset. Verified with negative controls - injected byte flips
and truncation - because an equality check fed only equal inputs proves nothing.

## PHASE 2 PRECONDITION: MEASURED, and it holds (2026-08-29 evening)

The handoff's "measure this FIRST" item. `CompeteOneFile` filters its `fileRunQ` on the GLOBAL
survivor set (`Pass2FdrSidecar:1202`, the union over all files); a per-file worker can only
supply its own. The XML doc asserts a file can win for an entry_id that is a survivor only
elsewhere; earlier TODO entries claimed it both ways.

Temporary diagnostic at the one point holding all three sets (the file's whole pass-1
population, its own survivors, the global union), straight-through, both datasets:

| dataset | file | population | inGlobal | inOwn | **globalOnly** | ownOnly |
|---|---|---|---|---|---|---|
| Stellar | _20 | 482,891 | 332,138 | 332,138 | **0** | 0 |
| Stellar | _21 | 482,910 | 332,143 | 332,143 | **0** | 0 |
| Stellar | _22 | 482,897 | 332,158 | 332,158 | **0** | 0 |
| Astral | _49 | 2,096,935 | 1,164,226 | 1,164,226 | **0** | 0 |
| Astral | _55 | 2,102,639 | 1,167,128 | 1,167,128 | **0** | 0 |
| Astral | _60 | 2,027,170 | 1,129,929 | 1,129,929 | **0** | 0 |

`inGlobal == inOwn` exactly on every file over 8.2 M observations, and `ownOnly = 0` proves
own is a subset of global rather than the two matching by accident. So restricted to a file's
own pass-1 population the two filters are the same set, which is what the structural argument
predicts: `RescoreCompaction` retains by `base_id` against a global set, so a base_id surviving
anywhere survives everywhere it holds a row.

Where it WOULD have mattered: `CompeteOneFile` -> `FoldFileContribution` -> `minRunQ`, the
cross-file best-of-runs floor on experiment q. The per-file stamping path is unaffected either
way, because the caller re-filters to the survivors it holds.

**Caveat, stated because it is not closed**: both datasets are 3 files, and the doc's concern is
about precursors seen in MANY runs. Brendan's ruling: the guard is sufficient, and the night
session does equivalence testing at scale (possibly a 257-file CHS run to capture post-phase-2
state) with the option to roll back to `2d07cf48fd`. So the worker must carry a STRUCTURAL
GUARD - if the local set ever diverges from what the competition needs, fail the run loudly
rather than silently lowering experiment q. Phase 1's lesson applied: absence must be a stop,
never a plausible default.

The instrumentation was reverted after the measurement; the numbers above are the record.

## NIGHT SESSION 2026-08-29/30 - step 1 at scale, and a second precondition nobody had named

Session opened 22:07 with 90% context. Phase-2 step 1's acceptance run had come back green
before the session started (`-Dataset All` 55 PASS / 0 FAIL, EXITCODE=0), so step 1 stands
committed at `3593cd2ff6`.

### Landed and pushed

`origin/Skyline/work/20260826_osprey_stage7_stream_pool` moved `2d07cf48fd` -> `b327152c9d`
(PR #4621). That is master merged into the branch plus step 1. All five master commits are
Skyline-side and touch **zero** Osprey files; the only shared file that moved is
`pwiz_tools/Shared/PortableUtil/SystemUtil/CommandStatusWriter.cs`, a null-guard on a disposed
writer that changes no output format. Gate before pushing: build clean, 597/597, ReSharper 0/0.

TeamCity 4157715 was still running on `2d07cf48fd` at the time and is unaffected - it is pinned
to the commit, not the branch tip.

### THE D:\test MIGRATION SILENTLY BROKE `-LinkFrom` FOR EVERY RECORDED RUN

Cost ~7 minutes to find and is worth more than that to anyone who reuses a completed run.

`Run-SeaAd.ps1 -LinkFrom` reported

```
LinkFrom: pinned OSPREY_VERSION_OVERRIDE=26.1.1.232 from the source run(s)
LinkFrom: hard-linked 328 file(s) for stages before FirstPassFDR, 0 missing, from 1 source(s)
```

and then **re-scored file 1 from scratch anyway** - "Running RT calibration... Scoring
calibration windows" at 22:14 on a run that was supposed to resume at Stage 5.

Root cause: `OspreyTask.ValidityKey` (`Osprey.Tasks/OspreyTask.cs:179`) is
`search={SearchParameterHash};library={LibraryIdentityHash}{pick suffix}`, and
`SearchIdentity.SearchParameterHash` (`Osprey.Core/SearchIdentity.cs:60`) folds
`decoy_pairing_manifest` in as an **absolute path**. The migration moved the mzML and the
libraries out of `D:\test\Pilot-MTG-Tissue-May2026\...` and
`D:\test\AstralTest-TargetDecoyLibraries\...`, so every run recorded before it now computes a
different `search=` hash than its own artifacts carry.

**The link tally cannot see this.** It matches by FILE NAME and reports "0 missing"; Osprey then
rejects each linked artifact on its validity key, one file at a time, silently. So the banner
says the link worked and the run says nothing - the only symptom is that Stage 1-4 runs.

Repaired with junctions restoring the recorded paths, and the relaunch went straight to
`PerFileScoring:skipping (outputs valid)` -> `FirstPassFDR:starting`:

```
D:\test\Pilot-MTG-Tissue-May2026\Astral-DIA\mzml
    -> D:\test\osprey-runs\sea-ad\mzml
D:\test\AstralTest-TargetDecoyLibraries\target+decoy+entrapment-20260817-ungated
    -> D:\test\osprey-runs\sea-ad\lib\target+decoy+entrapment-20260817-ungated
```

Every SEA-AD run under `runs\` is dated 2026-08-14 to 2026-08-21, i.e. all pre-migration, so the
junctions are what makes any of them linkable. Two follow-ons worth filing separately: the
runner should VERIFY adoption rather than report a filename tally (watch for
`PerFileScoring:skipping (outputs valid)` and fail loudly otherwise), and a path-dependent
validity key defeats relocating a dataset at all - a content hash of the manifest would not.

### The 82-file scale test

Launched 22:18:55 against `D:\test\osprey-runs\_bin\20260829-phase2-step1-merged\Osprey.exe`
(the merged branch build, version 26.1.1.241, pinned to 26.1.1.232 by the LinkFrom auto-pin).
Stages 1-4 linked from
`seaad-82files-libdecoy-r1.0-protein-compact-p2-pickrun3-oursungated-n82`; Stage 5+ regenerates
because that run carries `fdrsidecar=4` and today's build emits `fdrsidecar=5` - the invalidation
is correct and is the intended shape.

Run dir: `D:\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-protein-compact-phase2step1-20260829_221855`

What it tests is precondition ONE only - the survivor-scope guard step 1 added. It carries no
guard for the second precondition below, because that guard was written after it launched.

### A SECOND PRECONDITION OF THE RELOCATION, previously unnamed - now guarded (`570ca41466`)

Reading `CompeteOneFile` for the relocation surfaced a second thing the sidecar fold depends on,
of exactly the same shape as the survivor-scope one and with the same silent failure mode.

`CompeteOneFile` reduces to per-base_id bests over the file's whole **stratum population**
(`StreamingFdr.cs`, the `bestTarget`/`bestDecoy` loop). After the relocation, SecondPassFDR folds
those bests out of the per-run `.2nd-pass.fdr_scores.bin`, which carries only that file's
**survivors**. The two agree exactly when the winning TARGET observation is itself a survivor:
the survivor-restricted scan is a subsequence of the population scan and both take the first
observation at the maximum, so if the population winner is in the subset it is also the subset's
winner. If it is not, the folded experiment-wide maximum silently falls to a lower-scoring
observation - no exception, no failing gate.

The check is therefore one line - `bestTarget[bid].entryId` must be in this file's own survivor
set - and it now throws in `ComputeFullPopulationPrecursorFdrStreaming`, beside the step-1 guard.

Three things deliberately scoped:

* **Stratified only.** Unstratified transfer-compete reduces over the file's ENTIRE population,
  which includes base_ids that survive nowhere; their bests are non-survivors by definition, so
  the same assertion there would fire on the first file and say nothing about the fold.
  **transfer-compete's fold equivalence is a separate open question** and needs its own
  measurement before that mode's per-file half moves. Asserting the stratified invariant over it
  would disguise the gap as coverage.
* **Decoys are not checked**, because every non-survivor decoy observation is carried forward
  into the per-run sidecar by design. That is what makes the carry-forward NON-OPTIONAL: drop it
  and `bestDecoy` needs the same check, and it fails - the measured
  `decoy: population-only=305` on Stellar is exactly that failure.
* **Measured on Stellar 3-file only** (`target: differs=0 population-only=0`). Same caveat the
  survivor-scope precondition carried, and the same answer: guard it, then measure at scale.

**How to validate it at 82 files in ~25 minutes, not 8.5 hours.** Once the run above finishes,
its Stage 5 sidecars are format v5 and its Stage 6 reconciled parquets are on disk, so
`Run-SeaAd.ps1 -Task SecondPassFDR -LinkFrom <that run> -Fresh` re-runs Stage 7 alone against a
freshly snapshotted guarded binary. That is the cheap way to test the second precondition at
cohort scale, and it needs a NEW exe snapshot - the one the run above holds predates the guard.

### `LoadExperimentRecords` tightened (`cf413e61bd`)

The handoff's open item. It coalesced every `FdrExperimentSidecar.ReadMap` failure to an empty
map, so a truncated, wrong-version or wrong-pass sidecar was indistinguishable from an analysis
that never wrote one. Consumers apply these values through a `TryGetValue`, so both read as "no
matching entry" and every entry keeps its `ResetScores` defaults - an `ExperimentAggregateScore`
of 0.0 that `BuildCoAssignment` then takes a MINIMUM over. That is the phase-1 defect that
admitted 483,220 decoys against an expected 272, arriving by a second route.

Absence stays tolerated and is now tested separately from unreadability; only a file that EXISTS
and cannot be read throws. `LoadExperimentRecordsFrom(path, pass)` was split out so the
distinction is testable without standing up an `OspreyConfig`, and the new assertions were proven
RED against the old behavior before being kept - a throws-on-corrupt test fed only corrupt input
proves nothing about the case it must let through, so the valid-file control is asserted first.

There is no pre-v5 experiment sidecar in the wild to be broken by this: the analysis-wide file is
new in v5, and the two sidecar types carry different magic, so a per-file file cannot be
mistaken for one.

### The OTHER open phase-1 defect is BLOCKED ON A GATE, not on the fix

`ComputePass2Resident` never publishes `Pass2ExperimentScope`, so `WritePass2ExperimentSidecar`
takes its early return and a resident pass-2 run writes **no 2nd-pass experiment sidecar at
all**. Confirmed by reading: the `ctx.Publish(new Pass2ExperimentScope(...))` at
`Pass2FdrSidecar.cs:1945` is inside `ComputePass2Projection` (1826+), not inside
`ComputePass2Resident` (1652-1825), which ends at `FirstPassFdrTask.RunPercolatorFdr` and
publishes nothing.

The fix looks small - accumulate over the same entries the per-file sidecar write loop already
walks, so the analysis-wide file and the per-file files cannot disagree, then publish. **It was
not written, deliberately.** Two reasons, and the second is the one that decides it:

1. `FdrExperimentAccumulator.Add` throws when two observations of an entry_id disagree. Whether
   the resident path's experiment values are per-entry consistent is UNKNOWN - it is the same
   question phase 1 answered for the frozen path, and answering it needs a run, not a reading.
2. **`regression.ps1` never sets `OSPREY_PASS2_QVALUE=transfer`.** Every leg of every dataset
   runs the frozen `protein-compact` default, so `ComputePass2Resident` is not exercised by the
   local gate at all. A fix landed there would be ungated code on an ungated path.

So the next step on this defect is a regression leg that reaches the resident pass-2 path, not
the fix. Filing the fix without it would be the "untested capability is a liability" trade in
its purest form.

### BOTH PRECONDITIONS OF THE RELOCATION ARE NOW MEASURED AT 82 FILES (2026-08-30 early)

Two runs, both `EXITCODE=0`, both on the SEA-AD 82-file libdecoy r=1.0 protein-compact cohort.

**Precondition 1 - survivor scope.** Stages 5-7, 22:18:55 -> 01:37:09 (3 h 18 m), against the
merged step-1 build.

```
D:\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-protein-compact-phase2step1-20260829_221855
```

**0 `Survivor scope violation`.** This closes the caveat the day session recorded verbatim: the
`globalOnly = 0` measurement was made on two 3-file datasets, and the XML doc's concern was
about precursors seen in MANY runs. At 82 files it still holds.

**Precondition 2 - experiment-fold scope.** Stage 7 alone, 05:21:39 -> 05:39:24 (17 m 45 s),
against the fold-guard snapshot (`570ca41466`).

```
D:\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-protein-compact-foldguard-stage7-20260830_052138
```

**0 `Experiment-fold scope violation`.** `-Task SecondPassFDR -LinkFrom` made this 18 minutes
instead of another 4.5 hours; use that shape for every Stage-7-only question from here.

**The guard was EXERCISED, not merely silent** - checked, because exit 0 on an unexercised guard
proves nothing and this file already records that trap once ("an empty filtered dump is
indistinguishable from an unexercised code path unless the diagnostic also emits a COUNT"):

```
05:27:46  protein-compact: streaming the competition over 82 file(s)...
05:34:36  protein-compact: writing experiment q to 82 file(s)...
```

protein-compact is the stratified path, so `stratumBaseIds != null` and the guard loop walked
`contribution.BestTarget` on each of the 82 `CompeteOneFile` calls.

**And it is output-neutral at scale.** All 82 `.2nd-pass.fdr_scores.bin` match the precondition-1
run's byte for byte in length, and the four sampled match by SHA-256. The `out.blib` files differ
in SIZE (340,525,056 vs 357,494,784 bytes) and that is SQLite container overhead, not a computed
difference - the per-file Stage-7 binaries are what Stage 7 actually produces. NOT verified:
blib CONTENT equality, because there is no `sqlite3` on this box. If that matters, it needs a
query-level comparison.

### MEMORY AT 82 FILES: the Stage 7 resident FLOOR fell 64%

`perfviz.py --files 82`, precondition-1 run vs the recorded 2026-08-20 baseline
(`seaad-82files-libdecoy-r1.0-protein-compact-p2-pickrun3-oursungated-n82`), same cohort, same
library, same arm, same `--threads 30`:

| | baseline 2026-08-20 | 2026-08-29/30 | delta |
|---|---|---|---|
| **SecondPassFDR p10 (resident floor)** | **28.9 GB** | **10.4 GB** | **-18.5 GB (-64%)** |
| SecondPassFDR p50 | 37.9 GB | 23.1 GB | -14.8 GB |
| SecondPassFDR peak / wall | 48.6 GB / 20:03 | 44.0 GB / 16:58 | -4.6 GB / -15% |
| PerFileRescoring managed peak / wall | 47.6 GB / 155:56 | 18.6 GB / 109:24 | **-29 GB** / -30% |
| FirstPassFDR wall | 66:12 | 71:52 | +8.6% |
| private peak | 53.6 GB | **55.1 GB** | **+1.5 GB** |
| gaps >= 30 s | 0 | **1 (35 s)** | OVER the README's gate |

The floor is the number #4486 is about - "peak is not the scaling number, the floor is" - and
Stage 7's floor fell by nearly two thirds at cohort scale.

**Three reasons this is an indication and not a proven A/B**, stated because the numbers are
attractive enough to be quoted carelessly:

1. It compares the WHOLE branch against an Aug-20 build, not phase 1 and step 1 alone.
2. The new run LINKED Stages 1-4, so no PerFileScoring preceded Stage 5 and the heap it inherits
   is different. The floor delta is far too large to be that, but the WALL times are not proof.
3. One run per side.

**Two things got WORSE and must not be lost in the good news:**

* **Private peak rose 1.5 GB to 55.1 GB on a 64 GB box.** The floor improved while the ceiling
  crept toward the edge. At 82 files that is still fine; it is the direction that matters.
* **A 35 s reporting gap appeared in `stage7-protein-fdr`** (01:34:31, after
  `[MEM stage7-protein-fdr] managed_heap=21.13 GB`) where the baseline had ZERO gaps >= 30 s.
  The SEA-AD README makes `gaps >= 30s` an explicit gate on every long run, and the worked
  example there is precisely this: a gap is an observability failure, not a throughput one -
  nobody can tell "working" from "hung" and no watchdog can be tuned below it. **File it.**

### Gates

`regression.ps1 -Dataset Stellar` on `cf413e61bd` + `570ca41466`: **PASSED, EXITCODE=0**.
`-Dataset All` started 05:39:29 - that is the one that decides the push, because only
StellarLibDecoy and Astral carry `--model-diagnostics` and the co-assignment panel takes a
MINIMUM over aggregates.

### Process note, recorded because it cost the most of anything tonight

After the Stellar gate went green at ~01:50 the session STOPPED rather than launching the two
prepared next steps. Both were scripted and ready; ~3.5 h of machine time went unused, and the
Stage-7 validation above only ran at 05:21 when it could have run at 02:00. The fix is
mechanical and is now in place: chain the next job behind the current one at launch time
(`run-regression-all.ps1` waits on `Get-Process Osprey` and starts itself), rather than
intending to launch it after a notification.

## PHASE 2 RELOCATION WRITTEN: 46 PASS, failures confined to the diagnostics panel (2026-08-30)

The per-file half of the second pass now runs in `PerFileRescoreTask`. Two local commits on
`Skyline/work/20260827_osprey_stage7_stream_increment` in `C:\proj\pwiz-work1`, **neither
pushed** - the pushed tip is still `570ca41466`:

| commit | what |
|---|---|
| `1e63f5c22f` | the move: worker competes, stamps run q, writes the per-run sidecar; SecondPassFDR folds it and recomputes only to assert against it |
| `a5e1d9a372` | ownership decided from disk + the HPC-chain relay + the stratum filter on carried decoys |

Local gate: build clean, **598/598**, ReSharper 0/0.

### `-Dataset All`: 46 PASS, and the failures are ONE thing

```
FAIL: StellarLibDecoy  mode1b, mode5, mode7
      StellarGenDecoyEntrap  mode1b, mode5, mode7
      Astral  mode1b, mode5, mode7
```

Exactly the three diagnostics comparisons on exactly the three `--model-diagnostics` datasets.
Stellar, which carries none, passes completely. **Everything structural passes on every dataset**:
golden blib (mode1), 2nd-pass protein-q liveness (mode1c), route-independence (mode3, Astral
included), resume (mode2), warm re-run (mode4), rehydrate (mode5's non-diagnostics assertions),
library-fragment release (mode6).

So the relocation is output-neutral everywhere except the co-assignment panel.

```
StellarLibDecoy        pass2.coAssign.experiment.target.nBetter  988 -> 977
                       enrichment  2.9494 -> 2.9826   (UP)
StellarGenDecoyEntrap  nBetter 858 -> 846, entrapment.nBetter 10 -> 9
                       enrichment  2.3632 -> 2.1570   (DOWN)
Astral                 mode1b 2 issues
```

`AssertContributionsMatch` NEVER fired, on any file of any dataset - the worker's per-file
competition is bitwise identical to Stage 7's recomputation, `bestDecoy` included. The
competition is not what moved; only which entries end up carrying experiment-scope values did.

### Brendan's ruling on the carried-forward decoys - do not undo them

The carry-forward is **expected, intended and on-plan**: the original implementation required
Pass-1 files to satisfy SecondPassFDR and blib writing, and that requirement is what it removes.
It is **expected to have no functional impact on results other than the contents of the sidecar
itself**, so the diagnostics movement means one of exactly two things:

1. we have not got it quite right, or
2. the old code was doing something it should not - the same shape as the Pass-1 gap-fill issue,
   where the golden move WAS the fix becoming visible (`nBetter 13270 -> 13279`).

Telling them apart may need digging. **Do not "fix" the carried decoys away** - that was the
first instinct here and it is wrong.

Evidence that argues for digging rather than reverting: `enrichment` moved in OPPOSITE directions
on the two Stellar arms, which differ precisely in decoy source (library-supplied vs generated).
A "my extra rows inflate the null" story predicts one direction.

### MEASURED: carried records do reach the experiment sidecar - and why that is not yet a verdict

Probe on real bytes (Astral straight, branch build):

```
experiment sidecar : 1,419,388 entry_ids, 670,655 decoys (47.2%)
per-file _49       : 1,204,306 records, 549,357 decoys, 323,272 carried-signature
                     -> 323,272 of those IN the experiment sidecar (100%)
```

Step 4 of `ComputePass2TransferCompeteFull` reads EVERY record of each per-file sidecar and feeds
it into `FdrExperimentAccumulator`, so the mechanism is real. **But the "carried signature"
(`runQ==1.0 && runPeptideQ==1.0 && pep==1.0`) is NOT unique to carried decoys** - a surviving
decoy that won nothing carries the same three values - so 323,272 is an upper bound, and 47.2%
decoys is about what a 1:1 target-decoy library yields anyway. Decoys were plausibly always there.

**The decisive measurement, not yet run**: does the experiment sidecar's entry_id SET differ from
baseline, and by which ids? Baseline binary exists at
`D:\test\osprey-runs\_bin\20260830-foldguard\Osprey.exe` (`570ca41466`). `regression.ps1` has NO
`-Exe`, so the baseline side needs `pwiz-work2` at `570ca41466` (it is at `5acc2dd24c`; RESTORE
it). Use `-Dataset StellarLibDecoy -KeepOutput -KeepRunDirs 5` (~10 min, the cheapest failing
reproducer - NOT `-Dataset All`), copy artifacts out immediately, set-difference the two
`output.2nd-pass.fdr_experiment.bin` entry_id sets, then trace the new ids through the per-file
sidecars on both sides and read their siblings - the entry-11989 technique from phase 1.

### Seven defects fixed getting here, none visible in review

1. **Stage 7 skipped the join entirely** (`SecondPassFDR:done (2.7s)`) - the worker's sidecar
   satisfied the `missingPass2` recompute gate. A worker-written sidecar means the PER-FILE HALF
   is done, not pass 2.
2. **Task-level version of the same skip** - Stage 7 DECLARED those sidecars as outputs, so
   `IsTaskAlreadyDone` could short-circuit the whole task.
3. **Task declarations corrected in all three tasks.** The per-file sidecar is PerFileRescoring's
   output and SecondPassFDR's input; the analysis-wide experiment sidecars are now declared by
   the tasks that write them, which NOTHING did before - including Stage 5's, which it writes and
   counts a failed write against, a pre-existing phase-1 gap. Verified: the straight route now
   shows `PerFileRescoring=3, SecondPassFDR=0` stamps - single ownership.
4. **An in-process byproduct cannot cross a process boundary.** `Pass2WorkerFiles` was published
   in Stage 6 and read in Stage 7 - correct in process, absent in an HPC chain. Replaced by
   testing for the PRESENCE of the producer's validity stamp, since `<output>.<taskName>.osprey.task`
   already records the owner. Recomputing the producer's KEY from the consumer's leg would not
   have worked either: `PerFileRescoreTask.ValidityKey` folds in
   `LibraryFragmentRelease.ValidityKeySuffix`, which reads the per-leg `ExpectReconciledInput`.
5. **Carried decoys were unfiltered** - every non-survivor decoy (75,486 per Stellar file) instead
   of the stratum-restricted set the fold reduces over (~305 base_ids).
6. **The HPC chain never received the new input** - THE mode 3 blocker. `regression.ps1` relays
   each phase's outputs into the next phase's directory and copied four files per stem;
   `.2nd-pass.fdr_scores.bin` was not among them because it used to be Stage 7's OUTPUT. Phase 4
   never saw the worker's sidecars, recomputed, and wrote its own - giving disjoint carried-decoy
   sets (104 straight vs 131 chain). Fixed by relaying the binary AND its stamp; copying the
   binary alone would be worse than copying neither, since phase 4 would fold a file it believed
   it had produced.
7. **Latent harness format bug** at `regression.ps1`'s experiment-sidecar mismatch report: single
   parens round a `-f` operand list bound only the first operand, so the comparison result was
   replaced by an exception naming neither file. Latent since written - the branch runs only when
   the sidecars differ between routes, which had never happened. Fixed with the double-paren
   idiom already used at `Regression/FdrSidecars.ps1` 873/991.

### Three claims made and retracted - do not re-derive them

* The `ValidityKey`/`ExpectReconciledInput` cross-leg mismatch is a real hazard but was NOT the
  cause of the route divergence. The harness relay was.
* "chain: PerFileRescoring=0" was a counting error - the stamps live in `phase3_rescore_*`
  subdirectories, not the chain root. The worker was stamping correctly all along.
* Treating the carried decoys as pollution to remove. They are the design.

All three came from reading rather than measuring; each was settled by one command. The
`/debugging` skill's rule applies to this phase as it did to phase 1: prove it from inside.

### NEW GATE: cross-impl comparison BEFORE SEA-AD (Brendan)

Squeeze the limited regression data before spending 3 h 18 on the cohort.

```powershell
$env:PWIZ_ROOT = 'C:\proj\pwiz-work1'    # REQUIRED - Get-PwizRoot defaults to master
pwsh -File C:/proj/ai/scripts/Osprey/Compare/Compare-EndToEnd-Crossimpl.ps1 -Dataset Stellar -Files All
pwsh -File C:/proj/ai/scripts/Osprey/Compare/Compare-EndToEnd-Crossimpl.ps1 -Dataset Astral  -Files All
```

The comparator already has special handling for the C#/Rust sidecar difference, because the
per-run vs experiment-wide split was deliberately NOT implemented on the Rust side, and an
`entry_id` present on one side only is COUNTED (`MissingExperiment`), never skipped. So "carried
decoys will break parity" is a QUESTION for the run, not a prediction.

**Rust side**: `C:\proj\osprey` is on `fix/experiment-q-per-entry-not-per-file` (`90c8968`). A
SECOND branch matters - `fix/exclude-decoys-from-reconciliation-gap-fill` (`a42351d` +
`bb3d2df` + `e193fbc`, touching `crates/osprey/src/pipeline.rs` and
`docs/12-intermediate-files.md`) - the limited Rust change matching the C# gap-fill fix, which
per Brendan **also required a one-line update to the golden masters for `regression.ps1`**.
Decide which Rust branch (or merge) the comparison runs, and check whether that golden line is
present in this pwiz branch: if a golden line is owed to the gap-fill fix and is missing, a
diagnostics comparison reports a delta belonging to that fix rather than to the relocation.

### Still open

* **`ComputePass2Resident` never publishes `Pass2ExperimentScope`**, so no 2nd-pass experiment
  sidecar is written on resident/retrain paths. This is why the experiment-sidecar OUTPUT
  declaration had to be gated by mode rather than declared unconditionally. Still ungated:
  `regression.ps1` never sets `OSPREY_PASS2_QVALUE=transfer`, so the fix needs a gate before it
  needs code.
* **The fold-scope guard goes VACUOUS** when the Stage 7 recompute is deleted - a sidecar-derived
  contribution holds only survivors by construction. It must move into `CompeteOneFile`, which
  after the move runs in the worker. Noted at the guard site in `StreamingFdr`.
* **SEA-AD rungs not started**: 82-file Stages 5-7 (3 h 18 measured), then `transfer` and
  `mean-best-N=6`. `transfer` does NOT exercise the move (`TryCreatePass2Worker` returns null)
  but is the only arm reaching `ComputePass2Resident`; `transfer-compete` is the in-scope arm
  with genuinely unmeasured fold equivalence.
* **`1e63f5c22f`'s title says "WIP: mode 3 red"**, which `a5e1d9a372` fixed. Squash or reword when
  preparing the branch for review.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260827_osprey_stage7_stream_increment.md` before starting work.

## ROOT CAUSE of the diagnostics panel movement: the relocation DROPS experiment-scope values (2026-08-30)

Measured, not inferred. The verdict is that **the branch's values are wrong and the baseline's
are right**, so this is not a golden-rebaseline case - it is a defect to fix.

### Method: control first, then the first divergence, then the rows

Brendan's framing set the bar: the phase is a pure code relocation, so nothing may change
without a concrete argument that the new value is MORE correct.

1. **A/B on identical inputs.** `pwiz-work2` at `570ca41466` + the same diagnostic patch as
   `pwiz-work1`; `regression.ps1 -Dataset StellarLibDecoy -KeepOutput -SkipResume -SkipWarmRerun
   -SkipRehydrate -SkipHpcChain` (~5 min/side). Baseline all-green, branch red on mode1b/mode7.
2. **A CONTROL run first.** Two runs of the SAME branch binary in different run dirs. This is
   what stops a false root cause: `output.blib`, `output_cold.blib`,
   `output.model-diagnostics.html`, every `.calibration.json`, every `.scores-reconciled.parquet`
   and `_20.scores.parquet` (including a 1-BYTE size change) all differ **run to run on one
   binary**. Any of them would have read as a Stage-3 / Stage-6 regression.
3. **Signal = DIFF branch-vs-baseline AND SAME in the control.** Exactly four artifacts:
   the three `.2nd-pass.fdr_scores.bin` and `output.2nd-pass.fdr_experiment.bin`. Every
   upstream artifact - 1st-pass sidecars, the 1st-pass experiment sidecar, protein groups,
   `cs_stage7_protein_fdr.tsv` - is byte-identical. The first divergence is exactly at the
   relocation boundary.

### What actually moved, at record level

| set | count | composition |
|---|---|---|
| experiment sidecar, branch-only | 140 | **all decoys**, q=1.0, real aggregate |
| experiment sidecar, baseline-only | 0 | - |
| experiment sidecar, shared ids with a moved value | **0** | - |
| per-file sidecars, branch-only observations | 397 | **all decoys** (135/131/131) |
| per-file sidecars, baseline-only observations | **594** | **all TARGETS** (208/185/201) |
| per-file sidecars, shared ids with a moved value | **0** | - |

No target is lost globally - every dropped target observation is still present in another
file, and the union over files is a strict superset on the branch (+140 decoys, 0 missing).
The competition is untouched, which is why `AssertContributionsMatch` never fires.

`q == 1.0` is NOT the rule: the branch keeps 170,156 target q=1.0 observations and drops 594,
i.e. 0.35% of that class. "Has a real q in another file" does not separate them either
(416 vs 178). The set is named by the code, not by the data.

### The defect

`Pass2PerFileWorker.BuildRecords` emits a record only for entries that SURVIVED in that file,
plus stratum decoys, and drops non-survivor targets on purpose:

    // Not a survivor. Carried forward only when it is a decoy; a non-survivor TARGET
    // is genuinely absent from this artifact, and the experiment-fold scope guard is
    // what says the join never needs one ...
    if (survivorIds.Contains(eid)) continue;
    if (!isDecoy) continue;

That argument is scoped to **what the join needs**. It is not true of the other consumer.
`Pass2FdrSidecar.ApplyRecord` (Pass2FdrSidecar.cs:1107) stamps the pool's experiment-scope
values while iterating PER-FILE SIDECAR RECORDS, looking the entry up by `rec.EntryId`:

    private void ApplyRecord(FdrEntry entry, FdrScoreRecord rec)
    {
        entry.Score = rec.Score;
        entry.Pep = rec.Pep;
        if (_experimentRecords != null && _experimentRecords.TryGetValue(rec.EntryId, out var exp))
            entry.ExperimentAggregateScore = exp.ExperimentAggregateScore;
    }

An entry with no per-file record is therefore never visited, so it keeps `ResetScores`'
defaults. Its own doc comment states the rule it breaks: *"the experiment aggregate is a
property of the entry for the whole analysis"*.

### The consequence, measured in the panel's own input

New gate `OSPREY_DUMP_COASSIGN_ROWS=<dir>` dumps `BuildCoAssignment`'s per-observation input
plus the sealed boundaries. Branch vs baseline:

* **Pool membership identical** - 933,913 rows both sides, 0 on either side only. The dropped
  sidecar records do NOT remove entries from the pool.
* **Every cutoff bit-identical** - run (x3), experiment, in/off-stratum, accepted counts.
  The panel did not move because a boundary moved.
* **Exactly 594 rows changed value, and they are the SAME 594 dropped observations** (set
  identity asserted, not just equal counts). `exp_agg_score` moved on all 594, `exp_q` on 351,
  and `included` flipped on **139 - all `true -> false`, all Target**.

That is the whole of `pass2.coAssign.experiment.target.nBetter 988 -> 977`.

### Why the new values are NOT more correct

The branch's OWN experiment sidecar still holds real values for all 594 entry_ids, and the two
sides' experiment sidecars **agree bit-for-bit on every one of them**. Example, entry 103759:

    exp sidecar (both sides): precQ=6.588917440864466e-05  agg=6.256937598046329
    pool BASELINE           : expQ=6.588917440864466e-05   expAgg=6.256937598046329  included=true
    pool BRANCH             : expQ=1                       expAgg=0                  included=false

Of the 594, the pool's aggregate equals the experiment sidecar's aggregate on
**baseline 594/594, branch 0/594**. A strongly-detected target (experiment q = 6.6e-05) is being
reported in the pool as q = 1.0, undetected. This is the SAME participation-vs-value error class
already root-caused and resolved for master in "RESOLVED: 'experiment-wide' must be per-entry",
re-entering through the per-file artifact.

### Fix options - needs a ruling before code

1. **Widen the seeder (preferred).** Apply experiment-scope values to every pool entry by
   entry_id from the experiment sidecar, independent of whether a per-file record exists. Matches
   the stated rule, keeps the per-file artifact lean, and the experiment sidecar already has the
   data. Needs care that the entry set being seeded is enumerated from the pool, not the records.
2. **Restore the dropped target records** to the per-file sidecar. Reproduces the baseline
   byte-for-byte but re-adds 594 records / 3 files of duplication the split exists to remove, and
   leaves the seeder's coverage rule still keyed to the wrong thing.

Whichever is chosen, the carried-forward DECOYS are a separate question and remain per Brendan's
earlier ruling; note that they cause **no** diagnostics movement here - 0 shared values moved and
the panel's decoy admission is unchanged.

### SECOND DEFECT found by mode 7, unrelated to the above

`--task ModelDiagnostics` now REWRITES all three `.2nd-pass.fdr_scores.bin`, breaking the task's
"touch nothing but the report" contract (3 of mode 7's 5 issues). `TryCreatePass2Worker`'s
`WriteSidecar` has the guard - `if (config.DiagnosticsOnly) return;` - so the write is coming
from somewhere else on that path. NOT the cause of the panel movement: the straight-through and
regenerated dumps are byte-identical (asserted), and mode1b fails before mode 7 runs.

### Artifacts

* Session dir: `ai/.tmp/sessions/20260830-coassign-ab/` - `diff_sidecars.py`, `survey.py`,
  `rule.py`, `trace_entries.py`, `verify_loss.py`, `diff_rows.py`, `cmp_artifacts.ps1`,
  both run logs, and the `coassign-dump.patch` applied to both trees.
* Run dirs kept: branch `pwiz-work1/pwiz_tools/Osprey/TestResults/regression-20260830_135109`,
  baseline `pwiz-work2/.../regression-20260830_135620`.
* `pwiz-work2` is at `570ca41466` + the dump patch - **restore it to `5acc2dd24c`** when done.
* The `OSPREY_DUMP_COASSIGN_ROWS` gate is uncommitted in `pwiz-work1`; it is the permanent
  verifier for this class and should land with the fix.

### CORRECTION and the clean statement (2026-08-30, after Brendan pushed back)

Two things in the section above are wrong or unearned, and the corrected version is
simpler than either.

**1. `ApplyRecord` is the WRONG site.** It is the 1st-pass seeder (restores Score/Pep from
1st-pass sidecars). The 2nd-pass experiment values are stamped in `AssignPerRunQ`
(Pass2FdrSidecar.cs:2702), whose null-record defaults are exactly the observed values:

    double expPrecQ = firstPassExperiment?.ExperimentPrecursorQvalue ?? 1.0;
    double expAgg   = firstPassExperiment?.ExperimentAggregateScore  ?? 0.0;
    // An entry with no record never competed: q = 1.0, aggregate = 0.0.

**2. "Are the per-run sidecars identical?" - NO.** Only the EXPERIMENT sidecar is a clean
superset. The per-run files differ in BOTH directions.

**THE INVARIANT THAT BROKE.** Measured pool-vs-sidecar population, per file:

| file | pool obs | baseline sidecar | branch sidecar | pool obs w/o branch record | branch records not in pool |
|---|---|---|---|---|---|
| _20 | 311,278 | 311,278 | 311,205 | 208 | 135 |
| _21 | 311,284 | 311,284 | 311,230 | 185 | 131 |
| _22 | 311,351 | 311,351 | 311,281 | 201 | 131 |

**On the baseline the per-run 2nd-pass sidecar IS the pool for that file - a bijection, zero
in one and not the other, on all three files.** On the branch it is the worker's own set
(per-file survivors + carried stratum decoys), which is neither a subset nor a superset.

**Disk-vs-memory is NOT the variable.** Every pool observation whose record still exists gets
bit-identical values (0 shared-id value moves; 933,319 of 933,913 pool rows unchanged). The 594
rows that lost their values are EXACTLY the 594 that lost their record (set identity asserted).
Reading from disk only became capable of losing information once the file stopped being a
complete image of the pool; in the baseline the choice was immaterial because the two held the
same population.

**Where the populations diverge.** The pool carries every observation of any entry that survived
ANYWHERE in the analysis - entry 3602 is in the pool for files 20/21/22 and survives only in 21.
`Pass2PerFileWorker.BuildRecords` filters on a PER-FILE survivor set, so an entry's observations
in the files where it did not win are dropped. That is the substantive change, and it is not a
relocation.

**Fix.** Supersedes the two-option menu above. `BuildRecords` must restore the invariant: one
record per POOL OBSERVATION in its file, not one per per-file survivor. This is
O(observations in this file), so it does not reintroduce any O(files x entries) structure and
does not conflict with #4486 - it is ~200 records per file on Stellar. The carried decoys are
additive (not pool members) and remain the separate question Brendan already ruled on.

**Still to verify before coding:** whether the 594 reach `AssignPerRunQ` with a null
`firstPassExperiment` or are never visited at all. `score` and `pep` are IDENTICAL on both sides
for all 594, so whatever covers the run-scope values does reach them; only the experiment-scope
assignment misses. That distinction decides whether the worker's iterated population or the
lookup is what needs widening.

### THE ORACLE: do the per-run sidecars match the baseline? (Brendan, 2026-08-30)

The per-run 2nd-pass sidecar must not change because its author formed a new view of what the
file should hold when written by PerFileRescoring rather than SecondPassFDR. The phase's goal is
that per-run FDR can be computed on any number of HPC nodes and experiment-wide FDR computed on a
SEPARATE computer from what those nodes wrote. **The only admissible justification for adding or
changing a row is proof that the old code held rows in memory that its experiment-wide
calculation needed and never wrote.** Measured against that standard, neither delta qualifies.

#### The ADDED rows (397 decoy observations, 140 entry_ids) - justification FAILS

| test | baseline | branch |
|---|---|---|
| per-run union, distinct entry_ids | 313,537 | 313,677 |
| experiment sidecar records | 313,537 | 313,677 |
| experiment ids NOT in any per-run sidecar | **0** | **0** |
| per-run ids NOT in the experiment sidecar | **0** | **0** |

The baseline's experiment sidecar is EXACTLY the union of what the per-run sidecars contained -
zero in either direction. No in-memory row was needed and unwritten. Adding the 140 moved
**0 of 313,537** shared experiment-wide values, so they are inert.

The premise behind the carry-forward is also factually wrong: the baseline per-run sidecars
already carry **466,055 decoy observations**, 294,540 of them at q=1.0. Non-survivor decoys were
being written all along; the 397 are new participants, not a recovered omission.

**Open, and the decisive test**: the code's `bestDecoy` argument is about the JOIN rebuilding the
null without reopening a pass-1 file - the separate-computer case. The measurement above is on the
straight-through route; **mode 3 was skipped in this A/B**. Run mode 3 on the BASELINE: if the
cross-process sidecar-only rehydrate is green without carried decoys, the justification is dead.

#### The DROPPED rows (594 gap-fill observations) - a straight regression

No justification is available: the old code DID write them. They are gap-fill observations -
precursors reconciliation placed into a file where pass 1 never detected them (measured: 0 of 594
appear in that file's 1st-pass sidecar; baseline record is (score, 1.0, 1.0, 1.0) for all 594, and
the score is NOT the 1st-pass score).

**Why the new code cannot see them**, verified: `ReadOneFilePass2Inputs`
(Pass2FdrSidecar.cs:2327) builds the worker's entire observation universe from the file's
**1st-pass sidecar**:

    FdrScoresSidecar.ReadScalars(pass1SidecarPath, FdrScoresSidecar.Pass.FirstPass,
        out entryIds, out scores, survivorIds.Contains, pass1Records);

`BuildRecords` iterates `entryIds`, so a gap-filled peak is unreachable regardless of survivor
status. The baseline's Stage 7 iterated the POOL, which contains gap-fills, and wrote them via
`AssignPerRunQ`'s explicit GAP-FILL branch. The blind spot is visible in the code's own comment,
which reasons that *"decoys are never gap-filled, so they never become survivors"* and carries
decoys forward - without asking what happens to gap-filled TARGETS.

This runs AGAINST the phase's goal: an experiment node reading only what the run nodes wrote now
receives less than before.

#### Both deltas are inert for experiment-wide VALUES

The branch produced identical experiment-wide values for all 313,537 shared entries while its
per-run sidecars were missing 594 rows and carrying 397 extra. The drop's damage is downstream, in
pool seeding: those 594 pool entries never receive experiment-scope values, keep `ResetScores`
defaults (expQ=1.0, expAgg=0.0), and 139 of them fall out of the panel's experiment-scope detected
set - the whole of `nBetter 988 -> 977`.

#### Disposition

Restore the per-run sidecars to the baseline in BOTH directions. Order is already compatible:
restricted to shared ids, branch and baseline record order are identical on all three files, so
byte-identity needs the gap-fill records reinserted at their baseline positions and the carried
decoys removed. Keeping the carried decoys requires first naming an experiment-wide quantity the
baseline per-run sidecars cannot supply - and the mode 3 test above is what would show one.

### THE FIX, fully specified: the worker reads its universe from the WRONG artifact

Brendan's constraint: PerFileRescoring must understand the global set WITHOUT re-reading the
entire population the way SecondPassFDR is allowed to. Measured answer: it already can, from
bounded per-file inputs it is already handed, and doing so reads FEWER rows than today.

| source | file 20 | is it the pool? | bounded |
|---|---|---|---|
| 1st-pass sidecar (**used today**) | 958,241 ids | no - pre-compaction, no gap-fills | per-file |
| **reconciled parquet** (already a parameter) | 311,278 rows | **YES - identical ids AND order** | per-file |
| `.reconciliation.json` `gap_fill_targets` | 208 entries | declares exactly the dropped set | per-file |

**Measured, all three files:**

* reconciled-parquet entry_id sequence == baseline 2nd-pass sidecar record sequence,
  **same ids and same order** (311,278 / 311,284 / 311,351). The parquet IS the per-run
  2nd-pass sidecar's population, in order.
* `gap_fill_targets` (keyed by `target_entry_id`) is SET-EQUAL to the dropped observations on
  every file: 208 / 185 / 201. First element of file 20 is `target_entry_id: 3602` - the entry
  traced at the start of this investigation.
* the dropped ids appear in the reconciled parquet 208/208, and in the 1st-pass sidecar 0/208.

**So the answers are:** the old code did NOT need the whole population in memory; there is NO
flaw in the per-file parquet - it carries exactly the right rows; and the defect is a wrong
choice of source in `ReadOneFilePass2Inputs` (Pass2FdrSidecar.cs:2327), which derives the
universe from `pass1SidecarPath` when `effectiveParquetPath` - the artifact that DEFINES the
pool - is a parameter of the same call.

#### One change resolves both deltas

Source the observation universe from the reconciled parquet and:

* the 594 gap-fills are **restored** (they are parquet rows), and
* the 397 carried decoys are **removed** (they are not parquet rows),

landing byte-identical to the baseline, in the right order, with no global traversal and no new
relay. The carried-decoy question then needs no separate ruling: the correct source excludes them
by construction. If the fold truly needs `bestDecoy`, it surfaces as a real failure with a real
diagnosis rather than as a pre-emptive redefinition of the artifact.

#### Gate for the fix

Byte-identity of all three `.2nd-pass.fdr_scores.bin` and `output.2nd-pass.fdr_experiment.bin`
against the baseline run dir, then mode1b / mode5 / mode7 green. The
`OSPREY_DUMP_COASSIGN_ROWS` gate should land with it as the permanent verifier: it is what turns
"the panel moved" into "these 594 observations lost these fields".

**Do NOT reason from the metric.** `nBetter` and `enrichment` moved in opposite directions on the
two Stellar arms and that told us nothing; the artifacts told us everything.

### THE FRAMING THAT MATTERS: an existing contract was not adopted, and nothing verified it

Brendan's reading, confirmed in the code: the "a per-file node reconstructs the join's set from a
Stage 5 artifact" problem was ALREADY solved, hash-validated and version-guarded - for the
parquet. The new PerFileRescoring 2nd-pass sidecar did not abide by it.

`FirstPassFdrTask.WriteReconciliationFiles` writes `.reconciliation.json` from the JOIN node,
which has traversed the whole population. It carries `file_stems`, the join-wide
`first_pass_base_ids` (156,832), this file's `gap_fill_targets`, the reconcile actions and the
refined calibration - explicitly so *"a worker rescoring its single parquet can compute the
join-wide reconciliation hash that --task SecondPassFDR will validate against"*.

`ReconciledParquetWriter.BuildReconciliationMetadata` then stamps the parquet with:

* `osprey.reconciliation_hash` - the JOIN-wide hash from those stems, *"not the worker's
  single-file InputFiles hash; without that, a worker rescoring a single parquet stamps a
  single-file hash that the downstream --task SecondPassFDR node rejects on mismatch"*;
* `osprey.reconciled = "survivors"` - *"this parquet holds only the Stage 5 survivor rows ... an
  older Osprey compares this value against "true" exactly and REFUSES, instead of reading a
  subset as though it were the whole file and reporting a confidently wrong answer"* - citing
  issue #4486, THIS sprint.

The parquet's population is therefore DEFINED as survivors + gap-fills, which is exactly what is
measured: 311,070 + 208 = 311,278 (and 311,099 + 185, 311,150 + 201), identical in ids AND order
to the baseline per-run 2nd-pass sidecar.

**The per-file worker reached back PAST the Stage 5 -> 6 boundary** to the pre-compaction
1st-pass sidecar (958,241 ids) for its universe, which by construction cannot contain a gap-fill.

#### The verifier gap - the reason this got as far as it did

The parquet has a verifier: SecondPassFDR rejects a mismatched reconciliation hash. **Nothing
asserts that the per-run 2nd-pass sidecar describes the same rows as the parquet it was computed
from.** That is why a 594-row omission passed mode 1 (blib), mode 1c, mode 2, mode 3, mode 4 and
mode 6, and surfaced only as two moved numbers in a diagnostics panel - the weakest possible place
to learn it, and the reason the previous session spent its budget on `nBetter` and `enrichment`
instead of on the artifact.

CRITICAL-RULES: *"When a rule's verifier is weak, the rule will drift; strengthen the verifier
rather than the wording."*

#### Fix, in two parts

1. **Adopt the existing contract.** Take the worker's observation universe from the reconciled
   parquet (`effectiveParquetPath`, already a parameter of `ReadOneFilePass2Inputs`) instead of
   `pass1SidecarPath`. Restores the 594 gap-fills and removes the 397 carried decoys together,
   byte-identical to the baseline, in order, reading FEWER rows than today (311K vs 958K).
2. **Add the missing verifier.** Assert the per-run 2nd-pass sidecar's entry_id sequence equals
   the reconciled parquet's entry_id sequence. Streaming, O(1) memory, holds on every route -
   and on HPC it is precisely the property that must hold for a separate experiment node to be
   correct.

#### Gate

Byte-identity of all three `.2nd-pass.fdr_scores.bin` plus
`output.2nd-pass.fdr_experiment.bin` against the baseline run dir, then modes 1b / 2 / 3 / 5 / 7.
Mode 3 is the one that exercises the cross-process case the new verifier is really for.

### THE DECISION: the worker must WRITE its competition (2026-08-30)

Two in-memory dependencies are now PROVEN, both by running the fix and reading the baseline.
Neither justifies changing the per-run sidecar's population; both are satisfied by writing down
an answer the authorized node already computes.

#### Dependency 1: which rows COMPETED (gap-fills)

`BuildRecords` restored to one record per pool entry -> the per-run sidecars became
byte-identical to the baseline on `entry_id`, `score`, `run_precursor_q`, `run_peptide_q` and
on record COUNT (11,206,040 / 11,206,256 / 11,208,668, exact). The ONLY differing column was
`pep`, on 52,640 ids, because the aborted run never reached `PatchPep`. **The files were right.**

The Stage 7 assert then fired: `FileCompetitionFromRecords` folds the pool image, which contains
gap-fill rows that never competed (`CompeteOneFile` draws its population from the file's 1st-pass
sidecar, where a gap-fill has no record). Excluding them via the envelope's `gap_fill_targets`
fixed the target side: 153,868 -> matching.

#### Dependency 2: the decoy BESTS - the decisive one

The next assert: *"best decoy for base_id 16536 is score -5.82647366877369 on entry_id
2147500184 as recomputed, but absent in the worker's answer."* That entry is the FIRST of the 140
carried decoys measured at the start of this investigation. The carry-forward was load-bearing
for `FileCompetitionFromRecords`, exactly as its comment claimed.

**Read from the baseline code, this is confirmed and it is NOT aggregate knowledge.** Baseline
Stage 7's `ReadFile(fileKey)` calls
`ReadOneFilePass2Inputs(sidecarByKey[fileKey], effectiveParquetPath, ...)` - it opens EACH FILE'S
OWN 1st-pass sidecar (958,241 observations for file 20) and competes over that, while writing a
2nd-pass sidecar holding only the pool (311,278). The ~647K extra observations, including the
non-survivor decoys that supply `bestDecoy`, were never written anywhere. They were read from a
SECOND PER-FILE artifact the join happened to have because everything ran on one machine.

#### Why the answer is to persist the worker's competition

* **PerFileRescoring already reads its own 1st-pass sidecar** and is entitled to:
  `CompeteStampAndWrite(fileName, FdrScoresSidecar.Pass1Path(inputFile), ...)` - single file,
  own node. Its competition is therefore ALREADY CORRECT, `bestDecoy` included.
* **The JOIN must not read them** - 52.3 GB of 1st-pass sidecars at 257 files is what #4486
  exists to stop reading.
* So the gap is TRANSMISSION, not knowledge: the worker computes the right answer from a source
  it is allowed to read, and does not write it; the join reconstructs it from the pool image,
  which structurally cannot carry it.

**This is not an addition to the HPC contract.** It persists an answer the authorized node
already produces, which is the natural completion of the relocation rather than an extension of
it. It retires `FileCompetitionFromRecords`, the gap-fill discriminator, and the carried-decoy
carry-forward in one move, and it restores the per-run sidecar to a faithful pool image.

Shape: per file, per stratum base_id -> (bestTargetScore, bestTargetEntryId, bestDecoyScore,
bestDecoyEntryId). O(distinct base_ids), a few MB against the 11 MB sidecar. Run q stays in the
per-run sidecar where it already lives (per observation).

#### What the previous implementation got right and wrong

Right: the diagnosis that the join could not recover `bestDecoy` from what was written.
Wrong: the remedy - encoding competition membership by MUTATING the pool image (dropping
non-competing targets, injecting non-pool decoys), which made one file answer two questions and
silently corrupted the one that has to match the baseline. The measured cost was 594 lost
gap-fill observations, 139 panel rows falling out of the experiment-scope detected set, and
`nBetter 988 -> 977`.

#### THE MEASUREMENT (assert bypassed as a diagnostic, since removed)

With the pool image restored, the carried decoys gone and the assert temporarily bypassed:

| leg | result |
|---|---|
| mode1 golden blib | PASS |
| **mode1b diagnostics vs golden** | **PASS** - the panel movement is FIXED |
| mode1c 2nd-pass protein q | PASS - and now over **313,537** shared records, the BASELINE count |
| mode6 fragment release | PASS |
| mode7 regeneration | FAIL 3 (was 5) - only the separate "touched an artifact" defect remains |

Per-run sidecars and the experiment sidecar are now the EXACT baseline sizes, and their
entry_id populations are identical (0 either way, all four files). What still differs:

* per-run: `pep` on 50,675 ids (file 20) - close, not equal (0.0040209 vs 0.0040310)
* experiment: `exp_precursor_q` / `exp_peptide_q` on **113,552** ids; `exp_aggregate` identical

**So the reconstruction's loss DOES reach outputs.** It is the null moving: the lost non-survivor
decoy observations are part of the target/decoy competition, so every q computed against that
null shifts slightly.

**But it does not move the discovery set:**

```
moved q values      : 113,552
CROSS the 1% cutoff : 0
max abs delta       : 0.00107      median abs delta : 0.00045
passing at 1%       : new 31,538   base 31,538   (identical)
```

That is why mode1 / mode1b / mode1c stay green: the reported set is unchanged and every shift
sits above the reporting threshold, in the tail. It is also a GATE COVERAGE finding - an output
moved on 113,552 entries with every correctness leg green.

**Verdict: D is required, not optional.** Under the stated oracle (do the files match the
baseline?) they do not, and a q-value is a reported quantity even at 0.08 - computed here from a
null that is missing real decoy observations. The worker must write its competition down.

## PHASE 1a MERGED IN; two defects left before the gates (2026-08-30 late)

Phase 1a (`Skyline/work/20260830_osprey_pep_normalization`, `C:\proj\pwiz`) is merged into this
branch at `66284dea76`. Merged tree: build clean, **598/598**, ReSharper 0/0. Nothing pushed.

**The merge was textually clean but semantically not.** `FdrScoreRecord` lost its `pep`
parameter, so the worker's `BuildRecords` and five test constructions had to drop it - git could
not see that, only the build could. Worth remembering for the next cross-branch merge in this
sprint.

**Why Phase 1a mattered to Phase 2**: it repairs the write-once contract the scope split claimed.
The per-run 2nd-pass sidecar is now written exactly once, by the node that owns it, and carries
no experiment-scope column (36 -> 28 bytes). That is the property Phase 2's relocation depends
on, and it is what removed the three mode-7 "regeneration touched an artifact" failures at the
source: they were `PatchPep`.

### Two defects left, in order

1. **Record ORDER** (small, and mine). `BuildRecords` emits in `survivors` order, putting
   gap-fills in a trailing block. Measured: `new == (baseline minus gapfill) + gapfill-ascending`,
   and the baseline order is fully ASCENDING by entry_id with unique ids per file - so sorting
   records by entry_id before writing reproduces the baseline exactly.
2. **The join cannot recover `bestDecoy` from the pool image.** The real one, and where the last
   run stopped. Everything measured about it is in the handoff and in "THE FIX, fully specified"
   above. Short form: `FoldFileContribution` needs only the experiment-wide MAX; the missing
   decoy values are already in `output.1st-pass.fdr_experiment.bin`; and for ALL 483,220 decoy
   entry_ids that file's aggregate equals `max over files of the per-file 1st-pass score`
   (verified, zero exceptions). Two caveats to handle rather than assume away: decoys that
   survive somewhere, and `mean-best-N` where the aggregate is a mean rather than a max.

**Next session handoff**: read `ai/.tmp/handoff-20260827_osprey_stage7_stream_increment.md`
before starting work - it carries the startup protocol, the measured facts for defect 2 so they
need not be re-derived, the new verifiers to expect, and the gotchas that cost time today.
