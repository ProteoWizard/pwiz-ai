# TODO: Speed up spectrum lookup in large BiblioSpec libraries

- **Branch:** `Skyline/work/20260801_redundant_spectra_perf`
- **Base:** `master`
- **Module:** `skyline`
- **Created:** 2026-08-01
- **Status:** Active

## Objective

Selecting a peptide against a large non-redundant BiblioSpec library was very slow.
`BiblioSpecLiteLibrary.GetRedundantSpectra` queries the `RetentionTimes` table on every
call, and that table has no index on `RefSpectraID` - BiblioSpec has never created one
(`BlibMaker::commit` creates six indexes, none on `RetentionTimes`, and the
`FOREIGN KEY(RefSpectraID)` in the DDL does not give SQLite an index on the child column).
So each call is a full table scan, twice: once for `RetentionTimesPsmCount`'s
`SELECT count(*)` and once for the actual query.

The library that exposed this is
`I:\bugs_i\maccoss\20260722_MemoryOptimization\NewFormat\imputation_template.blib`:
129,448,506 rows in `RetentionTimes`, 171,518 in `RefSpectra`, 936 source files.

The query was never necessary for these libraries. It dates from 2011 (c82800860), when
`BiblioLiteSpectrumInfo` held only key/copies/numPeaks/id and SQL was the only source of
file name and retention time; 611b7ca29 then routed best-match through it as well, and
ff70a03ad (2012) moved retention times into memory without revisiting it. The whole
`RetentionTimes` table is already read at load by `RetentionTimeReader.ReadAllRows`.

Requested by Nick.

## Implementation

### Part 1: skip the RetentionTimes table when it cannot yield a redundant spectrum (done)

`RedundantRefSpectraID` is the row's id in the `.redundant.blib`. `BlibFilter` always
writes a real rowid (>= 1); libraries built without BlibFilter write a literal zero
(`DiaNNSpecLibReader.cpp:1461`), because there is no redundant library at all. `BlibDb`
has treated `RedundantId == 0` as "nothing to load" since 2013 (bd177aa91).

- `RetentionTimeRow` now maps `RedundantRefSpectraID` (the read is already `SELECT *`, so
  no extra I/O), and `RetentionTimeReader.AnyRedundantSpectra` latches true if any row is
  non-zero. Only ever set to true, so the parallel reader threads need no synchronization.
- `BiblioSpecLiteLibrary._anyRedundantSpectra` holds it after `ReadAllRows`.
- `GetRedundantSpectra`'s `hasRetentionTimesTable` is renamed `useRetentionTimesTable` and
  is now just `_anyRedundantSpectra`, so these libraries take the existing
  `RefSpectra JOIN SpectrumSourceFiles WHERE t.id = ?` branch, which hits the primary key.
  Verified the values agree: for `RefSpectra.id = 1`, `retentionTime` and `fileID` match
  the `bestSpectrum = 1` row in `RetentionTimes`.

Behavior change: for an all-zero library the redundant path returns one spectrum (the
best) instead of one per run. Those extra entries were never loadable - `LoadSpectrum`
threw `IOException` on all but the best - and Library Explorer's existing "older libraries
don't support getting redundant spectra" fallback covers the single-option case.

`RetentionTimesPsmCount` is still used for library details, just no longer per selection.

### Part 2: key IndexedRetentionTimes/IndexedIonMobilities by file index (done)

Both mapped `fileId` (a `SpectrumSourceFiles` primary key) to an array of values, using an
`ImmutableSortedList<int, T[]>`. That is one object per file per spectrum, which on a
library where every peptide was seen in every one of hundreds of runs dominates the memory.

- New `IndexedMultiArray<T>` (Model/Results, next to its `ReplicatePositions` dependency):
  an `IReadOnlyList<IList<T>>` laid out by a `ReplicatePositions` over one flat
  `ImmutableList<T>`, the same shape as `ChromFileIdMap`, with the indexer handing back a
  `ReadOnlyList.Create` view rather than copying. Two objects per spectrum instead of two
  per file per spectrum. The tradeoff is that space is proportional to the highest index
  used, so the keys have to be small numbers - which is why the key changed from the
  database id to the index into `LibraryFiles`.
- `IndexedRetentionTimes` and `IndexedIonMobilities` are now thin wrappers over it.
- Every call site already had the file's index in hand and was converting it to an id with
  `_librarySourceFiles[j].Id`, so most sites got shorter.

Guarding against the id/index mix-up (both are `int`, so the compiler cannot tell them
apart): the properties were renamed `RetentionTimesByFileId` -> `RetentionTimesByFileIndex`
and `IonMobilitiesByFileId` -> `IonMobilitiesByFileIndex`, which turned every read site
into a compile error that had to be visited. Note that `PeakBoundariesByFileId` is
deliberately still keyed by id, and `ChromLibSpectrumInfo.SampleFileId` still holds an id.

Producers which had to learn the mapping:
- `RetentionTimeReader` gained a `FileIndexesById` property, set from the
  `SpectrumSourceFiles` rows which are already read before the retention times.
- `ChromatogramLibrary` had to move its `SampleFile` query ahead of the precursor query,
  since it previously read the sample files after building the entries.
- `BlibDb.CreateLibraryFromSpectra` collects ion mobilities by source file id during its
  parallel insert loop and indexes them afterwards, once all the file ids are known.

The ChromLib cache format changed (it serializes `IndexedRetentionTimes`), so
`CURRENT_VERSION`/`MIN_READABLE_VERSION` went 5 -> 6.

Also removed while converting: `BiblioSpecLiteLibrary.GetMinRetentionTime` (no callers) and
`IndexedIonMobilities.Write`/`Read` (no callers since the .slc cache was dropped in #3478).

## Tests

Existing coverage only. Passing: TestAddLibrary, TestAddMixedLibrary, TestLibraryExplorer,
TestLibraryExplorerAsSmallMolecules, TestSplitGraph, TestIonMobility,
TestRetentionTimeAlignment, the LibraryLoadTest set, DocLoadLibrary, TestBlibDriftTimes,
the MeasuredDriftValues set, TestRedundantComboBox, TestBuildLibraryShare, TestMinimizeIrt,
TestMinimizeWithEmptyFiles, CodeInspection.

## Status

- [x] Part 1 implementation complete
- [x] Part 2 implementation complete
- [x] Build clean
- [x] Tests pass
- [ ] Measure the memory improvement on imputation_template.blib
- [ ] PR created
