# TODO: Stage 6 writes a separate reconciled parquet (stop overwriting Stage 4)

**Status**: Completed
**Branch**: `Skyline/work/20260531_ospreysharp_stage6_reconciled_parquet` (pwiz)
**PR**: [#4261](https://github.com/ProteoWizard/pwiz/pull/4261) (merged 2026-05-31 as e7e989cc7d)
**Created**: 2026-05-31
**Scope**: `C:\proj\pwiz\pwiz_tools\OspreySharp` (C#-only; Rust `osprey` untouched)

## Objective

Stage 6 (`PerFileRescoreTask`) must stop **destructively overwriting** the Stage 4
(`PerFileScoringTask`) per-file `<stem>.scores.parquet`. It now writes a separate
`<stem>.scores-reconciled.parquet` sibling, leaving the Stage 4 output intact. Stage 7
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
- Concrete design (separate `.scores-reconciled.parquet`, update `--join-at-pass=2`
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
  compare `.scores-reconciled.parquet` at the Stage 6 boundary, assert the Stage 4
  original survived, and feed the reconciled parquet to `--join-at-pass=2`.
- [x] PR #4261 + Copilot (4 comments, resolved) + `/pw-self-review` (3 minor findings,
  doc items addressed). Ready for human merge (not merged).

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
Stage 5 sidecars byte-identical, Stage 6 `.scores-reconciled.parquet` bit-identical
(`parquet_diff --tolerance 0` / SHA), Stage 7 dump + blib content 1e-9, and the
Stage 4 `.scores.parquet` original survived intact in both truth and worker dirs
(overwrite confirmed gone). Also fixed that archived harness's stale dependency
paths (it had not been runnable from `Compare/archive/`).

### 2026-05-31 - PR #4261 opened; Copilot round addressed (commit 0a3878825c)

PR #4261 opened (foundation commit ed94f19304); ai TODO + harness pushed to pwiz-ai
master (72938e4). Copilot raised 4 comments; all addressed in a follow-up commit:

- **Naming refined** from `<stem>.reconciled.scores.parquet` to
  `<stem>.scores-reconciled.parquet` (#1-3, one root cause). The marker now follows
  the controlled `.scores` token, so a Stage 4 path -- which always ends exactly
  `.scores.parquet` -- can never be misread as a reconciled output, even for an input
  stem ending in `.reconciled`. Removes the suffix ambiguity with no metadata read.
  Added regression test `TestReconciledNamingUnambiguousForReconciledStem`.
- **Write-back safety** (#4): `WriteReconciledParquet` returns success; the validity
  sidecar is written only on a successful write, and a stale reconciled parquet +
  sidecar are cleared on failure (no false-valid output for Stage 7 / resume).

Re-verified after the change: pre-commit gate (352 tests, inspection 0/0), Tier 2
rehydrate parity (Stellar, bit-identical at every boundary with the new filename),
Tier 1 straight-through cross-impl (Astral, 1e-9 PASS). All 4 Copilot threads resolved.
Fresh-context `/pw-self-review` launched on head 0a3878825c.

### 2026-05-31 - Self-review addressed (commit 0af02ae180); review chain complete

`/pw-self-review` traced every pipeline mode against the new read contract and found
the design sound. 3 minor findings:
- (Low) stale overwrite-describing doc comment in `OspreyTask.cs` -- fixed.
- (Medium, efficiency) `PerFileRescoreTask.Outputs()` over-declares reconciled paths
  for no-work files, so the driver's coarse task-level resume skip is inert when any
  no-work file is present (the within-task per-file skip preserves correctness) --
  documented inline; not filtered (the work-file set isn't known until the planner runs).
- (Low) explicit-file `--input-scores` can pass both an original and its reconciled
  sibling for one stem -- left as-is; `--join-at-pass=2`'s strict reconciled-input gate
  rejects the original (clear abort), so no silent corruption.
The no-work-file-in-pass=2 strict-gate rejection the reviewer asked about is
PRE-EXISTING (no-work files were `reconciled=false` before this PR too); Tier 2's 3
Stellar files all had Stage 6 work. PR #4261 head: 0af02ae180.

### 2026-05-31 - Merged

PR #4261 squash-merged to master as commit e7e989cc7d. Shipped the full
reconciled-parquet split: Stage 6 writes `<stem>.scores-reconciled.parquet` (no
longer overwriting Stage 4's `.scores.parquet`); Stage 7 + resume read the effective
(reconciled-else-original) path; `--input-scores` dir mode dedupes per stem; the
`.scores-reconciled` marker keeps original-vs-reconciled unambiguous; and the
write-back reports success so no stale output is marked valid. C#-only; bit-identical
on straight-through (Astral 1e-9) and in-memory-vs-HPC-rehydrate (Stellar) gates.
Merged with `--admin` over an unrelated intermittent `teamcity - Bumbershoot Linux
x86_64` failure (Bumbershoot is C++; this PR touches only OspreySharp). Deferred (per
user, until true HPC testing): the pre-existing no-work-file `--join-at-pass=2`
strict-gate rejection. The intermediate-artifact cleanup CLI flag remains a future
follow-up.
