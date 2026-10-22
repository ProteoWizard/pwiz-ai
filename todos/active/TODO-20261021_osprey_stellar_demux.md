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
- Pipeline now: tool (makima, `--profile --channel-th 0.09 --fill-time-ions 1000`) -> Centrix -> Osprey
  (`Run-StellarTool.ps1 -Centrix`). Arms queued 2026-10-22 00:00: 50% profile, 2Th and 4Th profile through the
  same pipeline (controls), 50% and 4Th thinned 2x, SuperOverlap profile.

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
