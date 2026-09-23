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
- [ ] Result columns: each of the 8 result columns re-enters `CachedValue` on a cold TransitionResult/PrecursorResult (~556M calls, ~0.5us each = memory latency, ~300s worker CPU). Fetch ChromInfo once per row for all six TransitionResult columns, and/or fold CachedValues fields into TransitionResult to save a pointer hop
- [ ] Parquet writer thread is now on the critical path: main thread blocks ~51s in `writeWorker.Add`; writer is ~120s CPU, mostly dictionary encoding of string columns. Write row groups from more than one thread or skip dictionary encoding for high-cardinality strings
- [ ] Overlap enumeration of chunk N+1 with population of chunk N (MoveNext is ~38s serial on the main thread)
- [ ] `Array.SetValue` / boxing in `ColumnData.StoreValue` (~70s across workers): consider typed columns
- [ ] Document open: the tail waits ~42s for the peptide deserialization workers; the "Load Document XML" QueueWorker is capped at 8 threads
- [ ] Later ceiling: Parquet writer thread (149s CPU, mostly dictionary encoding of string columns) once the export drops under ~150s

## Progress (main thread, ms; profiles in the bugs folder)

| Snapshot | Total | Open | Export | Export workers CPU |
|---|---|---|---|---|
| 15-16-19 SequentialStream | 765,007 | 198,203 | 506,477 | 2,434,588 |
| 21-06-29 ReflectedPropertyGetter | 580,569 | 198,081 | 327,644 | 1,563,094 |
| 22-07-59 DependsOnRowValue | 454,857 | 188,969 | 214,006 | 732,485 |

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
