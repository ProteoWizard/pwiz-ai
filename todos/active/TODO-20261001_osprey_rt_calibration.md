# Late-eluting peptides searched at the wrong RT where library RTs compress at the end of the gradient

## Branch Information
- **Branch**: `Skyline/work/20261001_osprey_rt_calibration`
- **Base**: `Skyline/work/20260612_net8_port` (5c90942d48)
- **Worktree**: `C:\Dev\pwiz-osprey-rtcal` (SCARFELL)
- **Created**: 2026-10-01
- **Status**: In Progress - reproducing on the Astral regression set against DIA-NN
- **GitHub Issue**: [#4759](https://github.com/ProteoWizard/pwiz/issues/4759)
- **Module**: `osprey`
- **PR**: (pending)

## Objective

On SCIEX ZT Scan data Osprey recovers only 16.9% of DIA-NN's precursors eluting after 10 min (66-72% elsewhere),
with the same data and library; 21.5% of everything Osprey misses. Osprey scores those precursors but predicts
their RT 0.24-0.97 min early, so its +/-0.5 min window misses the true peak. Two layers:
1. The Carafe libraries (starting model and fine-tuned) compress late library RTs (peptides observed 10.0-11.4 min
   all at library RT 9.70-9.86); DIA-NN's own predictor does not. Fine-tuning on Osprey's export reinforces it.
2. Osprey's LOESS calibration (572 confident first-pass peptides, none past library RT 10.07 / observed 10.36) and
   its fixed +/-0.5 min window cannot adapt where library RT stops discriminating; DIA-NN, on the same library,
   stays within ~0.3 min. `LoessRegression.ExtrapolateAbove` continues the last slope, so extrapolation is not
   the fault.

Full evidence and data paths: the issue, and `TODO-20260923_osprey_demux.md` ("What Osprey loses").

## Tasks

- [ ] Astral regression set (`osprey-testfiles-mzML-v2\astral`, `SkylineAI_spectral_library.tsv`, 1,567,424
      precursors, no decoys, no entrapment): DIA-NN 2.3.2 and Osprey (port-branch build) on the same library
- [ ] Osprey recall of DIA-NN's precursors by RT; library RT against observed RT; Osprey's calibration coverage
- [ ] Same on Stellar (DIA-NN needs `--mass-acc-cal 900 --no-ms1`; `stellar-libdecoy` has entrapment for FDP)
- [ ] Decide the fix: calibration refit after the first pass from all passing IDs, and/or an RT-dependent window
      (local residuals, local slope)
- [ ] Regression test pinning the behavior
- [ ] Re-measure on Astral, Stellar and ZT Scan; `regression.ps1 -Dataset All` (expected to move goldens if the
      fix changes the search; rebless with the measured gain)

## How the RT calibration works today (code map, 2026-10-01)

Paths under `pwiz_tools/Osprey/`.
- **Calibration funnel** (`Osprey.Tasks/Calibrator.cs`):
  - Pass 1 searches a wide window (0.2x the mzML RT range, ~+/-2.3 min here; 0.5x when library and run ranges
    differ; Cal:300-315).
  - It samples a 2D grid over library RT x m/z, 100K targets plus paired decoys, with a retry ladder x2 up to all
    targets (Cal:343-455, 1766-1923).
  - A point is kept with >= 3 spectra, >= 2 XICs, CWT correlation sum >= 0.5, LDA + TDC q <= 0.01 and reference
    S/N >= 5 (Cal:1075-1164, 1666-1706, 1979-2066).
  - No RT-range filter or top-N cap.
  - Pass 2 re-scores only at +/-pass-1 tolerance around pass 1's LOESS (Cal:581-639), so late peptides pass 1
    mis-predicts by > 0.5 min cannot re-enter.
- **LOESS** (`Osprey.Chromatography/LoessRegression.cs`, `RTCalibration.cs`):
  - Bandwidth 0.3 (k = ceil(0.3 n), about 172 neighbours at n = 572, one-sided at the run's end), degree 1.
  - Bisquare robustness with s = 6 x median|resid| (~0.3 min), which zero-weights a systematic late minority.
  - No monotonicity; `ExtrapolateAbove` continues the last slope.
  - `mad` in the JSON is the median of |residual|.
  - Window = clamp(3 x 1.4826 x mad, floor 0.5, 3.0) (RTC:411-468); 0.227 raw -> 0.5 here.
- **Search** (`Osprey.Scoring/ScoringPipeline.cs`:138-151, `PeakDataExtractor.cs`):
  - One global window for every precursor; the apex must lie within +/-tol of `Predict(libRT)` (PDE:282-285).
  - XICs are extracted over +/-2 tol; RT penalty sigma = max(5 x 1.4826 x mad, 0.1).
  - Stored CWT candidates come only from inside the gate.
  - **`RTCalibration.LocalTolerance` (RTC:344-348), a per-RT window from smoothed residuals, exists and nothing in
    production calls it.**
- **Stage 6 refit** (`Osprey.FDR/Reconciliation/CalibrationRefit.cs`):
  - Multi-file only.
  - Reconciles precursors already passing FDR, and gap-fill with the first-pass window.
  - Never re-runs the first-pass search; `second_pass_rt` is always null.
- **Docs:** `docs/04-calibration.md` and `05-rt-alignment.md` (partly stale: retry ladder, line numbers);
  `DIVERGENCES.md` U1 stale.
- **Tests:** `CalibrationTest.cs` (fit, window clamps, ladder, guards), `ReconciliationTest.cs` `TestRefit*`. None
  covers a gradient end without points, compressed library RTs, robust zero-weighting of a late cluster, or an
  RT-dependent window.

**Fix options:**
- **(A)** Use `LocalTolerance` in the first-pass search (window widens where residuals grow).
- **(B)** Make the fit follow the end: local robustness scale, or a narrower span at the edges.
- **(C)** Refit from all passing IDs and re-search (expensive).

Start with (A), measured on Astral, Stellar and ZT Scan against DIA-NN.

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: Osprey.Test
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

## Progress Log

### 2026-10-01 - Session Start

Issue filed from the ZT Scan Osprey-vs-DIA-NN analysis. Branch created from the port branch; starting with the
Astral regression set against DIA-NN, same library.

**Astral, same library (`C:\temp\osprey-runs\rtcal\astral\`; `Run-RegressionCompare.ps1`, `compare_rt.py` in the
session folder `ai/.tmp/sessions/20260927-054c052f`):**
- DIA-NN 2.3.2, library-based, own tuning, no MBR: 25 min; 137,110 / 136,035 / 134,243 precursors per run at 1%.
- Osprey, port-branch build 5c90942d48, as regression.ps1 runs Astral plus `--fdrbench`: 14 min; 108,438 / 106,743
  / 106,215 per run, 117,236 experiment.
- Osprey recovers 74.6% of DIA-NN's 149,643 experiment-level precursors (both at q <= 0.01). **Recall is flat along
  the gradient (70-77%); only the last bin, 21.8-23.6 min, drops to 62%, and it holds 2.1% of the misses.**
- The SkylineAI library is not compressed: library RT follows observed RT throughout.
- Calibration covers the run: about 2,900 points per file, library RT 2.0-23.7; residual SD 0.20; window +/-0.53-0.55.
- A mild version of the end effect remains. Osprey's apex is within 0.1 min of DIA-NN's in 95-96% of cases mid-run,
  86-88% at 18-22 min and 80-83% in the last bin, where it predicts about 0.1 min early.

So ZT Scan's late loss is mainly the Carafe libraries' compressed late RTs plus a global window that cannot absorb
it. On Astral the ~25% gap to DIA-NN is spread evenly along the gradient: not RT calibration.
