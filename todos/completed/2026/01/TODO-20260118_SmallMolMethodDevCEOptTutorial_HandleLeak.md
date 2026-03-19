# Handle Leak in TestSmallMolMethodDevCEOptTutorial

## Branch Information
- **Branch**: `Skyline/work/20260118_SmallMolMethodDevCEOptTutorial_HandleLeak`
- **Base**: `master`
- **Created**: 2026-01-18
- **GitHub Issue**: https://github.com/ProteoWizard/pwiz/issues/3833
- **Pull Request**: https://github.com/ProteoWizard/pwiz/pull/3836

## Objective

Fix the reproducible handle leak of approximately 15 User+GDI handles per pass in TestSmallMolMethodDevCEOptTutorial. This is a chronic issue affecting 9+ machines in nightly testing (222 handle leak reports historically).

## Tasks

- [x] Bisect DoTest() to find which dialog/operation leaks handles
- [x] Use handle reporting tools to identify handle types
- [x] Fix undisposed dialogs or forms causing the leak
- [x] Verify fix with multi-pass testing

## Root Cause

The handle leak was in `ProducerConsumerWorker.RunAsync()` (line 103). When called with a different thread count than currently running, it calls `Abort()` without waiting for old threads to exit before creating new ones. This race condition caused ~9 GDI handles to leak per occurrence.

**Fix**: Changed `Abort()` to `Abort(true)` to wait for old threads to exit before creating new ones.

## Progress Log

### 2026-01-18 - Session Start

Starting work on this issue. The test is in `pwiz_tools/Skyline/TestTutorial/SmallMolMethodDevCEOptTutorial.cs` (600 lines).

Dialogs/forms used by the test that may be leaking:
- TransitionSettingsUI dialog
- ExportMethodDlg (multiple times)
- ImportResultsDlg with OpenDataSourceDialog
- ManageResultsDlg with RenameResultDlg
- DocumentGridForm
- PeptideSettingsUI
- CalibrationForm
- EditCEDlg
- SchedulingOptionsDlg

### 2026-01-18 - Root Cause Found

Through bisection and handle tracking, identified the leak in `ProducerConsumerWorker.RunAsync()`. The issue occurs when:
1. RunAsync is called to change thread count (e.g., 2 → 4 threads)
2. Abort() is called but doesn't wait for old threads
3. New threads start while old threads are still shutting down
4. GDI handles from old thread contexts leak

The fix is a one-line change: `Abort()` → `Abort(true)` to wait for clean handoff.

### 2026-01-19 - Fix Verified

- Ran TestSmallMolMethodDevCEOptTutorial and TestMethodRefinementTutorial together 70+ times with -ReportHandles
- No handle growth observed (previously both showed obvious handle growth)
- Also discovered unrelated Listen/Unlisten cleanup opportunities (stashed for separate PR)
- Created PR #3836

### 2026-01-20 - Merged

- PR #3836 merged to master (commit 82ae5a2fd091)
- Cherry-picked to release branch via PR #3837 (merged to Skyline/skyline_26_1, commit 87313f2efd6d)

## Resolution

**Status**: Complete

**Fix**: One-line change in `pwiz_tools/Shared/CommonUtil/SystemUtil/ProducerConsumerWorker.cs` line 103:
```csharp
// Before
Abort();
// After
Abort(true);
```

**Impact**: Fixes handle leaks in TestSmallMolMethodDevCEOptTutorial, TestMethodRefinementTutorial, and potentially other tests that trigger thread count changes during file import.
