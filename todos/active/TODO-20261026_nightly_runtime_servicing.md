# SkylineNightly dies silently when Microsoft Update services the .NET runtime mid-run

## Branch Information
- **Branch**: `Skyline/work/20261026_nightly_runtime_servicing`
- **Base**: `master`
- **Created**: 2026-10-26
- **Status**: In Progress
- **GitHub Issue**: [#4919](https://github.com/ProteoWizard/pwiz/issues/4919)
- **Module**: `skyline`
- **PR**: (pending)

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

- [ ] Publish SkylineNightly self-contained (`SkylineTester.csproj` `_StageDistroZipPrereqs`, `SelfContained=true`)
- [ ] At startup, detect an interrupted previous run (latest log lacks `Done.`) and record a cause from the event log (1074, WindowsUpdateClient 19/20, MsiInstaller 11707/1033, 6008/Kernel-Power 41, .NET Runtime 1026 / Application Error 1000)
- [ ] If feasible, post the interrupted log so skyline.ms shows a short run with a reason
- [ ] `AppDomain.UnhandledException` handler: full exception to the nightly log, note missing runtime directory
- [ ] Log `SystemEvents.SessionEnding`
- [ ] Optional: `LogFileMonitor` watches TestRunner's shared-framework folder and logs its disappearance

## Regression Test

- **Test name**: (pending)
- **Test project**: (pending - SkylineNightly has no test project; event-log classification logic should be factored for unit testing)
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

## Progress Log

### 2026-10-26 - Session Start

Root cause established from the dump with dotnet-dump (see issue). Starting implementation.
