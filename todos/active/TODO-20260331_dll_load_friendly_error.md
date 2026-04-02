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

- [x] Add startup check that verifies pwiz_data_cli.dll can load
- [x] Show friendly error dialog with troubleshooting info and wiki link
- [x] Build and test (CodeInspection passes, manual test with renamed DLL)
- [ ] Create PR

## Progress Log

### 2026-03-31 - Implementation

- Added `CheckNativeLibraries()` with `[NoInlining]` to isolate JIT trigger for pwiz_data_cli.dll
- Shows `AlertLinkDlg` with friendly message and link to `tip_recover_install` wiki page
- Skipped during `FunctionalTest` to avoid interfering with test infrastructure
- Manually tested by renaming pwiz_data_cli.dll — dialog displays correctly
