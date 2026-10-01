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

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: Osprey.Test
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

## Progress Log

### 2026-10-01 - Session Start

Issue filed from the ZT Scan Osprey-vs-DIA-NN analysis. Branch created from the port branch; starting with the
Astral regression set against DIA-NN, same library.
