# TestFullScanProperties: GC-LEAK failure - SkylineWindow/SrmDocument not collected after test

## Branch Information
- **Branch**: `Skyline/work/20260307_fullscan_gc_leak`
- **Base**: `master`
- **Created**: 2026-03-07
- **Status**: Merged
- **GitHub Issue**: [#4060](https://github.com/ProteoWizard/pwiz/issues/4060)
- **PR**: [#4061](https://github.com/ProteoWizard/pwiz/pull/4061)
- **Fix Type**: failure
- **Test Name**: TestFullScanProperties

## Objective

Fix pre-existing GC-LEAK now caught by GarbageCollectionTracker: SkylineWindow and SrmDocument
survive GC after TestFullScanProperties. Root cause is in GraphFullScan.OnClosed — missing
`base.OnClosed(e)` call and/or not clearing PropertyGrid.SelectedObject before closing.

## Tasks

- [x] Add `base.OnClosed(e)` call to `GraphFullScan.OnClosed`
- [x] Clear `PropertiesSheet.SelectedObject = null` in `GraphFullScan.OnClosed` to break
      COM/accessibility chain from PropertyGrid through to SkylineWindow
- [x] Verify fix by running TestFullScanProperties in stress/loop mode

## Resolution

- **Status**: Fixed and merged
- **Merge commit**: `c139a3a05c8c01ed0ecad68a0f17e0da755582ef`
- **Fix summary**: Added `base.OnClosed(e)` call and `PropertiesSheet.SelectedObject = null`
  in `GraphFullScan.OnClosed` to break the COM/accessibility retain cycle that kept
  SkylineWindow and SrmDocument alive past GC after the test.

## Progress Log

### 2026-03-07 - Session Start

Two candidates for the leak:
1. Missing `base.OnClosed(e)` suppresses FormClosed event, so SkylineWindow never nulls
   `_graphFullScan`, keeping the retain cycle live
2. PropertyGrid COM accessibility objects holding PropertyGrid → GraphFullScan →
   _documentContainer → SkylineWindow alive past the FlushMemory GC passes

Fix: clear SelectedObject and call base in GraphFullScan.OnClosed.

### 2026-03-10 - Merged

PR [#4061](https://github.com/ProteoWizard/pwiz/pull/4061) merged to master.
Merge commit: `c139a3a05c8c01ed0ecad68a0f17e0da755582ef`
Branch `Skyline/work/20260307_fullscan_gc_leak` deleted.
