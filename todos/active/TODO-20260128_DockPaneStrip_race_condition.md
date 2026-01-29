# Race condition in DigitalRune DockPaneStrip.DrawTabStrip causes ThreadExceptionDialog hang

## Branch Information
- **Branch**: `Skyline/work/20260128_DockPaneStrip_race_condition`
- **Base**: `master`
- **Created**: 2026-01-28
- **Status**: In Progress
- **GitHub Issue**: [#3886](https://github.com/ProteoWizard/pwiz/issues/3886)
- **PR**: (pending)

## Objective

Fix race condition in DigitalRune.Windows.Docking.DockPaneStrip.DrawTabStrip that causes ArgumentOutOfRangeException when tab collection changes mid-iteration during document switch, leading to ThreadExceptionDialog hangs in unattended tests.

## Tasks

- [ ] Fix DrawTabStrip_ToolWindow (lines 493-513) - snapshot tabs before iteration
- [ ] Fix DrawTabStrip_Document (lines 463-489) - same pattern
- [ ] Use GetTabRectangle(DockPaneTab tab) overload instead of index-based access
- [ ] Test manually with document switching
- [ ] Run relevant functional tests

## Progress Log

### 2026-01-28 - Session Start

Starting work on this issue. Branch created from master.

Evidence:
- Nightly test hang: TestNormalizeToCalibrationCurve on BRENDANX-UW6 (run #80292)
- Exception fingerprint e47eb5e67419a4b7 - 11 reports from 8 users since May 2025
