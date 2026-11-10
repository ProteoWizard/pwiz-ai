# TODO-20261110_osprey_feature_set.md

## Branch Information
- **Branch**: not created yet (experiments need no code until Phase 4; base will be the #4950 line,
  currently `Skyline/work/20261110_osprey_uw25_pb_fixes` on `Skyline/work/20261109_osprey_scoring_uw8`)
- **Base**: #4950 (`Skyline/work/20261028_osprey_diann_fdr_gap`) and its pending branches
- **Module**: `osprey`
- **Created**: 2026-11-10 (designed on BRENDANX-UW25)
- **Status**: Design. No arm run yet.

## Goal

Find the smallest PIN feature set that keeps #4950's detection gain, measured on the #5011 split
oracle, and make it the default. #4950 closed most of the gap to DIA-NN (5-6% behind at FDP 1% on
SEA-AD) by growing the classifier's input from 21 to 109 features. The cost of that growth now
shows on every other axis a user compares Osprey with DIA-NN on:

- **Disk.** `.scores.parquet` is 3.9 GB per SEA-AD run at 109 features (about 0.5-0.8 GB at 21). With
  the 4.4 GB `.spectra.bin` cache, Osprey keeps ~8.8 GB per run: ~725 GB at 82 runs, ~3.9 TB at 446,
  and a 2,000-run experiment would need ~18 TB while it runs. DIA-NN appears to leave no per-run binary
  cache at all (to be measured; see "Related").
- **Time.** On an HDD every FirstPassFDR read of every file costs in proportion to the bytes. At 82 files:
  October (21 features) training-feature load 4.7 min / 40 GB and score pass 8.8 min / 46 GB;
  November (109 features) 16.8 min / ~200 GB and 34.4 min / 205 GB. FirstPassFDR went from ~22 min to
  84.7 min, more of it from the features than from protein-best. (UW25 numbers, see
  `TODO-20261030_osprey_scoring_library-other-machines.md`, UW25 section.)
- **Scoring CPU.** Each family costs computation in PerFileScoring, family by family (one
  per-candidate computation per family; see the profile notes in the other-machines TODO).

A feature earns its place by detections at matched true FDP, not by being informative on its own:
correlated features compete for the same splits, so the question is what the SET needs.

## What already exists (no code needed to start)

