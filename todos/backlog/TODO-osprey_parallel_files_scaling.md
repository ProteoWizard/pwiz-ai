# TODO-osprey_parallel_files_scaling.md

## Branch Information
- **Branch**: (none yet - a measurement study; code changes only if the results call for them)
- **Base**: `Skyline/work/20260612_net8_port`
- **Created**: 2026-10-04
- **Status**: Backlog - next step is the 64 GB i9 sweep
- **Module**: `osprey`
- **Follows**: `ai/todos/completed/TODO-20261002_osprey_cold_window_reads.md` (#4767)

## Objective

How much does `--parallel-files` buy per machine, and where does memory start to cost time? Brendan's NUMA
server (512 GB, 36 cores / 72 logical) saw little gain beyond P~4, and Stage 6 may need its own lever with a
different curve from Stages 1-4.

## Result on the 128 GB i9 (2026-10-04, #4767's code)

i9-14900K (24 cores = 8P + 16E, 32 logical), 128 GB, caches on D: (7200 rpm SATA HDD), 30 threads.
SEA-AD PerFileScoring only (calibration + first-pass scoring) from cold `.spectra.bin` caches, 12 files per leg:

| Leg | 12 files | vs P=1 | Peak total (pre-GC) | CPU median | Calibration pass 1 / file |
|---|---|---|---|---|---|
| P=1 (sequential) | 26:55 | - | 29.8 GB | 82% | 23 s |
| P=2 | 25:42 | -5% | 33.8 GB | 90% | 43 s |
| P=3 | 23:33 | -12% | 43.1 GB | 79% | 43 s |
| P=4 | 24:39 | -8% | 50.3 GB | 75% | 62 s |
| P=4, `OSPREY_SERIAL_READ_SCOPE=process` | 22:38 | -16% | 47.7 GB | 68% | 66 s |
| P=4, `OSPREY_SERIAL_WINDOW_READS=0` | 32:33 | +21% | 49.8 GB | 55% | 237 s |

- One file already keeps the CPU at 80-96% while it scores; P only fills the cold-read and startup gaps.
- Per-file read locks let P files' calibration reads compete for one disk (pass 1 climbs 23 -> 62 s at P=4);
  the process-wide lock gave the best result (single leg each, noise unknown).
- Without serial reads, P=4 is slower than sequential: #4767 is what makes --parallel-files viable on an HDD.
- Logs and samples on the 128 GB box: `C:\proj\ai\.tmp\sessions\20260930-night\pfsweep-*` and
  `D:\test\osprey-runs\sea-ad\runs\pfsweep-*\run.log`.

## Next: the 64 GB i9

Same sweep, same data, to see whether it reproduces or hits a memory slowdown before P=4.

1. Pull pwiz-ai; check out (or build) the port branch at or after #4767 (`12a0431bbe`); build Release and copy
   `pwiz_tools\Osprey\Osprey\bin\x64\Release\net10.0` to a snapshot dir.
2. SEA-AD caches (`.spectra.bin`) and the library must be present; the runner resolves the data dir from its env
   var (see `ai/scripts/Osprey/SEA-AD/README.md`). Run `Run-SeaAd.ps1 ... -WhatIf` first.
3. Make sure nothing else uses the disk (SkylineTester, other runs) and launch detached:
   `Start-Process pwsh -WindowStyle Hidden -ArgumentList '-NoProfile','-File','C:/proj/ai/todos/backlog/TODO-osprey_parallel_files_scaling/Run-ParallelFilesSweep.ps1','-Exe','<snapshot>\Osprey.exe','-LibraryDir','<lib dir>','-RunsDir','<runs dir>','-LogMemory'`
   (~2.5 h). `-LogMemory` adds post-GC probes: pre-GC peaks include garbage, and Server GC behaves
   differently with less headroom.
4. Check each leg's `run.log` for the `Window reads (DIAGNOSTIC)` line where a switch is set.

What to look for:
- **Memory pressure on the file cache**: calibration reads each cache cold, then first-pass scoring re-reads it
  from the file cache. At P files, the process (~30-50 GB) plus P caches (~4.4 GB each) may not fit in 64 GB;
  scoring then reads cold with PARALLEL LoadWindow (the seek-heavy pattern). Tell: disk read rate during the
  "Scoring isolation windows" phase and a jump in per-file scoring time at P=3 or P=4.
- Paging (Available MBytes near zero) and peak/floor from perfviz per leg.

## Later
- Stage 6 with P (`-Task PerFileRescoring -LinkFrom <completed run>`), separately from Stages 1-4.
- Repeat the P=4 per-file vs process-wide lock legs to see if the -16% vs -8% difference is real; if it is,
  consider the process-wide lock as the default under --parallel-files.
