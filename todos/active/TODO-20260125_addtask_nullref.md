# BackgroundActionService.AddTask NullReferenceException Fix

## Branch Information
- **Branch**: `Skyline/work/20260125_addtask_nullref`
- **Base**: `master`
- **Created**: 2026-01-25
- **GitHub Issue**: https://github.com/ProteoWizard/pwiz/issues/3864

## Objective

Fix NullReferenceException when `BackgroundActionService.AddTask` is called after the service has been disposed, which occurs during FileSystemWatcher event callbacks racing with control disposal.

## Tasks

- [x] Apply thread-safe fix to `BackgroundActionService.AddTask` method
- [x] Capture queue reference in local variable before null check
- [x] Add exception handling for disposal race conditions
- [x] Verify fix with Files view tests (TestFilesModel, TestFilesTreeFileSystem, TestFilesTreeForm, TestSkylineWindowEvents)

## Progress Log

### 2026-01-25 - Session Start

Starting work on this issue. The fix involves capturing the `_workQueue` queue reference in a local variable and handling disposal exceptions appropriately.

### 2026-01-25 - Fix Applied

Applied thread-safe fix to `AddTask` method:
1. Capture `_workQueue` reference in local `queue` variable before null check
2. Return early if already disposed (queue == null)
3. Add try/catch around `queue.Add()` to handle race conditions:
   - `InvalidOperationException`: DoneAdding was called but Dispose not yet complete
   - `ObjectDisposedException`: Dispose already called on the underlying BlockingCollection
4. Decrement `_pendingActionCount` in catch block to maintain accurate count

Note: Used C# 8.0 compatible syntax (`||` instead of `or` pattern) since Skyline targets C# 8.0.

Build succeeded.

### 2026-01-25 - Tests Passed

Ran 4 Files view tests that exercise BackgroundActionService:
- TestFilesModel (24 sec) - Pass
- TestFilesTreeFileSystem (4 sec) - Pass
- TestFilesTreeForm (29 sec) - Pass
- TestSkylineWindowEvents (0 sec) - Pass

All tests passed. Ready for commit.
