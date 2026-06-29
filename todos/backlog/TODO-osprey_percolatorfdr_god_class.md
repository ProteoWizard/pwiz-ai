# TODO-osprey_percolatorfdr_god_class.md

## Summary
`Osprey.FDR/PercolatorFdr.cs` has grown to ~2,500 lines and is a god-class:
it accretes several distinct responsibilities that should be separate collaborators.
Surfaced 2026-06-25 while extracting `FeatureContributions` (PR #4328) — the right
reflex was to add the new concept as its own class rather than grow the monolith;
the same reflex applies to the responsibilities already inside it.

**Status**: Backlog (not started). **Type**: OOP / modularity refactor (structural).

## Why
Organic feature-cycle growth (see [[project_osprey_organic_growth_needs_iterative_oop_review]],
[[project_ospreysharp_debt_paydown_arc]]) keeps adding to this one file. A large class
that mixes training, scoring, FDR math, and diagnostics is hard to read, test in
isolation, and reason about. This is exactly what the periodic blind OOP-review pass
(`/pw-oop-review`) is meant to catch and pay down.

## Candidate seams observed (starting points, not a final design)
- **SVM training orchestration** — `RunPercolator`, fold cross-validation, iteration loop.
- **Model application / population scoring** — `ScorePopulationAndComputeFdr` (apply avgWeights).
- **FDR machinery** — TDC competition (`CompeteAll`), conservative q-values
  (`ComputeConservativeQvalues`, run/experiment variants), PEP estimation. A natural
  `TargetDecoyFdr` collaborator.
- **Stage-5 diagnostic dumps** — `WriteStage5SvmWeightsDump`, `WriteStage5StandardizerDump`,
  etc. Candidate `PercolatorDiagnosticsDump` collaborator (note: also a target of the
  OspreyDiagnostics reduction pass the author flagged 2026-06-25).
- **Already extracted**: `FeatureContributions` (the percent-contribution decomposition).

## Approach (do NOT bundle into a feature PR)
Its own branch, structural-only, gated like the prior `AbstractScoringTask` decomposition:
byte-parity (`regression.ps1`, committed golden + resume + HPC) + perf (`Test-PerfGate.ps1`).
Best driven by an iterative `/pw-oop-review` pass that surfaces the next dominant seam each
round. Reporting-only / pure pieces (FeatureContributions, the diagnostic dumps) are the
lowest-risk first extractions; the FDR-math extraction is parity-critical and goes last.

## Origin
Author note during #4328 review (2026-06-25): "Even those line numbers indicate a large
class that may be doing too much ... keep thinking about modularity and separation of concerns."
