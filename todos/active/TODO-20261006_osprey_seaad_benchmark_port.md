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

## Handoff: tune the 128 GB i9 from the MACS2 lessons (beat its 4:12)

Question to answer: do the MACS2 lessons transfer to a single-socket 32-thread desktop with excess RAM,
or is the i9 already at its optimum? Expect much less than MACS2's 2x - one i9 file already keeps the CPU
80-96% busy (2026-10-04 sweep: P=3 gave -12%). Every lever below is an experiment, not a setting to copy.

**Build**: PR #4780 (branch `Skyline/work/20261005_osprey_per_stage_parallel_files`, tip `c84de72a6e`, on the
current port tip) - it adds `--parallel-files-caching/-scoring/-rescoring` and runner switches
`-ParallelFilesScoring/-ParallelFilesRescoring` (pwiz-ai master). Build Release, snapshot to `_bin`.

**Method that worked on MACS2** (keep it - the box noise and cache state fooled single runs twice):
- Measure one stage at a time. Scoring: the first 8 files, `-Task PerFileScoring -NumFiles 8`, fresh tag per
  leg (a reused tag resumes instead of re-scoring). FirstPassFDR: `-Task FirstPassFDR -LinkFrom <the 4:12
  run> -Fresh` (hard-links Stage 1-4; regenerates only FirstPassFDR; pins the version stamp).
- The FIRST leg after anything else reads cold (MACS2: +300-650 s on FirstPassFDR). Run a throwaway warm-up
  leg, or discard leg 1. Compare `[PATH] ... block reads ... read Ns, gate wait Ns` to spot a cold leg.
- Repeat the winner; alternate A/B legs. Compare the CPU-bound `Coelution scoring: ... cand/s` per lane to
  separate CPU contention from disk.
- `DOTNET_*` and `OSPREY_FDR_FILE_LANES` pass through the runner (it strips only its own OSPREY_* list).
- Each full 82-file run writes ~200 GB to the run dir: check free space first.

**Experiments, in order**
1. Threads: `--threads 32` (all logical). The runner default is 30, so this is ~free here (MACS2 gained 1.44x
   from 30 -> 72 only because 30 left most of its cores idle).
2. Scoring lanes `-ParallelFilesScoring 2 / 3 / 4` (threads divide by lanes). MACS2 plateaued at ~2.2x once all
   cores were busy - the i9 is already near that, so look for 5-15%, and watch memory (~10-15 GB per lane).
3. Re-scoring lanes `-ParallelFilesRescoring 2 / 4` - lighter per file; probably the i9's best remaining lever.
   It also sets Stage 7's per-run fold width (MACS2 SecondPassFDR halved at 8 lanes).
4. FirstPassFDR lanes: default resolver = min(threads/2, free RAM / 7.4 GB, 8). Try `OSPREY_FDR_FILE_LANES=12/16`
   only if RAM allows (~7.4 GB per lane on SEA-AD). MACS2: 16 best, 24 worse (queued on the read gate).
5. GC heaps: Server GC defaults to one heap per logical CPU (32 here). Try `DOTNET_GCHeapCount=24` (physical
   cores, 8P+16E) and `16`. MACS2 (2 sockets, 72 heaps): 36 heaps cut FirstPassFDR ~20% and made it repeatable;
   on scoring the effect was lost in noise. One socket -> expect smaller; possibly none.
6. Keep `OSPREY_BLOCK_READ_GATE` ON - off cost +11% on MACS2's RAID with warm files; on an HDD it should be worse.
7. Then one full run with the best per-stage values; compare per task (`[TASK] X:done (Ns)`) with the 4:12 run.

Record results under the Progress Log as "i9 128 GB tuning", with the same per-task table shape.

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

### 2026-10-06/07 night - MACS2 FirstPassFDR sweep: 16 lanes + 36 GC heaps = 970 s (-21%)

`--task FirstPassFDR -LinkFrom <fast1> -Fresh --threads 72`, PR #4780 build, one leg at a time
(`sea-ad\runs\fdr-sweep-20261006\sweep-summary.log`; per-leg run dirs beside it; script
`.tmp/sessions/20261006-night/Run-FdrSweep.ps1`). Every leg reads the same 271.8 GB (104,210 block reads).

