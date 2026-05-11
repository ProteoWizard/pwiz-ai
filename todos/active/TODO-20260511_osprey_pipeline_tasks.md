# TODO-20260511_osprey_pipeline_tasks.md — Phase B follow-up

> Continuation of **[TODO-20260509_osprey_pipeline_tasks.md](../completed/TODO-20260509_osprey_pipeline_tasks.md)**
> (Phase 0 snapshot regression + Phase A task-based pipeline
> rearchitecture, merged 2026-05-11 via ProteoWizard/pwiz #4197).
> That TODO has the full Phase 0 / Phase A history and design
> decisions; this file is forward-looking only.

## Branch Information

- **Branch**: (none yet — to be created from master)
- **Base**: `master`
- **Created**: 2026-05-11
- **Status**: Planning
- **PR**: (pending)

## Predecessor: Phase 0 + Phase A — merged

ProteoWizard/pwiz #4197 (merged 2026-05-11, squash):

- `AnalysisPipeline.cs` went from 7,054 lines to 220 lines (96.9%
  reduction). Four task classes
  (`PerFileScoringTask`, `FirstJoinTask`, `PerFileRescoreTask`,
  `MergeNodeTask`) align with the HPC fan-out / join boundaries from
  `Osprey-workflow.html`.
- `AbstractScoringTask` base class holds the shared scoring engine
  (RunCoelutionScoring + feature compute + library prep + dedup +
  static utilities).
- `PipelineContext` is a typed task registry; consumers reach
  upstream producers via `ctx.GetTask<T>().GetX()` (no constructor
  threading). Fail-fast `UnknownTaskException` on miss.
- `OspreySharp.IO/FileSaver.cs` is the atomic-write helper, with
  cross-platform `Path.GetRandomFileName` + `FileStream(CreateNew)`
  unique-name allocation (no kernel32 P/Invoke). Wired into
  `FdrScoresSidecar.Write` + `ReconciliationFile.Save`.
- `Test-Snapshot.ps1` is the same-impl byte-equality regression
  harness; baselines live at
  `D:\test\osprey-runs\{stellar,astral}\_snapshots\main\`.

Validated end-to-end at merge: 303/303 OspreySharp unit tests pass;
Stellar AND Astral 3-file snapshot regression PASS at every stage
(stage1to4 / stage5 / stage6 / stage7 / blib).

## Plan

Three workstreams, ordered by dependency. Each is a separate
commit gated by Stellar + Astral snapshot regression PASS; whether
they bundle into one PR or split is a sprint-end decision based on
size.

### 1. Pass 2 — worker convergence via lazy rehydrate

Each producer task's `Get*` accessor learns to lazy-hydrate from
disk when its `Run` has not executed (the worker entry path).
`RescoreWorker.Run` becomes:

```csharp
var ctx = new PipelineContext(config, new OspreyTask[]
{
    new PerFileScoringTask(),
    new FirstJoinTask(),
    new PerFileRescoreTask(),
}, Program.LogInfo, Program.LogWarning, Program.LogError);
return RunTask(ctx.GetTask<PerFileRescoreTask>(), ctx) ? 0 : ctx.ExitCode;
```

`PerFileRescoreTask.RunWorker` and the parameterless `RunWorker`
path go away. The lazy chain pulls upstream state from disk on
first accessor call.

Hydration responsibilities per producer:

| Producer | Accessor | Worker rehydrate |
|----------|----------|------------------|
| PerFileScoringTask | GetFullLibrary | LoadLibrary(config) + GenerateDecoys (skip when DecoysInLibrary) |
| PerFileScoringTask | GetLibraryById | Derive from GetFullLibrary |
| PerFileScoringTask | GetPerFileEntries | RescoreHydration.HydrateForRescore(config.InputScores) + RescoreCompaction.Apply |
| PerFileScoringTask | GetPerFileCalibrations | Load sibling .calibration.json per file |
| PerFileScoringTask | GetPerFileParquetPaths | Build from config.InputScores |
| FirstJoinTask | DidPlan | true after Hydrate populates outputs |
| FirstJoinTask | GetPerFileConsensusTargets | MultiChargeConsensus.SelectRescoreTargets per file (from perFileEntries) |
| FirstJoinTask | GetReconciliationActions | From RescoreHydration result |
| FirstJoinTask | GetRefinedCalibrations | From RescoreHydration result |
| FirstJoinTask | GetPerFileGapFillForRescore | From RescoreHydration result |

Open design Qs (decide as we go; both feel reasonable today):

- **Where the `RescoreHydration` bundle lives.** It produces a
  `RescoreInputs` object that PerFileScoringTask needs (entries) AND
  FirstJoinTask needs (reconciliation actions, refined cals,
  gap-fill). Cheapest: PerFileScoringTask owns the bundle and
  exposes the FirstJoin-owned bits through accessor methods that
  FirstJoinTask delegates to. Cleaner: a memoized helper on
  `RescoreHydration` itself that both tasks call lazily.
- **Sentinel for "not yet computed".** Today the producer-task
  output fields default to non-null empty collections so accessor
  callers never NPE before Run completes. Pass 2 needs to switch
  to a null sentinel (or a `_hydrated` bool) so the accessor can
  detect "must hydrate." Worth confirming the null route is
  consistent with Pass 1's defaults before flipping.

### 2. Phase B — validity-key resume layer

The bigger architectural step that the task framework was built to
support. Build on Pass 2's lazy-rehydrate accessors:

- Add `ValidityKey(PipelineContext)` virtual method to
  `OspreyTask`. Returns a hash of (search_hash + library_hash +
  version + task-specific inputs). Default impl reads
  `config.SearchParameterHash` + `config.LibraryIdentityHash` +
  `Program.VERSION`; tasks with extra-state can override.
- Add `Inputs(ctx)` + `Outputs(ctx)` virtuals returning the
  per-file artifact paths the task reads / writes. The driver
  walks Outputs and asks "do these exist and does their sidecar
  `.osprey.task` ValidityKey match?" If yes, skip Run; the
  accessors lazy-rehydrate from those existing artifacts.
- Sidecar format: `.osprey.task` JSON next to each output, carrying
  `{"task": "...", "version": "26.5.0", "validity_key": "...",
  "inputs": [...], "outputs": [...]}`. Trivial to inspect by hand;
  survives format evolution.
- The existing `--no-join` / `--join-at-pass=1` / `--join-only` /
  `--join-at-pass=2` CLI flags become aliases for "force start at
  task N" / "stop after task N". Mid-run crash resume happens
  automatically on next invocation against the same dataset.

### 3. Minor cleanups (deferred from /review feedback)

Three items from the post-merge `/review`:

- **Stale comment** in `OspreySharp.IO/FdrScoresSidecar.cs:181`.
  Still says "allocated by Win32 GetTempFileName so parallel
  writers can never collide on the same temp path." After PR
  #4197's portability fix, allocation is `Path.GetRandomFileName`
  + `CreateNew` retry; tighten the comment to match.
- **Stale doc-comment** on `PerFileRescoreTask.cs` class header.
  Says "Two entry shapes: In-process: construct via the multi-arg
  constructor with the assembled state produced upstream
  (FirstJoinTask)" — but the registry refactor dropped the
  multi-arg constructor. Rewrite for the registry model.
- **`PerFileRescoreTask.GetPerFileEntries()` returns null**
  pre-Run, inconsistent with the project's fail-fast posture
  (`UnknownTaskException` elsewhere). Either initialize to an
  empty list (consistent with `PerFileScoringTask`'s defaults) or
  throw a clear "called before producer Run" exception. Pass 2's
  null-sentinel decision (above) probably governs this.

## Backlog (out of scope this branch but tracked)

| Item | Reason |
|------|--------|
| `CalibrationIO.SaveCalibration` (.calibration.json) wiring through `FileSaver` | Adding the `FileSaver` dependency requires Chromatography → IO project reference; arch decision worth a sub-discussion |
| `BlibWriter` (output.blib) wiring through `FileSaver` | SQLite write path is more involved; blib is the final artifact, deserves care |
| `ParquetScoreCache.WriteScoresParquet` (.scores.parquet) alignment with `FileSaver` | Already does ad-hoc temp-file-then-rename, but should match the rest |
| Unit test for `FileSaver` itself | End-to-end snapshot regression exercises it indirectly; a small `FileSaverTest` would lock Commit / Dispose-without-Commit / collision-retry contracts |
| Phase C parallelism polish | Per-file tasks run across files concurrently rather than via per-stage `Parallel.ForEach` loops. Mostly no-op in performance terms today; the value is uniformity in how the driver schedules work |

## Validation gate

Each commit on this branch must pass:

- `pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1 -RunTests`
  (303+/303+ tests pass)
- `pwsh -File ./ai/scripts/OspreySharp/Test-Snapshot.ps1 -Dataset Stellar -Files All`
- `pwsh -File ./ai/scripts/OspreySharp/Test-Snapshot.ps1 -Dataset Astral -Files All`

The worker entry path is the riskiest seam to exercise; once Pass
2 lands, validate `--join-at-pass=1 --no-join` end-to-end on both
datasets before opening the PR.

## Open questions for sprint-end review

- **PR shape**: bundle Pass 2 + Phase B + cleanups into one PR, or
  split (e.g. Pass 2 alone first, Phase B as the headline of a
  second PR)? Probably one PR — Phase B builds directly on Pass
  2's rehydrate accessors, and the cleanups are tiny.
- **`OspreyConfig` mutation tightening**: Pass 1 documented the
  actual contract (hash-affecting fields stable; pipeline-populated
  fields fair game). Worth promoting to compile-time guarantees
  (e.g. an immutable `IConfigCore` interface for the
  hash-feeding fields, with `OspreyConfig` implementing both that
  and a mutable per-pipeline-run wrapper)? Probably not yet — solve
  the resume layer first; revisit if Phase B surfaces mutation
  bugs.
