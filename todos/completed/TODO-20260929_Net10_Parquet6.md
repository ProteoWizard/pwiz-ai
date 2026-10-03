# TODO-20260929_Net10_Parquet6.md

## Branch Information
- **Branch**: `Skyline/work/20260929_Net10_Parquet6`
- **Base**: `Skyline/work/20260612_net8_port`
- **Created**: 2026-09-29
- **Status**: Completed
- **Completed**: 2026-10-02
- **GitHub Issue**: #4762 (fixed here; closed by hand since the PR targets the port branch)
- **Module**: `skyline`
- **PR**: [#4751](https://github.com/ProteoWizard/pwiz/pull/4751)

## Objective

Move every Parquet.Net consumer in pwiz from Parquet.Net 4.25.0 to the 6.1.0 fork built from
`developers/skylinedev/Parquet.Net6` (a sibling checkout of the `maccoss-developers` repo), and
change nothing else.

The same upgrade already works on `Skyline/work/20260923_ParquetPerfNet8` (commit `d16b59f16f`),
but that branch also holds the report export performance work from
[TODO-20260922_ExportReportPerf.md](TODO-20260922_ExportReportPerf.md). This branch carries only
the Parquet 6 upgrade, so it can be reviewed and merged by itself.

## Consumers

| Module | File | Change |
|---|---|---|
| skyline | `Model/Databinding/ParquetReportExporter.cs` | typed 6.x write API |
| skyline | `FileUI/PeptideSearch/DiannSearchDlg.cs` | reader row count; the reader is no longer disposable |
| osprey | `Osprey.IO/ParquetScoreCache.cs` | typed 6.x read and write API |
| pwiz | `pwiz-sharp/Tools/BiblioSpec/src/BiblioSpec/DiaNNSpecLibReader.cs` | typed 6.x read API |

Build plumbing: `pwiz_tools/Shared/Lib/Parquet/ParquetNet.targets` (new), imported by
`pwiz_tools/Directory.Build.targets` and `pwiz-sharp/Directory.Build.targets`. A project that sets
`ReferenceParquetNet=true` gets the `Parquet.Net` 6.1.0 package for its dependency graph (with
`ExcludeAssets="compile"`), compiles against `ParquetNet.dll`, and has the fork copied over
`Parquet.dll` in its output after Build. The unreferenced net472 companion DLLs in
`Shared/Lib/Parquet` were deleted.

Module is `skyline` because the report exporter is the main consumer, but the change also touches
osprey and pwiz (BiblioSpec) code.

## Decisions

- **DLL**: `ParquetNet.dll` and `ParquetNet.xml` come from `Parquet.Net6/BinariesForProteoWizard`
  at 6.1.0-osprey3 (maccoss-developers commit `76f5f6b`, branch `20260923ParquetNet6`). osprey2
  (`5fff229`) added `PrepareColumnAsync`/`WritePreparedColumnAsync`, which Osprey now uses. osprey3
  fixed the `byte`/`sbyte`/`short`/`ushort` plain encoders, which returned their pooled `int[]`
  before encoding from it. That is the same bug the 4.25.0 fork fixed, and it only matters when
  columns are prepared concurrently.
- **Report exporter**: master's exporter was ported directly rather than taking the perf branch's
  version, which depends on its ColumnBuffer and threading rewrite. The changes:
  - `ParquetOptions` with Zstd and `CompressionLevel.Optimal`. The 6.x default, SmallestSize, is
    Zstd level 19 and much slower.
  - Columns keep master's `new DataField(Name, StorageType)`. Parquet.Net 6 already treats a string
    field as nullable, because its `IsNullable` is true for any class.
  - Non-list string columns get `EncodingHint.Dictionary`, with `DictionaryEncodingSampleSize`
    10,000. Parquet.Net 4 dictionary-encoded them by default; 6 only does it when asked.
  - The chunk's typed arrays are written with `WriteAsync<T>` (the string overload for strings),
    in place of `DataColumn`.
  - List columns go through `WriteAllPartsAsync<T>` with explicit definition levels, so a null
    list, an empty list and a null element each get their own level (0, 1 and 2, where 3 means a
    value is present). Master wrote a null list and an empty list the same way.
    `ParquetReportExporterTest` checks this.
  - `ParquetWriter` is only `IAsyncDisposable` in 6.x. It is disposed with `DisposeAsync` on
    success and on cancel, and not disposed after a failure, because writing the footer would
    throw again and hide the original exception.
  - `CreateAsync` and `DisposeAsync` run under `ActionUtil.CallWithoutSynchronizationContext`
    (which gained an `Action` overload). 6.x awaits the footer write and flush without
    `ConfigureAwait(false)`, so blocking on them from a WinForms thread, such as the Immediate
    Window, can deadlock.
  - The column-write dispatch passes `BindingFlags.DoNotWrapExceptions`, so a failure is reported
    as itself rather than as `TargetInvocationException`.
  - The exporter skips `DoneAdding(wait: true)` once the writer thread has failed. In
    `ProducerConsumerWorker` the failing consumer has already filled the one-slot queue with its
    stop null, so another `Add` would block forever. This is a master bug, made easier to hit
    because more work now runs on the writer thread.
- **ParquetNet.targets**: the `Reference` uses the DLL's full path. With the simple name
  `Parquet` plus a HintPath, ResolveAssemblyReference found `Parquet.dll` among Skyline's Content
  items first, and Release Skyline compiled against
  `pwiz-sharp/Tools/BiblioSpec/src/BlibBuild/bin/Release/net10.0/Parquet.dll`.
- **Osprey writes**: a row group's columns are prepared concurrently with `PrepareColumnAsync` on
  `ParallelEx` threads and appended in schema order, as master did with the 4.x fork's
  `WriteColumnsAsync`. `OSPREY_PARQUET_WRITE_THREADS` sets the thread count and defaults to the
  core count. String and blob columns are packed with their own definition levels. String columns
  are dictionary-encoded.
- **Osprey merge**: master had moved the score cache's error text into RESX (#4721), so the
  merged code keeps that resource string and gets the type name from `cwtField.ClrType`.

## Progress

- [x] Cherry-picked `d16b59f16f` and resolved the conflicts in `ParquetScoreCache.cs` and
  `ParquetReportExporter.cs`
- [x] Copied the current fork DLL and XML into `Shared/Lib/Parquet` and updated the
  `ParquetNet.targets` comment to describe what the fork adds
- [x] Skyline Debug build succeeds
- [x] Skyline tests pass: TestConvertToStorageType, TestParquetArrays, TestParquetReportInvariant,
  TestTextReportInvariant, TestExportHugeParquetReport
- [x] Osprey tests pass: all 615
- [x] BiblioSpec DIA-NN tests pass: all 8, including Diann2_Parquet
- [x] Committed and pushed `ff622113da`
- [x] `/code-review max`: 15 findings. Fixed the WinForms deadlock, the missing dictionary
  encoding, the hang after a writer-thread failure, the Content-item reference, the wrapped
  exceptions, the wrong nullability comment, and Osprey's lost concurrent writes. Left out of
  this PR: how the fork DLL is delivered (see Notes), Osprey's double copy of blob columns on
  read, DIA-NN's boxed reads, a float16 sibling parquet aborting BlibBuild, and test gaps.
- [x] Rebuilt the fork as 6.1.0-osprey3 and copied it in
- [x] Skyline Parquet tests, all 615 Osprey tests, and the 8 BiblioSpec DIA-NN tests pass on
  osprey3
- [x] `TestParquetRoundTripScalarStress` passes 5,000 iterations
- [x] Release Skyline builds, and its reference cache resolves `Parquet` to `ParquetNet.dll`
- [x] Committed and pushed `5ba451a946`; opened [#4751](https://github.com/ProteoWizard/pwiz/pull/4751)
  against `Skyline/work/20260612_net8_port`
- [x] Ported `54af0de323` (Skyline/work/20260930_parquet_timestamps) to 6.x: DateTime report columns
  use TIMESTAMP(MILLIS). Millis because 6.x converts a local DateTime to UTC for Micros and Nanos,
  which would shift a wall-clock time. TestParquetTimestamps passes.
- [x] Copilot: the exporter's pre-check before `DoneAdding` still raced the consumer's failure.
  Fixed in `ProducerConsumerWorker`: a consumer failure clears the queue and calls `CompleteAdding`,
  and `Add`/`DoneAdding`/`Take` return instead of blocking on a completed queue. Reverted the
  exporter pre-check.
- [x] Skyline deploys BlibBuild, BlibFilter, msconvert and bullseye-sharp through
  `_DeployBundledToolOutputs`, which asks each `DeployOutput="true"` reference for `GetTargetPath`.
  A VS build of Skyline.sln gives these out-of-solution references Platform=AnyCPU and
  Build-Skyline.ps1 gives them x64, so no fixed path is right for both. Debug and Release bins
  match the x64 build outputs byte for byte.
- [x] Applied the `_DeploySkylineCmd` hunks of `15dc5be3b7` (not its server GC hunk), which made
  TestCmdLineAssociateProteins pass. It was the only Test.dll failure (420 of 421 passed).
- [x] Committed and pushed `9abe7ccc3e`; replied to and resolved the Copilot thread
- [x] #4762 (Matt): `dotnet publish` of Osprey shipped the stock NuGet `Parquet.dll`, because the
  after-Build copy only patched `$(OutDir)` and publish copies package assets from the NuGet cache.
  `ParquetNet.targets` now removes the package's `Parquet.dll` from `RuntimeCopyLocalItems` (after
  `ResolvePackageAssets`, unconditionally, so transitive consumers like Osprey.exe are covered) and
  the patched `Reference` is `Private=true`; the after-Build copy is gone. `ExcludeAssets="runtime"`
  was tried first and dropped every Parquet.Net dependency (CommunityToolkit.HighPerformance,
  Snappier, ZstdSharp, ...), failing 28 Osprey tests, because NuGet applies it to dependencies too.
  A README publish now ships the patched dll and all five dependencies.
- [x] Skyline `Program.Main` shows a message after the 32-bit check when the loaded `Parquet.dll`
  lacks the fork's `ParquetRowGroupWriter.PrepareColumnAsync` (`WriteColumnsAsync` was the 4.x
  fork's method and exists in neither 6.1 build). It warns and keeps starting, since Skyline only
  calls `WriteColumnAsync`, which the stock dll has. Committed `a31a3f35e8`.
- [x] Merged the port branch twice: the CRLF restore (`3f9a7ab674`) conflicted on four csproj only
  on line endings; kept our content in CRLF, staged with `hash-object --no-filters` because
  `core.autocrlf=true` re-normalized a plain `git add` to LF

## Notes

- The Osprey test run printed an unhandled `NullReferenceException` from
  `OspreyDiagnostics.cs:107` after every test had passed. It comes from master (#4694), not this
  branch: the `ProcessExit` handler reads the static `s_sink`, which a later `Initialize` can set
  back to null.
- `TestParquetRoundTripScalarStress` did not catch the unfixed encoders either: osprey2 also passed
  5,000 iterations with concurrent prepare on. So the osprey3 fix rests on reading the code, not on
  a reproduction. .NET 10's shared `ArrayPool` usually hands a returned array back to the thread
  that returned it, which keeps the race rare.
- ExportHugeParquetReportTest's 50,000-row `prism.parquet` is 22,363 bytes with the dictionary
  hint. Protein, Peptide, Fragment_Ion, Replicate_Name and File_Name are dictionary-encoded. The
  review reported 18,388 bytes for 4.x and 33,634 without the hint; those numbers were not
  re-measured.
- Fork DLL delivery was a copy after Build, which `dotnet publish` bypassed; fixed for #4762 by
  removing the package's dll from the copy-local items (see Progress). A repo-local package feed
  remains the cleaner long-term answer.
- Files written by the fork record `created_by` as `Parquet.Net version ${VERSION} (build
  ${GITHUB_SHA})`, because the fork build does not substitute `Globals.cs`.

### 2026-10-02 - Merged

PR #4751 squash-merged into `Skyline/work/20260612_net8_port` as `e60a58be42`, titled
"skyline: Upgraded to Parquet.Net version 6", with all ten TeamCity checks green (Skyline Windows
1,806 tests, Core Windows 650, Core Linux 421, Osprey Windows and Linux 642 each, code inspection
clean). #4762 closed by hand with a comment crediting Matt, since `Fixes` only auto-closes on
master. No human approval was recorded.

## Resolution

**Status**: Completed (merged into the .NET 10 port branch, not master).

Skyline's report exporter, the DIA-NN search dialog, the Osprey score cache and pwiz-sharp's
BiblioSpec DIA-NN reader moved from Parquet.Net 4.25.0 to the patched 6.1.0-osprey3 fork.
`Shared/Lib/Parquet/ParquetNet.targets` makes every opted-in project compile against and deploy the
patched `Parquet.dll`, and drops the package's own dll from build, publish and deps.json (#4762).
Along the way: WinForms-safe writer creation and disposal, dictionary encoding of report strings,
TIMESTAMP(MILLIS) DateTimes, a `ProducerConsumerWorker` that cannot deadlock a producer after a
consumer fails, tool deploys from the folder each tool was built into, and a Skyline startup
message when the loaded Parquet.dll is not the patched build.

Not done: the Osprey README still documents `net8.0` publish commands (Nick: not needed); master
keeps the 4.25.0 setup with the publish bug (Nick: Osprey on master does not matter); the
`Dispose` path of `ProducerConsumerWorker` can still block with two or more consumers on a bounded
queue smaller than the consumer count (pre-existing, no such caller).
