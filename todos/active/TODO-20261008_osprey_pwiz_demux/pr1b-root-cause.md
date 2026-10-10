# PR 1b root cause: why does a correct search span lose identifications?

Question (Brendan, 2026-10-09): how can a clear logic correction lead to noticeably worse performance?
Either we learn something to apply correctly, or we show the benefit is a fluke. We do not leave a
bug in the code because the number it produces makes us happier.

Baseline numbers (6 Eclipse runs, `D:\test\osprey-runs\pwiz-demux\eclipse-search6`):
defect (`pwiz-nnlsfix`) 38,088 precursors, FDP 0.47%; corrected span + half-open bins
(`pwiz-extractfix`) 34,718, FDP 0.49% (-8.8%).

Working files: `ai/.tmp/sessions/20261009-pr1b/` (scripts and their outputs named below).
Measurement-only code (never ship) in worktree `C:\proj\pwiz-demux-parity`:
`SpectrumPeakExtractor.cs` env knobs DEMUX_SPAN / DEMUX_HALFOPEN / DEMUX_CAP / DEMUX_WIDTHMATCH /
DEMUX_SHIFT_PPM; `PercolatorConfig.cs` OSPREY_DIAG_SEED; plus last night's
OSPREY_DEMUX_MASS_ERROR_PPM in DemuxCache.cs. Last night's uncommitted extractor change saved as
`parity-uncommitted-0758.diff`. Snapshots `_bin/pwizdemux-knobs`, `_bin/pwizdemux-knobs-seed`.

## Established (each with its verifier)

1. **What the defect does, exactly.** C++ `SpectrumPeakExtractor` starts its bin search at
   `query - maxDelta` (maxDelta = the largest bin HALF-width in the spectrum). Equivalent to: every
   bin accepts only `[Low, min(High, Low + maxDelta)]`. Above half the spectrum's top m/z that is a
   window of constant width maxDelta Th anchored at the low edge (-10..0 ppm at the top, 20 ppm wide
   below half). **Verifier:** knob build with the correct loop + explicit cap writes EV13's
   `.demux.spectra.bin` byte-identical to the defect's; default knobs = defect bytes; correct +
   half-open = the `pwiz-extractfix` bytes.
2. **It is a regression from the reference implementation.** Skyline's TransitionBinner
   (`AbstractDemultiplexer.cs:1113`) is the same loop with the FULL width; C++ (2017, d24a142315)
   used the half-width.
3. **No mass offset.** Neighbour-peak offsets around reference peaks centre on 0 ppm in every m/z
   band (median -0.07..0.00 ppm, ~50/50 intensity either side; 70% within +/-2 ppm)
   (`offsets-ev13.txt`); Osprey calibration MS2 correction -0.23 / +0.10 ppm, SD 2.0
   (EV13/EV14). A -5 ppm shift cannot explain -10..0 as ideal.
4. **The defect only changes the split, and only above half the top m/z.** Regularized output
   conserves each source peak's intensity, so peak counts barely move (`peaks-by-mz.txt`). The
   split: identical below 0.5 of top m/z; in the top band the defect splits evenly far more often
   (largest share < 0.6 for 22.6% of intensity vs 4.7% corrected) (`split-shares.txt`). The defect
   starves neighbour rows, so the solve cannot tell the windows apart.
5. **The corrected code demultiplexes MORE accurately (ground truth).** Fragments of 26,672
   precursors identified by both arms, share given to the window that contains the precursor:
   top band 0.912 corrected vs 0.829 defect; decisively correct 92.1% vs 68.6%; decisively wrong
   1.0% vs 0.7%; identical below half (`assignment-accuracy.txt`).
6. **The lost precursors' own spectra barely change.** For the 4,199 EV13 precursors the corrected
   arm lost, apex fragment assignment is identical below half and moves <= 0.02 above
   (`assignment-accuracy-lost.txt`); they are weak calls (20% of low-m/z fragment intensity goes
   decisively to the wrong window, vs 4% for shared precursors). Losses are uniform over precursor
   m/z, charge and position in the demux bin (`lost-gained-6run.txt`).
