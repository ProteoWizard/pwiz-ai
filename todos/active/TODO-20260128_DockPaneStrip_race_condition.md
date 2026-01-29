# Race condition in DigitalRune DockPaneStrip.DrawTabStrip causes ThreadExceptionDialog hang

## Branch Information
- **Branch**: `Skyline/work/20260128_DockPaneStrip_race_condition`
- **Base**: `master`
- **Created**: 2026-01-28
- **Status**: In Progress
- **GitHub Issue**: [#3886](https://github.com/ProteoWizard/pwiz/issues/3886)
- **PR**: [#3889](https://github.com/ProteoWizard/pwiz/pull/3889)

## Objective

Investigate and fix race condition in DigitalRune.Windows.Docking.DockPaneStrip.DrawTabStrip_ToolWindow that causes ArgumentOutOfRangeException when tab collection changes mid-iteration, leading to ThreadExceptionDialog hangs in unattended tests.

## Approach

Rather than immediately fixing the suspected race condition, we are deploying diagnostics first to confirm the root cause. The exception fingerprint (e47eb5e67419a4b7) has 11 reports from 8 users but no line numbers because the PDB was never shipped.

### Phase 1: Diagnostic (this PR)
- [x] Add try/catch in DrawTabStrip_ToolWindow reporting initial count, current count, and activeTab index
- [x] Ship DigitalRune.Windows.Docking.pdb in ClickOnce and MSI installers for line numbers
- [x] Run full English test pass (1020 tests)
- [x] Verify ClickOnce publish includes PDB

### Phase 2: Fix (after diagnostic data collected)
- [ ] Analyze diagnostic output from next exception occurrence
- [ ] Determine if collection modification is re-entrant (same thread) or cross-thread
- [ ] Apply appropriate fix (likely: snapshot tabs before iteration)

## Analysis

### Exception stack trace (fingerprint e47eb5e67419a4b7)
```
DockableFormCollection.GetVisibleContent → TabCollection.get_Item →
DockPaneStrip.DrawTabStrip_ToolWindow → DockPaneStrip.OnPaint →
Control.PaintWithErrorHandling
```

Only `DrawTabStrip_ToolWindow` is implicated. `DrawTabStrip_Document` has no exception reports.

### Key difference between the two methods
- **DrawTabStrip_Document**: Iterates backward (`for (int i = count - 1; i >= 0; i--)`) with count captured at entry. Backward iteration is safer when elements may be removed mid-iteration.
- **DrawTabStrip_ToolWindow**: Iterates forward (`for (int i = 0; i < Tabs.Count; i++)`) re-reading Count each iteration. Forward iteration skips elements when removals occur. The post-loop `Tabs[activeTab]` access is the most likely failure point if the collection shrinks.

### TabCollection is a live view
`TabCollection.Count` and `TabCollection[index]` delegate directly to `DockPane.DisplayingContents` - there is no snapshot. Any modification to the underlying collection is immediately visible.

## Files Modified
- `DockPaneStrip.cs` (maccoss-developers - source + rebuilt DLL/PDB)
- `pwiz_tools/Shared/Lib/DigitalRune.Windows.Docking.dll` (rebuilt)
- `pwiz_tools/Shared/Lib/DigitalRune.Windows.Docking.pdb` (new)
- `pwiz_tools/Skyline/Skyline.csproj` (ClickOnce PDB entry)
- `pwiz_tools/Skyline/Executables/Installer/Product-template.wxs` (MSI PDB entry)
- `pwiz_tools/Skyline/Executables/Installer/FileList64-template.txt` (file list)

## Progress Log

### 2026-01-28 - Session Start

Starting work on this issue. Branch created from master.

Evidence:
- Nightly test hang: TestNormalizeToCalibrationCurve on BRENDANX-UW6 (run #80292)
- Exception fingerprint e47eb5e67419a4b7 - 11 reports from 8 users since May 2025

### 2026-01-28 - Diagnostic deployed

Decided against immediate fix in favor of diagnostic-first approach per debugging principles.

Key findings during analysis:
- Stack trace confirms only DrawTabStrip_ToolWindow is affected (not Document)
- No line numbers in exception reports because PDB was never shipped
- TabCollection is a live view over DockPane.DisplayingContents, not a snapshot
- The forward-iterating ToolWindow method is inherently less safe than the backward-iterating Document method for collections that may shrink

Changes:
- Added diagnostic try/catch to DrawTabStrip_ToolWindow
- Added PDB to both ClickOnce and MSI installer configurations
- Rebuilt DLL from maccoss-developers source
- Full test pass (1020 English tests), ClickOnce publish verified
- PR created: #3889
