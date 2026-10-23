# TODO-20261022_wiff2_scantypes.md - wiff2 reader mishandled triple-quad scan types (ProductIon, Q1MI)

## Branch Information
- **Branch**: `Skyline/work/20261022_wiff2_scantypes` (checkout `C:\Dev\Quickee`)
- **Base**: `master`
- **Module**: `pwiz`
- **Created**: 2026-10-22
- **Status**: In Progress
- **GitHub Issue**: (none)
- **PR**: (pending)

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
triaged and fixed; tests green.
