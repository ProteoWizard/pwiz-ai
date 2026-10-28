# TODO-20261002_osprey_cold_window_reads.md

## Branch Information
- **Branch**: `Skyline/work/20261002_osprey_cold_window_reads` (worktree `C:\proj\pwiz-4708`)
- **Base**: `Skyline/work/20260612_net8_port` (PR [#4619](https://github.com/ProteoWizard/pwiz/pull/4619))
- **Created**: 2026-10-02
- **Status**: Completed
- **Module**: `osprey`
- **PR**: [#4767](https://github.com/ProteoWizard/pwiz/pull/4767) (merged 2026-10-04)
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
- [x] `regression.ps1 -Dataset Stellar` PASSED (byte-identical vs golden)
- [x] DIAGNOSTIC switches `OSPREY_SERIAL_WINDOW_READS=0` (old arm, same exe) and
  `OSPREY_SERIAL_READ_SCOPE=process` (for --parallel-files); commit ae4f5959c8
- [x] Cold A/B on SEA-AD (P=1): calibration pass 1 55.4 -> 23.1 s/file, Stage 6 85.5 -> 54.9 s/file; all
  scoring and Stage 6 outputs byte-identical to the completed run (calibration.json: timestamp only)
- [x] /code-review max on ae4f5959c8: 14 low-severity findings, no correctness bugs. Fixed in 580788a7ac: the =0
  switch gated at the two call sites (base-equivalent arm), startup log line naming the switches, scope read
  once, PROCESS_BLOCK_READ_LOCK, stale comments. Open for Brendan: warm serial reads (first-read-serial policy
  in the index instead of call-site choices), NVMe unmeasured, pre-GC LOH garbage (post-GC unaffected).
- [x] `--parallel-files` 1/2/3/4 sweep on the 128 GB i9 (day session 2026-10-04, not a night session)
  (i9-14900K, 24 cores = 8P + 16E, 32 logical, 128 GB) - see todos/backlog/TODO-osprey_parallel_files_scaling.md
- [x] PR #4767; TeamCity at 2992a096a2: Perf/Regression 4201294 (48/0), Windows .NET 4201287, Linux .NET 4201288

## Progress Log

### 2026-10-02
- Branch from port branch ebde3bf6cd. Exe snapshot `D:\test\osprey-runs\_bin\coldreads-wip1`; baseline
  `D:\test\osprey-runs\_bin\export-reviewfix-wip` (#4756 code, same scoring/rescore read path as the base).
- 2026-10-04: merged the port branch (#4715, #4751, #4763) -> 2992a096a2: 647/647, inspection 0, Stellar
  regression PASSED. The planned night session never ran; the sweep ran in a day session instead.
- `--parallel-files` sweep (PerFileScoring from cold caches, 12 files/leg, i9 128 GB): P=1 26:55, P=2 -5%,
  P=3 -12%, P=4 -8%, P=4 process-wide lock -16%, P=4 with serial reads off +21% (calibration pass 1 237 s/file).
  Peak total 30 -> 50 GB from P=1 to P=4. Full table and the 64 GB follow-up:
  `todos/backlog/TODO-osprey_parallel_files_scaling.md`.

### 2026-10-04 - Merged

PR #4767 merged into `Skyline/work/20260612_net8_port` as commit 12a0431bbe. Shipped: calibration and the Stage 6
subset re-score read cold spectra caches one window block at a time (cold SEA-AD per file: calibration pass 1
55 -> 23 s, Stage 6 86 -> 55 s, output byte-identical), and two DIAGNOSTIC switches for timing studies. Not
done, left for Brendan: the review's first-read-serial policy in SpectraWindowIndex (warm later calibration
passes pay ~0.5 s), NVMe/network storage unmeasured. Follow-up study: TODO-osprey_parallel_files_scaling.md.
