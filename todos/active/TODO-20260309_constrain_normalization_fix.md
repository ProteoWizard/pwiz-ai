# TODO-20260309_constrain_normalization_fix.md

## Branch Information
- **Branch**: `Skyline/work/20260309_constrain_normalization_fix`
- **Base**: `master`
- **Created**: 2026-03-09
- **Status**: In Progress
- **GitHub Issue**: (none - direct nightly fix)
- **PR**: (pending)

## Objective

Fix intermittent failure in `ConstrainNormalizationMethodTest` seen on nightly parallel test machines.

## Root Cause

`ConstrainNormalizationMethodTest.DoTest()` opens `Rat_plasma.sky` (which has results referencing
a `.skyd` file), modifies the document to remove global standard types, then saves it as
`NoGlobalStandards.sky`. It later re-opens `NoGlobalStandards.sky` to verify normalization options.

`SaveDocument` calls `OptimizeCache`, which creates `NoGlobalStandards.skyd` **only if**
`results.IsLoaded` is true. Results load in the background. On slower machines running multiple
parallel test clients, the `.skyd` may not finish loading before `SaveDocument` is called.

When `NoGlobalStandards.sky` is later opened and `NoGlobalStandards.skyd` is missing, Skyline
shows a `MultiButtonMsgDlg` about missing data. That dialog fires inside a `RunUI()` (synchronous
`Invoke`) call, so the test thread is blocked and cannot dismiss it. After 10 seconds,
`HangDetection.InterruptAfter` aborts the dialog and the test fails.

The failure was machine-dependent: on Brendan's dev machine, raw data files at
`C:\Users\Brendan\Downloads\Tutorials\...` happen to exist, so `CheckResults` skips the dialog
even without a `.skyd`. On the nightly machine, those files are absent.

## Fix

Add `WaitForDocumentLoaded()` before `SaveDocument(pathNoGlobalStandardsNoHeavy)`. This ensures
results are fully loaded so `OptimizeCache` reliably creates `NoGlobalStandards.skyd`.

## Files Modified

- `pwiz_tools/Skyline/TestFunctional/ConstrainNormalizationMethodTest.cs` - added `WaitForDocumentLoaded()` before save

## Tasks

- [x] Diagnose root cause (OptimizeCache skipped when results not loaded)
- [x] Implement fix (WaitForDocumentLoaded before SaveDocument)
- [x] Build and verify test passes locally
- [ ] Commit and push branch
- [ ] Create PR
