# Listener Cleanup and RetentionTimeManagerTest Fix

## Branch Information
- **Branch**: `Skyline/work/20260119_ListenerCleanup`
- **Base**: `master`
- **Created**: 2026-01-19
- **GitHub Issue**: None (cleanup discovered during #3833 investigation)
- **Related Issue**: https://github.com/ProteoWizard/pwiz/issues/3838 (RetentionTimeManagerTest failures)
- **PR**: https://github.com/ProteoWizard/pwiz/pull/3852

## Objective

Clean up BackgroundLoader listener registration/unregistration and fix file locking issue in RetentionTimeManagerTest. These issues were discovered during the handle leak investigation but are unrelated to the root cause fix in PR #3836.

## Background

While investigating the handle leak in TestSmallMolMethodDevCEOptTutorial, we discovered:

1. **BackgroundLoader.Unregister() not called on dispose** - When document containers are disposed, they should unregister from BackgroundLoaders to prevent potential event handler leaks.

2. **RetentionTimeManagerTest file locking failures** - The test was failing intermittently (within 10-20 runs) due to file locking during cleanup. The test was saving and reopening a file without waiting for it to load, and the reopen had no clear purpose or validation.

## Tasks

- [x] Add `loader.Unregister(this)` call in `Skyline.OnClosed()`
- [x] Add `.ToList()` to BackgroundLoaders enumeration to avoid modification during iteration
- [x] Add `loader.Unregister(this)` call in `MemoryDocumentContainer.Dispose()`
- [x] Add `using System.Linq` to MemoryDocumentContainer.cs
- [x] Make `SkylineWindow.Listen()` an explicit interface implementation
- [x] Fix RetentionTimeManagerTest file locking (remove unnecessary save/reopen)
- [x] Verify with multi-pass testing

## Files to Modify

1. **pwiz_tools/Skyline/Skyline.cs**
   - `OnClosed()`: Add `loader.Unregister(this)` and `.ToList()` for safe enumeration
   - `Listen()`: Change to explicit interface implementation `void IDocumentContainer.Listen(...)`

2. **pwiz_tools/Skyline/Model/MemoryDocumentContainer.cs**
   - Add `using System.Linq`
   - `Dispose()`: Add `loader.Unregister(this)` call

3. **pwiz_tools/Skyline/TestFunctional/RetentionTimeManagerTest.cs**
   - Remove unnecessary save/reopen that caused file locking during cleanup

## Stashed Changes

The initial implementation is stashed:
```
stash@{0}: On 20260118_SmallMolMethodDevCEOptTutorial_HandleLeak: Listen/Unlisten cleanup for separate PR
```

## Progress Log

### 2026-01-19 - TODO Created

- Created TODO for listener cleanup work discovered during handle leak investigation
- Changes are stashed, ready to be applied to a new branch

### 2026-01-19 - Changes Applied

- Created branch from updated master
- Applied stashed changes
- Committed locally (not pushed)
- RetentionTimeManagerTest still failing intermittently - waiting on #3838 investigation before PR

### 2026-01-21 - PR Created

- Rebased onto master (incorporates Nick's fix #3846 for WaitForDocumentLoaded)
- Simplified RetentionTimeManagerTest: removed early Unlisten, let ScopedAction handle cleanup
- Ran 100+ iterations of TestRetentionTimeManager with 0 failures
- Full parallel test run (3000+ tests) in 3 languages (en, zh, fr) passed
- Created PR #3852
