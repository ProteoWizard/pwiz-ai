# TODO-20260923_osprey_demux.md

## Branch Information
- **Branch**: `Skyline/work/20260923_osprey_demux`
- **Base**: `Skyline/work/20260612_net8_port` (stacked on PR [#4619](https://github.com/ProteoWizard/pwiz/pull/4619))
- **Created**: 2026-09-23
- **Status**: In Progress. M0 and M1 (staggered DIA) in review by Brendan (#4710, requested 2026-09-25).
  M6 ZT Scan ([#4714](https://github.com/ProteoWizard/pwiz/issues/4714)): the per-channel demultiplexer is on
  the follow-on branch below, evaluated through `Osprey.DemuxTool`, not yet wired into `--demux`. M2-M5 not started.
- **Follow-on branch**: `Skyline/work/20260926_osprey_ztscan_persweep`, stacked on #4710's head (ab5c54c416), pushed
  2026-09-27 at d6366f4493 (8 commits; no PR yet; run /code-review before opening one). Its algorithms are
  documented in `pwiz_tools/Osprey/docs/22-demultiplexing.md`, "The per-channel demultiplexer".
- **In flight (2026-09-27, `ai/.tmp/sessions/20260923-osprey-demux/model/Run-Followups.ps1`)**, DIA-NN arms under
  `D:\test\osprey-runs\ztscan\`:
  - `diann\W_wiff_scanning`: A1 .wiff, `--scanning-swath` (DIA-NN's proper ZT Scan baseline), ~09:30;
  - `diann\W_wiff_scanning_3runs`: the three .wiff files, ~13:00;
  - `slices\diann\full_cs_framed31_A1`: full A1 framed:3:1 without the floor (layout vs floor), ~14:00;
  - `slices\diann\full_raw_plain`: the three acquired mzMLs, plain, the CV baseline for
    `slices\diann\full_cs_centered5` (CV 0.139), ~17:00.
- **Module**: `osprey`
- **GitHub Issue**: [#4711](https://github.com/ProteoWizard/pwiz/issues/4711)
- **PR**: [#4710](https://github.com/ProteoWizard/pwiz/pull/4710) (M0 + M1)
- **Worktree**: `D:\Dev\pwiz-osprey-demux`

## Objective

Demultiplex overlapping-window DIA inside Osprey. Read vendor raw files directly (pwiz-sharp),
demux to the narrowest bins, and write a demuxed spectra cache that the rest of the pipeline
searches. Source spec: the lab's `osprey-demux-spec.md` (Aug 2026), copied verbatim into
[TODO-20260923_osprey_demux/osprey-demux-spec.md](TODO-20260923_osprey_demux/osprey-demux-spec.md). The review of that spec and
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
- **Upcoming Orbitrap data (Mike, 2026-09-27):** today's staggered runs are 50% overlap (k = 2). Planned
  experiments use 33% and 25% overlap (k = 3, 4), the offset window sets acquired in successive cycles
  rather than adjacent within one. This is in the spec: §4.1-4.2 (interleave, and interpolation error by
  points per FWHM per window for k = 2-4), G4.1 (every Phase 1 gate rerun at k = 3 and 4), and §13 item 8
  (the useful k is platform-specific; 25% on an Orbitrap may recover little in the AGC-limited regime).
  What it means for the per-channel staggered path:
  - each window recurs once per rotation of k sets, so interpolation spans the whole rotation, and each
    window has k times fewer points per peak (the spec's cliff is between 3 and 2 per FWHM);
  - bins narrow to width / k, and each bin is covered by k windows, like ZT Scan but with sharp edges,
    so bins stay the right columns of A;
  - cycle detection by window repetition treats the whole rotation as one cycle, which works but needs
    a synthetic k = 3 / 4 alternate-cycle test;
  - it reopens per-time interpolation vs the separable model (a source does not move in m/z) for the
    Orbitrap, which only nearly tied at k = 2.

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

- [x] **M0**: search the Orbitrap staggered raw file (undemuxed) and the pwiz-demuxed mzML; record IDs, FDP and window counts; fix what Osprey mishandles on demuxed input (first-cycle window detection, at minimum).
  - The undemuxed raw is refused by the demux-off guard, as intended; msconvert's mzML was searched (see "Osprey search" below).
  - First-cycle window detection fixed in b54a34a642 (all distinct windows, every cache).
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
  - [ ] Metrics JSON (`--demux-metrics`): deferred to [#4713](https://github.com/ProteoWizard/pwiz/issues/4713);
    for now the summary and the timing gate go to the log.
  - [ ] Streaming demux (input ring buffer of ~8 cycles, streaming cache writer): needed for Astral and
    profile data, where input plus demux output resident together (~2.7x input) is too much.
  - [x] Gates: G7.1 vs msconvert explained (median cosine 0.999 msconvert-like, 0.997 default); timing gate 0.10-0.13 of parse; IDs/FDP above the msconvert baseline.
  - [x] `regression.ps1 -Dataset Stellar` all PASS at d179d98fec, and again at 366f7d0220 (2026-09-25).
  - [x] Tests added 2026-09-25 (after a `pw-test-review`): `TestDemuxRealisticSynthetic` (3 ppm jitter, k=3, variable width, moving elution),
    `TestDemuxEclipseFixture` (in-repo 3-min, 8-window EV13 slice + msconvert's demux + golden, `Osprey.Test/Data/Demux`), `TestDemuxPipelineWiring`.
  - [x] `docs/22-demultiplexing.md`: pipeline flow, files, algorithm, msconvert differences, validation, limitations.
  - [ ] Later: an optional Panorama-hosted regression dataset (e.g. `osprey-demux-eclipse-v1.zip` in `/MacCoss/software/@files/perftests/`)
    and an opt-in `EclipseDemux` entry in `regression.ps1`, outside `-Dataset All`. Mike (2026-09-25): save it for later; in-repo tests for now.
    The upload is Mike's or Brendan's.
  - [ ] Unit-resolution channel tolerance (fixed 10 ppm today); decide with Stellar data (M5).
- [ ] **M2**: MSX. Every precursor, whole-cycle A, periodicity check; port Thermo `Multi Inject Info` onto the PRECURSOR in pwiz-sharp `SpectrumList_Thermo`.
- [ ] **M3**: Astral staggered (variable width).
- [ ] **M4**: Osprey.Centroid (centrix port), `--centroid centrix` on any profile input (separate branch).
- [ ] **M5**: Stellar profile demux (§5.4c, then §5.4d).
- [ ] **M6**: ZT Scan, with streaming demux: [#4714](https://github.com/ProteoWizard/pwiz/issues/4714). See "ZT Scan (M6)" below.

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
- `D:\demux-test-data\Amodei-Q-ExactiveHF`: still downloading as of 2026-09-23.
- `D:\demux-test-data\ZenoTOF8600-ZTScan`: complete 2026-09-25, three replicates; see "ZT Scan (M6)".
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
- **Which is right needs truth.** The Osprey search is the real test: Mike is providing an
  Eclipse-appropriate library, since the Astral-tuned one would mispredict RT here.

### Osprey search, Eclipse EV13 + EV14 (2026-09-25)

Setup:
- Library: `D:\demux-test-data\Eclipse-staggered\carafe_spectral_library+decoy+entrapment.tsv` (13.6 GB, Carafe).
  - 7.04 M entries, with library decoys (`decoy_` prefix) and 1:1 shuffled entrapment (`_p_target`, r = 0.9999).
  - Decoys were paired to targets by composition, 100%.
- Flags: `--resolution hram --fdr-level precursor --protein-fdr 0.01 --decoys-in-library --fdrbench <dir>/fdrbench.tsv`.
- Each search used its own spectra cache (`--cache-dir`); the libcache was copied between dirs.
- Run dirs: `D:\test\osprey-runs\eclipse-staggered\search-{msconvert,osprey-default,osprey-msconvertlike}`.
- Comparator: `ai/scripts/Osprey/Compare/Compare-DemuxSearches.py`.
- Wall time: Osprey-default 32 min; msconvert mzML 51 min.

`output.stats.tsv` (precursors / peptides / proteins):

| search | EV13 | EV14 | Experiment |
|---|---|---|---|
| msconvert demux (mzML) | 35,006 / 30,436 / 3,064 | 34,277 / 29,686 / 3,056 | 38,465 / 33,199 / 3,202 |
| Osprey default demux (raw) | 36,244 / 31,439 / 3,097 | 35,409 / 30,609 / 3,098 | 39,409 / 33,959 / 3,235 |

First-pass run-level precursors at 1% (the metric least affected by the SVM C pick): msconvert 28,670 / 28,481;
Osprey default 29,260 / 28,726 (+1.5%); Osprey msconvert-like 29,372 / 29,441 (+2.9%).

Experiment level, q <= 0.01, over the precursor m/z both searches scored (< 1000.70):

| search | target precursors | FDP | target peptides | FDP |
|---|---|---|---|---|
| msconvert | 38,411 | 0.28% | 33,145 | 0.33% |
| Osprey default | 39,298 (+2.3%) | 0.27% | 33,883 (+2.2%) | 0.32% |
| Osprey msconvert-like | 39,328 (+2.4%) | 0.30% | 33,957 (+2.4%) | - |

- The two Osprey configurations are indistinguishable at this noise level, and both beat msconvert: the gain is in
  implementation details (candidates: neighbors by index vs by window/RT, off-center interpolation points, NNLS non-convergence), not isolated.

- Both have 54 entrapment hits, so FDR control is conservative and equal.
- Peptide overlap: 31,098 shared; 2,785 only with Osprey; 2,047 only with msconvert.

**Defect found (M0, fix on this branch):**
- Osprey's first-cycle window detection drops the top bin, [1000.70, 1006.70), of msconvert-demuxed mzML: the search logged 101 windows vs 102.
- That bin is covered only by the offset set's last window, so it first appears after the cycle has wrapped.
- The m/z restriction above removes its effect from the comparison: msconvert loses 0 IDs to it and Osprey-default 57.
- Fix: on plain caches too, take all distinct windows. First check that the regression caches' distinct windows equal their first-cycle windows, so the goldens are unaffected.

### Stagger consistency, Eclipse (2026-09-24, library-free)

Method: `ai/scripts/Osprey/Compare/Measure-StaggerConsistency.py`.
- Each bin is sampled alternately through its two parent windows.
- Zigzag = sum |x_i - time-weighted mean of its two neighbors| / sum x over the apex window
  (+/- 6 samples).
- Events: the top 300 apexes per bin, found in msconvert's output and measured identically in
  every input.
- Lower means the two parent windows agree better. Curvature and counting noise are common to
  all inputs, so the differences between inputs are the allocation.
- Outputs: `D:\test\osprey-runs\eclipse-staggered\stagger-consistency-EV1{3,4}-allbins.txt`.

EV13, all bins (30,598 events):

| input | median | mean | p90 | per event lower than msconvert |
|---|---|---|---|---|
| msconvert | 0.2210 | 0.3044 | 0.551 | - |
| Osprey default (covered_bins + makima) | 0.2109 | 0.2793 | 0.481 | 55.7% |
| Osprey msconvert-like (truncated + natural3) | 0.2125 | 0.2869 | 0.505 | 50.7% |
| covered_bins + natural3 | 0.2120 | 0.2814 | 0.487 | 51.4% |
| truncated + makima | 0.2117 | 0.2853 | 0.501 | 54.7% |

EV14 (30,599 events) replicates it:
- msconvert: median 0.2195, p90 0.545;
- default: median 0.2093, p90 0.482, lower in 56.0% of events;
- msconvert-like: median 0.2110, p90 0.499.

Readings:
- The defaults are best in every m/z region.
- covered_bins mostly trims the tail; makima raises the per-event win rate.
- Osprey's msconvert-like setting is already more self-consistent than msconvert (p90 0.505 vs
  0.551). Probably pwiz's index-based choice of block rows and interpolation stencil (with
  possible duplicate rows of one window) rather than Osprey's time-based choice.
- The 1st and last bins are covered once, so they have no alternation; about 0.51-0.61 for all.

## Data needed (from Mike)

- Orbitrap staggered raw files, the pwiz-demuxed mzML, and the msconvert command line used
- The matching library/FASTA
- The MSX raw file and the Astral staggered data
- ~~The ZT Scan data~~: received 2026-09-25 (`D:\demux-test-data\ZenoTOF8600-ZTScan`)
- ~~For M6 validation, a DIA-NN report~~: not needed; we run DIA-NN ourselves (`C:\DIA-NN\2.3.2\diann.exe`,
  which has `--scanning-swath`; older versions 1.8.1-2.2.0 alongside)
- For G6.1-G6.3: matched ZT Scan vs Zeno SWATH acquisitions of one sample, or a ZT Scan three-proteome mix
- Later: the Stellar profile staggered data

## ZT Scan (M6, #4714)

Data: `D:\demux-test-data\ZenoTOF8600-ZTScan`, `250814_ZTScan_100spd_A_{1_A1,2_D1,3_G1}` (A_3_G1 is the file the
net8 port characterized as `D:\test\ABI\ZTscan`). Per replicate:

| File | Size | What it is | Needed |
|---|---|---|---|
| `.wiff` | 40 MB | Legacy Analyst container (OLE compound file): method, sample, index | this or `.wiff2` |
| `.wiff2` | 78 MB | SCIEX OS container (encrypted database; `-journal` is its empty rollback journal) | this or `.wiff` |
| `.wiff.scan` | 8.6 GB | The spectra, shared by both containers | yes |
| `.wiff.dia` | 5.7 GB | Apparently DIA-NN's converted `.dia` format of the run | no |
| `.wiff.dia.quant` | 32 MB | Apparently DIA-NN's per-run quant file (records the `.wiff.dia` path) | no (validation) |
| `.timeseries.data` | 24 KB | SCIEX OS sidecar; not referenced by the SDKs ProteoWizard ships | no |

Evidence for the DIA-NN attribution: the naming (`<run>.dia`, `<run>.dia.quant`) and the path string in the quant file;
neither Clearcore2 nor the wiff2 SDK contains `.dia`, `dia.quant` or `timeseries.data`. Mike (2026-09-27): these came
from a collaborator and are not needed; our DIA-NN arms read the .wiff themselves.

What is already known (TODO-20260612_net8_port.md, "2026-08-20/24: Sciex ZT Scan"):
- 430 experiments x 699 cycles = 300,570 spectra: experiment 0 `TOF MS (400-900)`, 1..429 `TOF PI` quad bins.
- Bins tile [392.760634, 899.778995] exactly, 1.181866 Da steps, the same position in every cycle.
- Measured transmission ~Gaussian, FWHM ~10 bins (11.8 Da) vs method Q1 width 5.9 Da; apex within +/-1 bin of the
  nearest reported center (9 of 10), so no lag calibration observed. Per-bin scan start 2.010 ms apart.
- Per-bin CE is interpolated from the ramp endpoints (`ZtScanBin`, PR #4598); the linear ramp is an assumption.
- Mode flag: `.wiff2` `GroupName == "ZTScan"`; `.wiff` sample field `Is ZT Scan`.
- Native ids `sample= period= cycle= experiment=`, no `scan=`; Osprey does not stage the wiff2 plugin yet.

Plan: follow the spec's unified model (§2): ZT Scan is `y = A x` with `A` from the fitted kernel, events gathered
within one cycle, the shared solver. (An earlier "(b) search the reported bins undeconvolved" option was withdrawn
2026-09-25 as a departure from the spec.) The gap analysis and order of work are in
[TODO-20260923_osprey_demux/spec-status-2026-09-25.md](TODO-20260923_osprey_demux/spec-status-2026-09-25.md).

Decisions (with Mike, 2026-09-25):
- ~~**Output bin width is the encoded bin, 1.18 Th**~~. Revised the same evening: Mike said it is fine not to
  map each precursor to one 1.18 Th bin, and that about 3 x 1.18 Th centered on a bin would do. The modeling
  (`TODO-20260923_osprey_demux/modeling-2026-09-26.md`) found one bin not recoverable per channel under counting
  noise, and 3 bins centered on each bin close to the best a perfect demux allows at that width.
- **Product ions only: no coupling across fragment channels (spec §6.5 is out).** Reverses an earlier same-day
  decision. Grouping fragments into precursor components is the DIA-Umpire step, and the MS2 signal is far more
  sensitive than a precursor-level grouping. Each fragment channel is solved on its own, across the events that
  transmit it and, where needed, the cycles of its elution (§4.3).
- **The msconvert mzML is centroided** (`peakPicking vendor`, `centroid spectrum`), but every centroid is written
  with a zero-intensity point one TOF sampling step (~8 ppm) either side, so two thirds of the points are zeros.
  Checked on six spectra of A1 cycle 350: no two nonzero points adjacent, exactly 2 zero flanks per centroid, and
  ~90% of centroid m/z values off the sampling grid (interpolated). Channel extraction must drop the zeros.
- **Validation against DIA-NN** runs locally (`--scanning-swath`, 2.3.2), on all three replicates.

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
- **The demux-off refusal was swallowed on a cache hit** (found by `TestDemuxPipelineWiring`). `EnsureSpectraCache` called
  `Resolve` inside the try that guards reading the cache, so the refusal became a warning and a re-parse, which then
  failed with a NotSupportedException on the stand-in source. Fixed by resolving outside the try.
- **Round-off shares wrote spurious peaks.** The exactness runs had 60 peaks at round-off level in bins without the
  fragment. Shares below 1e-6 of the channel total are now dropped; `ALGORITHM_VERSION` 2 rebuilds older demux caches.
- **Eluting-case leak is inherent, and ranks the interpolants.** With moving elution (sigma 2.5 cycles), intensity put in
  bins without the fragment: makima 0.033%, PCHIP 0.072%, then natural 3-point and linear; makima max error 0.77%.
- **On the Eclipse slice the msconvert-like setting is closer to msconvert in median cosine** (0.9991 vs 0.9987), not in
  the fraction at 0.95 (93.4% vs 93.6%); the fixture test asserts the median only.
- **The regression datasets are non-overlapping**, so the demux-off guard cannot trip on the goldens:
  - Stellar is 125 x 4 Th windows, centers 4.0018 apart;
  - Astral is 167 x 3 Th windows, touching within about 1 mTh, well under the 0.2 Th merge width.
  - The data is at `C:\Users\maccoss\Downloads\Perftests\osprey-testfiles-mzML-v2`.

## Progress log

- 2026-09-23: reviewed the spec; plan approved; created the worktree/branch.
- 2026-09-23: Osprey.Demux library, tests and pipeline wiring written; demux tests green. Full pre-commit gate running.
- 2026-09-23: committed d179d98fec; Stellar regression all PASS (Release build via Build-Osprey.ps1, then `-NoBuild`,
  because regression.ps1 builds with the VS 2022 toolset, which cannot load the .NET 10 SDK).
- 2026-09-24: G7.1 and stagger consistency on Eclipse EV13/EV14; b54a34a642 fixed first-cycle window detection.
- 2026-09-25: Osprey searches with the Carafe library (+2.3% precursors at equal FDP); test review; tests 1-3, fixture,
  wiring fix, share floor and docs/22 committed as 366f7d0220; opened PR #4710 and issue #4711; Stellar regression
  PASS on 366f7d0220; copied the spec into this TODO's folder.
- 2026-09-25: Copilot review on #4710, both findings real, fixed in 711d4ced1c: the demux descriptor joins every task
  validity key (scores were reused after a settings change rebuilt the demux cache); half-open fragment channels (a peak
  on a split edge counted twice; algorithm version 3). Its path-trigger nit did not apply (triggers match pwiz_tools/Osprey/.*).
- 2026-09-25: `/code-review high` on #4710: 7 findings. Fixed in ab5c54c416: a stale demux cache whose source and
  .spectra.bin are gone is now refused at start-up (header-only `SpectraCache.CheckHeader`); Stage 6 no longer
  logs a rebuild it does not do; scheme detection uses `IsolationWindows`; header truncation tests. Deferred:
  descriptor in the key for non-overlapping `auto` runs; input + output resident (streaming); peaks dropped
  when the target bins' share is zero (count it in #4713). Opened #4713 (metrics JSON).
- 2026-09-25: demux thread scaling on EV13 (cache hit, `ai/.tmp/sessions/20260923-osprey-demux/Measure-DemuxThreads.ps1`,
  logs in `D:/test/osprey-runs/eclipse-staggered/thread-scaling`): NOT CLEAN - another session's 16-thread Stellar
  regression ran throughout. Raw: 1/2/4/8/16 threads = 125.4/94.6/38.9/38.6/17.6 s. Re-run on a quiet machine.
- 2026-09-25: requested Brendan's review of #4710 (TeamCity green on ab5c54c416, 0 unresolved threads). Opened #4714
  (ZT Scan + streaming); ZenoTOF data inventoried (see "ZT Scan (M6)").
- 2026-09-25: back to the spec. Decisions with Mike: product ions only (no §6.5 coupling); ZT Scan output about
  3 x 1.18 Th centered on a bin; the msconvert ZT Scan mzML is centroided with zero flanks.
- 2026-09-25/26 (night session): synthetic modeling of both instruments and a real-data ZT Scan slice test with
  DIA-NN. Report: [TODO-20260923_osprey_demux/modeling-2026-09-26.md](TODO-20260923_osprey_demux/modeling-2026-09-26.md).
  - Per-channel demux cuts fold-change error by more than half in a realistic background. Eclipse is best with
    the separable model; ZT Scan with per-sweep NNLS, Poisson weights, and 3- or 5-bin output.
  - Real ZT Scan slice: own-bin output -50% identifications, 3 bins -12%, 5 bins equal to raw.
  - The accuracy gain needs known-ratio data to confirm.
- 2026-09-26: transmission calibrated from identified precursors: a symmetric trapezoid, nearly m/z-independent.
  Signal start and end locate precursors. Next steps agreed with Mike (report, "Next steps"):
  - Track 1: a 5-6 Th demux file layout, then full runs with DIA-NN and Osprey.
  - Track 2: combine weak signal across sweeps.
  - Then the C# port, and a request for known-ratio data.
  - Waiting for the CarafeSharp testing to finish.
- 2026-09-26/27 (night session 2): the C# port on local branch `Skyline/work/20260926_osprey_ztscan_persweep` (not
  pushed), stacked on #4710: commits c7f20cdd74, 0f217a3331, f275c565aa, 6c5cb2f5ad, 4fe286e574, 90924fb009,
  0dbd3641f3.
  - One strategy for both instruments: per-channel NNLS with Poisson weights. ZT Scan writes the solved
    intensities in a framed:3:1 layout; staggered data apportions the observed peaks.
  - Eclipse, Osprey search: 40,009 precursors at 0.26% FDP (msconvert 38,411, #4710 39,355).
  - ZT Scan slice, DIA-NN: framed:3:1 and centered:5 about +5% over raw at raw CV; tiled layouts lose at edges.
    A 1-ion output floor adds 3-7% more at CV 0.113-0.119; framed:3:1 with it writes 0.23 GB per slice.
  - Full A1, centered:5: +1.7% over raw, with gains where dense and losses early in the gradient.
  - Osprey.DemuxTool reads .wiff2 and .raw directly, vendor-centroided. The SCIEX SDK read (about 8-9 ms
    per spectrum) is now the tool's floor; the solve runs under it.
  - Morning of 2026-09-27: full A1 framed:3:1 with the floor lost 1.2% against plain (losses above
    600 m/z), so the layout is open again. DIA-NN reads ZT Scan only from .wiff (not .wiff2), and its
    README says ZT Scan must not go through mzML; the .wiff search is the proper DIA-NN baseline.
  - The algorithms are documented in `pwiz_tools/Osprey/docs/22-demultiplexing.md` on the branch
    (d6366f4493); the measurement scripts are in `ai/scripts/Osprey/Demux`.
  - Report: [modeling-2026-09-26.md](TODO-20260923_osprey_demux/modeling-2026-09-26.md), "Night 2".
