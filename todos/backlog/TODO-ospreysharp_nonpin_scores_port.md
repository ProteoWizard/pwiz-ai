# TODO-ospreysharp_nonpin_scores_port.md

## Summary

Port the **non-PIN Osprey scores** — the ~26 features the Rust engine computes but
excludes from the 21-feature PIN vector (hyperscore, the dot-product/Top-N family,
DIA-NN-style pCos, fragment/sequence coverage, base-peak rank, peak width/symmetry,
etc.) — onto OspreySharp's modular calculator model, **each byte-parity-verified
against the original Rust implementation**, and surface them as a Skyline-style
catalog (active scores live, disabled scores present-but-not-selected, with their
exclusion explanations).

**Status**: Backlog (not started). **Type**: Scoring port + cross-impl verification.
**Prerequisite work DONE**: the 21 PIN features are already decomposed into
one-class-per-score calculators on the `OspreySharp.Scoring` SPI
(`IOspreyFeatureCalculator` / `OspreyScoringContext` / `IOspreyDetailedPeakData` /
`OspreyFeatureCalculators`) — see the completed sprint
`TODO-20260607_ospreysharp_modular_scoring.md` and its PR. This work builds directly
on that SPI.

## Why this is a separate sprint (the parity problem)

**Most** of these scores do not exist in OspreySharp today. The C# port builds a
bare `double[21]` PIN vector directly from the 21 calculators; it never populates a
`CoelutionFeatureSet`. The `CoelutionFeatureSet` class
(`OspreySharp.Core/CoelutionFeatureSet.cs`, ~40 properties) is a near-**dead 1:1
mirror** of the Rust struct — its non-PIN fields are defined-but-never-assigned in
the C# scoring path (a unit test, `CoreTypesTest.cs:362-363`, even asserts
`Hyperscore == 0.0` / `PeakWidth == 0.0` defaults). The full ~47-field set is
computed in **Rust** (`crates/osprey/src/pipeline.rs` `run_search` +
`crates/osprey-scoring/src/lib.rs`), which then selects 21 for the PIN.

**Two tiers of effort (verified 2026-06-08, important correction):** a *few* of the
excluded scores ARE already computed in C# — the math exists, it is just consumed as
a byproduct or for peak bounds, never emitted as a feature. Wiring those into
calculators is cheap and (for `dot_product`) even has a partial oracle. The
*majority* have no C# code at all and need a from-scratch Rust→C# port.
- **C#-AVAILABLE (cheap to wire):**
  - `dot_product` (= `lib_cosine`): real, exercised C# computation in
    `SpectralScorer.LibCosine` (`SpectralScorer.cs:573`), invoked at the apex
    (`AbstractScoringTask.cs:1433`, currently a vestigial/unused local). Also
    `BatchScorer.LibCosineScorer`.
  - `signal_to_noise`: computed for peak-bounds detection
    (`PeakDetector.ComputeSnr`; stored on `XICPeakBounds.SignalToNoise`, used at
    `AbstractScoringTask.cs:1671`). A calculator would just read `bestPeak.SignalToNoise`.
  - `top6_matches`: computed inline via `CountTop6Matches` as a dedup byproduct.
- **NO C# CODE (needs a verified port):** hyperscore, dot_product_smz, the
  dot_product[_smz]_top4/5/6 family, fragment_coverage, sequence_coverage,
  base_peak_rank, mass_accuracy_std, peak_symmetry, peak_width, n_scans,
  coelution_min, n_fragment_pairs, fragment_corr_0..5, elution_weighted_cosine
  (pCos), modification_count, peptide_length, missed_cleavages,
  median_polish_rsquared. (~22 scores; whole-tree search finds only the dead field
  declarations, no computing method.)

Consequently there is **no cross-impl oracle** for the NO-C#-CODE tier: the existing
end-to-end gate (`Compare-EndToEnd-Crossimpl.ps1`, Stage 7 + blib @ 1e-9) only
covers the 21 PIN columns. Porting that Rust math to C# without a per-feature parity
gate would mean shipping unverified scoring functions — against the project's
byte-parity discipline. So this sprint must **first build the verification harness**,
then port that tier. (The C#-AVAILABLE tier can be wired up before the harness,
since its math is already in the tree; `dot_product` can be checked against Rust's
`lib_cosine`, and `signal_to_noise` reuses the already-validated bounds SNR.)

