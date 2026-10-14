# TODO-20261014_osprey_parquet_datafield_race.md

## Branch Information
- **Branch**: `Skyline/work/20261014_osprey_parquet_datafield_race`
- **Base**: `master`
- **Created**: 2026-10-14
- **Status**: Completed
- **GitHub Issue**: (none - found by the 2026-10-13 sprint acceptance run)
- **Module**: `osprey`
- **PR**: [#4842](https://github.com/ProteoWizard/pwiz/pull/4842) (merged 2026-10-14)

## Objective

Fix concurrent `.scores.parquet` / `.scores-reconciled.parquet` writes corrupting nullable
columns. With `--parallel-files-scoring` or `--parallel-files-rescoring` above 1, one write could
record present values as null. The values after them then shift within the row group, and
nothing in the file shows it.

## How it was found

The three-machine acceptance of the no-resident-pools sprint
(`TODO-20261010_osprey_no_resident_pools_sprint.md`, results under
`\\...\MacCoss\Osprey\acceptance-20261013\results\`) required byte-identical products across
machines. On SEA-AD 82, MACS2 (`-ParallelFilesScoring 4 -ParallelFilesRescoring 8`) and UW25
(sequential) had identical `out.protein_groups.tsv`. `out.stats.tsv` differed in one row,
run `SEA-AD-0028_7240_C07_037`: 36,501 / 33,976 / 5,356 precursors / peptides / proteins on
MACS2 vs 36,480 / 33,957 / 5,354 on UW25.

- First divergence in `run.log`: run 28's cross-run reconciliation, with 35,295 re-pick /
  41,048 impute on MACS2 vs 35,891 / 40,452 on UW25.
- `ReconciliationPlanner.DetermineAction` chooses re-pick or impute from the stored
  `cwt_candidates` list.
- A sequential 30-thread rescore of run 28 on MACS2 gave a parquet identical to the
  acceptance one in every column except `cwt_candidates`. In the acceptance file, row
  group 0 has 6 null cells at rows 1349-1354, every later value in the group is shifted
  down 6 rows, and the last 6 lists are dropped. Row group statistics report
  `null_count = 0`.
- So it is not a difference in machine arithmetic: the corruption happened inside the
  parquet write.

## Root cause

`ParquetScoreCache` held its columns as `static readonly DataField`s and built a new
`ParquetSchema` from them on every write.

- Attaching a field to a schema runs Parquet.Net's `DataField.PropagateLevels`, which sets
  `MaxDefinitionLevel = 0` and then increments it to 1.
- `PrepareNullableColumn` reads `field.MaxDefinitionLevel` for every row.
- With two writes in flight in one process, a schema build on one thread could make the
  other thread write definition level 0 (null) for a present value while still appending
  the value.
- Statistics are counted from the values, so they still report zero nulls.

Reproduced against the shipped `Parquet.dll`: a per-row reader saw `MaxDefinitionLevel != 1`
1,315,526 times in 3.6 billion reads while another thread built schemas over the same field.

## Fix

- Each write builds its own `WriteFields`: fresh `DataField`s plus the schema they are
  attached to. Nothing is shared between writes.
- Readers address columns by `COLUMN_*` name constants.
- New test `IOTest.TestConcurrentScoresParquetWritesKeepCwtCandidatesAligned`:
  - concurrent 20,000-row writes, where each row's candidate apex equals its id;
  - each file is read back and checked row by row;
  - fails on the old code in 3 of 5 runs (e.g. "3 of 125 concurrently written files
    misaligned"); passes 9 of 9 on the fix.

## Verification

- [x] New test fails on old code, passes on fix (after a clean rebuild; an incremental
      build skipped a file restored by `Copy-Item` with an old timestamp)
- [x] Osprey unit tests 641/641; inspection 0 warnings
- [x] End-to-end SEA-AD 82, FirstPassFDR onward, with the fix binary and
      `-ParallelFilesRescoring 8`, from the acceptance run's artifacts with run 28's
      parquet replaced by the clean rescore:
  - `out.stats.tsv` and `out.protein_groups.tsv` are byte-identical to UW25's.
  - `out.blib` differs only in `LibInfo` and the source file paths.
  - The 82 reconciled parquets it wrote are clean by `parqdetect.py`.
- [x] `/code-review medium`: no correctness findings. Fixed a stale comment, and the test now also checks the read-back row count and makes a minimum of 3 writes per writer.
- [x] TeamCity: all 16 checks green, including Perf/Regression #315 (#313 was red from `tctest.bat`'s `OSPREY_EXIT`, fixed in `e22de13b7e`)

## Detection of existing files

`results\MACS2\parqdetect.py` on the acceptance share compares each nullable column's data
nulls with its statistics `null_count`, per row group. It reads the full columns, because
statistics alone cannot see the corruption.

- SEA-AD acceptance: 1 of 164 parquets hit.
- CHS acceptance, first 304 `.scores.parquet`: 0 hit.
- Only runs with parallel files are exposed: MACS2's fast1 (2026-10-06) and CHS (2026-10-08)
  could carry it. The i9s' sequential runs cannot.

## Progress Log

### 2026-10-14 - Found, fixed and verified during the MACS2 acceptance night session

Branch commit `b160fcd8f8`, based on master `4c2eba1af8` (#4838).

### 2026-10-14 - Perf/Regression red from tctest.bat, not from the fix

Build #313 (ID 4216731): Osprey regression 48/48 and 106 tests passed; the CarafeSharp chained
leg failed at Osprey startup with "does not recognize the environment variable(s) OSPREY_EXIT".
`tctest.bat` saves the Osprey regression's exit code in `OSPREY_EXIT` before running CarafeSharp,
and #4825 made Osprey refuse unknown `OSPREY_*` variables. The last green build (#302) predates
both #4825 and #4717, so master fails the same way. Renamed it to `OSPREYDEV_EXIT`, the prefix
for script variables (commit `e22de13b7e`).

### 2026-10-14 - Merged

PR #4842 merged as commit `7066e0ac39`. Shipped: a `WriteFields` instance (fresh `DataField`s
plus schema) per scores-parquet write so concurrent writes no longer race on
`MaxDefinitionLevel`, the `TestConcurrentScoresParquetWritesKeepCwtCandidatesAligned`
regression test, and the `tctest.bat` rename to `OSPREYDEV_EXIT` that unblocked
Perf/Regression on master (the chained CarafeSharp leg passed for the first time in #315).
Nothing deferred; no follow-up issues. Existing parquets written with parallel files before
this fix can be checked with `parqdetect.py` on the acceptance share.
