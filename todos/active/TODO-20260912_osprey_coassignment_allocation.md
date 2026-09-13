# Osprey: the model-diagnostics co-assignment panel allocates ~30 GB/min and inflates committed memory to 42 GB at 446 runs

## Branch Information
- **Branch**: `Skyline/work/20260912_osprey_coassignment_allocation` (`C:\proj\pwiz-work2`, off
  master `7af9eb0ea5`)
- **Base**: `master`
- **Created**: 2026-09-12
- **Status**: In Progress
- **GitHub Issue**: [#4657](https://github.com/ProteoWizard/pwiz/issues/4657)
- **Module**: `osprey`
- **PR**: (pending)
- **Labels to carry**: `performance`

## Objective

`PeakCoAssignmentSource.Build` is the largest single memory consumer in `--task ModelDiagnostics`
at cohort scale and the only part of that command whose memory is not flat: on the 446-run CHS
cohort it takes private bytes from ~10 GB to 41.7 GB in 12.5 minutes (12.5 of `FirstPassFDR`'s
69). The live set is small and bounded - the O(files x entries) retention was already removed -
so what remains is ALLOCATION RATE: per-file dictionaries of ~4.2 M entries built from empty and
discarded 446 times, plus per-file parquet column reads, at ~30 GB/min of large-object garbage.
Server GC answers that rate by expanding committed memory. Committed-but-free, not a leak, and
cheap to fix without changing a byte of output.

Measured (446-run CHS, `--task ModelDiagnostics`, exe snapshot of `1b9dc83cf7`):

| when | phase | private | managed |
|---|---|---|---|
| 56 min | `FirstPassFDR` fold, one run resident at a time | flat ~10.5 GB | flat ~7.5 GB |
| 3.5 min | co-assignment phase 1: scanning 1st-pass sidecars over 446 files | 10 -> 35 GB | sawtooth 9-19 GB |
| 9 min | co-assignment phase 2: joining apex RT over 446 files | 35 -> 41.7 GB | sawtooth 9-19 GB |

## Where the allocation comes from (from the issue)

**Phase 1 - decoy score cutoffs.** Per file, `FdrScoresSidecar.ReadRecords` streams every record
(~4.18 M x 28 B = 117 MB; 52 GB of IO cohort-wide) and `ObserveCutoff` folds each into
`_fileBest` (`Dictionary<uint, double>` keyed by entry id) and `_fileAccepted` (`HashSet<uint>`).
`SealRunCutoff` reduces the dictionary to ONE number plus a few thousand admitted decoy ids, then
`_fileBest = new Dictionary<uint, double>()`: ~22 prime-doubling resizes to ~4.18 M entries, each
a new bucket + entry array on the LOH, ~230 MB of garbage per file, 446 times in 3.5 min. The
dictionary is ~100x larger than the information it yields.

**Phase 2 - apex-RT join** (`AddFile`). Per file: `ParquetScoreCache.TryReadEntryIdsAndApexRts`
reads two full columns (4.18 M x 12 B = 50 MB of arrays plus Parquet's transient buffers), then
the SAME sidecar is streamed a second time (another 52 GB of IO) to re-derive `runQ` /
`experimentQ` for rows already classified in phase 1. Rows clearing the cutoff build a string key
(`modSeq + "|" + charge`) and a `CoAssignmentRow`, retained in `_fileRows` / `_byPrecursor` -
O(accepted precursors x runs), ~16.5 M rows, ~2-3 GB: the genuine live growth. The rest of
35 -> 41.7 GB is committed expansion from the per-file column reads.

## Tasks

- [ ] Phase 1: stop re-allocating the per-file containers. Minimal: `Clear()` keeps the grown
      capacity. Better: replace `_fileBest` with two flat `double[]` indexed by base id (targets
      and decoys; base ids are dense under the 6.2 M-entry library), ~100 MB allocated once for
      the whole panel, O(1) per record, zero per-file allocation; `_fileAccepted` as a bit array
- [ ] Phase 2: read each sidecar once. The join needs apex RT only for rows that clear the
      cutoff, and which rows those are is known after phase 1 - carry the per-file accepted set
      (or re-derive from the sealed cutoff) instead of re-streaming 117 MB per file
- [ ] Phase 2: pool the two parquet column arrays (`ArrayPool<T>`) so the 50 MB per file is not
      re-allocated; Parquet's own buffers are out of reach
- [ ] Verify with `perfviz.py` on the 446-run bed (`D:\test\osprey-runs\chs-seer\runs\chs446-mdiagtest-copy`,
      `--task ModelDiagnostics`, products deleted first, `OSPREY_VERSION_OVERRIDE=26.1.1.243`,
      exe snapshotted): the 22:01-22:14 excursion should collapse toward the fold's ~10 GB
      floor, and the report must stay byte-identical (`Compare-DiagReports.ps1`, strict,
      against the products the current build produces - banked at
      `ai/.tmp/sessions/20260910-01Qwgkv/oracle-products/`)
- [ ] Gates: `regression.ps1 -Dataset StellarLibDecoy` (modes 7 and 11 cover the panel), then
      `regression-parallel.ps1 -Dataset All`; output byte-identical is the whole acceptance
      criterion

## Regression Test

- **Test name**: (the acceptance criterion is byte-identical output; the diagnostics-report
  goldens in modes 1b / 5 / 7 / 11 are the regression test, and the 446-run perfviz plot is the
  performance verification - no new unit test is planned unless the phase-1 restructuring
  earns one for the flat-array reduction)
- **Test project**: Regression (goldens)
- **Fails on master**: n/a - performance change, output must not move
- **Passes on fix**: (perfviz numbers and the strict report compare, when run)

## Watch for

- `SealRunCutoff` builds `admitted` as a `HashSet<uint>` from a dictionary walk; if any consumer
  enumerates that set into the report, the enumeration order (insertion-dependent) is part of
  the byte-identity contract and a flat-array walk changes it. Check every reader of
  `_admittedRunDecoys` before touching the container.
- The same per-file `Dictionary<uint, FdrScoreRecord>` shape lives in
  `FirstPassFdrTask.StreamFirstPassFileScores` (protein FDR reduce, and since #4661 the pass-1
  FDRBench emitter). Same churn at 446 files; a fix here should be the shape that one adopts.

## Progress Log

### 2026-09-12 - Session Start

Branch created off master `7af9eb0ea5` in `pwiz-work2` (the other two checkouts hold open PRs
#4660 and #4661). Origin: PR #4656's 446-run oracle and
`TODO-20260910_osprey_mdiag_resident_removal.md` ("Recorded from the 446 runs").
