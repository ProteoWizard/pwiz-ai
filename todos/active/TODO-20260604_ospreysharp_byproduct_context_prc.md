# TODO: PR-C — typed byproduct context (retire GetTask/_runOrHydrated)

**Status**: PR open — [#4267](https://github.com/ProteoWizard/pwiz/pull/4267) (in review).
Successor to PR-B (#4266, the declarative-dataflow refactor).
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

## Progress Log

### 2026-06-04 — C0–C7 implemented on branch `Skyline/work/20260604_ospreysharp_byproduct_context`

Executed the full plan, one parity-gated commit per concern. Branch off the
#4266 merge (`23d196a762`).

- **C0** — Re-confirmed the baseline on the fresh tree: build + 353 tests +
  inspection; worker-mode strict bit-parity (Stellar net8.0, Stage-5 truth hash
  `0C353A72CBCC` reproduced); Compare-EndToEnd 1e-9 (59768). No code.
- **C1** (`2ddec933d4`) — `Publish<T>`/`TryGet<T>`/`Get<T>` on `PipelineContext`
  (modeled on Skyline `PeakScoringContext.AddInfo`/`TryGetInfo`) + a
  byproduct→producer registry built from a new `OspreyTask.Publishes`. `Get<T>`
  resolves a cache miss by demanding the registered producer (whose `Rehydrate`
  publishes). `Demand<T>` refactored to a runtime-`Type` core (`DemandByType`)
  the registry shares. **The registry is the answer to "by-byproduct lookup, so
  which class do I rehydrate?"** — the named-byproduct → producer-task map, which
  `PeakScoringContext` never needed (it has no skipped producers / disk rehydrate).
- **C2+C3** (`9c2c8f6235`) — ~13 named byproduct purpose types (collision: two are
  `IReadOnlyDictionary<string,RTCalibration>`). **Design refinement (Brendan's
  idea):** the one mutable shared buffer became a three-milestone state hierarchy
  — abstract `PerFileEntries` base + `ScoredEntries` → `CompactedEntries` →
  `RescoredEntries`, each published once by its single producing task over the
  same no-copy backing list. This **dissolved the registry exception entirely**
  (the buffer now resolves uniformly; my first cut had left it out of the
  registry and used explicit demand). Producers `Publish` on both Run and
  Rehydrate paths and declare `Publishes`. Additive; byte-identical.
- **C4+C5** (`434b4a5e22`) — Switched all ~15 consumer sites to `ctx.Get<T>()`;
  the milestone type now *selects the producer*: FirstJoin.Run reads
  `ScoredEntries`, PerFileRescore.Run reads `CompactedEntries` (triggers
  FirstJoin), MergeNode reads `RescoredEntries` (triggers PerFileRescore — the
  merge-mode materialization), and PerFileRescore's merge-mode Rehydrate reads
  `ScoredEntries` so it does NOT materialize FirstJoin (the "merge mode must not
  re-run Stage 5" invariant is now a type choice, not a comment). Deleted the
  dead surface: FirstJoin's four dual-source getters (`_didPlan ? computed :
  bundle.X` collapse into one slot each), PerFileScoring's six getters,
  PerFileRescore's `GetPerFileEntries`, `PipelineContext.GetTask<T>`.
- **C6** (`acf687b427`) — Retired per-task `_runOrHydrated`: the driver now calls
  `ctx.MarkMaterialized(task)` after each `task.Run`, so `_materialized` is the
  single guard coordinating the driver-Run and lazy-Rehydrate paths.
- **C7** — Folded-in PR-B deferrals: (1) `DemandByType` throws
  `RehydrateFailedException` when a lazily-driven Rehydrate fails *with
  ExitCode != 0* (surfaces previously-silent worker-materialization failures;
  success-stops with ExitCode 0 stay benign — verified against `FinalizeAndCheck`
  publish-before-stop); (2) comment in `FirstJoin.IsIncluded` documenting the
  CLI-enforced `StopAfterStage5 ⟹ InputScores` invariant, pinned by the existing
  `ProgramTests.TestValidateJoinOnlyRequiresInputScores`; (3) new
  `ByproductContextTest` (3 tests) pinning the throw/benign-stop discriminator
  and publish-once. 356 tests total.

Each behavioral step gated green: build + tests + inspection, worker-mode strict
(Stellar), Compare-EndToEnd 1e-9.

### 2026-06-04 — Final validation + PR opened (#4267)

- **Correctness**: worker-mode strict bit-parity (Stellar net8.0, Stage-5 `0C353A72CBCC`) +
  Compare-EndToEnd 1e-9 (59768) green on the clean-rebuilt branch.
- **A rare pre-existing flake surfaced** during the first final-validation run: a one-off
  heap-corruption-class `InvalidCastException` in the Percolator→protein-FDR path (code
  UNCHANGED by PR-C). Clean PR-C was **0/20** on the exact failing `--join-only` command; the
  single failure was on an incrementally-built binary that then *passed* on re-run. User call:
  accept as a pre-existing rare flake, file separately → filed
  `ai/todos/backlog/TODO-ospreysharp_percolator_proteinfdr_rare_heap_corruption.md`. (Lesson:
  I over-reached calling it a "race"; corrected to "non-deterministic, mechanism unknown" once
  investigation showed the parallel infra is thread-safe.)
- **Perf gate** (single-run Astral side-by-side, C#, same machine): PR-C **1057.9s** vs master
  HEAD **1064.8s** — no regression (PR-C marginally faster, incl. stage6 the no-copy buffer).
  A Rust anchor (unchanged) confirmed the environment was stable (1464.7s vs published 1466s).
  Side-finding: a ~9% C# `stage1to4` regression from the *earlier* PR-A/B sprint (not PR-C) →
  filed `ai/todos/backlog/TODO-ospreysharp_sprint_stage1to4_perf_regression.md`.
- **PR opened**: [#4267](https://github.com/ProteoWizard/pwiz/pull/4267) — 5 commits (C1, C2+C3,
  C4+C5, C6, C7) off the #4266 merge.

## Related
- `ai/todos/active/TODO-20260601_ospreysharp_declarative_pipeline_dataflow.md` (PR-A/B umbrella)
- `ai/todos/backlog/TODO-ospreysharp_straightthrough_resume_1stpass_rt.md`
