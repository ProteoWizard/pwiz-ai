# TODO: OspreySharp OOP / architecture review — findings and refactor backlog

**Status**: Backlog (not started)
**Priority**: Medium — no correctness risk today; this is "pay down before the next pipeline
stage lands." The #1 item (AbstractScoringTask) is the one that compounds if deferred.
**Type**: Architecture / refactor (structural-only; gate every change on byte-parity)
**Source**: 2026-06-10 `/pw-oop-review` (ultracode) of `pwiz_tools/OspreySharp`. 23-agent
fan-out: 8 project mappers, 12 deep-file reviews, 3 cross-cutting probes. Findings below were
adversarially cross-checked (the coupling probe downgraded several mapper findings once control
flow was traced) and the two highest-severity claims were re-verified by hand (see "Verified").
**Context**: This is the next iteration of the recurring blind OOP-review cadence for osprey's
organic growth — see [[project_osprey_organic_growth_needs_iterative_oop_review]]. The *previous*
iteration's dominant issue (dual straight-through/worker spines + producer-named getters) is
**fixed** — the typed byproduct registry and single driver are now in place and graded strong.
**This** iteration's dominant issue is `AbstractScoringTask`.

> Note: the developer is pausing OOP cleanup after ~a week on it to spend a few days on
> **testing tech debt** (see the test-review work / [[feedback_no_unverified_ports]] and the
> e2e-regression-gate backlog). This file exists so the OOP findings are not lost in the gap.

## Headline assessment

Well-architected code that has visibly absorbed prior review iterations; growing it further is
**safe if the next structural iteration is spent on the EXE `Tasks/` layer.** The 8-project
dependency graph is clean and acyclic, boundaries are real and respected, and the orchestration
spine (`PipelineContext` typed-byproduct registry modeled on Skyline `PeakScoringContext`, the
single `CanonicalPipeline()` source of truth, the membership-driven driver loop) is genuine
load-bearing dataflow architecture. The dominant debt is **narrow and nameable**: one
god-base-class and the ambient state radiating from it. The library projects (Core, ML,
Chromatography, FDR, IO) are healthy. This is "refactor before adding the next stage," not
"rearchitect."

Inventory at review time: 8 production projects + EXE + Test, ~52K LOC, 131 `.cs` files.
Dependency graph (verified acyclic):
```
Core <- {ML, Chromatography, IO}
{Scoring, FDR} <- Core + ML + Chromatography
Tasks(library) <- Core
OspreySharp(EXE) <- everything
```
Weight inversion to keep in mind: the **EXE** owns the heaviest classes
(`AbstractScoringTask` 2177, `FirstJoinTask` 1744, `PerFileScoringTask` 1558,
`PerFileRescoreTask` 1522, `Calibrator` 1329, `MergeNodeTask` 1094), while the `OspreySharp.Tasks`
*library* holds only the lightweight framework. Algorithm bodies are trapped in the EXE behind
inheritance + `internal` statics, so they aren't reusable from the Scoring/FDR libraries.

## Verified by hand (not just agent-reported)

- `AbstractScoringTask.cs:60` `internal PipelineContext _ctx;` — **187** `_ctx` references across
  `OspreySharp/Tasks/` (grep-confirmed). Breakdown: PerFileScoringTask 65, FirstJoinTask 30,
  AbstractScoringTask 24, PerFileRescoreTask 21, MergeNodeTask 17, **Calibrator 29**. Important
  nuance: `Calibrator.cs:85` uses the **correct** pattern — `private readonly PipelineContext _ctx`
  set once in the ctor — so the ambient-state problem is specifically AbstractScoringTask + its 4
  subclasses, and Calibrator is the template for the fix.
- `SpectralScorer.cs:357-403` — confirmed 48 lines of `StreamWriter("cs_xcorr_diag.txt")` + per-bin
  formatting inlined in the XCorr hot path, immediately before the production
  `return xcorrRaw * XCORR_SCALING` at `:406`. Reads `OSPREY_DIAG_XCORR_SCAN` on every scoring call.

## Per-lens findings

