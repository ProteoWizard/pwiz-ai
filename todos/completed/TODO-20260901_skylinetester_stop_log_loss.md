# TODO-20260901_skylinetester_stop_log_loss.md

## Branch Information
- **Branch**: `Skyline/work/20260901_skylinetester_stop_log_loss` (UIbug)
- **Module**: `skyline` - SkylineTester UI and its log handling
- **Base**: `master` @ `99609d5bc0`
- **Created**: 2026-09-01
- **Status**: Completed
- **PR**: [#4630](https://github.com/ProteoWizard/pwiz/pull/4630) (merged 2026-09-01)

## Problem

A nine-hour leak-testing run's log was destroyed by a second click on the Stop button.

The run was stopped from the Quality tab. Over RDP it was not obvious the first click
had registered, so Stop was clicked again. The second click started a new run, and
starting a run deletes the log before a single test executes. Nine hours of output,
gone with no copy anywhere on disk.

This is not a near miss that needed bad luck. Every ingredient is ordinary: an
uncertain click over a slow remote session, a button whose meaning changes underneath
it, and a delete with no backup.

### 1. Starting a run deletes the previous log (product)

`CommandShell.LogFile` is a property whose *setter* deletes the file
(`CommandShell.cs:555-574` on master):

```csharp
set {
    _logFile = value;
    if (File.Exists(_logFile)) {
        try { File.Delete(_logFile); }
        catch (Exception) { }   // silent
    }
```

`TabQuality.Run()` assigns it on every run (`TabQuality.cs:96`), as does
`TabBase.RunCommands()` (`TabBase.cs:91`). So the log is destroyed at run start,
before any test output exists to replace it. `DefaultLogFile` is a single fixed path
(`RootDir\SkylineTester.log`, `SkylineTesterWindow.cs:196`) - there is no roll, no
backup, and the swallowed exception means a failed delete would be invisible too.

A destructive side effect inside a property assignment is the deeper hazard here: no
caller reads as though it deletes a file.

### 2. The Run/Stop button silently means Run again while a stop is in flight (UI)

`RunOrStopByUser()` (`Main.cs:39-56`) picks its branch from:

```csharp
if (_runningTab != null && (_runningTab.IsRunning() || _runningTab.IsWaiting()))
```

`Stop()` is asynchronous - it calls `_runningTab.Cancel()` and returns. `_runningTab`
is not cleared until `Done()` (`Main.cs:238`). Between the click and that callback,
the same button takes the *else* branch and starts a run. The button still reads
"Stop" for part of that window.

Nothing about the second click looks like "start a nine-hour run"; it looks like
"make sure it stopped".

### Why the Output tab is safe

`tabOutput` has its own dedicated `buttonStop` (`SkylineTesterWindow.Designer.cs:2746`)
that is permanently labelled Stop and is disabled in `Done()` (`Main.cs:245`). It is
never a Run toggle. The Quality, Nightly, Tests, Tutorials and Forms tabs share
`_runButtons`, whose `Text` flips between "&Run" and "&Stop" - one control, two
meanings, selected by state that lags the click.

Stopping from the Output tab has been the safe habit. The Quality and Nightly tabs are
the tempting ones precisely because they show the graph worth watching.

## Fix

### 1. Make the stop window unclickable

Turn the toggle's ambiguous window into a state a person cannot click through:

* On a successful `StopByUser()`: set every `_runButtons` entry to "Stopping..." and
  `Enabled = false`.
* In `Done()`, when the stop was user-initiated: set "Stopped", leave disabled, and
  start a one-shot 1 s timer that restores "&Run" and `Enabled = true`.
* Normal completion (not a user stop) keeps today's behaviour - straight back to
  "&Run" with no "Stopped" beat. A `_stoppingByUser` flag distinguishes them.
* `Done()` also drives the restart-after-failure path (`if (_restart) Run();`). That
  is programmatic and must not be gated by the disabled button.

This is the actual fix. It removes the race rather than hoping nobody clicks into it.

### 2. Roll the log, keeping exactly one previous

Instead of deleting, rename. On starting a run whose target is `DefaultLogFile`:

* If `SkylineTester.log` exists and is non-empty, rename it to
  `SkylineTester-YYYYMMDD-HHMMSS.log` (matching the convention already used by hand in
  `D:\test\nightly-logs`).
* Delete any older `SkylineTester-*.log` first, so at most one previous log is kept.

One level of undo is all this needs - it is what would have saved the nine-hour run -
and a fixed limit of two files means the accumulation that has never happened in ten
years of SkylineTester still cannot start. No preference, no checkbox to forget.

**Only for `DefaultLogFile`.** Nightly runs pass their own path
(`TabBase.cs:91`, `MainWindow.NightlyLogFile`) and are already timestamped and pruned
to 90 runs by `Summary.GetLogFile()` / `MAX_STORED_SUMMARIES` (`Summary.cs:110-118`,
`247-255`). Rolling those would fight an existing, working scheme.

Replace the delete-in-setter with an explicit call (`StartNewLog()` or similar) that
rolls and then opens, so no future caller can destroy a log by assigning a property,
and a failure stops being silent.

### 3. .gitignore

`.gitignore:443` is the exact name `SkylineTester.log`, so a timestamped log would
show up as untracked. Widen to `SkylineTester*.log`. Verify it does not disturb
`SkylineTester test list.txt` (line 442, different extension).

## Verification

* Start a Quality run, let it produce output, click Stop twice quickly: the second
  click must do nothing, and the log must survive.
* Confirm the button sequence reads Stop -> Stopping... -> Stopped -> Run, disabled
  throughout the middle two.
* Start a second run: the previous log becomes `SkylineTester-<stamp>.log`; start a
  third: still exactly one timestamped file, now from the second run.
* Nightly run: per-run logs still land via `Summary.GetLogFile()` and are not rolled or
  deleted by the new path; the Runs combo still resolves them.
* `git status` clean after a rolled run.
* Normal (non-stopped) run completion still returns the button to "&Run" with no
  "Stopped" pause.

## Notes

* Reported by Brendan, from losing a nine-hour leak-test log on 2026-09-01.
* Recovery was attempted and failed: no copy in `D:\test\nightly-logs` (rolled by hand
  only through 2026-08-29), nothing in `SkylineTester Results`, and the two
  `TestRunner.log` files on disk were from a different run and the accidental restart.
  Shadow copies and restore points both needed elevation and are unlikely on a dev box.
* The habit that has been compensating for this - asking a Claude Code session to copy
  the log to `D:\test\nightly-logs` before stopping - should not be necessary.

## Progress Log

### 2026-09-01 - Merged

PR #4630 merged as commit `893544fb6b`. All three planned parts shipped, and the
investigation found two more destructive paths than the one the plan named:
`TabBase.StartLog` truncated the log with `File.WriteAllText(..., "")` right after being
handed it, and `TabQuality.Run` deleted it outright. Removing the `File.Delete` from the
`LogFile` setter alone would not have fixed anything.

Verified interactively by Brendan on the net10 build in `pwiz-work1`: Stop now changes to
"Stopping..." and disables immediately, repeated clicking is harmless, the log rolls
exactly once, and both it and the test list are back in `pwiz_tools/Skyline` rather than
the SkylineTester project folder.

Scope added during review, beyond the original plan:

* `RootDir` now prefers a directory named exactly `Skyline`, falling back to the first
  `Skyline*` only when there is none above. The `StartsWith` was deliberate - the
  standalone SkylineTester zip is rooted on a SkylineTester directory - but in an
  SDK-style build the exe sits under `Skyline\SkylineTester\bin`, so the walk stopped a
  level early. This is why the log and test list had moved on the net10 branch.
* Opening the window no longer deletes the log, so reopening SkylineTester to go read the
  last run's log no longer throws it away.
* The roll takes `LogLock`, which every other access to that file already holds, so a
  memory-graph refresh landing mid-roll cannot fail the `Move` with a sharing violation.
* `StopByUser` returns early when the run finished while the nightly confirmation was up,
  which would otherwise leave the buttons disabled with no run left to restore them.

Two review rounds found real defects in the fix itself, both fixed before merge: the
`FileInfo.Length` check sat outside the `try`, and pruning the older rolled log ran
*before* the `Move`, so a failed roll discarded it for nothing.

The `.gitignore` change deliberately kept the anchored `/pwiz_tools/Skyline/` paths and
added only `/pwiz_tools/Skyline/SkylineTester-*.log`. Widening the pattern would have
masked the `RootDir` regression rather than fixing it.

Deferred: `TabNightly.cs:297` still hard-deletes `SkylineTester.log` when a nightly
starts. Consistency value only, on the unattended nightly path, so it did not meet the
bar for landing here. Not filed as an issue.

Merged with `--admin`: the gate was genuinely green (20/20, including
`Skyline master and PRs`), but master had picked up an unrelated revert commit after the
run started, and this repository requires branches to be up to date. No TeamCity
configuration covers SkylineTester behavior, so the coverage that matters here is
Brendan's manual testing above plus the Release compile.
