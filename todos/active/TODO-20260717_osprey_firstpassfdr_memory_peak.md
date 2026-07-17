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
3. **Feature-buffer reuse** -- reuse a per-file feature buffer instead of 4.2M fresh
   `double[21]` per file in the score pass + subset extraction (and, if cheap, avoid
   loading all rows for the <=300K subset). Collapses ~30 GB feature churn + the HDD
   re-reads. `LoadPinFeaturesFromParquet` + the two streaming loops.
4. *(stretch)* reuse the competition per-substep scratch (the sawtooth).

Target: commit peak 87 -> ~45-50 GB, no paging, faster. Gates: `regression.ps1`
byte-identical + `Test-PerfGate` (feature-load path is perf-sensitive). Does NOT
bound 500 files -- that is B.

**Step B -- bounded q-value competition redesign (next).** Restructure
`ComputeStreamingCompetitionQvalues` + the score pass so only the bounded
per-precursor / per-file structures are resident and rows are streamed twice.
Truly flat in file count. Touches the most parity-critical code (PEP KDE order,
the experiment-q clamp), so gate on the full regression + FDRBench oracle with
careful bisection. Design against Step A's measured numbers.

## Gates
- `regression.ps1 -Dataset Stellar` (fast) + `-Dataset Astral` for any
  algorithm-adjacent change; `-Dataset All` before a behavior/perf-sensitive merge.
- `Build-Osprey.ps1 -RunTests -RunInspection`.
- FDRBench entrapment oracle for Step B (moves the discovery set / q-values).
- Memory A/B: the 82-file `--task FirstPassFDR` run (final scaling demo);
  Astral 3-file + dotTrace for iteration.

## References
- Sibling: `[[TODO-osprey_perfilescoring_calibration_memory_peak]]`.
- `[[project_sead_pilot_mtg_dataset]]`, `[[reference_osprey_astral_thread_memory_oom]]`,
  `[[reference_osprey_perfile_mem_measurement]]`,
  `[[reference_osprey_resident_firstpass_streams_features]]`.
