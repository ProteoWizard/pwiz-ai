# TODO: Osprey --model-diagnostics — per-feature "training-pool" (max-separation) distributions

**Status**: Backlog — **night-ready as PR 1 (second priority)** in
  `ai/.tmp/handoff-20260708-osprey-model-diagnostics-two-prs.md` (Storey null-alignment PR 2
  goes first). Decided scope: Option A (second binning pass after q), final-model global
  q≤TrainFdr, full set shown ghosted. Diagnostics-only (regression golden unchanged).
**Priority**: Medium (high interpretive value; enhances the just-shipped per-feature distributions)
**Created**: 2026-07-06
**Requested by**: Brendan
**Scope**: `pwiz_tools\Osprey\Osprey.FDR\FeatureContributions.cs`, `PercolatorFdr.cs`
  (the iterative SVM training loop), `Osprey.FDR\ModelDiagnostics\ModelDiagnosticsData.cs`,
  `Osprey.Tasks\ModelDiagnostics\model-diagnostics-template.html`
**Related**: builds on the per-feature score distributions in PR #4377
  ([[TODO-20260705_osprey_model_diagnostics]]).

## Why this exists — the two-target-distributions problem

On the Model tab, clicking a feature shows its standardized target-vs-decoy
distribution (the mProphet "Feature Scores" view). It is often hard to SEE the
separation a feature provides, because the **target population is, by definition,
a mixture of two sub-distributions**:
1. **False targets** — decoy-like; they should and do overlap the decoys.
2. **True targets** — the peptides we are actually trying to separate from the null.

The false-target sub-population piles on top of the decoys and blurs the picture,
so a genuinely discriminating feature can look weak on the full target set.

## The idea — plot only the peptides the NEXT training cycle would use

Semi-supervised model training (Osprey's Percolator SVM; mProphet's LDA) is
**iterative**: each cycle (a) scores all PSMs with the current model, (b) selects
**high-confidence targets** (q <= `TrainFdr`, default 0.01) as positives + **all
decoys** as negatives, (c) trains, (d) re-scores; it loops until it either hits
`MaxIterations` (default 10) or **converges** (the confident-target set stops
growing). `PercolatorResults.IterationsPerFold` already records which of the two
stopped each fold.

Proposal: for each feature, add a **"training pool" / "max separation" view** — the
standardized distribution of ONLY the peptides that WOULD form the next training
cycle if there were one: **{targets with q <= TrainFdr} vs {decoys}**. Because the
loop has converged (or maxed out), this is the maximum-separation state the model
reached. It approximately isolates the *true* targets, so the per-feature
separation the SVM actually exploits becomes visible, undiluted by the false
targets.

Present as a toggle on the per-feature (and optionally the composite) distribution:
"all peptides" <-> "training pool (confident targets vs decoys)". Applies to both
the pass-1 and pass-2 models (PR #4377 added the 2nd-pass model view).

## Feasibility + implementation sketch (achievable)

The per-feature histograms already exist (`FeatureContributions.Accumulator`,
gated on `--model-diagnostics`). The new view needs a THIRD population binned:
confident targets (q <= TrainFdr) + decoys.

- **The wrinkle (worth calling out):** the current histograms are binned *during*
  the scoring pass in `ScorePopulationAndComputeFdr`, where `finalScores[i]` exists
  but the **q-value does not yet** (q needs the full score array + target-decoy
  competition). The confident-target subset is a function of q, so it can't be
  selected in that same loop.
  - **Option A (simplest):** after q-values are computed, do a second pass over the
    entries binning only `!isDecoy && q <= TrainFdr` (plus all decoys) into a
    parallel per-feature histogram set. One extra O(n * nFeatures) pass, gated on
    the flag; production path untouched.
  - **Option B:** defer ALL histogram binning to after q is known (removes the
    current single-pass coupling), then bin both the full set and the confident
    subset together.
- **Which q / which model:** use the FINAL averaged model's best-per-precursor q at
  `TrainFdr`, matching the "next cycle on the full population" framing. Note in the
  UI that CV training selected positives per-fold; this diagnostic uses the final
  model's global selection (a deliberate, explainable choice).
- **Data model:** add optional `TargetHistTrain` / (decoys unchanged) per
  `FeatureRow`, or a parallel edges+counts set on `ModelPass`. Reuse `HistEdges()`
  (same standardized bins) so the two views share an x-axis and overlay cleanly.
- **HTML:** a small toggle in the feature-distribution card; `drawFeatureSvg` /
  `featureHist` already parameterized enough to swap the count arrays. Could also
  show both as an overlay (full = faint, training pool = solid) to make the
  "which targets dropped out" visually obvious.
- **Composite too (optional):** the same confident-targets-vs-decoys cut on the
  composite score is the cleanest picture of the model's achieved separation, and a
  natural companion to the decoy-normal overlay already there.

## Open questions / design decisions
- Confident-target selection: q <= TrainFdr on the final model (proposed) vs
  reconstructing the exact last-iteration per-fold positive set (more faithful to
  "the next cycle" but CV-fold-specific and harder to explain). Lean to the former.
- Should the "unknown"/below-threshold targets be shown ghosted (to see what was
  excluded) or hidden entirely? A toggle or an overlay likely reads best.
- Interaction with the entrapment classes (P/Pd): keep them out of the training-pool
  view (training is target-vs-decoy) or show entrapment as a reference overlay.
- Does exposing `IterationsPerFold` (converged vs hit-max, per fold) next to this
  view help the reader trust "this is the maximum separation reached"? Probably a
  one-line caption: "converged after N iterations" vs "stopped at the 10-iteration cap".

## Companion: permutation importance (added 2026-07-13)
Pair the per-feature *distribution* view with a per-feature **permutation importance** scalar: shuffle
one feature's values across entries (breaking its association with class), **re-score with the frozen
model (no retrain)**, and measure the degradation — drop in accepted targets at 1% q, and/or rise in the
entrapment FDP. It is the cheap, model-agnostic substitute for leave-one-out ablation (no `features x
folds` retrains), and it answers the "would we lose IDs without this feature?" question the
percent-contribution table deliberately does **not**. Caveat to note in the UI: under collinearity,
permuting one of a covarying pair understates its importance (the partner still carries the signal) —
so read it alongside the correlation/grouped view in
[[TODO-osprey_model_diagnostics_feature_importance]]. Cheap (one rescore pass per feature over the
resident standardized matrix, flag-gated); surfaces as a column next to the training-pool separation.
Routed here (rather than the importance/redundancy TODO) because it is the natural scalar companion to
this per-feature distribution view. See [[TODO-osprey_model_diagnostics_feature_importance]] for the
fold-stability / univariate-AUROC / correlation-grouping analyses.

## Why it is worth doing
It gets *inside* the semi-supervised separation the model achieves — turning "the
model works" into "here is exactly how well each individual score separates the
peptides the model trusts," which is squarely in the spirit of the transparency the
--model-diagnostics report is for.
