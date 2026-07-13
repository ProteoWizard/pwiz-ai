# TODO: Use ExceptionDispatchInfo to rethrow stored exceptions

- **Branch:** `Skyline/work/20260713_exception_dispatch_info`
- **Base:** `master`
- **Created:** 2026-07-13
- **Status:** Active

## Objective

`ExceptionUtil.WrapAndThrowException` rethrew an exception caught on another thread by
re-wrapping it in a new exception of the same type, but only for a short hard-coded list
of types (`InvalidDataException`, `IOException`, `OperationCanceledException`,
`UnauthorizedAccessException`, `UserMessageException`); everything else became a
`TargetInvocationException`. `ExceptionDispatchInfo` does this properly: it preserves
every exception type and the original stack trace from the throw site, instead of the
stack trace of the rethrow.

Requested by Nick.

## Implementation

- `ExceptionUtil.WrapAndThrowException` is now `ExceptionDispatchInfo.Capture(x).Throw()`.
  Dropped the `Assume.IsTrue(IsProgrammingDefect(x))` (only guarded the fall-through to
  `TargetInvocationException`) and the note on `IsProgrammingDefect` about keeping its
  list in sync.
- Two other copies of the same type-list logic replaced:
  - `ParallelEx.LoopWithExceptionHandling` (CommonUtil; was missing the
    `UserMessageException` case, so those arrived as `TargetInvocationException`).
  - `SharedBatchTest/Helpers.WrapAndThrowException` (was missing both
    `UnauthorizedAccessException` and `UserMessageException`).
- Two hand-rolled `TargetInvocationException` rethrows of a stored exception now use
  `WrapAndThrowException`: `ToolService.GetSelectedElementLocator` and
  `SkylineWindow.OnClosing` (`Settings.Default.SaveException`). Safe for `OnClosing`
  because the unhandled-exception handler shows `ReportErrorDlg` for any type - it never
  consulted `IsProgrammingDefect` - so the wrap was not needed to force reporting.
- Consumers that existed only to undo the old wrapping were cleaned up:
  `ToolInstallUI` (dug `JsonReaderException` out of a `TargetInvocationException`),
  `BiblioSpecLite.Load` (`x is TargetInvocationException && x.InnerException is
  SQLiteException`), and `JsonUiService.InvokeOnUiThread` (special case for
  `ArgumentException`). `JsonToolServer` keeps its `catch (TargetInvocationException)` -
  that one catches genuine `MethodInfo.Invoke` wrappers.
- `SkylineWindow.SaveDocument`'s "silent failure is OK" block was catching
  `TargetInvocationException`, which meant it silently swallowed programming defects from
  `SaveLayout`/`OptimizeCache`. It now uses `ExceptionUtil.IsProgrammingDefect` and calls
  `Program.ReportException` for defects, since the document is already saved and the
  method has more work to do.

Left alone: `ProcessRunner.ThrowExceptionWithOutput` (rebuilds the exception to append
captured stdout to the message, so it cannot be a plain rethrow) and
`SkylineTool/RemoteClient` (wraps an exception deserialized from another process, where
there is no local stack to preserve).

## Tests

No new tests. No existing test depended on the `TargetInvocationException` wrapping.

## Status

- [x] Implementation complete
- [x] Build clean
- [x] Tests pass (UtilTest, ParallelEx tests, TestToolService)
- [ ] PR created
