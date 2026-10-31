# TODO-20261030_osprey_scoring_library.md

## Branch Information
- **Branch**: `Skyline/work/20261030_osprey_scoring_library` (local, not pushed), cut from Mike's
  `Skyline/work/20261028_osprey_diann_fdr_gap` at 2674437153 (pushed 2026-10-30)
- **Checkout**: `D:\Users\brendanx\proj\pwiz-scores` (worktree, MACS2)
- **Base**: Mike's FDR-gap branch (TODO-20261028_osprey_diann_fdr_gap.md), then `master`
- **Module**: `osprey`
- **Created**: 2026-10-30
- **Status**: Loop established - record with PerFileScoring, value with FirstPassFDR under OSPREY_FDR_FEATURE_MASK
  (51318083fd). Best so far: all 47 features, 12 XICs, 41,956 at FDP 0.5% on SEA-AD 3 files (master 35,654;
  DIA-NN on the same Carafe library 68,418).

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
- [x] Osprey MaxTrainSize 300k vs 3M: no change (41,956 vs 41,895); Osprey fold calibration and pair ties are sound
- [ ] Correlation-cluster drops and forward selection in the harness
- [ ] Peak-shape reference chosen by mutual correlation / consensus instead of max intensity
- [ ] DIA-NN shortlist that needs no new extraction (pRef, pRT, AA composition), then extractor work
      (tight-tolerance XICs, shadow XICs at -1.00336, MS1 M+1/M+2, all library fragments, wider window)
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