### 1. Separation of concerns — Adequate overall, **Weak in EXE `Tasks/`**
- `PerFileScoringTask.ProcessFile` (`PerFileScoringTask.cs:1120-1413`, ~293 LOC): config clone +
  thread budget + spectra I/O + calibration compute/load/save + scoring + 2 dedup passes + TSV
  dump + parquet write in one method.
- `MergeNodeTask.Run` (`MergeNodeTask.cs:118-492`, ~375 LOC): 3 inline disk sidecar passes nested
  5–6 levels; `inputByFileName` rebuilt 3× (`:152,327,433`).
- `PercolatorFdr.cs` (2374 LOC, largest file): FDR math + 4 inline `WriteStage5*Dump` writers
  (`:2127-2319`) + `Environment.Exit(0)` env-gates mid-algorithm (`:247,262,369,476`) — a library
  method that can vanish the process.
- Diagnostics bleed into leaf production code with no facade to route through: `SpectralScorer`
  (above); `PercolatorFdr` env reads (`:241,256,363,470`).

### 2. Encapsulation — **Weak in the scoring engine, Strong on the bus**
- Standout: `_ctx` mutable, `internal`, externally-assigned back-reference (see Verified). Same
  context reachable two ways — `ctx.ExitCode` (`PerFileScoringTask.cs:464`) vs `_ctx.ExitCode`
  (`:569,650`). Hazard at the per-window thread boundary.
- Shared mutable buffer crossing task instances: `PerFileScoringTask._perFileEntries` documented
  (`:119-124`) as a "live, mutable, shared List" that FirstJoin/PerFileRescore mutate **in place
  on another task's instance**.
- Config stability is prose-only: `PipelineContext.cs:98-117` "Mutation contract" (hash-affecting
  fields frozen post-parse; per-file mutation via `ShallowClone`), honored manually, with
  `AbstractScoringTask.cs:513 config.FragmentTolerance = searchFragTol`.
- Fully-mutable central DTOs (`LibraryEntry.cs:45-56`, `OspreyConfig.cs:36-205`) with publicly
  replaceable collections — **acceptable as a Rust-parity serialization layer**; do not fight this
  unless the `RunPlan` split is finished so parsed config can go init-only.
- Strong counter-evidence: `PipelineContext` (all maps `private readonly`, `Tasks` defensively
  copied `IReadOnlyList`); `OspreyScoringContext.cs:62-117` (`{get; private set;}` + explicit
  `SetWindow/SetMs1Machinery`); `BlibWriter`.

### 3. Modularity — **Strong at project level, Adequate inside EXE**
- Acyclic graph, correct direction, no back-edges. `InternalsVisibleTo` used sparingly/deliberately
  (`ML -> FDR` for `Matrix.WrapPrefixNoClone`).
- The one real problem is the weight inversion above: algorithm bodies in the EXE, behind
  inheritance + internal statics, not reusable by libraries.

### 4. Cohesion — Adequate
- God-files dilute within-class cohesion: `AbstractScoringTask` hosts decoy-gen (`:142`) + scoring
  (`:366,855`) + dedup (`:1912,2114`) + 2 **confirmed-dead** private methods
  (`TheoreticalIsotopeEnvelope:1803`, `CosineSimilarity:1832`). `FirstJoinTask` carries two axes —
  FDR execution (~470 LOC) and Stage-6 planning+serialization (~430 LOC).
- Duplication that should be shared:
  - **UniMod accession→mass table hand-copied 4×**: `BlibWriter.cs:46`, `DiannTsvLoader.cs:433`,
    `BlibLoader.cs:40`, plus `Scoring/DecoyGenerator`.
  - **Modified-sequence parser reimplemented per loader**: `DiannTsvLoader.ParseModifications:223`,
    `BlibLoader.ParseBlibModifications:181`, `ElibLoader.ParseModifiedSequence:185`.
  - Pearson / median / trapezoidal-area variants 3× each, self-documented "NOT merged"
    (`ScoringMath.cs:40-51`). Float formatter `Diagnostics.FormatF64Roundtrip` *is* centralized
    (92 sites) — the writer scaffolding around it is not.

