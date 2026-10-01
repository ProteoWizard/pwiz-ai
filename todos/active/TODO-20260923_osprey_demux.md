# TODO-20260923_osprey_demux.md

## Branch Information
- **Branch**: `Skyline/work/20260923_osprey_demux`
- **Base**: `Skyline/work/20260612_net8_port` (stacked on PR [#4619](https://github.com/ProteoWizard/pwiz/pull/4619))
- **Created**: 2026-09-23
- **Status**: In Progress. M0 and M1 (staggered DIA) in review by Brendan (#4710, requested 2026-09-25).
  M6 ZT Scan ([#4714](https://github.com/ProteoWizard/pwiz/issues/4714)): the per-channel demultiplexer is on
  the follow-on branch below, evaluated through `Osprey.DemuxTool`, not yet wired into `--demux`. M2-M5 not started.
- **Follow-on branch**: `Skyline/work/20260926_osprey_ztscan_persweep`, stacked on #4710's head (ab5c54c416),
  pushed to 1c94fd6a57 (2026-09-29; 22 local commits since, through eb9e893553 on 2026-09-30),
  checked out on SCARFELL in `C:\Dev\pwiz-osprey-demux`. No PR yet; run /code-review before opening one. Its
  algorithms are documented in `pwiz_tools/Osprey/docs/22-demultiplexing.md`, "The per-channel demultiplexer".

## Handoff (2026-09-27): moving the work to another machine

Read this first on the new machine. Everything needed is on the remotes; nothing below depends on
the old machine except the in-flight results listed last.

**Where things are**
- Code: the follow-on branch above. Its commits, oldest first:
  - c7f20cdd74 the per-sweep weighted ZT Scan demultiplexer, histogram channels, layouts, the tool;
  - 0f217a3331 the staggered path, vendor `.wiff2` / `.raw` reading;
  - f275c565aa the sparse Gram build, the incremental NNLS factor and warm start (~3x faster solve);
  - 6c5cb2f5ad apportioned staggered output (this is what beat msconvert on Eclipse);
  - 4fe286e574 framed layouts; 90924fb009 `--apportion` and `--min-out`;
  - 0dbd3641f3 read the next batch while solving; d6366f4493 the doc;
  - 89401fdf71 `--position-mz`; 1517e4803c `--source-positions` and `--source-l1`;
  - d2f9811fd4 the doc updated with them.
- The algorithms, options, and every result table: `pwiz_tools/Osprey/docs/22-demultiplexing.md` on the
  branch. The modeling and the day's experiments: `TODO-20260923_osprey_demux/modeling-2026-09-26.md`,
  "Day of 2026-09-27".
- Scripts, kernels, and machine setup (the data to copy with sizes, building the tool, DIA-NN's SCIEX
  DLLs, pinned DIA-NN settings): `ai/scripts/Osprey/Demux/README.md`. The scripts there are copies of
  the session's. Their data roots come from `DEMUX_DATA_ROOT` and `DEMUX_RUN_ROOT`, defaulting to the
  old machine's `D:\demux-test-data` and `D:\test\osprey-runs`. On the new machine (SCARFELL,
  2026-09-27) the data root is `Z:\demux-test-data` and the run root is local, `C:\temp\osprey-runs`;
  the old machine's run folder is moving to `Z:\test\osprey-runs`, and finished arms go there too.
- The old local branch `Skyline/work/20260925_osprey_ztscan_demux` (WIP ba0b22546b, the superseded
  pooled-sweep version) exists only on the old machine and is not needed.

**Where the results stand**
- Eclipse (Orbitrap staggered, 50% overlap): apportioned per-channel demux gives 40,009 precursors at
  0.26% FDP, against msconvert's 38,411 and #4710's 39,355. Done unless the k = 3 / 4 data changes it.
- ZT Scan identifications (updated 2026-09-28, see the night's section below): on whole runs,
  centered:7 `--position-mz` with DIA-NN pinned finds 28,171 / 28,188 / 28,729 peptides (FDP 0.89-1.00%)
  against 26,475 / 27,174 / 27,635 (1.01-1.07%) for DIA-NN's scanning mode on the `.wiff`: +3.7-6.4% per run,
  22,197 against 21,341 in all three runs, 35,140 against 33,370 in any (`ids_summary.py`). Precursors
  +4.0-6.6%. **Mike's criterion (2026-09-28): detect as many peptides as DIA-NN on the `.wiff` or more;
  somewhat worse precision is acceptable. Met.** The demux files at the slice's 14 / 17 ppm give fewer
  (27,506 / 27,776 / 27,858 peptides, `slices\diann\full_c7pz_scarfell_ma14`): keep 17 / 19 on whole runs.
  Running: the `.wiff` searched with the same pinned settings (`ztscan\diann\W_wiff_scanning_3runs_pinned`).
- ZT Scan quantitation is the open gap: CV 0.119 against 0.112 acquired and 0.088 for DIA-NN on the
  `.wiff` (was 0.135 with DIA-NN's own settings and centered:5).
- `--source-positions` (each channel's sources placed once per block, each sweep solved over just
  those) is the answer being tested for that gap. In the Python prototype it moved the share of an
  identified precursor's fragment signal landing in its own bin from 0.52 to 0.69.

**In flight on the old machine at handoff** (outputs under `D:\test\osprey-runs\ztscan\` there; rerun
on the new machine if they did not finish, with the scripts named):
- Slice, `--source-positions --position-mz`, centered:7 and centered:5: arms
  `slices\diann\cs_centered7_posmz_src` and `cs_centered5_posmz_src`
  (`Run-CsSlices.ps1 -Layouts centered:7,centered:5 -Extra '--position-mz --source-positions' -Suffix _posmz_src`).
  Compare with `cs_centered7_posmz` (2,770 / 2,950 / 2,959, CV 0.095 on the slice).
- Whole runs, centered:7 `--position-mz`, three replicates, DIA-NN settings pinned: arm
  `slices\diann\full_cs_centered7_posmz_fixed` (`Run-FullC7Posmz.ps1`). Compare its CV with the table above.
- The results of both are recorded below if they finished before the move.

**Results that landed after the handoff was written**
- Slice, centered:7 `--position-mz --source-positions`: 2,391 / 2,423 / 2,359 targets, FDP 0.75-1.07%,
  CV 0.130 on 1,504 shared, against 2,770 / 2,950 / 2,959 and CV 0.093 without source positions.
  **Source positions as implemented are worse on both counts**, although the prototype's placement
  check improved. Suspects:
  - the drop rule (sources under 5% of their channel's total are discarded, so a weak precursor sharing
    a fragment channel with a strong one loses that fragment; the placement check saw only identified,
    mostly strong precursors; the file is 13% smaller);
  - DIA-NN chose an 8 ppm fragment tolerance for this arm, against 12-14 ppm for the others.
  The pinned re-searches (arms `cs_centered7_posmz_src_pinned` and `cs_centered7_posmz_pinned`, with
  `--window 6 --mass-acc 14 --mass-acc-ms1 17`) and the centered:5 source-positions arm were stopped
  unfinished to free the old machine; rerun them on the new one (`Search-Slices.ps1 -Extra '<pinned>'`
  on the existing slice files, or `Run-CsSlices.ps1` to remake them).
- **Whole runs, centered:7 `--position-mz`, DIA-NN settings pinned (`--window 6 --mass-acc 17
  --mass-acc-ms1 19`): 31,512 / 31,506 / 32,117 targets, FDP 0.79-0.89%.** That is 4-7% more than DIA-NN's
  scanning mode on the `.wiff` (29,552 / 30,285 / 30,882, FDP 0.90-0.96%) and 13-15% more than the
  acquired data. CV on the 18,035 precursors all four arms found in all three runs: 0.119, against
  0.089 for scanning mode, 0.112 acquired, 0.135 for centered:5 with DIA-NN's own settings. 24,600
  precursors are quantified in all three runs (scanning mode 23,589). **Identifications now beat
  DIA-NN's scanning mode; quantitative precision is the remaining gap.** Files:
  `D:\test\osprey-runs\ztscan\full\cs_centered7_posmz` (about 16 GB each) on the old machine.

The old machine's slice re-searches were stopped unfinished; its whole-run search finished (above), but
its whole-run mzML were not copied to Z: (logs only). SCARFELL reran the whole-run arm from scratch and
got exactly the same numbers (below), and ran the slice arms again, pinned.

## Night of 2026-09-27/28 on SCARFELL: the lasso, and the centroiding gap

Goal (Mike): close the ID and quant gap to DIA-NN reading the `.wiff` itself; try the L1 / lasso. Full
timeline with every number: `ai/.tmp/night-session-budget.md` on SCARFELL. Results are in the doc on the
branch ("Sparsity: the lasso", "Centroiding and the TOF grid"); scripts in `ai/scripts/Osprey/Demux`.

**Commits on the follow-on branch, local on SCARFELL, not pushed:** a62aa3f782 `--sweep-l1`,
`--sweep-l1-refit`, `--min-source-fraction`; 2506acc4de `--sweep-l1-z`; ba9fb73506 `--block-support-z`;
8b479d8ac4 `EventCentroider`, `--centroid events`, `--profile`; 474c740a1c MS2-only event centroiding
and the doc; dcc2cd4cb9 and 045c71d0c9 the whole-run and joint results in the doc. Each code commit passed build, 611-612 unit tests and a
clean inspection. With every new option off, A1's slice is byte-identical to d2f9811.

**Setup and baseline**
- SCARFELL reproduces the old machine exactly: centered:7 `--position-mz` on the slice gives 2,770 / 2,950 /
  2,959 (arm `cs_centered7_posmz_scarfell`).
- **Pin DIA-NN on the slice too** (`--window 6 --mass-acc 14 --mass-acc-ms1 17`): 2,909 / 3,067 / 3,094,
  CV 0.093, against DIA-NN scanning mode on the acquired slice 2,768 / 2,807 / 2,958, CV 0.100. The demux
  already beats scanning mode on the acquired slice data on both counts.
- Compare arms precursor by precursor (`paired_cv.py`): the median CV moves with DIA-NN's own choices
  (pinning alone: paired +0.0015, 46.5% improved, with 9% quantity shifts).

**The lasso does not help** (all on the slice, pinned, paired against the baseline; details in the doc):
fixed L 2 / 6, z-scaled L z 2 / 3 (relaxed), block-level support z 2 / 3, and `--source-positions` with no
drop fraction (2,593 / 2,818 / 2,543). None improves IDs or CV. Why: a fixed L in the Poisson-weighted fit is
a z threshold that varies with the background; per-sweep selection flickers positions between sweeps (CV
up); per-block selection removes the flicker but pushes left-out signal onto neighbours (about -10% IDs).
`--counts-per-ion 50` is neutral too.

**Where the gap really is: the data DIA-NN reads from the `.wiff`**
- New arm `full_raw_scanning_3runs` (DIA-NN `--scanning-swath` on the acquired whole-run mzML). Whole
  runs, CV on 19,656 shared: `.wiff` scanning 0.090, mzML scanning 0.103, mzML plain 0.113. The scanning
  algorithm is 0.010 of the 0.023; the `.wiff` data path is 0.013, uniform across RT, m/z and abundance.
  IDs: `.wiff` 29,552 / 30,285 / 30,882, mzML scanning 29,373 / 29,872 / 30,485 (about 1%).
- SCIEX vendor centroiding (msconvert's and our reader's) drops every one-sample 100-count profile event
  (19.5% of profile intensity; part of them are fragment ions, 1.55x above chance), and a kept centroid
  carries 0.25 of its profile peak's area. Calibration is not the difference (within 0.3 ppm).
- **The ZT Scan TOF profile is one exact grid**, uniform in sqrt(m/z) (step 9.786595e-5; 9.8 ppm per sample
  at 400 m/z, 7.4 at 700), identical across spectra, sweeps and runs. TOF peak sigma 1.2-1.5 samples.
  Spec §5.4c-d's precondition holds on ZT Scan.
- Crude event centroids (`--centroid events`) without demux: CV better (0.093 vs 0.097, 53.5% improved),
  IDs worse, and worse demultiplexed; MS1 was centroided the crude way too (DIA-NN wanted 31-38 ppm MS1
  tolerances). Reruns with MS2-only event centroids were in flight at the end: arms `raw_events_ms2`
  and `c7pz_events_ms2` (controls `raw_plain`, `cs_centered7_posmz_scarfell_w6`, DIA-NN `--window 6`).
- First joint prototype (`joint_prototype.py`, A kron B NNLS, Gaussian B), placement on 341 identified
  precursors: 0.48 / 0.84 own / +/-1 without L1 and 0.49 / 0.85 (median own 0.35) with the z = 2 Poisson L1,
  against 0.51 / 0.87 (0.34) for the channel solve on vendor centroids and 0.43 / 0.81 for per-sample profile
  demux (§5.4c). Per-sample is clearly worst, as §5.4d argues.
- **Whole runs, centered:7 `--position-mz`, DIA-NN pinned** (`full_c7pz_scarfell`, `--window 6 --mass-acc 17
  --mass-acc-ms1 19`): **31,512 / 31,506 / 32,117 targets at 0.79-0.89% FDP, 4.0-6.6% more than DIA-NN's
  scanning mode on the `.wiff`** (29,552 / 30,285 / 30,882, 0.90-0.96%); 24,600 precursors in all three runs
  against 23,589, identical to the old machine's `full_cs_centered7_posmz_fixed`. **The ID gap is
  closed.** CV 0.119 on 17,948 shared (acquired 0.112, mzML scanning 0.102,
  `.wiff` 0.088; centered:5 unpinned was 0.134). By abundance the demux equals the acquired data at the top
  quartile (0.093) and is 0.010 worse at the bottom, growing with m/z: the solve's counting noise on weak
  signal. The `.wiff`'s lead (0.013-0.018 in every quartile) is the data path, which the demux inherits.

**The joint solve in C# (started 2026-09-28 afternoon)**
- 9a3575e52f `JointDemultiplexer` + `TofGrid` + `--joint` / `--joint-z` / `--joint-relaxed`; f2b837f317 12x faster.
  Model y_i[k] = sum_j A_ij sum_q B[k - q] beta_j[q] on the exact TOF grid, Gaussian B (sigma by m/z), Poisson
  weights (first from the data smoothed by B, then reweighted once), z-scaled L1 (default z = 2). Solver:
  block coordinate descent per grid point, exact NNLS over that point's active positions (plain coordinate
  descent could not separate neighbouring positions' near-collinear transmission columns: 21% of a source
  stayed in neighbours after 50 passes), active set grown from the factored gradient, overlapping 2,048-sample
  chunks. Tests: exact recovery, near-isobaric fragments of two precursors 2 samples apart resolved, noise.
- Input: profile dumps (`Osprey.DemuxTool --raw --profile`); the slice dumps are
  `C:\temp\osprey-runs\ztscan\profile\<stem>_slice_profile.mzML` (sweeps 243-375 as 0-132, 475-725 m/z, 5.4 GB).
- Output on sweep 301: 7,326 peaks per spectrum (channel 5,885), 3.2x the ions (full profile areas), 33% of
  peaks under one ion (channel 63%).
- 81c153dfc2 (2026-09-28 evening) 5.4x faster: one A1 sweep, precursors 560-600, one pinned P-core, 46.6 s -> 8.6 s.
  Zero coefficients leave the active set after each pass (blocks 15 -> 3 positions); only grid points with
  data within a peak's reach are solved (exact: a coefficient covering no data only adds misfit), and again
  only when a neighbour moved; coefficients stored grid point by grid point; 48-bin blocks by default with
  `--joint` (16-bin blocks solve 36 positions to keep 16); block steps over-relaxed by 1.7. Tuning switches:
  `--solve-profile`, `--joint-param Name=Value`, `--group-bins`. Benchmark: `sessions/.../Bench-Joint.ps1`.
- **Convergence matters:** against the same sweep solved to convergence (hundreds of passes; plain and
  over-relaxed agree to |log2| 0.0004), the old default's peaks were off by ion-weighted mean |log2 ratio|
  0.08-0.11 (mass moved between neighbouring positions); now 0.055. Final objectives are NOT comparable
  across runs (the reweighted pass's weights come from each run's own first solution); compare peaks
  (`sessions/.../joint_diff.py`).
- Why it costs more than the spec suggests: per iteration it is as cheap as §5.4d says, but the problem is
  badly conditioned twice over, neighbouring grid points 0.87 correlated (TOF peak ~3 samples wide) and
  neighbouring positions sharing ~90% of their bins (10.5 Th window over 1.14 Th bins). 88% of the ions sit
  in interacting groups of 51-200 coefficients, whose largest position holds only 31-42% of their ions.
  Cost now: ~77 thread-s per 430-bin sweep, ~1-1.5 h per run (699 sweeps) at 10 threads; the channel solve
  is ~7 thread-s per sweep. Next idea if the joint solve is worth it: decide the positions once per block
  of sweeps (12 sweeps pooled), then solve each sweep's amplitudes on that fixed support.
- **Whole-run wall time is the SCIEX library, not disk:** SSD 2.1 GB/s write, 1.6 GB/s read; NAS 265 MB/s.
  Per spectrum, one thread: profile decode 2.6 ms, vendor centroiding +4.5-8.5 ms; opening a run 80 s.
  The channel pipeline's 6 h per file = one serial vendor read+centroid (2.6 s per sweep) plus the writer
  asking again for every header, which re-centroided each spectrum (2.7 s per sweep; fixed in ff7e429fb4,
  byte-identical output), all three runs at once on a busy machine. Next: parallel vendor reads.
- ff7e429fb4 also fixed a confound in the joint arms: MS1 passed through as profile (83k points against
  32k vendor centroids) and MS2 were labelled profile. The joint path now takes vendor MS1 centroids from a
  vendor file; run it from the `.wiff2` (copies in `C:\temp\demux-test-data\ZenoTOF8600-ZTScan`), not the
  profile dumps. Arm `slices\c7_joint` (old solver, dump input) is confounded.
- **Is the joint solve worth it? Yes, on the slice (night of 2026-09-28/29).** Arms from the `.wiff2`
  (`sessions/.../Run-JointWiffEval.ps1`: sweeps 247-371, precursors 500-700, MS1 vendor-centroided like the
  control), DIA-NN as the channel controls `cs_centered7_posmz_scarfell_w6` / `_pinned`
  (`sessions/.../Compare-JointArms.ps1`, `ids_summary.py`, `paired_cv.py`, `abundance_cv.py`):

  | arm (`--window 6`) | precursors A1 / D1 / G1 | FDP | peptides all / any | CV (shared) |
  |---|---|---|---|---|
  | channel, vendor centroids | 2,885 / 2,890 / 3,027 | 0.35-1.31% | 2,197 / 3,743 | 0.094 |
  | joint 81c153dfc2 (`c7_joint_v4`) | 3,396 / 3,407 / 3,426 | 0.47-1.22% | 2,522 / 4,386 | 0.119 |
  | joint + 12 ppm cross-position merge (`c7_joint_v4_m12`) | 3,334 / 3,318 / 3,427 | 0.64-1.13% | 2,469 / 4,334 | 0.098 |
  | **joint + sigma merge (12f7d84d04, `c7_joint_v4_sig`)** | **3,431 / 3,578 / 3,332** | 0.66-0.84% | **2,536 / 4,452** | **0.094** (channel 0.094) |

  Pinned (14 / 17 ppm): joint 3,513 / 3,421 / 3,336 against 2,909 / 3,067 / 3,094; with the sigma merge
  3,330 / 3,652 / 3,328, peptides 2,516 / 4,457, CV 0.093 against the channel's 0.096 on 2,064 shared (paired
  -0.004, 54% better): **the joint solve with the sigma merge beats the channel solve on IDs and precision.** The merge arm's CV by
  abundance quartile is 0.129 / 0.108 / 0.093 / 0.073 against the channel's 0.118 / 0.103 / 0.090 / 0.073.
  What the night established:
  - **MS1 must be centroided for DIA-NN:** the same joint MS2 with profile MS1 (`c7_joint_v4_ms1prof`) loses
    10-15% of its IDs (2,945 / 3,266 / 2,835); profile MS1 does not change the CV. Yet profile MS1
    quantifies better (DIA-NN's Ms1.Area CV 0.101 against 0.123 for vendor centroids).
  - **The joint MS2 is the better signal:** fragment areas straight from the spectra (top-6 library
    fragments over the `.wiff`'s elution windows, no DIA-NN; `sessions/.../fragment_area_cv.py`) have CV
    0.093 against 0.099 for the channel, better in every quartile; cosine to the library 0.923 against 0.905,
    fragment co-elution 0.81 against 0.74 (`fragment_extract.py`; a +0.2 Th shifted control finds nothing).
  - **What DIA-NN saw instead was split fragments:** 40% of a joint fragment's instances were two or more
    peaks within 15 ppm (channel 19%), neighbouring positions' centroids of one fragment, which the layout
    merged only within 5 ppm (`MERGE_PPM`, set for the channel solve's shared channel m/z). Taking the largest
    peak instead of the sum erased the joint's advantage (0.107 against 0.104). Merging within 12 ppm left 10%
    and brought DIA-NN's CV from 0.119 to 0.098. This is Centrix's final step (merge centroids closer than
    sigma, "spurious close doublets"; github.com/maccoss/centrix) - the spec meant it to be reused.
  - DIA-NN tightens its tolerance for the joint centroids (12 ppm against 17 for the channel), which also
    narrows its integration (by 0.36 sweeps on average; not when both are pinned at 14 ppm).
  - Arm `slices\c7_joint` (old solver, profile MS1 from the dumps) is confounded; still, its CV (0.095) is
    better than 81c153dfc2's before the merge, for reasons not yet understood (`c7_joint_v4_g16`, 16-bin
    blocks, tests the block size).

**Joint solve speed: everything tried or proposed (2026-09-28/29)**

Benchmark: one A1 sweep (sweep 300), precursors 560-600 (48 bins), one thread pinned to a P-core with the
machine otherwise quiet (`sessions/.../Bench-Joint.ps1`, `--solve-profile`); quality against the same sweep
solved to convergence (`--joint-param MaxRounds=40 MaxPasses=400 ...`, `joint_diff.py`). Original 46.6 s, now
8.6 s. A whole run: 699 sweeps of 430 bins, ~77 thread-s a sweep, so ~1-1.5 h at 10 threads; the channel
solve is ~7 thread-s a sweep. Acquisition at 100 spd is 14.4 min: another ~5-10x is needed.

Done, in 81c153dfc2 (each measured on the benchmark):

| change | effect |
|---|---|
| positions at zero leave the active set after every pass | 2x; blocks 15 -> 3 positions |
| objective tracked from each block step's exact decrease | objective phase 5.9 -> 0.2 s |
| only grid points with data within a peak's reach; coefficients point-major; flat per-column rows | 1.55x, byte-identical |
| re-solve a point only when a neighbour moved by more than the tolerance; gradient checks only near such moves | ~10% |
| 48-bin blocks for `--joint` (16-bin blocks solve 36 positions to keep 16) | 1.6x; fewer block edges |
| block steps over-relaxed by 1.7 (a block overshot past its optimum is re-solved) | same speed; distance to the converged solution 0.083 -> 0.055 |

Tried and dropped: admitting only the top-k violators per point (more rounds, no gain); looser tolerances
(ToleranceIons 0.01-0.03, RelativeTolerance 1e-3, MaxRounds 3: 10-15% faster but further from convergence).

Where the time goes now: the first pass of round 0 (about 21 positions activated per grid point), then each
of ~8 rounds a gradient check over the active region plus a pass; 25 passes per chunk. The second,
reweighted solve is ~40% of the total (9.2 s against 13.8 s without it). 88% of the ions sit in interacting
groups of 51-200 coefficients.

Not yet tried, most promising first:
1. **Centrix-style regions:** segment the grid into signal regions (threshold, merge small gaps, extend by
   the peak reach) and solve each to convergence on its own, instead of rounds over a whole chunk.
2. **Centrix-style selective second pass:** refit only the regions whose weights (lambda) changed by more
   than ~20%, warm-started; the rest keep pass 1. Aims at the ~40% the reweighted solve costs.
3. **Decide the positions once per block of sweeps:** a fragment's precursor position does not change over its
   elution; choose the support from the 12 sweeps pooled (12x the counts), then solve each sweep's amplitudes
   on it. Estimated 5-10x; may also reduce the spread of ions over neighbouring positions.
4. **Tighter inner loops:** SIMD for the 11-tap dot products and residual updates, bounds-check-free spans,
   closed-form 2x2 / 3x3 block solves (now ~13k cycles for ~1.5k flops per block). 2-3x.
5. Seed the active set from the channel solve's support (fewer rounds).
6. Exact solve per interaction group (dense NNLS with the cross-grid-point terms): the converged answer,
   about speed-neutral given the large groups.
7. Smaller peak support (PeakHalfWidth 5 -> 4, ~20% of the convolution work); 96-bin blocks (~1.2x).
8. Unweighted solve (as Centrix) for a Toeplitz / Kronecker Gram; loses the Poisson weights. Coefficients every
   other grid sample (half the unknowns, neighbours 0.58 correlated) - model error for peaks between them.
9. GPU: chunks and blocks are independent.

**Afternoon of 2026-09-29: steps 1-3, and what sets the solve's work**
- Steps 1-3 as agreed: 0f6cb3a2f8 counts per ion from the data (`IonCalibration`, spec 6.2; MS2 99.665 per
  file, fit 1.00; MS1 per spectrum, 5.9-19.3, following the TIC; no m/z dependence); 995fa89766 `--ms1 joint`
  (MS1 on its own TOF grid, step 9.786586E-05, 0.45 of a sample off MS2's); 63cf71f3fc `--peak-shape measured`
  (`TofPeakShape`: MS2 B[0] 0.48 at 222 m/z to 0.37 at 887, against the Gaussian's 0.34-0.26); 009659cbe7 the
  MS1 kernels (5 spectra in 100 m/z bins gave 64 isolated peaks and fell back to the Gaussian; 30 spectra in
  200 m/z bins give 394: sigma 1.62 at 475 m/z, 1.70 at 660, wider than MS2's 1.44).
- Slice arms in flight (`Run-JointWiffEval.ps1`, compare with `c7_joint_v4_sig`): `c7_joint_sig_shape`
  (measured MS2 shape, vendor MS1), `c7_joint_all` (plus `--ms1 joint` with measured MS1 kernels),
  `c7_joint_fast` (as `sig_shape`, with `MaxRounds=3 RelativeTolerance=1e-3`).
- **The measured kernel brings the solve near convergence:** one sweep against itself solved to convergence
  (`bench\admit_ref`), ion-weighted mean |log2 ratio| 0.013; with the Gaussian it was 0.055.
- **The work is set by the stopping rules, not by the start.** Item 3 above, tried: each sweep's active set
  seeded from the block's 12 sweeps pooled (`bench\pool12_*`), or each sweep started from the previous
  sweep's solution (`warm12_*`): the same 8.5 rounds and 28-30 passes, no faster; the converged solve also ends
  after 8.4 rounds with a cap of 40. Keeping to the pooled support without growing it is slower (blocks of 5.8
  positions) and 0.149 from the per-sweep solve. Dropped (`sessions/.../pool-support.diff`,
  `warm-rowgram-counts.diff`).
- Where a pass goes (`--solve-profile`, b6bae12c32): block gradients, Hessian, NNLS, update about 30 / 30 /
  12 / 12%. A block's positions span 25 positions (other precursors, not neighbours) and share half their
  rows: b6bae12c32 computes each row's term once (62 -> 30 per block, byte-identical). Caching each point's
  Hessian (64% hits) and smaller chunks (256-512 samples) saved nothing, so it is not cache capacity. SCARFELL
  timings are unreliable while arms run (their threads share the P-cores' L1/L2); A/B on P-cores freed by
  setting the arms' affinity.
- Stopping rules against the converged solve (one sweep; block solves, |log2|): default 1.96M, 0.013;
  `RelativeTolerance=3e-4` 1.61M, 0.016; `1e-3` 1.26M, 0.022; plus `MaxRounds=3` 1.03M, 0.041 and 37% fewer
  gradient checks (`c7_joint_fast` tests it on IDs); `ToleranceIons=0.01` little; an admission threshold of
  0.2 ions little (7.5 rounds) at 0.038 (not kept); no reweighting 0.244 (a different objective);
  `RefitLambdaChange=0.5` 0.114 (keep 0.2). Next if the loose rules hold on IDs: make them the default (~1.7x),
  then float32 kernels (8 lanes), a coloured parallel pass, or the GPU.
- **Slice results (pinned 14 / 17 ppm; peptides in all three runs; CV on shared precursors):**

  | arm | precursors A1 / D1 / G1 | peptides all / any | CV |
  |---|---|---|---|
  | Gaussian + sigma merge, vendor MS1 (`c7_joint_v4_sig`) | 3,330 / 3,652 / 3,328 | 2,516 / 4,457 | 0.096 |
  | measured MS2 shape (`c7_joint_sig_shape`) | 3,010 / 3,500 / 3,449 | 2,435 / 4,276 | 0.103 |
  | measured MS2 + `--ms1 joint`, measured MS1 kernels (`c7_joint_all`) | 3,389 / 3,492 / 3,544 | **2,613** / 4,408 | 0.109 |
  | measured MS2, `MaxRounds=3 RelativeTolerance=1e-3` (`c7_joint_fast`) | 3,211 / 3,306 / 3,369 | 2,451 / 4,199 | 0.118 |

  With `--window 6` (DIA-NN chooses the tolerance) the measured shape loses 8% (2,303 peptides in all runs,
  CV 0.104 against 0.095): DIA-NN tightens to 10 ppm (14 for the Gaussian).
  - **The measured kernel splits fragments:** straight from the spectra (`fragment_area_cv.py`), 27.0% of
    library fragments have 2+ peaks within 15 ppm against 13.6%; fragment-area CV 0.0969 against 0.0954. The
    extra pairs are 2-3 grid samples apart, median intensity ratio 0.48 (`sessions/.../split_spacing.py`),
    just outside the 1-sigma merge. On the benchmark sweep a 2-sigma merge leaves 0.142 close pairs per peak
    (measured) and 0.122 (Gaussian), against 0.304 and 0.209 at 1 sigma. Arms `c7_joint_shape_m2`,
    `c7_joint_sig_m2` (2-sigma merges) and `c7_joint_sig_ms1` (Gaussian, `--ms1 joint`) are running.
  - **Joint MS1 helps IDs** (+7% peptides in all runs over the same MS2 with vendor MS1, pinned), not CV.
  - **Looser stopping rules cost precision, not IDs:** CV +0.013-0.017. The unconverged split between
    neighbouring positions differs run to run. Keep the default; test whether tighter convergence helps CV.
  - Also tried on one sweep and dropped: skipping rows with no data in a peak's reach (exact, but only 13% of
    gradient-check terms are empty: single-ion noise is everywhere); Poisson weights from the previous
    sweep's fit, solved once (a third fewer block solves, but 0.170 from converged against 0.010; diff in
    `sessions/.../prior-weights.diff`); `PeakHalfWidth=4` (no fewer block solves, twice the error).
  - Untested: a narrower layout (`centered:5` / `centered:3`) with the joint solve. DIA-NN picks candidates
    at 1.18 Th but each spectrum carries 8.3 Th of positions, so fragments interfere up to 3 bins away.

**Whole runs through the joint solve (2026-09-30):** A1, D1, G1 with `--merge-sigmas 2 --ms1 joint`
(`full\joint_m2_ms1`), searched as the other whole-run arms (DIA-NN 2.3.2, 16 threads, `--window 6
--mass-acc 17 --mass-acc-ms1 19`, arm `slices\diann\full_joint_m2_ms1`; `sessions/.../Compare-Whole.ps1`):

| Arm | Precursors A1 / D1 / G1 | FDP | Peptides in all runs / any | CV (20,957 shared) |
|---|---|---|---|---|
| DIA-NN scanning mode on the `.wiff` | 30,567 / 30,323 / 31,016 | 0.96-1.04% | 21,591 / 33,956 | 0.091 |
| per-channel solve (`full_c7pz_scarfell`) | 31,512 / 31,506 / 32,117 | 0.79-0.89% | 22,197 / 35,140 | 0.123 |
| **joint solve** | **36,314 / 36,169 / 36,627** | 0.81-0.84% | **25,622 / 39,984** | **0.106** |

**+19% over DIA-NN on the `.wiff`, +15% over the per-channel solve; half the CV gap to the `.wiff` closed**
(joint against channel on their 23,390 shared: 0.108 against 0.126, 61% of precursors better). Time per
file: demux 107 min (A1 alone at 16 threads; 89 min each for two side by side at 8 threads), DIA-NN 2.4 min
loading and 25 min searching; DIA-NN on the `.wiff` spends 50 min loading (the SCIEX library, not a
demux: its scanning analysis starts after it) and 46 searching.

**Night of 2026-09-29/30: CPU speed of the joint solve, unchanged output**
- **1.36x on 12 sweeps** (A1 dump sweeps 57-68, precursors 560-600, measured shape, one thread on a cleared
  P-core): b6bae12c32 114-120 s, 6ae9643df7 82.5-87 s, both 0.0101 from the converged solve (`bench\ref12_ref`).
  - fb80b10ca2 block Hessian from each column pair's shared rows (a block's positions span about 25, so many
    pairs share none) and the first weights spread from samples with data: byte-identical, 12%.
  - c54a6be7a4 gradient check four grid points per vector (it made 83M peak-gradient calls a sweep against
    the block solves' 59M): 13%, output unchanged on the benchmark.
  - 77c84dd54e prune only the points a pass solved, active counts per point: byte-identical, 2.5%.
  - 6ae9643df7 v and curvature four points per vector, one residual update per row: 5%.
- **Measuring on SCARFELL:** timings while arms run are only usable with the arms and DIA-NN kept off the
  benchmark's P-cores (affinity 0xFF003) and A/B pairs swapped between cores; identical runs still differ by
  about 4-8%, so a part under about 10% cannot be ranked. Ablation (`OSPREY_JOINT_ABLATE`, a part run twice,
  `sessions/.../Bench-Ablate.ps1`) ranked the Hessian first; the profile's own sub-timers understate it.
- Tried and dropped: inlined, bounds-check-free peak loops (byte-identical, about 3%, within noise; not worth
  unchecked writes); alternating pass directions (46 passes against 28, 39.7M block solves against 24.1M);
  96-bin units (`--group-bins 96`: 36% fewer block solves but blocks of 5.3 positions against 4.0, about 3%,
  output 0.043 away); `PeakHalfWidth=4`; skipping rows with no data near a point (13% of terms).
- **0025884217 over-relaxation 1.7 -> 1.5**, against 12 sweeps solved to convergence (`bench\gref12_base`
  Gaussian, 637 passes; `bench\ref12_ref` measured), block solves and |log2|: Gaussian 1.0 19.7M 0.033, 1.2
  18.8M 0.028, 1.4 18.7M 0.024, **1.5 19.1M 0.022**, 1.6 19.9M 0.022, 1.7 21.2M 0.023, 1.8 23.7M 0.026, 1.9
  29.1M 0.032; measured **1.5 19.5M 0.0056**, 1.6 21.3M 0.0073, 1.7 24.1M 0.0101. The Gaussian default is
  twice as far from converged as the measured shape, and convergence moves the CV (looser rules cost
  +0.013-0.017).
- **43b3088e67 `BlockPoints` (option, default 1):** each block step solves the active positions of up to 5
  neighbouring grid points together (cross terms from v shifted by their distance, boundaries moving each
  pass). 12 Gaussian sweeps, block solves / positions per block / |log2| from converged: 1 19.1M / 3.9 /
  0.022; 2 11.5M / 6.3 / 0.019; 3 8.1M / 8.5 / 0.010; 4 6.1M / 10.8 / 0.008; 5 4.9M / 13.1 / 0.007. It buys
  accuracy, not speed: timed back to back on the same cores (6 sweeps, 6 runs each) 1 point 33.5 s, 3 points
  with `RelativeTolerance=1e-3` 38.8 s (0.019), 4 points with it 43.9 s (0.014). Worth a slice arm if tighter
  convergence improves the CV.
- Where the current build's time goes (12 Gaussian sweeps): passes 66%, gradient check 23%, weights 8%; each
  grid point in reach is solved about 12 times per sweep. On a whole run (A1): passes 53%, checks 31%,
  weights 11%, 96 thread-s a sweep.
- **618708e3fa exact screening:** within a descent no coefficient's gradient exceeds its value at zero
  (weights fixed, model non-negative), so the first check screens the coefficients the data alone cannot
  activate and the later checks skip them; rows are slid only for the columns tested. Byte-identical; 12
  sweeps 22% fewer check slides and 28% fewer check sums. Screening the reweighted descent as well costs its
  extra data-only check (211M slides against 212M unscreened). A hard ion threshold per grid point would
  save more but changes the output (a slice arm, as `--min-out`).
- Also tried and dropped: admitting near-violators early (`AdmitMargin`): rounds unchanged, 5-13% more block
  solves.
- **Slice, 2-sigma merge + joint MS1 (`c7_joint_m2_ms1`, `--window 6`):** 3,447 / 3,788 / 3,532 precursors,
  2,651 peptides in all runs and 4,640 in any (the most of any arm; channel 2,197 / 3,743, Gaussian 2-sigma
  2,610 / 4,508), CV 0.095 against 0.092 for the 2-sigma merge alone. Pinned (14 / 17 ppm): 3,586 / 3,775 /
  3,589, 2,698 peptides in all runs and 4,698 in any (channel 2,281 / 3,851), CV 0.0905 against the channel's
  0.0964 on the precursors both quantify (0.094 against 0.092 for the 2-sigma merge alone). **Recommended
  defaults: `--merge-sigmas 2 --ms1 joint`.** Whole runs with them: `full\joint_m2_ms1`
  (`sessions/.../Run-WholeJoint.ps1`: A1 alone at 16 threads for the timing, then D1 and G1, then DIA-NN as
  `full_c7pz_scarfell`, arm `slices\diann\full_joint_m2_ms1`).

I/O around the solve (separate from it): the writer re-centroided every spectrum to get its header (fixed,
ff7e429fb4); the vendor reads were serial (4 threads, aac2026874: 3.95x, identical peaks). Opening a run takes
~80 s. Still open: mzMLb or an in-memory hand-off to Osprey instead of a 17-19 GB mzML per run.

**Next, in order.** Quantitation has two separate problems: the demux's counting noise on weak signal
(0.010 at the lowest abundance quartile, nothing at the top), and the vendor centroids' missing signal
(0.013-0.018 everywhere). The joint solve addresses both.
1. The joint solve (spec §5.4d) on the profile grid, which Mike prefers: add the Poisson-scaled L1 in
   (position x m/z) space (NNLS on the normal equations with A^T W y - lambda, per-column lambda from
   sqrt((A^T W A)_jj) as `--sweep-l1-z` does), the measured peak shape by m/z instead of a Gaussian, and a
   sub-sample grid for the fragment position; then score it against the channel solve on placement AND
   on a DIA-NN slice file, since placement of strong fragments cannot show the joint solve's gain on
   near-isobaric fragments of different precursors. The L1 is in `joint_prototype.py` (`joint-z2`,
   exact through the Cholesky factor of the weighted Gram; `--half 8` windows give the same numbers as
   16 and are 4x cheaper). On all 341 precursors: joint-z2 0.49 / 0.85 own / +/-1, median own 0.35, against
   joint 0.48 / 0.84 / 0.33 and the vendor channel solve 0.51 / 0.87 / 0.34, while carrying about 4x the
   signal (the full profile area). The L1 helps the joint solve; on placement it is now comparable to the
   channel solve. 78 min in Python for 341 precursors: C# (coordinate descent on the Kronecker
   structure) before a whole slice.
2. Done: MS2-only event centroids (MS1 vendor) are worse raw (2,344 / 2,583 / 2,465 peptides against
   2,652 / 2,686 / 2,621, paired CV +0.0075) and demultiplexed (2,849 / 2,713 / 2,802 against 2,875 / 2,880 /
   3,017, +0.0070). Keeping single events and full areas is not enough with adjacency grouping; the peak model
   has to be in the solve. Do not polish the adjacency centroider.
3. Profile reading is the bottleneck: the SDK takes about an hour per replicate for the slice under load.
   Copy the `.wiff2`/`.wiff.scan` to local disk, and read each spectrum's profile once into a cache.
4. Separate the demux's own noise from how DIA-NN quantifies a centered:7 spectrum, which carries its
   neighbors' fragments (the old machine's suggestion): CV by local precursor density, and a
   quantification from the demultiplexed values themselves at DIA-NN's identified apexes.
5. Still open from before: fragment grouping, the anchored per-candidate extraction as an Osprey feature,
   Orbitrap k = 3 / 4, and wiring the demultiplexer into Osprey's `--demux`.
6. /code-review max before any PR; the PR goes to #4710's branch, or to the port branch once #4710 merges.
- **Module**: `osprey`
- **GitHub Issue**: [#4711](https://github.com/ProteoWizard/pwiz/issues/4711)
- **PR**: [#4710](https://github.com/ProteoWizard/pwiz/pull/4710) (M0 + M1)
- **Worktree**: `D:\Dev\pwiz-osprey-demux` (old machine); `C:\Dev\pwiz-osprey-demux` on the new one,
  checked out at the follow-on branch

## Day of 2026-09-30 on SCARFELL: speed, precision, and one pipeline

**Speed** (A1 sweeps 324-431, 16 threads, joint solve): the solve is memory-bandwidth bound, so the chunk
size is what moves it. 2048-point chunks 1,263 s, 1024 1,189 s, 512 1,159 s, 256 1,153 s; queuing the next
batch before waiting (e2a9a7199c) plus preallocation 1,058 s at 512. 20 threads: 1,150 s, no gain.
`ChunkSamples` default is now 512 (a96c614e0d).

**Slice arms** (sweeps 247-371, 500-700 m/z, centered:7 unless named, 512-point chunks, DIA-NN pinned at
`--window 6 --mass-acc 14 --mass-acc-ms1 17`; `ids_summary.py`, `paired_cv.py --rt 4.1 5.9`):

| Arm | Precursors A1 / D1 / G1 | Peptides, all runs / any | Median CV |
|---|---|---|---|
| 2048-point chunks (`c7_joint_m2_ms1_pinned`) | 3,586 / 3,775 / 3,589 | 2,698 / 4,698 | 0.090 |
| 512-point chunks (`c7_joint_c512_pinned`) | 3,670 / 3,821 / 3,752 | 2,785 / 4,821 | 0.091-0.093 |
| Gaussian sigma x 0.8 (`sig080`) | - | 2,578 | 0.094 |
| Gaussian sigma x 0.67 (`sig067`) | - | 2,533 | 0.097 |
| centered:5 (`c5_joint_c512_pinned`) | 3,443 / 3,612 / 3,716 | 2,680 / 4,597 | 0.0917 vs 0.0932 (2,479 shared) |

- A narrower peak model is worse, and centered:5 loses 3.8% of the peptides at an unchanged CV: centered:7
  stays. D1's FDP was 1.15% in the 512 arm; watch it.
- **Wider peak models** (each with its own 2,396-2,539 shared precursors; DIA-NN's settings alone move the
  paired CV by 0.0015 with 46.5% improved):

  | Sigma | Peptides, all runs / any | Median CV vs x1.0 | Paired dCV, improved | Precision | Within 10 ppm | On grid |
  |---|---|---|---|---|---|---|
  | x0.67 | 2,533 | 0.097 | - | 5.97 ppm | 65.0% | 28.4% |
  | x0.8 | 2,578 / 4,496 | 0.094 | - | 5.86 | 65.7% | 31.2% |
  | x1.0 | 2,785 / 4,821 | 0.0935 | - | 5.71 | 66.6% | 34.2% |
  | x1.2 | 2,758 / 4,687 | 0.0869 | -0.0042, 57.3% | 5.50 | 67.4% | 36.0% |
  | x1.4 | 2,755 / 4,765 | 0.0979 | +0.0038, 45.7% | 5.30 | 68.0% | 36.6% |

  Identifications peak at x1.0-1.2; the CV is best at x1.2 and worse again at x1.4; mass precision improves
  all the way (partly selection: the wider arms match 99.7-101.3k observations against 102.7k). The
  default stays at x1.0 for identifications; x1.2 is the candidate for quantitation, to confirm on whole
  runs before changing anything (`Run-SliceArms.ps1` arms `sig120`, `sig140`; precision from
  `mass_accuracy.py --arms`).
- **Whole runs at sigma x1.2** (`full\joint_sig120`, 512-point chunks; DIA-NN 17 / 19 ppm, arm
  `slices\diann\full_joint_sig120`): 37,317 / 36,645 / 37,503 precursors (FDP 0.80-0.85%) against the joint
  default's 36,314 / 36,169 / 36,627; peptides 26,086 in all runs / 40,920 in any against 25,622 / 39,984
  (+20.8% over DIA-NN on the `.wiff`); CV 0.1068 against 0.1119 on 26,828 shared (paired -0.0042, 55.9%
  improved), and against the `.wiff`'s 0.0918 the gap goes from +0.0141 to +0.0099. Better on every
  measure: **make x1.2 the default.** The reference used 2048-point chunks, so part of the ID gain may be
  the chunk size (+3% on the slice at an unchanged CV); a whole-run x1.0 control at 512 would separate it.
  Demux 91 min for A1 alone at 16 threads; D1 and G1 together 161 min, shared with a CarafeSharp run.

**CarafeSharp + Osprey on ZT Scan (Mike, 2026-09-30: train on the middle run, fine-tune, search all three,
keep the fine-tuned library for later tests).** Built from #4717's head 27a0ba6595 in the worktree
`C:\Dev\pwiz-carafesharp` (CPU libtorch; SCARFELL has no NVIDIA GPU), snapshots
`C:\temp\osprey-runs\_bin\carafesharp-27a0ba6-cpu` and `osprey-27a0ba6-vendor`; `Run-CarafeSharpWorkflow.ps1
-Dataset ZTScan -InputFormat mzML -Device cpu`, work dir `C:\temp\osprey-runs\ztscan\carafesharp`. Input: the
joint solve's whole-run mzMLs (`full\joint_m2_ms1`); training run D1.
- Pretrained library (SciexTOF, NCE 27, charge 2-4, 392-900 m/z): 4 h 16 min on the CPU, shared with the
  sigma x1.2 demux. Osprey on D1 with it: **20,426 precursors, 17,989 peptides** - against DIA-NN's 36,169
  precursors on the same file with a pretrained Carafe library. Not yet understood: the C-selection
  bimodality reported for Osprey (~21k or 28-30k), the 1.18 Th windows each carrying 8.3 Th of positions,
  or something else. To look into after the fine-tuned search.
- Training export: ZenoTOF 8600, HCD, Q-TOF, collision energy 18; MS2 calibration +4.38 ppm, SD 5.68 ppm (the
  slice's accuracy and precision). SCIEX activation would train CarafeSharp's resonance-CID slot, hence
  `-ms_instrument SciexTOF`, which training and prediction both keep.
- Fine-tune (94 min): MS2 cosine 0.878 -> 0.984, PCC 0.868 -> 0.983, spectral angle 0.682 -> 0.887 (n=831,
  held out of D1); RT R2 0.922 -> 0.997, median error 0.034 -> 0.006. 13,623 of 20,426 spectra kept. Library:
  8,936,669 precursors (4.47M target/decoy pairs, shuffled entrapment), `osprey_new_library\`; model
  `carafe_fine_tuned_model.carafemodel` (re-predict with `-model`).
- **Three-run search with it (45 min, `osprey_project\`):** per run 27,901 / 28,534 / 27,696 precursors
  (24,425 / 24,880 / 24,338 peptides); experiment 33,951 precursors at q <= 0.01 with 0.26% entrapment FDP
  (44 hits), 29,409 peptides at 0.30% (`Compare-DemuxSearches.py --search finetuned=osprey_project`).
  Osprey's q is conservative here: q 0.02 gives 37,256 at 0.48% FDP, q 0.03 39,226 at 0.52%. D1 went from
  20,426 (pretrained, one-run search) to 28,534; the SVM C choices are ordinary in both (folds 0.1 / 1 / 1
  and 10 / 0.1 / 1), so not the C-selection bimodality. Still ~22% under DIA-NN per run (36-37k at ~0.8%
  FDP). Mike (2026-10-01): fine as a first pass, and the initial library stays target+decoy without
  entrapment (entrapment would double its prediction and search time and cost sensitivity), so no
  pretrained entrapment baseline. The fine-tuned library is the one to use for later ZT Scan tests.
- **Mass accuracy is not the matching problem, precision is.** Accuracy (offset from library m/z) is +4.4 ppm
  in every arm, the instrument's calibration. Precision (sweep-to-sweep spread of a fragment's m/z): joint
  5.66 ppm, centroid solve 5.59, acquired 6.03. The joint solve's centroids snap to the TOF grid: 36.1% lie
  within 0.05 samples of a grid point, against 12.2% for the centroid solve (`mass_accuracy.py`).

**One pipeline (Mike's decisions, `TODO-20260923_osprey_demux/pipeline-design-2026-09-30.md`).** Each step
gated byte-identically on the tool's reference outputs (`Capture-DemuxGoldens.ps1`: ZT joint, ZT joint at
512, ZT centroid solve, Eclipse EV13 staggered):
- 09f393fd7d, 32b00d275c, dea1c73b77: the scanning demux on `DemuxPipeline` + `DemuxPlan` behind
  `IDemuxSource`; ZT Scan detected from the data (`DemuxSchemeDetector.DetectScanning`: 64+ bins of at
  most 3 Th per cycle and the strongest points persisting across bins; the tool exits without `--scheme` on
  anything else).
- 6b89e21901: staggered on the same driver (`StaggeredDemuxPlan`); the whole Eclipse EV13 file 350 s
  against 830 s, on a differently loaded machine.
- eb9e893553: **`--demux auto` runs the weighted staggered demultiplexer by default**
  (`WeightedDemultiplexer`); the overlap demultiplexer is `OSPREY_DEMUX_ENGINE=msconvert`, to be removed.
  Algorithm version 4, so demultiplexed caches rebuild. Through Osprey, EV13's demultiplexed cache carries
  every peak of the tool's output byte for byte (121,121,741 m/z and intensities); only the metadata
  differs (scan numbers kept per parent, precursor m/z at the bin center, window edges within 1e-13 Th).
  Demultiplexing took 93.7 s against a 136.6 s parse under load (the msconvert engine: 18.8 s).
  **EV13 + EV14 through Osprey: 39,956 precursors at 0.26% FDP, 34,483 peptides at 0.30%, 52 entrapment
  hits** (below 1000.70 m/z; `Compare-DemuxSearches.py`), against 40,009 / 34,501 / 52 for Osprey searching
  the tool's mzML: the same result within run noise, +4.0% over msconvert. 44 min for both files
  (`C:\temp\osprey-runs\eclipse-staggered\search-osprey-weighted`).
- Next: ZT Scan through Osprey. Per Mike, the cache never holds the profile: the joint solve runs as the
  run is read (`.wiff2`, `.wiff`, mzML) and only its demultiplexed, centroided spectra go to the spectra
  cache. Also the kernel measured per file in C# and the .wiff2 reader for Osprey.exe. **TODO: a
  joint-solved file Skyline can read.** Then the Stellar staggered profile (needs data), then
  the rest of the spec. Step 3 changes `DemuxCacheBuilder`, which #4710 adds: agree the order with Brendan
  before pushing.

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

- **ZT Scan goal and next step (Mike, 2026-09-28):** detect as many peptides as DIA-NN given the `.wiff`,
  or more; somewhat worse precision is acceptable (met on whole runs, see the night's section). Next: solve
  centroids and demultiplexing together on the profile grid (spec §5.4d), in C#.
- **Skyline must be able to read the demultiplexed data (Mike, 2026-09-28).** Inside Osprey, `--demux` must
  also write the demultiplexed spectra to a file Skyline reads (mzMLb, or mzML), and the blib Osprey writes
  must point at that file, not at the vendor file, so the search results open in Skyline on the spectra
  they were scored on.

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
