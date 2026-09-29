# osprey: Move regression.ps1 pipeline-mechanics legs to SubsetPipelineTest and halve the -Dataset All wall time

## Branch Information
- **Branch**: `Skyline/work/20260928_osprey_regression_to_subset_tests`
- **Base**: `Skyline/work/20260612_net8_port` (where #4727's SubsetPipelineTest landed; not master)
- **Created**: 2026-09-28
- **Status**: In Progress
- **GitHub Issue**: [#4728](https://github.com/ProteoWizard/pwiz/issues/4728)
- **Module**: `osprey`
- **PR**: (pending)
- **Checkout**: `C:\proj\pwiz-osprey`

## Objective

#4727 added `SubsetPipelineTest`, which runs the whole Osprey pipeline in-process on
small committed subsets of the Stellar and Astral regression data
(`Osprey.Test/TestData/*.zip`) in about 25 s on per-commit CI. About half of
`regression.ps1 -Dataset All` validates pipeline mechanics (caching, resume,
rehydrate, HPC task boundaries, sidecar contracts, route markers), which are valid on
any data. Move those legs to the subset tests: `regression-parallel.ps1 -Dataset All`
from 39.8 to ~20 min wall, serial from 78 to ~39 min.

Must stay on real data: straight-through runs and mode 1 golden on all 4 datasets
(only coverage of gap-fill, multi-charge consensus, LOESS); mode 1b Tier-2 FDR bounds;
one real HPC chain (mode 3 on LD) as the guard against statics leaking between phases.

## Tasks

- [x] Drop now: Stellar modes 2, 3 and 5 (603 s)
- [x] SubsetPipelineTest: compare every run's `*.2nd-pass.fdr_scores.bin` with the straight run at 1e-9 (port `Compare-FdrSidecars`); assert the verifier split (straight `verify=on`, chain shipped path)
- [x] SubsetPipelineTest: Astral HPC chain (TestAstralSubsetHpcTaskChain)
- [ ] ~~Gap-fill variant; then drop Astral mode 3~~ - DROPPED by decision 2026-09-29, see
  "Decisions". Astral mode 3 STAYS at full scale; the truncated-replicate fixture collapses on
  the current peak_sharpness score (see "peak_sharpness evidence").
- [ ] Red-check the new chain assertions (force the chain's verifier on; tamper one pass-2
  sidecar record) before relying on them
- [ ] SubsetPipelineTest: rescore-cut resume and crash-resume (`[PATH] rescore-resume:`, reconciled-parquet count, blib at 1e-9); then drop LD modes 8 and 9 (166 s)
- [ ] SubsetPipelineTest: file-set and `[PATH]` marker checks on transfer / mean-best-2 arm; then drop LD mode 10 (234 s)
- [ ] SubsetPipelineTest: re-emit diagnostics on rehydrate; pay-later with all four diagnostics products deleted; then drop LD modes 5, 7 and 11 (116 s)
- [ ] SubsetPipelineTest: per-phase fragment release (mode 6) incl. #4650 count equality; no `[PATH] all-runs-bundle:`; data-dir fingerprint before/after (no-copy)
- [ ] Optional: stripped-decoy subset library for mode 12; then drop LD mode 2 (162 s), keep GE mode 2
- [x] Quick win: switch kept self-consistency legs from PowerShell `Compare-BlibFull` to C# `BlibComparer` (#4727)
- [ ] Rebalance the two lanes of `regression-parallel.ps1` - revisit once the LD cuts land;
  with Astral mode 3 kept, lane B (GE + Astral, 2,325 s) is the wall
- [ ] Docs at PR time: osprey-development skill + ai/scripts/Osprey/PRE-COMMIT.md say
  `-Dataset Stellar` includes a resume leg; it no longer does (SubsetPipelineTest carries it)

## Decisions (Brendan, 2026-09-29)

* **Keep Astral mode 3** (straight vs HPC chain at real-data scale). A subset chain is added
  coverage, not a replacement for the rigor of the full-scale comparison.
* **No product or golden changes in #4728.** The feature set is going to be reassessed
  systematically, which will move the goldens anyway; nothing here should pre-empt that.
* **peak_sharpness: neither proposed fix adopted now.** The evidence below is recorded as
  part of the growing case against keeping the score, for a later systematic choice of the
  best feature set (Brendan and Mike plan to implement many known scores as calculators and
  run a competition).
* Why the Stellar cut is worth it even without a wall-time gain: unit tests + `-Dataset
  Stellar` is the habitual iterative smoke test. It is now faster, and pipeline-mechanics
  checks live in the per-commit unit tests instead of accumulating in the Stellar leg.

## Measured timings (regression-parallel -Dataset All, this machine)

Before: `C:\proj\pwiz-work1\...\TestResults\regression-lane-*-20260928_000529.log`.
After: `C:\proj\pwiz-osprey\...\TestResults\regression-lane-*-20260928_172848.log`
(58 PASS / 0 FAIL / 0 SKIP). Phase-cost totals, s:

| Dataset | Before | After |
|---|---:|---:|
| Stellar | 839 | 284 |
| StellarLibDecoy | 1,549 | 1,423 |
| StellarGenDecoyEntrap | 488 | 493 |
| Astral | 1,799 | 1,833 |
| Serial | 4,675 (77.9 min) | 4,033 (67.2 min) |
| Wall | 39.8 min | 38.8 min (lane B now critical) |

C# comparer on LD: mode 2 162->91, mode 5 78->33, mode 8 83->30, mode 9 83->51 s. Other
sessions' Osprey runs overlapped this run, so treat +/-10% as noise (mode 10/11 +30/+42 s).
Astral mode 3 measured 831 s here (the issue estimated 1,069).

## peak_sharpness evidence (for the future feature-set competition)

Prior notes on the same defect, read these first:
* `ai/todos/completed/TODO-20260927_osprey_subset_pipeline_test.md` (FINDING, NOT FIXED)
* `ai/.tmp/handoff-20260928.md`, `ai/.tmp/night4360/sharpness-impact.md` (impact study)
* Candidate fix (slopes from ref-XIC max) on LOCAL branch `nightlywork/reconciled-peak-sharpness`
  bbf588e4eb, worktree `C:\proj\pwiz-sharpfix`, with TestSubsetTruncatedReplicate (in-test
  mzML truncation; 0 precursors without the fix). Not adopted: moves goldens (Stellar -2.7%,
  FDP flat).

What this session added:
* **Causal proof.** Truncated-replicate run (Stellar subset, _22 cut at 10.5 min): 0 of 285
  peptides at 1%. Zeroing ONLY the sharpness weight in the saved first-pass models and re-running
  Stage 6/7 restores exactly 177 - the untruncated control's count. First-pass C per fold:
  control 0.001/0.01/0.01, truncated 0.001/1/100; fold 3 weights apex -0.56, area +3.77,
  sharpness -2.74, so a re-scored 0 (z ~ -7) adds ~+22 to the score.
* **Full-scale prevalence** (Stellar run 20): peak_sharpness == 0 on 33-37% of re-scored rows
  (12,637 of 36,884) vs 0.1% of first-pass rows; the zero rows' supplied apex is centred in the
  window (median position 0.5), apex always moved at re-score, so "stale apex" is ruled out.
* **Fold weights at full scale**: Stellar sharpness -0.042/0.124/0.124 with apex -0.36..-1.03 and
  area +0.28..+0.67; GenDecoyEntrap 0.046/0.099/-0.034. Sign flips across folds = fitting
  residuals among collinear intensity features, the same failure shape as Skyline's
  delta-RT-squared (a feature whose extreme values were never meant to carry a sign).
* **Barely separates at first pass**: sharpness median target 5.16 vs decoy 5.10, against
  fragment_coelution_sum 6.07 vs 5.00. It mostly restates log apex/area.
* **Correlation features degrade gracefully** on the same re-scored zero-sharpness rows:
  fragment_coelution_sum z median -1.5, 0% at |z|>4; median_polish_cosine z +0.3, 0.4%;
  sharpness 100% at z = -6.9. Bounded + scale-free is the property that matters.
* **Skyline has no single-trace peak-shape score.** mQuest "Shape" (MQuestFeatureCalc.cs:784)
  is area-weighted max-over-shift Pearson between transition pairs - a co-elution score;
  Osprey's fragment_coelution_* is the zero-shift, unweighted-SUM analogue (a sum is unbounded
  and partly a fragment count; Skyline uses a mean). Closest "is there a peak" score is
  NextGenSignalNoiseCalc (log apex / median background +/-500 pts), which stores Math.Abs of the
  log ratio - a trace 10x BELOW background scores like 10x above: the same degenerate-input
  pitfall, firing only on forced integration. IDetailedPeakData exposes Fwhm /
  IsFwhmDegenerate / IsTruncated but no calculator uses them.
* **Candidate replacement calculators** (reference XIC inside the window, all bounded and
  scale-free, noise -> natural low value): prominence fraction
  `(max - mean(edges)) / max` in [0,1] (peak vs flat); width in points = fraction of points
  >= half max, or FWHM in points (multi-point peak vs one-scan spike); signed S/N without Abs.
  Screen offline from the parquets (reference_xic_* columns) before any code change.
* **Competition criteria to build in**: sign stability across folds; in-distribution on
  re-scored/imputed rows, not only first-pass peaks; judge by the entrapment oracle, not counts.
  Check the Rust tree for Mike's earlier, larger feature set (reportedly one large function)
  as free candidates.
* Scratch scripts for all of the above (session scratchpad `gapfill/`): expq.py,
  topdecoys.py, zero_sharp.py.

## Regression Test

- **Test name**: SubsetPipelineTest (extended)
- **Test project**: Osprey.Test
- **Fails on master**: n/a - test-infrastructure migration, not a bug fix. Each new subset check must be shown to catch the defect its dropped regression leg caught (break the path, see red) before that leg is removed.
- **Passes on fix**: (pending)

## Progress Log

### 2026-09-28 - Session Start

Starting work on this issue. Branched from net8_port at fcd59201a3 (#4727 merge).
Checkout: `C:\proj\pwiz-osprey`. No open PR (#4730, #4725, #4724) touches regression.ps1 or
SubsetPipelineTest.

* Stellar SkipModes -> @(2, 3, 5, 8, 9). `regression.ps1 -Dataset Stellar` PASS with 5 lines
  (1, 1c, 4, streamed join, 6); 236 s of phases vs ~931 s before.
* Compare-BlibFull now calls Osprey.Test\BlibComparer.cs, compiled into the pwsh session by
  Initialize-Sqlite via Add-Type (needs netstandard + ComponentModel refs). Full Stellar blib:
  1.8-2.4 s vs 93 s PowerShell. Output capped to 20 rows + per-table counts (a changed
  pass-2 arm is 253K differing rows). C# comparer is a superset: it also compares peaks.
* TestSubsetHpcTaskChain: straight now runs verify=on; added the verifier split, per-run
  pass-1 (phase3 dirs) and pass-2 (phase4) sidecar compare at 1e-9 via the product reader
  FdrScoresSidecar.ReadRecords, and byte-equal experiment sidecars (pass 1 vs phase2, pass 2
  vs phase4). Not yet built.
* Doc follow-up at PR time: skill + PRE-COMMIT.md say `-Dataset Stellar` includes a resume
  leg; it no longer does (SubsetPipelineTest carries resume per-commit).

### 2026-09-29

* Full `regression-parallel -Dataset All`: 58 PASS / 0 FAIL / 0 SKIP, 38:46 wall (every
  Compare-BlibFull caller on the C# comparer). regression.html regenerated with
  -VerifyAgainst/-CostsFrom on those lane logs; fixed a stale mode-11 label in
  Write-RegressionMatrix.ps1's map (the script had added ", from every entry point").
* Build + 616/616 tests + zero-warning inspection. Chain helper refactored to a `Subset`
  descriptor; TestAstralSubsetHpcTaskChain added (3 s).
* Gap-fill fixture built, found the sharpness collapse, then withdrawn by decision (see
  Decisions). StellarSubset.zip restored to the committed bytes. Kept one pwiz-ai builder fix:
  build_subset.py writes the README with LF, so the zip no longer depends on autocrlf; verified
  it now regenerates StellarSubset.zip byte-identically.
* Uncommitted on the pwiz branch: regression.ps1, regression.html, BlibGolden.ps1,
  Write-RegressionMatrix.ps1, BlibComparer.cs, SubsetPipelineTest.cs.
