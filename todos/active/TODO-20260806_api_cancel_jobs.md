# TODO-20260806_api_cancel_jobs.md

## Branch Information
- **Branch**: `Skyline/work/20260806_api_cancel_jobs`
- **Base**: `master`
- **Created**: 2026-08-06
- **Status**: In review prep - description and screenshots done, awaiting CI and ready-for-review
- **GitHub Issue**: none
- **Module**: `skyline`
- **PR**: [#4546](https://github.com/ProteoWizard/pwiz/pull/4546) (draft)

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

- Wait for TeamCity on `2fadcfcbd7`, then mark #4546 ready for review.

## Review and PR prep (2026-11-02)

Three commits, pushed together as `d94485ac5b..2fadcfcbd7`:

1. **`5f942dc420`** - `RunInBackground` registered the job's cancellation and made
   its first progress report AFTER releasing `_lock`. Work finishing in that gap
   disposes the job (`ObjectDisposedException` reading the token), and a late
   non-final report re-adds a finished job to the status bar
   (`SkylineWindow.UpdateProgress` adds a non-final status it cannot find). Both
   moved inside the lock; `RunWork` sets `_finished` under the same lock before
   `FinishBackgroundJob`. Renamed `btnCancelJob`/`CancelSelectedJob` to
   `btnStopJob`/`StopSelectedJob` to match the button. Restored master's
   `TestFunctional.csproj`: a master merge had rewritten it LF->CRLF (162 lines of
   pure line-ending churn in the PR diff).
2. **`58718d0aab`** - `/code-review medium` over `origin/master...HEAD` (10 findings;
   6 fixed, 4 dropped):
   - Request threads came from `ActionUtil.RunAsync`, which makes FOREGROUND
     threads. An abandoned request whose verb never returns kept the process alive
     with no windows after exit (seen live: a Skyline whose start page was closed
     over the MCP stayed running and had to be killed). Now a `new Thread` with
     `IsBackground = true` running `CommonActionUtil.RunNow`.
   - Exit stopped the jobs before `CheckSaveDocument`, so Cancel at the save prompt
     left Skyline open with its exports already stopped. Split into
     `AskToStopBackgroundJobs` (before the save prompt) and `StopBackgroundJobs`
     (after it).
   - A failure between `RunInBackground` and `PerformWork`'s finally was both
     rethrown to the caller and reported by the job. `PerformWork` no longer
     rethrows once `_backgroundJob` is set.
   - `GetReportRows`/`GetReportFromDefinitionRows` now pass
     `RunJob(..., stopIfAbandoned: true)`: their token is linked with
     `RequestCancellation`, since nobody can receive the rows once the caller has
     gone.
   - The `GetRunningJobs` docs said "only jobs this service/connection started";
     since the registry moved to `BackgroundJobs` it also lists jobs the user
     backgrounded. Docs and the MCP tool description corrected (the tool now tells
     the model not to stop those unless asked); `SkylineAiConnector.zip` rebuilt
     with `dotnet build SkylineMcp.sln -c Release` (26.1.2.306,
     `EXPECTED_ZIP_VERSION` updated).
   - `ExportLiveReportDlg` creates the `FileSaver` after everything that can throw.
   - Dropped: exit prompt during an MCP read (something is running; abandoned
     reads now end), backgrounded error lacking the file name (IO errors carry the
     path), the abandoned-call error text (written to a closed pipe, never read),
     double progress report per tick (trivial cost).
3. **`2fadcfcbd7`** - The exit prompt read "The job 'Exporting report 'Transition
   Results'' is still running" (the description already quotes the report name).
   Now "{0} is still running."; both exit resources renamed after
   `AskToStopBackgroundJobs`.

Verified live over the Skyline MCP on this branch's Debug build:
`TTOF6600_64w.sky` (552,644 transitions x 6 replicates) and `CTOSymposium.sky`
(715,802) from `F:\skydata\pedro`. A backgrounded Transition Results export is
byte-identical to a foreground one; Stop Job, `skyline_cancel_job` and exit-OK
leave no partial file; exit-OK ends the process. A "Raw Chromatograms" report
(RawTimes/RawIntensities) runs far past the MCP's 30 s `CallTimeout`: the accept
on its Save dialog timed out, the next call reached Skyline with the export's
LongWaitDlg still up, Run in Background and `skyline_cancel_job` both worked
over the MCP. The button placement noted below as "not visually confirmed" is
now confirmed. Screenshots in `nickshulman/pr-assets` under
`pwiz/4546-background-jobs/`, embedded in the PR description.

**Connector gap found (not this branch's scope):** accepting a native Save
dialog through the MCP does not return until the work it starts finishes (up to
the 30 s timeout). Capturing the wait dialog of a shorter export needed an
out-of-band `BM_CLICK` posted to the dialog's Save button.

Tests: `TestJsonToolJobs`, `TestLongWaitDlgBackground` (3 loops),
`TestSkylineMcp`, `TestJsonToolServer`, `TestMcpConnectorDisconnect`,
`TestRunCommandMcpConnector`, `CodeInspection`.

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

## Exit guard, second pass (fifth commit)

Reworked so exiting actually gets you out. `CheckBackgroundJobs`:

1. Nothing running -> close.
2. Some jobs not yet asked to stop -> OK/Cancel prompt. One: "Background jobs must
   be stopped before exiting. The job '{0}' is still running. Do you want to stop
   it?" More: "... Do you want to stop the {0} jobs that are still running?" Cancel
   stays in Skyline; OK calls `CancelAll` and falls through to (3).
3. `WaitForBackgroundJobs` - a `LongWaitDlg` (500 ms delay, so jobs that stop at
   once show nothing) polling until `BackgroundJobs.Running` is empty. Giving up on
   that wait stays in Skyline, with the jobs still stopping. Finishing it closes.

Everything already asked to stop skips straight to (3) - there is nothing left to
ask. The View Jobs button is gone; Tools > Running Jobs and the status-bar
double-click are how you look.

Waiting on the UI thread here is safe because `LongWaitDlg` does not block it:
`ShowDialog` runs a modal message loop, so messages keep pumping for as long as
the dialog is up, and anything a job Invokes is serviced. The one stretch that
does not pump is `PerformWork`'s pre-dialog `completionEvent.WaitOne(delayMillis)`
- but it is bounded by that timeout, so the worst it can cost is a stall of
`delayMillis`, never a deadlock. (An earlier note here claimed a deadlock was
possible: wrong on both counts.)

**"Stop", not "terminate"**: settled after trying "terminate" (a dialog with both
"Cancel Jobs" and "Cancel" is ambiguous, which is what started this). "Stop Job"
in the Running Jobs dialog, "Stopping" in its progress column, "stop" in the exit
prompt. Code names below the UI stay Cancel* (`BackgroundJobs.Cancel`, `CancelAll`)
- cancellation is the mechanism, and "stop" reads as a promise the mechanism
cannot make. The dialog's own button and method are `btnStopJob`/`StopSelectedJob`
(renamed 2026-11-02 to match what the user clicks).

## Exit guard, first pass (fourth commit)

`SkylineWindow.OnClosing` now refuses to close while `BackgroundJobs.Running` is
non-empty, ahead of the save prompt (asking about saving and only then refusing to
close would be worse). A three-button `MultiButtonMsgDlg` says "Skyline cannot
exit while background jobs are still running." with:

- **View Jobs** (default) - opens the Running Jobs dialog
- **Terminate Jobs** - `BackgroundJobs.CancelAll()`
- **Cancel** - stays

It returns false in EVERY branch, including after terminating: terminating is a
request, and the jobs stop at their next cancellation check. Exiting again once
they have gone is what closes the window. The alternative - wait for them and
then continue closing - needs a pumped wait (a job reports progress by Invoking
the UI thread, so a plain blocking wait there would deadlock; `LongWaitDlg` pumps,
which is what makes it safe) and a timeout path. Not worth it for one extra click
in a rare situation, but that is the upgrade if the extra click annoys.

**"Terminate" over "Cancel"**: a dialog with both "Cancel Jobs" and "Cancel" is
ambiguous. The Running Jobs dialog's button changed to "Terminate Job" too, so one
word means stopping a job everywhere and "Cancel" always means cancelling the
dialog. The code names stay Cancel* - it IS cooperative cancellation, and
"Terminate" would over-promise if it named the mechanism.

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
