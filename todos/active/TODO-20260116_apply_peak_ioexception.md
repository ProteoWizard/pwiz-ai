# IOException in ApplyPeak shown as programming defect instead of user-friendly message

## Branch Information
- **Branch**: `Skyline/work/20260116_apply_peak_exception`
- **Base**: `master`
- **Created**: 2026-01-16
- **GitHub Issue**: [#3811](https://github.com/ProteoWizard/pwiz/issues/3811)

## Objective

Fix the ApplyPeak operation to display a user-friendly error message when an IOException occurs (e.g., network error reading .skyd cache file) instead of showing the "programming defect" dialog.

## Tasks

- [ ] Read EditMenu.cs and locate ApplyPeak method (lines 792-917)
- [ ] Add try-catch around `longWait.PerformWork()` and subsequent code
- [ ] Use `ExceptionUtil.DisplayOrReportException()` pattern
- [ ] Verify code compiles
- [ ] Run unit tests

## Progress Log

### 2026-01-16 - Session Start

Starting work on this issue. The fix is straightforward - wrap the long operation in try-catch using the established pattern from other similar operations.
