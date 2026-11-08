# TODO-20261030_osprey_scoring_library.md - Phase 1

Continued in [TODO-20261030_osprey_scoring_library-phase2.md](TODO-20261030_osprey_scoring_library-phase2.md) and then
the active [TODO-20261030_osprey_scoring_library.md](TODO-20261030_osprey_scoring_library.md). Frozen; do not edit.

## Branch Information
- **Branch**: `Skyline/work/20261030_osprey_scoring_library` (local, not pushed), cut from Mike's
  `Skyline/work/20261028_osprey_diann_fdr_gap` at 2674437153 (pushed 2026-10-30); split into focused PR branches
  on 2026-11-02 (A/B/F below)
- **Checkout**: `D:\Users\brendanx\proj\pwiz-scores` (worktree, MACS2); PR worktrees `pwiz-gbtfast`, `pwiz-tworound`,
  `pwiz-scorelib`
- **Base**: Mike's FDR-gap branch (TODO-20261028_osprey_diann_fdr_gap.md, PR #4950), then `master`
- **Module**: `osprey`
- **Created**: 2026-10-30
- **Status**: Phase 1 complete (2026-10-30 to 2026-11-03): #4967 and #4968 merged to master, #4969 merged into #4950.
- **Split**: 2026-11-07 into phases. This file holds the phase-1 log as it was written, the PR summaries, and detail
  recovered from the sessions' uncommitted status files (`ai/.tmp/agent-*-status.md`, handoffs) on MACS2.

## PRs in this phase

