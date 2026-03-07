# TestFullScanProperties: GC-LEAK failure - SkylineWindow/SrmDocument not collected after test

## Branch Information
- **Branch**: `Skyline/work/20260307_fullscan_gc_leak`
- **Base**: `master`
- **Created**: 2026-03-07
- **Status**: In Progress
- **GitHub Issue**: [#4060](https://github.com/ProteoWizard/pwiz/issues/4060)
- **PR**: (pending)
- **Fix Type**: failure
- **Test Name**: TestFullScanProperties

## Objective

Fix pre-existing GC-LEAK now caught by GarbageCollectionTracker: SkylineWindow and SrmDocument
survive GC after TestFullScanProperties. Root cause is in GraphFullScan.OnClosed — missing
`base.OnClosed(e)` call and/or not clearing PropertyGrid.SelectedObject before closing.

## Tasks

- [ ] Add `base.OnClosed(e)` call to `GraphFullScan.OnClosed`
- [ ] Clear `PropertiesSheet.SelectedObject = null` in `GraphFullScan.OnClosed` to break
      COM/accessibility chain from PropertyGrid through to SkylineWindow
- [ ] Verify fix by running TestFullScanProperties in stress/loop mode

## Progress Log

### 2026-03-07 - Session Start

Two candidates for the leak:
1. Missing `base.OnClosed(e)` suppresses FormClosed event, so SkylineWindow never nulls
   `_graphFullScan`, keeping the retain cycle live
2. PropertyGrid COM accessibility objects holding PropertyGrid → GraphFullScan →
   _documentContainer → SkylineWindow alive past the FlushMemory GC passes

Fix: clear SelectedObject and call base in GraphFullScan.OnClosed.
