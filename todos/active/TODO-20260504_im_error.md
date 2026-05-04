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

### Phase 1 - Accumulation [DONE]
- [x] Extended `IntensityAccumulator` with `MeanIonMobilityError` mirroring the Welford weighted-mean pattern from mass error
- [x] Wired `imsArray[iNext]` from `SpectrumFilterPair.cs:378` into accumulator
- [x] Target IM = midpoint of `MinIonMobilityValue` / `MaxIonMobilityValue`
- [x] Gated on non-FAIMS and IM filter present
- [x] Commit: `d83da9ecd`

### Phase 2 - Per-spectrum delivery [DONE]
- [x] Extended `ExtractedSpectrum` with `IonMobilityErrors` array (CCS arrays deferred — plumbed at peak detection instead, see below)
- [x] `SpectrumFilterPair.FilterSpectrumList` populates the array; converts mean delta to % IM error per target
- [x] Commit: `d83da9ecd`

### Phase 3 - Persistence [DONE for IM; CCS computation still pending]
- [x] `ChromCollector` accepts optional `hasIonMobilityErrors` / `hasCcsErrors`, with parallel `BlockedList<float>` storage
- [x] `TimeIntensities` carries `IonMobilityErrors` and `CcsErrors` immutable lists; `Truncate`, `Interpolate`, `InterpolateTime` preserve them
- [x] `SpectraChromDataProvider.ProcessExtractedSpectrum` plumbs IM error into `ChromCollector.AddPoint`
- [x] Cache format bumped v19 -> v20 (`CacheFormatVersion.Twenty`)
- [x] `ChromGroupHeaderInfo.FlagValues.has_ion_mobility_errors = 0x200` + `HasIonMobilityErrors` getter
- [x] `ChromTransition.FlagValues.missing_ion_mobility_errors = 0x08` + `MissingIonMobilityErrors` for partial-merge cases
- [x] `RawTimeIntensities` (protobuf) and `InterpolatedTimeIntensities` (legacy stream) round-trip IM errors
- [x] `ChromDataSet.GetFlagValues` sets the IM error flag
- [x] `ChromCacheBuilder` marks transitions missing IM errors
- [x] Per-peak `ChromPeak.IonMobilityError` + `CcsError` (scaled-short fields, struct 52 -> 56 bytes for v20, flag bits 0x0100 / 0x0200)
- [x] Per-peak `ChromPeak` constructor computes weighted-mean % IM error across the peak window
- [x] Per-peak `TransitionChromInfo.IonMobilityError` + `CcsError` (scaled-short fields, flags HasIonMobilityError / HasCcsError); ChangePeak propagates both
- [x] `ChromPeak.WithCcsError(double?)` helper for applying CCS after construction
- [x] Commits: `9dab2d0a2`, `1740ebb79`, `9e558710f`, `470ff66c5`
- [ ] **TODO: CCS computation at peak detection in `ChromCacheBuilder.WriteLoop`** (line ~1399, just before `ChromPeakSerializer().WriteItems`). Available there: `chromDataSet.NodeGroups[0].Item2` (TransitionGroupDocNode → PrecursorAdduct.AdductCharge), `chromDataSet.PrecursorMz`, `_currentFileInfo` (file/converter access). Pattern:
  ```
  centroidIm = targetIm * (1 + peak.IonMobilityError / 100)
  centroidCcs = converter.CCSFromIonMobility(centroidIm, mz, charge, ctx)
  ccsErrorPct = 100 * (centroidCcs - targetCcs) / targetCcs
  peak = peak.WithCcsError(ccsErrorPct)
  ```

### Phase 4 - Reporting [DONE for column surface; lacks CCS values until Phase 3 finishes]
- [x] `TransitionResult.IonMobilityErrorPercent` and `CcsErrorPercent` on the entity, formatted like `MassErrorPPM`
- [x] Column captions in `ColumnCaptions.resx` + Designer.cs (English; ja/zh-CHS handled by translators)
- [x] Tooltips in `ColumnToolTips.resx` + Designer.cs
- [x] Commit: `288a9ff32`

### Phase 5 - Tests [PENDING]
- [ ] Unit test: weighted-mean accumulator for IM/CCS error
- [ ] Functional test: extraction over a known IM dataset (drift time + 1/K0), verify % IM error and % CCS error in document grid
- [ ] Cache compatibility test: load a v19 cache, confirm IM-error columns are null, save as v20
- [ ] FAIMS CV check: ensure no spurious values when filter window is empty / FAIMS

### Phase 6 - Release notes [PENDING]
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
- **2026-05-04**: CCS computation pivoted from per-spectrum (in `SpectrumFilterPair`) to per-peak (in `ChromCacheBuilder` at peak detection). Reason: `PrecursorTextId` doesn't carry charge; pushing charge through to that layer would touch hundreds of call sites, while `TransitionGroupDocNode.PrecursorCharge` is naturally available at peak detection. Cache build still has the file present, so the user's "compute during extraction" constraint still holds.
- **2026-05-04**: `ChromCollector` and `TimeIntensities` retain (latent) `CcsErrors` array support for future graph panes — zero runtime cost when not allocated.

## Notes

- This is a long-standing request (skyline.ms #774, opened 2021-03-04 by Brian Pratt).
- Recent support inquiries (PanoramaWeb) suggest AutoQC tracking utility - call out in PR description.
- IMoffset branch (`wip/im-window-offset`) is conceptually related (IM filter window machinery) but does not overlap with the error-measurement work here.
