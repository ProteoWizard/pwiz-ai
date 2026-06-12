# TODO-20260423_osprey_sharp_stage6.md — Phase 4 Stage 6: refinement parity

> Sub-sprint of **TODO-20260423_osprey_sharp.md** (Phase 4
> umbrella, Stages 6-8). The umbrella is the authoritative plan;
> this file tracks the Stage 6 branch, progress log, and PR links.

## Branch Information

- **pwiz**: `Skyline/work/20260423_osprey_sharp_stage6` -> merged to master via #4169 on 2026-04-28.
- **osprey**: PR #19 (`feature/stage6-planning-diagnostics-dumps`) merged to main on 2026-04-28. PR #21 (`feature/stage6-fixes`) merged to main on 2026-04-28. PR #22 (`feature/stage6-copilot-followups`) opened 2026-04-28 with the post-merge Copilot review fixes.
- **Base**: `master` (pwiz) / `main` (maccoss/osprey)
- **Created**: 2026-04-23
- **Status**: COMPLETE — all PRs merged or queued for merge. Cross-run reconciliation byte-identical with Rust on Stellar + Astral 3-file. Continuation of Stage 6 work tracked in `TODO-20260428_osprey_sharp_stage6.md` (Second-pass re-score box + close-out items).
- **GitHub Issue**: (none — tool work, no Skyline integration yet)

### PR list (final)

- ProteoWizard/pwiz #4169 — merged 2026-04-28. Cross-run reconciliation byte parity with Rust. Three Copilot review items deferred to next pwiz PR (see continuation TODO).
- maccoss/osprey #19 — merged 2026-04-28. Diagnostic dumps for Stage 6 cross-impl bisection (`OSPREY_DUMP_PROTEIN_FDR`, `_LOESS_FIT`, plus inv_predict tiebreak).
- maccoss/osprey #21 — merged 2026-04-28. Three production fixes: f64::from_str parser, reconciliation_enabled gate, refit env-var honor.
- maccoss/osprey #22 — opened 2026-04-28. Post-merge Copilot follow-ups (comment fix + DRY type alias + borderline-f64 regression test).

Closed (superseded during PR restructure):

- pwiz #4167 / #4168 — split diagnostics-vs-fixes; consolidated into #4169.
- maccoss/osprey #20 — split-but-bundled fixes; replaced by #21 with a clean diagnostics-vs-fixes line.

## Scope

Covers Priorities 1-3 of the umbrella TODO:

1. **Upstream resync delta catalog**: scan `maccoss/osprey:main`
   for commits since the last review (2026-04-21 session caught
   up to `885339b`). Disposition each as parity-critical port /
   Stages 1-5 drift / out-of-scope. Dump to
   `ai/.tmp/stage6_upstream_delta.md`.
2. **Multi-file Stage 5 validation**: extend the single-file
   Stellar Stage 5 parity (already bit-identical at 462,802 rows /
   34,158 precursors / 30,712 peptides / 5,471 protein groups) to
   3-file Stellar + Astral. Exercises best-per-precursor
   subsampling across files + experiment-level FDR compaction,
   neither of which single-file touches.
3. **Stage 6 refinement parity**: multi-charge consensus leader
   pick + cross-run RT reconciliation + gap-fill + second-pass
   re-score at locked boundaries + re-trained Percolator SVM.
   Add the three new diagnostic dumps per the umbrella
   (`OSPREY_DUMP_CONSENSUS` / `OSPREY_DUMP_RECONCILIATION` /
   `OSPREY_DUMP_REFINED_FDR`, each with matching `_ONLY`
   early-exit), mirroring the Stage 5 four-dump pattern that
   shipped in PR #18 / pwiz #4160.

## Gate for PR

Bit-identical cross-impl parity on Stellar + Astral, single-file
and 3-file, through end-of-Stage-6. `Compare-Percolator.ps1`
extended (or a sibling harness script added) for consensus +
reconciliation dump comparisons. Stages 1-5 parity gates
(`Test-Features.ps1` 21/21 @ 1e-6 + end-of-Stage-5 Percolator
dump byte-identical) must still hold.

## Implementation plan (locked 2026-04-23 session 2)

### Answers to the three open design questions

1. **Parquet write-back (Q1 of plan):** YES. The C# port already has
   per-file Parquet score caching working end-of-Phase-4 (Stage 5)
   — Stage 6 follows the same cache model: reload full scored
   entries, re-score subset at locked boundaries, write back with
   reconciled metadata. Compression: OspreySharp only reads/writes
   Snappy; Rust defaults to ZSTD but supports Snappy via
   `--parquet-compression snappy`. Cross-impl parity runs must pass
   `--parquet-compression snappy` to both tools until ZSTD lands in
   OspreySharp.
   - **Prerequisite**: verify Rust's reconciliation write-back read
     path handles Snappy on the round-trip (ZSTD is the Rust default
     everywhere, so a Rust-side code patch may be needed if any read
     path assumes ZSTD). Catch it early with a single-file Rust
     `--no-join --parquet-compression snappy` → `--join-only --reconcile`
     smoke test before doing the C# port.
2. **C# `run_search` entry point (Q2 of plan):** located during
   the boundary-overrides commit (step 5 below). Expected to live
   in `OspreySharp.Scoring`.
3. **Gap-fill (Q3 of plan):** IN SCOPE. Byte parity with Rust +
   full parallelism are the goals, and Rust gap-fill is intrinsic
   to Stage 6 (consensus RTs imply which precursors should have
   been found in every file; gap-fill tries CWT first, then forced
   integration). Skipping gap-fill would break byte parity.

### Parallelism stance

Match Rust's within-file parallelism (per-window XIC + scoring).
Go further at file level: Rust forces sequential per-file re-scoring
because its spectra + Parquet reload runs ~3 GB per file; OspreySharp
has historically file-parallelized all of Stages 1-4 (0.59x Rust on
Stellar 3-file) and should continue doing so for Stage 6 — the
consensus + reconciliation plan is global, but the per-file
re-scoring + Parquet write-back is independent. Byte-parity is
preserved because re-scoring within a file is deterministic and
write-back is keyed by `parquet_index` per file.

### Recent Rust design points to mirror

Captured from `C:\proj\osprey\CLAUDE.md` "Recent Changes":

1. **Consensus weighting** = `sigmoid(SVM score)`, NOT
   `coelution_sum`. A wrong-peak negative-score detection gets
   weight ~0.02 and cannot poison the weighted median.
2. **Consensus qualification** = hard
   `run_precursor_qvalue <= consensus_fdr`. Protein-FDR rescue can
   only upgrade borderline peptide-level evidence.
3. **Reconciliation RT tolerance** = global median of per-peptide
   apex MADs in library RT space. Falls back to 0.05 min if fewer
   than 3 detections per peptide. Capped by per-file calibration MAD.
4. **Multi-charge consensus + cross-run reconciliation merged** into
   one per-file re-scoring pass. Dedup by entry index; reconciliation
   wins on conflict.
5. **`consensus_fdr` default = 0.01** (was 0.05). C# config already
   matches.
