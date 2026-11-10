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
(none yet)

## Related (not this TODO's work)
- **DIA-NN on three axes** (detections, wall time, disk), same machine and files: Brendan to request of UW8
  or MACS2. Bytes written per run by file type, and the peak free-space drop during the run.
- **Disk accounting in the log**: track bytes on disk the way `--memstamp` tracks memory, so the working
  space a 2,000-run experiment needs is measured rather than estimated.
- **Cache policy**: delete per-run artifacts once no later task needs them; which ones a rerun needs.
- **Entrapment ratio**: 1:1 entrapment doubles the library and the scored rows; how much the FDP oracle needs.
- **FirstPassFDR**: the protein-best round-1 run bound (UW25, pending commit), survivors-only intermediate
  files, and a fan-out FirstPassScoring task (other-machines TODO, UW25 section).
