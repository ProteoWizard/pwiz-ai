# TODO-20260514_osprey_pipeline_tasks.md — Phase C: worker convergence

> Continuation of **[TODO-20260511_osprey_pipeline_tasks.md](../completed/TODO-20260511_osprey_pipeline_tasks.md)**
> (Phase B core: resume-on-restart capability, merged 2026-05-14 via
> ProteoWizard/pwiz #4199). Phase B history and design decisions live
> there; this file describes the remaining Phase C work — fold the
> separate `RescoreWorker.Run` entry path into `AnalysisPipeline.Run`
> and finish what the Phase B design statement called for: "single
> canonical pipeline + StartAt/StopAfter + lazy rehydrate + per-file
> skip + worker convergence." First four landed in #4199; this is
> the fifth.

## Branch Information

- **Branch**: `Skyline/work/20260514_osprey_pipeline_tasks`
- **Base**: `master` (post-#4199 squash, currently at `a8d9111c5b`)
- **Created**: 2026-05-14
- **Status**: In Progress
- **PR**: (pending)

## Phase B core (what #4199 shipped) — short version

- Per-(output, task) `.osprey.task` JSON sidecars; the driver skips
  any task whose outputs all exist with a matching `validity_key`.
- `StartAtTask` / `StopAfterTask` on `PipelineContext` route CLI
  flags to a subrange of the invariant 4-task pipeline (replaces
  the discarded `IsWorkerMode` flag-gate).
- Lazy-rehydrate accessors call `Run(ctx)` once via a `_runOrHydrated`
  guard, so downstream consumers pulling state from a driver-skipped
  task get it from disk.
- Per-file skip inside `PerFileScoringTask.Run` via `ScoreOrLoadForFile`;
  a 1000-mzML crash on file 487 resumes by re-scoring only 487+.

Stellar + Astral snapshot regression PASS at every stage; Stellar
cross-impl Test-Regression PASS; manual crash-resume verified.

## Phase C — what this sprint does

### The shape change

Today `Program.Main` has a two-way dispatch:

```csharp
if (config.NoJoin && config.InputScores != null && config.InputScores.Count > 0)
{
    return RescoreWorker.Run(config);
}
return new AnalysisPipeline().Run(config);
```

That `if` is the artifact this sprint deletes. After Phase C:

- `RescoreWorker.Run` is one line: `return new AnalysisPipeline().Run(config);`
- `PerFileRescoreTask.RunWorker` body is deleted (the 200+ line worker
  body folds into the unified hydration path).
- `Program.Main` dispatches unconditionally to `AnalysisPipeline.Run`.
- `AnalysisPipeline.CanonicalPipeline()` is the single source of truth
  for the 4-task list (the only construction site for the array).
- CLI-mode branches inside task `Run` methods (the `if (joinOnly)` and
  `if (config.ExpectReconciledInput)` blocks) are deleted where the
  StartAt mechanism + lazy-rehydrate subsumes them.

### The hard part: unifying the two hydration paths

The reason this didn't ship in Phase B is that there are two parallel
load-from-disk code paths today producing different shapes of in-memory
state:

| Path | Reads | Produces |
|------|-------|----------|
| `PerFileScoring.joinOnly` (stage5 + stage7 today) | `.scores.parquet` | raw `FdrEntry` stubs + PIN features |
| `RescoreHydration.HydrateForRescore` (stage6 worker today) | `.scores.parquet` + `.1st-pass.fdr_scores.bin` + `reconciliation.json` | stubs with 1st-pass SVM overlay + parsed reconciliation actions + refined RT calibrations + gap-fill targets |

After Phase C, one unified hydration in `PerFileScoringTask.joinOnly`
dispatches **probe-the-disk**: for each `--input-scores` parquet,
check which sidecars are present next to it on disk and produce the
matching `RescoreInputs` shape:

- `.scores.parquet` only → raw stubs + PIN features (stage5 shape).
- `.scores.parquet` + `.1st-pass.fdr_scores.bin` → stubs with 1st-pass
  SVM overlay + parsed `reconciliation.json` (today's `HydrateForRescore`
  bundle).
- `.scores.parquet` + `.1st-pass` + `.2nd-pass` → 2nd-pass overlay
  (today's stage7 FirstJoin work moved upstream).

Probe cost is three `File.Exists` calls per file. The CLI mode is
incidental — what determines the right hydration is what an upstream
orchestrator wrote to disk. (This is exactly the Phase B principle:
mechanism-driven, not flag-driven.)

### Settled design decisions

These were the open questions from the predecessor TODO; they're
resolved here so the next session can start coding.

1. **`RescoreInputs` ownership: PerFileScoringTask owns it.** The
   joinOnly path computes the bundle and stores it on the task
   instance; `PerFileScoringTask` exposes `GetRescoreInputs(ctx)` and
   `FirstJoinTask`'s four lazy-rehydrate accessors
   (`GetReconciliationActions`, `GetRefinedCalibrations`,
   `GetPerFileGapFillForRescore`, and the consensus-targets accessor)
   read from it. Tied to task lifetime — no static caches.
2. **Hydration shape dispatch: probe-the-disk** (as described above).
   No CLI-mode enum threaded through; sidecar presence is the
   discriminator.
3. **Stage6-completion marker: the existing sidecar is the marker.**
   `<parquet>.PerFileRescore.osprey.task` already records "PerFileRescore
   wrote this parquet under validity_key X." A separate marker would
   duplicate that contract. The orchestrator (NextFlow — see below)
   checks for the `.PerFileRescore.osprey.task` sidecar's existence
   to decide whether a worker task is done.
4. **Per-file skip inside `PerFileRescoreTask.Run`: include it
   (folded into commit 4 or 5).** Mirrors Phase B's `ScoreOrLoadForFile`
   in `PerFileScoringTask`, so a single
   `OspreySharp --no-join --input-scores f1 f2 f3` invocation resumes
   mid-fan-in. Keeps the per-file mechanism symmetric across both
   loop-based tasks even though typical NextFlow fan-out is
   one-file-per-process.

## Implementation plan

Five commits, each gated by build + unit tests + Stellar snapshot
regression at every stage.

### Commit 1 — `TaskValiditySidecar` unit tests

Independent of the convergence refactor; lands first to underwrite the
rest of the sprint. Covers `Write` / `IsValid` / `Delete`:

- Round-trip (write, read back, verify validity_key match).
- JSON escape paths (paths with quotes, backslashes, control chars).
- Malformed-content rejection (truncated file, missing field,
  not-JSON garbage; each should produce `IsValid → false`, never
  throw).
- Missing-sidecar behavior (`IsValid → false`, not exception).
- Per-task naming collision (two writes to same `outputPath` with
  different `taskName` → two distinct sidecar files, neither
  overwrites the other).

Mirrors the existing `FdrScoresSidecar` test pattern in
`OspreySharp.Test/IOTest.cs`. Resolves Copilot thread #3221935440.

### Commit 2 — `AnalysisPipeline.CanonicalPipeline()` factory

Pure refactor; no behavior change. Move the 4-task array construction
out of `AnalysisPipeline.Run` into a static factory:

```csharp
internal static OspreyTask[] CanonicalPipeline() => new OspreyTask[]
{
    new PerFileScoringTask(),
    new FirstJoinTask(),
    new PerFileRescoreTask(),
    new MergeNodeTask(),
};
```

`AnalysisPipeline.Run` now calls `CanonicalPipeline()`. No other
caller in this commit. The single-source-of-truth property is the
point — when `RescoreWorker.Run` collapses in commit 4, it does NOT
re-state the task list.

### Commit 3 — hydration unification

The big one. `PerFileScoringTask`'s `joinOnly` branch grows the
probe-the-disk dispatch; `PerFileScoringTask` owns and exposes the
`RescoreInputs` bundle; `FirstJoinTask`'s four lazy-rehydrate accessors
read from it via `ctx.GetTask<PerFileScoringTask>().GetRescoreInputs(ctx)`.

- Move `RescoreHydration.HydrateForRescore` invocation into the
  joinOnly path (under the "1st-pass sidecar present" branch).
- Add `GetRescoreInputs(ctx)` to `PerFileScoringTask` with the
  same `_runOrHydrated` idempotency pattern.
- Update `FirstJoinTask`'s reconciliation-state accessors to read
  from the bundle.
- The current `FirstJoinTask.Run` ExpectReconciledInput branch's
  2nd-pass sidecar overlay moves to the joinOnly path (matching
  "2nd-pass sidecar present" probe).

Stage5, stage6 (still routed via `RescoreWorker.Run` at this commit),
and stage7 all need byte-identical snapshot output before and after.
This is the regression-risky commit — run Stellar snapshot at every
stage between this commit and the next.

### Commit 4 — worker entry-path collapse

- Delete `Program.Main`'s `if (NoJoin && InputScores)` branch.
- `RescoreWorker.Run` → `return new AnalysisPipeline().Run(config);`
  one-liner. Class stays (preserves the public entry point name in
  case anything outside OspreySharp references it).
- `PerFileRescoreTask.RunWorker` body deleted; method body becomes
  a one-line stub that throws (or the method is removed entirely if
  no caller references it).
- Add per-file skip inside `PerFileRescoreTask.Run`'s loop, mirroring
  `PerFileScoringTask.ScoreOrLoadForFile`: probe the per-file
  `.PerFileRescore.osprey.task` sidecar's validity_key; on match,
  skip rescoring that file and load its outputs from disk. This is
  what the manual stage6 crash-resume gate exercises.

Stage6 (`--no-join --input-scores`) now routes through
`AnalysisPipeline.Run` with `StartAt = StopAfter = PerFileRescoreTask`,
exercising the unified hydration from commit 3.

### Commit 5 — CLI-mode branch deletion

Remove the inside-task `Run` branches that the StartAt + lazy-rehydrate
+ unified hydration paths now subsume. Specifically:

- `PerFileScoringTask.Run`: the joinOnly path stays (it's now the
  unified hydration entry), but config-flag-based branches inside it
  collapse if any are redundant. The `if (config.ExpectReconciledInput)`
  decoy-skip optimization stays (it's a perf optimization not a
  dispatch).
- `FirstJoinTask.Run`: the `if (!config.ExpectReconciledInput)`
  Percolator gate and the `if (config.ExpectReconciledInput)`
  2nd-pass overlay block both go away (the overlay moved upstream
  in commit 3; the Percolator gate is now equivalent to "do I have
  pre-rescore stubs?", which the unified hydration determines).
- `PerFileRescoreTask.Run`: the `firstJoin.DidPlan(ctx)` self-gate
  stays (it's the only correct way to know whether reconciliation
  planning produced anything to act on).
- `MergeNodeTask.Run`: the `if (config.ExpectReconciledInput)` Pass2
  sidecar-load is already moved out by commit 3; verify no other
  references remain.

This is the cleanup commit. The risk is missing a branch and breaking
a mode. The snapshot regression catches that.

### (Optional) trivial P3 follow-ups

Fold these in where they land naturally, or skip if convenient:

- **try/finally around `Run`'s body** so `_runOrHydrated` resets on
  exception (PR #4199 Claude /review P3 item).
- **Comment the dead `--no-join + --input-scores` branch** in
  `AnalysisPipeline.DeriveStartAtTask` as Phase-C-staging — once
  commit 4 lands, that branch becomes live, so this comment instead
  becomes a removal of any "dead branch" note Phase B left.
- **Backport the `$aiRoot`-based fix-crlf invocation** to
  `Build-Skyline.ps1` (the existing version silently no-ops in the
  sibling-repo layout).
- **`version` skew check in `TaskValiditySidecar.IsValid`** — make
  the sidecar reader compare the stored `version` field against
  `Program.VERSION` with the same major/minor skew rules as the
  parquet metadata check.

## Validation gates (per commit)

- Build green; OspreySharp unit tests pass (303+/303+).
- Stellar 3-file snapshot regression PASS at every stage.

## PR-open gates

- Astral 3-file snapshot regression PASS at every stage.
- Stellar cross-impl Test-Regression PASS at every stage (Rust vs C#
  byte-equality).
- **Manual stage6 worker crash-resume verification.** Mirror the
  Phase B manual test, but for the worker path:
  1. Fan stage6 invocations across 3 file workers in parallel
     (3 separate `OspreySharp --no-join --input-scores …`
     processes against pre-staged stage5 outputs).
  2. After all 3 finish, delete one worker's `.scores.parquet` +
     its `.PerFileRescore.osprey.task` sidecar to simulate a
     mid-rescore crash on that file.
  3. Re-invoke the same CLI on just that file.
  4. Confirm: the surviving files (now upstream of nothing, since
     each worker handles one file) aren't touched; the deleted file
     is re-rescored and gets a fresh sidecar.
- No code in the OspreySharp pipeline references `IsWorkerMode` by
  any flag. The phrase "worker mode" survives only in doc comments
  describing CLI semantics.
- `RescoreWorker.Run` is one line.

## NextFlow integration contract

There's no end-user on OspreySharp HPC yet, but the likely consumer is
the MacCoss Lab's NextFlow pipeline orchestration project. NextFlow
caches task outputs and re-runs only what's missing. Phase C's job is
to make each OspreySharp worker invocation idempotent and resume-aware
so NextFlow's re-run logic does the right thing without bespoke
glue. The contract this PR creates with that orchestrator:

- **Idempotence**: re-invoking the same OspreySharp CLI on the same
  inputs is a no-op if the outputs (and their `.osprey.task`
  sidecars) are already present.
- **Per-file resume**: per-file outputs each carry their own
  `<output>.<TaskName>.osprey.task` sidecar; a deleted file's sidecar
  is the orchestrator's signal "this file needs to be re-run." The
  orchestrator does not need to know about pipeline stages — it
  needs to know "which files have a valid sidecar."
- **Stable exit code semantics**: success → 0, error → non-zero
  (today's contract; this PR preserves it).
- **No new CLI surface added**: stage6's invocation is unchanged.

## Phase C success criteria

- One pipeline entry point: `AnalysisPipeline.Run`. `RescoreWorker.Run`
  is one line; `Program.Main` has no NoJoin+InputScores dispatch.
- `PerFileRescoreTask.RunWorker` body deleted.
- `AnalysisPipeline.CanonicalPipeline()` is the single source of truth
  for the 4-task list.
- One hydration path: `PerFileScoringTask.joinOnly` probe-the-disk
  dispatch produces the right `RescoreInputs` shape for stage5,
  stage6, and stage7.
- All Phase B success criteria still hold (Stellar + Astral + cross-impl
  + per-file resume).
- Stage6 worker crash-resume verified manually.

## Progress Log

### 2026-05-14 — Design session, pre-work

Phase C scope and approach settled in a design-discussion session
before /clear. Branch not yet created; pwiz on master at `a8d9111c5b`
(post-#4199 squash).

- 5-commit plan agreed: TaskValiditySidecar tests → CanonicalPipeline
  factory → hydration unification → worker entry collapse →
  CLI-mode branch deletion. See "Implementation plan" above.
- Three design questions resolved: `RescoreInputs` ownership (option
  (a): PerFileScoringTask owns and exposes `GetRescoreInputs(ctx)`);
  hydration shape dispatch (probe-the-disk on sidecar presence, no
  CLI-mode enum); stage6-completion marker (none — the existing
  `.PerFileRescore.osprey.task` sidecar is the orchestrator's
  done-signal).
- NextFlow identified as the likely consumer; success criteria
  framed around the idempotence + per-file-resume contract that
  consumer needs.
- Trivial P3 follow-ups from the #4199 review listed as fold-in
  candidates rather than required commits. Style / DRY cleanup
  deferred to a separate post-Phase-C pass.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260514_osprey_pipeline_tasks.md` before starting work.

### 2026-05-14 — Sprint start

- Per-file-skip-in-`PerFileRescoreTask.Run` decision: include it,
  fold into commit 4. Reasoning: keeps the per-file mechanism
  symmetric with `PerFileScoringTask` and makes the manual
  3-file crash-resume gate exercise a single-process invocation
  rather than three separate ones.
- Branch `Skyline/work/20260514_osprey_pipeline_tasks` created
  from master at `a8d9111c5b`.

### 2026-05-14 — Commit 1 landed: TaskValiditySidecar unit tests

- 6 new tests in `OspreySharp.Test/IOTest.cs` (region
  `TaskValiditySidecar Tests`): round-trip, JSON escapes,
  missing-sidecar, malformed (4 shapes), per-task naming
  collision, Delete contract.
- 309/309 OspreySharp unit tests pass (was 303 before this commit).
- Stellar 3-file snapshot regression PASS at every stage.
- Resolves Copilot thread #3221935440 from #4199 review.
- Commit `e35f928a55`. Branch pushed.
