# TODO: Osprey --task FirstPassFDR (join node) memory peak

**Status**: Active.
**Branch**: `Skyline/work/20260717_osprey_firstpassfdr_memory` (pwiz, off master).
**Priority**: Medium-High -- the FirstPassFDR join node holds the whole
all-file scored population resident for Percolator scoring + FDR estimation.
The two PerFile tasks are now bounded < 15 GB sequential; the aggregating
model-training + FDR tasks are the remaining unbounded frontier, and this is
step one.
**Created**: 2026-07-17
**Scope**: `pwiz_tools/Osprey/Osprey.FDR/PercolatorEngine.cs`
(`RunStreamingIntoProjection`), `Osprey.FDR/PercolatorFdr.cs`
(`ScoreProjectionAndComputeFdrInPlace`, `ComputeStreamingCompetitionQvalues`),
`Osprey.FDR/FdrProjection.cs`, `Osprey.Tasks/FirstJoinTask.cs`,
`Osprey.Tasks/PerFileScoringTask.cs` (`LoadJoinOnlyScores`).

## End goal (Brendan, 2026-07-17)

An architecture whose FirstPassFDR memory is **bounded in file count** --
flat from 82 -> 500 files, not linear. The PerFile scoring + rescoring tasks
are already bounded < 15 GB in sequential mode; the aggregating model-training
+ FDR-estimation tasks are next. **FirstPassFDR is the first step.**

Iteration loop: the Astral regression dataset (small enough for
`regression.ps1` correctness + dotTrace/dotMemory), then the final memory
demonstration on the 82-file `pass2ab-82file-percolator-Bmdiag` set via the
hard-link-sidecars + `--task FirstPassFDR` recipe.

## Assessment run (reproducible recipe)

`ai/.tmp/firstpass-mem.ps1` -- builds a fresh hard-link folder with ONLY the
PerFileScoring inputs (`*.scores.parquet` + `*.calibration.json`, hard-linked so no
130 GB copy and so resume does NOT skip), then runs `--task FirstPassFDR` under
`OSPREY_LOG_MEMORY=1`. Key setup facts (from the source run's `.log`):
- Data: `D:\test\Pilot-MTG-Tissue-May2026\runs\pass2ab-82file-percolator-Bmdiag`
  (82 files, each `.scores.parquet` ~1.6 GB / 4.3M rows / SINGLE row group, v26.1.1.194).
- Library: `...\lib\regression\target+decoy+entrapment\carafe_spectral_library.tsv`
  (6.32M entries), decoy manifest `osprey_library_db_pairing.tsv`.
- Search args to match the recorded hashes:
  `--resolution hram --fdr-level precursor --decoys-in-library --decoy-pairing-manifest <manifest>`.
- **Version gate bypass:** `OSPREY_VERSION_OVERRIDE=26.1.1.194` pins the daily-build
  version to the data's (the parquets are 4 days old; today's binary is v198, and the
  parquet gate hard-fails on a daily-build mismatch). No code change / no regeneration.
- `--input-scores <dir>` takes a DIRECTORY (globbed + sorted internally).
- FirstPassFDR needs NO mzML / spectra -- it reads the scored features + library only.

