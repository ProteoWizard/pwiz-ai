# TODO-20260806_api_cancel_jobs.md

## Branch Information
- **Branch**: `Skyline/work/20260806_api_cancel_jobs`
- **Base**: `master`
- **Created**: 2026-08-06
- **Status**: In Progress
- **GitHub Issue**: none
- **Module**: `skyline`
- **PR**: (pending)

## Motivation

A long `IJsonToolService` call could not be got out of. Two gaps:

1. **The server did not notice a client that had gone.** A verb that watches the
   request cancellation itself (anything driving the UI thread through
   `DialogWatcher`) let go when the client disconnected, but a verb with no such
   wait - a report export grinding through rows - had nothing to notice it with,
   and ran on the server's one thread. The pipe server is single-instance, so the
   next connection could not be served until the export finished. The MCP drops
   the pipe after 30 seconds; a two-minute export locked Skyline's tool service
   out for the rest of it.
2. **There was no way to ask what was still running, or to stop it.** The advice
   in the MCP's timeout message was to find the operation's progress dialog and
   press Cancel - which only works for work that has a dialog.

## What changed

**`JobProgressStatus : ProgressStatus`** (`ToolsUI/JobProgressStatus.cs`) - a
`JobId` (GUID) and a fixed `Description`, alongside the inherited Message the
work rewrites as it advances. Being this type is what makes an operation the
client's to control: `SkylineWindow`'s progress list holds everything that
reports progress, and a results import or library build the user started is not
a tool's business to cancel. Identity only - the cancellation is NOT on the
status, which is immutable and freely copied (a new copy per progress update),
leaving no one owner for a `CancellationTokenSource`.

**`JsonToolServer` owns the cancellations** in a static
`Dictionary<Guid, CancellationTokenSource>`. `RunJob(description, work)` creates
the source, registers it under the job id, reports the job to the main window
(status bar + the list `GetRunningJobs` reads), and in its finally reports the
final status and removes + disposes the source. Both the cancel and the disposal
happen under the dictionary's lock, so a source cannot be disposed out from under
a cancel.

**Two new verbs** on `IJsonToolService` (+ `SkylineJsonToolClient`,
`SkylineConnection`, and `skyline_get_running_jobs` / `skyline_cancel_job`):

- `GetRunningJobs()` -> `JobInfo[]` (id, description, message, percent,
  cancel_requested), read from a new `SkylineWindow.ProgressStatuses` snapshot
  filtered with `OfType<JobProgressStatus>()`.
- `CancelJob(jobId)` -> `ActionResult`. `Completed = false` (not an error) when
  no job has that id - the usual cause is that it finished between the list and
  the cancel.

**Every request is served on its own thread.** `HandleRequestWatchingForDisconnect`
starts the request with `ActionUtil.RunAsync` and then waits on the server thread
with `finished.Wait(DISCONNECT_POLL_MILLIS)`, peeking the pipe on each wake. On a
disconnect it cancels the request token and returns while the WORK GOES ON - which
is what frees the single-instance server for the connection that then lists and
cancels the job. This replaced the separate watchdog thread (same two threads per
request as before; the difference is which one can be abandoned). Cancelling the
token could never have freed the server thread on its own: it does not unblock a
thread that is not watching it, and killing the work on disconnect is the wrong
semantics anyway - a 30-second client timeout must not abort a legitimate
two-minute export.

**The four report verbs run as jobs** - `ExportReport`,
`ExportReportFromDefinition`, `GetReportRows`, `GetReportFromDefinitionRows`.
They report progress against the job status, take the job token where they used
to pass `CancellationToken.None`, and report through a `JobProgressMonitor` that
forwards to the main window but answers `IsCanceled` from the token -
`SkylineWindow` reports canceled only when it is closing, so the exporter's
per-row check would never have seen a `CancelJob`. A cancelled export throws
before `saver.Commit()`, so no partial file is left.

`_currentLog` became thread-local, like `_requestCancellation`: an abandoned
request goes on running while the next one is served, and the two must not write
into each other's diagnostic log.

## Verification

- New `JsonToolJobsTest` (TestFunctional), over a real pipe connection: a job
  started through `JsonToolServer.RunJob` is listed with its id/description,
  progress that is NOT a job (a plain `ProgressStatus`) is not listed, `CancelJob`
  stops it, an unknown id reports `Completed = false`, a malformed id is an
  `ERROR_INVALID_PARAMS`, and a finished verb leaves no job behind.
- `TestJsonToolServer`, `TestMcpConnectorDisconnect`, `TestRunCommandMcpConnector`,
  `TestNativeMessageBox`, `TestPrmMcpConnector`, `CodeInspection` all pass.
- ReSharper QuickInspection: zero warnings.

## Remaining

- **`SkylineAiConnector.zip` rebuild (Nick, in Visual Studio).** `SkylineMcpTest`
  diffs the `[McpServerTool]` names in source against the ZIP's advertised list,
  so it fails until the ZIP is rebuilt from `SkylineMcp.sln` with the two new
  tools. `EXPECTED_ZIP_VERSION` is already set to `26.1.1.218` to match what
  `PackageToolZip` stamps from `AssemblyInfo.cs`.
- **`/code-review max`** before opening the PR.

## Follow-ups (design, not yet scoped)

- **A jobs window for the user.** Everything above is reachable only through the
  tool service; the user sees a job in the status bar but has no way to see the
  list or stop one. A window listing the running jobs with a Cancel per job would
  use the same `GetRunningJobs`/`CancelJob` mechanism (the progress list plus the
  cancellation dictionary), and would be the natural home for the "generic cancel
  button in the status bar" CONSIDER note in `SkylineWindow.IProgressMonitor.IsCanceled`.
- **"Run in Background" on `LongWaitDlg`.** File > Export > Report puts up a
  LongWaitDlg the user has to sit through. For work that does not have to hold the
  document, a button that closes the dialog and turns the running work into a job -
  reporting to the SkylineWindow status bar, cancellable the same way - would let
  the user get on with something else. Needs a rule for WHICH operations may be
  backgrounded (anything that modifies the document on completion probably may
  not) and a way for the caller to say so.
