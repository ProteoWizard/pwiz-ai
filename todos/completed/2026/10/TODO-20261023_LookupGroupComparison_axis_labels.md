# TODO-20261023_LookupGroupComparison_axis_labels.md - Fix intermittent TestLookupGroupComparison

## Branch Information
- **Branch**: `Skyline/work/20261023_LookupGroupComparison_axis_labels` (checkout `C:\Dev\UIbug`)
- **Base**: `master`
- **Module**: `skyline`
- **Created**: 2026-10-23
- **Status**: Completed
- **PR**: [#4908](https://github.com/ProteoWizard/pwiz/pull/4908) (merged 2026-10-23)
- **Test Name**: TestLookupGroupComparison
- **Fix Type**: Test timing (UI race)

## Problem
TestLookupGroupComparison failed 8 times on Nightly x64 between 2026-09-01 and 2026-10-23, on
6 machines (BOSS-PC, BRENDANX-UW5, BSPRATT-UW2, KAIPOT-PC1, SKYLINE-DEV1, SKYLINE-DEV4), with
two errors in `GetAreaAxisLabels`:
- `Assert.IsNotNull(graphSummary)`: the `AreaReplicateGraphPane` was not found yet (6 runs)
- `ArgumentNullException` from `XAxis.Scale.TextLabels.ToList()`: labels not set yet (2 runs)

Every failure is on the first call (test line 85), which runs right after
`ShowPeakAreaReplicateComparison()` with no wait. The labels are set in
`AreaReplicateGraphPane.InitFromData` once the graph data has been computed asynchronously.
The three later calls each follow `WaitForGraphs()` and never failed.

## Fix
All four label checks now call `WaitForAreaAxisLabels(expected)`, which waits until the pane
exists and `GetOriginalXAxisLabels()` equals the expected labels, with expected/actual in the
timeout message. The first version (wait for `TextLabels != null`) only covered the first call;
`/code-review medium` pointed out that the later calls could still read stale labels after
reordering/regrouping, and that `TextLabels` can hold abbreviated labels.

## Progress
- [x] Fix applied, build + single run passed
- [x] 20-loop run (0 failures), CodeInspection passed
- [x] /code-review medium; revised to wait for expected labels; 20 loops x en/fr/ja (60/60 pass)
- [x] PR

### 2026-10-23 - Merged

PR #4908 merged as commit 89e5c6405c after TeamCity passed (Skyline: 1823 tests). Test-only
fix: all four area graph label checks now wait for the expected labels instead of reading
them once. Nothing deferred. Watch the next couple of weeks of Nightly x64 to confirm the
intermittent failure is gone.
