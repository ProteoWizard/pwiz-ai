# TODO: PR-C — typed byproduct context (retire GetTask/_runOrHydrated)

**Status**: Active — not started. Successor to PR-B (#4266, the declarative-dataflow
refactor). Start in a FRESH session.
**Priority**: Medium-strategic (no defect; the next OOP slice once PR-B's explicit dataflow
lands). This is iteration N+1 of the recurring OspreySharp OOP-review program.
**Branch (to create)**: `Skyline/work/<YYYYMMDD>_ospreysharp_byproduct_context` in `C:\proj\pwiz`.
**Origin**: user's design idea during PR-B (2026-06-03) — mirror Skyline's
`PeakScoringContext.AddInfo<TInfo>`/`TryGetInfo<TInfo>`. See memory
`project_ospreysharp_byproduct_context_prc` and `project_ospreysharp_runtime_parity`.

## The goal

Replace the producer-task **getter** surface PR-B landed (`ctx.Demand<T>().GetX(ctx)`) with a
typed **byproduct cache** on `PipelineContext`, modeled on
`pwiz_tools/Skyline/Model/Results/Scoring/IPeakScoringModel.cs:761` `PeakScoringContext`:
`Dictionary<Type,object>` + `AddInfo<TInfo>(TInfo)` (publish-once) + `TryGetInfo<TInfo>(out)`.
Keyed by the **byproduct value type** (`RescoreInputs`, `ReconciliationActions`, …), NOT by
producer task type. Producers publish; consumers `GetInfo<T>()` without knowing the source.

**Primary win:** dissolves FirstJoin's dual-source getter fallbacks (the
`if (_didPlan) return _x; else return bundle.X` branches that exist only because the same
value has two producers) and the consumer-reaches-through-producer Demeter coupling.

## Two design constraints (do NOT lose — both bit PR-B)

1. **Lazy rehydrate-from-disk.** `PeakScoringContext` has no disk fallback (`TryGetInfo`
   returns false on miss). OspreySharp workers start mid-pipeline and must lazily load a
   *skipped* producer's byproducts from sidecars. Keep a **type→producer-task registry** so a
   `GetInfo<T>` miss `Demand`s/`Rehydrate`s the producing task (which then `AddInfo<T>`s).
   `Demand<Task>` survives as the INTERNAL mechanism; the PUBLIC surface becomes `GetInfo<T>`.
   Coupling moves from ~15 consumer sites to one registration point.
2. **The load-bearing mutable `_perFileEntries`** (single List, mutated in place by
   PerFileScoring→FirstJoin compact→PerFileRescore overlay; no-copy for Astral perf,
   PerFileScoringTask.cs ~141-148). It is the ONE mutable byproduct (publish-once, mutated
   through the shared ref) — a documented exception. Do NOT model its mutations as fresh
   byproduct versions; that forces the copies the no-copy design avoids.

## Fold in from PR-B (deferred items — address as part of PR-C)

- **Retire `_runOrHydrated`.** PR-B kept it (load-bearing: it coordinates the driver-`Run`
  path with the `Demand`-`Rehydrate` path so a producer the driver already ran is a no-op on
  Demand). The clean removal is a **mark-materialized-in-RunTask** refactor: have the driver's
  `RunTask` add the task type to `ctx._materialized` so a later `Demand` skips `Rehydrate`;
  then the per-task `_runOrHydrated` guard is redundant. Do this alongside the byproduct move.
- **`Demand` swallows `Rehydrate`'s bool** (Copilot #145 / self-review LOW #3 on #4266). A
  failed rehydrate (library load fail, empty scores → `ExitCode` set) is currently ignored;
  consumer proceeds with default-empty state. Pre-existing pattern (old `EnsureHydrated`
  ignored `Run`'s bool too). Fix when the materialization mechanism is reworked here.
- **`IsIncluded` membership relies on the CLI rejecting `--join-only` without `--input-scores`**
  (Copilot #178-adjacent / self-review LOW #2). The oracle truth table
  (`PipelineMembershipTest.cs`) does not encode that cross-file invariant. Add a guard/comment
  or a CLI-rejection test when touching membership.
- **`FinalizeAndCheck` applies the `--no-join` stop in the rehydrate path** (Copilot #178) —
  benign today (Demand ignores the bool; rescore-worker gate byte-identical) but becomes real
  if the `Demand`-checks-return change above lands. Re-evaluate together.

## Separate (NOT PR-C, but related): pre-existing resume bug

`ai/todos/backlog/TODO-ospreysharp_straightthrough_resume_1stpass_rt.md` — straight-through
resume writes 1st-pass RTs (`ExecuteRescore` per-file skip leaves `_perFileEntries`
un-overlaid for MergeNode). Pre-existing on master; surfaced + filed during PR-B's
self-review. Confirmed (2026-06-03) straight-through resume IS supported, so it is a real bug.
Needs its own parity-gated fix + a straight-through-resume smoke (the gate coverage gap).

## How to verify (same gates as PR-B)

- Pre-commit: `pwsh -File C:/proj/ai/scripts/OspreySharp/Build-OspreySharp.ps1 -RunTests -RunInspection`
  (353 tests + inspection; ~30s). Run from `C:\proj`, or use the absolute path if cwd is `pwiz`.
- Same-impl byte parity:
  `C:/proj/ai/scripts/OspreySharp/Compare/Compare-Stage7-Rehydration-Strict-CSharp.ps1 -Dataset Stellar -Framework net8.0 -Force`
  (the worker-mode oracle restored at PR-B's B0; default net8.0 = canonical runtime). Run on
  Astral too before the riskiest step. Stage-5 truth hashes have been `0C353A72CBCC` / … and
  must stay unchanged.
- Cross-impl: `Compare-EndToEnd-Crossimpl.ps1 -Files All -SkipRust -Framework net8.0` (1e-9 vs
  cached Rust; precursors 59768 Stellar 3-file).
- `IsIncluded` is pinned by `PipelineMembershipTest.TestIsIncludedMembershipTable`.

## Handoff state (2026-06-04)

- **PR-B = pwiz #4266**, branch `Skyline/work/20260603_ospreysharp_dataflow`. CI passing; being
  squash-merged (`--auto`). 10 commits (B1–B6 + self-review NPE fix `fd5012a805`), byte-identical
  on Stellar AND Astral. After it lands: `git -C C:/proj/pwiz checkout master && git pull`,
  `git branch -d` the work branch, move
  `ai/todos/active/TODO-20260601_ospreysharp_declarative_pipeline_dataflow.md` → `completed/`.
- The umbrella TODO (`TODO-20260601_...`) has the full B0–B6 progress log + the PR-C shaping.
- PR-A1 (`SearchIdentity` + `RunPlan`) merged as #4264 (`b2d4072ff1`).
- Memories to read first: `project_ospreysharp_byproduct_context_prc`,
  `project_ospreysharp_runtime_parity`, `feedback_bit_parity_tolerance`,
  `feedback_ospreysharp_csharp_regression_gate`, `project_osprey_organic_growth_needs_iterative_oop_review`.

## Related
- `ai/todos/active/TODO-20260601_ospreysharp_declarative_pipeline_dataflow.md` (PR-A/B umbrella)
- `ai/todos/backlog/TODO-ospreysharp_straightthrough_resume_1stpass_rt.md`
