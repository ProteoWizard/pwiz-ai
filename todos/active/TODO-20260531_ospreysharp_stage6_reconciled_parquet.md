# TODO: Stage 6 writes a separate reconciled parquet (stop overwriting Stage 4)

**Status**: In progress
**Branch**: `Skyline/work/20260531_ospreysharp_stage6_reconciled_parquet` (pwiz)
**PR**: (pending)
**Created**: 2026-05-31
**Scope**: `C:\proj\pwiz\pwiz_tools\OspreySharp` (C#-only; Rust `osprey` untouched)

## Objective

Stage 6 (`PerFileRescoreTask`) must stop **destructively overwriting** the Stage 4
(`PerFileScoringTask`) per-file `<stem>.scores.parquet`. It now writes a separate
`<stem>.reconciled.scores.parquet` sibling, leaving the Stage 4 output intact. Stage 7
(`MergeNodeTask`) and the resume / `--join-at-pass=2` paths read the reconciled file
when it exists, else fall back to the original.

## Provenance (this is a long-deferred fix, not a new idea)

- Flagged a **design defect to fix** in the WSL-parity sprint:
  `ai/todos/completed/TODO-20260516_ospreysharp_wsl_parity-phase1.md` finding #7
  ("Stage 6 destructively overwrites the original `.scores.parquet` ... A partial
  Stage 6 crash leaves indeterminate state across 300-1000 file HPC workloads. User
  confirmed this is a design defect to fix."). That Phase-1 file was orphaned in
  `active/` (its Phase-2 successor was already in `completed/`); moved to `completed/`
  as part of this work.
- Concrete design (separate `.reconciled.scores.parquet`, update `--join-at-pass=2`
  loaders + cache validity probes) was specced in the (gitignored) 2026-05-19
  `ai/.tmp/stage7-divergence-smoke/FINDING.md` + `handoff-20260519_stage7_divergence.md`
  task #35, but was never promoted to a tracked TODO. This TODO closes that gap.
- The coupled blocker from 2026-05-19 (C# not running 2nd-pass Percolator -> the
  60373-vs-45153 "which is truth" question) is since resolved: C# 2nd-pass Percolator
  is wired in (`MergeNodeTask.Run` "Bug C" block). Straight-through (60373) is the
  confirmed production baseline.
- **Supersedes PR-D** in `ai/todos/backlog/brendanx67/TODO-ospreysharp_task_layer_decomposition.md`
  (the Stage 5->7 forward-reach move): eliminating the overwrite is the proper root
  fix; the forward-reach is no longer the target.

## Decisions

- **C#-only.** The 1e-9 cross-impl gate compares Stage-7 protein-FDR dump + `.blib`
  content, not intermediate parquet paths, so a C#-side filename change does not affect
  it. Rust keeps overwriting at the original path.
- **Per-file read contract: reconciled-if-exists-else-original.** `PerFileRescoreTask`
  skips no-work files (no reconciled parquet written), so this fallback is provably
  byte-equivalent to the former in-place overwrite.
- Intermediate-artifact cleanup flag (disk reclaim) is **deferred** to a follow-up.

## Tasks

- [x] `ParquetScoreCache`: `GetReconciledScoresPath`, `ReconciledPathFromScoresPath`,
  `EffectiveScoresPathFromScoresPath`.
- [x] `PerFileRescoreTask`: `Outputs()` -> reconciled; `WriteReconciledParquet` split
  read(original)/write(reconciled); resume skip/delete/sidecar on reconciled path.
- [x] `MergeNodeTask`: 2nd-pass feature reload + `Inputs()` + validity-dep via
  `EffectiveScoresPathFromScoresPath`.
- [x] `RescoreHydration.SyntheticInputFromParquet` strips `.reconciled.scores`;
  `PerFileScoringTask.LoadJoinOnlyScores` unified onto that helper.
- [x] `Program.ResolveInputScores`: per-stem dedupe of the dir glob (prefer reconciled).
- [x] `TaskValiditySidecar` class doc updated (no longer "overwrites in place").
- [x] Unit tests (4 new) + pre-commit gate (build OK, inspection 0/0, 349/351 pass).
- [x] Tier 1 straight-through 1e-9 gate (Astral, `-SkipRust`): PASS (precursor delta 0,
  Stage 7 + blib content 1e-9).
- [x] Tier 2 **in-memory vs sidecar+rehydrate parity gate**
  (`Compare/archive/Compare-Stage7-Rehydration-Strict-CSharp.ps1`): proves the HPC
  4-phase chain reproduces the straight-through in-memory result. Harness updated to
  compare `.reconciled.scores.parquet` at the Stage 6 boundary, assert the Stage 4
  original survived, and feed the reconciled parquet to `--join-at-pass=2`.
- [ ] PR + Copilot + `/pw-self-review`.

## Verification

- Pre-commit: `pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1 -RunInspection -RunTests`.
- Tier 1: `Compare-EndToEnd-Crossimpl.ps1 -Dataset Astral -Files All -SkipRust` (clear
  `cs/` only). Straight-through ALONE does NOT exercise the reconciled-read path (the
  in-memory buffer flows Stage 6->7 directly).
- Tier 2 (required): `Compare/archive/Compare-Stage7-Rehydration-Strict-CSharp.ps1`
  (Phase 3 worker writes the reconciled file; Phase 4 `--join-at-pass=2` reads it).
  Harness edited to compare the reconciled filename + assert the original
  `.scores.parquet` survived byte-identical.

## Progress Log

### 2026-05-31 - Implemented + both gates green

All production edits landed (see Tasks). Pre-commit gate passed: build OK, ReSharper
inspection 0/0, 349 passed + 2 skipped (4 new path/glob tests green).

**Tier 1** (Astral 3-file straight-through cross-impl, `-SkipRust`): OVERALL PASS --
precursor delta 0 (167285=167285), Stage 7 protein FDR 1e-9 PASS, blib content 1e-9
PASS. (blib SIZE delta 565 KB is the known-normal SQLite layout difference.)

**Tier 2** (Stellar 3-file in-memory vs HPC sidecar+rehydrate,
`Compare-Stage7-Rehydration-Strict-CSharp.ps1`): OVERALL PASS at every boundary --
Stage 5 sidecars byte-identical, Stage 6 `.reconciled.scores.parquet` bit-identical
(`parquet_diff --tolerance 0` / SHA), Stage 7 dump + blib content 1e-9, and the
Stage 4 `.scores.parquet` original survived intact in both truth and worker dirs
(overwrite confirmed gone). Also fixed that archived harness's stale dependency
paths (it had not been runnable from `Compare/archive/`).
