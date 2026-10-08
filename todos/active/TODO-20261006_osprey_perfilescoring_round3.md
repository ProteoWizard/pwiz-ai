# TODO-20261006_osprey_perfilescoring_round3.md

## Branch Information
- **Branch**: `Skyline/work/20261006_osprey_perfilescoring_round3` (`C:\proj\pwiz-scanmajor`)
- **Base**: `Skyline/work/20260612_net8_port` (PR #4619), at 490a4d3825 (the 2026-10-06 force-pushed history)
- **Created**: 2026-10-06
- **Status**: Reviewed and fixed; waiting on the port branch becoming master, then PR to master. Rebased on
  9e2b516bcb (#4789); FOUR local commits, not pushed (hooks, reads, sidecar buffer, 02c467d8cf review fix).
  Stellar + Astral regressions PASS (before the review fix; the validity branch's Stellar gate covers it).
  Stacked on it:
  `TODO-20261007_osprey_self_validating_artifacts.md` (C:\proj\pwiz-validity).
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

## Where PerFileScoring profiling stands (2026-10-07) - read this before more PerFileScoring perf work

- SEA-AD PerFileScoring: 4 h 11 m (2026-08) -> 2 h 00 m (2026-10-06), via #4767 serial block reads, #4768 lazy
  xcorr, #4770 m/z bucket index, #4779 scan-major prefilter/XIC/calibration, #4781 median selection + cosine
  index, and (round 3, local) pooled calibration read blocks (-11% calibration).
- Per file (Astral 49, quiet, library excluded): coelution 58% of wall, calibration 25%, parquet write 13%.
- Window scoring has no single hotspot above ~27%, and every item with a known fix is now under ~2% of it:
  XIC extraction 27% (see below), xcorr preprocess 13.5% (each touched spectrum once, already on demand), CWT
  12%, rest of SG sweep ~10%, prefilter 7.6%, median polish ~7% (duplicate polish ~1.4%).
- XIC extraction, attributed with temporary NoInlining (2026-10-07, `sprofile-xic-attrib-report.xml`): 65% of
  it is the body of `MzBucketIndex.LowerBound` (~17% of window scoring, ~1.6 billion calls/file, ~68 ns of thread
  time each); loop overhead 20%, `ClosestPeakFrom` 5.5%, the intensity write 1.8%. 68 ns is far above the
  arithmetic, so it is cache misses on `_start`/`mzs` or branch mispredicts in the bucket scan - telling them
  apart needs hardware counters (VTune / WPR PMU). Upper bound if made 4x cheaper: ~12% of window scoring,
  ~7% of PerFileScoring, ~3.5% of a SEA-AD run.
- Ruled out by measurement (do not retry): rolling join (+4%), miss-filter bitmap (no gain), reading only the
  spectra calibration needs (95% coverage), producer/consumer scoring thread (cores already full).
- Conclusion: PerFileScoring has reached diminishing returns for code changes on this machine. The large remaining
  lever is parallelism on bigger machines: MACS2 (72 threads) ran SEA-AD in 2:09 with `--threads 72
  --parallel-files-scoring 4 --parallel-files-rescoring 8` vs 4:19 at defaults
  (`TODO-20261006_osprey_seaad_benchmark_port.md`).

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
- [x] SEA-AD 82-file end-to-end baseline at the port tip: **4 h 12 m (15,139.8 s) vs 510 min on 2026-08-12,
      -51%.** PerFileScoring 2 h 00 m (was 4 h 11 m, -52%), FirstPassFDR 29 m (1 h 16 m, -62%),
      PerFileRescoring 1 h 20 m (2 h 42 m, -50%), SecondPassFDR 23 m (~28 m). Peak private 46.5 GB (FirstPassFDR;
      was 52.1 GB), floor falling. PerFileScoring is still the largest stage (48%). (launched 2026-10-06 11:53, snapshot
      `D:\test\osprey-runs\_bin\port-490a4d3825-hooks`, run dir
      `D:\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-protein-compact-port490a4d-20261006_115333`);
      compare to 2026-08-12 (510 min; PerFileScoring 4 h 11 m)
- [x] Miss filter for m/z lookups - **abandoned (no gain).** Quiet 3-rep A/B, coelution sum over 3 files: baseline
      72.1/70.3/70.0 s, filter 71.1/71.8/71.3 s (overlapping); calibration ~1 s slower every rep. Data-identical.
      Scoped profile: XIC extraction 25.1% -> 27.3% of ScoreWindow; prefilter's HasTopNFragmentMatch 8.0% -> 4.4%,
      but index construction 2.5% -> 3.7% (bitmap build). Patch: `miss-filter-abandoned.patch`.
- [x] Calibration CPU breakdown (quiet scoped profile `sprofile-port-490a4d3825-hooks`, file 49): 11.8 s wall,
      283 s thread. `LoadWindowSerialRead` 147 s (52%: own 43 s, ReadRecords 9 s, ~95 s outside Osprey code =
      lock wait + kernel copy); ScoreResolvedCalibrationEntry 82 s (LowerBound 28, LibCosine 15, CWT 13);
      FindCalibrationCandidatesScanMajor 28 s; xcorr preprocess 9 s. 334 serialized window reads (2 passes x 167)
      at ~35 ms each = the calibration wall time: the read lock is the critical path.
- [x] Calibration read lock - **committed (pooled blocks).** Lock timing, file 49 (`rddbg.log`): 334 reads, 12.6 GB;
      hold 9.4 s total (median 24.4 ms) vs 7.3 s re-reading into a resident buffer -> page faults ~22% of the
      hold; waits 121 s thread; the copy itself runs ~1.7 GB/s from the file cache. `ArrayPool<byte>.Shared`
      blocks in LoadWindowSerialRead: quiet 3-rep A/B calibration sum 33.3/31.3/31.9 -> 28.3/27.7/28.3 s
      (-11%, ~1.2 s/file, non-overlapping); coelution unchanged; data-identical. Memory not yet checked (pool
      keeps up to ~30 x 64 MB) - check on the next SEA-AD run. Remaining levers: pass 2 loads whole windows at
      +/-0.54 min tolerance (read less), memory-mapped reads (no copy; needs a cold-HDD measurement).
      Do NOT turn serial reads off: cold HDD reads need them (parallel-files sweep, +21% without).
- [x] Read only the spectra calibration needs (Brendan's Skyline RT-pass idea) - **not worth building, measured.**
      Coverage, file 49 (`rcdbg.log`): pass 1 (+/-4.77 min) needs 100% of scans in-range, 91.9% used; pass 2
      (+/-0.57 min) 95.3% in-range (95-96% every window), 91.0% used. ~1,195 entries per window cover the whole
      gradient; even the ~4,500 pass-1 winners (~27/window) would cover ~93%. Skyline's pass pays because it uses a
      handful of standards.
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
- SEA-AD baseline done (see Tasks): 4 h 12 m, -51% vs 2026-08-12. Miss filter measured and abandoned; reverted.
- Two hypotheses about XIC extraction cost are now ruled out by measurement: traversal order (rolling join) and the
  cost of the miss path (bitmap). The ~25% share does not move with either; what dominates inside that loop is not
  known. Further XIC work should start from a finer measurement (line-level sampling or hardware counters), not
  another guess.
- Brendan's cross-machine SEA-AD race at defaults: 4:12 here (i9-14900K, 128 GB), 4:19 NUMA server (36 cores / 72
  threads, 512 GB), 5:00 other i9-14900 (64 GB). The NUMA session will try --parallel-files.
- Agreed order: calibration read lock -> median polish winner reuse (~1.4%) -> profile PerFileRescoring (32% of
  SEA-AD) -> XIC only after a line-level measurement.

### 2026-10-07
- Calibration breakdown recorded (Tasks). Read-lock timing -> pooled blocks committed (2c9afdefca). Calibration
  scan coverage measured (95%) -> reading less not worth it. XIC attribution: 65% is `MzBucketIndex.LowerBound`
  body (see "Where PerFileScoring profiling stands"). Survey of completed perf TODOs done (summary in the handoff).
- Session closed with PerFileScoring at diminishing returns. Open decision for Brendan: PR the two local commits
  (profiler hooks + pooled reads; memory check on the next SEA-AD run), then pick the next task - FirstPassFDR's
  listed opportunities or a fresh PerFileRescoring profile.

### 2026-10-07 (evening) - moved on to FirstPassFDR and PerFileRescoring
- Rebased onto the port tip e35b05852f (#4658 layout hoist); clean, 655/655. Local commits now
  9d5dce85e4 (hooks) + 197f2b3a7d (pooled reads). Snapshot `D:\test\osprey-runs\_bin\round3-e35b05852f`.
- Added `-ProfileTo <dtp>` to `OspreyDatasetRun.psm1` / `Run-SeaAd.ps1` (dotTrace sampling with the
  runner's exact environment). Harness + reports: `ai/.tmp/sessions/20261007-fdr/` (`Run-FdrAB.ps1`
  interleaved 12-file A/B linked from the 10-06 run; `stage6_phases.py`; `top.py`; `prof/`).
- **This box's D: is a SATA HDD** and 144 GB of scores parquet + 358 GB of spectra.bin do not fit in
  128 GB RAM: both stages are largely disk-bound at 82 files. FirstPassFDR reads 170 GB of parquet
  (972 s of its 1,742 s is serialized read time). Per-phase (82 files, 10-06 log): planning pass 2
  398 s (+61 GB: 44 GB is the cwt_candidates column, 542 MB/file), pass 1 341 s (+46 GB), training
  load 245 s (+40 GB for 300k rows) + SVM 57 s, pass 2 201 s, pass 0 134 s, planning pass 1 132 s.
- **Sidecar write buffer - measured, data-identical, UNCOMMITTED** (`FdrScoresSidecar.WriteInternal`
  FileStream 4 KB -> 1 MB). Profile: lanes blocked 229 s in OSFileStreamStrategy.Write (38k
  WriteFile calls per 155 MB sidecar). Warm 12-file A/B, 2 interleaved reps: stage 256/266 s ->
  220/222 s (-15%), pass 1 66-77 s -> 31-32 s; 36 outputs byte-identical. Also covers Stage 6's
  2nd-pass sidecars. Snapshot `sidecarbuf-wip1`.
- FirstPassFDR CPU (warm 12-file profile): `LoadPinFeaturesFromParquet` builds a double[21] for EVERY
  row (~830 MB/file) to keep ~3.6k training rows - a sparse load is byte-identical (ResolveFeatureRow
  only indexes by ParquetIndex); `LinearSvmClassifier.Train` 439 s thread (~57 s wall, fixed);
  per-file LOESS refit ~17 s CPU/file. Planning decodes every row's CWT list but only rows failing
  DetermineAction's Keep test use it (~6.3M of 353M, 1.8%). Not reading the column at all needs the
  CWT pick deferred to the rescoring node (it already reads the column when it writes the reconciled
  parquet) - a sidecar-contract change, Brendan's call.
- PerFileRescoring (82 files 4,825 s): rescore 1,897 s, write 1,773 s, next-file hydrate ~817 s,
  gap-fill 299 s. **Rescore is the spectra.bin read**: 4.37 GB/file read serially at ~200 MB/s (82 x
  4.37 GB ~ 1,790 s); 12-file profile has ~7,250 s of thread time waiting in LoadWindowSerialRead for
  ~1.7% of peaks. Next measurement: RT coverage of rescore targets per window (how much of each
  window the targets' scoring spans actually need) - decides whether reading less is worth building.

### 2026-10-08
- Committed the sidecar write buffer (0b879300ae; FirstPassFDR -15% at 12 files, byte-identical). Stellar
  (3.5 min) + Astral (22 min) regressions PASS on the branch. Rethought the sidecar files with Brendan ->
  stacked branch, see TODO-20261007_osprey_self_validating_artifacts.md.
- Open perf leads (not started): sparse training feature load (byte-identical, CPU/allocation only);
  decode CWT only for rows failing the Keep test in planning (or defer the CWT pick to the rescoring node -
  a sidecar-contract change, Brendan's call); measure rescore-target RT coverage per window before
  building any "read less spectra" path in Stage 6.
- Port moved to 9e2b516bcb (#4789 LF normalization): ran `/pw-configure-git`, rebased with `-X renormalize`
  (diff identical, no CRLF blobs); 655/655 + inspection 0/0. Brendan: NO PR until the port branch becomes
  master; then target master.
- `/code-review max` (9 findings). Fixed in 02c467d8cf: the pooled calibration blocks (ArrayPool.Shared kept
  a 32/64 MiB array per thread through the main search, ~2-3.5 GiB at 32 threads; power-of-two commit; rent
  outside the try) -> per-worker exact-size buffer scoped to the calibration loop
  (`LoadWindowSerialRead(int, ref byte[])`, Calibrator.CalibrationWorker), IOTest buffer-reuse pass,
  ProfilerHooks docs, sidecar comment. Dropped: IDE-dotCover takeover (unreproduced; the same bracket predates
  3a6e017b9e), try/finally around the bracket (90-line re-indent for a profiler edge case), shared buffer
  constant (style), decode double copy (pre-existing, unmeasured).
- Cost of the fix, interleaved A/B on 4 warm SEA-AD files (`ai/.tmp/sessions/20261008-validity/calibration-ab.log`,
  runs `seaad-4files-...ab{pool,worker}N`): RT calibration pooled 34.7s median (34.1-35.2, n=3 warm) vs
  worker buffer 36.6s (35.3-37.8, n=4), ~0.45 s/file. The shared pool's arrays outlive each FILE, so files
  2+ read into resident pages; that cross-file reuse was part of the -11%. Kept the bounded-memory version.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20261007_osprey_self_validating_artifacts.md` before starting work.
