# TODO-20261114_osprey_hram_defaults.md

## Branch Information
- **Branch**: not created. Proposed: `Skyline/work/20261115_osprey_hram_defaults`, stacked on #5033
  (`Skyline/work/20261112_osprey_default_feature_set`), which is stacked on #4950
  (`Skyline/work/20261028_osprey_diann_fdr_gap`). Merge #4950's tip first (2fca953602 = #5036).
- **Base**: #5033 -> #4950
- **Module**: `osprey`
- **Created**: 2026-11-14 (plan by UW8; Brendan is handing implementation to MACS2)
- **Status**: plan only, no code. The open experiment (MIN_RT_TOLERANCE / LOESS_BANDWIDTH drop-one) is queued
  on UW8; results land in this TODO.

## Goal

Make the scoring recipe that closed most of the DIA-NN gap on Astral (#4950, the 13 opt-in env switches) the
default path for users, with per-resolution defaults and only the CLI options most users would want. Today a
user gets the old defaults unless they copy the recipe's env block from `pwiz_tools/Osprey/docs/25-diann-gap-settings.md`.

## Principle (Brendan, 2026-11-14)

Not every lever used in testing becomes a CLI argument. A CLI argument has to be something ~90% of users would
want access to and be glad to see in `--help`. Anything only developers or deep researchers would set stays an
`OSPREY_*` env var: off the most travelled path and out of the most-read documentation. Env vars stay as
developer overrides even where the default changes.

## Evidence

Per-switch evidence, cost and resolution dependence: `ai/.tmp/recipe-switches-20261113.md` (2026-11-13).
Feature sets and the 82-file A/B: `TODO-20261110_osprey_feature_set.md`. Headline: the whole recipe vs the
defaults, 3 SEA-AD files: 45,858 -> 74,646 at true FDP 1% (+63%).

## The plan

### CLI (user-facing) - three options, two of them already exist

| Option | Default | Why a user sets it |
|---|---|---|
| `--resolution auto\|hram\|unit` | auto (exists) | selects the whole default set below |
| `--feature-set core\|efficient\|default\|all` | `default` HRAM, `core` unit (#5033) | disk/time vs detections; large cohorts |
| `--protein-best on\|off` | **on for HRAM**, off unit (exists, default off today) | changes what an ID means (costs some single-peptide proteins) |

Deliberately NOT a CLI option: `--fdr-model`. Few users have a reason to choose a classifier; it stays
`OSPREY_FDR_MODEL`.

### Built-in per-resolution defaults (env var stays as a developer override)

| Setting (env var) | HRAM | Unit | Note |
|---|---|---|---|
| Classifier (`OSPREY_FDR_MODEL`) | gbdt | svm | Stellar pass-2 FDP at q 1% is 1.15-1.19% under gbdt; svm until explained |
| XIC fragments (`OSPREY_XIC_FRAGMENTS`) | 12 | 6 | 12 is -15% on Stellar. UW25 is testing 10/8/6 on Astral |
| Correlation tolerance (`OSPREY_CORR_FRAGMENT_TOLERANCE`) | 7 ppm | calibrated (today) | ppm is HRAM-only by construction |
| Reference XIC (`OSPREY_REF_XIC`) | corr | most-intense (today) | free; Stellar needs one confirmation pair |
| Local RT tolerance (`OSPREY_LOCAL_RT_TOLERANCE`) | 15 | off | near free; floored at the global width |
| TC half window (`OSPREY_TC_HALF_WINDOW`) | 0.40 min | 0.15 min | in minutes, so gradient-dependent; follow-up: express in scans |
| Two-round GBDT training (`OSPREY_GBT_PREFILTER_SIZE` etc.) | on (required by protein-best) | n/a under svm | recipe-switches doc proposes LFDR 0.9 + sample, 500k cap after a re-check |

### Built in at all resolutions (the knob goes away, or becomes developer-only)

- `OSPREY_GBT_OOF=1`: always on for gbdt. Removing it also closes its validity-key gap (it is in no key today).
- `OSPREY_PASS2_QVALUE=transfer`: calibrated on Astral and Stellar; protein-compact overshoots (q-1% FDP 1.30-1.55%).
  Keep protein-compact only as a developer env var, if at all.
- `OSPREY_RECON_REFIT=off`: under transfer the refit only re-picks. The commit (a35c73458e) asked for an 82-file
  check first; the study's 82-file runs all ran with refit off, which is that check for HRAM.
- `OSPREY_PEP_FORMULA=ratio` (not in the recipe table; fixes PEP 4-8x too pessimistic, detections unchanged).

### Stays developer-only

`OSPREY_FDR_SEED` (keep 42; re-quote docs at 42), `OSPREY_FEATURE_MASK`, `OSPREY_RECORD_ALL_FEATURES`, GBT
hyperparameters and `PREFILTER_*`, `PROTEIN_BEST_SHUFFLE`, `FDR_TRAIN_FDR`, `NO_PREFILTER`.
Remove as leftovers: `MEANBEST2_FLOOR_*`, `EXPERIMENT_AGG`, `MIN_FRAGMENT_TOLERANCE`, `LOAD_CALIBRATION`,
`PROTEIN_BEST_DECOY=own`.

### Undecided - one experiment (UW8, below)

`OSPREY_MIN_RT_TOLERANCE` (recipe 1.0, default 0.5) and `OSPREY_LOESS_BANDWIDTH` (recipe 0.10, default 0.3) were
never ablated one at a time; they always moved together with TC 0.40. Ship at today's defaults unless the
experiment shows they pay.

## Implementation notes (from a code survey, 2026-11-14, #5033 @ fab7e0caed)

- Resolution is known in one place: `Osprey/Program.cs:537-544`. `--resolution auto` runs `ResolutionDetector.Detect`,
  then `config.ApplyResolutionMode`, then `PinFeatureMask.ApplySearchSettings(config.ResolutionMode, config.FeatureSet)`.
  That static "apply once the resolution is known, before anything reads it" call is the precedent to follow.
- The recipe settings today are `static readonly` fields on `Osprey.Core/OspreyEnvironment.cs` (e.g.
  `XicFragments` ~line 790, `SearchXicFragments` line 802), parsed at type init with a fixed default. They cannot
  depend on resolution as written. Proposed shape: one resolved settings object (resolution -> CLI -> developer
  env var), built at Program.cs:544, logged as one settings block, and fed into the validity keys.
- Watch static initializers that capture the value early: `Osprey.Scoring/TopFragmentExtractor.cs:50`
  (`SearchTopNFragments = OspreyEnvironment.SearchXicFragments`, static readonly) would freeze the XIC count before
  resolution detection runs.
- The XIC count is already recorded and checked in parquet metadata (`ParquetScoreCache.META_XIC_FRAGMENTS`,
  check at `Osprey.IO/ParquetScoreCache.cs:2698`; written by `PerFileScoringTask.cs:304`,
  `ReconciledParquetWriter.cs:222`). Each newly defaulted scoring setting needs the same treatment, or a resume
  across a default change silently mixes settings. `SearchIdentity.cs` hashes `resolution_mode`.
- CLI: `Osprey/OspreyCommandArgs.cs:455` (`ARG_PROTEIN_BEST`, default read from `new OspreyConfig().ProteinBest`:
  it needs to become resolution-dependent, like `--feature-set`'s help at line 467-476),
  `OspreyConfig.ProteinBest` (`OspreyConfig.cs:235`).
- HPC chain: every task must resolve the same settings; the resolution is in the task/identity, so derive the
  defaults from it rather than from the process env alone.

## Costs to plan for

- Every HRAM regression-test result changes (Astral legs); the Stellar legs change through the all-resolution
  items (transfer, OOF, refit off, PEP ratio). Re-record after review, per the usual process.
- Unit-resolution defaults stay at today's values for everything resolution-dependent until Stellar is measured
  (feature-set ladder, protein-best pair, REF_XIC pair, gbdt pass-2 calibration).
- `docs/25-diann-gap-settings.md` becomes history: the recipe is the default; the doc should say so.

## UW8 experiment: MIN_RT_TOLERANCE / LOESS_BANDWIDTH drop-one

Queued on UW8 behind the SSD-layout cwt A/B (starts ~06:00-07:00 PT Sun 11-15; one Osprey at a time on UW8).
Script `ai/.tmp/sessions/20261110-uw8featset/lrt.ps1` (chain `lrt-chain.sh`), results `lrt.tsv` there, runs in
`D:\test\osprey-runs\sea-ad\runs-uw8\lrt\`.

- Build: #5033 snapshot `_bin\uw8-featdefault-fab7e0caed` (default-70 features), `--protein-best on`, transfer,
  gbdt + OOF, 12 XICs, 7 ppm, REF_XIC corr, LOCAL_RT 15, refit off.
- Files: A01_005 / A06_010 / A10_014. Oracle: split entrapment, real targets kept at true FDP 1%, pass 1 (`score.py`).
- Arms (only these three settings move): `recipe` (MIN_RT 1.0, LOESS 0.10, TC 0.40), `minrt0.5`, `loess0.3`,
  `both-def` (0.5 / 0.3), `tc0.15`. Each scores once (FDR seed 1, full pipeline), then FirstPassFDR reruns at
  seeds 2 and 3 on that scoring (scoring is seed-independent).
- Decision rule: a setting ships at its recipe value only if dropping it loses more than the seed spread at
  3 seeds; otherwise today's default. If an arm is within ~1%, rerun that pair at 20 files before deciding
  (pruning effects grew with file count in the feature-set study).
