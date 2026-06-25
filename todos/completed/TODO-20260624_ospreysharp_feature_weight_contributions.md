# TODO-ospreysharp_feature_weight_contributions.md

> **DONE (2026-06-25):** Author-requested structural refinement complete and committed
> (`e0e64a6f62` on PR #4328, base `3099488f15`). `FeatureContributions.Accumulator` now owns both
> the per-feature summing (a `double[]` streaming overload + a `Matrix` row overload) and the
> fold-averaging (`Build`); the decomposition ctor is `internal` so `Build` is the only public path
> from a trained model. Both Percolator paths (direct + streaming) use the Accumulator;
> `PercolatorResults` carries a `FeatureContributions` object in place of the speculative
> `AvgWeights`/`AvgBias`, and `TestFeatureContributionReport` is rewired off them. Gates green:
> pre-commit (build + 439 tests + 0-warning inspection) and regression.ps1 Stellar 3/3 legs PASS
> with the blib byte-identical (52,514,816 bytes) -- confirming reporting-only. fw TeamCity
> re-triggered on pull/4328 (`ProteoWizard_OspreyWindowsNet` #4062498 +
> `...PerfRegressionTests` #4062499).
>
> **Review round 2 (2026-06-25, `054bec9993`):** addressed two author review notes.
> (1) Collapsed the three parallel feature arrays (FeatureNames/FeatureLabels/ReversedScore) into one
> `OspreyFeatureInfo` struct (new, in Core) carrying name+label+direction; the Tasks caller populates
> the vector from the calculators via `OspreyFeatureCalculators.BuildFeatureInfos` (replaces
> GetFeatureLabels/GetReversedScoreFlags). FDR can't see the Scoring SPI, so the struct lives in Core
> (FDR and Scoring are siblings that both reference Core). One `OspreyFeatureInfo[]` now threads through
> PercolatorConfig/PercolatorEngine/PercolatorFdr (Stage 5 dumps + report). (2) Trimmed the
> over-detailed EmitFeatureContributions doc to defer to FeatureContributions. Two getter tests
> consolidated into TestBuildFeatureInfos. Gates green again: build + 438 tests + 0-warning inspection,
> regression.ps1 Stellar 3/3 PASS (blib still 52,514,816 bytes). Re-triggered fw TeamCity on pull/4328
> (`ProteoWizard_OspreyWindowsNet` #4062666 + `...PerfRegressionTests` #4062667).
>
> **Review round 3 (2026-06-25, `2c7b5bab72`, test-only):** rewrote `TestBuildFeatureInfos` -- the
> hard-coded label/direction oracle was a change-detector re-encoding data the calculators already
> own. Now it calls `BuildFeatureInfos(ParquetScoreCache.PIN_FEATURE_NAMES)` and asserts each info's
> name == the supplied PIN name and its label/direction == the calculator at the same index, i.e. it
> verifies the by-index merge itself. Build + 438 tests + 0-warning inspection green; production code
> unchanged from `054bec9993` so the perf run #4062667 still applies, only the per-commit unit-test
> build re-triggered on pull/4328. Next: confirm CI green, then the PR is mergeable.
> This was the first clean extraction toward `ai/todos/backlog/TODO-ospreysharp_percolatorfdr_god_class.md`.

## Summary

After Percolator training, emit a **feature weight + percent-contribution table** for
the trained linear model — for each of the 21 PIN scores: its trained coefficient and
its relative importance as a percentage (signed, all summing to 100%), exactly like
Skyline's peak-scoring model report. The percentages express each score's share of the
target-decoy *separation* of the composite discriminant (`w_j * Delta-mu_j`, where
`Delta-mu_j` is the feature's target-minus-decoy mean gap), and a contribution is
**negative** (red in Skyline's UI) when the trained coefficient points in the *unexpected*
direction for that score.

This is a follow-up to the modular-scoring refactor (now **completed**,
`TODO-20260607_ospreysharp_modular_scoring.md`): the `IOspreyFeatureCalculator`
SPI it added is the natural home for the per-score **direction** this feature
needs, so that dependency is now satisfied -- the direction property + the
contribution table can be built directly on the existing seam.

**Status**: **Completed** -- PR [#4328](https://github.com/ProteoWizard/pwiz/pull/4328)
merged 2026-06-25 as `74cf4785e9`. **Type**: Scoring interpretability / FDR reporting.

## Why it's valuable

It tells you which scores actually drive discrimination and which may not be working
as expected (a coefficient in the unexpected direction — e.g. higher peak-shape
correlation or signal-to-noise *lowering* the composite score). One of the most
useful interpretability tools Skyline exposes; not free to compute, but worth it to
understand and audit the 21-feature model.

## The Skyline analog (the target output)

Skyline shows, per feature, `coefficient (percent%)`, e.g.:

```
Intensity:                     0.4074 (13.2%)
Retention time difference:    -0.0331  (0.4%)
Library intensity dot-product: 6.0406 (54.8%)
Shape (weighted):             -0.8902 (-10.7%)   <- unexpected direction (red)
Co-elution (weighted):        -0.1125  (1.8%)
Co-elution count:              0.8225 (38.1%)
Signal to noise:              -0.1864 (-3.5%)     <- unexpected direction (red)
Product mass error:           -0.0423  (1.9%)
```

The percentages are a **target-decoy mean-difference decomposition** of the composite
score across features (NOT a variance / `w*std` decomposition -- see "How the math works
(why it ports across training paradigms)" below); the sign is set by the feature's expected
direction (see "direction" below). Negative contributions render red in
`EditPeakScoringModelDlg`.

## What Osprey already has (grounding)

`OspreySharp.FDR/PercolatorFdr.cs` trains a linear SVM and already exposes the model:
- Per-fold weight vectors `FoldWeights` (`List<double[]>`), averaged into `avgWeights[j]`
  (`PercolatorFdr.cs:707-718`); the final decision score is the linear combination
  `score += avgWeights[j] * featureBuf[j]` (`:743`).
- Features are **standardized** before the SVM (a per-feature mean/std standardizer is
  applied, `:721`) — so the weights are on unit-variance features, and the standardizer
  already carries the per-feature std the contribution math needs.
- `config.FeatureNames` (the 21 PIN names) and an existing diagnostic
  `WriteStage5SvmWeightsDump` (gated by `OSPREY_DUMP_SVM_WEIGHTS=1`; mirrors Rust
  `osprey-fdr/src/percolator.rs::dump_stage5_svm_weights`) that already prints per-fold
  weights + bias.

So the linear equation exists post-training; this TODO adds the **contribution %**, the
**direction**, and a first-class **report**.

## How the math works (why it ports across training paradigms)

Settled in design discussion (2026-06-24). The percent-contribution is a property of **a
linear discriminant and the data it scored**, independent of the optimizer that produced the
weights -- so it ports to Percolator's linear SVM exactly as to mProphet's LDA. (This was
doubted on the grounds that "an SVM equation differs from an LDA equation"; that conflates
the *fitting objective* with the *model form*. Both emit the same object -- a bias + weight
vector, `d(x) = b + sum_j w_j z_j`. OspreySharp scores precisely this:
`PercolatorFdr.cs:738-740`, `score = avgBias + sum_j avgWeights[j]*featureBuf[j]` on the
standardized `featureBuf`.)

**Skyline's exact formula** (`TargetDecoyGenerator.GetPercentContribution`, `:233-258`,
reached via `LinearModelParams.CalculatePercentContributions` / `MProphetScoringModel`) is a
target-decoy **mean-difference** decomposition -- NOT a variance / `w*std` formula:

    contribution_j = w_j * (mean_target(x_j) - mean_decoy(x_j)) / (mean_target(d) - mean_decoy(d))
                   = w_j * Delta-mu_j / Delta-mu_composite

By linearity of expectation the denominator equals the sum of the numerators
(`Delta-mu_composite = sum_j w_j*Delta-mu_j`; the bias cancels in the difference), so the
per-feature percentages sum to **exactly 100% for any linear model whatsoever**. The only
ingredients are the coefficients `w_j` and the data's per-feature target-minus-decoy gap
`Delta-mu_j`; the training paradigm leaves no fingerprint beyond the numeric values of `w_j`.

- **Load-bearing assumption:** linearity of the final scorer. It breaks only for a
  nonlinear/kernel SVM, a tree, or feature interactions -- none in play here. A linear SVM
  yields the same object as LDA.
- **Do NOT** port an LDA-specific importance formula (e.g. backing weights out through the
  pooled within-class covariance, `w = Sigma^-1 (mu_T - mu_D)`) -- that *would* assume the
  generative model. Skyline deliberately uses the model-agnostic mean-difference method above;
  port that.
- **Sign / direction** falls out of the same formula: feature `j` contributes negatively when
  `w_j*Delta-mu_j < 0` -- the weighted feature pushes targets *below* decoys, i.e. the trained
  sign disagrees with the score's expected direction (the `IsReversedScore` property of task 1).
- **Score calibration is orthogonal.** OspreySharp applies Granholm-2012 between-fold
  calibration to the composite score (anchors the FDR-threshold score -> 0, median decoy -> -1;
  `CalibrateScoresBetweenFolds`, `:1678-1728`) and does NOT z-score the output. That does not
  touch the contribution table: the % is invariant to any affine rescale of the composite, and
  is computed from `avgWeights`, which the calibration never modifies. (Aside: inputs ARE
  z-scored -- the per-feature standardizer -- but the composite output is decision-anchored,
  not moment-standardized, mirroring Percolator/mokapot/Rust.)

## What to build

1. **Per-score direction on the calculator SPI.** Add an `IsReversedScore`-equivalent
   (bool: is lower "better"/target-like, or higher?) to `IOspreyFeatureCalculator` (the
   refactor's SPI), set on each of the 21 calculators. This is Skyline's
   `IPeakFeatureCalculator.IsReversedScore`. It defines the *expected* sign of the
   trained coefficient; the table marks a contribution negative when the trained sign
   disagrees. (Map each PIN score's expected direction from its meaning / from Rust /
   from Skyline's analogous calculator.)

2. **Percent-contribution computation.** Port Skyline's exact method (do NOT approximate):
   `TargetDecoyGenerator.GetPercentContribution` (`:233-258`), reached via
   `LinearModelParams.CalculatePercentContributions` / `MProphetScoringModel`. It is the
   **target-decoy mean-difference** decomposition
   `contribution_j = w_j * Delta-mu_j / Delta-mu_composite` (see "How the math works"), NOT a
   `w*std` variance formula. Compute `Delta-mu_j` (target-minus-decoy mean of feature `j`) in
   the SVM's actual input space -- the standardized `featureBuf` OspreySharp already scores on
   -- and use `avgWeights[j]`. Contributions are invariant to standardized-vs-raw as long as
   `w` and `Delta-mu` share a space (`w_j^std * Delta-mu_j^std = w_j^raw * Delta-mu_j^raw`);
   only the *displayed coefficient* differs (see open questions). Percentages sum to exactly
   100%.

3. **Report / output.** Emit the table (per-feature: friendly name, coefficient,
   signed percent) after Stage 5 training — a log line set and/or a structured report
   row, alongside the existing weights dump. Use the 21 PIN names with human-friendly
   labels (Skyline-style).

## Skyline reference code (port the math from here)

- `pwiz_tools/Skyline/Model/Results/Scoring/LinearModelParams.cs` — weights + the
  percent-contribution calculation.
- `pwiz_tools/Skyline/Model/Results/Scoring/MProphetPeakScoringModel.cs` — model that
  produces the trained weights + contributions.
- `IPeakFeatureCalculator.IsReversedScore` — the per-score direction.
- `pwiz_tools/Skyline/SettingsUI/...EditPeakScoringModelDlg` — the UI that renders the
  table (negative = red), for the exact display semantics.

## Dependencies / synergy

- Builds on the modular-scoring SPI (`IOspreyFeatureCalculator`) — the per-score
  direction property lives there.
- Uses the already-trained `PercolatorFdr` weights + standardizer; no change to FDR
  values, so it does not touch the scoring/q-value parity.

## Cross-impl / parity notes

- The trained weights themselves are already parity-gated (they determine the FDR
  q-values compared at 1e-9). This feature only *surfaces* them + derived percentages,
  so it is reporting, not a scoring change.
- Decide whether Rust osprey (`osprey-fdr`) should emit the same table for cross-impl
  comparison, or whether this is C#-side reporting only. If both emit it, the
  contribution math must be identical (deterministic) to compare.

## Open questions

- **Standardized vs raw coefficients in the display.** Osprey trains on standardized
  features, so `avgWeights` are standardized-scale; Skyline's example shows raw-scale
  coefficients (e.g. 6.0406). Decide whether to report standardized weights (simplest;
  `std_j = 1`) or un-standardize to raw scale (`w_raw_j = w_std_j / std_j`) to match
  Skyline's presentation. The percent contributions are invariant to this choice
  (`w_raw_j * std_j == w_std_j`), but the printed coefficient differs.
- **Which variance.** Use the standardizer's per-feature std (computed on the training
  subsample) vs the std over all scored entries. Skyline uses the model's training
  data; match that.
- **Per-fold vs averaged.** Report contributions for the averaged model (`avgWeights`)
  — confirm that is what users want (vs per-fold spread).
- **Correlated features (resolved).** Skyline's formula has **no covariance term** -- the
  mean-difference decomposition is exact and sums to 100% regardless of correlation,
  attributing the shared signal per the fitted weights. This limitation is *shared by LDA and
  SVM*, not a reason the method fails for the SVM. (SVM L2 tends to *spread* weight across
  correlated scores -- the median-polish / coelution families -- where LDA may concentrate it;
  different-looking, neither wrong, each describes its own model.) Nothing extra to port for
  correlation -- just don't substitute a covariance-aware variance method Skyline doesn't use.

## References

- Modular-scoring refactor (provides the calculator SPI + direction home):
  `ai/todos/active/TODO-20260607_ospreysharp_modular_scoring.md`.
- Osprey linear model: `OspreySharp.FDR/PercolatorFdr.cs` (`FoldWeights`, `avgWeights`,
  the standardizer, `WriteStage5SvmWeightsDump`); Rust
  `osprey-fdr/src/percolator.rs` / `mokapot.rs`.
- Origin: requested 2026-06-08 — replicate Skyline's per-feature weight + percent-
  contribution table (with signed/red unexpected-direction contributions) for Osprey's
  Percolator-trained linear model.

## Progress Log

### 2026-06-25 - Merged

PR #4328 merged as commit `74cf4785e9`. Shipped the post-Percolator per-feature weight +
signed percent-contribution table (Skyline's exact target-decoy mean-difference decomposition,
percents sum to 100% by linearity), `IsReversedScore` added to the `IOspreyFeatureCalculator`
SPI with the `(unexpected direction)` wrong-sign flag, and an optional machine-precision TSV
via `OSPREY_DUMP_FEATURE_CONTRIB`. Three structural review rounds landed on top of the feature:
(1) extracted the calculation into a `FeatureContributions` class with a nested `Accumulator`
owning the summing + fold-averaging, carried on `PercolatorResults`; (2) collapsed the three
parallel name/label/direction arrays into one `OspreyFeatureInfo` struct (new in Core) the Tasks
layer populates from the calculators via `OspreyFeatureCalculators.BuildFeatureInfos`, keeping
OspreySharp.FDR free of a Scoring reference; (3) rewrote `TestBuildFeatureInfos` to validate the
by-index merge against its sources instead of a re-encoded oracle. Reporting only -- regression.ps1
Stellar all 3 legs byte-identical at 1e-9 throughout. Merged over a still-running CodeQL
`Analyze (c-cpp)` check (irrelevant to a pure-C# diff) per developer go-ahead; all other checks
green. **Follow-up (not filed):** the `TODO-ospreysharp_percolatorfdr_god_class.md` backlog item --
this contribution extraction was its first clean piece.
