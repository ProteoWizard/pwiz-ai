# Use the ion mobility dimension in peak picking when no IM filter value is set

## Branch Information
- **Branch**: `Skyline/work/20261127_im_peak_picking`
- **Base**: `master`
- **Created**: 2026-11-27
- **Status**: In Progress
- **GitHub Issue**: [#5083](https://github.com/ProteoWizard/pwiz/issues/5083)
- **Module**: `skyline`
- **PR**: (pending)
- **Requester/Reporter**: John (Agilent, 2018 report with mouse liver digest data) - `Requested by John.`

## Objective

When IM data is present and a precursor has no IM filter value, chromatograms are
extracted by summing across the whole IM dimension, peak picking runs on those summed
traces, and the IM library editor's *Use Results* takes the IM value from whichever RT
peak was picked. Interference can pick the wrong peak, and re-importing with the learned
IM value then locks the error in. Treat IM as a search dimension during peak picking
instead of collapsing it.

## Tasks

- [ ] Map the current path: summed-IM extraction, peak picking, IM library *Use Results*
      (including the 24.1 isotope-distribution matching)
- [ ] Find IM candidates per RT peak (cheapest first: IM profile at candidate RT apex from
      raw spectra; then IM-band extraction; then 2D RT x IM apex detection)
- [ ] Add peak scoring features for IM agreement (isotope IM apex consistency; fragment IM
      offset from precursor IM) usable by default and mProphet models
- [ ] Record the IM value that goes with the chosen peak so *Use Results* can store it directly
- [ ] Support MS1-only IM data (isotope agreement only) as well as fragmentation data
- [ ] Measure import time and memory against summed-IM extraction; opt-in setting acceptable at first
- [ ] Locate John's 2018 data (PanoramaWeb Agilent transfer folder)

## Acceptance

- John's 2018 cases pick the right peak with the right IM value (20.5 min rather than
  19.5 min; the 48.8 min peak where M, M+1 and top fragment align in RT and IM)
- IM library filled by *Use Results* after one import matches one built from a clean,
  simple-mixture run, within tolerance
- No regressions when IM filtering is on

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: TestFunctional or TestPerf (depends on data size)
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

## Progress Log

### 2026-11-27 - Session Start

Starting work on this issue. Branch created in C:\Dev\PeakPickWithIM.
