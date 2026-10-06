# TODO-20261005_osprey_per_stage_parallel_files.md

## Branch Information
- **Branch**: `Skyline/work/20261005_osprey_per_stage_parallel_files` (worktree `pwiz-net10b` on MACS2)
- **Base**: `Skyline/work/20260612_net8_port` at `2937deaae8` (after #4765 merged as `f7021e609c`) - see "Base" below
- **Created**: 2026-10-05 (backlog item `TODO-osprey_parallel_files_scaling.md`, created 2026-10-04, adopted and widened)
- **Status**: In Progress - branch created, no code yet
- **Module**: `osprey`
- **PR**: (pending)
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
  -NumFiles 21`, shared `-CacheDir`): E: delivered **~140 MB/s aggregate**, CPU ~22%, ETA ~1.5 h.
* E: was NOT the limit: queue length 0.8, read latency 0.4 ms, 59 KiB reads, 43% idle. Each file is bound
  by its own single-threaded decode, so lanes should scale nearly linearly well past 8 here.
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

- [ ] SpectraCache on `OrderedFileLanes.For`, honoring the shared count; 1 lane == today's loop
- [ ] `--parallel-files-caching / -scoring / -rescoring` args (+ usage text, resx, `OspreyArgNames`)
- [ ] Per-stage resolution and `RunPlan` properties; rescoring resolves its own instead of inheriting
- [ ] `[PATH]` logging of count + source per stage
- [ ] Runner support: `-ParallelFilesCaching/-Scoring/-Rescoring` in `OspreyDatasetRun.psm1` + dataset wrappers
- [ ] Docs: `pwiz_tools/Osprey/docs/20-command-line.md`, Help `CommandLine.html` (en; ja/zh-Hans need the
      translation flow)
- [ ] Tests: arg precedence matrix (`OspreyCommandArgsTests`); SpectraCache 1 lane vs N lanes byte-identical
      caches; `SubsetPipelineTest` leg with different per-stage values producing identical outputs
- [ ] Gates: Build-Osprey Debug -RunTests; `regression.ps1 -Dataset Stellar`; `regression-parallel.ps1 -Dataset All`
- [ ] Measure: TDP-43 SpectraCache at lanes 1 / 8 / 16 from E: on MACS2 (quiet box); scoring vs rescoring
      curves (see the sweep below)
- [ ] `/code-review max`, then PR against the port branch

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
