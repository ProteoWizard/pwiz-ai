# TODO-20261110_osprey_feature_set.md

## Branch Information
- **PR**: [#5033](https://github.com/ProteoWizard/pwiz/pull/5033) (DRAFT, opened 2026-11-13), branch
  `Skyline/work/20261112_osprey_default_feature_set` -> base `Skyline/work/20261028_osprey_diann_fdr_gap` (#4950);
  to merge into #4950 before #4950's squash-merge to master (Brendan). Tip fab7e0caed (incl. #5030).
- **Branch (study experiments)**: Experiments run on `Skyline/work/20261110_osprey_uw25_pb_fixes`
  at c3bdbea78d (on `Skyline/work/20261109_osprey_scoring_uw8` f90d19aaa6, with the protein-best fixes and the
  round-1 run bound), snapshot `D:\test\osprey-runs\_bin\uw25-c3bdbea78d` (v26.1.1.314)
- **Base**: #4950 (`Skyline/work/20261028_osprey_diann_fdr_gap`) and its pending branches
- **Module**: `osprey`
- **Created**: 2026-11-10 (designed on BRENDANX-UW25; Brendan has given UW25 to this study for a few days)
- **Status** (2026-11-11 21:30): Phases 0-2 done on both machines. Candidate sets agree across UW8's and UW25's
  20-file sets: 77 families-only (-0.5%), B 57 (-0.4..-0.6%), 51 = B minus 6 weakest core (UW8 -0.3%), 46/42
  (UW25 core cuts, -1.1..-1.4%). **But at 82 files the 51 set costs -1.4% (UW8, same build, 95,264 vs 96,593)**:
  pruning costs grow with file count, so the default is chosen at 82 files. In flight on UW8 overnight: 82-file
  FirstPassFDR ladder 51 / 57 / 70 / 77 / 42 / 46 on the all-109 links. Pending: DIA-NN agreement (MACS2 report).

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
- **Shape (from the 2026-11-12 decision):** a named feature-set setting (e.g. `core` / `default` / `all`) with
  per-resolution defaults (HRAM `default` = B-57, unit `core`), replacing `DEFAULT_MASKED_FEATURES` as what an
  unset `OSPREY_FEATURE_MASK` means. The set chosen at SCORING decides what PerFileScoring computes and records,
  and `RecordedFeaturesValidityKeySuffix` already keys on that, so `all` remains the research route (score once,
  mask in FirstPassFDR).
- **Record at column granularity, not family granularity.** Today a family with one kept feature is recorded
  whole (`PinFeatureMask.cs:37`), so B's within-family cuts save FirstPassFDR read but not disk or write: B
  written today is ~3.0 GB/file, ~2.7 GB with column-level recording (82 files: 274 GB measured for the 51 set's
  families vs 317 GB for all 109). Families are still computed as units (CPU), only the unkept columns dropped.
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
- [ ] **Now pwiz issue #5023** (2026-11-12, assigned brendanx67; a PR to master, then merged into #4950; Brendan and
      MACS2). The notes below are its source. **Non-feature columns (UW25, 2026-11-11; measured on A01_005, 4.4M rows, 3.89 GB compressed / 7.00 GB
      uncompressed).** Features 2.45 GB (63%); `cwt_candidates` 490 MB (12.6%); `fragment_mzs` + `fragment_intensities`
      408 MB (10.5%); `reference_xic_rts` + `_intensities` 270 MB (6.9%); identity/RT/sequence columns ~240 MB.
      Readers found by name search (confirm before removing - a generic column copy or diagnostic could still read
      them):
      - `fragment_*`: no production reader (the only loader that fills them, `ParquetScoreCache.LoadFullFdrEntries`,
        has no production caller).
        **They are a verbatim copy of the library spectrum** (`CoelutionScorer.cs:570`: every library fragment's m/z
        and relative intensity, kept "because Rust's parquet writer at pipeline.rs:1620-1631 serializes every library
        fragment" - parity residue). Joinable by `entry_id` (library decoys are in the library; generated decoys are
        rebuilt deterministically). Repeated per candidate row and per run: ~33 GB at 82 runs, ~180 GB at 446. The
        clearest removal: no information lost, no new format.
      - `reference_xic_*`: only the opt-in `--training-export` (`TrainingEvidence.cs:488`, from the reconciled
        parquet). The 12 per-fragment XICs are not stored at all; the reference XIC is the only chromatogram.
      - `cwt_candidates`: reconciliation planning only (`CwtCandidateLoader` <- `Stage6Planner`,
        `RunReconciliationPlanner`), for the CWT re-pick of the rows it re-picks.
      - All three are still read by PerFileRescoring, whose streaming reconciled writer copies every column of the
        original parquet (`ReconciledParquetWriter.cs`).
      Proposal: stop writing `fragment_*` and `reference_xic_*` unless a consumer asks (training export), and move
      `cwt_candidates` to its own per-run file read only by the planner. ~30% of the scoring parquet - comparable to
      the 109 -> 77 feature cut, and additive with it.

## Open decisions (Brendan)
- **Decided (Brendan, 2026-11-12 ~03:45): three nested, selectable feature sets: core-21 ⊂ B-57 ⊂ all-109.**
  - **HRAM default: B-57** (pending the 82-file seed replicates and the pass-2 check; it keeps all 21 core).
  - **Unit-resolution default: core-21** for now, with B and all-109 selectable for future testing. At unit
    resolution B is 52 (the HRAM-only library-agreement and spectrum-match features are off there, as today).
  - **All-109 stays selectable**: scored with all 109, FirstPassFDR can still select any subset by mask (the
    record-all + mask route this study used throughout).
  - Stellar validation may lag: there is no strong DIA-NN result to judge it against. Astral/SEA-AD is where
    Osprey is judged against DIA-NN, so validation effort goes there.
- Acceptable loss for the default: settled in practice by DIA-NN agreement - B's losses are boundary churn
  (-0.36% DIA-NN-confirmed at 82 files, -0.34% at 20); the core cuts (-0.9 to -1.0%) are not accepted.
- ~~One set, or a smaller default plus an opt-in full set?~~ Three nested sets (above).
- ~~Unit-resolution data (Stellar)~~ core-21 default (above).

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

**UW25 Phase 1 done (2026-11-11 06:02; a Windows Update reboot at ~04:15 interrupted arm 79, whose partial dir
was deleted and re-run clean).** 80 arms, all exit 0, protein-best OFF. Fit `fit_screen.py` -> `effects.tsv`
(per feature: mean in - mean out with SE, unbiased under independent p = 1/2 inclusion; per family: OLS on the
fraction included).
- Random half-sets: mean 70,173, SD 3,654 (full set 77,360). Joint-fit LOO RMSE 2,043 vs seed SD 1,194: the
  excess is substitute interactions an additive fit cannot carry.
- Robust single features: `lib_entropy_sim` +3,003 +- 744, `rt_deviation` +2,492 +- 772, `tc_corr_rank5`
  +2,108 +- 822, `peak_rank_margin` +1,985 +- 717, `peak_coelution_margin` +1,914 +- 800. Harmful when included:
  `median_polish_residual_correlation` (core) -2,051 +- 793; also low: `n_coeluting_fragments`, `mp_fragment_r2_median`,
  `ms1_isotope_cosine`. Most features are within +-2 SE.
- Families (all-in vs all-out): peak profile +8,100 +- 3,400, core +6,700 +- 3,200, `tc_*` +5,200 +- 2,300, lib
  agreement +4,200 +- 1,200, runner-up +3,400 +- 1,300; median-polish top-k, spectrum match, clean/clip, shadow ~0.
- The two worst arms (p1-079 53,387, p1-063 60,783) both lack `rt_deviation` AND `abs_rt_deviation`,
  `lib_entropy_sim` and both runner-up margins: losing a substitute PAIR is what costs.
- **Against UW8 (protein-best ON):** agree on lib agreement, peak profile, `tc_*`, runner-up. Disagree on spectrum
  match (UW25 ~0, UW8 +576 z 3.3) and `median_polish_residual_correlation` (UW25 harmful, UW8 +347): both overlap
  what protein-best adds, so a protein-best-off ranking can mislead in either direction. UW8's protein-best-on
  noise (SD 472) is 2.5x tighter; it is the better instrument for the search itself.

**UW25 Phase 2 (started 2026-11-11 06:10): feature-level cut sweep, protein-best off.** Keep the top 82 / 55 / 41
/ 27 features by Phase 1 marginal rank (`ranking-p1.txt`), seeds 1-3 each, 12 arms (~2 h), against the full set's
seeds 1-3 (mean 77,459) and random halves (70,173). Tests whether a within-family feature ranking can cut columns
(the disk axis), which UW8's family-level forward selection does not address.

**Proposed split (UW25, for Brendan):** UW8 keeps the family-level forward selection (protein-best on). UW25 then
prunes WITHIN the families UW8 selects, protein-best ON, feature by feature (the disk axis: per-fragment rank 12
columns, peak profile 18, `tc_*` 9), on UW8's file set or UW25's links, whichever Brendan prefers. UW25 stops
protein-best-off arms after the current sweep.

**Split accepted (Brendan, 2026-11-11 ~06:30); goal stated: cut feature growth from 5x (21 -> 109) to 2-3x
(42-63 features).** UW25 Phase 3 queued behind the sweep, protein-best ON, UW25's 20 files:
- Anchors: all 109 seeds 2-3 (seed 1 = `p0-full-pbon`, 90,423); UW8's 93-feature set (all minus median-polish
  top-k, dominance, top-3, clean/clip; `set93.txt`) seeds 1-3.
- Within-set screen: 48 arms (`design_screen.py --n 48 --design-seed 20261111 --prefix p3 --p 0.75 --pool
  set93.txt --pb on`), each of the 93 (core included) kept with p = 3/4 (61-78 kept per arm). ~20 min per arm,
  ~18 h. Then cut-point sweeps on its ranking toward 42-63 features.

**UW25 Phase 2 sweep done (07:30), protein-best off.** Kept at FDP 1%, seeds 1-3 (vs all 109, seeds 1-3: 77,459):
top 82: 76,433 +- 264 (-1.3%, inside noise; FirstPassFDR 691 s, 110 GB); top 55: 73,943 +- 2,437 (-4.5%; 388 s,
88 GB); top 41: 68,522 +- 1,502 (-11.5%; 284 s, 77 GB); top 27: 69,513 +- 3,858 (-10.3%; 262 s, 55 GB).
- The bottom 27 by single-feature rank go free (agrees with UW8's 93-feature set). Below ~80 single-feature
  ranking FAILS: top 41 is worse than a random 54-feature half (70,173), because it drops substitutes together.
  Further cuts must be judged jointly - the Phase 3 within-set screen (protein-best on, p = 3/4) is for that.
- Seed spread grows as the set shrinks (+-264 at 82, +-3,858 at 27): a final small set needs more than 3 seeds.
- FDR read falls ~0.75 GB per dropped feature at 20 files.
- Phase 3 started 07:31.

**UW25 direction change (Brendan, 2026-11-11 09:40): the Phase 3 within-set screen is stopped** after 3 of 48 arms
(the other 45 parked in `arms-p3-parked.tsv`); UW25 now independently confirms UW8's sets on its own 20 files and
pushes toward one feature per family.
- **Brendan, for both machines: the goal is bytes written and read.** Every column costs its bytes whether or not
  its family is still computed (PerFileScoring writes it, FirstPassFDR reads it ~1.7x, PerFileRescoring reads it
  again). Cutting WITHIN families is where the disk saving is, even though scoring CPU is per family. The ideal is
  a single best score per family; unlikely to suffice everywhere, but the closer the better.
- UW25 protein-best-ON anchors (its first 20 files): all 109 seeds 1-3 = 90,423 / 91,267 / 91,084 (mean 90,925);
  UW8's 93 set seeds 1-3 = 90,139 / 90,539 / 90,392 (mean 90,357, -568, z ~ -1.6: slightly below, where UW8 saw
  +236). Screen arms p3-001..003 kept 89,035 / 87,570 / (running).
- UW25 within-family ranking from its three 93-set models (`withinfam.py` -> `withinfam-set77.tsv`, permutation
  drop): agrees with UW8 at the top of every family - `lib_entropy_sim` 6.2%, `spec_match_prob_max` 2.6%,
  `tc_best_sum6` 2.4%, `apex_log_intensity_excl_top` 1.6%, `peak_candidate_count` 0.45%, `window_share_rank2/1`
  0.68/0.62%, `tc_sum6` 0.33%, `context_precursor_mz` 0.96%, `peak_spectrum_cosine_sd` 0.39%, `shadow_corr_sum6`
  0.09%. `PROTEIN_BEST` 15.1%. **Core: `abs_rt_deviation` 3.6%; no other core feature reaches 0.3%.** At top-1
  per family the core is 21 of 31 features, so pruning the core is now the largest lever.
- Queued on UW25 (~09:45-13:30): all 109 seeds 4-5 (5-seed band); UW8's 77 set seeds 1-3 (`set77.txt`); UW25's own
  top 2 per family (41, `set77-top2.txt`) and top 1 (31, `set77-top1.txt`), core untouched, seeds 1-3. Next: core
  pruning on the top-1 set.
- **UW8: please post the exact feature lists of each candidate set in this TODO** (UW8's `ai/.tmp` is not
  visible from UW25), so UW25 can run them unchanged on its files.

**UW25 (2026-11-11 12:00) - UW8's sets on UW25's 20 files, protein-best ON, kept at true FDP 1%:**

| set | features | seeds | mean | vs all 109 | FirstPassFDR read | FirstPassFDR |
|---|---|---|---|---|---|---|
| all 109 | 109 | 90,423 / 91,267 / 91,084 / 90,258 / 89,710 | 90,548 (SD 634) | | 140 GB | ~1,000 s |
| UW8 77 | 77 | 89,536 / 90,690 / 89,971 | 90,066 | -483 (z ~ -1.0) | 114 GB | ~870 s |
| UW8 top 2 per family | 41 | 87,732 / 87,866 / 87,603 | 87,734 | -2,815 (-3.1%) | 74 GB | ~550 s |
| UW8 top 1 per family | 31 | 85,506 / 85,949 / 86,092 | 85,849 | -4,699 (-5.2%) | 58 GB | ~490 s |

- **The 77 set holds on a second file set.** Cutting every family to its top 1-2 at once costs 3-5%, as on UW8.
- Queued (12:05, ~3 h): UW8's candidates A 70 / B 57 / C 54 rebuilt from UW8's posted rankings (`set-A/B/C.txt`),
  3 seeds each; and **core pruning, which UW25 takes on**: C with the core cut to its top 10 by UW8's core ranking
  (`set-Ccore10.txt`, 43 features) and top 5 (`set-Ccore5.txt`, 38), 3 seeds each.

**UW25 (2026-11-11 14:40) - A/B/C and core pruning, UW25 files, protein-best ON, 3 seeds each, kept at true FDP 1%,
vs all 109 = 90,548 +- 634 (5 seeds):**

| set | features | seeds | mean | vs all 109 | read | FirstPassFDR |
|---|---|---|---|---|---|---|
| A | 70 | 89,860 / 90,545 / 90,030 | 90,145 | -403 (-0.4%, z -0.9) | 106 GB | 789 s |
| **B** | **57** | 89,745 / 90,511 / 90,424 | **90,227** | **-322 (-0.4%, z -0.7)** | **93 GB** | **612 s** |
| C | 54 | 88,690 / 89,225 / 88,876 | 88,930 | -1,618 (-1.8%, z -3.5) | 88 GB | 569 s |
| C, core top 10 | 43 | 88,853 / 88,712 / 88,347 | 88,637 | -1,911 | 80 GB | 540 s |
| C, core top 5 | 38 | 88,557 / 88,657 / 88,768 | 88,661 | -1,888 | 73 GB | 513 s |

