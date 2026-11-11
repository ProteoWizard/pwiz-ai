# TODO-20261110_osprey_feature_set.md

## Branch Information
- **Branch**: none of its own until Phase 4. Experiments run on `Skyline/work/20261110_osprey_uw25_pb_fixes`
  at c3bdbea78d (on `Skyline/work/20261109_osprey_scoring_uw8` f90d19aaa6, with the protein-best fixes and the
  round-1 run bound), snapshot `D:\test\osprey-runs\_bin\uw25-c3bdbea78d` (v26.1.1.314)
- **Base**: #4950 (`Skyline/work/20261028_osprey_diann_fdr_gap`) and its pending branches
- **Module**: `osprey`
- **Created**: 2026-11-10 (designed on BRENDANX-UW25; Brendan has given UW25 to this study for a few days)
- **Status**: Design approved (2026-11-10). Phase 0 next.

## Goal

Find a small PIN feature set that keeps #4950's detection gain on the #5011 split oracle, and make it
the default. #4950 closed most of the gap to DIA-NN (5-6% behind at FDP 1% on SEA-AD) by growing the
classifier's input from 21 to 109 features, adding each family on a perception of value and declaring
success when close enough. Nothing since has asked which of them - core 21 included - are needed.
The cost of that growth shows on every axis a user compares Osprey with DIA-NN on:

- **Disk.** `.scores.parquet` is 3.9 GB per SEA-AD run at 109 features (estimated 0.5-0.8 GB at 21). With
  the 4.4 GB `.spectra.bin` cache, Osprey keeps ~8.8 GB per run: ~725 GB at 82 runs, ~3.9 TB at 446,
  ~18 TB of working space for a 2,000-run experiment. DIA-NN appears to leave no per-run binary cache.
- **Time.** On an HDD every FirstPassFDR read of every file costs in proportion to the bytes. At 82 files:
  October (21 features) training-feature load 4.7 min / 40 GB, score pass 8.8 min / 46 GB; November (109)
  16.8 min / ~200 GB and 34.4 min / 205 GB. FirstPassFDR went from ~22 min to 84.7 min, more from the
  features than from protein-best. (UW25 section of `TODO-20261030_osprey_scoring_library-other-machines.md`.)
- **Scoring CPU.** PerFileScoring computes each family as a unit, so a family costs nearly the same
  whether one of its features or all of them are kept.

A feature earns its place by detections at matched true FDP within a set, not by being informative
alone: correlated features substitute for each other, so there is no unique "required set", only
sufficient sets. The aim is a small one, plus a map of which features can stand in for which.

## What already exists (no code needed to start)

