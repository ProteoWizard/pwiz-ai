# TODO-20260216_change_peak_libraries_not_loaded.md

## Branch Information
- **Branch**: `Skyline/work/20260216_change_peak_libraries_not_loaded`
- **Base**: `master`
- **Created**: 2026-02-16
- **Status**: In Progress
- **GitHub Issue**: [#3949](https://github.com/ProteoWizard/pwiz/issues/3949)
- **PR**: [#3991](https://github.com/ProteoWizard/pwiz/pull/3991)

## Objective
Fix AssumptionException crash when user changes peak integration boundaries before libraries finish loading. 14 reports from 7 users. Fingerprint: `8e49b21de5c3939b`.

## Root Cause
`PeptideLibraries.TryGetRetentionTimes()` asserts `Assume.IsTrue(IsLoaded)`. When `SrmDocument.ChangePeak()` is called with `identified = null`, it tries to determine identification status by looking up library retention times. If libraries aren't loaded yet, the assertion throws.

## Fix Approach
Added `EnsureLibrariesLoadedForPeakIntegration()` helper on SkylineWindow that shows a user-friendly message and returns false when libraries aren't loaded. Guards placed at UI entry points:
- `graphChromatogram_PickedPeak` — single-click peak picking
- `ApplyPeakWithLongWait` — Edit > Apply Peak menu

The `Assume.IsTrue(IsLoaded)` assertions in PeptideLibraries remain unchanged — they correctly identify programming errors from code paths that should have checked first.

## Completed Tasks
- [x] Investigate call chain and identify entry points
- [x] Add resource string for user-friendly message
- [x] Add `EnsureLibrariesLoadedForPeakIntegration()` helper to SkylineWindow
- [x] Guard `graphChromatogram_PickedPeak` in SkylineGraphs.cs
- [x] Guard `ApplyPeakWithLongWait` in EditMenu.cs
- [x] Build successfully

## Files Modified
- `pwiz_tools/Skyline/SkylineGraphs.cs` — helper method + guard in PickedPeak handler
- `pwiz_tools/Skyline/Menus/EditMenu.cs` — guard in ApplyPeakWithLongWait
- `pwiz_tools/Skyline/SkylineResources.resx` — new resource string
- `pwiz_tools/Skyline/SkylineResources.designer.cs` — generated property
