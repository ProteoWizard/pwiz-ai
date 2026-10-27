# TODO-20261022_wiff2_scantypes.md - wiff2 reader mishandled triple-quad scan types (ProductIon, Q1MI)

## Branch Information
- **Branch**: `Skyline/work/20261022_wiff2_scantypes` (checkout `C:\Dev\Quickee`)
- **Base**: `master`
- **Module**: `pwiz`
- **Created**: 2026-10-22
- **Status**: Completed
- **GitHub Issue**: (none)
- **PR**: [#4907](https://github.com/ProteoWizard/pwiz/pull/4907) (merged 2026-10-26)
- **Backport PR**: [#4912](https://github.com/ProteoWizard/pwiz/pull/4912) into `Skyline/skyline_26_1_1` (merged 2026-10-27)

## Objective
A SCIEX ACO-CE compound optimization .wiff2 (`ACO-CE-DKTGKN_2-332-Positive-2026-10-21-10-20-43.wiff2`,
found while fixing SeeMS in TODO-20261022_seems_wiff2.md) reports its experiments with triple-quad
scan types. The C# wiff2 reader only knew the ZenoTOF strings ("TOFMS", "TOFMSMS"), so:
- "ProductIon" MS2 scans came out as "MS1 spectrum" with no precursor or collision energy, and
  Skyline extracted nothing from them in PRM mode
- the "Q1MI" (Q1 multiple ion) point had m/z 0, an unbounded scan window, and came out empty when
  vendor centroiding was requested

## Fix (C# only; C++ backport expected later)
- `Wiff2Experiment.ExperimentTypeFor()` maps "ProductIon" -> Product and "Q1MI" -> MS;
  `HasIsolationInfo` uses the same mapping, so ProductIon scans get MSn, isolation target and CE
- Q1MI (`IsQ1MultipleIon`): point m/z = centre of each mass range's isolation window; scan window
  = span of the isolation windows when the selection window is unbounded; never sent through SDK
  centroiding or framing zeros; reported as centroid
- SeeMS draws a single-point profile spectrum as a stick (a line needs two points)

## Validation
- [x] Sciex.Tests `Reader_Sciex_ACO_CE_wiff2` with profile and -centroid reference mzMLs; red/green
      verified per step; all 11 Sciex tests pass
- [x] Skyline PRM (SkylineCmd, fresh .skyd): DKTGKN 2+ gets 8-point peaks on y3/y2/y1/b2; fragments
      above the 321.677 scan-window upper limit are correctly empty
- [x] `/code-review medium`: fixed scan-window fallback scope (Q1MI only), multi-ion span, framing
      zeros for Q1MI, shared Q1MI helper, stale SeeMS comment

## Progress Log

### 2026-10-23
Test data cleared for public use (already public via the support board). Code review findings
triaged and fixed; tests green. Committed 9755573c3d and opened PR #4907.

Copilot: SeeMS stick fallback now requires DefaultArrayLength == 1 (metadata-only Waters IMS
reports 0) - 654edbd1ee. Matt's review:
- Moved all Sciex test/Reference fixtures into Reader_Sciex_Test.data (no C++ tree left) - 93ed45a0dc
- Q1MI -> SIM: SIM targets from isolation-window centres, SICs via SDK GetMrmXic (matches the
  per-cycle points exactly); test runs default / simAsSpectra / simAsSpectra+peakPicking - 688d896142
- That broke Skyline PRM: any SIM chromatogram makes MsDataFileImpl.HasChromatogramData true and
  ChromCacheBuilder imports chromatograms only, dropping the MS2 spectra. wiff2 now omits SIM
  chromatograms under simAsSpectra (legacy .wiff unchanged) - 1b1f3b0870. Re-verified with
  SkylineCmd: identical peaks to pre-SIM (precursor + y3/y2/y1/b2)
- ProductIon kept as spectra (scanned Q3, CE ramp one experiment per step); replied on the PR
- Matt approved #4907 at 1b1f3b0870

C++ backport to `Skyline/skyline_26_1_1` (checkout `C:\Dev\Backport`, branch
`Skyline/work/20261023_wiff2_scantypes_26_1_1`): PR [#4912](https://github.com/ProteoWizard/pwiz/pull/4912).
WiffFile2.ipp / SpectrumList_ABI.cpp / ChromatogramList_ABI.cpp + Reader_ABI_Test configs and
references. Decoded C++ output matches the C# references (TIC ms-level array width aside, a
pre-existing C#/C++ difference); SkylineCmd PRM import identical to master. Code review fixes
in aac82ee46f. SpectrumList_ABI.cpp has mixed line endings - edit it byte-level, not with Edit.
Copilot on #4912: getSIC used the file's current sample (msSample, shared across samples and
moved by setSample) - fixed with msExperiment->SampleId there and in the pre-existing spectrum
and TIC requests. Master's C# reader is not affected: each Wiff2File binds one sample and every
Wiff2Experiment carries it.

### 2026-10-26 - Master merged

PR #4907 merged as commit 3f80263d84: ProductIon -> Product (MSn with CE), Q1MI -> SIM (SIM
chromatograms by default, single-point centroid SIM spectra with simAsSpectra, no wiff2 SIM
chromatograms then so Skyline reads the product ion spectra), SeeMS single-point stick, Sciex
fixtures moved into Reader_Sciex_Test.data. Nothing deferred. The TODO stays in active/ until the
26.1.1 backport #4912 merges; move it to completed/2026/10/ then.

### 2026-10-27 - Backport merged

PR #4912 merged into `Skyline/skyline_26_1_1` as commit a2e5c6cc: the C++ wiff2 reader gets the
same ProductIon -> Product and Q1MI -> SIM handling, omits wiff2 SIM chromatograms under
simAsSpectra, and takes each request's sample ID from the experiment's own sample (Copilot
finding); SeeMS single-point stick. Reported by Le. Nothing deferred.
