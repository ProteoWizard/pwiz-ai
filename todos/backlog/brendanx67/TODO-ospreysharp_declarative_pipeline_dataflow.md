# TODO: Make the OspreySharp task dataflow explicit / driver-owned (the next OOP iteration)

**Status**: Backlog (design + large refactor — not yet a coding task)
**Priority**: Medium-strategic (no defect; the next-dominant structural issue once the
mega-methods are gone)
**Complexity**: Large (touches the task framework + every task + the resume/worker model)
**Created**: 2026-06-01
**Scope**: `pwiz_tools\OspreySharp` — the task/pipeline layer (`OspreyTask`,
`PipelineContext`, `AnalysisPipeline`, the 4 concrete tasks)

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
iteration 2's headline finding.

## The finding: 3/3 independent reviewers named the same next-dominant issue

The task pipeline *looks* like a clean linear list of 4 tasks, but the real
producer->consumer dependency graph is an **implicit, side-effecting mesh**:
- Tasks find each other by concrete type via `ctx.GetTask<T>()` (`PipelineContext.cs:179`)
  — a typed service-locator (~10 call sites; e.g. `MergeNodeTask` pulls from both
  `PerFileRescoreTask` and `PerFileScoringTask`; `FirstJoinTask` pulls reconciliation
  state through `PerFileScoringTask`).
- Those accessors trigger `EnsureHydrated -> Run` (`PerFileScoringTask.cs:171`,
  `FirstJoinTask.cs:147`), so a **getter silently executes an entire upstream stage**
  (or rehydrates it from disk).
- One buffer (`_perFileEntries`) is mutated in place by three tasks.

So execution order, resume behavior, and correctness all hinge on side-effecting getters
whose dependencies appear nowhere in type signatures — only `Inputs`/`Outputs` (declared
for the sidecar resume system) hint at them. A newcomer can't read the dataflow off the
task definitions; it lives in comments + call sites.

## The proposal: declarative, driver-owned dataflow

Have each task **declare the typed artifacts it consumes and produces**; the **driver**
resolves/validates that DAG up front and owns rehydration, instead of tasks reaching
sideways through getters that lazily re-run upstream `Run`. Concretely:
- A task publishes typed outputs to the context (or a `PipelineArtifacts` record); it
  declares typed inputs it requires.
- The driver wires producer->consumer, validates the DAG (no cycles, all inputs
  produced), and decides compute-vs-rehydrate-from-disk explicitly (the validity-key
  sidecar system already exists — `AnalysisPipeline.cs:191-256` — it just isn't the
  thing that drives dependency resolution).
- Lazy `EnsureHydrated`-in-a-getter becomes an explicit "load this artifact" step.

Payoff: the actual DAG becomes readable from the task definitions; resume/worker modes
become a property of the declared graph rather than 5 CLI-flag branches in
`DeriveStartAt/StopAfterTask`; adding a 5th task or an alternate pipeline shape becomes a
checked contract instead of "works because the 4 hardcoded tasks happen to be ordered
right and hydrate on demand."

**This is the "option C / driver-owned-skip" model** noted as a deferred future
initiative in [[TODO-ospreysharp_task_layer_decomposition]] — and it independently
reproduces Brendan's own 2008 pipeline-architecture instinct (each task provides its
input/output files; the pipeline handles skipping completed tasks; tasks do NOT reach
forward). Three cold reviewers re-derived it as the top next move.

## Partner refactors the same review surfaced (sequence alongside or before)

1. **Extract the scoring engine out of `AbstractScoringTask`** (2,732-LOC god-base) into
   a `.Scoring` engine class (`CoelutionScoringEngine` or similar). The ~2,400 scoring
   lines are a *service the tasks invoke*, not task logic. Bonus: dissolves
   `FirstJoinTask`'s inheritance-for-utility — it extends `AbstractScoringTask` but uses
   none of the scoring engine, only `_ctx` + shared constants
   (`FirstJoinTask.cs:1126,1158,1381`). Makes the numerics independently testable. The
   bit-parity comments move with the code intact. *Effort: large. Payoff: high.*
2. **Make `OspreyConfig` immutable post-parse** — move mid-run mutated fields
   (`EffectiveFileParallelism`, calibrated `FragmentTolerance`, synthesized `InputFiles`)
   into a per-run `RunPlan`/`ScoringContext`, type-enforcing the prose mutation contract
   (`PipelineContext.cs:54-72`). *Effort: medium. Payoff: high.*
3. **Inject an `IDiagnosticsSink`** instead of static `OspreyDiagnostics.WriteXxx` woven
   through the hot scoring loops — removes process-global mutable state, decouples the
   hot path from file I/O, no-op default keeps production clean. *Effort: medium.
   Payoff: medium.*

(Reviewers split on whether to move the 4 concrete tasks into the `OspreySharp.Tasks`
project; one called it a discoverability fix, another called the current split sound.
Low priority either way.)

## Constraints / cautions

- **Bit-parity is the hard gate.** The scoring code is saturated with Rust bit-for-bit
  invariants (exact eval order, `>=`-on-tie selection); the dense comments are
  load-bearing, not noise. Any refactor here is mechanical-but-delicate and must stay
  byte-identical under the C#-only `Compare-EndToEnd-Crossimpl` gate AND the
  in-memory-vs-HPC rehydrate parity gate (resume path).
- The `GetTask<T>()` service-locator's *payoff* is the lazy-rehydrate that unifies
  worker-mode and straight-through (`feedback`/decomposition notes). Whatever replaces it
  must preserve resume/worker/`--join-at-pass` semantics exactly — this is a
  re-architecture of *how* dependencies are expressed, not a change to *what* runs.
- Sequence after deciding the DLL/shared-scoring direction
  ([[TODO-ospreysharp_skyline_shared_scoring]]) only if the scoring-engine extraction
  (#1) would land in a seam destined for sharing; the dataflow refactor itself is
  independent of that.

## Divergence from the first review to keep in mind

The 2026-06-01 group was **less forgiving** than the 2026-05-29 review on two items the
first explicitly waved through as "cohesive": `OspreyConfig` (mutable bag that also owns
SHA identity hashing — two responsibilities) and `OspreyDiagnostics` (2K-LOC static
dumping ground). Not a unanimous "those are fine" — weigh accordingly.

## Related

- [[TODO-ospreysharp_task_layer_decomposition]] — iteration 1 (mega-methods, PR-A..PR-D)
- [[TODO-ospreysharp_assembly_consolidation]], [[TODO-ospreysharp_skyline_shared_scoring]]
- Memory: `feedback_ospreysharp_csharp_regression_gate`, `feedback_parity_vs_impact`,
  `feedback_bit_parity_tolerance`
