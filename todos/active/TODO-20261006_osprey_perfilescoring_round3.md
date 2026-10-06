# TODO-20261006_osprey_perfilescoring_round3.md

## Branch Information
- **Branch**: `Skyline/work/20261006_osprey_perfilescoring_round3` (`C:\proj\pwiz-scanmajor`)
- **Base**: `Skyline/work/20260612_net8_port` (PR #4619), at 490a4d3825 (the 2026-10-06 force-pushed history)
- **Created**: 2026-10-06
- **Status**: In progress - SEA-AD baseline running; miss-filter prototype next
- **Module**: `osprey`
- **PR**: none
- **Follows**: `ai/todos/completed/TODO-20261005_osprey_perfilescoring_round2.md` (#4781)

## Objective

Reduce PerFileScoring CPU further, in measured priority order, adding complexity only where a quiet
interleaved A/B proves it (Brendan's rule: clean code first, measure before optimizing, complexity only where
the measurements warrant it). Each change: data-identical output, 3-rep interleaved A/B on the quiet machine,
kept only if the reps do not overlap - otherwise dropped, not tuned.

## Measured picture (quiet i9-14900K, Astral file 49, port tip, library load excluded)

Scoped dotTrace (`ProfilerHooks` around the per-file loop; `sprofile-port-213b66b9de-hooks` in
`ai/.tmp/sessions/20261005-pfs2/`): per-file span 43.7 s wall = coelution + dedup 25.5 s (58%), RT calibration
10.8 s (25%), parquet write 5.5 s (13%, single-threaded). Thread time: coelution ~635 s, calibration ~276 s of
which ~133 s is serialized window reads (mostly lock wait), so ~80/20 coelution/calibration in real CPU.

Within window scoring: XIC lookups 25%, xcorr preprocess 13.5%, CWT 12%, rest of SG sweep ~10%, prefilter 7.6%,
median polish ~7%. XIC counters (temporary instrumentation): 1.6 billion m/z lookups per file, 19% hits.

## Decisions
- **Rolling join for XICs: abandoned (measured slower).** One scan-major rolling join per window (spectra and
  candidates both in RT order, scored on completion, entries re-sorted by index) was data-identical but coelution
  was +4% (68.7-69.0 s -> 71.6-72.0 s over 3 files, 3 interleaved reps, quiet). XIC extraction itself fell only
  6%; scoring interleaved in the join slowed (cache pressure of ~1,300 active candidates). The 512-candidate
  library-order blocks are not the bottleneck - lookup count is, and Skyline pays the same count. Patch kept at
  `ai/.tmp/sessions/20261005-pfs2/rolling-join-abandoned.patch`; branch deleted.
- **Producer/consumer scoring thread (Skyline's shape): not pursued.** ~28 windows are already in flight on 32
  hardware threads, so overlapping extraction and scoring within a window adds threads, not capacity.
- **Parallel files for the baseline: defaults (sequential, 30 threads)** for comparability with 2026-08-12.

## Tasks
- [x] Wire `ProfilerHooks.StartMeasure/SaveAndStopMeasure` around the PerFileScoring per-file loop (nothing called
      them; `Profile-Osprey.ps1 -ScopeToMainSearch` recorded nothing) - committed 971f4227bb
- [ ] SEA-AD 82-file end-to-end baseline at the port tip (launched 2026-10-06 11:53, snapshot
      `D:\test\osprey-runs\_bin\port-490a4d3825-hooks`, run dir
      `D:\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-protein-compact-port490a4d-20261006_115333`);
      compare to 2026-08-12 (510 min; PerFileScoring 4 h 11 m)
- [ ] Miss filter for m/z lookups (per-spectrum occupancy bitmap; exact: only rules out windows with no peak);
      kill if XIC share does not drop >= 30% with a non-overlapping coelution A/B
- [ ] Calibration CPU breakdown (after the miss filter)
- [ ] Median polish: reuse the pick's winner polish in the feature pass (~1.4%); bound-skip of non-winning peaks
- [ ] Optional: re-measure --parallel-files 1 vs 4 (process-wide lock) on 12 SEA-AD files with current code;
      hand numbers to `TODO-20261005_osprey_per_stage_parallel_files.md`

## Progress Log

### 2026-10-06
- Created after #4781 merged. Quiet measurements, rolling-join abandonment, scoped profiling, SEA-AD launch.
- Miss filter prototyped (UNCOMMITTED until measured): `MzBucketIndex` gains an occupancy bitmap (32 bins/peak,
  4 B/peak) and `LowerBoundIfAnyIn(lower, upper)` returning -1 when no peak can lie in the window (exact: bins are
  monotone like buckets); `Spectrum.MzLowerBoundIfAnyIn`; used by `TopFragmentExtractor.FindClosestPeakInWindow`
  (XICs) and `FragmentMath.HasTopNFragmentMatch` (prefilter, calibration). `TestMzBucketIndexMatchesBinarySearch`
  checks every window against brute force. Gate 655/655, inspection 0/0. Snapshot
  `D:\test\osprey-runs\_bin\missfilter-wip1`. One ~3 min gate ran during SEA-AD PerFileScoring (noise ~0.5%).
- Queued: `ai/.tmp/sessions/20261005-pfs2/after-seaad-chain.ps1` (detached, waits on the SEA-AD driver pid 9680),
  then a 3-rep interleaved A/B port-490a4d3825-hooks vs missfilter-wip1 (`missab.log`, also the identity check)
  and scoped profiles of both (`sprofile-*`). Log: `after-seaad-chain.log`.
