# TODO-ospreysharp_debt_paydown_pr3.md -- OspreySharp debt-paydown PR 3 (next OOP-review iteration)

> **Status: BACKLOG.** PR 3 of the OspreySharp debt-paydown arc. Date it and move
> to active/ when the sprint starts. See memory project_ospreysharp_debt_paydown_arc
> for the full arc and project_osprey_organic_growth_needs_iterative_oop_review for
> the iterative-blind-review doctrine.

## Where the arc stands (as of 2026-06-16)
- **PR 1 (#4302, merged 2026-06-15):** diagnostics static-coupling broken; new
  OspreySharp.Diagnostics DLL with IOspreyDiagnostics injected on PipelineContext.
- **PR 2 (#4304, merged 2026-06-16):** the 7 task bodies + RescoreHydration/
  RescoreCompaction + ProfilerHooks lifted into the OspreySharp.Tasks DLL -- the
  pipeline layer is now a **unit-testable DLL**. Also adopted the Skyline version
  scheme + cache-version hard-fail (see memories project_ospreysharp_official_rust_retired,
  feedback_hard_fail_over_warn_proceed). Output byte-identical, perf-neutral.

## This sprint: start with a blind OOP review, then scope the PR
Per the iterative-review doctrine, **do NOT assume the scope below** -- run a blind
`/pw-oop-review` of the now-DLL-ified OspreySharp pipeline first (the exe's
AnalysisPipeline + the OspreySharp.Tasks DLL) to surface the next *dominant*
structural issue, then scope the PR around it. The candidates below are the known
deferred items going in; the review confirms which one leads.

### Candidate A (the arc's planned PR 3): extract collaborators + unit tests
The headline goal: migrate the ~30% coverage that currently rides the 41-min nightly
TeamCity regression onto fast per-PR unit tests. As each task is touched, extract
collaborators and write unit tests against each new seam:
- per-file resume driver,
- PercolatorRunner (2nd-pass FDR),
- reconciliation I/O.
Don't decompose parity-locked giants (ScoreCandidate, RunPercolator) for testability
alone -- a characterization test at their current boundary is cheaper and lower
parity-risk (see feedback_no_unverified_ports).

### Candidate B (deferred from PR 2): the full thin-exe
Move the 2076-line OspreyFileDiagnostics sink, AnalysisPipeline, and the
OspreyDiagnostics bootstrap out of the exe. Makes the exe a thin shell.

### Candidate C (deferred): IOspreyDiagnostics : IScoringDiagnostics split
The gate-flags-vs-writes interface split (see project_ospreysharp_diagnostics_bleed_blocks_scoring_extraction).

## Gates (the standing OspreySharp cadence -- see osprey-development skill)
- Per commit: `Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection`
  (0 warnings) + `regression.ps1 -Dataset Stellar` (mode 1 + mode 2).
- Pre-merge: `regression.ps1 -Dataset All` + `Test-PerfGate.ps1 -Dataset Stellar`
  + `/pw-self-review` (then open PR, Copilot, optional /code-review ultra).
- PR cadence (Brendan's preference): ONE PR, multiple commit-and-test cycles;
  parity-check after EACH commit. The 41-min nightly stays as the integration
  backstop -- lean on it for big mechanical moves; the goal is to grow per-PR unit
  coverage so we depend on it less.

## Out of scope / watch
- The dash-hygiene verifier + cleanup is a SEPARATE backlog item
  (TODO-dash_hygiene_verifier_and_cleanup.md), not this sprint.
- The Jamfile version-injection path (PR 2) is only TeamCity-verified; glance at the
  next nightly to confirm it stamps cleanly.

**Next session handoff**: For the detailed startup protocol (skills, memories,
blind-OOP-review-first, build/gate commands), read
`ai/.tmp/handoff-20260616_ospreysharp_oop_pr3.md` before starting work.
