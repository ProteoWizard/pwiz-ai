# TODO-20261124_osprey_per_run_model_logging_and_diagnostics.md

Per-run first-pass models: PerFileScoring logging gaps and a per-run Model tab

## Branch Information
- **Branch**: `Skyline/work/20261124_osprey_per_run_model_logging`
- **Base**: `master`
- **Created**: 2026-11-24
- **Status**: Completed (part 2 continues in TODO-20261125_osprey_diagnostics_after_per_run_models.md)
- **Module**: `osprey`
- **PR**: [#5077](https://github.com/ProteoWizard/pwiz/pull/5077) (merged 2026-11-26)

Written 2026-11-24, right after #5070 merged.
**Related**: [#5070](https://github.com/ProteoWizard/pwiz/pull/5070) (merged as aa864c3d2e: per-run
first-pass models trained in PerFileScoring), its TODO
[TODO-20261121_osprey_per_file_fdr.md](../completed/2026/11/TODO-20261121_osprey_per_file_fdr.md).

Two small follow-ups to #5070. Both are about what the user sees, not about results: the blib and every
golden must stay byte-identical.

## 1. Long logging gaps in PerFileScoring

**What**: since #5070, each run's PerFileScoring trains its own first-pass model (two-round gbdt with the
protein-best column, out of fold, then calibration and the best-single-feature safeguard) after
extraction finishes, and that training logs nothing until it is done. With `--parallel-files` the runs in
a wave finish extraction together, so the log stops for minutes and reads as a hung run.