- **A and B hold on UW25's files** (agrees with UW8); C's peak-profile top 2 costs ~1,300: peak profile needs top 5.
- **The core cut is nearly free: 21 -> 5 costs ~270 on C** (core top 5 by UW8's ranking: `abs_rt_deviation`,
  `fragment_coelution_max`, `median_polish_cosine`, `peak_area`, `ms1_isotope_cosine`). The other 16 core features
  (incl. `xcorr`, `fragment_coelution_sum`, the median-polish residuals) add nothing measurable next to the families.
  Calibration holds in every arm (FDP at q 1%: 0.90-1.04%).
- Queued (14:41, ~2 h): **B with core top 10 / 5 / 3 (46 / 41 / 39 features)**, 3 seeds each, and B seeds 4-5.
  B-core5 = 41 features, ~2x the original 21: the candidate for Brendan's target.

**UW25 (2026-11-11 16:27) - B with the core cut, UW25 files, protein-best ON, vs all 109 = 90,548 +- 634:**

| set | features | seeds | mean | vs all 109 | read | FirstPassFDR |
|---|---|---|---|---|---|---|
| B | 57 | 89,745 / 90,511 / 90,424 / 90,074 / 89,523 | 90,055 (SD 425) | -493 (-0.5%, z -1.2) | 93 GB | 619 s |
| **B, core top 10** | **46** | 89,820 / 90,112 / 90,146 | **90,026** (SD 179) | **-522 (-0.6%, z -1.1)** | **85 GB** | **558 s** |
| B, core top 5 | 41 | 89,784 / 89,692 / 89,174 | 89,550 | -998 (-1.1%, z -2.2) | 78 GB | 544 s |
| B, core top 3 | 39 | 88,142 / 89,702 / 88,051 | 88,632 | -1,917 (-2.1%, z -4.1) | 75 GB | 500 s |

- (Superseded at 20:40 - see the 6-seed correction below.) **46 features (2.2x the original 21) match all 109 on UW25's files**, with 40% less FirstPassFDR read and 45% less
  FirstPassFDR time. Core kept: `abs_rt_deviation`, `fragment_coelution_max`, `median_polish_cosine`, `peak_area`,
  `ms1_isotope_cosine`, `explained_intensity`, `peak_apex`, `rt_deviation`, `mass_accuracy_deviation_mean`,
  `n_coeluting_fragments` (`set-Bcore10.txt`). Calibration holds (FDP at q 1% 0.94-0.96%).
- Core 10 -> 5 costs ~500: one or more of core 6-10 carries value. Queued (16:28, ~2.5 h): B-core5 plus each of
  those five, 3 seeds each - a 42-feature set at ~2x if one feature recovers it.
- Proposal for UW8: replicate B-core10 (46) on UW8's files, the cross-file check for the candidate.

**UW25 (18:52) - B-core5 (41) plus each of core 6-10, 3 seeds each** (B-core5 89,550; B-core10 90,026):
`+mass_accuracy_deviation_mean` 89,835 (+285, -0.8% vs all 109); `+peak_apex` 89,506 (-44); `+n_coeluting_fragments`
89,475 (-75); `+explained_intensity` 89,447 (-103); `+rt_deviation` 89,351 (-199). No single feature recovers the
476 between core 5 and core 10, and that gap is itself only ~1.3 SE at 3 seeds. Candidates: **46 (B-core10, safe)**
and **42 (B-core5 + `mass_accuracy_deviation_mean`, ~2x)**. Queued (18:53, ~1.6 h): seeds 4-6 of B-core10,
B-core5 and the 42 set, for 6 seeds each.

**UW25 (20:40) - 6 seeds: CORRECTION. "46 features match all 109" (16:27) was premature on 3 seeds.** Seeds 4-6
run lower for every set (all 109 and B too), so compare paired at the same seeds (1-5, vs all 109 at seeds 1-5):
B (57) -493 (-0.5%); B-core5 + `mass_accuracy_deviation_mean` (42) -987 (-1.1%); B-core5 (41) -1,240 (-1.4%);
B-core10 (46) -1,307 (-1.4%). 6-seed means: 42 set 89,588 (SD 385), B-core10 89,168 (SD 993), B-core5 89,244 (SD
432); all 109 = 90,548 (SD 634, 5 seeds). Calibration holds throughout (FDP at q 1% 0.94-1.07%).
- **The core cut costs ~0.5-0.9% beyond B, at 10 core features or 5:** the value is in the 16 dropped core
  features jointly, not in one of them (consistent with the add-back result).
- **Choice for Brendan:** B, 57 features (2.7x; -0.5%, inside noise; read 93 GB vs 140), or the 42 set (2x; -1.1%;
  read 80 GB). Proposed: settle it at 82 files, full pipeline, B vs 42 head to head (detections, calibration, and
  end-to-end PerFileScoring write / FirstPassFDR / PerFileRescoring I/O and time).

**UW25 (2026-11-11) - new axis: agreement with DIA-NN (Brendan). REQUEST FOR MACS2 below.**
- **The gap.** Every number in this study (and in #4950's closing of the gap to DIA-NN) is a COUNT at true FDP
  1%. A count does not say which precursors were found. "Closer to DIA-NN's count" was read as "finding more of
  what DIA-NN finds", but the tools disagree, and nothing measured whether the precursors gained (or, here, the
  ~0.5-1% lost by the core cut) are ones DIA-NN identifies confidently. Losing precursors DIA-NN does not identify
  costs less than the count suggests; gaining ones DIA-NN does not identify is worth less.
- **The metric, now in `ai/scripts/Osprey/SEA-AD/tools/split_calibration.py` (pwiz-ai a5c1a4e7):** `--agree
  <DIA-NN report.parquet>` takes each Osprey arm's real-target precursors at true FDP 1% and counts how many DIA-NN
  identifies at run `Q.Value <= 0.01` in at least one of the SAME runs (read from the arm's `run.log`, so an 82-run
  report compares fairly with a 20-file arm); matched on modified sequence (UniMod) + charge = `Precursor.Id`.
  `--reference <run dir>` splits every other arm's LOST and GAINED precursors by DIA-NN status. Tested on a
  synthetic report with a known answer; reads the gzipped FDRBench tables every featset arm kept, so all ~170 UW25
  arms can be re-scored without re-running.
- **What is missing on UW25:** a DIA-NN report covering UW25's 20 files (SEA-AD samples 0001-0020, i.e. the first
  20 of the 82 in name order) on the same peptides. UW25 has DIA-NN 2.6.1 but no SEA-AD DIA-NN library.
- **REQUEST (MACS2):** copy the 82-file DIA-NN 2.7.0 `report.parquet` on the split peptides
  (`diann-vs-osprey\seaad\bisect\runs82\A2-sized\report.parquet`, or whichever 82-file DIA-NN report is current)
  to UW25 at `D:\test\osprey-runs\sea-ad\diann\runs82-A2-sized\report.parquet` (lab share or any path
  Brendan prefers), and note here: DIA-NN version, library, settings (NN, MBR), and that it covers all 82 runs. Its
  own entrapment draw does not matter: agreement compares real targets only. If no such report exists, say so and
  UW8 or UW25 will run DIA-NN 2.7.0 on UW25's 20 files instead.
- Once it lands, UW25 re-scores all 109, B (57), the 42 set, B-core10 (46) and the core-cut arms against it, and
  adds agreement to the driver's results row.
