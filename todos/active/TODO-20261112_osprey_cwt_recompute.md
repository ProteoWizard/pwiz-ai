# Recompute CWT candidates in PerFileRescoring instead of storing them in Osprey .scores.parquet

## Branch Information
- **Branch**: `Skyline/work/20261112_osprey_cwt_recompute`
- **Base**: `Skyline/work/20261028_osprey_diann_fdr_gap` (#4950, stacked)
- **Created**: 2026-11-12
- **Status**: In Progress
- **GitHub Issue**: [#5024](https://github.com/ProteoWizard/pwiz/issues/5024)
- **Module**: `osprey`
- **PR**: (pending)

## Objective

`cwt_candidates` is ~0.54 GB per SEA-AD run (the largest column group left after #5023), but the
Stage 6 planner reads ~0.7% of its rows (~30k of ~4.3M per run: consensus, passing, apex outside
tolerance) and only 3 of the 6 values per candidate. Planning already runs per run in
PerFileRescoring just before the rescore. Recompute the candidates there for the consulted rows
and stop writing the column - with candidates identical to Stage 4's, so goldens do not move.

## Tasks

- [ ] Diagnostic: recompute candidates for consulted rows in PerFileRescoring, compare field by
      field with the stored lists (opt-in). SEA-AD 3 files + regression datasets. Gate: 0 mismatches.
- [ ] Planner uses recomputed candidates; Stage 4 stops writing `cwt_candidates`
- [ ] Remove `CwtCandidateLoader`, `LoadCwtCandidatesFromParquet`, `ProbeCwtRowMetadata`,
      range validation, the column
- [ ] Goldens byte-identical (`regression-parallel.ps1 -Dataset All`), `SubsetPipelineTest`
- [ ] SEA-AD A/B: disk, PerFileScoring write, PerFileRescoring time

## Regression Test

- **Test name**: (pending - the diagnostic's comparison, then the goldens)
- **Test project**: OspreySharp.Test / regression
- **Fails on master**: n/a (storage change; goldens prove outputs unchanged)
- **Passes on fix**: (pending)

## Progress Log

### 2026-11-12 - Session Start

Working in `D:\Users\brendanx\proj\pwiz-nightbase` (MACS2), branched from #4950 head e2ea35f0cc.
Developer chose to stack on #4950 because its CoelutionScorer changes are not expected to move
again. Overlap with #5023 (targets master, same ParquetScoreCache writer code): #5023 should be
merged into #4950 before this lands, or this branch merges it in.
