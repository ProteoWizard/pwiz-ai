# TODO-20260224_connectionpool_unit_test_cleanup.md

## Branch Information
- **Branch**: `Skyline/work/20260224_connectionpool_unit_test_cleanup`
- **Base**: `master`
- **Created**: 2026-02-24
- **Status**: In Review
- **GitHub Issue**: (none - bug fix for PR #4033)
- **PR**: #4038 (full cleanup), #4037 (minimal fix, merged)

## Context

PR #4033 added ConnectionPool tracking but only wired cleanup into the functional test
path. Since `TrackHistory` was a static bool that stayed `true` once any functional test
set it, all subsequent unit tests accumulated `StackTrace` strings in `_history`, causing
93 tests to show as memory leaks in nightly runs.

## Tasks

- [x] Change `PoolEvent` to store lazy `System.Diagnostics.StackTrace` instead of string
- [x] Add ConnectionPool tracking init/cleanup to `AbstractUnitTest`
- [x] Scope functional test tracking to `WaitForSkyline()` via `ScopedAction`
- [x] Fix Quality tab Pass 1 skip bug (added `qualityonly` flag)
- [x] Fix dotMemory snapshot regression from PR #4034
- [x] Add `dotmemoryattests` feature for targeted memory snapshots
- [x] Address Copilot review: move ScopedAction to cover EndTest()
- [x] Address Nick's review: make TrackHistory an instance field
- [x] Remove HasPooledStreams/ReportPooledStreams from IStreamManager interface
- [x] Add StartTrackingHistory/EndTrackingHistory methods to ConnectionPool and FileStreamManager
- [x] ReportPooledConnections returns null when no connections open
- [x] Merge master after #4037 merged, resolve conflict
- [x] Build, CodeInspection, and reproduction test all pass

## Key Design Decisions

1. **Two PRs**: #4037 (3-line minimal fix) merged immediately to fix nightly leaks.
   #4038 (full cleanup) follows with all improvements.
2. **TrackHistory as instance field**: Nick's review pointed out the static was the root
   problem. Making it per-instance on ConnectionPool eliminates cross-test contamination
   and makes FileStreamManager the clean interface for test code.
3. **Rejected HistoryTracking IDisposable class**: Added complexity (fields, null checks,
   split reporting paths) without clear benefit for test infrastructure code.
4. **StartTrackingHistory/EndTrackingHistory**: Named methods with clear semantics.
   Start clears stale history then enables. End disables then clears to free memory.

## Files Modified
- `pwiz_tools/Skyline/Util/UtilIO.cs` - Instance TrackHistory, Start/End methods, null return
- `pwiz_tools/Skyline/TestUtil/AbstractUnitTest.cs` - Init/cleanup through FileStreamManager
- `pwiz_tools/Skyline/TestUtil/TestFunctional.cs` - ScopedAction with method groups
- `pwiz_tools/Skyline/TestUtil/MemoryStreamManager.cs` - Removed unused members
- `pwiz_tools/Skyline/Test/ConnectionPoolTest.cs` - Updated for new API
- `pwiz_tools/Skyline/SkylineTester/TabQuality.cs` - qualityonly flag
- `pwiz_tools/Skyline/TestRunner/Program.cs` - qualityonly, dotMemory fixes
- `pwiz_tools/Skyline/TestRunnerLib/RunTests.cs` - dotmemoryattests feature
