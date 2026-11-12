# Stop writing non-scoring data no reader needs to Osprey .scores.parquet

## Branch Information
- **Branch**: `Skyline/work/20261112_osprey_scores_parquet_slim`
- **Base**: `master`
- **Created**: 2026-11-12
- **Status**: In Progress
- **GitHub Issue**: [#5023](https://github.com/ProteoWizard/pwiz/issues/5023)
- **Module**: `osprey`
- **PR**: (pending)

## Objective

Each Osprey `<run>.scores.parquet` written by PerFileScoring is ~37% non-feature data, much of it with no
production reader. On SEA-AD Astral (82 runs, split-sized library, #4950 settings) about 30% of every scoring
parquet can be removed or moved without losing information. Each byte is written once, read ~1.7x by
FirstPassFDR and again by PerFileRescoring (whose reconciled writer streams every column), so each byte saved
is ~3-4x its size in I/O per run. PR targets `master`; #4950 takes it by merge.

Measured file (UW25): `..._A01_005.scores.parquet`, 4,403,242 rows, 3.89 GB compressed / 7.00 GB uncompressed.
`cwt_candidates` 12.6%, `fragment_mzs`+`fragment_intensities` 10.5%, `reference_xic_*` 6.9%.

## Tasks

- [ ] Stop writing `fragment_mzs` / `fragment_intensities` (verbatim library spectrum; joinable by `entry_id`)
- [ ] Write `reference_xic_*` only when a consumer asks (`--training-export`)
- [ ] Move `cwt_candidates` to its own per-run file read only by the reconciliation planner
- [ ] Reconciled writer stops copying the dropped/moved columns into `.scores-reconciled.parquet`
- [ ] Record PIN features at column granularity, not family granularity (coordinate with #4950)
- [ ] *(Option, after measuring)* Normalize identity columns against the library by `entry_id`

## Verification

- [ ] Regression goldens byte-identical (`regression.ps1`, `regression-parallel.ps1 -Dataset All`)
- [ ] Confirm every reader of each column before removing it (round-trip tests, diagnostics, generic copies)
- [ ] `SubsetPipelineTest` and the training export pass
- [ ] SEA-AD measurement: per-file parquet size, PerFileScoring write time, FirstPassFDR / PerFileRescoring bytes read

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: OspreySharp.Test
- **Fails on master**: n/a (size/IO change; goldens prove outputs unchanged)
- **Passes on fix**: (pending)

## Progress Log

### 2026-11-12 - Session Start

Started on MACS2 in `D:\Users\brendanx\proj\pwiz`, branch from origin/master 829aee74b6.
