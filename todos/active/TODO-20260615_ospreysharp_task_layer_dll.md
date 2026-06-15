# TODO-20260615_ospreysharp_task_layer_dll.md -- Lift the OspreySharp task layer into the OspreySharp.Tasks DLL

> PR 2 of the OspreySharp debt-paydown arc (PR 1 = #4302, the diagnostics seam,
> merged 2026-06-15). Move the ~7,900-LOC task bodies out of the exe project
> (`OspreySharp\Tasks\`) into the `OspreySharp.Tasks` DLL so the pipeline layer
> becomes unit-testable. **Pure relocation, output-identical, regression-gated --
> no new tests** (those are PR 3). Unblocked by PR 1: the task bodies no longer
> reach the exe-only OspreyDiagnostics static facade. See
> [[project_ospreysharp_debt_paydown_arc]].

## Branch Information
- **Branch**: `Skyline/work/20260615_ospreysharp_task_layer_dll`
- **Base**: `master` (cut from post-#4302 master, 6752500b)
- **Created**: 2026-06-15
- **Status**: In Progress
- **PR**: (pending)

## Decisions (Brendan, 2026-06-15)
1. **Fold into the existing `OspreySharp.Tasks` DLL** (not a new OspreySharp.Pipeline
   project). Tasks becomes the full pipeline layer; resolves the confusing "two
   folders named Tasks" (exe `OspreySharp\Tasks\` vs the Tasks DLL).
2. **Task-bodies-first scope.** Move the task bodies only; leave AnalysisPipeline
   (driver), RescoreWorker, Program, and the diagnostics sink in the exe. The
   full thin-exe (moving AnalysisPipeline + the 2076-line OspreyFileDiagnostics +
   the OspreyDiagnostics bootstrap) is a deliberate follow-on, not this PR.

## Exe-only coupling to resolve (scoped 2026-06-15)
The task bodies are nearly DLL-ready already (PR 1 removed the diagnostics-facade
reach). Remaining exe-only deps:
- **`Program.VERSION` / `Program.VERSION_STRING`** -- used by MergeNodeTask (389,
  1079), PerFileRescoreTask (563, 877), PerFileScoringTask (195, 822, 1021), and
  AnalysisPipeline (230). **Move VERSION to a Core type** (e.g. `OspreyVersion` in
  OspreySharp.Core); update all refs (Program keeps the value via the Core type).
- **`ProfilerHooks`** -- used by AbstractScoringTask. **Move ProfilerHooks.cs into
  the Tasks DLL**; move the `JetBrains.Profiler.Api` PackageReference from the exe
  csproj to the Tasks csproj.
- **Two stale comments** naming OspreyDiagnostics (no code impact): PerFileRescoreTask:788,
  PerFileScoringTask:1455 -- tidy while here.
- **AnalysisPipeline stays in exe** but constructs the (now-DLL-internal) tasks via
  `CanonicalPipeline()` -- works because the Tasks DLL already grants
  `InternalsVisibleTo("OspreySharp")`. Verify it still resolves after the move
  (or move `CanonicalPipeline()` into the DLL as a factory).

## Move set (into OspreySharp.Tasks DLL)
- `OspreySharp\Tasks\AbstractScoringTask.cs`, `Calibrator.cs`, `FirstJoinTask.cs`,
  `MergeNodeTask.cs`, `PerFileRescoreTask.cs`, `PerFileScoringTask.cs`,
  `PipelineByproducts.cs` -- already in namespace `pwiz.OspreySharp.Tasks`, so
  **no namespace change** (just `git mv` into the DLL folder).
- `RescoreHydration.cs` / `RescoreCompaction.cs` -- **verify**: if the task bodies
  reference them (likely -- hydration/compaction are part of rescore), move them
  too; if only AnalysisPipeline uses them, they can stay in the exe. Determine by
  build error during the move.
- `ProfilerHooks.cs`.

## csproj changes
- **OspreySharp.Tasks.csproj**: add ProjectReferences to IO, ML, Chromatography,
  Scoring, FDR (the bodies call ParquetScoreCache, PercolatorFdr, CoelutionScorer,
  etc.); add the `JetBrains.Profiler.Api` PackageReference. Keep Core + Diagnostics
  refs + the two InternalsVisibleTo (OspreySharp, OspreySharp.Test).
- **OspreySharp.csproj** (exe): drop the JetBrains.Profiler.Api package (moved);
  keep all ProjectReferences (still references Tasks DLL).
- **OspreySharp.Core.csproj**: gains `OspreyVersion` (no ref changes).
- Confirm no dependency cycle: Tasks -> {Core, Diagnostics, IO, ML, Chromatography,
  Scoring, FDR}; nothing below references Tasks. Exe -> Tasks (+ all). Acyclic.

## Commit plan (one PR, parity-gated each commit -- the PR-1 cadence)
Each commit: `Build-OspreySharp.ps1 -RunTests -RunInspection`, then
`regression.ps1 -Dataset Stellar` (output must stay byte-identical -- this is pure
relocation). Suggested commits:
1. Move `Program.VERSION` -> `OspreyVersion` in Core; repoint all refs.
2. Move `ProfilerHooks.cs` into Tasks DLL; shift the JetBrains package ref.
3. `git mv` the task bodies + PipelineByproducts (+ RescoreHydration/Compaction if
   needed) into the Tasks DLL; add the csproj ProjectReferences; fix
   `CanonicalPipeline()` resolution; tidy the 2 stale comments.
4. (If split needed) repoint OspreySharp.Test references; confirm tests still bind.

## Pre-merge gate
`regression.ps1 -Dataset All` (Stellar + Astral) + `Test-PerfGate.ps1 -Dataset Stellar`
(relocation -> expect perf-neutral) + zero-warning inspection + `/pw-self-review`.
A dumps-on run is NOT needed (no diagnostics code changes this PR).

## Out of scope (future)
- Full thin-exe: move AnalysisPipeline + OspreyFileDiagnostics + OspreyDiagnostics
  bootstrap out of the exe.
- PR 3: extract collaborators (per-file resume driver, PercolatorRunner, reconciliation
  I/O) + the unit tests that migrate coverage off the 41-min nightly regression.
- The `IOspreyDiagnostics : IScoringDiagnostics` / gate-flags-vs-writes interface split.

## Progress Log

### 2026-06-15 -- Created
Scoped the exe-only coupling (above) after #4302 merged. Decisions captured. Branch
cut from post-#4302 master. **Implementation deferred to a fresh context** -- the
~8,000-LOC cross-DLL move plus per-commit build/regression cycles needs more
headroom than remained in the session that planned it. Next session: execute the
commit plan above; it is a pure `git mv` + csproj-wiring relocation, so the Stellar
regression after each commit is the proof it stayed output-identical.
