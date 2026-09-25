# TODO-20260924_osprey_gbdt_lean_path.md

## Branch Information
- **Branch**: `Skyline/work/20260924_osprey_gbdt_lean_path`
- **Base**: `Skyline/work/20260612_net8_port` (899f348f3d)
- **Created**: 2026-09-24
- **Status**: In Progress
- **GitHub Issue**: [#4491](https://github.com/ProteoWizard/pwiz/issues/4491)
- **Module**: `osprey`
- **PR**: (pending)
- **Worktree**: `D:\Dev\pwiz-osprey-gbdt`

## Objective

`--fdr-method gbdt` on the default first-pass path trained the linear SVM instead of gradient-boosted
trees (since #4446). Filed by Brendan as #4491 (2026-08); he folded it into #4543 (demote `--fdr-method` to
an env var) on an unpushed branch, and on 2026-09-18 marked it parked. Rediscovered by `/code-review max` on
#4703; the developer asked for its own branch. COORDINATE with Brendan before opening a PR: this branch fixes
both defects his #4491 comment names (the dropped config and the missing tree scoring on the streaming path).

## Root cause

- `PerFileScoringTask.CanUseLeanProjection` is true for gbdt (`UsesPercolatorFramework()` includes it), so
  the default run takes `RunFirstPassStreaming` -> `PercolatorScorer.RunStreamingFirstPass`.
- That path rebuilt the training config by hand without `UseGradientBoostedTrees` / `GbtParams` / `NThreads`,
  so `PercolatorTrainer` trained an SVM (with the GBDT iteration cap), and its score passes averaged linear
  fold weights only.

## Change (commit `46a79a4ba6`)

- Streaming first pass trains with `CloneForTrainOnly()` and scores trees (`ResolveGbtModels`, shared
  `ScoreRowsGbt`); the feature-contribution report is skipped for trees, as on the projection path.
- Resuming with a persisted model of the other classifier stops with an error.
- `FirstPassModelIO` saves and reloads tree ensembles (a linear model file is byte-identical: the new field is
  omitted when empty).
- `transfer` pass-2 mode scores through `FrozenModelScorer` (it averaged fold weights itself and would throw on
  trees).
- Tests: `FdrTest.TestStreamingFirstPassTrainsGbdt` (failed before the fix), `FirstPassModelIoTest` tree round
  trip, `Pass2FdrSidecarTest.TestTransferOneFileScoresTreeModel`.

## Gates

- [x] `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection` (601 tests, 0 inspection warnings)
- [x] `regression.ps1 -Dataset Stellar` (percolator output unchanged against the branch's goldens): PASSED
- [ ] `/code-review` before the PR
- [ ] `regression.ps1 -Dataset All`

## Found while fixing (not in this branch)

- The FDR method and `OSPREY_GBT_*` are in no task validity key, so re-running a directory under a different
  `--fdr-method` can adopt the other method's results; a gbdt directory made before this fix holds SVM results.
- `FrozenModelScorer.Score` writes a shared `_scratch` buffer, and one scorer is shared across Stage 6's
  parallel file loop (`PerFileRescoreTask.cs:~930/981/1561`, `Pass2FdrSidecar.cs:2771`). Only with
  `--parallel-files` (the default is sequential). Silent, timing-dependent score corruption. Filed as #4706; awaiting the
  developer's go-ahead for its own branch.
- Step 6 of `07-fdr-control.md` still describes a removed second-pass retrain.
