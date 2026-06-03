# TODO: Make the OspreySharp task dataflow explicit / lazy-rehydrate / driver-owned

**Status**: Active — PR-A1 MERGED (pwiz #4264 → `b2d4072ff1`, 2026-06-03); init-only
immutability deferred; PR-B (dataflow) + optional PR-C remain. See Progress.
**Priority**: Medium-strategic (no defect; the next-dominant structural issue once the
mega-methods are gone)
**Complexity**: Large (3-PR core; touches the task framework + every task + the resume/worker
model; each PR parity-gated)
**Created**: 2026-06-01
**Branch**: `Skyline/work/20260602_ospreysharp_config_identity` (pwiz) — PR-A: config
identity split + RunPlan.
**Scope**: `pwiz_tools\OspreySharp` — the task/pipeline layer (`OspreyTask`,
`PipelineContext`, `AnalysisPipeline`, the 4 concrete tasks). Framework types
(`OspreyTask`, `PipelineContext`, `TaskValiditySidecar`) live in the `OspreySharp.Tasks`
project; the 4 concrete tasks + `AbstractScoringTask` + `AnalysisPipeline` live in the
`OspreySharp` exe project under `Tasks\`.

## Progress — PR-A (branch `Skyline/work/20260602_ospreysharp_config_identity`)

Splitting "freeze config" (partner refactor #2) into verifiable slices, each byte-identical
(unit: 352 tests + inspection green; cross-impl e2e bit-parity at 1e-9 on Stellar 3-file via
`Compare-EndToEnd-Crossimpl -Files All -SkipRust`). **PR-A1 MERGED as pwiz #4264** (squash
`b2d4072ff1`, 2026-06-03) with the three commits below:

- **`a217284b79`** — extracted the SHA identity hashing (`SearchParameterHash` /
  `LibraryIdentityHash` / `ReconciliationParameterHash[ForStems]` + `EscapeForRustDebug`)
  out of `OspreyConfig` into a single-responsibility `SearchIdentity` (`.Core`).
- **`4aaa85e846`** — repointed all ~10 hash callers to `config.Identity` / `SearchIdentity`
  and removed the `OspreyConfig` delegators (+ fixed `<see cref>` docs).
- **`9df75088c1`** — moved `EffectiveFileParallelism` off `OspreyConfig` onto a new
  driver-owned `RunPlan` (`.Tasks`, exposed as `PipelineContext.RunPlan`).

**Full `OspreyConfig` init-only immutability — DEFERRED (decision 2026-06-02: ship PR-A1,
defer immutability).** The remaining mid-run mutations turned out to be a **load-bearing
in-place propagation pattern**, structurally like the deliberately-kept `_perFileEntries`
buffer: the MS2-calibrated `FragmentTolerance` is written back onto the per-file config clone
(`AbstractScoringTask.cs:527`) and read by ~15 downstream scoring sites through that shared
reference; per-file `NThreads` (`PerFileScoringTask.cs:1014`) is the same. Making the config
init-only would mean converting `:527` to a copy-with-change + verifying propagation to all
readers, relocating `NThreads`, restructuring `Program.cs` config-building to object-
initializers + a `net472` `IsExternalInit` shim, and resolving the join-only `InputFiles`
synthesis (`PerFileScoringTask.cs:235-240`) at parse time. Payoff: type-enforce a contract
that already works and whose only mid-run-mutated hash-affecting field (`FragmentTolerance`)
is already correctly scoped via `ShallowClone` (shared config keeps the configured value for
hashing; the clone gets the calibrated value for scoring). Marginal vs. the parity risk — so
deferred/likely-dropped, mirroring the `_perFileEntries` call. Revisit only if a concrete
defect motivates it.

**Parity-gate note (2026-06-02):** the C#-only gate appeared RED on master, but it was a
FALSE alarm — `-SkipRust` had reused a stale **single-file** Rust reference against a 3-file
C# run (proven: fresh 3-file Rust vs 3-file C# = OVERALL PASS at 1e-9; C# branch-vs-master
also byte-identical). A stale-reference guard now fails the gate fast on a file-set mismatch
(ai commit `5c1cee7`), and the cached Stellar reference is regenerated to 3-file. See
`feedback_ospreysharp_csharp_regression_gate`.

### 2026-06-03 — PR-A1 merged

PR #4264 merged (squash `b2d4072ff1`). Shipped the `SearchIdentity` responsibility split + the
`RunPlan` seam (`EffectiveFileParallelism` moved off `OspreyConfig`), all parity-verified (352
tests + inspection; cross-impl 1e-9 on Stellar 3-file; C#-vs-C# byte-identical). Copilot (2 doc
nits) + fresh-context self-review (clean — byte-identical hash compare + Rust cross-check) both
addressed. **Deferred:** full `OspreyConfig` init-only immutability (the per-file
`FragmentTolerance`/`NThreads` load-bearing in-place propagation — see above). This umbrella
TODO stays Active for **PR-B** (the lazy-rehydrate / `IsIncluded` dataflow change) and the
optional **PR-C** (retire `GetTask<T>()`).

## Why this exists (and why it's iteration N, not a one-off)

A **second, independent OOP review (2026-06-01)** ran three reviewers cold — no
knowledge of the first (2026-05-29) review or the decomposition program (#4249-#4262).
They converged tightly: **"Solid-with-issues," maintainability 5-6/10, Modularity
unanimously Strong.** Critically, **none of the three flagged the orchestration
mega-methods** that were the first review's #1 concern — confirming the PR-B
decomposition landed. Freed from that, all three re-anchored on the next layer down.

This iterative pattern is expected. The upstream Rust `osprey` grew **organically** —
feature-cycle pairing (an inexperienced programmer + Claude), progressively adding
capability. That mode reliably accretes unstructured code; the mechanism that keeps it
maintainable as it grows is exactly this kind of periodic OOP review, applied in
iterations. Each pass fixes the dominant structural issue, which then exposes the next
one underneath (like perf work: the next bottleneck is only visible once the dominant
one is fixed). So expect more iterations as the code keeps growing — this TODO is
iteration 2's headline finding. See [[TODO-ospreysharp_task_layer_decomposition]] for
iteration 1 and [[project_osprey_organic_growth_needs_iterative_oop_review]].

## The finding: 3/3 independent reviewers named the same next-dominant issue

The task pipeline *looks* like a clean linear list of 4 tasks, but the real
producer->consumer dependency graph is an **implicit, side-effecting mesh**:
- Tasks find each other by concrete type via `ctx.GetTask<T>()` (`PipelineContext.cs:179`)
  — a typed service-locator (~9 call sites; e.g. `MergeNodeTask` pulls from both
  `PerFileRescoreTask` and `PerFileScoringTask`; `FirstJoinTask` pulls reconciliation
  state through `PerFileScoringTask`).
- Those accessors trigger `EnsureHydrated -> Run` (`PerFileScoringTask.cs:171`,
  `FirstJoinTask.cs:147`), so a **getter silently executes an entire upstream stage**
  (or rehydrates it from disk). This is the core "Claude-ism" the refactor removes:
  *compute should never be a hidden side-effect of asking for state.*
- One buffer (`_perFileEntries`) is mutated in place by three tasks.

So execution order, resume behavior, and correctness all hinge on side-effecting getters
whose dependencies appear nowhere in type signatures — only `Inputs`/`Outputs` (declared
for the sidecar resume system) hint at them. A newcomer can't read the dataflow off the
task definitions; it lives in comments + call sites. Resume/worker behavior additionally
hinges on 5 CLI-flag branches in `DeriveStartAt/StopAfterTask` (`AnalysisPipeline.cs:131-170`).

## The agreed design: declarative, lazy-rehydrate, driver-owned

Tasks declare their files and own *how* they compute (`Run`) and *how* they reload
(`Rehydrate`). The orchestrator owns *which* tasks this node should run (`IsIncluded`). The
**context owns rehydration at request time** — a task asks the context for another task's
state, and the context loads it from disk on demand if that task was skipped. This is the
team's proven 2008 HPC-pipeline model: each task declares its input/output files, the
pipeline skips completed tasks by output presence, and tasks never reach forward.

**The decisive design constraint:** `Run` is called from the outer loop **and nowhere
else**. Compute is never a hidden side-effect of requesting state. The only thing the
context may trigger lazily is `Rehydrate`, which merely loads artifacts the context has
already verified exist and are valid — not "secretly run a stage."

```csharp
// The ONLY place Run is called. Reads as: "run the tasks this node was told to
// run, unless their artifacts already exist with valid sidecars."
foreach (var task in canonicalPipeline.Where(IsIncluded))
    if (!ctx.CanRehydrate(task))   // task.Outputs(ctx) all present + ValidityKey matches
        task.Run(ctx);             // compute into shared ctx state

// Lazy rehydration, owned by the context, at request time:
public T Demand<T>() where T : OspreyTask
{
    var producer = _producers[typeof(T)];
    if (_materialized.Add(typeof(T)))   // first request for a not-yet-run task
        producer.Rehydrate(ctx);        // load its artifacts (CanRehydrate held → they exist)
    return (T)producer;                 // pure accessors now safe to read
}
```

### Ownership contract

| Method / predicate | Owner | When it fires |
|---|---|---|
| `Run(ctx)` | **outer loop only** | included task whose artifacts aren't present/valid |
| `Rehydrate(ctx)` | **context, lazily** | a consumer first `Demand<T>()`s a skipped task's state |
| `CanRehydrate(task)` | context predicate | `task.Outputs(ctx)` present + `ValidityKey` matches — today's `IsTaskAlreadyDone` (`AnalysisPipeline.cs:245`) |
| `IsIncluded(task)` | orchestrator | node membership from `RunPlan`/CLI — the tasks to **run** here; replaces the 5-branch `Derive*Task` ladder |
| `Outputs(ctx)` / `ValidityKey(ctx)` | task | declarations (already on `OspreyTask`, `OspreyTask.cs:84-132`) |
| `Run(ctx)` / `Rehydrate(ctx)` impls | task | task owns *how* to compute and *how* to reload its own artifacts |

### How the worker modes fall out

`IsIncluded` enumerates only the tasks to **run**; dependencies rehydrate lazily via the
context, so `IsIncluded` need not list rehydrate-only upstreams. It is purely the "don't
compute past my goal" boundary (the old `StopAfter`). This is what stops a rescore worker
from running `MergeNode`.

| Mode (CLI) | `IsIncluded` (runs) | Rehydrated on demand |
|---|---|---|
| straight-through | all 4 | none — every upstream `Demand` hits an already-run task |
| per-file scoring (`--no-join`) | `{PerFileScoring}` | none |
| join-only (`StopAfterStage5`) | `{FirstJoin}` | `PerFileScoring` (from `.scores.parquet`) |
| rescore worker (`--no-join --input-scores`) | `{PerFileRescore}` | `FirstJoin` (`reconciliation.json`) + `PerFileScoring` (buffer) |
| merge (`--join-at-pass=2`) | `{MergeNode}` | `PerFileRescore` + `PerFileScoring` (library); **`FirstJoin` never demanded** |

The `--join-at-pass=2` "FirstJoin is skipped" case becomes just *absence of demand* — no
special rule, no lazy-getter accident. Today it works only because MergeNode happens not to
touch FirstJoin (an emergent property); the new model makes it explicit.

### What disappears (the readability wins)
- `EnsureHydrated` and the **side-effecting getters** → getters become pure reads; the only
  lazy action is `Rehydrate` (load), never `Run` (compute).
- `GetTask<T>()` side-effecting lookup → `ctx.Demand<T>()`, with the lazy load owned by the
  context.
- `DeriveStartAtTask` / `DeriveStopAfterTask` (the 5-branch ladder) → replaced by
  `IsIncluded`.

### What is preserved (hard constraints)
- **Load-bearing shared buffer.** `_perFileEntries` stays one shared, in-place-mutated
  instance (`PerFileScoringTask.cs:141-148` — "Do NOT fix to IReadOnly / return a copy"; the
  no-copy hand-off is a measured Astral-scale perf win). It lives on `ctx`; whichever of
  `Run`/`Rehydrate` fires writes that one instance, and the next task mutates it in place.
  Consumers demand the **last mutator** (e.g. MergeNode demands `PerFileRescore`, not
  `PerFileScoring`), so keying `Demand<T>()` by producing task preserves the
  scored→compacted→rescored ordering through the demand edges — the data type alone could
  not disambiguate which stage's version you want.
- **Both parity gates green per PR.** C#-only `Compare-EndToEnd-Crossimpl` (byte-identical
  blib + Stage 7 protein-FDR dump at 1e-9, in-memory straight-through) AND the
  in-memory-vs-HPC rehydrate parity gate (resume path). No unilateral tolerance loosening —
  bisect drift first (`feedback_bit_parity_tolerance`).
- **Bit-parity hashing** stays byte-identical with Rust (invariant culture, `{:?}` escaping,
  lowercase bools — `OspreyConfig.cs:214-304`). All worker modes run the same task set
  before/after the refactor; this re-architects *how* dependencies are expressed, not *what*
  runs (`feedback_parity_vs_impact`).

## PR decomposition (3-PR core)

- **PR-A — Freeze config → `RunPlan` + `SearchIdentity` (this is partner refactor #2).**
  Extract the bit-parity SHA hashing into a `SearchIdentity` value object; move the 3
  mid-run-mutated fields (`EffectiveFileParallelism`, synthesized `InputFiles`, per-file
  calibrated `FragmentTolerance`) into a per-run `RunPlan` (+ a small per-file
  `ScoringContext` for the calibrated tolerance — confirm no name collision with the
  existing `OspreySharp.Scoring\ScoringContext.cs`). `OspreyConfig` becomes immutable
  post-parse, type-enforcing the prose mutation contract at `PipelineContext.cs:54-72`.
  *Why first:* de-risks PR-B by giving `IsIncluded`/`CanRehydrate` stable, authoritative
  inputs and a drift-proof `ValidityKey`. *Parity:* the SHA byte-sequence must stay
  character-identical — add a unit assert that `SearchIdentity` hashes equal the
  pre-refactor `OspreyConfig` hashes on a fixture config, then the end-to-end parity run
  confirms. *Files:* `OspreyConfig.cs`, new types in `.Core`, `PipelineContext.cs`,
  `PerFileScoringTask.cs:275-279,1001`, `PerFileRescoreTask.cs:635,1042`,
  `AnalysisPipeline.cs:131-170`, `OspreyTask.cs:128-131`. *Effort: medium. Payoff: high.*

- **PR-B — The dataflow change (the headline).** Add `Rehydrate(ctx)` to `OspreyTask`; in
  each task, split the probe-disk path out of `Run`/`EnsureHydrated` into `Rehydrate`,
  leaving `Run` compute-only. Make the producer getters pure reads; add `ctx.Demand<T>()`
  (lazy rehydrate) + `ctx.CanRehydrate(task)`; replace the driver loop with
  `Where(IsIncluded)` + `if (!CanRehydrate) Run`; delete `EnsureHydrated`, the `GetTask<T>()`
  side-effecting accessors, and `DeriveStartAt/StopAfterTask`. *Riskiest part:* `IsIncluded`
  must reproduce **exactly** which tasks run in each of the 5 modes — keep the old
  `Derive*Task` as a test oracle until parity is proven. *Files:* `OspreyTask.cs`, all 4
  tasks, `AnalysisPipeline.cs`, `PipelineContext.cs` (host shared state, `Demand`,
  `CanRehydrate`, `IsIncluded`). *Effort: large. Payoff: high.*

- **PR-C (optional, last).** Move the shared state from task fields fully onto `ctx` so
  consumers read products directly rather than `Demand<T>()`-then-accessor. Most deferrable;
  only after PR-B proves out. The 80/20 readability win is fully banked at PR-B — `Run` is
  loop-only, getters are pure, the DAG is readable off `IsIncluded` + the `Demand` edges, and
  the 5-branch ladder is gone. PR-C is polish.

## Partner refactors (sequencing)

1. **#2 — immutable `OspreyConfig` → `RunPlan`/`ScoringContext`.** Promoted to **PR-A above**
   (the de-risking lead): type-enforces the mutation contract and stabilizes the inputs to
   `IsIncluded`/`CanRehydrate`/`ValidityKey`.
2. **#3 — inject an `IDiagnosticsSink`** instead of the static `OspreyDiagnostics.WriteXxx`
   woven through the hot scoring loops (process-global mutable state; couples the hot path to
   file I/O; no-op default keeps production clean). **Independent parallel track** — it does
   *not* de-risk the dataflow change, so land it on its own and do **not** interleave it with
   PR-A/B (keeps parity-bisects clean; it carries its own hot-loop bit-parity risk in the
   dump formatting: LF newline, F10/ryu). *Effort: medium. Payoff: medium.*
3. **#1 — extract the scoring engine out of `AbstractScoringTask`** (2,732-LOC god-base, ~2,400
   scoring lines) into a `.Scoring` engine class (`CoelutionScoringEngine` or similar). The
   scoring lines are a *service the tasks invoke*, not task logic. Bonus: dissolves
   `FirstJoinTask`'s inheritance-for-utility — it extends `AbstractScoringTask` but uses none
   of the scoring engine, only `_ctx` + shared constants (`FirstJoinTask.cs:1126,1158,1381`).
   **Deferred** until the Skyline-shared-scoring direction
   ([[TODO-ospreysharp_skyline_shared_scoring]]) is settled, since #1 would land in a seam
   possibly destined for sharing. The dataflow refactor (PR-A/B) does **not** depend on it.
   *Effort: large. Payoff: high (when unblocked).*

(Reviewers split on whether to move the 4 concrete tasks into the `OspreySharp.Tasks`
project; one called it a discoverability fix, another called the current split sound — and
the EXE-stays-standalone decision makes "concrete tasks in the exe" a non-issue. Low
priority either way; see [[project_ospreysharp_exe_and_shared]],
[[project_ospreysharp_dll_boundaries_vs_sharing]].)

## Honest "is it worth it?" (skeptic check kept on the record)

1. **The parity gates are the real spec and already enforce correctness.** This refactor buys
   readability/maintainability, not capability. The ROI is "easier to add the next worker
   mode / 5th task"; if that demand never comes, the 5-branch `Derive*Task` (37 commented
   lines) is comprehensible as-is. Justified by the iterative-review thesis (organic growth
   *will* keep adding capability), not by a present defect.
2. **The shared-buffer constraint fights the declarative ideal.** The headline state is a
   deliberately-mutated shared reference, so the design can *describe* the in-place chain
   (consume + produce the same logical buffer) but cannot *enforce* the usual produce-once /
   read-after invariant for the one piece of state that matters most. Real risk: a future
   maintainer "cleans up" the shared slot to copy and regresses Astral-scale perf. The
   `PerFileScoringTask.cs:141-148` comment must travel with the buffer onto `ctx`.
3. **Bit-parity tax.** Each PR is a parity-bisect surface. The 3-PR core keeps that surface
   small; do not expand it by interleaving #3 or attempting #1 in the same arc.

## Constraints / cautions

- **Bit-parity is the hard gate.** The scoring code is saturated with Rust bit-for-bit
  invariants (exact eval order, `>=`-on-tie selection); the dense comments are load-bearing.
  Any refactor here is mechanical-but-delicate and must stay byte-identical under both the
  C#-only `Compare-EndToEnd-Crossimpl` gate AND the in-memory-vs-HPC rehydrate parity gate.
- The `GetTask<T>()` service-locator's *payoff* is the lazy-rehydrate that unifies worker-mode
  and straight-through. The replacement (`Demand<T>()` + context-owned `Rehydrate`) must
  preserve resume/worker/`--join-at-pass` semantics exactly — this is a re-architecture of
  *how* dependencies are expressed, not a change to *what* runs.
- Sequence #1 (scoring-engine extraction) after the DLL/shared-scoring direction is decided;
  PR-A/B are independent of it.

## Divergence from the first review to keep in mind

The 2026-06-01 group was **less forgiving** than the 2026-05-29 review on two items the
first explicitly waved through as "cohesive": `OspreyConfig` (mutable bag that also owns SHA
identity hashing — two responsibilities, now split in PR-A) and `OspreyDiagnostics` (2K-LOC
static dumping ground — addressed by partner #3). Not a unanimous "those are fine"; weigh
accordingly.

## Related

- [[TODO-ospreysharp_task_layer_decomposition]] — iteration 1 (mega-methods, #4249-#4262)
- [[TODO-ospreysharp_assembly_consolidation]], [[TODO-ospreysharp_skyline_shared_scoring]]
- Memory: `feedback_ospreysharp_csharp_regression_gate`, `feedback_parity_vs_impact`,
  `feedback_bit_parity_tolerance`, `feedback_ospreysharp_precommit`,
  `project_osprey_organic_growth_needs_iterative_oop_review`
