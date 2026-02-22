# TODO: ConnectionPool file lock leak diagnostics

**Created**: 2026-02-22
**Branch**: `Skyline/work/20260222_connectionpool_leak_diagnostics`
**Status**: Planning

## Goal

Improve ConnectionPool diagnostic infrastructure so that intermittent file lock
failures in tests produce actionable root-cause information instead of cryptic
"couldn't delete directory" errors.

## Background

Skyline's immutable document model uses `ConnectionPool` to manage mutable file
handles (.skyd, .blib, .irtdb). When tests end, `EndTest()` switches to an empty
document and waits for the pool to drain. Intermittent failures occur when connections
aren't released in time, but the current diagnostics only report
`"{GlobalIndex}. {TypeName}"` — not enough to identify the cause.

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
* Optionally add `string FilePath` to `IPooledStream` for uniform access

### Layer 2: Reorder EndTest() cleanup

* Move `WaitForBackgroundLoaders()` BEFORE the pool drain check
* `CloseRemovedStreams` runs inside BackgroundLoaders, so checking the pool before
  they finish is checking too early
* Current order: `SwitchDocument -> wait 1s for pool -> WaitForBackgroundLoaders`
* New order: `SwitchDocument -> WaitForBackgroundLoaders -> wait for pool`
* This alone may fix some intermittent failures

### Layer 3: Pool connection tracking seam

* Add `static bool TrackHistory` flag on `ConnectionPool` (default false)
* When enabled, record connect/disconnect events in a
  `Dictionary<int, List<PoolEvent>>` on the pool:
  - Event type (Connect / Disconnect / DisconnectWhile)
  - Timestamp
  - Stack trace (or `[CallerFilePath]`/`[CallerLineNumber]`)
* `ReportPooledConnections()` includes full history for still-open connections
  when tracking is enabled
* Zero overhead when `TrackHistory` is false

### Layer 4: Assert on leaked connections in EndTest

* After the reordered wait + pool check, if connections remain open:
  - If tracking is on: dump full connect/disconnect history per connection
  - Add a `TestException` so the failure shows up in nightly reports as a proper
    test failure with root-cause information
  - Include file paths from Layer 1

## Key Files

| File | What changes |
|------|-------------|
| `pwiz_tools/Skyline/Util/UtilIO.cs` | ConnectionPool tracking, PooledFileStream.ToString, PooledSessionFactory.ToString |
| `pwiz_tools/Skyline/Util/PooledSqliteConnection.cs` | PooledSqliteConnection.ToString |
| `pwiz_tools/Skyline/TestUtil/TestFunctional.cs` | EndTest() reorder and enhanced reporting |
| `pwiz_tools/Skyline/Model/BackgroundLoader.cs` | Potential tracking integration |

## Test Plan

- [ ] Verify `ReportPooledStreams()` output includes file paths (manual inspection)
- [ ] Verify EndTest() reorder: `WaitForBackgroundLoaders` before pool check
- [ ] Verify `ConnectionPool.TrackHistory = true` records events correctly
- [ ] Verify tracking output for a deliberately leaked connection in a test
- [ ] Verify zero overhead when `TrackHistory = false`
- [ ] Run full test suite to check for regressions

## Progress

* 2026-02-22: Created TODO, wrote architecture-files.md documentation
