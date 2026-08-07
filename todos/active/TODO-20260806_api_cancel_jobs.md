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

## "Run in Background" (second commit)

The job mechanism moved out of `JsonToolServer` into `Util/RunningJobs.cs` so the
UI can use it too: `RunningJobs.Start(description)` hands out a `RunningJob` that
owns the job's `CancellationTokenSource` and, when disposed, reports the final
status that takes the job out of the progress list. `JsonToolServer.RunJob` is now
`using (var job = RunningJobs.Start(...))` around the work; `GetRunningJobs` /
`CancelJob` are thin adapters over `RunningJobs.Running` / `.Cancel`.
`JobProgressStatus` moved to `Util` with it - a job is no longer a tool-service
concept.

`LongWaitDlg` gained a **"Run in Background"** button, shown only when the caller
sets `BackgroundJobDescription`. Pressing it starts a job, registers the job's
token to trip the dialog's own `CancellationTokenSource` (so the work goes on
watching the one token it always had), reports the current message/percentage to
the job, and closes the dialog - which returns `PerformWork` to its caller with
the work still running. From there every `Message` / `ProgressValue` the work sets
is forwarded to the job, so the status bar and the job list follow it; `RunWork`'s
finally ends the job, reporting the exception it failed with (nothing else will -
the caller is gone).

Backgrounding is opt-in because most operations may not be: the work has to be
self-contained (everything that finishes it must happen inside the delegate),
must not apply a result to the document when it lands, and must not ask the user
anything through the broker's ShowDialog. All three are on
`BackgroundJobDescription`'s doc comment.

`ExportLiveReportDlg.ExportReport` is the first caller: the `FileSaver` and its
`Commit` moved inside the work delegate, and the export already reads a document
snapshot, so nothing it does depends on what the user does next.

New `LongWaitDlgBackgroundTest`: the button is absent without a description;
with one, pressing it closes the dialog, returns PerformWork, leaves the job
running with the message and percentage the work reported, and
`RunningJobs.Cancel` stops it.

**Not visually confirmed**: the button's placement (144,102, 115x23, bottom-right
anchored, 6px left of Cancel) is by the numbers - nobody has looked at the dialog
with it showing, and it only appears on an export slow enough to pass the 1500 ms
delay.

## Running Jobs dialog and StartJob (third commit)

`LongWaitDlg.StartJob(parent, delayMillis, jobDescription, performWork)` replaced
the `BackgroundJobDescription` property: backgroundable work now calls a DIFFERENT
method from everything else, which is what carries the contract. `PerformWork`
keeps `[InstantHandle]` (its delegate is finished with by the time it returns);
`StartJob` deliberately does not, because its delegate outlives the call. It
returns `JobOutcome` - `completed` / `canceled` / `backgrounded` - so a caller can
tell "the user cancelled" from "it is still running".

`RunningJobs` -> `BackgroundJobs`, `RunningJob` -> `BackgroundJob`. "Job" over
"Task" deliberately: `Task` is the most overloaded identifier in C#, and a
`BackgroundTasks.Start` returning a `RunningTask` would read as a
System.Threading.Tasks API in a codebase that bans async/await.

`RunningJobsDlg` (Controls) lists Job / Status / Progress on a 500 ms timer, rows
matched by job id and updated in place so the selection survives; "Cancel Job"
cancels the selected one, which then reads "Canceling" until the work stops.
Reached from **Tools > Running Jobs...** and by **double-clicking the status bar**
(wired on both `statusGeneral` and `statusProgress` - one visual area, and the
progress bar is the bigger target).

Two gates came with the menu item, both handled: `RunningJobsDlg` added to
`TestRunnerFormLookup.csv`, and `KeyboardShortcuts.html` re-recorded in
en/ja/zh-CHS (`IsRecordMode`, set back to false). Alt+T,R does not clash.

**Line-ending trap hit here**: `sed -i` under Git Bash rewrites a file with LF.
For .cs files `core.autocrlf` normalizes it away, but `Skyline.csproj` is stored
CRLF and the first commit of this work showed 15,136 changed lines in it. Fixed by
restoring the file from HEAD~1 and re-applying the edits with an editor that keeps
the file's endings. Use the Edit tool or a PowerShell rewrite, not `sed -i`.

## Follow-ups (design, not yet scoped)

- **The status-bar cancel button.** `SkylineWindow.IProgressMonitor.IsCanceled`
  still carries a CONSIDER note about a generic cancel button in the status bar.
  The Running Jobs dialog answers it for jobs; the note is about progress that is
  not a job (a results import), which is still only cancellable through whatever
  UI started it.
- **More backgroundable operations.** Report export is the only caller that sets
  `BackgroundJobDescription` so far. Candidates are the other operations that
  write a file and touch nothing else - chromatogram / spectral library exports,
  the various File > Export items - each needing the same check: self-contained
  work, no document change on completion, no mid-operation dialog.
