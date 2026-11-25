# Per-run first-pass models: PerFileScoring logging gaps and a per-run Model tab

**Status**: Backlog. Written 2026-11-24, right after #5070 merged.
**Module**: `osprey`
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

## 2. Per-run Model tab in the `--model-diagnostics` HTML

**What**: the Model tab showed the one experiment-wide first-pass model (feature weights / contributions).
Since #5070 there is no experiment-wide model: `FirstPassFdrTask.ModelViewFromArtifacts`
(`Osprey.Tasks/FirstPassFdrTask.cs` ~409) loads `FirstPassModelIO.LoadForAnalysis`, finds no analysis-wide
`model.json`, returns null, and the tab shows only its explanatory note. Its feature shares also came from the
per-run `.1st-pass.fdr_scores.bin` sidecars, which #5070 no longer writes.

**Want** (Mike asked for this): a drop-down of runs on the Model tab, showing each run's own model, the same
way other per-file views in the report already use a run drop-down. Each run's model, calibration map and
safeguard choice are in `<stem>.1st-pass.model.json` (`FirstPassModelIO.RunModelPathFor`); a run scored by its
best single feature (the safeguard's fallback, `FallbackFeature` in that file) should say so rather than show
a model. Worth an "all runs" summary too (e.g. the spread of each feature's contribution across runs), since
per-run views of 446 runs are not browsable one by one.

**Constraints**: the report is built by a reduce (FirstPassFDR / SecondPassFDR) from per-run artifacts, so the
per-run model views must come from what each run already writes (doc 00's P3 corollaries and P16), streamed
run by run, not by holding every run's model at once. Where the feature sums for contributions come from now
that the sidecars are gone has to be settled: the stub parquet does not carry features; either PerFileScoring
records each run's contribution summary in its model file, or the tab shows weights without shares.
Code: `Osprey.FDR/ModelDiagnostics/ModelDiagnosticsData.ModelView.cs` (`ModelView.From`),
`Osprey.Tasks/ModelDiagnostics/ModelDiagnosticsReport.cs`, `ModelDiagnosticsHtml.cs`,
`model-diagnostics-template.html`, `PercolatorEngine.FirstPassContributionsFromShares`.

**Done when**: the 3-file regression datasets with `--model-diagnostics` (StellarLibDecoy, StellarGenDecoyEntrap,
Astral) show a working per-run Model tab; the diagnostics goldens in `osprey-regression.data/*/diagnostics.tsv`
are unchanged or re-recorded with an explained diff; a SubsetPipelineTest asserts the report carries one model
view per run (and the fallback note for a run that fell back).

## Suggested order

1 first (small, self-contained), then 2. Either can be its own PR.
