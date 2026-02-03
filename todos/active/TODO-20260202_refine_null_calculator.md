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

When no usable calculators exist (library unloaded), `_calculator` is set to null via `usableCalculators.FirstOrDefault()`. But `Refine()` dereferences `_calculator.IsUsable` without a null check. The constructor calls `Refine()` when `IsRefined()` returns false, which is exactly the state when no calculator was found.

## Tasks

- [x] Create branch and TODO
- [x] Add null check before `_calculator.IsUsable` in `Refine()`
- [ ] Build and verify
- [ ] Create PR

## Files Modified

- `pwiz_tools/Skyline/Model/RetentionTimes/RetentionTimeRegressionGraphData.cs` - Add `_calculator == null ||` guard at line 396
