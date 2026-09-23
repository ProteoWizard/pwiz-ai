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
- [ ] Re-profile with the compiled getters and the progress fix; confirm reflection frames are gone from the workers
- [ ] `Transition.get_Precursor` takes `lock (this)` on every call (85s own time across workers); check the field before locking
- [ ] Per-row recomputation of per-entity values: `Path.GetFileName` for ResultFile.FileName (~25s), `ModifiedSequence.GetModifiedSequence` for UnimodIds (~22s)
- [ ] Overlap enumeration of chunk N+1 with population of chunk N, so the serial ~130s between chunks stops idling the workers (matters more once the parallel part shrinks)
- [ ] `Array.SetValue` / boxing in `ColumnData.StoreValue` (~70s across workers): consider typed columns
- [ ] Document open: the tail waits ~42s for the peptide deserialization workers; the "Load Document XML" QueueWorker is capped at 8 threads
- [ ] Later ceiling: Parquet writer thread (149s CPU, mostly dictionary encoding of string columns) once the export drops under ~150s

## Decisions

- **Do not raise ParallelEx's 8-thread cap** even though the profiling machine has 64 processors; the machines that matter do not.
- **HashingStream stays synchronous.** A background hashing thread was tried (commit 7f65d9f465) and reverted: with SequentialReadStream feeding the parser, the queue and copy overhead cost more than the SHA1 it moved off the thread. A version where HashingStream owned 64KB buffers was also slower and is parked in `git stash` on this branch ("HashingStream owns 64KB read/write buffers").
- **No .NET thread pool.** SequentialReadStream uses its own `Thread`; task continuations were rejected because pool threads complicate leak checking.
- **Compiled getters only for the framework's own ReflectPropertyDescriptor**, gated by exact type name, and applied at the evaluation site in `ColumnDescriptor.Reflected` rather than by wrapping descriptors in DataSchema. Any PropertyDescriptor subclass with its own GetValue is untouched. A first attempt wrapped descriptors in DataSchema and keyed its cache on the descriptor; `PropertyDescriptor.Equals` ignores ComponentType, so `Replicate.Name` got `Protein.Name`'s getter and every call threw. Watch for this if the cache key ever changes.

## Verification so far

- PRISM export from `CommandLineReportTest`'s Rat_plasma.sky is byte-identical with and without compiled getters.
- Passing in Release: AuditLogSavingTest, AuditLogListTest, CommandLineReportTest, ParquetReportExporterTest, DocumentGridTest.

## Regression Test

- **Test name**: n/a (performance work; correctness covered by the existing report and audit log tests above)
- **Test project**: TestFunctional / TestData
- **Fails on master**: n/a
