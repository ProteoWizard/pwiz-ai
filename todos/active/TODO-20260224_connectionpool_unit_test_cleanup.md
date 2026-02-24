# TODO-20260224_connectionpool_unit_test_cleanup.md

## Branch Information
- **Branch**: `Skyline/work/20260224_connectionpool_unit_test_cleanup`
- **Base**: `master`
- **Created**: 2026-02-24
- **Status**: In Progress
- **GitHub Issue**: (none - bug fix for PR #4033)
- **PR**: (pending)

## Context

PR #4033 (`e5febdda1`) added ConnectionPool tracking and leak reporting but only wired
cleanup into the functional test path (`TestFunctional.RunTest()`/`EndTest()`). Unit tests
have no ConnectionPool cleanup at all. Since `ConnectionPool.TrackHistory` is a static bool
that stays `true` once any functional test sets it, all subsequent unit tests accumulate
`Environment.StackTrace` strings in `_history` without ever clearing them. This causes
run-to-run memory growth detected as 93 memory leaks in nightly run #80975.

Additionally, `Environment.StackTrace` resolves the full stack trace to a `string` at
capture time, which is wasteful. `new StackTrace(true)` stores `StackFrame[]` and only
resolves to text on `ToString()`.

## Tasks

- [ ] Change `PoolEvent` to store `System.Diagnostics.StackTrace` instead of `string`
- [ ] Add ConnectionPool init to `AbstractUnitTest.MyTestInitialize()`
- [ ] Add ConnectionPool check + cleanup to `AbstractUnitTest.MyTestCleanup()`
- [ ] Update `ConnectionPoolTest.cs` for new `StackTrace` type
- [ ] Build and test

## Plan

### 1. UtilIO.cs - Lazy StackTrace in PoolEvent

- `PoolEvent.StackTrace`: `string` -> `System.Diagnostics.StackTrace`
- Constructor param: `string stackTrace` -> `System.Diagnostics.StackTrace stackTrace`
- `RecordEvent()`: `Environment.StackTrace` -> `new StackTrace(true)`
- `FormatEventLine()`: `string.IsNullOrEmpty(...)` -> `== null`
- `ToDetailString()`: no change (interpolation calls `.ToString()`)

### 2. AbstractUnitTest.cs - ConnectionPool tracking and cleanup

**MyTestInitialize()**: Add `ConnectionPool.TrackHistory = true` and `ClearHistory()`

**MyTestCleanup()**: Before `CleanupFiles()`:
- Check `HasPooledStreams`, capture report if true
- Call `CloseAllStreams()` to release handles and clear history
- After `CleanupFiles()`: `Assert.Fail` with pool report if streams were leaked

### 3. ConnectionPoolTest.cs

- Update PoolEvent construction to pass `null` instead of `string.Empty`

## Files to Modify
- `pwiz_tools/Skyline/Util/UtilIO.cs`
- `pwiz_tools/Skyline/TestUtil/AbstractUnitTest.cs`
- `pwiz_tools/Skyline/Test/ConnectionPoolTest.cs`
