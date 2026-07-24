# TODO-20260724_scan_source_spectrum_filter.md

## Branch Information
- **Branch**: `Skyline/work/20260724_scan_source_spectrum_filter`
- **Checkout**: `C:\Dev\ReaderBug`
- **Base**: `master`
- **Created**: 2026-07-24
- **GitHub Issue**: [#4457](https://github.com/ProteoWizard/pwiz/issues/4457)
- **Origin**: audit follow-up to PR #4301 (observed ion mobility). Brian asked to broaden
  the finder-only issue to the shared root and fix it here.
- **Status**: Branch created (empty, at master tip). Not yet implemented.

## Objective

Make the raw-spectrum consumers honor the spectrum filter (`SpectrumClassFilter`) so that
reference/displayed IM values are computed over the same spectrum population that filtered
chromatogram extraction uses.

## Root cause (shared)

`ScanProvider.GetMsDataFileSpectraWithCommonRetentionTime()` and
`MsDataFileScanHelper.GetFilteredScans()` select spectra by scan index + IM range only; they
never apply `SpectrumClassFilter` (global `FullScan.SpectrumClassFilter` or per-group). Every
consumer reading spectra through this path inherits the blind spot. Extraction, by contrast,
honors it: `SpectraChromDataProvider.cs:135,367` applies `FullScan.SpectrumClassFilter.MakePredicate()`.

## Consumers to fix

1. **IonMobilityFinder** (`IonMobilityFinder.cs:544`) — iterates all `MsDataSpectra` at the RT;
   derives the library/target IM over the unfiltered population, so observed-vs-target % error
   (from #4301, filtered) can reflect a population mismatch rather than a real drift. Keyed per
   (peptide, charge, file), not per filter — so per-group filter needs a design decision.
2. **Full Scan graph display** (`GraphFullScan.cs`) — heatmap (`CreateIonMobilityHeatmap`),
   mobilogram (`CreateMobilogram`), and the observed-tooltip peak metrics (area/height/FWHM from
   `PlotY2D`) are all built from unfiltered spectra, while the dotted observed-IM line and IM/CCS
   values drawn on top read the filter-honoring stored `TransitionChromInfo.ObservedIonMobility`.
   Filter-honoring reference on an unfiltered backdrop.

Not affected (confirmed): `OnDemandFeatureCalculator` (threads per-group filter, cached chroms),
`SpectralLibraryExporter`/`BlibDb` (stored values, no raw re-scan).

## Proposed approach

Thread a `SpectrumClassFilter` predicate through the shared root (`ScanProvider` /
`MsDataFileScanHelper`) so both consumers filter consistently. Global filter is straightforward;
the per-group filter needs a decision for the finder (which is not per-group today).

## Open questions

- Full Scan **properties-pane** raw-file stats (data-point/mz counts, TIC, injection time,
  IM range) — may be intentionally describing the raw file. Decide per-field whether to filter.
- Per-group `SpectrumClassFilter` in the finder: honor it (finder becomes per-filter) or only the
  global filter for now?

## Test plan (to develop)

- Functional test with a non-empty `SpectrumClassFilter` that excludes a spectrum subset with a
  distinct IM: assert the finder's target IM and the Full Scan mobilogram both reflect the
  filtered population (currently they would not).