**Hard invariant (carry into any change):** nothing here may alter the 21-element
PIN vector, its order, or its values. The PIN width is fixed at 21 in three
co-located constants that must all stay 21:
- C# `OspreyFeatureCalculators.FeatureCount` (`OspreySharp.Scoring/OspreyFeatureCalculators.cs`)
- C# `AbstractScoringTask.NUM_PIN_FEATURES` (`OspreySharp/Tasks/AbstractScoringTask.cs`)
- Rust `NUM_PIN_FEATURES` (`crates/osprey-fdr/src/mokapot.rs:950`)
Excluded scores must **never** become PIN columns.

## Plan (suggested)

1. **Build the per-feature cross-impl verification harness (prerequisite).**
   Make both Rust and C# emit the FULL `CoelutionFeatureSet` (~47 fields) per scored
   entry to a comparable dump (Rust already computes them; C# would compute them via
   the new calculators), then compare every column at 1e-9 — the same discipline the
   21-feature `.cs_features.tsv` golden diff uses, extended to the full set. Without
   this, a ported score cannot be trusted.
2. **Port each non-PIN score as a live `IOspreyFeatureCalculator`** that is NOT added
   to the 21-index `_calculators` registry (its inputs are already reachable via the
   existing SPI — see "Inputs" below). Keep a SEPARATE Skyline-style catalog list of
   these non-PIN calculators (mirrors `PeakFeatureCalculator.Calculators` where
   disabled scores are listed/commented with reasons).
3. **Verify each ported score byte-identical to Rust** via the §1 harness before
   trusting it. Bisect any drift; do NOT widen tolerance.
4. **pCos / elution_weighted_cosine is special — do NOT live-port.** Rust deliberately
   deleted its computation (hard-coded `0.0`, comment: "removed: expensive per-scan
   ppm matching, not in PIN", `pipeline.rs:7527`). It must stay `0.0` to preserve
   parity. Represent it as a commented-out / sentinel catalog entry carrying that
   verbatim reason, not a live calculator.

## The catalog of non-PIN scores (durable copy)

Status legend: **RUST-ONLY** = computed in Rust, C# mirror field dead (no C#
computation). **C#-AVAILABLE** = the C# math already exists (as a byproduct or for
peak bounds), just not emitted as a feature — cheap to wire into a calculator.
**RUST-ZEROED** = Rust hard-codes 0.0. **C#-BYPRODUCT** = computed in C# for a
non-feature purpose. Reason "bulk-removed" = dropped from PIN as a group during
feature-weight optimization (`osprey-fdr/src/mokapot.rs:957-964` + osprey `CLAUDE.md`);
no per-feature rationale exists in source. Line numbers are as of 2026-06-07; re-grep
before use.

