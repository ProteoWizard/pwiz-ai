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

## Results (median change, branch vs master)

- Agilent: Spectrum Mill IMS -45%, Ramped IMS -43%, MeasuredDriftValuesPerfTest -24%,
  TestDriftTimePredictorTutorial -23% (346 s -> 266 s), AgilentIMSImportTest -18%
- Waters: WatersIMSImportTest -43%, WatersSonarPerfTest -33%, WatersLockmassPerfTest -11%
- Bruker: BrukerPrmPasefImportTest -16%, BrukerAllIonsbbCIDImportTest -11%,
  BrukerDiaPasefImportTest -9%
- Control (non-IMS Agilent, untouched code): -2%

## Notes

- The OS file cache favors whichever side runs second, so reps alternate the order; a single
  baseline-first pass showed -20%/+15% on unchanged controls.
- Rejected: using Agilent's stored ProfileTotalFrameMs (total frame spectrum). It equals the
  summed drift bins but drops the mobility dimension Skyline needs - too much work for now.
- Gaps: no pwiz reference test covers Bruker diaPASEF whole-frame output (Skyline
  BrukerDiaPasefImportTest does); no test turns on SortAndJitter.
- Benchmark scripts and results: ai/.tmp/sessions/20261118-3e7798af/ (ab3/readers-results-summary.md)

## Progress Log

### 2026-11-18 - Implemented, benchmarked, reviewed

- Committed 3d77134f66; CodeInspection passed; opened PR #5057.
