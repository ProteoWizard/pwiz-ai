# Fix ArgumentOutOfRangeException in Apply Peak Subsequent

## Branch Information
- **Branch**: `Skyline/work/20260217_apply_peak_exception`
- **Base**: `master`
- **Created**: 2026-02-17
- **Status**: Completed
- **GitHub Issue**: [#3996](https://github.com/ProteoWizard/pwiz/issues/3996)
- **PR**: (pending)
- **Exception ID**: 73977

## Objective

Fix `ArgumentOutOfRangeException` when using "Apply Peak" / "Apply Peak Subsequent" on a precursor
that has no results in some replicates.

## Root Cause Analysis

In `PeakMatcher.GetPeakMatch()`, when `referenceTarget == null` (the reference replicate has no peak
data for this precursor), the method returned `new PeakMatch(0, 0)` immediately at line 214 **without
first checking whether the target replicate has chromatogram data**.

This bypassed all the chromatogram existence checks (lines 217-227):
- `TryLoadChromatogram` call
- File path matching in loaded infos
- Peak count and data point checks
- Transition chromatogram info checks

Then when `PeakMatch.ChangePeak` called `SrmDocument.ChangePeak`, the `FindChromInfos` constructor
called `TryLoadChromatogram` and failed because no chromatogram existed for this precursor in this
replicate, throwing `ArgumentOutOfRangeException`.

This is the same class of bug as PR #3646 - a code path that bypasses chromatogram existence
verification that `SrmDocument.ChangePeak` relies on.

### What PeakMatch(0, 0) means

- `PeakMatch(0, 0)` = "remove the peak" (set zero-width boundaries)
- `null` = "skip this replicate, don't change anything"

When `referenceTarget == null`, the intent is to clear peaks in other replicates (apply "no peak"
everywhere). But for replicates with no chromatogram data at all, there's nothing to clear.

## Fix

Moved the chromatogram existence checks **before** the `referenceTarget == null` early return in
`GetPeakMatch()`. Now replicates without chromatogram data return `null` (skip) before we ever try
to return `PeakMatch(0, 0)`.

## Tasks

- [x] Investigate root cause of ArgumentOutOfRangeException
- [x] Implement fix in PeakMatcher.GetPeakMatch
- [x] Build and run test (TestRemovePeakFromAll)
- [x] Create PR

## Files Modified

- `pwiz_tools/Skyline/Model/PeakMatcher.cs` - Moved chromatogram checks before referenceTarget null check

## Progress Log

### 2026-02-17 - Session 1

* Analyzed exception report #73977 and GitHub issue #3996
* Reviewed PR #3646 for precedent (same class of bug: different TryLoadChromatogram arguments)
* Identified root cause: GetPeakMatch returns PeakMatch(0,0) without verifying chromatograms exist
* Applied fix: reordered checks so chromatogram existence is verified before referenceTarget null return
* Test TestRemovePeakFromAll passes
