# DockPaneStrip.DrawTabStrip_ToolWindow paints with zero visible tabs

## Branch Information
- **Branch**: `Skyline/work/20260217_dockpanestrip_zero_tabs`
- **Base**: `master`
- **Created**: 2026-02-17
- **Status**: In Progress
- **GitHub Issue**: [#3978](https://github.com/ProteoWizard/pwiz/issues/3978)
- **PR**: (pending)
- **Exception Fingerprint**: `a28941ab620eb6fa`
- **Exception ID**: 73964

## Objective

Add early-return guards in `DrawTabStrip_ToolWindow` and `DrawTabStrip_Document` when there are no visible tabs (`Tabs.Count == 0`). This complements the snapshot-based fix from #3886 (which handles mid-iteration shrinking) by also handling the zero-content case.

## Tasks

- [ ] Add `if (Tabs.Count == 0) return;` guard to `DrawTabStrip_ToolWindow`
- [ ] Add `if (Tabs.Count == 0) return;` guard to `DrawTabStrip_Document`
- [ ] Build and verify no compilation errors
- [ ] Create PR

## Progress Log

### 2026-02-17 - Session Start

Starting work on this issue. The diagnostics from #3886 revealed that the tab collection can be empty when paint fires (initial count=0), so the snapshot fix alone doesn't help — we need an early-return guard.
