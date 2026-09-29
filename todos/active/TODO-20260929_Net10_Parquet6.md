# TODO-20260929_Net10_Parquet6.md

## Branch Information
- **Branch**: `Skyline/work/20260929_Net10_Parquet6`
- **Base**: `master`
- **Created**: 2026-09-29
- **Status**: In Progress
- **GitHub Issue**: (none)
- **Module**: `skyline`
- **PR**: (pending)

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

- **DLL**: `ParquetNet.dll` and `ParquetNet.xml` are copied from
  `Parquet.Net6/BinariesForProteoWizard` as they are now (fork commit `5fff229`). That is newer than
  the DLL in `d16b59f16f`. It is the same build `801d4a59bd` on the perf branch switched to, and it
  adds an API that splits writing a column into preparing it and appending it. Nothing on this
  branch calls that API.
- **Report exporter**: master's exporter was ported directly rather than taking the perf branch's
  version, which depends on its ColumnBuffer and threading rewrite. The changes:
  - `ParquetOptions` with Zstd and `CompressionLevel.Optimal`. The 6.x default, SmallestSize, is
    Zstd level 19 and much slower.
  - Every non-list column is created with `isNullable: true`. Parquet.Net 6 makes only a
    `Nullable<T>` column nullable by itself, not a string column.
  - The chunk's typed arrays are written with `WriteAsync<T>` (the string overload for strings),
    in place of `DataColumn`.
  - List columns go through `WriteAllPartsAsync<T>` with explicit definition levels, so a null
    list, an empty list and a null element each get their own level (0, 1 and 2, where 3 means a
    value is present). Master wrote a null list and an empty list the same way.
    `ParquetReportExporterTest` checks this.
  - `ParquetWriter` is only `IAsyncDisposable` in 6.x. It is disposed with `DisposeAsync` on
    success and on cancel, and not disposed after a failure, because writing the footer would
    throw again and hide the original exception.
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
- [x] Committed locally (not pushed)
- [ ] Release build of Skyline
- [ ] `/code-review max`
- [ ] Push and open the PR

## Notes

- The Osprey test run printed an unhandled `NullReferenceException` from
  `OspreyDiagnostics.cs:107` after every test had passed. It comes from master (#4694), not this
  branch: the `ProcessExit` handler reads the static `s_sink`, which a later `Initialize` can set
  back to null.
- The fork's `PATCH-NOTES.md` still says it differs from upstream only by the Thrift struct-skip
  fix. It does not mention the column-write split in `5fff229`.
