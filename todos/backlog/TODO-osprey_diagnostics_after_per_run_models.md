# Model diagnostics after per-run first-pass models, with a smaller stub

**Status**: Backlog. Written 2026-11-25, split from
[TODO-20261124_osprey_per_run_model_logging_and_diagnostics.md](../active/TODO-20261124_osprey_per_run_model_logging_and_diagnostics.md)
(whose part 1, the PerFileScoring logging gaps, is its own quick PR). One branch from master, one PR.
**Module**: `osprey`
**Related**: #4950, [#5070](https://github.com/ProteoWizard/pwiz/pull/5070) (per-run first-pass models),
[TODO-osprey_scores_parquet_reduction.md](TODO-osprey_scores_parquet_reduction.md) - folded into this work
(Brendan, 2026-11-25): move it to active together with this one and treat it as part 3 below.

Three changes that decide together what `--model-diagnostics` can show:

## Decisions (Brendan, 2026-11-25)

- **Full diagnostics depend on flags given at the start of the run.** The old rule that
  `--task ModelDiagnostics` produces the full report after any completed run, whatever the user chose
  (doc 00, P16), is dropped or already was. Per-feature views (histograms, mean gaps) require
  `--keep-scores-parquet`, whose `<stem>.features.parquet` checkpoint is their only source. A view the
  run's flags did not keep gets a note naming the flag. Revise P16 in
  `pwiz_tools/Osprey/docs/00-pipeline-architecture.md` to say so.
- **The per-feature coefficient and percent-of-separation table is a linear-model view.** It applies to
  SVM and LDA, not to GBDT or NN. `PercolatorScorer.BuildForTreeEnsemble` already leaves Coefficient /
  Percent / Composite NaN for trees and keeps only per-feature target-decoy mean gaps and histograms.
- **The per-run shares may require the features checkpoint** rather than a new summary in the run's
  model file (2026-11-24).
- **Help groups**: `--keep-scores-parquet` (now General I/O) and `--fdrbench`, `--fdrbench-per-run`,
  `--fdrbench-pass` (now FDR & Protein Inference) move to Diagnostics & Info beside
  `--model-diagnostics`: they ask for extra diagnostic output. `Osprey/OspreyCommandArgs.cs`
  `GROUP_GENERAL_IO` (~203), `GROUP_FDR` (~509), `GROUP_INFO` (~717). Check whether a test pins the help.

## 1. Per-run Model tab

**Want** (Mike asked for it): a drop-down of runs on the Model tab, each run's own model from
`<stem>.1st-pass.model.json` (`FirstPassModelIO.RunModelPathFor` / `LoadRunModel`). A run scored by its
best single feature (`RunFirstPassModel.FallbackFeature`) says so. An "all runs" summary, since 446 runs
are not browsable one by one.

**Open for Brendan before code**:
- What a tree-model run's view shows: per-feature histograms + mean gaps (needs the checkpoint), or only
  the run's classifier, calibration anchor, safeguard result and fallback note.
- Per-run histograms are ~34 KB per run (60 bins x 2 classes x ~70 features), ~15 MB of JSON at 446 runs:
  every run, or the feature table only.
- Re-reading every run's features parquet in FirstPassFDR costs GBs per SEA-AD run, cold: the price of
  the tab, or its own opt-in.
- Whether the regression's three diagnostics legs add `--keep-scores-parquet`.

**Survey (2026-11-24, code at aa864c3d2e)**:
- `FirstPassFdrTask.ModelViewFromArtifacts` (`Osprey.Tasks/FirstPassFdrTask.cs` ~409) still loads
  `LoadForAnalysis` and every run's `FdrScoresSidecar.ReadFeatureSums(Pass1Path(...))`; it gets null because
  `PerFileScoringTask.WriteStubScores` deletes the Pass1 sidecar. A second caller (~1955) uses in-memory
  `mdiagContributions`.
- `FeatureSums` (`Osprey.Core/FeatureSums.cs`): target/decoy counts, per-feature sums of STANDARDIZED
  vectors, 60-bin histograms over [-5, 7]; built by `FeatureContributions.Accumulator.Add(standardized,
  isDecoy)` / `ToFeatureSums()`. `PercolatorEngine.FirstPassContributionsFromShares(model, shares,
  featureInfos)` -> `PercolatorScorer.ContributionsFromShares`: linear `Accumulator.Build(FoldWeights, ...)`,
  trees `BuildForTreeEnsemble`.
- One run's view is computable from its model file and features checkpoint: standardize each FDR-feature
  row with `runModel.Model.Standardizer`, append `ProteinBestColumn[r]` when the model has the column (as
  `PerFileFirstPassModel` scores), feature infos `ScoringTaskShared.FdrFeatureInfos(config)` +
  `ProteinBestFeature.WithColumnInfo`.
- `ParquetScoreCache.LoadFullFdrEntries` would hold a whole run (~2.5 GB at 4.5M SEA-AD rows); the
  row-group reader `ReadFdrEntryGroup` is private - a public per-row-group streaming read is needed so the
  reduce holds one run's small view at a time (P3).
- Report data: `ModelDiagnosticsData.ModelView` (`From`, `ApplyTo` onto top-level `D.model`,
  `D.featureCount`, ...), serialized by `ModelDiagnosticsHtml.SerializeData`. JS `renderModelTab`,
  `buildFeatureTable`, `buildTreeFeatureTable` in `model-diagnostics-template.html`. The only run drop-down
  today is CAL mode: `D.cal.files` array in input order, `buildCalPickers` / `setCalFile` /
  `renderCalModel` - the pattern to copy. Proposed data: a new `D.runModels = [{file, fallbackFeature,
  view}]`, leaving the top-level fields alone.
- Goldens: `osprey-regression.data/{astral,stellar-libdecoy,stellar-gendecoy-entrap}/diagnostics.tsv` pin
  `featureCount 0` (`Compare-DiagnosticsGolden -NoTrainedModel`, `Regression/DiagnosticsGolden.ps1`); a
  new array keeps them byte-identical. Tests: `SubsetPipelineTest.TestSubsetLibraryDecoysAndReports`,
  `TestSubsetDiagnosticsWithoutReanalysis` / `TestSubsetDiagnosticsAddedLater` (`AssertSameFirstPassProduct`
  deep-compares every pass-1 JSON property), `SubsetPipelineTest.ProteinBest.cs`.

**Done when**: the 3-file diagnostics datasets show a working per-run Model tab; `diagnostics.tsv`
unchanged or re-recorded with an explained diff; a SubsetPipelineTest asserts one model view per run and
the fallback note.

## 2. Help groups

As in Decisions. Done when `--help` lists the four arguments under Diagnostics & Info.

## 3. Smaller stub

See [TODO-osprey_scores_parquet_reduction.md](TODO-osprey_scores_parquet_reduction.md). Its "keep every
diagnostic exact" plan keeps `entry_id` + `score` for every row and a peak location for every row, which
keeps the accumulator, FDRBench pass 1 and peak co-assignment exact; the stub then carries no features, so
per-feature views come only from the features checkpoint (as decided above). Settle its open questions
first - they decide what the stub can drop.