- **Feature families** (`Osprey.IO/PinFeatureMask.cs`): 21 core features (PIN 0-20, always computed;
  `fragment_coelution_sum` is every row's first-pass score) and 16 families, each computed as a unit
  (`FAMILY_FIRST_FEATURES`): runner-up (`peak_coelution_margin`), context, per-fragment rank,
  spectrum-across-peak, median-polish top-k, reference correlation, peak profile, time correlation
  (`tc_*`), heavy/tight, dominance, top-3, wide, shadow, clean/clip, library agreement (HRAM only),
  spectrum match (HRAM only).
- **`OSPREY_FEATURE_MASK`**: comma-separated feature names hidden from the FDR classifier (`none` masks
  nothing; unset masks `DEFAULT_MASKED_FEATURES`). Keyed into FirstPassFDR and rescoring.
- **`OSPREY_RECORD_ALL_FEATURES=1`**: scoring records every family whatever the mask, so mask arms share
  one scoring. The scoring key is the recorded SET (`RecordedFeaturesValidityKeySuffix`), so an arm with
  this switch should adopt scoring done under `OSPREY_FEATURE_MASK=none`.
- **Scored data with all 109 columns**: UW25's SEA-AD legs `D:\test\osprey-runs\sea-ad\runs-uw25\
  seaad-{20,21,41}files-...-uw25-score*` (files 1-20, 21-41, 42-82; split-sized r=1.0 library, full
  #4950 settings, `OSPREY_FEATURE_MASK=none`), driven by `ai/.tmp/sessions/20261109-uw25mem/ladder.ps1`.
- **The oracle**: `ai/scripts/Osprey/SEA-AD/tools/split_calibration.py` on the on-target half of the
  split (q 1% kept with true FDP, and kept at true FDP 1%), the standing rule of the scoring-library TODO.
- **Prior signal to start from**: "wide_* (93-96) and heavy/tight, dominance families add ~0" and an
  incomplete per-family decomposition ablation (scoring-library TODO, open items); issue #4467 (open)
  specifies permutation importance, fold stability, univariate AUROC and correlation grouping for
  `--model-diagnostics`. Percent-contribution is a sanity check, not importance.

## Method

**Arm** = one FDR-only run on linked scoring: `Run-SeaAd.ps1` with the #4950 settings,
`OSPREY_RECORD_ALL_FEATURES=1`, `OSPREY_FEATURE_MASK=<arm>`, `-Task FirstPassFDR` (pass-1 numbers via
`-FdrBenchPass both`) and `-LinkFrom` the UW25 scoring legs. Read pass 1 with `split_calibration.py`.

**Protein-best off for the search, on for the confirmation** (Brendan's proposal). With it off, round 2
and the protein-best read disappear and an arm is roughly one training read plus the score pass. The
assumption - a set that matches the full set without protein-best also matches it with protein-best -
is tested explicitly in Phase 3, not taken on trust.

**Noise band first.** Two sets are "similar" only relative to seed-to-seed spread, which has not been
measured on this cohort. The 20-file protein-best rung moved -0.3% at FDP 1% on a change of round-1
sample alone.

**Cohort size.** Search at 20 files (fast, and the legs exist); confirm the short list at 82 files.

## Phases

### Phase 0 - Wiring and noise (UW25)
- [ ] One arm with `OSPREY_FEATURE_MASK=none` + `OSPREY_RECORD_ALL_FEATURES=1`, protein-best off, 20 files:
      confirm the log shows PerFileScoring adopted ("outputs valid"), only FirstPassFDR ran, and the FDRBench
      pass-1 file is written. Record wall time and parquet bytes read per arm.
- [ ] Baseline noise: full set, protein-best off, `OSPREY_FDR_SEED` 1-5 at 20 files -> mean and spread of
      kept at FDP 1% and q 1% (FDP). Also seed 1 with protein-best on, for Phase 3's reference.
- [ ] Core-only arm (21 features, the October set) at 20 files, to size the whole gap the families buy.

### Phase 1 - Family ablation (20 files, protein-best off)
- [ ] Leave-one-family-out: 16 arms. A family whose removal stays inside the noise band is a removal candidate.
- [ ] Core-plus-one-family: 16 arms. Shows which families carry signal alone (and which only in combination).
- [ ] Cheap priors alongside, from data already on disk: GBDT split/gain counts per feature from the arm
      models' JSON; univariate AUROC per feature on the training export; feature-feature correlation groups.
- [ ] Per-family cost: parquet bytes per column group, and PerFileScoring CPU per family from the existing
      dotTrace profile (`runs-uw8\profile-full-polish.dtp` report) or a family-masked scoring of one file.

### Phase 2 - Within-family pruning and candidate sets
- [ ] Inside the families that survive Phase 1, drop features by backward elimination guided by Phase 1's
      priors (rank features, ranks 5-6, shape bins, etc. are the likely redundancies).
- [ ] Assemble 2-3 candidate sets on the cost/benefit curve (e.g. ~30, ~40, ~60 features), each with its
      detections, parquet bytes per run, and scoring CPU.

### Phase 3 - Confirmation
- [ ] Each candidate set with protein-best ON at 20 files (tests the Phase 1-2 assumption) and at 82 files,
      full pipeline (pass 2, transfer), against the full set at 82 files (pass 2: 96,641 at q 1%, FDP 0.99%;
      96,654 at FDP 1%, UW25 run `seaad-82files-...-uw25-fdr82`).
- [ ] Stellar (unit resolution; HRAM-only families already off there) and Astral regression datasets.
- [ ] Timing and disk of the chosen set at 82 files on UW25 (same HDD), to quote against the November numbers.

### Phase 4 - Make it the default (code)
- [ ] Remove the dropped families from computation (not just mask them), so PerFileScoring and the parquet
      shrink; keep the mask/record-all switches for research.
- [ ] Recapture goldens; gate; regression-parallel; Perf/Regression on TeamCity when the PR is ready.

### Phase 5 - Storage format (separate measurement, after the set is known)
- [ ] float32 vs float64 feature columns: first as an FDR-only experiment (round the loaded features to
      float32 at load), so the classifier impact is measured before the parquet format changes; then bytes.
- [ ] Parquet encoding/compression options for the remaining columns.

## Open decisions (Brendan)
- Acceptable loss for the default set: inside the seed noise band at FDP 1%, or an explicit bound (e.g. 0.5%)?
- Is a smaller default plus an opt-in "full" set acceptable, or one set only?
- Does unit-resolution data (Stellar) get its own set, or the HRAM set minus the HRAM-only families as today?

## Related (not this TODO's work)
- **DIA-NN on three axes** (detections, wall time, disk), same machine and files: to be requested of UW8 or
  MACS2. Measure bytes written per run by file type and the peak free-space drop during the run.
- **Disk accounting in the log**: track bytes on disk the way `--memstamp` tracks memory, so the working
  space a 2,000-run experiment needs is measured rather than estimated.
- **Cache policy**: delete per-run artifacts once no later task needs them; which artifacts a rerun needs.
- **Entrapment ratio**: 1:1 entrapment doubles the library and the scored rows; how much is needed for the
  FDP oracle at a given cohort size.
- **FirstPassFDR handoff and task split**: survivors-only intermediate files and a fan-out FirstPassScoring
  task (other-machines TODO, UW25 section).