### 5. Coupling — Adequate, three localized escapes from the otherwise-uniform spine
- **`DidPlan` concrete-type reach**: `PerFileRescoreTask.cs:219-220`
  `ctx.Demand<FirstJoinTask>().DidPlan(ctx)` → `FirstJoinTask.cs:125` — the one compile-time edge
  to a sibling task in an otherwise uniform `ctx.Get<T>()` design (`FirstJoinTask.cs:98-99` even
  documents the pattern it violates).
- **FDR subset-selection policy duplicated across the assembly boundary** (highest
  change-amplification risk in the spine): `PercolatorFdr.RunPercolatorFdr` owns best-per-precursor
  dedup + peptide-grouped subsample; `FirstJoinTask.cs:1571,1596` re-invokes the same public
  statics to re-derive an identical training subset for the streaming path. Two copies, agreement
  guaranteed only by prose (`FirstJoinTask.cs:1545-1547`), no cross-DLL compiler check.
- **`Calibrator` reaches `AbstractScoringTask` internal statics**: `Calibrator.cs:543,1030,1163`
  (`s_calXcorrScorer`, `ExtractTopNFragmentXics`, `CountTop6Matches`); class doc `:36-49` admits it.
- Heavy, **intentional** coupling to Rust `pipeline.rs`/`percolator.rs` line numbers as the parity
  oracle is pervasive and correct for this codebase's mission — but ties maintainability to an
  external file staying in sync.

## Top 3 recommendations (ruthlessly prioritized)

### 1. Extract a non-inherited `CoelutionScorer` collaborator out of `AbstractScoringTask`
- **Action**: move `ScoreWindow` + `ScoreCandidate` (~825 LOC, `:855-1681`) + `ExtractFragmentXics`
  and the shared scoring machinery `Calibrator` reaches for into a class that takes its deps
  (`PipelineContext`/`ILog`, `OspreyConfig`, `ScoringContext`) as **constructor args**. Tasks
  *compose* it instead of inheriting. Kills three problems at once: the ambient `_ctx`, the
  assembly-wide `internal` leakage forcing siblings to reach in, and the untestability of
  `ScoreCandidate` (today exercisable only via a task subclass).
- **Low-risk first step (do this even before the full extraction, one PR)**: make `_ctx`
  `private readonly` + ctor-injected (mirror `Calibrator.cs:85`); delete the 2 dead methods
  (`:1803,1832`); relocate `GenerateDecoys`/`BuildDecoyFromSequence` to a `LibraryPrep` type and
  `TotalOrderComparer`/`TotalOrderGreater`/`F10` to a shared math util.
- **Effort**: first step = one-PR cleanup; full extraction = multi-sprint.
- **Payoff**: removes the single dominant growth-rot risk; every other EXE-`Tasks/` problem traces
  back to this base.

### 2. Close the two coupling escapes from the spine
- **Action**: publish `DidPlan` as a typed byproduct token through the existing registry; give the
  library a single `BuildTrainingSubset` entry point (streaming-vs-materialized as a strategy) so
  the dedup/subsample policy is owned **once** instead of hand-mirrored in `FirstJoinTask`.
- **Effort**: one PR.
- **Payoff**: removes the highest cross-assembly change-amplification risk and folds the last two
  ad-hoc getters back into the architecture built to eliminate them.

### 3. Stop diagnostics bleeding into production FDR/Scoring; encode the byte-parity contract once
- **Action**: move the 4 `WriteStage5*Dump` methods out of `PercolatorFdr` into the existing
  `FdrDiagnostics` class (same project, today holds only 2 dumps); give Scoring a diagnostics seam
  so `SpectralScorer.cs:357-403` isn't inlined; add a per-layer `DumpWriter`/`OpenDump(path)` helper
  that sets `NewLine="\n"` + invariant culture once (hand-repeated ~20×; docs at
  `OspreyFileDiagnostics.cs:70-82` flag that forgetting it silently breaks the cross-impl diff).
- **Effort**: one PR. **Likely aligns with the existing `TODO-20260606_ospreysharp_diagnostics_di`**
  — reconcile with that before starting.