Astral 3-file scores (fast correctness + dotTrace) live at
`D:\test\osprey-runs\astral\` (`*.scores.parquet` + `*.calibration.json`).

## Root cause -- CORRECTED (code read 2026-07-17)

The first-assessment note ("all 82 files' `FdrEntry` stubs materialized at once")
was WRONG about the mechanism, and its 32 GB "Stage 5 start" probe fires BEFORE
the real peak:

- On a fresh `--task FirstPassFDR` run (no `--model-diagnostics`/FDRBench,
  `hasReconSidecars=false`), `LoadJoinOnlyScores` (`PerFileScoringTask.cs:1164`)
  takes the LEAN path: it streams 32 B `FdrProjection` rows straight from parquet;
  the `FdrEntry` stub lists stay EMPTY. The resident data is the
  `FdrProjectionSet`, not fat stubs.
- Model TRAINING is already bounded: `RunStreamingIntoProjection`
  (`PercolatorEngine.cs:670`) subsamples to `MaxTrainSize=300K` and loads only the
  subset's features.
- The unbounded frontier is the **per-row scoring + q-value competition**
  (`ScoreProjectionAndComputeFdrInPlace` + `ComputeStreamingCompetitionQvalues`,
  `PercolatorFdr.cs:1113`/`946`), which allocates one `double[n]` per output.

## MEASURED baseline (2026-07-17, Start-Process detached, 82 files, --threads 8)

Run: `firstpass-mem-n.ps1 -MaxFiles 82` (probes + capacity-hint build), 36m22s,
survived. Dual probes report no-GC managed (committed high-water incl. churn) AND
post-GC managed (genuinely live). `peak_paged` = peak private bytes (commit).

| Probe | live (post-GC) | commit (peak_paged) |
| --- | --- | --- |
| projection built | 15.68 GB | -- (capacity hint: 21.09 -> 15.68, saved ~5.4 GB) |
| model trained | 26.81 GB | -- |
| score pass done | 29.37 GB | -- |
| **q-value peak** | **38.04 GB** | **86.97 GB** |
| after pass (transients freed) | 20.57 GB | 87 held |

- **Peak = 87 GB commit / 38 GB live.** Peak WS 56 GB, ~10 GB paged. The box
  commits ~100 GB via the page file and SURVIVES (earlier "OOM kills" were
  harness reaping of background-bash runs, NOT real OOM -- launch long runs via
  `Start-Process` + Monitor, per `[[feedback_night_session_detached_runs]]`).
- **~49 GB of the 87 GB commit is reclaimable churn + Server-GC committed slack,
  NOT live.** Two churn sources, both visible as memory sawtooth:
  1. **Feature-load churn (~30 GB):** `LoadPinFeaturesFromParquet` allocates 21
     column arrays + 4.2M `double[21]` per file, loaded TWICE (subset extraction +
     score pass), ~115 GB allocated total. HDD-I/O-bound (D: is a SATA HDD).
  2. **Competition scratch churn (the q-value-pass sawtooth):** each helper
     (`ComputePerRun*`, `ComputeExperiment*`, `CompeteAll`) reallocates O(n)
     temp arrays / dicts per sub-step.
- **The 38 GB live is the structural O(files) set** (the Step-B target): projection
  11.3 + library 4.4 (fixed) + flat identity arrays ~7 + finalScores 2.8 + sink
  outputs 5.5 + 5 q-value arrays (net ~8.7 at peak). At 500 files ~210+ GB live.
- **Wall time is also a cost:** the q-value competition + clamp are SINGLE-THREADED
  over 344.6M rows (CPU ~4% = one core), plus double HDD feature reads. Stage 6
  planning by contrast parallelizes (CPU 92%). Bounding (B) should parallelize the
  serial passes too.
- Correct output: 1,870,745 precursors pass; compaction 344.6M -> 12.4M survivors
  (90,544 passing base_ids). Log: `D:\test\osprey-runs\_firstpassmem_82f_base\firstpassfdr-mem-base.log`.

## Reader A/B result (2026-07-17) -- the feature reader does NOT lower the peak

82-file A/B, baseline (probe+capacity-hint) vs +`ParquetFeatureReader`
(`_firstpassmem_82f_reader`):

| Probe (post-GC live) | baseline | +reader |
| --- | --- | --- |
| projection built | 15.68 | (same) |
| model trained | 26.81 | 27.74 |
| score pass done | 29.37 | 30.30 |
| q-value PEAK live | 38.04 | 38.97 |
| **q-value PEAK commit (peak_paged)** | **86.97** | **90.88** |
| after pass (transients freed) | 20.57 | 20.57 |

- **Live matches (+~0.9 GB = the reader's one reused ~706 MB row buffer). Peak commit
  is UNCHANGED within variance (90.88 vs 86.97).** Byte-identical output confirmed:
  1,870,745 precursors (identical), Stellar golden PASS (mode1/2/3), 509/512 unit tests.
- **Why no peak win:** the peak commit is Server-GC slack over the **LOH column churn**,
  not the gen-0 row churn the reader fixed. Each per-file column read is a 34 MB array
  (single-row-group test data) -- well over the 85 KB LOH threshold -- allocated inside
  Parquet.NET (not reusable), so ~58 GB of LOH column garbage sets the high-water
  regardless of the row arrays. 100K-row-group data (#4430) would be 800 KB reads --
  still LOH, just smaller (easier gen-2), so somewhat better but not off the LOH; can't
  test without regenerating (or a parquet re-chunk).
- **The reader's defensible value (NOT a peak win):** byte-identical; removes 344.6M
  gen-0 row-array allocations (GC object-count / CPU); FLAT in file count (row churn no
  longer grows with N -- matters at 500 files). Commit gated on a wall-time perf sign.

**Why a bounded design is possible (byte-identical, Step B):** the q-value math's
intrinsic working set is bounded, not O(n) -- PEP KDE is fit on competition
winners (one per base_id ~= O(library)); experiment-q is best-per-precursor
(~= O(distinct precursors)); run-q is per-file competition (~= O(rows in one
file)). The O(n) arrays exist only because the current design assigns a q-value
to every row and holds all of them to write back, even though the write-back
already streams per-file via `IFdrOutputSink`. A two-pass streaming design
(collect bounded lookup structures -> stream per-file to assign + emit) is
bounded in file count and byte-identical (same exact target-decoy counting,
less RAM held).

## Plan (Brendan's call 2026-07-17: A first, then B)

**Step A -- byte-identical churn reduction (revised after measurement).** The
measurement showed the reclaimable slice is ~49 GB of CHURN + Server-GC committed
slack, NOT the live buffers -- so Step A targets the churn, byte-identical, and
leaves the flat-array / q-array live reduction to B (which rewrites those helpers
anyway). Sub-steps:
1. **Capacity hint on the projection lists** -- DONE (`PerFileScoringTask.LoadJoinOnlyScores`
   pre-sizes each per-file `List<FdrProjection>` to the parquet row count; -5.4 GB).
2. **Peak `[MEM]` probe** -- DONE (threaded `Action<string> logMemory` from
   `FirstJoinTask.RunFirstPassProjection` -> `RunPercolatorFdr(projection)` ->
   `RunStreamingIntoProjection` -> `ScoreProjectionAndComputeFdrInPlace`; logs
   no-GC committed + post-GC live at model-trained / score-pass-done / q-value peak).
3. **Feature-buffer reuse** -- DONE (`ParquetScoreCache.ParquetFeatureReader`, nested
   in Osprey.IO). One reused `double[][]` row buffer refilled per file, columns read +
   scattered one at a time; `FirstJoinTask.RunFirstPassProjection` owns one reader for
   the whole projection pass (subset load + score pass both request one file at a time
   and copy/clone what they keep) and disposes it before survivor reload. Byte-identical
   (same columns/order/NaN-clamp). Eliminates the ~115 GB per-file feature re-alloc
   churn; the reused buffer is one file's worth (~706 MB) reused, so it is already flat
   in file count. Validated: Stellar regression PASS (mode1/2/3 byte-identical) + 509/512
   unit tests + my files inspection-clean.
4. *(stretch, not done)* reuse the competition per-substep scratch (the q-value-pass
   sawtooth).

Gates: `regression.ps1` byte-identical (Stellar DONE) + 509/512 unit tests DONE.
**82-file memory A/B DONE -- see "Reader A/B result" above: peak NOT lowered (LOH column
churn dominates), wall time flat (36m39 vs 36m22, HDD-bound). Brendan gated the commit on
"any sign of perf improvement"; none -> the reader commit is HELD, kept in the working
tree (byte-identical + flat-in-files, not a peak/wall-time win). Capacity hint + probe
are separable and unambiguously worth keeping.** Does NOT bound 500 files -- that is B.

**Step B -- bounded q-value competition redesign (next).** Restructure
`ComputeStreamingCompetitionQvalues` + the score pass so only the bounded
per-precursor / per-file structures are resident and rows are streamed twice.
Truly flat in file count. Touches the most parity-critical code (PEP KDE order,
the experiment-q clamp), so gate on the full regression + FDRBench oracle with
careful bisection. Design against Step A's measured numbers. Concrete Step-B levers
surfaced by the measurement:
- **100K-block feature streaming (Brendan, 2026-07-17):** the parquet is now written in
  100K-row row groups (#4430/#4433), and on the 1st pass the `(EntryId,Charge,ParquetIndex)`
  sort is a NO-OP (parquet already in that order), so the score pass walks features
  SEQUENTIALLY by ParquetIndex -- it is genuinely 100K-block-streamable (reused buffer
  ~17 MB instead of a whole file). Catch: the training-subset load random-accesses ~300K
  scattered rows, so it needs the whole-file buffer OR a selective by-parquet-index read.
  The `ParquetFeatureReader` already reads per-row-group, so the COLUMN transient already
  matches the block size; this lever shrinks the resident ROW buffer + enables true
  bounded streaming of the score pass.
- **Parallelize the serial 344.6M-row passes** (score + q-value competition + clamp are
  single-threaded, ~4% CPU = one core, and drive the 36-min wall time). Stage 6 planning
  already uses `OspreyParallel.For` (92% CPU) as a template.
  - **Per-run q-values -- COMMITTED (f4719e084, 2026-07-17), MEASURED 3.46x, byte-identical.**
    `ComputePerRunPrecursorQvalues` + `ComputePerRunPeptideQvalues` run one file per thread
    via `OspreyParallel.For` (degree = `PercolatorConfig.MaxParallelism` <- `OspreyConfig.NThreads`,
    default 1 = serial for tests/FdrEntry). Each file's competition is independent + writes
    disjoint `qvalues` indices -> any degree byte-identical. A/B (24-file, degree 8):
    precursor 21.66->5.73s (3.8x), peptide 49.93->14.98s (3.3x), total 71.6->20.7s (3.46x);
    ~4 min -> ~1.2 min at 82 files. Gate passed: Stellar mode1/2/3 + 509/512 unit tests.
    Still serial (parity-fragile, Part-B): the clamp (partition + `min`-merge is easy), and
    the global PEP/experiment competitions (sort tie-break + sequential cumulative scan +
    KDE base_id-order).
- **Bound the q-value output arrays / sink** (the 5 `double[n]` + `FdrProjectionOutputs`)
  by streaming per-file assignment from bounded lookup tables (see the "Why a bounded
  design is possible" section above).

## Gates
- `regression.ps1 -Dataset Stellar` (fast) + `-Dataset Astral` for any
  algorithm-adjacent change; `-Dataset All` before a behavior/perf-sensitive merge.
- `Build-Osprey.ps1 -RunTests -RunInspection`.
- FDRBench entrapment oracle for Step B (moves the discovery set / q-values).
- Memory A/B: the 82-file `--task FirstPassFDR` run (final scaling demo);
  Astral 3-file + dotTrace for iteration.

## Session update (2026-07-17 PM)

- **Reader (ParquetFeatureReader / feature-buffer pooling): DISCARDED.** Brendan's call:
  don't add pooling to beat GC without a demonstrated win -- Gen-0 is very fast, GC
  usually wins, and a single "within variance" run is not proof of no-regression (need
  >=1 more A/B where the new code is actually faster). The reader was byte-identical but
  moved neither the peak (LOH column churn dominates) nor wall time (HDD-bound). Lesson
  saved to memory `[[feedback_no_unproven_pooling_vs_gc]]`.
- **Per-run q-value parallelization: being MEASURED** (measurement build with env-var
  degree `OSPREY_QVAL_THREADS` + `[QVAL-TIMING]` probe; 24-file A/B degree 1 vs 8 via
  `ai/.tmp/qval-ab.ps1`). Keep + do the commit-ready (config-plumbed) version only if the
  A/B proves it faster.
- Capacity hint (-5.4 GB live projection) + the peak `[MEM]` probe were also discarded
  with the reader (entangled). The capacity hint is a proven, separable live win, cheap
  to re-add standalone if wanted.

## Parquet chunk-sizing study (Brendan, 2026-07-17) -- next task

The prior session picked 100K rows/row-group (#4430/#4433) fairly arbitrarily. Study
smaller sizes for the cost/benefit tradeoff. Deliverables:

1. **Re-chunk utility** -- a standalone Osprey tool: read a `.scores.parquet`, rewrite it
   with a configurable rows-per-row-group, WITHOUT rescoring (byte-identical data, only
   the row-group blocking changes). Lets us test chunk sizes on the existing 82-file data
   without regenerating (the hard-link recipe avoids the expensive PerFileScoring).
   Useful utility to keep until we settle on the optimal chunking. Reuse Osprey.IO's
   Parquet read/write (`ParquetScoreCache`); verify a re-chunked file still passes
   `ValidateScoresParquetGroup` (hashes search/library/version, which re-chunking preserves).
2. **Study matrix**: re-chunk to **10,000 / 20,000 / 50,000 / 100,000** rows and measure
   for each:
   - **disk size** (does 10K bloat the file via row-group metadata/footers?),
   - **load time** (`--task FirstPassFDR` feature-read wall time -- HDD-bound),
   - **memory ceiling** (peak commit / the LOH column-read transient: smaller groups =>
     smaller column reads; <~10K rows would drop columns below the 85 KB LOH threshold ->
     gen-0 not LOH; 10K x 8 B = 80 KB is right at the boundary).
   Directly feeds Part B's 100K-block score-pass streaming (optimal block = this study's answer).

## References
- Sibling: `[[TODO-osprey_perfilescoring_calibration_memory_peak]]`.
- `[[project_sead_pilot_mtg_dataset]]`, `[[reference_osprey_astral_thread_memory_oom]]`,
  `[[reference_osprey_perfile_mem_measurement]]`,
  `[[reference_osprey_resident_firstpass_streams_features]]`.
