# TODO-20260923_osprey_demux.md

## Branch Information
- **Branch**: `Skyline/work/20260923_osprey_demux`
- **Base**: `Skyline/work/20260612_net8_port` (stacked on PR [#4619](https://github.com/ProteoWizard/pwiz/pull/4619))
- **Created**: 2026-09-23
- **Status**: In Progress. Core library (M1) being written; M0 blocked on data paths from Mike.
- **Module**: `osprey`
- **PR**: (pending)
- **Worktree**: `D:\Dev\pwiz-osprey-demux`

## Objective

Demultiplex overlapping-window DIA inside Osprey. Read vendor raw files directly (pwiz-sharp),
demux to the narrowest bins, and write a demuxed spectra cache that the rest of the pipeline
searches. Source spec: the lab's `osprey-demux-spec.md` (Aug 2026). The review of that spec and
the approved plan are summarized below.

## Decisions (with Mike, 2026-09-23)

- First end-to-end target: **Orbitrap staggered**. Raw files plus the pwiz-demuxed mzML are the reference.
- The Sciex data is ZT Scan DIA. MSX, Astral staggered, ZT Scan and Stellar profile data arrive as-is, with no reference.
- Centrix (`maccoss/centrix`, Rust) gets ported to C#. Osprey should be able to use its own centroiding on ANY profile data.
- New code lives in Osprey as pure-library projects (`Osprey.Demux`, later `Osprey.Centroid`) that depend only on `Osprey.Core`. They can be lifted into pwiz-sharp later.
- Demux is opt-in (`--demux off` by default) until the G6 ID/quant/FDR gates pass.
- RT interpolation defaults to **makima** (modified Akima). This is interpolation, not imputation; missing centroids stay zero-filled. The simulation is below.
- §7 SIMD work waits for the M1 timing gate (demux wall time vs parse wall time). Scalar double first, with per-geometry cached factorization, tier-0/1 shortcuts, and thread parallelism across groups.
- Determinism is designed in, not free:
  - no shared mutable state across groups;
  - fixed iteration order;
  - ties broken toward the lowest index;
  - a fixed NNLS iteration cap.
- Cross-platform output is held to the 1e-9 gate, not byte identity.
- Undemuxed staggered or MSX input is out of scope, as expected. With demux off, Osprey should detect such a scheme and stop with a message pointing at `--demux`.

## Architecture

```
raw/mzML -pass 1-> <stem>.spectra.bin (v4, unchanged)
                 + <stem>.acquisition.bin (per MS2: IT, all precursor sub-windows,
                                           per-precursor fill time or NaN, analyzer, profile flag)
spectra.bin + acquisition.bin -pass 2-> <stem>.demux.spectra.bin
                 (v4 body/index/footer reused; distinct magic + descriptor: demux version,
                  parameter hash, scheme kind, k, source-cache fingerprint)
```
- One processing descriptor (centroider, demux, versions, parameters) is hashed into the processed-cache header and into `SearchIdentity`.
- Hooks:
  - `ScoringTaskShared.EnsureSpectraCache`, between `LoadAllSpectra` and `SaveSpectraCache`;
  - `SpectrumFileReader.AddSpectrum`, to capture IT, every precursor and the profile flag;
  - `SpectraWindowIndex`, to take all distinct keys rather than the first cycle.
- The v1 solver mirrors the pwiz overlap structure (7x7 local block, target centroids as channels,
  apportioned output), so G7.1 can diff against pwiz. §6.5 anchored coupling and §4.3
  acquired-axis fitting come after v1, each gated against it.

## Milestones

- [ ] **M0**: search the Orbitrap staggered raw file (undemuxed) and the pwiz-demuxed mzML; record IDs, FDP and window counts; fix what Osprey mishandles on demuxed input (first-cycle window detection, at minimum). BLOCKED on data paths.
- [ ] **M1**: Osprey.Demux v1 for stepped staggered data, plus the demux cache, `--demux`, `SearchIdentity`, metrics, and the demux-off guard.
  - [x] Library (`pwiz_tools/Osprey/Osprey.Demux`):
    - `DemuxSchemeDetector`: boundary-union bins; the overlap factor is width-weighted, so DIA with a 1 Th margin overlap is NOT a stagger.
    - `NnlsSolver`: Lawson-Hanson on the normal equations; unconstrained fast path when full rank; deterministic.
    - `RtInterpolator`: makima, PCHIP, pwiz 3-point natural, linear.
    - `OverlapDemultiplexer`: the `covered_bins` (default) and `truncated_slice` (pwiz) block modes; `apportioned` (default) and `solution` output modes.
  - [x] Synthetic unit tests (`Osprey.Test/DemuxTest.cs`), all passing:
    - NNLS vs brute-force enumeration over 3000 random systems (G1.3);
    - interpolant exactness and apex-bias ordering;
    - scheme detection: k=2, k=3, jitter, variable width, margin overlap, a late window;
    - exact staggered round trip (G1.1, G1.2, G1.4);
    - the truncated_slice bias demonstrated;
    - threads 1 vs 4 identical;
    - demux cache round trip and refusals;
    - search hash unchanged with demux off.
  - [x] Wiring:
    - `--demux {off|auto}`, `OspreyConfig.DemuxMode`, a `SearchIdentity` term only when on;
    - `.demux.spectra.bin` (distinct magic plus descriptor, v4 body) and the `DemuxSettingsChanged` rejection;
    - `DemuxCacheBuilder` in `EnsureSpectraCache` and Stage-6 `LoadSpectraForRescore`;
    - `SpectraWindowIndex` takes all distinct windows on demuxed caches;
    - Program's missing-source acceptance;
    - the demux-off guard (throws on an overlapping scheme).
  - [ ] Metrics JSON (`--demux-metrics`); for now the summary and the timing gate go to the log.
  - [ ] Gates: goldens unchanged with demux off (run `regression.ps1 -Dataset Stellar`); G7.1 vs pwiz-demuxed mzML explained (needs data); timing gate on real data.
  - [ ] Unit-resolution channel tolerance (fixed 10 ppm today); decide with Stellar data (M5).
- [ ] **M2**: MSX. Every precursor, whole-cycle A, periodicity check; port Thermo `Multi Inject Info` onto the PRECURSOR in pwiz-sharp `SpectrumList_Thermo`.
- [ ] **M3**: Astral staggered (variable width).
- [ ] **M4**: Osprey.Centroid (centrix port), `--centroid centrix` on any profile input (separate branch).
- [ ] **M5**: Stellar profile demux (§5.4c, then §5.4d).
- [ ] **M6**: ZT Scan. Stage the wiff2 plugin in Osprey; empirical kernel (§2.4).

## Spec review notes (for the lab)

**Contradictions:**
- There are three competing solvers (§6.1-6.4, §4.3, §6.5), and §13 phases only the first.
- §9.1 is superseded by §9.1c.
- §9.1c pass 2 lacks IT and multi-precursor metadata in v4.
- Profile demux cannot be cache-to-cache.
- The rank-deficiency claim holds only for local blocks.
- §2.3's kernel notation is off.
- *(Withdrawn: §6.2 on the Orbitrap is consistent. The open question is the floor, 6-10 ions measured vs 13-27 extrapolated.)*

**Corrections from the code:**
- pwiz interpolates with a 3-point natural cubic spline, not monotone Hermite.
- pwiz apportions the observed intensity, so mass balance is 1.0 by construction.
- MSX variable fill has no working reference: C++ puts `MultiFillTime` on the scan while the demux reads the precursor, and pwiz-sharp never ported the parsing.
- In ZT Scan each Q1 bin is its own spectrum with a nominal ~1.18 Da window, while true transmission is ~11.8 Da.

**Osprey facts:**
- MSX is read with `precursors[0]` only.
- First-cycle window detection silently drops later windows.
- Scan-number Option A is safe.
- The window list is persisted in `.calibration.json`.
- Isotope envelopes straddle narrow bins (measure with G4.16 first).

### Interpolation simulation (2026-09-23)
Setup: EMG peaks, k=2 target at the half-cycle offset, 600 trials per cell. The numbers are mean
apex error as a % of peak height, with the % of values that came out negative in brackets.

| pts/FWHM | pwiz 3-pt natural | PCHIP | makima | linear |
|---|---|---|---|---|
| 6 | -0.6 | -1.1 | -0.4 | -1.9 |
| 4 | -1.5 | -2.6 | -0.6 | -4.1 |
| 3 | -3.2 (5%) | -4.5 | -1.3 | -6.9 |
| 4, 100 ions | -2.0 (1%) | -2.8 | -1.6 (0.1%) | -4.5 |

- A global natural spline rings under noise, with 11-38% of values going negative.
- Log-Gaussian interpolation biases area on tailing peaks.

## Coordination

- `TODO-20260923_osprey_carafe_export` also edits `SpectrumFileReader.AddSpectrum` and plans a
  `<stem>.run-info.json` sidecar next to `.spectra.bin`. Converge on one per-run acquisition sidecar.
- `TODO-20260908_osprey_parallel_files_cache_sizing` (local branch on MACS2) sizes inputs from
  `.spectra.bin`. A demux cache changes that size.

## Data (on this machine)

- `D:\demux-test-data\Eclipse-staggered`: 2 Orbitrap Eclipse staggered runs (`Ecl_2022_0705_Beads_EV13/14_SAXN_12mz_*`), each as `.raw` plus the msconvert-demultiplexed `.mzML` (same stem).
  - The scheme is 12 Th windows at k=2, giving 6 Th bins covering about 394-1006 m/z.
  - msconvert command (per Mike): `--zlib --simAsSpectra --filter "peakPicking vendor msLevel=1-" --filter "demultiplex optimization=overlap_only massError=10.0ppm"` (plus titleMaker), with ProteoWizard 3.0.26100.
  - By the pwiz defaults that is: truncated 7x7 block, 3-point natural-spline RT interpolation, apportioned output.
- `D:\demux-test-data\Amodei-Q-ExactiveHF` and `D:\demux-test-data\ZenoTOF8600-ZTScan`: still downloading as of 2026-09-23.
- No library came with Eclipse. The first comparison (spectrum-level G7.1) needs none. For ID/FDR, the human SkylineAI library in the Astral regression set covers only 400-902 m/z of the 394-1006 range.

## G7.1 plan (spectrum level, no library)

1. `--task SpectraCache --demux auto` on each `.raw` gives Osprey's `.demux.spectra.bin`, with default settings.
2. The same with `OSPREY_DEMUX_BLOCK=truncated_slice OSPREY_DEMUX_INTERPOLATION=natural_three_point` gives the msconvert-like configuration, which should nearly reproduce msconvert.
3. `--task SpectraCache` on each msconvert `.mzML` gives a plain `.spectra.bin` of msconvert's demux.
4. Use separate cache dirs per variant, because the raw and the mzML share a stem.
5. `ai/scripts/Osprey/Compare/Compare-DemuxSpectra.py` pairs the spectra by (parent RT, bin center) and reports cosine, intensity ratio and exclusive-peak intensity.
6. Step 2 vs 3 validates the reimplementation; step 1 vs 3 sizes the deliberate differences. The logs also give the timing gate (demux vs parse).

Reading `.raw` needs a build with `-VendorReader` (`IAgreeToVendorLicenses`).

### G7.1 results, Eclipse EV13 (2026-09-23)

Setup:
- Run dirs are under `D:\test\osprey-runs\eclipse-staggered\{msconvert,osprey-default,osprey-pwizlike,osprey-covered-natural3,osprey-truncated-makima}`.
- The exe is the snapshot at `D:\test\osprey-runs\_bin\demux-m1-vendor`.

Osprey's own run:
- Scheme: 101 windows into 102 bins of 6.000-6.003 Th, 2-fold.
- Spectra out: 158,700 for EV13 and 159,000 for EV14, identical to msconvert.
- All 158,700 spectra pair one-to-one with msconvert's.
- **Timing gate:** demux 18.8 s and 36.3 s (16 threads) vs raw parse 191 s and 286 s, a ratio of 0.10-0.13, so no SIMD is needed.

Versus msconvert (cosine over the union of peaks, per demultiplexed spectrum):

| Osprey variant | median | >= 0.99 | >= 0.95 | < 0.80 |
|---|---|---|---|---|
| truncated_slice + natural_three_point (msconvert-like) | 0.9989 | 83.2% | 95.3% | 1.2% |
| truncated_slice + makima | 0.9984 | 80.1% | 94.8% | 1.2% |
| covered_bins + natural_three_point | 0.9976 | 73.3% | 92.0% | 1.9% |
| covered_bins + makima (default) | 0.9969 | 70.5% | 91.5% | 2.0% |

- The block mode is the main source of difference from msconvert; the interpolant is minor. Total intensity agrees to 0.2% in every variant.
- Where the msconvert-like residual lives: across the interior the per-bin p05 is 0.93-0.98. It is worst at the top of the range (986-1004 Th, p05 0.76-0.86). There pwiz clamps its 7-bin slice and its 7 nearest rows leave the last bins with no measurement, so the NNLS solution is not unique and solvers legitimately differ.
- Inputs check: msconvert's demux summed back per parent vs Osprey's undemuxed raw read gives a median cosine of 1.0000, and Osprey's input carries 0.1% more intensity. That fits msconvert dropping peaks whose solution is zero in both bins; no difference in centroids is evident.
- **Open: which is RIGHT needs truth.** Candidates:
  - a library-free stagger-consistency metric: each bin is sampled alternately from window A and window B parents, so a biased demux shows as an A/B sawtooth in the bin's XICs;
  - a search with a library covering 394-1006 m/z.

## Data needed (from Mike)

- Orbitrap staggered raw files, the pwiz-demuxed mzML, and the msconvert command line used
- The matching library/FASTA
- The MSX raw file and the Astral staggered data
- The ZT Scan data (a TODO cites `D:\test\ABI\ZTscan`; `D:\test` is absent on this machine)
- Later: the Stellar profile staggered data

## Findings during M1

- **pwiz's truncated block is biased.** It cuts the edge window's row to a 7-bin slice, but that
  row still carries signal from its bin just outside the slice. In a staggered ladder the error
  alternates in sign into the target bins whenever a channel is present in several consecutive
  bins; common fragments (y1, immonium, b2) are the usual case.
  - `covered_bins` keeps every covered bin as a column: the model is exact, and non-negativity
    resolves the one-dimensional null space when two adjacent bins lack the channel.
  - `TestDemuxStaggeredRoundTrip` demonstrates both: covered_bins exact to < 1e-5, truncated error > 1%.
- **Apportioned output hides solver error** wherever the target's other bin solved to zero: all
  the observed intensity goes to one bin. pwiz's G2.7 mass balance is 1.0 by construction, and
  errors show only in `solution` output.
- **Staggered data needs no acquisition sidecar.** A window's bins are co-isolated in one
  contiguous isolation with a single fill, and intensities are rates, so the design matrix is 0/1.
  Injection time matters only for noise weights (deferred). The sidecar moves to M2 (MSX).
- **The regression datasets are non-overlapping**, so the demux-off guard cannot trip on the goldens:
  - Stellar is 125 x 4 Th windows, centers 4.0018 apart;
  - Astral is 167 x 3 Th windows, touching within about 1 mTh, well under the 0.2 Th merge width.
  - The data is at `C:\Users\maccoss\Downloads\Perftests\osprey-testfiles-mzML-v2`.

## Progress log

- 2026-09-23: reviewed the spec; plan approved; created the worktree/branch.
- 2026-09-23: Osprey.Demux library, tests and pipeline wiring written; demux tests green. Full pre-commit gate running.
