# TODO: Evaluate Osprey assembly count (8 DLLs) vs. fewer/single assembly

**Status**: Backlog (evaluation / decision, not yet a coding task)
**Priority**: Low-Medium (no defect; structural question raised once the project went past proof-of-concept)
**Complexity**: Medium to evaluate; Large if a consolidation is chosen (touches every csproj + the layering-enforcement story)
**Created**: 2026-05-29
**Scope**: `C:\proj\pwiz\pwiz_tools\Osprey` -- the 8-project solution graph

## The question (raised by Brendan, 2026-05-29)

Does it make sense to have so many DLLs versus a single binary artifact?
The project graph (`Core` <- `ML`/`Chromatography` <- `Scoring`/`FDR` <-
exe, plus `IO`, `Tasks`) is a near 1:1 port of the Rust **crate** graph
-- evidenced by file headers like `PearsonCorrelation.cs`: "Port of
correlation functions from osprey-scoring/src/lib.rs". The boundaries
were inherited from Rust's crates.

The mismatch worth naming: **crate boundaries are free at runtime in
Rust; .NET assembly boundaries are not.** Rust statically links all
crates into one binary and inlines `pub` functions across crates (MIR
inlining + LTO), so the split is a pure compile-time
privacy/organization device with zero runtime cost. In .NET each
project is a separately-loaded assembly: cross-assembly JIT inlining is
more heuristic-sensitive than intra-assembly, there is assembly-load
overhead, and the boundary forces `public` (or `internal` +
`InternalsVisibleTo`) where one assembly could use `internal`/private.
So Osprey pays a .NET-specific tax for a decomposition that cost
Rust nothing.

Added irony: Rust split into many crates but kept a **monolithic
`pipeline.rs` of thousands of lines**. Osprey inherited both the
fine-grained assembly split *and* (until the task decomposition) the
monolith. The Tasks-layer work is fixing the monolith Rust still
hasn't, while carrying Rust's crate-count as DLLs.

## Evidence already collected (from the scoring-math extraction PR)

The 2026-05-29 `extract_scoring_math` PR moved four hot-loop helpers
(`PearsonOverRange`, `PearsonCorrelationInRange`, `BinarySearchLowerBound`,
`LowerBoundDouble`) from the exe project into `Osprey.Scoring.dll`,
turning previously same-assembly calls into cross-assembly calls in the
scoring hot path (per-fragment m/z lower-bound search, per-XIC-pair
Pearson). A 3-repeat Stellar C#-only perf A/B (master vs branch):

- **stage1to4** (the stage exercising those helpers): master median
  90.4s vs branch median 88.7s -- branch marginally *faster*, the
  delta buried inside ~15-20% run-to-run variance (mzML parse I/O).
- All other stages identical (s5 ~68s, s6 35.4s, s7 ~38s, blib ~4s).

**Read:** cross-assembly placement of small IL-inlinable helpers cost
nothing measurable here. That weakens the "collapse for performance"
argument and leaves layering-enforcement as the real axis.

## The tradeoff to decide

**The one thing the multi-assembly split genuinely buys in C#** is
compile-time enforcement of the acyclic layering: today you physically
cannot make `Core` depend on `Scoring` because there is no project
reference -- the compiler stops you. Collapse to one assembly and that
guarantee degrades to convention, enforced only by an architecture test
(e.g. NetArchTest, or a namespace-dependency inspection rule). That
enforcement is real and is the strongest reason the structure earns its
keep.

Cutting the other way: the boundaries provide ~no runtime value (per the
perf data), complicate "which DLL does this helper live in?" placement
decisions (recurring in the Tasks-layer cleanup PR-C), and inflate
public surface. Namespaces + folders preserve the logical layering
without separate assemblies.

**Constraint from the Shared direction**: whatever eventually migrates
to `pwiz_tools\Shared` (`Common*`) must be its own assembly to be
referenced by both Skyline and Osprey (see
[[project_ospreysharp_exe_and_shared]]). So the `Core`-like bottom layer
stays separate regardless. The live question is really the middle
(`Scoring`/`FDR`/`ML`/`Chromatography`/`Tasks`): could those be one
"engine" assembly with layering enforced by a test instead of by the
reference graph?

## What an evaluation would produce

1. A recommendation: keep-as-is / collapse-the-internal-middle /
   collapse-to-one-plus-Core-plus-Shared.
2. If collapsing: a concrete layering-enforcement replacement (an
   architecture test that fails the build on an upward dependency) so
   the compile-time guarantee is not simply lost.
3. A measure of any real cost beyond perf: build-parallelism change,
   `InternalsVisibleTo` churn for the test project, deployment surface.

## DECISION 2026-06-01 (Brendan): keep all 8 DLLs as-is for now

A 3-subagent study of how Osprey scoring might inter-relate with Skyline's
peak-scoring architecture ([[TODO-osprey_skyline_shared_scoring]]) **reversed the
earlier lean toward "collapse the middle."** The boundaries `Core / Scoring /
FDR(linear-model)` are exactly the seams a future *shared cross-tool scoring core*
(feature-vector -> linear model -> FDR, the point where Skyline and Osprey scoring
converge) would be carved along. `Osprey.Scoring` already has the property a
Shared-bound assembly needs -- dependency-light (no Parquet/SQLite/WinForms). Collapsing
the middle into the exe now would destroy that scaffolding and force a re-extraction
later, while the perf motive to collapse is already nil.

So: **no consolidation now.** Keep the 8-assembly split, especially the Scoring + FDR
seams. Revisit this together with the shared-scoring direction -- the two decisions are
coupled and the sharing question dominates. (If a consolidation is ever chosen, it would
still keep Core + Scoring + FDR distinct; only assemblies with no sharing future and no
dep-isolation value would be candidates, and even those aren't worth churning while the
sharing direction is undecided.)

The keep-as-is vs collapse analysis below is retained for context; the layering-
enforcement-via-architecture-test option remains valid IF a collapse is ever revisited.

## Why backlog

- No defect; pure structural improvement.
- Interacts with the Tasks-layer cleanup (PR-C placement decisions), the
  Shared-migration direction, AND the Skyline<->Osprey shared-scoring question
  ([[TODO-osprey_skyline_shared_scoring]]) -- best decided deliberately.
- The perf question that motivated urgency is already answered (no
  measurable cross-assembly cost), so this can wait for a considered call.

## Related

- `TODO-osprey_task_layer_decomposition.md` (PR-C placement decisions
  depend on this outcome)
- Active PR: `TODO-20260529_ospreysharp_extract_scoring_math.md` (source
  of the perf evidence above)
- Memory: [[project_ospreysharp_exe_and_shared]]
