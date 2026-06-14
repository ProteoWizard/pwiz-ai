# TODO-20260614_ospreysharp_diagnostics_seam.md -- Inject diagnostics through PipelineContext, retire the OspreyDiagnostics static global

> Replace the task layer's reaches into the exe-only `OspreyDiagnostics`
> static facade with an `IOspreyDiagnostics` instance carried on
> `PipelineContext`, modeled on the proven `IScoringDiagnostics` injection
> into `CoelutionScorer`. This removes the last exe-only static dependency
> from the task bodies and is the **precondition** for lifting the task layer
> into a testable DLL (the next PR in the arc).

## Branch Information
- **Branch**: `Skyline/work/20260614_ospreysharp_diagnostics_seam`
- **Base**: `master`
- **Created**: 2026-06-14
- **Status**: In Progress
- **PR**: (pending)

## Why this is one PR with multiple commit/test cycles
Per Brendan's working style (2026-06-14): this is **one logical block = one PR**,
done in several commit-and-test cycles, **not** a PR per commit. Each commit below
is independently built + regression- + perf-gated, but they merge together. No
checkpoint PRs within the block.

## Background
- 4th OspreySharp OOP review (2026-06-14) identified the diagnostics static
  coupling as the keystone constraint: task bodies call
  `OspreyDiagnostics.DumpX` (flag reads) and `OspreyDiagnostics.WriteX(...)`
  (dump calls) directly. Approx counts (re-grep at implementation time):
  Calibrator ~33, FirstJoinTask ~32, PerFileRescoreTask ~8, MergeNodeTask ~7,
  PerFileScoringTask ~6, AbstractScoringTask ~5, plus Program/AnalysisPipeline
  bootstrap. ~90 call sites total.
- The scoring DLL already broke this coupling with `IScoringDiagnostics`
  (nullable interface injected into `CoelutionScorer`) -- this PR extends the
  same pattern to the task layer. See
  `project_ospreysharp_diagnostics_bleed_blocks_scoring_extraction` and
  `project_ospreysharp_debt_paydown_arc` in auto-memory.
- Coverage context (`TODO-20260610_ospreysharp_cumulative_coverage.md`):
  `OspreyFileDiagnostics` is 829 statements at ~7% coverage; the static facade
  is the largest single uncovered block dragging the exe number down.

## Scope
**In scope:** every `OspreyDiagnostics.*` reach in the **exe task layer** and
its bootstrap (the ~90 sites above). The concrete writer `OspreyFileDiagnostics`
(file I/O for cross-impl dumps) **stays in the exe** -- only the abstraction it
sits behind moves.

**Out of scope (different code, different PRs):**
- `PercolatorFdr` / `FdrDiagnostics` dump code -- already in the FDR DLL, writes
  files directly, does **not** go through `OspreyDiagnostics`. Leave alone.
- Moving the task bodies to a DLL -- that is PR 2 of the arc (this PR only
  removes the blocker).
- Decomposing giant methods, extracting collaborators -- PR 3 of the arc.
- Raising diagnostics coverage -- the dumps stay env-var-gated and off in normal
  runs; this PR does not add dump tests.

## Design
- New `IOspreyDiagnostics` interface in **`OspreySharp.Tasks`** DLL (alongside
  `PipelineContext`, which will carry it). Mirrors the existing
  `OspreyDiagnostics` surface: the boolean gate properties (`DumpX`, `DiagY`,
  typed `DiagXicEntryId` etc.) **and** the `WriteX(...)` methods. (Core is the
  fallback host if a lower DLL turns out to need it; Tasks is preferred so the
  pipeline contract stays in one place.)
- `NullOspreyDiagnostics` no-op implementation (all flags false, all writes
  no-op) is the default, so `ctx.Diagnostics` is **never null** -- call sites
  read `ctx.Diagnostics.DumpX` / call `ctx.Diagnostics.WriteX(...)` without
  null-guards. (This is a deliberate divergence from `IScoringDiagnostics`'
  nullable form: the task layer has too many sites to null-guard each.)
- `PipelineContext` gains a `Diagnostics` property, set at construction. The exe
  wires the concrete `OspreyFileDiagnostics`-backed adapter in; everything else
  (tests, future DLL consumers) gets the null object by default.
- Net semantic change: **none in normal runs** (sink is off unless
  `OSPREY_DUMP_*`/`OSPREY_DIAG_*` set). The dump *content* is unchanged because
  `OspreyFileDiagnostics` itself is untouched -- only its access path changes
  from static to injected.

## Commit plan (one PR)
Each commit: `Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection`,
then `regression.ps1 -Dataset Stellar` (correctness, 1e-9 vs golden + resume),
then `Test-PerfGate.ps1 -Dataset Stellar` (perf A/B vs pwiz-perfbase).

