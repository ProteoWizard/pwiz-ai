# TODO-20260202_markquantitative_nooptimization.md

## Branch Information
- **Branch**: `Skyline/work/20260202_markquantitative_nooptimization`
- **Base**: `master`
- **Created**: 2026-02-02
- **Status**: In Progress
- **GitHub Issue**: [#3936](https://github.com/ProteoWizard/pwiz/issues/3936)
- **PR**: (pending)

## Objective

Add `[MethodImpl(MethodImplOptions.NoOptimization)]` attribute to `SkylineWindow.MarkQuantitative` so future exception reports include accurate line numbers instead of `line 0` due to JIT inlining.

## Root Cause

JIT inlining causes exception reports to show `Skyline.cs:line 0`, making it impossible to determine which dereference causes the NullReferenceException. The method is UI-triggered (not a hot path), so disabling optimization has negligible performance impact.

## Tasks

- [x] Create branch and TODO
- [x] Add `using System.Runtime.CompilerServices` to Skyline.cs
- [x] Add `[MethodImpl(MethodImplOptions.NoOptimization)]` attribute to `MarkQuantitative`
- [ ] Build and verify
- [ ] Create PR

## Files Modified

- `pwiz_tools/Skyline/Skyline.cs` - Add using statement and NoOptimization attribute on `MarkQuantitative` (line 4728)
