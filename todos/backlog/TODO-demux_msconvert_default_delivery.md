# TODO-demux_msconvert_default_delivery.md

## Branch Information (Future)
- **Branch**: Not yet created - will be `Skyline/work/YYYYMMDD_demux_msconvert_defaults`
- **Module**: `pwiz`
- **Depends on**: the demux PR stack merged to master - #4805, #4814, #4806, #4813, #4815, #4817,
  #4827 (Poisson refit + makima / closed-form interpolation options), then #4818 (Osprey)
- **Objective**: msconvert and MSConvertGUI users get the best-known demultiplexer by default, with
  the legacy (C++-equivalent, plus the fixes) behaviour still available through arguments and the UI.

## Why (Brendan, 2026-10-12)

The stack ends with the improvements as opt-in options so that msconvert's output does not change
under review. Measured in `ai/todos/active/TODO-20261008_osprey_pwiz_demux.md` ("Status 2026-10-12
night") and `demux-integration.html`: makima + the Poisson-weighted refit give +3.1% precursors on
the Webinar 27 runs with Mike's library and +3.8% on a second set, at equal or lower entrapment FDP,
unchanged replicate CV, and less time than today's default. Osprey's `--demux auto` already uses
them (#4818). Everyone else running msconvert should get them too.

## Proposed defaults

- `poissonWeights=true` (Poisson-weighted NNLS refit, `NnlsSolver.PoissonWeightFloor = 100`)
- `interpolation=makima` (3+3 samples around the target, 3-point fallback on short runs)
- One spline, not two: today `spline` (MathNet, the C++ behaviour) and `natural3` (the same curve in
  closed form, within 1e-12 relative, every gold test passes with it, about a third faster) are both
  options. Make `spline` mean the closed form and remove the MathNet path.
- Fold in the `FindNearbySpectra` end-of-run stride fix (inherited from C++: the walk back from the
  earliest spectrum keeps the forward walk's stride count, so a run's last cycles can take another
  window's spectrum). Patch beside this file:
  `TODO-demux_msconvert_default_delivery-stepcount-fix.patch`. It moves the Eclipse NNLS fixture, so re-bless that gold.

## Legacy behaviour

- Reachable through arguments (`interpolation=spline poissonWeights=false`) and perhaps one switch
  (e.g. `legacy=true`) that sets every key to the C++ choice; decide which.
- "Legacy" keeps the fixes (#4805 NNLS limit and snapping, #4814 full search span); it is not
  bit-for-bit C++.
- The C++-parity gold tests pin the legacy settings explicitly; new gold values cover the new default.

## Work items

- [ ] Change the `SpectrumListDemux.Params` defaults and the msconvert filter defaults together
- [ ] MSConvertGUI Demultiplex panel: interpolation choice and a Poisson refit checkbox (beside the
      "Solve threads" box from #4813), defaults matching msconvert
- [ ] msconvert usage/help text for the demultiplex keys (the C# factory documents none today)
- [ ] Skyline: `MsDataFileImpl`'s demultiplex option follows the new defaults; re-baseline tests that
      consume msconvert demux output (`TestEncyclopeDiaSearchTutorialDraft` moved with #4805/#4814)
- [ ] Validate beyond Thermo before changing the default for everyone: the Poisson floor is a fixed
      100 intensity units, chosen on Orbitrap centroids (1,350 minimum); TOF data in ion counts sit
      much closer to it (SCIEX, Bruker, Waters staggered DIA if available). Also MSX (no real data
      here yet).
- [ ] Release notes / announcement: what changes for existing msconvert users, and how to get the
      old behaviour

## Open questions

- One `legacy=true` switch, or only the individual keys?
- Should Skyline's own demultiplexer (`pwiz_tools/Skyline/Model/Results/OverlapDemultiplexer.cs`) be
  retired in favour of `MsDataFileImpl`'s, now that it is the better one?
- Default the refit on for MSX as well as overlap, or overlap only until MSX data is tested?
