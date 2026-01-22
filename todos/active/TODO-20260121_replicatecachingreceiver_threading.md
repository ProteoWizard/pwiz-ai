# TODO-20260121_replicatecachingreceiver_threading.md

## Branch Information
- **Branch**: `Skyline/work/20260121_replicatecachingreceiver_threading`
- **Base**: `master`
- **Created**: 2026-01-21
- **Status**: Ready for PR
- **GitHub Issue**: [#3857](https://github.com/ProteoWizard/pwiz/issues/3857)
- **PR**: (pending)

## Problem Description

`InvalidOperationException: Collection was modified; enumeration operation may not execute` occurs in `ReplicateCachingReceiver.ClearCache()`.

The error occurs when:
1. `ClearCache()` iterates over `_pendingListeners.Values` (line 374)
2. Concurrently, `OnProductAvailable()` modifies the dictionary via `_pendingListeners.Remove(_cacheKey)` (line 421)

This is the same class of threading bug as GitHub #3832.

## Root Cause Analysis

The `_pendingListeners` dictionary is accessed from multiple threads:
- **UI thread**: `ClearCache()` iterates `_pendingListeners.Values` in a `foreach` loop
- **Background thread**: `CompletionListener.OnProductAvailable()` removes entries via `_owner._pendingListeners.Remove(_cacheKey)`

When both happen concurrently, the enumeration is invalidated by the modification.

## Planned Fix

Copy dictionary values to an array before iterating and clear the dictionary first:

```csharp
public void ClearCache()
{
    _localCache.Clear();
    _cachedSettings = null;
    _currentCacheKey = int.MinValue;
    _reportedException = null;

    // Copy to array and clear first to avoid modification during enumeration
    var listenersToClean = _pendingListeners.Values.ToArray();
    _pendingListeners.Clear();
    foreach (var listener in listenersToClean)
    {
        listener.Unlisten();
    }
}
```

This pattern:
1. Takes a snapshot of values to iterate
2. Clears the dictionary immediately (so Remove() calls find nothing)
3. Iterates the safe snapshot

## Files to Modify

- [x] `pwiz_tools/Skyline/Controls/Graphs/ReplicateCachingReceiver.cs`

## Progress

- [x] Created branch from master
- [x] Created TODO file
- [x] Analyzed source code and confirmed race condition
- [x] Implement fix
- [x] Local commit (8b03e6eaa5)
- [x] Update TODO with completion status
- [x] Build verification PASSED
- [x] Code review verified
- [x] Test verification PASSED (TestPeakPickingTutorial)

## Build Verification

**Build Status**: PASSED (2026-01-22)

Build completed successfully in the review worktree (`C:\proj\review`) in 38.9 seconds.

**Test Status**: PASSED (2026-01-22)

`TestPeakPickingTutorial` passed in 26.5 seconds:
- Memory: 16.13/13.27/126.2 MB
- Handles: 96/610
- No failures

**Important Note**: The race condition is intermittent, so a single passing test doesn't guarantee the fix but confirms the change doesn't break existing functionality. The fix pattern (copy-to-array-then-iterate) is a standard thread-safe approach for this class of problem.

## Completion Summary

**Commit**: 8b03e6eaa5 - Fixed threading race condition in ReplicateCachingReceiver.ClearCache

The fix copies `_pendingListeners.Values` to an array before iterating, then clears the dictionary.
This prevents `InvalidOperationException` when `OnProductAvailable()` on a background thread
calls `Remove()` during the `ClearCache()` enumeration.

## Notes

The fix pattern matches what was done for #3832 - copy-then-iterate is a standard thread-safe pattern for collections that may be modified during enumeration.
