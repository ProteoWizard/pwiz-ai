# DIA-NN Sum Coelution Score

## Branch Information
- **Branch**: `Skyline/work/20260329_sum_coelution_score`
- **Worktree**: `sky_sumcoelutionscore`
- **Base**: `master`
- **Created**: 2026-03-29
- **Status**: In Progress
- **GitHub Issue**: [#4096](https://github.com/ProteoWizard/pwiz/issues/4096)
- **PR**: (pending)

## Objective

Add a "Sum Coelution Score" to Skyline, based on DIA-NN's primary scoring approach. For each peak, compute pairwise Pearson correlations between all transition XICs within the peak boundaries and sum them. With N transitions there are N*(N-1)/2 pairs, so the score ranges from -N*(N-1)/2 to +N*(N-1)/2 (e.g., -15 to +15 for 6 transitions).

## Tasks

- [ ] Identify where peak scoring is computed in Skyline
- [ ] Implement pairwise Pearson correlation computation for transition XICs
- [ ] Add SumCoelutionScore as a new peak feature/score
- [ ] Wire up the score so it's available in reports and mProphet model
- [ ] Add tests
- [ ] Verify with existing test data

## Progress Log

### 2026-03-29 - Session Start

Starting work on this issue. Working in sky_sumcoelutionscore worktree.
