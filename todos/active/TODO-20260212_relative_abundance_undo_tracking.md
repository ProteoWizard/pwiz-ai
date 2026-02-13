# TODO-20260212_relative_abundance_undo_tracking.md

## Branch Information
- **Branch**: `Skyline/work/20260212_relative_abundance_undo_tracking`
- **Base**: `master`
- **Created**: 2026-02-12
- **Status**: In Progress
- **GitHub Issue**: None (diagnostic improvement for intermittent nightly test failure)
- **PR**: [#3973](https://github.com/ProteoWizard/pwiz/pull/3973)

## Objective

Add cache tracking to Test 4 (undo after multi-peptide delete) in
`TestPeakAreaRelativeAbundanceGraph`, using the same `GraphDataCachingReceiver.TrackCaching`
pattern already used in Test 6 (PR #3830). This transforms an opaque intermittent failure
(`CachedNodeCount=0`) into a diagnostic failure that reveals whether the root cause is
multiple `DocumentChanged` events (same pattern as Test 6) or something else entirely.

## Background

- **Test**: `TestPeakAreaRelativeAbundanceGraph` - Test 4 (undo after multi-peptide delete)
- **Failure pattern**: Intermittent `CachedNodeCount=0` instead of expected 121
- **Nightly history**: 22 failures since 2025-03-27 across 4 fingerprints
- **Related PR**: #3830 fixed the same class of issue in Test 6 (document reopen)
- **Root cause hypothesis**: Multiple `DocumentChanged` events during undo cause parallel
  graph calculations; if a full calculation completes and overwrites the cache, the final
  result shows `CachedNodeCount=0`

## Tasks

- [x] Add `GraphDataCachingReceiver.TrackCaching` wrapper around Test 4's undo operation
- [x] Assert exactly 1 cached result (dump diagnostic info if multiple)
- [x] Verify incremental update pattern on the single result
- [x] Build and test pass
- [x] Create PR - [#3973](https://github.com/ProteoWizard/pwiz/pull/3973)

## Files Modified

- `pwiz_tools/Skyline/TestFunctional/PeakAreaRelativeAbundanceGraphTest.cs` - Test 4 section

## Key Decisions

- Assert `cachedResults.Count == 1` to detect parallel calculations (rather than tolerating
  them like Test 6). This is intentionally strict so that when the intermittent failure
  occurs on nightly, the assertion message tells us exactly what happened.
- If there IS a second calculation, the failure message dumps `GetDiagnosticInfo()` for all
  cached results, revealing what triggered the extra calculation.
- If there's only 1 calculation with wrong counts, `GetDiagnosticInfo()` on the single result
  reveals whether it was a full or incremental calculation and its cache state.
