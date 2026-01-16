# TestPeakPickingTutorial: Systemic failure in CheckPointsTypeRT since Jan 1, 2026

## Branch Information
- **Branch**: `Skyline/work/20260116_peak_picking_tutorial_hang`
- **Base**: `master`
- **Created**: 2026-01-16
- **GitHub Issue**: [#3789](https://github.com/ProteoWizard/pwiz/issues/3789)

## Objective

Fix the systemic TestPeakPickingTutorial test failure that started January 1, 2026, affecting 3+ machines. The failure is likely a race condition introduced by PR #3730 which added background threading for RT graph calculations.

## Failure Details

- **Fingerprint**: `fbff507f7c30085f`
- **Test Method**: `PeakPickingTutorialTest.CheckPointsTypeRT`
- **Stack**: `→ AbstractFunctionalTest.RunUI → HangDetection.InterruptAfter → AbstractFunctionalTest.SkylineInvoke`
- **Affected Machines**: BRENDANX-UW5, BRENDANX-UW7, KAIPOT-PC1, BOSS-PC
- **Pattern**: 8 failures since Jan 1, 2026

## Suspected Cause

PR #3730 "Improved Relative Abundance graph performance with background computation and incremental updates" merged December 30, 2025. Modified:
- `RTLinearRegressionGraphPane.cs`
- `RetentionTimeRegressionGraphData.cs`
- Added background threading for graph calculations

The test likely accesses graph data before background calculation completes.

## Tasks

- [ ] Review PR #3730 changes to understand the background threading model
- [ ] Examine CheckPointsTypeRT in TestPeakPickingTutorial to understand what it validates
- [ ] Identify the race condition between background calculation and test validation
- [ ] Add appropriate synchronization or waiting mechanism
- [ ] Run TestPeakPickingTutorial locally to verify fix
- [ ] Create PR with fix

## Progress Log

### 2026-01-16 - Session Start

Starting work on this issue. Will begin by reviewing the PR #3730 changes and the test code to understand the timing issue.
