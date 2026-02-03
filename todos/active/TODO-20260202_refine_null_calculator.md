# TODO-20260202_refine_null_calculator.md

## Branch Information
- **Branch**: `Skyline/work/20260202_refine_null_calculator`
- **Base**: `master`
- **Created**: 2026-02-02
- **Status**: In Progress
- **GitHub Issue**: [#3933](https://github.com/ProteoWizard/pwiz/issues/3933)
- **PR**: (pending)

## Objective

Fix NullReferenceException in `InstanceData.Refine` when RT calculator library is unavailable, leaving `_calculator` null.

## Root Cause

When a named iRT calculator is selected for the RT regression graph but its `.irtdb` database is unavailable (e.g., deleted or moved), `RetentionTimeRegressionSettings.GetCalculators()` can return calculators that don't match the named one. `InstanceData` then used `usableCalculators.FirstOrDefault()` without checking the name, potentially selecting the wrong calculator. When no calculator matches, `_calculator` is null, and `Refine()` dereferences `_calculator.IsUsable` causing an NRE.

## Fixes

1. **NRE guard in Refine**: Added `_calculator == null ||` check before `_calculator.IsUsable`
2. **Calculator name matching**: Changed `usableCalculators.FirstOrDefault()` to match by name against `RegressionSettings.CalculatorName`, preventing wrong calculator scores from being shown
3. **Test coverage**: Added test in IrtTest that clears the calculator list and IRT cache, reopens the document, and verifies the regression graph handles the missing calculator gracefully (all peptides as outliers, no crash)

## Follow-up

Enhancement [#3939](https://github.com/ProteoWizard/pwiz/issues/3939) tracks improving the UX when a named calculator is unavailable (auto-revert to "Auto", informational message about missing database path).

## Tasks

- [x] Create branch and TODO
- [x] Add null check before `_calculator.IsUsable` in `Refine()`
- [x] Add calculator name matching in `InstanceData` constructor
- [x] Add test coverage in IrtTest for missing calculator scenario
- [x] Build and verify
- [ ] Create PR

## Files Modified

- `pwiz_tools/Skyline/Model/RetentionTimes/RetentionTimeRegressionGraphData.cs` - Null guard in Refine, name matching in InstanceData constructor
- `pwiz_tools/Skyline/TestFunctional/IrtTest.cs` - Test for missing calculator regression graph
