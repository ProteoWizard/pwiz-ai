# TODO-20261114_osprey_hram_defaults.md

## Branch Information
- **Branch**: `Skyline/work/20261115_osprey_hram_defaults` on MACS2, LOCAL ONLY (not pushed), from #5033's
  head 1b3156778a (which carries #4950's tip with #5036 and #5037).
- **Base**: #5033 -> #4950
- **Module**: `osprey`
- **Created**: 2026-11-14 (plan by UW8; Brendan is handing implementation to MACS2)
- **Status** (2026-11-15 ~00:30, MACS2 night session): the HRAM half of the per-resolution table is implemented
  and gated locally (see "MACS2 night 2026-11-14" below); not pushed, no PR. Still to do: the all-resolution items
  (transfer, refit off, PEP ratio, OOF knob removal), the leftover-variable removals, the settings log block, and
  MIN_RT_TOLERANCE / LOESS_BANDWIDTH once UW8's drop-one experiment lands here.

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

### Consumer survey (2026-11-14 20:30, read-only agent; traps spot-checked by UW8)

Paths under `pwiz_tools/Osprey`; OE = `Osprey.Core/OspreyEnvironment.cs`. Every chain task (PerFileScoring,
FirstPassFDR, PerFileRescoring, SecondPassFDR) is its own process and re-runs resolution detection
(`Program.cs:541`, `ResolutionDetector.cs:77-104`: measures inputs, else the mode recorded in the scores parquet,
else `Program.cs:542` falls back to HRAM), so each must resolve the defaults identically.

**Values captured before resolution is known (must be re-assigned after `Program.cs:542`):**
1. `Osprey.Scoring/TopFragmentExtractor.cs:50` `SearchTopNFragments` (static readonly): stackalloc sizes,
   extraction and the base key `;xic=`. `ParquetScoreCache.cs:2698` checks the live `OE.SearchXicFragments`
   instead, so making only one resolution-aware makes them disagree.
2. `Osprey/OspreyCommandArgs.cs:918` copies `OE.FdrModel` into `config.FdrClassifier` at parse.
3. `Osprey.Core/RTCalibrationConfig.cs:38,50`: `LoessBandwidth` / `MinRtTolerance` instance initializers read OE on
   every construction (at parse via `OspreyConfig.cs:141`, the factories at :64/:70, and the
   `Default(() => new OspreyConfig())` help lambdas). Both feed `SearchParameterHash` (`SearchIdentity.cs:116,118`),
   which is also parquet `META_SEARCH_HASH`.
4. OE:1239 `PROTEIN_BEST_PREFILTER_SIZE` is a `const` (also in the help text at OE:1143).
5. `--protein-best` default: `OspreyConfig.ProteinBest` plain auto-prop (false); the help default
   (`OspreyCommandArgs.cs:460`) reads `new OspreyConfig()`. Protein-best forces two-round training, not gbdt
   (`PrefilterSizeFor`, OE:1281-1286; `PercolatorEngine.cs:1070`).
Everything else is read live from OE at its use sites; only OE's resolution changes.

**Keying gaps:**
- `OSPREY_GBT_OOF` is in no key (OE:774, 1131). Baking it in for gbdt removes the gap.
- Base-key and FDR-key terms are emitted only when the env var is set (`;tcwin`, `;fcorr`, `;refxic`, `;rtlocal`,
  OE:1834-1842; likewise `;pep=ratio`, `;reconrefit=off`, `;gbtprefilter=`, `;fdrmodel=`). Once a default is
  non-null they must come from the RESOLVED value, or an env-unset run keys like a different default.
- Parquet metadata records only the XIC count and (via the search hash) MIN_RT / LOESS. The rest are checked only
  through the task stamps' ValidityKey (`ArtifactStamp`, `FdrScoresSidecar.cs:155-157`).
- `PercolatorEngine.cs:385` (projection path) uses raw `GbtPrefilterSize` while the key uses `PrefilterSizeFor`
  (:294); harmless today, two rules once the size is resolution-dependent.
- A Rescore / SecondPassFDR process without its inputs relies on the parquet's recorded mode; if that is missing it
  falls to HRAM. Keyed terms catch a mismatch; an unkeyed one would not.

Per-variable table (consumers, keys, tasks): the agent report is in this session's transcript; ask UW8 if needed.

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

## MACS2 night 2026-11-14 (Brendan asleep; night log `ai/.tmp/night-session-budget-20261114.md`)

Scope chosen: the **HRAM-only** rows of the table, because they leave every unit-resolution result unchanged, so a
byte-identical Stellar regression checks them. The all-resolution items move the Stellar results and the plan
wants them reviewed first; MIN_RT / LOESS wait for UW8.

Design (follows the code survey's notes above):
- `Osprey.Core/ResolutionDefaults.cs`: the one table (`LEGACY`, `HRAM`, `UNIT_RESOLUTION` = `LEGACY`) for the
  classifier, protein-best, XIC count, correlation tolerance, reference XIC, local RT tolerance, TC window and OOF.
- The classifier and `--protein-best` follow the precedent of the fragment tolerance: `OspreyConfig.ApplyResolutionMode`
  fills them unless given (`FdrClassifierGiven`, set when OSPREY_FDR_MODEL is set; `ProteinBestGiven`, set by the
  argument). Both the explicit `--resolution` and the detected route go through it.
- The developer variables: `OspreyEnvironment.ApplyResolutionDefaults(mode)`, called in Program beside
  `PinFeatureMask.ApplySearchSettings` (so every `--task` node resolves the same values); `InProcessOsprey` restores it.
  Each variable overrides, with explicit off spellings for what is now on: `OSPREY_GBT_OOF=0`, `OSPREY_REF_XIC=intensity`,
  `OSPREY_LOCAL_RT_TOLERANCE=off`, `OSPREY_CORR_FRAGMENT_TOLERANCE=off` (and the existing `OSPREY_FDR_MODEL=svm`,
  `OSPREY_XIC_FRAGMENTS=6`, `OSPREY_TC_HALF_WINDOW=0.15`, `--protein-best off`).
- Validity keys need no new terms: each term is spelled when the RESOLVED value differs from the legacy one, so an
  HRAM default keys exactly like the variable that once chose it (`;tcwin=0.4;fcorr=7;refxic=corr;rtlocal=15`,
  `;xic=12`, the gbdt and protein-best terms), and recipe outputs are adopted. Pinned by
  `TaskValidityKeyTest.TestResolutionDefaultsKeyLikeTheirVariables`.
- `TopFragmentExtractor.SearchTopNFragments` was a static readonly capture of the XIC count; now read live.

Commits (local): 11d13a33ba plumbing with legacy values at both resolutions (gate 685/685); cecff38a40 HRAM = recipe
(gate 686/686, help regenerated, docs 07 and 25); 5e27a2d80a **fix: an unset OSPREY_FDR_MODEL parsed to svm, so the
classifier always counted as given and HRAM silently trained the SVM** (caught because the first Astral recapture's
log showed SVM C sweeps; my first unit test skipped itself whenever FdrModel had a value, which hid it; now it parses
with no classifier); e32943ddcd the Astral results below and the gbdt log line without EXPERIMENTAL (gate 686/686).

Astral regression (3 files, HRAM) under the HRAM defaults vs #5033's default-70 set with the old defaults:
132,654 -> 138,820 library precursors at 1% (+4.6%), 8,612 -> 9,065 proteins (+5.3%), straight-through wall
15:00 -> 19:24 (+29%). `regression-parallel.ps1 -Dataset All`: 49 PASS / 0 FAIL, 52:30 (46:07 before); Stellar
unchanged. Logs: `ai/.tmp/sessions/20261112-5023/hd-astral-golden.log`, `hd-regression-all.log`, gates `hd-gate*.log`.

Timing: TeamCity Perf/Regression (tctest.bat) has no timing gate - it is regression-parallel.ps1 -Dataset All plus
CarafeSharp's nightly checks - so the slower HRAM defaults (+29% straight-through on Astral) only lengthen the
Astral lane (local -Dataset All 46:07 -> 50:58-52:30); nothing fails on it. The ja / zh-Hans resx have no `--protein-best` entry,
so those help pages show the new English text until it is translated.

`/code-review medium` on 1b3156778a..HEAD: 9 findings. Fixed in 12127bb099 (gate 686/686):
- `regression.ps1` still called the goldens the linear SVM's; now the default classifier's, and any set
  OSPREY_FDR_MODEL is refused under -CreateGolden (warned on compare).
- OSPREY_CORR_FRAGMENT_TOLERANCE and OSPREY_TC_HALF_WINDOW accepted any text, so a typo fell through to the HRAM
  default: both now refuse unparseable values at startup. (OSPREY_REF_XIC was already refused by its Values list.)
- OSPREY_TC_HALF_WINDOW=0.15 keyed `;tcwin=0.15`, unlike legacy outputs: 0.15 (`LEGACY_TC_HALF_WINDOW_MINUTES`,
  now also the scorer's constant) adds no term.
- A library phase under `--resolution auto` applied HRAM developer defaults while its config kept legacy ones:
  Program now passes null (legacy) while the resolution is undetected.
- The OSPREY_FDR_MODEL startup error still called svm the unset default; the test's inconclusive guard missed
  variables that switch a default off (now checks the six variables directly).
Dropped: the XIC-mismatch message already says to set OSPREY_XIC_FRAGMENTS to match the files.
**Decisions for Brendan:**
- The table is applied in two places: the classifier and protein-best per config (ApplyResolutionMode, like the
  tolerances), the six developer variables as process statics (ApplyResolutionDefaults, like PinFeatureMask). A
  host calling only ApplyResolutionMode gets half the recipe; production and InProcessOsprey get both. One option:
  hold all eight on OspreyConfig, which means threading config through the scorers that read the statics.
- `ai/scripts/Osprey/Benchmark/Run-DiannEntrapment.ps1`: its `osprey` step was the SVM baseline beside
  `osprey-gbdt`; at HRAM both now train gbdt with the recipe. Not changed: what should the baseline arm be?

**Equivalence check (01:45):** the HRAM defaults reproduce the recipe exactly. Same 3 Astral files and arguments as
regression mode 1, two arms: #5033's build (1b3156778a, snapshot `D:\Users\brendanx\test\osprey-runs\_bin\fs-1b3156778a`)
with OSPREY_FDR_MODEL=gbdt, OSPREY_GBT_OOF=1, OSPREY_XIC_FRAGMENTS=12, OSPREY_CORR_FRAGMENT_TOLERANCE=7, OSPREY_REF_XIC=corr,
OSPREY_LOCAL_RT_TOLERANCE=15, OSPREY_TC_HALF_WINDOW=0.40 and `--protein-best on`, vs this branch (12127bb099,
`_bin\hd-12127bb099`) with nothing set. Every blib table is identical row for row (138,820 RefSpectra, 9,065 Proteins,
LibMetadata included); only LibInfo's creation time differs. The defaults build pointed at the env arm's work dir skipped
all four tasks (`outputs valid`, 212 ms), so recipe output directories are adopted. Runs:
`D:\Users\brendanx\test\osprey-runs\hd-equiv\{fs,hd}` (`run.log`, `fs\adopt.log`); scripts
`ai/.tmp/sessions/20261112-5023/hd-equiv.ps1`, `hd-equiv-compare.py`. Final regression on 12127bb099: 49 PASS / 0 FAIL, 50:58.
