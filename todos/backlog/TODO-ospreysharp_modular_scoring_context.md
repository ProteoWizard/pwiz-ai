# TODO: OspreySharp — modular per-score classes driven by a Skyline-aligned scoring context

**Status**: Backlog (not started)
**Priority**: Medium-High — the highest-leverage structural change, but the
highest parity risk; sequence after the lower-risk extractions
**Type**: Architecture / scoring decomposition
**Source**: OOP review of `pwiz_tools/OspreySharp` (2026-06-06), Cohesion +
Separation-of-concerns lenses + Top Recommendation #2

## Problem

`OspreySharp/Tasks/AbstractScoringTask.cs` (2,731 LOC) plays two roles at once:

1. A **scoring engine** — `GenerateDecoys`, `RunCoelutionScoring`,
   `ScoreCandidate`, and the feature computations
   (`ComputeCoelutionStats`, `ComputePeakShapeFeatures`, `ComputeApexMatchFeatures`,
   `ComputeMs1Features`, `CountConsecutiveIons`, `CountTop6Matches`, …).
2. A **logging/constants base** — the `internal PipelineContext _ctx` field
   (`:60`), `NUM_PIN_FEATURES = 21` (`:89`), `BASE_ID_MASK` (`:96`).

`PerFileScoringTask` and `PerFileRescoreTask` genuinely use the engine, but
**`FirstJoinTask` uses essentially none of it** — it inherits 2,731 lines to get
`_ctx` logging and two constants (its only base references are `_ctx`,
`BASE_ID_MASK:519`, `NUM_PIN_FEATURES:1305`). That is inheritance for incidental
reuse: an FDR/reconciliation task wearing a scoring task's inheritance.

The 21 PIN features are computed **inline** inside `ScoreCandidate`
(`AbstractScoringTask.cs:857–1734`, a single ~877-line method). There is no way to
see "what is the set of scores?" or "what inputs does a score need?" without
reading the whole method, and the harness inputs (XICs/chromatograms, peak
boundaries, apex spectrum, MS1 spectra, RT/mass calibration) are threaded as a
long parameter list rather than a named context.

## Desired design (user direction) — mirror Skyline peak scoring

Skyline already solves exactly this problem in
`pwiz_tools/Skyline/Model/Results/Scoring/IPeakScoringModel.cs`:

- `IPeakFeatureCalculator` (`:396`) — one class **per score**, each
  self-contained, with `Summary`/`Detailed` abstract bases
  (`SummaryPeakFeatureCalculator:431`, `DetailedPeakFeatureCalculator:471`).
- `IPeptidePeakData` (`:607`) — the data a calculator scores against.
- `PeakScoringContext` (`:761`) — the harness-provided context, with the
  `AddInfo<T>` / `TryGetInfo<T>` byproduct pair OspreySharp already borrowed for
  `PipelineContext` (see PR-C).

Bring the same shape to OspreySharp:

- **`OspreyScoringContext`** — a read-only object exposing exactly what the harness
  provides to a score: window spectra + RTs, the XIC/chromatogram set, the chosen
  peak boundaries (apex/start/end), the apex spectrum, MS1 spectra, RT calibration,
  mass calibration, tolerances. This replaces `ScoreCandidate`'s long parameter
  list and makes the score inputs explicit and named.
- **One class per score** implementing a common
  `IOspreyFeatureCalculator` (the `IPeakFeatureCalculator` analog):
  `Calculate(OspreyScoringContext ctx, candidate/peakData) -> double`. The 21 PIN
  features become 21 calculators (or a small number of grouped calculators where
  the math is genuinely shared).
- **A feature set / registry** that owns the **parity-critical ordering** (the
  `NUM_PIN_FEATURES = 21` vector order) in one place, so the order is data, not a
  hand-maintained inline sequence.
- Once scores are modular calculators driven by a context, the
  engine-vs-logging conflation in `AbstractScoringTask` **dissolves**: tasks hold a
  calculator set + a thin logging base (or take a logger by parameter), `_ctx` as a
  mutable field goes away (Encapsulation lapse from the review), and
  **`FirstJoinTask` stops inheriting the scoring engine** (derives from the thin
  base or directly from `OspreyTask`).

### Skyline transferability (the strategic payoff)

Align `OspreyScoringContext` / `IOspreyFeatureCalculator` with Skyline's
`PeakScoringContext` / `IPeakFeatureCalculator` / `IPeptidePeakData` shapes so a
calculator's **context requirements** are expressed the same way in both tools.
The goal: a score whose inputs are satisfiable from a Skyline peak-data context can
be ported (eventually shared) between Skyline and Osprey with minimal glue — the
"shared scoring core" direction already noted for `pwiz_tools\Shared`. Capture, per
calculator, which context fields it reads, so transferability is auditable.
(Reality check from prior analysis: the *spectrum wall* limits which Osprey scores
have a Skyline-side equivalent input — treat full parity of the context as
aspirational, and document where Osprey needs inputs Skyline cannot provide.)

## Constraints (osprey) — this is the high-risk one

- `ScoreCandidate` is the **byte-for-byte parity heart**. Its inline comments
  (`AbstractScoringTask.cs:933–944`) document f64 boundary-ordering effects where
  rewriting an arithmetic chain flips which scan enters a window and cascades
  through CWT peak detection. **Extraction must preserve order of operations
  exactly** — each extracted calculator must reproduce the identical f64 value.
- Phase it: extract **one calculator at a time behind a golden feature-dump diff**,
  not a big-bang rewrite. After each extraction, the C#-side refactor regression on
  Stellar + Astral must hold (exact for a pure move) -- the multi-file
  straight-through run reusing the cached Rust reference:
  `Compare-EndToEnd-Crossimpl.ps1 -Files All -SkipRust`, plus the pre-commit
  `Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection`.
  (Cached Rust reference must match the `-Files` set; no `-Force` with `-SkipRust`.)
- Full cross-impl drift check (rare; re-runs Rust, only if porting a Rust algorithm
  change): drop `-SkipRust`. See `Compare/README.md`.
- net8.0 canonical for parity. Do not loosen a gate to land a step; if a feature
  moves, the extraction changed the math — bisect and fix, don't widen tolerance
  (needs explicit sign-off and end-of-pipeline review per project rule).
- Skyline conventions apply (no async/await, resource strings for user-facing text,
  `_camelCase` privates, CRLF, helpers after public methods).

## Open design questions

- One class per PIN feature (21 classes) vs. grouped calculators where math is
  shared (e.g. the consecutive-ion / top-6 family)? Favor whatever keeps each
  calculator's context dependency honest without duplicating shared sub-computations.
- Does `OspreyScoringContext` subsume the per-candidate scratch (`WindowXcorrCache`,
  scorer, resolution) or sit beside it?
- How close can the context get to Skyline's `IPeptidePeakData` before the spectrum
  wall forces a divergence — and where exactly is that line?

## Relationship to sibling TODOs

- Sequence **after** `TODO-ospreysharp_extract_calibrator.md` (lower-risk, shrinks
  the file first) and ideally after / alongside
  `TODO-ospreysharp_diagnostics_di.md` (so extracted calculators get an injected
  diagnostics sink, not static calls).
- Precedent: `TODO-20260604_ospreysharp_byproduct_context_prc.md` (PR-C) — the
  `AddInfo`/`TryGetInfo` lineage this extends from `PipelineContext` down to the
  per-score context.
