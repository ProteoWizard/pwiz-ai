# TODO-20260504_im_error.md

## Branch Information
- **Branch**: `Skyline/work/20260504_im_error`
- **Base**: `master`
- **Created**: 2026-05-04
- **Status**: In Progress
- **GitHub Issue**: [#4183](https://github.com/ProteoWizard/pwiz/issues/4183)
- **Source Issue**: [skyline.ms #774](https://skyline.ms/home/issues/issues-details.view?issueId=774)
- **PR**: (pending)

## Objective

Add a precision/error sense to ion mobility filtering during chromatogram extraction, parallel to the existing mass-error machinery on the m/z dimension.

Per JohnF (in skyline.ms #774 comments): the intensity center of gravity of IM values across the IM extraction band, compared against the target IM, expressed as **% error in IM** and **% error in CCS**.

## Algorithm

Mirror the mass-error path in `SpectrumFilterPair` / `IntensityAccumulator`:

```
weighted mean of (im_peak - im_target), weighted by intensity, accumulated across the
IM extraction band; divide by im_target for % IM error.
```

Same for % CCS error, computed alongside in the same loop (per developer decision: CCS
conversion needs the mass spec file present, which is not safe to assume at report time).

## Scope

**In scope (this TODO):**
- Data path: extraction → cache → ChromPeak / TransitionChromInfo → Document Grid columns
- Cache format bump (v19 -> v20) to add per-peak IM error and CCS error
- Tests against representative IM data (drift time, 1/K0, FAIMS CV)

**Deferred (track separately, do not forget):**
- Graph panes parallel to `MassErrorHistogramGraphPane`,
  `MassErrorPeptideGraphPane`, `MassErrorReplicateGraphPane` (i.e.
  `IonMobilityErrorHistogramGraphPane` etc.)
- Any tutorial / wiki updates beyond release notes

## Implementation Plan

### Phase 1 - Accumulation
- [ ] Decide: extend `IntensityAccumulator` to track IM weighted mean alongside m/z, or add a parallel `IonMobilityErrorAccumulator`
- [ ] Add `MeanIonMobilityError` (and CCS counterpart) accumulation per the Welford pattern at `IntensityAccumulator.cs:48-56`
- [ ] Wire `imsArray[iNext]` (already present at `SpectrumFilterPair.cs:378`) into the new accumulator
- [ ] Resolve target IM: comes from the IM filter window center on the filter pair

### Phase 2 - Per-spectrum delivery
- [ ] Extend `ExtractedSpectrum` to carry parallel IM-error and CCS-error arrays alongside `MassErrors`
- [ ] Update `SpectrumFilterPair` extraction path (`SpectrumFilterPair.cs:348-393`) to populate them

### Phase 3 - Persistence
- [ ] Add `IonMobilityErrors` (and CCS errors) to `ChromCollector`, parallel to `MassErrors` (`ChromCollector.cs:40-50`)
- [ ] Add fields on `ChromPeak` (`DocNodeChromInfo.cs:329-334`) and `TransitionChromInfo` (`DocNodeChromInfo.cs:629-645`), scaled-short like mass error
- [ ] Bump cache format v19 -> v20; add migration path (zero/null for old caches)
- [ ] Update `TimeIntensities` and serialization

### Phase 4 - Reporting
- [ ] Surface `IonMobilityErrorPercent` on `TransitionResult` (`TransitionResult.cs:85` is the mass-error analog)
- [ ] Surface `CcsErrorPercent` on `TransitionResult`
- [ ] Add column captions and tooltips (`ColumnCaptions.Designer.cs`, `ColumnToolTips.Designer.cs`)

### Phase 5 - Tests
- [ ] Unit test: weighted-mean accumulator for IM/CCS error
- [ ] Functional test: extraction over a known IM dataset (drift time + 1/K0), verify % IM error and % CCS error in document grid
- [ ] Cache compatibility test: load a v19 cache, confirm IM-error columns are null, save as v20
- [ ] FAIMS CV check: ensure no spurious values when filter window is empty / FAIMS

### Phase 6 - Release notes
- [ ] Add to release notes

## Key Files (from initial code map)

**Extraction / accumulation:**
- `pwiz_tools/Skyline/Model/Results/SpectrumFilterPair.cs` (lines 348-393, 67-68, 228-230)
- `pwiz_tools/Skyline/Model/Results/IntensityAccumulator.cs` (lines 22-63)
- `pwiz_tools/Skyline/Model/Results/ExtractedSpectrum.cs` (line 52)

**Persistence:**
- `pwiz_tools/Skyline/Model/Results/ChromCollector.cs` (lines 40-50, 74-79, 167)
- `pwiz_tools/Skyline/Model/Results/DocNodeChromInfo.cs` (lines 329-334, 629-645)
- `pwiz_tools/Skyline/Model/Results/ChromatogramCache.cs` (cache format version)
- `pwiz_tools/Skyline/Model/Results/TimeIntensities.cs`

**Reporting:**
- `pwiz_tools/Skyline/Model/Databinding/Entities/TransitionResult.cs` (line 85)
- `pwiz_tools/Skyline/Model/Databinding/ColumnCaptions.Designer.cs`
- `pwiz_tools/Skyline/Model/Databinding/ColumnToolTips.Designer.cs`

**IM filtering context (read-only reference):**
- `pwiz_tools/Skyline/Model/IonMobility/TransitionIonMobilityFiltering.cs`
- `pwiz_tools/Skyline/Model/IonMobility/IonMobilityFinder.cs`

## Open Design Questions

1. Cache format bump v19 -> v20: confirm migration story (Pratt's call - usually we add fields nullable and bump version)
2. Storage size on `TransitionChromInfo`: short scaled by 10x (mass-error pattern) sufficient resolution for % IM error? Range and precision check needed.
3. Where does CCS conversion live during extraction? `IonMobilityFinder` and friends know how, but the extraction path currently doesn't compute CCS — confirm we have the calculator at the right layer.

## Decisions Log

- **2026-05-04**: Algorithm = intensity-weighted mean of `(im - im_target)` across extraction band, expressed as % error. Aligns with mass-error treatment, not RT-error treatment.
- **2026-05-04**: Compute % CCS error during extraction (not at report time), because CCS conversion requires the mass spec file to be present.
- **2026-05-04**: Defer graph panes — add to "deferred" section above; revisit after data path lands.

## Notes

- This is a long-standing request (skyline.ms #774, opened 2021-03-04 by Brian Pratt).
- Recent support inquiries (PanoramaWeb) suggest AutoQC tracking utility - call out in PR description.
- IMoffset branch (`wip/im-window-offset`) is conceptually related (IM filter window machinery) but does not overlap with the error-measurement work here.
