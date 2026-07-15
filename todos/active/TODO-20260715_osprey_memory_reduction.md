# TODO: Osprey per-file memory reduction (single Astral file 49)

**Status**: Active
**Branch**: `Skyline/work/20260715_osprey_memory_reduction` (off master @ 110c9f7833)
**Created**: 2026-07-15
**Goal**: Lower the per-file memory ceiling for the single Astral file-49 case
with verified, byte-identical, regression-green code. Bank safe wins; take the
next big step on the ceiling. Merge nothing that is not regression-green AND
byte-identical (the standing refactor gate: `regression.ps1 -Dataset Stellar`).

See the analysis in
`ai/todos/backlog/brendanx67/TODO-osprey_perfile_scored_entry_streaming.md`
(peak decomposition, ranked levers) and the handoff
`ai/.tmp/handoff-osprey-memory-nightsession.md`.

## Measured baseline (file 49, uncapped, cal-recompute, spectra+lib cache hit)

Single Astral file, `--task PerFileScoring`, `OSPREY_LOG_MEMORY=1`
(run script `ai/.tmp/run-astral-mem.ps1`, ~111 s/run):

| boundary | working_set (peak) | managed_heap |
|---|---|---|
| library-resident | -- | 2.92 GB (3.13M entries) |
| post-calibration (CAL peak) | 20.24 GB | 13.36 GB |
| single file scored (SCORING peak) | 30.91 GB | 16.08 GB |
| perfile-scored-live (floor) | -- | 3.52 GB |

Scoring is the apex here (16.08 GB managed), calibration second (13.36 GB). Both
hold library (~2.9 GB) + MS2 spectra (~6.3 GB). CAL managed also carries the
~3.3 GB uncollected dense XCorr cache.

## Task 0 -- post-calibration MEM boundary (DONE, byte-identical)

`PerFileScoringTask.ProcessFile` emits `[MEM post-calibration]` +
SnapshotReady-gated `CaptureRetentionSnapshot("post-calibration")` right after
`ResolveCalibration` returns, so the calibration peak is measurable (previously
only the scoring peak was). Log-only + profiler-gated -> no-op on batch/regression.

## Task 1 -- library-load cleanups (DONE, byte-identical, regression-green)

- **1a decoy string interning**: `LibraryStringInterner.InternInPlace(decoys)`
  right after `DecoyGenerator.GenerateAllWithCollisionDetection`
  (`PerFileScoringTask.cs`). Decoys mint fresh `"DECOY_"+accession` ProteinIds
  never re-interned; interning collapses the per-protein duplicates (measured
  55.8% collapsed, ~2.9M dup strings).
- **1b shared empty-list sentinels**: `LibraryEntry.EmptyModifications` /
  `EmptyStringList` (`static readonly`) assigned by `LibraryCache.ReadEntries`
  at its `count==0` branches (mods / proteinIds / geneNames), where the `.Add`
  loops run zero times so the sentinel is never mutated. **The constructor keeps
  fresh lists** -- an earlier cut that shared them in the constructor broke 7
  unit tests that do `entry.Modifications.Add` on a fresh-built entry (aliasing
  the shared sentinel); the loaders are the only place the retained empties come
  from anyway.
- **Result**: library-resident 2.92 -> 2.67 GB (-250 MB, -8.6%); CAL peak
  13.36 -> 13.15 GB. Regression Stellar mode1/2/3 byte-identical
  (blib 45,064,192). 506/509 tests pass.

## Task 2 -- MS2 spectra during scoring (IN PROGRESS)

Design in `ai/.tmp/agent-task2-plan.md`. On a calibrated (Astral) file,
`ScoringPipeline.RunCoelutionScoring` builds a full `calibratedSpectra` copy
(~4.2 GB new Mzs) WHILE the caller still holds the original 6.3 GB for
`DeduplicateDoubleCounting` -> ~10.5 GB double-hold during scoring.
- **Bankable slice**: calibrate into the per-window groups + hand
  `DeduplicateDoubleCounting` the pre-extracted MS2 RTs (a `double[]`), then drop
  the original resident list before scoring -> frees ~4.2 GB. Byte-identical
  (same calibration multiply; `ScoreWindow` re-sorts each window by
  `(RetentionTime, ScanNumber)`; identical RT multiset for dedup).
- **Full per-window disk streaming** (another ~6.3 GB, scoring MS2 -> ~NThreads
  windows): `.spectra.bin` is window-seekable (48-byte MS2 prefix + n_peaks*12).
  Larger surface (new index/loader, 3 signature changes, parallel reader). Roadmap
  in the agent plan; attempt only if runway allows, else leave prototyped.

## Task 3 -- calibration phase reduction (PROTOTYPE, likely not mergeable)

The apex crux. `Calibrator.RunCalibration` holds all spectra + the ~3.3 GB dense
XCorr cache across TWO passes (pass 2 needs pass 1's RT model). Investigate
per-window build+release within each pass reusing the Task 2 loader; must stay
byte-identical. If it doesn't land clean, leave a detailed design + the exact
2-pass obstacle.

## Gates (every change)

- `pwsh -File ./pwiz_tools/Osprey/regression.ps1 -Dataset Stellar` (byte-identical).
- `pwsh -File ./ai/scripts/Osprey/Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`
  (SystemMemory.cs 9 warnings are known local #4379 noise).
- `-MemoryProfile` / `OSPREY_LOG_MEMORY` A/B before+after each change.
