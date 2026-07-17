# TODO: Osprey PerFileScoringTask (Stages 1-4) calibration memory peak

**Status**: Backlog.
**Priority**: High -- this is the single largest per-worker RSS peak measured so far
(15.5 GB), higher than PerFileRescoring (~11 GB). Goal: get BOTH workers to ~10 GB.
**Created**: 2026-07-17
**Scope**: `pwiz_tools/Osprey/Osprey.Tasks/PerFileScoringTask.cs` +
`Osprey.Tasks/Calibrator.cs` / `Osprey.Chromatography/*Calibration*`,
`Osprey.ML/LinearDiscriminant.cs` (whatever the calibration phase allocates).

## What we measured (dotMemory, single-file Astral SEA-AD MTG, 2026-07-17)

PerFileScoringTask dotMemory timeline, snapshots:
- **post-calibration: 15.56 GB total, but only 2.13 GB .NET *used* (15.5M live objects)**
  -> **~13.4 GB is dotMemory "unmanaged" gray.**
- perfile-scoring (mid scoring plateau): 11.66 GB total, 3.96 GB live / 34.5M objects.
- perfile-scored (end / chunked write): 12.70 GB total, 2.46 GB live.

Shape: a 0-2 min **calibration ramp** climbs to the 15.5 GB peak (gen-2 to ~8 GB +
gen-0 on top), then the managed heap collapses but the gray stays ~13 GB for the
entire ~6 min scoring plateau, then a small bump at the end-of-task chunked write.

## Root cause (SAME mechanism as the Stage-6 investigation -- see below)

The gray "unmanaged" band is **NOT native and NOT a leak** -- it is Server-GC
**committed-but-free** managed segments. Proven on the Stage-6 rescore path with
`[MEM]` probes: at that peak `gc_committed=9.80 GB` vs `gc_heap(used)=3.55 GB` (~6 GB
retained), `native = peak_paged - gc_committed ~= 0.8 GB`. dotMemory GCs before each
snapshot, so it paints the retained committed as gray. `DOTNET_GCConserveMemory=9`
decommits it (`gc_committed 9.80 -> 4.53`, peak 10.33 -> 8.76) but at **3x the GC
count** -- a throughput cost we will NOT pay (Server GC's parallel throughput is
load-bearing for Skyline; keep it). So the peak is set by the **calibration phase's
committed high-water**, which Server GC then retains harmlessly.

## The lever (do NOT fight Server GC)

Lower the **calibration phase's peak managed allocation** (the ~8 GB gen-2 + gen-0
burst in the 0-2 min ramp), because that is what Server GC commits and keeps. Steps:
1. Add `[MEM]` stage-boundary probes around the calibration phase in
   `PerFileScoringTask` (before/after RT+mass calibration, LDA/LOESS/KDE) -- reuse
   `ProfilerHooks.LogMemoryStatsIfEnabled` + `LogManagedHeapAfterGcIfEnabled`; find
   which calibration sub-step drives the gen-2 ramp.
2. dotMemory dominators at the `post-calibration` snapshot (the workspace already
   exists on Brendan's machine) -> what 8 GB of gen-2 objects calibration builds
   (candidate: materializing all scored entries / a per-entry transient over the
   whole file at once, rather than streaming/binning).
3. Reduce that peak allocation (stream/bin the calibration inputs; free before the
   scoring plateau) so the committed high-water never reaches 15 GB.

## Gates
- `regression.ps1 -Dataset Stellar` (byte-identical golden) -- calibration is
  algorithm-affecting; any change must stay 1e-9.
- `Build-Osprey.ps1 -RunTests -RunInspection`.
- Memory A/B: dotMemory + `[MEM]` before/after, single-file Astral SEA-AD MTG,
  target post-calibration peak 15.5 -> ~10 GB.

## References
- Sibling peak: `[[TODO-osprey_firstpassfdr_memory_peak]]` (join-node peak).
- The retained-committed finding + GCConserveMemory proof came out of the Stage-6
  streaming investigation: `[[project_osprey_pipeline_peak_is_servergc_retained_committed]]`,
  `[[TODO-20260717_osprey_stage6_chunked_reconciled_transfer]]`.
- Memory measurement how-to: `[[reference_osprey_perfile_mem_measurement]]`.
