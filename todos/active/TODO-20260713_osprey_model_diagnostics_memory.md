# TODO-20260713_osprey_model_diagnostics_memory -- Stream Stage-6 planning + --model-diagnostics so memory does not scale with run count

## Branch Information
- **Branch**: `Skyline/work/20260713_osprey_diagnostics_memory`
- **Base**: `master`
- **Created**: 2026-07-13
- **Status**: In Progress
- **Raised by**: Brendan (2026-07-13, after the 82-file run OOMed on a 64 GB box)
- **GitHub Issue**: (pending)
- **PR**: (pending)

## Problem
Two independent all-runs-resident memory ceilings block 82-file (SEA-AD Astral, ~2x entrapment
library) processing on 64 GB. BOTH are addressed in this branch (scope: A+B, one PR).

1. **Stage-6 reconciliation PLANNING amasses all runs' CWT candidates at once** (the actual 82-file
   death point -- see Findings). `Stage6Planner.PlanReconciliation` -> `CwtCandidateLoader.Load`
   builds `Dictionary<file -> List<List<CwtCandidate>>>` for ALL files, each list indexed to that
   file's FULL pre-compaction parquet row count, held simultaneously on top of the ~12-18 GB
   post-Stage-5 live floor. This is the deferred lever #4378 / #4394 both flagged
   ("perFileCwtCandidates loaded at once during planning, planner indexes one file at a time ->
   streamable, NOT done").
2. **`--model-diagnostics` forces the RESIDENT first-pass pool** at the FirstJoin
   (`FirstJoinTask.cs:274` `needsResidentFirstPassPool`) -- the pool the projection streaming path
   (#4400, default) was built to DROP. So memory scales with run count DIFFERENTLY with the flag.
   20 files WITH --model-diagnostics peaks ~60 GB; 82 files would OOM at the FirstJoin resident pool.

## Goal
Make an 82-run SEA-AD run feasible on 64 GB both WITHOUT and WITH `--model-diagnostics`, with memory
NOT scaling with run count differently than a normal run. Streaming, byte-identical default path.

## Findings (2026-07-13 session) -- empirical root cause of the 82-file OOM
From `D:\test\Pilot-MTG-Tissue-May2026\runs\pass2ab-82file-percolator\run.log`
(START `mdiag=False`, `OSPREY_PASS2_QVALUE=''`, `--fdrbench-pass 2`):
- NONE of the three `needsResidentFirstPassPool` triggers fired. Line 5478 confirms the PROJECTION
  streaming path (`RunStreamingIntoProjection: 344,615,472 rows`) -- ceiling #2 above was never in play.
- Progressed through: first-pass compaction `344,615,472 -> 12,405,655`, multi-charge consensus
  (344,364 to rescore), consensus RTs, and calibration refit `82/82 files` (LAST line logged).
- Died `exit=-1` at 371 min. The next phase after calibration refit is `PlanReconciliation` ->
  `CwtCandidateLoader.Load` (all-82-files CWT load). The run never reached the per-file rescore loop.
- => The true 82-file blocker (no-mdiag) is ceiling #1 above (Stage-6 planning CWT all-files load),
  NOT --model-diagnostics and NOT the rescore reload. Do it first, in this branch.
- `#4406` probe: post-Stage-5 live floor ~12-18 GB at 82 files (12.4M post-compaction stubs +
  library + interned peptides). Fits 64 GB; the all-files CWT load on top is what breaks it.

## Plan (A + B, one PR)
### Deliverable A -- stream reconciliation-planning CWT load (unblocks the no-mdiag 82-file run)
1. `CwtCandidateLoader.ValidateAllInRange(...)`: cheap PARQUET-METADATA-only pre-pass (footer row
   counts, no blob decode, no residency) preserving the current all-or-nothing gate
   (`perFileCwtCandidates.Count == perFileEntries.Count`).
2. `ReconciliationPlanner.Plan`: take a lazy `Func<string, IReadOnlyList<IReadOnlyList<CwtCandidate>>>`
   loader; load each file's candidates inside the per-file loop (line ~149/192, which already touches
   only the current file's candidates), release after -- one file resident at a time, not 82.
   Byte-identical: cross-file inputs (`passingBaseIds`, `consensusMap`) do not use CWT candidates.
   Reuse Mike's #4400 callback pattern + #4406 `Release` where applicable.
### Deliverable B -- stream --model-diagnostics accumulation (ceiling #2; enables diagnostics-on 82-file)
Fold each file's contribution into the report's histograms / FDP-yield curves / feature contributions
on the projection path instead of forcing the 344M resident FdrEntry pool. Keep byte-identity of the
default (no-flag) path. (Design TBD after A; the report needs aggregate-shaped data, not per-entry.)

## Validation
- `--memstamp` per phase; confirm no phase's private MB scales with run count once streamed.
- Byte-identical default path: `regression.ps1 -Dataset Stellar` (mode1/2/3, 1e-9); `Test-PerfGate.ps1`.
- 82-file feasibility: hard-link the Stage-5 caches from `pass2ab-82file-percolator` into a fresh dir
  (skips Stage 1-4; first-pass FDR re-runs ~30-60 min to reach the Stage-6 wall), run the new build
  with `--memstamp`; confirm it clears Stage 6 on 64 GB. Then a WITH-`--model-diagnostics` resume for B.

## References
- `Stage6Planner.cs:267` (`CwtCandidateLoader.Load`), `ReconciliationPlanner.cs:149/192`,
  `CwtCandidateLoader.cs`, `ParquetScoreCache.LoadCwtCandidatesFromParquet`.
- `FirstJoinTask.cs:274` (needsResidentFirstPassPool), #4400 (projection streaming callback pattern),
  #4406 (PipelineContext.Release), #4394 / #4376 (reconciliation transients; deferred reload lever),
  #4378 (memory bounding; names Stage 6 as the remaining ceiling).
- Companion: `TODO-osprey_progress_reporter_heartbeat.md` (the ~1 h silent Stage-6 phase in this run).
- This session's 82-file OOM log + `ai/.tmp/pass2ab-20file-results.md`.
