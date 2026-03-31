# Normalize CommonActionUtil and Skyline.ActionUtil thread handling

## Branch Information
- **Branch**: `Skyline/work/20260331_normalize_thread_handling`
- **Base**: `master`
- **Worktree**: `pwiz`
- **Created**: 2026-03-31
- **Status**: In Progress
- **GitHub Issue**: [#3842](https://github.com/ProteoWizard/pwiz/issues/3842)
- **PR**: (pending)

## Objective

Normalize thread initialization and exception handling between `CommonActionUtil.RunAsync()` and `Skyline.ActionUtil.RunAsync()`. Add `LocalizationHelper.InitThread()` to `CommonActionUtil.RunNow()`, inject `Program.ReportException` at Skyline startup, and simplify `ActionUtil.RunAsync` to delegate to CommonActionUtil.

## Tasks

- [ ] Enhance CommonActionUtil.RunNow() with locale init and exception reporter injection
- [ ] Update SafeBeginInvoke to wrap in RunNow()
- [ ] Set CommonActionUtil.ExceptionReporter at Skyline startup
- [ ] Simplify Skyline.ActionUtil.RunAsync to delegate to CommonActionUtil
- [ ] Build and test
- [ ] Create PR

## Progress Log

### 2026-03-31 - Session Start

Starting work on this issue.