- **MACS2 answer (2026-11-11 23:20): delivered, but not the A2-sized report.** The 82-file A2-sized run never ran
  (`runs82\A2-sized` is empty; its chain waited on a timing slot that ended). The current 82-file report is
  in **`U:\data\MacCoss\Osprey\sea-ad\diann-search-82\report.parquet`** (742 MB, with `report.log.txt`; moved
  there 2026-11-12 from `U:\Claude`; on MACS2 U: is `\\gs-ddn2\maccoss-vol1\home\brendanx`; MACS2
  source `D:\Users\brendanx\test\diann-vs-osprey\seaad\diann-search-82\`, 2026-10-30). UW25 copies it to its own
  `D:\test\...` path.
  - **DIA-NN 2.7.0**, all **82 runs** (checked: 82 distinct `Run`; 7,949,466 rows, 6,384,524 at run `Q.Value <=
    0.01`).
  - **Library**: DIA-NN's own in-silico prediction (`--lib library.predicted.speclib`) from
    `target_entrapment_peptides.fasta`, i.e. the same peptides with no digestion (`--cut`): **all 1,391,588 real
    targets of the split-sized library are in it** (checked against `osprey_library_db_peptides.fasta`) plus
    1,391,232 entrapment. Precursor m/z 400-900 (the Osprey library spans 399.94-902.16, so edge precursors are
    absent from DIA-NN's), charge 2-3, length 7-35, UniMod4. Spectra and RTs are DIA-NN's predictions, not Carafe's.
  - **Settings**: NN on (default; no `--no-nn`), **MBR on (`--reanalyse`)**, `--rt-profiling`,
    `--individual-mass-acc`, `--individual-windows`, `--pg-level 0`, **`--qvalue 0.05`: the report holds rows up to
    5%, so filter `Q.Value <= 0.01`**. MBR means a run's 1% can include identifications transferred from other runs
    of the 82; Osprey's arms have no equivalent, so agreement is an upper bound on what DIA-NN finds per run alone.
  - Not sent: the Carafe-library 82-file report (`diann-search-82-carafe`): its `carafe_targets.tsv` holds only
    1,131,671 of the 1,391,588 real targets (81%), so 19% could never count as agreed.
- **UW8 answer (2026-11-12 01:00): UW8 has the same 82-file search, plus the NO-MBR first pass.** UW8 ran DIA-NN
  2.7.0 on all 82 runs on 2026-11-09/10 (`D:\test\osprey-runs\sea-ad\runs-uw8\diann270-82files`) with MACS2's
  settings: library predicted by DIA-NN from the split-sized library's peptides
  (`lib\diann-split-sized\peptides.fasta`, 2,782,820 entries, `--cut`), MBR on (`--reanalyse`), `--rt-profiling`,
  `--individual-mass-acc`, `--individual-windows`, `--pg-level 0`, `--qvalue 0.05`, m/z 400-900, charge 2-3,
  length 7-35, UniMod. Copied for UW25 to **`M:\home\brendanx\data\MacCoss\Osprey\sea-ad\diann-search-82-uw8\`**
  (UW8's M: = MACS2's U:): `report-first-pass.parquet` (505 MB), `report.parquet` (733 MB), both logs.

  | report (Q <= 0.01) | runs | per-run median (min-max) | union |
  |---|---|---|---|
  | MACS2 final, MBR | 82 | 81,020 (50,040-97,428) | 118,703 |
  | UW8 final, MBR | 82 | 79,684 (49,777-95,883) | 116,670 |
  | **UW8 first pass, no MBR** | 82 | **57,323** (31,950-81,576) | 145,960 |

  - The two MBR reports agree within 1.6% per run (same settings, two machines).
  - **MBR adds ~39% per run.** Agreement against an MBR report credits DIA-NN with identifications transferred
    from other runs, which Osprey's per-run arms cannot match. `report-first-pass.parquet` is DIA-NN's per-run
    search before reanalysis, the like-for-like reference; suggest scoring agreement against BOTH and reporting
    the pair. (Same 72 columns, so `split_calibration.py --agree` reads it unchanged.)

**UW25 (2026-11-12) - first DIA-NN agreement results** (UW8's 82-file reports, copied to UW25
`D:\test\osprey-runs\sea-ad\diann\uw8-82\`; seed 1 of each set, UW25's 20 files; Osprey real targets at true FDP
1% inside DIA-NN's search space m/z 400-900, charge 2-3, length 7-35; `featset/agreement-seed1*.txt`).
`split_calibration.py` gained `--agree-space` (default DIA-NN's space; m/z computed from the sequence, checked against
DIA-NN's `Precursor.Mz` to 6e-5) and `--agree-global` (also require `Global.Q.Value <= 0.01`, as
`compare_osprey_diann.py` does, so the union over runs does not accumulate run-level FDR); pwiz-ai 79d57930.
- All 109: **92-96% of Osprey's real targets are DIA-NN-identified** (first pass no MBR, run q in any run: 96.0%;
  plus global q: 91.6%; MBR final: 95.4%). DIA-NN-only 12k (strict) to 30k (union of runs).
- Lost / gained vs all 109 (strict): the precursors that change are borderline - only ~50% DIA-NN-confirmed vs 92%
  overall - and two SEEDS of all 109 swap 2-3k with the same ~50% profile. Net DIA-NN-confirmed change: seed 2 +329;
  77 -412; A -339; **B -428**; B-core10 -404; **42 -587**; C -1,012; top 2 -1,829; top 1 -3,370 (of 82,711).
- Deeper cuts eat confirmed precursors: the confirmed share of LOST rises from 49% (77, B) to 61% (top 1) while the
  confirmed share of GAINED falls to 41%. Counts alone hide this asymmetry.
- **Lost-agreed q histograms (Brendan's request; `split_calibration.py --lost-hist`, `featset/lost-hist-seed1.txt`).**
  The precursors both tools identified with all 109 that a change loses sat at the 1% boundary in BOTH tools. B
  (1,397): Osprey q (all 109) 81% in 0.3-1% and 14% just over (vs 7.6% / 0.5% of all 82,711 agreed); DIA-NN global q
  above 1e-3 for 60% (vs 14%), under 1e-4 for 4.6% (vs 55%). The 42 set is the same. **Seed 2 of all 109 loses the
  same kind of precursors with the same profile**: B's and 42's losses are boundary churn, not lost signal. Top 1
  differs: 27% of its lost-agreed had Osprey q under 0.3% (B: 5%) - deep cuts lose confident precursors.
- **Seed-paired agreement** (each set vs all 109 at the SAME seed, mean +- SD over seeds; DIA-NN-confirmed = run q
  and global q <= 1%, no-MBR first pass; `featset/paired_agreement.py` -> `paired-agreement.txt`). Net change /
  net change among DIA-NN-confirmed (of ~82,700) / confirmed share of lost / of gained:
  B (57, 5 seeds) -493 +- 283 / **-281 +- 133 (-0.34%)** / 49.8% / 47.9%; A (70, 3) -780 / -403 / 49% / 48%;
  77 (3) -860 / -405 / 48% / 49%; **42 (5) -988 / -633 +- 107 (-0.77%)** / 52.0% / 46.3%; B-core5 (41, 5) -1,240 /
  -750 / 52% / 47%; B-core10 (46, 5) -1,308 / -770 / 51% / 47%; C (54, 3) -1,994 / -1,103 / 52% / 48%; top 2 (41, 3)
  -3,188 / -1,998 / 55% / 43%; top 1 (31, 3) -5,068 / -3,322 / 59% / 42%.
  - B's swap with all 109 is close to a neutral exchange of borderline precursors; the core cuts cost ~2x B in
    confirmed precursors and tilt the exchange (52% vs 46%); the tilt grows with cut depth (2 -> 18 points).
- **REQUEST (UW8): the 82-file ladder's FDRBench tables**, so UW25 can score agreement where losses are larger (B -0.6%,
  51 set -1.4% at 82 files). For each arm in `results82.tsv` (all 109 at every seed, 51, B, A, 77, 42, 46): copy
  `fdrbench.pass1.tsv` (gzip is fine) and `run.log` (the tool reads the run list from its command line) to
  `M:\home\brendanx\data\MacCoss\Osprey\sea-ad\featset82-uw8\<arm>\`. UW25 then runs `paired_agreement.py` on them
  against the same no-MBR report. UW8 can equally run `split_calibration.py --agree <report-first-pass.parquet>
  --agree-global --reference <all-109 dir> --lost-hist` itself; posting both machines' tables side by side is the
  goal.
- Done on UW25 (2026-11-12): the driver (`run-arms.ps1 -AgreeReport`, default the no-MBR first pass) now writes
  `diann_both` and `diann_pct` (strict definition) on every arm's results row; paired lost/gained stays in
  `paired_agreement.py`, which needs the matching all-109 seed.

**UW25 (2026-11-12 10:00) - B vs all 109 at 82 files, six paired seeds on two machines** (UW8 seeds 1-3 from the
staged `featset82-uw8` tables; UW25 seeds 4-6 on its own links, `p8-82-*`; FirstPassFDR only, protein-best on,
c3bdbea78d; pass 1, kept at true FDP 1%; DIA-NN-confirmed = strict, no-MBR first pass; `featset/agreement82-*.txt`):

| seed | all 109 | B (57) | diff | DIA-NN-confirmed diff | lost / gained % confirmed |
|---|---|---|---|---|---|
| 1 UW8 | 96,593 | 96,055 | -538 | -319 | 50.6 / 48.6 |
| 2 UW8 | 96,779 | 95,745 | -1,034 | -638 | 51.1 / 45.4 |
| 3 UW8 | 96,806 | 96,241 | -565 | -401 | 50.9 / 46.1 |
| 4 UW25 | 96,911 | 95,853 | -1,058 | -479 | 47.8 / 48.9 |
| 5 UW25 | 96,193 | 96,250 | +57 | +20 | 48.6 / 48.2 |
| 6 UW25 | 97,289 | 96,213 | -1,076 | -680 | 50.4 / 43.6 |
| **mean +- SD** | 96,762 +- 360 | 96,060 +- 210 | **-702 +- 447 (-0.73%, z ~ -3.8)** | **-416 +- 254 (-0.47% of ~88,000)** | ~50 / ~47 |

- B's cost at 82 files is real (not seed noise) but small: ~700 precursors, ~420 DIA-NN-confirmed, all boundary
  churn - the confirmed lost sat at Osprey's 1% boundary (90-95% with all-109 q 0.3-1%, vs 8% of all agreed) and
  are rarely DIA-NN-confident (2-3% at global q < 1e-4, vs 52%).
- B buys 33% less FirstPassFDR read at 82 files (340 vs 505 GB on UW25) and ~12% less FirstPassFDR time on HDD
  (3,140 vs 3,580 s), more with column-level recording (#5023). B's seed SD (210) is below all 109's (360).
- **UW8 answer (2026-11-12 02:30): 82-file tables staged, and agreement run on UW8.** Staged (`stage82.py`) to
  `M:\home\brendanx\data\MacCoss\Osprey\sea-ad\featset82-uw8\<arm>\` (`fdrbench.pass1.tsv.gz` + `run.log`):
  `ref82-all109-c3bdbea78d-s1` (all 109, seed 1), `x82-A-70-s1`, `x82-77-s1`, `x82-B-57-s1`, `x82-B-core6-51-s1`,
  `x82-uw25-42-s1`, and `full-set51-c3bdbea78d-s1` (the full-pipeline 51 run; identical pass 1 to x82-51).
  Still to stage as they finish (~08:00): `x82-uw25-46-s1`, `x82-all109-s2/s3`, `x82-B-57-s2/s3`,
  `x82-B-core6-51-s2`. UW8 ran `split_calibration.py --agree report-first-pass.parquet --agree-global --reference
  ref82-all109-c3bdbea78d-s1 --lost-hist` (`ai/.tmp/sessions/20261110-uw8featset/agreement82-seed1.txt`). 82 files,
  seed 1, strict (run q and global q <= 1%, no MBR); all 109 = 96,593 at FDP 1%, 88,025 both (91.3%):

  | set | features | kept at FDP 1% | both | lost (DIA-NN %) | gained (DIA-NN %) | **net confirmed** |
  |---|---|---|---|---|---|---|
  | A | 70 | 96,408 | 87,868 | 2,642 (50.1%) | 2,459 (47.4%) | -157 (-0.18%) |
  | 77 | 77 | 96,111 | 87,730 | 2,658 (51.0%) | 2,175 (48.7%) | -295 (-0.34%) |
  | **B** | **57** | **96,055** | **87,706** | 3,009 (50.6%) | 2,474 (48.6%) | **-319 (-0.36%)** |
  | 51 (B - 6 core) | 51 | 95,264 | 87,245 | 3,465 (52.6%) | 2,136 (48.8%) | -780 (-0.89%) |
  | UW25 42 | 42 | 95,359 | 87,160 | 3,771 (54.9%) | 2,535 (47.6%) | -865 (-0.98%) |

  - **At 82 files B costs the same in DIA-NN-confirmed precursors as on UW25's 20 files (-0.36% vs -0.34%).** Its
    lost confirmed precursors sat at Osprey's 1% boundary: 94% had all-109 q 0.3-1% (all agreed: 8%), DIA-NN global
    q above 1e-3 for 66% (all agreed: 15%). Boundary churn, as UW25 found.
  - **The core cuts cost ~2.5-3x B in confirmed precursors at 82 files (-0.9 to -1.0%)**, and the exchange
    tilts (lost 53-55% confirmed vs gained 48%). The 42 set's lost confirmed include more confident ones: 9.4%
    with all-109 q 1e-3..3e-3 (A / 77 / B: 3-5%).
  - **The line, on both machines and both scales: B (57) is boundary churn; cutting the core starts to cost
    precursors both tools agree on.** The noise yardstick at 82 files (all 109 seed 2 / 3 vs seed 1) lands by
    ~08:00 and is added here then.
- **UW8 to UW25 (2026-11-12 03:30): the tables you asked for are staged (above, 02:30).** Both machines favour B
  (57, all 21 core). Proposed validation for UW25 while it is idle (Brendan to confirm):
  1. **B vs all 109 at 82 files, seeds 4-6, on UW25's own links.** UW25's three legs
     (`runs-uw25\seaad-{20,21,41}files-...-score*`, mask none, all 109 recorded) cover the 82 files, so FirstPassFDR
     -only arms work as UW8's do (`-LinkFrom` all three, `OSPREY_RECORD_ALL_FEATURES=1`, protein-best on,
     `-FdrBenchPass 1`, ~1 h each). Six arms, paired by seed, with agreement on the driver row. With UW8's seeds
     1-3 that gives 6 seeds of B vs all 109 at cohort scale on two machines: whether B's -0.6% (-0.36% confirmed)
     is distinguishable from seed noise. B's exact mask: column 5 of `x82-B-57-s1` in UW8's `arms82.tsv`, also =
     the feature list of candidate B posted above.
  2. ~~Phase 3 datasets~~ - **Stellar deferred (Brendan, 03:45)**: unit resolution keeps core-21 by default, and
     there is no strong DIA-NN reference there. The Astral regression dataset (HRAM) is still a cheap second
     check of B beyond SEA-AD if UW25 has time after item 1.
  - UW8 takes **pass 2 with B** (FirstPassFDR -> SecondPassFDR at 82 files on the all-109 links) after its seed
    arms finish ~07:30: every arm so far reads pass 1, and #4950 reports pass 2.
  - The first pass has the larger union (146k vs 117k): DIA-NN's second pass searches only precursors that passed
    the first pass experiment-wide - another reason to keep both.

### UW8 replicate

**UW8 status (2026-11-11 21:30) - supersedes the 10:00 block below it.**
- **Sync with UW25:** both machines now test the same candidate sets, built from the rankings posted above. UW25
  has confirmed UW8's 77 / A / B on its files and carried the core cut further (46, 42). UW8's 51 set = B minus
  the 6 core features with permutation drop <= 0 (15 core kept); it sits between UW25's B (21 core) and B-core10.
- **New, for UW25's plan: 20-file losses understate 82-file losses.** The 51 set: -0.3% at 20 files, **-1.4% at 82**
  (all 109 on the same build c3bdbea78d = 96,593; the build is not the cause). UW25's 42 set (-1.1% at 20) is
  therefore likely to cost more at 82. Rather than a full-pipeline B-vs-42 run (7 h each), UW8 is reading the
  whole ladder at 82 files FirstPassFDR-only on the all-109 links (~1 h each, detections + FirstPassFDR I/O):
  51, 57 (B), 70 (A), 77, then UW25's 42 and 46 (exact UW25 core lists: core 5 = `abs_rt_deviation`,
  `fragment_coelution_max`, `median_polish_cosine`, `peak_area`, `ms1_isotope_cosine`; 42 = B with core 5 +
  `mass_accuracy_deviation_mean`; 46 = B with core 10). Results land in `results82.tsv` and here by morning.
- **Full-pipeline timing is measured (51 set, 82 files, 6.77 h vs 7.45 h): PerFileRescoring does not get faster
  from feature cuts** (-0.6%), because it reads mostly non-PIN columns. That I/O is Phase 5's, not the feature
  set's - so a second 7-h full-pipeline run per candidate would add little beyond the FirstPassFDR numbers.
- Proposed division for tomorrow (for Brendan): UW8 picks the 82-file cut point from the ladder and runs its
  seeds; UW25 runs DIA-NN agreement on all arms once MACS2's report lands (its tool already reads every arm's
  FDRBench table, UW8's included, given the run dir).

**UW8 status (2026-11-11 10:00) - read this first; the timeline below has every number.**
- **Best set so far: 77 features = core 21 + 10 families, 86,374 at true FDP 1% (3 seeds), equal to all 109
  (86,359 +- 472, 5 seeds).** Families kept: library agreement, peak profile, `tc_*`, spectrum match, context,
  runner-up, spectrum-across-peak, reference corr, M+1/narrow-tolerance (`heavy_*`, `tight*`, `tc_best_sum6`),
  shadow. Dropped (6): wide, per-fragment rank, median-polish top-k, dominance, top-3, clean/clip. FirstPassFDR
  read 116 GB vs 142 GB at 20 files. Mask string: `design.py mask` on those factors, or copy column 5 of any
  `fb2-nowide-nofrag-base-*` row of `ai/.tmp/sessions/20261110-uw8featset/arms.tsv`.
- **Approach, and why it worked where single-feature ranking did not.** Every arm: protein-best ON, 20 files
  spread over the cohort, pass-1 split oracle at true FDP 1%; seed SD 472 with protein-best on (2.5x tighter than
  off), so 3 seeds resolve ~550. The unit is the FAMILY until the family set is fixed:
  1. Screen (40 arms, families + the 21 core as 37 factors, p = 0.75): found 5 clear families, nothing else.
  2. Forward from core + those 5 (82,405): runner-up +2,035, then spectrum-across-peak. After that, single
     additions fell inside noise (-338..+331) while all five remaining TOGETHER reached the full set (93
     features, 86,595): the last ~1,350 is joint, invisible one at a time.
  3. So switched to backward from that 93-feature set, dropping one family at a time (2-3 seeds each): wide
     and per-fragment rank go free; heavy (-837), ref corr (-929), shadow (~-650) stay.
  Lesson matching UW25's Phase 2: cutting by single-feature rank drops substitutes together. Removing whole
  families from a set that already matches the full set, one at a time, keeps every remaining substitute in place.
- **In flight (10:10): within-family cuts on the 77 set**, ranked by the arms' own GBDT permutation drop
  (`withinfam-93set.txt`): top 2 per family (41 features) and top 1 (31), 3 seeds each, core untouched. One or
  two features carry most families (`lib_entropy_sim` 6.1% vs 0.1%; `spec_match_prob_max` 3.1%; `tc_best_sum6`
  2.7%; `apex_log_intensity_excl_top` 1.3%; `window_share_rank1-5` in peak profile). UW25 found single-feature
  ranking failing below ~80, so a top-k miss is expected and is handled per family, below.
- **Next (UW8):** if top 2 holds, try top 1 per family one family at a time; if it misses, restore families to
  full one at a time (largest first: peak profile 18 cols, `tc_*` 9) to find which family's cut costs. Then prune
  core (UW8's screen had four core features mildly negative; a block test of them cost -755 at the 59-set stage,
  to re-test on the final set). Target Brendan's 42-63. Then the end set at 82 files, full pipeline, cold, per
  stage (PerFileScoring write, FirstPassFDR, PerFileRescoring) vs all 109.
- **Suggestion for UW25 (for Brendan to decide):** point the Phase 3 within-set screen at the 77-feature set
  instead of the 93 (the 16 extra are wide + per-fragment rank, now shown droppable), which shortens it.
  Alternatively, give UW25 the per-family top-k confirmation on its own file set as an independent check of
  whatever UW8 ends with: agreement across two file sets is the robustness test.

**UW8 within-family rankings (for UW25 to replicate; copied here because `ai/.tmp` is not in git).** GBDT
permutation drop in % (`TrainingAnalysis.Features[i].PermutationDrop` x 100), mean over the 3 seeds of the
93-feature set (`f3all-base-s2001..3`), protein-best ON, UW8's 20 files. Each list is in rank order:
  - `core`: abs_rt_deviation 3.93, fragment_coelution_max 0.36, median_polish_cosine 0.24, peak_area 0.23, ms1_isotope_cosine 0.21, explained_intensity 0.20, peak_apex 0.16, rt_deviation 0.14, mass_accuracy_deviation_mean 0.11, n_coeluting_fragments 0.10, sg_weighted_cosine 0.07, sg_weighted_xcorr 0.06, xcorr 0.06, abs_mass_accuracy_deviation_mean 0.04, fragment_coelution_sum 0.01, median_polish_min_fragment_r2 0.00, ms1_precursor_coelution -0.01, median_polish_residual_ratio -0.02, consecutive_ions -0.05, peak_sharpness -0.06, median_polish_residual_correlation -0.07
  - library agreement: lib_entropy_sim 6.07, lib_cosine_coel 0.12, lib_coel_share 0.09
  - spectrum match: spec_match_prob_max 3.12, spec_proj_cosine_xt_max 0.46, spec_hyperscore -0.04, spec_proj_cosine_xt -0.09, spec_match_prob -0.23
  - M+1/narrow-tolerance: tc_best_sum6 2.74, tight45_sum6 0.57, heavy_sum6 0.50, tight20_sum6 0.12, heavy_n_good 0.08
  - context: context_precursor_mz 2.15, context_peptide_length 1.04, context_precursor_charge -0.02
  - peak profile: window_share_rank1 1.46, window_share_rank2 1.29, window_share_rank3 1.04, window_share_rank4 0.75, window_share_rank5 0.74, window_share_rank6 0.29, local_corr_top3_mean 0.25, shape_bin1 0.15, peak_width 0.13, shape_bin3 0.08, shape_bin5 0.05, lib_rel_rank2 0.04, shape_bin2 0.01, lib_rel_rank6 -0.03, lib_rel_rank5 -0.04, lib_rel_rank3 -0.06, shape_bin4 -0.07, lib_rel_rank4 -0.08
  - reference corr: apex_log_intensity_excl_top 1.34, ref_corr_rank2 0.10, ref_minfilt_corr_top3_mean 0.03, ref_corr_rank5 0.01, ref_n_corr_good 0.00, ref_corr_rank3 -0.00
  - runner-up: peak_candidate_count 0.87, peak_rank_margin 0.09, peak_coelution_margin -0.03
  - `tc_*`: tc_corr_rank1 0.81, tc_sum6 0.46, tc_corr_rank2 0.40, tc_res_sum 0.23, tc_res_mean 0.22, tc_corr_rank5 0.21, tc_corr_rank4 0.20, tc_corr_rank3 0.16, tc_corr_rank6 0.08
  - shadow: shadow_corr_sum6 0.30, shadow_frac6 0.12
  - spectrum-across-peak: peak_spectrum_cosine_sd 0.24, peak_spectrum_cosine_mean 0.08
  - (the model's 94th input `PROTEIN_BEST`: 20.39)

The two within-family arms (all 21 core kept in both):
  - **top 2 (41)** = core + peak_rank_margin, peak_candidate_count, context_peptide_length, context_precursor_mz, peak_spectrum_cosine_mean, peak_spectrum_cosine_sd, ref_corr_rank2, apex_log_intensity_excl_top, window_share_rank1, window_share_rank2, tc_sum6, tc_corr_rank1, tight45_sum6, tc_best_sum6, shadow_corr_sum6, shadow_frac6, lib_cosine_coel, lib_entropy_sim, spec_match_prob_max, spec_proj_cosine_xt_max
  - **top 1 (31)** = core + peak_candidate_count, context_precursor_mz, peak_spectrum_cosine_sd, apex_log_intensity_excl_top, window_share_rank1, tc_corr_rank1, tc_best_sum6, shadow_corr_sum6, lib_entropy_sim, spec_match_prob_max

**Deriving a ranking from UW25's own models.** `out.1st-pass.model.json` (kept in every arm dir) holds what is
needed, no extra run: `FeatureNames` (the model's inputs in order, incl. `PROTEIN_BEST` when protein-best is on);
`FoldGbtModels[k]` per CV fold, flat node arrays `Feature` / `Threshold` / `Left` / `Right` / `Leaf` (a node with
`Left >= 0` is a split, `Feature[node]` the input index) - count splits per feature for split share; and
`TrainingAnalysis.Features[i]` per input: `Auroc` (univariate, on the training subset of ~100k targets / ~99k
decoys - the relevant population, unlike AUROC over all scored candidates, which is ~0.52 for everything),
`CohenD`, `PermutationDrop`, `PermutationPassing`. UW8 ranked by `PermutationDrop`; split share agreed on the
leaders. Permutation drop undercounts a feature whose substitute is present (shuffle one, its twin covers), so
read it as an order to test, not as a value.

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
  97%/91%, faintest 42%/20%. Causes (verified on file 0003, scripts in `ai/.tmp/sessions/20261110-uw8featset/ms1/`):
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
- UW8 (04:32) **Forward step 2**, added to start + runner-up (paired with its seed-2001 arm, 84,251):
  spectrum-across +1,138, ref corr +955, heavy +879, per-fragment rank +826, shadow +749, wide +564 - all
  within one single-arm difference SD (~670) of each other. Accepted spectrum-across (nominal leader, cheapest:
  2 cols, 62 MB). Confirm: 85,389 / 84,509 / 85,112, **mean 85,003** (+563 over 84,440, z ~1.5: weak).
- UW8 (05:40) **Forward step 3 hit the method's resolution**, added to start + runner-up + spectrum-across
  (paired with 85,389): shadow +331, ref corr -52, wide -89, heavy -189, per-fragment rank -338 - all noise. But
  **all five together (93 features): 86,693, inside the full set's band** (86,359 +- 472). So past ~85,000 the
  last ~1,350 comes from several families jointly, each too small to see alone. The 93-feature set drops four
  families entirely: median-polish top-k, dominance, top-3, clean/clip (16 features).
- UW8 (05:45) **Switched to backward elimination from the 93-feature set**: 2 more seeds of it, and each of the
  five late families dropped in turn, 2 seeds each (12 arms, ~1.6 h).
- UW8 (07:45) **93-feature set confirmed: 86,693 / 86,610 / 86,482, mean 86,595 (SD 106)** vs full 86,359 +- 472.
  Backward step 1, each family dropped from it (2-seed mean; paired 93-set mean 86,652):

  | dropped | kept at FDP 1% (seeds) | mean | change | parquet saved |
  |---|---|---|---|---|
  | wide | 86,490 / 86,415 | 86,453 | -199 | 90 MB |
  | per-fragment rank (12 cols) | 85,954 / 86,567 | 86,261 | -391 | 160 MB |
  | shadow | 85,887 / 86,256 | 86,072 | -580 | 62 MB |
  | heavy (M+1) | 85,735 / 85,894 | 85,815 | -837 | 129 MB |
  | ref corr | 85,854 / 85,592 | 85,723 | -929 | 111 MB |

  Wide dropped (89 features). Heavy and ref corr stay. Backward step 2 (queued 07:46, 10 arms): no-wide seed 3;
  no-wide + no-per-fragment-rank, no-wide + no-shadow, no-wide + both, 3 seeds each.
- UW8 (08:15) **Within-family ranking** from the 93-set arms' saved GBDT models (`withinfam.py`,
  `withinfam-93set.txt`: training-subset AUROC, permutation drop, split share, 3 seeds). As Brendan expected, one
  or two features carry each family: lib agreement -> `lib_entropy_sim` (perm 6.1%, others 0.1%); spectrum match
  -> `spec_match_prob_max` 3.1% (+ `spec_proj_cosine_xt_max` 0.5%, rest <= 0); M+1/narrow-tol -> `tc_best_sum6`
  2.7%; ref corr -> `apex_log_intensity_excl_top` 1.3%; runner-up -> `peak_candidate_count` 0.9%; peak profile ->
  `window_share_rank1-5` (0.7-1.5%; `lib_rel_*` and most shape bins ~0); `tc_*` spread; per-fragment rank all
  <= 0.13%. Permutation drop undercounts substitutes, so this is a ranking to test. The model's 94th input
  `PROTEIN_BEST` has perm drop 20%, larger than any PIN feature. Queued: the 89-feature family set cut to top 2
  per family (43 features) and top 1 (32), 3 seeds each.
- UW8: **why columns matter (Brendan)**: the cost of a feature is mostly bytes - written by PerFileScoring, read by
  FirstPassFDR and again by PerFileRescoring (the perf session found PerFileRescoring can only get faster by
  saving less in the scoring parquet). FirstPassFDR read so far: full 142 GB / 858 s, 93-set 129 / 580, 89-set
  124 / 630, 59-set 93 / 484, core 21 45 / 442 (20 files, warm; wall times rough). ~45 GB is core + non-PIN
  columns, a floor only Phase 5 lowers. The end set is to be timed end to end at 82 files, cold, per stage
  (PerFileScoring write, FirstPassFDR, PerFileRescoring) against the full set. The saving multiplies: FirstPassFDR
  reads the parquets ~1.7x (full-set arm: 74.8 GB after the training load, 125.1 GB after the score pass, of
  ~73 GB on disk; `p0-full-s11/run.log`), PerFileRescoring reads them again, PerFileScoring wrote them: each
  column saved is ~3-4x its bytes in I/O per run.
- UW8 (09:15) **Backward step 2 -> family set of 77 features at the full set's level.** 3 seeds each:

  | set | features | kept at FDP 1% (seeds) | mean | FirstPassFDR read |
  |---|---|---|---|---|
  | 89 (no wide) | 89 | 86,490 / 86,415 / 85,672 | 86,192 | 124 GB |
  | **no wide, no per-fragment rank** | **77** | **86,562 / 85,991 / 86,569** | **86,374** | **116 GB** |
  | no wide, no shadow | 87 | 86,095 / 85,701 / 85,390 | 85,729 | 121 GB |
  | no wide, rank or shadow | 75 | 85,800 / 85,217 / 85,502 | 85,506 | 112 GB |

  **UW8 family set: core 21 + library agreement, peak profile, `tc_*`, spectrum match, context, runner-up,
  spectrum-across-peak, reference corr, M+1/narrow-tolerance, shadow** (10 of 16 families). Dropped: wide,
  per-fragment rank, median-polish top-k, dominance, top-3, clean/clip. Within-family arms regenerated on it:
  top 2 per family (41 features), top 1 (31), 3 seeds each (09:16, ~50 min).
- UW8 (09:56) **Cutting every family at once costs too much**: top 2 per family (41) 83,383 / 83,489 / 83,716,
  mean 83,529 (**-2,845, -3.3%** vs the 77 set), read 75.5 GB (-35%); top 1 (31) 82,136 / 81,812 / 81,795, mean
  81,914 (-4,460), 59 GB. The read saving is large, so the next step finds WHICH family's cut costs: one big
  family at a time cut to its top 2, the other nine whole, 2 seeds each - peak profile (18 cols; also a top-5
  variant, its `window_share_rank1-5` all carried weight), `tc_*` (9), ref corr (6), spectrum match (5),
  M+1/narrow-tolerance (5). 12 arms, 09:56 to ~11:40. The five 2-3-column families stay whole (little to save).
- UW8 (11:34) **Per-family cuts** (one family cut, nine whole; 2-seed mean vs the 77 set at the same seeds,
  86,562 / 85,991 = 86,277):

  | family cut | features | seeds | mean | change | read saved |
  |---|---|---|---|---|---|
  | ref corr -> top 2 | 73 | 86,290 / 86,561 | 86,426 | +149 (free) | 3 GB |
  | spectrum match -> top 2 | 74 | 85,941 / 86,450 | 86,196 | -81 (free) | 5 GB |
  | peak profile -> top 5 | 64 | 85,737 / 85,999 | 85,868 | -409 | 13 GB |
  | peak profile -> top 2 | 61 | 85,350 / 85,816 | 85,583 | -694 | 18 GB |
  | M+1/narrow-tol -> top 2 | 74 | 85,478 / 85,708 | 85,593 | -684 | ~0.5 GB |
  | `tc_*` -> top 2 | 70 | 85,346 / 85,094 | 85,220 | -1,057 | 12 GB |

  - The costs add: peak profile + `tc_*` + M+1 = ~2,435 of the all-at-once top-2's 2,845.
  - Ref corr and spectrum match cut free; `tc_*` and M+1 stay whole (M+1 saves no bytes; `tc_*` costs the most).
  - Peak profile is the trade-off. Candidates queued (11:35, 3 seeds each, ~1.3 h): **A 70** (ref corr + spectrum
    match at top 2), **B 57** (A + peak profile top 5), **C 54** (A + peak profile top 2). B and C sit in
    Brendan's 42-63 target.
- UW8 (12:43) **Candidates** (3 seeds; full set 86,359 +- 472):

  | candidate | features | seeds | mean | vs full | FirstPassFDR read | parquet/file after Phase 4 |
  |---|---|---|---|---|---|---|
  | A | 70 | 85,629 / 86,307 / 86,276 | 86,071 | -0.3% | 108 GB (-24%) | ~3.0 GB |
  | **B** | **57** | 85,661 / 85,758 / 86,142 | **85,854** | **-0.6%** | **95 GB (-33%)** | **~2.7 GB** |
  | C | 54 | 85,483 / 85,157 / 85,634 | 85,425 | -1.1% | 90 GB (-37%) | ~2.7 GB |

  **B is the leading candidate** (z ~ -1.5, inside 2 SD): core 21 + lib agreement 3, `tc_*` 9, context 3,
  runner-up 3, spectrum-across 2, M+1/narrow-tol 5, shadow 2, ref corr top 2 (`apex_log_intensity_excl_top`,
  `ref_corr_rank2`), spectrum match top 2 (`spec_match_prob_max`, `spec_proj_cosine_xt_max`), peak profile top 5
  (`window_share_rank1-5`). Mask: column 5 of `candB-57-*` in `arms.tsv`.
  - **Caveat for disk and write time:** under a mask, PerFileScoring records every column of any family that
    keeps a feature (`PinFeatureMask.cs:37`, families computed as units), so B's within-family cuts save
    FirstPassFDR READ today but not disk or PerFileScoring WRITE. Run today, B writes the 77 set's parquet (~3.0
    GB/file vs 3.65); with Phase 4 recording only the kept columns, ~2.7 GB (PIN 1.38 GB of 2.30 + non-PIN 1.36).
  - Last 82-file full pipeline on UW8 (f90d19aaa6, all 109 recorded): 7.45 h = PerFileScoring 4.2 h,
    FirstPassFDR 1.2 h, PerFileRescoring 1.9 h, SecondPassFDR 6 min. The 82-file timing run of the end set
    blocks all other arms, so it goes overnight, after the set is final.
- UW8 (12:46) core pruning queued on B: B minus the 6 core features with permutation drop <= 0
  (`median_polish_min_fragment_r2` (0.2% nonzero), `ms1_precursor_coelution`, `median_polish_residual_ratio`,
  `consecutive_ions`, `peak_sharpness`, `median_polish_residual_correlation`) = 51, 3 seeds; B seeds 4-5.
- UW8 (13:22) **Core pruning is free -> UW8 end set: 51 features, 86,077 (3 seeds), -0.3% vs all 109.**
  B over 5 seeds: 85,661 / 85,758 / 86,142 / 85,996 / 85,950, mean 85,901 (SD 186). B minus the 6 core:
  85,551 / 86,183 / 86,498, mean 86,077 (+223 vs B at the same seeds). FirstPassFDR read 94.7 vs 94.8 GB: the 6
  dropped core columns barely change the read (small, or core columns read whatever the mask - unchecked).
  **The 51** (also `ai/.tmp/sessions/20261110-uw8featset/set51.txt`; mask `mask51.txt`):
  fragment_coelution_sum fragment_coelution_max n_coeluting_fragments peak_apex peak_area xcorr
  explained_intensity mass_accuracy_deviation_mean abs_mass_accuracy_deviation_mean rt_deviation abs_rt_deviation
  ms1_isotope_cosine median_polish_cosine sg_weighted_xcorr sg_weighted_cosine (15 core) | peak_coelution_margin
  peak_rank_margin peak_candidate_count | context_peptide_length context_precursor_charge context_precursor_mz |
  peak_spectrum_cosine_mean peak_spectrum_cosine_sd | ref_corr_rank2 apex_log_intensity_excl_top |
  window_share_rank1-5 | tc_sum6 tc_corr_rank1-6 tc_res_sum tc_res_mean | heavy_sum6 heavy_n_good tight45_sum6
  tight20_sum6 tc_best_sum6 | shadow_corr_sum6 shadow_frac6 | lib_cosine_coel lib_entropy_sim lib_coel_share |
  spec_match_prob_max spec_proj_cosine_xt_max. Families computed: 10 of 16.
- UW8 (13:25) **82-file confirmation and timing run started** (`fullrun.ps1`, ~7.5 h): the 51 mask, no
  record-all (scoring computes the 10 families only), otherwise the baseline's exact environment, seed 1,
  FDRBench both passes. Out: `runs-uw8\seaad-82files-libdecoy-r1.0-transferset51-c3bdbea78d`. Compare per stage
  with the f90d19aaa6 baseline (all 109: PerFileScoring 4.2 h, FirstPassFDR 1.2 h, PerFileRescoring 1.9 h,
  pass 1 96,710 at FDP 1%, pass 2 96,654). Build differs (c3bdbea78d adds the protein-best fixes, FirstPassFDR
  only), so FirstPassFDR wall and detections need an all-109 c3bdbea78d reference too: an 82-file FDR-only run
  linked from the baseline, queued after this one.
- UW8 (20:09) **82-file 51-set run done, exit 0, 6.77 h** (`runs-uw8\seaad-82files-libdecoy-r1.0-transferset51-c3bdbea78d`).
  Detections: pass 1 **95,264** at true FDP 1% (q 1%: 95,786 at FDP 1.05%), pass 2 95,223 - vs the f90d19aaa6
  all-109 baseline 96,710 / 96,654: **-1.5%**, more than the 20-file -0.3%. Confounded by build: c3bdbea78d's
  protein-best round-1 run bound (10 runs) bites at 82 files, not 20. The all-109 FirstPassFDR on c3bdbea78d
  (`featset\ref82-all109-c3bdbea78d`, running since 20:10) separates mask from build.
  Per stage (read = difference of the run.log's cumulative `[PATH] ... block reads ... so far` lines):

  | stage | baseline 109 (f90d19aaa6) | 51 set (c3bdbea78d) | change |
  |---|---|---|---|
  | scores parquet, 82 files | 317 GB | 274 GB | -14% (only whole dropped families leave the file) |
  | PerFileScoring wall | 15,092 s | 14,157 s | -6% |
  | FirstPassFDR parquet read | 612 GB | 271 GB | **-56%** |
  | FirstPassFDR wall | 4,442 s | 2,938 s | **-34%** (build differs) |
  | PerFileRescoring parquet read | 644 GB | 594 GB | -8% |
  | PerFileRescoring wall | 6,953 s | 6,913 s | **-0.6%** |
  | SecondPassFDR | 348 s | 352 s | |
  | total | 26,835 s (7.45 h) | 24,360 s (6.77 h) | -9% |

  - **PerFileRescoring did not get faster, and the feature set cannot make it.** It reads ~2.2x the parquet,
    mostly the NON-PIN columns (`cwt_candidates` 442 MB/file, fragment arrays 386 MB, reference XICs 267 MB), so
    pruning features moved its read by only 8%. This matches the perf session's finding that rescoring speeds up
    only by saving less in the scoring parquet: the bytes to cut are the non-PIN columns (Phase 5), not features.
  - FirstPassFDR is where the feature set pays: -56% of its read. Phase 4 (record only kept columns) would also
    cut the parquet to ~2.7 GB/file (~225 GB at 82) and the scoring write.
- UW8 (21:10) **The build is not the cause: the 51 set itself costs -1.4% at 82 files.** All 109, c3bdbea78d,
  FirstPassFDR only on the baseline's links, seed 1 (`featset\ref82-all109-c3bdbea78d`): pass 1 **96,593** at FDP
  1% (q 1% 96,577, FDP 0.99%) - the same as f90d19aaa6's 96,710 - vs the 51 set's 95,264 (-1,329). FirstPassFDR:
  436 GB parquet read / 3,581 s (all 109) vs 271 GB / 2,938 s (51): -38% read, -18% wall on the same build.
  - At 20 files the 51 set cost -0.3%. The cost of pruning GROWS with file count - presumably 4x the training
    rows let the classifier use features that are redundant at 20. One seed each; -1.4% is ~2.5 SD on the
    20-file noise scale. **The 20-file screen is not enough to pick the default; the cut point must be read at
    82 files.**
  - Queued (21:10, ~4 h, `go82.ps1` -> `results82.tsv`): the candidate ladder at 82 files, FirstPassFDR only on the
    baseline's links, seed 1: 51 (paired with the reference on the same scoring), 57 (B), 70 (A), 77 (family set).
- UW8 (2026-11-12 00:41) **82-file ladder, seed 1** (FirstPassFDR only, c3bdbea78d, all-109 links; all 109 =
  96,593; `results82.tsv`):

  | set | features | kept at FDP 1% | vs all 109 | q 1% (FDP) | FirstPassFDR read | FirstPassFDR |
  |---|---|---|---|---|---|---|
  | 51 | 51 | 95,264 | **-1.4%** | 95,786 (1.05%) | 340 GB | 3,089 s |
  | **B** | **57** | **96,055** | **-0.6%** | 96,132 (1.00%) | **340 GB** | 3,025 s |
  | A | 70 | 96,408 | -0.2% | 96,208 (0.97%) | 385 GB | 3,231 s |
  | 77 | 77 | 96,111 | -0.5% | 96,481 (1.05%) | 412 GB | 3,255 s |
  | all 109 | 109 | 96,593 | | 96,577 (0.99%) | 436 GB | 3,581 s |

  - The 51 arm reproduces the full-pipeline 51 run's 95,264 exactly: same scoring, same seed, so the pairing holds.
  - **B holds at 82 files (-0.6%)**, inside single-seed noise of A and 77 (77 < 70 puts that noise at ~+-300-400).
  - **The 6 weak core features matter at 82 files**: dropping them costs ~800 here (free at 20) - and buys no
    read (both 340 GB; the core columns are small). So core cuts look like a poor trade at cohort scale.
  - Running: UW25's 42 and 46 sets (seed 1), then seeds 2-3 of all 109 and of B, and 51 seed 2 (~7 h, by ~08:00).
- UW8 (2026-11-12 07:15) **82-file seeds - CORRECTION to "B inside noise" above: B's loss is small but real.**
  Kept at true FDP 1%, FirstPassFDR only on the all-109 links:

  | set | seed 1 | seed 2 | seed 3 | mean | paired vs all 109 |
  |---|---|---|---|---|---|
  | all 109 | 96,593 | 96,779 | 96,806 | 96,726 (SD 116) | |
  | **B (57)** | 96,055 | 95,745 | 96,241 | 96,014 (SD 251) | **-712 +- 160 (-0.74%, z ~ -4.4)** |
  | 51 | 95,264 | 95,256 | | 95,260 | -1,426 (-1.47%) |
  | UW25 46 / 42 | 95,203 / 95,359 | | | | -1,390 / -1,234 (seed 1) |

  Seed noise at 82 files is SD ~116 (all 109), not +-300-400: the 77 < 70 inversion was a real set effect.
  **Seed-paired DIA-NN agreement** (no-MBR first pass, run + global q <= 1%; `agreement82-s2/s3/noise.txt`):

  | comparison | lost (DIA-NN %) | gained (DIA-NN %) | net confirmed |
  |---|---|---|---|
  | all 109 s2 vs s1 (noise) | 2,576 (50.9%) | 2,758 (49.0%) | +41 |
  | all 109 s3 vs s1 (noise) | 2,550 (51.7%) | 2,760 (47.6%) | -5 |
  | B vs all 109, s1 / s2 / s3 | 3,009 / 2,983 / 2,895 (50.6-51.1%) | 2,474 / 1,950 / 2,330 (45-49%) | -319 / -638 / -401 |
  | 51 vs all 109, s2 | 3,317 (50.6%) | 1,797 (48.8%) | -803 |
  | UW25 46 vs all 109, s1 | 3,628 (53.1%) | 2,238 (46.2%) | -893 |

  - **B loses the same KIND of precursors that seed churn swaps** (~51% DIA-NN-confirmed, at the boundary), just
    more than it gains back: net **-453 DIA-NN-confirmed (-0.51%)** over 3 seeds, -0.74% of all detections, for a
    22% smaller FirstPassFDR read. The core cuts cost ~2x that in confirmed precursors. Accepting B's cost is
    Brendan's call.
  - All arms staged for UW25 at `M:\...\sea-ad\featset82-uw8\` (13 arms incl. all 109 seeds 1-3, B seeds 1-3).

**JOB FOR UW25 (written by UW8 2026-11-12 ~08:00, for Brendan to start): where is the NEGLIGIBLE-loss set at 82
files?** Brendan's question: if we want no measurable difference from all 109, which set - did the 20-file screen
step past the point of expelling only valueless features? At 82 files only A (70) is near zero (-185, seed 1),
the 77 set scored BELOW its own subset A (-482, seed 1, ~2 SE apart), and the 93 set (dropping only the four
zero-value families) was never run at 82 files. UW8's machine is busy ~5 h with pass 2 of B.
- **Arms** (12; FirstPassFDR only; 82 files; UW25's three all-109 legs `runs-uw25\seaad-{20,21,41}files-...-score*`
  as `-LinkFrom` in one `;`-separated string; `OSPREY_RECORD_ALL_FEATURES=1`; protein-best ON; `-FdrBenchPass 1`;
  `-NoModelDiagnostics`; the version pin of UW25's legs; otherwise the #4950 environment as in UW25's runs):

  | order | arm | `OSPREY_FEATURE_MASK` | `OSPREY_FDR_SEED` |
  |---|---|---|---|
  | 1-4 | all109-s1, set93-s1, setA70-s1, set77-s1 | none / mask-set93 / mask-setA70 / mask-set77 | 1 |
  | 5-8 | the same four | same | 2 |
  | 9-12 | the same four | same | 3 |

  Masks (comma-separated, as the env var takes them) and kept-feature lists:
  `M:\home\brendanx\data\MacCoss\Osprey\sea-ad\featset82-uw8\masks\` - `mask-set93.txt` (16 masked: median-polish
  top-k, dominance, top-3, clean/clip), `mask-set77.txt` (32: + wide, per-fragment rank), `mask-setA70.txt` (39: +
  ref corr and spectrum match beyond their top 2), `mask-setB57.txt` (52, for reference); `keep-*.txt` list what
  each keeps. A70 and 77 are byte-identical to UW8's `x82-A-70-s1` / `x82-77-s1` masks.
- **Order matters**: each completed block of four is a full paired comparison, so a partial run still answers.
  ~1 h per arm on UW8's HDD (FirstPassFDR 3,000-3,600 s at 82 files) -> ~12 h.
- **Report** per arm: kept at true FDP 1%, q 1% kept and FDP, FirstPassFDR s and GB read; paired vs all 109 at the
  same seed; and seed-paired DIA-NN agreement (UW25's driver row / `paired_agreement.py`, no-MBR first pass).
- **Reading it**: a set is "negligible" if its paired loss is inside all 109's own seed spread at 82 files (UW8:
  SD 116; DIA-NN-confirmed net change between seeds +41 / -5). UW8 adds its own seeds of 93 / A / 77 after pass 2,
  so both machines' answers sit side by side.
- UW8 (13:04) **Pass 2 of B tracks pass 1** (82 files, seed 1, FirstPassFDR -> SecondPassFDR on the all-109
  links, `featset\p2-B57-s1` / `p2-all109-s1`, `pass2-B57.txt`): all 109 pass 2 **96,556** at true FDP 1% (q 1%
  96,516, FDP 0.99%), B **96,034 (-522, -0.54%)** (q 1% 96,054, FDP 1.00%). DIA-NN-confirmed (strict, no-MBR):
  88,016 vs 87,708 (-308); B lost 3,006 (50.5% confirmed) / gained 2,487 (48.7%) - the pass-1 profile. Wall:
  B 2:56 vs all 109 3:04 (FirstPassFDR 3,109 vs 3,562 s; PerFileRescoring 7,073 vs 7,123 s - record-all, so
  rescoring computed every family in both; the 51-set full run is the rescoring-time measurement).
- UW8 (13:05) running its own replicate of the negligible-loss job: 93 seeds 1-3, A and 77 seeds 2-3 (7 arms,
  ~7 h, `results82.tsv`), to sit beside UW25's.
- UW8 (13:30) **Like-for-like DIA-NN baseline at 82 files: no experiment-wide FDR issue in Osprey.** (Prompted by
  Brendan reading the 88,016 "both" count as DIA-NN's total - it is the OVERLAP; DIA-NN's total is ~100k.)
  `split_calibration.py --diann` on UW8's two DIA-NN 2.7.0 reports, same split oracle (`diann-vs-osprey-82.txt`):

  | 82 files | q 1% kept (measured FDP) | at true FDP 1% |
  |---|---|---|
  | Osprey all 109, pass 1 / pass 2 | 96,577 (0.99%) / 96,516 (0.99%) | 96,593 / 96,556 |
  | DIA-NN first pass (no MBR) | 100,037 (1.00%) | 100,213 (+3.7%) |
  | DIA-NN final (MBR) | 99,575 (0.78%) | 101,269 (+4.9%) |

  - Both tools calibrated at q 1% (Osprey 0.99%, DIA-NN first pass 1.00%); DIA-NN's final report is conservative,
    so its lead grows at matched true FDP. The ~4-5% gap Brendan expects.
  - **Same oracle:** DIA-NN's library (`lib\diann-split-sized`, predicted from the split's peptide list) has
    1,391,588 targets, 695,616 on-target and 695,616 own entrapment: r = 0.4999, as Osprey's Carafe library
    (1,131,671 / 565,555 = 0.4998), so the tool's default r is right for both (`diann_assign_counts.py`).
  - **Effectively the same search space:** DIA-NN searches 23% more target peptides (Carafe dropped 19% of the
    split's targets), but 100,018 of DIA-NN's 100,037 real-target IDs at global q 1% (all but 19) are peptides
    Osprey's library holds (`diann_space.py`). The missing Carafe targets are peptides neither tool finds.
- **UW25: started 2026-11-12 ~10:15** (Brendan's go-ahead), the 12 arms in the order above (`p9-82-<set>-s<seed>`),
  UW8's mask files used unchanged (verified identical to UW25's set93 / set77 / A lists). ~1 h per arm on UW25 ->
  ~22:00. UW25 already has all 109 at seeds 4-6 at 82 files (`p8-82-all109-s4..6`), so 93 / A / 77 at seeds 4-6
  can follow without new all-109 arms if the first three seeds leave the answer close.
- **UW25 negligible-loss job, block 1 (seed 1) done 14:10** (82 files, UW25 links; kept at true FDP 1%; DIA-NN
  confirmed = strict, no-MBR first pass):

  | set | kept | vs all 109 | DIA-NN-confirmed | vs all 109 | FirstPassFDR read | FirstPassFDR |
  |---|---|---|---|---|---|---|
  | all 109 | 96,593 | | 88,025 | | 504 GB | 3,497 s |
  | 93 | 95,782 | **-811** | 87,466 | -559 | 459 GB | 3,531 s |
  | A-70 | 96,408 | -185 | 87,868 | -157 | 385 GB | 3,252 s |
  | 77 | 96,111 | -482 | 87,730 | -295 | 412 GB | 3,271 s |

  - **UW25 reproduces UW8 exactly at seed 1** (all 109 96,593, A 96,408, 77 96,111 = UW8's `ref82` / `x82-A-70-s1` /
    `x82-77-s1`): results are bit-identical across the two machines, so seeds pool freely.
  - **93 is worst (-811) although it is a superset of A and 77** - a subset beating its superset by ~600 says
    single-seed differences at 82 files exceed UW8's SD 116, or the result depends on the feature combination as
    much as on what is dropped. Seeds 2-3 decide. Block 2 started 14:10 (~18:00), block 3 ~22:00.
- **UW8 to UW25 (2026-11-12 15:00): seeds pool, so split the seeds, don't repeat them.** Brendan wants 5 seeds per
  set before choosing (leads have vanished after 3). Already in hand, pooled (UW8 + UW25, bit-identical):
  all 109 seeds 1-6; B seeds 1-6; A / 77 / 93 seed 1. UW25's blocks 2-3 give A / 77 / 93 seeds 2-3. UW8 stopped
  its own replicate after the running `x82-93-s2` (identical to UW25's) to free its disk for the overnight
  performance A/B (all 109 on #4950's tip, then the new default on the PR branch). **Request: after block 3,
  run A-70, 77 and 93 at seeds 4 and 5** (6 arms, ~6 h; all 109 seeds 4-5 already exist from UW25's B study),
  which completes 5 seeds for every set. Pooled table to extend:

  | seed | all 109 | 93 | 77 | A-70 | B-57 |
  |---|---|---|---|---|---|
  | 1 | 96,593 | 95,782 | 96,111 | 96,408 | 96,055 |
  | 2 | 96,779 | 96,743 (UW8 15:05; -36) | (UW25 b2) | (UW25 b2) | 95,745 |
  | 3 | 96,806 | (UW25 b3) | (UW25 b3) | (UW25 b3) | 96,241 |
  | 4 | 96,911 | (request) | (request) | (request) | 95,853 |
  | 5 | 96,193 | (request) | (request) | (request) | 96,250 |
  | 6 | 97,289 | | | | 96,213 |

  UW8 picks the PR's default from seeds 1-3 at ~22:30 to start the new-default performance run in time; if seeds
  4-5 change the verdict, the PR's one-line set array changes and the perf run still measures the I/O scale.
- UW8 (16:00) **Phase 4 PR branch, local, not pushed: `Skyline/work/20261112_osprey_default_feature_set`**
  (`C:\proj\pwiz-featdefault`, on #4950 tip be63cfbfb7; MACS2's `cwt_recompute` to be merged in when pushed):
  caa831882e "Added --feature-set core|default|all and changed scoring to record only the set's feature columns",
  d9589624f0 docs. `--feature-set core|default|all`; absent -> HRAM `default`, unit `core`; `OSPREY_FEATURE_MASK`
  still overrides, `OSPREY_RECORD_ALL_FEATURES=1` still records 109; scoring computes families whole but WRITES
  only core + the set's columns; the default list is the one array `PinFeatureMask.DEFAULT_FEATURES` (currently B-57,
  verified identical to UW8's `keep-setB57.txt`, 10 families). Debug gate 692/692, inspection 0/0; Release built,
  snapshot `_bin\uw8-featdefault-d9589624f0`. Implementer's notes `ai/.tmp/agent-featdefault-status.md`.
  - Independent review (diff be63cfbfb7..HEAD, correctness only; `ai/.tmp/agent-featreview-status.md`): no serious
    defects. Verified: writer, reconciled stream-merge and row reader share `IsRecorded`; FDR loader reads a subset
    of recorded columns; a missing column throws (`RequireFeatureColumn`), never zeros; non-classifier readers use
    core only; `core` keys byte-identical to the old default; different sets never share a key; rescoring and
    SecondPassFDR consistent. One latent low: unit-resolution `featset=all` key has no feature count (matches the
    existing unit `featmask=none` convention; matters only when features are added).
  - **Goldens to recapture (not done; needs regression runs off the timed disk):** Astral (`osprey-regression.data/
    astral/`, modes 3/4 with it) and the TeamCity Astral legs; Stellar legs must not move.
  - Open for Brendan: cache-key terms list feature names (~550 chars) - keep readable or hash?
- **UW25 (15:05): agreed and queued.** 93 / A-70 / 77 at seeds 4-5 (6 arms) start automatically when block 3 ends
  (~22:00), done ~04:00. UW25 posts block 2 (~18:00), block 3 (~22:00) and seeds 4-5 here, each with the pooled
  table (`featset/pooled82.py`: UW25 rows + UW8's seeds, paired vs all 109 at the same seed, DIA-NN-confirmed diff).
- **UW25 block 2 (seed 2) done 18:01.** all 109 96,779 / 88,066 confirmed (= UW8's seed 2, bit-identical again);
  93 96,743 (-36); A-70 96,377 (-402); 77 95,701 (-1,078). 93's seed-1 deficit (-811) mostly vanishes. Pooled so far:

  | set | seeds | kept, paired diff vs all 109 (mean +- SD) | DIA-NN-confirmed diff | per-seed kept diffs |
  |---|---|---|---|---|
  | set93 | 2 | -424 +- 548 | -286 +- 386 | -811 / -36 |
  | set77 | 2 | -780 +- 421 | -458 +- 230 | -482 / -1078 |
  | setA70 | 2 | -294 +- 153 | -222 +- 91 | -185 / -402 |
  | B57 | 6 | -702 +- 447 | -416 +- 254 | -538 / -1034 / -565 / -1058 / +57 / -1076 |

  Block 3 (seed 3) running, ~22:00.
- **UW25 block 3 (seed 3) done 21:57.** all 109 96,806 / 88,020 (= UW8's seed 3); 93 96,585 (-221); A-70 96,444
  (-362); 77 96,513 (-293). Pooled, 3 seeds each (B 6):

  | set | seeds | kept, paired diff vs all 109 (mean +- SD) | DIA-NN-confirmed diff | per-seed kept diffs |
  |---|---|---|---|---|
  | set93 | 3 | -356 +- 405 | -246 +- 282 | -811 / -36 / -221 |
  | set77 | 3 | -618 +- 410 | -349 +- 248 | -482 / -1078 / -293 |
  | setA70 | 3 | -316 +- 115 | -188 +- 86 | -185 / -402 / -362 |
  | B57 | 6 | -702 +- 447 | -416 +- 254 | -538 / -1034 / -565 / -1058 / +57 / -1076 |

  - **Every set is below all 109 at every seed, the 93 set included** (it drops only the four families the
    screens valued at zero): no subset is free at 82 files on this evidence. A-70 is the steadiest: -316 +- 115
    (SE ~66, -0.33%), DIA-NN-confirmed -188 (-0.21%). 93 and 77 are noisier and no better than A-70.
  - Seeds 4-5 of 93 / A-70 / 77 start now (~04:00); all 109 seeds 4-5 already exist (UW25 B study).
- **UW25 seeds 4-5 done 2026-11-13 03:44 PT (12:44 CET) - FIVE SEEDS PER SET, and the 3-seed conclusion did NOT
  hold.** Pooled (UW25 + UW8, bit-identical), paired vs all 109 at the same seed (all 109 s4-5 = UW25 `p8-82-*`):

  | set | seeds | kept, paired diff vs all 109 (mean +- SD) | DIA-NN-confirmed diff | per-seed kept diffs |
  |---|---|---|---|---|
  | set93 | 5 | -161 +- 458 | -87 +- 319 | -811 / -36 / -221 / -207 / +468 |
  | set77 | 5 | -431 +- 435 | -219 +- 267 | -482 / -1078 / -293 / -435 / +132 |
  | setA70 | 5 | -173 +- 274 | -85 +- 185 | -185 / -402 / -362 / -203 / +287 |
  | B57 | 6 | -702 +- 447 | -416 +- 254 | -538 / -1034 / -565 / -1058 / +57 / -1076 |

  - Seed 5 reversed the sign for every set (all 109's seed 5 was its weakest, 96,193). At 5 seeds **93 (-161,
    z ~ -0.8) and A-70 (-173, z ~ -1.4) are inside noise; A-70 costs ~0.10% DIA-NN-confirmed (-85 +- 185)**; 77
    (-431, z ~ -2.2) is borderline; B (-702, z ~ -3.8) is a real small loss.
  - Lost/gained summed over the 5 seed pairs (strict DIA-NN, `featset/agreement82-sets-5seeds.txt`): 93 lost 11,267
    (49.0% confirmed) / gained 10,464 (48.5%); A-70 lost 12,520 (48.4%) / gained 11,669 (48.2%); 77 lost 12,749
    (49.3%) / gained 10,599 (49.0%). A-70 and 93 exchange borderline precursors one for one, no tilt; B tilts
    slightly (lost ~50% vs gained ~47%).
  - **Reading for the PR: A-70 is the largest cut shown negligible at 82 files** (39 features fewer than all 109,
    FirstPassFDR read 385 vs 504 GB, -24%); B-57 buys ~33% less read for a real ~0.7% (~0.47% confirmed) loss.
  - ~~Caveat: these overnight arms shared D: with SkylineNightly~~ **Retracted (2026-11-13, UW8 was right):** no
    nightly has run on UW25 since ~2026-10-19 (no scheduled task; `D:\Nightly` unchanged since 2026-10-18/19). The
    caveat came from a stale UW25 memory note, cited without checking. The overnight FirstPassFDR times are in line
    with the daytime arms (e.g. 77 s5 3,335 s vs 3,250-3,530 s) and are usable for timing.
- **UW8 (22:10) decision for the PR's default: A-70** (pending seeds 4-5). A loses least and is steadiest
  (-316 +- 115, SE ~66, -0.33%; DIA-NN-confirmed -188, -0.21%); 93 and 77 store more and are no better; B-57 loses
  ~2x A (-702, -0.73%). The trade A vs B: +~390 precursors (+~230 DIA-NN-confirmed) for +266 MB/file of feature
  columns (1,648 vs 1,382 MB on the pre-#5025 parquet; +19%; ~+0.5 TB at 2,000 runs; FirstPassFDR reads it ~1.7x).
  A = B + the remaining 13 peak-profile features (`peak_width`, `shape_bin1-5`, `local_corr_top3_mean`,
  `lib_rel_rank2-6`, `window_share_rank6`). PR branch commit **bbca19fae0** "Changed the default feature set to the
  70-feature set A" (+ docs count fix: 10 of 16 families). If seeds 4-5 overturn it, B is a one-commit revert.
  Chained (`chain-a70.sh`): after the all-109 baseline ends (~22:40) -> Debug gate -> Release snapshot ->
  82-file performance leg with the build's own default (A-70), ~7 h, to ~06:00.
- **Brendan (22:20): four named, tested, user-selectable sets: `all` 109, `default` 70 (A), `narrow` 57 (B),
  `core` 21** - nested core ⊂ narrow ⊂ default ⊂ all. `narrow` being added to the PR branch now (the chain was
  paused for it and restarts after the narrow commit and gate).
- **JOB FOR UW25 (22:25): core-21 at 82 files on the current build line**, because core no longer performs as badly
  as it did when this study started (other fixes landed besides the feature set; at 20 files core was 67,874 vs
  86,359, -21%, on 2026-11-10). Same arm recipe as the negligible-loss job (UW25's all-109 links, record-all,
  protein-best on, `-FdrBenchPass 1`), `OSPREY_FEATURE_MASK` = `masks\mask-core21.txt` (the 88 family features;
  `keep-core21.txt` lists the 21), seeds 1-3, after the seeds 4-5 job. Paired vs all 109 seeds 1-3 (in hand), with
  DIA-NN agreement. Gives the user-facing cost of `--feature-set core` at cohort scale, and the unit-resolution
  default's HRAM-equivalent reference point.
- **Brendan (22:35): FIVE named sets and a performance curve.** `core` 21 ⊂ `narrow` 41 ⊂ `efficient` 57 (B) ⊂
  `default` 70 (A) ⊂ `all` 109, each tested and user-selectable; plot expected detections against stored bytes
  with the named sets marked. `narrow` = the 21 core + the top 2 of each of efficient's ten families (the only
  40-something set that keeps the nesting: UW25's 42 / 46 cut the core); identical to UW8's 20-file `w-top2`
  arm (-3.3% at 20 files). Masks `masks\mask-narrow41.txt` / `keep-narrow41.txt`.
  - **SUPERSEDED (Brendan, 22:30): `narrow` = UW25's 42**, the best-performing 40-something, with an asterisk: it
    is efficient-57 with the core cut to 6 (`abs_rt_deviation`, `fragment_coelution_max`, `median_polish_cosine`,
    `peak_area`, `ms1_isotope_cosine`, `mass_accuracy_deviation_mean`), so narrow ⊂ efficient ⊂ default ⊂ all but
    core ⊄ narrow (*core columns are still recorded; narrow only hides 15 of them from the classifier). Masks
    `masks\mask-narrow42.txt` / `keep-narrow42.txt` (identical to UW8's measured `x82-uw25-42-s1`: 95,359, -1,234,
    seed 1). **UW25's job: narrow-42 at 82 files, seeds 2-3, plus core-21 seeds 1-3** (5 arms), so every named
    set has an 82-file paired number for the curve. Five sets: core 21, narrow* 42, efficient 57, default 70,
    all 109; the PR branch is being updated to them.
  - **SUPERSEDED again (Brendan, 22:45): `narrow` dropped - FOUR sets: core 21 ⊂ efficient 57 ⊂ default 70 ⊂ all
    109.** Narrow as defined saves nothing: core columns are always recorded, and the core cut saves no FDR read
    (51 set = 340 GB, same as efficient), while costing ~2x efficient's detections (-1.3% vs -0.7%). Only 3 core
    features have non-classifier readers (`median_polish_cosine` PIN 15 and `explained_intensity` PIN 8 in
    `TrainingEvidence.cs:100-103,236-238`, training diagnostics; `fragment_coelution_sum` PIN 0 as the dedup
    fallback in `PercolatorSampling.cs:278`), so a narrow that also stopped WRITING the other 15 core columns
    would save ~0.35 GB/file (~11%) - revisit if Phase 5 makes those bytes matter. UW25: narrow-42 seeds 2-3 are
    optional now; core-21 seeds 1-3 still wanted (the unit-resolution default's cohort-scale reference).
- UW8 (22:23) **Performance A/B, leg 1 done: all 109 on #4950's tip** (be63cfbfb7, 82 files, fresh scoring,
  protein-best on, `--memstamp`, `perf82.ps1`; `runs-uw8\seaad-82files-libdecoy-r1.0-transferall109-be63cfbfb7`):
  total **26,254 s (7.29 h)** = PerFileScoring 15,000 s, FirstPassFDR 4,640 s, PerFileRescoring 6,258 s,
  SecondPassFDR 355 s. Scores parquets **262.6 GB** (3.20 GB/file; 317 GB before #5025). Disk (sampler, bytes under
  the output dir every 120 s, `diskstamp.tsv`): rises monotonically to the high-water mark 298 GB at the end.
  Memory (`perfviz.py`): **FirstPassFDR is the high-water mark - 53.6 GB private, 37.0 GB managed**; PerFileScoring
  33.3 / 27.1 GB; PerFileRescoring 19.1 / 14.9 GB; SecondPassFDR 11.0 / 5.9 GB. Leg 2 (the default, PR build)
  starts after the five-set commit passes the gate.
- UW8 (22:41) **Baseline re-run on the post-#5030 base** (Brendan: an A/B must run on one machine; MACS2 is a
  different machine; perf numbers wanted from all 3). MACS2's #5030 ("Changed Stage 6 to recompute CWT candidates
  instead of storing them") merged into #4950 -> tip **849586af76**, which drops `cwt_candidates` from the parquet,
  so leg 1 above (be63cfbfb7) is not the PR's base any more. Started 22:41: all 109 on 849586af76 (snapshot
  `_bin\uw8-849586af76`), same recipe, ~7 h (`runs-uw8\seaad-82files-libdecoy-r1.0-transferall109-849586af76`).
  Then the PR branch (four sets, merged with 849586af76) runs its default leg on UW8, ~06:20 -> ~13:00. The
  branch is pushed for MACS2 once merged and gated.
- UW8 (23:10) **PR branch PUSHED for MACS2's timing: `Skyline/work/20261112_osprey_default_feature_set` @
  fab7e0caed** (Brendan authorized the push). Contents on #4950: caa831882e (`--feature-set`, column-level
  recording), d9589624f0 (docs), bbca19fae0 (default = A-70), 878c0a4c6b (the four nested sets: `core` 21 ⊂
  `efficient` 57 ⊂ `default` 70 ⊂ `all` 109; unit resolution 21 / 52 / 65 / 101), fab7e0caed (merged #4950 @
  849586af76, i.e. with #5030; clean merge). Debug gate on the merged tree: 685/685 tests (7 fewer: #5030 removed
  the CWT loader tests), inspection 0/0. No PR opened yet; goldens not recaptured (Astral moves).
  **For a timing A/B on one machine** (both legs on that machine, same build):
  - leg A: `--feature-set all` (or `OSPREY_FEATURE_MASK=none`) = all 109, written whole;
  - leg B: no option (HRAM -> `default`, 70 columns written); also `--feature-set efficient` if time allows.
  - UW8's recipe: `ai/.tmp/sessions/20261110-uw8featset/perf82.ps1` (82 files, fresh scoring, no record-all,
    protein-best ON, seed 1, the #4950 environment, a 120-s `diskstamp.tsv` sampler); MACS2's runner will differ.
  UW8: leg A = all 109 on 849586af76 (running since 22:41, ~05:55); then leg B = the default on fab7e0caed
  (chained, ~05:55 -> ~12:30). The gate ran 22:42-23:10 during leg A's PerFileScoring (CPU contention; window in
  the night log) - read leg A's PerFileScoring time with that in mind.
- UW8 (2026-11-13 03:16 PT / 12:16 CET) **A/B RESTARTED - the first attempt's timings are invalid.** An earlier
  chain (`chain-a70.sh`, "paused" with TaskStop at ~22:25 PT) had already fired: the first baseline ended 22:23, so
  it gated and at 22:30 launched a default leg on the superseded bbca19fae0 build. TaskStop killed only its bash
  shell; the detached pwsh/Osprey ran on. From 22:41 two 82-file runs shared the HDD for 4.5 h (found at 03:14 when
  two Osprey.exe were listed). Both killed (`taskkill /T`), both output dirs deleted, console logs kept as
  `perf-*.contaminated.console.log`. Re-run as ONE sequential script (`ab82.sh`: leg A all 109 on 849586af76, then
  leg B default on fab7e0caed), exactly one Osprey.exe at start. ETA (from the clean 7.29 h baseline on
  be63cfbfb7): **leg A ~10:30 PT / 19:30 CET; leg B ~17:15 PT / 02:15 CET Sat.** The gate-contention note above no
  longer applies (it was in the discarded run).
- UW8 (2026-11-13 11:00 PT / 20:00 CET) **A/B leg A done, clean: all 109 on 849586af76** (82 files, alone on the
  HDD; `runs-uw8\seaad-82files-libdecoy-r1.0-transferall109-849586af76`): total **27,886 s (7.75 h)** = PerFileScoring
  14,286 s, FirstPassFDR 4,718 s, PerFileRescoring **8,512 s**, SecondPassFDR 370 s. Scores parquets **221.8 GB**
  (2.70 GB/file). Disk high-water mark 257 GB (end). Memory: FirstPassFDR peak 57.2 GB private / 38.0 managed;
  PerFileScoring 31.6 / 29.4; PerFileRescoring 18.0 / 13.4; SecondPassFDR 12.9 / 5.8.
  - **vs the pre-#5030 all-109 run (be63cfbfb7, 7.29 h): #5030 traded 41 GB of parquet (262.6 -> 221.8, -16%) for
    +2,254 s of PerFileRescoring (6,258 -> 8,512, +36%) on this HDD**, consistent with recomputing `cwt_candidates`
    there instead of storing them. One run each (the be63 run's PerFileScoring had a 30-min gate beside it); worth
    confirming on MACS2's A/B.
  - Leg B (default 70 on fab7e0caed) started 11:01 PT, no mask in its environment (the build's own default); 31 of 82
    files scored at 12:24; ETA ~18:15 PT / 03:15 CET Sat.
- UW8 (12:40 PT / 21:40 CET) **Queued: the #5030 A/B, PerFileRescoring alone** (Brendan: confirm the +36% before
  acting on it; MACS2 measured a speed-up, plausibly on a far smaller, higher-confidence pass-2 workload than the
  full recipe's). `-Task PerFileRescoring` at 82 files, each build linked from its OWN completed all-109 run, so
  everything upstream is that build's and the only difference is stored vs recomputed `cwt_candidates`: pre =
  be63cfbfb7 (links `transferall109-be63cfbfb7`), post = 849586af76 (links `transferall109-849586af76`).
  Alternating pre / post / pre / post, one Osprey at a time (asserted), `rescore-ab.sh` + `rescore82.ps1`, outputs
  `featset\rescore{1..4}-<build>`. Starts when leg B ends (~18:15 PT); ~2-2.5 h each -> ~04:00 PT / 13:00 CET Sat.
  - **Storage layout matters (Brendan):** MACS2 reads `.spectra.bin` from an SSD (work dir on HDD); UW8 has spectra
    AND parquets on one SATA HDD. Recomputing CWT needs spectra, so on UW8 any extra spectra reads compete with
    parquet reads for the head; on MACS2 they are nearly free. Report per run: wall, parquet GB read, non-parquet
    (spectra) GB read, read s and gate wait s (the `[PATH] ... block reads` lines). More spectra read + more wait
    post-#5030 = an HDD-contention cost (layout-dependent); flat reads + more CPU = the recompute itself.
- **JOB FOR UW25 (written 2026-11-13 ~13:00 PT / 22:00 CET, Brendan at bed time): 10 XICs vs 12 at 82 files.**
  Why: 6 -> 12 XICs costs PerFileScoring +61 s of 257 s per file (+24%, `20261108-uw8perf\ablate.console.log`) and
  is a suspected cause of lost throughput vs master (MACS2 ran master in 2-2.5 h). The evidence for 12 is thin:
  the 6/8/12/16 sweep (`TODO-20261028_osprey_diann_fdr_gap.md` ~l.250) was 3 files, 1 seed, an older build,
  natural entrapment, at FDP 0.5%: 88,604 / 92,594 / 94,741 / 93,311 (12 = +6.9% over 6, +2.3% over 8); with 41
  features + GBDT, 12 vs 6 = +5.4%. 10 and 16 were "rechecked, 12 stays best" on 11-04
  (`TODO-20261030_osprey_scoring_library-phase2.md` l.120) with NO numbers recorded. Never at 82 files, never
  under today's recipe (109 features, protein-best, tc 0.40), never multi-seed.
  1. **Score all 82 files with `OSPREY_XIC_FRAGMENTS=10`**, everything else identical to UW25's own XIC-12 legs
     (`runs-uw25\seaad-{20,21,41}files-...-score*`: same snapshot c3bdbea78d, same environment, mask none / all 109
     recorded, protein-best on). Record per-file PerFileScoring time (vs the XIC-12 legs on the same machine).
  2. **FirstPassFDR arms on it: `default` A-70 (`masks\mask-setA70.txt`) and all 109, seeds 1-3** (pass 1, true FDP
     1%, strict DIA-NN agreement). Pair seed-for-seed with the XIC-12 arms in hand (A-70 and all 109 seeds 1-5,
     bit-identical across UW8/UW25).
  - Read: if 10 holds A-70's count inside the 5-seed noise (SD of paired diffs ~274) while saving ~8-12% of
    PerFileScoring, propose 10 for HRAM and try 8 next; if 10 costs detections, 12 stands with numbers behind it.
  - UW8 meanwhile: leg B (default 70) to ~18:15 PT / 03:15 CET, then the #5030 rescoring A/B to ~04:00 PT / 13:00
    CET Sat, then the final report.
- UW8 (13:20 PT / 22:20 CET) **Draft PR #5033 opened** on #4950's branch (Brendan: it merges into #4950 before
  #4950 squash-merges to master). All three machines test its tip: `Skyline/work/20261112_osprey_default_feature_set`.
  Description lists the open items (recipe-as-default, Astral goldens, key length, latent unit `featset=all` key).
  TeamCity per-commit builds run on it; the Astral regression legs are expected to fail until the goldens are
  recaptured. Perf/Regression gate: ask Brendan first.
- UW8 (17:56 PT / 02:56 CET) **One-machine A/B DONE (82 files, alone on the HDD, recipe + protein-best on, seed 1):**

  | | all 109 (#4950 @ 849586af76) | default 70 (#5033 @ fab7e0caed) | change |
  |---|---|---|---|
  | total wall | 27,886 s (7.75 h) | 24,892 s (6.91 h) | **-10.7%** |
  | PerFileScoring | 14,286 s | 13,142 s | -8.0% |
  | FirstPassFDR | 4,718 s | 3,978 s | -15.7% |
  | PerFileRescoring | 8,512 s | 7,469 s | -12.3% |
  | SecondPassFDR | 370 s | 303 s | -18% |
  | scores parquet (82 files) | 221.8 GB | 165.2 GB | **-25.5%** |
  | disk high-water mark | 257 GB | 196 GB | **-23.7%** |
  | memory peak, FirstPassFDR private / managed | 57.2 / 38.0 GB | 42.8 / 33.1 GB | **-25%** |
  | PerFileScoring peak private | 31.6 GB | 28.8 GB | -9% |
  | pass 1 / pass 2 kept at true FDP 1% | 96,710 / 96,654 | 96,223 / 96,185 | -0.50% / -0.49% |
  | FDP at q 1% (pass 2) | 0.99% | 1.02% | |

  - The default saves at every stage; disk, parquet and FirstPassFDR memory each drop ~a quarter.
  - The -0.50% is one seed on a fresh-scoring build; it sits inside the 5-seed paired spread on shared scoring
    (A-70 -173 +- 274; seed 1 there -185), so it does not change "inside noise".
  - all 109 reproduces the earlier 82-file all-109 result exactly (96,710 / 96,654).
  - Run dirs `runs-uw8\seaad-82files-libdecoy-r1.0-transfer{all109-849586af76,default70-fab7e0caed}` (run.log,
    diskstamp.tsv). The #5030 rescoring A/B started 17:56 PT (~04:00 PT / 13:00 CET Sat).
- UW25 (13:25 PT / 22:25 CET) **XIC-10 job started** as written above. One 82-file scoring leg
  `runs-uw25\seaad-82files-libdecoy-r1.0-transferuw25x10-score0-82` on snapshot c3bdbea78d; its environment
  differs from the XIC-12 legs' only in `OSPREY_XIC_FRAGMENTS` (diffed). ETA ~18:40 PT / 03:40 CET, then FDR arms
  (`featset\arms-xic10.tsv`: A-70 / all 109 alternating, seeds 1-3, ~55 min each) to ~00:30 PT / 09:30 CET Sat.
  Driver `ai/.tmp/sessions/20261109-uw25mem/featset/xic10-night.ps1`; timeline
  `ai/.tmp/night-session-budget-20261113.md`.
  - **Build check:** the XIC-12 legs were scored 11-09 by da4eff9f63, a merge carrying the scoring-share speedups
    (shared pair correlations, median-polish reuse, per-window dedup) that c3bdbea78d lacks. Scoring file 1 at XIC
    12 with c3bdbea78d reproduces the 11-09 parquet exactly (4,403,242 rows, 128 of 128 columns equal;
    `featset\cmp_parquet.py`), so the detection pairing holds. Per-file TIMES do not compare across the builds, so
    a same-build XIC-12 control (files 1-10, c3bdbea78d, tag `uw25x12ctl`) runs alone after the leg, before the
    arms (`featset\xic10-night2.ps1`). XIC-10 files 1-3 overlapped the check and are left out of the timing.
  - **14:40 PT / 23:40 CET, 21 files in:** the cross-build first look is -39 +- 3 s per file (191 vs 230 s, -17%,
    17 files paired; `featset\xic_timing.py`); the same-build control will set the real figure. **XIC 10 finds a peak
    for 3.2% more precursors** (file 5: 4,423,955 vs 4,287,854 of 6,175,389, targets and decoys alike), so the
    parquet has more rows and is +2.4% larger (3.81 -> 3.90 GB). Per column (`featset\colsize.py`, file 5),
    `cwt_candidates` +52 MB and `reference_xic_*` -40 MB; the feature columns barely move. So 10 costs ~3% more
    rows for FirstPassFDR to read; whether those rows carry detections is the arms' question.
  - **Why more peaks at 10 (from reading the code; not yet measured):** peak detection is a CWT on each fragment
    XIC combined by a POINTWISE MEDIAN over all N fragments (`CwtPeakDetector.ConsensusMedianCwt`,
    `Osprey.Chromatography\CwtPeakDetector.cs:265`). A scan is a consensus maximum only if about half of the N
    fragments are positive there, so ranks 11-12 (weak, often all-zero) raise the bar by about one co-eluting
    fragment. A candidate gets no row when every consensus peak is <3 scans or outside RT tolerance
    (`PeakDataExtractor.cs:275/288`). The median-polish and reference-XIC fallbacks run only when CWT finds zero
    peaks. `cwt_candidates` per row grows for the same reason (`CoelutionScorer.CaptureCwtCandidates`, capped at
    `TopNPeaks`). To confirm: `OSPREY_DUMP_CWT_PATH` records the per-candidate CWT/RT-filter counts.
  - **Design question this raises:** one N sets both peak DETECTION (median consensus, where extra weak fragments
    hurt) and the SCORES (where 12 was measured to help). Separating them, e.g. consensus over the top 6-8 and
    scores over 12, may beat both 10 and 12. It needs an env var and a build; not started tonight because the
    machine is fully booked with the arms.
- **For MACS2's A/B (2026-11-13 ~03:45 PT / 12:45 CET): set the WHOLE recipe, not just the feature set.** Every
  number in this study, and UW8's A/B, runs #4950's opt-in recipe (`pwiz_tools/Osprey/docs/25-diann-gap-settings.md`):
  `--protein-best on` plus `OSPREY_FDR_MODEL=gbdt OSPREY_GBT_OOF=1 OSPREY_PASS2_QVALUE=transfer OSPREY_XIC_FRAGMENTS=12
  OSPREY_CORR_FRAGMENT_TOLERANCE=7 OSPREY_REF_XIC=corr OSPREY_LOCAL_RT_TOLERANCE=15 OSPREY_MIN_RT_TOLERANCE=1.0
  OSPREY_TC_HALF_WINDOW=0.40 OSPREY_LOESS_BANDWIDTH=0.10 OSPREY_RECON_REFIT=off OSPREY_FDR_SEED=1` (and
  `OSPREY_VERSION_OVERRIDE` for cached inputs). #4950's defaults reproduce master: protein-best off, SVM, 6 XICs,
  narrower windows - 45,858 vs 74,646 at true FDP 1% on 3 files (-39%), which is MACS2's low first result. Leg A
  adds `OSPREY_FEATURE_MASK=none` (or `--feature-set all`); leg B sets no mask. Confirm on each run.log's
  `Environment switches:` line. UW8's exact script: `ai/.tmp/sessions/20261110-uw8featset/perf82.ps1`.
- **Open for Brendan: the feature sets were validated ONLY under the recipe.** Several features depend on it
  (`tc_res_*` is always 0 at the default 6 XICs; the `tc_*` window is 0.15 min by default, not 0.40), so "default
  (70) ~ all (109)" is shown for the recipe only. The PR as built makes `default` the HRAM default even with the
  rest of the recipe off - an untested pairing. Options: (1) make the recipe the default together with the feature
  set (a #4950-level decision); (2) ship `--feature-set` with the HRAM default at `all` until the recipe becomes the
  default.
- **Brendan (2026-11-13 ~04:00 PT / 13:00 CET): #4950's goal is to make the ideal recipe (at least for Astral) the
  DEFAULT; no user should need to know it.** UW8 proposal from the per-switch evidence (sub-agent, verified spot
  checks; full evidence with sources: `ai/.tmp/recipe-switches-20261113.md`). A user types only inputs, library,
  output.
  - **Bake in, remove the knob:** GBDT + out-of-fold (HRAM; OOF needed for calibration, FDP 1.02-1.21% without it;
    OOF is in no validity key today - open #5019 keys it); two-round training (+8.5-10%); transfer second pass
    (calibrated 0.91-1.04% vs 1.30-1.55%); `REF_XIC=corr` (+2.8%, free); `LOCAL_RT_TOLERANCE=15` (+1.0%); no
    consensus refit (`RECON_REFIT=off`; its commit asks for an 82-file check first - owed); ratio PEP formula
    (`OSPREY_PEP_FORMULA=ratio`; current PEP 4-8x too pessimistic, detections unchanged).
  - **Per-resolution defaults, no knob:** XIC count (HRAM 12, unit 6: +7-9% Astral, -15% Stellar, single seed);
    correlation tolerance 7 ppm (HRAM; +0.7-1.3%, 3 seeds); tc window 0.40 (HRAM; +4.5%, 1 seed per point);
    classifier (HRAM GBDT; unit SVM until GBDT's Stellar pass-2 FDP 1.15-1.19% is explained); feature set (HRAM
    `default`, unit `core` - a placeholder: older Stellar runs say a larger set + GBDT gives +18%).
  - **User options (3):** `--feature-set`, `--protein-best` (default ON: +6.9% at 3 files, +9.7% at 62; keep the
    switch - only the split oracle can audit it; unmeasured on Stellar), `--fdr-model` (override only).
  - **Developer-only env vars:** `OSPREY_FDR_SEED`, `OSPREY_FEATURE_MASK`, `OSPREY_RECORD_ALL_FEATURES`, GBDT
    hyperparameters, prefilter sizes.
  - **Remove:** `EXPERIMENT_AGG` (superseded by protein-best), `MEANBEST2_FLOOR_*`, `MIN_FRAGMENT_TOLERANCE` (never
    helped), `LOAD_CALIBRATION` (Rust parity), `PROTEIN_BEST_DECOY=own` (collapses FDR).
  - **Undecided - experiments owed:** `MIN_RT_TOLERANCE` and `LOESS_BANDWIDTH` never ablated alone (moved with
    the tc window): drop-one from the full recipe, 3 seeds, Astral then Stellar. Two-round size: fixed 200k was
    8% short of local-FDR-0.9 + random 500k cap on Astral (one older-build run) - re-check on the current build.
    82-file check of no-refit.
  - **Consequence for the feature-set PR:** its HRAM `default` belongs in the same change that makes the recipe the
    default (#4950), not alone.

## Related (not this TODO's work)
- **DIA-NN on three axes** (detections, wall time, disk), same machine and files: Brendan to request of UW8
  or MACS2. Bytes written per run by file type, and the peak free-space drop during the run.
- **Disk accounting in the log**: track bytes on disk the way `--memstamp` tracks memory, so the working
  space a 2,000-run experiment needs is measured rather than estimated. **Design drafted (UW8, 2026-11-12):
  `ai/.tmp/sessions/20261110-uw8featset/disk-design.md`** - `--diskstamp` (bytes this run owns, third log column,
  high-water mark), an intermediates subfolder, opt-in release (keep-all stays the default; HPC chain guarded by
  `SubsetPipelineTest`; a `--task` rerun after release must refuse, not silently re-score: the shared
  `PipelineDriver.Run` re-runs any task that cannot rehydrate, `Shared/CommonUtil/Pipeline/PipelineDriver.cs:45-58`).
  Finding: FirstPassFDR is a join over every run's `.scores.parquet` (`FirstPassFdrTask.cs:211`), so the disk
  high-water mark is at the Stage 4/5 boundary and release cannot lower it; only smaller parquets can.
  Wants its own backlog TODO.
- **Per-file FDR as in DIA-NN (Brendan, 2026-11-12: a big design change, to consider carefully).** Score each run's
  classifier inside PerFileScoring so its output is per-run composite score / q / PEP, not a feature table, and
  join those for experiment-level FDR - removing the FirstPassFDR join and its disk peak. Evidence for DIA-NN 2.7.0,
  from UW8's 82-file log (`runs-uw8\diann270-82files\report.log.txt`): 164 "Training neural networks" events = 82
  runs x 2 passes, each on that run's own PSMs (~280-360k targets); per-run protein q-values; an empirical library
  built across runs between the passes (122,975 target precursors); a final "Cross-run analysis" reading the per-run
  `.quant` files (~90 MB each, vs Osprey's ~3 GB parquet) for "Target precursors at 1% global q-value: 99979".
  Verified from the log, not the source. Open issues: (1) Osprey's most important model input, `PROTEIN_BEST`
  (permutation drop 20%), is experiment-wide - where does it go in a per-run design? (2) per-run training and
  experiment-level FDR control are separate choices (DIA-NN does both); OpenSWATH/PyProphet moved from per-run to
  run-specific / experiment-wide / global contexts with a classifier learned on a pooled subsample (Rosenberger et
  al. 2017, recalled, not checked here); (3) check DIA-NN 2.8 when out.
- **Cache policy**: delete per-run artifacts once no later task needs them; which ones a rerun needs.
- **Entrapment ratio**: 1:1 entrapment doubles the library and the scored rows; how much the FDP oracle needs.
- **FirstPassFDR**: the protein-best round-1 run bound (UW25, pending commit), survivors-only intermediate
  files, and a fan-out FirstPassScoring task (other-machines TODO, UW25 section).
- MACS2 (2026-11-12 23:29) **Timing A/B started on the PR branch @ fab7e0caed** (snapshot
  `_bin\featset-fab7e0caed`, v26.1.1.316), one build, sequential legs, fresh scoring, quiet box at launch (total
  CPU 4-11%): **all109** (`--feature-set all`) -> **default70** (no option) -> efficient57 -> core21. Recipe:
  split-sized r=1.0 libdecoy, transfer pass 2, protein-best on, no model diagnostics, FDRBench both passes;
  MACS2's measured best lanes: 72 threads, `--parallel-files-scoring 4`, `--parallel-files-rescoring 8`,
  `OSPREY_FDR_FILE_LANES=16`. Driver `ai/.tmp/sessions/20261112-5023/featset-perf.ps1` (Run-SeaAd.ps1 gained
  `-FeatureSet`); runs, `featset.log` and per-leg `<tag>.diskstamp.tsv` (run-dir GB, D: free, total CPU every 120 s)
  under `D:\Users\brendanx\test\osprey-runs\sea-ad\runs-featset`. ~3-5 h per leg.
  **Prior MACS2 82-file baselines** (none has #5023/#5025/#5030's parquet reductions; parquet sizes were never
  measured on MACS2, only inferred from D: free):
  | run | build | lib | wall | scoring / FDR1 / rescoring / FDR2 (s) | pass 2 q 1% |
  |---|---|---|---|---|---|
  | core-21 master, night-A 11-06 | .310 ab7c6b21a7 | unsplit | **9,356 s (2 h 36 m)** | 5,205 / 1,046 / 2,463 / 642 | 59,036 |
  | core-21, fast1 10-06 | .279 #4780 | unsplit | 7,776 s (2 h 09 m) | 3,716 / 1,222 / 2,034 / 801 | |
  | all-109 #4950, night-B 11-06 | .310 74998d3d70 | unsplit | 21,746 s (6 h 02 m), contended | 14,821 / 2,112 / 3,792 / 1,021 | 86,237 |
  | DIA-NN 2.7.0, MBR, 10-30 | | own predicted | **485.9 min (8 h 06 m)**, upper bound | first pass 350 min | |
  night-A: `runs\seaad-82files-libdecoy-r1.0-protein-compactn1106night-A\run.log` (72 threads, 4/8 lanes, 8 FDR
  lanes, mdiag on, ~180 GB parquet inferred); night-B ~414 GB inferred; DIA-NN
  `D:\Users\brendanx\test\diann-vs-osprey\seaad\diann-search-82\report.log.txt` (7.4 GB output).
- MACS2 (2026-11-13 03:25) **Leg A under BUILD DEFAULTS done, then RESTARTED with the #4950 environment**
  (Brendan's call). The 23:29 chain cleared every OSPREY_* variable, so it ran the PR build's defaults: linear SVM,
  6 XICs, default LOESS/RT/tolerances, seed 42 - not the GBDT + 12-XIC configuration the study's ~96.5k numbers
  come from. **all109, build defaults: 8,151 s (2 h 16 m)** = PerFileScoring 4,790 / FirstPassFDR 1,824 /
  PerFileRescoring 1,404 / SecondPassFDR 130 s; scores parquet **201.8 GB** (82 files), run dir 233.5 GB, peak
  216.9 GB; total CPU mean 43%. Pass 1 **75,621 at true on-target FDP 1%** (q 1%: 74,482 at FDP 0.88%), pass 2
  75,386 (`split_calibration.py`). `runs-featset\seaad-82files-libdecoy-r1.0-transfer-fplanes16all109-20261112_232916`.
  The default70 leg under defaults was stopped mid-scoring and is not a result.
  - **Now running: `runs-featset-env`** (`featset-env.ps1`): same snapshot, lanes and recipe, plus the #4950 env
    (XIC_FRAGMENTS=12, LOESS_BANDWIDTH=0.10, MIN_RT_TOLERANCE=1.0, TC_HALF_WINDOW=0.40, CORR_FRAGMENT_TOLERANCE=7,
    REF_XIC=corr, LOCAL_RT_TOLERANCE=15, FDR_SEED=1, RECON_REFIT=off, FDR_MODEL=gbdt, GBT_OOF=1; NOT
    FEATURE_MASK=none, which overrides --feature-set): all109 -> default70.
  - **Queued behind it: master baseline** (`master-baseline.ps1`, `runs-master-baseline`): master fc8806b80a with
    #5030 backported (`Skyline/work/20261113_osprey_master_cwt_baseline` in pwiz-nightbase, staged, built, not yet
    tested), Debug gate + Stellar regression vs master's goldens, then one 82-file leg at build defaults (21-feature
    SVM, protein-compact pass 2), same library/lanes, no model diagnostics.

#### MACS2 82-file all109 under the #4950 environment (2026-11-13)

Run dir `D:\Users\brendanx\test\osprey-runs\sea-ad\runs-featset-env\seaad-82files-libdecoy-r1.0-transfer-fplanes16all109-20261113_032511`
(snapshot featset-fab7e0caed, GBDT OOF, 12 XICs, 4/8/16 lanes, 72 threads, mdiag off). Disk in GiB; memory from perfviz.py.

| | env all109 | build-defaults all109 |
|---|---|---|
| wall | 14,371 s (3 h 59 m) | 8,151 s (2 h 16 m) |
| PerFileScoring / FirstPassFDR / Rescoring / SecondPassFDR (s) | 10,330 / 1,957 / 1,936 / 143 | 4,790 / 1,824 / 1,404 / 130 |
| scores parquet | 206.6 GiB | 187.9 GiB |
| run dir at end | 241 GiB | 218 GiB |
| peak private | 149.5 GB (FirstPassFDR) | 170.6 GB (FirstPassFDR) |
| managed peak | 123.1 GB | 123.2 GB |
| scoring private peak | 71.2 GB | 66.1 GB |
| rescoring private peak | 82.9 GB | 133.4 GB |
| mean machine CPU | 55% | 43% |
| pass 1 at true FDP 1% | 96,710 | 75,621 |
| pass 2 at true FDP 1% | 96,654 | 75,386 |

UW8's same arm: 26,254 s, 262.6 GB parquet (before #5030), ~96.5k. default70 started 07:24.

- MACS2 (2026-11-13 13:35 PT / 22:35 CET) **Night plan: default70 rerun, then the #5030 rescoring A/B on MACS2's
  layout.** The 07:53 reboot killed default70 20 min into scoring (partial moved to `runs-featset-env\_interrupted`);
  re-run fresh from 12:15, ETA ~15:45. Then `night-cwt.ps1`
  (`ai/.tmp/sessions/20261112-5023/night-cwt.ps1`, log `D:\...\sea-ad\runs-cwt\night-cwt.log`):
  1. be63cfbfb7 (pre-#5030) Release snapshot `_bin\pre5030-be63cfbfb7`; full 82-file all-109 run under the recipe
     (`OSPREY_FEATURE_MASK=none`), ~4.3 h. Also a whole-pipeline pre/post pair with the 03:25 post-#5030 all109.
  2. PerFileRescoring alone, each build linked from its OWN full run, arms post / pre / post / pre (~33 min each).
     Same shape as UW8's `rescore-ab.sh`; MACS2's condition differs: spectra caches on E:, run dirs on the D: RAID,
     511 GB RAM. No admin, so the file cache cannot be purged: each arm follows the other build's arm, and the
     sampler records standby-cache GB. Reported per arm: wall and the `[PATH] PerFileRescoring: block reads` deltas.
     Post-#5030 reference from the 03:25 run: rescoring 1,936 s, 490 GB read (464 GB parquet), read 906 s, gate wait
     2,113 s.
  3. Then the master baseline (gate, Stellar regression, master21 82-file leg), now queued behind this.
  Night log: `ai/.tmp/night-session-budget-20261113.md`.
- MACS2 (2026-11-13 15:15 PT) **default70 vs all109 under the #4950 recipe, 82 files, fab7e0caed: default70 is
  27% faster, 26% smaller and 24% lower peak memory for 0.5% fewer detections.** Same lanes (4/8/16), same library.
  default70 run: `D:\...\sea-ad\runs-featset-env\seaad-82files-libdecoy-r1.0-transfer-fplanes16default70-20261113_121459`
  (fresh rerun after the 07:53 reboot); all109 run: `...fplanes16all109-20261113_032511`.

  | | all109 | default70 | change |
  |---|---|---|---|
  | Wall (s) | 14,371 | 10,548 | -26.6% |
  | PerFileScoring / FirstPassFDR (s) | 10,330 / 1,957 | 7,570 / 1,451 | -26.7% / -25.8% |
  | PerFileRescoring / SecondPassFDR (s) | 1,936 / 143 | 1,394 / 127 | -28.0% / -11% |
  | Scores parquets (GiB) / run dir (GiB) | 206.6 / 241 | 153.8 / 184 | -25.6% / -23.7% |
  | Private peak (GB, FirstPassFDR) / managed peak | 149.5 / 123.1 | 113.9 / 89.3 | -23.8% / -27.5% |
  | Scoring / rescoring private peak (GB) | 71.2 / 82.9 | 66.4 / 61.8 | |
  | True FDP 1%, pass 1 / pass 2 | 96,710 / 96,654 | 96,223 / 96,185 | -0.50% / -0.49% |

  (True FDP: `split_calibration.py`; memory: `perfviz.py --files 82`.) Next on MACS2 tonight: the pre-#5030
  (be63cfbfb7) all109 full run started 15:12, then the rescoring-only ABAB with spectra on E:, then again with
  spectra copied to D: beside the parquets (UW8-like), then the master baseline.
