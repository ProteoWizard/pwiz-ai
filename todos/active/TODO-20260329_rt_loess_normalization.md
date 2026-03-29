# RT Loess Normalization

## Branch Information
- **Branch**: `Skyline/work/20260329_rt_loess_normalization`
- **Base**: `master`
- **Created**: 2026-03-29
- **Status**: In Progress
- **GitHub Issue**: [#4094](https://github.com/ProteoWizard/pwiz/issues/4094)
- **PR**: (pending)

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
