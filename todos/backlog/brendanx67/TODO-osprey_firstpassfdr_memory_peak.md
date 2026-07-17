# TODO: Osprey --task FirstPassFDR (join node) memory peak

**Status**: Backlog -- first assessment run launched 2026-07-17 (in flight at write time).
**Priority**: Medium-High -- the FirstPassFDR join node loads EVERY per-file
`.scores.parquet` at once for Percolator training; historically the largest join-node
peak (the "~53 GB at 82 files" era before streaming). Confirm where it sits now.
**Created**: 2026-07-17
**Scope**: `pwiz_tools/Osprey/Osprey.Tasks/FirstJoinTask.cs` +
`PerFileScoringTask.LoadJoinOnlyScores`, `Osprey.FDR/PercolatorEngine.cs`,
`Osprey.FDR/Reconciliation/*`.

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

## Observed (first run, 2026-07-17, OSPREY_LOG_MEMORY, log at D:\test\osprey-runs\_firstpassmem\firstpassfdr-mem.log)

- library-resident: managed 4.38 GB (6.32M entries).
- **PEAK = "Stage 5 start: 82 files loaded (stubs), before first-pass FDR":
  working_set=32.11 (peak=35.52 GB), managed_heap=32.56 GB, gc_committed=31.88 GB,
  gc_heap(used)=22.98 GB, gc_fragmented=2.51.**
- stage5-start-live (post-GC): managed **20.53 GB**.
- projection built (344,615,472 rows, 4.5M distinct peptides; FdrEntry stubs released):
  managed 20.53 GB, gc_heap 20.60 GB.

**KEY: this peak is DIFFERENT from the Stage-6 / calibration peaks.** Here
`gc_heap(used)=22.98 GB` is GENUINELY LIVE managed data -- it is NOT Server-GC
retained-committed. The ~32 GB peak is **all 82 files' `FdrEntry` stubs materialized
at once** before the 32 B projection is built and the stubs released (drops to ~20.5
GB). So the lever here is REAL: **stream the per-file load -> projection -> release**
so all 82 files' fat stubs never coexist, rather than `LoadJoinOnlyScores` building
the whole pooled stub set first. The projection itself (344.6M rows x 32 B ~= 11 GB +
per-peptide maps) is the ~20.5 GB residual -- a second, smaller target.

- dotMemory follow-up (optional, heavy on 82 files): `loh-diag`-style `-DotMemory`.

## Expected shape / where to look

- Loads all 82 `.scores.parquet` -> `LoadJoinOnlyScores` already streams 32 B
  `FdrProjection` rows (not fat stubs) unless a resident pool / reconciled bundle is
  needed (`[[reference_osprey_resident_firstpass_streams_features]]`) -- confirm that
  path is taken here (it should be: first-pass, no `hasReconSidecars`).
- Percolator SVM training across the whole pooled set (`PercolatorEngine`) -- the
  fold matrices scale with total PSMs (82 x 4.3M).
- Same retained-committed lens as the other peaks: expect the RSS "gray" to be
  Server-GC committed-but-free, not native. Measure `gc_committed` vs `gc_heap(used)`;
  do NOT reach for `DOTNET_GCConserveMemory` (throughput cost) -- lower the actual
  peak *allocation* instead. See `[[project_osprey_pipeline_peak_is_servergc_retained_committed]]`.

## Gates
- `regression.ps1 -Dataset Stellar` for any algorithm-affecting change.
- Memory A/B on this 82-file FirstPassFDR run.

## References
- Sibling: `[[TODO-osprey_perfilescoring_calibration_memory_peak]]`.
- `[[project_sead_pilot_mtg_dataset]]`, `[[reference_osprey_astral_thread_memory_oom]]`,
  `[[reference_osprey_perfile_mem_measurement]]`.
