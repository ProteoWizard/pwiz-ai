# TODO-20261030_osprey_scoring_library.md - Phase 2

Follows [TODO-20261030_osprey_scoring_library-phase1.md](TODO-20261030_osprey_scoring_library-phase1.md); continued in
the active [TODO-20261030_osprey_scoring_library.md](TODO-20261030_osprey_scoring_library.md). Frozen; do not edit.

## Branch Information
- **Branches**: `Skyline/work/20261103_osprey_fragment_tolerance` (#4992), `..._20261103_osprey_protein_compact_symmetric`
  (#4993), `..._20261105_osprey_weak_peak_scoring` (#4998), `..._20261106_osprey_spectrum_match` (#5005); local
  nightlywork branches named below
- **Base**: #4950 (`Skyline/work/20261028_osprey_diann_fdr_gap`) for #4992/#4998/#5005; master for #4993
- **Module**: `osprey`
- **Status**: Phase 2 complete (2026-11-03 to 2026-11-07): #4993 merged to master; #4992, #4998, #5005 merged into #4950.
- Metric throughout unless stated: real (non-entrapment) targets at entrapment FDP 0.5% (combined estimator), SEA-AD
  Astral A10_014 single file or 3 files (A01_005, A06_010, A10_014).

## PRs in this phase

### #4992 - Added fragment-tolerance diagnostics and opt-in wider-tolerance correlation XICs
[#4992](https://github.com/ProteoWizard/pwiz/pull/4992), into #4950, merged 2026-11-06 as `000d147b6a`. Branch
`Skyline/work/20261103_osprey_fragment_tolerance` (worktree `pwiz-gbtfast`; experiment worktree `pwiz-cdexp`).
- The calibrated fragment tolerance (|mean| + 3 SD of confident matches; 4.58 ppm on SEA-AD Astral vs configured 10)
  is now logged at the default level. `OSPREY_MIN_FRAGMENT_TOLERANCE` floors it (keyed `;ftolmin=`); a uniform floor
  does not help (calibrated 53,934, 5.5 ppm 53,935, 7 ppm 53,362, 12 ppm 51,113): a wider window moves the apex onto
  interference and helps decoys more on the intensity-pattern features.
- Per-file fragment mass-error plot in CAL > Summary (`<stem>.fragment-mass-errors.json`, with `--model-diagnostics`),
  beside the calibration corrections table, with lines at the MS2 mean, mean +/- search tolerance and configured
  tolerance.
- `OSPREY_CORR_FRAGMENT_TOLERANCE=<ppm>`: once the peak is chosen, fragments re-extracted at max(search, setting) ppm
  for the correlation-shape features only (coelution, tc_*, ref_corr_*, mp_fragment_r2_*, dom_*, top3_*, wide_*);
  apex, intensity-pattern, spectral and mass-error features stay on search-tolerance XICs. Keyed `;fcorr=`.
  A10_014, 3 seeds: 54,383 / 56,609 / 58,165 -> 54,765 / 57,187 / 58,898 at FDP 0.5 / 0.75 / 1% (+0.7 / +1.0 / +1.3%).
  Coelution scoring cost about +65% (117.5 s vs 71.3 s).
- Fixed a resume re-running PerFileRescoring with the report on (sidecar file identity in the key).
- Gates: 669/669 after merging #4950's tip, regression on Stellar, StellarLibDecoy, StellarGenDecoyEntrap, Astral.

### #4993 - Fixed pass-2 protein-compact FDR to compete the stratum's complement against its own decoys
[#4993](https://github.com/ProteoWizard/pwiz/pull/4993), base master, merged 2026-11-06 as `ab7c6b21a7` (master merged
in first as b02849d607). Branch `Skyline/work/20261103_osprey_protein_compact_symmetric` (worktree `pwiz-tworound`).
- Root cause: the stratum (proteins with >= 2 detected peptides) takes ~87% of high-scoring targets but ~15% of
  high-scoring decoys; the decoys it left behind counted against no one. A10_014: off-stratum survivors at first-pass
  q 1% held 1,302 targets vs 478 decoy winners (~37% FDR); the nominal-1% union held 1,132 decoy winners vs 66,832
  targets (1.7%).
- Fix: stratum and complement compete separately against their own paired decoys at run scope
  (`StreamingFdr.CompeteOneFile`) and experiment scope (`StreamingFdr.ComputeComplementExperimentQ`). A peak Stage 6
  moved competes in its own half. Keyed `;pass2strata=2` on PerFileRescoring and SecondPassFDR.
- The #4581 premise (target-only `>= 2` count) was checked and is not the cause: membership is by base_id, and
  leave-one-out barely moves the shuffled FDP (1.52% -> 1.45-1.50%).
- SEA-AD A10_014 GBDT-OOF: entrapment at q 1% 134 -> 9, real at FDP 0.5% 50,893 -> 52,217 (+1,324), protein groups
  5,462 -> 4,276 (single-peptide groups 2,114 -> 927). Under the default SVM the change is small (master already
  dropped most of the complement). Shuffled library: protein-aware FDP stays 1.4% (SVM) / 1.9% (GBDT) inside the
  stratum - not fixed here (fold-mean rescoring of OOF training rows is part of it).
- Goldens re-captured on all four datasets (Stellar 32,705 -> 32,270 precursors; entrapment GenDecoyEntrap 260 -> 51,
  LibDecoy 147 -> 18). Test floors moved: `MIN_ASTRAL_RECOVERED_FRACTION` 0.7 -> 0.6; tuning-run export floor on the
  total. PEP left as the pooled pass-1 fit for complement records.
- Added `pwiz_tools/Osprey/docs/protein-shuffled-entrapment.md` and
  `ai/scripts/Osprey/Library/Build-ProteinShuffledEntrapment.py`. Addresses #4581 (does not close it).
- **Open question for Brendan and Mike**: per-half conservative +1 (what shipped) vs one +1 for the union.
- Gates: all tests, regression-parallel All 49/49 against the re-banked goldens, Perf gate -1.4%, four TC checks.

### #4998 - Added correlation-chosen reference XIC, local RT window and fragment shadow features as experiments
[#4998](https://github.com/ProteoWizard/pwiz/pull/4998), into #4950, merged 2026-11-07 as `953e947278`. Branch
`Skyline/work/20261105_osprey_weak_peak_scoring`.
- `OSPREY_REF_XIC=corr`: the reference fragment XIC (apex scan, area, SNR, sharpness, MS1 reference) is the fragment
  with the best summed correlation to the others inside the chosen peak (`ReferenceCorrelations.ChooseReference`),
  not the largest total intensity over the window (which interference inflates).
- `OSPREY_LOCAL_RT_TOLERANCE=<K>`: per-library-RT half-width = 3 x 1.4826 x median |residual| of the K nearest
  calibration points, floored at the global width, capped at the max RT tolerance; RT-penalty sigma scales with it.
  The SEA-AD library RT saturates near 19.2-19.3 (one library RT spans ~19-23 min elution).
- Fragment M-1 shadow features (`shadow_corr_sum6`, `shadow_frac6`) and interference-cleaned time correlation
  (`tc_clean_sum6`, `tc_clip_sum6`), slots 97-100, masked; `shadow_frac6` carries the gain.
- A10_014, 3 seeds, FDP 0.5% / 1%: baseline (#4992) 54,517 / 58,952; + ref 56,069; + local RT 56,557; + shadow
  57,427 / 61,122 (+5.3% / +3.7%). 3 files, 2 seeds: 60,163 -> 62,902 (+4.6%), FDP at q 1% 0.86-0.89% -> 0.75-0.77%.
- Tried and not kept: same reference in the pick; wider CWT bounds; CWT on top 6 fragments; 10 or 16 XICs; no signal
  prefilter; per-rank shadow variants (the round-2 shadow commit c34dd8d345, +324 at 0.5%, flat at 1%, did NOT go
  in); intensity-dependent fragment tolerance.

### #5005 - Added HRAM-only spectrum-match and library-agreement feature families
[#5005](https://github.com/ProteoWizard/pwiz/pull/5005), into #4950, merged 2026-11-07 as `c0c2bcd43c` (the #4950 head
the 2026-11-07 work branched from). Branch `Skyline/work/20261106_osprey_spectrum_match`.
- Spectrum-match slots 104-108 (`spec_match_prob`, `spec_proj_cosine_xt` after EncyclopeDIA, `spec_hyperscore`, peak-max
  versions); library agreement slots 101-103 (`lib_cosine_coel`, `lib_entropy_sim`, `lib_coel_share`).
  `PinFeatureMask.HRAM_ONLY_FAMILIES`: not computed, recorded or trained at unit resolution.
- A10_014, 3 seeds: 57,427 -> + library agreement 57,779 (+0.6%) -> + spectrum match 58,429 (+1.7%); FDP 1% 61,122 ->
  62,034. Stellar: within seed noise (match probability alone 52-112 vs xcorr 12,812), hence HRAM only.
- Gates: 678/678, Stellar byte-identical default, independent code review fixes (validity keys, DeterministicMath,
  hyperscore floor, wiring test), full SEA-AD, Test-PerfGate, TC Perf/Regression.

### #4950 (open, Mike) - the integration branch these PRs land in
[#4950](https://github.com/ProteoWizard/pwiz/pull/4950) `Skyline/work/20261028_osprey_diann_fdr_gap`: GBDT as the
scoring core, new PIN features and per-dataset switches. #4969, #4992, #4998, #5005 merged into it; #4967, #4968, #4993
went to master and reach it by master merges. Mike reviews within #4950. Sibling TODO:
`TODO-20261028_osprey_diann_fdr_gap.md`.

## Progress log (as written)
  - 2026-11-03 night: master merged into #4950 (fc9677add1) and #4950 into #4969 (5566096500, TC 4249159 green).
    Mike then MERGED #4969 into #4950 (5340c30909, with his Copilot fixes f33860f583) and asked that further work go
    to his branch; he reviews it within #4950. OPENED #4992 (C+D: fragment-tolerance diagnostics + opt-in
    OSPREY_CORR_FRAGMENT_TOLERANCE, base = #4950; SEA-AD 7 ppm +0.7/+1.0/+1.3% at FDP 0.5/0.75/1%, 3 seeds) and #4993
    (E: protein-compact complement competes against its own decoys, base = master; SEA-AD GBDT-OOF entrapment 134 -> 9
    at q 1%, real at FDP 0.5% +1,324, protein groups 5,462 -> 4,276; goldens re-baselined; Addresses #4581; open
    question: per-half vs shared +1). Docs: pwiz_tools/Osprey/docs/protein-shuffled-entrapment.md; script
    ai/scripts/Osprey/Library/Build-ProteinShuffledEntrapment.py. Local only: f0cfff35f3 Osprey CI inspection in
    tcbuild.bat (Skyline/work/20261104_osprey_ci_inspection, pwiz-scorelib) awaiting Brendan.
- 2026-11-04 night (local branches, NOT pushed; SEA-AD A10_014 full single-file pipeline, real targets at
  entrapment FDP 0.5%, 3 seeds; baseline = #4992 tip b96c3e60d6 with GBDT + OOF + prefilter 200k, all features,
  12 XICs, corr XICs 7 ppm, RT floor 1.0, tc window 0.40: 54,592 / 54,323 / 54,636, mean 54,517):
  - OSPREY_REF_XIC=corr 23cada1bc3 (Brendan: the most-intense-fragment reference is at odds with more fragments
    at low intensity). The core reference XIC (apex scan -> every apex-spectrum feature, area, SNR, sharpness, MS1
    reference) was the fragment with the largest total intensity over the WHOLE extraction window; now the
    fragment with the best summed correlation to the others inside the chosen peak. 56,069 (+2.8%), q1% FDP
    0.60-0.66%. Same reference choice in the pick (top-5 corr, tie-break): no gain (dropped).
  - OSPREY_LOCAL_RT_TOLERANCE=15 d93b039dab (agent, pwiz-scorelib nightlywork/20261104_rt_edge): per-library-RT
    half-width from the 15 nearest calibration residuals; the library RT saturates near 19.2-19.3 (one library RT
    spans ~19-23 min elution). +554 (+1.0%), late-edge recovery 57% -> 82%, +1.7% candidates.
  - Shadow (fragment m/z - 1.00336/z) + cleaned-tc features b07eb8a73a (agent, pwiz-cdexp
    nightlywork/20261104_interference), slots 97-100, masked by default: +740 (+1.4%); shadow_frac6 carries it.
  - All three (pwiz-gbtfast nightlywork/20261104_shape_ref 480afc4ca5, gated): 57,427 (+5.3%); FDP 0.75% +4.2%,
    1% +3.7%; q1% FDP 0.63-0.68%. 3 files (A01_005/A06_010/A10_014) seed 1, ref + local RT: 59,914 -> 62,851 (+4.9%).
  - Ruled out: CWT valley threshold 0.15/0.30, coverage 3/4 and both (bounds +49% wider, no gain: narrow bounds
    mark the misses, they do not cause them); CWT detection on top-6 fragments; 10 or 16 XICs (12 stays best);
    no signal prefilter (+104 at +40% candidates).
  - Gap classes (private numbers in U:\tools\claude\diann-study): same-peak low score still dominates, two
    thirds in the lowest-quantity tercile; the fixed-window tc/tight family is the only one still separating it.
- 2026-11-06: origin/master (5d12377aad) merged into #4993 (merge b02849d607, pushed; no amend/rebase). One
  conflict, `pwiz_tools/Osprey/docs/README.md` table: kept master's fractional-entrapment text and
  equal-chance-diagnostics row (#4987, #4989) plus this branch's protein-shuffled-entrapment row. Catalog: nothing
  to register - the branch reads no new variable (`Pass2StrataValidityKeySuffix` uses the existing
  `Pass2ProteinCompact` / ENV_PASS2_QVALUE EnvVar; the test sets OSPREY_PASS2_QVALUE through
  `OverrideVariables`). No `new ProgressReporter` scopes added by the branch (constructor still public on master
  anyway). #4986's StreamingFdr change was comment-only; nothing in the branch depends on removed arms. Master
  moved no goldens since the merge base. Gates: Build-Osprey Debug 653/653 tests, 0 inspection warnings
  (`ai/.tmp/pc1-build.log`); `regression-parallel.ps1 -Dataset All` 49 PASS / 0 FAIL in 40:38 against the
  branch's goldens (`ai/.tmp/pc1-regr/console.log` and lane logs).

## 2026-11-06: spectrum-match and library-agreement families (branch Skyline/work/20261106_osprey_spectrum_match)
Stacked on #4998. Commits dd94ef9d00, 8211bc3a37. Masked by default and HRAM only.
- SEA-AD A10_014, real targets at entrapment FDP 0.5%, 3 seeds: 57,427 -> + library agreement 57,779 -> + spectrum match 58,429
  (FDP 1%: 61,122 -> 61,594 -> 62,034). Paired 5 seeds with the pick reweighting on: spectrum match +675, positive on every seed.
- Offline apex scores: xcorr's weakness is its whole-scan preprocessing in chimeric scans. Removing its 5% floor barely helps and
  removing per-window scaling hurts. Matched-fragment scores read at library positions pass about 3x as many strong misses.
  Advantage holds at 10 ppm and is mostly gone by 20 ppm.
- Stellar (3 files, 3 seeds): both families within seed noise; match probability alone 52-112 at q 1% vs xcorr 12,812, hence HRAM only.
  Masking xcorr on Stellar costs 4-5% (one seed). GBDT env vs defaults: pass 1 +37% / +29% at FDP 0.5% / 1%; pass 2 +20% / +15%, with
  pass-2 FDP at q 1% 1.15-1.19% vs 0.99%, to check before GBDT becomes the unit-resolution default.
- Not kept (local record nightlywork/20261105_double_counting): MS1 evidence (-317); OSPREY_PICK_WEIGHT_SCALE 1,1,0.75,2 (+467 without
  the spectrum family, about +200 with it, within seed noise; moves 9 -> 279 of 848 wrong-peak precursors onto DIA-NN's peak);
  spectrum score in the peak pick (-109; +210 at FDP 1%); duplicate-peak winner by spectrum score (-282); no prefilter (-67; +127 at
  FDP 1%, +40% candidates); calibration LDA with spectrum scores (about 30% more anchors, higher anchor entrapment, tolerance
  4.57 -> 5.57 ppm, -830); calibration peak choice by match probability (-215).
- Still to do: full SEA-AD, performance metrics, default flip with re-recorded goldens as a separate PR. Later: feature cost analysis.

### 2026-11-06 - #4993 merged

PR #4993 merged as ab7c6b21a7 (master merged in first, b02849d607: README conflict only, nothing to register in the EnvVar catalog; all-datasets regression 49/49 against the re-banked goldens; the four required TeamCity checks green; no Perf/Regression re-run by Brendan's decision). Shipped: stratum and complement compete separately against their own decoys at run and experiment scope; goldens re-banked on all four datasets; docs/protein-shuffled-entrapment.md. Not addressed here: the stratum's own residual protein-aware FDP under GBDT out-of-fold (training rows rescored with the averaged model).

## 2026-11-06 night: SEA-AD 82 files, A master / B stack / C DIA-NN
Deck: https://claude.ai/artifact/JRAMrxSaHJcAXhu5MJDu1P (private). Analysis: `ai/.tmp/sessions/20261104-night/abc-compare.py`, output under `D:\Users\brendanx\test\diann-vs-osprey\seaad\abc-night`.
- Pass 1 real targets at FDP 0.5% / 1%: A 44,648 / 50,181; B 79,635 / 86,111; C 99,548 / 107,129. B vs A +78%, A vs C -55%, B vs C -20%. C searched its own library, not Carafe. One seed; B's gains need settings that are off by default.
- Wall: A 2h36m, B 6h02m (contended to 16:46), C 8h06m (upper bound). Back to back on 8 files, one order, load not logged: B 39m10s, A 23m58s, 1.63x; peaks 89.4 and 59.4 GB. Estimated B at 82 quiet files: 4.25 to 5 hours.
- Protein FDR is inert on library decoys, on master too: all groups q = 0 (A 6,205 with 255 entrapment; B 7,779 with 440). `ProteinFdr.cs:732` looks up `DECOY_` + peptide. A fix would pair by base_id and change StellarLibDecoy output, so it needs a decision on the goldens. Not attempted.
- Not done: weak-file cohort single-file FirstPassFDR, masked first-pass arm, local Test-PerfGate for #5005, 82-file DIA-NN on Carafe.

## Recovered detail (2026-11-07)
From the sessions' uncommitted status files on MACS2 (`ai/.tmp/agent-*-status.md`,
`handoff-2026103*.md`). Paths: `seaad\` = D:\Users\brendanx\test\diann-vs-osprey\seaad\, `_bin\` =
D:\Users\brendanx\test\osprey-runs\_bin\, `sessions\` = ai\.tmp\sessions\. Tags name the PR each item fed.

### 2026-11-03

- Deterministic-math switch (agent detswitch): OspreyEnvironment.UseDeterministicMath, GbtParams.UseDeterministicMath,
  validity key ;gbtmath=system only when off, Program.cs aborts on a bad value; "system" reproduces the old Windows golden and
  old Linux row 15000. Bench/e2e: detswitch\micro_*.txt, fit_WIN.txt, D:/test/osprey-runs/detswitch/e2e/summary.txt;
  snapshot `_bin\detswitch`. [#4967]
- Linux regression (agent linuxregress): WSL OspreyLinux had pwsh 7.6.7 + .NET 10.0.11 runtime only; pwsh-Linux Join-Path
  normalizes '\' to '/', Get-CimInstance absent. Patch in that agent's scratchpad (linuxregress/regression-linux.patch:
  launcher prefix/-OspreyBinDir, /proc comm liveness, Linux Downloads default) - recovered 2026-11-10, see the main TODO. Stellar
  PASS on Linux 452 s vs Windows 391 s from the same bin. The WSL distro was unregistered 2026-11-07. [unmerged]
- prBmerge: B merged with the upstream PercolatorEngine refactor (RunStreamingFirstPass edits ported into PercolatorEngine);
  SEA-AD fdrbench.tsv byte-identical pre vs post merge. Clone C:/t/prBpre left behind (rm blocked) - cleanup item. [#4968]
- Protein-compact root cause detail (agent E): stratum = base_ids of proteins with >= 2 distinct detected target peptides
  (FirstPassFdrTask.BuildProteinCompactStratum; protein-compact is the default via NormalizePass2QValue). Leave-one-out
  membership barely moves it (1.52% -> 1.45-1.50%); in-stratum re-competition is calibrated (260 vs 232). The defect: the
  stratum holds 87% of high-scoring targets but ~15% of high-scoring decoys, so the off-stratum leftover is decoy-rich
  (1,302 targets vs 478 decoy winners, ~37% FDR) and kept its pass-1 q. [#4993]
- Master behaviour found (agent E): unchanged off-stratum survivors get run q 1.0 and are effectively dropped; CHANGED ones
  (moved peak, or under GBDT OOF every training row) compete pooled with the stratum and keep pass-1 experiment q. On master
  Stellar ~509/487/521 off-stratum targets per file reached pass-2 run q <= 1% that way. [#4993]
- #4993 test floors (FLAGGED for Brendan): per-half conservative +1 kept; with ~25-28 off-stratum targets and 0 decoys per
  subset file the complement's q >= 1/28 accepts nothing. TestAstralSubsetHram MIN_ASTRAL_RECOVERED_FRACTION 0.7 -> 0.6
  (141/203); TestSubsetLibraryBuildTuned export floor moved from per run to the total over tuning runs. Alternative not
  taken: one +1 for the union of both halves. [#4993]
- #4993 golden effects: Stellar RefSpectra 32,705 -> 32,270; "Raised N to best run-level" 797 -> 0. GenDecoyEntrap run-level
  entrapment 260 -> 51 (targets -848); LibDecoy run entrapment 147 -> 18; Astral acceptedOffStratum 632 -> 0. Dropped protein
  groups are single-peptide (Stellar 454/454, LibDecoy 741/742, Astral 623/623; entrapment groups 123 -> 18). [#4993]
- #4993 SEA-AD 8 arms (C:\test\osprey-runs\protfix\{.,p2,p3,p4}): default SVM shuf master/fix 117/120 entrapment at q1
  (protein-aware FDP 1.35/1.38%) - fix changes nothing under SVM; GBDT-OOF orig 134 -> 9, real +1,324; GBDT-OOF shuf 302 -> 192,
  protein-aware 2.18% -> 1.92%. Remaining in-stratum excess = fold-mean rescoring of OOF training rows, hence "Addresses #4581".
  [#4993]
- #4993 commits on Skyline/work/20261103_osprey_protein_compact_symmetric: 1e45e63b4a (46 files) and 9c7d19729e (;pass2strata=2
  validity term, two-file mutation-checked test). Perf gate -1.4% (ai\.tmp\perf-gate\20261104-021803Z\verdict.md). [#4993]
- Harness gotchas (agent E): the twoxic-era audit env vars (XIC_FRAGMENTS, FEATURE_MASK, LOESS_BANDWIDTH, MIN_RT_TOLERANCE,
  FDR_SEED, TC_HALF_WINDOW) did not exist on master and master refuses unknown OSPREY_*; two concurrent arms both rewrote a
  "stale" shared blib cache (atomic temp+rename) - serialize arms that share a library. SEA-AD on D: is IO-slow under
  contention (library TSV load 38% after 36 min). [harness]
- C+D port (agent cd) to pwiz-gbtfast: bfb3013129, 18d172d4a1, afc29a26fe, cd41085ff0, d9f134db96; Astral regression aborted at
  mode 3 on full disk; experiment worktree D:\Users\brendanx\proj\pwiz-cdexp (b4fc2af782, local). Review fix b96c3e60d6 (agent
  cdfix): a failed mass-error summary is recorded, not re-measured; report renders only summaries stamped for this search,
  library and run FDR; nodes without calibration keep shipped summaries; no NaN in the log line; 669/669. [#4992]
- CI inspection (agent inspect): pwiz_tools/Osprey/tcinspect.ps1 modeled on Skyline's, ReSharper CLI pinned 2025.3.3 in
  pwiz_tools/Osprey/.config/dotnet-tools.json, BuildWarnings.psm1 (#4844) warnings log; tcbuild.bat runs every step and fails
  at the end. Commit f0cfff35f3 + a second commit on Skyline/work/20261104_osprey_ci_inspection. Pinned 2025.3.3 on #4950
  5340c30909 flags ParquetScoreCache.cs(407) PossibleNullReferenceException and (416) RedundantCast. Optional TeamCity params
  env.GITHUB_STATUS_TOKEN / env.INSPECTION_TARGET_URL for a separate GitHub status. [separate PR, TODO-20261104_osprey_ci_inspection completed]
- DIA-NN reader fixtures (agent diannfix): conversions and search fixtures copied to U:\data\MacCoss\Osprey\DIA-NN with README;
  Stellar (unit resolution) and tiny FASTAs gave 0 IDs, so the empirical fixture is Astral _49.raw with HeLa top-20/top-100.
  [fed the DIA-NN parquet loader TODO]

### 2026-11-04

- Gap decomposition (agent decomp): the confident IDs inside Osprey's window with no scored row are mostly signal-prefilter
  drops (most gain a row, on the same peak, in a no-prefilter scoring run `scores3-nopre-xic12`). Answers the TODO's open
  "776 no-row" item in part. Offline HistGB ablation proxy reads ~9% low (51,713 vs Osprey 56,587). Variant 3 stalled > 65 min
  at 100% CPU and could not be stopped (permission denied). [research]
- Local RT tolerance detail (agent rtedge, REPORT `seaad\rtedge1104\REPORT.md`): only ~10 of 529 calibration anchors lie above
  library RT 19, and pass-2 anchors are truncated by the 1.0-min window. Local width = 3 x 1.4826 x median |res| of K nearest,
  floor = global, cap = MaxRtTolerance 3.0. Offline K=15: edge coverage 63% -> 94% at +6% window cost; run log "up to 1.87 min,
  wider at 9.1% of points"; candidates 4,403,117 vs 4,327,732. Timing A/B noise-dominated. [#4998]
- Shadow features round 1 per-arm (agent interf): all 3 seeds 54,950 / 55,286 / 55,535; shadow only 54,823 / 55,494 / 54,778
  (+515); cleaned-tc only 54,478 / 54,673 / 54,221 (-60). Shadow-flag variant (tc_unshadowed_mean, shadow_n_flagged; 103 feats)
  55,089 vs 55,257: no gain, reverted, patch sessions\20261104-interf\shadow-flag-variant.patch. [#4998]
- Shadow-detail round 2 c34dd8d345 (tc_shadow_wsum6, shadow_frac_rank1-3, shadow_frac6_t45; slots 101-105, masked) on top of
  ref + local RT: 57,997 / 57,443 / 57,814, mean 57,751 vs 57,427 (+324); FDP 1% 61,144 vs 61,122 (flat). Ablation: rank-only
  57,665 / 57,375; weighted + t45 only 57,110 / 57,230 vs base 57,340 / 57,321. Gain small, carried by rank fractions.
  [#4998 if included - verify; else unmerged]
- Intensity-dependent fragment tolerance (agent masscal, OSPREY_INTENSITY_FRAGMENT_TOLERANCE k[:outer[:floor]], plus corr:
  scope): fit SD^2 = 0.655 + 3930/I ppm^2 (bins 2.61..0.82 ppm), small m/z trend (-0.35 ppm/1000 m/z). Base 57,427. Arm A k=3
  floor 1 (tighter for strong peaks) 56,613 mean - loses; B k=3 floor 4.6 (wider for weak, main XICs) 56,808 - loses; C
  corr:3:10:4.6 57,277 - neutral; D corr:3:12:7 57,018 - loses. Nothing committed; patch masscal1104\intensity-tolerance.patch,
  results masscal1104\results-all.tsv. [rejected, unmerged]
- Disk: interf clean-s3 failed on a full D: and was rerun; run dirs trimmed to fdrbench/calibration/logs after recording. [harness]
