# Carafe library RTs plateau at the end of the gradient, so Osprey loses late eluters

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

**Stellar, same library (`C:\temp\osprey-runs\rtcal\stellar\`):**
- DIA-NN with `--mass-acc-cal 900 --no-ms1`, no MBR: 12 min; 35,219 / 34,212 / 34,428 precursors per run.
  - With its own library and MBR in July it found 23.5k; with the SkylineAI library it is ahead of Osprey.
- Osprey: 4 min; 27,957 / 28,519 / 28,730 per run, 31,720 experiment.
- Osprey recovers 68.2% of DIA-NN's 40,358, flat at 65-71% along the gradient. The last bin, 22.0-23.8 min, is 57%
  (2.6% of misses).
- There the calibration (5,579 points) ends at observed 23.35 while the run reaches 23.78: Osprey predicts 0.35 min
  early, and apex agreement is 64% against about 86% mid-run (87% at best: unit resolution).
- DIA-NN writes `<library>.skyline.speclib` beside its library. The two it wrote into the regression data folder
  were moved to the `rtcal\<dataset>\diann` folders, and the driver now gives DIA-NN a copy of the library.

**Summary across the three sets:**
- **The RT edge costs 2-3% of the misses on the regression sets** (in their last 1.5-2 min) and 21.5% on ZT Scan
  with the Carafe library.
- The bulk of the same-library gap to DIA-NN (25% Astral, 32% Stellar, 31% ZT Scan before 10 min) is uniform in RT:
  a separate, sensitivity question.
- The RT fix should recover ZT Scan's late region and the last bins of Astral and Stellar without changing the
  middle of a run.

### 2026-10-01 - Per-RT window (Mike: try it, keep it if it works)

**Offline check first** (`simulate_local_window*.py`). From each run's `calibration.json` points and DIA-NN's IDs (library
RT = iRT), what fraction of the latest 7% of DIA-NN's precursors would fall inside each window:

| Window | Astral | Stellar | ZT Scan A1 / D1 / G1 | Mean width (min) |
|---|---|---|---|---|
| global (today) | 90-91% | 80-81% | 0.4 / 16 / 79% | 0.50-0.55 |
| existing `LocalTolerance` (mean of 5, x3) | 96% | 92-93% | 10.5 / 98 / 97% | 0.53-0.60 |
| median of nearest 5% (8-50) x 3 x 1.4826, clamped [global, 3.0] | 99.3-99.7% | 98.8-99.2% | 99.4 / 99.9 / 100% | 0.58-0.64 |

A1 is sensitive to k (8: 30%, 12: 99%, 20: 0.4%): it has no calibration points past observed 9.88 min.

**Implemented** as dc30890311 (local, not pushed):
- `RTCalibration.LocalSearchWindowHalfWidth`: the median |residual| of the k points around each calibration point in
  library-RT order (k = n/20 within 8-50), interpolated at the candidate's library RT; 3 x 1.4826 x that; clamped
  [global, `MaxRtTolerance`].
- `PeakDataExtractor` uses it, and scales the RT penalty sigma by the same ratio, only with `OSPREY_RT_LOCAL_WINDOW`
  (off by default; not in any validity key, so A/B arms use separate output directories). Stage 6 boundary
  overrides are unaffected.
- `TestLocalSearchWindowHalfWidth`.
- Gate: build, 639 tests, inspection 0/0.

**Inspection in a fresh worktree (tooling gap).** `Build-Osprey.ps1 -RunInspection` resolves the 15 pwiz-sharp and Shared
projects outside `Osprey.sln` (`CommonUtil`, `MsData`, `ProteowizardWrapper`, ...) through their
`bin/x64/Debug/net10.0` outputs, which a fresh worktree's build never makes (it builds them platform-neutral, to
`bin/Debug/net10.0`): 515 spurious "Cannot resolve symbol" errors.
- Worked around by copying each `bin/Debug/net10.0` to `bin/x64/Debug/net10.0`, plus the demux worktree's built
  ProteowizardWrapper (same source).
- Fixed in the script (pwiz-ai 8dbfb082): `-RunInspection` now builds `Osprey.Test.csproj` as x64 first. Cold tree:
  515 errors to 0. Root cause is #4725's AnyCPU pinning; noted on #4685.

**A/B running** (`Run-LocalWindowAB.ps1`, `C:\temp\osprey-runs\rtcal\`):
- ZT Scan off/on with this build;
- Stellar and Astral on, against their `osprey-base`.

**ZT Scan A/B** (same build, off/on; `C:\temp\osprey-runs\rtcal\ztscan\`):
- Per run 27,901 / 28,534 / 27,696 -> 29,781 / 29,175 / 29,734.
- Matched FDP 0.3 / 0.5 / 0.7%: 34,175 -> 34,964, 38,715 -> 41,170, 44,591 -> 46,025.
- Recall of DIA-NN past 10 min: 10.2% -> 43.0%. Late apex agreement A1 0.7 -> 62.0%, D1 12.8 -> 78.0%, G1 68.9 -> 93.2%.
- Remaining loss: the calibration curve is still 0.33-0.87 min early at the end, so the RT-deviation features penalize
  the right peaks. The fine-tuned library itself compresses late RTs (round 1 trained on 12 / 1 / 0 peptides at
  10.0-10.5 / 10.5-11.0 / 11+ min, against DIA-NN's 1,314 / 2,632 / 187), so round 2 of the CarafeSharp loop runs
  with the window on (`ztscan\carafesharp-r2\`).

**Stellar A/B** (`rtcal\stellar\osprey-base` vs `osprey-localwin`, DIA-NN Global.Q <= 0.01, 40,358 precursors):
- Per run 27,957 / 28,519 / 28,730 -> 28,934 / 29,564 / 29,834 (+3.5-3.8%); experiment 31,720 -> 32,722 (+3.2%).
- Recall of DIA-NN 68.2% -> 70.1%. Last three bins (18.4-23.8 min) 67.0 / 66.5 / 57.0% -> 75.4 / 76.9 / 79.9%; mid-run
  bins +0.4-0.8 points.
- Shared with DIA-NN +775, Osprey-only +227 (4,211 -> 4,438). No entrapment in this library; FDP check pending.

**Astral A/B** (`rtcal\astral\osprey-base` vs `osprey-localwin`, DIA-NN Global.Q <= 0.01, 149,643 precursors):
- Per run 108,438 / 106,743 / 106,215 -> 110,020 / 108,519 / 107,528 (+1.2-1.7%); experiment 117,236 -> 119,606 (+2.0%).
- Recall of DIA-NN 74.6% -> 75.9%. Last three bins (18.2-23.6 min) 74.3 / 74.6 / 62.0% -> 79.4 / 81.6 / 71.6%; the
  other bins +0.5-1.6 points.
- Shared with DIA-NN +1,970, Osprey-only +400 (5,623 -> 6,023). No entrapment in this library.

**Stellar entrapment A/B** (`rtcal\stellar-libdecoy\osprey-{base,localwin}`, the StellarLibDecoy regression library:
Carafe, library decoys, `_p_target` entrapment 1:1; `entrap_ab.py`):
- Experiment q <= 0.01: 30,963 -> 30,272 (-2.2%), entrapment FDP 0.55% -> 0.63%.
- Matched FDP 0.3 / 0.5%: 28,641 -> 27,426, 30,474 -> 28,953 (-4 to -5%).
- Every RT bin before 18 min loses 2-5% of its targets; the last bin gains 366 (FDP ~1.5% in both arms).

**Why the window costs mid-run IDs.** The decoys' features before the end of the gradient are identical in both arms
(`decoy_inflation.py`: the local window clamps to the global one there). Only late decoys change: they find peaks
farther away (median |rt deviation| 0.24 -> 0.37 min on Stellar Carafe, 0.09 -> 0.18 on ZT Scan) with higher co-elution.
The first-pass SVM is trained on all entries and re-weights: `sg_weighted_cosine` 1.573 -> 0.923 on Stellar Carafe;
on ZT Scan `abs_mass_accuracy_deviation_mean` -0.551 -> -0.161 and `abs_rt_deviation` -0.385 -> -0.534. The regression
libraries barely move (Stellar `sg_weighted_cosine` 1.491 -> 1.542), hence their clean gains.

**Decision (Mike, 2026-10-01): drop the per-RT window.** dc30890311 stays local, not pushed.

**Root cause of the late losses: Carafe library RTs saturate at the end of the gradient** (`library_rt_vs_observed.py`).
- Stellar Carafe library: no target past 20.08 min (p99.9 19.61) on a gradient to 23.8. The 2,578 precursors DIA-NN
  observes at 19.5-23.8 min (7.6% of its IDs) all have library RT 19.1-19.5. The SkylineAI regression library gives the
  same peptides 20.4 and 22.1 min.
- ZT Scan fine-tuned library: 9.70-9.86 for peptides observed at 10-11.4 min.
- Within the plateau the library RT carries no order, so no calibration or window can recover it. Osprey's calibration
  ends at the plateau (Stellar Carafe: observed 2.01-19.66 min; last bin predicted 2.66 min early, apex agreement with
  DIA-NN 0.0%).
- Not a hard cap in CarafeSharp: the RT decoder is linear (`ModelRtLstmCnn`), and RT is normalized by the run's last
  MS2 RT + 0.1 (`OspreyTrainingSet.GetRtMax`). It is learned: round 1 trained on 17,989 peptide forms, 13 past 10 min.

**Peak pick (Mike's question).** Mid-run the pick agrees with DIA-NN's apex 93-98% on ZT Scan, the same as Astral
(93-96%), so it is not the mid-run limit. Late, it inherits the bad prediction: the Astral pick model's RT term has scale
0.053, so a candidate 1-2 sigma off the predicted RT loses 3-6 rank units, more than perfect co-elution gives back.
Candidate dump for A1/D1 in `rtcal\ztscan\pickdump\` (`OSPREY_PICK_DUMP_CANDIDATES`), analysis `pick_dump_analysis.py`.

**Round 2 of the CarafeSharp loop** (`ztscan\carafesharp-r2\`, training search with the window on). RT training peptide
forms by RT, round 1 -> round 2 (DIA-NN finds 1,314 / 2,632 / 187 at 10-10.5 / 10.5-11 / 11+):
- < 9 min 16,143 -> 16,328; 9-9.5 1,102 -> 1,082; 9.5-10 731 -> 883; 10-10.5 12 -> 770; 10.5-11 1 -> 1,324; 11+ 0 -> 105.
- 20,492 peptide forms (17,989). Fine-tune and the 3-run search to follow.

**Peak pick, measured** (`rtcal\ztscan\pickdump\analysis.txt`; first-pass candidate dump, window on, A1 and D1; the
offline re-pick reproduces Osprey's pick for 100% of precursors). Share of DIA-NN's precursors whose chosen apex is
within 0.1 min of DIA-NN's:
- DIA-NN's peak is a candidate for 99.5-100% (every bin): the loss is in the choice, not detection.
- Mid-run the Astral pick model is the best of those tried, 95-98% (no RT term 92-97%, co-elution only 87-93%, legacy
  product 89-93%, Stellar model 90-95%).
- Last bin (past 10 min): Astral model 80.5% (D1) / 66.3% (A1); without its RT term 92.1% / 91.1%.
- So the pick is not the problem except where the predicted RT is wrong; fixing the library fixes the pick. No ZT
  Scan-specific pick model needed on this evidence.

**Which RT predictor tracks the end of the gradient?** (`koina_rt_test.py`; Koina KServe v2 as the maccoss/Carafe
fork's `KoinaClient` sends it; DIA-NN's IDs as truth; "cal err" = median |observed - isotonic calibration|, what a
search engine can recover from the predictor's order; outputs `rtcal\ztscan\koina_rt_test_D1*.txt`,
`rtcal\stellar\koina_rt_test_20.txt`)

| Predictor | ZT Scan D1 late Spearman | late / early cal err (min) | Stellar 20 late Spearman | late / early cal err |
|---|---|---|---|---|
| Chronologer_RT | 0.96 | 0.041 / 0.072 | 0.97 | 0.163 / 0.138 |
| DIA-NN predictor | 0.95 | 0.049 / 0.097 | - | - |
| Deeplc_hela_hf | 0.89 | 0.083 / 0.146 | 0.86 | 0.390 / 0.307 |
| Prosit_2019_irt | 0.83 | 0.104 / 0.134 | 0.91 | 0.305 / 0.262 |
| AlphaPeptDeep_rt_generic (= CarafeSharp start) | 0.69 | 0.205 / 0.160 | 0.59 | 0.681 / 0.225 |
| CarafeSharp fine-tuned, round 1 (D1 in-sample) | 0.60 | 0.152 / 0.063 | - | - |

- Koina's AlphaPeptDeep matches CarafeSharp's starting library exactly: the plateau is the generic model's.
- Chronologer has no plateau on either gradient and is the best predictor everywhere; out of the box it is within
  0.01 min of the in-sample fine-tuned model mid-run.

**Chronologer arm** (`ztscan\carafesharp-chrono\`, `Run-CarafeChrono.ps1`): round one's starting library with every RT
replaced by Chronologer_RT (`blib_set_koina_rt.py`, 2,636,987 peptidoforms), then stages 3, 4-5, 6 with the per-RT
window OFF. Queued behind round 2.
