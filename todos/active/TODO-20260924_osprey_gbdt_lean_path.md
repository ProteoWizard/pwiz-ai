# TODO-20260924_osprey_gbdt_lean_path.md

## Branch Information
- **Branch**: `Skyline/work/20260924_osprey_gbdt_lean_path`
- **Base**: `Skyline/work/20260612_net8_port` (899f348f3d)
- **Created**: 2026-09-24
- **Status**: In Progress
- **GitHub Issue**: [#4491](https://github.com/ProteoWizard/pwiz/issues/4491) and
  [#4543](https://github.com/ProteoWizard/pwiz/issues/4543) (one PR, per #4543's Sequencing; developer decision
  2026-09-25)
- **Module**: `osprey`
- **PR**: (pending)
- **Worktree**: `D:\Dev\pwiz-osprey-gbdt`

## Objective

`--fdr-method gbdt` on the default first-pass path trained the linear SVM instead of gradient-boosted
trees (since #4446). Filed by Brendan as #4491 (2026-08); he folded it into #4543 (demote `--fdr-method` to
an env var) on an unpushed branch, and on 2026-09-18 marked it parked. Rediscovered by `/code-review max` on
#4703; the developer asked for its own branch. COORDINATE with Brendan before opening a PR: this branch fixes
both defects his #4491 comment names (the dropped config and the missing tree scoring on the streaming path).

**Scope widened 2026-09-25:** the developer chose Brendan's recommendation in #4543, so the #4543
cleanup ships in this branch too:
- remove `--fdr-method`;
- select trees with `OSPREY_FDR_MODEL=gbdt`, failing on an unrecognized value;
- delete `simple` (and the unreachable `Mokapot`) together with the `non-percolator-fdr` resident token;
- mark gbdt Experimental in doc 07.

The wider command-argument audit stays follow-up. The starting-work note on #4543 states gbdt's purpose:
it is not expected to help with the current (SVM-chosen) features, and exists for future features that
do not suit a linear SVM.

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

## Review fixes (commit `44c2c4e261`, from `/code-review max`; 9 fixed, 6 skipped)

- A trained model is persisted whenever it was not adopted from disk (a retrain replaced nothing before, so
  Stage 6 and distributed SecondPassFDR could score with a stale model of the other classifier).
- `PercolatorEngine.GbdtValidityKeySuffix`: a gbdt-only term (method, every `GbtParams` value, iterations,
  inner folds), empty for percolator, on the FirstPassFDR, PerFileRescoring and SecondPassFDR keys.
- The classifier refusal runs before the Pass 0 ingest with a corrected message; the compaction gate
  declines a model of the other classifier (`CompactionGateRefusals`).
- Model diagnostics under trees: distributions kept, contribution table marked not applicable
  (`FeatureContributions.BuildForTreeEnsemble`, `ModelIsTreeEnsemble`).
- The model is serialized once per run; `LoadFromAny` parses one copy; `Save` validates what `Load` does.
- Tests: non-monotone fixture with `MaxTrainSize = 60`, a serial `ScoreSingle` oracle, resumed-file and
  per-file-flush cases. Docs 00/07/12/14 corrected, including the in-sample scoring note.
- Skipped: the #4706 race and batch `FrozenModelScorer` scoring (Brendan's), the fold-reduction dedup,
  score-source consolidation and `CloneForTrainOnly` altitude refactors, and in-sample tree scoring,
  which waits on the entrapment measurement below.
- Percolator unchanged: a fixture dump of every percolator output and key is byte-identical before and
  after (`ai/.tmp/sessions/20260925-gbdtfix/dump-base.txt`, `dump-new.txt`).

## Gates

- [x] `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection` (602 tests, 0 inspection warnings)
- [x] `regression.ps1 -Dataset Stellar` on `46a79a4ba6`: PASSED
- [x] `/code-review max` (findings above)
- [x] `regression.ps1 -Dataset Stellar -NoBuild` on `44c2c4e261`: PASSED, all phases (build Release with
  `Build-Osprey.ps1` first; the script's own build uses VS 2022 MSBuild, which cannot build .NET 10)
- [x] Entrapment comparison, gbdt vs percolator on StellarGenDecoyEntrap (below; posted on #4491)
- [x] Brendan's answer on #4491: his #4543 Sequencing says one PR; the developer chose that (2026-09-25)
- [x] `regression.ps1 -Dataset All -NoBuild` on `44c2c4e261`/`cbf8289404`: PASSED, 43 phases, 2.5 h
  (`D:\test\osprey-runs\gbdt-fix-44c2c4e\regression-all.log`)
- [x] #4543 cleanup committed as `939ff0bb44` (Debug gate: 603 tests, 0 inspection warnings; all 36 SVM key
  lines byte-identical before and after)
- [ ] `regression.ps1 -Dataset All -NoBuild` on `939ff0bb44` (`D:\test\osprey-runs\gbdt-4543-939ff0b\regression-all.log`)
- [ ] gbdt through `OSPREY_FDR_MODEL=gbdt` gives the same results as the `--fdr-method gbdt` run
  (`D:\test\osprey-runs\gbdt-4543-939ff0b\entrap\gbdt`)
- [ ] Push; open the PR against the port branch (`osprey:` prefix, label `osprey`, closes #4491 and #4543)

## Entrapment result (2026-09-25, build `44c2c4e261`)

StellarGenDecoyEntrap command line, once per `--fdr-method`. Script:
`ai/.tmp/sessions/20260923-carafesharp/run-gbdt-entrap.ps1`. Output: `D:\test\osprey-runs\gbdt-fix-44c2c4e\entrap`
(`fdp-comparison.csv`, and a `model-diagnostics.html` for each arm).

| True FDP at reported q 1% (accepted) | percolator | gbdt |
|---|---|---|
| Pass 1, experiment | 1.24% (28,691) | 1.65% (28,589) |
| Pass 1, run | 2.43% (30,847) | 3.19% (30,442) |
| Pass 2, experiment | 0.95% (29,742) | 1.27% (31,404) |
| Pass 2, run | 1.43% (33,399) | 1.95% (33,542) |

- **Where gbdt is worse:** everywhere in pass 2, and in every other view from q 0.5% to 5%. The one
  exception is pass-1 experiment at q 5% (5.39% vs 6.22%).
- **Matched true FDP:** at gbdt's 1.27%, percolator accepts about 32,000 targets (interpolated), against
  gbdt's 31,404.
- **Decoy exchangeability:** paired-win fraction 0.464 vs 0.471; null tilt 0.52 vs 0.38.
- **Sanity bounds:** both arms pass them.
- **What this is:** a baseline, not a blocker (developer, 2026-09-25). gbdt exists to evaluate candidate
  features that do not suit the linear SVM (some were removed for that reason); the default feature set
  was chosen for the SVM, so the default stays percolator. Held-out scoring of subset rows is a possible
  later experiment, not a requirement for this branch.

## Scope of this branch (developer, 2026-09-25)

1. gbdt must not break the current regression tests. They run percolator: Stellar PASSED on `44c2c4e261`;
   `-Dataset All` is the remaining gate.
2. gbdt itself must keep working, because MARS (`maccoss/mars`) uses it.

## MARS dependency

- MARS vendors two files from `Osprey.ML`: `GradientBoostedTrees.cs` verbatim and the `XorShift64` class
  from `LinearSvmClassifier.cs` (`dotnet/third_party/Osprey.ML`, SHA-256 drift guard in `UPSTREAM.json`,
  re-synced by `dotnet/scripts/sync-osprey-ml.ps1`). This branch touches neither file, and nothing in
  `Osprey.ML`.
- MARS main vendors `6efbc3ea5d`, the #4595 PR branch before its squash. What landed (`cec7ee38d9`, on the
  port branch only, not master) adds a private `TreeWorkspace` refactor and a `LeafValue` guard for
  `h + RegLambda <= 0`. No public API changed; MARS uses squared error with `RegLambda` 1.0 by default, so its
  output is unchanged unless a user sets `reg_lambda` 0. Optional MARS re-sync picks up the guard.
- Master still has the #4446 `GradientBoostedTrees.cs` without the squared-error objective MARS needs;
  that arrives when the port branch merges.
- MARS tests were not run here: the pwiz hook blocks direct `dotnet test` and there is no MARS wrapper.

## Found while fixing (not in this branch)

- `FrozenModelScorer.Score` writes a shared `_scratch` buffer, and one scorer is shared across Stage 6's
  parallel file loop (`PerFileRescoreTask.cs:~930/981/1561`, `Pass2FdrSidecar.cs:2771`). Only with
  `--parallel-files` (the default is sequential). Silent, timing-dependent score corruption. Filed as #4706 and left to Brendan (he owns the `--parallel-files` work). Evidence posted there: a stress test
  corrupts 49% of concurrent scores at 2 threads; two real 3-file Stellar Stage 6 runs at `--parallel-files 3` were
  byte-identical to sequential (the per-file scoring loops are milliseconds long and did not overlap).
- `07-fdr-control.md:~586` still says production scores are normalized "(3g)"; no production path runs 3g.
