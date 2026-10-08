# TODO-20261005_osprey_per_stage_parallel_files.md

## Branch Information
- **Branch**: `Skyline/work/20261005_osprey_per_stage_parallel_files` (worktree `pwiz-net10b` on MACS2)
- **Base**: `master` (retargeted 2026-10-08 after #4619 merged; started on `Skyline/work/20260612_net8_port`) - see "Base" below
- **Created**: 2026-10-05 (backlog item `TODO-osprey_parallel_files_scaling.md`, created 2026-10-04, adopted and widened)
- **Status**: Completed
- **Module**: `osprey`
- **PR**: [#4780](https://github.com/ProteoWizard/pwiz/pull/4780) (merged 2026-10-08)
- **Follows**: `ai/todos/completed/TODO-20261002_osprey_cold_window_reads.md` (#4767)

## Objective

`--parallel-files` is one number for three per-file stages that do not scale alike. Make each stage's
concurrency settable on its own, and make the one stage that ignores it (SpectraCache) honor it:

* `--parallel-files-caching`, `--parallel-files-scoring`, `--parallel-files-rescoring` override the shared
  `--parallel-files` for their stage only. With only `--parallel-files`, every stage shares it, exactly as
  today; it still works for any single `--task`.
* SpectraCache runs its files on `OrderedFileLanes.For` instead of a plain sequential loop.
* Answer the original backlog question with data: how much does each stage gain per machine, and where
  does memory start to cost time?

## Why: the three stages are limited by different things

| Stage | Limit | Per-file memory | Evidence |
|---|---|---|---|
| SpectraCache | Single-threaded vendor decode (~17 MB/s per file) | One parse buffer, a few GB | 2026-10-05 TDP-43 on MACS2, below |
| PerFileScoring | CPU, multi-threaded per file | ~10-15 GB | 128 GB i9 sweep, below: little gain past P~3-4 |
| PerFileRescoring | Different curve from scoring (Brendan, from another MACS2 session) | Smaller | To measure |

### SpectraCache, measured 2026-10-05 (MACS2, TDP-43, 163 Thermo `.raw` on E:, caches to D:)

`SpectraCacheTask.Run` is a plain `for` loop; its comment justifies sequential by "contention for the same
spindle". That assumption is wrong on SSD storage:

* One file at a time: file 1 cached in **167.6 s** at ~20 MB/s, CPU 4% -> ~7.7 h for 163 files.
* Sharded by hand into 8 runner processes (`Run-Tdp43.ps1 -Task SpectraCache -SkipFirstFiles 21*i
  -NumFiles 21`, shared `-CacheDir`): **2 h 08 m wall** (16:51:02 -> 18:59:41), all 163 caches
  (553.9 GB, 27,550,939 MS2 records) PASSED `Test-SpectraCaches.ps1`. Shards took 5,597-7,718 s.
* **Speedup ~3.6x, not 8x.** Per-file time per shard rose from 168 s (alone) to ~350-370 s (8 at once);
  aggregate E: read was ~140 MB/s in the first minutes and ~102 MB/s averaged over the run. Contiguous
  blocks also left shard 7 (16 files) idle for its last ~35 min - lanes with one-at-a-time dispatch fix that.
* At 2 minutes in, E: did not look like the limit: queue length 0.8, read latency 0.4 ms, 59 KiB reads,
  43% idle, CPU ~22%. So the per-file slowdown under concurrency is UNEXPLAINED - candidates: E: degrading
  as more of it is read concurrently, memory bandwidth / cache contention in the decoders, the Thermo
  reader's own locking. Measure lanes 1/4/8/16 and E: vs D: inputs before claiming a scaling curve.
* The cache is built in memory and written in one burst per file (2.10 GB in ~2 s to D:), so a lane holds
  one parse buffer until its file saves.
* Run dirs: `D:\Users\brendanx\test\osprey-runs\tdp43\runs\tdp43-*e2d-cache*`; caches in
  `D:\Users\brendanx\test\osprey-runs\tdp43\cache`. Storage background: `U:\docs\Machines\MACS2\disk-performance.md`.

### PerFileScoring, measured 2026-10-04 (128 GB i9, #4767's code)

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

## Where the count lives today (read 2026-10-05; updated for #4765 as merged)

**Since #4765 merged:** first-pass FDR has its own count, `RunPlan.FirstPassFdrLanes`, chosen by
`Osprey.Core/FdrLaneResolver.cs` from `--threads` / 2 and free memory over the largest file's row count,
capped at `MAX_LANES = 8`, overridable with `OSPREY_FDR_FILE_LANES`. Leave it alone here.
`RunPlan.FileLanes` - the rescore and second-pass per-file phases - is still `EffectiveFileParallelism`,
i.e. scoring's count. That is the coupling `--parallel-files-rescoring` breaks.

Earlier reading (on `e3c823a92b`, still accurate for the per-file stages):

* Parsed in `Osprey/OspreyCommandArgs.cs` (`OspreyArgNames`), stored on `OspreyConfig`; an environment
  fallback in `OspreyEnvironment` applies only when the argument is absent.
* Resolved ONCE, in `PerFileScoringTask.ResolveFileParallelism` -> `FileParallelismResolver.Resolve`
  (`Osprey.Core/FileParallelism.cs`: explicit N, sequential default, or AUTO from free RAM / est. per-file
  bytes), and stored on `RunPlan.EffectiveFileParallelism`.
* `PerFileRescoreTask` REUSES that stored value (and divides `--threads` by it); it does not resolve its own.
* `RunPlan.FileLanes` (the FDR lanes, #4765) derives from it too - but #4765's decision moves the FDR lanes to
  a `--threads` + free-memory resolver, independent of `--parallel-files`. Keep that independence here.
* `SpectraCacheTask` ignores the count entirely (sequential `for`).

## Design

* **Precedence per stage**: stage flag > `--parallel-files` > the existing default (sequential, or AUTO when
  `--parallel-files` is given with no value). Each stage flag accepts the same forms as `--parallel-files`
  (N, or no value for AUTO).
* **One resolver, per stage**: `FileParallelismResolver.Resolve` gains a stage input (or callers pass the
  stage's requested value); each stage records its resolved count on `RunPlan` (one property per stage),
  replacing the single `EffectiveFileParallelism` that rescoring inherits from scoring today.
* **AUTO per stage**: the per-file memory estimate differs by stage (caching: one parse buffer; scoring:
  ~10-15 GB). Start with explicit values; per-stage AUTO estimates are a follow-up unless trivial.
* **Thread division**: scoring and rescoring divide `--threads` by their own lane count; caching's decode is
  single-threaded, so `--threads` is not divided there (check `EnsureSpectraCache`'s internal threading).
* **Logging**: each stage logs its resolved count AND its source (stage flag / shared flag / env / default)
  on a `[PATH]` line, so a run log always says how it ran.
* **Outputs never depend on it**: none of these flags may enter a validity key or change any output byte.
  1 lane == the plain loop.
* **SpectraCache on lanes**: `OrderedFileLanes.For` over the inputs. Per-file failure handling stays as is
  (one unreadable input logs and continues, but still fails the run - see the existing catch). The
  progress line should show the files in flight, as PerFileScoring's multi-progress does.

## Tasks

- [x] SpectraCache on `OrderedFileLanes.For`, honoring the shared count; 1 lane == today's loop
- [x] `--parallel-files-caching / -scoring / -rescoring` args (+ usage text, resx, `OspreyArgNames`)
- [x] Per-stage resolution and `RunPlan` properties; rescoring resolves its own instead of inheriting
- [x] Logging of count + source per stage (the existing `File parallelism: N (...)` line names the deciding flag)
- [x] Runner support: `-ParallelFilesCaching/-Scoring/-Rescoring` in `OspreyDatasetRun.psm1` + dataset wrappers
- [x] Docs: `pwiz_tools/Osprey/docs/20-command-line.md`, Help `CommandLine.html` (en; ja/zh-Hans need the
      translation flow)
- [x] Tests: arg precedence matrix (`OspreyCommandArgsTests`); SpectraCache 1 lane vs N lanes byte-identical
      caches; `SubsetPipelineTest` leg with different per-stage values producing identical outputs
- [x] Gates: Build-Osprey Debug -RunTests; `regression.ps1 -Dataset Stellar`; `regression-parallel.ps1 -Dataset All`
- [ ] Measure: TDP-43 SpectraCache at lanes 1 / 8 / 16 from E: on MACS2 (quiet box); scoring vs rescoring
      curves (see the sweep below) - DEFERRED: only 8 lanes measured (2 h 22 m, plus the GC heap-count legs)
- [x] `/code-review max`, then PR - #4780, retargeted to master after #4619 merged

## Base

Started stacked on #4765's tip (`e3c823a92b`) because `OrderedFileLanes` existed only there. #4765 then
merged (squash `f7021e609c`, carrying more than `e3c823a92b`: `FdrLaneResolver`, `BlockReadStream`, ...),
and the port branch itself was REBASED at the same time (forced update `aae172e475...2937deaae8`; e.g.
#4715 is now `ec10fd3f95`). The branch had no commits of its own, so it was repointed at the port tip
`2937deaae8` (`git checkout -B`); the remote copy needed one force-push (no PR existed). #4765 also closes
`ai/todos/active/TODO-20260930_osprey_parallel_files_static_partitioning.md`.

Related: `ai/todos/active/TODO-20260908_osprey_parallel_files_cache_sizing.md` (AUTO mode ignored memory
on cache-only cohorts) is code-complete on a LOCAL branch on MACS2 based on master. Its fix lives in
`FileParallelismResolver`, which this work touches - port it first or fold it in.

## Measurement plan carried from the backlog item

### The 64 GB i9 sweep (PerFileScoring)

Same sweep, same data, to see whether it reproduces or hits a memory slowdown before P=4.

1. Pull pwiz-ai; check out (or build) the port branch at or after #4767 (`12a0431bbe`); build Release and copy
   `pwiz_tools\Osprey\Osprey\bin\x64\Release\net10.0` to a snapshot dir.
2. SEA-AD caches (`.spectra.bin`) and the library must be present; the runner resolves the data dir from its env
   var (see `ai/scripts/Osprey/SEA-AD/README.md`). Run `Run-SeaAd.ps1 ... -WhatIf` first.
3. Make sure nothing else uses the disk (SkylineTester, other runs) and launch detached:
   `Start-Process pwsh -WindowStyle Hidden -ArgumentList '-NoProfile','-File','C:/proj/ai/todos/active/TODO-20261005_osprey_per_stage_parallel_files/Run-ParallelFilesSweep.ps1','-Exe','<snapshot>\Osprey.exe','-LibraryDir','<lib dir>','-RunsDir','<runs dir>','-LogMemory'`
   (~2.5 h). `-LogMemory` adds post-GC probes: pre-GC peaks include garbage, and Server GC behaves
   differently with less headroom.
4. Check each leg's `run.log` for the `Window reads (DIAGNOSTIC)` line where a switch is set.

What to look for:
- **Memory pressure on the file cache**: calibration reads each cache cold, then first-pass scoring re-reads it
  from the file cache. At P files, the process (~30-50 GB) plus P caches (~4.4 GB each) may not fit in 64 GB;
  scoring then reads cold with PARALLEL LoadWindow (the seek-heavy pattern). Tell: disk read rate during the
  "Scoring isolation windows" phase and a jump in per-file scoring time at P=3 or P=4.
- Paging (Available MBytes near zero) and peak/floor from perfviz per leg.

### Later
- Stage 6 with P (`-Task PerFileRescoring -LinkFrom <completed run>`), separately from Stages 1-4 - the
  rescoring curve this work's `--parallel-files-rescoring` is for.
- Repeat the P=4 per-file vs process-wide lock legs to see if the -16% vs -8% difference is real; if it is,
  consider the process-wide lock as the default under --parallel-files.

## Progress Log

### 2026-10-05 - adopted from backlog, branch created
- Brendan proposed per-stage `--parallel-files-*` flags after the TDP-43 SpectraCache run showed caching
  scales differently again (sequential by design; 8 hand-made shards ran ~5x faster with E: still 43% idle).
- Branch created from #4765's tip `e3c823a92b` in `pwiz-net10b`. No code yet.
- #4765 merged the same day; branch repointed at the (rebased) port tip `2937deaae8`. Still no code.
- The hand-sharded TDP-43 caching finished: 2 h 08 m, 163/163 caches verified, ~3.6x over sequential
  (not the ~8x the first minutes suggested). The per-file slowdown under concurrency is open.

### 2026-10-06 (00:30) - #4778 merged; SpectraCache lanes coded (uncommitted); ONE PR decided

- #4778 (cache-only auto sizing, a prerequisite touching `FileParallelismResolver`) merged as
  `cc6e7040ca`; this branch repointed at that port tip and force-pushed to match (no commits of its own).
- **Decision: one PR** - SpectraCache on lanes AND the per-stage flags together; the flags are what make
  the caching lanes controllable, and both touch the same resolution code.
- Coded, NOT yet built or tested, uncommitted in `pwiz-net10b`:
  * `SpectraCacheTask.Run` -> 1 lane = the plain loop; N lanes = numbered legend +
    `OrderedFileLanes.For` + `MultiProgressReporter.BeginFile(fileIdx, 1)` + `BeginSegment()`; per-file
    body extracted to `CacheFile(ctx, fileIdx, nFiles)`; `built` counted with `Interlocked`. The read gate
    stays OFF (`EnsureSpectraCache(inputFile, false, ...)`) - gating would serialize the lanes.
  * Lane count from `PerFileScoringTask.ResolveFileParallelism` (made internal) - to be replaced by the
    per-stage `--parallel-files-caching` resolution. Its sequential-default log line says "to score" -
    reword when the per-stage messages land.
  * New resource `SpectraCacheTask_Run_Caching__0__files___1__at_a_time_` (resx + Designer, English only;
    `OspreyLocalizedResourcesTest` skips keys a satellite lacks).
  * `SubsetPipelineTest`: after the existing spectra-cache leg, a `--parallel-files <runs>` leg asserting
    the legend line and byte-identical caches vs the one-lane run.
- TDP-43 caches copied D: -> E: (`robocopy /J /MT:8`, 553.9 GB in 3 h 42 m, 44.7 MB/s) and verified
  163/163 against the `.raw` files in `E:\...\tpd43-plasma-ev\raw`. The `.raw` files are NOT deleted
  (awaiting Brendan); the D: copies in `D:\Users\brendanx\test\osprey-runs\tdp43\cache` are kept until a
  search has read from E:.

### 2026-10-06 (night session) - PR #4780 opened; TDP-43 re-cached on 8 in-process lanes

- Commits: `4bebdc8f3e` SpectraCache lanes; `48a6706364` per-stage flags; `2b1984e1ad` review fixes
  (`/code-review max 4780`: 15 findings, 11 fixed, 4 dropped - pre-existing zero-MS2 cache left on
  disk, decision-line placement, progress display at 100% during a lane's write, unstamped lane blocks).
- Review fixes worth knowing: `--parallel-files* 0` is now an explicit 1 (the sequential default yields
  to `OSPREY_MAX_PARALLEL_FILES`, an explicit "off" must not); the env cap no longer applies to caching
  (Test-PerfGate -SplitSpectraCache sets it); mzML parses on caching lanes still take the read gate;
  `SystemMemory` forces a gen0 GC before its first reading (it reported all RAM free at startup);
  auto re-scoring keeps scoring's count rather than re-probing lower.
- **TDP-43, 163 Thermo .raw on E: -> D:\...\tdp43\cache-lanes8, ONE process, `--parallel-files 8`,
  exe `_bin\26.1.1.279-4bebdc8f3e-vendor-4bebdc8f3e`**: 00:25:42 -> 02:47:59, **2 h 22 m 12 s**
  (`[TIMING] Total pipeline: 8532.4s`), exit 0. 163/163 PASSED `Test-SpectraCaches.ps1`, 27,550,939
  MS2 records (same as the hand-sharded set). Per file: min 295 s, median 410 s, max 532 s
  (alone: 167.6 s -> 2.45x slower per file at 8 lanes). Speedup ~3.2x over sequential (27,320 s est.).
  E: read mean 84.5 MB/s (max 147), queue 0.58, 0.36 ms/read; D: write mean 58 MB/s; >= 349 GB free.
  Box otherwise idle, except two ~5 min Debug build+test overlaps (~00:33 and ~01:57).
- **In-process lanes were ~10% SLOWER than 8 hand-sharded processes** (2 h 08 m, 7,719 s). Sample at
  ~00:45: 5.4-7.5 cores busy, decode threads 68-84% each, kernel time only 0.35 cores, ~70 server-GC
  threads ~2% each, process WS ~40 GB. So the per-file slowdown is user-mode work, not disk or page
  zeroing; candidates: memory-bandwidth/cache contention in the decoder, Server GC over one shared
  40 GB heap (separate processes each had their own). Not yet discriminated.
- Logs: run dir `D:\Users\brendanx\test\osprey-runs\tdp43\runs\tdp43-163files-libdecoy-r1.0-protein-compact-lanes8\run.log`;
  `runs\launch--lanes8-20261006_002542.log`; 30 s samples `runs\iosample--lanes8-*.csv`.
- Runner: `-ParallelFilesCaching/-Scoring/-Rescoring` in `OspreyDatasetRun.psm1` + the three wrappers.
- Regression gates on `2b1984e1ad`: Stellar 5/5 PASS; `regression-parallel.ps1 -Dataset All` 48 PASS /
  0 FAIL / 0 SKIP in 39 m 29 s. TeamCity Perf/Regression NOT triggered (Brendan's call).
- The session hit the Max 5x usage limit after ~04:08; the sweep below finished unattended.

#### Caching lane sweep: where the in-process 10% went (MACS2, 03:36-04:08)

Same first 8 TDP-43 `.raw` files (E: -> scratch on D:, deleted after each leg), one leg at a time, box
otherwise idle, exe `_bin\26.1.1.279-4bebdc8f3e-vendor-4bebdc8f3e`. Script:
`ai/.tmp/sessions/20261006-night/Run-CacheLaneSweep.ps1`; results
`D:\Users\brendanx\test\osprey-runs\tdp43\runs\sweep-20261006\sweep-summary.log` (per-leg run dirs beside it).

| Leg | 8 files wall | vs default |
|---|---|---|
| solo: 1 file, 1 lane | 152 s (one file) | - |
| lanes8: 8 lanes, Server GC default (72 heaps) | 505 s | - |
| wksgc: 8 lanes, `DOTNET_gcServer=0` | 435 s | -14% |
| heaps8: 8 lanes, Server GC, `DOTNET_GCHeapCount=8` | **400 s** | **-21%** |
| procs8: 8 processes x 1 file | 404 s | -20% |

- **The in-process gap is the GC's heap count, not lanes:** 8 Server GC heaps match 8 processes exactly.
  Even workstation GC beat the 72-heap default - the opposite of Skyline's history, where workstation
  GC was the bottleneck and Server GC was what closed the gap to multi-process.
- **The ~2.6x per-file slowdown under concurrency is NOT GC** (400 s for 8 vs 152 s alone in every
  8-at-once leg, separate processes included): it is in the vendor decode or the memory system.

**Limits of this result - read before acting on it:**
- **One rep per leg.** Noise is unmeasured; the 400 vs 404 tie and the 14% / 21% steps could move.
- **One machine, and an unusual one:** MACS2 is 2 sockets x Xeon Gold 6354 (18C/36T each, 72 logical,
  2 NUMA nodes, 2 Windows processor groups). Server GC's default is one heap (and one GC thread) per
  logical processor, so 72 here; cross-socket heap traffic and 72-way GC thread coordination are
  plausible parts of the cost. Whether it transfers to a single-socket i9 (e.g. i9-14900K: 32 logical,
  one NUMA node, hybrid P/E cores -> 32 heaps) is UNKNOWN - expect a smaller effect, but measure.
- **One workload:** 8 single-threaded Thermo decodes allocating multi-GB spectrum lists. The scoring
  stage allocates from 30+ threads and may WANT many heaps - do not generalize `GCHeapCount=8` to the
  scoring or re-scoring stages without their own A/B.
- **8 lanes only.** Not measured: heap count = lanes at 4 / 16, `GCHeapAffinitizeMask`, or
  `DOTNET_GCConserveMemory`. Heap count cannot change at run time, so acting on this means an env var
  or runtimeconfig setting chosen per process (e.g. the runner setting `DOTNET_GCHeapCount` for
  `-Task SpectraCache` runs), not a code change inside one process.
- **Next measurement:** repeat solo / lanes8 / heaps8 / procs8 with 3 reps on MACS2, then on an i9
  with any vendor `.raw` set (the script's paths are MACS2-specific; parameterize DataDir/RunsRoot).

### 2026-10-08 - Merged

#4619 (the .NET 10 port) merged into master first, so the PR was retargeted from the port branch to
master: `git merge -X renormalize origin/master` into the branch was conflict-free and left exactly the
PR's 26 Osprey files as the difference (655/655 unit tests on the merged tree). TeamCity passed and the
branch had been tested on two other machines; merged by admin override of the review requirement.
PR #4780 merged as commit `011dfc9ff2`. Shipped: `--parallel-files-caching`, `-scoring` and
`-rescoring` overriding `--parallel-files` per stage (absent / bare = auto / N; `0` = an explicit single
lane), each stage resolving and logging its own count (re-scoring no longer inherits scoring's),
SpectraCache on `OrderedFileLanes.For` with byte-identical caches, the runners' per-stage switches, and
docs. Deferred: the lanes 1 / 16 points of the caching curve, the scoring-vs-rescoring curves, and acting
on the GC heap-count finding (Server GC with 72 heaps cost 21% at 8 caching lanes; one rep, one machine).
No issues filed.