**Evidence** (SEA-AD 82 files, 3 at a time, `D:\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-defaultfullperrun\run.log`;
`python ai/scripts/perfviz.py <run.log> --files 82`, output in `ai/.tmp/sessions/20261123-night/seaad/perfviz.txt`
while it exists): 10 reporting gaps of 30 s or more, the five largest 121-178 s in the first hour, each right
after `[n] 92%  [n+1] 92%  [n+2] 9x%` (the wave's extraction progress), i.e. during training. Master's run
of the same data had a largest gap of 42 s. The plot (`seaad/pr5070.png`) shows them as spikes in the lower pane.

**Fix direction**: progress from inside the per-run training, on the same cadence and form as the rest of
PerFileScoring's progress (`[n] %` lines via the existing progress reporter, not a new log format). Natural
points: round 1 / round 2 of the two-round training, each fold, the gbdt iteration count, calibration and the
safeguard decision (the safeguard already logs one `[COUNT]` line per run at the end). Where:
`Osprey.FDR/PerFileFirstPassModel.cs` (`TrainAndScore`), `PercolatorEngine` / the gbdt trainer it calls,
and `Osprey.Tasks/PerFileScoringTask.cs` (`TrainOwnModelFromEntries`, `ScoreWithOwnModel`).

**Done when**: perfviz on an 82-file SEA-AD run (or a cheaper 12-file run, `Run-SeaAd.ps1 -NumFiles 12`)
shows no reporting gap over 30 s inside PerFileScoring; output unchanged (`regression-parallel.ps1 -Dataset All`
49 PASS / 0 FAIL / 0 SKIP against the current goldens).

### Part 1 progress (2026-11-24)

Committed as 3ae9253249 (built, 681/681 tests, inspection clean):
- `Osprey.FDR/TrainingProgress.cs` (new): the per-run training's percent, step slices sized by
  SEA-AD wall time (round 1 0-35, round-1 scoring + protein-best column 35-45, round 2 45-85,
  out-of-fold scoring 85-93, safeguard 93-98, calibration 98-100). A fold's fraction is
  iterations done / (done + fewest still to come under the patience rule), so each ~7 s
  gbdt iteration moves the percent; the loops stop on convergence, so i / MaxIterations (30)
  would barely move.
- `PercolatorConfig.TrainingProgress` (internal, null except on the per-run model's own clone;
  copied by `CloneForTrainOnly`). `PercolatorTrainer.TrainProgressReporter.ReportConvergence`
  is called from both fold loops (SVM patience 2 is now `SVM_PATIENCE`);
  `TrainWithScorePrefilter` opens round_1_scoring and round_2.
- `PerFileFirstPassModel.TrainAndScore` runs under a `ProgressReporter` with a new heading
  resource; single-round training now clones the shared config too, so it can carry progress.
- `PerFileScoringTask`: segments now read 2, calibrate 6, score 60, features checkpoint 4,
  own model 24, stub write 4; the resume-from-features path opens the model segment directly
  through a new `MultiProgressReporter.FileScope.BeginSegment(int)` (CommonUtil; the
  no-argument form now delegates to it, unchanged behavior).
- `MultiProgressReporterTest.TestMultiProgressReporterWeightedSegments` extended: segment skip,
  never-backward, fold-iteration mapping.

Verification in flight: 12-file SEA-AD `-Task PerFileScoring -ParallelFiles -1`, split-sized
library, exe snapshot `D:\test\osprey-runs\_bin\perrunlog-wip`, out dir
`D:\test\osprey-runs\sea-ad\runs\seaad-12files-libdecoy-r1.0-defaultperrunlog-20261124_*`.
Then `regression-parallel.ps1 -Dataset All`.

**SEA-AD 12-file result** (`...defaultperrunlog-20261124_182802\run.log`, perfviz output in
`ai/.tmp/sessions/20261124-perrun/perfviz-12.txt`): 0 gaps >= 30 s, max 29 s, median 6 s,
PerFileScoring 38:25. The 29 s gap is calibration in wave 1 (`[1] 7% -> 8%`), not training.
Largest gap inside training 26 s, in the last wave (2 files): round 2's last iteration plus
out-of-fold scoring (~11 s, reports nothing inside `ScoreRowsWithModel`). Gap list from
`ai/.tmp/sessions/20261124-perrun/gaps.py <log> 18`.

**Regression**: `regression-parallel.ps1 -Dataset All` 49 PASS / 0 FAIL / 0 SKIP in 49:44
(lane logs `pwiz_tools/Osprey/TestResults/regression-lane-{Stellar,StellarGenDecoyEntrap}-20261124_190725.log`).
Part 1 done-when met.

### Code review (/code-review medium, 2026-11-25)

8 findings, no correctness bugs. Fixed in 47417a9bd8 (681/681, inspection clean): training reports
only inside a --parallel-files file scope (sequential log unchanged, which also removed the
heartbeat-shows-units finding); each fold reports done when it returns (early `break` stalled its
share); `BeginSegment(int)` leaves the open segment alone for itself or an earlier one; two comments
corrected. Dropped: one-round step layout jumps 35 -> 85 (only under OSPREY_GBT_PREFILTER_SIZE=0);
hard-coded segment indices (declared beside the weights, with a comment).

## 2. Per-run Model tab - moved (2026-11-25)

Split into its own branch and PR (Brendan, 2026-11-25), together with the scores-parquet reduction and
the help-group move:
[TODO-20261125_osprey_diagnostics_after_per_run_models.md](TODO-20261125_osprey_diagnostics_after_per_run_models.md).
This TODO is part 1 only, one commit (3ae9253249).

### 2026-11-26 - Merged

PR #5077 merged as b1757d1129, right after #5067 (merge onto the new master verified clean). Before merge, the
"Skyline code inspection" check failed with 3 InvalidXmlDocComment warnings in
`pwiz_tools/Shared/CommonUtil/SystemUtil/MultiProgressReporter.cs` (lines 69, 146, 243): the new
`BeginSegment(int)` overload made `<see cref="BeginSegment"/>` ambiguous. Fixed in 179bb71b6c (the references
name `BeginSegment()`), found by a local full Skyline inspection on UW25; all 18 checks then green. Shipped:
progress reporting inside per-run first-pass training, and `FileScope.BeginSegment(int)`. Part 2 (diagnostics
after per-run models) continues in its own TODO.
