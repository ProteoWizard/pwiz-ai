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

### 2026-09-12 - Implemented; unit gate green; StellarLibDecoy gate running

Three files, +130/-48, on `pwiz-work2`:

* **Phase 1** (`CoAssignmentPassBuilder`): `_fileBest` (`Dictionary<uint, double>` by entry id,
  rebuilt per file) and `_fileAccepted` (`HashSet<uint>`) are two `double[]` by BASE id (target
  and decoy sides) plus a `bool[]`, allocated once via `ReserveRunScope(maxBaseId)` - the
  caller takes the bound from the experiment-scope map, since every record phase 1 folds is
  gated on having one - and reset by a fill between files. NaN = not seen this file, which is
  what the dictionary's missing key meant, so `ObserveCutoff`'s store rule and
  `SealRunCutoff`'s two reductions are the same expressions over a different container.
  `_admittedRunDecoys[f]` is still the per-file `HashSet` (only ever probed with `Contains`,
  never enumerated, so no ordering reaches the report). Grows on demand if unreserved, so the
  unit tests that build a builder bare still work.
* **Phase 2** (`ParquetScoreCache.TryReadEntryIdsAndApexRts`): fills caller-owned `ref` arrays
  and reports `count`, growing them only when a file is larger than any before it;
  `PeakCoAssignmentSource.BuildCore` holds them across the loop. Parquet.Net's own per-row-group
  column arrays are out of reach.
* **Not done, and why**: "read each sidecar once" (the issue's second phase-2 item). Phase 2
  keeps the best-scoring row per (precursor, file) among rows that clear a gate the DECOY side
  of which is only known after every file is sealed (`SealCutoffs`), and pass 1 is
  pre-compaction, so a precursor has many candidate rows per file. Carrying "the rows phase 2
  will keep" from phase 1 therefore means buffering candidate rows for every file across the
  cohort - the O(files x rows) shape this panel was rebuilt to avoid. The second sidecar stream
  is IO (117 MB/file) with no per-record allocation (`in FdrScoreRecord`), so it is not what
  drives the committed-memory excursion; the column arrays and the per-file dictionary were.

`Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`: 593/593, 0 warnings.
`regression.ps1 -Dataset StellarLibDecoy` (modes 7 and 11 compare the diagnostics report to
its golden) running; then the 446-run bed via `oracle-446-4657.ps1` (this session dir), strict
against the banked current-build products, with perfviz; then `regression-parallel.ps1
-Dataset All`.

### 2026-09-12 - The flat arrays were O(n^2) without a reserve; fixed and pinned

The StellarLibDecoy gate passed but was 30-60% slower everywhere a pass-2 diagnostics report is
built. Per-leg, against the same dataset's legs on the fdrbench branch's `-Dataset All` run
earlier the same day:

| leg | fdrbench branch | #4657 branch |
|---|---|---|
| pay-later diagnostics fold (mode 11) | 15.7 s | 492.2 s |
| HPC 4-task chain (mode 3) | 557.6 s | 846.5 s |
| resume (mode 2) | 172.7 s | 470.2 s |
| Stage-5 rehydrate (mode 5) | 93.0 s | 422.8 s |

Root cause: `EnsureRunScopeCapacity` grew to exactly `baseId + 1`. Rows reach `ObserveCutoff`
in parquet row order, which is ASCENDING entry id, so an unreserved builder saw a new maximum on
almost every row and copied all three arrays each time - O(n^2) per file. `ReserveRunScope` hides
it on the phase-1 path (`PeakCoAssignmentSource`), which is why the 446-run bed's first phase
looked fine; the PASS-2 builder in `SecondPassFdrTask` is constructed bare and never reserved, so
every pass-2 fold paid it. The 446-run oracle launched at 18:36 was still inside that fold at
21:22 (it had reached the pass-1 boundary at 19:46), which is what exposed it.

Fix: geometric growth (`max(baseId + 1, 2 * old)`), so a reserve from empty still lands exactly
on `maxBaseId + 1` and an unreserved ascending stream grows O(log n) times.
`TestCoAssignmentRunScopeGrowsGeometrically` pins both halves and is red on the exact-growth
version (verified: "grew the run scope 100000 times; geometric growth allows at most 18").

Commits `997ed8d94b` + `e23ffdd616`, now REBASED onto the #4661 branch
(`Skyline/work/20260912_osprey_fdrbench_pass_bitmask` @ `7c595218e6`) so one TeamCity run
validates both, per Brendan's night-session instruction. #4661 merges first.
