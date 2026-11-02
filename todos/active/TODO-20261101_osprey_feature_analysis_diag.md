# TODO-20261101_osprey_feature_analysis_diag.md

## Branch Information
- **Branch**: `Skyline/work/20261101_osprey_feature_analysis_diag`
- **Base**: `master`
- **Created**: 2026-11-01
- **Status**: In Review. DECISION FOR BRENDAN: the training-set analysis runs on EVERY run,
  not only under `--model-diagnostics` (P16, see Decision 1). Measured cost on the 3-file Stellar
  regression: `[TIMING] Percolator training-set analysis: 0.8s` (300,000-row subset, 21 features,
  linear SVM) against `Percolator train all folds (parallel): 106.5s`. To gate it on the flag
  instead, set `CollectTrainingAnalysis = config.ModelDiagnostics` in
  `PercolatorEngine.BuildPercolatorConfig`, and accept that the pay-later report then lacks the
  training-set views (`TestSubsetDiagnosticsAddedLater` would need those keys exempted).
- **GitHub Issue**: [#4550](https://github.com/ProteoWizard/pwiz/issues/4550), [#4467](https://github.com/ProteoWizard/pwiz/issues/4467)
- **Module**: `osprey`
- **PR**: (pending)
- **Worktree**: `D:\Dev\pwiz-featdiag` (overnight agent worktree of `C:\proj\pwiz`)

## Objective

Feature analysis in the `--model-diagnostics` report, built for valuing candidate score
calculators one feature at a time (see TODO-20261030_osprey_scoring_library.md):

- #4550 training transparency: per-feature AUROC and distributions on the FINAL TRAINING SET
  (per fold, the positives + decoys the returned fold model was trained on), per-feature and
  composite ROC on a log-FPR axis, in-sample vs held-out composite overlay, fold-to-fold
  weight stability.
- #4467 feature analysis: Cohen's d, permutation importance (no retrain), feature
  correlation with grouping at a stated threshold, grouped contribution and grouped
  permutation importance.

## Tasks

- [x] Capture each fold's final training set in `PercolatorTrainer`
- [x] `TrainingSetAnalysis` (Osprey.FDR): AUROC, Cohen's d, TPR at 1% FPR, ROC curves,
      composite ROC (training / in-sample / held-out), permutation importance, correlation +
      groups
- [x] Fold weight stability on `FeatureContributions`
- [x] Persist the analysis in `.1st-pass.model.json` (P16)
- [x] Diagnostics JSON: additive keys on `FeatureRow`, top-level `trainingSet`, `ModelPass.trainingSet`
- [x] HTML: table columns, training-set overlay on the feature distribution, ROC card,
      correlation/groups card, cross-references
- [x] Docs: 07-fdr-control.md feature-contribution section, 14-intermediate-files.md
- [x] Unit tests (metric math) + SubsetPipelineTest assertion
- [x] Gates: Build-Osprey -RunTests -RunInspection; regression Stellar + StellarLibDecoy
- [x] Review (fresh agent)
- [ ] PR

## Decisions

1. **Computed on every run, not gated on `--model-diagnostics`** (deviates from the issue
   text and the agent brief; Brendan may revisit - see Status). Doc 00 P16 requires the
   pay-later report (analysis run without the flag, report added later) to equal the
   flag-up-front report, and `SubsetPipelineTest.TestSubsetDiagnosticsAddedLater` byte-compares
   the pass-1 product with "no view exempt". The per-fold training sets exist only inside
   `PercolatorTrainer`, so a flag-gated capture would make the report's training-set views
   impossible to produce later. So the trainer computes the (small) analysis on every run and
   persists it in `.1st-pass.model.json` (optional additive key, like `ExperimentAgg`). Same
   precedent as the per-run `FeatureSums` histograms. Scores, q-values and the blib are
   untouched (regression goldens pass). Switch: `CollectTrainingAnalysis`.
2. **"Final training set"** = per fold, the positives + decoys that the fold's RETURNED
   (best-iteration) model was trained on (trees: inner fit rows). Per-feature values pool the
   folds (a row in two folds counts twice); per-fold AUROC range shown alongside. Answers the
   issue's "per fold or unioned" by doing both: pooled scalar, per-fold spread.
3. **Composite ROC**: three fold-averaged curves - final training set (in-sample), all fit-row
   targets vs decoys in-sample, and the same held-out. In-sample/held-out use all targets vs
   decoys, not a score-selected positive set, so the overfitting readout is not circular. On
   Stellar the all-targets AUROC is ~0.55 because most library targets are absent; the card says
   to read the gap, not the level.
4. **AUROC vs pAUC**: full AUROC plus TPR at 1% FPR (the low-FPR corner) and the log-FPR
   curve; curves computed exactly from sorted values (not the 60-bin histograms).
5. **Permutation importance**: held-out rows (each subset row scored by the fold model it was
   held out of), metric = targets passing the training FDR under paired competition, per fold
   then summed; one fixed-seed shuffle per feature per fold; frozen models. Bounded by
   `MaxTrainSize`; for trees additionally capped at ~50,000 held-out rows per fold, thinned by
   whole target-decoy pairs (`TREE_PERMUTATION_ROW_CAP`), since a tree re-score is costly.
6. **Correlation**: Pearson over the training subset (each row once), single-linkage groups at
   |r| >= 0.8; grouped contribution = summed percent share; grouped permutation = joint
   shuffle with one shared row order.
7. **Cohen's d included** (the brief asks for it; #4550 had dropped it as redundant with the
   standardized mean gap). Cheap, one column.
