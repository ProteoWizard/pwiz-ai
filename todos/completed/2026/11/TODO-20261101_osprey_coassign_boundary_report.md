# TODO-20261101_osprey_coassign_boundary_report.md

## Branch Information
- **Branch**: `Skyline/work/20261101_osprey_coassign_boundary_report`
- **Base**: `master`
- **Created**: 2026-11-01
- **Status**: Completed
- **GitHub Issue**: [#4672](https://github.com/ProteoWizard/pwiz/issues/4672)
- **Module**: `osprey`
- **PR**: [#4961](https://github.com/ProteoWizard/pwiz/pull/4961) (merged 2026-11-03)

## Objective

`--model-diagnostics` logged one `coassign-boundary pass=1 run=X cutoff=Y` line per run (446 on
CHS, now `[COUNT]`-tagged behind `--perf-stats`). Keep the experiment line, drop the per-run
lines, and carry the per-run values in the report as a plotted per-run statistic.

## Design

- `CoAssignmentData` gains `RunNames` and `RunCutoffs` (NaN for a run that accepted nothing),
  filled by `CoAssignmentPassBuilder.Build()` from the run-scope boundaries it already holds, so
  both passes carry them.
- Placed in the co-assignment payload rather than `perFile` (the issue's suggestion): the boundary
  is that panel's quantity, exists for pass 1 and pass 2 alike, and carrying its own run axis keeps
  the series aligned without assuming `perFile` / `crossRun` order. `perFile` is built by a
  different reducer with no access to the builder.
- Template: a line plot of the per-run boundary over the run axis in the co-assignment card, with
  the experiment boundary as a dashed reference and a hover tooltip naming the run; points drawn
  only up to 120 runs; the block hides when no run has a boundary.
- Regression: the diagnostics golden (`Regression/DiagnosticsGolden.ps1`) compares NAMED metrics,
  not bytes, so the added fields move nothing there.

## Tasks

- [x] Data fields + builder
- [x] Per-run log loop removed; experiment-level `[COUNT]` line kept; comments updated
- [x] Template plot
- [x] SubsetPipelineTest.TestSubsetDiagnosticsWithoutReanalysis asserts one finite boundary per run
- [x] Build-Osprey -RunTests -RunInspection: 646/646, inspection 0 warnings
- [x] regression.ps1 -Dataset Stellar: PASSED; -Dataset StellarLibDecoy (carries --model-diagnostics,
      runs the diagnostics golden mode 1b and the mode-3 chain report): PASSED, 17 checks. Its
      chain products carry runCutoffs for 3 runs in both passes (pass 1 0.215/0.191/0.176 vs
      experiment 0.474)
- [x] Render check: `ai/.tmp/sessions/20261101-quickwins/plotcheck.js` runs `drawCaRunCutoffs`
      from the template under a DOM shim - 446 runs with an outlier and a "NaN" run (line breaks,
      no markers, reference line, tooltip names the run), 3 runs (markers), no experiment
      boundary (no reference line), an old product without the series (block hidden): all pass
- [x] Review (independent agent; `/code-review` is blocked from this agent's pinned cwd): no
      defects. Dropped: the subset assertion that every run has a boundary assumes the subset
      data (true today, and the message says so); pinning RunCutoffs in the diagnostics golden
      would mean re-recording it, outside this issue
- [x] PR #4961 opened

## Progress Log

### 2026-11-01
- Implemented. Commit f548323f96.

### 2026-11-03 - Merged

PR #4961 merged as commit 2461de8241. Shipped: per-run boundary lines out of the log, RunNames and
RunCutoffs in the co-assignment data for both passes, and the per-run line plot in the report. Not
done, by choice: pinning RunCutoffs in the diagnostics golden (would re-record it). Issue #4672
closed by the merge. #4955, #4959 and #4965 each share one file with this change and take a small
merge from master.
