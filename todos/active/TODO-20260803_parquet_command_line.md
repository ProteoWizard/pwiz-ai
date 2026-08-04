# TODO-20260803_parquet_command_line.md

## Branch Information
- **Branch**: `Skyline/work/20260803_parquet_command_line`
- **Base**: `master`
- **Created**: 2026-08-03
- **Status**: In Progress
- **Module**: `skyline`

## Motivation

Exporting a report to .parquet worked in the UI but failed from the command
line. `SkylineCmd.exe.config` was maintained by hand, had not been touched since
2017 (#992), and was missing the `<codeBase>` hint that maps the `Parquet`
assembly to `ParquetNet.dll`, plus the version redirects its dependencies need.

There was also no `parquet` option for `--report-format`, which offered only
`csv` and `tsv`.

## What Was Done

* `--report-format` is now a `ReportFormat { csv, tsv, parquet }` enum in
  `ReportExporters.cs`, with `ReportExporters.ForFormat()`.
  `CommandArgs.ReportColumnSeparator` became `CommandArgs.ReportFormat`.
* `SkylineCmd.exe.config` is deleted from the tree. `Skyline.csproj` includes the
  config MSBuild generates for Skyline as a Content item linked to that name, so
  the two cannot drift. It has to be included from `obj` rather than `bin`: the
  content copy runs before `_CopyAppConfigFile`, and including from `bin` fails a
  cold build with MSB3113 while succeeding on every incremental one. A linked
  Content item is also what puts the file in the ClickOnce manifest, which is
  built from project items - generating it into the output folder was not enough,
  and would have shipped a config-less SkylineCmd.exe to the usual install.
  `SkylineCmdConfigTest` verifies the copy, and that `TestData.dll.config` and
  `TestFunctional.dll.config` cover every version mismatch too, since a Test
  Explorer run uses those rather than `TestRunner.exe.config`.
* `app.config` lost 11 bindingRedirects and the `<system.data>` block. Verified
  by stripping them and rebuilding: `AutoGenerateBindingRedirects` regenerates
  exactly the load-bearing set, and never regenerated the four that a reference
  scan had independently called dead. Only the Parquet `codeBase` remains.
* `SkylineCmd/Program.cs` uses `Assembly.Load` instead of `Assembly.LoadFrom`,
  which also removed the need for `<loadFromRemoteSources>`.

## Findings Worth Keeping

**Why only parquet broke.** The `Parquet` entry is a `codeBase`, not a
redirect: the assembly's simple name is `Parquet` but its file is
`ParquetNet.dll`, because a native `parquet.dll` already owns that name in the
output folder. Probing finds the native DLL and fails with "expected to contain
an assembly manifest" - 100% of the time, unlike the version redirects, which
only bite on a mismatch and are resolved lazily per code path.

**Mark of the web.** Extracting a downloaded .zip with Windows Explorer marks
every file `ZoneId=3`. Verified against the real installer zip (302 of 302
binaries marked): ordinary probing and `codeBase` resolution are unaffected,
child processes (BlibBuild, method builders) are unaffected because Skyline
starts them with `UseShellExecute=false`, and only `Assembly.LoadFrom` is
refused. The remaining `LoadFrom` in shipping code is
`ToolsUI/ToolDescriptionRunUI.cs:338` for tool argument collectors, which has
never had `loadFromRemoteSources` - not a regression, but `UnsafeLoadFrom` is
the one-word fix if it ever surfaces.

## The Parquet Export Hang

Exporting to parquet hung on roughly one run in eight in Debug and one in three
in Release, pegging every core and growing to 400-600 MB, while csv never hung
in 20 runs.

Root cause: `CalibrationCurveFitter.GetTransitionQuantities` read and then added
to the plain `Dictionary` field `_replicateQuantities` with no synchronization.
`ParquetReportExporter.PopulateChunk` is the only report path that evaluates row
values on more than one thread (`ParallelEx.For`; csv and tsv are serial), so it
was the only one that could corrupt the dictionary and spin forever in
`Dictionary.FindEntry`. Fixed by locking, which also covers the `_identityPaths`
IndexedList that the same method mutates.

How it was found, in case a similar hang turns up:

* Stacks came from ClrMD (the same API `TestUtil/HangDetection.cs` uses) against
  the hung process. Identical stacks five seconds apart with cores busy means a
  spin, not a deadlock. ClrMD cannot walk past `RuntimeMethodInfo.Invoke`, so
  the spinning frame itself was invisible.
* What localized it was varying the report: Peptide RT Results, Transition
  Results and Peptide Quantification were 0 hangs in 25 runs each, and only
  Peptide Ratio Results reproduced. That pointed at the quantification path,
  which matched `Dictionary+Entry<IdentityPath, PeptideQuantifier+Quantity>[]`
  in the heap dump.

Rates measured with the lock reverted, 40 CLI exports each: Debug 5 hangs,
Release 14. Release is the more likely to hang, not the less. Verified after the
fix: 40 Release and 60 Debug exports of the ratio report with `PopulateChunk`
still parallel, 0 hangs.

`ConsoleParquetReportExportTest` exports once, in process. If the regression
returns the test hangs rather than fails, which is deliberate - the threads are
stuck inside the corrupted Dictionary lookup and never reach a cancellation
check, so nothing can stop them, and a hang in the runner is easier to debug
than a killed child process. One export caught it 5 times in 40 in Debug, so a
passing run is weak evidence that the bug is absent.

`CalibrationCurveFitter._transitionsToQuantifyOn` is still lazily initialized
without a lock. It looks benign - the set is built in a local and published by a
single reference assignment, so a racing caller sees null or a complete set, and
only duplicates work.

## Deferred

**user.config location.** SkylineCmd uses a different `user.config` than
Skyline.exe, so the CLI cannot see custom reports made in the UI. `Upgrade()`
crosses version boundaries but not the `_Url_<hash>` boundary, which is why
this machine has 218 separate settings folders. `ExecuteAssembly` in a second
AppDomain was measured and does not fix it - it corrects company, app name and
version, but the Url-evidence hash still differs because the CLR normalizes a
secondary domain's codebase differently (`file:///I:\...\X.exe` vs
`file:///I:/.../X.EXE`). Options are a fixed per-user path, or next to
Skyline.exe alongside the Tools folder, seeded from the exe folder for the
read-only administrator install. Deferred: the .NET 8 port will likely break
settings migration anyway, so the design should be settled there.

**Always UTF-8.** `--culture` is an `InternalUse` test argument; it and the
UTF-8 forcing arrived together in #544 to fix ja/zh-CHS nightly failures. The
gating is caution about mutating the console code page, not a decision that
normal runs should not be UTF-8. `EncodingManager` already restores it, so
making it unconditional is small.
