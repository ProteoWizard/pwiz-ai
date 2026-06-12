# TODO-20260611_ospreysharp_decouple_abstractscoring.md

Decompose the `AbstractScoringTask` god-class (2177 LOC) incrementally, the
first PR series off the 2026-06-10 OOP review
([`TODO-ospreysharp_oop_review_findings.md`](../backlog/TODO-ospreysharp_oop_review_findings.md),
rec #1). Each stage is structural-only and gated on byte-parity + perf.

## Branch Information

- **Branch**: `Skyline/work/20260611_ospreysharp_decouple_abstractscoring`
- **Base**: `master`
- **Created**: 2026-06-11
- **Status**: In Progress (Stage 1 done; PR open, awaiting Copilot)
- **PR**: [#4290](https://github.com/ProteoWizard/pwiz/pull/4290)

## Standing gates (every stage)

Both must pass before each commit; see `ai/scripts/OspreySharp/PRE-COMMIT.md`:
- **Pre-commit**: `Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection` (zero-warning).
- **Correctness**: `pwiz_tools/OspreySharp/regression.ps1 -Dataset Stellar` (committed C# golden + resume, 1e-9).
- **Performance**: `ai/scripts/OspreySharp/Test-PerfGate.ps1 -Dataset Stellar` (A/B vs pinned pwiz-perfbase; total-only fail at 4%).
  - Both gates were stood up + validated this session (perf gate A/A on a quiet
    machine; see [[feedback_ospreysharp_csharp_regression_gate]]).

## Key finding (corrects the parent TODO's rec #1 framing)

The review called "make `_ctx` `private readonly` + ctor-injected (mirror
`Calibrator`)" a low-risk first step. Tracing the code shows it is **not** low
risk, and the framing was off:
- `OspreyTask.Run(ctx)` / `Rehydrate(ctx)` take `ctx` as a **call-time
  parameter**; the driver constructs a task once, then calls Run *or* Rehydrate.
  That is why the 3 subclasses each reassign `_ctx = ctx` at **both** entry
  points. `readonly` ctor-injection therefore requires changing task
  construction in the driver, not a mechanical field-modifier swap.
- It is **3 subclasses**, not 4: `FirstJoinTask`, `PerFileScoringTask`,
  `PerFileRescoreTask` share the base `internal _ctx`. `Calibrator` is a
  **standalone** collaborator (no base) that already ctor-injects correctly;
  `MergeNodeTask : OspreyTask` (not AbstractScoringTask) has its own mutable
  `_ctx`. So Calibrator is a pattern reference, not a drop-in template for the
  inherited field.

=> `_ctx` injection is promoted to its own designed stage (Stage 3), after the
lifecycle is decided (construct-with-ctx vs. a set-once guard).

## Stage 1 -- dead code + math relocation (this commit)

Lifecycle-independent, behavior-identical, lowest-risk first cut at the
god-class. `AbstractScoringTask.cs`: -99 / +3 lines.
- [x] New `OspreySharp.Core/TotalOrder.cs`: the IEEE-754 total-order helpers
  (`Key`/`Comparer`/`Greater`) relocated out of AbstractScoringTask, which held
  **two copies** of the same bit transform (the FDR-ranking comparer + the
  main-search `Greater` tie-break). DRY'd via a shared `Key`; arithmetic
  verbatim, so cross-impl parity is unaffected. Mirrors the `FragmentMath`
  relocation precedent.
- [x] Deleted the two confirmed-dead private methods (`TheoreticalIsotopeEnvelope`,
  `CosineSimilarity`) -- zero callers tree-wide (grep-confirmed; they survived
  because the inspection profile disables unused-private-member warnings, see
  [[reference_ospreysharp_inspection_gate_coverage]]).
- [x] Removed a misplaced `Score a single library entry candidate` doc comment
  that was dangling above `TotalOrderGreater` (would have caused CS1587 once the
  method beneath it was deleted).
- [x] Updated the 2 call sites to `TotalOrder.Greater` / `TotalOrder.Comparer`.

**Validation**: pre-commit green (382 tests pass, incl. `TestStableSortOnApexRanking`
+ `TestApexTieBreakLastWins` which exercise the relocated comparer; zero-warning
inspection). Correctness + perf gates: _(filling in from the runs in progress)_.

## Staged plan (subsequent PRs on this branch / night session)

- **Stage 2 -- relocate decoy generation**: move `GenerateDecoys` /
  `BuildDecoyFromSequence` (~88 LOC) to a `LibraryPrep` type. Needs the logger
  (`_ctx`) passed in rather than ambient -- a stepping stone toward Stage 3.
- **Stage 3 -- `_ctx` decoupling (designed)**: decide the task lifecycle, then
  make the base context non-ambient (ctor-injected or set-once-guarded) across
  the 3 subclasses. This is the review's real dominant-debt item.
- **Stage 4+ -- extract `CoelutionScorer`** (rec #1 full): pull `ScoreWindow` +
  `ScoreCandidate` (~825 LOC) into a composed, dependency-injected collaborator.

## Relationship to other work

- Parent: [`TODO-ospreysharp_oop_review_findings.md`](../backlog/TODO-ospreysharp_oop_review_findings.md)
  (backlog epic; consumed PR-by-PR, not moved wholesale).
- All structural changes gated on byte-parity ([[feedback_ospreysharp_csharp_regression_gate]],
  [[feedback_bit_parity_tolerance]]); do not loosen tolerances.
- One turn of the recurring blind-OOP-review cadence
  ([[project_osprey_organic_growth_needs_iterative_oop_review]]).
