# Thermo reader decodes every spectrum's peaks for metadata requests; audit all pwiz-sharp readers for the same port gap

## Branch Information
- **Branch**: `Skyline/work/20261119_thermo_detail_level` (took over Brendan's #5062; stacked on #5057)
- **Base**: `Skyline/work/20261118_agilent_ims_fewer_copies` (#5057), then `master` once it merges
- **Created**: 2026-11-20
- **Status**: In Progress
- **GitHub Issue**: [#5059](https://github.com/ProteoWizard/pwiz/issues/5059)
- **Module**: `pwiz`
- **PR**: [#5062](https://github.com/ProteoWizard/pwiz/pull/5062)
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

- [x] `SpectrumList_Thermo`: override `GetSpectrum(int, DetailLevel)` (Brendan's, now on #5062)
- [x] Audit every pwiz-sharp reader and spectrum-list wrapper (see 2026-11-20 entries)
- [x] Extend the vendor test harness check from #5057 to every reader, every spectrum, strict precursors,
      polarity, and no peaks below full metadata
- [ ] Re-measure the Astral metadata pass after the fix.

## Regression Test

- **Test name**: `VendorReaderTestHarness.AssertLowerDetailLevelsAgree` (every vendor reference file);
  `SpectrumListDetailLevelTests.Wrappers_MetadataLevels_ReachInnerListWithoutPeaks` (Analysis.Tests);
  `SpectrumListUnifiTests.GetSpectrum_MetadataLevels_ReadNoPeaks` (UNIFI.Tests)
- **Test project**: pwiz-sharp vendor reader tests, Analysis.Tests, UNIFI.Tests
- **Fails on master**: yes - harness red on Agilent/Bruker/Mobilion/Sciex/Shimadzu/UIMF/Waters before the
  reader fixes; both unit tests red with the source fixes reverted (2026-11-20)
- **Passes on fix**: yes (2026-11-20, local)

## Progress Log

### 2026-11-20 - Session Start

Starting work on this issue. Branch created from origin/master in `C:\dev\pwiz-msconvert-pr` (the Sciex
wiff2-retry-latch work there was set aside as local WIP commit c71b338a18 on
`Skyline/work/20261005_wiff2_retry_latch`). Depends on #5057 for the harness check; decide whether to stack on
it or wait for it to merge.

### 2026-11-20 - Took over #5062; harness made strict

Decided: #5062 becomes the PR for all of #5059 (all vendors). The branch was already stacked on #5057.

Harness (`VendorReaderTestHarness.AssertLowerDetailLevelsAgree`, uncommitted):
* Every spectrum, not first/last 25. Measured cost before adding no-peaks: +4.7 s of check time over
  all vendor suites (4.5 s -> 9.2 s), not visible in per-project totals (~122 s).
* Precursors strict when a lower level returns any: new public `MSDataDiff.DescribePrecursors`,
  peak intensity stripped from both sides (MsDataFileImpl.GetPrecursors settles on the first
  non-empty level, field by field).
* Polarity must match when precursors are returned; otherwise lenient.
* No peaks below FullMetadata: defaultArrayLength 0 and no array points. Stricter than cpp for
  Waters (PEAKS_IN_SCAN at fast), Sciex (getDataSize reads data at fast) and Shimadzu.
* IndexRange fixtures: check the original list, not the full-data SpectrumListSimple.
* Deleted `SpectrumListThermoDetailLevelTests.cs` as redundant.

Red baseline (first failure per reference file): Agilent 10/17 failed, Bruker 5/16, Mobilion 2/2,
Sciex 6/12 (fast only), Shimadzu 2/2, UIMF 1/3, Waters 13/21; Thermo 15/15 and UNIFI 44/44 pass.
Populated arrays at instant come from the CWT peak-picker wrapper (Waters, Mobilion -centroid-cwt).

### 2026-11-20 - All vendors and wrappers fixed (uncommitted)

Every vendor harness suite green with the strict check (Agilent 17, Bruker 16, Mobilion 2, Sciex 12,
Shimadzu 2, Thermo 15, UIMF 3, UNIFI 45, Waters 21); Analysis.Tests 207, MsData.Tests 104.

Readers (rule everywhere: no peak count and no arrays below FullMetadata):
* Waters: new DetailLevel override; instant = type/msLevel (incl. MSe CE)/RT/drift/polarity/representation;
  fast adds scan stats + precursors; PEAKS_IN_SCAN count only from full metadata (cpp: fast).
  Lockmass methods now take DetailLevel (only caller is SpectrumList_LockmassRefiner).
* Agilent: non-IMS and drift paths return before the spectrum read below full metadata. Precursors are
  dropped there because charge/parent scan/all-ions window come from that read (cpp returns them half
  built); Skyline then escalates precursors to full metadata. Non-MS (DAD) returns type only.
* Bruker TSF/BAF/CompassXtract: return before reading peaks below full metadata (precursors from tables).
* Sciex: fast now stops where instant does (cpp reads data at fast via getDataSize).
* Shimadzu: below full metadata only GetSpectrumInfo (msLevel, type, polarity, RT); no SDK spectrum read,
  so no precursors there (cpp reads the spectrum object at every level).
* Mobilion, UIMF, UNIFI: overrides matching cpp's returns; counts from full metadata up.

Wrappers:
* PeakPicker: non-vendor path passes the level through; below full metadata returns after relabelling
  with no count; removed cpp's minDetailLevel_ escalation (it turned metadata reads into full-metadata
  reads for readers without a representation term below full metadata, e.g. Agilent). Skyline reads
  IsCentroided at full metadata.
* Pass-through + metadata transform: Filter, Sorter, TitleMaker, MzShift, IonMobility, LockmassRefiner.
* Peak-changing (no count below full, cpp PeakFilter rule): PeakFilter, ZeroSamplesFilter, MzWindow,
  Smoother via new SpectrumListWrapper.GetSpectrumWithoutPeakCount. MetadataFixer passes through.
* Left at full reads like cpp: ChargeStateCalculator, ChargeFromIsotope, PrecursorRefine, ScanSummer,
  Demux, MZRefiner (precursor shift needs full-metadata details). DiaUmpire already reads no peaks.
* Not changed: mzML/mzXML/mz5/MGF readers (their bool(false) path already skips binary decode).

Regression tests: harness `AssertLowerDetailLevelsAgree` (red baseline above); new
`SpectrumListDetailLevelTests.Wrappers_MetadataLevels_ReachInnerListWithoutPeaks` and
`SpectrumListUnifiTests.GetSpectrum_MetadataLevels_ReadNoPeaks`, both verified red with the source
changes reverted and green with them.