7. **The classifier, not the spectra, differs sharply.** One first-pass model per arm (identical
   across runs). Defect: 3 folds agree (min weight cosine 0.984, median_polish_cosine weight
   +3.5..+5.3). Corrected: folds disagree (min cosine 0.363; that weight +3.85 / +0.96 / +0.08)
   although 20 of 21 feature means/SDs agree to 3-4 digits. Across 6 arms fold agreement varies
   0.36-0.98 and tracks IDs only loosely.

8. **Training is decided by a nearly tied C choice on thin evidence.** Only 0.6-0.9% of the 300,000
   training peaks' targets pass 1% FDR during training (~1,000-1,400 positives). C is chosen per fold,
   "most regularized within 1% of the best": defect folds chose 100 / 10 / 1, corrected 10 / 1 / 0.1;
   the C = 0.1 fold is the one whose median_polish_cosine weight fell to +0.08 (regularization, not a
   broken feature). First-pass targets at 1%: defect 89,739, corrected 80,581 (-10%), so the gap is
   there before anything downstream.
9. **EV13-only knob arms** (`D:\test\osprey-runs\pwiz-demux\eclipse-ev13\compare-knobs.txt`; EV13 searched
   alone, so not comparable with 6-run counts):

   | Arm | Precursors | vs defect | C per fold |
   |---|---|---|---|
   | defect | 34,229 | | 1 1 1 |
   | correct span only | 34,063 | -0.5% | 10 1 10 |
   | defect + half-open | 33,128 | -3.2% | 1 1 1 |
   | width-matched, centred | 33,120 | -3.2% | 1 1 1 |
   | shift -5 ppm, +/-5 | 29,527 | -13.7% | 1 1 1 |
   | centred +/-5 ppm | 33,008 | -3.6% | 1 1 1 |
   | correct + half-open (= extractfix) | 33,547 | -2.0% | 1 10 1 |

   The shift is far worse than the centred window of the same width: confirms no offset. On EV13 alone
   the full correction costs 2.0%, against 8.6% for EV13 inside the 6-run search.
10. **Noise floor, measured: ~36 peaks move IDs by 3.2%.** "Defect + half-open" differs from the
    defect only for peaks exactly on a shared bin edge: 432 bytes over the whole EV13 cache (~36
    peaks in 158,700 spectra, worst spectrum cosine 0.9999,
    `spectra-defect-vs-caphalfopen.txt`), yet -3.2% precursors. Identification counts respond to
    trivial input changes by several percent, so few-% arm comparisons are inside the noise, including
    some of last night's.

11. **EV13 noise floor (`eclipse-ev13\compare-seeds.txt`): the gap is inside it, and reverses on
    average.** Percolator seeds 42 (default), 1, 2, 3, 4: defect 34,229 / 32,072 / 34,048 / 34,166 /
    34,369 (mean 33,777, range 6.7%); corrected 33,547 / 34,463 / 34,492 / 34,042 / 34,173 (mean
    34,143, +1.1%, range 2.8%). Fixed C (no selection): C = 1 defect 34,251 vs corrected 33,995
    (-0.7%); C = 10 33,587 vs 33,215 (-1.1%). The seed alone moves the defect by 6.3%.

12. **Six-run: the gap is consistent, NOT noise** (`eclipse-search6\compare-6run-variance.txt`).
    Defect vs corrected: seed 42 38,088 vs 34,718 (-8.8%); seed 1 37,720 vs 34,021 (-9.8%); seed 2
    35,781 vs 30,876 (-13.7%); fixed C = 1 37,431 vs 36,053 (-3.7%). Seed alone moves an arm 6-11%.
    Corrected arms mostly run at lower entrapment FDP (0.33-0.36% at seeds 1-2 vs 0.46-0.49%).
    Training positives at 1% FDR lower for corrected in every pair (0.6-0.8% vs 0.8-0.9%), and
    first-pass targets lower in every pair.
13. **Per-file features do not depend on the other runs**: EV13's scores.parquet is byte-identical
    in the EV13-alone and six-run searches. The six-run gap is in shared training / FDR only.