| leg | FDR lanes | read gate | GC heaps | FirstPassFDR | read / gate wait (summed) |
|---|---|---|---|---|---|
| l8 (COLD cache - discard) | 8 | on | 72 | 1,582 s | 529 / 2,159 s |
| l8w | 8 | on | 72 | 1,474 s | 193 / 67 s |
| l16 | 16 | on | 72 | 1,227 s | 182 / 293 s |
| l24 | 24 | on | 72 | 1,326 s | 257 / 1,101 s |
| l16g0 | 16 | OFF | 72 | 1,357 s | 252 / 0 s |
| l24g0 | 24 | OFF | 72 | 1,339 s | 323 / 0 s |
| l16h8 | 16 | on | 8 | 1,027 s | |
| l16h16 | 16 | on | 16 | 1,099 s | 126 / 186 s |
| **l16h36** | 16 | on | **36** | **970 s** | |
| l24h16 | 24 | on | 16 | 1,040 s | |

- 16 lanes > 8 (the `FdrLaneResolver.MAX_LANES` cap) > 24; past 16 the lanes queue on the read gate.
- The block-read gate HELPS even with warm files: off cost +11% at 16 lanes (more total read time).
- **Server GC heap count is the biggest lever**: 72 heaps (default, one per logical CPU on this 2-socket
  box) -> 36 (one per physical core) cut 21% at 16 lanes; 8 and 16 also beat 72.
- The FIRST leg of any sweep reads cold (the previous sweep evicted the files): l8 paid 336 s extra read.
- Scoring check (8 files, 4 lanes; `scoring-sweep-20261006`): p4r 664 s, p4h16 498 s, p4h36 506 s - but the
  box was CONTENDED by another user (p4r coelution 24k cand/s per lane vs 48k at 18:05 for the identical
  config), so only the relative order holds: fewer heaps did not hurt scoring and probably helped.
- Single rep per leg throughout; noise unmeasured. One 2-socket NUMA box: the i9s have 32 heaps by default.
- Applied: full run `-fast2` (01:03:55) = fast1 + `OSPREY_FDR_FILE_LANES=16` + `DOTNET_GCHeapCount=36`.

**Replicated (04:00-05:16)**: r16a 1,528 s (COLD, read 775 s - discard), r16b (36 heaps) 980, r16a2 (72) 1,047,
r16b2 (36) 990. So 36 heaps: **970 / 980 / 990 s** (three runs within 2%); 72 heaps warm: 1,047 / 1,227 s.
The heap-count win for FirstPassFDR is real and repeatable (-6% to -20%, and far less variable).

**Full runs with the best FDR settings were NOT faster end to end - the shared box's noise dominates:**
- `-fast2` (01:03:55 -> 03:22:52): **2 h 18 m 51 s** (8,330.6 s), exit 0, 6,654 protein groups. Per task vs
  fast1: scoring 4,408.6 (+19%), FirstPassFDR 1,288.8 (+5%; 16 lanes confirmed in the log), rescoring 1,971.0
  (-3%), SecondPassFDR 658.9 (-18%). Coelution per lane was 15-20% lower in every 10-file bucket.
- Heap A/B on scoring (8 files, 4 lanes, warm-up leg first; `scoring-sweep-20261006`): 72 heaps 356 / 475 s,
  36 heaps 359 / 315 s. The SAME config spread 356-475 s within 15 minutes: other users' load (invisible to
  us) is larger than any heap effect on scoring, so fast2's slow scoring cannot be pinned on the heaps.
