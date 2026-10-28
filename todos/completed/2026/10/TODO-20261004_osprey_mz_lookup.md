# TODO-20261004_osprey_mz_lookup.md

## Branch Information
- **Branch**: `Skyline/work/20261004_osprey_mz_lookup` (worktree `C:\proj\pwiz-mzlut`)
- **Base**: `Skyline/work/20260612_net8_port` (PR [#4619](https://github.com/ProteoWizard/pwiz/pull/4619)) at 12a0431bbe;
  independent of #4768 (different code)
- **Created**: 2026-10-04 (night session)
- **Status**: Completed (#4770 merged). The scan-major experiment branch stays local - see its section
- **Module**: `osprey`
- **PR**: [#4770](https://github.com/ProteoWizard/pwiz/pull/4770) (merged 2026-10-05)

## Objective

First-pass scoring (PerFileScoring) is dominated by fragment matching, not xcorr. Profile of Astral file 49
(`C:\proj\ai\.tmp\osprey-profile-20261004-114448.dtp`), scoring CPU 1,561 s thread-summed:
`FragmentMath.HasTopNFragmentMatch` 561 s own (the signal prefilter: top-6 fragments x every scan of the RT
range, >= 2 of 6 matched in 3 of 4 consecutive scans) and `ScoringMath.BinarySearchLowerBound` 554 s own (from
`TopFragmentExtractor.FindClosestPeakInWindow`, XIC extraction: top-6 fragments x every scan) = ~71%. Both spend
their time in a binary search for the first peak >= (fragment m/z - tolerance) over ~1-3K peaks.

Brendan (2026-10-04 ~21:08): PerFileScoring is the bigger prize; prioritize it after #4768 (no more Stage 6 work
beyond the window-major branch).

## Design (first cut, d451ecf16e)
- `MzBucketIndex` (Osprey.Core): one bucket per peak over [first, last] m/z; `_start[b]` = first peak with bucket
  >= b. Bucket function is monotone, so the lower bound lies in [_start[b], _start[b+1]] - scanned linearly
  (~1 peak). Exactly the binary search's result, incl. below-first, above-last, NaN. 4 bytes/peak, lives with
  the spectrum.
- `Spectrum.MzLowerBound` builds it on first use; assigning `Mzs` resets it; in-place m/z changes after the
  first lookup are disallowed (only the window provider calibrates in place, before returning).
- Used by the prefilter (`PeakDataExtractor` -> `HasTopNFragmentMatch(entry, Spectrum, tol)`) and XIC extraction
  (`FindClosestPeakInWindow(Spectrum, ...)`). Calibrator and TrainingEvidence still use the array forms.
- `TestMzBucketIndexMatchesBinarySearch`: index vs search on clustered/duplicate/single/all-equal and 20 random
  spectra at, around, below, above every peak and NaN; plus both entry points.

## Gates
- [x] Debug build, 648/648, inspection 0
- [x] Astral 3-file PerFileScoring A/B vs `_bin\coldreads-pr4767` (port-branch code), interleaved x3, warm -
  driver `ai/.tmp/sessions/20261004-night/Run-ScoringAB.ps1`, log `scoreab1.log`. All `.scores.parquet`
  byte-identical on every run.
  - wall: old 247.3 / 245.8 / 244.2 s, new (`_bin\mzlut-wip1`, d451ecf16e) 204.4 / 186.9 / 184.5 s
    -> median 245.8 -> 186.9 s (-24%)
  - coelution scoring (3-file sum): old 169.6 / 168.9 / 167.7 s, new 119.5 / 107.7 / 107.0 s (-36%)
  - calibration scoring (sum): old 46.7 / 48.1 / 48.3, new 54.3 / 51.5 / 50.2 (+3-6 s): calibration XIC
    extraction now builds indexes while its prefilter still binary-searched -> Calibrator switched (wip2)
- [x] Calibrator prefilter switched (02af04dc05), `_bin\mzlut-wip2`, log `scoreab2.log`: wall 165.9 / 166.7 s
  (vs old median 245.8 -> -32%), coelution sum 105.8 / 106.5 s, calibration scoring 33.0 / 32.7 s (old ~48),
  byte-identical. 648/648, inspection 0.
- [x] Profile of file 49 with wip2 (`ai/.tmp/sessions/20261004-night/mzlut-profile.log`): coelution window loop
  1,046 s thread-summed (was 1,561). Fragment matching still ~55%: HasTopNFragmentMatch 270 s own,
  ExtractFragmentXics 267 s own (lookup inlined) - now memory-bound (spectrum -> index -> start -> mzs, ~1,200
  spectra per window). Index build 17 s. Next tier: SG cosine 47, CWT convolve 46, xcorr preprocess 43, median
  polish ~70. Further gain needs a structural change (e.g. scan-major traversal so one spectrum stays hot across
  candidates) - a design discussion, not a night refactor.
- [x] regression.ps1 Stellar + Astral PASSED vs the golden masters on 02af04dc05 (`mzlut-*-regression.log`)
- [x] SEA-AD paired A/B, 10 files, new/old/new/old (`Run-MzlutPaired.ps1`, `mzlutpaired.log`, report
  `mzlutpaired-report.txt`, all in `ai/.tmp/sessions/20261004-night/`):
  - coelution per file: mean -31.4 s/file (-33.7%), sd 8.65, sem 2.74 s; every file -25% to -48%;
    new run-to-run sd 4.4 s
  - wall: new 891.3 / 865.3 s, old 1,299.9 (overlapped review benchmarks) / 1,176.0 s -> clean pair -26%
  - all `.scores.parquet` byte-identical across the 4 runs
- [x] /code-review max: index exact (0 mismatches in >100M differential queries). Fixing (sub-agent, 23:25):
  test reused entry Id 1 (top-6 memo made the parity check vacuous), stale-index guard (Source ref), fallback
  to binary search for empty/non-finite/unsorted input, bounded in-bucket scan, cheaper build, closure alloc in
  GetTop6FragmentMzs, edge-aligned test spectra, single implementation, Calibrator apex lookup. Deferred: a
  calibrated-stream test through StreamingWindowSpectraProvider; index memory (+4 B/peak in flight, ~0.35-0.7
  GB at 24-48 concurrent Astral windows - consider ushort/fewer buckets); hoisting the index out of the
  fragment loop (~3%). Dropped: d451ecf16e message is 11 lines (squash-merge discards it).

- [x] Review fixes 75d20c76d8 (sub-agent): 648/648, inspection 0; Astral 3-file byte-identical (`scoreab3.log`,
  wall 209.0 [cold after SEA-AD] / 166.4 s); Stellar + Astral regression tests PASSED vs golden masters
  (`mzfix-*-regression.log`)
- [x] Merged port branch (#4765) as 12971fe153: 652/652, inspection 0, Stellar regression test PASSED; pushed, PR #4770
- [x] Rebuilt onto the force-pushed port branch (f1300c7a06) 2026-10-05: 3 commits cherry-picked (7750333ab7,
  28d87b34b6, 722b5b1eaf), 652/652, inspection 0, force-pushed with lease; Brendan then merged the port branch
  (#4766, #4757) as cac0dd89e1
- [x] TeamCity Osprey Windows .NET, Osprey Linux .NET, native shims, Wine container: all green on cac0dd89e1
- [x] Perf/Regression #293 SUCCESS on 12971fe153 (the pre-rewrite head); not re-run on the rebuilt head -
  Brendan's call (later changes are rebase/merge churn)
- [x] Memory A/B, 2026-10-05 18:33-18:56: SEA-AD 3 files, PerFileScoring, base f1300c7a06 vs PR 722b5b1eaf,
  interleaved x2 via Run-SeaAd.ps1 (--memstamp), `ai/scripts/perfviz.py` on each run.log
  (`D:\test\osprey-runs\sea-ad\runs\memab-*`, since deleted; drivers/logs in `ai/.tmp/sessions/20261004-night/`):

  | | base 1 | base 2 | PR 1 | PR 2 |
  |---|---|---|---|---|
  | private (process) peak | 30.4 GB | 31.7 GB | 30.4 GB | 26.5 GB |
  | managed peak | 17.9 GB | 20.5 GB | 21.0 GB | 21.0 GB |
  | managed median (p50) | 10.2 GB | 10.3 GB | 11.4 GB | 10.9 GB |
  | sustained 60 s managed | 10.7 GB | 10.3 GB | 11.1 GB | 10.6 GB |
  | wall | 7:00 | 6:08 | 4:42 | 4:38 |

  Private peak (what decides whether a run fits) does not rise. Live managed memory +~0.35 GB sustained /
  +~0.9 GB median - the index's one int per peak for the concurrent windows' spectra, as designed (estimate was
  0.35-0.7 GB). Managed peak is noisy (base runs differ by 2.6 GB). The index lives exactly as long as its
  spectrum, so it adds no O(files) term; perfviz flags a rising floor equally in both arms over only 3 files.
  Caveat: --memstamp includes uncollected garbage (shape, not live bytes); OSPREY_LOG_MEMORY=1 post-GC probes not run.
  An earlier attempt on the Astral bed failed: `D:\test\osprey-runs\astral` had been deleted.

## Experiment: scan-major prefilter (nightlywork/osprey_scan_major_prefilter, worktree C:\proj\pwiz-scanmajor)
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

## Non-Thermo data assessment (2026-10-05 morning, read-only sub-agents)
- Bucket index (this branch): data-agnostic, exact for any input; no IM dependency; applies to timsTOF combined
  frames (Osprey sorts at load) and to demuxed ZT Scan. On timsTOF the per-peak IM test in the tolerance walk
  may dominate, and Skyline's open TODO (SpectrumFilterPair.cs:354) suggests native scan-major (IM) layout +
  per-scan m/z search instead of sorting - a possible later evolution, not a blocker.
- Scan-major (nightlywork): no ZT dependency after demux (fixed abutting windows, one spectrum per window per
  cycle); timsTOF OK only with combined frames. Re-measure on ZT (about 10x more windows, fewer candidates each)
  before relying on the gain. HOLD until the window model for timsTOF/ZT is decided.
- PR #4710 (Mike): ZT Scan demux is a standalone Osprey.DemuxTool writing mzML (validated with DIA-NN); Osprey
  --demux auto is staggered-only. Risk: raw ZT Scan with --demux off would be searched silently as 429 x 1.18 Th
  windows (true Q1 transmission ~10.5 Th FWHM) - suggest a scanning-quadrupole guard.
- timsTOF: Osprey reads uncombined (SpectrumFileReader.cs:102-107); first-cycle center-key window discovery
  likely breaks on diaPASEF (inferred) and explodes on diagonalPASEF. Skyline keys by (window group, m/z, width)
  and assigns precursors by 2D m/z x IM overlap (SpectrumFilter.cs:410-461, 1229-1244). Design question for
  later: a window-group abstraction with IM-aware candidate assignment.

### 2026-10-05 - Merged

PR #4770 merged into `Skyline/work/20260612_net8_port` as commit ff78a4c2bc. Shipped: `MzBucketIndex` (one bucket
per peak, exact binary-search lower bound in O(1) expected, binary-search fallback for empty/non-finite/unsorted
input), built lazily per `Spectrum` and rebuilt if `Mzs` is reassigned; used by the scoring prefilter, XIC
extraction and the calibration prefilter and apex lookups. PerFileScoring: Astral 3 files 245.8 -> 166 s wall
(-32%); SEA-AD 10 files coelution -33.7%/file, wall -26%; memory peak unchanged (A/B above). All outputs
data-identical. Merged on Perf/Regression #293 (pre-rewrite head) by Brendan's call.

Not in this PR: the scan-major prefilter / XIC / calibration passes (`nightlywork/osprey_scan_major_prefilter`,
`C:\proj\pwiz-scanmajor`, a further ~-16% Astral / -17% SEA-AD wall), held pending the timsTOF/ZT Scan window
model decision; the branch still sits on the pre-rewrite history and needs a rebase onto ff78a4c2bc before use.

## Ideas not yet tried
- Calibrator (calibration pass scoring ~13 s/Astral file) uses the same searches - switch to the Spectrum forms.
- The prefilter re-tests the same (fragment, scan) pairs for every candidate sharing fragments - none shared
  exactly, but per-spectrum work dominates; the index removes the log factor only.

## Progress Log

### 2026-10-04 (night)
- First cut written, tested, committed locally.
