# TODO-20260707_osprey_secondpass_percolator_gating.md

## Branch Information
- **Branch**: `Skyline/work/20260707_osprey_secondpass_percolator_gating` (not yet created — use `/pw-startissue 4389`)
- **Base**: `master`
- **Created**: 2026-07-07
- **Status**: Not Started
- **GitHub Issue**: [#4389](https://github.com/ProteoWizard/pwiz/issues/4389)
- **PR**: (pending)

## Problem

The C# Osprey port runs the **second Percolator pass only when `--protein-fdr` is set**.
In the Rust reference the second pass is gated on whether cross-run reconciliation
re-scored anything (`total_rescored > 0`) and is independent of protein FDR. When
`--protein-fdr` is not set (the common peptide-level case), C# writes the `.blib` from
**stale first-pass, pre-reconciliation q-values** — a different passing set and different
reported scores than Rust.

Found during a first-pass/second-pass Percolator cross-implementation parity review
(Rust `maccoss/osprey` @ `main` vs C# `pwiz_tools/Osprey`). Reported by Michael.

## Root cause

Type/semantics mismatch:
- Rust `config.protein_fdr` is a plain `f64`, default `0.01`, **always present** (a
  threshold) → picked-protein FDR and the second pass always run.
- C# `OspreyConfig.ProteinFdr` is a nullable `double?`, **null by default** → used as an
  on/off switch, and the second-pass Percolator got nested inside the `HasValue` guard.

## Evidence

**Rust — second pass gated on reconciliation work, not protein FDR:**
- `crates/osprey/src/pipeline.rs:5209` — `if total_rescored > 0 { … run_percolator_fdr(...) }` (straight-through)
- `pipeline.rs:4712`/`4744` — `--join-at-pass=2` path gates on `expect_reconciled_input`
- `pipeline.rs:5293` — second-pass **protein** FDR is a separate, unconditional block
  ("Always runs; threshold comes from `config.protein_fdr`")

**C# — second Percolator pass lives inside the protein-FDR guard:**
- `Osprey.Tasks/MergeNodeTask.cs:132` — `if (config.ProteinFdr.HasValue)` wraps **both**
  `Pass2FdrSidecar.ComputeAndPersist(...)` (line 139, the 2nd-pass Percolator retrain)
  and `RunProteinFdr(...)` (line 147)
- `Osprey.Tasks/Pass2FdrSidecar.cs:53-55` self-documents the coupling ("Only invoked when
  protein FDR is enabled"); lines 83-88 note the consequence ("…the blib output would use
  stale 1st-pass scores")
- Secondary instance: first-pass protein-FDR recompute gated `if (ctx.Config.ProteinFdr.HasValue …)`
  at `PerFileRescoreTask.cs:438` (Rust guard there is `!can_skip_fdr || config.expect_reconciled_input`,
  `pipeline.rs:4529`)

## Impact

- Whenever reconciliation re-scores entries and `--protein-fdr` is off: C# blib reflects
  pre-reconciliation q-values; Rust reflects reconciliation-corrected q-values.
- Code comments (Rust `pipeline.rs:4708-4711`, C# `Pass2FdrSidecar.cs:83-88`) estimate
  ~25% of precursors differ in the HPC-distributed case.
- Both straight-through and HPC C# paths route through `MergeNodeTask`, so both affected.
- Default `--fdr-level` is `Peptide`, so many real runs (no `--protein-fdr`) hit this.
- Also quietly defeats the point of retaining decoys through reconciliation — the
  reconciled decoy scores are never consumed by a recomputed q-value in the off path.

## Scope / Tasks

### Primary fix (issue #4389)
- [ ] Decouple the 2nd-pass Percolator from protein FDR in `MergeNodeTask.Run`: move
      `Pass2FdrSidecar.ComputeAndPersist` out of the `if (config.ProteinFdr.HasValue)`
      block; trigger it on the reconciliation/rescore condition (C# analog of Rust's
      `total_rescored > 0`). Leave only `RunProteinFdr` inside the protein-FDR gate.
- [ ] Reconcile the parallel gate at `PerFileRescoreTask.cs:438` (first-pass protein-FDR
      recompute) against Rust's `!can_skip_fdr || config.expect_reconciled_input`.
- [ ] Update the now-inaccurate `Pass2FdrSidecar` docstring ("Only invoked when protein
      FDR is enabled") and the `Outputs()` sidecar gate in `MergeNodeTask.cs:87` if the
      2nd-pass sidecars should now be written without `--protein-fdr`.
- [ ] Add/adjust a regression test that runs multi-file reconciliation **without**
      `--protein-fdr` and asserts the blib uses 2nd-pass (reconciliation-corrected) q-values.
- [ ] Validate cross-impl (`Compare-EndToEnd-Crossimpl.ps1`) on Stellar + Astral **with and
      without `--protein-fdr`** (the without case is what diverges today) + straight-through
      regression vs the C# golden.

### Additional parity divergences found during the review (triage — may split to own issues)
- [ ] **Gap-fill isolation-window m/z filter disabled in C#** (HIGH, GPF only) —
      `FirstJoinTask.cs:850` passes `perFileIsolationMz: null`; Rust plumbs it
      (`pipeline.rs:5045`, filter `reconciliation.rs:956-968`). Filter code exists in C#
      (`GapFillTargetIdentifier.cs:165-181`) but is never reached. No-op for standard DIA.
- [ ] **SVM training dot-product reduction order** (HIGH, determinism) — C# SIMD
      lane-partial-sums (`LinearSvmClassifier.cs:546-568`) vs Rust sequential scalar fold
      (`svm.rs:95`). Sub-ULP drift, can flip `best_C`/boundary PSMs, non-deterministic across
      CPU SIMD width. Scoring path (`decision_function`) is unaffected.
- [ ] **`reconciliation_compaction_fdr` knob absent in C#** (MEDIUM, config) — Rust
      `pipeline.rs:4650` uses a dedicated field (default 0.01); C# hardwires `config.RunFdr`
      (`FirstJoinTask.cs:597`). No `ReconciliationCompactionFdr` property exists in C#.
      Identical at defaults; diverges if the Rust knob is set ≠ run_fdr.
- [ ] **Multi-charge consensus leader tie-break** (LOW) — Rust `max_by` keeps last
      (`pipeline.rs:7644-7658`); C# keeps first (`MultiChargeConsensus.cs:118-142`). Exact
      score+q ties only.
- [ ] **Missing-feature entries** (LOW, path-dependent) — Rust skips
      (`pipeline.rs:6137-6141`); C# fabricates a placeholder vector
      (`PercolatorEntryBuilder.cs:82-85`). Only when feature-less stubs reach the builder.
- [ ] **Simple-FDR winner sort stability** (LOW, non-default path) — Rust stable sort
      vs C# unstable `List.Sort` (`FdrController.cs:187`, self-flagged). Simple FDR only.
- [ ] Latent/theoretical (safe to defer): UTF-8 vs UTF-16 peptide key ordering
      (`percolator.rs:1541` vs `PercolatorFdr.cs:2148`); `total_cmp` vs `double.CompareTo`
      on ±0/NaN.

## Confirmed NOT divergences (parity holds — from the same review)
- Target+decoy pairs retained through compaction → consensus → reconciliation by `base_id`
  on both sides (Rust `pipeline.rs:4680-4683`; C# `FirstJoinTask.cs:616`,
  `RescoreCompaction.cs:198`). Decoys get independent consensus RTs and are re-scored;
  the one deliberate decoy exclusion (both sides) is the calibration refit (targets only).
- Core TDC granularity (per `base_id`), conservative `(decoys+1)/targets` q-values with
  backward-running-min monotonization, four q-value levels, fold assignment, subsampling
  (xorshift64 + Fisher-Yates), dual-CD SVM, positive-set selection, grid search, Granholm
  calibration — all faithful ports (agents confirmed ~16 mechanisms matching).

## Doc-vs-code notes (both impls agree with each other; `docs/07-fdr-control.md` is stale)
- Initial feature selection is ascending-only (doc claims both directions).
- Grid search for C runs every iteration (doc claims first iteration only).
- `reconciliation_compaction_fdr` default: doc 07 says 0.05, code (`config.rs`) says 0.01.

## Progress Log
- 2026-07-07: Cross-impl parity review of first/second-pass Percolator (4 parallel agents
  + direct verification of the orchestration in `pipeline.rs` and C# Tasks). Root-caused the
  second-pass gating bug (C# side), catalogued the additional divergences above, confirmed
  decoy retention parity through compaction/consensus/reconciliation. Filed issue #4389,
  created this TODO. Branch not yet created — work not started.
