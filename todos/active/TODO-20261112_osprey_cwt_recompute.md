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

**Code map (read-only audit of this branch, 2026-11-12; nothing run yet):** bit-identical
recompute looks feasible - every Stage 4 input is on disk.
- Stage 4 chain: `CoelutionScorer.ScoreCandidate` -> `PeakDataExtractor.TryExtract` (non-override
  path) -> `CaptureCwtCandidates` -> stable descending rank-score sort, truncated to
  `Reconciliation.TopNPeaks` (5) -> `BuildFdrEntry`. Window: Stage 3 RT calibration,
  MAD = `rtCalibration.Stats().MAD`, `SearchWindowHalfWidth(...)`, sigma max(5*1.4826*MAD, 0.1),
  `OSPREY_LOCAL_RT_TOLERANCE`; fragment tolerance from ms2Cal SD; spectra (RT, scan) sorted.
- No cross-precursor dependency (per-candidate context cleared); dedup only drops rows.
- Catch: a precursor in two overlapping isolation windows is scored per window and dedup keeps
  one row; the window is not stored -> identify it from the apex `ScanNumber`.
- Stage 6 has no call that reproduces it: re-pick/forced rows are rescored as boundary overrides
  (no CWT) with the REFINED calibration. Recompute must use the Stage 3 calibration, and spectra
  load after planning today (`LoadSpectraForRescore` follows `PlanRun`).
- The planner reads only Apex/Start/End RT and list order (candidate index into
  `.reconciliation.json`); Area/SNR/CoelutionScore are read by nothing.
- Risks: wrong window choice, `refined` vs Stage 3 calibration, OSPREY_* drift between stages,
  `OSPREY_LOAD_CALIBRATION`, demux-cache vs `.spectra.bin`, `OSPREY_REF_XIC=corr` (candidate
  apex/area depend on which peak won).

Diagnostic (`OSPREY_CWT_RECOMPUTE_CHECK=1`, compare recomputed vs stored for every non-Keep row)
being implemented by a sub-agent in pwiz-nightbase; status in `ai/.tmp/agent-cwtcheck-status.md`.
