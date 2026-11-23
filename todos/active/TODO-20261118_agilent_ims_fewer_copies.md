# Remove array copies from the Agilent, Waters and Bruker IMS readers

## Branch Information
- **Branch**: `Skyline/work/20261118_agilent_ims_fewer_copies` (Quickee)
- **Base**: `master`
- **Created**: 2026-11-18
- **Status**: In Progress
- **Module**: `pwiz`
- **PR**: [#5057](https://github.com/ProteoWizard/pwiz/pull/5057)

## Objective

TestDriftTimePredictorTutorial import felt slow. Combined IMS spectra (m/z, intensity, ion
mobility) hold a million or more points, and the pwiz-sharp readers built each one in temporary
lists and then copied it into the spectrum's arrays - large-object-heap allocations, list
regrowth and gen-2 GCs. Write the points straight into the spectrum's arrays instead.

## Tasks

- [x] Agilent `BuildImsCombinedSpectrum`: append into the spectrum's arrays, capacity hinted
      from the previous spectrum of the same MS level
- [x] Waters combined path: same, hinted per function; non-combined path widens float to double
      in place, with an m/z/intensity length check
- [x] Bruker combined and diaPASEF whole-frame: arrays sized exactly from the peak count and
      filled in place; SortAndJitter now sorts in place (removed duplicate Read* gather loops)
- [x] pwiz Agilent (17), Waters (21), Bruker (16) reader tests pass
- [x] Skyline A/B vs master_clean, 3 reps alternating order, 168 runs all passed
- [x] /code-review high; fixed comments, dead code, SONAR per-bin call, length check
- [x] CodeInspection test
- [x] Goal widened to match or beat release 26.1.1 (C++ readers) on import, not just master
- [x] Detail levels: Agilent, Bruker BAF/TSF and Thermo decoded whole spectra to answer
      InstantMetadata requests; Agilent and Bruker IMS decoded whole frames; Waters combined
      spectra read every drift scan to count peaks. All now answer from the scan record, as C++ does
- [x] TestHarness DetailLevelChecks: metadata read below full metadata must agree with the full read
- [x] Bruker timsdata/tsfdata decode on 4 threads instead of 1
- [x] Skyline takes the reader's peak buffers with a used-length count (DetachData, SetBuffers)
      instead of copying to exact length
- [x] Spectrum.RetainedByList for lists that return the same instance on a re-read (MGF,
      SpectrumListSimple, demux cache); Skyline copies those instead of taking them
- [x] Bruker TSF profile: count condensed points, then fill exact-size spectrum arrays with m/z
      converted in place (was growing lists plus two copies; 2x slower than 26.1.1)
- [x] SkylineCmd import benchmark vs release 26.1.1 on 13 real-world sets: faster on 11, tied on 2
- [x] PR description updated with the benchmarks (posted 2026-11-22)

## Results (median change, branch vs master)

- Agilent: Spectrum Mill IMS -45%, Ramped IMS -43%, MeasuredDriftValuesPerfTest -24%,
  TestDriftTimePredictorTutorial -23% (346 s -> 266 s), AgilentIMSImportTest -18%
- Waters: WatersIMSImportTest -43%, WatersSonarPerfTest -33%, WatersLockmassPerfTest -11%
- Bruker: BrukerPrmPasefImportTest -16%, BrukerAllIonsbbCIDImportTest -11%,
  BrukerDiaPasefImportTest -9%
- Control (non-IMS Agilent, untouched code): -2%

## Results vs release 26.1.1 (SkylineCmd import, seconds, peak working set)

Release 26.1.1 vs branch, 2 reps alternating order; every run exited 0 with identical .skyd sizes.
Script: ai/.tmp/sessions/20261118-3e7798af/Run-ImportCompare.ps1 (results.csv beside it).

| Set | Release | Branch | Peak memory |
|---|---|---|---|
| thermo-dda | 10.5-11.2 | 11.0-11.1 | 4.9 -> 1.6 GB |
| thermo-mikeb | 38-44 | 30-31 | 5.1 -> 3.5 GB |
| thermo-faims | 97.5 | 25.5 | 8.0 -> 3.2 GB |
| thermo-coral | 3904-3994 | 2697-3159 | 34 -> 25.8 GB |
| thermo-labelfree | 109-120 | 82-84 | 14.3 -> 5.9 GB |
| sciex-zswath | 151-153 | 102-103 | 5.5 -> 1.4 GB |
| sciex-ztscan | 449-451 | 292-295 | 5.4 -> 1.8 GB |
| sciex-wiff2 | 511-637 | 302-303 | 2.9 -> 1.6 GB |
| sciex-stoyan | 93-100 | 63-64 | 13.3 -> 2.6 GB |
| waters-mse | 31 | 32 | 1.7-2.4 -> 0.3 GB |
| waters-slowmse | 18.5-18.9 | 11.6 | 4.6 -> 0.4 GB |
| bruker-tsf | 22.5 | 3.5-3.8 | 0.8 -> 0.3 GB |
| bruker-agnes | 54-55 | 32-34 (105-109 before the TSF fix) | 40 -> 0.5 GB |

TestDriftTimePredictorTutorial, 4 interleaved reps, median: release 270 s, master 335.5 s, branch 218 s.

## Notes

- The OS file cache favors whichever side runs second, so reps alternate the order; a single
  baseline-first pass showed -20%/+15% on unchanged controls.
- Rejected: using Agilent's stored ProfileTotalFrameMs (total frame spectrum). It equals the
  summed drift bins but drops the mobility dimension Skyline needs - too much work for now.
- Gaps: no pwiz reference test covers Bruker diaPASEF whole-frame output (Skyline
  BrukerDiaPasefImportTest does); no test turns on SortAndJitter.
- Benchmark scripts and results: ai/.tmp/sessions/20261118-3e7798af/ (ab3/readers-results-summary.md)
- Import benchmark gotchas: Skyline looks for document-named .blib/.irtdb beside the document,
  so each set's run folder needs them copied in; release 26.1.1 imports can peak near 40 GB, and
  the harness stops background jobs when memory runs low (happened twice; rerun by hand).
- sciex-wiff excluded from the benchmark.
- Profiling the TSF set: dotTrace sampling via `dottrace start --profiling-type=Sampling`
  (profile/agnes-branch.dtp in the session folder).

## Progress Log

### 2026-11-18 - Implemented, benchmarked, reviewed

- Committed 3d77134f66; CodeInspection passed; opened PR #5057.

### 2026-11-19 to 2026-11-22 - Matched release 26.1.1

- Found the main gap to the C++ readers: whole-spectrum decodes for metadata-only requests
  (9e55b2d105, db0e17dc53, 68338e304f, d3ac64a4aa), single-threaded Bruker frame decoding
  (fba1a20d12).
- Removed the peak array copy into Skyline (5d1bf4bbe9, 7abe5e25ca) and fixed the re-read case it
  exposed (318e608ab1, RetainedByList); fixed code review findings (bc7983111b).
- Benchmarked SkylineCmd import vs release 26.1.1 on 13 sets; the one loss (Bruker profile TSF,
  2x slower) traced with dotTrace to list growth and double copies in profile condensing, fixed in
  5309e7d3e2 (105 s -> 33 s; release 54 s). Bruker reader tests 17/17 including the TSF profile
  reference mzML.
- Updated the PR description with the full benchmark; all pushed.
- Side work: PR #5065 (TestIssues checkout) changed the DIA-Umpire full-fileset tests to compare
  scoring coefficients within 0.15 after showing they differ by machine (the commit that recorded
  them fails here); root cause not found.

## Remaining

- Review and merge PR #5057.
