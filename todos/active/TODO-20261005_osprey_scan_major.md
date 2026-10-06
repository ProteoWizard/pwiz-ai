# TODO-20261005_osprey_scan_major.md

## Branch Information
- **Branch**: `Skyline/work/20261005_osprey_scan_major` (worktree `C:\proj\pwiz-scanmajor`)
- **Base**: `Skyline/work/20260612_net8_port` (PR #4619), branched at ff78a4c2bc (#4770)
- **Created**: 2026-10-05 (from the night-session experiment branch `nightlywork/osprey_scan_major_prefilter`)
- **Status**: PR #4779 open; awaiting TeamCity Windows + Linux and Perf/Regression
- **Module**: `osprey`
- **PR**: [#4779](https://github.com/ProteoWizard/pwiz/pull/4779)
- **Follows**: `ai/todos/completed/TODO-20261004_osprey_mz_lookup.md` (#4770)

## Objective

After #4770's m/z bucket index, first-pass fragment matching is memory-bound: the prefilter and XIC extraction
loop candidate -> scan -> fragment, so successive lookups hit different spectra (~1,200 per window). Walk the
scans in the outer loop instead, so each spectrum stays hot in cache across all candidates whose RT range
covers it. Applied to the scoring prefilter, XIC extraction (blocks of candidates under a byte budget, original
order) and the calibration prefilter. Output must stay data-identical.

## Switches

Each pass has an environment switch, on by default; `=0` restores the candidate-major path and is logged:
`OSPREY_SCAN_MAJOR_PREFILTER`, `OSPREY_SCAN_MAJOR_XIC` (needs the prefilter on), `OSPREY_SCAN_MAJOR_CAL_PREFILTER`
(`OspreyEnvironment.cs`). Both paths give identical output, so the choice is performance only.

**Direction (Brendan, 2026-10-05): scan-major is what Skyline does, so it is the right shape for all data types.**
Skyline's chromatogram extraction is scan-major by construction - `SpectraChromDataProvider` streams spectra
in acquisition order and, per spectrum, `SpectrumFilter.FindFilterPairs` finds every precursor whose isolation
window covers it and `SpectrumFilterPair.FilterQ3SpectrumList` extracts all its transitions - across Thermo,
SCIEX, Agilent, Waters and 3D timsTOF. So the switches are a migration aid (A/B and bisection), not a
per-vendor selector; once trusted, the candidate-major `=0` arms can be retired, and future timsTOF/ZT work
should build on the scan-major sweep rather than the candidate-major loop.

## Future direction (Brendan, 2026-10-05)

- **Rolling join by RT**: yes - candidates are bucketed by start scan (counting sort; with a global RT tolerance
  this is predicted-RT order), enter an active list at their start scan and leave at their end scan or as soon
  as the prefilter passes. This is the RT-ordered rolling join Skyline's extraction relies on.
- **Convergence with Skyline**: when fixed isolation windows disappear (diagonalPASEF, raw scanning-quad data),
  the per-window join should become one RT-ordered sweep over all of a file's spectra, matching each spectrum to
  the candidates whose RT range AND precursor/IM range it covers - today's per-window join is that algorithm
  restricted to one window.
- **Possibly drop `.spectra.bin`**: Skyline needs no binary cache because it makes linear sweeps over the data
  file. The cache exists in Osprey largely for random access by window across passes (calibration sampling,
  first-pass scoring, Stage 6 re-score). Questions to measure before deciding: memory of a whole-file sweep
  (active candidates of every window at once, bounded by the RT tolerance), the pass count (calibration must
  precede scoring - at least 2 sweeps; can Stage 6 piggyback?), and cold-read cost on HDD for large cohorts
  (a linear sweep is the best-case read pattern, but mzML/vendor parse cost is what the cache avoids today).

## Rebase onto the rewritten port branch (2026-10-05)

The five commits were cherry-picked onto ff78a4c2bc (the #4770 squash), which already holds the three bucket-index
commits they were stacked on: 95e357610a, a3ecd020fe, 5060bb2089, ed02d2e970, b85e9b010f. The resulting delta is
identical to the experiment branch's (only hunk offsets differ). Old tip kept locally as `backup/scanmajor-pre-rebase`.

## Gates
- [x] Debug build, unit tests 654/654, inspection 0 (log `ai/.tmp/sessions/20261004-night/scanpr-debug.log`)
- [x] Stellar + Astral regression tests PASSED vs golden masters (`scanpr-*-regression.log`, 20:49)
- [x] Pushed `Skyline/work/20261005_osprey_scan_major`, PR #4779 opened 2026-10-05 ~20:52
- [ ] TeamCity Windows + Linux (auto on push); Perf/Regression (ask)

## Open items (from the two code reviews; for the PR discussion)
- Make the switches overridable (not `static readonly`) and add a `=0` SubsetPipelineTest leg - today no test
  or default run exercises the candidate-major fallbacks.
- Register the `=0` arms in `TODO-osprey_parity_path_retirement.md` (team convention for parity arms).
- The scan-major sweep scaffold is hand-written three times (prefilter, XIC, calibration); a shared helper would
  make adapting it to a future window model (timsTOF window groups, 3D spectra) cheaper.
- Stage 6 override / gap-fill passes still extract XICs candidate-major.
- Re-measure on ZT Scan data (about 10x more windows, fewer candidates each) before relying on the gain there.

## Evidence (experiment branch, 2026-10-05 night; commit SHAs are pre-rebase)
Stacked on 75d20c76d8; sub-agent, 2026-10-05 00:00-01:00. Status file `ai/.tmp/agent-scanmajor-status.md`.
- 244d6b5192 (wip1): `PeakDataExtractor.ComputePrefilterScanMajor` - per window, candidates sorted by start
  scan, outer loop over scans, inner over active candidates, same 4-slot ring per candidate; scan range via a
  shared `TryResolveScanRange`; TryExtract takes the verdict (`not_computed` -> its own loop, unchanged for
  overrides / short ranges). `OSPREY_SCAN_MAJOR_PREFILTER=0` restores candidate-major. Test
  `TestScanMajorPrefilterMatchesCandidateMajor` (400 candidates x 80 synthetic spectra). 649/649, insp 0.
- 906d542ed6 (wip2): top-6 fragment windows computed once per candidate into a flat array.
- Astral 3-file A/B (`scanmajor1.log`, old = `_bin\mzlut-wip3`): medians wall 167.0 -> 157.4 s (-5.7%),
  coelution 106.6 -> 96.9 s (-9.1%), all identical=True. wip2 vs wip1 (`scanmajor2.log`): coelution 96.8 ->
  95.0, wall 157.2 -> 154.3; wip2 parquets data-identical (Compare-ScoreParquets.py, 3/3 SAME) - its
  byte mismatch is only the osprey.version stamp (build after one more commit).
- Profile wip2 file 49 (`scanmajor-profile.log`): window loop 1,046 -> 934 s thread. Prefilter ~312 -> ~48 s,
  but ~60 s of cache misses moved into ExtractFragmentXics (267 -> 326 s own): the old order had the prefilter
  warm the candidate's spectra just before extraction. XIC extraction is now the top hotspot.

- d02ceac95f (scan-major XIC, sub-agent 01:05-01:38): ScoreWindow scores in blocks of 512 candidates in
  original order; each block's XICs for prefilter-passing candidates are extracted scan-major
  (`PeakDataExtractor.ExtractXicsScanMajor`) and handed to TryExtract, slot released as scored.
  `OSPREY_SCAN_MAJOR_XIC=0` restores. Test extended (bitwise XIC parity, block sizes 1/37/128/400). 649/649, insp 0.
  A/B `scanxic1.log` (old = scanmajor-wip2): medians wall 154.9 -> 140.4 s (-9.4%), coelution 95.6 -> 81.0 s
  (-15.3%); Compare-ScoreParquets 3/3 SAME (re-verified by parent). Peak working set 18.92 -> 18.46 GB.
  Profile (`scanxic-profile.log`): ScoreWindow 916 -> 716 s thread; top own: MzBucketIndex.LowerBound 138 s,
  HasTopNFragmentMatch 78 (calibration, still candidate-major), SG cosine 52, ExtractXicsScanMajor 46,
  xcorr preprocess 44, CWT convolve 42. Next idea: sort a block's fragment targets by m/z and merge-walk each
  spectrum once (no LowerBound calls).
- **Cumulative, Astral 3-file PerFileScoring medians: port branch -> full stack: wall 245.8 -> 140.4 s (-43%),
  coelution 168.9 -> 81.0 s (-52%).**
- [x] Stellar + Astral regression tests PASSED vs golden masters on d02ceac95f (`scanxic-*-regression.log`)
- [x] SEA-AD paired A/B, 10 files, port-branch exe vs full stack (`scanxicpaired.log`, `scanxicpaired-report.txt`):
  wall old 1,164.2 / 1,172.8 s, new 719.8 / 718.5 s (-38.5%); coelution per file mean -41.0 s (-47.5%), sd
  2.92, sem 0.92, every file -46.6..-48.5%; run-to-run sd old 0.76 / new 0.30 s. Compare-ScoreParquets
  (2-old vs 3-new): 10 of 10 data-identical (hash mismatch is only osprey.version).

- 4de3f23579 (scan-major calibration prefilter, sub-agent): `Calibrator.FindCalibrationCandidatesScanMajor`
  per window (entries' RT ranges by binary search + the exact original RT test; whole-window fallback on
  non-finite/unsorted RTs); old loop kept as `FindCalibrationCandidates`; `OSPREY_SCAN_MAJOR_CAL_PREFILTER=0`
  restores. Test `TestScanMajorCalibrationPrefilterMatchesEntryMajor`. 650/650, insp 0. A/B `scancal1.log`
  (old = scanxic-wip1): medians wall 140.9 -> 135.0 s, calibration scoring 32.5 -> 27.4 s (-16%), coelution
  unchanged; Compare-ScoreParquets 3/3 SAME; `.calibration.json` identical except "timestamp" (parent verified).
- **Cumulative Astral 3-file PerFileScoring: port branch -> 4de3f23579: wall 245.8 -> 135.0 s (-45%).**
- [x] Stellar + Astral regression tests PASSED vs golden masters on 4de3f23579 (04:01, `scancal-*-regression.log`)

- /code-review max on 244d6b5192..4de3f23579 (~04:30): no output-changing bug (22 verifiers; NaN/Inf/-0 RTs,
  ties, empty windows traced). Fixed by a sub-agent (04:35-04:58) in 7bec5ec504: XIC blocks by byte budget (wide-tolerance memory),
  one scan-range resolution per candidate, calibration entries in blocks, fragment-count/tie test coverage, one
  shared XIC recipe + null-fragment guard, log set switches, docs, expected-RT single source, Id-base constants.
  Left for the PR discussion: make the OSPREY_SCAN_MAJOR_* switches overridable + a =0 SubsetPipelineTest leg;
  scan-major for Stage 6 override passes; pooling scratch; =0 arms' timing caveat (906d542ed6 changed the
  candidate-major overload's per-call cost); a shared sweep helper (3 hand-written copies); shared test generator;
  register the =0 arms in TODO-osprey_parity_path_retirement.md.

- 7bec5ec504 review fixes: 650/650, insp 0; A/B `scanfix1.log` (old = scancal-wip1) medians wall 136.8 -> 135.5 s,
  coelution 81.4 -> 80.8, calibration 27.7 -> 27.3; Compare-ScoreParquets 3/3 SAME; calibration.json same
  excluding "timestamp".
- [x] Stellar + Astral regression tests PASSED vs golden masters on 7bec5ec504 (05:21, `scanfix-*-regression.log`)
- [x] Final SEA-AD paired A/B, port branch vs 7bec5ec504 (`finalpaired.log`, `finalpaired-report.txt`): wall old
  1,160.4 / 1,174.1 s, new 708.1 / 731.8 s (-38%); coelution -40.5 s/file (-47.1%), sem 1.04; run-to-run sd
  0.5-0.6 s; 10/10 data-identical (Compare-ScoreParquets, 2-old vs 3-new).

## Progress Log

### 2026-10-05
- Experiment results above (night session); rebased onto ff78a4c2bc as Skyline/work/20261005_osprey_scan_major.
