# ProductionFacility.Unlisten Race Condition Fix

## Branch Information
- **Branch**: `Skyline/work/20260120_ProductionFacility_Unlisten`
- **Base**: `master`
- **Created**: 2026-01-20
- **GitHub Issue**: https://github.com/ProteoWizard/pwiz/issues/3832

## Objective

Fix race condition where `ProductionFacility.Unlisten` throws `InvalidOperationException` when attempting to unlisten from a WorkOrder that was already removed by another thread.

## Root Cause

Race condition between entry cleanup and unlisten operations:
1. Thread A calls `AfterLastListenerRemoved()` which executes `Cache.RemoveEntry(this)`
2. Thread B calls `Unlisten()` for the same or a dependent WorkOrder
3. Thread B's `GetEntry()` runs AFTER Thread A removed the entry, throwing the exception

## Fix Applied

Made both `Unlisten` and `AfterLastListenerRemoved` tolerant of missing entries:

1. **Unlisten** - Use `TryGetValue` instead of `GetEntry` (which throws)
2. **AfterLastListenerRemoved** - Check if dependency entry exists before calling `RemoveListener`

## Tasks

- [x] Create branch from master
- [x] Fix `Unlisten` to handle missing entries gracefully
- [x] Fix `AfterLastListenerRemoved` to handle missing dependency entries
- [x] Verify build succeeds
- [ ] Create PR

## Files Modified

1. **pwiz_tools/Shared/CommonUtil/SystemUtil/Caching/ProductionFacility.cs**
   - `Unlisten()`: Changed from `GetEntry(key).RemoveListener()` to `TryGetValue` check
   - `AfterLastListenerRemoved()`: Changed from `Cache.GetEntry(input)` to `Cache._entries.TryGetValue()`

## Progress Log

### 2026-01-20 - Fix Implemented

- Created branch `Skyline/work/20260120_ProductionFacility_Unlisten`
- Applied fix to make `Unlisten` and `AfterLastListenerRemoved` tolerant of missing entries
- Build verified successful
