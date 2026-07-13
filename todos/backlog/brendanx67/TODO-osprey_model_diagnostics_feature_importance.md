# TODO: Osprey --model-diagnostics — feature importance & redundancy companions to the percent-contribution table

**Status**: Backlog
**Priority**: Medium (interpretive value; answers the standing "is percent-contribution
  appropriate for Percolator?" question with the diagnostics that actually measure importance/redundancy)
**Created**: 2026-07-13
**Requested by**: Brendan
**Scope**: `pwiz_tools\Osprey\Osprey.FDR\FeatureContributions.cs`,
  `Osprey.FDR\PercolatorFdr.cs` (fold weights already in hand),
  `Osprey.FDR\ModelDiagnostics\ModelDiagnosticsData.cs`,
  `Osprey.Tasks\ModelDiagnostics\model-diagnostics-template.html`
**Related**:
- Builds on the percent-contribution table + per-feature distributions (PR #4377).
- Sibling: [[TODO-osprey_model_diagnostics_training_pool_distributions]] (per-feature
  *distribution* view + **permutation importance** lives there, not here).
- Diagnostics-only, off the regression golden path (never sets `--model-diagnostics`).

## Why this exists — the percent-contribution table is a description, not importance

The shipped table (`FeatureContributions`, `--verbose` / `--model-diagnostics`) decomposes the
composite target-decoy mean gap: `Delta-mu_composite = sum_j w_j*Delta-mu_j`, so each feature's
"share (%)" is `100 * w_j*Delta-mu_j / Delta-mu_composite`. Its heading already frames it correctly:
**"Model sanity check -- feature share of target-decoy separation"**, and the code comment states it
is **NOT feature importance**.

When we added it, Mike MacCoss pushed back (it moved to `--verbose`). Untangling his objections, for
the record and to guide this work:

1. **"Percolator uses a hyperplane"** -- true, but not a distinction from mProphet. *Every* linear
   model scores `s = w.x + b`; a q=0.01 cutoff maps monotonically to a score threshold `s*`, and
   `{x : w.x = s*}` is a hyperplane (2 features -> line, 3 -> plane, >=4 -> hyperplane). SVM and LDA
   share this functional form; they differ only in the objective that orients `w` (SVM = max margin;
   LDA = Fisher ratio under an equal-covariance Gaussian). So the decomposition of `w` is valid for
   both.
2. **"People used leave-one-out with Percolator because percent-contribution was invalid."** The real
   issue is not the SVM -- it is **collinearity**. Percent-contribution faithfully describes the
   equation you got; it does **not** tell you whether a feature is *necessary* (importance), because
   correlated features trade weight. This is true for LDA too; importance needs a different measure
   (ablation / permutation), regardless of the trainer.
3. **Covariance is handled differently by the two trainers** (the load-bearing insight for this TODO):
   - **LDA (mProphet, no CV)**: `Sigma^-1` **concentrates** weight -- loads one of a correlated pair,
     near-zeros the twin, and can blow up / go unstable when `Sigma` is near-singular.
   - **L2 SVM (Percolator, 3-fold CV)**: **spreads** weight across a correlated group (L2 prefers many
     small weights over one large). So each member of a covarying set shows a modest share and **none
     looks essential -- yet the group is**. This is exactly why "is one of a covarying set
     unnecessary?" is unreadable from the table alone.

**The point of this TODO:** add the companion diagnostics that (a) measure importance/redundancy
rather than describe the equation, and (b) turn the covariance blind spot into something visible --
while leaning on a Percolator advantage mProphet lacks (cross-validation gives fold-to-fold weight
stability for free).

## Deliverables (three cheap, no-retrain analyses)

### 1. Fold-to-fold weight stability (Percolator CV freebie)
Percolator trains `nFolds` (default 3) SVMs; `FeatureContributions.Accumulator.Build` already receives
`foldWeights` but currently only **averages** them. Report, per feature, the **spread** of its
standardized weight across folds: mean +/- std (or min/max), and a **sign-consistency** flag (did the
weight keep the same sign in every fold?). A stable, same-sign weight is a robust contributor; a weight
that swings or flips sign across folds is a redundancy / collinearity tell. This is the direct,
data-in-hand answer to "mProphet has no CV" -- a robustness signal LDA cannot give.
- **Cost**: ~free (fold weights already resident at Stage 5; no extra pass).
- **Surfacing**: extra columns on the existing feature table (coefficient +/- fold spread; a
  "sign flips across folds" marker), and/or a small per-feature error-bar glyph.

### 2. Univariate discrimination scalars
For each feature *alone* as a score, the marginal separation: **AUROC** (target vs decoy), **Cohen's d**
(`(mu_t - mu_d)/pooled_sd`), and optionally **IDs-at-1%q** using that single feature. This is the scalar
summary of the per-feature histograms already collected for `--model-diagnostics`, and it lets a reader
compare "how much this feature separates *by itself*" against "its share of the *joint* model" -- a large
joint share on a feature with poor univariate separation (or vice-versa) is the interesting signal.
- **Cost**: cheap. AUROC computable from the existing per-feature histograms; Cohen's d needs a
  per-feature **sum-of-squares** added to `Accumulator` (currently only sums are kept).
- **Surfacing**: columns on the feature table (AUROC, d) beside the joint share.
- **Coordinate with** [[TODO-osprey_model_diagnostics_training_pool_distributions]]: that TODO draws the
  confident-target-vs-decoy *distribution*; these scalars annotate it (AUROC/d on the confident-pool cut
  is the honest univariate number, undiluted by false targets).

### 3. Feature correlation + grouped contribution
Accumulate the feature-feature correlation matrix over the standardized population (target-side, or
pooled), cluster it to surface **covarying groups**, and report the **summed** percent-contribution per
cluster. Reading a covarying set's *total* share as one number fixes the SVM-spreading blind spot: the
group can be shown to matter even when no member does individually. Optionally a scalar **VIF** per
feature (`1/(1 - R_j^2)` from regressing each feature on the rest) as a collinearity score.
- **Cost**: one `O(n * p^2)` accumulation pass for the `p x p` covariance (p ~ 21 -> cheap), gated on the
  flag; production path untouched. VIF is a `p x p` matrix inversion (trivial at this p).
- **Surfacing**: a correlation heatmap card + a "grouped contribution" view (features bracketed by
  cluster with a per-cluster subtotal). New "Feature analysis" section/tab, or an expansion of the Model
  tab.

## Explicitly out of scope (routed elsewhere / deferred)
- **Permutation importance** (shuffle a feature, no retrain, measure ID/FDP degradation) -> add to
  [[TODO-osprey_model_diagnostics_training_pool_distributions]] per Brendan.
- **Leave-one-out / true ablation** (drop feature, RETRAIN, measure Delta-IDs at 1% q) -- the gold
  standard, but `features x folds` retrains is expensive and off the mainline. Defer to a separate
  opt-in flag / offline tool; the three analyses above are the no-retrain substitutes that cover most of
  the interpretive need.

## Design constraints
- **Diagnostics-only**: all of this is gated on `--model-diagnostics` (and/or `--verbose` for the table
  columns); the production scoring path pays nothing and `regression.ps1` stays byte-identical.
- **Data resident at Stage 5**: fold weights (analysis 1) and standardized features + per-feature
  histograms (analyses 2/3) are already in hand where `FeatureContributions.Accumulator` runs. The only
  new accumulation is the per-feature sum-of-squares (Cohen's d) and the `p x p` covariance (correlation
  / VIF) -- both flag-gated.
- **Applies to both passes**: pass-1 and pass-2 models (the Pass 1/Pass 2 switch from #4413), so the
  columns/cards must live in the per-pass bundle, not top-level only.
- **Framing discipline**: keep the "sanity check vs importance" line the table already draws. Label
  clearly which columns *describe the equation* (share, coefficient, fold spread) vs which *measure
  importance/redundancy* (AUROC, d, grouped share, VIF).

## Validation
- Entrapment / decoy oracle: a feature the analyses call redundant should, when dropped (spot-check via
  the deferred ablation tool), not move the entrapment FDP or ID count at 1% q. A feature with high
  univariate AUROC but near-zero joint share should have a covarying partner carrying it (visible in the
  correlation cluster) -- the analyses should agree.
- Unit tests in `ModelDiagnosticsDataTest` for each new scalar on a synthetic model with a known
  covarying pair (build two correlated features + one independent, assert: SVM spreads the pair, the
  correlation cluster groups them, grouped share ~= sum, fold-stability flags the unstable member).

## Why it is worth doing
It converts Mike's objection into features: the report stops *only* describing the trained equation and
starts answering "which features actually carry the separation, and which are redundant?" -- with cheap,
no-retrain diagnostics that exploit Percolator's cross-validation, and that make the covariance behavior
(the real source of the "percent-contribution is invalid" folklore) visible rather than hidden.
