# TODO-20260511_osprey_pipeline_tasks.md — Phase B: resume + worker convergence (unified design)

> Continuation of **[TODO-20260509_osprey_pipeline_tasks.md](../completed/TODO-20260509_osprey_pipeline_tasks.md)**
> (Phase 0 snapshot regression + Phase A task-based pipeline
> rearchitecture, merged 2026-05-11 via ProteoWizard/pwiz #4197).
> Phase 0 / Phase A history and design decisions live there; this
> file describes the Phase B design and remaining implementation
> work.

## Branch Information

- **Branch**: `Skyline/work/20260511_osprey_pipeline_tasks` — merged to master via #4199 on 2026-05-14 (squash).
- **Base**: `master`
- **Created**: 2026-05-11 from `origin/master` at `12825485a9` (the squash-merge of #4197).
- **Status**: COMPLETE — Phase B core (resume-on-restart capability via per-(output, task) `.osprey.task` sidecars, StartAt/StopAfter routing, lazy-rehydrate accessors, and per-file skip in `PerFileScoringTask`) merged. Continuation in [TODO-20260514_osprey_pipeline_tasks.md](../active/TODO-20260514_osprey_pipeline_tasks.md) (Phase C worker convergence + post-Phase-B cleanups).
- **PR**: https://github.com/ProteoWizard/pwiz/pull/4199 — merged 2026-05-14 (squash). All CI checks PASS (CodeQL, TeamCity Skyline PR Perf + Tutorial, Skyline master+PRs, code inspection, Wine container, debug build). Copilot review feedback addressed in commit `dd21ca3a4d` (6 of 7 threads resolved; the TaskValiditySidecar unit-test thread is left as a tracker for Phase C). Claude `/review` surfaced 6 prioritized follow-ups (P1-P3); all rolled forward into the Phase C TODO.

## Current branch state (commits already on branch)

| Commit | Subject | Status |
|--------|---------|--------|
| `778628dd86` | `/review` cleanup from PR #4197 (stale FdrScoresSidecar comment, PerFileRescoreTask doc, `GetPerFileEntries` null guard) | KEEP — independent value |
| `9430e41a34` | Framework surface: `Inputs` / `Outputs` / `ValidityKey` virtuals on `OspreyTask` + `TaskValiditySidecar` JSON reader/writer | KEEP — foundation |
| `70f8a578c3` | Per-task `Inputs` / `Outputs` / `ValidityKey` overrides on each concrete task | KEEP — declarative metadata |
| `e7763c490e` | Revert of an earlier RunTask skip-wiring commit (the `IsWorkerMode` flag gate that was the wrong abstraction) | (revert) |
| `811d630ff8` | Phase B commit 1 — `StartAtTask` / `StopAfterTask` on `PipelineContext` + CLI flag mapping in `AnalysisPipeline.Run` | LANDED |
| `498e562f36` | Phase B commit 2 — `RunTask` skip-if-outputs-valid via per-output sidecar check + post-Run sidecar write; no CLI gate | LANDED |
| `9a9dd327f2` | Phase B commit 3 — activate `StartAt`/`StopAfter` range-gating + lazy-rehydrate accessors (PerFileScoring 5, FirstJoin 4 + DidPlan, PerFileRescore GetPerFileEntries); `_runOrHydrated` idempotent re-entry guard | LANDED |
| `f8fd33d3b3` | Phase B commit 4 — per-file skip inside `PerFileScoringTask.Run` via `ScoreOrLoadForFile` helper; per-output sidecar lifecycle moved into task bodies (FirstJoin/MergeNode/PerFileRescore delete-at-start; PerFileScoring delete-then-write per file) | LANDED |

Commits 1-4 deliver Phase B's primary goal: the canonical 1000-mzML crash-resume scenario. Default-mode pipelines (`stage1to4`) now skip already-scored files via per-file `.osprey.task` sidecars; the StartAt/StopAfter mechanism replaces the discarded `IsWorkerMode` flag gate.

**Commit 5 (worker convergence) is DEFERRED to a follow-up branch.** Converging the stage6 `RescoreWorker.Run` entry path onto `AnalysisPipeline.Run` requires unifying the disk-load semantics between `PerFileScoringTask.joinOnly` (raw stubs + PIN features, no overlay) and `RescoreHydration.HydrateForRescore` (stubs with 1st-pass SVM overlay + reconciliation.json parsing). The two paths serve different scenarios (stage5 raw vs stage6 with overlay) and unifying them is a non-trivial refactor that warrants its own change-set with focused validation. See `## Phase C` below.

## Predecessor: Phase 0 + Phase A — merged

ProteoWizard/pwiz #4197 (merged 2026-05-11, squash):

- `AnalysisPipeline.cs` went from 7,054 lines to 220 lines (96.9%
  reduction). Four task classes
  (`PerFileScoringTask`, `FirstJoinTask`, `PerFileRescoreTask`,
  `MergeNodeTask`) align with the HPC fan-out / join boundaries
  from `Osprey-workflow.html`.
- `AbstractScoringTask` base class holds the shared scoring engine.
- `PipelineContext` is a typed task registry; consumers reach
  upstream producers via `ctx.GetTask<T>().GetX()`.
- `OspreySharp.IO/FileSaver.cs` (cross-platform atomic writes) is
  wired into `FdrScoresSidecar.Write` + `ReconciliationFile.Save`.
- `Test-Snapshot.ps1` is the same-impl byte-equality regression
  harness; baselines at
  `D:\test\osprey-runs\{stellar,astral}\_snapshots\main\`.

## Phase B unified design

The user's HPC scenario: a pipeline run processing 1000 mass-spec
files. The orchestration server crashes after file 487 has been
scored. The user re-invokes the same CLI. The pipeline should
fast-forward through every completed file's work and pick up where
the crash left off — *not* re-score the 487 already-scored files.

Three mechanisms together produce that behavior:

### 1. Single canonical pipeline, with `StartAt` / `StopAfter`

The pipeline definition is invariant: always
`[PerFileScoringTask, FirstJoinTask, PerFileRescoreTask, MergeNodeTask]`,
in order. CLI flags do **not** change which tasks are in the
pipeline. They map to two new properties on `PipelineContext`:

- `StartAtTask` (`Type`, default `typeof(PerFileScoringTask)`)
- `StopAfterTask` (`Type`, default `typeof(MergeNodeTask)`)

The driver iterates `ctx.Tasks`:

- Tasks **before** `StartAt`: `Run` is never called. They sit in
  the registry; their accessors lazy-rehydrate from disk if a
  downstream task queries them.
- Tasks **from `StartAt` through `StopAfter`**: normal flow —
  skip-if-outputs-valid check, then run otherwise, write sidecars
  on success.
- Tasks **after** `StopAfter`: not reached.

CLI → StartAt/StopAfter mapping (CLI parser populates these from
existing flags; no new CLI surface):

| CLI | StartAt | StopAfter |
|-----|---------|-----------|
| (default) | `PerFileScoringTask` | `MergeNodeTask` |
| `--no-join` | `PerFileScoringTask` | `PerFileScoringTask` |
| `--join-at-pass=1 --join-only` (no `--input-scores`) | `PerFileScoringTask` | `FirstJoinTask` |
| `--join-at-pass=1 --join-only --input-scores ...` | `FirstJoinTask` | `FirstJoinTask` |
| `--join-at-pass=1 --no-join --input-scores ...` (rescore worker) | `PerFileRescoreTask` | `PerFileRescoreTask` |
| `--join-at-pass=2 --input-scores ...` | `MergeNodeTask` | `MergeNodeTask` |

This collapses the worker entry path onto the standard pipeline.
`RescoreWorker.Run` becomes one line:

```csharp
public static int Run(OspreyConfig config) => new AnalysisPipeline().Run(config);
```

The CLI parser is what makes it work (it sets
`config.StartAtTask = typeof(PerFileRescoreTask)` etc.).

**Canonical pipeline lives in one place.** With the invariant
pipeline, no caller should construct a `new OspreyTask[] { ... }`
list naming all four tasks — that would be re-stating the canonical
definition. The single source of truth is a static factory on
`AnalysisPipeline`:

```csharp
internal static OspreyTask[] CanonicalPipeline() => new OspreyTask[]
{
    new PerFileScoringTask(),
    new FirstJoinTask(),
    new PerFileRescoreTask(),
    new MergeNodeTask(),
};
```

`AnalysisPipeline.Run` is the only caller. `RescoreWorker.Run` is
literally `return new AnalysisPipeline().Run(config);` — it never
sees a task list. (`PipelineContext` itself can't own the factory
because the four task classes live in `OspreySharp` and
`PipelineContext` lives in `OspreySharp.Tasks` — making
`OspreySharp.Tasks` reference `OspreySharp` would create a project
cycle. `AnalysisPipeline` is on the correct side of that boundary.)

### 2. Lazy-rehydrate accessors on producer tasks

When `MergeNodeTask` runs in `--join-at-pass=2` mode, it queries
`ctx.GetTask<PerFileScoringTask>().GetFullLibrary()`. The
`PerFileScoringTask`'s `Run` was skipped (it's before `StartAt`)
so its field is null. The accessor detects null and lazy-loads
from disk:

| Task / Accessor | Lazy rehydrate |
|-----------------|----------------|
| `PerFileScoringTask.GetFullLibrary` | `LoadLibrary(config) + GenerateDecoys` (skip decoys when `DecoysInLibrary`) |
| `PerFileScoringTask.GetLibraryById` | derive from `GetFullLibrary` |
| `PerFileScoringTask.GetPerFileEntries` | `RescoreHydration.HydrateForRescore(config.InputScores)` + `RescoreCompaction.Apply` (mirrors today's `RunWorker` body) |
| `PerFileScoringTask.GetPerFileCalibrations` | load each `.calibration.json` sibling |
| `PerFileScoringTask.GetPerFileParquetPaths` | build from `config.InputScores` or `config.InputFiles` |
| `FirstJoinTask.DidPlan` | `true` once `_perFileGapFillForRescore` is hydrated |
| `FirstJoinTask.GetPerFileConsensusTargets` | `MultiChargeConsensus.SelectRescoreTargets` per file (from perFileEntries) |
| `FirstJoinTask.GetReconciliationActions` | from `RescoreHydration` result |
| `FirstJoinTask.GetRefinedCalibrations` | from `RescoreHydration` result |
| `FirstJoinTask.GetPerFileGapFillForRescore` | from `RescoreHydration` result |

**Shared hydration seam.** `PerFileScoringTask.GetPerFileEntries`
and the four `FirstJoinTask` accessors that pull from
`RescoreHydration` share an internal bundle (the existing
`RescoreInputs` type). To avoid double-loading, one of these tasks
owns the bundle. Suggested split: `PerFileScoringTask` owns
`_rescoreInputs`, exposes both its own bits AND a
`GetRescoreInputs()` that `FirstJoinTask`'s rehydration calls.
Alternative: a memoized cache on `RescoreHydration` itself.
Implementer's call — both work.

Once the lazy-rehydrate path exists, every CLI-mode-aware branch
inside the four task `Run` methods becomes dead code and can be
deleted (e.g. the `if (config.ExpectReconciledInput)` blocks in
`PerFileScoringTask.Run` and `FirstJoinTask.Run`). The task's
`Run` only handles the case where its own `Run` is actually
invoked (i.e. when it's at-or-after `StartAt`).

### 3. Per-file skip inside `PerFileScoringTask.Run`

Task-level skip on `PerFileScoringTask` is all-or-nothing: if 999
of 1000 outputs exist with valid sidecars, the task still
re-runs and the inner `foreach (var inputFile in config.InputFiles)`
re-scores every file. To fix:

- At the top of the per-file loop in `PerFileScoringTask.Run`, check
  the file's `.scores.parquet.PerFileScoring.osprey.task` sidecar.
- If valid: load the existing parquet into `_perFileEntries` (same
  code path the lazy-rehydrate accessor uses), populate
  `_perFileCalibrations` from the sibling `.calibration.json`, log
  `[file] X: skipping (outputs valid)`, and continue to the next
  file.
- Else: score the file as today.

Same pattern applies to `MergeNodeTask`'s 2nd-pass FDR sidecar
loop. The 2nd-pass sidecars are per-file outputs; per-file skip
keeps the loop fast on re-runs.

### Skip-if-outputs-valid mechanism (the part that returns)

The `RunTask` driver helper (on `AnalysisPipeline`) still does:

1. Before invoking `task.Run`: enumerate `task.Outputs(ctx)`; if
   every output exists with a `.osprey.task` sidecar whose
   `validity_key` matches `task.ValidityKey(ctx)`, log
   `[task] X: skipping (outputs valid)` and return `true` without
   executing.
2. Delete stale sidecars for this task before running (mid-Run
   crash protection).
3. Run the task. On success, write fresh sidecars next to each
   declared output.

What changes vs. the earlier (reverted) wiring:

- **No `IsWorkerMode(ctx)` CLI flag gate.** The gate's purpose was
  to bypass the validity check in worker / cross-impl mode. The
  StartAt mechanism subsumes this: in `--join-at-pass=2 --input-scores`
  mode, `StartAt = MergeNodeTask`, so upstream tasks never reach
  `RunTask` and never check their sidecars. The flag-gate
  abstraction is gone.
- The existing parquet `osprey.search_hash` metadata check on
  `--input-scores` parquets stays untouched. It's a separate
  cross-impl correctness gate and the user wants it preserved
  (Light posture; see TODO-20260509 for the discussion).

## Implementation plan

Five commits, each gated by build + 303/303 unit tests + Stellar
snapshot regression. Astral cross-dataset PASS gates the PR open.

### Commit 1 — `StartAt` / `StopAfter` on `PipelineContext`

- Add `public Type StartAtTask { get; }` and `public Type StopAfterTask { get; }` to `PipelineContext`. Constructor takes them with sensible defaults (`PerFileScoringTask` and `MergeNodeTask`).
- Map CLI flags to the two properties in the parser (probably `Program.ConfigureFromArgs`). Use the table above.
- No behavior change yet — the driver still iterates `ctx.Tasks` ignoring these properties. Validation: build + 303 tests pass; Stellar regression PASS (no skip behavior yet).

### Commit 2 — driver respects `StartAt` / `StopAfter`

- `RunTask` in `AnalysisPipeline` (or the surrounding `Run` loop): for each task, decide whether it's before StartAt, in-range, or after StopAfter. Before: skip silently. After: don't reach.
- Reintroduce the skip-if-outputs-valid check from the reverted commit, but only for in-range tasks. Same pattern: check sidecars, run otherwise, write sidecars after success. No CLI gate.
- Validation: Stellar regression PASS for every CLI mode (default, `--no-join`, `--join-at-pass=1 --join-only`, `--join-at-pass=2 --input-scores`).

### Commit 3 — lazy-rehydrate accessors

- `PerFileScoringTask`: each `Get*` accessor detects null/empty and hydrates from disk using the table above. Choose the shared hydration seam (probably `_rescoreInputs` on `PerFileScoringTask` with `GetRescoreInputs()` exposed for `FirstJoinTask`).
- `FirstJoinTask`: same pattern for its four hydrated outputs + `DidPlan`.
- `MergeNodeTask` doesn't have downstream consumers, so no rehydrate needed there.
- Delete CLI-mode branches inside task `Run` methods that lazy-rehydrate now subsumes (the `ExpectReconciledInput` branches).
- Validation: Stellar regression PASS; Astral regression PASS.

### Commit 4 — per-file skip inside `PerFileScoringTask.Run`

- At the top of the per-file `foreach`, check the per-file sidecar; if valid, load the existing parquet into `_perFileEntries` and skip the scoring.
- Apply the same pattern to `MergeNodeTask`'s 2nd-pass FDR sidecar loop.
- Validation: Stellar regression PASS on fresh run; **manual crash-resume verification** — invoke the full pipeline against a small dataset, delete one file's `.scores.parquet`, re-invoke, confirm only that file is re-scored and the other tasks skip.

### Commit 5 — worker convergence (deferred)

Carved off into [TODO-20260514_osprey_pipeline_tasks.md](../active/TODO-20260514_osprey_pipeline_tasks.md). The hydration-unification rationale, the three-mode table for stage5/6/7, and the implementation plan all live there.

## Validation gates

Every commit must pass:

- `pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1 -RunTests` (303+/303+ tests pass)
- `pwsh -File ./ai/scripts/OspreySharp/Test-Snapshot.ps1 -Dataset Stellar -Files All`

PR-open gates:

- Astral regression PASS at every stage
- Manual crash-resume verification (after commit 4)
- Cross-impl Test-Regression with Mike's Rust osprey still passes (after commit 5)

## Open implementation Qs

Rolled forward into [TODO-20260514_osprey_pipeline_tasks.md](../active/TODO-20260514_osprey_pipeline_tasks.md) — Phase B's open Qs about the shared `RescoreInputs` hydration seam, the CLI parser location for StartAt/StopAfter wiring, the "not yet computed" sentinel choice, and validity-key-mismatch sidecar cleanup are all Phase C concerns now.

## Phase B success criteria

### Phase B core (commits 1-4 in this PR)

- A 1000-mzML pipeline crash on file 487 → user re-invokes same CLI →
  files 1-486 skip via per-file sidecar check; file 487 onward are
  scored. ✅ achieved by commit 4's per-file skip
- `StartAt = MergeNodeTask` mode (`--join-at-pass=2 --input-scores`)
  dispatches with no `IsWorkerMode` flag gate in the pipeline. ✅
  achieved by commits 1 + 3
- Cross-impl testing with Mike's Rust osprey continues to work
  unchanged. The parquet `osprey.search_hash` metadata check stays. ✅
  by construction — commit 2 has no CLI gate; commit 4 only adds
  per-file skip inside the actual-scoring paths
- Stellar + Astral 3-file snapshot regression PASS at every stage on
  the final branch state. ✅ Stellar PASS on commit 4; Astral PASS on
  commit 3 (commit 4 only touches the stage1to4 actual-scoring path
  Astral already exercised; re-run as PR-open gate)
- Manual crash-resume verification — full Stellar 3-file pipeline
  run (5:38), simulated mid-PerFileScoring crash by deleting file
  20's `.scores.parquet` + downstream outputs, re-invoked same CLI,
  observed `[file] 2/3 ...21: skipping (outputs valid)` +
  `[file] 3/3 ...22: skipping (outputs valid)`, file 20 re-scored,
  pipeline completed in 4:28 (~70s saved on per-file skip). ✅
