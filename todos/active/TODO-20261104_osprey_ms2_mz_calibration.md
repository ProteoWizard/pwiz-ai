# TODO-20261104_osprey_ms2_mz_calibration.md

## Branch Information
- **Branch**: `Skyline/work/20261104_osprey_ms2_mz_calibration`
- **Base**: `master`
- **Created**: 2026-11-04
- **Status**: In Progress
- **PR**: #4997 (Brendan to review once the entrapment check is in)

## Why

We added the MS2 m/z offset curve because of a poorly calibrated set of Stellar experiments,
and it turned out to benefit HRAM data too.

- **Stellar (the reason it exists).** On Stellar profile data converted in 2026 (HeLa 2 Th
  DIA, TR01-TR03) the MS2 m/z axis runs 0.5-0.7 Th low, while MS1 is on target (the
  unfragmented precursor in each MS2 window confirms it without identifications). The old
  unit-resolution calibration takes each top-6 library fragment's closest peak within the
  0.5 Th fragment tolerance and subtracts the mean of those errors. An offset that wide puts
  the monoisotopic (M+0) peak on the window's edge, the closest peak is as often the M+1, and
  the calibration was partly aligning to the M+1 instead of the M+0: the mean came out near
  zero (+0.08 Th for Thermo's centroids, 0.00 for Centrix's). Osprey compensated only by
  widening the tolerance to 3 SD (+-0.85 Th).
- **HRAM (the bonus).** The same curve, with widths scaled from a ppm tolerance, helps ppm
  data too: on a demultiplexed ZenoTOF 8600 ZT Scan run it found 5.7% more precursors and
  5.2% more protein groups at 1% FDR than the mean. (2026-11-09: that did not hold with the current
  Osprey on 3 ZT runs or on Astral; see Results.) There the gain is less the m/z dependence
  (the curve varies only 1.5 ppm) than centering on the bulk of skewed fragment errors
  (median 5.0 ppm, mean 4.28). It is opt-in and experimental for now
  (`OSPREY_MS2_CAL_CURVE_PPM=1`).

## Solution

`Ms2OffsetCurve` (Osprey.Chromatography), documented in
`pwiz_tools/Osprey/docs/04-calibration.md` ("MS2 m/z offset curve"):
- Collect the centroids around each calibration target match's top-6 fragments (2.5 Th
  either side at unit resolution; 2T + T/4 for a ppm tolerance T).
- Shift scan: the shift that puts the most fragments within the hit tolerance of a peak
  (unit resolution: +-1.3 Th on a 0.01 Th grid, 0.2 Th; ppm: +-2T, T/100, T/4).
- Unit resolution only: step down one isotope spacing while most 1+ fragments show a larger
  peak one spacing below (the shift landed on the M+1).
- LOESS of each fragment's nearest offset (within 0.5 Th, or T, of the shift, then of the
  curve) against m/z, as the RT calibration fits; SD of the offsets about it; 3 SD
  tolerance; 21 knots.
- Applied by `MzCalibration.ApplyCalibration` (`OffsetAt`; in ppm, `mz * offset / 1e6`),
  stored as `ms2_calibration.offset_curve` in the calibration JSON (older files load as the
  mean; Rust reads only the mean, SD and tolerance).
- When it applies (`OspreyEnvironment.UsesMs2OffsetCurve`):
  - Unit resolution with a Th tolerance: by default, when the shift is beyond half the
    tolerance; otherwise the mean, so the 2024 Stellar regression and subset data (-0.06 Th)
    is unchanged, golden and Rust parity included.
  - ppm (HRAM): only under `OSPREY_MS2_CAL_CURVE_PPM=1`, at any shift. Off by default, so
    Astral and every other ppm search is unchanged.
  - `OSPREY_MS2_CAL_MEAN=1` keeps the mean everywhere (Rust parity) and overrides the ppm
    switch.
- Validity-key terms: `;ms2cal=curve|mean` for unit-resolution Th searches,
  `;ms2cal=curveppm` for ppm searches under the opt-in.

