# Carafe library RTs plateau at the end of the gradient, so Osprey loses late eluters

## Branch Information
- **Branch**: `Skyline/work/20261001_osprey_missed_vs_diann` (local, not pushed)
- **Base**: `Skyline/work/20260923_carafesharp` (#4717, a7bf9f70be). Focus: why Osprey misses peptides DIA-NN finds,
  not the demux.
- **Worktree**: `C:\Dev\pwiz-carafesharp` (SCARFELL)
- **Superseded branch**: `Skyline/work/20261001_osprey_rt_calibration` (`C:\Dev\pwiz-osprey-rtcal`, from the port
  branch 5c90942d48) holds only the dropped per-RT window, dc30890311, local
- **Created**: 2026-10-01
- **Status**: In Progress - Chronologer as CarafeSharp's starting RT predictor
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

- [x] Astral and Stellar regression sets against DIA-NN; Osprey recall by RT; library RT against observed RT
- [x] Per-RT search window: tried and dropped (costs mid-run IDs through SVM re-weighting)
- [x] Root cause: AlphaPeptDeep's generic RT model plateaus at the end of the gradient; fine-tuning on a first pass
      that misses the late peptides keeps it
- [x] Peak pick measured: fine mid-run; late it follows the bad prediction
- [x] Chronologer weights and encoding committed (`models/chronologer-20220601193755`, d79aae9e3c)
- [ ] Port Chronologer to TorchSharp in CarafeSharp; parity with jchronologer's golden vectors and the 2.64M cached
      Koina predictions
- [ ] Chronologer as the starting-library RT predictor (option), AlphaPeptDeep MS2 unchanged
- [ ] Decide the final-library RT: fine-tuned AlphaPeptDeep on a good training set (round 2), Chronologer directly,
      or Chronologer fine-tuned
- [ ] Held-out RT error by RT bin in the CarafeSharp training report
- [ ] Re-measure on ZT Scan, Stellar and Astral against DIA-NN

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

**Round 2 library, window off** (`ztscan\carafesharp-r2\osprey_project_nowin\`, the production-relevant arm):
- Per run 31,950 / 31,709 / 32,742 (round 1: 27,901 / 28,534 / 27,696); experiment 37,314 (33,995).
- q <= 0.01: 37,269 targets, entrapment FDP 0.24% (round 1 33,951, 0.26%); matched FDP 0.3% 38,242 (34,175, +11.9%).
- Last RT bin (9.9-11.2 min) 4,580 (round 1 1,075), the same as with the window: the library, not the window, does it.
- Against DIA-NN out of the box (.wiff, its own library) at FDP 0.3%: -6.3% (round 1 -16.3%).
- Caveat: Osprey's `FDRBench-Input.tsv` is not complete at loose q (at q <= 1 it holds 9,145 / 1,884 entrapment against
  ~400k targets on a 1:1 library), so matched-FDP numbers mean something only up to q ~0.02 (FDP 0.3% here).
  `entrap_ab.py` now cuts at the first crossing of the FDP level.

**Chronologer start, window off: training set** (`ztscan\carafesharp-chrono\`): 22,981 RT training peptide forms;
18,102 / 887 / 1,769 / 165 at < 9 / 10-10.5 / 10.5-11 / 11+ min (round 2 with the window: 16,328 / 770 / 1,324 / 105).
A starting RT that tracks the end breaks the loop in one round without the window. Fine-tune and search running.

**Chronologer in CarafeSharp** (`Skyline/work/20261001_osprey_missed_vs_diann`, local, not pushed):
- d79aae9e3c: weights + encoding JSON committed (`models/chronologer-20220601193755`).
- c3998d2127: TorchSharp port (`ModelChronologer`, `ChronologerEncoding`, `ChronologerFiles`, `ChronologerModel`;
  iRT fit moved to `IrtKit`). Matches jchronologer's golden cases to 2e-5.
- 492dc3dde5: `-rt_model alphapeptdeep|chronologer` for library prediction (`IRtPredictor`,
  `ChronologerRtPredictor` with an AlphaPeptDeep fallback; library RT iRT; training only with `-tf ms2`).
- Gate: build, 78 tests passed (8 Carafe parity tests inconclusive: `carafesharp-testfiles-v1.zip` not on SCARFELL),
  inspection 0/0.
- Bulk parity: 20,000-peptide subset of the ZT Scan training DB (`ztscan\chronologer-native-check\`): native against
  Koina's Chronologer on 17,937 peptidoforms, max |difference| 7.6e-6 HI, Pearson 1.00000000.
- Next: fine-tuning Chronologer (per-source normalization infrastructure, frozen BatchNorm, HI -> normalized-RT head),
  the RT model type in the saved model, then the default by measurement on G1.

**Chronologer fine-tuning** (625d57d2ba, 0f10709372; local, not pushed):
- `-rt_model chronologer` in training fine-tunes Chronologer: the least-squares line from its hydrophobic index to the
  training peptides' normalized RT is folded into the output layer, then every weight trains with the RT L1 loss; the
  BatchNorm running statistics stay frozen (`ModelChronologer.FreezeBatchNorm`, eval mode inside training).
- Batches mix peptide lengths (0f10709372): Chronologer pads every peptide to 52 positions and its output layer weighs
  each position, so single-length batches pulled it a different way per length.
- Saved `rt.safetensors` carries `carafesharp.rt_model = chronologer`, `carafesharp.rt_scale = normalized_rt`;
  library prediction uses a fine-tuned Chronologer whatever `-rt_model` says, with rt_max like AlphaPeptDeep.
- Gate: 79 tests passed (8 Carafe parity tests inconclusive, no test data), inspection 0/0.
- CLI smoke test on the Chronologer-start ZT Scan export (22,981 forms, held-out 1,000; `ztscan\chronologer-finetune-smoke\`):

| RT model | R2 | median error (normalized) | final test L1 |
|---|---|---|---|
| Chronologer, linear calibration only | 0.9916 | 0.00849 | - |
| Chronologer fine-tuned, single-length batches | 0.9981 | 0.00483 | 0.00916 |
| Chronologer fine-tuned, mixed-length batches | 0.9982 | 0.00473 | 0.00628 |
| AlphaPeptDeep fine-tuned, round 2 (AlphaPeptDeep-start export) | 0.9954 | 0.00593 | 0.01194 |

  One-epoch test-loss spikes remain at the peak learning rate (1e-4); a lower rate for Chronologer is a tuning option.

**Comparison matrix** (`Run-Matrix.ps1`, `C:\temp\osprey-runs\matrix\<dataset>-<rtmodel>`, progress `matrix\matrix.log`):
Stellar, Astral, ZT Scan, each AlphaPeptDeep then Chronologer, the whole loop (FASTAs, starting library, single-file
training search with the export, fine-tune + final library, 3-file search); CarafeSharp 0f10709, Osprey 492dc3d,
window off. Compare per dataset: the single-file search with the starting model against the 3-file search with the
fine-tuned models (per-run counts; matched entrapment FDP for the 3-file searches up to q ~0.02; recall of DIA-NN by
RT), and AlphaPeptDeep against Chronologer, plus each library's RT error by RT bin on a held-out run.

**Chronologer start, one round, window off** (`ztscan\carafesharp-chrono\`, older build 27a0ba6; Koina-built starting
library, equal to native; RT fine-tuned is AlphaPeptDeep): per run 32,203 / 32,587 / 33,084, experiment 38,194;
q <= 0.01 38,137 targets at entrapment FDP 0.30%; matched FDP 0.3% 38,182 (round 2 window off: 38,242; round 1:
34,175); last RT bin 4,463 (round 2 4,381, round 1 865). Fine-tuned AlphaPeptDeep RT R2 0.9969, median 0.00581.
One round from a Chronologer start equals two rounds from AlphaPeptDeep's.

**Matrix, Stellar** (`matrix\stellar-{alphapeptdeep,chronologer}`, `matrix\stellar-report.txt`, `matrix_report.py`;
about 33 min per arm). DIA-NN reference: the regression-library search, 40,358 precursors.

| | AlphaPeptDeep | Chronologer |
|---|---|---|
| single-file search, starting library (run 21) | 22,842 | 27,510 (+20.4%) |
| 3-file search, fine-tuned, per run | 27,435 / 27,850 / 27,963 | 31,141 / 31,667 / 31,708 |
| 3-file experiment precursors / peptides / proteins | 31,197 / 28,426 / 4,201 | 35,578 / 32,318 / 4,515 |
| entrapment FDP at q <= 0.01 | 0.56% | 0.52% |
| matched FDP 0.3% / 0.5% | 28,946 / 30,514 | 32,528 / 35,250 |
| RT R2 / median, starting model (held-out split) | 0.8747 / 0.0507 | 0.9976 / 0.0062 |
| RT R2 / median, fine-tuned | 0.9974 / 0.0050 | 0.9989 / 0.0038 |

- Recall of DIA-NN in the last two RT bins (18.4-21.1, 21.1-23.8 min): AlphaPeptDeep single 28.7% / 0.2%, 3-file
  44.1% / 0.6%; Chronologer single 67.0% / 72.5%, 3-file 79.7% / 82.8%. Mid-run bins +1-3 points for Chronologer.
- Library RT error on held-out run 20 (median |obs - isotonic|) in those bins: AlphaPeptDeep fine-tuned 0.40 / 0.83 min,
  Chronologer fine-tuned 0.12 / 0.14 min; mid-run both 0.07-0.10.
- One round cannot teach AlphaPeptDeep the end of a 24-min gradient: its training search finds 0.2% of the last bin.

**Matrix, Astral** (`matrix\astral-*`, `matrix\astral-report.txt`; about 2 h 20 min per arm). DIA-NN reference: the
regression-library search, 149,643 precursors.

| | AlphaPeptDeep | Chronologer |
|---|---|---|
| single-file search, starting library (run 55) | 85,917 | 99,469 (+15.8%) |
| 3-file search, fine-tuned, per run | 94,530 / 94,453 / 92,673 | 103,444 / 103,809 / 102,153 |
| 3-file experiment precursors / peptides / proteins | 103,538 / 91,472 / 7,918 | 114,764 / 101,150 / 7,948 |
| entrapment FDP at q <= 0.01 | 0.52% | 0.41% |
| matched FDP 0.3% / 0.5% | 95,147 / 103,068 | 109,446 / 116,822 |
| RT R2 / median, starting model (held-out split) | 0.8586 / 0.0555 | 0.9973 / 0.0064 |
| RT R2 / median, fine-tuned | 0.9978 / 0.0049 | 0.9989 / 0.0040 |

- Recall of DIA-NN, last two RT bins (18.2-20.9, 20.9-23.6 min): AlphaPeptDeep single 30.7% / 0.2%, 3-file 50.5% / 0.4%;
  Chronologer single 69.9% / 64.8%, 3-file 76.9% / 71.9%. Mid-run bins +3-4 points for Chronologer.
- Library RT error on held-out run 49 in those bins: AlphaPeptDeep fine-tuned 0.42 / 0.99 min, Chronologer fine-tuned
  0.14 / 0.15 min; mid-run Chronologer 0.07-0.12 against 0.08-0.14.

**Matrix, ZT Scan** (`matrix\ztscan-*`, `matrix\ztscan-report.txt`; about 3 h per arm; training run D1, held-out A1).
DIA-NN reference: DIA-NN's own library on our demux files (`full_joint_diannlib`), 52,684 precursors, RT 1.5-11.2 min.

| | AlphaPeptDeep | Chronologer |
|---|---|---|
| single-file search, starting library (D1) | 20,423 | 26,518 (+29.8%) |
| 3-file search, fine-tuned, per run (A1 / D1 / G1) | 29,967 / 29,144 / 29,769 | 34,338 / 34,402 / 34,890 |
| 3-file experiment precursors / peptides / proteins | 34,569 / 29,829 / 3,670 | 40,404 / 34,754 / 3,893 |
| entrapment FDP at q <= 0.01 | 0.27% | 0.26% |
| matched FDP 0.3% | 34,814 | 40,780 (+17.1%) |
| matched FDP 0.5% | not reached by q 0.015 (0.37%) | not reached (0.42%) |
| RT R2 / median, starting model (held-out split) | 0.9172 / 0.0353 | 0.9914 / 0.0080 |
| RT R2 / median, fine-tuned (train rows) | 0.9967 / 0.0058 (17,074) | 0.9980 / 0.0049 (21,993) |

- Recall of DIA-NN, last RT bin (10.0-11.2 min, 5,792 precursors): AlphaPeptDeep single 0.4%, 3-file 11.6%;
  Chronologer single 52.9%, 3-file 67.5%. Every other bin +3-7 points (3-file 67-72% against 64-68%).
- Library RT error on held-out A1, last two bins: AlphaPeptDeep fine-tuned 0.116 / 0.199 min, Chronologer fine-tuned
  0.068 / 0.061; mid-run 0.033-0.056 against 0.038-0.061.
- Against DIA-NN at matched 0.3% FDP (`TODO-20260923_osprey_demux.md` table): Chronologer's 40,780 equals DIA-NN out of
  the box on the `.wiff` (40,833), where Osprey with the fine-tuned AlphaPeptDeep library was 15% under; it is still
  17% under DIA-NN on the same demux files with its own library (48,897) and 21% under DIA-NN with the fine-tuned
  Carafe library (51,561). The late-gradient loss of #4759 is gone; the remaining gap is Osprey's scoring.
- matrix_report.py: matched FDP now stops at q 0.015 (the export's complete range) and says when a level is not reached,
  instead of counting every target of the export (it had printed 234,254 / 431,076 at 0.5%).

**SkylineAI regression libraries** (`osprey-testfiles-mzML-v2\{astral,stellar}\*SkylineAI_spectral_library.tsv`): Mike: a
library fine-tuned with a new Carafe model, in which only the RT model changes; its FDR is not controlled as well, so its
Osprey count (Astral 117,236 at 1%, port build) is not comparable with the matrix's entrapment-checked numbers. Library
RT error on Astral run 49 (median |obs - isotonic|): no plateau (0.18 / 0.21 min in the last two bins, AlphaPeptDeep
fine-tuned 0.42 / 0.99), mid-run 0.075-0.131; fine-tuned Chronologer is lower in every bin (0.074-0.115 mid, 0.136 /
0.146 late), though run 49 may be in-sample for the SkylineAI fine-tune.

**Osprey FDR, for the record (separate from #4759; not filed yet):**
- q-values are conservative: entrapment FDP at q <= 0.01 is 0.41-0.56% on Stellar and Astral (matrix 3-file searches),
  0.24-0.30% on ZT Scan. At q <= 0.015 Chronologer's FDP is still 0.64% (Astral) / 0.76% (Stellar) with 5% more
  precursors (Astral 114,527 -> 120,577). A calibrated 1% would add roughly 5-10%.
- `FDRBench-Input.tsv` is not a faithful sample past q ~0.015: the FDP flattens while targets keep growing, and at
  q <= 1 it reads 1.5-5.4% for 150-620k targets on 1:1 entrapment libraries. It should carry every scored precursor.

| arm (3-file) | q 0.005 | q 0.01 | q 0.015 | q 0.02 |
|---|---|---|---|---|
| Stellar AlphaPeptDeep | 28,940 (0.30%) | 31,110 (0.56%) | 32,739 (0.89%) | 33,840 (0.91%) |
| Stellar Chronologer | 32,946 (0.30%) | 35,485 (0.52%) | 37,253 (0.76%) | 38,578 (0.78%) |
| Astral AlphaPeptDeep | 95,084 (0.29%) | 103,269 (0.52%) | 108,445 (0.70%) | 112,168 (0.82%) |
| Astral Chronologer | 104,810 (0.22%) | 114,527 (0.41%) | 120,577 (0.64%) | 124,811 (0.68%) |

**Next (Mike, 2026-10-02): get the Chronologer work into the CarafeSharp PR (#4717).** If Chronologer becomes the
default, CarafeSharp's regression goldens (Stellar, Astral) change.

### 2026-10-02 - Code review, provenance, ZT Scan

- Pushed 89c75b3808 to #4717 (Mike: push now, flip the default after ZT Scan). `/code-review max` on the Chronologer
  diff: 15 findings, all fixed in 30701dad86 (local): saved models name their RT model (`carafemodel-2`; `-1` still
  read); `-rt_model` optional (else `-model`'s, else AlphaPeptDeep), another kind starts from its pretrained model with
  a warning; Chronologer clipped at 0, test-set fallback, encoded-row counts, summed same-site mods, version metadata;
  files checked up front and by `-TestData Verify`; leak-safe loading; end-to-end tests; docs 01/04/06.
- Mike: track model type and provenance through fine-tune chains. 4d102b2ecd (local): each manifest model has `model`,
  `model_version` (AlphaPeptDeep v1, Chronologer 20220601193755) and `start` (pretrained / base / ms2_model), and each
  `base_models` entry its own, so one file holds each model's lineage; `-model_info` prints it.
- a9c0e2fac2 (local): a full-suite run failed in `PthReader` with libtorch `NYI` in `clone`: the strided view had no
  reference once clone had its handle, so its finalizer could free it mid-copy. Fixed there and in `StateDict.Load`,
  `SafetensorsFile.Write`, `Ms2Model.PlaceColumns`. Gate: 92 tests, 84 pass + 8 parity Inconclusive, three full passes;
  inspection 0.
- ZT Scan matrix (above) agrees with Stellar and Astral: Chronologer wins every count and every RT bin. Next: flip the
  default to Chronologer (CLI, workflow script, parity tests pinned to AlphaPeptDeep, docs/05), regenerate the Stellar
  and Astral goldens (needs the ~6.5 GB test data), push.
- Default flipped, 0338c2a309 (local): `LibrarySettings.DEFAULT_RT_MODEL = chronologer` (else `-rt_model`, else the
  model folder's or saved model's); `CarafeReferenceRun` pins `alphapeptdeep` for the Carafe parity tests; a
  `carafemodel-1` file without an RT model stays AlphaPeptDeep; docs 01/05/06. `Run-CarafeSharpWorkflow.ps1`
  defaults `-RtModel chronologer` and always passes it. Gate green (92 / 84 + 8 Inconclusive, inspection 0).
  Pending: regenerate the Stellar and Astral regression goldens (`regression.ps1 -CreateGolden -Force`, clean tree,
  CPU; needs `build.ps1 -TestData Fetch`, ~6.5 GB), then push the four commits to #4717.
- Pushed to #4717 (Mike: yes to both): decaae533e (review fixes, finalizer races, provenance, merged with another
  session's Copilot fix d1b7738ce1, `.carafemodel` entries must be plain names), then 7e03af27c1: the default flip
  (6a1f1e41bc), goldens Stellar 3c3d40a502 / Astral 9f98c03903, docs/04 7e03af27c1. Test data fetched to
  `C:\Users\macco\Downloads\Perftests` (all four packages).
  - Goldens remade on this machine (i9-13900H, 14 threads; the old ones were the i9-9900K's). Against the AlphaPeptDeep
    goldens only the RT metrics and library RT fail: Stellar pretrained RT R2 0.8707 -> 0.9933, fine-tuned 0.9976 ->
    0.9980 (MAE 0.0050 -> 0.0037); Astral 0.8595 -> 0.9943, fine-tuned 0.9972 -> 0.9971 (MAE 0.0048 -> 0.0039).
    Training tables identical; sampled spectral cosine median 0.99974 / 0.99982; machine: MS2 <= 3.3e-4, peaks
    -0.18% / -0.11%, Astral 3 pairs fewer.
  - With data: `build.ps1 -RequireData` 92 of 92 (the Carafe parity tests pass with `-rt_model alphapeptdeep`
    pinned), `-TestCategory Astral -RequireData` 4 of 4.
  - Logs: `ai/.tmp/sessions/20260927-054c052f/golden-{stellar,astral}.log`, `build-requiredata.log`,
    `build-astral.log`.

### 2026-10-02/03 - Chronologer docs, run alignment (-rt_align kde)

- docs/07-chronologer.md (a2c6d99b04, local): HI (% ACN at elution), its scale (iRT = 7.254 x HI - 45.47; 0.87 min
  per HI on the 24-min gradients), network, encoding, library, the fine-tune step by step, Chronologer's own
  multi-source training, HI to minutes for new gradients and chemistries.
- Mike: several runs of an experiment must be put on one scale. Today one row per form from its best run, one rt_max:
  run drift is target noise, different gradients silently wrong. Drift measured on the matrix 3-file searches
  (`run_drift.py`): Stellar <= 0.01 min, ZT Scan 0.02-0.04, Astral _60 vs _49 up to 0.16 min (a stretch); a smooth
  per-run map leaves 0.005-0.018.
- Built (e8911f24b3, local): `KdeRidgeAlignment` (Chronologer's KDE_align; knots match its own to 1e-9, 20k points at
  grid 3000 < 1 s), `MonotoneMap`, `RtAlignment` (per-run maps onto pretrained Chronologer HI, pointwise median map
  back to minutes, spread, rt_maps.json). `-rt_align none|kde`, `-rt_select best|median`. Rows converted to HI
  through their run's map before selection; Chronologer fine-tunes on HI (in a fixed line's units, folded out after),
  saves an HI model; libraries in the median map's minutes (also from a saved model; pretrained + maps = minutes
  without fine-tune). Mike: library minutes default = pointwise median of the runs' maps, not the most-ID run.
  97/97 tests, inspection 0.
- Replicate experiment (Astral 49/55/60, search of the pretrained-Chronologer library with exports in
  `C:\temp\osprey-runs\multirun\astral-train3`; `Run-AlignExperiment.ps1`, `eval_align.py`,
  `multirun\align-report.txt`), -tf rt, library of DIA-NN's 130k peptides, scored against DIA-NN per run:

  | arm | minutes median abs err (49/55/60) | order err | last-bin order |
  |---|---|---|---|
  | single _55 | 0.100 / 0.094 / 0.106 | 0.091 | 0.152 |
  | single kde | 0.097 / 0.092 / 0.104 | 0.090 | 0.153 |
  | three unaligned | 0.097 / 0.094 / 0.110 | 0.091 | 0.155 |
  | three kde best | 0.097 / 0.091 / 0.103 | 0.090 | 0.153 |
  | three kde median | 0.097 / 0.091 / 0.103 | 0.090 | 0.151 |

  Small, consistent: on replicates drift (+-0.05 min about the median run) is half the model's per-peptide error
  (0.09), so alignment is safe and slightly better; unaligned pooling shifts library minutes +0.011 min. Aligned
  library sits on the median run (-0.048 / +0.001 / +0.058 vs 49/55/60). Mixed-gradient test (Astral + ZT Scan)
  running: `Run-MixedExperiment.ps1`, `eval_mixed.py`.
- Mixed-gradient experiment (`Run-MixedExperiment.ps1`, `eval_mixed.py`, `multirun\mixed-report.txt`): Astral _55
  (24 min) and ZT Scan D1 (11.4 min), -tf rt, library of both datasets' DIA-NN peptides. Order error (isotonic, mean of
  3 runs) Astral / ZT: astral-kde 0.090 / 0.054; zt-kde 0.119 / 0.045; both-kde 0.092 / 0.053; both unaligned 0.099 /
  0.135 (last bin 0.456 / 0.131). Unaligned mixing breaks; aligned, one model serves both (Astral within 2%; ZT diluted
  by 85k Astral rows to 23k ZT, still better than Astral's model). Minutes through each training run's own map: 0.092 /
  0.055; through the median map (default) 2.8 / 3.4 min wrong: the median of two gradients is neither. Spread flags
  it (6.4 min against 0.095 for replicates). Next (proposed): -rt_reference <run> and a warning or iRT when the maps
  spread; -rt_align kde default (Mike); per-source balance in the loss.

### 2026-10-03 - -rt_reference, sparse-run tiers, -rt_align kde default

- Mike: no per-source balance in the loss. A form counts once, so the run with more peptides carries more weight,
  which is wanted. (Chronologer's per-source Laplace scale is about noise, not size; not taken.)
- `-rt_reference <run>` (name or unique end, e.g. `_55`): the library in that training run's minutes. Without it, when
  the runs' 95th-percentile distance from their median passes 5% of its span (`RtAlignment.IsWide`; replicates 0.4%,
  Astral+ZT 30%), the library is iRT with a warning naming the runs. Refused without maps or with AlphaPeptDeep.
- `RtMapFit` (Core): each run's map in Osprey's tiers (`Calibrator.SelectFitPlan`): KDE ridge >= 1000 forms (Mike's
  number); robust LOESS (bw 0.3, widening to 0.3 x 200 / n below 200); Theil-Sen line below 100 if it spans half the
  run; < 15 forms or a failed fit leaves the whole training unaligned with a WARNING (not an error, now that kde is
  the default). PAV makes LOESS monotone. rt_maps.json records each run's fit.
- Does KDE need 1000? Measured with a temporary harness (`ai/.tmp/sessions/20260927-054c052f/rt-map-fit-report.txt`,
  `ScratchRtMapFitExperiment.cs.txt`), 95th percentile of the disagreement of shared forms between runs' maps:

  | forms/run | 3 Astral replicates KDE / LOESS (min; raw 0.185) | Astral + ZT KDE / LOESS (HI) |
  |---|---|---|
  | all | 0.070 / 0.070 | 0.27 / 0.47 |
  | 1000 | 0.115 / 0.094 | 0.30 / 0.45 |
  | 300 | | 0.34 / 0.48 |
  | 200 | 0.179 / 0.136 | |
  | 100 | 0.26 / 0.15 | |

  KDE wins across gradients at every size (LOESS's 30% window bends differently per gradient shape; on replicates the
  bias cancels); on replicates LOESS is less noisy below the full run, and KDE at 100 is worse than unaligned. Kept
  KDE >= 1000.
- `-rt_align kde` is now the default (`TrainingSettings.DEFAULT_RT_ALIGNMENT`); `-rt_align none` is Carafe's. A `-tf ms2`
  training with aligned runs gives a pretrained-Chronologer library in the runs' median minutes.
- docs 07 (new "Aligning the runs" section with both experiments), 06 (`rt_maps.json`), 01 updated.
- Commit `00d768491f`; gate 98/98, inspection 0 (`gate-tiers.log`). Goldens remade for the default: Stellar
  `b64f178ecf` (KDE on 20,791 forms; held-out RT pretrained MAE 0.0063 -> 0.0058, fine-tuned 0.0037 -> 0.0035),
  Astral `7180cb9d8f` (KDE on 77,073; 0.0067 -> 0.0061, 0.0039 -> 0.0037). MS2 identical. Logs
  `golden-{stellar,astral}-aligned.log`. Full Astral libraries old vs new against DIA-NN (~2,660 observed precursors
  per run): isotonic order error 0.083-0.086 both, past 20 min halved (20-22: 0.39-0.41 -> 0.20-0.26; >22:
  0.82-1.01 -> 0.40-0.53); raw minutes past 20 min worse (0.33-0.41 -> 0.60-0.68), the map extended past Osprey's
  last training point at 19.87 min.
- Pushed to #4717 (Mike: "please push"): `7e03af27c1..7180cb9d8f` (docs 07, KDE alignment, tiers + default, both
  goldens). PR body update drafted in `ai/.tmp/sessions/20260927-054c052f/pr4717-body-align-draft.md`, not posted.
  With the test data: `-RequireData` 98/98, `-TestCategory Astral -RequireData` 4/4
  (`build-{requiredata,astral}-aligned.log`).
- Mike: the plan is DIA run -> Osprey -> fine-tune -> save the model and reuse it, even for targeted assays, with no
  iRT step; HI is right only for mixed gradients. Changed (`58bfcdf18a`): runs on one gradient (not `IsWide`) train on
  their aligned minutes, so the saved network predicts minutes itself; runs on different gradients still train
  Chronologer on HI with the maps (AlphaPeptDeep there warns). The maps are kept either way (`-rt_reference`,
  provenance, `-tf ms2`); `-rt_reference` on a minutes model goes median minutes -> HI -> run minutes
  (`RtAlignment.MedianToRunMinutes`). New `TestRtAlignmentMixedGradients`. Gate 99/99, inspection 0.
- Experiment (`Run-MinutesExperiment.ps1`, `eval_minutes.py`, `C:\temp\osprey-runs\multirun\minutes-report.txt`): minutes
  model, one Astral run 0.100 min (as unaligned), three runs 0.099 with drift removed (mean offset +0.003 vs +0.015);
  last RT bin 0.170 / 0.171 vs 0.169 unaligned and 0.166 / 0.167 HI. HI+map better only at the gradient's start
  (0.084 vs 0.097 min, first eighth of `_60`).
- Goldens remade again (Stellar `7323f690dc`, Astral `77dec9157e`; the HI pair `b64f178ecf`/`7180cb9d8f` superseded):
  RT metrics back to the pre-alignment goldens'. Astral libraries by RT bin against DIA-NN (unaligned / HI / minutes):
  order 0.084 all; 20-22 min order 0.405 / 0.235 / 0.410, minutes 0.369 / 0.627 / 0.364 (the regression export's
  training stops at 19.87 min). `-RequireData` 99/99, Astral 4/4. Not pushed yet.
