# Normalize CommonActionUtil and Skyline.ActionUtil thread handling

## Branch Information
- **Branch**: `Skyline/work/20260331_normalize_thread_handling`
- **Base**: `master`
- **Worktree**: `pwiz`
- **Created**: 2026-03-31
- **Status**: In Progress
- **GitHub Issue**: [#3842](https://github.com/ProteoWizard/pwiz/issues/3842)
- **PR**: [#4126](https://github.com/ProteoWizard/pwiz/pull/4126)

## Objective

Normalize thread initialization and exception handling between `CommonActionUtil.RunAsync()` and `Skyline.ActionUtil.RunAsync()`. Add `LocalizationHelper.InitThread()` to `CommonActionUtil.RunNow()`, inject `Program.ReportException` at Skyline startup, and simplify `ActionUtil.RunAsync` to delegate to CommonActionUtil.

## Tasks

- [x] Enhance CommonActionUtil.RunNow() with locale init and exception reporter injection
- [x] Update SafeBeginInvoke to wrap in RunNow()
- [x] Set CommonActionUtil.ExceptionReporter at Skyline startup
- [x] Simplify Skyline.ActionUtil.RunAsync to delegate to CommonActionUtil
- [x] Removed unused RunAsyncNoExceptionHandling
- [x] Build and test (CodeInspection passes)
- [ ] Create PR

## Progress Log

### 2026-03-31 - Implementation

- Added `ExceptionReporter` static property to CommonActionUtil for dependency injection
- `RunNow()` now calls `LocalizationHelper.InitThread()` and catches `OperationCanceledException`
- `HandleException()` routes to injected reporter, falls back to debug message
- `SafeBeginInvoke()` wraps action in `RunNow()` for consistent thread init
- `ActionUtil.RunAsync()` now delegates to `CommonActionUtil.RunAsync()`, only adding `LoadCanceledException` catch
- Removed `RunAsyncNoExceptionHandling` (unused and dangerous)
- `Program.Main()` sets `CommonActionUtil.ExceptionReporter = ReportException`
