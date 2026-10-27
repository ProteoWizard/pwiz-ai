# SCIEX wiff reader in the .NET 10 port fetches and centroids peaks for every metadata request, and each open costs ~4 s

## Branch Information
- **Branch**: `Skyline/work/20261026_sciex_lazy_metadata`
- **Checkout**: `C:\dev\pwiz-net8`
- **Base**: `master`
- **Created**: 2026-10-26
- **Status**: In Progress
- **GitHub Issue**: [#4916](https://github.com/ProteoWizard/pwiz/issues/4916)
- **Module**: `pwiz`
- **Other labels**: `performance`
- **PR**: [#4921](https://github.com/ProteoWizard/pwiz/pull/4921)

## Objective

Since the .NET 10 port became master, reading a SCIEX wiff through Skyline is 2-4x slower end to end.
Every metadata request fetches (and, when asked, centroids) the spectrum's peaks, and every
`MsDataFileImpl` open costs about 4 s. The C++ reader did neither. Thermo, Waters, Bruker and mz5
are unaffected.

Nightly perf (BRENDANX-UW7, Sep 17 on 4.7.2 vs Oct 25 on .NET 10):
`zzzNativeVsMz5_AbDiaChromatogramPerformanceTest` 942 s -> 1,695 s, `AbIda` 375 s -> 769 s,
`DecoysMatchTest` 114 s -> 213 s.

On `Hoofnagle_01_IDA.wiff` (59,441 spectra): open 3.9-4.4 s; 2,000 `GetMsLevel` = 5.7 s plain,
46.3 s centroided (same as 2,000 `GetSpectrum`). Thermo raw: open 0.3 s, 2,000 GetMsLevel 0.04 s.

Root causes (C++ on `Skyline/skyline_26_1_1` vs the port):
- Detail levels collapsed: `ISpectrumList.GetSpectrum(int, DetailLevel)` (`pwiz/data/msdata/ISpectrumList.cs:96`)
  maps to `GetSpectrum(index, detailLevel >= FullData)`; `SpectrumList_Sciex` does not override it.
  C++ `SpectrumList_ABI::spectrum(index, DetailLevel, ...)` returned at `SpectrumList_ABI.cpp:231`
  for InstantMetadata before base-peak/TIC/array work.
- Peaks fetched eagerly: `SpectrumList_Sciex.GetSpectrumImpl` calls `exp.GetSpectrum(cycle, addZeros, centroid)`
  unconditionally; `WiffExperiment.GetSpectrum` calls `_exp.GetMassSpectrum` and centroids. The C++
  `SpectrumImpl` read only `GetMassSpectrumInfo` and fetched `GetMassSpectrum` in `getData`/`getDataSize`.
- Open is eager: `WiffFile` constructor loads the sample, enumerates all sample names, fetches every
  experiment; C++ did that lazily via `setSample`/`setExperiment`.

## Tasks

- [x] Regression test (deterministic peak-read counter instead of a timing threshold)
- [x] Build `WiffSpectrum` from `GetMassSpectrumInfo`; defer `GetMassSpectrum` and centroiding to `XValues`/`YValues`
- [x] Override `GetSpectrum(int, DetailLevel)` in `SpectrumList_Sciex` with the C++ gate (InstantMetadata returns before SDK peak work; FullData alone attaches arrays)
- [x] Pass DetailLevel through `SpectrumList_PeakPicker` / `IVendorCentroidingSpectrumList` (the centroided path)
- [x] Open cost: not the `WiffFile` ctor (0.05 s) - fixed by the lazy spectrum in CreateIndex's acceptZeroLengthSpectra branch; ctor left alone
- [x] Wiff2Spectrum lazy, matching cpp Spectrum2Impl
- [ ] Audit other ported readers for the same `DetailLevel` collapse - deferred, no measured cost
- [x] Verify reference mzML output unchanged (Sciex.Tests)
- [x] Re-measure on `Hoofnagle_01_IDA.wiff` (open, 2,000 InstantMetadata plain/centroided)
- [x] /code-review medium (9 findings: 3 fixed, 6 dropped with reasons - see log)
- [x] /code-review high (10 findings, triage only on second cycle - none a shipped-behavior defect;
      demux wrapper not forwarding DetailLevel is real but narrow and pre-existing, left out)
- [x] AbIda perf test: pass, 685 s; centroided wiff leg outside open+GetSpectrum 1.7 s (Oct nightly 411 s, Sep cpp 2.6 s), open 968 ms
- [x] Commit cfcd4469f7 + PR #4921

## Regression Test

- **Test name**: SpectrumListSciexDetailLevelTests.Sciex_InstantMetadata_ReadsNoPeaks (counts SDK peak reads; no timing)
- **Test project**: Sciex.Tests (pwiz/data/vendor_readers/Sciex/test)
- **Fails on master**: yes - verified by disabling the InstantMetadata gate (4,592 peak reads; red-check.log). The counter is new, so master itself cannot compile the test.
- **Passes on fix**: yes (sciex-tests-fix.log)

## Progress Log

### 2026-10-26 - Session Start

Starting work on this issue. Branch created in `C:\dev\pwiz-net8` (C:\dev\pwiz is occupied by open PR #4851).

Baseline on this machine (Hoofnagle_01_IDA.wiff, 59,441 spectra, default ReaderConfig; temporary
bench test, not committed): AbstractWiffFile.Open 0.05-0.28 s; Reader_Sciex.Read 9.8 s warm / 78 s
cold; 2,000 InstantMetadata reads 11-15 s plain, 126-131 s vendor-centroided (same as FullData).

Findings:
- The open cost is not the WiffFile constructor (0.05 s). Skyline's MsDataFileImpl defaults to
  acceptZeroLengthSpectra=true, whose CreateIndex branch asks `GetSpectrum(...).HasPrecursorInfo`
  for every Product cycle - on master a full GetMassSpectrum per MS2 cycle. cpp's getSpectrum there
  reads only GetMassSpectrumInfo. The lazy WiffSpectrum fixes this without touching the ctor.
- SpectrumList_PeakPicker (and every wrapper) collapsed DetailLevel to bool, so Skyline's centroided
  path turned InstantMetadata into a full vendor centroid. Ported cpp's DetailLevel overload
  (incl. minDetailLevel_ escalation) and added a DetailLevel overload to IVendorCentroidingSpectrumList
  (default method keeps the other five vendors unchanged).
- C++ wiff2 (Spectrum2Impl) was lazy too; Wiff2Spectrum now matches (precursor from a plain read only
  when nothing has been read; SpectrumList_Sciex reads the peaks first above InstantMetadata so an MS2
  spectrum still costs one SDK read).

Changes: SpectrumList_Sciex (DetailLevel override + cpp :231 gate), WiffFile.cs (WiffExperiment.GetSpectrum
reads info only; WiffSpectrum lazy), Wiff2File.cs (lazy Wiff2Spectrum), SpectrumList_PeakPicker,
IVendorCentroidingSpectrumList, Sciex.csproj (InternalsVisibleTo Sciex.Tests for a peak-read counter).
Regression test: Sciex.Tests SpectrumListSciexDetailLevelTests.Sciex_InstantMetadata_ReadsNoPeaks.

Verified (logs in C:\dev\pwiz\ai\.tmp\sessions\20261026-sciex4916\):
- Sciex.Tests 12/12 (all wiff + wiff2 reference mzMLs unchanged, wiff2 concurrency tests pass);
  Analysis.Tests 206/206.
- Red check: with the cpp :231 gate disabled the regression test fails (4,592 peak reads).
- Hoofnagle_01_IDA.wiff, same machine, master -> fix:
  - open in Skyline's config (acceptZeroLengthSpectra=true): 8.7-10.1 s -> 0.33-0.68 s
  - 2,000 InstantMetadata reads: 11-15 s -> 0.01-0.02 s plain; 126-131 s -> 0.02 s centroided
  - FullMetadata/FullData unchanged (11-13 s plain; centroided 91-107 s vs 108-132 s)
  - default config (BPC index) open: 9.8 s -> 7.4-7.6 s; still the per-experiment BPC fetch, same as
    cpp's createIndex, and not on Skyline's path

/code-review medium fixes: removed the peak picker's below-FullMetadata early return (it labelled
a full-metadata inner read's profile defaultArrayLength as centroid on the non-vendor path);
_minDetailLevel only rises; regression test also compares instant vs full metadata on the ACO-CE
wiff2. Dropped: unreadable cycles now get real metadata + empty arrays instead of the old
null-spectrum form (cpp threw; msconvert's probe drops them); SDK exceptions surface from wiff2
property getters to the same caller; CentroidMode stays true when GetPeakArray fails (only consumer
already marks centroid); FastMetadata still reads peaks (cpp getDataSize does too); wiff2 plain-read
reuse ignoring latched retry flags (only after SDK failures). Re-ran: Sciex.Tests 12/12,
Analysis.Tests 206/206.

Out of scope: auditing the other vendor readers' DetailLevel handling - none shows the cost (Thermo
GetMsLevel is 0.02 ms/spectrum per the issue).
