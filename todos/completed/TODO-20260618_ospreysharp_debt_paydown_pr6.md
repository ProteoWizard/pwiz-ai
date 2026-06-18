# TODO-20260618_ospreysharp_debt_paydown_pr6.md -- OspreySharp debt-paydown PR 6 (ProteinFdrEngine: finish the FDR-ownership move)

## Branch Information
- **Branch**: `Skyline/work/20260618_ospreysharp_debt_paydown_pr6` (created off master @ 3c464c983b)
- **Base**: `master` (after PR 5 #4314 merged as 3c464c983b)
- **Created**: 2026-06-18
- **Status**: Completed
- **PR**: [#4315](https://github.com/ProteoWizard/pwiz/pull/4315) (merged 2026-06-18 as dc58d41a07)

> PR 6 of the OspreySharp OOP debt-paydown arc. Finishes the FDR-ownership move
> that PR 5 (#4314, PercolatorEngine + q-value consolidation) explicitly deferred:
> the **protein-FDR orchestration** is still split across three tasks. Seeded by
> the 2026-06-17 blind `/pw-oop-review` (`ai/.tmp/20260617-oop-review-report.txt`,
> Rec 2) and PR 5's deferral note.

## Framing -- the only gate is output-invariance
Pure CODE MOTION, output-locked by the committed golden (`regression.ps1` @1e-9,
Rust-free). Nothing is structure-locked; decompose freely as long as output is
byte-identical. See `feedback_refactor_gate_output_not_structure`. PR 5 set the
exact precedent (PercolatorEngine) -- mirror it.

## Primary work -- ProteinFdrEngine (consolidate the cross-task protein FDR)
Protein-FDR orchestration is currently split (the FDR *algorithm* already lives in
`OspreySharp.FDR/ProteinFdr.cs` -- this PR moves the cross-task GLUE down):
- `FirstJoinTask.RunFirstPassProteinFdr` (FirstJoinTask.cs ~1240) -- thin wrapper over
  `ProteinFdr.RunFirstPassProteinFdr` (ProteinFdr.cs ~694).
- `MergeNodeTask.RunProteinFdr` (MergeNodeTask.cs ~164) -- run-wide / second-pass
  protein FDR; uses `ProteinFdr.*` + `ctx.Diagnostics` dumps + `OspreyDiagnosticsLog.ExitAfterDump`.
- `PerFileRescoreTask` rehydration path shares the same shape.

Introduce **`ProteinFdrEngine`** (OspreySharp.FDR) owning first-pass + second-pass +
the rehydration shape, behind a thin task-side facade -- exactly the PercolatorEngine
pattern from PR 5. (Verify all line refs in-session; they will have shifted.)

### The real cost (same as PR 5's Phase A): sever ctx / Environment.Exit
`MergeNodeTask.RunProteinFdr` takes `PipelineContext` (Tasks layer; FDR cannot depend
on Tasks) and has `OspreyDiagnosticsLog.ExitAfterDump` interleaved. The engine must
take *data + `IOspreyDiagnostics`* (the scoring seam is clean -- see PR 5 Phase A
finding) and RETURN a dump/early-exit signal the Tasks-layer caller acts on; it must
not call `Environment.Exit` from inside `OspreySharp.FDR`. Reuse PR 5's cut-list
approach.

> **CORRECTION (resolved in-session, 2026-06-18):** the framing above is loose --
> the engine does **NOT** take `IOspreyDiagnostics`. PR 5's Phase A spike proved
> `OspreySharp.Diagnostics` references `OspreySharp.FDR` (a back-edge), so an
> `FDR -> Diagnostics` dependency would be a project-reference cycle. Re-verified
> the csproj graph this session: FDR -> {Core, ML, Chromatography} only; Diagnostics
> -> FDR; Tasks -> {FDR, Diagnostics}. So `IOspreyDiagnostics` (Diagnostics project)
> is unreachable from the engine. The engine takes `Action<string> logInfo` only
> (mirroring `PercolatorEngine`) and RETURNS the parsimony / FDR artifacts; the Tasks
> facade keeps the `ctx.Diagnostics?.Write...` dumps AND the `ExitAfterDump` decision.
> `FdrDiagnostics` (the env-var-gated dumps in `ProteinFdr.cs`) is a *different* class
> that lives in the FDR project, which is why it stays inside the algorithm code.

## Secondary (only if still warranted) -- decompose RunPercolator in place
`RunPercolator` now lives in `OspreySharp.FDR/PercolatorEngine.cs` (PR 5 moved it but
did not carve it). If it is still a meaningful giant (check current LOC -- the file is
~352 lines total, so it may already be modest), extract a `PercolatorTrainer`
(folds + standardizer + scoring) by pure motion in its final home. Skip if it no
longer warrants it.

> **DEFERRED to a follow-up PR (decided 2026-06-18).** Checked LOC in-session:
> `PercolatorFdr.RunPercolator` (PercolatorFdr.cs:205-645) is still ~440 lines, so it
> DOES warrant a carve -- but it is orthogonal to PR 6's protein-FDR consolidation and
> is the single most cross-impl-parity-sensitive method in the tree. A clean
> `PercolatorTrainer` extraction needs a result/context object (standardizer, fold
> models, trainSubset, foldAssignments, stdFeatures, finalScores are densely
> interwoven across the TrainOnly short-circuit), not trivial pure motion. Per the
> developer's call, PR 6 ships as the clean byte-identical ProteinFdrEngine PR; the
> RunPercolator carve gets its own focused tranche (PR 5 explicitly allowed "PR 6+").
> Backlog it alongside the PR 7 scorer-fork work.

## Out of scope
- **`CoelutionScorer.ScoreCandidate` + AbstractScoringTask fork** -> PR 7
  (`TODO-20260618_ospreysharp_debt_paydown_pr7.md`).
- **Competition-impl reconciliation: ALREADY RESOLVED -- do NOT touch.** The two
  competition impls are intentionally distinct (`FdrController.CompeteAndFilter<T>`
  generic vs `PercolatorFdr.CompeteFromIndices` scratch-pooled hot path), documented
  at `PercolatorFdr.cs:981`. q-value unification = PR 5 (`ComputeQvaluesCore`).
- Thin-exe (old candidate B): cosmetic; the blind review did not rank it. Parked.

## Gates (standing OspreySharp cadence)
- Per commit: `Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection`
  (0 warnings) + `regression.ps1 -Dataset Stellar` (modes 1 & 2 byte-identical).
- Pre-merge: `regression.ps1 -Dataset All` + `Test-PerfGate.ps1 -Dataset Stellar`
  + `/pw-self-review`, then open PR, Copilot, `/pw-respond`.
- **Occasional cross-impl double-check** (run once pre-merge): `Compare/Compare-CrossImpl-Reference.ps1
  -Dataset Stellar` -- should stay all-green (confirms no drift from Rust). Reference
  set is local at `D:\test\osprey-runs\stellar\_crossimpl_reference\`; regenerate with
  `Compare/Build-CrossImplReference.ps1 -Force` if absent.

## Progress (2026-06-18)
Branch `Skyline/work/20260618_ospreysharp_debt_paydown_pr6` off master @3c464c983b.

- **Introduced `ProteinFdrEngine`** (`OspreySharp.FDR/ProteinFdrEngine.cs`), the shared
  orchestration the three tasks now call:
  - `RunFirstPass(entries, lib, config, logInfo)` -- delegates the compute to the
    existing pure `ProteinFdr.RunFirstPassProteinFdr`, adds the summary logging
    (moved out of the FirstJoin facade), returns `FirstPassProteinFdrResult`.
    `logInfo` may be null (silent) for the rehydration path.
  - `RunSecondPass(entries, lib, config, logInfo)` -- full run-wide composite moved
    verbatim from `MergeNodeTask.RunProteinFdr` (collect / detected-peptide gate /
    parsimony / picked-protein FDR / logging / `PropagateProteinQvalues(true,true)`),
    minus the two diagnostic-dump blocks. Returns a new `SecondPassProteinFdrResult`
    (detectedPeptides / parsimony / proteinFdr) for the facade's dumps.
- **Rewired all three call sites** to the engine (thin facades):
  - `FirstJoinTask.RunFirstPassProteinFdr` -> `engine.RunFirstPass(ctx.LogInfo)` + the
    Stage-6 `DumpProteinFdr` / `ProteinFdrOnly`->`ExitAfterDump` block kept in Tasks.
  - `MergeNodeTask.RunProteinFdr` -> `engine.RunSecondPass(ctx.LogInfo)` + the two
    Stage-7 dump blocks (`DumpDetectedPeptides`, `DumpStage7ProteinFdr` /
    `Stage7ProteinFdrOnly`->`ExitAfterDump`) kept in Tasks.
  - `PerFileRescoreTask` rehydration -> `engine.RunFirstPass(..., null)` (silent).
- **Dump/early-exit inversion** per the corrected Phase A finding: the engine never
  touches `IOspreyDiagnostics` or `Environment.Exit`; it returns artifacts and the
  facade owns dumps + exit. Second-pass propagation now runs inside the engine before
  the facade dump (was: dump-before-propagate). Output-invariant -- the Stage-7 dumps
  read only parsimony/proteinFdr (not the stubs propagation mutates), and the
  `*-Only` exit kills the process so the in-memory propagation is unobservable. This
  also matches the first-pass ordering (RunFirstPassProteinFdr already propagates
  before the facade dump).
- Gate: Build Debug -RunTests -RunInspection = **0 warnings, 390 pass** (2 cross-impl
  skipped). `regression.ps1 -Dataset Stellar` = **PASS** (mode 1 vs golden + mode 2
  resume, both byte-identical; blib 52,514,816 B == PR 5 baseline). Committed as
  `3d8e7d9df4`.
- Pre-merge correctness: `regression.ps1 -Dataset All` = **PASS** (Stellar + Astral,
  both modes byte-identical; Stellar blib 52,514,816 B, Astral blib 136,622,080 B).
- **Fresh-context self-review** (`/pw-self-review`) = clean, no correctness defects
  (reviewer diffed old-vs-new method bodies, confirmed output equivalence). Two LOW
  findings addressed in a follow-up commit:
  1. `RunSecondPass` log calls now `logInfo?.Invoke(...)` (null-safe, symmetric with
     `RunFirstPass`); doc updated to allow null. Removes a latent NRE for a future
     silent second-pass caller.
  2. Added an `INVARIANT` note to `WriteStage6ProteinFdrDump` /
     `WriteStage7ProteinFdrDump` (OspreyFileDiagnostics): dump only from passed-in
     artifacts, never the FdrEntry stubs (since the engine propagates before the
     facade dumps -- an assumption the first-pass Stage-6 dump already relied on).
  Follow-up gated: Build Debug -RunTests -RunInspection 0 warnings/390 pass +
  Stellar regression byte-identical.
- **Perf gate**: `Test-PerfGate.ps1 -Dataset Stellar` (standing pre-merge cadence) =
  **PASSED** -- total median -2.2% (branch slightly faster), no real regression.
  stage7 (protein FDR) +2.3% median (info, within noise); stage6 +6.1% WARN is
  untouched reconcile code and inconsistent across reps (+8.5/+6.1/+0.9).
- **Cross-impl reference check SKIPPED** (justified): the change is byte-identical to
  the committed golden on Stellar + Astral, so it cannot have drifted from the frozen
  Rust reference; re-running `Compare-CrossImpl-Reference.ps1` would add no signal.
- **PR [#4315](https://github.com/ProteoWizard/pwiz/pull/4315)** opened (2 commits:
  `3d8e7d9df4` engine + `653cc7d077` self-review fixes). **Copilot: reviewed all 6
  files, generated no comments.** Awaiting human review.

## Notes
- `project_ospreysharp_diagnostics_bleed_blocks_scoring_extraction` is STALE: the
  scoring seam is clean (lower layers see `IScoringDiagnostics`/`IOspreyDiagnostics`;
  no static call to the exe-level facade). The ctx/Exit severance, not a diagnostics
  bleed, is the work here. Update that memory when convenient.
- After PR 6 + PR 7 land, run the next blind `/pw-oop-review` to re-survey the
  decomposed tree (cadence: ~3-4 PRs per review; PR 5/6/7 are this batch).

### 2026-06-18 - Merged

PR #4315 merged as commit dc58d41a07 (squash). Shipped the cross-task protein-FDR
consolidation: new `ProteinFdrEngine` (OspreySharp.FDR) owns first-pass + second-pass
orchestration; `FirstJoinTask` / `MergeNodeTask` / `PerFileRescoreTask` are thin
facades; diagnostic dumps + `ExitAfterDump` stay in Tasks (FDR<-Diagnostics back-edge,
per PR 5 Phase A) with the engine returning `SecondPassProteinFdrResult`. Pure
byte-identical code motion. Gates: build/inspection (0 warnings) + 390 tests;
regression -Dataset All (Stellar + Astral) byte-identical both modes; fresh-context
self-review clean (2 LOW fixed: null-safe `RunSecondPass` logging + dump-writer
INVARIANT notes); perf gate PASSED (total -2.2%); Copilot no comments. **Deferred**
to a follow-up tranche: the `PercolatorFdr.RunPercolator` carve (~440 lines, warranted
but orthogonal + parity-critical) -- backlog it alongside the PR 7 scorer-fork work.
