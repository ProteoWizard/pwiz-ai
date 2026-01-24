# TODO-20260121_replicatecachingreceiver_threading.md

## Branch Information
- **Branch**: `Skyline/work/20260121_replicatecachingreceiver_threading`
- **Base**: `master`
- **Created**: 2026-01-21
- **Status**: Complete
- **GitHub Issue**: [#3857](https://github.com/ProteoWizard/pwiz/issues/3857)
- **PR**: [#3865](https://github.com/ProteoWizard/pwiz/pull/3865), [#3866](https://github.com/ProteoWizard/pwiz/pull/3866)

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

## Actual Fix

Changed `_pendingListeners` from `Dictionary<int, CompletionListener>` to `ConcurrentDictionary<int, CompletionListener>`:

```csharp
private readonly ConcurrentDictionary<int, CompletionListener> _pendingListeners =
    new ConcurrentDictionary<int, CompletionListener>();
```

Updated all access sites to use atomic operations:
- `TryRemove()` instead of `TryGetValue()` + `Remove()`
- `TryAdd()` instead of `ContainsKey()` check + indexer assignment

**Why not copy-to-array?** The initial approach (copy values to array before iterating) only narrows the race window - `ToArray()` itself iterates the dictionary internally and would throw the same exception if a background thread called `Remove()` during that operation.

`ConcurrentDictionary` is the correct solution because:
1. Its enumerators support safe iteration during concurrent modification (snapshots internally)
2. `TryAdd` atomically checks for existing key and adds if not present
3. `TryRemove` atomically removes and returns the value
4. Matches the existing pattern for `_localCache` (already a `ConcurrentDictionary`)

## Files to Modify

- [x] `pwiz_tools/Skyline/Controls/Graphs/ReplicateCachingReceiver.cs`

## Progress

- [x] Created branch from master
- [x] Created TODO file
- [x] Analyzed source code and confirmed race condition
- [x] Initial fix attempt (copy-to-array) - insufficient
- [x] Code review identified flaw in initial approach
- [x] Implemented proper fix using ConcurrentDictionary
- [x] Build verification PASSED
- [x] Test verification PASSED (30 iterations x 3 tests)
- [x] Created PR #3865
- [x] Cherry-picked to release branch (PR #3866)

## Completion Summary

**Commit**: 4a6c213434 - Fixed threading race condition in ReplicateCachingReceiver

Changed `_pendingListeners` from `Dictionary` to `ConcurrentDictionary` for true thread safety.
Updated all access sites to use `TryRemove`/`TryAdd` atomic operations.

**Test Validation**: 30 iterations each with 0 failures:
- TestPeakPickingTutorial (original nightly failure)
- TestPeakBoundaryImputationDiaTutorial
- TestPeakAreaRelativeAbundanceGraph

## Notes

The initial copy-to-array approach was insufficient - `ToArray()` itself iterates and could throw during concurrent modification. Using `ConcurrentDictionary` provides true thread safety and matches the pattern already used for `_localCache` in the same class.
