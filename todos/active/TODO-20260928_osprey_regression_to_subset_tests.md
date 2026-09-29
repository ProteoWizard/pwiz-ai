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

- [ ] Drop now: Stellar modes 2, 3 and 5 (603 s)
- [ ] SubsetPipelineTest: compare every run's `*.2nd-pass.fdr_scores.bin` with the straight run at 1e-9 (port `Compare-FdrSidecars`); assert the verifier split (straight `verify=on`, chain shipped path)
- [ ] SubsetPipelineTest: Astral HPC chain + gap-fill variant (one replicate truncated at RT 10.5 min, shipped in the zip) with `--model-diagnostics` on one chain; then drop Astral mode 3 (1,069 s)
- [ ] SubsetPipelineTest: rescore-cut resume and crash-resume (`[PATH] rescore-resume:`, reconciled-parquet count, blib at 1e-9); then drop LD modes 8 and 9 (166 s)
- [ ] SubsetPipelineTest: file-set and `[PATH]` marker checks on transfer / mean-best-2 arm; then drop LD mode 10 (234 s)
- [ ] SubsetPipelineTest: re-emit diagnostics on rehydrate; pay-later with all four diagnostics products deleted; then drop LD modes 5, 7 and 11 (116 s)
- [ ] SubsetPipelineTest: per-phase fragment release (mode 6) incl. #4650 count equality; no `[PATH] all-runs-bundle:`; data-dir fingerprint before/after (no-copy)
- [ ] Optional: stripped-decoy subset library for mode 12; then drop LD mode 2 (162 s), keep GE mode 2
- [ ] Quick win: switch kept self-consistency legs from PowerShell `Compare-BlibFull` to C# `BlibComparer` (#4727)
- [ ] Rebalance the two lanes of `regression-parallel.ps1` (target ~1,218 s lane A / ~1,107 s lane B)

## Regression Test

- **Test name**: SubsetPipelineTest (extended)
- **Test project**: Osprey.Test
- **Fails on master**: n/a - test-infrastructure migration, not a bug fix. Each new subset check must be shown to catch the defect its dropped regression leg caught (break the path, see red) before that leg is removed.
- **Passes on fix**: (pending)

## Progress Log

### 2026-09-28 - Session Start

Starting work on this issue. Branched from net8_port at fcd59201a3 (#4727 merge).
