# pwiz: Fixed Bruker YEP/FID vendor peak picking ignoring the msLevel filter

## Branch Information
- **Branch**: `Skyline/work/20261126_compassxtract_yep_mslevel`
- **Base**: `master` (stacked on #5076 until it merged as 7e2e1f0495 on 2026-11-26)
- **Created**: 2026-11-26
- **Status**: In Progress
- **GitHub Issue**: [#5079](https://github.com/ProteoWizard/pwiz/issues/5079)
- **Module**: `pwiz`
- **PR**: [#5081](https://github.com/ProteoWizard/pwiz/pull/5081)

## Objective

`CompassXtractData.BuildSpectrumIndex` leaves `BrukerIndexEntry.MsLevel` at its default of 1
for YEP (`scan=N`) and FID (`file=...`) entries, and `SpectrumList_Bruker.BuildSpectrum`
decided vendor centroiding from that index value. So every YEP/FID spectrum was treated as MS1:
`peakPicking vendor msLevel=2-` returned MS2 as profile (then labeled centroid by the picker
without picking), and MS1-only vendor picking centroided MS2 too. cpp gates on each spectrum's
actual `MSMSStage` (`SpectrumList_Bruker.cpp:426`).

## Approach

Pass `msLevelsToCentroid` into `IBrukerData.FillSpectrum` instead of a precomputed bool, and let
each source test it against the spectrum's level: TDF / TSF / BAF from the index entry as before,
CompassXtract from `MSMSStage` read in the fill, as cpp does. Filling `MsLevel` at index time
instead (as the issue suggested) would mean a COM fetch per YEP spectrum, and opening every
`fid` analysis a second time for FID trees, at open.

## Tasks

- [x] Regression test: vendor centroiding by ms level on `Sample_1-A,1_01_985.d`
- [x] Fix: thread `msLevelsToCentroid` to the sources
- [x] /code-review medium: 2 test fixes applied (skip on no-vendor builds; require spectra at both levels that tell centroid from profile), 6 dropped
- [x] PR #5081 opened against #5076's branch

## Regression Test

- **Test name**: `Reader_Bruker_Sample_1_A_1_01_985` (new `AssertVendorCentroidingFollowsMsLevel` check)
- **Test project**: `pwiz/data/vendor_readers/Bruker/test/Bruker.Tests.csproj`
- **Fails on master**: yes - 102 mismatches (each of the 51 MS2 spectra wrong for both `[1]` and `[2-]`), on #5076's tip 888696f37e
- **Passes on fix**: yes - all 17 Bruker tests pass

The FID fixture (`100 fmol BSA`) is MS1 only, so it cannot show the bug.

## Progress Log

### 2026-11-26 - Session Start

Branched from #5076 (it will reach master first). Test written and seen failing, then the fix.