14. **Feature quality vs model quality, separated** (`frozen-model-ev13.txt`): EV13 features of both
    arms scored under the same frozen first-pass model, targets at 1% (TDC): corrected features score
    MORE under every model (+0.6% six-run defect model, +1.1% six-run corrected, +0.2% / +1.1% the
    C = 1 models, +0.3% EV13-alone model); one-column swaps move at most ~130. But the models trained
    on the corrected six-run pool are worse on ANY data (21,236 vs 24,014 on the same features;
    C = 1: 22,382 vs 23,854). **The fix improves spectra and features; the loss is entirely Osprey's
    first-pass training producing a worse classifier from the corrected six-run pool** - systematic in
    4/4 six-run configurations, absent in EV13 alone.

15. **Same split on every run** (`frozen-model-other-runs.txt`): features equal within +/-1%
    (EV14 -0.6%, Total01 -0.2%, Total02 -0.1%/+1.1%), while the corrected-trained model is 9-11%
    worse on every run's features. The Total runs do not carry worse features.
    Open: systematic or a run of bad draws? Corrected has lost 4/4 six-run draws (p ~ 0.06 if a coin
    toss); EV13 alone it won 3/5. Six-run seeds 3 and 4 queued for n = 5 per arm
    (`run-6run-seeds34.sh`; note the seed harness now passes --perf-stats --verbose, logging only).

16. **Three-run arms: the direction depends on the runs** (`D:\test\osprey-runs\pwiz-demux\eclipse-trios`):
    EV13-15 defect 37,771 vs corrected 33,932 (-10.2%, FDP 0.45% both); Total01-03 defect 7,201 vs
    corrected 7,889 (+9.6%, FDP 0.31% vs 0.15%). With --perf-stats, **the initial feature flips in
    the EV trio**: defect starts Percolator from median_polish_cosine (841 targets at 1%), corrected
    from fragment_coelution_sum (811) - a discrete choice decided by 30 of ~800. Both Total arms start
    from fragment_coelution_sum (333 vs 373), and there corrected wins. Hypothesis: the near-tie in the
    initial feature sets the starting direction the semi-supervised training converges from.
    Intervention queued (`run-init.sh`, measurement-only OSPREY_DIAG_INITIAL_FEATURE, snapshot
    `_bin/pwizdemux-knobs-init`): EV trio defect with no override (must reproduce 37,771), corrected
    forced to median_polish_cosine (should recover), defect forced to fragment_coelution_sum (should
    drop).

17. **Six-run, n = 5 seeds: real and significant** (`eclipse-search6\compare-6run-seeds.txt`).
    Defect 38,088 / 37,720 / 35,781 / 35,850 / 37,722 (mean 37,032); corrected 34,718 / 34,021 /
    30,876 / 32,416 / 35,502 (mean 33,507). Paired differences all negative, mean -3,526 (-9.5%),
    95% CI +/-1,217 (+/-3.3%), paired t ~ -8 (df 4).
    **Initial-feature hypothesis (16) refuted as the cause:** at seeds 3 and 4 both arms start from
    the same feature (xcorr; fragment_coelution_sum) and corrected still loses 9.6% / 5.9%. But the
    same feature on the same seed passes 898 targets (defect) vs 504 (corrected) in the training
    subsample, while full-data features are equal (14-15): the arms train on DIFFERENT subsamples.
    Why: the subsample (one random run per precursor, then a 300k peptide-group draw from ~16M
    candidate peaks) is a hash of the exact entry set, and the corrected arm scores 11,153 more EV13
    entries (2,979,337 vs 2,968,184), so every draw reshuffles.
18. Queued: initial-feature intervention on the EV trio (`run-init.sh`), then six-run defect vs
    corrected with OSPREY_MAX_TRAIN_SIZE=1500000 (5x; `run-6run-train15m.sh`). If a larger training
    set closes the gap, the root cause is subsample-driven training variance in Osprey's first pass.

