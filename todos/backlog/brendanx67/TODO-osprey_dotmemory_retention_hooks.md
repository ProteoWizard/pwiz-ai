# TODO: Osprey dotMemory retention hooks (who-holds-it diagnosis)

**Status**: Backlog
**Priority**: Medium (no active defect; a diagnosis-time gap that costs hours of
manual reasoning each time a live-set jump has to be attributed to a retaining
reference)
**Complexity**: Small-to-Medium (add a snapshot hook to an existing profiler
wrapper + a `-MemoryProfile` switch to one script; the design constraint work is
in *scoping* the run, not the wiring)
**Created**: 2026-07-10
**Scope**: `C:\proj\pwiz\pwiz_tools\Osprey\Osprey.Tasks\ProfilerHooks.cs` +
`ai/scripts/Osprey/Profile-Osprey.ps1`

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
