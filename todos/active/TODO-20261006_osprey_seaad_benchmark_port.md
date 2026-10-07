# TODO: SEA-AD 82-file benchmark of the port branch at default settings (three machines)

## Branch Information
- **Branch**: none - a measurement of `Skyline/work/20260612_net8_port` (port tip `dfcb8d17ef` or later)
- **Base**: `Skyline/work/20260612_net8_port` (PR #4619)
- **Created**: 2026-10-06
- **Status**: Not started. Handoff written 2026-10-06.
- **Module**: `osprey`
- **PR**: none (measurement only)

## Goal

Measure where Osprey stands after the recent performance work - #4765 (FirstPassFDR ordered file
lanes, planned/gated block reads, library identity, FdrLaneResolver), #4777 (charge check once per
file), #4767 (calibration / Stage 6 re-score reads one block per isolation window) and the rest of
the port branch - with a full SEA-AD 82-file run at default settings. Brendan is running the same
benchmark on three machines:

| machine | cores | RAM | notes |
|---|---|---|---|
| **this i9** (i9-14900, one HDD `D:` + NVMe `C:`) | 32 logical | **64 GB** | a TARGET configuration for Osprey - the one that matters most |
| a second i9 | | 128 GB | |
| NUMA PowerEdge server | 36 cores / 72 logical | > 500 GB | |

## Reference (same machine, same data, runner defaults, 2026-09-25)

`D:\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-protein-compact-logtag-progress-20260925_174500`
(exe `_bin\logtag-progress`, `--threads 30`, PerFile* sequential, model diagnostics on):

| task | seconds |
|---|---|
| PerFileScoring | 12,694.6 |
| FirstPassFDR | 4,444.2 |
| PerFileRescoring | 6,301.3 |
| SecondPassFDR | 1,263.6 |
| **total** | **6 h 51 min** |

## Plan

- [ ] Build Release from the port tip in `C:\proj\pwiz-work1`, snapshot to `D:\test\osprey-runs\_bin\port-<sha>`
- [ ] `Run-SeaAd.ps1 -WhatIf` with runner defaults (libdecoy, r1.0, protein-compact, threads 30,
      ParallelFiles 0, model diagnostics on) and `-Exe <snapshot>`; confirm cached mzML + .spectra.bin
- [ ] Full run, uncontested (see the nightly constraint below)
- [ ] Harvest per the SEA-AD README: perfviz (peak fits 64 GB, no gap >= 30 s), entrapment FDP tools
- [ ] Per-task and per-phase table vs the reference; FirstPassFDR lane decision line; peak private
- [ ] Record results here; compare with Brendan's other two machines when available

## Constraints
- SkylineNightly runs on this i9 from ~21:50 out of `D:\Nightly` - the same single HDD as the
  SEA-AD data - and made a 2026-10-04 CHS run 24% slower overall (every phase 20-85%). A full run is
  ~6-8.5 h: start it early enough to finish by ~21:30, or have the nightly skipped that night.
- The port branch was force-pushed on 2026-10-05 (#4765's merge `effd991447` became `f7021e609c`,
  same patch-id). Update with `git pull --ff-only`; never merge the old history back.

## Progress Log

### 2026-10-06 - MACS2 (NUMA PowerEdge) run started 12:51

Same analysis as the i9 runs, at runner defaults - match these when comparing:
- **Code**: port tip `490a4d3825` (#4781 on top of #4778 `08e46aedd9`; the history after the 10-06
  force-push). Release build snapshot `D:\Users\brendanx\test\osprey-runs\_bin\port-490a4d3825`
  (version `26.1.1.279-490a4d3825`). If an i9 built a different SHA, note it - #4781 changes PerFileScoring.
- **Library**: `target+decoy+entrapment-20260817` (passed with `-LibraryDir`; the runner's default
  still resolves Mike's unsuffixed 07-27 delivery - see the SEA-AD README).
- **Inputs**: 82 `.spectra.bin` only, no mzML on disk (cache-only; 82/82 structurally valid,
  13,400,091 MS2). Data, library and run dir all on D: (10K HDD RAID-5).
- **Settings** (runner defaults): libdecoy r1.0, protein-compact, `--threads 30`, files 1 at a time,
  FDRBench both passes, model diagnostics on.
- **Box**: 2 x Xeon Gold 6354 (72 logical), ~420 GB free at start; CPU 15% from another active user
  at launch (other users' processes are not visible - record load beside the result).
- Run dir: `D:\Users\brendanx\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-protein-compact-port-490a4d3825`;
  launcher log and 30 s CPU/disk samples (`launch-` / `iosample-port-490a4d3825-*`) in `sea-ad\runs`.

**MACS2 result: 4 h 19 m 28 s** (12:51:35 -> 17:11:03, `[TIMING] Total pipeline: 15567.9s`), exit 0.

| task | MACS2 port `490a4d3825` (s) | i9 reference 09-25, older code (s) |
|---|---|---|
| PerFileScoring | 8,162.9 | 12,694.6 |
| FirstPassFDR | 1,206.0 (8 FDR lanes: 30 threads, 429.6 GB free, 7.4 GB/lane) | 4,444.2 |
| PerFileRescoring | 4,542.4 | 6,301.3 |
| SecondPassFDR | 1,653.3 | 1,263.6 |
| **total** | **15,567.9 (4 h 19 m)** | **~24,660 (6 h 51 m)** |

The two columns differ in BOTH machine and code, so neither ratio is a speedup of the code. The i9
runs of `490a4d3825` are the comparisons that mean something.
- Memory (perfviz, `--files 82`): private peak 56.2 GB in FirstPassFDR (managed 40.3 GB); PerFileScoring
  priv 26.5 GB, PerFileRescoring 34.4 GB, SecondPassFDR 15.8 GB. Floors FALLING (-222 MB/file total);
  no reporting gap >= 30 s (max 28 s). The 64 GB i9's FirstPassFDR lane count will be lower (less free RAM).
- SecondPassFDR block reads: 356,611 reads, 835.6 GB (548.7 GB parquet), read 802.9 s, gate wait 722.1 s
  - the one task slower than the i9 reference, and the one that reads the most from D:.
- Box load (30 s samples): CPU median 7.5%, p90 19.7%, one spike to 95% (other users); >= 397 GB free
  throughout; D: read mean 51 MB/s (max 314).
- Output: 6,654 protein groups at 1%; FDRBench inputs for both passes written to the run dir.
  Entrapment FDP not yet computed (SEA-AD README harvest tools).

### 2026-10-06 - Planned
Created at handoff from the #4765 / #4777 session. **Next session handoff**: For detailed startup
protocol, read `ai/.tmp/handoff-20261006_osprey_seaad_benchmark_port.md` before starting work.