## Results

Stellar TR01-TR03, each arm's own predicted library, +-0.5 Th, 1% FDR:

| Arm | Old (mean) | New (curve) |
|---|---|---|
| Thermo centroids, precursors / protein groups | 17,175 / 2,077 | 39,025 / 5,122 |
| Centrix, precursors / protein groups | 33,601 / 4,503 | 40,299 / 4,931 |

Corrections -0.74 Th (Thermo) and -0.63 Th (Centrix) on average; tolerances +-0.58 and
+-0.37 Th. Data and analysis: `D:\Stellar-Profile_Testdata\osprey-{vendor,centrix}-{mean,curve}`,
deck https://claude.ai/artifact/B3WC4aAsVCFpRK7qi6GZez.

ZenoTOF 8600 ZT Scan A1 (250814_ZTScan_100spd_A_1_A1, demultiplexed, 10 ppm), the same
predicted library with its decoys and the same spectra cache, only `OSPREY_MS2_CAL_CURVE_PPM`
differing, 1% FDR:

| MS2 calibration | Precursors (run) | Protein groups (1st pass / final) | Library spectra |
|---|---|---|---|
| Mean, 4.28 ppm, 3 SD 11.05 ppm | 23,439 | 3,461 / 2,562 | 27,662 |
| Curve, 4.39 to 5.91 ppm, 3 SD 10.85 ppm | 24,769 (+5.7%) | 3,698 / 2,696 (+5.2%) | 28,144 |

25,791 precursors shared, 1,871 mean only, 2,353 curve only. Data:
`D:\ZenoTOF8600-TestData\osprey-ztscan-ab-{mean,curve}` (scripts `run-ztscan-*.sh` there).

**ZT Scan 3 runs with entrapment, latest Osprey (2026-11-08/09 night).** #4950 tip (two-round GBDT, 109 features)
with this branch merged locally (`nightlywork/zt-sigma-search` in `C:\Dev\pwiz-osprey-fdr`, not pushed), 20 ppm,
FDRBench combined FDP. Runs `C:\test\osprey-runs\ztsigma\arms`, handoff `ai/.tmp/handoff-20261108-ztsigma.md`.
- At 3 SD the curve LOSES: 3 runs pass-1 targets at FDP 0.5% / 1% 44,769 / 48,424 vs the mean 45,360 / 49,653;
  run-level 1% 132,567 vs 135,661 (-2.3%). The searched window is `MzCalibration.CalibratedTolerance` = 3 SD for both
  (`adjusted_tolerance`, |mean| + 3 SD, is written but not searched): 15.19 vs 16.86 ppm on A1, because the curve
  removes the m/z trend and its SD is smaller. The offset only moves 1-2 ppm over m/z on these runs.
