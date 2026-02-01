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
- [x] Changed `_normalizeOption.NormalizationMethod` to `_normalizeOption?.NormalizationMethod` in both occurrences in GetDotProductResults and the InitData caller

## Files Modified
- `pwiz_tools/Skyline/Controls/Graphs/AreaReplicateGraphPane.cs` - GetDotProductResults() at lines 1288 and 1318

## Test Plan
- [ ] TeamCity CI passes

## Implementation Notes
- The null-conditional causes `is NormalizationMethod.RatioToLabel` to fail the match when `_normalizeOption` is null, which correctly skips the ratio calculation — same behavior as `_expectedVisible == AreaExpectedValue.none` returning NaN
- Both occurrences guarded: line 1288 (InitData path) and line 1318 (GetDotProductResults path)
