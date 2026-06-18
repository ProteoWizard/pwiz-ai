# TODO-20260618_ospreysharp_debt_paydown_pr6.md -- OspreySharp debt-paydown PR 6 (ProteinFdrEngine: finish the FDR-ownership move)

## Branch Information
- **Branch**: `Skyline/work/20260618_ospreysharp_debt_paydown_pr6` (to be created off master)
- **Base**: `master` (after PR 5 #4314 merged as 3c464c983b)
- **Created**: 2026-06-18
- **Status**: Ready to start (PR 5 merged)
- **PR**: (pending)

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

## Secondary (only if still warranted) -- decompose RunPercolator in place
`RunPercolator` now lives in `OspreySharp.FDR/PercolatorEngine.cs` (PR 5 moved it but
did not carve it). If it is still a meaningful giant (check current LOC -- the file is
~352 lines total, so it may already be modest), extract a `PercolatorTrainer`
(folds + standardizer + scoring) by pure motion in its final home. Skip if it no
longer warrants it.

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

## Notes
- `project_ospreysharp_diagnostics_bleed_blocks_scoring_extraction` is STALE: the
  scoring seam is clean (lower layers see `IScoringDiagnostics`/`IOspreyDiagnostics`;
  no static call to the exe-level facade). The ctx/Exit severance, not a diagnostics
  bleed, is the work here. Update that memory when convenient.
- After PR 6 + PR 7 land, run the next blind `/pw-oop-review` to re-survey the
  decomposed tree (cadence: ~3-4 PRs per review; PR 5/6/7 are this batch).
