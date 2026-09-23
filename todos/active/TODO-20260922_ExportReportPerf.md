# Speed up opening a large document and exporting a report

## Branch Information
- **Branch**: `Skyline/work/20260922_ExportReportPerf`
- **Base**: `master`
- **Created**: 2026-09-22
- **Status**: In Progress
- **GitHub Issue**: (none)
- **Module**: `skyline`
- **PR**: (pending)

## Objective

Make the scenario "open a large Skyline document from a network drive, then export a
report" substantially faster, ideally more than twice as fast for the export part.
The driving case is the PRISM report (`Skyline-PRISM.skyr`, Transition rows with
`Results!*` pivot, 23 columns) exported to Parquet from a 27GB `.sky.zip` on the U: drive.

## Background (from profiling)

Profiles and test data live in `E:\Users\nicksh\bugs\maccoss\20260922_SlowPrismReport\`
(dotTrace `.dtp` snapshots, exported to XML with the dotTrace `Reporter.exe`; the
`analyze.py` / `compare.py` scripts used for the breakdowns were session scratch).

Baseline after the first round (`SkylineCmd - [2026-09-22 15-16-19]SequentialStream.dtp`):

| Main thread phase | ms |
|---|---|
| Open document (XmlSerializer.Deserialize) | 198,010 |
| WaitForDocumentLoaded | 59,341 |
| Export report | 506,477 |

Inside the export, the main thread spent 363s in `ParquetReportExporter.PopulateChunk`
(waiting on the ParallelEx worker threads) and about 130s doing serial work between chunks
(UpdateProgress 51s, CreateDataColumn 45s, MoveNext 33s) while the workers idled.
The workers burned 2,434s of CPU, of which about 45% was reflection plumbing under
`ReflectPropertyDescriptor.GetValue` (`RuntimeMethodInfo.UnsafeInvokeInternal`,
`Type.get_IsVisible`, `PerformSecurityCheck`, `TypeDescriptor.GetAssociation`).

Document open is bounded by the network: roughly 105s to pull the file off U:.

Key files:
- `pwiz_tools/Skyline/Model/Databinding/ParquetReportExporter.cs` - chunked export, PopulateChunk
- `pwiz_tools/Shared/Common/DataBinding/ColumnDescriptor.cs` - `Reflected.GetPropertyValue`, the per-cell evaluation site
- `pwiz_tools/Shared/Common/DataBinding/ReflectedPropertyGetter.cs` - compiled getters
- `pwiz_tools/Shared/Common/DataBinding/RowItemEnumerator.cs` - progress updates
- `pwiz_tools/Shared/CommonUtil/SystemUtil/SequentialReadStream.cs` - read-ahead stream
- `pwiz_tools/Skyline/Model/AuditLog/BlockHash.cs` - HashingStream
- `pwiz_tools/Skyline/Model/Serialization/DocumentReader.cs` - load thread runs XNode.ReadFrom, peptide deserialization on a QueueWorker

## Tasks

- [x] Have TransitionResult remember its PrecursorResult; avoid repeated Nullable.GetUnderlyingType calls (ParquetReportExporter.StorageType)
- [x] SequentialReadStream: forward-only stream with a dedicated reading thread, 64KB blocks, bounded queue, keepOpen; used by SkylineWindow.OpenFile and the command line `--in` path
- [x] Compiled property getters for the framework's plain ReflectPropertyDescriptor, used only in `ColumnDescriptor.Reflected`
- [x] Fix RowItemEnumerator.UpdateProgress restarting its stopwatch (was formatting a message per row)
- [x] Re-profile with the compiled getters and the progress fix; reflection frames are gone from the workers (export 506s -> 328s)
- [x] Removed the `lock (this)` from `Transition.get_Precursor`
- [x] Per-entity values recomputed per row (ModifiedSequence, FragmentIon, ...): solved generally by `DependsOnlyOnRowValue` - columns that read only `RowItem.Value` are evaluated once per run of rows sharing the same Value object (export 328s -> 214s)
- [x] Column tree: `ColumnDescriptor.GetValueFromParent` plus `ColumnValueTree` in the exporter evaluate shared ancestors once per row (Reflected calls ~54/row -> ~15/row, `Results!*.Value` 13/row -> 1); TransitionResult getters read ChromInfo once (b56e27f6e0)
- [x] Nick's 3-stage pipeline (reader thread, populate, writer thread; e9883b7e3f) - measured slightly slower on its own because per-chunk LOH churn made the stages pause each other
- [x] Typed `ColumnBuffer<T>` with definition levels, 3 buffer sets recycled through the pipeline, and the fork's `WriteColumnsAsync` for concurrent column compression (970f344861): export 236s -> 132s
- [x] .NET 10: `ServerGarbageCollection` in Skyline.csproj and SkylineCmd.csproj (app.config's gcServer is ignored on .NET Core; the workstation GC stalled the workers, 237s of String.Ctor), SkylineCmd deploy targets fixed to the platform folder, dictionary hints for string columns (Parquet.Net 6 makes dictionary encoding opt-in per field via `ColumnEncodingHints`; the `ClrType` of a string field is `ReadOnlyMemory<char>`) (15dc5be3b7)
- [ ] Hash on the read-ahead thread: HashingStream now wraps the FileStream under SequentialReadStream in SkylineFiles.OpenFile and CommandLine.OpenSkyFile (uncommitted in sky_parquetnet8perf; AuditLogSavingTest passes)
- [ ] Fork 6.1 `-osprey2`: `DataColumnWriter.PrepareAsync`/`EmitAsync` split and `ParquetRowGroupWriter.PrepareColumnAsync<T>`/`WritePreparedColumnAsync`; the library starts no threads, Skyline prepares a row group's columns on ParallelEx workers and emits in order. Byte-identical output verified; 73 fork writer tests pass. (uncommitted in the fork and in sky_parquetnet8perf)
- [ ] Build gotcha: Skyline's compile resolves `Parquet` from BlibBuild's AnyCPU output (pwiz-sharp/Tools/BiblioSpec/src/BlibBuild/bin/Release/net10.0/Parquet.dll), not from the ParquetNet.dll HintPath, so a new fork API is invisible until that copy is refreshed (a full build's OverridePatchedParquetNet does it; otherwise copy by hand)
- [ ] Document open is 74% of the run now: read-ahead thread 97s inside the U: read (the floor), load thread 42s XML parse + 21s hash + 52s waiting for data + 29s waiting for peptide workers; WaitForDocumentLoaded 44s reading .skyd headers serially afterwards. Next: overlap the chromatogram cache header load with the XML parse
- [ ] Reader thread: pre-size the chunk list to RowsPerGroup (12s of List growth); not the bottleneck
- [ ] Result columns still ~55% of worker CPU (CachedValue GetValue ~216s own): fold CachedValues fields into TransitionResult, or fetch ChromInfo once per row for all six columns
- [ ] Overlap enumeration of chunk N+1 with population of chunk N (MoveNext is ~38s serial on the main thread)
- [ ] `Array.SetValue` / boxing in `ColumnData.StoreValue` (~70s across workers): consider typed columns
- [ ] Document open: the tail waits ~42s for the peptide deserialization workers; the "Load Document XML" QueueWorker is capped at 8 threads

## Progress (main thread, ms; profiles in the bugs folder)

| Snapshot | Total | Open | Export | Export workers CPU |
|---|---|---|---|---|
| 15-16-19 SequentialStream | 765,007 | 198,203 | 506,477 | 2,434,588 |
| 21-06-29 ReflectedPropertyGetter | 580,569 | 198,081 | 327,644 | 1,563,094 |
| 22-07-59 DependsOnRowValue | 454,857 | 188,969 | 214,006 | 732,485 |
| 00-44-50 MoreParallel (3-stage pipeline) | 475,634 | 188,109 | 236,166 | 736,053 |
| 01-09-09 typed buffers + WriteColumnsAsync | 372,487 | 187,462 | 132,048 | 598,821 |
| 11-51-09 .NET 10 + Parquet.Net 6.1 (workstation GC, plain strings) | 490,360 | 199,175 | 237,410 | 473,742 |
| 12-53-18 .NET 10 + server GC + dictionary hints | 286,998 | 168,095 | 73,991 | 157,591 |

The .NET 10 work continues in checkout `sky_parquetnet8perf`, branch `Skyline/work/20260923_ParquetPerfNet8`
(Nick's .NET 10 port merged with this branch), with the Parquet.Net 6.1 fork at
`E:\Users\nicksh\git_e\developers\skylinedev\Parquet.Net6` (branch `20260923ParquetNet6`).
Profile the x64 output: `pwiz_tools\Skyline\bin\x64\Release\net10.0-windows\SkylineCmd.exe`. The team
build script always builds x64, so `bin\Release\net10.0-windows` (AnyCPU) goes stale silently; two profiles
were taken against it before this was noticed.

Stages in the last run: reader ~67s busy, populate 90s, writer 121s wall. The writer is the wall
now. Its ~315s of CPU across the compression threads is mostly not compression: ArrayPool.Rent
fallback allocations 121s (17MB column chunks exceed the 1MB max of ArrayPool<byte>.Shared on
.NET Framework), LINQ Buffer<T> from a ToArray in the plain encoder 40s, Span.ToArray of the
compressed chunk 25s, and ~90s computing Distinct for every column to decide on dictionary
encoding (Dictionary.FindEntry, GetHashCode, HashSet).

Reporter.exe's XML `Samples` attribute is stack samples, not call counts (Program.Main shows 48,275), even with `--only-call-count`. Call counts need the dotTrace GUI on a Tracing snapshot. The exported report has 69,483,192 rows in 33 row groups.

## Decisions

- **Do not raise ParallelEx's 8-thread cap** even though the profiling machine has 64 processors; the machines that matter do not.
- **HashingStream stays synchronous.** A background hashing thread was tried (commit 7f65d9f465) and reverted: with SequentialReadStream feeding the parser, the queue and copy overhead cost more than the SHA1 it moved off the thread. A version where HashingStream owned 64KB buffers was also slower and is parked in `git stash` on this branch ("HashingStream owns 64KB read/write buffers").
- **No .NET thread pool.** SequentialReadStream uses its own `Thread`; task continuations were rejected because pool threads complicate leak checking.
- **Peptide.ModifiedSequence caching was committed (5a06ff7629) and then undone (af8250a099)** in favor of the general DependsOnlyOnRowValue mechanism, which covers every per-entity column without touching entities.
- **Compiled getters only for the framework's own ReflectPropertyDescriptor**, gated by exact type name, and applied at the evaluation site in `ColumnDescriptor.Reflected` rather than by wrapping descriptors in DataSchema. Any PropertyDescriptor subclass with its own GetValue is untouched. A first attempt wrapped descriptors in DataSchema and keyed its cache on the descriptor; `PropertyDescriptor.Equals` ignores ComponentType, so `Replicate.Name` got `Protein.Name`'s getter and every call threw. Watch for this if the cache key ever changes.

## Verification so far

- PRISM export from `CommandLineReportTest`'s Rat_plasma.sky is byte-identical with and without compiled getters.
- Passing in Release: AuditLogSavingTest, AuditLogListTest, CommandLineReportTest, ParquetReportExporterTest, DocumentGridTest.

## Regression Test

- **Test name**: n/a (performance work; correctness covered by the existing report and audit log tests above)
- **Test project**: TestFunctional / TestData
- **Fails on master**: n/a
