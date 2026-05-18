# RT Loess Normalization

## Branch Information
- **Branch**: `Skyline/work/20260428_PeakScoringAndNormalization` (shared with sibling TODOs below)
- **Worktree**: `sky_peakscoringandnormalization`
- **Base**: `master`
- **Created**: 2026-03-29
- **Status**: In Progress
- **GitHub Issue**: [#4094](https://github.com/ProteoWizard/pwiz/issues/4094)
- **PR**: [#4170](https://github.com/ProteoWizard/pwiz/pull/4170) — bundled "New peak scoring and normalization options" (open)
- **Related**:
  - [[TODO-20260329_sum_coelution_score]] — sibling on same branch / same PR (#4096)
  - Also bundled in PR #4170: issue [#4097](https://github.com/ProteoWizard/pwiz/issues/4097) (peptide/protein rollup — no TODO file)

### Branch history
- Original per-feature branch was `Skyline/work/20260329_rt_loess_normalization`.
- First combined PR was [#4127](https://github.com/ProteoWizard/pwiz/pull/4127) on branch
  `skyline/work/20260329_PeakScoringAndNormalization` — closed (not merged) because the
  branch name had a lowercase "skyline". Superseded by PR #4170 on the correctly-cased
  branch above.

## Objective

Add "RT Loess" as a normalization option in Skyline. This performs a LOWESS fit to peptide abundances across the RT gradient per sample, then normalizes each sample's curve to the median curve. This is how DIA-NN and MapDIA perform normalization between samples.

## Tasks

- [ ] Add RT Loess to NormalizationMethod.cs
- [ ] Implement normalization data tracking in NormalizationData for different retention times
- [ ] Update PeptideQuantifier to use the RT Loess normalization factor
- [ ] Make available in group comparisons and peptide settings > quantitation tab
- [ ] Add tests

## Progress Log

### 2026-03-29 - Session Start

Starting work on this issue. Key files identified by the issue:
- NormalizationMethod.cs - Add new normalization option
- NormalizationData - Track normalization factors per RT
- PeptideQuantifier - Apply the normalization factor
- Reference implementation: https://github.com/maccoss/skyline-prism/blob/main/skyline_prism/normalization.py
