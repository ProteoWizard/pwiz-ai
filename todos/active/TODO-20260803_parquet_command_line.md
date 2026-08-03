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
* `SkylineCmd.exe.config` is deleted from the tree. The `CopyConfigToSkylineCmd`
  target in `Skyline.csproj` copies the config MSBuild generates for Skyline, so
  the two cannot drift. `SkylineCmdConfigTest` verifies the copy and that the
  policy covers every version mismatch in the build output.
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

## Remaining Work

**Parquet export hangs about 1 run in 5.** Measured back to back on the same
document: parquet 4 hangs in 20 runs, csv 0 in 20. Hung runs peg every core and
grow to 460-620 MB; completed runs take 1.3-1.6s. Pre-existing in
`ParquetReportExporter.Export`, the only place using `QueueWorker` with
`maxQueueSize: 1` alongside `ParallelEx.For`, but the new
`--report-format=parquet` makes it easy to reach. Should be fixed before the
option ships.

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
