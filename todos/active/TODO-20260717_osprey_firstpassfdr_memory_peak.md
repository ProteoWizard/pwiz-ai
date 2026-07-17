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

**Resident cost model** (n = total scored rows across all files, ~344.6M @ 82 files):

| Buffer | B/row | @344.6M | Where |
| --- | --- | --- | --- |
| `FdrProjectionSet` (per-file `List<FdrProjection>`) | 32 | ~11 GB | held all pass |
| flat `labels`+`entryIds`+`peptides`+`fileNames` | 21 | ~7 GB | `RunStreamingIntoProjection` -> reused by score pass |
| `finalScores` | 8 | ~2.8 GB | score pass |
| `peps` + 4 q-value arrays | 40 | ~14 GB | `ComputeStreamingCompetitionQvalues` |
| **peak** | **~101** | **~35 GB** | + CompeteAll winners + peptide table |

True peak ~35-40 GB @ 82 files (higher than the recorded 32 GB, which missed the
q-value pass) -> ~210+ GB @ 500 files. Unlike the Stage-6 / calibration peaks,
this is GENUINELY LIVE managed data, so the lever is real -- this is NOT
Server-GC retained-committed. See
`[[project_osprey_pipeline_peak_is_servergc_retained_committed]]` for the
contrast.

**Why a bounded design is possible (byte-identical):** the q-value math's
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

**Step A -- byte-identical buffer reduction (this commit).** Drop the redundant
flat identity arrays (they duplicate projection fields: `peptides`/`fileNames`
are `PeptideId`/`FileIdx` re-expanded as 8 B refs) and stop holding all five
q-value `double[n]` at once. ~2x peak reduction, `regression.ps1` byte-identical.
Also stands up the Astral test harness + a `[MEM]`/probe at the REAL peak (the
q-value pass), which is currently unmeasured. De-risks B.

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
