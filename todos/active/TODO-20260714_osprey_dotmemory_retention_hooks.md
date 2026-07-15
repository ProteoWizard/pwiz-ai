# TODO: Osprey dotMemory retention hooks (who-holds-it diagnosis)

## Branch Information
- **Branch**: `Skyline/work/20260714_osprey_dotmemory_retention_hooks`
- **Base**: `master`
- **Created**: 2026-07-14
- **Status**: In Progress
- **PR**: [#4423](https://github.com/ProteoWizard/pwiz/pull/4423)

**Status**: In Progress
**Priority**: Medium (no active defect; a diagnosis-time gap that costs hours of
manual reasoning each time a live-set jump has to be attributed to a retaining
reference)
**Complexity**: Small-to-Medium (add a snapshot hook to an existing profiler
wrapper + a `-MemoryProfile` switch to one script; the design constraint work is
in *scoping* the run, not the wiring)
**Created**: 2026-07-10
**Scope**: `C:\proj\pwiz\pwiz_tools\Osprey\Osprey.Tasks\ProfilerHooks.cs` +
`ai/scripts/Osprey/Profile-Osprey.ps1`

## Progress log

### 2026-07-14 - Implemented + validated (Brendan steered toward single-file)

Built the capability and ran it. Brendan refined the target in-session: the
pain is the **per-file** memory envelope (`perfviz.html` on a 20-file Astral run
shows the green *private bytes* + orange *managed* lines high and **stable
file-to-file**, a per-file sawtooth, not cross-file accumulation), so the
scenario is a **single file**, and the goal is to *lower those two lines*.

Implemented:
- `ProfilerHooks.cs` - `SnapshotReady` + `CaptureRetentionSnapshot(name)`
  wrappers around `JetBrains.Profiler.Api.MemoryProfiler` (same NoInlining +
  try/catch isolation shape as the `MeasureProfiler` wrappers). Folded a
  `CaptureRetentionSnapshot(label)` into `LogManagedHeapAfterGcIfEnabled`, so
  **every** forced-GC `[MEM ...]` boundary also captures a dotMemory snapshot
  when a `--use-api` session is attached (no-op otherwise).
- `PerFileScoringTask.cs` - added a `perfile-scored-live` forced-GC boundary in
  the single-file path (pre-GC crest + post-GC floor). Also closes the
  "scoring plateau has no live probe" gap for the single-file path. Zero batch
  impact (batch never takes the `nFiles==1` branch).
- `Profile-Osprey.ps1` - `-MemoryProfile` switch: forces net8.0, sets
  `OSPREY_LOG_MEMORY=1`, runs one file through Stage 1-4 under
  `dotMemory start --use-api`, writes `.dmw` to `ai/.tmp`, prints the
  human-in-the-loop retention read + crest-vs-floor interpretation.
- `Dataset-Config.ps1` - shared `Get-DotMemoryExe` / `Get-DotMemoryInstallHint`
  resolvers (mirror Run-Tests.ps1's order); refactored `Test-Snapshot.ps1` to
  use them (de-duped its inline copy).
- `ai/docs/osprey-development-guide.md` - "Retention diagnosis via dotMemory".

Gates: Debug build + 506 tests + inspection (0 warnings) green; Release net8.0
built. Smoke test (Stellar, `-MaxWindows 2`) confirmed the snapshot fires and a
254 MB `.dmw` is written.

**Finding - full uncapped Astral file 49** (log
`ai/.tmp/astral-memprofile-run.log`; workspace
`ai/.tmp/osprey-memory-20260714-171533.dmw`, 1.9 GB, 34.5M objects):

```
[MEM library-resident]            managed_heap=3.23 GB (3,131,286 entries)
[MEM single file scored (pre-GC)] working_set=28.63 GB, managed_heap=15.12 GB,
                                  gc_committed_last_gc=26.45 GB, gc_heap_last_gc=13.78 GB
[MEM perfile-scored-live]         managed_heap=4.34 GB (post-GC)
```

Root cause of the high green (private bytes) + orange (managed) per-file lines:
the per-file peak is **GC heap-growth / churn, not live retention**.
- Managed crest 15.12 GB -> post-GC floor 4.34 GB: ~71% (10.8 GB) is collectable
  garbage (scoring-loop churn).
- working_set 28.63 GB with gc_committed 26.45 GB but only 4.34 GB live: Server
  GC (32 heaps on this box) expanded the managed heap to ~26 GB committed while
  <5 GB is live. The 28-vs-50 GB gap vs the batch is GC *weather* (where a gen2
  lands), not a fixed requirement -- the stable number is the 4.34 GB live floor.
- Of the 4.34 GB live floor, 3.23 GB is the spectral library (3.13M target+decoy
  entries, already 71.5% string-interned); ~1.1 GB is held scored entries.

Levers (in priority for "lower the two lines"):
1. **GC config A/B (biggest/cheapest, no code change):**
   `DOTNET_GCHeapHardLimitPercent`, fewer heaps (`DOTNET_GCHeapCount` /
   workstation GC), `DOTNET_GCConserveMemory` -- collapse the ~24 GB elastic
   slack toward the ~4-5 GB live floor, paid in throughput. Matches the guide's
   "GC weather" corollary and the thread-scaling OOM note
   `[[reference_osprey_astral_thread_memory_oom]]`.
2. **Cut allocation churn** in Stage-1-4 scoring (the 10.8 GB transient): needs
   allocation tracking (`Test-Snapshot.ps1 -MemoryProfileStages stage1to4`,
   dotMemory `-c`) to name the top allocators -- a forced-GC snapshot can't see
   transient garbage.
3. **Shrink the live floor** (the true wall GC flags can't move): the 3.23 GB
   library dominates; on-the-fly decoys / compact library rep are the only lever.

**Finding - allocation traffic (`-MemoryProfile -TrackAllocations`, Astral file
49, auto-capped 6 windows; log `ai/.tmp/astral-alloc-run.log`, workspace
`ai/.tmp/osprey-alloc-20260714-174547.dmw`):**

```
6 windows (87,049 entries, ~5% of the full 1.7M):
[MEM single file scored (pre-GC)] working_set=25.39 GB (peak), managed_heap=17.73 GB,
                                  gc_committed_last_gc=20.83 GB
[MEM perfile-scored-live]         managed_heap=2.99 GB (post-GC)
```

**Key result: the per-file managed peak is a FIXED SETUP COST, not
scoring-proportional.** 6 windows churns as much managed heap (17.73 GB) as the
full 167-window run (15.12 GB). So the dominant allocators are front-loaded --
target+decoy library build (3.13M entries) and loading all 204,149 HRAM spectra
from the 6 GB mzML at once -- NOT per-window scoring temporaries. Levers reorder:
streaming/windowing the spectra load and lazy decoy generation are the
structural wins; pooling per-window scoring temporaries would barely move the line.

**Tooling caveat (record in guide):** full `-c` is heavy -- 32 min wall (~32x)
and a 26.9 GB workspace even at 6 windows, capturing the first ~200 s (which is
the setup churn, conveniently). A lighter API-driven alloc mode
(`--use-api` + `MemoryProfiler.CollectAllocations(true)` at scoring start +
`GetSnapshot` at the boundary) would capture the exact boundary at a fraction of
the cost -- deferred to the follow-up TODO.

**Finding - GC-config A/B** (Astral file 49, Stage 1-4, net8.0 Server GC;
harness `ai/.tmp/gc-cap-experiment.ps1`, logs `ai/.tmp/gc-cap-logs/`,
summary `ai/.tmp/gc-cap-summary.csv`):

```
config          wall_s  WS_peak  mgd_crest  committed  live  scored     exit
baseline(warm)   118.4   28.00    15.04      25.41      4.03  1,699,771   0
conservemem9     115.7   26.02    13.50      24.68      4.03  1,699,771   0
heapcount8       114.8   27.79    15.57      26.86      4.03  1,699,771   0
hardlimit50pct   113.7   28.11    15.03      25.55      4.03  1,699,771   0
hardlimit30pct    -      CRASH (exit 1 at 71s: 19 GB cap < in-scoring live need)
(baseline cold-cache first read was 160.9s -- a confound; warm re-run 118.4s)
```

Conclusions:
- **Perf cost negligible**: all configs 114-118s (the 160.9s was a cold mzML
  read, not GC). GC config does not move wall time for this workload.
- **Results identical**: 1,699,771 scored + 4.03 GB live floor in every
  successful config -- GC config cannot change search output (correctness).
- **Target-metric impact modest**: `DOTNET_GCConserveMemory=9` is the safe win
  -- WS 28.0->26.0 GB (~7%), managed crest 15.0->13.5 GB (~10%), no perf cost,
  no crash. HeapCount/50%-cap do ~nothing (50% ~= 32 GB never binds).
- **Root-cause refinement (the load-bearing result)**: the 30% cap (~19 GB)
  **crashes mid-scoring** -> the per-file peak is NOT mostly collectable garbage.
  ~20 GB is genuinely LIVE during scoring (all 200k HRAM spectra resident +
  in-flight scoring + the accumulating 1.7M scored entries); the 4 GB floor is
  low only because those free AFTER scoring. So GC tuning caps out ~10%; the real
  lever to move the green/orange lines is **structural streaming** of the spectra
  load and scored-entry accumulation, not a GC flag.

### Remaining
- [x] Interpret the full Astral single-file crest-vs-floor + snapshot.
- [x] GC-cap A/B: negligible perf cost, ~10% safe win (ConserveMemory), 30% cap
      crashes -> peak is genuine in-scoring live set, not garbage.
- [x] Self-review (clean; one clarifying comment applied, commit 7109061f77).
- [x] Correctness gate `regression.ps1 -Dataset Stellar` -> PASS (mode1/2/3,
      byte-identical golden; instrumentation env-gated, zero normal-run impact).
- [x] Allocation-tracking capture -> setup-dominated churn (above).
- [x] Commit C# (`350f07bac3`, pwiz branch).
- [ ] Commit ai (scripts/docs/TODO); push + PR on Brendan's go.
- [ ] Follow-up TODO(s): (a) GC-cap A/B on one Astral file (quantify green/orange
      drop vs throughput); (b) spectra-load streaming investigation (the real
      structural lever); (c) lighter API-driven allocation mode.

## Motivation

The Osprey memory work (#4398 / #4400 / #4406 / #4409) is instrumented entirely by
a homegrown printf layer: the `[MEM …]` probes from `ProfilerHooks`
(`LogMemoryStats`, `LogManagedHeapAfterGcIfEnabled`) parsed into A/B tables by
`ai/scripts/Osprey/Get-MemoryReport.ps1`. That layer is the **right** primary
instrument and is NOT being replaced — it is the only thing that runs
autonomously, at ~zero cost, on the real 82-file / 6–8 h / 60+ GB Astral batch and
trends the live set across builds. A memory profiler is *terrible* for that
workload: continuous profiling (especially allocation tracking) of a multi-hour,
multi-tens-of-GB run is impractical and would perturb the very thing being
measured. (Confirmed with Brendan 2026-07-10.)

The gap the printf layer structurally cannot close is **retention diagnosis**:
*what* object is live and *who* is holding it. The forced-GC live probes answer
"how much is live" — they *detected* the #4405 retention bug (a ~5.7 GiB
`FdrProjectionSet` pinned in `PipelineContext` past its only consumer) as an
unambiguous `8.40 → 18.30 GB` jump at `reconciliation-floor` — but naming the
retaining reference took human reasoning. A dotMemory retention path answers that
in one screenshot. This is exactly the Skyline GC-leak workflow, which Skyline
already has tooling for and Osprey does not.

## Current state (verified 2026-07-10)

`ProfilerHooks.cs` wraps **only** the dotTrace measure API —
`JetBrains.Profiler.Api.MeasureProfiler` (`GetFeatures` /
`StartCollectingData` / `StopCollectingData` / `SaveData` / `Detach`,
`ProfilerHooks.cs:59-95`), driven by `Profile-Osprey.ps1`. There is **no**
dotMemory integration anywhere in the Osprey tree: the only mention of
`MemoryProfiler` is the comment at `ProfilerHooks.cs:35` citing Skyline's
`TestRunnerLib/MemoryProfiler.cs` as the pattern it copied. All memory numbers are
hand-rolled on `GC.GetTotalMemory`, `Process.GetCurrentProcess()`, and forced
`GC.Collect()`.

Skyline, by contrast, drives dotMemory from `ai/scripts/Skyline/Run-Tests.ps1`
(`-MemoryProfile` → `dotMemory start --use-api --save-to-file … --overwrite`,
Run-Tests.ps1:700-718), resolves `dotMemory.exe` from
`~/.claude-tools\dotMemory` or the NuGet console package (Run-Tests.ps1:379-420),
and the leak-debugging skill documents the human-in-the-loop retention-path read.

## What to build

1. **Snapshot hook in `ProfilerHooks`.** Add a `MemoryProfiler.GetSnapshot()`
   wrapper (via `JetBrains.Profiler.Api.MemoryProfiler`) using the SAME
   `[MethodImpl(NoInlining)]` + try/catch isolation shape as the existing
   `MeasureProfiler` wrappers, so a missing profiler assembly is a caught no-op
   rather than a JIT failure of the caller. Trigger it at the **same forced-GC
   stage boundaries** the live probes already sit at — `stage5-start-live`,
   `first-pass-fdr-live`, `reconciliation-floor` — so the snapshot captures the
   same live set the `[MEM …]` line reports (dotMemory forces a GC before a
   snapshot, so the two are the same category of number; capturing at the same
   points keeps them reconcilable). Gate on the same `MemoryLoggingEnabled` /
   profiler-ready check so ordinary and headless-batch runs are unaffected.

2. **`-MemoryProfile` switch on `Profile-Osprey.ps1`,** mirroring the Skyline
   `Run-Tests.ps1` dotMemory driver: resolve `dotMemory.exe` the same way,
   launch with `dotMemory start --use-api --save-to-file <path> --overwrite`
   wrapping the Osprey exe, and write the `.dmw` to `ai/.tmp`. Reuse the Skyline
   resolution/install-hint code path rather than re-implementing it.

3. **Design for a SCOPED run, not the batch.** This capability is explicitly for
   short, diagnosis-focused runs: `OSPREY_MAX_SCORING_WINDOWS` and/or a small
   file subset so profiler overhead and snapshot cost stay tolerable. Document
   loudly that it is NOT for the full 82-file / 6–8 h run — that stays the printf
   layer's job. The dominant retention questions (Stage 5 / Stage 6 boundaries)
   reproduce on a handful of files.

4. **Human-in-the-loop, by design.** Emit the `.dmw` and stop; a human opens it in
   the dotMemory GUI for retention paths / dominators / biggest-retained-types
   (per the leak-debugging skill's "Step 3 requires a human — do NOT guess
   retention paths"). This is a *diagnosis* aid, not an autonomous gate.

## Explicitly NOT in scope

- **Do not replace or retire the printf `[MEM …]` layer.** It stays the primary
  sizing/regression instrument (the "will it fit in N GB" and branch-A/B tool).
  This item is purely additive — the "who holds it" complement.
- **Do not wire dotMemory into the long batch run** or into any autonomous
  night-session path.

## Gotchas / verify

- **net472 vs net8.0.** Confirm which TFM the profiling runs use. The snapshot API
  works on both, but `#4409`'s new `gc_*_last_gc` fields come from
  `GC.GetGCMemoryInfo()`, which is netcoreapp3.0+ only (absent on .NET Framework
  4.7.2). If the memory runs are net8.0 this is moot; if net472 is in play, both
  the `#4409` fields and any snapshot assumptions need a guard. (Osprey
  multi-targets — memory `[[project_ospreysharp_runtime_parity]]`; `Osprey.exe.config`'s
  `gcServer` is a Framework artifact, so verify rather than assume.)
- **dotMemory has its own misleading numbers** — retained vs. exclusive size, and
  a snapshot forces a GC so its figure is a *live* number that will not match a
  non-forced `managed_heap`. Extend the guide's "know what each number means"
  ethos to the profiler view too.
- **Native memory is poorly attributed by dotMemory too** (BLAS / Parquet.Net /
  mzML buffers). Retention diagnosis here is managed-heap-focused; the
  "native memory = negative 10 GB" trap the guide warns about is not solved by
  this tool. Managed retention (the #4405 class) is the target.
- **NEVER run two Osprey processes at once** (SQLite / parquet cache corruption).
  The profiled run must be serialized like every other Osprey run.

## References

- Guide section this complements:
  `ai/docs/osprey-development-guide.md` → "Measuring memory: the live set vs GC
  weather" (the printf discipline) and "Profiling C# via dotTrace".
- **PR #4409** (sparse HRAM XCorr cache) — adds the `gc_*_last_gc` fields and the
  forced-GC `stage5-start-live` / `first-pass-fdr-live` probes; this item plugs
  the retention view into those same boundaries. Its own note: the live scoring
  *plateau* is still unmeasured (tracked #4404).
- **#4405** — the `FdrProjectionSet`-pinned-in-`PipelineContext` retention bug that
  motivates this: detected by the forced-GC probe, but the retainer had to be
  found by hand. The canonical case this tooling would have shortcut.
- Skyline dotMemory driver to mirror: `ai/scripts/Skyline/Run-Tests.ps1`
  (`-MemoryProfile`, lines 379-420 resolution / 700-718 launch); the
  **leak-debugging** skill + `ai/docs/leak-debugging-guide.md` for the
  human-in-the-loop retention-path workflow.
- Files to change: `pwiz_tools/Osprey/Osprey.Tasks/ProfilerHooks.cs`,
  `ai/scripts/Osprey/Profile-Osprey.ps1`.
- Memory: `[[project_ospreysharp_runtime_parity]]`,
  `[[feedback_report_output_file_paths]]`.
