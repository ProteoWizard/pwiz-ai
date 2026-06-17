# TODO-20260616_ospreysharp_debt_paydown_pr4.md -- OspreySharp debt-paydown PR 4 (decompose remaining god-methods)

## Branch Information
- **Branch**: `Skyline/work/20260616_ospreysharp_debt_paydown_pr4`
- **Base**: `master` (created off 6ee60e4e43; REBASE onto merged master after PR 3 #4308 lands -- see startup)
- **Created**: 2026-06-16
- **Status**: Queued (PR 3 #4308 must merge first)
- **PR**: (pending)

> PR 4 of the OspreySharp OOP debt-paydown arc. ONE PR, phases A -> B -> C as
> sequential commit-and-test cycles (Brendan cadence: parity-check after EACH
> commit). See memory project_ospreysharp_debt_paydown_arc.

## Cadence change (2026-06-16, Brendan)
We are **NOT** running a blind `/pw-oop-review` after every PR anymore. We batch
~3-4 PRs per OOP review. PR 4's phases A/B/C all come from PR 3's existing blind
review (no new review needed to start). **Run the next blind OOP review only AFTER
PR 4 merges** -- it will re-survey the post-decomposition tree and surface the next
dominant issue. See memory project_osprey_organic_growth_needs_iterative_oop_review.

## Where the arc stands
- **PR 1 (#4302):** diagnostics static-coupling broken; OspreySharp.Diagnostics DLL.
- **PR 2 (#4304):** task bodies lifted into the unit-testable OspreySharp.Tasks DLL.
- **PR 3 (#4308, merge pending):** extracted ReconciledParquetWriter + PerFileResumeDriver
  (rec 1) and decomposed ExecuteRescore -> RescoreOneFile + ProcessFile ->
  ResolveCalibration (rec 2). Byte-identical, perf-neutral. PR 3's blind review flagged
  FOUR 290-374 LOC god-methods; PR 3 decomposed two. PR 4 finishes the other two and
  closes the rec-3 coverage gap.

## This sprint: phases A -> B -> C (all from PR 3's review)
Same proven recipe each phase: extract named collaborators / step methods via PURE
CODE MOTION, keep parity-locked scoring/FDR cores WHOLE (characterize at their
boundary; do NOT decompose for testability -- see feedback_no_unverified_ports),
unit-test the parity-safe seams, verify byte-identical after each commit.

### Phase A -- decompose MergeNodeTask.Run (374 LOC, the largest remaining)
`MergeNodeTask.Run` (MergeNodeTask.cs:113-486) conflates 2nd-pass FDR (reload features
-> write `.2nd-pass.fdr_scores.bin` sidecars -> reload onto stubs) + protein FDR + blib
writing. `WriteBlibFile` (928-1088) interleaves SQLite I/O with FDR-result lookups.
Extract (names indicative):
- `Pass2FdrSidecar` -- the reload/write-sidecar/reload-onto-stubs block (Run 203-465).
- `ProteinFdr` collaborator -- promote the existing private RunProteinFdr (493-584).
- `BlibWriter` orchestrator -- the per-spectrum table-emission loop in WriteBlibFile.
Reduce Run to a sequencer. Blib writing + 2nd-pass sidecar logic are nightly-only today,
so this also advances the coverage goal -- unit-test what's parity-safe.

### Phase B -- decompose FirstJoinTask.PlanStage6 (320 LOC) + the safe pure-data seam
- `PlanStage6` (FirstJoinTask.cs:561-880): extract `CwtCandidateLoader` (the parquet
  load + ParquetIndex bounds-validation, ~704-752) and the reconciliation-planning
  decision; reduce to a sequencer.
- The ONE clean pure-data extraction rec 3 endorsed: `PercolatorEntry` construction +
  `BuildBasicFeatures` (FirstJoinTask.cs:1296-1359, 1488-1562). Extract as a testable
  `PercolatorEntryBuilder` and UNIT-TEST the feature-fallback logic (no SVM, no parity
  risk). Do NOT decompose RunPercolatorFdr itself (parity-locked).

### Phase C -- coverage closeout for the parity-locked giants
- Characterization tests at the CURRENT boundary (do not decompose) for
  RunCoelutionScoring, RunPercolatorFdr, ScoreCalibrationEntry. Needs a small spectra +
  library fixture in OspreySharp.Test (build it as phase C's first commit -- this is the
  fixture deferred in PR 3's open Q2).
- The deferred `ScoreAndDeduplicate` extraction from ProcessFile (PerFileScoringTask;
  ~44 lines of RunCoelutionScoring + the two dedup passes) -- takes ProcessFile to ~135.
- Add a guard/assert for the gap-fill `ParquetIndex` latent invariant the PR 3 self-
  review flagged: `ReconciledParquetWriter.ApplyRescoredRows` reassigns gap-fill
  ParquetIndex in place; a double-Write of the same in-memory list would re-append.
  Not reachable today (fresh per-file lists per invocation) -- add a debug assert or a
  one-line comment-guard so it stays not-reachable.

## Gates (standing OspreySharp cadence -- see osprey-development skill)
- Per commit: `Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection`
  (0 warnings) + `regression.ps1 -Dataset Stellar` (mode 1 + mode 2 byte-identical).
- Pre-merge: `regression.ps1 -Dataset All` + `Test-PerfGate.ps1 -Dataset Stellar`
  + `/pw-self-review`, then open PR, Copilot, `/pw-respond`.
- Perf gate is noisy on stage1to4 (parallel main-search); a single >4% total flag that
  is all stage1to4 with one flat rep is almost certainly environment -- RE-RUN before
  concluding a regression (see PR 3: first run +5.0%, re-run -1.6%).

## Out of scope (defer to the post-PR-4 blind OOP review)
- **Thin-exe** (Candidate B): move OspreyFileDiagnostics 2076-line sink +
  AnalysisPipeline + bootstrap out of the exe. Mostly cosmetic.
- **IOspreyDiagnostics : IScoringDiagnostics split** (Candidate C): strategic -- unblocks
  moving scorer code into OspreySharp.Scoring (project_ospreysharp_diagnostics_bleed_blocks_scoring_extraction).
  Elevate if the post-PR-4 review points at the Scoring DLL boundary.
- No always-braces ReSharper rule (feedback_no_always_braces_rule); single-line-if
  stays review-enforced.
