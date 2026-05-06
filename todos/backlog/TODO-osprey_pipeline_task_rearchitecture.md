# TODO-osprey_pipeline_task_rearchitecture.md

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
