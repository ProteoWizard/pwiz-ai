# TODO-20261030_osprey_scoring_library.md

## Branch Information
- **Branch**: `Skyline/work/20261030_osprey_scoring_library` (local, not pushed), cut from Mike's
  `Skyline/work/20261028_osprey_diann_fdr_gap` at 2674437153 (pushed 2026-10-30)
- **Checkout**: `D:\Users\brendanx\proj\pwiz-scores` (worktree, MACS2)
- **Base**: Mike's FDR-gap branch (TODO-20261028_osprey_diann_fdr_gap.md), then `master`
- **Module**: `osprey`
- **Created**: 2026-10-30
- **Status**: Rebased onto Mike's PR #4950 (80f7c2469d; FDR-load mask OSPREY_FEATURE_MASK). 89 features, new ones masked
  by default. Best: GBDT, time-correlation family, half-window 0.25 min: 50,537 at FDP 0.5% on SEA-AD 3 files
  (3-seed mean; SVM all47 40,922; DIA-NN 68,418). Night 2026-10-30 log: `ai/.tmp/night-session-budget.md`.

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
