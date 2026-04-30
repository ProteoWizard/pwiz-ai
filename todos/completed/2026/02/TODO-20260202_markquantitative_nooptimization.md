# TODO-20260202_markquantitative_nooptimization.md

## Branch Information
- **Branch**: `Skyline/work/20260202_markquantitative_nooptimization`
- **Base**: `master`
- **Created**: 2026-02-02
- **Status**: Completed
- **GitHub Issue**: [#3936](https://github.com/ProteoWizard/pwiz/issues/3936)
- **PR**: [#3942](https://github.com/ProteoWizard/pwiz/pull/3942)

## Objective

Add `[MethodImpl(MethodImplOptions.NoOptimization)]` attribute to `SkylineWindow.MarkQuantitative` so future exception reports include accurate line numbers instead of `line 0` due to JIT inlining.

## Root Cause

JIT inlining causes exception reports to show `Skyline.cs:line 0`, making it impossible to determine which dereference causes the NullReferenceException. The method is UI-triggered (not a hot path), so disabling optimization has negligible performance impact.

## Tasks

- [x] Create branch and TODO
- [x] Add `using System.Runtime.CompilerServices` to Skyline.cs
- [x] Add `[MethodImpl(MethodImplOptions.NoOptimization)]` attribute to `MarkQuantitative`
- [x] Build and verify
- [x] Create PR

## Files Modified

- `pwiz_tools/Skyline/Skyline.cs` - Add using statement and NoOptimization attribute on `MarkQuantitative` (line 4728)

## Resolution

- **Status**: Fixed
- **PR**: [#3942](https://github.com/ProteoWizard/pwiz/pull/3942) — merged to master 2026-02-03 (commit `a309b63`)
- **Release cherry-pick**: [#3944](https://github.com/ProteoWizard/pwiz/pull/3944) — merged to `Skyline/skyline_26_1` 2026-02-04 (commit `33876af`)
- **Summary**: Added `[MethodImpl(MethodImplOptions.NoOptimization)]` to `MarkQuantitative` so future exception reports show accurate line numbers instead of `line 0`.

## Progress Log

### 2026-02-03 - Merged
- PR #3942 merged to master (commit `a309b63`)
- Cherry-pick PR #3944 merged to `Skyline/skyline_26_1` (commit `33876af`)
