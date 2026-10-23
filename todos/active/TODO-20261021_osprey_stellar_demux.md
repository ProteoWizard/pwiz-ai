# TODO-20261021_osprey_stellar_demux.md

## Branch Information
- **Branch**: `Skyline/work/20261021_osprey_stellar_demux`
- **Base**: `Skyline/work/20260923_osprey_demux` (PR [#4710](https://github.com/ProteoWizard/pwiz/pull/4710), head
  936b79994f). Mike (2026-10-21): this work merges back into #4710, not into master.
- **Created**: 2026-10-21
- **Status**: In Progress. Data downloaded and characterized; acquired baselines searching.
- **GitHub Issue**: [#4711](https://github.com/ProteoWizard/pwiz/issues/4711) (M5: Stellar profile demux)
- **Module**: `osprey`
- **PR**: none; commits go to #4710's branch when ready
- **Checkout**: `D:\Dev\pwiz-osprey-demux` (this machine); scripts in `ai/scripts/Osprey/Demux`

## Objective

Demultiplex Stellar (ion trap) overlapping-window DIA, from centroids and from the profile, at
2-fold (50%) and 4-fold (25% step) overlap, with the offset window sets in successive cycles.
Measure it against the acquired narrow and wide windows of the same sample. Spec §5.4c-d (profile
demux, then the joint demux and centroiding), §2.0 (fill-time rows), §4.3 (acquired-axis fit).

## Data

Lauren's set for Mike, Panorama `MacCoss/Lauren/20261009_Stellar-Centroiding-for-Mike/RawFiles`
(24 files, 45 GB), on this machine in `D:\test\osprey-runs\stellar-demux\raw`. HeLa, 24 min
gradient, precursors 400-900 m/z, HCD 20, fragments 200-1200 m/z, three replicates (TR01-03) per
method, each method acquired once centroided and once in profile (`_profile`).

Library: the Osprey Stellar test library (Mike: same HeLa),
`%USERPROFILE%\Downloads\Perftests\osprey-testfiles-mzML-v2\stellar\hela-filtered-SkylineAI_spectral_library.tsv`.
No entrapment; for FDP, the libdecoy entrapment library from `stellar-libdecoy-v3.zip` is an option.

| Method | Windows per pass | Passes per cycle | Demux bin | A window repeats every | Max fill |
|---|---|---|---|---|---|
| `2Th` | 251 x 2 Th | 1 | (2 Th, acquired) | 3.33 s | 11.5 ms, always reached |
| `4Th` | 126 x 4 Th | 1 | (4 Th, acquired) | 3.14 s | 23 ms |
| `4Th-50pctOverlap` | 126 x 4 Th, +2 Th per pass | 2 (k=2) | 2.0009 Th | 6.28 s | 23 ms |
| `4Th-SuperOverlap` | 126 x 4 Th, +1 Th per pass | 4 (k=4) | 1.0004 Th | 12.5 s | 23 ms |

One MS1 per full cycle (per 2 or 4 passes in the overlapped methods). Window centers step 4.0018-4.002 Th.

## Findings (2026-10-21)

- **Profile grid:** every MS2 profile spectrum has exactly 5,000 points, 200.2-1200.0 m/z, uniform
  0.2 Th, identical across spectra. Strong peaks: FWHM ~0.94 Th (IQR 0.78-1.34), about 5 points.
  26.7% of points are zero. So each grid point is a fixed channel across spectra (spec §5.4c's
  precondition), as on the ZT Scan TOF grid but linear in m/z.
- **Intensities are rates.** TIC x fill time is about constant (4.4e6, the AGC target) while fill
  time runs 0.2-23 ms mid-run, centroided and profile alike. Ions are intensity x fill time / scale,
  so Poisson weights need each spectrum's fill time; the weighted engine's one `CountsPerIon` for
  the run is wrong by up to 100x between scans here.
- **One ion:** isolated profile events (3+ points) start sharply at area x fill time ~470, mode
  ~700 (a multiplier pulse-height distribution); their height x fill time is ~380. Centroid
  intensity x fill time has a hard floor at 100 and median 2,600. With ~400 per ion for centroid
  heights, 4.4e6 is ~11,000 ions per spectrum, consistent with an AGC target of 1e4 charges.
- **Unit resolution breaks the 10 ppm fragment channels.** The weighted engine matches channels in
  ppm only (10 ppm), as docs/23 already says is not right for Stellar centroids. Vendor centroids are
  never closer than 0.62 Th (median spacing 1.28 Th, ~533 per spectrum) and the search's MS2 error SD
  is 0.22 Th: a centroid channel is essentially a nominal-mass channel (+/-0.4 Th), most with several
  sources. The profile's 0.2 Th grid is the cleaner channel.
- **Sampling (corrected 2026-10-21 evening).** The cycle is NOT fixed: at the run's start every fill hits its
  maximum and a pass takes 3.13 s, but from 4 to 22 min a pass takes 1.17-1.25 s (fills median 0.6-2 ms;
  < 1% of MS2 reach 11.5 ms). Earlier notes here said "1.6 passes per FWHM" from the 3.1 s start-of-run pass:
  wrong. Measured on each search's identified-precursor XICs (4-22 min): 2Th interval 2.39 s, FWHM 5.1 s
  (inflated by the coarse sampling); 4Th, 50% and SuperOverlap interval 1.18 s per bin; true FWHM about
  4.2 s (4Th, IQR 3.2-5.0) = 3.5 passes. So every bin is well sampled; what is sparse is each *window* at
  k=4 (every 4.7 s, ~1 sample per FWHM), which the current engine interpolates. Its SuperOverlap XICs come
  out 1.9 s wide (1.6 points), its 50% ones 3.5 s: the demultiplexing chops the elution.
- MS1: Mike (2026-10-21) - DIA-NN runs with MS1 scoring off for Stellar, and Osprey does not use MS1, so
  SuperOverlap's sparse MS1 does not matter.

## Results

Osprey (stellar-base-vendor snapshot = #4710 head + build fixes), unit resolution, test library, 1% FDR:

| Arm | Precursors TR01 / TR02 / TR03 | Experiment precursors / peptides / protein groups |
|---|---|---|
| 2Th acquired | 37,596 / 36,455 / 36,971 | 42,232 / 37,875 / 5,717 |
| 4Th acquired | 24,277 / 24,552 / 24,931 | 28,133 / 25,422 / 4,720 |
| 50% `--demux auto`, current engine (10 ppm channels, one counts-per-ion) | 24,911 / 25,403 / 25,823 | 28,241 / 25,225 / 4,595 |

| 50% tool, interpolation + 0.4 Th channels + fill-time ions (`50pct-interp-th`) | 25,137 / 25,875 / 25,432 | 29,521 / 26,423 / 4,706 |
| 50% tool, elution fit (FWHM 5.1 s) + 0.4 Th channels + fill-time ions (`50pct-elution`) | 22,019 / 21,863 / 21,904 | 26,311 / 23,854 / 4,419 |

**Why the elution fit loses on real data (2026-10-21 night).** Osprey's features, medians over the 19,912
precursors every arm scores in TR01 (`feature_compare.py`): fragment_coelution_sum 4Th 9.95, 2Th 12.32,
interp-th 8.61, elution 6.30, current 9.66; sg_weighted_cosine 0.917 / 0.926 / 0.879 / 0.803 / 0.896;
xcorr 1.05 / 1.19 / 0.97 / 0.81 / 0.90. Each fragment channel is fitted on its own, so each fragment of a
precursor gets its own pattern of shares in time (one keeps all its signal at a pass, another, sharing its
unit-resolution channel with a neighbor's fragment, a third): demultiplexed fragments no longer co-elute,
and the coelution and cosine scores fall. Per pass, near the apex, the elution fit keeps more of a
precursor's own signal than interpolation (median share 0.99 vs 0.86; `diag_shares.py`) but zig-zags
between the two offsets' passes; the peak width (5.1 / 4.2 / 3.5 s) does not change that. The synthetic
tests scored each fragment alone and could not see it. Every demultiplexed arm is far below acquired 2Th
(42,232), which ideal 2 Th bins at twice the fill time should exceed.
**Next: couple a precursor's fragments** (spec §6.5): e.g. a factorization across windows - each window's
(time x fragment) data as a sum of components with their own elution profile and fragment pattern, a
component in bin b present in both windows covering b and absent elsewhere - so fragments are split by
one elution and stay consistent.

The current engine on 50% is no better than acquired 4Th: 54.4M fragment channels for 138k MS2 spectra
(at unit resolution nearly every peak is its own 10 ppm channel) and 20% of the ions passed through unsolved.

**k=4 coupling prototype** (`coupling_proto.py`: 70 precursors x 8 fragments over 400 unit-resolution
channels, 40 1-Th bins, 40 passes, Poisson noise; apex error of single-source channels / leak):
oracle 12.7% / 0; per-channel elution fit 17.4% / 4.0%; per-channel peaks pooled into a (bin, apex)
map that restricts a second fit 16.2% / 3.5%; group-sparse greedy across channels (S-OMP) 16.8% / 4.2%;
support oracle (true bin and apex given) 14.2% / 1.1%. With exact peak widths the leak halves (1.9%),
so width mismatch drives the bin errors. The largest remaining loss is dropped observations: 7.7% of
single-source apex observations have no fitted peak in their window (weak fragments below the gain
threshold); the pooled fit as a fallback prior recovers part (5.0%). Next for k=4: how weak, unexplained
signal is apportioned, and a peak-width dictionary (several sigmas).

**Sampling model** (`sampling_model.py`, NB 32, NP 36, precursors at the 2Th search's identified density 0.25
per bin per pass, 8 fragments over 1000 unit-resolution channels, Poisson counts, FWHM jitter 15%; tables
`D:\test\osprey-runs\stellar-demux\synthetic\sampling_k{2,3,4}.tsv`). Interference = fraction of a bin's
output from other bins' fragments (no demultiplexing: 46% / 61% / 69% at k = 2 / 3 / 4):

| FWHM (passes) | k=2 interp / elution | k=3 interp / elution | k=4 interp / elution | k=4 area error elution / oracle |
|---|---|---|---|---|
| 1.65 | 13% / 0.1% | 30% / 1.2% | 43% / 6.6% | 13.4% / 9.6% |
| 2.0 | 9% / 0.1% | 23% / 0.8% | 34% / 2.3% | 9.5% / 8.3% |
| 3.0 | 4% / 0% | 12% / 0.2% | 21% / 0.6% | 6.9% / 6.6% |
| 4.0 | 3% / 0% | 7% / 0.1% | 13% / 0.3% | 6.3% / 6.1% |

The data sit at ~3.5 passes per FWHM: the elution fit should be near ideal even at k=4, the interpolating
engine is not even at 4 passes (13% at k=4). The 50% elution arm runs with FWHM 5.1 s (harmless at k=2);
SuperOverlap's with 4.2 s.

**Synthetic, noiseless** (`DemuxTest.TestDemuxPassRateMeasurement`, temporary; table in
`D:\test\osprey-runs\stellar-demux\synthetic\passrate-elution.tsv`): apex error of single-source fragments,
mean, by FWHM in passes. The current engine's per-window interpolation (`weighted`) against the elution fit:

| FWHM (passes) | k=2 weighted / elution | k=4 weighted / elution |
|---|---|---|
| 1.5 | 8.6% / 0.0% (leak 13% / 3%) | 39% / 2.1% (leak 46% / 5.5%) |
| 2 | 3.6% / 0% | 28% / 0.9% |
| 3 | 1.0% / 0% | 12% / 0% |

Weak spot of the elution fit: one fragment shared by four neighboring bins with broad overlapping peaks
(FWHM >= 6 passes) is misassigned by 5-9% at the apex (interpolation < 5%) - outside Stellar's regime.
Python prototype with Poisson noise (`ai/.tmp/sessions/20261021-stellar/passrate_proto.py`): at k=2 the
greedy elution fit equals the oracle (apex error = counting noise, 9.5%; leak 0.1% vs 14% interpolated);
at k=4 16.7% vs oracle 12.5% (leak 5.1% vs 39%): at FWHM 1.6 passes a source is seen strongly by only
three consecutive offsets, which share two bins, so the 1 Th bin is ambiguous between neighbors unless
tails decide. Fitting a precursor's fragments together (same bin, same apex) should resolve most of it.

## Code (branch commits 74df92bbba, bea8a1e2cb; local, not pushed)

- `ElutionDemultiplexer` (Osprey.Demux): per fragment channel and block, greedy sparse fit of Gaussian
  chromatographic peaks (bin, apex on a sigma/2 grid) under Poisson weights, NNLS refit of the amplitudes,
  stop when the weighted misfit drops by < 6; each observed peak apportioned at its own time. Tool:
  `--elution-fwhm S`, `--elution-param Name=Value`; `DemuxParams.Elution` for `--demux` later.
- `FragmentChannelFinder.FindLinear` (Th on a linear axis): tool `--channel-th T`; `DemuxParams` with
  `ChannelToleranceIsPpm = false` now works in the weighted engine.
- Fill-time ions: `DemuxSpectrumInfo.InjectionTime`, `ScanningDemuxOptions.FillTimeIonScale` (tool
  `--fill-time-ions S`), output written back per spectrum.
- `EventCentroider.CentroidLinear` and tool `--centroid-output SEP` for ion-trap profile output.
- bea8a1e2cb: candidates rescored only where observations changed (output identical, checked on a real
  slice); each new peak refits only the group of peaks sharing observations with it, warm-started, then
  one final refit per group: the slice's solve 18.0 s -> 2.1 s, output moved by mean |log2| 0.035 with
  synthetic accuracy unchanged or better; spectra described on the read threads when indexing (737 s
  serially through the Thermo reader). 677/677 unit tests.
- Inspection: 11 LocalizableElement warnings are #4710's own (DemuxCacheBuilder, SpectraCache,
  Osprey/Program.cs, untouched here): resource strings needed before this goes into #4710.
- Runners: `Run-StellarSearch.ps1` (Osprey on .raw or the tool's mzML), `Run-StellarTool.ps1`
  (tool on the three replicates, then search).

## Direction (Mike, 2026-10-21 22:40): demultiplex the PROFILE, not centroids

Unit-resolution centroids cannot be demultiplexed well: a vendor centroid of overlapping fragments from
different bins is one merged peak. Every searched demux arm up to 22:40 used the centroided acquisitions
(current engine, interp-th, elution); they stay as references, and the centroid-domain SuperOverlap arms
were cancelled. From here on, only the `_profile` acquisitions are demultiplexed, and we centroid ourselves.
**Ion scale (checked):** a Thermo ion-trap vendor centroid's intensity is the profile peak's maximum point
(ratio 1.000 on 30,637 isolated peaks); summed profile points are ~3.4x the height, and for the smallest
peaks summed profile x fill time is ~951: ions = summed profile intensity x fill ms / 1000 (Mike), i.e.
`--fill-time-ions 1000` for profile points (290 for centroid heights). The first profile arms used 380 and
keep it for comparability; later arms use 1000.
Since pwiz bf1933d1a8 / 2a781c91ee the option is the switch `--ions` (Mike: the intensity is ions/s, the 1000 only
converts the fill time from ms to s; precision is set by ions, so use ions): the solve and the written spectra are in
ions, converted last, after Centrix (`IonCountSpectrumList`). Arms run before it used `--fill-time-ions 1000`: the same
solve, output in ions/s. On the 2Th profile slice with Centrix, 13% of MS2 centroids are under 1 ion (0.5% of the
ions) and 38% under 3; median 4.6 ions. MS1: none under 1.

## Ground truth on real data: remultiplexed 2Th (2026-10-21 night)

`Osprey.DemuxTool --remultiplex K` sums each cycle's adjacent narrow windows into K-fold staggered windows
(grouping shifted one window per cycle; ions added through each member's fill time), so any demultiplexer can be
scored against the narrow spectra it should recover. Slice: 2Th profile TR01, spectra 30000-35999 (24 cycles,
RT 6.7-7.6 min; `D:\test\osprey-runs\stellar-demux\synthetic\remux2`), k=2 -> 4 Th windows, 2 Th bins (each
window every 4.8 s: sparser than the real 50%'s 2.4 s). `eval_remux.py`: per (bin, cycle) with >= 50 true ions,
cosine of the demultiplexed spectrum to the true one on a 0.05 Th grid blurred by 0.3 Th.

| k=2 | No demux | Makima per 0.2 Th grid point |
|---|---|---|
| Profile vs true profile | 0.788 | 0.983 (ion-weighted 0.985) |
| Centrix vs Centrix-centroided truth | 0.735 | **0.979** (0.983) |
| My valley-split centroider (EventCentroider.CentroidLinear) vs the same | 0.645 | 0.888 |

- The demultiplexing itself is near-perfect at k=2 on the profile; the stand-in centroider was the weak link,
  and **Centrix** keeps the agreement. The per-grid-point elution fit scored 0.849 (centroided, own centroider)
  against makima's 0.888: makima stays the default.
- **Centrix** (maccoss/centrix, Rust) is installed in WSL (`~/.cargo/bin/centrix`). Its CWT sigma calibration
  is wrong on these data (0.61 Th, snapped to its 200 kTh/s preset); a Gaussian fit to isolated MS2 peaks gives
  **sigma 0.327 Th (FWHM 0.77)** at every m/z (Turbo-like, on a 0.2 Th grid): run with `--sigma-ms2 0.33`.
  It refuses files whose first spectra are centroided (keep MS1 in profile too). ~1 min per 6,000 spectra.
- **k=3 and k=4** (same slice summed into 6 and 8 Th windows stepped 2 Th; `k3.mzML`, `k4.mzML`), makima +
  Centrix vs Centrix truth, median / ion-weighted / p10: k=2 0.979 / 0.983 / 0.877; k=3 0.950 / 0.961 /
  0.706; k=4 0.917 / 0.934 / 0.603 (no demux: 0.735, 0.507, 0.389). Pessimistic on sampling: here a window
  returns every k x 2.4 s (9.6 s at k=4) against 4.7 s in the real SuperOverlap, and the windows are twice as wide.
- Tool code committed: bc76e155e9 (`--remultiplex`), d31553c8ff (`--thin`).

**The joint solve for Stellar (90a692b196, 2026-10-22 ~01:00).** Mike: the Stellar profile demux + centroiding
was meant to be a joint solve borrowing the ZT Scan code, and the centroider Centrix-like (the stand-in
`CentroidLinear` was removed, 6358ddfe99). `IProfileGrid` (`LinearGrid` beside `TofGrid`); staggered
pseudo-sweeps: in each pass the windows not acquired are interpolated (makima, sample by sample, in rates) to the
pass's time, all in ions at the pass's median fill time; `JointDemultiplexer` fits each bin's Gaussian peaks
(sigma 0.33 Th = 1.65 samples). Three ways to use the fit, k=2 truth (scored against truth centroided the same way):

| Output | Score |
|---|---|
| Fitted peaks as centroids (`--joint-fitted`) | 0.944 |
| Measured profile split by the fitted peaks, centroided by the joint solve (default) | 0.954 |
| Makima split, centroided by the joint solve | 0.944 |
| Makima split + Centrix | 0.979 |
| **Joint split + Centrix** (`--joint-profile`, then Centrix) | **0.982** |

And by overlap, vs Centrix truth (median / ion-weighted / p10): joint split + Centrix k=2 0.982 / 0.985 / 0.926,
k=3 0.959 / 0.967 / 0.798, k=4 0.930 / 0.942 / 0.684; makima split + Centrix 0.979 / 0.983 / 0.877, 0.950 /
0.961 / 0.706, 0.917 / 0.934 / 0.603. Joint truth vs Centrix truth (centroiders on clean spectra): 0.981.
- **Architecture:** the joint solve does the demultiplexing (its peak-shaped fit splits the measured profile;
  writing the fit itself carries the interpolated windows' errors - the msconvert lesson again), and **Centrix**
  does the centroiding: it is more stable than the joint solve's single-bin lasso on demultiplexed spectra (0.979
  vs 0.944 on the same makima splits) although the two agree on clean spectra. One centroider = a C# port of
  Centrix (spec M4), for Stellar after the joint split, and to try inside the ZT Scan path.
- Full runs started 2026-10-22 ~01:05 (`-Threads 8`, beside the makima queue): `50pct-profile-joint-centrix`,
  then `super-profile-joint-centrix` (`--profile --joint --joint-profile --ms1 joint --fill-time-ions 1000`,
  then Centrix `--sigma-ms2 0.33`).
- Pipeline now: tool (makima, `--profile --channel-th 0.09 --fill-time-ions 1000`) -> Centrix -> Osprey
  (`Run-StellarTool.ps1 -Centrix`). Arms queued 2026-10-22 00:00: 50% profile, 2Th and 4Th profile through the
  same pipeline (controls), 50% and 4Th thinned 2x, SuperOverlap profile.

**C# Centrix port (ad6f14adca, 0834d6fc03; 2026-10-22).** Mike: port Centrix to C#, for regular centroiding of
profile data and inside the joint solves. New pure library `pwiz_tools/Osprey/Osprey.Centroid` (no references):
`CentrixBasis` (Toeplitz Gram row; Rust's f64::EPSILON truncation, not .NET's double.Epsilon), `NonNegativeLasso`
(coordinate descent, active set, KKT sweep every 10, log-parabola subgrid), `NoiseProfile` (IQR rough, residual +
gap refinement in 20 Th windows), `SignalRegion`, `CentrixCentroider` (two passes, merge within sigma);
`CentrixParams` holds Centrix's defaults. Not ported: sigma calibration (filter-string preset and CWT both misread
the Stellar), so the caller gives sigma. `CentrixTest` ports Centrix's unit tests (681/681 pass).
- **Parity with Rust Centrix** on `k2_jointprof.mzML` (6,000 spectra; `centrix_parity.py` in
  `ai/.tmp/sessions/20261021-stellar`): the same 832,332 centroids, equal counts in every spectrum; 99.98% within
  1e-4 Th and 1e-4 relative intensity (over 99% bit-identical m/z); worst 4e-4 Th and 0.4%, from BLAS vs sequential
  summation of A'y under the 1e-6 absolute stopping tolerance.
- **In the staggered joint solve** (0834d6fc03): each bin's apportioned share per pass is centroided in-process by
  Centrix, in the pass's intensity units (its noise floor of 1 is in an instrument's units, not ions), replacing the
  one-bin joint solve. `--joint` alone now gives what `--joint-profile` + WSL Centrix gave: k=2 truth scored
  identically (median 0.982, ion-weighted 0.985, p10 0.926; `remux2/k2_jointcentrix.mzML`), 38 s for the slice
  against 49 s + 25 s. Settings: `ScanningDemuxOptions.Centrix`; sigma from `--peak-sigma-th`, spacing from the grid.
- **Tool:** `Osprey.DemuxTool --scheme none --centroid centrix` centroids any profile mzML/raw (MS1 sigma
  `--centrix-sigma-ms1`, MS2 `--centrix-sigma`, tuning `--centrix-param Name=Value`); with a demux scheme,
  `--centroid centrix` centroids the output as it is written (MS1 too, e.g. `--joint --centroid centrix`).
- **Cost:** about 10 ms per spectrum on one thread (6,000 spectra: 29 s I/O, ~58 s centroiding). 579k lasso solves,
  347 sweeps each on average, 6% stopping at the 2,000-sweep cap: neighboring basis peaks correlate at 0.91 (sigma
  1.65 samples), so coordinate descent converges slowly. Inside the joint path it runs on the solve threads. An exact
  active-set solve of each region's small active set would be much faster but would differ from Rust where Rust
  stops unconverged; not done.
- Rust Centrix in WSL took 808 s on one 4Th file and 2,329 s on one SuperOverlap file in the queued arms.

**Rust golden, exact solver, and `--centroid centrix` in Osprey (2026-10-22).**
- **Rust golden** (24bcfe51d1): `Osprey.Test/Data/Centrix` holds 30 Stellar profile spectra (14 MS2 + 2 MS1 as
  converted from the `.raw`, 14 joint-split MS2) and the 4,836 centroids Rust Centrix 39370f1 (built in WSL from
  `D:\Dev\centrix`, `~/centrix-golden`) gives them at sigma 0.2 / 0.33. `TestCentrixRustGolden` requires equal counts in
  every spectrum and each centroid within 1e-3 Th and 1%, 99.9% within 1e-4; the port matches to 1e-11 Th, and a 1.7%
  change to the lasso penalty fails it. Over the full 6,000-spectrum slice the port and Rust (old binary and new build
  agree exactly with each other) differ in 0.02% of centroids, by up to 4e-4 Th and 0.4%. Scripts:
  pwiz-ai `scripts/Osprey/Centrix` (slice, golden TSV, parity).
- **Exact solver** (`CentrixParams.Solver = active_set`, `NonNegativeLasso.SolveActiveSet`): Lawson-Hanson active
  set on `min 1/2 b'Gb - (A'y - lambda)'b, b >= 0` with Cholesky solves of the passive set; falls back to coordinate
  descent if a pivot fails. `TestCentrixActiveSet`: on 300 random Stellar-like regions it meets the KKT conditions to
  1e-9, its objective is never worse than coordinate descent's, and it reaches the same optimum from a warm start.
  On the 6,000-spectrum slice: 18-31 s against 64-169 s for coordinate descent, I/O included (loaded machine);
  deterministic. It moves 8.5% of centroids by more than 1e-4 and changes the count in 23% of spectra (net +0.13%):
  the capped solves, and through pass-1 residuals the refined noise and so other regions' penalties. Truth benchmark,
  joint + Centrix, either solver for the output and for the truth: identical to 0.001 at k=2/3/4 (k=2 0.982 / 0.985 /
  0.926-0.927; k=3 0.959 / 0.967-0.968 / 0.798; k=4 0.930 / 0.942-0.943 / 0.683-0.684). The in-process k=3 and k=4
  match the WSL joint + Centrix arms exactly.
- **Peak sigma is not a measurement on these peaks.** Stellar MS2 fits: 3-point log-parabola 0.311, 5-point 0.363,
  linear Gaussian over 5/7/9/11 points 0.36/0.43/0.51/0.61 (the last is Centrix's wavelet value), half-maximum width
  0.40 (overlaps), isolated peaks only 0.25-0.31. MS1: 0.156 (3-point), 0.191 (5-point), 0.20 (half max). Narrow core,
  broad wings: an automatic calibration was written and removed; sigma is a setting (Stellar defaults MS2 0.33,
  MS1 0.2), to be chosen by its effect on IDs.
- **Osprey `--centroid centrix`** (`--centrix-sigma-ms1/-ms2`, `--centrix-solver descent|active-set`): the reader
  opens vendor files without vendor centroiding and centroids profile spectra with Centrix, 512 at a time in parallel
  (`--threads`); centroided spectra pass through. The cache is `<stem>.centrix-<8 hex>.spectra.bin` (and
  `.demux.spectra.bin`), the tag a hash of the settings and `CentrixCentroider.ALGORITHM_VERSION`, set once on
  `ArtifactPaths`, so every reader of the cache finds it and vendor caches are never overwritten. The search hash
  records the settings and the task validity key the descriptor; both empty for vendor, so defaults are unchanged.
  `TestCentrixInOsprey` covers the CLI, the hash, the tag and the reader against the Rust golden.
**Peak-width calibration and documentation (4bb15ee69a, 2026-10-22).** Mike: the sigma is the instrument's resolution,
set by the scan rate; Centrix's table gives each rate's broadest peak, and real peaks are narrower; a wider peak is
usually unresolved species (what Centrix should separate); and it must not be tuned on IDs (those depend on mass
accuracy).
- `CentrixCalibration` / `CentrixSigmaCalibrator` (Osprey.Centroid): scan rate from the profile point spacing (1/30,
  1/15, 1/8, 1/5 Th = 33, 67, 125, 200 kTh/s; broadest FWHM 0.5, 0.6, 0.8, 2.0), not from the filter code; isolated
  intense peaks' FWHM (monotone to half max, apex from the log-parabola, no missing points); sigma = lower quartile /
  2.3548, capped at the broadest; < 20 peaks: the broadest; 3,000 spectra sampled evenly across the run. Default in
  Osprey (`--centrix-sigma-ms1/-ms2` absent), DemuxTool `--centroid centrix`, and the joint solve
  (`LinearPeakSigmaTh` = 0).
- Measured (truth slice): MS2 0.309 Th (FWHM 0.72; cap 0.85), MS1 0.170 (cap 0.25). Lower quartile flat across m/z
  (0.71-0.74 Th), rises with intensity (0.63 weakest fifth, 0.81 strongest). Mode rejected: plateau 0.70-0.85, 6%
  spread at 3,000 peaks vs 0.6% for the quartile. First spectra of a run read 4% wide. Summed windows read wider:
  k=2 0.331, k=4 0.340 (what the joint solve measures). Benchmark cannot tell 0.31 from 0.34: within 0.003.
- **Stellar "Z" (memory `stellar-zoom-scan-annotation`):** every DIA MS2 in these runs is `ITMS + c|p NSI Z ms2`
  (2Th TR01: 142,317 MS2, all Z, all 2 m/z; MS1 `r Full ms`). The Stellar does no zoom scans and uses the Zoom
  annotation for Adaptive RT spectra, but here it is on every DIA scan (method PDF shows no zoom scans). Do not drop
  Z scans; Adaptive RT spectra are 20 or 50 m/z wide, so filter by isolation width > 10 m/z on a Stellar. Not done
  yet (Osprey reader and the mzML written for Skyline); none in these runs.
- **Docs:** `pwiz_tools/Osprey/docs/24-profile-centroiding.md` (Centrix: use, algorithm, sigma, Z, solvers, fidelity,
  caches, open items); `23-demultiplexing.md` "Stellar profile data (linear ion trap)" plus the DemuxTool option rows;
  `14` (the tagged cache), `20` (the CLI). Scripts: pwiz-ai `scripts/Osprey/Demux/eval_remux.py` (truth benchmark),
  `scripts/Osprey/Centrix/fwhm_peaks.py` (width distributions).
- **ID arms, 2Th profile runs read by Osprey** (snapshot `_bin/stellar-centrix-osprey`, fixed sigma 0.2 / 0.33, before
  calibration; precursors TR01 / TR02 / TR03, experiment precursors / peptides / protein groups, 1% FDR):

  | Arm | Precursors per run | Experiment |
  |---|---|---|
  | 2Th acquired centroided (`2Th-centroid`, the instrument's centroids) | 37,596 / 36,455 / 36,971 | 42,232 / 37,875 / 5,717 |
  | 2Th profile, vendor centroiding on read (`2th-profile-vendor`) | 16,307 / 16,112 / 16,383 | 19,483 / 17,992 / 3,712 |
  | 2Th profile, `--centroid centrix` (`2th-profile-cs-descent`) | 23,703 / 23,206 / 22,848 | 27,761 / 25,669 / 4,613 |
  | 2Th profile, `--centroid centrix --centrix-solver active-set` (`2th-profile-cs-active`) | 23,457 / 23,147 / 22,644 | 27,673 / 25,591 / 4,603 |
  | 2Th profile, DemuxTool + Rust Centrix in WSL (`2th-profile-centrix`) | 23,510 / 4,769 / 4,924 | 23,382 / 21,600 / 3,926 |

  Centrix gives +42% over vendor centroiding of the same profile files; the two solvers are within 0.3%. Both are
  far below the instrument-centroided acquisition (-35%): open question whether the profile acquisitions are
  themselves worse or the centroiding is (compare matched spectra across the paired runs). The Rust Centrix arm's
  TR02/TR03 collapse (4.8k) is that arm's alone (its TR02 calibration: 23,852 target matches vs 32,514 TR01); not
  investigated. Times: vendor arm 1,349 s, descent 3,032 s (Centrix read 12-20 min a file, with other runs loading
  the machine), cache `...TR01.centrix-f3aa677d.spectra.bin`.
- **Profile arms through DemuxTool + Rust Centrix in WSL** (queues finished 2026-10-22; precursors per run, experiment):

  | Arm | Precursors per run | Experiment |
  |---|---|---|
  | 4Th acquired centroided | 24,277 / 24,552 / 24,931 | 28,133 / 25,422 / 4,720 |
  | 4Th profile + Centrix | 16,846 / 17,285 / 16,838 | 20,137 / 18,766 / 3,798 |
  | 4Th profile + Centrix, thinned 2x | 14,521 / 15,208 / 14,859 | 18,031 / 16,828 / 3,448 |
  | 50% profile, makima + Centrix | 21,329 / 21,144 / 20,605 | 25,180 / 23,276 / 4,267 |
  | 50% profile, joint + Centrix | 21,604 / 22,415 / 20,690 | 25,464 / 23,504 / 4,273 |
  | 50% profile, makima + Centrix, thinned 2x | 4,611 / 14,628 / 15,988 | 19,264 / 17,891 / 3,324 |
  | SuperOverlap profile, makima + Centrix | 236 / 190 / 357 | 459 / 433 / 191 |
  | SuperOverlap profile, joint + Centrix | 10,847 / 21,203 / 10,463 | 22,069 / 20,534 / 3,812 |

  50% demultiplexed (21-22k a run) comes close to 2Th profile + Centrix (23.5k) and well above 4Th profile (16.8k).
  Several WSL-Centrix runs collapse for no reason seen yet (super makima all runs; super joint TR01/TR03; 50% thin2
  TR01; 2Th TR02/TR03): the C# in-process arms have shown none. Every profile arm is below its centroided acquisition.
- **The profile files hold no centroids** (2026-10-22, RawFileReader probe `ai/.tmp/sessions/20261021-stellar/
  probe_centroid_api.ps1` on 2Th profile TR01 scan 30052): packet LinearTrapProfile, 5,000 points; centroid stream
  (with or without reference peaks), label data, simplified centroids and Scan.FromFile's CentroidScan all empty. The
  vendor arm's peaks are CommonCore `Scan.ToCentroid` computed at read (identical to the cache), about 609 a spectrum,
  off the profile apexes (209.49 vs 209.6) and with peaks where the profile is near baseline; Centrix 168 a spectrum,
  cosine to the profile 0.96-0.985 vs 0.88-0.94. Mike: ITMS profile data does store centroids; how he sees them (FreeStyle?
  MSFileReader/XRawfile?) is the open question. MS2 calibration: centroid acquisition mean -0.093 SD 0.216 (39,668
  matches); profile vendor +0.093 SD 0.273 (2,649); profile Centrix +0.146 SD 0.309 (20,920).

**The Stellar profile m/z axis is 0.55 Th low (2026-10-22): the profile arms' loss and the SuperOverlap 2-of-3
failure.** Scripts in `ai/.tmp/sessions/20261021-stellar`: `fragment_mz_error.py` (observed - theoretical for detected
peptides' b/y ions at their apex scans, per centroid set), `profile_fragment_offset.py` (the same on the profile itself,
no centroider), `probe_trailer.ps1`.
- On the 2Th profile TR01 profile (1,062 peptides, 17,544 fragments), fragments peak at -0.44 to -0.60 Th from theoretical
  at every m/z (200-1200). Vendor centroids and Centrix inherit it; the M+1 isotope then sits at +0.45, so error modes
  flip from -0.55 to +0.45 above 600 m/z. Instrument centroids (centroid acquisition): modes -0.07 to -0.37, robust SD
  0.28, 92% within 0.5 Th; profile-derived: robust SD 0.63, 63-71% within 0.5. Same scan, same window: base peak
  524.80 (profile) vs 525.295 (centroid acquisition). Trailers identical; no offset field. Likely a scan-rate
  dependent shift the instrument corrects when it centroids but not in the stored profile (0.5 Th = 2.5 us at
  200 kTh/s; untested).
- Osprey's calibration starts at +/-0.5 Th (unit default) and corrects only a mean: it sees mostly the isotope at
  +0.45 and the tail of the monoisotopic peak, measures about +0.15, and corrects the wrong way. Which peak it latches
  onto decides the file: SuperOverlap joint + Centrix TR02 (21.2k precursors) matches fragments at -0.53 (mono) below
  800 m/z, median error -0.30; TR01 and TR03 (10.8k, 10.5k) match at +0.41 (isotope) from 400 m/z up, median +0.30.
  Pass-1 calibration: TR01/TR03 8.4k / 8.3k fragment matches, mean +0.18; TR02 16.9k, mean +0.09.
- Fix options: correct the profile axis at read (a per-scan-rate offset, or estimated per file), and/or make Osprey's
  unit-resolution calibration robust (initial window past 0.55, offset from the intensity-weighted mode, not the
  mean). Mike suggested opening the initial tolerance to about 0.6.
**Root cause of the WSL-Centrix collapses: Rust Centrix mispairs spectra after an empty one (2026-10-22).** Mike: the
mass axis cannot move 0.5 Th between adjacent runs, so it is our processing. Confirmed:
- The raw profile axis (RawFileReader, no ProteoWizard, `raw_profile_offset.ps1` on 1,500 peptides common to all three
  runs) is the same in SuperOverlap TR01 / TR02 / TR03: fragments at -0.42 to -0.56 Th in every m/z range, within 0.02.
- The demultiplexed profile is right in all three. But the Rust Centrix output of TR01 at spectrum 278858 is exactly what
  Rust Centrix gives spectrum 278859 alone (and 278859 holds 278860's, ...): every spectrum carries the next one's
  centroids. The slip begins at the first empty spectrum (SuperOverlap TR01 index 20675, 0 points; 2Th TR02 index 754;
  `find_centroid_slip.py`); TR02 SuperOverlap and 2Th TR01 have none. Cause: `ProfileReader::next` in Centrix's
  `src/io/reader.rs` skips empty spectra (`Ok(None) => continue`) while the passthrough writer writes every spectrum,
  so results shift by one per empty spectrum. In the demultiplexed files the next spectrum is the next 1 Th bin, whose
  precursors include a 2+ peptide's M+2, so its fragments carry heavy isotopes: the +0.41 matches, calibration on the
  wrong peaks, half the IDs.
- Affected: every WSL-Centrix arm whose input has empty spectra (SuperOverlap joint TR01/TR03, SuperOverlap makima, 2Th
  TR02/TR03, likely 50% thin2 TR01). Not affected: the in-process C# Centrix (centroids each spectrum in place).
- Fix: SuperOverlap rerun in-process (`super-profile-joint-cscentrix`: `--profile --joint --fill-time-ions 1000
  --centroid centrix --centrix-param Solver=active_set`, measured sigma; snapshots `_bin/stellar-cscentrix-*`). For Rust
  Centrix: return an empty spectrum instead of skipping it, or pair results with spectra by native id (not filed yet).
- The -0.55 Th profile axis offset itself is real and the same in every run; separate from this bug.
**In-process rerun read sigma too narrow (2026-10-22, pwiz 88fef2dff3).** `super-profile-joint-cscentrix` gave 10.2k /
10.8k / 11.5k precursors (13.9k experiment), consistent across runs but low: the calibrator measured MS2 sigma 0.213 Th
(picker) / 0.230 (joint), 2-5 centroids per spectrum. Two causes, measured with Osprey's own `AddPeakWidths` on whole
raws read by RawFileReader (`raw_calibrator_check.ps1`; `raw_peak_widths.ps1` for the split by points above half max):
- 26% of profile points are zeros; peaks whose half-max walk ends on a zero are a few ions' spikes (an ion trap ejects
  each ion at one instant), a third of the intense maxima. Counted: sigma 0.266 (2Th TR01) / 0.285 (SuperOverlap TR01);
  left out: 0.305 / 0.310, the same as with the zeros removed. Now left out.
- The calibrator stopped at 3,000 peaks, all from the run's first minutes (sample indices ascend): 0.174 / 0.213 with
  spikes. Cap removed; every one of the 3,000 sampled spectra is used (10-15k peaks).
- MS1 "0 isolated peaks" in the DemuxTool's joint branch is expected: MS1 is vendor-centroided there before the
  calibrator sees it, and the Centrix MS1 picker passes centroided spectra through.
- Also limiting: the earlier search calibrated MS2 to mean -0.21 Th (pass 2, ~5-6k matches): the +/-0.5 window sees the
  tail of the monoisotopic peak at -0.55, so after the +0.21 correction the M+1 (+0.67) is inside the 0.73 tolerance.
- Runs: `super-profile-joint-cscentrix-s033` (sigma fixed 0.33, old snapshot), `super-profile-joint-cscentrix-tol06`
  (the 0.213 output searched with `--fragment-tolerance 0.6`); next `_bin/stellar-cscal2-*` (88fef2dff3, measured).
## Plan

1. **Baselines, current #4710 code** (`Run-StellarSearch.ps1`, Osprey on the `.raw`, unit resolution):
   acquired 2Th and 4Th; `--demux auto` on 50% and SuperOverlap; the same on the profile acquisitions
   read through vendor centroiding. Precursors and peptides at 1% FDR, replicate CV. The target:
   50% demultiplexed (2 Th bins, 23 ms fills) at or above acquired 2Th (2 Th, 11.5 ms fills).
   Also measure chromatographic peak width, which decides step 3.
2. **Centroid domain, unit resolution:** fragment channels in Th (linear m/z histogram, tolerance
   from the peak width); ions per spectrum from fill time (counts per ion as above); the isolation
   edge measured from the SuperOverlap data (1 Th steps) if the quadrupole's edge is soft.
3. **k=4 in time. Goal (Mike): each 1 Th bin represented at the full sampling frequency**, one
   demultiplexed spectrum per bin per pass (~3.1 s): 1 Th selectivity at a 4 Th acquisition's cycle
   time. Every bin is observed every pass, through a different window each pass; only each *window*
   repeats every 12.5 s. The current engine interpolates each overlapping window's own series
   (12.5 s apart) to the target's time to get the shares, which misses an apex a few seconds wide.
   Instead: take bin b's value at pass p from the window that observed it in pass p, and use the
   other passes only for how that observation splits among its four bins, over the nearest +/-1-2
   passes (one source bin per fragment: no split at all; several: a local fit, spec §4.3 in
   spirit). Gate on synthetic k=3/4 runs with known 1 Th elution profiles (each bin's series
   recovered at every pass, apex included), then SuperOverlap against acquired 4Th and 2Th.
   Note MS1 comes once per 12.5 s in SuperOverlap.
4. **Profile domain:** (a) per-grid-point demux (§5.4c) on the 0.2 Th grid, then centroid;
   (b) the joint demux and centroiding (§5.4d), generalizing `JointDemultiplexer`/`TofGrid` to a
   linear grid with the ion-trap peak and the staggered design with its time model. Argument for
   profile on unit resolution: a centroid of overlapping fragments from precursors in different
   bins moves with the mixture, so it is not a stable channel across windows; a grid point is.
   Compare with the vendor centroids of the same profile runs and with the centroided acquisitions.
5. **Into `--demux auto`** for Stellar profile `.raw`: solve as the run is read, cache only the
   demultiplexed centroids (as planned for ZT Scan).

## Progress log

- 2026-10-21: branch from #4710's head. Fixed two build breaks the port's layout move left on
  #4710 (uncommitted): `Osprey.DemuxTool.csproj` still pointed at `pwiz-sharp\pwiz\src\...`, and
  `System.Security.Cryptography.Xml` 8.0.4 now fails NuGet audit (master's #4841 pins 8.0.5).
  Snapshots `D:\test\osprey-runs\_bin\stellar-base-vendor` (Osprey) and `stellar-base-demuxtool`.
  Inspection dumps and scripts: `D:\test\osprey-runs\stellar-demux\inspect`,
  `ai/.tmp/sessions/20261021-stellar` (scheme.py, profile.py, itcheck.py, ionlevels.py, profileevents.py).
