# TODO-20261125_osprey_tuning_test_failures.md

## Branch Information
- **Branch**: `Skyline/work/20261125_osprey_tuning_test_failures`
- **Base**: `master`
- **Created**: 2026-11-25
- **Status**: Completed
- **PR**: [#5080](https://github.com/ProteoWizard/pwiz/pull/5080) (merged 2026-11-25)
- **Module**: `skyline`

## Problem

`TestBuildLibraryCarafeWizard` and `TestOspreySearchTuning` have failed on every bt209 master
build since c21d734ce7 (first failure: build 4279908; last green: 4279126 on c022df2a4c), with
Osprey's "No precursor passed the first pass". Both fine-tune on the three-run Stellar subset at
unit resolution (0.5 Th), whose first pass searches the untuned predicted library.

#4997 changed only Osprey/CarafeSharp paths, so the smart trigger never ran bt209 on it.

## Root cause

- Osprey reports q-values as (decoys + 1) / targets (`PercolatorQValues.ComputeConservativeQvalues`),
  so a run reports nothing at 1% until 100 targets outscore its best decoy. Each subset run is
  one isolation window of 276 target candidates.
- Before #4997 (mean MS2 calibration) the runs sat right at that floor: 100 / 0 / 111 precursors.
- #4997 made the m/z offset curve the default at any unit-resolution offset (Mike, 2026-11-10).
  Its 3 SD window is the SD of fragment offsets about a LOESS fit, narrower than the mean's
  (+-0.32-0.35 vs +-0.35-0.39 Th on the subset), and the runs fell to 0 / 0 / 0.
- Not overfitting (about 341 fragments per run, LOESS span 0.3): the curve removes a real
  -0.18 to +0.01 Th trend, and the narrower 3 SD window cuts heavy-tailed true matches.
- #5070 (per-run first-pass models) also made the starved first pass's RT training export small
  (123 rows), dropping the fine-tuned RT R2 to 0.69; at 5% FDR it has 155 rows and R2 0.998.

## Fix

Both tests set run, experiment and protein FDR to 5% on the search settings page (private
constants `TUNING_FDR` / `SEARCH_FDR` in each test, not shared). At 5% the floor is 20 targets
and the runs keep 106-163. No environment variable, no Osprey change, curve default kept.

Tried first and reverted (commits 1e2c8151bb, 85269f5f2d): `OSPREY_MS2_CAL_MEAN=1` for the
Osprey the tests launch, plus a lower RT R2 bar. It only restored the 100-target cliff.

## Evidence (local, 2026-11-25)

| Osprey | Test | Result |
|---|---|---|
| master, curve | unchanged | both fail (first pass), as TeamCity |
| master | mean (env var) | tuning passes; Carafe wizard RT R2 0.69 |
| c21d734ce7 (#4997, no #5070) | mean | both pass |
| c022df2a4c (before #4997) | unchanged | Carafe wizard passes |
| master, curve | 5% FDR | both pass, R2 bar unchanged at 0.9 |

Direct Osprey runs of the tuning search: `pwiz_tools/Skyline/TestResults/osprey-fdr-ab/fdr-all01`
(1%, fails) and `fdr-all05` (5%) in sky_testbuildlibrary; scripts in
`ai/.tmp/sessions/20261125-01DBpr/`.

## For Mike (Osprey, separate from this PR)

#4997's curve costs on nearly calibrated unit-resolution data: -1.8% at 1% entrapment FDP on the
2026 Stellar centroid runs (TODO-20261104_osprey_ms2_mz_calibration.md), and this subset's cliff.
Proposal: search the curve at the mean's width (the larger of the two windows); the HRAM numbers
there show the curve even with the mean at matched width.

## Tests
- [x] TestOspreySearchTuning, TestBuildLibraryCarafeWizard pass against master's Osprey
- [x] CodeInspection
- [x] bt209 on the PR (build 4281112)

## Follow-ups (separate work)
- [ ] Smart trigger: Osprey/CarafeSharp changes do not run bt209, though Skyline tests launch
  Osprey (`scripts/misc/vcs_trigger_and_paths_config.py`).

## Progress Log

### 2026-11-25 - Diagnosed and fixed
Root cause and A/B above; both tests passing locally at 5% FDR.

### 2026-11-25 - Merged

PR #5080 merged as commit 1134bd96e9, with every check green including bt209. Both tests now
search the Stellar subset at 5% FDR; Osprey and the curve default are unchanged. Not done here:
the curve's cost on nearly calibrated unit-resolution data is for Mike (note drafted, see the "For Mike"
section), and the smart-trigger follow-up is unfiled separate work.
