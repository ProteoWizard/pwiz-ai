# TODO-20260707_osprey_secondpass_percolator_gating.md

## Branch Information
- **Branch**: `Skyline/work/20260707_osprey_secondpass_percolator_gating`
- **Base**: `master`
- **Created**: 2026-07-07
- **Status**: In Progress
- **GitHub Issue**: [#4389](https://github.com/ProteoWizard/pwiz/issues/4389)
- **PR**: (pending)

## Design decision (from Michael): FULL PARITY for #1

In Rust there is no "protein-FDR off" state — `config.protein_fdr` is a plain `f64`
(default 0.01) and the protein machinery runs unconditionally: first-pass protein FDR
(→ compaction + consensus protein-rescue), second Percolator pass, second-pass protein
FDR, and the `proteins.csv` report all run every time. `--protein-fdr` only *sets the
threshold* and gates protein-level output filtering.

C# must match this: the protein-FDR machinery + second Percolator pass always run at
default 0.01; `--protein-fdr` becomes threshold + `--fdr-level protein` output only.
A default C# run will now always compute protein FDR and write `proteins.csv`.

### C# gates to flip (all currently keyed on `config.ProteinFdr.HasValue`)
1. `FirstJoinTask.cs:235` — first-pass protein FDR → run always (Rust guard is
   `!can_skip_fdr`, not protein_fdr; pipeline.rs:4529).
2. `FirstJoinTask.cs:598` — compaction `proteinGate = ProteinFdr ?? 0.0` → `?? 0.01`,
   rescue always active (Rust pipeline.rs:4651/4658).
3. `MergeNodeTask.cs:132` — split: second Percolator pass (`Pass2FdrSidecar.ComputeAndPersist`)
   runs when reconciliation rescored (analog of Rust `total_rescored > 0`, pipeline.rs:5209 —
   detect via "any `<stem>.scores-reconciled.parquet` exists"); protein FDR + `proteins.csv`
   run always (Rust pipeline.rs:5293).
4. `PerFileRescoreTask.cs:438` — first-pass protein-FDR recompute in the rehydration path →
   run always.
5. `ConsensusRts.cs` consensus protein-rescue — use default 0.01 threshold, always active.
6. `MergeNodeTask.cs:87` `Outputs()` — declare 2nd-pass sidecars when rescored, not on protein_fdr.
7. Introduce an effective-threshold accessor on `OspreyConfig` (e.g. `ProteinFdr ?? 0.01`)
   and a default constant; `--fdr-level protein` no longer needs `--protein-fdr`.

### Validation plan for #1 (does NOT require Rust)
- Self-consistency: C# Stellar 3-file **without** `--protein-fdr` blib == **with** `--protein-fdr 0.01`
  blib (machinery now always runs at 0.01). This is the direct proof of the fix.
- `regression.ps1 -Dataset Stellar` (uses `--protein-fdr 0.01`) stays green — the with-protein-fdr
  path is unchanged. Regenerate golden only if an intended delta appears.
- Cross-impl confirmation once the Windows Rust reference builds (below).

## Environment setup (this machine, for Windows cross-impl parity)
- Rust: no toolchain was installed. Installed rustup stable MSVC (cargo/rustc 1.96.1).
- Rust osprey needs OpenBLAS on Windows (`openblas-src` "system" via vcpkg). Installing vcpkg
  at `~/vcpkg` + `openblas:x64-windows` (the wrapper sets `VCPKG_ROOT=$USERPROFILE\vcpkg`).
  Michael normally builds Rust under WSL2; for this parity work we build the **Windows** Rust
  binary to compare against Windows C#.
- Build wrappers: C# `Build-Osprey.ps1 -Configuration Release -TargetFramework net8.0`;
  Rust `Compare/Build-OspreyRust.ps1 -OspreyRoot C:\Users\macco\Documents\github\maccoss\osprey`.
  Note: `cargo`/`pwsh` must have `~/.cargo/bin` on PATH (Git Bash→pwsh does not by default).
- GPF dataset for divergence #2 (gap-fill isolation m/z): `Y:\osprey-test-data\stellar\calibrated-GPF-data`
  (5 disjoint-m/z windows 400–500 … 800–900).

## Rust doc fixes (DONE — stale notes, in the maccoss/osprey repo)
Fixed `docs/07-fdr-control.md` to match the code: initial feature selection is ascending-only;
grid search runs every iteration; `reconciliation_compaction_fdr` default is 0.01. Needs a
Rust-side commit/PR (LF, upstream conventions) — separate from the pwiz branch.

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
- [ ] **#2 Gap-fill isolation-window m/z filter disabled in C#** (HIGH, GPF). DECISION (Michael):
      **fix BOTH C# and Rust** so distributed GPF filters and parity holds. Key finding: Rust
      only filters straight-through — its join/HPC path never rebuilds isolation intervals
      (serializes `isolation_scheme.windows` to calibration.json but never reads them back), so
      the filter is a no-op on the distributed path on BOTH sides today.
      C# filter already implemented (`GapFillTargetIdentifier.cs:165-181`); only the feed is null
      (`FirstJoinTask.cs:850`). C# already extracts windows (`ScoringTaskShared.ExtractIsolationWindows`,
      `PerFileScoringTask.cs:1232`; `IsolationWindow` = Center/LowerOffset/UpperOffset).
      Target shape: `IReadOnlyDictionary<string,IReadOnlyList<(double Lo,double Hi)>>` keyed by file
      stem; interval = `(Center - Width/2, Center + Width/2)` (matches Rust `pipeline.rs:4248-4255`).
      Plan:
      - C# straight-through: add `PerFileIsolationMz` byproduct (`PipelineByproducts.cs`), populate in
        `PerFileScoringTask.ProcessFile` next to `perFileCalibrationsOut` (~:1232/:1266), publish in
        `FinalizeAndCheck` (~:519), consume in `FirstJoinTask.Run` (~:204) → thread through
        `PlanStage6→WriteReconciliationFiles→BuildReconciliation` to replace `perFileIsolationMz: null`.
      - C# HPC/merge: add `windows` (double[][]) to `IsolationSchemeJson` (`CalibrationParams.cs:133-154`,
        currently missing), populate `Metadata.IsolationScheme` when writing calibration.json
        (`PerFileScoringTask.cs:1493-1518` — pass `isolationWindows` into `ResolveCalibration`), read
        back in `LoadJoinOnlyScores` (~:905-935) to fill the byproduct.
      - Rust: on the join path (`pipeline.rs:3874+`), read `metadata.isolation_scheme.windows` from
        calibration.json and populate `per_file_isolation_mz` (Rust serializes it at
        `calibration/mod.rs:129-143` but never reads it back).
      - Validate on GPF (`Y:\osprey-test-data\stellar\calibrated-GPF-data`): straight-through AND
        HPC chain, C# vs Rust cross-impl (`Compare-Blib`/`Compare-EndToEnd`); expect gap-fill target
        set to shrink (precursors outside a file's m/z windows no longer force-integrated).

### Remaining-work priority (Michael: ALL of these must be done; determinism first)
All divergences below are tracked here and in issue #4389 (Tier 1/2/3). Work order after #2:
1. **#3 / "#C" SVM training dot-product reduction order — DETERMINISM-CRITICAL, do next.**
   C# hand-vectorized SIMD lane-partial-sums (`LinearSvmClassifier.cs:546-568`) vs Rust sequential
   scalar fold (`svm.rs:95`). Not just sub-ULP drift vs Rust — the C# result is **non-deterministic
   across CPU SIMD width** (AVX2 vs AVX-512 vs NEON give different sums), so the same input can flip
   `best_C` and shift boundary PSMs run-to-run/machine-to-machine. Rust is identical on every platform.
   Scoring path (`decision_function`) is scalar on both sides and matches. Fix: make C# training use a
   deterministic sequential (or fixed-order) reduction. **Filed as its own issue: #4392.**
2. **#4 reconciliation_compaction_fdr knob absent in C#** (MEDIUM) — add the config field; C#
   hardwires `RunFdr` (`FirstJoinTask.cs:597`) vs Rust `config.reconciliation_compaction_fdr`
   (`pipeline.rs:4650`). Inert at default 0.01; diverges when set.
3. **#5 multi-charge consensus leader tie-break** (LOW, determinism-adjacent) — Rust `max_by` keeps
   last (`pipeline.rs:7644-7658`); C# keeps first (`MultiChargeConsensus.cs:118-142`). Exact ties only.
4. **#6 missing-feature entries** (LOW, path-dependent) — Rust skips (`pipeline.rs:6137-6141`); C#
   fabricates a placeholder vector (`PercolatorEntryBuilder.cs:82-85`). Bites only when nWithoutFeatures>0.
5. **#7 Simple-FDR winner sort stability** (LOW, non-default path, DETERMINISM) — Rust stable
   (`lib.rs:148`) vs C# unstable `List.Sort` (`FdrController.cs:187`, self-flagged). Simple FDR only.
6. **Tier 3 (latent, defer):** UTF-8 vs UTF-16 peptide-group key sort (`percolator.rs:1541` vs
   `PercolatorFdr.cs:2148`); `f64::total_cmp` vs `double.CompareTo` on +/-0.0/NaN. Unreachable today
   but both feed ordering — worth a shared comparator eventually.
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
  created this TODO.
- 2026-07-07: Started the branch. Fixed the Rust stale docs (07-fdr-control.md). Set up the
  Windows Rust cross-impl toolchain (rustup MSVC; vcpkg + openblas:x64-windows building).
  Locked the FULL-PARITY design for #1 with Michael (see above) and the no-Rust-needed
  self-consistency validation. Next: implement the 7 gate changes for #1, then build + validate.
- 2026-07-07: **#1 DONE + committed** (pwiz `251ece004`). Implemented all 7 gate changes via
  `OspreyConfig.EffectiveProteinFdr` (ProteinFdr ?? 0.01). Validation:
  * `regression.ps1 -Dataset Stellar` PASS all 3 modes (straight/HPC/resume), with --protein-fdr.
  * Stellar 3-file WITHOUT --protein-fdr == WITH 0.01: `Compare-Blib` OVERALL PASS at 1e-9.
  * Single-file C# == Rust: `Compare-Blib` OVERALL PASS at 1e-9 (both run intra-run multi-charge
    consensus -> 2nd pass; blib size differs only by SQLite page layout). Confirmed Michael's rule:
    the ONLY no-2nd-pass case is a single file with nothing to reconcile -- but intra-run
    multi-charge consensus still rescores within one run, so single-file DOES run a 2nd pass.
  * Pre-commit gate: 453 unit tests pass, inspection clean.
  * Rust doc fix pushed to maccoss/osprey main (`fe52573`).
- 2026-07-07: GPF multi-charge behavior (Rust, for #2): cross-run consensus RT is peptide-level
  (`compute_consensus_rts` groups by modified_sequence, charge-agnostic across files) so a
  peptide's charges in different GPF runs share one library-RT consensus; gap-fill is m/z-gated
  (`reconciliation.rs:956-968`) so a charge is only force-filled into runs whose isolation windows
  cover its m/z. C# matches on consensus RT but disables the gap-fill m/z filter
  (`FirstJoinTask.cs:850` perFileIsolationMz: null) = divergence #2. GPF data: Y:\...\calibrated-GPF-data.
  Next: #2 -- plumb per-file isolation-window m/z through C# and enable the filter.
