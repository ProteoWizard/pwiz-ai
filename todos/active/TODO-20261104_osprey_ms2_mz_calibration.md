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
  5.2% more protein groups at 1% FDR than the mean. There the gain is less the m/z dependence
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
- [ ] ppm curve as the default for ppm searches: repeat on ZT Scan D1 and G1 (demultiplexed
  in `D:\ZenoTOF8600-TestData\demux`) and on Astral, check entrapment, then regenerate the
  Astral golden (Astral is searched in ppm). Also test a plain median correction: it may give
  most of the ZT Scan gain.
- [ ] Calibration discovery itself matches within the uncorrected tolerance: a shift of -0.5
  to -0.7 Th on the small subset calibrated nothing (full runs had enough peptides). A
  fallback discovery at a wider tolerance, or an ID-free MS2-vs-MS1 precursor estimate, would
  close it.
- [ ] Training export metadata and the model-diagnostics CAL view report only the mean: add a
  has-curve flag or the knots.
- [ ] Port to Rust osprey, or keep `OSPREY_MS2_CAL_MEAN=1` for parity runs.
- [ ] A regression dataset with a large MS2 offset (the 2026 Stellar runs).
