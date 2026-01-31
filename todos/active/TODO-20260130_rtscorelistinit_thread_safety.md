# TODO-20260130_rtscorelistinit_thread_safety.md

## Branch Information
- **Branch**: `Skyline/work/20260130_rtscorelistinit_thread_safety`
- **Base**: `master`
- **Created**: 2026-01-30
- **Status**: In Progress
- **GitHub Issue**: [#3908](https://github.com/ProteoWizard/pwiz/issues/3908)
- **PR**: [#3916](https://github.com/ProteoWizard/pwiz/pull/3916)

## Objective
Fix IndexOutOfRangeException caused by RTScoreCalculatorList.Initialize modifying Settings.Default from a background thread.

## Root Cause Analysis
`RTScoreCalculatorList.Initialize` combined computation (initializing calculators) with Settings.Default mutation (`SetValue`) in a single method. When called from `EditRTDlg.ShowGraph` via `LongWaitDlg.PerformWork` (background thread), the `SetValue` modified the internal `Dictionary` in `MappedList` concurrently with UI thread reads.

The original exception stack trace (fingerprint `bb1fde1684c77ec5`, version 25.1.0.237) went through `RTLinearRegressionGraphPane.GraphData..ctor` — that path was already refactored to a Producer/Receiver pattern. But the `EditRTDlg` path remained unsafe.

Additionally, `EditRTDlg.UpdateCalculator` called `Initialize(null)` for bulk initialization, blocking the UI thread entirely with no progress feedback.

## Exception Details
- **Fingerprint**: `bb1fde1684c77ec5`
- **Reports**: 1 user report (version 25.1.0.237)

## Changes Made
- [x] Separated `RTScoreCalculatorList.Initialize` into static pure-computation methods (safe for background threads) and `SetInitializedValue` (UI thread settings mutation)
- [x] Added backwards-compatible `Initialize(IProgressMonitor)` wrapper on base `RetentionScoreCalculatorSpec` that delegates to new `Initialize(IProgressMonitor, ref IProgressStatus)` virtual
- [x] Renamed `RCalcIrt.Initialize(IProgressMonitor, ref IProgressStatus)` to `InitializeIrt` to disambiguate from base virtual
- [x] Wrapped bulk calculator initialization in `EditRTDlg.UpdateCalculator` with `LongWaitDlg` (was blocking UI with `Initialize(null)`)
- [x] Fixed `EditRTDlg.ShowGraph` to call static Initialize in background, SetInitializedValue on UI thread

## Files Modified
- `pwiz_tools/Skyline/Model/DocSettings/Prediction.cs` - Base virtual method + backwards-compatible wrapper
- `pwiz_tools/Skyline/Model/Irt/RCalcIrt.cs` - Override updated, renamed to InitializeIrt
- `pwiz_tools/Skyline/Model/Irt/IrtDbManager.cs` - Updated to use InitializeIrt
- `pwiz_tools/Skyline/Properties/Settings.cs` - Static Initialize methods, SetInitializedValue
- `pwiz_tools/Skyline/SettingsUI/EditRTDlg.cs` - Both callers fixed

## Test Plan
- [x] IrtFunctionalTest passes (exercises missing iRT database path through UpdateCalculator)
- [ ] TeamCity CI passes

## Implementation Notes
- NOT cherry-picking to release — too much scope for a release this close. Goes into daily builds after 26.1.
- The bulk Initialize in UpdateCalculator is best-effort: individual calculator failures (e.g. missing database) are silently handled. `CalculatorException` is caught per-calculator. With a non-null monitor, `RCalcIrt.InitializeIrt` reports missing files through progress status and returns null (vs throwing with null monitor). `SetInitializedValue` handles both paths: null returns are skipped, and `ReferenceEquals` catches unchanged calculators.
- `LongWaitDlg` does not currently support cancellation for this operation — `IrtDb.Load` has no progress/cancellation support. But the infrastructure is now in place for future improvement.
- Progress segmentation is set up in the bulk Initialize (one segment per calculator) for future use.
