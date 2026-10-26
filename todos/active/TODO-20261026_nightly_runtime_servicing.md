# SkylineNightly dies silently when Microsoft Update services the .NET runtime mid-run

## Branch Information
- **Branch**: `Skyline/work/20261026_nightly_runtime_servicing`
- **Base**: `master`
- **Created**: 2026-10-26
- **Status**: In Progress
- **GitHub Issue**: [#4919](https://github.com/ProteoWizard/pwiz/issues/4919)
- **Module**: `skyline`
- **PR**: [#4920](https://github.com/ProteoWizard/pwiz/pull/4920)

## Objective

SkylineNightly on BSPRATT-UW2 died overnight 10/25-26 with an unhandled
`FileNotFoundException` (`System.Diagnostics.TraceSource`) on the finalizer thread while
JIT-compiling a ClrMD finalizer. Microsoft Update had serviced the .NET 10 runtime
(10.0.13 -> 10.0.14) under the ~24 h framework-dependent process. Nothing recorded what
happened, so it read as a random crash and cost a day of analysis. Losing a run to
Windows Update is acceptable; failing to name the cause is not.

Dump: `ai/.tmp/20261026-SkylineNightly.dmp`; dotnet-dump output in
`ai/.tmp/sessions/20261026-dump/`.

## Tasks

- [x] Publish SkylineNightly self-contained (per-item `SelfContained` metadata; shim stays framework-dependent)
- [x] At startup, detect an interrupted previous run (latest `SkylineNightly-*.log` lacks `Done.`) and diagnose from System/Application events (1074, 6008, Kernel-Power 41, WindowsUpdateClient 19, .NET Runtime 1026, Application Error 1000); logged to both logs and sent as a TestResults alert
- [x] ~~Post the interrupted log to skyline.ms~~ - dropped: partial runs would pollute the statistics being retrained, and a truncated log reads as a hang. The existing TestResults alert email carries the cause instead
- [x] `AppDomain.UnhandledException` handler logs the exception and the installed runtimes
- [x] ~~Log `SystemEvents.SessionEnding`~~ - dropped: no message loop in `run` mode, so delivery is unreliable; event 1074 gives the restart time after the fact
- [x] In-run `MachineStateMonitor`: logs .NET runtime changes and a pending restart (replaces the TestRunner-folder idea; covers every shared-framework process)
- [x] `/code-review medium` - 10 findings; 9 fixed in `a4ed0c124f` (UTC times, update cutoff at run end, command logs excluded, FileShare.ReadWrite read, log lock, background alert, guarded diagnostics, RID restore before self-contained publish, non-vacuous runtimes assert); 1 dropped (open settings window counts as "still running": rare, and the window was already killed)
- [x] Pushed and opened PR #4920
- [ ] TeamCity green, human review, merge

## Regression Test

- **Test name**: TestRunInterruption (`Test/RunInterruptionTest.cs`)
- **Test project**: Test - `RunInterruption.cs` and `MachineState.cs` linked in (SkylineNightly is a WinExe with no test project)
- **Fails on master**: n/a - new code. Teeth verified by mutation instead: removing the computer-name strip from the 1074 process path failed the test (`Expected:<windows_update_restart>. Actual:<restart>`)
- **Passes on fix**: yes, `ee86d100f6`
- **Not covered**: the Nightly.cs wiring (startup check, alert send) - exercised only by a real nightly run

## Progress Log

### 2026-10-26 - Session Start

Root cause established from the dump with dotnet-dump (see issue). Starting implementation.

Implemented and committed `ee86d100f6` (local). Verified:
- TestRunInterruption passes; mutation check fails it as expected
- The XPath event query returns real WindowsUpdateClient records on BRENDANX (`ai/.tmp/sessions/20261026-dump/xpath-check.ps1`)
- `-DistroZips SkylineNightly.zip` builds: SkylineNightly.exe 124 MB self-contained, zip 49 MB (download cost per nightly run)
- CodeInspection passes

Environment fix: `pwiz_tools/Skyline/SkylineTester/Properties/AssemblyInfo.cs` was a gitignored
.NET Framework leftover (9/24) that broke the SDK build with duplicate attributes; moved to
`ai/.tmp/sessions/20261026-dump/SkylineTester-AssemblyInfo.cs.stale`. Other pre-port checkouts likely have it too.

Unverified: 1074 insertion-string layout (no restart in this machine's 3-day System log); parser accepts the path with or without a trailing "(MACHINE)".
