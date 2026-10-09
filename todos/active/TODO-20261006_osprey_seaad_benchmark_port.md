# TODO: SEA-AD 82-file benchmark of the port branch at default settings (three machines)

## Branch Information
- **Branch**: `Skyline/work/20261007_osprey_fdr_lanes_gc` (pwiz-work1) - the FirstPassFDR lane fix this
  benchmark found. Originally a measurement of `Skyline/work/20260612_net8_port`.
- **Base**: `master` (PR #4619 merged 2026-10-08 as `156dab478b`; the fix was rebased onto master as `e703a48580`)
- **Created**: 2026-10-06
- **Status**: Lane fix MERGED (#4804, 2026-10-09). Benchmark TODO stays active for the UW8 128 GB tuning
  handoff below and the cross-machine identical-results check.
- **Module**: `osprey`
- **PR**: [#4804](https://github.com/ProteoWizard/pwiz/pull/4804) (merged 2026-10-09 as `4f4c74ea66`)

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

- [x] Build Release from the port tip in `C:\proj\pwiz-work1`, snapshot to `D:\test\osprey-runs\_bin\port-<sha>`
- [x] `Run-SeaAd.ps1 -WhatIf` with runner defaults (libdecoy, r1.0, protein-compact, threads 30,
      ParallelFiles 0, model diagnostics on) and `-Exe <snapshot>`; confirm cached mzML + .spectra.bin
- [x] Full run, uncontested (see the nightly constraint below)
- [x] Harvest per the SEA-AD README: perfviz (peak fits 64 GB, no gap >= 30 s), entrapment FDP tools
- [x] Per-task and per-phase table vs the reference; FirstPassFDR lane decision line; peak private
- [ ] Record results here (i9 done); compare with Brendan's other two machines when available
- [x] FirstPassFDR lanes: `-LinkFrom` A/B at `OSPREY_FDR_FILE_LANES=1/2/3/4`, then the collect-before-measure
      fix (#4804, merged)
- [ ] Cross-machine identical-results check: one exe snapshot on UW8 + UW25, diff `out.blib` and pass counts

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

### 2026-10-08 - MACS2 CHS 446 first full run: 9 h 34 m

19:48:45 -> 05:22:52, **9 h 34 m 30 s** (`Total pipeline: 34470.3s`), exit 0, 5,573 protein groups at 1%.
Settings as launched (below): caches on E:, outputs on D:, threads 72, scoring 4 / rescoring 8 lanes,
FDR 16 lanes, 36 GC heaps.

| task | CHS 446 (s) | per file | SEA-AD 82 fast1 (s) | per file |
|---|---|---|---|---|
| PerFileScoring | 22,105.1 (6 h 08 m) | 49.6 s | 3,715.6 | 45.3 s |
| FirstPassFDR | 4,660.2 (1 h 18 m) | 10.4 s | 1,221.6 | 14.9 s |
| PerFileRescoring | 5,265.1 (1 h 28 m) | 11.8 s | 2,034.2 | 24.8 s |
| SecondPassFDR | 2,423.5 (40 m) | 5.4 s | 800.9 | 9.8 s |
| **total** | **34,470.3** | | **7,776.0** | |

- The i9's CHS reference (README): first FDR pass 4 h 46 m, second 69 min - MACS2 1 h 18 m and 40 min.
- Memory: private peak 116.8 GB (FirstPassFDR, 16 lanes x 446 files), PerFileRescoring 70.1 GB, scoring
  55.2 GB, SecondPassFDR 59.2 GB; floors FALLING; >= 348 GB free throughout.
- 10 reporting gaps of 30-58 s, all inside FirstPassFDR's 1.34 B-candidate Percolator scoring (progress
  granularity at this scale, not stalls).
- E: as the input disk: read mean 62 MB/s (max 640), 0.16 ms mean / 6.1 ms max per read - no sign of the
  post-write collapse. Box CPU median 49%, p90 92% (includes other users).
- Coelution averaged 22.7k cand/s per lane vs ~51k on SEA-AD - but per-file scoring time is similar
  (49.6 vs 45.3 s), so CHS files simply carry more/costlier candidates; not comparable across datasets.
- Run dir `D:\Users\brendanx\test\osprey-runs\chs-seer\runs\chs-446files-libdecoy-r1.0-protein-compact-fast`;
  samples `chs-seer\runs\iosample-chs446-fast-20261007_194815.csv`.

### 2026-10-07 - MACS2 input disk A/B (cold reads): E: beats D:; CHS 446 launched reading from E:

Every SEA-AD run above read its caches from D: - and with ~420 GB of file cache vs 346 GB of SEA-AD caches,
much of fast1's input likely came from RAM. CHS (1,168.5 GB of caches) cannot fit on D: beside its ~1.1 TB of
output, so the inputs must come from E:. A/B: 8 SEA-AD files, `--task PerFileScoring`, fast1 settings,
outputs on D:; each leg read its OWN fresh unbuffered (`robocopy /J`) copy so no leg started in the file cache
(session not elevated - cannot purge the standby list). `sea-ad\runs\ab-cold-20261007\ab-summary.log`.

| leg | input | PerFileScoring | cal pass 1 mean (read-heavy) | coelution (CPU) |
|---|---|---|---|---|
| d1 / d2 / d3 | D: fresh copy | 524 / 464 / 479 s | 54.9 / 56.3 / 72.7 s | 35k / 42k / 48k |
| e1 | E: fresh copy | 429 s | 44.6 s | 42k |
| e3 | E: original (settled) files 9-16 | 419 s | 47.5 s | 49k |
| e2 | E: fresh copy, right after 1.2 TB of writes | 1,298 s | 477.9 s | 45k |

- E: is ~13% faster than D: overall and ~25% faster in the read-heavy phase (e3: E: reads to 329 MB/s, <= 0.5 ms).
- e2: E: reads collapsed (cal 130-165 s, then ~800 s per file) while CPU was normal - transient, right after
  the CHS copy (1.2 TB) plus 64 GB of A/B copies onto QLC drives. 90 min later a cold sequential read gave
  143-164 MB/s per file and e3 was the fastest leg. **Let E: settle after large writes before a timed run.**

**CHS copy**: 446 caches U: (Nexus) -> E: with `.tmp/sessions/20261006-night/Copy-ChsCaches.ps1` (unbuffered
robocopy passes of finished files only), 08:21 -> 18:10, avg 36 MB/s (E: QLC write-bound; network had headroom).
446/446 structurally valid, 84,323,746 MS2, every size equal to the Nexus copy.

**CHS 446 run launched 19:48:45** (`.tmp/sessions/20261006-night/Launch-Chs.ps1`): PR #4780 build, caches on
E:, run dir `D:\Users\brendanx\test\osprey-runs\chs-seer\runs\chs-446files-libdecoy-r1.0-protein-compact-fast`,
library 20260817, `--threads 72`, scoring 4 lanes, rescoring 8 lanes, `OSPREY_FDR_FILE_LANES=16`,
`DOTNET_GCHeapCount=36`. Inputs via `--input-list` (the runner now falls back to it past 24,000 chars; -i
would have been 35,458 > 32,767). Estimate ~11 h (fast1 x 5.4); i9 reference for its first FDR pass: 4 h 46 m.

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

### 2026-10-06 - Launched (i9, 64 GB)
- The port branch had been force-pushed AGAIN since the handoff: local `dfcb8d17ef` was ahead 42 /
  behind 80. Its tree is identical to origin's `7028447045` (#4777), so the content was already
  upstream. With Brendan's OK: saved it as `backup/net8_port-pre-rewrite-20261006` in pwiz-work1,
  then `reset --hard` to origin. The tip is now `490a4d3825`, which adds #4779 (scan-major
  first-pass fragment matching), #4778 (`--parallel-files auto` sizing) and #4781 (median polish
  / SG cosine on the m/z index). **So this measures #4765/#4767/#4777 plus #4779/#4781**, and
  PerFileScoring is expected to move too.
- Exe snapshot: `D:\test\osprey-runs\_bin\port-490a4d3825` (Osprey v26.1.1.279).
- To match the reference, data and library are passed explicitly: `-DataDir D:\test\osprey-runs\sea-ad\mzml`,
  `-LibraryDir ...\lib\target+decoy+entrapment-20260817-ungated`. This shell had no
  `OSPREY_SEAAD_DIR` set. 82/82 `.spectra.bin` present. No `OSPREY_*` tuning vars set (only
  `OSPREY_TEST_BASE_DIR`).
- Box quiet (no TestRunner/SkylineNightly). Ran `Clear-StandbyCache.ps1` first. Started 12:27:46,
  so at ~6-8.5 h it should finish before the ~21:50 nightly. Nightly not skipped.
- Run dir: `D:\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-protein-compact-port-490a4d3825-bench-20261006_122746`
  (`run.log`); console: `ai/.tmp/sessions/20261006-55ccd0be/seaad-bench.console.log`.
- Early PerFileScoring pace (from `Scoring file N/82` timestamps): file 19 started at +30:04 vs
  +47:14 in the reference; files 15->19 took ~107 s/file vs ~160 s/file. That is ~33% faster
  (#4779/#4781 are the likely cause). Projected PerFileScoring is ~8,100 s vs 12,695 s; confirm at the end.
- **PerFileScoring done: 8,297.3 s vs 12,694.6 s (-34.6%)**, at 14:46:03.
- **FINDING - FirstPassFDR picked 1 lane, a near-miss on 2**: `First-pass FDR file lanes: 1 (limited
  by memory; 30 threads, 29.3 GB free, 7.4 GB per lane, 82 files)`. In `FdrLaneResolver`, 2 lanes need
  2 x 7.4 / `RAM_BUDGET_FRACTION` 0.5 = 29.6 GB free. The 7.4 GB comes from ~4.97 M rows in the largest
  file x 1,600 B. The figure is 0.3 GB short. `FirstPassFdrTask.ResolveFileLanes` reads
  `SystemMemory.AvailablePhysicalBytes()` with no collection first. In a straight-through run, the
  PerFileScoring heap is still resident at that moment: memstamp read 13.3 / 22.0 GB, while the first column's
  floor during the last scoring files was ~8 GB. So reclaimable garbage was very likely counted as
  used. Candidate fix: a blocking compacting `GC.Collect` before measuring. It is cheap once per run,
  and memory-band-guide's post-GC probe uses the same idea. Also recheck the 0.5 fraction now that
  SEA-AD rows are ~1.6x CHS. CHS 446 got 3 lanes on this box. Judge the impact by FirstPassFDR wall time
  vs a forced `OSPREY_FDR_FILE_LANES=2`/`3` run (a later A/B with `-LinkFrom`).
- **FirstPassFDR done: 4,081.5 s vs 4,444.2 s (-8.2%)** at 1 lane, at 15:54:05. CHS improved much more
  (4.76 h -> 2.6 h) at 3 lanes, which fits the lane count being the limiter here.
- **PerFileRescoring done: 4,475.1 s vs 6,301.3 s (-29.0%)**, at 17:08:40.

### 2026-10-06 - i9 results (exit 0 at 17:27:56)

| task | this run (s) | reference (s) | change |
|---|---:|---:|---:|
| PerFileScoring | 8,297.3 | 12,694.6 | -34.6% |
| FirstPassFDR | 4,081.5 | 4,444.2 | -8.2% (1 lane) |
| PerFileRescoring | 4,475.1 | 6,301.3 | -29.0% |
| SecondPassFDR | 1,155.7 | 1,263.6 | -8.5% |
| **total** | **18,009.6 (5 h 00 m)** | **24,703.7 (6 h 51 m)** | **-27.1%** |

- perfviz: private peak 29.3 GB (ref 25.7), FirstPassFDR peak 23.7 GB, floor FALLING, **0 gaps
  >= 30 s** (max 23 s; the reference had 2).
- Entrapment: pass 1 experiment n at true FDP <= 1% 46,183 vs 46,458 (-0.6%), at <= 0.75% 42,723 vs
  43,620 (-2.1%); pass 2 FDP at reported q 1% 1.606% vs 1.745%; >= 41-run peptides 0.24% vs 0.21%.
  The discovery set moved slightly; the change is not attributed (the reference exe was `13373c6b4f-dirty`).
- Full write-up: `<run dir>\FINDINGS.md`; reader outputs in `<run dir>\harvest\`.

### 2026-10-07 - vs BRENDANX-UW8 (i9-14900K, 128 GB): 4 h 12 m vs 5 h 00 m
Cross-machine write-ups: `M:\home\brendanx\docs\Machines\BRENDANX-UW25\README.md` (corroboration
log) and `..\BRENDANX-UW8\osprey-performance-vs-uw25.md`.
- ~80% of the 2,870 s gap is **FirstPassFDR lanes**: UW8 had 5 (81.7 GB free), we had 1. The stage took 1,742 vs 4,082 s.
  This raises the priority of the lane-resolver fix above.
- About 800 s is coelution scoring at UW8's higher sustained clock (4.73 vs 2.55 GHz on the scalar
  test; scoring only 1.25x faster). Calibration pass 1 scoring is identical on both machines
  (~2,035 s): it streams the `.spectra.bin` at ~190 MB/s, so it looks HDD-bound (hypothesis).
- The libraries match in size (6,174,152 vs 6,175,389). Both machines read from a SATA HDD.
- **But they are different libraries**: UW8 used Mike's `-20260817` delivery, which the README calls standard.
  Our `-ungated` is our own Carafe rebuild (same FASTA, our spectra/RT, no similarity gate; see
  `TODO-20260801_decoy_similarity_gate.md`). The timing comparison stands, but ID counts do not compare.
  Proposed to Brendan: make the runner default the canonical library and print a library
  fingerprint in the banner and START line. Pending his answer.

### 2026-10-07 - FirstPassFDR lane A/B (`--task FirstPassFDR -LinkFrom <bench run>`)
Added `-FdrFileLanes N` to `Run-SeaAd.ps1` / `OspreyDatasetRun.psm1` (exports `OSPREY_FDR_FILE_LANES`,
stripped otherwise; banner, START/DONE `fdrlanes=`, dir suffix `-fplanes<N>`). Standby cache cleared before each arm.

| arm | lanes | free at decision | FirstPassFDR s | private peak | run dir suffix |
|---|---:|---:|---:|---:|---|
| straight-through bench | 1 (resolver) | 29.3 GB | 4,081.5 | 23.7 GB (stage) | `port-490a4d3825-bench-20261006_122746` |
| task, auto | 3 (resolver) | **44.6 GB** | **2,050.5** | 23.9 GB | `fp-lanes-auto-20261007_142425` |
| task, forced | 1 | - | 3,298.2 | ~19.9 GB (phase peak) | `fplanes1-20261007_145905` |
| task, forced | 2 | - | 2,244.2 | 23.1 GB | `fplanes2-20261007_155542` |
| task, forced | 4 | - | 2,011.0 | 28.5 GB, **2 gaps 30-32 s** | `fplanes4-20261007_163315` |

- **Knee at 3 on this box (one HDD)**: 1->2 -1,054 s, 2->3 -194 s, 3->4 -39 s, with +4.6 GB and two
  reporting gaps (32 s in pass-1 scoring at 16:41:21, 30 s in in-order recon planning at 17:00:07). The
  resolver's existing formula gives exactly 3 at the correct free reading (44.6 x 0.5 / 7.4). **So no
  leniency change. The fix is to read free memory after a collection.**
- Fix on branch `Skyline/work/20261007_osprey_fdr_lanes_gc` (pwiz-work1, off port `e35b05852f`):
  `FirstPassFdrTask.ResolveFileLanes` runs `GC.Collect(MaxGeneration, Aggressive, blocking, compacting)` +
  `GC.Collect(0)` before `SystemMemory.AvailablePhysicalBytes()`, and only when no lane override is set
  and there is more than 1 file. It does not touch `SystemMemory.cs` (#4780 edits it).
- Local commit `3db02e8720` (not pushed). Debug build, 655/655 unit tests and inspection pass;
  `regression.ps1 -Dataset Stellar` PASSED.
- **Verification run (nightly turned off by Brendan)**: full straight-through 82 files, started 2026-10-07 ~17:15,
  exe `_bin\fdrlanes-gc-3db02e8720` (v26.1.1.280), **canonical library `-20260817`** (via the new default,
  byte-verified), runner defaults. Pass criteria: lane line ~44 GB free -> 3 lanes, and FirstPassFDR near
  2,050 s rather than 4,082 s. This is also UW25's first run that is directly comparable with UW8.
  - PerFileScoring 7,321.0 s (UW8 7,205.5 on the same library; yesterday's `-ungated` run here 8,297.3 incl. a
    129 s libcache build).
  - **Lane line: `3 (limited by memory; 30 threads, 45.2 GB free, 7.4 GB per lane, 82 files)`.** The collections
    took ~2 s (19:17:23 -> :25), and private memory fell 20.5 -> 5.9 GB across them. Fix confirmed straight through.
  - **FirstPassFDR 2,123.1 s vs 4,081.5 s yesterday (-1,958 s, -48%, ~33 min)**. It is within 73 s of the
    task-mode 3-lane run (2,050 s), so the leftover-heap penalty is gone too. UW8 at 5 lanes: 1,742.5 s.
  - PerFileRescoring 4,167.4, SecondPassFDR 938.2. **Total 14,550.2 s = 4 h 02 m** (UW8 4 h 12 m; 06 Oct here 5 h 00 m).
    Peak private 30.9 GB, 0 gaps >= 30 s. Pass 1 experiment: 46,815 at 1% q (combined FDP 0.762%), 48,772 at true
    FDP <= 1%. Write-up: `<run dir>\FINDINGS.md`, also copied to `M:\...\Machines\BRENDANX-UW25\seaad-82files-fdrlanes-gc-3db02e8720-20261007\`.
  - Run dir: `D:\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-protein-compact-fdrlanes-gc-3db02e8720-20261007_171521`
- **Next**: open the PR for `3db02e8720` against the port branch (`/code-review` first). Push the `ai/` runner
  changes (`-LibraryBuild` default 20260817, `LibraryFile:` fingerprint, `-FdrFileLanes`). Run the cross-machine
  identity check with one exe snapshot on UW8 + UW25.

- 1 -> 3 lanes in the same mode: -1,248 s (-38%), for ~+4.6 GB peak, i.e. ~2.3 GB per extra lane against
  the resolver's 7.4 GB estimate (~3x conservative for SEA-AD).
- **The straight-through 1-lane stage was 784 s slower than the task-mode 1-lane run** (4,082 vs 3,298 s).
  So entering FirstPassFDR with PerFileScoring's heap resident costs time even at a fixed lane count. Do not
  attribute that to lanes. A full GC at stage entry may recover it too. To verify straight through.
- Library check (2026-10-07 15:54): UW25's `target+decoy+entrapment-20260817` passed UW8's
  `verify-seaad-library.ps1`, **byte-identical** to the reference, although its mtime differs (08-18 vs 09-26).

- A fresh `--task` process sees ~15 GB more free than the straight-through run did at the same point. So the
  resolver's 1-lane choice came from PerFileScoring's leftover heap, not the cohort.

### 2026-10-08 - Rebased onto master; `/code-review max` applied
- #4619 merged (`156dab478b`), then #4780 (`011dfc9ff2`). Rebased the fix onto master (no PR yet, so allowed).
- `/code-review max`: 11 findings, triaged. **Fixed**:
  - The gen0 refresh can be turned into a background GC under DATAS (reproduced in a probe; one retry
    fixes it). It now repeats until the GC record is newer (max 3).
  - The collection now runs for every multi-file entry, including forced `OSPREY_FDR_FILE_LANES`, so
    forced-vs-auto lane A/Bs share the same memory state. This removed the `availableBytes = 0` placeholder.
  - The recipe moved into `SystemMemory.AvailablePhysicalBytesAfterCollect`, next to #4780's refresh.
  - The comment now pairs the right timings and names the real cause: committed-but-free heap, not a stale
    sample. Named GC arguments. Commit message cut to 10 lines.
  - Runner banner: "no [MEM]-probe GCs".
- **Dropped**:
  - cgroup 75% hard-limit under-read: an existing `SystemMemory` behavior, out of scope.
  - Skipping the collection when lanes cannot change: it conflicts with the forced-lane fix and costs ~2 s.
  - No unit test of collect-then-read ordering: GC timing is not meaningfully unit-testable; the SEA-AD
    lane line is the oracle.
  - Redundant GCs under `OSPREY_LOG_MEMORY`: profiling runs only.
- Not re-run at 82 files after the revision: the mechanism is unchanged (aggressive GC + gen0 refresh), and
  the retry only adds collections.

### 2026-10-09 - #4804 merged
PR #4804 merged (squash, `--admin` at Brendan's direction; CodeQL still running on the comment-only last
commit) as `4f4c74ea66`. It shipped `SystemMemory.AvailablePhysicalBytesAfterCollect` (an aggressive GC, then a
gen0 refresh repeated until newer) and FirstPassFDR calling it at every multi-file entry. On UW25 SEA-AD 82 files:
1 -> 3 lanes, FirstPassFDR 4,082 -> 2,123 s, whole run 5 h 00 m -> 4 h 02 m. Copilot's one finding (the
SystemMemory doc's zero-reading claim) was fixed in `4b06dc92cd`. The TODO stays in `active/` on purpose, because
the UW8 tuning handoff and the identity check are still open; it was not moved to `completed/`. The local branch
and remote branch were deleted after the ancestry check.
