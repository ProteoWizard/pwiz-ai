# TODO-20260509_osprey_pipeline_tasks.md

## Branch Information
- **Branch**: `Skyline/work/20260509_osprey_pipeline_tasks`
- **Base**: `master`
- **Created**: 2026-05-09
- **Status**: In Progress
- **GitHub Issue**: (none - internal refactor)
- **PR**: (pending)

## Sprint Plan

User has scoped this as one medium-sized sprint on a single branch
(not the multi-week, ~7-PR cadence the original write-up sketched).
Rationale: the OspreySharp folder has a single owner, so merge risk
is low. If the work stretches to weeks, that's a signal the original
pipeline design was worse than expected, not a sign to split.

**Decision 2026-05-09: Rust mirror dropped.** The project plans to
move primary work to OspreySharp and eventually retire Rust osprey.
Phase D (mirror task structure in `crates/osprey/src/tasks/`) is
removed. On-disk validity-key formats no longer need cross-impl
symmetry; we can pick whatever fits OspreySharp.

Phases now:

- **Phase 0** — new `Test-Snapshot.ps1` script: "snapshot ≡ current
  C#" regression gate. Mandatory prerequisite to Phase A.
- **Phase A** — mechanical extraction. Lands on this branch as a
  single PR.
- **Phase B** — resume semantics + FileSaver-backed atomic writes,
  follow-up branch.
- **Phase C** — parallelism polish, optional follow-up.
- ~~Phase D — Rust port.~~ Dropped.

### Phase A status: 4 of 4 super-tasks extracted + bodies moved (2026-05-10)

| Task                | Orchestration | Body move | Latest commit |
|---------------------|---------------|-----------|---------------|
| Tasks scaffolding   | LANDED        | n/a       | `7f2a42bcfe`  |
| MergeNodeTask       | LANDED        | LANDED    | `6a72150829`  |
| PerFileRescoreTask  | LANDED        | n/a (Stage6Rescore.cs already separate) | `eda5ca0ea2` |
| FirstJoinTask       | LANDED        | LANDED    | `ce217bc0a9`  |
| FileSaver helper    | LANDED        | + 2 wirings | `34a329c582` / `9a601f788b` |
| PerFileScoringTask  | LANDED        | LANDED    | `c378187bbe`  |

`AnalysisPipeline.cs` is now 3131 lines (down from 7054 originally
— a 56% reduction). The four task files total 4433 lines:

| File                  | Lines |
|-----------------------|-------|
| AnalysisPipeline.cs   | 3131  |
| FirstJoinTask.cs      | 1497  |
| MergeNodeTask.cs      |  780  |
| PerFileRescoreTask.cs |  126  |
| PerFileScoringTask.cs | 2030  |

What stays on `AnalysisPipeline.cs`:
- `Run()` itself (the thin task-pipeline driver)
- The shared scoring engine (RunCoelutionScoring + ScoreWindow +
  ScoreCandidate + all the feature-compute helpers like
  ComputeMs1Features, ComputePeakShapeFeatures, etc.) — used by
  PerFileScoringTask AND by Stage6Rescore (rescore loop)
- Library helpers (LoadLibrary, GenerateDecoys, BuildDecoyFromSequence,
  ExtractIsolationWindows) — used by both PerFileScoringTask AND
  RunWorker (Stage 6 worker mode entry)
- Stage6Rescore.cs partial (RunWorker, ExecuteStage6Rescore, +
  helpers) — unchanged
- Top-level static fields (SG_WEIGHTS, s_calXcorrScorer,
  s_mzmlReadGate) — promoted to internal where the moved methods
  needed cross-class access

A future cleanup pass could extract the shared scoring engine into
its own class (e.g. `SearchEngine` or move into `OspreySharp.Scoring`)
to shrink AnalysisPipeline.cs further; that would let
PerFileScoringTask and PerFileRescoreTask both be self-contained
without `_pipeline` back-references.

**Cross-dataset confirmation (2026-05-10):** snapshot regression
PASS at every stage on both Stellar 3-file AND Astral 3-file after
all body moves. The mechanical extraction preserves byte-exact
output on TSV / FDR / blib artifacts and content-equal output on
the parquet (subject to Parquet.Net ZSTD compression noise on the
boolean columns).

### Phase A++ : AbstractScoringTask base class (2026-05-10 evening)

