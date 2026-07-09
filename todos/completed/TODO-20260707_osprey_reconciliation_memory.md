# Osprey: reduce reconciliation (Stage 6) memory during large runs

**Issue:** ProteoWizard/pwiz#4376
**Branch:** `Skyline/work/20260707_osprey_reconciliation_memory`
**Base:** master (rebased off the #4378 branch after #4378 merged).
**Status:** Completed
**PR:** [#4394](https://github.com/ProteoWizard/pwiz/pull/4394) (merged 2026-07-08 as 9353ed4c31)

## Problem

In an 8-file Astral Carafe run the `[STAGE-WALL] stage6` reconciliation leg (~600 s) is the
overall working-set peak (~80 GB WS on a 94 GB box with lazy Server GC). #4378 bounded per-file
scoring and the first-pass join and explicitly left Stage 6 to #4376. Goal: run 100s of Astral
files on a 32-64 GB machine, byte-identical.

## Approach (measure-first -- same discipline that reframed #4372)

The ~80 GB is WORKING SET; #4378 measured managed heap ~31-47 GB vs ~79 GB WS, so the true
reconciliation footprint may be much smaller (the library turned out 9 GB WS -> 3.2 GB real).
1. Map the reconciliation stage: what task(s), what holds memory at peak, what scales with FILE
   COUNT vs library size. (Explore agent in progress.)
2. Add a post-full-GC `[MEM reconciliation-peak]` `GC.GetTotalMemory(true)` probe at the peak
   (gated by `OSPREY_LOG_MEMORY`), like the #4372 `[MEM library-resident]` probe.
3. **Measure** the true reconciliation managed heap on the 8-file Carafe run (this #4378 base).
4. Only if genuinely large (>~target): find the lever (stream per-file instead of all-files-at-once,
   heavy per-candidate class->struct, O(files x N) buffers, redundant copies) and reduce it,
   BYTE-IDENTICAL. Check whether the Rust reference streams this differently.

## Exploration (2026-07-07)

Stage6 = `PerFileRescoreTask` (`[STAGE-WALL] stage6`). The rescore per-file loop
(`ExecuteRescore`, `PerFileRescoreTask.cs:489`) runs `Parallel.For` at
`EffectiveFileParallelism`; Rust runs the same loop SEQUENTIALLY (`pipeline.rs:3047`,
"limit peak memory -- each file loads spectra ~1.5 GB; per-file rescore is already
internally parallelized"). C# has a byte-identical sequential path (`parallelism==1`,
comment `:535`). Candidate levers: (1) all-files `perFileCwtCandidates`
(`CwtCandidateLoader.cs:53`) loaded at once during planning, planner indexes one file at
a time -> streamable; (2) heavy `FdrEntry` class (6 nullable heap arrays each,
`FdrEntry.cs:33`) held for all files, arrays repopulated during rescore (array-of-arrays,
like #4372 fragments); (3) full original-parquet reload per file in
`ReconciledParquetWriter`. Probes added at reconciliation start/end (`PerFileRescoreTask`).

## Measurement (2026-07-07, PARTIAL -- run killed mid-rescore)

8-file Carafe on this #4378 base, wiped work-dir, `OSPREY_LOG_MEMORY=1`:
- `[MEM reconciliation start]` working_set **63.49 GB** (peak 65.91), managed_heap **28.92 GB**
  (UNFORCED -- includes stage5 garbage), peak_paged **69.45 GB**.
- Rescore ran **SEQUENTIALLY** ("Re-scoring file 1/8" then "2/8"): the #4378 free-RAM guard
  set `EffectiveFileParallelism=1` on this machine. Run **killed during file 2/8** (likely
  machine sleep ~night, as a prior #4378 run was, or memory pressure).

**REFRAME:** parallelism is ALREADY 1 when memory-constrained, so the rescore-concurrency
lever (match Rust sequential) only helps on a big-RAM box where the guard allows >1. On a
64 GB box the guard forces sequential and reconciliation STILL sits at ~63.5 GB WS. So the
real #4376 lever is the **persistent/planning state entering reconciliation** (~28.9 GB
managed unforced) -- suspects above (perFileCwtCandidates all-files load, heavy FdrEntry
buffer, library). Unlike the library (WS-inflated), reconciliation looks like a genuine
large heap -- but the forced-GC number is still needed to separate real heap from garbage.

**NEXT:** a fresh clean run (machine not sleeping; consider `-Files 4` to finish faster, or
overnight with sleep disabled) to capture the new post-GC `[MEM reconciliation-floor]`
(added, fires early) + the end `[MEM reconciliation-resident]` + pre-GC peak_ws. Then size
the lever (likely stream `perFileCwtCandidates` per-file and/or lean the FdrEntry buffer).

## Measurement (2026-07-07, CLEAN 4-file run completed)

`[MEM reconciliation-floor]` **7.60 GB** (post-GC, entering rescore; identical at 4 and 8 files
-> does NOT scale with file count), `[MEM reconciliation-resident]` **6.94 GB** (post-GC, after
all files). But the pre-GC end snapshot was managed **48.70 GB** / peak WS **71.5 GB** -> ~42 GB
is uncollected garbage. So reconciliation's PERSISTENT heap is ~7 GB (fits easily); the big WS is
lazy Server-GC slack + per-file transients (reloaded spectra + the writer's full-parquet reload),
exactly like the library (WS-inflated). On a 64 GB box the GC collects under pressure -> fits.

Rescore already ran SEQUENTIALLY (the #4378 free-RAM guard set `EffectiveFileParallelism=1`).
The two 8-file runs that died mid-rescore were killed by a live **Monitor** tailing the log (the
no-monitor 4-file run completed) -- do NOT run a Monitor on a long background run.

## #4378 already mapped these levers (its own TODO), NOT done

- "Reconciliation re-scoring parallelism: Rust forces SEQUENTIAL (`iter_mut`) to avoid K x ~3 GB
  spectra resident; C# uses `Parallel.For`... On 64 GB match Rust's sequential default. **WATCH**"
- "C# reloads FULL ~940 B entries via `ParquetScoreCache.LoadFullFdrEntries` -- the ~22 GB @24M
  cost Rust designed away. The real remaining full-reload; **biggest post-first-pass lever. MISSING.**"
  (used by `ReconciledParquetWriter` AND the blib path; Rust uses a 5-col ~96 B `BlibPlanEntry`.)

## Fix (2026-07-07) -- deterministic per-file transient drop

Can't hold 300 x ~1.5 GB spectra, so per-file load/release is mandatory; the gap is that C#
frees each file's spectra at scope exit but the Server GC defers collection until near the RAM
ceiling, so the WS rides UP with file count. Added a per-file **deterministic drop** at the end
of `RescoreOneFile` (null spectra/ms1Spectra/rescored/isolationWindows + `GC.Collect()`), gated to
`EffectiveFileParallelism <= 1` (skip when concurrent files legitimately share residency and a
blocking GC would stall them). Mirrors Rust's per-iteration spectra drop; keeps the reconciliation
WS at ~persistent floor + one file's transient regardless of file count. **Byte-identical (GC
timing only).** Build green, 466/469 tests. `regression.ps1 -Dataset Stellar` running.

**Follow-up lever (bigger):** stream/project `LoadFullFdrEntries` (Rust's 5-col `BlibPlanEntry`)
so the per-file reload is small in the first place -- #4378's "biggest remaining full-reload."

## Gates

`regression.ps1 -Dataset Stellar` byte-identical (mode1/2/3, 1e-9) + `Test-PerfGate.ps1`; validate
the reduction on the Carafe run with the managed-heap probe.

## Relationship

- #4378 (`TODO-20260703_osprey_memory_bounding.md`): scoring/join bounding -- the base for this work.
- #4372 (`TODO-20260705_osprey_library_resident_memory.md`, PR [#4381]): library floor, ~1.7 GB, independent.
- Reconciliation (this) is the largest remaining memory lever per #4378's own ceiling analysis.

## Progress Log

### 2026-07-08 - Merged

PR #4394 merged as commit 9353ed4c31 (squash). Shipped: drop each file's rescore transients
(spectra / ms1 / isolation windows / rescored list nulled + a forced GC on the sequential path)
right after WriteReconciledAndStamp, cutting reconciliation transient garbage ~48.7 -> ~17.4 GB,
byte-identical, no measurable perf cost; plus two OSPREY_LOG_MEMORY reconciliation probes via a
new shared `ProfilerHooks.LogManagedHeapAfterGcIfEnabled` helper (added during review to DRY the
two probe blocks). Rebased off the #4378 branch onto master after #4378 merged; base retargeted.
Gates: build + 473 tests + zero-warning inspection (local red is only the unrelated
SystemMemory.cs / #4379 jb-CLI false positive); Stellar `regression.ps1` mode1/2/3 byte-identical
vs the streaming-only golden (50,237,440); perf gate PASS (stage6 -1.5%, total +1.5%); TeamCity
Perf/Regression on `pull/4394` green (Stellar + Astral). Fixes #4376 (auto-closed).
Follow-up lever (deferred, tracked in the TODO): stream/project `LoadFullFdrEntries` so the
per-file reload is small in the first place -- #4378's "biggest remaining full-reload."