8. **Pass 2**: production trains no pass-2 model (#4484), so the new cards show a pass-2 n/a
   note; the per-pass shape (`ModelPass.TrainingSet`) is in place.

### Not done (remains on #4467)
- Leave-one-out / retrain ablation (out of scope in the issue itself).
- VIF per feature; single-feature IDs at 1% q.
- Tiered opt-in surface (moot while the analysis is cheap enough to run always).
- GBDT cost of the analysis not measured on full-size data (tree path covered by the subset
  test only); the permutation row cap bounds it.

### Review triage (fresh general-purpose reviewer, medium)
Fixed: (1) tree in-sample curve included the inner iteration-selection rows - now uses the
fold's fit rows (`FoldTrainingSet.FitRows`); (2) `FeatureRow` new fields defaulted to 0 / group 0
on an older pass-1 product - now NaN / -1; (3) tree permutation cost unbounded - row cap;
(4) NaN feature values would stall the AUROC merge - filtered; (5) tree model description lacked
the training-column note, pass-2 n/a message blamed an older build - both fixed; doc wording of
the ROC threshold. Dropped: none.

## Progress Log

### 2026-11-01
- Read #4550, #4467, FeatureContributions, ModelDiagnosticsData, template, doc 00 (P16/P17).
- Implemented `TrainingSetAnalysis` + `FeatureSeparation` (Osprey.FDR), trainer capture,
  model-file persistence, diagnostics keys, HTML (table columns, training overlay, ROC card,
  correlation card), docs 07 and 14, `FeatureAnalysisTest`, SubsetPipelineTest assertion.
- Gates: pre-commit (Debug, tests + inspection) 647/647, 0 warnings
  (`ai/.tmp/sessions/20261101-featdiag/precommit-6.log`). Regression r1 Stellar PASSED and
  StellarLibDecoy PASSED incl. mode1b diagnostics vs golden and mode3 HPC chain
  (`ai/.tmp/sessions/20261101-featdiag/regression-*-r1.log`); r2 on the post-review code
  (`regression-*-r2.log`).
- Rendered the StellarLibDecoy report with the final template in headless Edge: no console
  errors; on Stellar xcorr and SG-weighted xcorr group at r = 0.96, joint permutation drop 99.9%.
- Committed f8641f70e2.
