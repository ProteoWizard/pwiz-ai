# ProductionFacility.Unlisten Race Condition Fix

## Branch Information
- **Branch**: `Skyline/work/20260120_ProductionFacility_Unlisten`
- **Base**: `master`
- **Created**: 2026-01-20
- **GitHub Issue**: https://github.com/ProteoWizard/pwiz/issues/3832
- **Related Issue**: https://github.com/ProteoWizard/pwiz/issues/3840 (background thread exception handling audit)

## Objective

Fix race condition where `ProductionFacility.Unlisten` throws `InvalidOperationException` when attempting to unlisten from a WorkOrder that was already removed by another thread.

## Root Cause

`ReplicateCachingReceiver.CompletionListener` was calling `Unlisten()` twice:
1. From `OnProductAvailable()` when the result arrives (background thread)
2. From `ClearCache()` or `CleanStaleEntries()` (UI thread)

Per Nick's review: The fix belongs in `CompletionListener` which should track its listening state, not in `ProductionFacility` which should be able to assume balanced Listen/Unlisten calls.

## Fix Applied

Added `_isListening` flag to `CompletionListener` with `Interlocked.Exchange` for thread-safe check-and-set:

```csharp
private int _isListening = 1;  // 1 = listening, 0 = unlistened

public void Unlisten()
{
    // Atomic check-and-set to prevent double Unlisten from concurrent threads
    if (Interlocked.Exchange(ref _isListening, 0) == 0)
        return;
    _owner._receiver.Cache.Unlisten(_workOrder, this);
}
```

## Tasks

- [x] Create branch from master
- [x] Initial fix in ProductionFacility (reverted per review)
- [x] Move fix to ReplicateCachingReceiver.CompletionListener
- [x] Add thread-safe Interlocked.Exchange guard
- [x] Verify build succeeds
- [x] Create PR: https://github.com/ProteoWizard/pwiz/pull/3839
- [x] Address Nick's review feedback
- [x] Create follow-up issue #3840 for background thread exception handling audit

## Files Modified

1. **pwiz_tools/Skyline/Controls/Graphs/ReplicateCachingReceiver.cs**
   - Added `_isListening` field to `CompletionListener`
   - Added `Interlocked.Exchange` guard in `Unlisten()` to prevent double-unlisten

## Progress Log

### 2026-01-20 - Fix Implemented

- Created branch `Skyline/work/20260120_ProductionFacility_Unlisten`
- Initial fix made ProductionFacility tolerant of missing entries
- TestPeakPickingTutorial passed 50+ consecutive runs
- PR #3839 created, assigned to Nick, labeled for cherry-pick to release

### 2026-01-20 - Review Feedback

- Nick pointed out fix belongs in ReplicateCachingReceiver, not ProductionFacility
- Reverted ProductionFacility changes
- Added `_isListening` flag with `Interlocked.Exchange` to CompletionListener
- Force-pushed corrected fix
- Created issue #3840 for broader background thread exception handling audit
  - 878 test failures over past year show ThreadExceptionDialog from unhandled exceptions
  - CommonActionUtil.RunAsync() lacks proper exception handling unlike ActionUtil.RunAsync()