- `-fast3` (05:17:08, repeat of fast2) **FAILED at 06:33:13: D: full** ("There is not enough space on the
  disk" writing first-pass intermediates after PerFileScoring = 4,151.8 s). Each full run writes ~200 GB;
  this session's runs reached ~1.1 TB of D:. fast3's intermediates were deleted (150 GB), logs kept.
  Check free space before every full run (`Get-DiskUsage.ps1`, hard-link aware).

**Conclusions for MACS2**
- Stable gains: `--threads 72` + per-stage lanes (2:09 vs 4:19); FirstPassFDR 16 lanes + 36 GC heaps
  (~980 s vs ~1,220 s in isolation). The read gate stays on.
- Not established: that the full-run total improves beyond 2:09 - two runs of the same config took 2:09
  (fast1, 72 heaps) and 2:18 (fast2, 36 heaps), and scoring varies +-20% with other users' load.
- To measure MACS2 cleanly, the box needs to be quiet (or measure each config 2-3x and use the minimum).

**Candidate default-code changes (each needs its own A/B, incl. the i9s)**
1. `FdrLaneResolver.MAX_LANES` 8 -> 16, still bounded by threads/2 and free memory (64 GB i9 stays low).
2. Runner default `-Threads 30` -> all logical processors (no change on a 32-thread i9; 2.4x the cores here).
3. GC heaps: `System.GC.HeapCount` in runtimeconfig is one fixed number for every machine - unsuitable.
   First check whether .NET's adaptive heap sizing (DATAS) is active in Osprey's process; if it is off,
   enabling it may beat any fixed count. Otherwise runners/docs set `DOTNET_GCHeapCount` per machine.
4. Leave the block-read gate on (off cost +11% at 16 lanes, warm).

### 2026-10-06 (evening) - MACS2 tuned: 2 h 09 m with per-stage file parallelism

Brendan's results for the default-settings race: i9-14900 128 GB **4:12**, MACS2 4:19, i9-14900 64 GB
5:00. Goal set: a MACS2 configuration that beats the i9s.

**PerFileScoring sweep** (first 8 files, `--task PerFileScoring`, PR #4780 build `_bin\pr4780-c84de72a6e`,
fresh run dir per leg, box quiet; `sea-ad\runs\scoring-sweep-20261006\sweep-summary.log`):

| leg | threads | scoring lanes | caches | wall (8 files, incl. ~20 s library) |
|---|---|---|---|---|
| base | 30 | 1 | D: | 736 s |
| t72 | 72 | 1 | D: | 512 s |
| p4 | 72 | 4 | D: | 327 s |
| p8 | 72 | 8 | D: | 318 s |
| p8e | 72 | 8 | E: | 343 s |

Scoring is CPU-bound at a plateau: coelution throughput summed over lanes is ~95k cand/s for one file at
30 threads, ~212k (4 x 53k) at p4, ~208k (8 x 26k) at p8 - ~2.2x once all 72 logical (36 physical) cores
are busy, however they are split. Read gate wait 0 s. E: was no help.

**Full run `-fast1`**: same data / library / D: disks / analysis as the 12:51 baseline, PR #4780 build,
`--threads 72 --parallel-files-scoring 4 --parallel-files-rescoring 8`. 18:17:39 -> 20:27:19,
**2 h 09 m 36 s** (`Total pipeline: 7776.0s`), exit 0, 6,654 protein groups at 1% (same as baseline).

| task | baseline (s) | fast1 (s) | change |
|---|---|---|---|
| PerFileScoring | 8,162.9 | 3,715.6 | -54% (2.2x) |
| FirstPassFDR | 1,206.0 | 1,221.6 | 0% - already at the 8-lane cap |
| PerFileRescoring | 4,542.4 | 2,034.2 | -55% (2.2x) |
| SecondPassFDR | 1,653.3 | 800.9 | -52% (Stage 7 fold on 8 lanes + 72 threads) |
| **total** | **15,567.9** | **7,776.0** | **-50%** |

- Memory: private peak 59.7 GB (FirstPassFDR), PerFileScoring 57.7 GB, PerFileRescoring 35.2 GB.
  Two reporting gaps of exactly 30 s during FirstPassFDR candidate-peak scoring (19:22-19:23).
- Box load: CPU median 25.8%, p90 81%; >= 389 GB free.
- Run dir `D:\Users\brendanx\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-protein-compact-fast1`;
  launcher `.tmp/sessions/20261006-night/Launch-SeaAdFast.ps1`.

**Next on MACS2** (FirstPassFDR is now the largest unchanged cost, 16% of the run):
- FirstPassFDR lanes past the cap: `OSPREY_FDR_FILE_LANES=16` (MAX_LANES = 8 today).
- Rescoring lanes 4 vs 8 vs 16 - only 8 was tried; the scoring plateau suggests 4 may match it.
- `DOTNET_GCHeapCount` (72 Server GC heaps by default) on the lanes stages, per the caching sweep.

### 2026-10-06 - Planned
Created at handoff from the #4765 / #4777 session. **Next session handoff**: For detailed startup
protocol, read `ai/.tmp/handoff-20261006_osprey_seaad_benchmark_port.md` before starting work.
