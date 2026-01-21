# FileSystemService FSW event handlers can crash TestRunner with unhandled NullReferenceException

## Branch Information
- **Branch**: `Skyline/work/20260121_FileSystemService_FSW_NullRef`
- **Base**: `master`
- **Created**: 2026-01-21
- **GitHub Issue**: https://github.com/ProteoWizard/pwiz/issues/3845

## Objective

Fix race condition in FileSystemWatcher event handlers in `LocalFileSystemService` that can throw unhandled `NullReferenceException` on I/O completion port threads, causing TestRunner.exe to terminate with exit code -1.

## Tasks

- [x] Add `_isStopped` check at start of FSW event handlers:
  - [x] `FileSystemWatcher_OnDeleted`
  - [x] `FileSystemWatcher_OnCreated`
  - [x] `FileSystemWatcher_OnRenamed`
  - [x] `FileSystemWatcher_OnError`
- [x] Add defensive try-catch wrapper to each handler to prevent process termination
- [x] Move `_isStopped = true` to start of `StopWatching()` for proper ordering
- [x] Verify fix with existing tests (TestFilesTreeFileSystem + Files view coverage tests)

## Progress Log

### 2026-01-21 - Session Start

Starting work on this issue. The root cause is documented in the issue:
1. Race condition: FSW handlers don't check `_isStopped` before accessing disposed resources
2. No exception handling: Unhandled exceptions on I/O completion port threads terminate the process

Evidence from KAIPO-DEV run 80126 shows crash at line 533 in `FileSystemWatcher_OnDeleted` when `BackgroundActionService` is null after `StopWatching()` was called.

### 2026-01-21 - Implementation Complete

Implemented DRY solution with `SafeInvokeFswHandler()` helper method that:
1. Checks `_isStopped` first (early exit before any work)
2. Wraps the action in try-catch to swallow exceptions on background threads

Refactored all 4 FSW event handlers to use the helper:
- `FileSystemWatcher_OnDeleted` → calls `HandleFileDeleted(fullPath)`
- `FileSystemWatcher_OnCreated` → calls `HandleFileCreated(fullPath)`
- `FileSystemWatcher_OnRenamed` → calls `HandleFileRenamed(oldFullPath, fullPath)`
- `FileSystemWatcher_OnError` → calls `HandleFswError(directoryPath, exception)`

Also moved `_isStopped = true` to the **start** of `StopWatching()` so the flag is set before any cleanup begins, eliminating the window where events could arrive during cleanup.

**Tests passed:**
- TestFilesModel (9s)
- TestFilesTreeFileSystem (4s)
- TestFilesTreeForm (28s)
- TestSkylineWindowEvents (0s)

### 2026-01-21 - PR Review Feedback

Addressed Copilot review feedback on PR #3851:

1. **Silent exception swallowing** - Changed to use `ExceptionUtil.IsProgrammingDefect()` to distinguish:
   - Programming defects (NRE, IndexOutOfRange) → report via `Program.ReportException()` so tests fail
   - Expected FSW exceptions (IOException from network disconnects) → silently ignore
   - ObjectDisposedException → silently ignore (expected during cleanup race)

2. **OnError race condition** - Moved `fsw.Path` and `e.GetException()` access inside `SafeInvokeFswHandler()` protection

Design principle: Files view is auxiliary UI; its background processing should never interrupt user workflow with message boxes.
