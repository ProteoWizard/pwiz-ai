# TODO-20260423_osprey_sharp_stage6.md — Phase 4 Stage 6: refinement parity

> Sub-sprint of **TODO-20260423_osprey_sharp.md** (Phase 4
> umbrella, Stages 6-8). The umbrella is the authoritative plan;
> this file tracks the Stage 6 branch, progress log, and PR links.

## Branch Information

- **pwiz branch**: `Skyline/work/20260423_osprey_sharp_stage6` (created 2026-04-23 off master at `edc5e0251`, pushed to origin, zero commits of its own yet)
- **osprey branch**: TBD (created only if a parity-critical upstream port needs landing)
- **Base**: `master` (pwiz at `edc5e0251`) / `main` (maccoss/osprey at `2b73ba8`)
- **Created**: 2026-04-23
- **Status**: Pending (prerequisites done; Stage 6 walk starts in the next session)
- **GitHub Issue**: (none — tool work, no Skyline integration yet)
- **PR**: (pending)

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
