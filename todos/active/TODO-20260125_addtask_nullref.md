# BackgroundActionService.AddTask NullReferenceException Fix

## Branch Information
- **Branch**: `Skyline/work/20260125_addtask_nullref`
- **Base**: `master`
- **Created**: 2026-01-25
- **GitHub Issue**: https://github.com/ProteoWizard/pwiz/issues/3864

## Objective

Fix NullReferenceException when `BackgroundActionService.AddTask` is called after the service has been disposed, which occurs during FileSystemWatcher event callbacks racing with control disposal.

## Tasks

- [ ] Apply thread-safe fix to `BackgroundActionService.AddTask` method
- [ ] Capture queue reference in local variable before null check
- [ ] Add exception handling for disposal race conditions
- [ ] Verify fix prevents NullReferenceException in TestSmallMoleculesQuantificationTutorial

## Progress Log

### 2026-01-25 - Session Start

Starting work on this issue. The fix involves capturing the `_workItems` queue reference in a local variable and handling disposal exceptions appropriately.