6. **Determine action by apex proximity**, not boundary containment.
   A wide-tailed wrong-apex peak is NOT "Keep".
7. **Gap-fill two-pass**: CWT first (pre-filter off), then forced
   integration for whatever CWT missed.

### Commit layering (Stage 5 precedent: one logical change per commit)

Every commit leaves the Stage 5 parity harness green
(`Compare-Stage5-AllFiles.ps1 -Dataset {Stellar,Astral}` = 6/6
byte-identical). Stage 6 work is gated by
`config.InputFiles.Count > 1 && ReconciliationConfig.Enabled`, so
single-file runs stay on the Stage 5 path for all pre-integration
commits.

0. **Rust-side prerequisite (if needed)**: add/verify Snappy support
   on reconciliation Parquet write-back read path. osprey PR if
   necessary. Skip if single-file `--no-join --parquet-compression snappy`
   round-trip already works end-to-end.
1. **`PeptideConsensusRT` + `ComputeConsensusRts`.** New class in a
   new `OspreySharp.Reconciliation` project (or
   `OspreySharp.FDR\Reconciliation\`). Fields: ModifiedSequence,
   IsDecoy, ConsensusLibraryRt, MedianPeakWidth, NRunsDetected,
   ApexLibraryRtMad. Unit tests: fixture with 3-file target + decoy
   inputs, verify weighted-median RT + sigmoid weighting match
   hand-computed values; low-score detections down-weighted; hard
   precursor-q gate rejects poor-evidence entries.
2. **`ReconcileAction` + `DetermineReconcileAction` +
   `PlanReconciliation`.** `ReconcileAction` as a sealed abstract
   class hierarchy (`Keep` / `UseCwtPeak` / `ForcedIntegration`) —
   C#-idiomatic and matches the Rust enum with per-case data.
   Unit tests: "apex within tolerance → Keep", "wide-tail wrong-apex
   → UseCwtPeak picking closest-apex candidate", "no candidate in
   tolerance → ForcedIntegration", "empty CWT → all
   ForcedIntegration".
3. **`RefitCalibrationWithConsensus`.** Per-file LOESS refit using
   consensus peptides as anchor points. R² floor + fallback to
   pass-1 calibration. Unit tests: 2-file fixture, refit passes,
   refit fails → fallback.
4. **`SelectPostFdrConsensus` (multi-charge consensus picker).**
   Groups by `modified_sequence`; for peptides with >1 charge
   state where at least one passes FDR, highest-SVM-score charge
   state defines the consensus peak. Unit tests: 3-charge peptide
   where z=2 passes and z=3 has wrong peak → z=3 rescore target;
   single-charge → no target; no-passing peptide → no target.
5. **`boundaryOverrides` on C# search engine.** Locate the
   `run_search` equivalent (expected `OspreySharp.Scoring`), add
   `boundaryOverrides: IReadOnlyDictionary<uint, (double Apex, double Start, double End)>?`
   parameter; when present, skip CWT peak detection + pre-filter
   and score at fixed boundaries. Mirror the five Rust
   boundary-override tests at `pipeline.rs:8236-8700` (entry at
   specified boundaries, override skips prefilter, mixed
   override+CWT, no override uses CWT, narrow-boundary edge case).
6. **`IdentifyGapFillTargets` + `GapFillTarget`.** Run-level-passing
   precursors missing from each file. Unit tests: 3-file fixture
   where a target passes in file 1 and 2 but is absent from file 3
   → one gap-fill target for file 3.
7. **Wire Stage 6 into `AnalysisPipeline.cs`.** Replace the
   `Stage 6-7: Reconciliation (TODO for multi-file)` stub at
   line 404. Per-file re-scoring happens in parallel (C# goes
   beyond Rust's sequential per-file loop).
   Diagnostic dumps (mirror Stage 5):
   - `OSPREY_DUMP_CONSENSUS` → per-peptide consensus dump;
     `OSPREY_CONSENSUS_ONLY=1` early-exit.
   - `OSPREY_DUMP_RECONCILIATION` → per-(file, entry) action dump;
     `OSPREY_RECONCILIATION_ONLY=1` early-exit.
   - `OSPREY_DUMP_REFINED_FDR` → end-of-Stage-6 Percolator dump
     (same six-column schema as Stage 5); `OSPREY_REFINED_FDR_ONLY=1`
     early-exit.
   All numeric columns emit via
   `pwiz.OspreySharp.Core.Diagnostics.FormatF64Roundtrip` (handoff
   gotcha #1). Second-pass Percolator reuses existing `PercolatorFdr`,
   restricted to first-pass passing base IDs. PEP fit input order
   must be base-id-ascending (handoff gotcha #2).
8. **Cross-impl harness: `Compare-Stage6-AllFiles.ps1`.** Sibling to
   `Compare-Stage5-AllFiles.ps1`. Runs both tools with each of the
   three dump env-vars + `_ONLY`, byte-compares outputs across all 3
   files. Gate: 3/3 byte-identical on Stellar + Astral for all three
   dumps.

### Expected PR sequence

- **PR 1**: commits 1+2+3 (pure reconciliation types + logic, no
  pipeline changes, unit tests only).
- **PR 2**: commits 4+5 (multi-charge consensus + search-engine
  `boundaryOverrides`, unit tests only, not yet wired).
- **PR 3**: commit 6 (gap-fill identification + tests).
- **PR 4**: commits 7+8 (pipeline integration, three diagnostic
  dumps, and harness script). This is the parity-gate PR.

Each PR body: past-tense title, `* ` bullets, ≤10 lines,
`See ai/todos/active/TODO-20260423_osprey_sharp_stage6.md`,
`Co-Authored-By: Claude <noreply@anthropic.com>`.

Pre-commit for every OspreySharp commit:
`Build-OspreySharp.ps1 -RunInspection -RunTests` (~30s), then
`Compare-Stage5-AllFiles.ps1 -Dataset {Stellar,Astral}` = 6/6.

### Files expected to change

**New**:

- `OspreySharp.FDR\Reconciliation\PeptideConsensusRT.cs`
- `OspreySharp.FDR\Reconciliation\ConsensusRts.cs`
- `OspreySharp.FDR\Reconciliation\ReconcileAction.cs`
- `OspreySharp.FDR\Reconciliation\ReconciliationPlanner.cs`
- `OspreySharp.FDR\Reconciliation\CalibrationRefit.cs`
- `OspreySharp.FDR\Reconciliation\MultiChargeConsensus.cs`
- `OspreySharp.FDR\Reconciliation\GapFillTarget.cs`
- `OspreySharp.Test\ReconciliationTest.cs`
- `ai\scripts\OspreySharp\Compare-Stage6-AllFiles.ps1`

**Modified**:

- `OspreySharp\AnalysisPipeline.cs` — replace Stage 6 TODO stub
  at line 404.
- `OspreySharp\OspreyDiagnostics.cs` — three new dump methods +
  flags + `_ONLY` early-exit flags.
- `OspreySharp.Core\ReconciliationConfig.cs` — add tolerance-cap
  floor + whatever other knobs Rust `ReconciliationConfig` has that
  C# doesn't yet.
- `OspreySharp.Scoring\...` — add `boundaryOverrides` to
  search-engine entry point (exact file TBD during step 5).
- `Osprey-workflow.html` — flip Stage 6 boxes from `.st-missing` to
  `.st-done` as each substage lands; retire the "you are here"
  marker when Stage 6 is complete.

## See also

- `ai/todos/active/TODO-20260423_osprey_sharp.md` — Phase 4
  umbrella plan (Stages 6-8 in detail).
- `ai/todos/completed/TODO-20260422_ospreysharp_stage5_diagnostics.md`
  — Stage 5 precedent: one-commit-per-logical-change, bisection-
  to-ULP discipline, four-dump diagnostic harness +
  `Compare-Percolator.ps1`.
- `ai/docs/osprey-development-guide.md` — HPC flags, env-var
  reference, bisection methodology, determinism patterns,
  steel-thread parity doctrine.
- `C:\proj\osprey\CLAUDE.md` — Rust-side project overview and
  critical invariants.

## Progress log

### Session 6 (2026-04-27) — Cross-run reconciliation closed; ready for PR split

Closed both gaps from the prior session's handoff. Cross-run reconciliation
is now byte-identical with Rust on Stellar 3-file (8/8 dumps) and Astral
3-file (7/8 — protein_fdr / consensus / inv_predict / multicharge /
calibration / loess_fit / refit all PASS; only `stage5_percolator` shows
a 1-ULP gap on losing entries' `experiment_precursor_q` in file 49, see
known-issues below). Stage 5 single-file parity gate
(`Compare-Stage5-AllFiles.ps1`) re-verified GREEN on both datasets
(Stellar 3/3 × 4 dumps, Astral 3/3 × 4 dumps).

**Step 1 (consensus + inv_predict closure) — picked-protein FDR port:**

The C# `ComputeProteinFdr` was implementing **DIA-NN-style composite
scoring** (sum of per-peptide log-likelihoods + max best-peptide quality,
two parallel q-value sweeps, take min) -- the v26.1.2 algorithm that the
Rust `CLAUDE.md` "Critical Invariants" section explicitly forbids:
*"Do NOT revert to single-pass or composite scoring."* The diff between
the new `OSPREY_DUMP_PROTEIN_FDR` dumps showed 23,149 of ~171,000
peptide rows differing -- pervasive, not a tie-break. Replaced
`ComputeProteinFdr` body with the picked-protein algorithm (~100 lines
in/out), keeping `BuildProteinParsimony` / `CollectBestPeptideScores` /
`PropagateProteinQvalues` untouched. Also dropped the unused
`ComputeProteinQvaluesDiann` + `BinarySearchLeft` helpers, removed the
`GroupPep` field from `ProteinFdrResult` (Rust intentionally doesn't
compute protein PEP), and the `using pwiz.OspreySharp.ML` (no longer
needed). Closed `consensus` PASS + drove `protein_fdr` from 23K rows
divergent to byte-identical.

Also fixed `CollectBestPeptideScores` to read `RunPeptideQvalue` for
the gate field, not `RunPrecursorQvalue` (Rust's `collect_best_peptide_scores`
explicitly says "uses peptide_qvalue, not precursor q-value, because
picked-protein gates on peptide-level FDR per Savitski 2015"). The C#
side had been doc'd as precursor-q.

`inv_predict` was data-equivalent (same SHA256 when sorted) but FAILed
strict byte-parity due to **sort instability** on rows where the same
peptide had multiple charge-state detections in one file (tied on the
`(is_decoy, modseq, file_name)` sort key). Added apex_rt + library_rt
tiebreaks to the sort on both sides so the order is deterministic
regardless of `List<T>.Sort` (unstable in .NET) vs
`Vec::sort_by` (stable in Rust) AND the input-order divergence between
HashMap and Dictionary iteration.

**Step 2 (refit closure) — LOESS divergences:**

Built `OSPREY_DUMP_LOESS_FIT` on both sides (per-point library_rt +
fitted_value + abs_residual triples from each refit RTCalibration).
Diff showed ALL 130,785 rows differing at ~0.0002 magnitude (4-5
decimal places off, NOT ULP) — the smoother itself diverging, not the
stats computation.

**Root cause #1: `classical_robust_iterations` had opposite defaults.**
Rust `RTCalibratorConfig::default()` sets it `false`; C#
`RTCalibratorConfig` constructor sets it `true`. Stage 4 (initial
calibration) reads `OSPREY_LOESS_CLASSICAL_ROBUST` (default = on) on
both sides explicitly, so Stage 4 has byte parity. Stage 6 refit on
both sides used `RTCalibrator::new()` / `new RTCalibrator(new
RTCalibratorConfig{...})` without setting the flag → got Rust default
false vs C# default true → different LOESS algorithm. Aligned both
sides to read the env-var the same way Stage 4 does. After this fix,
divergence dropped from ~0.0002 to 1-2 ULP.

**Root cause #2: bisquare weight `Math.Pow` vs `powi`.**
C# `LoessRegression.Fit` computed bisquare via `Math.Pow(1.0 - u*u, 2)`.
.NET's `Math.Pow(x, 2)` routes through `exp(2*log(x))` and famously
diverges from `x*x` at the last ULP. Rust's `(1.0 - u*u).powi(2)` is
just `x*x`. Replaced with `t*t`. After this fix, refit + loess_fit are
both byte-identical.

**OspreyEnvironment migration to OspreySharp.Core:**

`OspreyEnvironment` (the env-var wrapper) lived in the main `OspreySharp`
project but the `CalibrationRefit` fix needed to read
`LoessClassicalRobust` from `OspreySharp.FDR`, which can't reference the
main project (would create a cycle). Moved `OspreyEnvironment.cs` from
`OspreySharp/` to `OspreySharp.Core/` (project at the bottom of the
dependency graph). Added a section to
`ai/docs/osprey-development-guide.md` codifying the rule: *"When a
class defined in one OspreySharp component is needed by another, push
it down to OspreySharp.Core."*

**Harness speedup:**

`Compare-Stage6-Planning.ps1` now supports `-Dump <list>` (run only the
specified dumps instead of all 8) and `-Clean` (force re-stage), and uses
a shared per-dataset workdir so Rust's `.1st-pass.fdr_scores.bin`
sidecars persist between dump invocations (skipping Percolator SVM
training on subsequent runs). Iteration speed: full 8-dump Stellar run
~23 min; single-dump iteration ~5-7 min including reuse.

**Files changed (uncommitted at end of session):**

pwiz worktree:
- `OspreySharp.FDR/ProteinFdr.cs` -- picked-protein algorithm port,
  drop GroupPep / ComputeProteinQvaluesDiann / BinarySearchLeft / EPSILON,
  drop `using pwiz.OspreySharp.ML`, peptide-q gate fix in
  `CollectBestPeptideScores`, `ProteinWinner` private struct
- `OspreySharp.FDR/Reconciliation/CalibrationRefit.cs` --
  `ClassicalRobustIterations = OspreyEnvironment.LoessClassicalRobust`
- `OspreySharp.FDR/Reconciliation/ConsensusRts.cs` -- inspection cleanup
  (XML doc for `invPredictTrace` parameter)
- `OspreySharp.Chromatography/LoessRegression.cs` --
  `Math.Pow(t,2)` -> `t*t` in bisquare weight
- `OspreySharp.Core/OspreyEnvironment.cs` -- new file (moved from main project)
- `OspreySharp/OspreyEnvironment.cs` -- DELETED (moved to Core)
- `OspreySharp/OspreyDiagnostics.cs` -- new
  `OSPREY_DUMP_PROTEIN_FDR` / `OSPREY_DUMP_LOESS_FIT` flags + dump
  methods + inv_predict sort tiebreak + inspection cleanup (redundant
  `System.IO.` qualifier)
- `OspreySharp/AnalysisPipeline.cs` -- protein_fdr + loess_fit dump
  call wiring after `RunFirstPassProteinFdr` and after `CalibrationRefit.Refit`

osprey worktree:
- `crates/osprey/src/diagnostics.rs` -- `dump_stage6_protein_fdr` +
  `dump_stage6_loess_fit` + inv_predict sort tiebreak
- `crates/osprey/src/pipeline.rs` -- dump call wiring
- `crates/osprey/src/reconciliation.rs` -- `refit_calibration_with_consensus`
  reads `OSPREY_LOESS_CLASSICAL_ROBUST` env-var (default on) and applies
  to refit calibrator config

ai worktree (master):
- `scripts/OspreySharp/Compare-Stage6-Planning.ps1` -- `-Dump` filter,
  `-Clean` switch, shared per-dataset workdir, `protein_fdr` +
  `loess_fit` dump specs
- `docs/osprey-development-guide.md` -- new "OspreySharp project
  layering" section codifying the push-down-to-Core rule

**Pending before PR (this is the goal of the next session):**

1. `pwiz_tools/OspreySharp/Osprey-workflow.html` -- flip Cross-run
   reconciliation box from `st-partial` to `st-done`, drop "ReconciliationPlanner
   not yet wired" from its description (deferred to the third-box / Second-pass
   re-score sprint per umbrella plan), rewrite the description to reflect
   byte parity. "YOU ARE HERE" arrow placement to be decided before that PR.
2. PR split (see below).

### PR plan (final, after Session 6 restructure on 2026-04-27 evening)

Three PRs total. Initially split into 4 (diagnostics + fixes per side),
then consolidated to one PR on the pwiz side (small enough that
splitting created more cross-PR coordination cost than it saved) plus
two PRs on the osprey side (cleanly split diagnostics-vs-fixes after
extracting the bundled parser fix and `reconciliation_enabled` gate
broadening from the original diagnostics branch into a new fixes
branch off main).

**pwiz — single PR off `Skyline/work/20260423_osprey_sharp_stage6`:**
Carries all OspreySharp work for Cross-run reconciliation closure.
Earlier `-diagnostics` (#4167) and `-fixes` (#4168) PR branches are
closed; the integration branch already has the consolidated history.
Contents include:
- `OspreyDiagnostics.cs`: new `OSPREY_DUMP_PROTEIN_FDR` and
  `OSPREY_DUMP_LOESS_FIT` flags + dump methods + inv_predict sort
  tiebreak + inspection cleanups (`System.IO.File` redundant qualifier,
  `ConsensusRts.cs` XML doc).
- `AnalysisPipeline.cs`: dump call wiring at first-pass protein FDR
  and at refit.
- `OspreySharp.FDR/ProteinFdr.cs`: picked-protein algorithm port (replaces
  composite scoring), peptide-q gate fix in `CollectBestPeptideScores`,
  drop GroupPep / composite helpers / unused `pwiz.OspreySharp.ML` using.
- `OspreySharp.FDR/Reconciliation/CalibrationRefit.cs`:
  `ClassicalRobustIterations = OspreyEnvironment.LoessClassicalRobust`.
- `OspreySharp.Chromatography/LoessRegression.cs`: `Math.Pow(t,2)` ->
  `t*t` in bisquare weight.
- `OspreySharp.Core/OspreyEnvironment.cs`: moved from main project to Core.
- `pwiz_tools/OspreySharp/Osprey-workflow.html`: Cross-run reconciliation
  -> `st-done`.

ai/ companion commits (master):
- `scripts/OspreySharp/Compare-Stage6-Planning.ps1` -- `-Dump`/`-Clean`/
  shared workdir + new dump specs.
- `docs/osprey-development-guide.md` -- "OspreySharp project layering"
  section codifying the push-down-to-Core rule.

**osprey #19 — diagnostics-only, branch `feature/stage6-planning-diagnostics-dumps`:**
- `crates/osprey/src/diagnostics.rs`: original Stage 6 planning dumps
  (consensus / multicharge / refit / calibration / inv_predict) plus
  new `dump_stage6_protein_fdr` and `dump_stage6_loess_fit`. Inv_predict
  sort tiebreak (apex_rt + library_rt). Multicharge dump entry_id key.
- `crates/osprey/src/pipeline.rs`: dump call wiring.
- `crates/osprey/src/reconciliation.rs`: dump-trace block in
  `compute_consensus_rts` for `OSPREY_DUMP_INV_PREDICT`.

**osprey #21 — fixes-only, branch `feature/stage6-fixes` (off main directly):**
- `f64::from_str` for RT calibration JSON to match .NET BCL parser
  (`Cargo.toml` + `crates/osprey-chromatography/src/calibration/mod.rs`).
- Broaden Stage 6 `reconciliation_enabled` gate so `--join-only`
  multi-file invocations driven by `--input-scores` enter Stage 6
  (`crates/osprey/src/pipeline.rs`).
- Refit honors `OSPREY_LOESS_CLASSICAL_ROBUST` (default on) so Stage 6
  refit and Stage 4 calibration agree on the LOESS robustness algorithm
  (`crates/osprey/src/reconciliation.rs`).

**Merge order:**
- pwiz PR can merge independently of either osprey PR.
- osprey #19 + osprey #21 must merge together for the
  `Compare-Stage6-Planning.ps1` harness to PASS post-merge: #19 adds the
  dumps that the harness invokes; #21 has the gate broadening that makes
  Stage 6 run on `--join-only` (otherwise the dumps don't fire) and the
  refit + parser fixes that make the dumps byte-identical with the C#
  side.

### Known issues / follow-ups

- **Astral 3-file experiment_precursor_q ULP gap.** 168 rows in file 49
  show 1-ULP divergence in the `experiment_precursor_q` column of the
  `stage5_percolator` dump (e.g. `0.09775161743164063` Rust vs
  `...62` C#). All affected rows are losing entries (q ~ 0.0977 >> any
  FDR threshold) so downstream behavior is identical -- every Stage 6
  dump PASSes. Single-file Stage 5 gate is GREEN. The divergence is in
  the experiment-level q-value computation across multiple files, not
  in any data path Stage 6 work touched. Defer as a separate
  investigation; not blocking Cross-run reconciliation PR.

### Session 1 (2026-04-23) — Pre-requisites shipped; Stage 6 not yet started

Session focused on getting everything lined up for a clean Stage 6
kickoff in a new session. Three pre-requisite PRs landed or are in
review:

1. **Stage 5 dump text format** (merged pwiz #4163, commit
   `80f5341bc`). See
   `ai/todos/completed/TODO-20260423_ospreysharp_dump_format.md`.
2. **Upstream resync delta catalog**: shipped to
   `ai/.tmp/stage6_upstream_delta.md`. Eight commits from
   `885339b..2b73ba8`; no outstanding ports other than the reconciliation
   gate broadening which is natural Stage 6 walk work.
3. **Percolator streaming path port**: required for Astral byte-
   parity. Split into its own branch + TODO because it is not
   Stage 6 itself, just the last Stage 5 prerequisite. See
   `ai/todos/active/TODO-20260423_ospreysharp_percolator_streaming.md`.
   When that PR merges, Stellar + Astral are both 3/3 byte-identical
   on all four Stage 5 dumps and Stage 6 can begin.

**Actual Stage 6 walk (Priority 3 of the umbrella) has not started
in this session.** Streaming port PR #4164 merged at `edc5e0251`
2026-04-24; Stage 6 branch `Skyline/work/20260423_osprey_sharp_stage6`
created off that commit and pushed to origin at end of session
(zero Stage 6 commits of its own yet). The next session picks up
from there.

**Path-normalization follow-up** (`LibraryIdentityHash` slash-
direction issue): deferred to a later PR; hitting it only when the
CLI is invoked with mixed slash styles, so Compare-Stage5 is
unaffected.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260423_osprey_sharp_stage6.md` before starting work.

### Session 5d (2026-04-26) — serde_json parser fix, consensus 99.999% bit-parity

The InversePredict ULP source documented at the end of Session 5c
turned out **not** to be in the LOESS arithmetic at all — it was in
Rust's JSON parser. `serde_json`'s default fast number parser is not
correctly rounded for full-precision f64 values: the decimal
`"1.9140296182650374"` (a fitted_value written by ryu in the
calibration JSON) parses to `0x3FFE9FDD85606113` under
`f64::from_str` and under .NET's `double.Parse` / Newtonsoft.Json on
.NET 8, but to `0x3FFE9FDD85606114` (= `1.9140296182650376`,
1 ULP higher) under `serde_json`'s default parser. C# was correct;
Rust was 1 ULP off on every full-precision fitted_value.

Bisection discipline: built a calibration-array dump
(`OSPREY_DUMP_CALIBRATION` / `OSPREY_CALIBRATION_ONLY`) on both sides
and compared the loaded `library_rts` + `fitted_values` arrays
directly. 7,186 / 22,207 rows differed under the original parser.
Same library_rt (input decimal short like `1.74`) matched
byte-for-byte; long full-precision fitted_value lines diverged by
1-2 ULP.

osprey commit `b7904d9` adds a custom serde deserializer for the
three `Vec<f64>` fields in `RTModelParams` (library_rts, fitted_rts,
abs_residuals). It captures each element via `serde_json::value::RawValue`
and re-parses through `f64::from_str`. The `serde_json/raw_value`
feature is enabled at the workspace level. pwiz commit `9b7dc76b7`
wires the matching cross-impl dumps + bisection trace on the
OspreySharp side.

**Compare-Stage6-Planning result on Stellar 3-file (4/6 PASS, 2 nearly):**

- `stage5_percolator`: PASS (1,388,872 rows)
- `calibration`: PASS (22,207 rows — newly verified)
- `multicharge`: PASS (31,270 rows)
- `inv_predict`: 99.99966% identical — sorted diff of 292,512 rows
  has exactly **one** extra row in C#: file 21
  `SQC[UniMod:4]LQVPER` target qualifies in C# but not in Rust.
  Stage 5 dump shows file 21 SQC has `run_precursor_q=0.0096`
  (passes hard gate) and `run_peptide_q=0.0107` (fails peptide gate),
  so the protein-rescue branch is the deciding factor. C#'s
  first-pass `run_protein_qvalue` ≤ 0.01 for this peptide; Rust's is
  > 0.01. This is **a different bug** in first-pass protein FDR
  (parsimony group assignment or picked-protein TDC tie-break at the
  borderline q ≈ 0.01).
- `consensus`: 99.9989% identical — same root cause as inv_predict;
  sorted diff is exactly **one row** (`SQC[UniMod:4]LQVPER`,
  `n_runs_detected = 1` in Rust vs `2` in C#). All other 87,342
  consensus_library_rt and apex_library_rt_mad values are now
  byte-identical thanks to the parser fix.
- `refit`: `n_points` byte-identical (43589 / 43611 / 43585) but
  `r_squared` / `residual_sd` / `mad` differ at 1-3 ULP. **A
  separate LOESS-fit divergence**: the consensus pairs input to the
  refit are now byte-identical, so the residual-stats divergence
  must come from the LOESS computation itself. Stage 4 PIN features
  used F10 tolerance and may have masked 1-3 ULP all along.

**Highest-leverage remaining gaps for full Stage-6-planning bit-parity:**

1. **First-pass protein FDR borderline**. Build a per-(modseq,
   group_id, q-value) dump on both sides, gated by an
   `OSPREY_DUMP_PROTEIN_FDR` env-var, and find the SQC peptide's
   protein-group computation. Likely a tie-break in greedy parsimony
   or picked-protein TDC at exactly q = 1%. Fixing closes the last
   row of consensus + inv_predict.
2. **LOESS-fit residual stats**. Add a per-fit dump capturing the
   final fitted_values + residuals from `RTCalibrator::fit` and diff
   cross-impl. If the fitted_values match but the stats computation
   differs, fix is local. If fitted_values diverge, the LOESS
   smoother itself has a cross-impl ULP path that wasn't visible
   under Stage 4's F10 tolerance.

The two fixes are independent. With both, all 6 Stage-6-planning
dumps (including refit) become bit-identical.

**PR readiness:** Multi-charge consensus is fully bit-identical
end-to-end. Cross-run reconciliation is 99.999% bit-identical (one
borderline peptide). The osprey side has one logically clean PR
(the serde_json parser fix + Stage 6 planning dumps); the pwiz side
has the matching reconciliation port + dumps. Worth opening as a
companion-PR pair once Astral 3-file is also verified, even with
the 1-row residual diff documented as a follow-up.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260423_osprey_sharp_stage6.md` before starting work.

### Session 5c (2026-04-25 late) — First-pass compaction + multicharge bit-parity

Closed the second highest-leverage gap from Session 5b. pwiz commit
`3ab11102f` adds first-pass compaction at the same point Rust does
(`pipeline.rs:3094-3132`): right after first-pass protein FDR, before
the Stage 6 planning block. Drops entries whose base_id (entry_id with
the high decoy bit masked) doesn't pass either the peptide-q gate
(config.RunFdr) or the protein-q gate (config.ProteinFdr). Targets
and paired decoys share base_id so they're kept or dropped together.

Same commit changes the multi-charge dump key from per-file Vec
position (`entry_idx`) to the stable library entry id (`entry_id`)
on both Rust and C# sides (osprey commit `e3a6ae3` for the matching
Rust signature change). The Vec position only agreed cross-impl when
both sides had compacted; the entry_id key is invariant and is also
a more meaningful key for operator inspection.

**Compare-Stage6-Planning result on Stellar (now 2/4 PASS):**
- `stage5_percolator`: PASS (1,388,872 rows)
- `consensus`: FAIL (still ULP-level — tracking to InversePredict)
- `multicharge`: **PASS** (31,270 rows byte-identical)
- `refit`: FAIL (n_points matches; r²/sd/mad differ at ULP)

**Hypothesis for the remaining 2/4 ULP gap:**

`median_peak_width` byte-matches between Rust and C# even though it
uses the same sigmoid-weighted-median algorithm as
`consensus_library_rt`. The only difference between the two columns:
`median_peak_width` reads `entry.EndRt - entry.StartRt` directly,
while `consensus_library_rt` reads `cal.InversePredict(entry.ApexRt)`
first. **`InversePredict` is the divergent code path** — and Stage 5
dumps don't exercise it (Stage 5 only goes through forward `predict`,
which Stage 4 calibration scoring confirms is byte-identical).

Rust `inverse_predict` and C# `LoessModel.InversePredict` look
expression-for-expression identical, including the `(y1 - y0).abs() <
1e-12` near-tie branch. Possible ULP sources to investigate next
session:

1. Binary search behavior on tied `_fittedY` values: `Array.BinarySearch`
   and `binary_search_by(total_cmp)` may pick different indices among
   equal entries; if the tie spans `library_rts` values that aren't
   identical, the interpolation result differs.
2. `entry.ApexRt` (stored in Parquet) decoded differently by
   Parquet.Net vs the Rust `parquet` crate — Stage 5 dumps don't
   include ApexRt so this hasn't been verified byte-identical.
3. `Math.Exp` vs Rust `f64::exp` 1-ULP divergence in the sigmoid
   weight (although `median_peak_width` uses the same weights and
   matches, suggesting weights are NOT the divergent value).

**Suggested next-session bisection plan:**
- Add a per-detection dump (`OSPREY_DUMP_CONSENSUS_DETAIL` style)
  that emits `(file_name, entry_id, modified_sequence, apex_rt,
  library_rt)` rows on both sides. `library_rt` is
  `InversePredict(apex_rt)`; `apex_rt` is the loaded Parquet value.
  Diff isolates whether divergence is in Parquet load or
  InversePredict.
- If apex_rt diverges → fix Parquet f64 decode; close the gap.
- If only library_rt diverges → focused bisection inside
  InversePredict (binary search idx, y0/y1 selection, formula).

### Session 5b (2026-04-25 evening) — First-pass protein FDR before Stage 6

Closed the highest-leverage remaining gap from Session 5. pwiz commit
`6836aed33` adds `RunFirstPassProteinFdr` to the pipeline at the same
position Rust runs first-pass picked-protein FDR (immediately after
the Stage 5 percolator dump, before any Stage 6 work):

- Detected-peptide gate uses `run_peptide_qvalue <= config.run_fdr`,
  matching Rust pipeline.rs:3048 exactly. The existing Stage 8
  `RunProteinFdr` used `EffectiveRunQvalue(FdrLevel.Both)`, which
  differs at the gate.
- Picked-protein FDR gate is `config.RunFdr` (Savitski 2015's first-pass
  convention), not the 2x relaxed gate the post-output Stage 8
  protein FDR uses.
- `PropagateProteinQvalues` called with `setRun: true,
  setExperiment: false` so Stage 8 protein FDR can later overwrite
  experiment q-values without disturbing first-pass values.

**Compare-Stage6-Planning result on Stellar:**
- `stage5_percolator`: PASS (1,388,872 rows, byte-identical)
- `consensus`: 47,148 differing rows (down from 48,718) — all
  remaining diffs are ULP-level floating point in
  `consensus_library_rt` and `apex_library_rt_mad`. The
  AAAEAAVPR n_runs_detected gap (1 vs 2) closed; protein-rescue
  paths now agree.
- `multicharge`: still failing on entry_idx — Rust uses post-compaction
  Vec position; C# (no compaction) uses pre-compaction. The (apex,
  start, end) values agree row-for-row by entry_id; only the index
  column diverges.
- `refit`: `n_points` matches per file (43589/43611/43585); ULP
  differences in `r_squared`, `residual_sd`, `mad`. Same
  floating-point math root cause as consensus.

Stage 5 single-file parity gate re-verified green (3/3 byte-identical
on Stellar) — the new first-pass protein FDR runs after the Stage 5
percolator dump, so it can't affect dump contents.

**Path-to-4/4 from here is all floating-point math:**

1. Sigmoid weighting in consensus uses `Math.Exp` / `Math.Log` —
   Rust's `f64::exp` and .NET's `Math.Exp` agree on most inputs but
   diverge by 1 ULP on a small subset. Could try alternative
   formulations (avoid catastrophic cancellation in the sigmoid),
   but this is deep and may require accepting a tolerance.
2. LOESS residual stats in refit (`residual_sd`, `mad`) involve
   accumulation order over many points; small differences compound.
3. Multicharge dump is structural (same data, different index space).
   Easiest fix: change both dumps to emit `entry_id` instead of
   `entry_idx` so the comparison key is stable across compaction
   models. That's a 5-line edit on each side.

### Session 5 (2026-04-25) — Stage 5 multi-file fix + Stage 6 planning checkpoint wired

Pivoted from "stack up commits in isolation" to "wire the planning
checkpoint into the pipeline and prove cross-impl parity at each
phase, even if we don't yet reach end-of-Stage-6". Built the
Compare-Stage6-Planning harness to byte-compare three new dumps on
each side, plus a 3-file Stage 5 percolator dump as the precondition.

What the harness exposed and what landed:

1. **3-file Stage 5 was NOT byte-identical.** The single-file Stage 5
   parity that shipped in PR #4160 didn't exercise multi-file
   experiment-level FDR propagation. C#'s
   `ComputeExperimentPrecursorQvalues` only assigned the q-value to
   the target-decoy competition winner per base_id; non-winning
   per-file observations stayed at `q = 1.0`, while Rust's
   `base_id_exp_prec_q` HashMap (`osprey-fdr/src/percolator.rs:2168`)
   propagated to all observations sharing the same base_id (target
   AND decoy sides). Fix: pwiz commit `a2972ab6d` adds the same
   propagation. Also fixed a CLI parsing gap where C# discarded all
   but the last value across repeated `--input-scores` flags. Result:
   `cs_stage5_percolator.tsv` byte-identical with Rust on 3-file
   Stellar (1,388,872 rows).

2. **Stage 6 planning wired into the pipeline.** pwiz commit
   `379fa92e2` replaces the TODO stub at `AnalysisPipeline.cs:404`
   with the planning-checkpoint flow: per-file
   `MultiChargeConsensus.SelectRescoreTargets`, cross-run
   `ConsensusRts.Compute`, per-file `CalibrationRefit.Refit`. The
   pipeline harvests live `RTCalibration` objects via a new
   `ConcurrentDictionary` parameter on `ProcessFile`, and the
   `--join-only` path best-effort-loads each parquet's calibration
   JSON sibling so multi-file `--input-scores` runs can drive
   Stage 6 planning. The Stage 6 gate is now
   `perFileEntries.Count > 1` (was `InputFiles.Count > 1`) so
   `--join-only` correctly enters the block.

3. **Three new diagnostic dumps on both sides.** pwiz commit
   `379fa92e2` adds `OSPREY_DUMP_CONSENSUS` /
   `OSPREY_DUMP_MULTICHARGE` / `OSPREY_DUMP_REFIT` (with `_ONLY`
   early-exits) writing `cs_stage6_*.tsv`, mirroring osprey commit
   `d7636ba` on `feature/stage6-planning-diagnostics` which adds
   `dump_stage6_consensus` / `dump_stage6_multicharge` /
   `dump_stage6_refit` writing `rust_stage6_*.tsv`. Numeric columns
   use `format_f64_roundtrip` / `Diagnostics.FormatF64Roundtrip` so
   the text format is byte-comparable.

4. **Rust gate fix on the same osprey branch.** Rust's
   `reconciliation_enabled` previously read `config.input_files.len()
   > 1`, which is zero on `--join-only` runs (input arrives via
   `--input-scores`). osprey commit `d7636ba` switches both
   occurrences to `per_file_entries.len() > 1` so multi-file
   join-only runs enter Stage 6.

**Compare-Stage6-Planning result on Stellar (1/4 PASS):**

- `stage5_percolator`: PASS (1,388,872 rows)
- `consensus`: FAIL (87,343 rows, 48,718 differ)
- `multicharge`: FAIL (31,270 rows, mostly index-vs-data divergence)
- `refit`: FAIL (3 rows, n_points matches; r²/sd/mad differ at ULP)

**Remaining gaps to drive parity to 4/4:**

1. **First-pass protein FDR before Stage 6 in C#.** Rust runs
   protein parsimony + picked-protein FDR after Stage 5 and BEFORE
   compaction (`pipeline.rs:3060-3083`), populating
   `run_protein_qvalue` on every entry. C# only runs protein FDR as
   "Stage 8" after blib output, so all `RunProteinQvalue` values are
   1.0 at Stage 6 time. This breaks the protein-rescue gate in
   `Qualifies` and produces fewer detections per peptide (e.g.,
   `AAAEAAVPR` has `n_runs_detected = 1` in C# vs `2` in Rust).
   Fix: add a first-pass protein FDR call right after the Stage 5
   percolator dump and before the Stage 6 planning block.
2. **Multicharge dump uses entry_idx; index space differs.** Rust
   indexes into the post-compaction `Vec<FdrEntry>` while C# (no
   compaction) indexes into the pre-compaction list. The (apex,
   start, end) values agree row-for-row when same-keyed; only the
   entry_idx column diverges. Fix: change both dumps to emit
   `entry_id` instead of `entry_idx`, and resolve idx → entry_id at
   dump time. Or: implement compaction in C# pre-Stage 6.
3. **ULP-level LOESS divergence in refit.** `n_points` matches
   exactly per file, but `r_squared` / `residual_sd` / `mad` differ
   at the last 1-2 decimal places. Likely `Math.Exp` / `Math.Log` /
   accumulation-order differences between .NET and Rust f64 math.
   Stage 5 single-file LOESS was already known to be sensitive to
   this; the fix lives in the calibration code and is independent
   of Stage 6.
4. **ULP-level consensus differences (sigmoid weighting).** ~56% of
   consensus rows differ at the last decimal of
   `consensus_library_rt` or `apex_library_rt_mad`. Expected from
   `Math.Exp` differences in the sigmoid weight; worth bisecting
   whether a different formulation (e.g., `1 / (1 + Math.Exp(-x))`
   vs an explicit branch on x's sign) makes the result agree.

Stage 5 parity gate (`Compare-Stage5-AllFiles.ps1`) re-verified
green on Stellar (3/3 byte-identical on all four Stage 5 dumps)
after the propagation fix.

Library-path-normalization in `LibraryIdentityHash` was discussed
but reverted: dropping the path component would invalidate every
existing `.scores.rust.parquet`'s stored library_hash, requiring
~6 hours to regenerate the test parquets. Worth doing as a
coordinated change later, separate from Stage 6 work.

### Session 4 (2026-04-23 night) — Commit 5 landed (search-engine override path)

5. `16bc080f8` **OspreySharp: Stage 6 boundary-overrides path through
   the search engine** — `ScoringContext.BoundaryOverrides` property
   plus an override branch in `AnalysisPipeline.ScoreCandidate` that
   skips the signal pre-filter and CWT detection when an entry has a
   supplied (apex, start, end). The override builds a one-element
   peak list via a new `BuildOverridePeaks` helper that picks the
   max-total-intensity reference XIC, maps RTs through saturating-sub
   partition-point semantics, and reuses `PeakDetector.TrapezoidalArea`
   + `PeakDetector.ComputeSnr` for the synthetic peak's area and SNR.
   The apex-acceptance filter is bypassed for overrides. 145
   insertions / 17 deletions.

After commit 5: full test suite green (264 tests), inspection clean,
`Compare-Stage5-AllFiles.ps1` 3/3 byte-identical on Stellar AND
Astral. The override branch is dormant on first-pass (BoundaryOverrides
defaults to null), so no Stage 5 regression risk.

Branch pushed to origin through commit 5
(`Skyline/work/20260423_osprey_sharp_stage6` @ `16bc080f8`).

**PR 1 (commits 1-3)** is fully reviewable now: pure
reconciliation types + logic with 36 unit tests, no pipeline
changes. Suitable for opening immediately.

**PR 2 (commits 4-5)** is also fully reviewable: multi-charge
consensus picker (commit 4) + boundary-overrides plumbing through
the search engine (commit 5). Commit 5 has no unit tests of its own
because the search engine's private methods aren't easily isolated
for unit testing — coverage comes via the Compare-Stage5 harness
(verifying the dormant path doesn't regress) and will come fully via
Compare-Stage6 once the pipeline is wired (commit 7).

**Remaining for the parity-proof PR (commit 6+ scope):**

1. Commit 6 — `IdentifyGapFillTargets` + `GapFillTarget` (port from
   reconciliation.rs:790-?). Independent of pipeline wiring; can land
   with unit tests in its own commit. Estimate ~1-2 hours.
2. Commit 7 — Pipeline integration in `AnalysisPipeline.cs:404`.
   Replace the TODO stub with the full Stage 6 flow: per-file
   `ConsensusRts.Compute` + `CalibrationRefit.Refit` +
   `ReconciliationPlanner.Plan` + `MultiChargeConsensus.SelectRescoreTargets`
   + per-file rescore loop driving `RunCoelutionScoring` with
   `ScoringContext.BoundaryOverrides` set + gap-fill two-pass
   (CWT + forced) + Parquet write-back of reconciled scores +
   single second-pass Percolator. Largest single piece. Estimate
   ~3-5 hours.
3. **Rust PR on `maccoss/osprey`**: add
   `OSPREY_DUMP_CONSENSUS` / `OSPREY_DUMP_RECONCILIATION` /
   `OSPREY_DUMP_REFINED_FDR` env vars + matching `_ONLY` early-exit
   variants, mirroring the four Stage 5 dumps that shipped in #18.
   Each dump uses
   `pwiz.OspreySharp.Core.Diagnostics.FormatF64Roundtrip`-equivalent
   (Rust `ryu`) text formatting. Estimate ~2-3 hours including CI.
4. Commit 8 — Matching C# diagnostic dumps in `OspreyDiagnostics.cs`,
   wired into the pipeline at the same logical points as the Rust
   dumps. Estimate ~1-2 hours.
5. `ai/scripts/OspreySharp/Compare-Stage6-AllFiles.ps1` — sibling to
   `Compare-Stage5-AllFiles.ps1`, runs both tools with each of the
   three new dump env-vars + `_ONLY` and byte-compares across all 3
   files of each dataset. Estimate ~1 hour.
6. Cross-impl byte-parity verification on Stellar + Astral 3-file
   (highly variable: 1 hour if everything aligns, 5+ hours of
   bisection if drift appears).

Realistic estimate to ship the parity-proof PR: **~10-15 working
hours**, almost certainly across multiple sessions, with the parity
bisection being the unknown.

**Recommended cadence:**

- **PR 1** (commits 1-3): open immediately, low review risk.
- **PR 2** (commits 4-5): open immediately, includes the search-engine
  modification; reviewer should check the dormant-branch invariant.
- **PR 3** = commit 6 (gap-fill, types only).
- **PR 4** = commit 7 (pipeline integration). May be the biggest
  single review, but parity-equivalent on Stage 5.
- **PR 5** = Rust dumps + commit 8 (C# dumps) +
  `Compare-Stage6-AllFiles.ps1` + parity-proof. The "byte-parity
  through Stage 6" gate PR.

### Session 3 (2026-04-23 evening) — Commits 1-4 landed (pure-logic layer)

Four commits on the branch, none pushed yet:

1. `73c0ffdf5` **OspreySharp: Stage 6 consensus RT computation** —
   `PeptideConsensusRT` + `ConsensusRts.Compute` in a new
   `OspreySharp.FDR.Reconciliation` namespace. 15 unit tests
   (sigmoid weighting, hard precursor-q gate, protein-FDR rescue,
   sort determinism, missing calibration). 808 insertions.
2. `05da31585` **OspreySharp: Stage 6 reconciliation planner and
   ReconcileAction** — `ReconcileAction` (Keep / UseCwtPeak /
   ForcedIntegration) + `ReconciliationPlanner.Plan` /
   `DetermineAction` / private `SigmaClippedMad`. RT tolerance from
   global within-peptide MAD with sigma-clipped per-file ceiling.
   16 unit tests covering all three action types and Plan paths
   (missing calibration fallback, non-passing precursor skipped,
   decoy reconciled alongside paired target). 827 insertions.
3. `2a1df07f3` **OspreySharp: Stage 6 calibration refit on consensus
   peptides** — `CalibrationRefit.Refit` ports
   `refit_calibration_with_consensus`. Five unit tests
   (too-few-points, all-decoys, all-FDR-failing, valid refit,
   decoys excluded). 242 insertions.
4. `45d4c0cff` **OspreySharp: Stage 6 multi-charge consensus leader
   selection** — `MultiChargeConsensus.SelectRescoreTargets` ports
   `select_post_fdr_consensus`. Seven unit tests covering
   single-entry / no-passing / same-apex / divergent-apex / score
   tie-break / target-decoy group separation. 308 insertions.

After every commit:

- `Build-OspreySharp.ps1 -RunInspection -RunTests` clean (0 errors,
  0 warnings, all tests green; total 257 unit tests after commit 4).
- `Compare-Stage5-AllFiles.ps1` 3/3 byte-identical on Stellar AND
  Astral on all four Stage 5 dumps.

**Commits 1+2+3 form PR 1** under the original plan grouping (pure
reconciliation types + logic, no pipeline changes). **Commit 4
opens PR 2** along with the upcoming commit 5
(`boundaryOverrides` on the C# search engine), which is the first
commit that modifies an existing hot path. Pause here to confirm
the search-engine integration before continuing.

**Open questions for next session start:**

- Locate the C# `run_search` equivalent (likely
  `OspreySharp.Scoring`). Likely entry point: a method that takes
  library + spectra + calibration + config and returns scored
  entries. Plan step 5 wires `boundaryOverrides:
  IReadOnlyDictionary<uint, (double Apex, double Start, double End)>?`
  through it; when present, peak detection + pre-filter are
  skipped and scoring uses the supplied (apex, start, end).

### Session 2 (2026-04-23 evening) — Plan locked; Stage 6 implementation starts next

- Re-verified Stage 5 parity harness still green on both datasets:
  Stellar 3/3 byte-identical (total 09:13), Astral 3/3 byte-identical
  (total 08:52) across all four Stage 5 dumps.
- Read the Rust Stage 6 reference in detail: `reconciliation.rs`
  (3,225 LOC with `PeptideConsensusRT`, `compute_consensus_rts`,
  `refit_calibration_with_consensus`, `ReconcileAction`,
  `determine_reconcile_action`, `plan_reconciliation`,
  `GapFillTarget`, `identify_gap_fill_targets`) and the Stage 6
  orchestration block in `pipeline.rs` (~lines 3140-3690, including
  `select_post_fdr_consensus`, the merged consensus +
  reconciliation + gap-fill per-file re-scoring driver, and the
  single second-pass Percolator call at the end).
- Confirmed the "gray boxes" in `Osprey-workflow.html` mean
  "missing / stubbed" (legend line 164) and that Stage 6 is
  entirely unimplemented on the C# side: the only Stage 6-adjacent
  C# code is a 41-line `ReconciliationConfig.cs` data class and a
  `LogInfo("TODO: Inter-replicate reconciliation not yet
  implemented")` stub at `AnalysisPipeline.cs:404`.
- Locked the three open design questions with the developer:
  (1) Parquet write-back uses the existing end-of-Phase-4 cache
  model, `--parquet-compression snappy` on both tools for interop
  until OspreySharp gains ZSTD. (2) C# `run_search` entry point
  to be located during step 5 (expected `OspreySharp.Scoring`).
  (3) Gap-fill is in scope — byte parity + full parallelism are
  the goals.
- Added the full **Implementation plan** section above (eight
  steps, four expected PRs, Rust-side Snappy prerequisite at
  step 0). The C# port goes beyond Rust's sequential per-file
  re-scoring — re-scoring runs file-parallel on the C# side
  (consistent with Stages 1-4 file-level parallelism).
- Next session: start commit 1 (`PeptideConsensusRT` +
  `ComputeConsensusRts`) plus its unit tests, after the Rust-side
  Snappy round-trip smoke test.
