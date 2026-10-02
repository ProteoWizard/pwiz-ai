# TODO-20261002_osprey_cold_window_reads.md

## Branch Information
- **Branch**: `Skyline/work/20261002_osprey_cold_window_reads` (worktree `C:\proj\pwiz-4708`)
- **Base**: `Skyline/work/20260612_net8_port` (PR [#4619](https://github.com/ProteoWizard/pwiz/pull/4619))
- **Created**: 2026-10-02
- **Status**: In progress
- **Module**: `osprey`
- **PR**: (pending)
- **Follows**: `ai/todos/completed/TODO-20261001_osprey_export_progress_interval.md` (#4756)

## Objective

Apply #4756's serial block reads (`SpectraWindowIndex.LoadWindowSerialRead`) to the two other readers that
read every window of a run cold:

1. **Calibration** (`Calibrator`, the Parallel.ForEach over calibration windows): cold whenever the
   `.spectra.bin` existed before the run - Brendan's normal workflow for large cohorts (`--task SpectraCache`
   once, raw files deleted, every analysis from the caches or later from scoring parquets).
2. **Stage 6 rescore** (`PerFileRescoreTask`, the subset re-score): cold for any cohort larger than RAM,
   fresh run or not. The gap-fill passes after it re-read warm windows and keep `LoadWindow`.

Expected on the SEA-AD HDD (from the 82-run straight log, caches pre-existing): calibration ~59 s/run cold vs
a ~23 s read floor, Stage 6 ~57 s/run cold vs ~4.5 s warm compute - ~33-35 s/run each. CHS 446 from caches:
~8 h; from scoring parquets: ~4 h. Only on spinning disks.

## Tasks
- [x] Calibration + Stage 6 subset re-score use serial block reads; 642/642, inspection 0
- [ ] `regression.ps1 -Dataset Stellar` (byte-identical vs golden)
- [ ] Cold A/B on SEA-AD: calibration (PerFileScoring from caches, 4-file legs) and Stage 6 (PerFileRescoring
  -LinkFrom, alternating exe every 6 files)
- [ ] Night session (fresh context): extended SEA-AD testing + `--parallel-files` 2/3/4 scaling on the i9
- [ ] /code-review, PR, TeamCity incl. Perf/Regression

## Progress Log

### 2026-10-02
- Branch from port branch ebde3bf6cd. Exe snapshot `D:\test\osprey-runs\_bin\coldreads-wip1`; baseline
  `D:\test\osprey-runs\_bin\export-reviewfix-wip` (#4756 code, same scoring/rescore read path as the base).
