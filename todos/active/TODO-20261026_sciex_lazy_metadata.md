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
- **PR**: (pending)

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

- [ ] Regression test first: 2,000 `GetMsLevel`-equivalent metadata calls on a wiff well under a second; open under a second
- [ ] Build `WiffSpectrum` from `GetMassSpectrumInfo`; defer `GetMassSpectrum` and centroiding to `XValues`/`YValues`
- [ ] Override `GetSpectrum(int, DetailLevel)` in `SpectrumList_Sciex` with the C++ gate (InstantMetadata returns before SDK peak work; FullData alone attaches arrays)
- [ ] Trim per-open setup in `WiffFile` constructor (lazy sample/experiment load as in C++)
- [ ] Audit other ported readers for the same `DetailLevel` collapse
- [ ] Verify reference mzML output unchanged (Sciex.Tests)
- [ ] Re-measure on `Hoofnagle_01_IDA.wiff` (open, 2,000 GetMsLevel plain/centroided)

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: Sciex.Tests (pwiz-sharp) and/or Skyline Test
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

## Progress Log

### 2026-10-26 - Session Start

Starting work on this issue. Branch created in `C:\dev\pwiz-net8` (C:\dev\pwiz is occupied by open PR #4851).
