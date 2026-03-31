# Show friendly error when Application Control policy blocks pwiz_data_cli.dll

## Branch Information
- **Branch**: `Skyline/work/20260331_dll_load_friendly_error`
- **Base**: `master`
- **Worktree**: `pwiz-work2`
- **Created**: 2026-03-31
- **Status**: In Progress
- **GitHub Issue**: [#3863](https://github.com/ProteoWizard/pwiz/issues/3863)
- **PR**: (pending)
- **Exception Fingerprint**: (from issue)

## Objective

When Windows Application Control (WDAC/AppLocker) blocks pwiz_data_cli.dll, show a friendly error message instead of a crash dialog. Add startup DLL verification, installation type detection, and a helpful error dialog with troubleshooting guidance.

## Tasks

- [ ] Add startup check that verifies pwiz_data_cli.dll can load
- [ ] Add installation type detection (ClickOnce, MSI, ZIP)
- [ ] Show friendly error dialog with troubleshooting info
- [ ] Create wiki troubleshooting page
- [ ] Build and test
- [ ] Create PR

## Progress Log

### 2026-03-31 - Session Start

Starting work on this issue.