- **Families** (`Osprey.IO/PinFeatureMask.cs`): 21 core features (PIN 0-20, always computed and recorded;
  `fragment_coelution_sum` is also every row's first-pass score and the training-row tiebreak) and 16
  families computed as units (`FAMILY_FIRST_FEATURES`): runner-up, context, per-fragment rank,
  spectrum-across-peak, median-polish top-k, reference correlation, peak profile, time correlation
  (`tc_*`), heavy/tight, dominance, top-3, wide, shadow, clean/clip, library agreement (HRAM only),
  spectrum match (HRAM only). `ParquetScoreCache.PIN_FEATURE_NAMES` is the full list.
- **`OSPREY_FEATURE_MASK`**: comma-separated names hidden from the FDR classifier (`none` masks nothing).
  Keyed into FirstPassFDR and rescoring. Masked columns are not loaded at all, so a smaller set also reads
  fewer bytes in the FDR stage.
- **`OSPREY_RECORD_ALL_FEATURES=1`**: scoring records every family whatever the mask. The scoring key is
  the recorded SET (`RecordedFeaturesValidityKeySuffix`), so an arm with this switch should adopt scoring
  done under `OSPREY_FEATURE_MASK=none`.
- **Scored data with all 109 columns**: UW25's SEA-AD legs `D:\test\osprey-runs\sea-ad\runs-uw25\
  seaad-{20,21,41}files-libdecoy-r1.0-transferuw25-score*` (files 1-20, 21-41, 42-82; split-sized r=1.0
  library; full #4950 settings with `OSPREY_FEATURE_MASK=none`), made by
  `ai/.tmp/sessions/20261109-uw25mem/ladder.ps1` (which also holds the exact environment block).
- **Oracle**: `ai/scripts/Osprey/SEA-AD/tools/split_calibration.py` on the on-target half of the split
  (q 1% kept with true FDP; kept at true FDP 1%) - the standing rule of the scoring-library TODO.
- **Prior signal**: "wide_* and heavy/tight, dominance families add ~0" and an incomplete per-family
  decomposition ablation (scoring-library TODO, open items); issue #4467 (open) specifies permutation
  importance, fold stability, univariate AUROC and correlation grouping for `--model-diagnostics`.

## Method

**Arm** = one FDR-only run on linked scoring: `Run-SeaAd.ps1` with the #4950 settings,
`OSPREY_RECORD_ALL_FEATURES=1`, `OSPREY_FEATURE_MASK=<the features this arm drops>`, protein-best off
(`-ProteinBest off`), `-Task FirstPassFDR`, `-FdrBenchPass both`, `-LinkFrom` the UW25 legs, 20 files.
**Result** = pass-1 `split_calibration.py`: kept at true FDP 1% (primary), q 1% kept and its FDP
(calibration check), plus FirstPassFDR wall time and parquet GB read from the log.

**Protein-best off for the search, on for confirmation.** Off, an arm is one training read plus the score
pass. The assumption that a set matching the full set without protein-best also matches it with
protein-best is tested in Phase 3, not taken on trust.

**Why not leave-one-out or plain bisection.** With substitutes everywhere (`tc_*`, `mp_*`, `ref_corr_*`,
the rank-k groups), leave-one-out finds every redundant feature worthless on its own, and plain halving
reaches different end states depending on which halves it draws (each half alone costs nothing; both
together cost a lot). So the search is in two stages:

1. **Random-subset screen.** ~40-60 arms, each keeping a random ~half of ALL features (core included), drawn
   from a fixed seed so the design is reproducible. Fit result ~ intercept + per-feature inclusion effects
   (ridge regression; also by family). Each feature is in and out across many contexts, so its estimate
   averages over its substitutes being present or absent, and seed noise becomes residual scatter averaged
   across arms - no per-arm replicates needed. Optionally draw correlated groups together to sharpen it.
2. **Guided halving elimination** (Brendan's bisection, in a cheap order). Rank by screened value; try
   removing the bottom half of what remains. Inside the noise band: accept and halve again. Outside: try the
   bottom quarter, and so on down to single features. Stop when removing any remaining chunk costs more
   than noise. Replicate seeds only at accept/reject decisions, which is where noise matters.

Read the final cut two ways: fewest columns (disk, FDR read) and fewest families (scoring CPU).

## Running it (one long unattended session)

The load is compute, not analysis, so one session can run it for days if it never reads raw logs:
- **Driver** `ai/.tmp/sessions/<session>/featset/run-arms.ps1`: takes an arms file (`arms.tsv`: arm id,
  seed, the dropped-feature list), runs each arm not yet in `results.tsv` through `Run-SeaAd.ps1` (detached,
  per `ai/docs/long-running-jobs-guide.md`), then runs `split_calibration.py` and appends ONE row to
  `results.tsv` (arm, seed, n features, kept at FDP 1%, q 1% kept, FDP, FirstPassFDR s, GB read, exit code).
  Restartable: a crash or reboot resumes at the first arm without a row. A `STOP` file halts between arms.
- **Disk hygiene**: after its row is written, an arm directory keeps `run.log`, the model JSON and the
  FDRBench pass-1 TSV (compressed); its `.fdr_scores.bin` files and hard links are deleted. 20-file arms
  otherwise leave ~3 GB each.
- **Session loop**: write arms -> run -> read `results.tsv` -> fit/decide -> write next arms. Log each decision
  and its numbers in this TODO (Progress) and push pwiz-ai as it lands, so a fresh session can resume from it.
- Check `quser` / `tasklist` before each batch; the machine is dedicated but the developer may log in.

## Phases

### Phase 0 - Wiring, timing and noise (UW25, ~half a day)
- [ ] One arm, `OSPREY_FEATURE_MASK=none` + record-all + protein-best off, 20 files: PerFileScoring adopted
      ("outputs valid"), only FirstPassFDR ran, FDRBench pass 1 written. Record its wall time and GB read.
- [ ] Core masks: can each core feature be masked from the classifier and still run with the meaning it
      claims? `fragment_coelution_sum` (first-pass score, training tiebreak) is the one to check; if it cannot
      be masked, it is fixed in every arm and says so in the results.
- [ ] Noise band: full set, `OSPREY_FDR_SEED` 1-5 -> mean and spread of kept at FDP 1%.
- [ ] Anchors: core-21-only arm (the October set) and the current default mask, to size what the families buy.
- [ ] Driver and `results.tsv` working end to end on these arms.

### Phase 1 - Random-subset screen (~1 day)
- [ ] Draw ~50 arms (fixed seed), each keeping a random half of all 109 features; run; fit per-feature and
      per-family effects with uncertainty. If the fit is too noisy, add arms rather than replicates.
- [ ] Cheap cross-checks from data the arms already leave: GBDT split/gain counts per feature from the arm
      models, univariate AUROC on the training export, feature-feature correlation groups.
- [ ] Per-family cost: parquet bytes per column group; PerFileScoring CPU per family from the existing
      dotTrace profile (`runs-uw8\profile-full-polish.dtp` report) or one family-masked scoring of one file.

### Phase 2 - Guided halving elimination (~1 day)
- [ ] From the screen's ranking, halve as above, with 3 seeds at each accept/reject decision.
- [ ] Record the path (each step's set, result, decision) and the end set; note the screened substitutes for
      each kept feature. Also read the curve the path traces as candidate sets (e.g. ~30, ~40, ~60 features).

### Phase 3 - Confirmation
- [ ] End set and 1-2 larger candidates with protein-best ON at 20 files (tests the protein-best-off
      assumption), then at 82 files, full pipeline (pass 2, transfer), against the full set at 82 files
      (pass 2: 96,641 at q 1%, FDP 0.99%; 96,654 at FDP 1%; UW25 run `seaad-82files-...-uw25-fdr82`).
- [ ] Stellar (unit resolution; HRAM-only families already off there) and Astral regression datasets.
- [ ] Timing and disk of the chosen set at 82 files on UW25 (same HDD), to quote against November's numbers.

### Phase 4 - Make it the default (code)
- [ ] Remove the dropped families from computation, not just the mask, so PerFileScoring and the parquet
      shrink; keep the mask and record-all switches for research.
- [ ] Core features get no exemption (Brendan, 2026-11-10: the core 21 were never rigorously vetted and newer
      families may measure the same aspect better). They are always computed and recorded today
      (`PinFeatureMask.CORE_FEATURE_COUNT`) because code outside the classifier reads some of them
      (`fragment_coelution_sum` as the first-pass score and training tiebreak; median-polish diagnostics; the
      training export). Inventory each core feature's non-classifier readers: one read only by the classifier
      is removed outright if the study drops it; one that is also a structural input stays computed but leaves
      the classifier and the parquet's FDR columns.
- [ ] Rename the KEPT features whose names came from DIA-NN internals and mislead (Brendan 2026-11-11: rename only
      what the end set keeps, not before). Known: `heavy_sum6` / `heavy_n_good` (natural 13C M+1 of each fragment,
      DIA-NN pHeavy) -> e.g. `frag_m1_corr_sum6` / `frag_m1_n_good`; `tight45_sum6` / `tight20_sum6` (fragment
      re-extracted at 0.45x / 0.2x tolerance, DIA-NN pTightCorrOne/Two). Feature reference with attribution:
      https://claude.ai/artifact/GJb8TyeS6f2MYxV5tsU19b (built by `ai/.tmp/sessions/20261110-uw8featset/build_table.py`).
- [ ] Recapture goldens; gate; regression-parallel; Perf/Regression on TeamCity when the PR is ready.

### Phase 5 - Storage format (after the set is known)
- [ ] float32 vs float64: first FDR-only (round loaded features to float32), then the file format and bytes.
- [ ] Parquet encoding/compression for the remaining columns.

## Open decisions (Brendan)
- Acceptable loss for the default: inside the seed noise band at FDP 1%, or an explicit bound?
- One set, or a smaller default plus an opt-in full set?
- Unit-resolution data (Stellar): its own set, or the HRAM set minus the HRAM-only families as today?

## UW8 independent replicate (proposed by UW8 2026-11-10, for Brendan to confirm)

Brendan wants a second machine to reach its own default set by a deliberately different route, then compare: where
the two converge is the robust answer, where they differ is a substitute choice to understand. UW8 differs on every
axis that could bias the result, and keeps the oracle and the metric identical:

| | UW25 (above) | UW8 |
|---|---|---|
| Files | 1-20 | 20 spread over the cohort: every 4th of 82 from file 3 (samples 0003, 0007, ... 0079) |
| Scored data | UW25 legs | UW8 82-file run `runs-uw8\seaad-82files-...-f90d19aaa6-nodiag` (mask none = all 109 recorded), linked; version pin 26.1.1.312 |
| Build | c3bdbea78d | the same c3bdbea78d (the protein-best fixes act in FirstPassFDR) |
| Random unit | columns, random half of all 109 | families as units (16 families + the 21 core features individually = 37 factors) |
| Keep probability | 0.5 | 0.75 (stays near the operating region where detections saturate; an additive fit learned far below it can misrank the top) |
| Protein-best in the screen | off (Phase 3 tests it) | on (the default; tests the off-assumption from the start) |
| Second stage | backward guided halving | forward selection: from the screen's best small set, add the family that gains most until within the noise band of the full set |
| Noise band | `OSPREY_FDR_SEED` 1-5 | seeds 11-15 |
| Metric | pass-1 `split_calibration.py` at true FDP 1% (on-target), q 1% FDP | identical |

Same driver discipline (arms.tsv / results.tsv, restartable, STOP file, disk hygiene after each row). UW8 logs to
this section and pushes as results land; the two sessions compare family-level effects after their screens and end
sets after their second stages. Cost estimate on UW8: ~18 min per 20-file arm with protein-best (FirstPassFDR
~54 s/file at 82 files), ~40 screen arms + 5 seeds + anchors ~14 h, forward stage ~1 day.
Brendan (2026-11-10): run it in a fresh UW8 session from the handoff `ai/.tmp/handoff-20261110-uw8-featset.md` (on
UW8; setup steps, paths, file pattern, driver spec, pitfalls).

## Progress

Driver, design and results: `ai/.tmp/sessions/20261109-uw25mem/featset/` (`run-arms.ps1`, `arms.tsv`,
`design.tsv`, `results.tsv`, `driver.log`); arm directories `D:\test\osprey-runs\sea-ad\runs-featset\`.
Every arm: 20 files, FirstPassFDR only on the UW25 links, `_bin\uw25-c3bdbea78d`, pass-1 split oracle.

**Phase 0 (2026-11-10 09:41-11:33, done).** Wiring confirmed: only FirstPassFDR runs, the mask reaches the
classifier ("109 features" / "108" / "21" in the Percolator input line), arm dirs trim to ~130 MB.

| arm | kept at FDP 1% | q 1% kept (FDP) | stage 5 | GB read |
|---|---|---|---|---|
| all 109, protein-best off, seeds 1-5 | 78,926 / 76,840 / 76,611 / 76,121 / 78,300 | 71,454-74,296 (0.56-0.60%) | 777-860 s | 114.9 |
| core 21 only (= today's default mask) | 55,148 | 50,172 (0.52%) | 339 s | 38.2 |
| all but `fragment_coelution_sum` (108) | 78,463 | 73,737 (0.56%) | 846 s | 114.9 |
| all 109, protein-best ON, seed 1 | 90,423 | 89,689 (0.92%) | 1,203 s | 139.8 |

- **Noise band: mean 77,360, SD 1,194 (1.54%), range 2,805 (3.6%)** across seeds 1-5. Wider than assumed:
  the round-1 run bound's -0.27% at matched FDP (UW25, 20 files) is well inside it, and any single-arm
  difference under ~2,400 (2 SD) is not evidence. Halving decisions need replicate seeds (3 seeds -> SE ~690).
- The families buy +40% over the core 21 (77,360 vs 55,148) for 3x the FDR read (114.9 vs 38.2 GB).
- `fragment_coelution_sum` can be masked from the classifier (108-feature arm runs, result inside noise).
- Protein-best adds +17% at 20 files (90,423 vs mean 77,360). Without it, q 1% is conservative (FDP ~0.58%);
  read every arm at true FDP 1%.

**Phase 1 (started 2026-11-10 11:3x).** 80 arms, `design_screen.py --design-seed 20261110`: each feature kept
with probability 1/2 independently (core included; 43-66 kept per arm, each feature in 30-50 arms), each arm its
own training seed. Expected ~10-14 min per arm, ~15-18 h.

### UW8 replicate

UW8: driver, design and results in `ai/.tmp/sessions/20261110-uw8featset/` (`arm.ps1`, `design.py`, `score.py`,
`run-arms.ps1`, `fit.py`, `arms.tsv`, `results.tsv`, `driver.log`); arm directories
`D:\test\osprey-runs\sea-ad\runs-uw8\featset\`. Every arm: FirstPassFDR only on links from
`runs-uw8\seaad-82files-...-f90d19aaa6-nodiag`, `_bin\uw8-c3bdbea78d` (v26.1.1.314, version pin 26.1.1.312),
protein-best ON, `OSPREY_RECORD_ALL_FEATURES=1`, pass-1 split oracle. Session log
`ai/.tmp/night-session-budget-20261110.md`.

- UW8 (2026-11-10 13:46): **file set corrected.** The 82 SEA-AD files are 75 samples (0001-0075) and 7 pools, so
  the planned pattern (samples 0003..0079) matched 19. Used the intent - every 4th of the 82 in name order from
  file 3 - = samples 0003, 0007, ..., 0075 and `pool-04`.
- UW8: the default mask is exactly the 88 family features, so the "current default" anchor IS the core-21 arm.
- UW8: `fragment_coelution_sum` as first-pass score and training tiebreak comes from the separate CoelutionSum
  stub column, not the feature vector, so masking it hides it from the classifier only. Kept as an ordinary factor
  (arm `p0-nocoelsum-s11` checks it, as UW25's 108-feature arm did).
- UW8 (13:29-13:46) wiring arm, all 109, seed 11: **85,702 kept at true FDP 1%**, q 1% 85,496 (FDP 0.97%),
  FirstPassFDR 976 s, 141.9 GB read. Only FirstPassFDR ran. With protein-best on, q 1% is close to calibrated
  (UW25's protein-best-off arms sit at FDP ~0.58%).
- UW8 (13:50) driver started: phase 0 (full set seeds 12-15, core 21, all-but-coelution-sum) then the screen,
  40 arms, design seed **8808** (UW25: 20261110), 37 factors each kept with p = 0.75, FDR seeds 1001-1040.
  ~16 min per arm, ~12 h. In the draw, `sg_weighted_xcorr` is dropped in only 4 arms (most others 5-15), so its
  effect will be loose; extend the design with `design.py screen --start 41` if the fit needs it.
- UW8 (15:04) **Phase 0 done** (protein-best ON, 20 spread files):

  | arm | kept at FDP 1% | q 1% kept (FDP) | FirstPassFDR | GB read |
  |---|---|---|---|---|
  | all 109, seeds 11-15 | 85,702 / 86,012 / 86,740 / 86,686 / 86,656 | 85,496-86,398 (0.91-1.03%) | 796-976 s | 142 |
  | core 21 only (= default mask) | 67,874 | 68,503 (1.07%) | 443 s | 44.7 |
  | all but `fragment_coelution_sum` (108) | 85,628 | 85,469 (0.98%) | 737 s | 142 |

  - **Noise band: mean 86,359, SD 472 (0.55%), range 1,038 (1.2%)** - 2.5x tighter than UW25's protein-best-off
    band (SD 1,194, 1.54%). Protein-best on makes single arms more informative, not less.
  - **The families buy +27% with protein-best on** (86,359 vs 67,874), against UW25's +40% with it off: part of
    what the families add, protein-best also adds. A set chosen with protein-best off may therefore over-keep.
  - `fragment_coelution_sum` masked: -731 (z -1.55), inside 2 SD; masking it is safe.
  - q 1% is calibrated with protein-best on (FDP 0.91-1.07%); UW25's off arms sit at ~0.58%.
- UW8: **parquet disk ceiling** (`colbytes.py`, file 0003, `colbytes-0003.txt`): 3.65 GB per file, of which PIN
  columns 2.30 GB (families 1.86, core 0.44) and non-PIN 1.36 GB (`cwt_candidates` 442 MB, `fragment_mzs` +
  `fragment_intensities` 386 MB, `reference_xic_*` 267 MB). Even core 21 alone leaves ~1.8 GB per file - the
  0.5-0.8 GB estimate in the Goal is too low unless Phase 5 also addresses those columns. Largest families:
  peak-profile (`peak_width`, 18 cols) 382 MB, `tc_*` 274 MB, per-fragment rank 160 MB, spectrum match 156 MB.
- UW8 (15:04-22:20) **Phase 1 screen done**: 40 arms, all exit 0, 52-102 features kept (9-15 families), kept at
  FDP 1% 80,599-86,317 (mean 83,688, SD 1,444); q 1% FDP 0.89-1.10% throughout. Ridge (lambda 3 by LOO CV, LOO
  RMSE 1,105 vs seed SD 472, bootstrap SE over arms, `fit.py`, `fit-screen40.txt`). Effect = detections gained by
  including the factor:

  | factor | effect | SE | z | | factor | effect | SE | z |
  |---|---|---|---|---|---|---|---|---|
  | **lib agreement** (HRAM) | +884 | 190 | 4.7 | | per-fragment rank | +49 | 128 | 0.4 |
  | **peak profile** (`peak_width`) | +823 | 158 | 5.2 | | wide | -2 | 182 | 0.0 |
  | **time corr `tc_*`** | +792 | 173 | 4.6 | | top-3 | -146 | 160 | -0.9 |
  | **spectrum match** (HRAM) | +576 | 173 | 3.3 | | dominance | -185 | 132 | -1.4 |
  | **context** | +417 | 112 | 3.7 | | core, best: `rt_deviation` | +352 | 232 | 1.5 |
  | heavy/tight | +346 | 157 | 2.2 | | `median_polish_residual_correlation` | +347 | 191 | 1.8 |
  | shadow | +330 | 169 | 2.0 | | core, worst: `median_polish_min_fragment_r2` | -381 | 148 | -2.6 |
  | spectrum-across-peak | +312 | 147 | 2.1 | | `abs_mass_accuracy_deviation_mean` | -302 | 106 | -2.8 |
  | clean/clip | +308 | 197 | 1.6 | | `peak_area` | -358 | 187 | -1.9 |
  | runner-up | +209 | 197 | 1.1 | | `sg_weighted_xcorr` (only 4 arms out) | -223 | 113 | -2.0 |
  | reference corr | +151 | 130 | 1.2 | | | | | |
  | median-polish top-k | +118 | 148 | 0.8 | | | | | |

  - Five families are clear (z >= 3.3); arms keeping all five average 85,459 (n=7), 1 family fewer 84,225 (n=13),
    2 fewer 83,279 (n=14): ~+1,000 per family, roughly additive at the top.
  - No core feature is clearly positive (all |z| < 2 positive); four are mildly NEGATIVE (z -1.9 to -2.8). At
    p = 0.75 a "negative" core effect most likely means a substitute stands in when it is out, not harm - tested
    as a block below rather than believed.
  - The additive fit under-predicts the full set (85,252 vs 86,359): ~1,100 of joint value the main effects miss.
- UW8 (22:25) **Phase 2 forward selection, step 1 queued** (16 arms, ~2.7 h). Deviation from the handoff plan:
  its start ("core features with clear positive effects, no families") is empty here, so the start is the screen's
  best small set = **core 21 + the 5 clear families** (59 features), 3 seeds (2001-2003); plus core-prune arms
  (the same minus the 5 negative-effect core features, 54 features, 2 seeds); plus each of the 11 other families
  added to the start, seed 2001. Accept a family when its arm beats the start by > 2 SD (~950), then confirm with
  3 seeds; stop when the set is within the full set's band (86,359 +- 944).
- UW8 (2026-11-10 ~23:30) Windows Update rebooted the machine during step 1 (8 of 16 arms done); resumed 02:30
  (driver restartable, the partial arm re-ran clean). No results lost.
- UW8 (03:31) **Forward step 1 done.** Start (core 21 + 5 clear families, 59 features): 82,205 / 82,406 / 82,604,
  **mean 82,405 - 3,954 (8 SD) below the full set**; the screen's "all five kept" arms reached 85,459 only because
  they also kept ~8 other families. Core prune (minus the 5 negative-effect core features, 54): 82,322 / 80,977
  (-755) -> core stays. Each other family added to the start, seed 2001:

  | added | kept at FDP 1% | gain | parquet |
  |---|---|---|---|
  | **runner-up** (`peak_coelution_margin`, 3 cols) | 84,251 | **+1,846** | 60 MB |
  | heavy/tight | 83,630 | +1,225 | 129 MB |
  | reference corr | 83,611 | +1,206 | 111 MB |
  | spectrum-across-peak | 83,491 | +1,086 | 62 MB |
  | wide / shadow | 82,931 / 82,870 | +526 / +465 | |
  | per-fragment rank / top-3 / mp top-k | 82,671 / 82,644 / 82,590 | +266 / +239 / +185 | |
  | clean/clip / dominance | 82,447 / 82,270 | +42 / -135 | |

  - Runner-up: the screen's +209 (z 1.1) undervalued it - its value appears only when its substitutes are out,
    which is what the forward stage is for. Cheap too: 3 columns.
  - Step 2 (queued 03:35): runner-up confirm seeds 2002-2003; then start + runner-up + each of heavy, ref corr,
    spectrum-across, wide, shadow, per-fragment rank (seed 2001, paired with the step-1 seed). The four with
    gains <= +250 are dropped as candidates; revisit at the end.
- UW8 (04:00) **Runner-up accepted**: start + runner-up = 84,251 / 84,440 / 84,628, mean 84,440 (+2,035 over
  the start, 4.3 SD). Gap to the full set now 1,919. Step 2 partial, vs 84,251 at seed 2001: heavy +879,
  ref corr +955.
- UW8 (04:00) **Feature reference** (all 109: what each measures, inputs, origin, file:line, nonzero rate, MB,
  screen effect, step-1 gain): https://claude.ai/artifact/GJb8TyeS6f2MYxV5tsU19b, data
  `ai/.tmp/sessions/20261110-uw8featset/featstats.json`. No feature needs a SIL standard: "heavy" is each
  fragment's natural 13C M+1, "shadow" the M-1 position, "reference" an endogenous fragment of the same peptide.
- UW8: **MS1 features are rarely populated** (file 0003, 4.2M rows): `ms1_precursor_coelution` nonzero on 22% of
  targets (33% of the strongest 10% by coelution), `ms1_isotope_cosine` on 7% (18%). Astral Orbitrap MS1 should
  give most real precursors an envelope, so this looks like an extraction/data problem, not chemistry - an MS1
  lead DIA-NN does use. Also `median_polish_min_fragment_r2` nonzero on 0.2% (a dead column). To investigate.
- UW8 (05:00) **MS1 correction - extraction is correct; the rate above was mostly the population.** Only
  68,947 of 2.09M target rows of file 0003 pass 1% FDR; the rest look like decoys (21%/6% nonzero, as decoys).
  Among PASSING targets: `ms1_precursor_coelution` nonzero 61%, `ms1_isotope_cosine` 40%; brightest MS2 decile
  97%/91%, faintest 42%/20%. Causes (verified on file 0003, scratch scripts in the session scratchpad):
  - The Astral MS1 is acquired centroided (`FTMS + c`, 240k, 375-985 m/z, 962 MS1 vs 160,527 MS2, ~1.5 s cycle)
    with a noise floor: lowest centroid ~5e4-1.2e5, found M0 median 4.1e5. Weak precursors are absent from the
    DATA; the mzML MS1 decodes identical to the `.spectra.bin` record. Not recoverable in Osprey.
  - Tolerance ruled out (3.3 ppm around +1.27 ppm; widening to 10 ppm adds ~2%, at background density).
  - **Fixable**: the isotope envelope reads only the MS1 scan nearest the apex (`PeakDataExtractor.cs:1427`);
    21.4% of passing targets have M0 in another scan of the peak. Taking the best-M0 scan (or summing over the
    peak) would lift `ms1_isotope_cosine` from 40% to up to 61% nonzero. Unmodified-sequence envelope
    (`Ms1Calculators.cs:90`) shifts values, never zeroes them.
  - Worth today: the screen puts both MS1 features at ~0 (-24 / -118, |z| < 1). Cheap test of the fix's value:
    offline best-scan cosine from the cache's MS1 section (~21 MB per file), passing targets vs decoys; then an
    "MS1 absent" indicator or missing-value handling so 0 stops meaning both "absent" and "uncorrelated".

## Related (not this TODO's work)
- **DIA-NN on three axes** (detections, wall time, disk), same machine and files: Brendan to request of UW8
  or MACS2. Bytes written per run by file type, and the peak free-space drop during the run.
- **Disk accounting in the log**: track bytes on disk the way `--memstamp` tracks memory, so the working
  space a 2,000-run experiment needs is measured rather than estimated.
- **Cache policy**: delete per-run artifacts once no later task needs them; which ones a rerun needs.
- **Entrapment ratio**: 1:1 entrapment doubles the library and the scored rows; how much the FDP oracle needs.
- **FirstPassFDR**: the protein-best round-1 run bound (UW25, pending commit), survivors-only intermediate
  files, and a fan-out FirstPassScoring task (other-machines TODO, UW25 section).
