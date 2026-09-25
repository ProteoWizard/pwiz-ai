# Osprey demux spec: where the plan stands (2026-09-25)

A pass over `osprey-demux-spec.md` against what PR #4710 built. The questions it answers:
- what the spec's unified plan still needs;
- where the spec itself needs revising;
- whether the instrument-dependent noise and threshold model is still needed;
- how Osprey should detect ZT Scan.

## The goal, stated plainly

Keep the ion statistics of a wide isolation, and recover the precursor specificity of a narrow one. For ZT Scan:
* The quadrupole transmits about 12 Da (FWHM, measured), so every precursor is sampled by about 10 to 15 consecutive encoded bins. That is the sensitivity.
* Demultiplexing has to put each precursor's fragments back at its own position, near the 1.18 Da encoded-bin spacing. That is the specificity.

## Decisions (with Mike, 2026-09-25)

1. **ZT Scan output bin width is the encoded bin, 1.18 Th.** The aim is the sensitivity of the ~11.8 Th transmission with the specificity of a 1.18 Th bin. Each precursor's signal is spread across the ~10 encoded bins that transmit it, and the solve deconvolves it back into the one bin its m/z falls in.
2. **Coupling across fragment channels (§6.5) is required for scanning data**, not a later refinement. One fragment channel carries too few ions to place a precursor to 1.18 Th. All of a precursor's fragments share one position along the Q1 axis, and its elution profile across the cycles of its peak. The trilinear model (bin x fragment x time, §6.5.3) pools all of them.

**Rough ion budget for 1.18 Th.** This is an estimate, not a measurement. Take the kernel as roughly Gaussian with a FWHM of 11.8 Th, so sigma is about 5 Th. The position of one isolated precursor is then known to about 5 Th divided by the square root of the ions pooled for it:
* 25 ions: about 1.0 Th.
* 100 ions: about 0.5 Th.

So one-bin placement needs a few tens of ions pooled across the precursor's fragments and across the cycles of its peak. That is well within reach on a counting detector once coupling pools them. Per fragment, per cycle, it is not.

Two cautions:
* **Separating two co-eluting precursors 1.18 Th apart is harder than placing one**, because it depends on their fragment patterns or elution profiles differing (§6.5). Precursors that co-elute exactly and share their fragments are not separable (§6.5.3, failure mode).
* **The estimate should be replaced** by the conditioning study (step 3 of the order below), which uses the measured kernel.

## Status by section

Legend: **done**, **partial**, **no** (not built), **n/a** (not relevant yet).

