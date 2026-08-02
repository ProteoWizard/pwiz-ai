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

### Part 2: key IndexedRetentionTimes/IndexedIonMobilities by file index (planned)

Both classes map `fileId` (a `SpectrumSourceFiles` primary key, an arbitrary integer) to an
array of values. Change them to key off the index into `LibraryFiles` instead, and store
the values as a `ReplicatePositions` plus one flat array, which suits a multimap from
dense zero-based keys when the value count is comparable to the key count.

Risk: old key and new key are both `int`, so a mix-up will not be caught by the compiler.

## Tests

Existing coverage only. TestRedundantComboBox, TestBuildLibraryShare, TestLibraryExplorer,
TestLibraryExplorerAsSmallMolecules, TestMinimizeIrt, TestMinimizeWithEmptyFiles pass.

## Status

- [x] Part 1 implementation complete
- [x] Build clean
- [x] Tests pass
- [ ] Part 2 implementation
- [ ] PR created
