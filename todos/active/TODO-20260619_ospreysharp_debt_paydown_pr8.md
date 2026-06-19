# TODO-20260619_ospreysharp_debt_paydown_pr8.md -- OspreySharp debt-paydown PR 8 (decompose the Tasks-layer orchestration monoliths)

## Branch Information
- **Branch**: `Skyline/work/20260619_ospreysharp_debt_paydown_pr8` (create off master)
- **Base**: `master` (after PR 7 #4316 merged as 3a6e017b9e)
- **Created**: 2026-06-19
- **Status**: In Progress -- 3 decompositions done + all pre-merge gates green; one open item (standing-cadence wiring) pending decision
- **PR**: (pending)

## Progress (2026-06-19)
Branch pushed: `Skyline/work/20260619_ospreysharp_debt_paydown_pr8` (off master 3a6e017b9e).

Commits (each built + inspected 0-warning + Stellar regression modes 1&2 byte-identical):
- `e1d44d4` RescoreOneFile -> TryResumeRescoredFile, TryAssembleRescoreTargets, WriteReconciledAndStamp (sequencer; scoring kept whole).
- `328c8c2` Stage6Planner collaborator class owning the 4 planning phases; PlanStage6 reduced to a sequencer.
- `842cf37` LoadLibraryAndDecoys -> MarkSuppliedDecoys + TryPairSuppliedDecoys.

Verified the TODO's stale line refs in-session (PR 3/4 had already extracted many helpers; these three methods remained 234-273 LOC sequencers with inline phases).

### Pre-merge gates -- ALL GREEN
- Build + 390 tests + 0-warning inspection: PASS (per commit).
- `regression.ps1 -Dataset All` (Stellar+Astral, modes 1 golden & 2 resume): PASS 4/4.
- `Compare-Stage7-Rehydration-Strict-CSharp -Dataset Stellar`: PASS at every boundary (Stage 5 sidecars byte-identical, Stage 6 reconciled parquets bit-identical, Stage 7 protein-FDR + blib 1e-9). Proves the 4-task `--task` HPC worker chain == straight-through.
- `Compare-StraightThroughResume-CSharp -Dataset Stellar`: PASS (cold==warm blib 52,514,816; 14.6x resume speedup). NOTE: the script's header note about a failing resume-RT bug is stale -- that bug was fixed in the earlier resume-purification PRs; it is green now.
- `Compare-CrossImpl-Reference -Dataset Stellar` (frozen Rust): PASS at every boundary.
- `Test-PerfGate -Dataset Stellar`: PASS (total median -3.8%, within noise; all stages ok/info, no regression).
- `/pw-self-review` (independent fresh-context agent): verdict BEHAVIOR-PRESERVING, no concerns; only benign log-reorder noted (now before the side-effect-free ShallowClone).

### Open item -- standing-cadence wiring (needs decision)
"Add the two rehydrate tests to the standing/pre-commit cadence." Finding: regression.ps1's **mode 2 already IS the in-process straight-through-resume rehydrate test**. The genuine gap is the **HPC `--task` worker chain** (Compare-Stage7-Rehydration-Strict-CSharp). regression.ps1 is deliberately self-contained (no ai/ dependency); the strict comparator lives in ai/ and depends on parquet_diff.py + Dataset-Config.ps1. Options: (A) add a self-contained mode-3 HPC-chain leg to regression.ps1; (B) have tctest.bat additionally invoke the ai/ comparator (cross-repo coupling); (C) separate TeamCity config. Pending user decision before implementing.

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
