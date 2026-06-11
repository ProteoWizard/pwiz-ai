# TODO-20260423_ospreysharp_percolator_streaming.md — Stage 5 Percolator streaming path port

> Phase 4 pre-Stage-6 prerequisite. Ports the Rust `run_percolator_fdr`
> **streaming** branch (`maccoss/osprey/crates/osprey/src/pipeline.rs:4186-4580`,
> introduced 2026-03-25 in commit `1d4a9a0e`) to OspreySharp so Stage 5
> output stays byte-identical with Rust on datasets above the 600K
> observation threshold (Astral single-file, 3-file Stellar, 3-file
> Astral, and anything larger Mike runs in production).

## Branch Information

- **pwiz branch**: `Skyline/work/20260423_ospreysharp_percolator_streaming`
- **osprey branch**: none (porting existing Rust behaviour to OspreySharp)
- **Base**: `master` (pwiz at `80f5341bc`)
- **Created**: 2026-04-23
- **Status**: Completed
- **GitHub Issue**: (none — tool work, no Skyline integration yet)
- **PR (pwiz)**: [#4164](https://github.com/ProteoWizard/pwiz/pull/4164) (merged 2026-04-24 at `edc5e0251`)

## Problem

`Compare-Stage5-AllFiles.ps1 -Dataset Astral` on the first day of
Phase 4 exposed a structural Stage 5 divergence: Rust's subsample
dump had 300,000 rows all `in_subsample=true` while C# had
1,683,779 rows (300K true + 1.38M false). Both tools were reading
the same Rust-generated `--join-only` Parquet; the divergence came
from a C# gap in the Percolator dispatch.

Root-caused to `pipeline.rs::run_percolator_fdr`'s **streaming**
branch, gated by `total_entries > max_train_size * 2` (=600K with
default 300K cap). On that branch Rust:

1. Deduplicates to one best-scoring observation per `base_id` + isDecoy
   across all files (`Features[0] = coelution_sum` ranking).
2. Peptide-grouped subsamples to `max_train_size` via XOR-shift
   Fisher-Yates.
3. Calls `run_percolator(subset, train_only=true)` so the feature
   **standardizer is fit on the 300K subset**, not on the full 1.7M-
   observation pool.
4. Applies averaged fold model + standardizer to ALL entries.
5. Computes PEP + per-run + experiment q-values from the flat score
   array via `compute_fdr_from_stubs`.

OspreySharp had only the direct path, which standardizes on every
entry passed in -- correct for Stellar (<600K, both tools take the
direct path) but wrong for Astral, where the two standardizers are
fit on different data pools and every downstream value cascades.
Stellar stayed byte-identical through single-file tests the whole
time, masking the gap.

## Fix

1. `OspreySharp.FDR.PercolatorConfig.TrainOnly` flag; when set,
   `PercolatorFdr.RunPercolator` trains + standardizes + writes the
   Stage 5 diagnostic dumps + returns, skipping CV/averaged scoring
   and q-value computation.
2. `OspreySharp.FDR.PercolatorFdr.ScorePopulationAndComputeFdr`
   (new public method): given `PercolatorResults` from a train-only
   run, applies averaged fold weights + standardizer to every entry,
   fits PEP, computes per-run + experiment precursor/peptide q-values.
   Mirrors Rust pipeline.rs phases 4-5 + `compute_fdr_from_stubs`
   ordering (winners sorted base_id-ascending before PepEstimator
   to avoid 1-ULP KDE-sum divergence).
3. `OspreySharp.AnalysisPipeline.RunPercolatorStreaming` (new
   private method): best-per-precursor dedup + peptide-group subsample
   + `RunPercolator(subset, TrainOnly=true)` + `ScorePopulationAndComputeFdr`.
   Uses the existing `SelectBestPerPrecursor` + `SubsampleByPeptideGroup`
   helpers (same XOR-shift RNG, seed, constants, and peptide-key sort
   order as Rust).
4. `AnalysisPipeline.RunPercolatorFdr` dispatches streaming vs direct
   on the same `total_entries > MaxTrainSize * 2` threshold Rust uses.

## Gate for PR

- `Build-OspreySharp.ps1 -RunInspection -RunTests` green (221/221).
- `Compare-Stage5-AllFiles.ps1 -Dataset Stellar` 3/3 byte-identical
  (regression check — Stellar still takes the direct path, unchanged).
- `Compare-Stage5-AllFiles.ps1 -Dataset Astral` 3/3 byte-identical
  (new parity).

## See also

- `ai/todos/active/TODO-20260423_osprey_sharp_stage6.md` — the
  umbrella Stage 6 sub-sprint that this PR unblocks.
- `ai/todos/active/TODO-20260423_osprey_sharp.md` — Phase 4 umbrella
  plan.
- `ai/todos/completed/TODO-20260423_ospreysharp_dump_format.md` —
  sibling Stage 5 fix (dump text format) that paved the way for
  byte-level parity validation.
- `C:\proj\osprey\crates\osprey\src\pipeline.rs:4186-4580` — Rust
  reference implementation (run_percolator_fdr streaming branch).
- `C:\proj\osprey\crates\osprey-fdr\src\percolator.rs:1877+` —
  `compute_fdr_from_stubs` (the base_id-sorted winner ordering that
  `ScorePopulationAndComputeFdr` mirrors).

## Progress log

### Session 1 (2026-04-23) — Ported + validated

- Implemented all four changes above on branch
  `Skyline/work/20260423_ospreysharp_percolator_streaming` (renamed
  from the prior `_stage6` branch name after scope was split).
- Build + inspection + 221/221 unit tests green on both net472 and
  net8.0.
- `Compare-Stage5-AllFiles.ps1 -Dataset Stellar`: 3/3 files byte-
  identical on all four Stage 5 dumps (std / sub / svm / perc).
  Regression-clean: Stellar still uses the direct path.
- `Compare-Stage5-AllFiles.ps1 -Dataset Astral`: initially 0/3, then
  3/3 std + sub + svm after the streaming dispatch + train-only +
  score-all, then 3/3 perc after sorting PEP winners base_id-
  ascending (matching Rust `compute_fdr_from_stubs`).
- Final state: 6/6 files across both datasets byte-identical on all
  four Stage 5 dumps.

### Session 2 (2026-04-23/24) — Review + merge

PR [ProteoWizard/pwiz#4164](https://github.com/ProteoWizard/pwiz/pull/4164)
opened, reviewed, merged `2026-04-24T00:50:33Z` at squash commit
`edc5e0251`.

Three Copilot inline review comments, two addressed pre-merge, one
deferred:

1. **XML doc adjacency** (AnalysisPipeline.cs) — `RunPercolatorStreaming`
   was inserted between `BuildBasicFeatures`'s existing `<summary>`
   and its signature, which detached `BuildBasicFeatures` from its
   doc. **Fixed** by moving `RunPercolatorStreaming` to land after
   `BuildBasicFeatures` (commit `bf30ede50`).
2. **Missing `pwiz_tools/OspreySharp` entry** in
   `scripts/misc/vcs_trigger_and_paths_config.py` (new gate from
   pwiz #4161). **Fixed** by adding
   `("pwiz_tools/OspreySharp/.*", {})` per Matt Chambers's guidance
   -- OspreySharp has no dedicated TeamCity build config yet, so the
   empty target set silences the gate without firing unrelated builds
   (commit `ac5ecd66a`). Follow-up: when OspreySharp gets wired into
   Skyline's TC build (Matt offered) or its own config, map the entry
   to the appropriate targets.
3. **Missing unit tests** for `PercolatorConfig.TrainOnly` early
   return and `PercolatorFdr.ScorePopulationAndComputeFdr`.
   **Deferred** -- integration-level parity is proven by
   `Compare-Stage5-AllFiles.ps1` running both Stellar + Astral at
   6/6 byte-identical across all four Stage 5 dumps, and
   constructing unit-test fixtures large enough to trigger the
   streaming path (>600K synthetic entries) is non-trivial. Worth a
   follow-up issue if the logic ever needs refactoring.