- **Payoff**: removes file I/O from the two hottest production methods; turns the load-bearing
  LF/parity incantation into one enforced helper (the most likely source of a future silent parity
  regression).

## Promising patterns — PRESERVE, do not "simplify" away

These are load-bearing and several encode hard-won byte-parity invariants. Flagging explicitly so
the upcoming testing work (and any `/simplify` pass) does not collapse them:
- **`PipelineContext` typed byproduct registry** (`Publish/TryGet/Get/Demand`, lazy producer
  materialization, fail-fast duplicate-producer check). The spine's core decoupling mechanism.
- **Single `CanonicalPipeline()` + membership-driven driver**; dual worker/straight-through spine
  eliminated (`RescoreWorker` now just `new AnalysisPipeline().Run(config)`).
- **Run/Rehydrate symmetry** publishing into the same typed slots (e.g. `FirstJoinTask.cs:296-300`
  vs `:352-356`) — handles the worker-vs-in-process duality uniformly.
- **`IOspreyFeatureCalculator` seam** (`AbstractScoringTask.cs:1501-1521` + `OspreyScoringContext`/
  `OspreyPeakData`) — Skyline `IPeakFeatureCalculator` analog; the 21 PIN features are already
  decoupled. This is the wedge for pulling more out of `ScoreCandidate`.
- **`PercolatorFdr` TrainOnly / ScorePopulationAndComputeFdr split** — clean train/apply factoring;
  the seam a future shared Skyline↔Osprey scoring core would reuse. (See
  [[project_ospreysharp_dll_boundaries_vs_sharing]].)
- **`BlibWriter` precompressed-blob perf seam** (parallel zlib pre-pass off the single-threaded
  SQLite insert).
- **`_perFileEntries` milestone-token-over-shared-buffer** — a deliberate no-copy hand-off for
  Astral scale, exhaustively documented (`PipelineByproducts.cs:136-168`). Do not touch. (But see
  open question on linearity.)
- Heavy tasks share via a **real base class, not copy-paste**; reusable math was actively pushed
  down to the Core leaf (`FragmentMath.cs:34-40` "Relocated verbatim out of AbstractScoringTask").

## Open questions (for whoever picks this up)

1. **Is the `AbstractScoringTask` extraction already roadmapped?** Its header self-describes as
   "Phase A scope: a mechanical lift" — reads like a known-temporary state. If a "Phase B"
   decomposition is planned, rec #1 *is* it.
2. **Will the pipeline stay linear?** The `_perFileEntries` milestone-token design is correct only
   while each milestone is consumed before the next in-place mutation (holds by the linear shape of
   `CanonicalPipeline()`). A branching/non-linear pipeline would silently hand a later task rescored
   data. Cheap insurance before that growth: a generation counter or debug-only frozen flag.
3. **How stable are the Rust source line numbers** that dozens of parity comments pin to? Manual
   re-anchoring, or tooling? They rot silently when `maccoss/osprey` reorganizes.
4. **Is `BatchScorer`/`LibCosineScorer` (485 LOC in Scoring, referenced only by tests) a production
   path or a parity scaffold?** If scaffold → move to the test project; reads as dead production
   code today.

## Relationship to other work

- Pairs with the testing push the developer is starting now: rec #1's extraction is much safer with
  the self-contained e2e regression gate in place — see
  `TODO-ospreysharp_selfcontained_e2e_regression_gate.md`. Sequence the gate first if possible.
- Rec #3 likely overlaps `TODO-20260606_ospreysharp_diagnostics_di` — reconcile before starting.
- All structural changes must be gated on byte-parity per
  [[feedback_ospreysharp_csharp_regression_gate]] (`Compare-EndToEnd-Crossimpl -Files All -SkipRust`,
  Stellar + Astral) and must not loosen parity tolerances unilaterally
  ([[feedback_bit_parity_tolerance]]).
- This is one turn of the recurring cadence in
  [[project_osprey_organic_growth_needs_iterative_oop_review]]; the next iteration after this debt is
  paid should re-run a blind review to surface whatever the new dominant issue is.
