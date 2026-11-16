# TODO-20261114_osprey_hram_defaults.md

## Branch Information
- **Branch**: `Skyline/work/20261115_osprey_hram_defaults`, from #5033's
  head 1b3156778a (which carries #4950's tip with #5036 and #5037).
- **Base**: #4950 (`Skyline/work/20261028_osprey_diann_fdr_gap`); #5033 merged into it 2026-11-15 as ec9a9e77fb
- **PR**: [#5038](https://github.com/ProteoWizard/pwiz/pull/5038) (merged 2026-11-15 into the #4950 branch as e7f8b17820;
  work branch deleted). Follow-up: one PR on the #4950 branch, three commits (see "Follow-up PR" below)
- **Module**: `osprey`
- **Created**: 2026-11-14 (plan by UW8; Brendan is handing implementation to MACS2)
- **Status** (2026-11-15, MACS2): the HRAM half of the per-resolution table is implemented and gated locally
  (see "MACS2 night 2026-11-14" below). Brendan approved pushing it as the way to lock the SEA-AD Astral gains
  into the defaults; pushed as #5038 (Perf/Regression #390 passed on 12127bb099); the settings then moved onto OspreyConfig (d95004c521), #4950 merged, head d29717e81d, Perf/Regression #391 (4266161) passed there; **#5038 merged into the #4950 branch as e7f8b17820**.
  This TODO stays active for the follow-up PR, which finishes the defaults; it waits for UW8's 20-file check
  (tc0.15, minrt0.5), not yet recorded here.

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

**Results, 3 files (2026-11-15 04:14 PT; `lrt.tsv`, runs `D:\test\osprey-runs\sea-ad\runs-uw8\lrt\`).** Real
targets kept at true FDP 1%, pass 1. q-1% FDP 0.99-1.08% in every arm (all calibrated).

| arm | seed 1 | seed 2 | seed 3 | mean | SD | vs recipe | per-seed difference |
|---|---|---|---|---|---|---|---|
| recipe (MIN_RT 1.0, LOESS 0.10, TC 0.40) | 73,408 | 74,685 | 74,133 | 74,075 | 640 | | |
| minrt0.5 | 73,035 | 73,182 | 73,113 | 73,110 | 74 | **-965 (-1.30%)** | -373 / -1,503 / -1,020 |
| loess0.3 | 73,808 | 74,201 | 74,003 | 74,004 | 197 | -71 (-0.10%) | +400 / -484 / -130 |
| both-def (0.5 / 0.3) | 73,191 | 73,335 | 73,152 | 73,226 | 96 | -849 (-1.15%) | -217 / -1,350 / -981 |
| tc0.15 | 72,806 | 73,795 | 73,915 | 73,505 | 609 | -570 (-0.77%) | -602 / -890 / -218 |

- **MIN_RT_TOLERANCE 1.0 pays (+1.3%).** Every minrt0.5 seed is below the recipe's lowest seed; both-def loses the
  same amount, so it is MIN_RT that matters. Proposed: HRAM default 1.0 (unit stays 0.5 until measured).
  **Cost (Brendan asked; one scoring run per arm, so no spread):** on these files the calibrated RT tolerance is
  +-0.55-0.59 min, so the 1.0 floor widens the window ~70%. PerFileScoring 329 / 352 s at the 0.5 floor
  (minrt0.5, both-def) vs 421 / 398 s at 1.0 (loess0.3, tc0.15): ~+20%, ~25 s/file. (recipe's 551 s ran first
  after the SSD arms, likely cold spectra reads.) Scores parquet 5.49 / 5.64 GB vs 5.91-6.03 GB per 3 files: +7-8%,
  ~0.15 GB/file. Reconciled parquet, FirstPassFDR, PerFileRescoring and SecondPassFDR unchanged. So MIN_RT 1.0 is
  +1.3% detections for ~+20% scoring time and ~+8% scores-parquet disk; the 20-file runs record both too.
- **LOESS_BANDWIDTH 0.10 does not pay** (-0.1%, sign flips by seed). Proposed: keep 0.3 at every resolution; it
  also avoids the 0.10 span's fragility with few calibration points.
- **TC_HALF_WINDOW 0.40: -0.8% without it, every seed negative but inside the recipe's own seed spread.** Within ~1%,
  so per the rule a 20-file check is queued. Keep 0.40 (MACS2's branch already has it) unless 20 files reverses it.
- **LOESS sweep queued first (Brendan, 04:25 PT: prove 0.3 vs 0.10 has no cost; look for a better value, e.g. 0.5).**
  `lsweep.ps1` -> `lsweep.tsv`, runs `D:\test\osprey-runs\sea-ad\runs-uw8\lsweep\`. Bandwidths 0.05 / 0.10 / 0.2 /
  0.3 / 0.5 / 0.75, recipe otherwise (MIN_RT 1.0, TC 0.40), same 3 files. Per bandwidth: two full-pipeline runs
  (FDR seeds 1 and 2: two scoring repeats for wall time and disk) plus seed 3 FDR-only; one warm-up run first;
  seed-1 runs ascending, seed-2 descending, so cache warmth and drift do not track bandwidth. Records detections,
  PerFileScoring / PerFileRescoring s, scores and reconciled parquet GB, calibrated RT tolerance. ~3 h.
- **LOESS sweep results (08:17 PT).** Kept at true FDP 1% (3 seeds), PerFileScoring and the scores parquet (two full
  runs each; the repeats agree within 5 s and to the byte), calibrated RT tolerance:

  | LOESS | kept (s1 / s2 / s3) | mean | SD | vs 0.10 | PerFileScoring | scores parquet | reconciled | RT tol |
  |---|---|---|---|---|---|---|---|---|
  | 0.05 | 74,044 / 73,518 / 74,601 | 74,054 | 542 | -21 | 415 / 415 s | 5.922 GB | 0.254 GB | 0.54 |
  | 0.10 (recipe) | 73,408 / 74,685 / 74,133 | 74,075 | 640 | | 411 / 415 s | 5.981 GB | 0.255 GB | 0.59 |
  | 0.2 | 73,218 / 73,701 / 73,533 | 73,484 | 245 | -591 (-0.8%) | 418 / 416 s | 5.984 GB | 0.254 GB | 0.60 |
  | **0.3 (master)** | 73,808 / 74,201 / 74,003 | 74,004 | 197 | -71 (-0.1%) | 420 / 423 s | 6.033 GB | 0.256 GB | 0.58 |
  | 0.5 | 72,410 / 73,292 / 73,154 | 72,952 | 474 | -1,123 (-1.5%) | 407 / 412 s | 5.936 GB | 0.250 GB | 0.59 |
  | 0.75 | 73,002 / 73,175 / 72,564 | 72,914 | 315 | -1,161 (-1.6%) | 409 / 409 s | 5.946 GB | 0.252 GB | 0.61 |

  (0.10 and 0.3 rows include the earlier lrt arms at identical settings; scoring is deterministic - the warm-up at
  0.3 reproduced lrt's loess0.3 seed 1 exactly, 73,808.)
  - **0.3 vs 0.10 has no meaningful cost:** scoring +8 s per 3 files (+2%, ~3 s/file), scores parquet +0.9%,
    reconciled, rescoring and FDR unchanged, detections -0.1% (sign flips by seed), calibration 0.98-1.12% everywhere.
  - **The response is a plateau from 0.05 to 0.3, then falls ~1.5% at 0.5 and 0.75.** 0.5 is not a missed optimum.
    The 0.2 dip (-0.8%, all three seeds) is inside the between-bandwidth scatter: a bandwidth change moves the
    calibration and so the candidate set, which acts like a fresh scoring draw (~0.5-1%).
  - Time and disk are flat across the whole range (407-423 s, 5.92-6.03 GB): the RT tolerance is set by the 1.0
    floor (computed 0.54-0.61 min), so the bandwidth barely changes the search window.
  - **Recommendation: keep master's 0.3 (no change).** MACS2's branch already leaves LOESS at 0.3.
- **20-file check results (2026-11-15 13:26 PT; `lrt-20.tsv`, runs `D:\test\osprey-runs\sea-ad\runs-uw8\lrt-20\`),**
  the feature-set study's 20 spread files, 3 FDR seeds, time and disk from each arm's seed-1 full run:

  | arm | kept (s1 / s2 / s3) | mean | vs recipe | PerFileScoring | FirstPassFDR | scores parquet | reconciled |
  |---|---|---|---|---|---|---|---|
  | recipe (MIN_RT 1.0, TC 0.40) | 85,694 / 85,547 / 86,616 | 85,952 | | 3,161 s* | 570 s | 40.5 GB | 2.22 GB |
  | minrt0.5 | 83,801 / 83,209 / 83,833 | 83,614 | **-2,338 (-2.7%)** | 2,582 s | 491 s | 36.9 GB | 2.07 GB |
  | tc0.15 | 85,177 / 85,982 / 85,663 | 85,607 | -345 (-0.4%) | 3,048 s | 524 s | 40.0 GB | 2.19 GB |

  *recipe ran first after the LOESS sweep; the sweep's warm-up showed a first run pays ~140 s of cold reads.
  q-1% FDP 0.91-1.11% everywhere.
  - **MIN_RT_TOLERANCE 1.0: the gain grows with files (+1.3% at 3 files, +2.8% at 20).** Cost at 20 files:
    PerFileScoring +17-22% (~23-29 s/file), FirstPassFDR +16%, scores parquet +9.8% (~0.18 GB/file), reconciled
    +7%; PerFileRescoring and SecondPassFDR unchanged. Recommend HRAM default 1.0; unit stays 0.5 until measured.
  - **TC_HALF_WINDOW 0.40: no demonstrated value.** -0.8% at 3 files, -0.4% at 20 (per seed -517 / +435 / -953),
    both inside the seed spread (recipe SD ~580). Cost also within noise (scoring +4% before the cold-start
    allowance, ~0 after; disk +1%). By Brendan's bar (no change without value and proven no cost) this favours
    **keeping master's 0.15**; MACS2's branch currently has 0.40 - decision for Brendan / MACS2.
- 20-file check (done, above) ran behind the LOESS sweep (~05:30 PT start): recipe, tc0.15, minrt0.5 on the feature-set
  study's 20 spread files, 3 seeds each (`lrt20-chain.sh` -> `lrt-20.tsv`). ~1.5-2 h per arm.

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

**Settings moved onto OspreyConfig (2026-11-15, Brendan's call).** The split left classifier and protein-best on the
config but the other six in process-wide state (`OspreyEnvironment.ApplyResolutionDefaults`, called from Program),
so a host that set up a config without Program got half the recipe, and the tests had to save and restore that
state around each in-process run. Brendan: values going into production belong in a production data structure, not
the form that was expedient for testing. Now `ScoringSettings` (XIC count, correlation tolerance, reference XIC,
local RT tolerance, tc window, gbdt out-of-fold) is `OspreyConfig.Scoring`, set by `ApplyResolutionMode` from
`ResolutionDefaults` with the env vars applied as overrides (`OspreyEnvironment.OverrideScoringSettings`); about 15
read sites, the validity keys and the parquet XIC-count check read the config; `ApplyResolutionDefaults`,
`AppliedDefaultsResolution` and the InProcessOsprey save/restore are gone. Commit d95004c521. Gates: 686/686 tests,
inspection 0 (`ai/.tmp/sessions/20261112-5023/build-scoring-settings3.log`); `regression-parallel.ps1 -Dataset All`
49 PASS / 0 FAIL, 1:05:44 (`cfg-regression.log` there); the Astral equivalence check (`cfg` arm, snapshot
`D:\Users\brendanx\test\osprey-runs\_bin\hd-cfg-uncommitted`) identical to the env-var recipe run in every blib
table but LibInfo's time (`cfg-equiv-compare.txt`), and pointed at that run's work dir it skipped all four tasks
(`D:\Users\brendanx\test\osprey-runs\hd-equiv\fs\adopt-cfg.log`). The #4950 branch (with the #5033 squash,
ec9a9e77fb, the same tree as 1b3156778a) merged with `-s ours` at d29717e81d. Still process-wide: #5033's feature
mask (`PinFeatureMask.ApplySearchSettings`), the same shape; a follow-up. Also committed (pwiz-ai 353e9fe6):
`Run-DiannEntrapment.ps1` gains `osprey-svm`, the classifier comparison on HRAM data now that `osprey` trains gbdt.

### 2026-11-15 - #5038 merged

PR #5038 merged into the #4950 branch as e7f8b17820 (tree identical to the PR head d29717e81d); the work branch is
deleted locally and on GitHub. It shipped the HRAM rows of the table (gbdt + OOF, `--protein-best on`, 12 XICs,
7 ppm, REF_XIC corr, LOCAL_RT 15, TC 0.40) on `OspreyConfig.Scoring`, and re-recorded the Astral regression results
once (12127bb099); Stellar unchanged.

## Follow-up PR (Brendan, 2026-11-15)

One PR on the #4950 branch with one re-record of the regression results, as three commits. It is a separate PR
only because the #4950 squash to master compresses the second re-record; otherwise it would have been part of
#5038.
1. Move #5033's feature mask (`PinFeatureMask.ApplySearchSettings`) onto the config. Output unchanged.
2. Remove the leftover variables (list under "Stays developer-only") and add the resolved-settings log block.
   Output unchanged.
3. The defaults: MIN_RT_TOLERANCE 1.0 for HRAM (`RTCalibrationConfig`, set in `ApplyResolutionMode`; it changes
   `SearchParameterHash`), OOF built in for gbdt, transfer / refit off / PEP ratio at every resolution, validity-key
   terms from the resolved values, `docs/25-diann-gap-settings.md` updated; LOESS stays 0.3; TC 0.40 unless the
   20-file check reverses it. One re-record of Astral and Stellar.

### 2026-11-15 - Follow-up PR in progress (MACS2, branch `Skyline/work/20261115_osprey_defaults_final`)

Local commits on the #4950 branch (e7f8b17820), not pushed:
1. 61de280c64 - `PinFeatureSelection` (new, `Osprey.IO/PinFeatureSelection.cs`): the features one search uses,
   computes and records, from `PinFeatureMask.For(config)` (its resolution and `--feature-set`). Replaces the
   process-wide `ApplySearchSettings` state; the scores parquet reader/writer, the first-pass model loader and the
   pass-2 worker take it explicitly. `FeatureSetScope` and the InProcessOsprey save/restore are gone. 686/686,
   inspection clean (`ai/.tmp/sessions/20261112-5023/build-featsel2.log`).
2. 0a206a5162 - removed `OSPREY_EXPERIMENT_AGG` (mean-best-N) with `MEANBEST2_FLOOR_*`, `MIN_FRAGMENT_TOLERANCE`,
   `LOAD_CALIBRATION` and `PROTEIN_BEST_DECOY` (done by a subagent in worktree `D:\Users\brendanx\proj\pwiz-defaults-c2`).
   Default-run keys unchanged: `;proteinbestdecoy=paired` kept as a literal, the model JSON still writes
   `"ExperimentAgg": "max"`. 670/670 (16 mean-best-only tests removed), inspection clean (`gate-c2-leftovers.log`).
   Still to update in pwiz-ai: runners that pass `OSPREY_EXPERIMENT_AGG` (`Common/OspreyDatasetRun.psm1`
   `-ExperimentAgg`, `SEA-AD/Run-SeaAd.ps1`, `CohortAnalysis/Run-CohortArms.ps1`,
   `Entrapment/coassign_decoy_estimate.py`) now hit the unknown-variable error if they set it.
   The resolved-settings log block is not done yet.
3. d65934dd4d - the defaults. HRAM: MIN_RT 1.0 (`ResolutionDefaults.MinRtTolerance`, applied in
   `ApplyResolutionMode`; same search hash as `OSPREY_MIN_RT_TOLERANCE=1.0`), TC back to 0.15 (Brendan, from UW8's
   20-file result). Every resolution: out-of-fold gbdt (legacy settings too), transfer, refit off (`on` restores
   it), ratio PEP (`mixture` restores it); the keys carry the old variables' terms, so recipe-variable runs adopt.
   Unit tests now run the default as transfer and pin `protein-compact` where they test the competition; the
   pre-protein-best digest runs with the three old defaults set. Found and fixed: a library build's tuning search
   keyed on the output's `--experiment-fdr` under transfer (`reconset=output@Precursor,<fdr>`), so
   `--experiment-fdr 1` re-ran the tuning; `TrainingSearchConfig` now gives it the default. 686/686, inspection
   clean (`build-c3c.log`).

Re-record running: `regression-parallel.ps1 -Dataset All -CreateGolden` at d65934dd4d (`final-golden.log`).

### 2026-11-15 - SEA-AD validation: the defaults reproduce the recipe (MACS2)

Brendan: prove the branch, run as a user runs it (no `OSPREY_*` variable), gives what the recipe was optimized to.
Script `ai/.tmp/sessions/20261112-5023/validate-seaad.ps1` calls Osprey.exe directly with the `OSPREY_*`
environment cleared (Run-SeaAd.ps1 always exports `OSPREY_PASS2_QVALUE`, `OSPREY_PICK_LDA` and
`OSPREY_LOG_MEMORY`); split-sized library `D:\Users\brendanx\test\osprey-runs\lib\astral\target+decoy+entrapment-20260817-split-sized`;
runs in `D:\Users\brendanx\test\osprey-runs\sea-ad\runs-validate\`; scored with `SEA-AD/tools/split_calibration.py`.
Build snapshot `_bin\final-d65934dd4d-log` (the three commits plus the settings log line).
- `old`: #5033's build (`_bin\featset-fab7e0caed`) with the recipe variables, exactly as `runs-featset-env` ran.
- `exact`: this branch with only LOESS 0.10, TC 0.40, seed 1 and PEP mixture set back.
- `user`: this branch with no variable, and no `--resolution` / `--protein-best` / `--fdr-level`.

3 files (A01_005 / A06_010 / A10_014):

| arm | pass 1 at true FDP 1% | pass 2 at true FDP 1% | pass 2 at q 1% (FDP) | wall |
|---|---|---|---|---|
| old | 73,408 | 73,976 | 73,566 (0.95%) | 13 min 1 s |
| exact | 73,408 | 73,976 | 73,566 (0.95%) | 11 min 30 s |
| user | 74,295 | 74,205 | 73,926 (0.95%) | 11 min 14 s |

- `exact` = `old` in every blib table, row for row (RefSpectra 73,810, peaks, RetentionTimes 221,350, proteins);
  only LibInfo's time and LibMetadata (version, and the `osprey.feature_set` row #5033 added) differ. So every
  setting of the recipe but the four is now the default. Pass 1 73,408 is UW8's recipe seed-1 number exactly:
  MACS2 reproduces UW8.
- `user` is +1.2% over the recipe (pass 1): 74,295 vs the docs' 74,646 (recipe, other build) and DIA-NN's 78,668 (-5.6%).
- 82-file recipe run on MACS2 (`sea-ad\runs-featset-env\...default70-20261113_121459`, #5033 build, variables, seed 1):
  pass 1 96,223 / pass 2 96,185 at true FDP 1%, 1.02% at q 1% (docs: 96,654 on UW8; DIA-NN 101,269). 2 h 55 min.
- **82-file `user` run (`runs-validate\user-82files`, 18:30-21:25): pass 1 93,349 / pass 2 93,382 at true FDP 1%,
  1.04% at q 1%; 2 h 54.6 min (10,476 s vs the recipe's 10,541 s).** That is -3.0% against the recipe's 96,223,
  where 3 files gave +1.2% and UW8's 20-file drop-ones put TC 0.15 at -0.4% and LOESS 0.3 at -0.1%. The drop is
  in pass 1: per-file first-pass total 4,365,265 vs 4,517,400 (-3.4%); scored candidates 360.19 M vs 358.90 M.
  First-pass FDR chose 8 lanes (cap; 409 GB free, 7.3 GB/lane). Next: FDR-only re-run on the same scoring with
  seed 1 + PEP mixture (`seed-pep-82.ps1` -> `user-seed1-mixture-82files`) to split seed/PEP from TC/LOESS.

Also: added a startup refusal of `--protein-best` with `OSPREY_PASS2_QVALUE=protein-compact` (Brendan: they must not
run together; on SEA-AD the pair read 1.47% true FDP at q 1%, TODO-20261030_osprey_scoring_library.md). Checked
after the resolution is known (HRAM turns the column on by default). 670/670, inspection clean (`build-pbpc.log`).
Regression Astral reference points (not like for like, other library): DIA-NN 2.7.0 145,788 at global q 1% with its
own predicted library (`D:\Users\brendanx\test\diann-vs-osprey\astral3-mike`); master 117,660, #5038 138,820,
this branch 133,766 at reported q 1% on `SkylineAI_spectral_library.tsv`.