1. **Seam (additive, no-op).** Add `IOspreyDiagnostics` + `NullOspreyDiagnostics`
   in Tasks DLL; add `PipelineContext.Diagnostics`; build the concrete adapter in
   AnalysisPipeline/Program and pass it through. Static `OspreyDiagnostics` still
   live in parallel -- no call sites migrated yet. Proves the seam compiles and
   is genuinely no-op.
2. **Migrate light task call sites** -- AbstractScoringTask, PerFileScoringTask,
   MergeNodeTask, PerFileRescoreTask (~26 sites) to `ctx.Diagnostics`.
3. **Migrate Calibrator** (~33 sites; it already holds `_ctx`).
4. **Migrate FirstJoinTask** (~32 sites).
5. **Retire the static.** Migrate the remaining Program/AnalysisPipeline reaches,
   then collapse `OspreyDiagnostics` to the bootstrap that constructs the sink
   (or delete it entirely if the adapter subsumes `Initialize`). Delete the
   static flag properties and Write delegators. Final inspection must be clean.

## Pre-merge gate (full)
- `regression.ps1 -Dataset All` (Stellar + Astral, straight + resume) green at 1e-9.
- `Test-PerfGate.ps1 -Dataset Stellar` (and Astral if touched) -- no regression.
- **Cross-impl dump parity spot-check**: one run with a representative
  `OSPREY_DUMP_*` flag set, before vs after, byte-identical dump output (the
  refactor moves the access path, not the writer, so this should hold by
  construction -- verify once). Use `Compare/Compare-EndToEnd-Crossimpl.ps1` or a
  direct dump diff.
- Zero-warning inspection (`-RunInspection`).

## Acceptance criteria
- No `OspreyDiagnostics.` static references remain in the task layer (grep clean).
- Task bodies depend only on `PipelineContext` / `IOspreyDiagnostics`, not on any
  exe-only type for diagnostics -- i.e. they would compile in a DLL that does not
  reference the exe (verified by inspection; the actual move is PR 2).
- Normal-run output and performance unchanged; dump output byte-identical.

## The larger arc (proposed PR set -- for review, not yet created)
This is PR 1 of a 3-block debt-paydown arc. Each block = one PR, multiple
commit/test cycles, no checkpoint PRs within. Blocks are sequential (each unblocks
the next):

- **PR 1 (this TODO) -- Diagnostics injection seam.** Remove the exe-only static
  blocker from the task layer.
- **PR 2 -- Lift the task layer into a testable DLL** (`OspreySharp.Pipeline`, or
  fold into `OspreySharp.Tasks`). Move the 6 task bodies + `PipelineByproducts`
  (+ `AnalysisPipeline`, `RescoreHydration`, `RescoreCompaction`) out of the exe;
  exe shrinks to Program + `OspreyFileDiagnostics` + `RescoreWorker` + wiring.
  Resolve the real edges: `Program.VERSION` and the log delegates (move VERSION
  to Core or the DLL; logging is already delegate-based). **Pure relocation,
  output-identical, regression-gated -- no new tests.** Outcome: the layer is
  reachable by `OspreySharp.Test` directly.
- **PR 3 -- Extract collaborators + unit tests** (the coverage migration). One
  PR, with these as internal commit/test cycles (Brendan, 2026-06-14: a single
  PR 3, not a/b/c sub-PRs):
  - per-file resume/sidecar driver (the check->skip->clear->compute->write
    pattern duplicated across PerFileScoring/PerFileRescore) + unit tests.
  - `PercolatorRunner` owning 2nd-pass FDR; removes the
    `MergeNodeTask -> FirstJoinTask.RunPercolatorFdr` cross-task static reach
    (`MergeNodeTask.cs:276`) + unit tests.
  - reconciliation-file I/O extraction + unit tests.
  This is where pipeline-layer coverage moves off the 41-min nightly regression
  onto fast per-PR unit tests. The regression stays as the bit-parity/integration
  backstop -- not deleted.
- **Deliberately deferred:** decomposing parity-locked giants
  (`CoelutionScorer.ScoreCandidate` ~800 LOC, `PercolatorFdr.RunPercolator`
  ~440 LOC) for testability alone. A characterization test at their current
  boundary is cheaper and lower parity-risk; open them only with an independent
  reason.

## Open decisions
1. **Interface host**: `OspreySharp.Tasks` (preferred, with PipelineContext) vs
   `OspreySharp.Core`. Decide at commit 1.
2. **One fat `IOspreyDiagnostics`** mirroring the static surface vs **split**
   (a read-only gate-flags snapshot + a writer interface). Leaning fat-but-simple
   for a mechanical, regression-safe first pass; split is a later cleanup if the
   surface proves unwieldy.
3. **Keep `OspreyDiagnostics.Initialize` as a thin bootstrap** vs delete entirely
   and have the exe `new` the adapter directly into `PipelineContext`. Decide at
   commit 5.

## Progress Log

### 2026-06-14 -- Created
Authored after the 4th OOP review. Plan reviewed with Brendan: one PR, multiple
commit/test cycles. Branch + ai-master commit of this TODO pending his sign-off on
the arc's PR decomposition above.
