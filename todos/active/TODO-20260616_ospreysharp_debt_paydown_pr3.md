# TODO-20260616_ospreysharp_debt_paydown_pr3.md -- OspreySharp debt-paydown PR 3 (extract collaborators + unit tests)

## Branch Information
- **Branch**: `Skyline/work/20260616_ospreysharp_debt_paydown_pr3`
- **Base**: `master` (pwiz at 6ee60e4e43, just merged #4304)
- **Created**: 2026-06-16
- **Status**: In Progress
- **PR**: [#4308](https://github.com/ProteoWizard/pwiz/pull/4308)

> PR 3 of the OspreySharp debt-paydown arc. See memory
> project_ospreysharp_debt_paydown_arc for the full arc and
> project_osprey_organic_growth_needs_iterative_oop_review for the
> iterative-blind-review doctrine.

## Where the arc stands (as of 2026-06-16)
- **PR 1 (#4302, merged 2026-06-15):** diagnostics static-coupling broken; new
  OspreySharp.Diagnostics DLL with IOspreyDiagnostics injected on PipelineContext.
- **PR 2 (#4304, merged 2026-06-16):** the 7 task bodies + RescoreHydration/
  RescoreCompaction + ProfilerHooks lifted into the OspreySharp.Tasks DLL -- the
  pipeline layer is now a unit-testable DLL. Also adopted the Skyline version
  scheme + cache-version hard-fail. Output byte-identical, perf-neutral.

## Blind OOP review (done 2026-06-16, this session)
Ran `/pw-oop-review` on the exe's AnalysisPipeline + the OspreySharp.Tasks DLL
before scoping. Findings:
- **Orchestration spine is strong.** AnalysisPipeline (283 LOC thin driver),
  OspreyTask, PipelineContext, PipelineByproducts. Encapsulation, modularity,
  coupling all graded Strong: cross-task reads go through the typed byproduct
  registry (Publish/Get/Demand), single-producer guard at construction, and the
  last concrete-sibling reach was already dissolved into the PlanningPerformed
  byproduct. Preserve this; do not disturb it.
- **Dominant issue: low cohesion INSIDE the task bodies.** Each task is a
  1000-1700 LOC file built around one 250-375 LOC god-method bundling 5-15
  responsibilities:
  - `PerFileRescoreTask.ExecuteRescore` (612-911, 300 LOC) -- worst offender
  - `MergeNodeTask.Run` (113-486, 374 LOC)
  - `FirstJoinTask.PlanStage6` (561-880, 320 LOC)
  - `PerFileScoringTask.ProcessFile` (1119-1413, 294 LOC)
  - `Calibrator.ScoreCalibrationEntry` (913-1203, 291 LOC; cohesive but dense)
- **Near-duplication:** per-file resume + reconciled-parquet I/O appears inline in
  BOTH PerFileScoringTask (ScoreOrLoadForFile / TryLoadStubsAndCalibration,
  983-1114) and PerFileRescoreTask (644-690, 867-900, WriteReconciledParquet
  475-587). Both probe disk, check TaskValiditySidecar.IsValid, stamp/clean
  sidecars. This is the highest-leverage extraction: real duplication + pure-ish
  I/O that is parity-safe to unit-test.

The review confirmed **Candidate A leads** over B (full thin-exe) and C
(IOspreyDiagnostics:IScoringDiagnostics split). Those stay deferred (see below).

## This sprint: scope = Seam + orchestrator (Brendan's call, 2026-06-16)
Recommendations 1 + 2 + 3 from the review, in order. Tackle the parity-safe seam
first, then the orchestrator decomposition behind the regression gate.

### Step 1 -- Extract the resume/IO seam, with unit tests (rec 1)
- [x] `ReconciledParquetWriter` (DONE 2026-06-16, commit 584309176a on branch):
  lifted `PerFileRescoreTask.WriteReconciledParquet` (was 475-587) into an
  internal `ReconciledParquetWriter` (OspreySharp.Tasks) with two pure helpers --
  `ApplyRescoredRows` (replace-by-ParquetIndex + skip Features==null + append
  gap-fill + reassign index + out-of-range warn) and `BuildReconciliationMetadata`
  (joinFileStems-present vs config fallback hash). Logging via `Action<string>`
  callbacks, NOT PipelineContext, so it unit-tests without a live context. The
  task now calls `ReconciledParquetWriter.Write(... ctx.LogInfo, ctx.LogWarning)`.
  - Tests: `ReconciledParquetWriterTest` (2 methods) cover both helpers. Q2
    resolved -- no parquet fixture needed; the pure helpers are the parity-
    relevant logic. (A full Write round-trip via Path.GetTempFileName, the
    IOTest idiom, can be added later if desired.)
  - Gate: 0 inspection warnings; 385 tests pass (2 pre-existing skips); Stellar
    regression mode 1 (vs golden) + mode 2 (resume==straight) PASS, blib
    byte-identical (52,514,816 bytes).
- [x] `PerFileResumeDriver` (DONE 2026-06-16, commit c098f80ca6 on branch):
  Q3 resolved -- SHARED HELPER, not a unified driver (Brendan's call). The driver
  owns ONLY the sidecar mechanics: `IsCurrent` (File.Exists && IsValid), `ClearStale`
  (Delete), `Stamp` (Write + try/catch + warn via Action callback). Each task keeps
  its own load/compute/output shape. Removed the duplicated try/catch sidecar-write
  block from both PerFileScoringTask and PerFileRescoreTask; the rescore task's
  failed-output parquet delete stays inline (output mechanics, not sidecar).
  - Tests: `PerFileResumeDriverTest` (2 methods) -- probe/stamp/clear round-trip
    (incl. the File.Exists gate and key-mismatch) and swallowed write failure.
  - Gate: 0 inspection warnings; 389 tests pass (2 pre-existing skips); Stellar
    regression mode 1 + mode 2 PASS, blib byte-identical (52,514,816 bytes). Mode 2
    (resume) directly exercises the touched paths.

**Step 1 COMPLETE.** Both resume/IO seams extracted + unit-tested, output
byte-identical. Two unpushed pwiz commits on the branch: 584309176a, c098f80ca6.
- `PerFileResumeDriver`: lift the sidecar probe-and-stamp logic shared by the two
  tasks (PerFileRescoreTask 644-690 + 867-900; PerFileScoringTask 983-1114). Unit-
  test skip decisions and sidecar validity directly. Decide (open Q3) whether the
  two tasks UNIFY on one driver or just both call a shared helper -- their output
  shapes differ (.scores.parquet vs .scores-reconciled.parquet).
- Build a tiny parquet + sidecar test fixture first if none exists (open Q2).

### Step 2 -- Decompose the orchestration loops (rec 2)
- [x] `ExecuteRescore` -> sequencer (DONE 2026-06-16, commit eaab6dab3d): lifted
  the 250-line per-file loop body into a named `RescoreOneFile`; `ExecuteRescore`
  is now a ~50-line setup + accumulate sequencer. Cross-file inputs bundled into a
  private `RescorePassInputs` (one collaborator object vs a dozen positional
  params). Pure code motion + dropped a now-provably-redundant null check.
- [x] `ProcessFile` -> extracted `ResolveCalibration` (DONE 2026-06-16, commit
  pending): lifted the ~115-line calibration phase (load cached/Rust JSON or
  compute via Calibrator, then persist the calibration JSON) into a named helper;
  ProcessFile drops ~294 -> ~180. Scoring orchestration left whole (characterized,
  not re-derived, per feedback_no_unverified_ports).
  - Optional further cut (not done): a `ScoreAndDeduplicate` helper around
    RunCoelutionScoring + the two dedup passes (~44 lines) would take ProcessFile
    to ~135. Deferred -- diminishing returns vs the calibration extraction.
- Each move verified output byte-identical (Stellar mode 1 + mode 2, blib
  52,514,816 bytes) + 0 inspection warnings + 389 tests pass.

**Step 2 COMPLETE** (both god-methods decomposed). Unpushed pwiz commits on the
branch: 584309176a, c098f80ca6, eaab6dab3d, + the ProcessFile commit.

### Step 3 -- Characterization tests on parity-locked giants (rec 3)
- Wrap RunCoelutionScoring, ScoreCandidate, RunPercolatorFdr (FirstJoinTask
  1265-1487), ScoreCalibrationEntry at their CURRENT boundary -- do not decompose
  for testability (honors feedback_no_unverified_ports).
- Only clean pure-data extraction worth pulling: BuildBasicFeatures /
  PercolatorEntry construction (FirstJoinTask 1296-1359, 1488-1562).

## Open questions to resolve as work proceeds
1. (answered) Scope = Seam + orchestrator.
2. Test substrate: does OspreySharp.Test already have a tiny few-row
   .scores.parquet fixture, or is building one the PR's first commit?
3. Unify PerFileScoring/PerFileRescore resume logic on one driver, or just have
   both call a shared helper? (Output shapes differ.)

## Pre-merge gate results (2026-06-16, all green)
- **Self-review** (`/pw-self-review`, fresh-context agent): CLEAN, no findings at
  any severity. Independently verified the dropped null-check (provably non-null),
  the continue->return counter equivalence, ResolveCalibration out-param definite
  assignment + preserved ordering, PerFileResumeDriver call-site equivalence,
  BuildReconciliationMetadata hash-regime + keys, and concurrency (helper touches
  only per-file clones).
  - Latent invariant it flagged (NOT a PR-3 regression; pre-existing behavior):
    `ApplyRescoredRows` reassigns gap-fill `ParquetIndex` in place, so passing the
    SAME in-memory FdrEntry list to `ReconciledParquetWriter.Write` twice would
    re-append. Not reachable today -- each pipeline/worker invocation hydrates
    fresh per-file lists and the loop visits each file once. Noted for the future.
- **Full regression** `regression.ps1 -Dataset All`: PASS. Stellar mode1+mode2
  (blib 52,514,816) and Astral mode1+mode2 (blib 136,622,080), all byte-identical.
- **Perf gate** `Test-PerfGate.ps1 -Dataset Stellar`: PASS (perf-neutral). First run
  flagged total +5.0% but entirely in high-variance stage1to4 (baseline's own
  intra-run spread was ~24%, one rep flat); re-run on a quiet machine gave total
  -1.6% (stage1to4 -3.6%, branch faster). Two runs straddling zero == environmental
  noise, not a code regression (pure code motion can't regress 5%). Verify-before-
  blaming confirmed environment, not code.

## Gates (the standing OspreySharp cadence -- see osprey-development skill)
- Per commit: `Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection`
  (0 warnings) + `regression.ps1 -Dataset Stellar` (mode 1 + mode 2).
- Pre-merge: `regression.ps1 -Dataset All` + `Test-PerfGate.ps1 -Dataset Stellar`
  + `/pw-self-review` (then open PR, Copilot, optional /code-review ultra).
- PR cadence (Brendan's preference): ONE PR, multiple commit-and-test cycles;
  parity-check after EACH commit. The 41-min nightly stays as the integration
  backstop -- lean on it for big mechanical moves; the goal is to grow per-PR unit
  coverage so we depend on it less.

## Out of scope / watch / deferred
- **Candidate B (full thin-exe):** move OspreyFileDiagnostics sink +
  AnalysisPipeline + OspreyDiagnostics bootstrap out of the exe. AnalysisPipeline
  still references Program.Log* and OspreyDiagnostics statics (AnalysisPipeline.cs
  62, 266-279) -- cosmetic vs the cohesion problem. Deferred.
- **Candidate C (IOspreyDiagnostics : IScoringDiagnostics split):** the gate-flags-
  vs-writes interface split (project_ospreysharp_diagnostics_bleed_blocks_scoring_extraction).
  Deferred.
- The dash-hygiene verifier + cleanup is a SEPARATE backlog item
  (TODO-dash_hygiene_verifier_and_cleanup.md), not this sprint.
- The Jamfile version-injection path (PR 2) is only TeamCity-verified; glance at the
  next nightly to confirm it stamps cleanly.