| Name | Family | Status | Rust compute (file:line) | Inputs (existing SPI accessor) | Exclusion reason |
|---|---|---|---|---|---|
| fragment_coelution_min | Coelution | RUST-ONLY | pipeline.rs:7499 | `Xics` | bulk-removed |
| n_fragment_pairs | Coelution | RUST-ONLY | pipeline.rs:7502 | `Xics` | bulk-removed |
| fragment_corr_0..5 | Coelution | RUST-ONLY | pipeline.rs:7503 | `Xics` | bulk-removed |
| peak_width | Peak-shape | RUST-ONLY | pipeline.rs:7506 | `Xics`/`PeakBounds` | bulk-removed |
| peak_symmetry | Peak-shape | RUST-ONLY | pipeline.rs:7507 | `Xics`/`PeakBounds` | bulk-removed |
| signal_to_noise | Peak-shape | **C#-AVAILABLE** | pipeline.rs:7508 (= peak SNR) | `bestPeak.SignalToNoise` (already computed: PeakDetector.ComputeSnr; XICPeakBounds.SignalToNoise) | bulk-removed — but C# value already exists for bounds; calculator just reads it |
| n_scans | Peak-shape | RUST-ONLY | pipeline.rs:7509 | `PeakBounds` | bulk-removed |
| hyperscore | Spectral-at-apex | RUST-ONLY | lib.rs:1463 (compute_hyperscore), lib.rs:2177; pipeline.rs:7511 | `ApexSpectrum` + `Candidate.Fragments` | bulk-removed (X!Tandem-style) |
| dot_product | Spectral-at-apex | **C#-AVAILABLE** | lib.rs:1635 (lib_cosine); pipeline.rs:7513 | `ApexSpectrum` — C# `SpectralScorer.LibCosine` (SpectralScorer.cs:573) already runs at apex (vestigial local AbstractScoringTask.cs:1433); also BatchScorer.LibCosineScorer | bulk-removed — C# math exists; checkable vs Rust lib_cosine |
| dot_product_smz | Spectral-at-apex | RUST-ONLY | pipeline.rs:7514 | `ApexSpectrum` | bulk-removed |
| dot_product_top6/5/4 | Spectral-at-apex | RUST-ONLY | lib.rs:1772-1774 (cosine_topn_sqrt); pipeline.rs:7515-7517 | `ApexSpectrum` + top-N lib frags | bulk-removed |
| dot_product_smz_top6/5/4 | Spectral-at-apex | RUST-ONLY | pipeline.rs:7518-7520 | `ApexSpectrum` | bulk-removed |
| fragment_coverage | Spectral-at-apex | RUST-ONLY | lib.rs:1734 (n_matched/n_library); pipeline.rs:7521 | `ApexSpectrum` | bulk-removed |
| sequence_coverage | Spectral-at-apex | RUST-ONLY | lib.rs:1975 (compute_sequence_coverage); pipeline.rs:7522 | `ApexSpectrum` + ion ordinals (`LibraryFragment.Annotation`) | bulk-removed |
| elution_weighted_cosine (**pCos**) | Spectral-at-apex | RUST-ZEROED | lib.rs:312 (helper, no longer called); pipeline.rs:7527 hard-codes 0.0 | per-scan `WindowSpectra` + coeff series | **"removed: expensive per-scan ppm matching, not in PIN" (pipeline.rs:7527). DIA-NN-inspired. Keep 0.0 — do NOT live-port.** |
| base_peak_rank | Spectral-at-apex | RUST-ONLY | lib.rs:2016 (compute_base_peak_rank); pipeline.rs:7524 | `ApexSpectrum` | silently excluded (no comment) |
| top6_matches | Spectral-at-apex | C#-BYPRODUCT | pipeline.rs:7525 | `ApexSpectrum` + top-6 frags | computed inline in C# (`CountTop6Matches`) for dedup, never a PIN feature |
| mass_accuracy_std | Mass-accuracy | RUST-ONLY | pipeline.rs:7530 | `ApexSpectrum` (matched-frag ppm) | bulk-removed |
| modification_count | Peptide-props | RUST-ONLY | pipeline.rs:7535 | `Candidate` metadata | silently excluded (no comment) |
| peptide_length | Peptide-props | RUST-ONLY | pipeline.rs:7536 | `Candidate` metadata | bulk-removed |
| missed_cleavages | Peptide-props | RUST-ONLY | pipeline.rs:7537 | `Candidate` metadata | bulk-removed |
| median_polish_rsquared | Median-polish | RUST-ONLY | pipeline.rs:7539 | `MedianPolishByproduct` | bulk-removed |

Inputs note: nearly all are reachable through the existing `IOspreyDetailedPeakData`
(`ApexSpectrum`, `Xics`, `WindowSpectra`, `ScanRetentionTimes`, `PeakBounds`,
`Candidate`) + `MedianPolishByproduct`. A shared "apex matched-fragments" byproduct
(lib intensity, obs intensity, ppm error, ion type/ordinal) would let hyperscore /
coverage / base_peak_rank / dot-product / mass_accuracy_std share one apex match pass
— an optimization, not a hard requirement.

## Exclusion-explanation sources (for the Skyline-style catalog reasons)

The exclusion explanations are sparse in source — surface these in the catalog:
1. **Per-feature (only one exists):** `osprey/crates/osprey/src/pipeline.rs:7527` —
   `elution_weighted_cosine: 0.0, // removed: expensive per-scan ppm matching, not in PIN`.
2. **Bulk removed-list:** `osprey/crates/osprey-fdr/src/mokapot.rs:957-964` — the "26
   features temporarily removed" comment (fragment_corr_0..5, fragment_coelution_min,
   n_fragment_pairs, dot_product[_smz][_top4..6], signal_to_noise, peak_symmetry,
   elution_weighted_cosine, peptide_length, missed_cleavages, peak_width, n_scans,
   fragment_coverage, hyperscore, sequence_coverage, ...).
3. **Project narrative:** osprey `CLAUDE.md` "Feature Set (21 PIN Features)" —
   "remaining fields are computed but not used (removed during feature weight
   optimization)."
`base_peak_rank` and `modification_count` are excluded silently (not named in the
removed-list text).

## References

- Completed modular-scoring sprint: `ai/todos/active/TODO-20260607_ospreysharp_modular_scoring.md`
  (the 21-feature decomposition + SPI this builds on).
- Full investigation artifact (ephemeral, may be gone): was `ai/.tmp/extended-scores/catalog.md`.
- Origin: requested 2026-06-07 during the modular-scoring sprint — port ALL scores,
  including those excluded from the 21, with the disabled ones shown Skyline-style
  with explanations. Deferred here because the scores are Rust-only (no C# parity
  oracle yet), so they need the §1 verification harness first.
