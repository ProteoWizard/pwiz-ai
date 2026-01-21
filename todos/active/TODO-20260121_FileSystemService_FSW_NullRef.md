# FileSystemService FSW event handlers can crash TestRunner with unhandled NullReferenceException

## Branch Information
- **Branch**: `Skyline/work/20260121_FileSystemService_FSW_NullRef`
- **Base**: `master`
- **Created**: 2026-01-21
- **GitHub Issue**: https://github.com/ProteoWizard/pwiz/issues/3845

## Objective

Fix race condition in FileSystemWatcher event handlers in `LocalFileSystemService` that can throw unhandled `NullReferenceException` on I/O completion port threads, causing TestRunner.exe to terminate with exit code -1.

## Tasks

- [ ] Add `_isStopped` check at start of FSW event handlers:
  - [ ] `FileSystemWatcher_OnDeleted` (line 508)
  - [ ] `FileSystemWatcher_OnCreated` (line 542)
  - [ ] `FileSystemWatcher_OnRenamed` (line 575)
  - [ ] `FileSystemWatcher_OnError` (line 353) - verify if needed
- [ ] Add defensive try-catch wrapper to each handler to prevent process termination
- [ ] Write or extend test to verify handlers are robust during shutdown
- [ ] Verify fix addresses the KAIPO-DEV crash scenario

## Progress Log

### 2026-01-21 - Session Start

Starting work on this issue. The root cause is documented in the issue:
1. Race condition: FSW handlers don't check `_isStopped` before accessing disposed resources
2. No exception handling: Unhandled exceptions on I/O completion port threads terminate the process

Evidence from KAIPO-DEV run 80126 shows crash at line 533 in `FileSystemWatcher_OnDeleted` when `BackgroundActionService` is null after `StopWatching()` was called.
