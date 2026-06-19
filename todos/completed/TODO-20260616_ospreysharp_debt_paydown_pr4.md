# TODO-20260616_ospreysharp_debt_paydown_pr4.md -- OspreySharp debt-paydown PR 4 (decompose remaining god-methods)

## Branch Information
- **Branch**: `Skyline/work/20260616_ospreysharp_debt_paydown_pr4`
- **Base**: `master` (created off 6ee60e4e43; REBASE onto merged master after PR 3 #4308 lands -- see startup)
- **Created**: 2026-06-16
- **Status**: Completed
- **PR**: [#4310](https://github.com/ProteoWizard/pwiz/pull/4310) (merged 2026-06-17 as 42bab53085)

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

## Progress Log

### 2026-06-16 -- session start + Phase A commit A1
- PR 3 (#4308) merged 22:17 UTC (merge cf9af7ec). Rebased the empty PR 4 branch
  onto merged master (trivial fast-forward; branch had no commits yet).
- Confirmed the file already matched the TODO's line refs: `ProteinFdr`, the
  low-level `BlibWriter`, and the `WriteBlib*` helpers were already separate;
  the one remaining god-method was `Run` (374 LOC), ~330 of which were the
  inline 2nd-pass FDR sidecar dance.
- **Commit A1 (ffc74a42a5):** extracted `Pass2FdrSidecar` (new Tasks-DLL file)
  via pure code motion -- the reload-features / run-2nd-pass-Percolator /
  write-sidecars / reload-onto-stubs block. `Run` is now a ~45-line sequencer.
  The parity-locked `FirstJoinTask.RunPercolatorFdr` is invoked whole through
  `ctx` (not decomposed). Build + 387 tests + 0-warning inspection green;
  `regression.ps1 -Dataset Stellar` byte-identical (modes 1 & 2, blib
  52,514,816 bytes).
- Confirmed `OspreyDiagnosticsLog` lives in the Diagnostics DLL, so the planned
  `ProteinFdr collaborator` promotion of `RunProteinFdr` cannot move to the FDR
  DLL (diagnostics bleed); it stays in Tasks. Note: the TODO's `BlibWriter
  orchestrator` name collides with the existing low-level `BlibWriter`; a
  different name (e.g. `BlibOutputWriter`) will be needed if that extraction
  proceeds.
- **Commit A2 (2e791e2fb2):** extracted the pure `MapFeaturesByParquetIndex`
  seam from `Pass2FdrSidecar` (bounds-checked ParquetIndex->Features overlay,
  out-of-range skip) and added `Pass2FdrSidecarTest` (390 tests now, +1).
  Byte-identical Stellar (modes 1 & 2). The parity-locked reload/percolator/
  sidecar-IO orchestration stays characterized by regression.ps1, not unit tests.
- **Commit A3 (c762e4f736):** at Brendan's call, finished the Phase A blib bullet.
  Moved `WriteBlibFile` + `WriteRetentionTimes` out of MergeNodeTask into a new
  `BlibOutputWriter` collaborator (named to avoid colliding with the low-level
  `BlibWriter` SQLite layer) and decomposed it into a sequencer:
  `CreateSourceFiles` -> `PrecompressSpectra` -> `EmitSpectrumRows` ->
  `WriteMetadata` (+ private `WriteRetentionTimes`). Removed now-redundant
  `System.Linq` / `System.Threading.Tasks` usings from MergeNodeTask.
  Byte-identical Stellar (modes 1 & 2).

### PHASE A COMPLETE (2026-06-16)
- A1 (4943ad2758) Pass2FdrSidecar; A2 (2e791e2fb2) MapFeaturesByParquetIndex
  + unit test; A3 (c762e4f736) BlibOutputWriter.
- `MergeNodeTask.cs`: **1091 -> 529 LOC**. `Run` is a ~45-line sequencer;
  the two Stage-7/9 substeps (2nd-pass sidecar, blib emission) now live in
  their own testable collaborators. All three commits pure code motion,
  byte-identical on Stellar; pre-commit gate (build + 0-warning inspection +
  388 unit tests) green throughout. Skipped only the `RunProteinFdr`
  promotion (diagnostics bleed keeps it in Tasks; Run is already a sequencer).
- **Next: Phase B** -- decompose `FirstJoinTask.PlanStage6` (320 LOC):
  extract `CwtCandidateLoader` (parquet load + ParquetIndex bounds-validation)
  and the reconciliation-planning decision; reduce to a sequencer. Plus the
  pure-data `PercolatorEntryBuilder` seam (PercolatorEntry + BuildBasicFeatures,
  unit-test the feature-fallback; do NOT decompose RunPercolatorFdr).

### PHASE B COMPLETE (2026-06-16)
- B1 (092f6c7632) `CwtCandidateLoader`: moved the Stage 6 per-file CWT-candidate
  load + ParquetIndex bounds-validation loop out of `PlanStage6` into a collaborator
  with a pure `MaxParquetIndex` seam + unit test.
- B2 (c968bfdfd6) `PercolatorEntryBuilder`: moved the PercolatorEntry construction
  + `BuildBasicFeatures` out of the parity-locked `RunPercolatorFdr` (the SVM core
  stays whole) + unit-tested the feature-fallback (stored 21-vec vs basic-vector
  for null/wrong-length, counts, order, PSM-id).
- Both pure code motion, byte-identical Stellar (modes 1 & 2); gate green (392 tests).
- **Observed dead code (preserved, NOT changed):** `BuildBasicFeatures`'s
  `libraryById` param is unused by its body, so the `libraryById` dict that
  `RunPercolatorFdr`/`PercolatorEntryBuilder.Build` builds is dead (its only
  consumer ignores it). Left verbatim to keep B2 strict pure-motion and avoid an
  unused-`fullLibrary`-param ripple on the public `RunPercolatorFdr` signature.
  Candidate tiny cleanup for a later commit / the post-PR-4 review.
### PHASE C (in progress 2026-06-16)
- C1 (dc41da48a7) ApplyRescoredRows single-invocation comment-guard (comment-only,
  byte-identical by construction; no Debug.Assert -- footprint collides with the
  legitimate out-of-range stub the existing ReconciledParquetWriterTest exercises).
- C2 (3a143c6475) extracted `ScoreAndDeduplicate` from ProcessFile (pure code
  motion; parity-locked scoring/dedup cores invoked whole). Byte-identical Stellar.
- **C3 characterization-fixture assessment (the PR 3 open-Q2 deferral):** after
  investigating the three targets, the in-process characterization fixture is
  **low-ROI / brittle** and recommended for continued deferral:
  - RunCoelutionScoring / RunPercolatorFdr / ScoreCalibrationEntry are heavy
    orchestrators needing a full spectra+library+calibration+context setup.
  - Their **primitives are already finely unit-tested** (ScoringTest,
    OspreyFeatureCalculatorsTest, MLTest, CalibrationTest), and their **end-to-end
    output is already pinned byte-identical** by the committed golden in
    regression.ps1 + the 41-min nightly.
  - An in-process characterization would need either large captured binary
    fixtures (duplicating the golden, brittle to any intended change) or a
    synthetic fixture so minimal it exercises a degenerate path -- exactly the
    no-unverified-tests concern (feedback_no_unverified_ports / feedback_parity_vs_impact).
  - **Recommendation:** treat Phase C as done with C1+C2; backlog the heavy
    characterization fixture until there is a concrete reason (a planned change to
    those scorers needing a finer-grained safety net than the golden). Awaiting
    Brendan's call (he selected "Full Phase C").
  - **DECISION (Brendan, 2026-06-16): defer C3.** Phase C complete with C1+C2;
    heavy characterization fixture backlogged. Moving to pre-merge gates + PR.

### PHASE C COMPLETE (C1+C2; C3 deferred) -- PR 4 ready for pre-merge
- 8 commits total: A1 4943ad2758, A2 2e791e2fb2, A3 c762e4f736, B1 092f6c7632,
  B2 c968bfdfd6, C1 dc41da48a7, C2 3a143c6475 (C3 deferred to backlog).
- All pure code motion / comment-only; every commit byte-identical on Stellar
  (modes 1 & 2); pre-commit gate (build + 0-warning inspection + 392 unit tests)
  green throughout. 3 new parity-safe unit-tested seams (MapFeaturesByParquetIndex,
  CwtCandidateLoader.MaxParquetIndex, PercolatorEntryBuilder feature-fallback).
- **Pre-merge (all green):** regression.ps1 -Dataset All (Stellar + Astral, modes
  1 & 2 byte-identical) + Test-PerfGate.ps1 -Dataset Stellar (+1.8% total, PASS)
  + /pw-self-review (no CRITICAL/HIGH). PR #4310 opened.

### COPILOT ROUND (2026-06-16) -- commit 78cffc9ab4
- Copilot flagged ONE issue: the dead `libraryById`/unused-param in
  PercolatorEntryBuilder (the exact dead code flagged after B2). Addressed it
  fully (Full removal, Brendan's call): threaded the now-dead `fullLibrary` out
  of PercolatorEntryBuilder.Build/BuildBasicFeatures, RunPercolatorFdr, RunFdr,
  Pass2FdrSidecar.ComputeAndPersist, and the MergeNodeTask call (5 files, -10 net).
  Pure dead-code removal, byte-identical Stellar (modes 1 & 2), 392 tests / 0
  warnings. Replied + resolved the thread. The earlier "dead libraryById param"
  TODO note is now RESOLVED in-PR (no longer a backlog item).
- Optional next: /ultrareview 4310 (user-triggered). Otherwise awaiting human merge.

### 2026-06-17 - Merged

PR #4310 merged as commit 42bab53085 (squash). Shipped: decomposition of the two
remaining OspreySharp task god-methods via pure code motion -- MergeNodeTask.Run
(1091->529 LOC file; Run itself 374->~45 LOC) and FirstJoinTask.PlanStage6 -- plus
a shrunk PerFileScoringTask.ProcessFile, four new Tasks collaborators
(Pass2FdrSidecar, BlibOutputWriter, CwtCandidateLoader, PercolatorEntryBuilder),
three new parity-safe unit-tested seams, the ApplyRescoredRows single-invocation
comment-guard, and the dead-fullLibrary removal from the Copilot round. Every
commit byte-identical on Stellar; pre-merge gates green (regression All Stellar +
Astral modes 1 & 2, perf +1.8%, self-review clean, Copilot addressed + resolved,
TeamCity 20/20). Ultrareview skipped (review yield was minimal).
**Deferred (NOT shipped):** the C3 characterization-test fixture for the
parity-locked giants (RunCoelutionScoring / RunPercolatorFdr / ScoreCalibrationEntry)
-- backlogged as low-ROI until a concrete trigger; see the C3 assessment above.
**Follow-up:** run a fresh blind /pw-oop-review on the post-decomposition
Tasks->Scoring/Diagnostics boundary to seed PR 5 (candidates: thin-exe B;
IOspreyDiagnostics:IScoringDiagnostics split C, the strategic one that unblocks
moving scorer code into OspreySharp.Scoring).
