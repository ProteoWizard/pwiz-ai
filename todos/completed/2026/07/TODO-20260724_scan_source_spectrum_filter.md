# TODO-20260724_scan_source_spectrum_filter.md

## Branch Information
- **Branch**: `Skyline/work/20260724_scan_source_spectrum_filter` (deleted, local and remote)
- **Checkout**: `C:\Dev\ReaderBug`
- **Base**: `master`
- **Created**: 2026-07-24
- **Closed**: 2026-07-26
- **GitHub Issue**: [#4457](https://github.com/ProteoWizard/pwiz/issues/4457) - closed, no code change
- **Origin**: audit follow-up to PR #4301 (observed ion mobility)
- **Outcome**: **Closed without code change.** Investigation showed the reachable
  surface is far narrower than the issue claimed, and not worth the cost of the fix.

## Original objective

Make the raw-spectrum consumers honor `SpectrumClassFilter` so that reference/displayed
IM values are computed over the same spectrum population that filtered chromatogram
extraction uses.

## What the investigation established

The issue's premise was substantially wrong. Corrected analysis:

### The anchor spectrum is already filter-correct

The scan index handed to `ScanProvider` always comes from an extracted chromatogram
(`MsDataFileScanHelper.GetScanIndex()` -> `TimeIntensities.ScanIds`), and extraction only
emits points for spectra that passed filtering. So *which* retention times get examined and
*which* spectrum anchors each examination already honor the filter.

`IonMobilityFinder` inherits this: `ProcessMSLevel` builds `times`, `apexRTs` and the scan
index from `results.TryLoadChromatogram(i, nodePep, nodeGroup, ...)` for that specific
`nodeGroup`, which carries its own `SpectrumClassFilter` via `ChromatogramGroupId`. The
issue's claim that the finder "cannot honor the per-group filter even in principle" because
it is keyed per (peptide, charge, file) is incorrect - it honors it by construction.

### The only divergence is the same-RT look-ahead run

`ScanProvider.GetMsDataFileSpectraWithCommonRetentionTime()` (`ScanProvider.cs:249-261`)
appends every consecutive spectrum sharing the anchor's retention time and having an IM
value, checking nothing else. `EvaluateBestIonMobilityValue` (`IonMobilityFinder.cs:544`)
and the Full Scan graph then iterate that whole run.

Everything the issue lists separately - heatmap, mobilogram, `PlotY2D` peak metrics,
properties-pane TIC/injection time/IM range - collapses to this one run. There is no other
exposure.

That run has length > 1 only for **uncombined ion mobility** data. Combined (3-array) IM and
non-IM data yield a single spectrum, the anchor, which is already correct.

### How extraction treats a run (the reference semantics)

- The run representative is `allSpectra[0]` (`SpectraChromDataProvider.cs:1287`).
- The **global** `FullScan.SpectrumClassFilter` is evaluated only on the representative
  (`SpectraChromDataProvider.cs:365`). Pass admits the entire run including non-matching
  frames; fail skips the whole run. So the global filter is never applied per-frame, and any
  fix must not apply it per-frame either - that would make display *stricter* than extraction.
- The **per-group** filter *is* applied per-frame within the run
  (`SpectrumFilter.SrmSpectraFromMs1Scan` `:957-966`, `SpectrumFilter.Extract` `:1009-1016`).

### Why it was dropped

`MsDataFileImpl` requests 3-array combined IM by default (`MsDataFileImpl.cs:172`), and the
only override, `ForceUncombinedIonMobility`, is hardcoded `false` (`:165`) - a dev toggle used
by a couple of perf tests. `ScanProvider.cs:292` opens the file with the same setting the
import used (`_cachedFile?.HasCombinedIonMobility`), so display and extraction agree.

Reaching the divergence therefore requires all of: uncombined IM data (legacy documents, or a
reader that cannot supply 3-array), a **per-group** spectrum filter, spectra within a single
same-RT run that genuinely differ in a `SpectrumClass` column, and a user reading IM values off
that graph. Against that, the fix would have cost an `IScanProvider` contract change, a
filtered/unfiltered split through `MsDataFileScanHelper`, `[0]`/`First()` guards across
`GraphFullScan`, and a synthetic mzML fixture built solely to make the behavior observable.

Existing fixtures cannot reproduce it: `Ms1SpectrumFilterTest.zip` is FAIMS with CV -50/-70 at
distinct scan start times (runs of length 1), and the Waters HDMSe data in `IonMobilityTest`
has same-RT runs whose frames all share MS level, CE and isolation window (accepted or rejected
uniformly).

## Genuine wart left in place

Extraction records the run representative's scan id (`allSpectra[0]`) for every chromatogram
point - `SpectraChromDataProvider.cs:454`, `:460`, and via `ProcessSpectrumList(...)` at `:469`
-> `:630` - even when a per-group filter excluded that exact frame and the point came from
surviving frames. A per-group-filtered precursor's stored scan id can therefore point at a
spectrum its own filter rejects.

Harmless while runs are single-spectrum. This is the thing that would bite first if uncombined
ion mobility ever became common again, and is the place to start if this area is revisited.

## Files examined (no changes made)

- `pwiz_tools/Skyline/Model/Results/ScanProvider.cs`
- `pwiz_tools/Skyline/Model/Results/MsDataFileScanHelper.cs`
- `pwiz_tools/Skyline/Model/Results/IonMobilityFinder.cs`
- `pwiz_tools/Skyline/Model/Results/SpectraChromDataProvider.cs`
- `pwiz_tools/Skyline/Model/Results/SpectrumFilter.cs`, `SpectrumFilterPair.cs`
- `pwiz_tools/Skyline/Controls/Graphs/GraphFullScan.cs`, `GraphChromatogram.cs`
- `pwiz_tools/Shared/ProteowizardWrapper/MsDataFileImpl.cs`