| Spec | Asks for | #4710 | For ZT Scan |
|---|---|---|---|
| §2 | One forward model `y = A x`, `x >= 0`, one solver | **partial**: `NnlsSolver` takes any real `A`, but `A` is built only as 0/1 staggered blocks | core |
| §2.0 | Fill-time-weighted `A` (`tau_ij / IT_i`) | **no**: equal fill assumed, correct for staggered | the kernel *is* this quantity |
| §2.2 | Staggered bins from the boundary union; optional edge softening | **done** (no edge softening); columns are every covered bin | n/a |
| §2.3, §2.4 | Scanning kernel, calibrated from surviving-precursor profiles | **no** | core |
| §2.5, §2.6 | Comb and MSX | **no**. MSX is misread today: only the first precursor is kept | n/a |
| §3 | Conditioning; ringing metric; report `sigma_min(A)` | **partial**: nonnegativity only, no metric (#4713) | needed; see "Revisions" |
| §3.1 | Isotope envelope straddles narrow bins; score across the bins it occupies | **no** | needed at 1.18 Da bins |
| §4.3 | Acquired-axis B-spline fit (the target for staggered) | **no** | n/a (§4.5: no RT treatment) |
| §4.4 | Interpolate-then-solve as a reference only, PCHIP | **shipped as the default**, with makima | n/a |
| §5.1, §5.2 | Channel linking: intensity-dependent tolerance, per-event offsets, union index, same-event split, pooled m/z | **no**: fixed ±10 ppm channels centered on the target's own centroids | needed; §7.4 says linking is the ZT Scan hot path |
| §5.4b to §5.4d | Unit-resolution grid, profile demux, joint demux plus centroiding | **no** | n/a (Stellar, M5) |
| §6.1, §6.2 | Weighted least squares; `alpha`; ion-count thresholds; censoring; charge floor | **no**: unweighted, no floors | partial; see "Noise and thresholds" |
| §6.3 | Tier 0/1/2, exhaustive enumeration | **partial**. Covered-bins blocks are never full rank, so Tier 1 never fires: 100% active set measured | performance only |
| §6.4 | Determinism | **done**: identical at 1 vs N threads | carries over |
| §6.5 | Coupling across fragment channels (anchored two-stage) | **no** | likely essential; see "Revisions" |
| §7 | SIMD, tier-homogeneous batching | **deferred**: scalar demux is 10-13% of the parse | not needed yet |
| §8 | Streaming: ring buffer, per-window spill | **no** (#4714) | required (8.6 GB per run) |
| §8.4 | Sparsify with an ion floor; no relative threshold | **differs**: a 1e-6 relative round-off floor | needs an ion floor |
| §9.1 | v5 header | **superseded** by §9.1c plus the descriptor | the kernel goes in the descriptor or a sidecar |
| §9.1c | Two artifacts; pass 1 collects kernel probes | **partial**: two artifacts done, no probe collection | needed |
| §9.2 | Scan numbers, option A | **done** | carries over |
| §9.3 | Acquisition kind from window layout plus vendor metadata; `--demux-kernel`, `--demux-metrics`, `--alpha` | **partial**: window geometry only; `--demux` defaults to off | detection is missing; see below |
| §10 | Diagnostics | **partial**: scheme, solve paths, timing in the log | #4713 |

Gates:
* **Passing:** G1.1 to G1.4, with G1.3 over 3,000 systems rather than 10^5; G2.8 to G2.12; G3.1; G4.1; G4.3; G7.1.
* **ID counts and entrapment FDP measured** (G6.4, G6.5).
* **Not run:** G0 (Phase 0 feasibility); G1.5 to G1.9 (noise, ringing, kernel misspecification, censoring); every G5 gate; G6.1 to G6.3 (quantitative accuracy).

**The spec's stated goal is quantitation (§1 goal 3), and nothing measured so far tests it.** G6.1 to G6.3 need three-proteome or dilution-series data, or matched acquisitions (§11.7).

## Revisions the spec needs

1. **§3 has no conditioning analysis for the scanning kernel, and that is the crux of the goal above.**
   * §3 covers staggered, comb and MSX.
   * A kernel about 10 bins wide, deconvolved to 1-bin resolution, is badly conditioned for the unconstrained problem: a smooth kernel passes little high-frequency information.
   * What makes narrow specificity recoverable is:
     * a precisely known kernel, especially its edges;
     * sparsity, since few precursors contribute to any one fragment channel;
     * nonnegativity;
     * pooling all of a precursor's fragments (§6.5).
   * This is localization rather than resolution: a precursor's position is read from where its profile sits across the bins. The precision scales roughly as the kernel width over the square root of its ions, well below the kernel width.
   * The spec should:
     * state achievable position precision and two-precursor separation as a function of ions and kernel shape;
     * choose the output bin width from that;
     * gate it on synthetic data.
2. **§6.5 should become required for scanning data, not a later refinement.** Per-channel NNLS has only one channel's ions to localize with. Coupling pools every fragment of the precursor onto one bin profile, and that pooling is how the narrow specificity is reached. The anchored two-stage form (§6.5.4) keeps the cost near per-channel.
3. **ZT Scan facts should be replaced with measured ones** (§2.1, §2.3, §7.4, §8.1, §12b). From the port branch's characterization of `250814_ZTScan_100spd_A_3_G1`:
   * 429 encoded bins of 1.18 Da, not 1.5 Th.
   * A 0.86 s sweep at about 588 Da/s within a 0.97 s cycle, not 858 Hz at 4000 Da/s.
   * Transmission near-Gaussian with a FWHM of about 11.8 Da, about twice the method's 5.9 Da Q1 width and not yet explained. The spec expected a trapezoid.
   * No visible lag: the apex was within one bin of the reported center in 9 of 10 probes. The spec expects a positive lag, so G5.3 ("positive and smoothly varying") may be the wrong gate.
   * Re-derive the kernel parametrization and G5.3 from the fit (G5.1 to G5.5).
4. **§2.0 and §6.2 have no `alpha` for a SCIEX TOF.** Hsu et al. Table 1 has none. The ion-denominated floors need one for the 8600, measured or bounded.
5. **§4.4:**
   * makima measured better than PCHIP (the spec's choice) at 3 to 4 points per FWHM;
   * interpolate-then-solve shipped as the default for v1;
   * record both, and say whether §4.3's acquired-axis fit is still the staggered target.
6. **§8.4:** allow a round-off floor (a share below 1e-6 of the channel's total, removing solver noise), which is distinct from the signal threshold the section rules out.
7. **§6.3 and §7.4:**
   * covered-bins staggered blocks are rank-deficient, so Tier 1 never fires;
   * measured: 69 M channel solves in 18.8 s on 16 threads, including extraction and interpolation;
   * update the cost model with these numbers.
8. **§9.1:** mark it superseded by §9.1c and the descriptor.
9. **§9.3:** `--demux` defaults to off until the method is validated more widely.

## Noise and thresholds: which parts are still needed

§6.2 is really three separate features.

* **Poisson row weights**, `w_i = IT_i / max(y_i, floor)`.
  * Matter where events differ in ion count: AGC-varied fill times in staggered data, and the low-count kernel tails in ZT Scan.
  * They break the shared factorization. Spec option B keeps the unweighted fast path and weights only the hard channels.
  * **Worth adding to the generalized solver, and judging with G1.5 and G1.6.**
* **Ion-count thresholds**: `alpha` per analyzer, `minIonsPerBin`, the output ion floor, the Tier 0 floor.
  * They make every threshold instrument-independent, and they replace our relative round-off floor with a physical one.
  * **Needed for ZT Scan output** (an ion floor on demultiplexed peaks), once there is an `alpha` for the 8600.
* **Orbitrap censoring and the transient-scaled charge floor** (items 4 and 5, and G4.15 Tier 0 gating).
  * These are Orbitrap-only.
  * The spec itself says not to apply them to scanning TOF: an empty bin on a counting detector is a real measurement.
  * **Not needed for ZT Scan.** For the Orbitrap staggered path they are a quantitative refinement. The ID gains came without them.
  * Revisit only once G6.1 to G6.3 can be measured, and after Phase 0 (G0.1 to G0.3) says Orbitrap demux is worth refining.

## ZT Scan detection

**Today:** Osprey cannot tell ZT Scan from ordinary narrow-window DIA.
* The 429 encoded bins tile exactly, so the window-geometry detector sees a non-overlapping scheme.
* `--demux off` does not refuse the data, and `auto` searches it as acquired.

**pwiz-sharp already knows.** `WiffFile` and `Wiff2File` build a `ZtScanBin` per experiment from the method: `GroupName == "ZTScan"` in `.wiff2`, the `Is ZT Scan` sample field in `.wiff`. But it uses them only to correct each bin's collision energy. Nothing reaches the spectra or `MsDataFileImpl`.

**Proposed detection:**
1. **Metadata first.** Add a reader-level query to pwiz-sharp and `MsDataFileImpl`, parallel to the existing `IsWatersSonarData()`. It would report that the run is a scanning-quadrupole acquisition, plus the sweep geometry the reader already has:
   * bin count;
   * sweep range;
   * each spectrum's bin index;
   * per-bin start times, 2.010 ms apart;
   * Q1 width and sweep rate from the method.

   This changes no mzML output, so it keeps the cpp/C# parity sweeps clean. It is a change on the port branch (#4619), so coordinate with Matt.
2. **Persist the acquisition kind** with the plain cache. `.spectra.bin` must stay a pure function of the raw file, and a cache hit has to know it is ZT Scan.
   * Prefer the per-run acquisition sidecar from the original plan (B.1) to a v5 header, which would strand cohorts.
   * Share that sidecar with the `.run-info.json` planned by the carafe-export branch.
3. **Verify from the data.** Every consecutive bin in a cycle should show each precursor's surviving ion and fragments across about 10 bins. The kernel fit (G5.1, G5.5) confirms the metadata and fails loudly if they disagree, per §9.3.
4. **mzML input** carries no marker. Either detect from the data alone, using the same cross-bin persistence test, or require the vendor file.
5. **Guard:** with demux off, refuse a detected scanning run, as the staggered guard does now.

## Proposed order of work

1. **Detection and reading:**
   * the pwiz-sharp query and the acquisition sidecar;
   * Osprey reads `.wiff` and `.wiff2`, staging the plugin;
   * the demux-off guard for scanning runs.
2. **Kernel calibration** on `A_3_G1`, then all three replicates: G5.1 to G5.5, with G5.3 re-derived. This measures the real kernel, and with it the conditioning question above.
3. **The conditioning study at the chosen 1.18 Th** (revision 1): synthetic scanning data with the measured kernel, per-channel versus coupled, swept over ions. It measures placement precision and two-precursor separation.
4. **Generalize the demux core.**
   * Acquisition models (stepped, scanning) supply the rows of `A` and gather the events.
   * The solver, output and cache stay shared.
   * Add Poisson weighting.
   * Add scanning versions of G1.1 to G1.8.
5. **Coupling across channels and time** (§6.5, anchored two-stage), required for scanning data per decision 2. Step 3 measures how much it buys over per-channel.
6. **Streaming** (§8, #4714).
7. **Metrics JSON** (#4713): ringing, `sigma_min`, mass balance, ion budget.
8. **Validation:**
   * G6.4 and G6.5 against DIA-NN on the three runs;
   * G6.1 to G6.3 once benchmark or matched data exists: ZT Scan against Zeno SWATH on the same sample, or a three-proteome mix.

**Deferred:** Orbitrap censoring and charge floor; SIMD; MSX (needs per-precursor fill times from the reader); comb; profile demux and centrix; the acquired-axis fit.

## Open questions for the lab

* **Validation data:** matched ZT Scan and Zeno SWATH acquisitions of the same sample, or a ZT Scan three-proteome mix, for G6.1 to G6.3?
* ~~**DIA-NN:** its report and library~~: resolved 2026-09-25. We run DIA-NN ourselves; versions 1.8.1 to 2.3.2 are in `C:\DIA-NN`. The 2.3.2 command-line `diann.exe` has `--scanning-swath`, the mode G7.2 names.
* **An `alpha` for the 8600 TOF**, or an infusion measurement to get one?
