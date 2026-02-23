# TODO: ConnectionPool file lock leak diagnostics

**Created**: 2026-02-22
**Branch**: `Skyline/work/20260222_connectionpool_leak_diagnostics`
**Status**: Ready for PR

## Goal

Improve ConnectionPool diagnostic infrastructure so that intermittent file lock
failures in tests produce actionable root-cause information instead of cryptic
"couldn't delete directory" errors.

## Background

Skyline's immutable document model uses `ConnectionPool` to manage mutable file
handles (.skyd, .blib, .irtdb). When tests end, `EndTest()` switches to an empty
document and waits for the pool to drain. Intermittent failures occur when connections
aren't released in time, but the current diagnostics only report
`"{GlobalIndex}. {TypeName}"` -- not enough to identify the cause.

Nick's current workflow: manually instrument `ConnectionPool` with addref/release
tracking to reproduce and diagnose. The fix is usually adding `WaitForCondition()`
to the test (the race is test-only, not user-facing). We want to formalize this
instrumentation as a permanent test seam.

See: `ai/docs/architecture-files.md` for full architecture documentation.

## Design

Four layers, implemented incrementally:

### Layer 1: Make ReportPooledConnections useful

* Override `ToString()` on `PooledFileStream`, `PooledSqliteConnection`, and
  `PooledSessionFactory` to include the file path
* Changes `"42. pwiz.Skyline.Util.PooledFileStream"` into
  `"42. PooledFileStream(C:\TestResults\data.skyd)"`
* Added `string FilePath` to `IPooledStream` for uniform access
* Changed `ConnectionPool._connections` dictionary key from `int` to
  `ReferenceValue<Identity>` so the report can access the Identity object
  and its `ToString()` override

### Layer 2: Reorder EndTest() cleanup

* Move `WaitForBackgroundLoaders()` BEFORE the pool drain check
* `CloseRemovedStreams` runs inside BackgroundLoaders, so checking the pool before
  they finish is checking too early
* Current order: `SwitchDocument -> wait 1s for pool -> WaitForBackgroundLoaders`
* New order: `SwitchDocument -> WaitForBackgroundLoaders -> wait for pool`
* This alone may fix some intermittent failures

### Layer 3: Pool connection tracking seam

* Add `static bool TrackHistory` flag on `ConnectionPool` (default false)
* When enabled, record connect/disconnect events with `Environment.StackTrace`
  in a `Dictionary<int, List<PoolEvent>>` on the pool:
  - Event type (Connect / Disconnect / DisconnectWhile)
  - Timestamp
  - Full stack trace
* `ReportPooledConnections()` includes full history with stack traces for
  still-open connections when tracking is enabled
* Zero overhead when `TrackHistory` is false
* Public static format helpers (`FormatConnectionLine`, `FormatEventLine`)
  for testable output

### Layer 4: Assert on leaked connections in EndTest

* `RunTest()` enables `TrackHistory` and clears history at test start
* After the reordered wait + pool check, if connections remain open:
  - Dump full connect/disconnect history with stack traces per connection
  - Add a `TestException` via `Program.AddTestException` so the failure
    shows up in nightly reports as a proper test failure with root-cause info
  - Include file paths from Layer 1

## Key Files

| File | What changes |
|------|-------------|
| `pwiz_tools/Skyline/Util/UtilIO.cs` | ConnectionPool ReferenceValue key, tracking, PoolEvent, ToString overrides |
| `pwiz_tools/Skyline/Util/PooledSqliteConnection.cs` | Public FilePath, ToString override |
| `pwiz_tools/Skyline/TestUtil/TestFunctional.cs` | EndTest() reorder, TrackHistory enable, enhanced reporting |
| `pwiz_tools/Skyline/TestUtil/MemoryStreamManager.cs` | FilePath on MemoryPooledStream for IPooledStream |
| `pwiz_tools/Skyline/Test/ConnectionPoolTest.cs` | Unit test for pool report and tracking |
| `pwiz_tools/Skyline/Test/Test.csproj` | New test file reference |

## Test Plan

- [x] Verify `ReportPooledStreams()` output includes file paths (unit test)
- [x] Verify EndTest() reorder: `WaitForBackgroundLoaders` before pool check
- [x] Verify `ConnectionPool.TrackHistory = true` records events correctly (unit test)
- [x] Verify tracking output includes stack traces with caller info (unit test)
- [x] Verify zero overhead when `TrackHistory = false` (unit test + 3080-test smoke run)
- [x] Run full test suite to check for regressions (3080 tests, 3 languages, all passed)
- [x] Performance comparison: 58 min with tracking vs 57 min without (within variance)

## Progress

* 2026-02-22: Created TODO, wrote architecture-files.md documentation
* 2026-02-22: Implemented all 4 layers, unit test, full smoke test passed