### #4967 - Sped up Osprey GBDT training ~40x with thread-count invariant models
[#4967](https://github.com/ProteoWizard/pwiz/pull/4967), base master, merged 2026-11-03 as `049d045e98`. Branch
`Skyline/work/20261102_osprey_gbdt_speedup` (worktree `pwiz-gbtfast`).
- Root cause: `GbtParams.MaxDegreeOfParallelism` was never set on the FDR path, so each of the 3 fold models trained
  on one thread. Each fold now gets NThreads / NFolds.
- Inside a tree: parallel binning, gradients, margin updates and stable partition; per-tree gather into partition
  order; 4-feature interleaved histograms with histogram subtraction; fixed row chunks whose count depends only on the
  node's row count, so a model is identical at any thread count. Leaf values from exact in-order sums.
- `DeterministicMath` (Osprey.Core): managed fdlibm 5.3 exp/log for the GBDT sigmoid and base score.
  `Math.Exp` differs between Windows UCRT and glibc on near-halfway cases, so GBDT models differed by ULPs across OS.
  Now bit-identical at 1-16 threads on both. `OSPREY_DETERMINISTIC_MATH=0` restores System.Math (keyed `;gbtmath=system`).
- 200-tree fit: 300k rows 151.7 s (1 thread) -> 15.9 s (4); 1M 1,049 s -> 26.6 s (16); 4.28M ~6,650 s -> 170 s.
  SEA-AD 3-file Percolator training 7.3 h -> 10 min. Histogram subtraction moved one SEA-AD GBDT first pass
  49,245 -> 49,416 (exact-tie splits; within seed noise). SVM default untouched; goldens unchanged.
- Gates: 649/649, GBDT goldens bit-identical Windows/WSL at 1-16 threads, new 40k-row MLTest at-scale golden,
  Stellar regression, TC Perf/Regression 4248590 and Osprey Linux .NET green.

### #4968 - Added opt-in out-of-fold scoring and two-round GBDT first-pass training
[#4968](https://github.com/ProteoWizard/pwiz/pull/4968), stacked on #4967 then retargeted to master, merged
2026-11-03 as `4ec653c0d4`. Branch `Skyline/work/20261102_osprey_gbdt_two_round` (worktree `pwiz-tworound`).
- `OSPREY_GBT_OOF=1`: each training row scored only by the fold model that held it out. Needed once training covers
  most rows (in-sample, every row: FDP at q 1% 1.02-1.21%).
- `OSPREY_GBT_PREFILTER_SIZE=N`: round 1 on the random 300k subsample; its fold models score every best-per-precursor
  candidate (OOF for round-1 rows); round 2 retrains on the N rows of the best-scoring peptide groups (pairs kept
  together), seeded by round-1 scores. Training on the hardest candidates is what moves the count.
- A10_014 on master's features: SVM 31,698 (0.65%); GBDT 34,922 (0.63%); GBDT + OOF + two-round 200k 38,448 (+10.1%,
  0.64%); 300k 38,516. After DeterministicMath: 36,734 -> 39,846 (+8.5%). 3 files on the wide feature set
  54,531 -> 59,429; detections in all 3 runs +3,109 with no entrapment increase, in one run only +1,185 with +90
  entrapment.
- Known limit carried forward: second-pass rescoring (FrozenModelScorer, PerFileRescore) scores training rows with
  the fold mean, not out of fold. A run with OOF retrains rather than adopting a saved first-pass model.
- Gates: 650/650 after merges, fdrbench byte-identical across the PercolatorEngine refactor merge,
  TestGbdtPrefilterTraining, Stellar regression, TC 4248751 green.

### #4969 - Added 56 candidate scores to the feature mask and dropped masked features from the FDR matrix
[#4969](https://github.com/ProteoWizard/pwiz/pull/4969), INTO Mike's #4950 (`Skyline/work/20261028_osprey_diann_fdr_gap`),
merged by Mike 2026-11-03 as `5340c30909` (with his Copilot fixes f33860f583); Mike asked that further work go to his
branch and reviews it within #4950. Branch `Skyline/work/20261102_osprey_score_library` (worktree `pwiz-scorelib`).
- 56 new PIN features in calculator families, masked by default, unmasked by name with `OSPREY_FEATURE_MASK`:
  median-polish top-k; reference correlation; peak profile; time correlation, M+1 isotope / tight-tolerance and peak
  dominance (ported from open-source DIA-NN 1.7.12 `src/diann.cpp`, CC BY 4.0, credited at each port); top-3-fragment
  and wide-span co-elution.
- Masked features are absent from the FDR matrix (not zero columns): `LoadPinFeaturesFromParquet` reads only unmasked
  columns; names travel into the model and `.1st-pass.model.json`; FDR tasks keyed `;fdrcols=unmasked`. The SVM's
  21-column form now matches master exactly (zero columns are not neutral in SIMD floating point).
- Stage 4 computes only the families the mask reads; `OSPREY_RECORD_ALL_FEATURES=1` (research) records all 97
  (116 columns, ~455 MB per Stellar file), keyed `;featrec=`; a reader needing a missing column refuses the file.
- Experiment switches: `OSPREY_TC_HALF_WINDOW`, `OSPREY_MIN_RT_TOLERANCE`, `OSPREY_FDR_TRAIN_FDR`, `OSPREY_FDR_SEED`,
  `OSPREY_NO_PREFILTER`, `OSPREY_LOESS_BANDWIDTH`.
- Value (SEA-AD 3 files, GBDT, FDP 0.5%, 3 seeds): peak profile 43,220 -> 46,204 (+6.9%); time correlation 46,738 ->
  49,692 (+6.3%), SVM 39,998 -> 45,271 (+13.2%). A10_014 with #4968: master's 21 features 38,448 -> all unmasked
  54,107.
- Gates: 657/657, Stellar exact golden, regression-parallel All 48/48, Test-PerfGate -0.6%.

## Goal (Brendan, 2026-10-30)
Build a large library of candidate scores as Osprey calculator classes (one class per score, Skyline's
IPeakFeatureCalculator architecture) from every source we can find - Skyline/mProphet/NextGen, maccoss/osprey,
DIA-NN 1.7.12 (src/diann.cpp is CC BY 4.0), EncyclopeDIA, OpenSWATH - and value them systematically. What Osprey
uses stays a table in code (OspreyFeatureCalculators + DEFAULT_MASKED_FEATURES), unless the evidence says a
NN-style combiner over 100+ scores is required to compete.

## The two tight loops
1. **Record**: `--task PerFileScoring` with every feature unmasked (`OSPREY_FEATURE_MASK=none`,
   `OSPREY_XIC_FRAGMENTS=12` for HRAM). SEA-AD 3 files: 7 min on MACS2.
   Launcher: `ai/.tmp/sessions/20261028-diann/seaad-scoring3.ps1 -Exe <snapshot> -Tag <tag>`.
2. **Value with Osprey** (preferred since 51318083fd): `-Task FirstPassFDR -LinkFrom <scored run>` with
   `OSPREY_FDR_FEATURE_MASK=<names>`, ~5 min per arm; matrix driver `ai/.tmp/sessions/20261028-diann/fdrmask-matrix.ps1`.
   Mask check: x6 pin21 reproduces master's 35,654 exactly.
3. **Screen offline** (approximate; reads ~15% low on wide feature sets): `ai/.tmp/sessions/20261028-diann/feature_ablation.py <run dir> <peptide fasta> <out.tsv>
   --variants ... [--model svm|gbdt] [--seed N]`. Percolator-style linear SVM (3 folds by peptide, random run per
   precursor, best-feature seed, train FDR 1%, paired competition, best run per precursor), measured by entrapment
   FDP. Validated on master scores: 35,057 vs Osprey's own 35,654 at FDP 0.5% (SEA-AD 3 files).
   Variant grammar: `pin21`, `mike41`, `all`, `<base>+group-group`, `+g+g`, `-feature`, `groups`, `loo`.

## Evidence that set the direction (night 2026-10-29, `ai/.tmp/handoff-20261030.md`)
- Gap at matched FDP 0.5% vs DIA-NN 2.7 no-MBR: Astral -39%, SEA-AD -53..-57% (1 to 82 files), TDP43 -59%.
  Engine, not library/decoys (DIA-NN on Osprey's Carafe library still +92%); 86% of misses on the same peak.
- Losses concentrate in low-intensity precursors; same-peak misses have collapsed apex/MS1 scores.
- 21-feature ablation: no reweighting moves > ~2%; multiscan group carries the most (-37% without it).
  New information is needed, not feature selection.
- DIA-NN 1.7.12 catalog: `ai/.tmp/diann-1.7.12-score-catalog.md` (110 scores, line refs, Osprey mapping, shortlist).

## Tasks
- [x] Median-polish top-k family (rank2..4, top3 mean, median, good-fit count) - 5ac97179ea
- [x] Value it (Osprey FirstPassFDR, SEA-AD 3 files, FDP 0.5%): x6 pin21 35,654 / +mpk 35,112 / mike41 39,023 /
      all47 39,935; x12 pin21 36,330 / +mpk 37,523 / mike41 40,110 / all47 41,956. mp_topk +3-5% at 12 XICs only.
- [x] OSPREY_FDR_FEATURE_MASK (51318083fd), 647/647 tests
- [x] Osprey MaxTrainSize 300k vs 3M: no change (41,956 vs 41,895; SVM era, all47); Osprey fold calibration and pair ties are sound
      (superseded for GBDT all80: full size +5-6%, see 2026-11-01)
- [ ] Correlation-cluster drops and forward selection in the harness
- [ ] Peak-shape reference chosen by mutual correlation / consensus instead of max intensity
- [ ] DIA-NN shortlist that needs no new extraction (pRef, pRT, AA composition), then extractor work
      (tight-tolerance XICs, shadow XICs at -1.00336, MS1 M+1/M+2, all library fragments, wider window)
- [x] Rebase onto Mike's PR #4950 (masking moved to FDR load)
- [ ] Ask Mike: record unmasked values always and mask only in the FDR model (today masked = written as 0)
- [ ] Tell Mike: inspection flags OspreyEnvironment.cs:782 (OSPREY_DUMP_RUN_PEP, PossibleNullReferenceException)

## Progress log
- 2026-10-30: Branch from Mike's 2674437153. Added MedianPolishTopKCalculators.cs (6 features, slots 41-46,
  masked by default). 644/645 then 645 tests (TestNoUnstableSort exemption). Scoring run
  `osprey-runs\sea-ad\runs\seaad-3files-...scores3-mpk1-xic12-nomask` (snapshot `_bin\scores-mpk-wip1`).
- 2026-10-30: Reference-correlation family 2cd2bb60c4 (648/648 tests): redundant with mp_topk (all53 41,555 vs
  all47 41,956 SVM). GBDT (OSPREY_FDR_MODEL=gbdt): pin21 38,449, mike41 42,235, all47 40,511, all53 43,587 (best;
  GBDT variance not yet measured). DIA-NN same library: 68,418.
- 2026-10-30: Skyline review docs `D:\Users\brendanx\test\diann-vs-osprey\seaad\review3\` (diann.sky, osprey.sky):
  libraries attached with --add-library-path (Osprey full3-all47-xic12 out.blib; DIA-NN BlibBuild of report-lib.parquet),
  targets from review_lists.fasta (>> peptide lists, ++ charges; 380 precursors in 5 groups); boundaries verified
  98-100% equal to each tool's. Builder `ai/.tmp/sessions/20261028-diann/build-review-doc.ps1`; Skyline built from
  pwiz-scores with -VendorLicenses (Brendan approved). Next: Osprey picks for its misses (shared Carafe library +
  scores.parquet bounds), a PauseTest review test driven over the Skyline MCP, annotations from review_precursors.tsv.
- Findings to file: (1) Import Peptide Search on an Osprey .blib keeps only the best run's RetentionTimes row
  (56,839 of 169,612); (2) DiaNNSpecLibReader.cs header says Parquet is unsupported, but BlibBuild reads it;
  (3) document the >> peptide-list format in --import-fasta help (own Skyline branch?).
- 2026-10-30 pm: Skyline MCP works (TestCEOptimizationTutorial + PauseTest, -AiConnector). Review harness
  `pwiz-scores\pwiz_tools\Skyline\TestFunctional\OspreyDiannReviewTest.cs` (UNTRACKED, never commit) opens
  review3\diann.sky then osprey.sky with a PauseTest each. Picture: `review3\VVDVLDSIK_side_by_side.png` -
  VVDVLDSIK 2+ run A10_014, same peak and bounds in both, DIA-NN q<0.001, Osprey pass 1 q 0.016 (score 0.446 vs
  threshold 0.767; passes pass 2). Best DIA-NN-only same-peak misses are clean, near-threshold (q 0.011-0.03),
  often short (7-mer recovery 49% vs ~60% for 10-15-mers).
- Score decomposition (`sessions\...\explain_score.py`, weight x z vs passing median): heavy-tailed features with
  wrong-signed weights penalize the strongest peaks - explained_intensity (mean 0.003, SD 0.010, weight -0.134;
  clean peaks at 0.2 = 20 SD -> -2.5 to -3.0), mp_n_fragments_good_fit (-0.253), peak_sharpness (-0.507),
  frag_rank1_intensity_share (-0.26; VVDVLDSIK's library is y7-dominated). Masking them costs IDs (41,054 / 40,606
  vs 41,956), so they carry information; testing OSPREY_FDR_FEATURE_LOG (sign*ln(1+1000|v|)) instead.
- Skyline findings: (4) `--import-fasta` `>>` peptide lists save as <protein label_name=...> with no name attribute
  and fail schema validation (TestOspreyDiannReview end-of-test check, line 122); (5) a library added with
  --add-library-path is found again by file name beside the document - build-review-doc.ps1 now copies it there.
- 2026-10-30 pm: OSPREY_FDR_FEATURE_LOG 26df050ad2 (648/648). log(explained_intensity): VVDVLDSIK q 0.016->0.003,
  SVEETLR 0.020->0.002, FTGSEIR 0.082->0.005, but GVIECLK (50x weaker) 0.016->0.046; aggregate 40,866 vs 41,956
  (log4 41,149). One linear weight cannot serve both intensity regimes. GBDT rescues the strong peaks with no
  transform (all47: VVDVLDSIK 0.001, SVEETLR 0.002) and all53-GBDT keeps GVIECLK at 0.014 (SVM 0.091) - the
  interaction a nonlinear combiner models is what the linear SVM is missing on these peaks.
- 2026-10-30 eve: why explained_intensity is negative (`sessions\20261028-diann\ei_probe*.py`, `.out`). It is a
  ratio (matched / apex-spectrum TIC), so #4412's log10 conditioning of absolute intensities never covered it. The
  negative weight is in master too (pin21: -0.169 at 3 files, -0.197 at 21) and survives log (logexpl -0.175).
  Alone on the training contrast (1% targets vs decoys) it is strong and positive (AUC 0.868; apex 0.703); in a
  47-feature logistic it turns -0.48, and no single removal flips it - it is collinear with the quality family
  (mp min fragment R2 +0.69, good-fit count +0.62, SG xcorr +0.56), so the model weights only its abundance residual,
  negatively, and that penalty grows without bound in the tail (clean strong peaks). log10 sharpness = 1.12 x log10
  apex + const (Spearman +0.90 on positives); its residual after apex has AUC 0.484, so it carries no shape
  information and the -0.507 / +0.395 pair is a width proxy (targets 0.145 min vs decoys 0.094). Supports #4466
  part 2. Next: a bounded EI (clip at a decoy quantile) vs EI split into log matched intensity + quality; width or
  scale-free sharpness in place of log sharpness.
- 2026-10-30 night (rebased on #4950; FDP 0.5%, 3-seed means, seed SD ~1-2%):
  - Peak-profile family d26b840900 (width, 5 shape bins, local corr, library-relative, window shares; 53-70): GBDT
    43,220 -> 46,204 (+6.9%), SVM nothing (40,797 -> 39,998).
  - Time-correlation family d50bf04e4d after DIA-NN pTimeCorr/pResCorr (71-79): GBDT 46,738 -> 49,692 (+6.3%),
    SVM 39,998 -> 45,271 (+13.2%) - the first family that helps the linear SVM. Half-window (e4c4873c6e,
    OSPREY_TC_HALF_WINDOW): 0.08 min 47,579, 0.15 49,692, 0.25 50,537; 0.40 queued.
  - M+1 isotope / tight-tolerance 29ccf4ed2c (80-84): +0.7% (noise) once tc_* is in.
  - Peak dominance 912e4585ff (pBestCorrDelta, pTotCorrSum, apex count, margin; 85-88): queued.
  - GBDT hyperparameters (600 trees lr 0.05, depth 8, depth 4): none beat the default (49,884). Offline harness: a
    bagged sklearn MLP is near the SVM (41,673 vs GBDT 45,850 on the profile run). The classifier half of the
    DIA-NN gap is not a stronger learner on the same rows.
  - DIA-NN 1.7.12 bisection (`D:\Users\brendanx\test\diann1712\REPORT.md`): on one file, ~half the gap is
    features, ~half DIA-NN's NN/filters; strongest pTimeCorr, pTightCorrOne, pLocCorr, pCos.
  - Coverage: RT-calibration tail defect - 181,780 precursors at library RT 19.0-19.5 predicted ~19.8 min, found
    by DIA-NN at ~21.3, outside the +/-0.58 min window: 3.3-4.2% of DIA-NN's IDs per file. Report to Mike.
  - D: filled at 00:29 (762 MB free); runs now delete their FDR arm folders after recording results.
- 2026-10-31/11-02 (night 2 and day). Metric: real targets at entrapment FDP 0.5% (combined estimator), SEA-AD
  A10_014 single file unless noted. Comparisons with external tools are kept privately
  (`U:\tools\claude\diann-study\`, reports under `D:\Users\brendanx\test\diann-versions\`); this log keeps
  Osprey's own results.
  - Training-set size is the classifier lever with iterative q<=1% labels (Python bench `clflab\`): random
    300k 49.3k, 1M 50.6k, all 4.3M rows 52.2k; bagging/folds noise; all-vs-all labels worse.
  - Out-of-fold scoring of training rows (1157b75cac, 79f77a3302; OSPREY_GBT_OOF=1) is required once training
    covers most rows: in-sample 3-file all rows gave FDP at q 1% 1.02-1.21%. With OOF: 1M 50,834 (0.63%),
    all rows 51,975 (0.61%); 3 files all rows 56,684 (0.85%) vs 54,531.
  - GBDT speedup 996b6d15af (~40x; folds had trained on 1 thread each; thread-count invariant; 300k first
    pass 49,245 -> 49,416 from last-bit histogram sums).
  - Two-round training f94bf045b2 (OSPREY_GBT_PREFILTER_SIZE=N): round 1 as now, score every candidate (OOF),
    retrain on the top-N peptide groups seeded by round-1 scores. A10_014 + OOF, 3 seeds x 200k/300k:
    53,230-53,934 (FDP at q 1% 0.58-0.62%), +9%. 3 files 200k: 59,429 (0.77%) vs 54,531; per run 45,933 ->
    49,261, 43,979 -> 47,140, 49,943 -> 53,792. Runs-detected (per-run q<=1%, 1/2/3 runs): 15,428 / 11,744 /
    39,428, entrapment 472 / 53 / 12 (baseline 14,243 / 10,847 / 36,319; 382 / 57 / 12): 3-run +3,109 with no
    entrapment increase; 1-run +1,185 with +90 entrapment. Bagging, 5 folds, more trees, a third round: noise.
  - Fragment tolerance (Brendan flagged it at the outset): the main search replaces the configured 10 ppm with
    the calibrated |mean| + 3 SD of confident matches = 4.58 ppm, not logged at default level. Wide-window
    histogram on accepted targets: SD 2.45 ppm overall, 5.06 / 2.47 / 1.30 by intensity tercile; |mean| + 3 SD
    over all matches ~7.4 ppm. Brendan: run slightly too wide, read the histogram, set |mean| + 3 SD; SD rarely
    < 2 ppm; < 5 ppm is very tight; in 2014 a too-wide window cost Skyline ~20%.
    - 40482fe670: OSPREY_MIN_FRAGMENT_TOLERANCE floor + the calibrated tolerance logged. Uniform floor, full
      pipeline: 5.5 ppm 53,935 = control 53,934; 7 ppm 53,362; 12 ppm 51,113. A wider tolerance moves the
      apex onto interference (~5.5% of real targets at 7 ppm) and helps decoys more than targets on the
      intensity-pattern features; correlation-shape features gain on weak precursors (dAUC +0.04..+0.10).
    - 7177775469: per-file fragment mass-error plot in CAL > Summary beside the calibration corrections table.
      The table's tolerance column (|mean|+3SD) is not what the search uses (3 SD about the corrected mean).
    - 307d273f2e: OSPREY_CORR_FRAGMENT_TOLERANCE re-extracts the chosen peak for 40 correlation-shape features.
      Unmasked, 3 seeds, FDP 0.5 / 0.75 / 1%: control 54,107 / 56,344 / 58,223; 7 ppm 54,797 / 57,324 / 59,064
      (+1.3-1.7%; every 7 ppm seed above every control seed at 0.75% and 1%). Small, real.
    - OSPREY_TC_HALF_WINDOW 0.40 still beats 0.15 (51,592) and 0.25-0.55 at every tolerance tried.
  - Brendan (2026-11-01 evening): changes of a few hundred are noise (seed range 53.2-53.9k); single-run Osprey
    is at a ceiling near 54k. Osprey's linear SVM on A10_014 at window 1.0: 45,054 unmasked (43,652 masked);
    GBDT adds ~20%. The remaining per-run gap looks like features, not the classifier.
  - Protein-shuffle entrapment audit (Brendan's idea, 2026-11-01; `diann-versions\protshuf\REPORT.md`):
    reassign each entrapment peptide's protein at random among target + entrapment proteins (decoys follow
    their paired target); same spectra and pairs, so any change is caused by protein information.
    - Osprey pass 1: identical under the shuffle (negative control).
    - Osprey pass 2 protein-compact: entrapment on detected target proteins 37 -> 291 at q 1% (10x boost);
      FDP at q 1% 0.53% -> 1.28%, ~2.3% protein-aware; ~57,900 at FDP 0.5% is fairer than nominal 68,692.
    - A protein-aware scorer whose decoys carry their target's protein (symmetric boost) stays calibrated under
      the same audit; protein-compact admits proteins by counting target peptides only (#4581).
    - The standard entrapment design (entrapment on its own proteins) cannot see protein-aware inflation.
- [ ] Fix pass-2 protein-compact FDR: decoys must get the same protein evidence as their paired targets;
  re-measure with the shuffled library (`protshuf\lib\osprey-shuf`). Filed: #4581 (gate target-conditioned,
  oracle cannot audit it; 1.51-1.53% at nominal 1% on 82 files, a lower bound), #4580 (continuous
  sibling-evidence feature), #4538 (validate protein-compact). Nick's #4823 is the separate protein-GROUP
  q-value fix and does not change the stratum or precursor q.
  - [ ] Draft a #4581 comment (method and Osprey tables) for Brendan's review
- [ ] Make a protein-shuffled entrapment arm a standard FDRBench check for any protein-aware pass
- [ ] PR branches (2026-11-02, worktrees, NOT pushed; push/PR only with Brendan's OK):
  - A `Skyline/work/20261102_osprey_gbdt_speedup` (`pwiz-gbtfast`, off master): 887f273bec, gate 646/646;
    review fixed (empty-bin guard on hessian only, ScoreRows serial below 20k rows/slice, docs); PR text
    `ai\.tmp\sessions\20261028-diann\pr-A-body.md`.
  - B `Skyline/work/20261102_osprey_gbdt_two_round` (`pwiz-tworound`, on A): OOF + two-round, env-list
    conflicts resolved to the 2 new switches; gate 647/647; review fixes in progress. SEA-AD A10_014 on
    master's features (`fdrmask-masterB`, FDP 0.5% / FDP at q 1%): SVM 31,698 / 0.65%; GBDT 34,922 / 0.63%;
    GBDT + OOF + prefilter 200k 38,448 / 0.64% (+10.1%); 300k 38,516 / 0.62%. Known limitation: pass-2 rescoring scores training rows with the
    fold mean.
  - F `Skyline/work/20261102_osprey_score_library` (`pwiz-scorelib`, on Mike's #4950 4e40a99310): 14
    commits; review fixes in progress (dropping OSPREY_FDR_FEATURE_LOG/CLIP/SHARPNESS, keying TRAIN_FDR,
    peak-dominance flagged set, clamped apex; measuring the cost of always-computed masked features).
  - Plan (Brendan, 2026-11-02): F is a PR INTO #4950 (base `Skyline/work/20261028_osprey_diann_fdr_gap`),
    like the .NET 10 port's growing PR; A, B, C are PRs to master that reach #4950 by merging master.
    B opens with A's branch as base, retargeted to master after A merges.
  - F review fixes bb8e469da9 (656/656, Stellar golden). Perf gate FAIL: total 3:52 -> 5:42, Stage 5
    1:39 -> 3:16 because masked features stay as zero columns (97 vs 41). Fix in F (agent maskcols):
    drop masked columns from the FDR matrix; SVM output identical, GBDT may change.
  - Worktrees pwiz-gbtfast, pwiz-tworound, pwiz-scorelib created without asking (CRITICAL-RULES); keep
    until the PRs merge unless Brendan says otherwise.
  - OPENED 2026-11-02: #4967 (A, master), #4968 (B, base = A's branch; retarget after #4967 merges), #4969 (F,
    into #4950). Perf gate vs master (pwiz-perfbase 728ff3a131): A 0.0%, B -1.2%, F -0.6%. TeamCity
    Perf/Regression: #4967 build 347 SUCCESS, #4968 build 348 SUCCESS, #4969 build 4246788 running.
  - F additions: 552332ce97 masked features absent from the FDR matrix (Stellar exact golden); b3798b87cf
    Stage 4 computes only families the mask reads, OSPREY_RECORD_ALL_FEATURES=1 research switch, ;featrec=
    key; parquet = master size. Local regression-parallel All on b3798b87cf: 48/48 PASS.
  - 2026-11-03 MERGED #4967 as 049d045e98 (GBDT speedup + DeterministicMath fdlibm exp/log, GBDT
    bit-identical Windows/Linux at 1-16 threads; TC Perf/Regression 4248590 and Osprey Linux .NET green).
    #4968 retargeted to master. Master (12 small PRs) merged into #4967, #4968, #4950 and #4969 first.
  - 2026-11-03 MERGED #4968 as 4ec653c0d4 (OSPREY_GBT_OOF + OSPREY_GBT_PREFILTER_SIZE, opt in; TC 4248751
    green). Night plan: master -> #4950 -> #4969; PR C+D (branch 20261103_osprey_fragment_tolerance) on
    #4969; PR E (20261103_osprey_protein_compact_symmetric) on master.
- [ ] Split this branch into focused PRs (A speedup; B OOF + two-round; C tolerance log/floor + mass-error plot;
  D corr tolerance; E protein-compact fix + shuffle audit); reword commit messages to describe Osprey's
  changes on their own merits before anything is pushed; base on Mike's #4950
- [ ] Why some confident IDs inside Osprey's RT window have no scored row (776 on A10_014)
- [ ] Fewer Percolator iterations at full size (training-target fraction flat from iteration 5)
- Commits (local, not pushed): 996b6d15af speedup, f94bf045b2 two-round, 40482fe670 ftol floor + log,
  7177775469 mass-error plot, 307d273f2e corr tolerance.

## Recovered detail (2026-11-07)
From the sessions' uncommitted status files on MACS2 (`ai/.tmp/agent-*-status.md`,
`handoff-2026103*.md`). Paths: `seaad\` = D:\Users\brendanx\test\diann-vs-osprey\seaad\, `_bin\` =
D:\Users\brendanx\test\osprey-runs\_bin\, `sessions\` = ai\.tmp\sessions\. Tags name the PR each item fed.

### 2026-10-30

- Gendecoy is miscalibrated: Osprey generated (reversed) decoys on SEA-AD 3 files give FDP 1.76% at q 1% vs library
  decoys 0.66%, with the same ~35.6k at matched FDP 0.5%. [research, unmerged]
- `ai/scripts/Osprey/Common/OspreyDatasetRun.psm1` gendecoy arm never passed the pairing manifest, so current Osprey
  refused the library (`_p_target` entrapment unpaired). An elseif was added, UNCOMMITTED, needs review. [unmerged]
- 21-feature offline ablation, group drops at FDP 0.5% (`seaad\ablation3\sweep.tsv`): multiscan -37%, coelution -8.5%,
  rt -5.5%, median_polish -4.2%, apex_spectrum -3.7%, mass +0.4%, ms1 +1.4%, shape +1.8%. Apex-spectrum scores are not a
  liability for the linear model (an earlier reading was wrong). [research, fed #4969]
- DIA-NN (aggregate) on SEA-AD: MBR is worth about +2% on both Astral and SEA-AD, so MBR is not a factor in the gap. [research]
- Coverage agent (A10_014): isolation windows are [center,width], 167 x 3.0 Th, coverage 400.43-901.66 m/z; only 5,070
  library targets fall outside. 1,116,809 of 3,089,390 library targets (36.1%) are in-range candidates dropped in
  PeakDataExtractor.TryExtract (prefilter 2-of-top6 in 3-of-4 scans at :123, or no CWT peak at :162). Other drop points:
  :88 nScans<5, :112 RT range, :150 xics<2; dedup ScoringPipeline.cs ~320; candidate select CoelutionScorer.cs:111-118.
  [research, fed #4998]
- BiblioSpec RT loss root cause (agent blibrt): BlibBuilder.TransferLibrary (BlibBuilder.cs ~493) -> BlibCopier.CopySpectrum
  copies no RetentionTimes; BlibFilter.CompAndInsert writes one RT row per redundant spectrum. Repro: BlibBuild -s -A -H -o
  -c 0.99 -i osprey + BlibFilter -b true -> RT rows 169,612 -> 56,839. Retired C++ never copied them either (6dd40d8c93^):
  long-standing, not a port regression. Also lost: LibMetadata osprey.* (6 rows), per-run RT score, DecoyPairs.
  [unmerged: pwiz-blib branch 42d9c53126, 26ea0d9a9d, no PR; issue #4948 filed]
- Gotcha for a BiblioSpec fix: Skyline IsRedundantLibrary (BiblioSpecLite.cs:338) means "no RetentionTimes table", so
  adding RT rows to a redundant library would make Skyline skip BlibFilter. No BiblioSpec test uses a non-redundant .blib
  input. [unmerged]
- PR #4950 research (agent pr4950): Mike's head 80f7c2469d contained 2674437153; only 3 commits beyond it (fbab5a883c mask
  moved to FDR load = PinFeatureMask with ;xic= / ;featmask= keys; 4145709c7d master merge; 80f7c2469d review fixes, recon/pep
  in FDR keys, RECONCILIATION=off removed). Mike's OSPREY_FEATURE_MASK duplicated our OSPREY_FDR_FEATURE_MASK, so ours was
  dropped in the rebase (51318083fd). Slots 41-70 needed no renumbering. [#4969]
- Rebase (agent rebase): backup ref backup/scoring-library-pre-rebase at eeb06510e1; 5ac97179ea, 2cd2bb60c4, 26df050ad2
  (LOG owns ReadFeatureColumn), c24924dec5, eeb06510e1 replayed; HEAD e128b11567 after a validity-key commit, 651/651 tests.
  Second backup ref backup/scoring-library-pre-rebase2 when rebasing onto 01853d89f1. [#4969]
- Heavy/tight family 29ccf4ed2c (agent heavy): Osprey.Scoring/ReextractedCorrelationCalculators.cs, slots 80-84
  (heavy_sum6, heavy_n_good, tight45_sum6, tight20_sum6, tc_best_sum6), reusing the TimeCorrelations window. [#4969]
- DIA-NN 1.7.12 (open source) study (agent diann1712, D:\Users\brendanx\test\diann1712\): `--candidate-psms` is a flag with
  no file argument (diann.cpp:1833); dump goes to <temp>/<run>.psms.tsv, one row per candidate peak of every target and
  decoy, written in the final linear pass, columns Precursor, Decoy, Score, RT, 0..109; no q or NN score. [research]
- 1.7.12 gotchas: it always writes <lib>.speclib beside a TSV library (moved to diann1712\lib\); full 3.09M-precursor dump
  runs ~55 MB/min (global spin-lock formatting), ~50 GB / 15 h, so it was aborted for a 6% stripped-peptide subsample
  (carafe_sub06.tsv, 185,281 precursors, 29:38 run, 2.7 GB dump, 8.9 candidates per precursor). msconvert 3.0.22182 needs
  --ignoreUnknownInstrumentError for Astral Zoom; A10_014 mzML 4.48 GB, ~30 min single-thread. [research]
- 1.7.12 on the 6% subsample: 3,451 at 1%; 68 entrapment (E/T 2.0%); best-by-linear candidate apex == report RT 99.78%;
  95 usable scores (15 all-zero). Univariate AUC: pTimeCorr 0.988, pTightCorrOne 0.982, pLocCorr 0.970, pCos 0.970,
  pMinCorr 0.967. 30% of 1% IDs have Ms1.Area 0 (sparse Astral MS1). [research, fed #4969]
- 1.7.12 bisection (analysis\bisect.tsv), real targets at 1% entrapment FDP on identical precursors: DIA-NN own 3,209;
  DIA-NN scores + our linear/GBDT 2,824-2,928; Osprey 71 features + same models 2,293-2,660; join test Osprey only 2,686,
  + shuffled nulls 2,734/2,760, + all DIA-NN 3,120. Group drops: -frag_coelution, -intensity_spectrum, -rt matter. [research]

### 2026-10-31

- Peak dominance 912e4585ff (agent dominance): PeakDominanceCalculators.cs slots 85-88 from 1.7.12 peaks() 7423-7536 and
  score 7715-7717; snapshot `_bin\scores-dom-wip1`. [#4969]
- Top-3 fragment and wide-span coelution families 606c841d00 (agent top3): TopFragmentCalculators.cs slots 89-92,
  WideSpanCoelutionCalculators.cs slots 93-96; 656/656 tests; snapshot `_bin\scores-top3-wip1`. Not valued in the TODO;
  a later offline ablation (2026-11-04 decomp) found -wide 51,999 vs all 51,713 (proxy noise ~+/-300): wide_* adds nothing.
  [#4969]
- GBDT diagnostics (agent gbdtdiag): GBDT q 1% experiment FDP 0.72% combined (0.70% paired) vs master SVM 0.66%; decoys
  outnumber entrapment in the tail for both models (conservative). Found that the streaming path scores training rows
  in-sample with averaged fold GBDTs (PercolatorScorer.ScoreProjectionAndComputeFdrInPlace) - the origin of OOF. [#4968]
- Per-run vs global model (agent perrun, `seaad\perrun\`, perrun.py): LinkFrom a 3-file scoring run works for 1-file runs
  (hard links, no re-score). Per-run models do NOT beat the global model: per-run mean -16..-556 at FDP 0.5%, -178..-711 at
  1%, experiment level tie. Seed noise per run is large (A10_014 49,221 vs 47,529). ~8 min per arm. [research, rejected]
- RT split (agent rtsplit, `seaad\rtsplit\`): a wide-RT arm gained 6,424 (coverage 2,444 + same-peak 3,783 + other 197) and
  lost 2,480 (2,364 same peak); tail bin 19.0-19.5 gave 905 gained (827 coverage); library RT saturates at 19.49 while
  elution reaches 21.7. Gotcha: two scoring runs with different RT floors also differ in calibration points, so MS1/MS2
  tolerances and corrections differ and same-apex rows differ in most features. [research, fed #4998]
- Weak-peak study (agent weakpeaks, REPORT.md in its folder): Osprey global GBDT on weak same-peak precursors vs matched
  decoys AUC 0.92, TPR at FPR 0.1% 0.31; weak Osprey peak width 7.2 s; tc window 0.40 gain small. GBDT run-level q 1%
  39.8k / 37.7k / 42.9k per run (est. FDP 0.60-0.69%). [research]
- Peak re-pick (agent repick, D:\Users\brendanx\test\diann1712\repick\ step12.md, step12c.md, step3b.md): 1.7.12 re-picks
  13.7% of its 1% IDs; distinct re-picks only 100 of 3,451; Osprey on corr-top and misses: 6; linear counterfactual about
  neutral. Peak re-picking is not the lever. [research, rejected]
- 1.7.12 decoy experiments (agent decoy4, open-source half only): 1.7.12 with Osprey library decoys logs "library contains
  decoy precursors, built-in decoy generation turned off"; combined FDP 0.5% 49,836 vs own mutation decoys 50,775; FDP at q
  1% 0.73% vs own 1.32%. Library build: 3,089,390 targets, 3,087,904 decoys (350 decoys without same-charge target, 1,836
  targets without decoy, 2,523 ambiguous decoy sequences dropped). Scripts decoy4\scripts\make_lib_full.py, fdp4.py. [research]
- 1.7.12 source (agent decoys): generate_decoy 3590-3668, MutateAAto 1370; q-values 9531-9600 use a separate decoy list with
  no pairing / no TDC. [research]
- Osprey libdecoy co-assignment (agent decoys): on A10_014 (rt16 GBDT) detected decoys co-assign 34% (31.6% with OTHER
  targets, 1.8% own) vs entrapment 22% (18.8% other). Co-assigned decoys are near-copies of other real targets (LGLELEK ~
  LGLLEEK, ELAEERK ~ ELAEEKR); 68% fragment overlap > 0.4 vs entrapment 38%. The gate checks only the decoy's own target.
  Library-wide near-copy (overlap > 0.4) of another same-mass target: reverse decoy 18.6%, shuffle entrapment 18.5%,
  1.7.12-style mutation decoy 1.0%. [research, unmerged]
- Mutation-decoy library for Osprey built but never searched: `decoys\lib\target+entrapment-r1.0-20260817-mutdecoy1712`
  (2.26M decoys) via scripts/build_mutation_decoys.py. [unmerged, open]

### 2026-11-01

- Classifier bench (agent clflab, Python, `clflab\`; export.py rebuilds X.npy in ~1 min): xgboost with Osprey recipe at 300k
  reproduces Osprey (seeds 48,820-50,084, mean 49,348 vs Osprey 49,943; seed SD ~650-700, use >= 3 seeds). At 300k,
  bagging 4/16 and 5/10 folds are noise; all-vs-all labels hurt (46,800). 1M 50.6k; all rows 52.2k (train 1,114 s at 12
  threads); all rows + bag4 52,610; torch MLP 51,959 (FDP at q1 0.73%). Summary analysis\summary.tsv. [#4968]
- 1.7.12 NN lever (agent nnlever, open-source 1.7.12, `nnlever\REPORT.md`): default NN 49,836; --nn-cross-val ep4/8/16
  50.5-50.7k and calibrated; CV + bigger ensemble: own features ep16 bag96 52,291 (FDP at q1 0.66%). Osprey's 80 features
  fed to the 1.7.12 NN (ext file, 4.28M rows): default 49,967 (= Osprey GBDT 49,943), cv ep16 bag96 52,891 (+5.9%),
  plateau ~52.9k (ep32 bag96 52,977). Ensemble size, not architecture, carries it; same level as GBDT on all rows. [#4968]
- Osprey vs its own pass 1 on A10_014 (nnlever join): Osprey q cut 0.00809 for 49,943 real. [research]
- GBDT speedup detail (agent gbdtspeed): root cause FDR folds trained with MaxDegreeOfParallelism=1 (3 of 64 cores busy),
  shuffled-order random gathers on column bins, no histogram subtraction. Bit-identical steps: parallel binning/gradients,
  ordered per-tree column bins, branch-free double-buffered partition, 4-feature interleaved histograms; then histogram
  subtraction + fixed row-chunk partials (chunking by row count, not threads, keeps results thread-invariant). 1M x 200
  trees: 1,049 s -> 26.6 s at 16 threads (~39x); 4.28M: 170 s; 300k: 151.7 s -> 23.1 s at 4 threads. Padding for false
  sharing gave nothing (reverted). Histogram build is memory-bound (~3x from 1 to 16 threads). [#4967]
- New MLTest at-scale golden (40k rows, captured from the pre-change implementation) exercises every threaded path at 1 and
  4 threads. [#4967]
- Two-round training design (agent prefilter): config.PrefilterTrainSize, PercolatorTrainer.TrainWithScorePrefilter,
  PercolatorSampling.SelectTopScoringGroups (+ shared BuildPeptideGroups), validity key ;gbtprefilter=N only when set;
  round 2 seeded by round-1 scores via RunPercolator initialEntryScores. FdrTest.TestGbdtPrefilterTraining. [#4968]
- Mass-error plot (agent masshist): per-run sidecar fragment-mass-errors.json (PerFileRescoring product); Brendan redesigned
  twice - first per-file pickers like CAL plots, then moved into CAL Summary beside the per-file corrections table with a
  shared File picker; the separate tab and combined/recommended scalars were removed. A10_014: SD 2.45 all, 5.06 / 2.47 /
  1.30 by tercile, search tolerance 4.57. [#4992]
- tc feature recomputation (agent fragcorr, fc_extract.py): stored tc_sum6 reproduces (r 0.98-0.989) only with closest peak
  at 4.5 ppm, which exposed that the main search uses the calibrated 4.58 ppm (ScoringPipeline.cs:172-195,
  MzCalibration.cs:345), not 10 ppm. Scan spacing 0.0245 min, so tc window 0.40 = 16 scans. [#4992]
- Mass error vs intensity (fragcorr fc_masserr.txt): low-intensity (< 316) top-6 fragment peaks on shared targets have robust
  SD 3.9 ppm, 27% outside 4.58 ppm (14% outside 7); high-intensity SD 1.1-1.5 ppm is what calibration measures. [#4992]
- Tolerance follow-up (fragcorr ftol\): at 7 ppm the apex moves for 5.5% of accepted targets (net away 1,323 vs 1,064), 12 ppm
  9.1%; the reference XIC switches in about half the away moves; cosine features favour decoys at wider tolerance; at <= 7
  ppm the closest and most-intense match agree. Entrapment rise 183 -> 230 not reproduced in a tc15 pair. [#4992]
- Two-XIC arms (agent twoxic, `seaad\fdrmask-twoxic\results.tsv`, one seed): corr7-tc40 53,958, corr6-tc40 54,418, corr7-tc15
  52,698 vs control tc40 53,934, tc15 51,592; q 1% 55,645 at 0.64% vs 54,754 at 0.58%. Cost: coelution scoring 117.5 s vs
  71.3 s (+65%). [#4992]
- Protein-shuffle audit (agent protshuf): Carafe libraries carry per-PEPTIDE accessions (sp|X_pepNNNNN|..), so every peptide
  is its own protein in any tool that reads the TSV's protein column; Osprey takes proteins from the pairing manifest
  (ApplyToLibrary), so its shuffle is a rewritten manifest. Shuffle: 1,391,232 entrapment peptides over 41,274 accessions,
  696,316 (50.05%) on target proteins, seed 20261101. Left on disk: protshuf\lib c_clean.tsv + c_shuf.tsv (22 GB),
  osprey-shuf (3.1 GB blib), runs\ 11 GB. [#4993]

### 2026-11-02

- Cross-OS GBDT root cause (agent ulp): first divergence is the gradient array at tree 2 - Math.Exp in Sigmoid differs
  between Windows UCRT and glibc 2.39 for 203 rows (glibc correctly rounded, UCRT the other neighbour, err 0.50x ulp); splits
  never change, leaves move by ULPs from tree 5. Pre-existing in master; branch == master bitwise per OS. [#4967]
- DeterministicMath (agent detgbt): Osprey.Core/DeterministicMath.cs, an fdlibm exp/log port wired into GBDT Sigmoid and base
  score; Windows and Linux bit-identical at 1-16 threads; MLTest small golden probe2 rebaselined. Linux Stellar SVM run still
  NOT bitwise: PrecursorPep <= 8.6e-16 abs, features ULP-level, all discrete results identical. [#4967]
- Feature-matrix columns (agent maskcols): #4950 trained 41 columns (21 + 20 zeros), the branch 97 (21 + 76 zeros). SVM dot
  product is SIMD (Vector<double>), so zero-padded vs absent columns round differently; the reduced 21-column run matches the
  master golden EXACTLY (97-col run differed at 1e-14). Perf vs #4950: total 3:53 -> 3:28 (-10.9%), Stage 5 1:37 -> 1:04
  (-33%). regression-parallel All 48/48 PASS in 1:07:46. [#4969]
- prF-fix review pushbacks (kept as comments): item 6 - diann.cpp peaks() j>2 uses get_corr_matrix over all fragments, the
  flag only counts, Osprey matches; item 7 - apex offsets are relative to unclamped bestPeak.ApexIndex, clamp is a no-op.
  Two ChooseReference copies unified. Before maskcols: scores.parquet 295.3 MB (#4950) vs 454.9 MB per file. [#4969]
- Feature gating (agent featgate): families in PinFeatureMask (core 0-20 always); readers fail loudly on a recorded-but-missing
  column; ;featrec= key on PerFileScoring and PerFileRescoring (empty by default). Record-all smoke: 116 columns, all identical
  to the earlier all-feature parquet; parquet 241,500,219 B vs 241,500,213 B master-based; perf total -0.6%. [#4969]
- prB-fix (agent prB-fix): review findings 1-6 and 9 fixed, 647/647, Stellar PASS; commit msg sessions\20261028-diann\
  commit-prB-fix.txt. [#4968]
