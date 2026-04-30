# FilesTree BackgroundActionService.Shutdown Deadlock

## Branch Information
- **Branch**: `Skyline/work/20260204_filestree_shutdown_deadlock`
- **Base**: `master`
- **Created**: 2026-02-04
- **Status**: Complete - Merged
- **Related**: PR #3743 (SafeBeginInvoke TOCTOU fix, improved in parallel)
- **GitHub Issue**: [#3934](https://github.com/ProteoWizard/pwiz/issues/3934)
- **PR**: [#3947](https://github.com/ProteoWizard/pwiz/pull/3947)
- **PR Merged**: 2026-02-04 (PST)
- **Cherry-pick**: [#3951](https://github.com/ProteoWizard/pwiz/pull/3951) (merged to Skyline/skyline_26_1)
- **Test Name**: TestEditSpectrumFilter
- **Fix Type**: hang

## Objective

Fix deadlock in `BackgroundActionService.Shutdown()` when called from the UI thread during `FilesTree.Dispose()`. Consumer threads with pending `RunUI` calls post work via `Control.BeginInvoke`, but the UI thread is blocked in `_threadExit.Wait()` and can't process those messages.

## Tasks

- [x] Investigate deadlock mechanism
- [x] Add `_isShutdown` flag to `BackgroundActionService`
- [x] Guard `RunUI()` and `AddTask()` with shutdown check
- [x] Fix existing `_pendingActionCount` leak when `SafeBeginInvoke` returns false
- [x] Build and run TestEditSpectrumFilter
- [x] Run FilesTree coverage tests (TestFilesModel, TestFilesTreeFileSystem, TestFilesTreeForm, TestSkylineWindowEvents)

## Plan

### Fix: Shutdown Flag in BackgroundActionService

Add a `volatile bool _isShutdown` field. Set it **before** `DoneAdding(true)` in `Shutdown()`. Check it in `RunUI()` and `AddTask()` to skip work when shutting down.

This breaks the deadlock because consumer threads that have already dequeued an item will skip the `BeginInvoke` call and finish quickly, allowing them to signal `_threadExit`.

### File to Change

`pwiz_tools/Skyline/Controls/FilesTree/BackgroundActionService.cs` — only file modified.

### Changes

1. Add `private volatile bool _isShutdown;` field
2. Set `_isShutdown = true` as first line in `Shutdown()`, before `Clear()` and `DoneAdding(true)`
3. Add `if (_isShutdown) return;` as first guard in `RunUI()`
4. Add `if (_isShutdown) return;` as first guard in `AddTask()`
5. Fix `RunUI()` to decrement `_pendingActionCount` when `SafeBeginInvoke` returns false (existing bug)

### Why Not Other Options

- **Message pumping (`Application.DoEvents`)**: Risky in dispose path — can re-enter event handlers
- **Non-blocking dispose (`DoneAdding(false)`)**: Consumer threads may access disposed controls

## Progress Log

### 2026-02-04 - Session 1

- Implemented `_isShutdown` volatile flag in `BackgroundActionService`
- Added early-out checks in `RunUI()` and `AddTask()`
- Set `_isShutdown = true` as first action in `Shutdown()`
- Fixed `_pendingActionCount` leak in `RunUI()` when `SafeBeginInvoke` returns false
- Build succeeded, TestEditSpectrumFilter passed
- Ran 4 FilesTree coverage tests (all passed)
- Also improved PR #3743 in parallel (pwiz-work2): extracted `IClosingAware` interface,
  added `IsClosingOrDisposing` to `DockableFormEx`, updated `SafeBeginInvoke` to check
  interface instead of concrete type
