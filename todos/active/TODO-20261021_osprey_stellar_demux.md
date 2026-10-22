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
  ppm only (10 ppm), as docs/23 already says is not right for Stellar centroids.

## Plan

1. **Baselines, current #4710 code** (`Run-StellarSearch.ps1`, Osprey on the `.raw`, unit resolution):
   acquired 2Th and 4Th; `--demux auto` on 50% and SuperOverlap; the same on the profile acquisitions
   read through vendor centroiding. Precursors and peptides at 1% FDR, replicate CV. The target:
   50% demultiplexed (2 Th bins, 23 ms fills) at or above acquired 2Th (2 Th, 11.5 ms fills).
   Also measure chromatographic peak width, which decides step 3.
2. **Centroid domain, unit resolution:** fragment channels in Th (linear m/z histogram, tolerance
   from the peak width); ions per spectrum from fill time (counts per ion as above); the isolation
   edge measured from the SuperOverlap data (1 Th steps) if the quadrupole's edge is soft.
3. **k=4 in time:** at k=4 a window set comes back every 12.5 s, so interpolating each window to
   the target's time (makima) cannot follow a peak a few seconds wide. Fit each bin's elution as a
   smooth function of time over all observations (spec §4.3), gated first on synthetic k=3/4 data
   with known peak widths, then on SuperOverlap against 50% and the acquired methods.
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
