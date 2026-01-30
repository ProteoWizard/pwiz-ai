# TODO-20260129_apply_peak_null_chrominfo.md

## Branch Information
- **Branch**: `Skyline/work/20260129_apply_peak_null_chrominfo`
- **Base**: `master`
- **Created**: 2026-01-29
- **Status**: In Progress
- **GitHub Issue**: [#3905](https://github.com/ProteoWizard/pwiz/issues/3905)
- **PR**: [#3911](https://github.com/ProteoWizard/pwiz/pull/3911)

## Objective
Fix NullReferenceException in EditMenu.ApplyPeakWithLongWait when FindChromInfo returns null for a transition group that has no chromatogram data in the selected replicate/file.

## Root Cause Analysis
In `ApplyPeakWithLongWait()`, the method iterates over peptide paths and for each one finds a transition group and its chromatogram info. Two null dereference issues exist:

1. **Primary bug (chromInfo)**: `FindChromInfo()` returns `TransitionGroupChromInfo` which is null when a transition group has no chromatogram data in the selected replicate/file. The null `chromInfo` is dereferenced on lines 891-892 to access `StartRetentionTime` and `EndRetentionTime`. This only manifests when synchronized integration is active (the `if` branch on line 883). The `else` branch (non-synchronized) calls `PeakMatcher.ApplyPeak` which does not use `chromInfo`.

2. **Secondary bug (peptideGroupDocNode)**: `document.FindNode()` can return null but the code used an unchecked direct cast `(PeptideGroupDocNode)`.

The crash was reported 14 times by 11 users (fingerprint `5fa11a95ed3d2c8e`) since June 2025.

`FindChromInfo` (SkylineGraphs.cs:2211) returns null when:
- The chromatogram set is not found in MeasuredResults
- The file path is not found in the chromatogram set
- The results for that transition group at the given index are empty
- No matching ChromInfo is found via FirstOrDefault

## Changes Made
- [x] Added null check for chromInfo after FindChromInfo call (continue to skip transition groups with no chromatogram data)
- [x] Added null check for peptideGroupDocNode with consistent explicit cast style
- [x] Replaced magic constants 0 and 1 with `SrmDocument.Level.MoleculeGroups` and `SrmDocument.Level.Molecules`
- [x] Added regression test in ApplyPeakToAllTest

## Files Modified
- `pwiz_tools/Skyline/Menus/EditMenu.cs` - ApplyPeakWithLongWait() null checks and Level enum
- `pwiz_tools/Skyline/TestFunctional/ApplyPeakToAllTest.cs` - Regression test for #3905

## Test Plan
- [x] TestApplyPeakToAll - Extended with regression test that:
  1. Enables auto-select transitions and pastes a new peptide (PEPTIDER) with no chromatogram data
  2. Enables synchronized integration for all replicates
  3. Selects all peptides and calls Apply Peak to All
  4. Without fix: NullReferenceException at EditMenu.cs:889. With fix: passes.
- [ ] TeamCity CI passes

## Implementation Notes
- Using `continue` when chromInfo is null is correct because the loop iterates over peptide paths. Skipping transition groups with no data allows the operation to proceed for others. This is consistent with the existing null check for `transitionGroupDocNode` on line 877-880.
- Kept explicit cast `(PeptideGroupDocNode)` rather than `as` to match the style of `(PeptideDocNode)` on the next line - the document guarantees these typed returns.
- Used `SrmDocument.Level` enum values instead of magic constants for self-documenting code.
- The NRE only occurs in the synchronized integration branch. The else branch calls `PeakMatcher.ApplyPeak` which does not use `chromInfo` directly.