19. **Initial-feature intervention, EV trio** (`eclipse-trios\compare-init.txt`). Verifier: the init
    build with no override reproduces 37,771 exactly. Defect forced to start from
    fragment_coelution_sum: first pass 65,102 (from 68,735), final 35,242 (-6.7%). Corrected forced to
    median_polish_cosine: first pass 69,224 (ABOVE the defect's 68,735), final 36,518 (from 33,932;
    recovers 67% of the gap, -3.3% remains, FDP 0.39% vs 0.45%). **The starting feature alone moves
    either arm 7-8% and accounts for the first-pass difference entirely**; a near-tie (841 vs 811)
    decides it. Not the whole story: ~3% remains after the first pass is equal (a later stage), and at
    six-run seeds 3-4 both arms started from the same feature and corrected still lost.

20. **A 5x training set closes the gap** (`eclipse-search6\compare-t15m.txt`, OSPREY_MAX_TRAIN_SIZE =
    1,500,000, seed 42): defect 37,627 (FDP 0.56%) vs corrected 37,436 (0.52%), **-0.5%**; first pass
    corrected 89,633 vs defect 89,045. At the 300k default the same pair was -8.8% and the 5-seed
    mean -9.5% +/- 3.3% (every paired difference <= -2,220). Holds although the arms again started
    from different features (xcorr vs fragment_coelution_sum) and picked different C (1 1 1 vs
    1 1 0.1). The defect does not gain from more data (37,627, inside its 300k range). Seeds 1 and 2
    at 1.5M queued (`run-6run-train15m-seeds.sh`) for an interval.

## Root cause (pending the 1.5M seed replicates)

PR 1b's identification loss is not a property of demultiplexing. The corrected search span
demultiplexes better (5), and its features are as good (14, 15). The loss comes from **Osprey's
first-pass Percolator training being underpowered at its default 300,000-peak training cap**: about
1% of the subsample is positive (~1,000-1,400 targets), so the trained classifier depends on which
entries land in the subsample (a hash of the exact entry set, which any change to the spectra
reshuffles) and on near-tied discrete choices (initial feature 841 vs 811; per-fold C within 1% of
the best). On these six runs the corrected pool lands on a worse classifier at every seed tried;
on EV13 alone it does not, and on the Total trio it is +9.6%. With five times the training data the
gap is -0.5%. The defect's "benefit" was a training artifact that its slightly different features
happened to steer toward on this data set.

**What we can apply:** (a) PR 1b can be judged on correctness (it restores the reference behaviour
and demultiplexes better) once training is not underpowered; (b) Osprey's training cap and its
near-tie choices are an Osprey issue in their own right, and arm comparisons at n = 1 (most of last
night's) are inside a 6-11% seed spread at the default cap.

## Ruled out

- Systematic mass offset (3 above).
- Interference outside the window (tails beyond +/-5 ppm hold a few % of matched intensity).
- The defect keeping more high-m/z peaks (4: intensity is conserved; counts within 6%).
- `median_polish_residual_ratio` outliers in the training set destabilizing the SVM: the feature
  IS unbounded (sum|obs - pred| / sum obs in linear space; ~146 entries > 1e12, max 7.1e15, in BOTH
  arms equally), but Mike's arms have a small SD for it (430, 9.6) and are still unstable, and the
  pre-fix pwiz arm has a huge SD and is stable. (Still a real Osprey feature defect to report.)

## In flight

Measurement-only Osprey overrides added: OSPREY_DIAG_SEED (Percolator seed, default 42) and
OSPREY_DIAG_SVM_C (single C, no selection), snapshot `_bin/pwizdemux-knobs-seed`.
- EV13 (`eclipse-ev13\seed-*`, `run-seeds-ev13.sh`): defect and corrected at fixed C = 1 and 10,
  then at seeds 1-4.
- 6 runs: done (12 above).
- Three-run arms (`D:\test\osprey-runs\pwiz-demux\eclipse-trios`, `run-trios.sh`, with --perf-stats
  --verbose to log the initial feature and per-fold iterations): EV13-15 and Total01-03, defect vs
  corrected. Localizes the training trigger: multi-run training as such, or the Total runs.