- At the mean's width the curve is a wash. Experimental `OSPREY_MS2_CAL_CURVE_TOL_SDS` (local 32ef839639 + fix
  06745cd1b3; in the validity key; curve only) searches the curve at k SD. A1 alone at FDP 0.5% / 1% | run-level:
  mean 39,709 / 43,180 | 44,352; curve 3 SD 39,502 / 43,485 | 44,079; 3.33 SD (16.86 ppm, the mean's window)
  40,404 / 43,766 | 44,837; 4 SD (20.25 ppm) 40,155 / 44,245 | 44,612. That A1 gain did not hold on 3 runs. Curve at
  3.33 SD against the mean, same fit sigma and seed, FDP 1% | run-level:
  - 1.0x seed 42: 48,596 vs 49,653 (-2.1%) | 132,617 vs 135,661 (-2.2%)
  - 1.0x seed 7: 48,904 vs 49,167 (-0.5%) | 133,563 vs 134,415 (-0.6%)
  - 1.3x seed 42: 50,123 vs 49,845 (+0.6%) | 136,654 vs 136,649 (0.0%)
  - 1.3x seed 7: 50,614 vs 49,859 (+1.5%) | 137,547 vs 136,087 (+1.1%)
  The seed replicates put the pipeline's own spread at ~1%. Averaged over the four, the curve at matched width is
  even with the mean (-0.1% at FDP 1%); the sign follows the fit sigma in both seeds (behind at 1.0x, ahead at 1.3x),
  which may be a real interaction but is no larger than the noise. At 3 SD it is 1-2% behind. Its offset moves only 1-2 ppm over m/z on these runs; the earlier +5.7%
  (10 ppm, older Osprey, 1 run) does not reproduce with the two-round GBDT and 109 features.
- Astral, the regression's 3 HeLa mzMLs (byte-identical to the golden set) with the 11-04 entrapment library
  (`C:\test\osprey-runs\astral-pr4950`, 1:1 Arabidopsis, r = 0.9904), same search config, 2026-11-09, arms
  `arms\mzcal-{mean,curve}`, `mzcal.log`. FDP 0.5% / 1% | run-level: mean 123,301 / 130,787 | 365,239; curve 3 SD
  123,039 / 131,292 | 364,144 (-0.2% / +0.4% / -0.3%). Astral has almost no m/z trend: the curve's SD is 2.00-2.11
  vs the mean's 2.06-2.17 ppm, searched 6.0-6.3 vs 6.2-6.5 ppm. No matched-width or golden-library arm was run.
- **Conclusion (Mike, 2026-11-09): not worth it for HRAM data.** Neither ZT Scan nor Astral gains; the curve stays
  opt-in for ppm (`OSPREY_MS2_CAL_CURVE_PPM`) and the work is about unit resolution, where Stellar's 0.5-0.7 Th offset
  is the case it was built for. The +5.7% ZT line in "Why" is from an older Osprey and does not reproduce.

## Tried and not adopted: a separate 2+ fragment calibration (2026-11-09)

**Decision (Mike, 2026-11-09):** unit-resolution MS2 calibration stays one m/z-based curve,
fit to the matched fragments of both charges. Correcting the offset that the unresolved M+1
causes is what helps, and it belongs in that single calibration. A charge-dependent shift is
more complicated and did not help.

Why it was tried: after the curve, 2+ fragments read high and 1+ fragments low at the same
m/z, because the curve is a blend of the two. Medians of TR02's strong, isolated fragments,
500-1150 m/z: 1+ -0.028 to -0.011 Th, 2+ +0.026 to +0.036 Th (Centrix MS2 sigma 0.38); 1+
-0.048 to -0.038, 2+ +0.058 to +0.076 (sigma 0.6).

What was tried (switches `OSPREY_MS2_CAL_BY_CHARGE=1`, `OSPREY_MS2_CAL_BY_CHARGE_XIC_ONLY=1`):
- The curve fit to 1+ fragments only, one 2+ shift (the median of the 2+ offsets about the
  curve), and the SD pooled from both.
- Spectra still calibrated whole by the 1+ curve; the shift added to the library's 2+
  fragment m/z instead, either everywhere or only for XIC extraction (the features scored
  against the library's own m/z).

Stellar HeLa 2 Th TR01-TR03, Centrix, GBDT, library decoys with entrapment, +-0.5 Th, 1% FDR:

| Arm | Precursors per run | Experiment | Entrapment FDP | 2+ shift (Th) | TR02 tolerance |
|---|---|---|---|---|---|
| sigma 0.38, one curve | 42,572 / 43,170 / 43,208 | 49,636 | 1.04% | none | +-0.29 Th |
| sigma 0.38, shift everywhere | 42,146 / 42,905 / 42,964 | 49,603 | 1.06% | +0.080 / +0.090 / +0.093 | +-0.28 Th |
| sigma 0.38, XIC only | 42,228 / 42,958 / 43,152 | 49,696 | 1.06% | same | +-0.28 Th |
| sigma 0.6, one curve | 44,341 / 44,764 / 44,505 | 51,467 | 0.88% | none | +-0.38 Th |
| sigma 0.6, shift everywhere | 43,957 / 44,323 / 43,832 | 51,145 | 0.88% | +0.150 / +0.156 / +0.142 | +-0.33 Th |
| sigma 0.6, XIC only | 44,469 / 44,550 / 43,989 | 51,246 | 0.82% | same | +-0.33 Th |

- The tolerance narrowed 5-11%, but identifications and entrapment FDP stayed within the
  run-to-run churn (each arm swaps 2,000-2,800 precursors each way with its baseline). 3+
  precursors, which carry most of the 2+ fragments, did not gain.
- XIC only beat shift-everywhere in all six runs, by 0.1-1.2%, and neither beat one curve.
- The shift overcorrects the strong, isolated 2+ fragments (-0.042 to -0.055 Th at sigma
  0.38, about -0.07 at sigma 0.6): the median over all matched 2+ fragments sits above them.
- Likely why nothing changed: a 0.05-0.15 Th offset inside a +-0.28-0.38 Th window loses few
  true matches.
- The mass defect does separate charges below about 800 m/z (73-91% of odd-nominal-mass 2+
  fragments sit over 0.25 Th off the 1+ lattice, against 2-8% of 1+), but the library already
  gives Osprey each fragment's charge.

Code (local only, not committed): `D:\Dev\ai\.tmp\sessions\20261106-stellar2th\ms2cal-by-charge.patch`,
against f498d9e608. Results: `summary7-bycharge.tsv` and `bycharge_compare.txt` in the same
folder; searches in `D:\test\osprey-runs\stellar-2th\2th-centrix-s0{38,60}-{z,zxic}`.

## Tests
- [x] `CalibrationTest.TestMs2OffsetCurve`: synthetic ion-trap fragments, -0.40 to -0.55 Th;
  curve within 0.03 Th, M+1 step-down, small offset keeps the mean, JSON round trip; doubly
  charged fragments do not step down; a full -0.75 Th calculation with M+1 in every fragment
  lands on the M+0; a ppm curve recovered within 0.5 ppm and applied in ppm.
- [x] `SubsetPipelineTest.TestSubsetLargeMs2Offset`: the Stellar subset with its MS2 m/z
  shifted -0.30 to -0.40 Th; curve recovers it within 0.1 Th, reports >= 90% of the
  unshifted subset; the mean under `OSPREY_MS2_CAL_MEAN=1` does worse.
- [x] `TaskValidityKeyTest`: the `UsesMs2OffsetCurve` truth table and the per-task keys under
  mean, curve and ppm-curve settings.
- [x] Full Osprey.Test suite (655), ReSharper inspection clean.
- [x] `regression.ps1 -Dataset All` (Stellar, StellarLibDecoy, StellarGenDecoyEntrap, Astral):
  PASS on 8c0577c89d, in place of the TeamCity Perf/Regression run.
- [x] Two fresh-context code reviews; findings addressed (8c0577c89d, 83a6955d46).

## Follow-ups
- [ ] Entrapment (FDRBench) check of the Stellar TR01-TR03 gains.
- [x] ppm curve as the default for ppm searches: ZT Scan 3 runs (with seed replicates) and Astral 3 runs, both
  with entrapment, 2026-11-09 (above): no gain on either. Dropped; the ppm path stays opt-in.
- [ ] Calibration discovery itself matches within the uncorrected tolerance: a shift of -0.5
  to -0.7 Th on the small subset calibrated nothing (full runs had enough peptides). A
  fallback discovery at a wider tolerance, or an ID-free MS2-vs-MS1 precursor estimate, would
  close it.
- [ ] Training export metadata and the model-diagnostics CAL view report only the mean: add a
  has-curve flag or the knots.
- [ ] Port to Rust osprey, or keep `OSPREY_MS2_CAL_MEAN=1` for parity runs.
- [ ] A regression dataset with a large MS2 offset (the 2026 Stellar runs).
