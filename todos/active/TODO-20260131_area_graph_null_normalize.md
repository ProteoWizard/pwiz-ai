# TODO-20260131_area_graph_null_normalize.md

## Branch Information
- **Branch**: `Skyline/work/20260131_area_graph_null_normalize`
- **Base**: `master`
- **Created**: 2026-01-31
- **Status**: In Progress
- **GitHub Issue**: [#3828](https://github.com/ProteoWizard/pwiz/issues/3828)
- **PR**: [#3924](https://github.com/ProteoWizard/pwiz/pull/3924)

## Objective
Fix NullReferenceException in AreaReplicateGraphPane.GetDotProductResults when _normalizeOption is null during import.

## Root Cause Analysis
`AreaGraphData.GetDotProductResults()` accesses `_normalizeOption.NormalizationMethod` without null-checking. While the `is` pattern matching handles null for `NormalizationMethod`, `_normalizeOption` itself can be null during document state transitions while importing results. The graph pane updates via `OnDocumentUIChanged` which fires during import before the normalize option is fully initialized.

## Exception Details
- **Exception ID**: 73749
- **Version**: 25.1.1.271

## Changes Made
- [x] Coalesced null `normalizeOption` to `NormalizeOption.DEFAULT` at AreaGraphData constructor (per Copilot review)
- [x] Guards all downstream accesses, not just GetDotProductResults
- [x] Added `[MethodImpl(MethodImplOptions.NoOptimization)]` to `GetDotProductResults` (per Nick's review — JIT may report wrong line numbers)

## Files Modified
- `pwiz_tools/Skyline/Controls/Graphs/AreaReplicateGraphPane.cs` - AreaGraphData constructor, GetDotProductResults

## Test Plan
- [ ] TeamCity CI passes

## Implementation Notes
- Initial fix used null-conditional at call sites; Copilot correctly identified that `_normalizeOption` is also dereferenced in `NormalizedValueCalculator.NormalizationMethodForMolecule` and other paths
- Coalescing to `NormalizeOption.DEFAULT` at the constructor is a single-point fix that protects all downstream code
- Nick noted he couldn't find a code path where `_normalizeOption` is actually null — the NullReferenceException may be reported on the wrong line due to JIT optimization. `NoOptimization` will give accurate line numbers if the exception recurs
