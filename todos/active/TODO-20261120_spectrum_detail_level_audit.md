# Thermo reader decodes every spectrum's peaks for metadata requests; audit all pwiz-sharp readers for the same port gap

## Branch Information
- **Branch**: `Skyline/work/20261120_spectrum_detail_level_audit`
- **Base**: `master`
- **Created**: 2026-11-20
- **Status**: In Progress
- **GitHub Issue**: [#5059](https://github.com/ProteoWizard/pwiz/issues/5059)
- **Module**: `pwiz`
- **PR**: (pending)
- **Related**: #5057 (open, `Skyline/work/20261118_agilent_ims_fewer_copies`) adds `GetSpectrum(int, DetailLevel)`
  for Agilent and Bruker, fixes the Waters IMS peak count, and adds the vendor-harness detail-level check this
  issue extends; #4921 (Sciex override)
- **Prior work**: Brendan has a Thermo-only fix on his machine (worktree `D:\Users\brendanx\proj\pwiz-thermo`,
  branch `Skyline/work/20261119_thermo_detail_level`, local commit 16b43b04eb, not pushed). Metadata pass
  22 s -> 2.1 s warm. See TODO-20261119_osprey_direct_raw_read.md, 2026-11-19 entry. Ask him to push it
  before re-implementing the Thermo part.

## Objective

`SpectrumList_Thermo` does not override `GetSpectrum(int, DetailLevel)`, so every request below full data
falls to the base class (`ISpectrumList.cs`), which calls `GetSpectrum(index, getBinaryData: false)`. That path
still decodes the scan's peaks (`_raw.GetPeaks`, "Always retrieve the mass list ... even when getBinaryData is
false"), and reads scan statistics, the trailer, and for MS2 the precursor's MS1 peaks
(`SumIntensityInWindow`). C++ `SpectrumList_Thermo` returns early at instant metadata and reads no peaks there.
So `MsDataFileImpl.GetMsLevel`, `GetStartTime` and `GetPrecursors` cost a full decode of every spectrum.

Measured on a 6.1 GB Astral DIA `.raw` (163,594 spectra), warm: metadata pass 22 s / 32 core-s, whole file
touched; 9 files cold from spinning disk: 430-520 s per file for the metadata pass alone.

## Tasks

- [ ] `SpectrumList_Thermo`: override `GetSpectrum(int, DetailLevel)` and stop at the same detail levels as
      C++ (no `GetPeaks`, no scan statistics, no precursor-intensity lookup below the level where C++ reads
      them). Coordinate with Brendan's unpushed commit first.
- [ ] Audit every pwiz-sharp reader and spectrum-list wrapper: any `SpectrumList` that does not override
      `GetSpectrum(int, DetailLevel)`, or does peak work with `getBinaryData == false` that C++ skips.
      Not yet covered: Thermo, Shimadzu, UNIFI, Mobilion, UIMF, Waters non-IMS, and the remaining wrappers in
      `pwiz/analysis`. (Already covered: Sciex, PeakPicker, IgnoreCalibrationScans; Agilent, Bruker, Waters
      IMS in #5057.)
- [ ] Extend the vendor test harness check from #5057 (metadata below full metadata agrees with the
      full-metadata read) to every reader, with a check that no peak arrays are read below full data.
- [ ] Re-measure the Astral metadata pass after the fix.

## Regression Test

- **Test name**: (filled in once written) - vendor harness detail-level check, extended from #5057
- **Test project**: pwiz-sharp vendor reader tests (`VendorReaderTestHarness`)
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

## Progress Log

### 2026-11-20 - Session Start

Starting work on this issue. Branch created from origin/master in `C:\dev\pwiz-msconvert-pr` (the Sciex
wiff2-retry-latch work there was set aside as local WIP commit c71b338a18 on
`Skyline/work/20261005_wiff2_retry_latch`). Depends on #5057 for the harness check; decide whether to stack on
it or wait for it to merge.
