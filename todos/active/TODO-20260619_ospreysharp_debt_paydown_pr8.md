# TODO-20260619_ospreysharp_debt_paydown_pr8.md -- OspreySharp debt-paydown PR 8 (decompose the Tasks-layer orchestration monoliths)

## Branch Information
- **Branch**: `Skyline/work/20260619_ospreysharp_debt_paydown_pr8` (create off master)
- **Base**: `master` (after PR 7 #4316 merged as 3a6e017b9e)
- **Created**: 2026-06-19
- **Status**: Ready to start
- **PR**: (pending)

> Seeded by the 2026-06-18 blind `/pw-oop-review` (`ai/.tmp/20260618-oop-review-report.txt`,
> Rec 1). The bones are rated excellent; the one remaining concentrated debt is the
> Tasks-layer orchestration monoliths -- Rust-pipeline porting residue.

## Framing -- output-invariance only; pure code motion
Decompose freely, output-locked by the committed golden (`regression.ps1` @1e-9,
Rust-free). See `feedback_refactor_gate_output_not_structure`. Keep BOTH the Run and
Rehydrate paths intact -- the HPC `--task` split is a CRITICAL near-term requirement
(a teammate is wiring it into a live NextFlow pipeline). Do NOT delete or simplify
side-car writing / rehydration.

## Work -- extract phase collaborators (names indicative; verify line refs in-session)
1. **`PerFileRescoreTask.RescoreOneFile`** (~333 LOC, 9 responsibilities) -> e.g.
   `RescoreResume` (resume-skip), `RescoreTargetAssembly` (target assembly/dedup),
   reload/calibration steps, `RescoreParquetWrite` (reconciled-parquet + sidecar stamp).
   Reduce to a sequencer. (PerFileRescoreTask.cs ~572-905.)
2. **`FirstJoinTask.PlanStage6`** (~274 LOC) -> SEPARATE Stage-5 first-pass FDR from a
   `Stage6Planner` (multi-charge consensus, cross-file consensus RTs, calibration refit,
   reconciliation planning). The class names already promise this split; the code doesn't.
   (FirstJoinTask.cs ~561-835.)
3. **`PerFileScoringTask.LoadLibraryAndDecoys`** (~240 LOC) -> library load / decoy
   marking / pairing-manifest parse / composition pairing as separate collaborators.

## Out of scope
- The small cleanups (env-gate lift, buffer assert) + AbstractScoringTask retire -> PR 9.
- The scorer (`ScoreCandidate` ~590) and `PercolatorFdr` -- review judged them FINE
  cohesive algorithms; do NOT decompose.
- HPC `--task` path SIMPLIFICATION (deleting dual Run/Rehydrate) -- NOT wanted; the split
  is a live requirement.

## Gates (HPC-critical -- this PR touches the side-car/rehydrate code)
- Per commit: `Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection`
  (0 warnings) + `regression.ps1 -Dataset Stellar` (modes 1 & 2 byte-identical).
- **Pre-merge, REQUIRED (the gap we are closing):**
  - `Compare/Compare-Stage7-Rehydration-Strict-CSharp.ps1 -Dataset Stellar` -- proves the
    4-task `--task` HPC worker chain == straight-through at every boundary (NextFlow path).
  - `Compare/Compare-StraightThroughResume-CSharp.ps1 -Dataset Stellar` -- in-process resume.
  - `Compare/Compare-CrossImpl-Reference.ps1 -Dataset Stellar` -- cross-impl (vs frozen Rust).
  - `regression.ps1 -Dataset All` + `Test-PerfGate.ps1 -Dataset Stellar` + `/pw-self-review`.
- **Also add the two rehydrate tests to the standing/pre-commit cadence** so the HPC
  worker path never silently drops out of testing again.

## Notes
- After PR 8 + PR 9, run a FINAL confirmatory blind `/pw-oop-review`; if clean, declare
  the OOP debt-paydown arc complete.
