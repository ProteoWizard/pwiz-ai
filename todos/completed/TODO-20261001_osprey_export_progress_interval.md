# TODO-20261001_osprey_export_progress_interval.md

## Branch Information
- **Branch**: `Skyline/work/20261001_osprey_export_progress_interval` (worktree `C:\proj\pwiz-4708`)
- **Base**: `Skyline/work/20260612_net8_port` (PR [#4619](https://github.com/ProteoWizard/pwiz/pull/4619))
- **Created**: 2026-10-01
- **Status**: Completed
- **Module**: `osprey`
- **PR**: [#4756](https://github.com/ProteoWizard/pwiz/pull/4756) (merged 2026-10-02)
- **Follows**: `ai/todos/completed/TODO-20260923_osprey_carafe_export.md` (#4708)

## Objective

Follow-ups to the #4708 training export, found validating it on SEA-AD (82 Astral files):

1. The export's "Exporting isolation windows" progress printed at the 2 s compute cadence: ~19 percent
   lines per run of a ~37 s export (~1,500 per 82-run regeneration). Use `IO_INTERVAL_SECONDS` (5 s).
2. Pay-later export (`--task TrainingExport`, or the original command with `--training-export` added) took
   ~50 s/run cold on the SEA-AD HDD: 30 threads each walking their own window block in small reads made the
   disk seek between streams (~85 MB/s against 191 MB/s sequential). That is ~6 h at 446 files and ~28 h at
   2,000. Read each window as one block, one read at a time; decode in parallel.

## Tasks
- [x] Progress interval -> `IO_INTERVAL_SECONDS` (6687371987)
- [x] `SpectraWindowIndex.ReadWindowBlock` / `DecodeWindowBlock`; serial block-read mode in
  `StreamingWindowSpectraProvider`, used only by the training export; `IOTest` asserts block == LoadWindow
- [x] Cold A/B on SEA-AD runs 11-30: 50.6 -> 27.6 s/run, 82/82 byte-identical, memory unchanged
- [x] Warm A/B (straight-through case), runs 11-15: block reads cost ~0.8 s/run warm (5.6-5.8 vs 4.8 s), so
  block reads are used only when the export loads the spectra itself (pay-later); straight-through keeps
  LoadWindow and is unchanged (0d43f40aa9)
- [x] Tried and reverted: read-ahead of the next run's spectra (see 2026-10-01 log) - slower
- [x] /code-review max (15 findings): fixed oversized-window fallback to LoadWindow, damaged-footer
  bounds check, single LoadWindowSerialRead owning the lock (alloc outside it), shared ReadRecords walk,
  out-of-center-order IOTest case (red under a center-order BlockEnd), stale comments (061b2c9057).
  Dropped: per-thread buffers (~1 GB at 30 threads for ~0.4 s warm), warm pay-later cost, double-held
  block, extra decode copy, other loops' progress cadence. Calibration/Stage 6 cold reads raised with Brendan.
- [x] PR #4756; TeamCity at 061b2c9057: Windows .NET 4197553, Linux .NET 4197571 (638 each)

## Progress Log

### 2026-10-01
- Merged exe tests on SEA-AD (all 82 regenerated, byte-identical): `--task TrainingExport` 1 h 05 m;
  original command + `--training-export` 1 h 08 m with PerFileScoring/FirstPassFDR/SecondPassFDR skipped.
  Logs: `run.test1-task-trainingexport.log`, `run.test2-straight-trainingexport.log` in
  `D:\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-protein-compact-trainexport-20260930_122429`.
- First 5 runs of test 1 took ~5 s: their `.spectra.bin` were still in the Windows file cache from the
  previous night's 5-run check (128 GB RAM, 105 GB standby). So the export's own work is ~5 s/run; the rest
  of a cold run is disk.
- Cold sequential read of one 4.19 GB `.spectra.bin`: 22.5 s, 191 MB/s (D: = WD8004FRYZ 7200 rpm SATA).
- Block reads, runs 11-30 cold: 27.6 s/run mean (24-34) vs 50.6 s; `run.blockab-11-30.log`. Exe snapshot
  `D:\test\osprey-runs\_bin\export-blockread-wip`.
- Warm A/B logs: `run.warm-old.log` (was cold - runs 11-15 had been evicted - 61.8 s/run),
  `run.warm-block.log` 5.8, `run.warm-old2.log` 4.8, `run.warm-block2.log` 5.6 s/run; 82/82 byte-identical.
- Quiet machine (SkylineTester stopped; the earlier numbers ran beside it), cold, s/run: merged exe 52.9
  (runs 32-39) and 52.0 (56-63); block reads 30.0 (40-47) and 28.5 (64-71). Logs `run.abc-*.log`.
- Read-ahead tried and REVERTED: a background thread read the next run's `.spectra.bin` from its start,
  started after a run's window loop and stopped before the next run's. Runs 48-55: 35.2 s/run, slower. Its
  sequential stream starved the next run's setup (small reads: the EOF index, the reconciled parquet), so
  setup took ~28 s instead of ~2 s and the read-ahead finished the whole file first; the window loop then ran
  from cache in ~3 s, serializing disk and compute that block reads overlap. Stopping it at the next run's
  setup leaves only the ~1-2 s parquet write (same disk) to fill: <= ~2 s/run. Block reads already hold the
  disk ~22 of ~28 s per run; further gains are storage (cached export ~5 s/run) or exporting straight-through.
- Review-fix exe on cold runs 72-75 + pool-01..04: 29-33 s (pools 19-21 s), 82/82 byte-identical;
  `run.reviewfix-72-75-pool1-4.log`.
- 2026-10-02: merged the port branch (#4752 translations, #4676 installers) -> 208e536d82. Designer.cs conflict
  (adjacent entries); #4752's TestArgumentTextComesFromArguments rejected the literal ".spectra.bin" in the new
  damaged-cache message, so it drops the remedy sentence like #4752's messages. 642/642, inspection 0.
  TeamCity: Perf/Regression 4198756 (48 PASS / 0 FAIL, 1:01:49), Windows .NET 4198775, Linux .NET 4198776.

### 2026-10-02 - Merged

PR #4756 merged into `Skyline/work/20260612_net8_port` as commit 5c6cb07140. Shipped: the pay-later training
export reads each isolation window in one block, one read at a time per spectra cache
(`SpectraWindowIndex.LoadWindowSerialRead`), cold SEA-AD ~52 -> ~29 s per run on a 7200 rpm HDD; the
straight-through export keeps parallel `LoadWindow`; the export's progress reports at `IO_INTERVAL_SECONDS`.
Not shipped: the next-run read-ahead (measured slower, reverted). Open question raised with Brendan, not
started: calibration and the Stage 6 rescore read cold windows the same seek-heavy way (~59 and ~57 s/run
cold vs ~16 and ~4.5 s warm on the 82-run straight-through log).