Subsequent refactor extracted the SHARED scoring engine off
AnalysisPipeline into a new `AbstractScoringTask` abstract base in
`OspreySharp/Tasks/AbstractScoringTask.cs` (3006 lines). All four
concrete tasks now inherit from it; AnalysisPipeline.cs collapses
to 220 lines (96.9% reduction from origin/master's 7054).

| Step | Commit |
|------|--------|
| AbstractScoringTask + inheritance + AnalysisPipeline shortcut | `ea80d789db` |
| Rename Stage6Rescore.cs → AnalysisPipeline.PostReconciliationRescore.cs + ExecuteStage6Rescore → ExecuteRescore | `07af36bac5` |
| Move rescore engine into PerFileRescoreTask + drop AnalysisPipeline inheritance | `4e2d84be79` |

### Phase A+++ : rescore engine fully self-contained (2026-05-10 late evening)

The rescore engine — `RunWorker`, `ExecuteRescore`,
`WriteReconciledParquet`, `LoadSpectraForRescore`,
`LoadMassCalibrations`, `LoadOriginalRtCalibration`, `AddIfNotNull`,
and `RescoreStats` — has been moved out of the
`AnalysisPipeline.PostReconciliationRescore.cs` partial and into
`PerFileRescoreTask.cs` (1181 lines). The partial file is deleted.

`PerFileRescoreTask` now has two constructors: the multi-arg one
for in-process invocation through `Pipeline.Execute`, and a
parameterless one for the `--join-at-pass=1 --no-join` worker
entry. `RescoreWorker.Run` switches to constructing the task
directly:

```csharp
var task = new PerFileRescore.PerFileRescoreTask();
return task.RunWorker(config);
```

With the engine self-contained, `AnalysisPipeline` no longer needs
the `AbstractScoringTask` inheritance shortcut. The base class +
`Name` + `Run(ctx)` stubs are removed; the `partial` keyword is
dropped (single-part now); AnalysisPipeline.cs is a plain class
(220 lines) that drives the four task-pipeline phases
(PerFileScoring → FirstJoin → PerFileRescore → MergeNode) and owns
the thin shared logging sinks + `FormatDuration` helper.

Inside the moved methods, the static `LogInfo` / `LogWarning` /
`Program.LogX` call sites have been switched to `_ctx.LogInfo` /
`_ctx.LogWarning` / `_ctx.LogError`. Since `_ctx`'s callbacks
delegate to the same `Program.LogX` sinks, output is identical.
The only test-side ripple was a one-line rename in
`CalibrationTest.cs`:
`AnalysisPipeline.s_calXcorrScorer` → `AbstractScoringTask.s_calXcorrScorer`.

Snapshot regression: Stellar 3-file AND Astral 3-file PASS at
every stage (stage1to4 / stage5 / stage6 / stage7 / blib).
303/303 OspreySharp unit tests pass.

Remaining follow-up:
- Decided 2026-05-10: the WriteStage6* diagnostic names in
  OspreyDiagnostics stay — those dumps exist specifically to debug
  maccoss/osprey ↔ OspreySharp diffs with heavy reference to
  Osprey-workflow.html, so the Stage N language is load-bearing
  there. The naming was kept out of the rest of the code so that
  reading non-diagnostic code does not require understanding
  Osprey-workflow.html.

### Phase A+++++ : task registry on PipelineContext (2026-05-10, evening)

Follow-up `f3236b6245`. Replaces upstream-task constructor params
with `ctx.GetTask<T>()` lookups.

- `PipelineContext` now holds an ordered task list keyed by `Type`.
  `ctx.GetTask<T>()` returns the registered task or throws
  `UnknownTaskException` (programming defect; fail fast).
- Each concrete task is parameterless-constructed. Downstream tasks
  read upstream-produced state via
  `ctx.GetTask<UpstreamTask>().GetX()` rather than through the
  constructor; producer tasks own typed `Get*` accessors for their
  outputs.
- `PerFileRescoreTask` self-gates on `FirstJoinTask.DidPlan`
  (returns true as a no-op when planning was skipped) and exposes
  `GetPerFileEntries()` as the post-rescore producer
  (ownership-transfer mutation contract; `MergeNodeTask` consumes
  the post-rescore version through this accessor, not through
  `PerFileScoringTask`).
- `AnalysisPipeline.Run` constructs the task list once, hands it to
  the context, and iterates a flat `foreach` — no per-phase
  conditional dispatch in the driver.
- Worker mode (`PerFileRescoreTask.RunWorker`) still builds state
  in-method for now; Pass 2 will move that hydration onto the
  upstream producers' accessors.

Stellar 3-file AND Astral 3-file PASS at every stage; 303/303
unit tests pass.

#### Pass 2 plan (worker convergence via lazy rehydrate)

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
| FirstJoinTask | GetPerFileConsensusTargets | MultiChargeConsensus.SelectRescoreTargets per file (computed from perFileEntries) |
| FirstJoinTask | GetReconciliationActions | From RescoreHydration result (shared with PerFileScoringTask via... a shared hydrate cache?) |
| FirstJoinTask | GetRefinedCalibrations | From RescoreHydration result |
| FirstJoinTask | GetPerFileGapFillForRescore | From RescoreHydration result |

Open design Qs for Pass 2:
- `RescoreHydration.HydrateForRescore` produces a `RescoreInputs`
  bundle that PerFileScoringTask (entries) AND FirstJoinTask
  (reconciliation actions, refined cals, gap-fill) both need.
  Should the bundle live on... one task that exposes the relevant
  bits and the other task queries through it? Or run hydration
  twice (once per task)? Cheapest: PerFileScoringTask owns the
  bundle and exposes both its own outputs AND a way for
  FirstJoinTask to read the FirstJoin-owned bits. Or: a shared
  hydrate helper that both call lazily, memoized once at the
  config-level.
- Sentinel for "not yet computed" — null for reference types,
  bool flag for value types (DidPlan). Today the fields default
  to non-null empty collections; Pass 2 needs to change that to
  null so the accessor can detect "must hydrate."

### Phase A++++ : task orchestration simplification (2026-05-10, later)

Follow-up cleanup commit `c612037c70`:

- Replaced the `Pipeline` class with a private `RunTask` helper on
  `AnalysisPipeline` since every call site was
  `new Pipeline(singleTask).Execute(ctx)`. Deleted
  `OspreySharp.Tasks/Pipeline.cs`.
- Consolidated four near-identical `new PipelineContext(...)`
  constructions in `AnalysisPipeline.Run` into a single shared
  context — matches the design intent documented on
  `PipelineContext`.
- Moved all four concrete task classes into the
  `pwiz.OspreySharp.Tasks` namespace (was per-task sub-namespaces);
  ReSharper-driven cleanup of redundant usings + doc-comment crefs
  across the task files + FileSaver.
- `OspreySharp.Tasks` project now exposes just `OspreyTask` +
  `PipelineContext` — the shared framework boundary used by the
  four task subclasses.

Snapshot regression PASS at every stage on Stellar 3-file;
303/303 unit tests pass. Inspection: 0 errors, 3 pre-existing
InvalidXmlDocComment warnings (down from 55 before the AnalysisPipeline
extraction work started).

All four super-tasks corresponding to the
Osprey-workflow.html HPC fan-out / join boundaries are in place.
AnalysisPipeline.Run is a thin driver that constructs the four
tasks in order and threads outputs from each into the next via
instance properties. Mid-extraction the framework picked up a
boolean-return early-exit pattern (mirroring
pwiz_tools/Skyline/CommandLine.cs) so tasks can short-circuit
the pipeline without throwing — the dropped/StopAfterStage5/--no-join
exits all flow through OspreyTask.Run returning false and
PipelineContext.ExitCode carrying the requested process code.

All four extractions follow the same pattern: thin task class in
pwiz_tools/OspreySharp/OspreySharp/Tasks/, takes the needed
inputs via constructor, calls back into the existing private (now
internal) AnalysisPipeline methods. Bodies of RunProteinFdr,
WriteBlibOutput, ExecuteStage6Rescore, RunFdr,
RunFirstPassProteinFdr, WriteFdrScoresSidecars,
WriteReconciliationFiles, LoadLibrary, GenerateDecoys, and
ProcessFile all stay where they were — only the orchestration
moved.

FileSaver (atomic temp-file-then-rename helper) ported from
SharedBatch/FileSaver.cs into OspreySharp.IO/FileSaver.cs, with
two callers wired through it tonight:

| Write path | Wired commit |
|------------|--------------|
| FdrScoresSidecar.Write (.{1st,2nd}-pass.fdr_scores.bin) | `34a329c582` |
| ReconciliationFile.Save (.reconciliation.json) | `9a601f788b` |

Two FileSaver hardening fixes shipped alongside the FdrScoresSidecar
wiring:

- The constructor now resolves the destination via
  Path.GetFullPath so a relative bare-filename argument doesn't
  dead-end inside Path.GetDirectoryName -> Win32 GetTempFileName
  with empty path.
- Commit deletes a pre-existing destination before File.Move so
  re-runs on the same dataset don't throw on overwrite (the common
  case for OspreySharp's per-file artifacts), and now throws on
  failure instead of swallowing through Trace.TraceWarning so the
  caller's try/catch sees the real error.

Still on the wiring backlog (deferred to user-supervised session):

| Write path | Reason |
|------------|--------|
| CalibrationIO.SaveCalibration (.calibration.json) | Adding the FileSaver dependency requires Chromatography -> IO project reference; arch decision worth reviewing. |
| BlibWriter (output.blib) | SQLite write path is more involved; blib output is the final artifact and should stay non-atomic only with care. |
| ParquetScoreCache.WriteScoresParquet (.scores.parquet) | Already does an ad-hoc temp-file-then-rename, but should be aligned with FileSaver for consistency. |

### Phase 0 status: COMPLETE (2026-05-10)

Snapshot regression harness is green end-to-end on both datasets.

| Dataset | Files | Capture | Round-trip verify |
|---------|-------|---------|-------------------|
| Stellar | Single | PASS    | PASS              |
| Stellar | All    | PASS    | PASS              |
| Astral  | Single | PASS    | PASS              |
| Astral  | All    | PASS    | PASS              |

All 5 stages PASS at every gate (stage1to4 / stage5 / stage6 /
stage7 / blib). 302/302 OspreySharp unit tests also pass against
the patched binaries.

Snapshots live at:
- `D:\test\osprey-runs\stellar\_snapshots\main\` (Stellar 3-file)
- `D:\test\osprey-runs\astral\_snapshots\main\` (Astral 3-file)

Both manifests record source commit `a309d286ea` and binary
SHA-256 `30772211f51c...`.

### Phase 0 progress (2026-05-09)

Phase 0 surfaced two latent OspreySharp bugs that the Rust↔C#
Test-Regression flow had been masking. Both fixed on this branch
before any rearchitecture work:

1. **Stage 6 rewrite stamps mutated-config search_hash.**
   `ExecuteStage6Rescore` (`AnalysisPipeline.Stage6Rescore.cs`)
   created `ScoringContext` instances with the outer `OspreyConfig`
   instead of a per-file clone. `RunCoelutionScoring` reassigns
   `config.FragmentTolerance` to the MS2-calibrated tolerance during
   the search (`AnalysisPipeline.cs` ~line 3552). The mutated outer
   config then fed `WriteReconciledParquet`'s
   `config.SearchParameterHash()` call, stamping a hash that no
   fresh-config recomputation reproduces. Stage 7
   (`--join-at-pass=2`) rejected the parquet with a
   `search_hash mismatch` error. **Fix:** clone outer config at the
   top of the per-file loop; use the clone for all in-loop
   ScoringContexts; keep the unmutated outer for
   WriteReconciledParquet's metadata stamp. Mirrors the per-file
   clone pattern in ProcessFile.

2. **RunCoelutionScoring window-result order non-deterministic.**
   `Parallel.ForEach` over isolation windows accumulated each
   window's entries into a shared list in completion order. Same
   row SET, different row ORDER across runs — and hence different
   parquet bytes. **Fix:** index by window position
   (`windowResults[wIdx]`) and flatten in window-index order
   (`AnalysisPipeline.cs` ~line 3592).

After the deterministic-windows fix, TSV dumps, FDR bin sidecars
(`.{1st,2nd}-pass.fdr_scores.bin`), `.reconciliation.json`, and
the blib output are all byte-stable across runs.

The `.scores.parquet` files themselves still have intermittent
1-byte-shifts on the `is_decoy` column when written through
Parquet.Net's IronCompress + ZstdSharp path — same logical data,
different ZSTD-compressed bytes. The data is fully deterministic at
the column level. The snapshot harness uses a content-equality
gate (`inspect_parquet.py --diff --tolerance 0`) for parquets and
SHA-256 byte equality for everything else, which catches every
logical regression while absorbing third-party compression noise.
The ZSTD non-determinism is tracked as a follow-up (not on this
branch's critical path).

### Phase 0 design decisions (locked 2026-05-09)

1. **New script, not a modification.** `Test-Regression.ps1` (rust ≡
   cs) stays untouched. New `Test-Snapshot.ps1` is a copy-and-modify
   sibling under `ai/scripts/OspreySharp/`. When Rust osprey is
   eventually retired, `git rm Test-Regression.ps1` + the
   Compare-*-Crossimpl.ps1 family deletes cleanly.
2. **Snapshot location**: `$datasetRoot/_snapshots/<tag>/<stage>/`,
   parallel to the existing `_test_regression_<tag>/` workdir. Local
   only, never committed (data files are too big). Manifest at the
   snapshot root records the OspreySharp commit SHA and binary
   SHA-256.
3. **Stage1to4 tolerance: bit-exact** (SHA-256 on the per-file
   `.scores.parquet`). Same-impl removes the documented Rust↔C#
   xcorr/sg_weighted_xcorr ~1e-7 drift.
4. **Two modes via `-CreateSnapshot` switch**:
   - default: run cs end-to-end, compare each stage against the
     snapshot dir. Freeze step copies snapshot outputs to the next
     stage's inputs.
   - `-CreateSnapshot`: run cs end-to-end, copy outputs into the
     snapshot dir as the new baseline. Then the freeze step pulls
     from the just-written snapshot, matching the regression flow.
5. **Sharing with Test-Regression.ps1**: deliberately none. The
   scripts are siblings with overlapping helpers; the duplication is
   intentional so the eventual Rust-mode deletion is one `git rm`,
   not a refactor.

## Task Boundary Doctrine

`Osprey-workflow.html` (refreshed 2026-04-30) frames the pipeline by
HPC fan-out / join boundaries, not by stage numbers. The boundaries
that matter for distribution are the same boundaries the existing
CLI flags already expose:

| Phase | CLI entry point | Shape |
|-------|-----------------|-------|
| Stages 1-4 | (default) `--no-join` exits here | per-file fan-out |
| Stage 5    | `--join-at-pass=1 --join-only` exits here | first join (all-file) |
| Stage 6    | `--join-at-pass=1` continues here | second per-file fan-out |
| Stage 7    | `--join-at-pass=2 --input-scores …` enters here | merge-node join (2nd-pass FDR + protein FDR + .blib) |

These four boundaries are the **primary** Task boundaries. Finer-
grained sub-tasks are useful for in-process resume / test isolation
but should compose under the four super-tasks, not violate them.

## Phase A Stage-to-Task Mapping

`AnalysisPipeline.cs` is 7,054 lines (TODO sketch underestimated at
~5K), `AnalysisPipeline.Stage6Rescore.cs` is 1,122 lines. Region
boundaries already align with the proposed split. The master `Run()`
method spans lines 104-1211 and is the orchestrator that becomes the
new `Pipeline.Execute()` driver.

Confirmed task list = **7 tasks**, not 9. Three deviations from the
original sketch (decided 2026-05-09):

- **SpectraCacheTask dropped.** Current `LoadSpectra()` writes no
  `.spectra.bin` artifact; folded into CalibrationTask/ScoringTask
  (whichever needs spectra first). A standalone task awaits the
  Phase B checkpoint write.
- **SecondPassFdrTask dropped.** No second-pass PSM-FDR call exists
  in current code; rescored SVM scores feed `RunProteinFdr` directly.
  Adding one would be a semantic change (Phase B+ scope).
- **FirstPassFdrTask stays run-wide.** Sketch listed it per-file,
  but `RunFdr` is called once across all files at line 542; per-file
  Percolator training would change FDR results.

Final mapping:

| # | Task | Granularity | Current code |
|---|------|-------------|--------------|
| 1 | CalibrationTask | per-file | `LoadSpectra` 2108, `RunCalibration` 2202 |
| 2 | ScoringTask | per-file | `RunCoelutionScoring` 3405 + features + dedup, `WriteFdrScoresSidecars` 1721 |
| 3 | FirstPassFdrTask | run-wide | `RunFdr` 5884, `RunFirstPassProteinFdr` 6309 |
| 4 | ReconciliationPlanTask | run-wide planner, per-file outputs | Stage 6 planning lines 768-1080, `WriteReconciliationFiles` 1771 |
| 5 | RescoreTask | per-file | `ExecuteStage6Rescore` (Stage6Rescore.cs) |
| 6 | ProteinFdrTask | run-wide | `RunProteinFdr` 6366 |
| 7 | BlibWriteTask | run-wide | `WriteBlibOutput` 6461 |

Stage 1 library loading (`LoadLibrary` + `GenerateDecoys`,
lines 1218 + 1302) stays in the driver as pre-pipeline setup, not a
Task. It produces no per-file artifact and is the input to the
PipelineContext rather than a pipeline step.

Pipeline execution order interleaves per-file and run-wide:

```
Setup     LoadLibrary + GenerateDecoys
Per-file  CalibrationTask, ScoringTask    (parallel across files)
Run-wide  FirstPassFdrTask
Run-wide  ReconciliationPlanTask
Per-file  RescoreTask                     (parallel across files)
Run-wide  ProteinFdrTask
Run-wide  BlibWriteTask
```

Each per-file task's `Run()` handles its own across-files fanout;
the Pipeline driver just iterates Tasks sequentially.

## Summary

Break up the monolithic `pipeline.rs` (~7,800 lines) and
`AnalysisPipeline.cs` (~5,000 lines) into a Task-based pipeline,
inspired by the LabKey Software pipeline framework (2008). Each Task
declares its inputs and outputs; the pipeline driver inspects them at
startup, skipping completed tasks so that a run interrupted mid-stage
can resume without redoing finished work.

C# proof-of-concept first; port to Rust after the abstraction proves
out and after the Stage 1-7 cross-impl byte-parity gate is fully
green. Until then, both files keep growing — accepted cost of the
Rust-first parity-port methodology.

## Background

### Why now (motivation)

- `pipeline.rs` and `AnalysisPipeline.cs` bundle all 7 pipeline stages
  + worker dispatch + diagnostics into one function-soup. Hard to
  navigate, hard to test individual stages in isolation, hard to
  reason about which inputs each stage actually needs.
- A 100-mzML run that dies in Stage 6 today either wastes the full
  Stage 1-4 work (default mode) or leaves the user manually
  orchestrating resume via `--no-join` / `--join-at-pass=1
  --join-only` flags. Existing artifacts (`.scores.parquet`,
  `.calibration.json`, `.reconciliation.json`,
  `.1st-pass.fdr_scores.bin`) are *de facto* checkpoints already; we
  just don't have a uniform skip-if-present mechanism.
- The `--no-join` / `--join-at-pass=1 --join-only` flags are a
  hand-rolled, two-checkpoint version of what a Task framework
  provides natively for every stage.

### Why C# first

- Mike McCoss owns Rust `pipeline.rs` upstream; a structural refactor
  of that scale needs his sign-off and would benefit from a working
  reference design. C# can prove the abstraction first, then propose
  it upstream.
- We already have a precedent: `FileSaver` (atomic write) lives in
  Skyline's `pwiz_tools/Skyline/Util/UtilIO.cs:1274`, with simpler
  variants in `SharedBatch` (used by SkylineBatch and AutoQC). The
  rearchitecture is an opportunity to align that pattern in
  `pwiz_tools/Shared/CommonUtil` so all three products share one
  implementation.

### Why Task-based (the LabKey pattern, adapted)

LabKey Software's pipeline framework (which Brendan implemented in
2008) modeled a long-running pipeline as a queue of `PipelineTask`
instances. Each task knew its inputs and outputs; on restart, the
framework checked which outputs already existed and skipped tasks
whose work was complete. This made multi-hour pipelines resilient to
mid-run failures and trivial to reason about: each task did one thing.

Osprey's existing per-file artifacts already match the model.
Formalizing them as Task outputs gives:

- **Resilience**: 100-mzML runs survive crashes; on restart, only
  unfinished files re-run.
- **Composability**: stages become independently testable; a Stage 6
  bug-fix iteration doesn't need a full Stage 1-4 re-run on every
  iteration.
- **Clarity**: each Task is a small, self-contained unit; the
  monolith dissolves into ~9 focused classes.
- **Diagnostic surface**: env-var gates (`OSPREY_DUMP_*`) can attach
  per-Task without polluting the driver.

## Proposed architecture

### Core model

```csharp
public abstract class OspreyTask
{
    /// <summary>Files this task reads. Existence + content hash drive
    /// the validity check.</summary>
    public abstract IEnumerable<TaskInput> Inputs(PipelineContext ctx);

    /// <summary>Files this task produces. Same path layout as today's
    /// per-file artifacts; the .osprey.task sidecar carries the
    /// validity key.</summary>
    public abstract IEnumerable<TaskOutput> Outputs(PipelineContext ctx);

    /// <summary>Search hash + library hash + version + task-specific
    /// params. Hash mismatch => task re-runs even if outputs exist.</summary>
    public abstract string ValidityKey(PipelineContext ctx);

    /// <summary>The actual work. Writes through FileSaver so partial
    /// outputs from a crash never poison the resume check.</summary>
    public abstract void Run(PipelineContext ctx);
}

public sealed class Pipeline
{
    public IReadOnlyList<OspreyTask> Tasks { get; }
    public void Execute(PipelineContext ctx)
    {
        foreach (var task in Tasks)
        {
            if (IsTaskComplete(task, ctx)) { Log.Skip(task); continue; }
            task.Run(ctx);
            PersistValidityKey(task, ctx);
        }
    }
}
```

### Atomic writes via `FileSaver`

Each `TaskOutput.Open()` returns a `FileSaver`-backed stream; on
disposal-without-Commit, the temp file is discarded. A crash mid-write
leaves no partial output that fools the resume check. Use the existing
`pwiz.Skyline.Util.FileSaver` directly during the C# proof-of-concept;
extract to `CommonUtil` in `pwiz_tools/Shared` once we factor out the
SharedBatch / AutoQC variants alongside it.

### Concrete task list

```
Per-file tasks (parallelized across mzMLs):
  1. SpectraCacheTask        in: .mzML/.raw    out: .spectra.bin
  2. CalibrationTask         in: spectra.bin + library  out: .calibration.json
  3. ScoringTask             in: spectra + cal + library  out: .scores.parquet (Stage 1-4)
  4. FirstPassFdrTask        in: .scores.parquet  out: .1st-pass.fdr_scores.bin
  5. ReconciliationPlanTask  in: 1st-pass sidecars (all)  out: .reconciliation.json (per file)
  6. RescoreTask             in: .scores.parquet + reconciliation.json  out: reconciled .scores.parquet (Stage 6)
Run-wide tasks (sequential):
  7. SecondPassFdrTask       in: reconciled .scores.parquet (all)  out: post-rescore q-values
  8. ProteinFdrTask          in: post-rescore  out: protein q-values
  9. BlibWriteTask           in: above  out: .blib + report
```

The existing per-file artifacts cover ≈90% of the checkpoint surface
already. Only the Stage 5 boundary needs slightly cleaner per-task
output (today it bleeds into `.reconciliation.json` mixing Stage 5 +
Stage 6 inputs).

### Decisions captured

(Locked in during design discussion; revisit at implementation time
if we learn something that contradicts.)

1. **Granularity = per-stage-per-file** for stages 1-6, run-wide for
   stages 7-9. Per-file is the resume granularity that matches the
   100-mzML scenario; losing one file's work is acceptable, losing
   the whole stage is not.

2. **Validity-key storage = per-output sidecar `.osprey.task`** (one
   small JSON next to each output: `{"task": "...", "version":
   "26.5.0", "search_hash": "...", "library_hash": "...",
   "input_hashes": {...}}`). Avoids burying state inside parquet/json
   formats; survives format evolution; trivial to inspect by hand.
   Cost: one extra small file per output.

3. **Migration = in place** under
   `pwiz_tools/OspreySharp/OspreySharp.Tasks/`. Yields one owner per
   concept, avoids long-lived divergence between old and new code
   paths. Cost: visible churn in the diff.

4. **Order = C# first, Rust after.** Rust port deferred until the C#
   abstraction has shipped and proven robust on real datasets, and
   until cross-impl Stage 1-7 byte-parity is green.

5. **PR scope = Phase A as one extraction PR per stage** (≈ 7 PRs
   over a few weeks). Each PR keeps cross-impl parity unchanged and
   is independently revertable. Phase B (resume + validity keys)
   lands as one PR after Phase A is done.

## Migration phases

### Phase A: mechanical extraction (C# only)

Pull each existing block of `AnalysisPipeline.cs` into an
`OspreyTask` subclass under
`pwiz_tools/OspreySharp/OspreySharp.Tasks/`. The driver runs them in
fixed order. No semantic change, no new behavior. Cross-impl parity
gates run unchanged. ≈ 7 PRs, one per task type.

### Phase B: resume semantics

Add the validity-key check + `FileSaver`-backed atomic writes. The
existing flags (`--no-join`, `--join-at-pass=1`, `--join-only`)
become aliases for "force start at task N". Mid-run crashes resume
naturally on next invocation. One PR.

### Phase C: parallelism (optional polish)

Per-file tasks run across files concurrently rather than via
per-stage `Parallel.ForEach` loops. This is mostly a no-op in
performance terms today (we already parallelize per file inside each
stage); the value is uniformity in how the driver schedules work.

### Phase D: Rust port

Mirror the C# Task structure in `crates/osprey/src/tasks/`. Same task
names, same on-disk validity-key format, so a Stage X failure on
Rust can resume on C# and vice versa (the cross-impl symmetry we
already have, but explicit). Coordinate with Mike McCoss; propose
upstream after the C# version has shipped at least one release.

## Files expected to change (Phase A)

- `pwiz_tools/OspreySharp/OspreySharp.Tasks/OspreyTask.cs` (new)
- `pwiz_tools/OspreySharp/OspreySharp.Tasks/Pipeline.cs` (new)
- `pwiz_tools/OspreySharp/OspreySharp.Tasks/{SpectraCache,Calibration,Scoring,FirstPassFdr,ReconciliationPlan,Rescore,SecondPassFdr,ProteinFdr,BlibWrite}Task.cs` (new — one per task)
- `pwiz_tools/OspreySharp/OspreySharp/AnalysisPipeline.cs` (shrinks
  to a thin driver that constructs the Pipeline and calls Execute;
  per-stage code moves to the corresponding Task)
- `pwiz_tools/OspreySharp/OspreySharp/AnalysisPipeline.Stage6Rescore.cs`
  (folded into RescoreTask + GapFillTask)

## Files expected to change (Phase B)

- `pwiz_tools/OspreySharp/OspreySharp.Tasks/TaskOutput.cs` — add
  `FileSaver`-backed `Open()` + commit-on-success
- `pwiz_tools/OspreySharp/OspreySharp.Tasks/ValidityKey.cs` — sidecar
  read/write
- `pwiz_tools/Shared/CommonUtil` — extract `FileSaver` from Skyline's
  `Util/UtilIO.cs` so SkylineBatch / AutoQC / OspreySharp share one
  implementation (separate small PR, prerequisite)

## Open questions for implementation time

- Does the validity key need `input_hashes`, or is `search_hash +
  library_hash + version` sufficient? `input_hashes` adds robustness
  (a manually-edited `.scores.parquet` invalidates the cache) but
  costs a content hash per output check. Probably yes; cheap.
- How do the existing `--join-at-pass=1` / `--no-join` / `--join-only`
  flags map onto Task-based "force start at task N" / "stop after
  task N"? Worth a small CLI translation table in the spec doc.
- Should `OSPREY_DUMP_*` env vars become per-Task hooks or stay at the
  global level? Probably per-Task, but the current global pattern is
  a working precedent.

## See also

- LabKey Pipeline Framework (2008, original inspiration; Brendan)
- `pwiz_tools/Skyline/Util/UtilIO.cs:1274` — canonical `FileSaver`
- `pwiz_tools/Skyline/Executables/SharedBatch/SharedBatch/FileSaver.cs`
  — simpler variant used by SkylineBatch + AutoQC
- `crates/osprey/src/pipeline.rs` — Rust monolith to be mirrored after
  C# proves the design
- `pwiz_tools/OspreySharp/OspreySharp/AnalysisPipeline.cs` +
  `AnalysisPipeline.Stage6Rescore.cs` — current C# monoliths


**AbstractScoringTask Astral 3-file confirmation (2026-05-10):** PASS at every stage. Cross-dataset confidence in the new base-class extraction.
