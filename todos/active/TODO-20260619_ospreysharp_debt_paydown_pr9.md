# TODO-20260619_ospreysharp_debt_paydown_pr9.md -- OspreySharp debt-paydown PR 9 (cleanups + retire AbstractScoringTask)

## Branch Information
- **Branch**: `Skyline/work/20260619_ospreysharp_debt_paydown_pr9` (create off master; REBASE onto master after PR 8 lands)
- **Base**: `master` (after PR 8 merges)
- **Created**: 2026-06-19
- **Status**: Queued (start after PR 8 merges)
- **PR**: (pending)

> Seeded by the 2026-06-18 blind `/pw-oop-review` (`ai/.tmp/20260618-oop-review-report.txt`,
> Rec 2 + Rec 3 + the AbstractScoringTask open question). The small/low-risk closeout of
> the arc.

## Framing -- output-invariance only; pure code motion + one debug assert
Output-locked by `regression.ps1` @1e-9. See `feedback_refactor_gate_output_not_structure`.

## Work
1. **Rec 2 -- lift the inline diagnostics out of `PercolatorFdr.RunPercolator`.** It reads
   four `OSPREY_DUMP_*` env vars inline and can `Environment.Exit(0)` mid-method. Pass a
   small `PercolatorDiagnosticsConfig` (or reuse the `IScoringDiagnostics` seam) so the FDR
   engine is a pure function of its inputs -- no env sensing, no process exit in the core.
   The Tasks-layer caller decides any early-exit. Consistent with the clean diagnostics seam.
2. **Rec 3 -- guard the shared-mutable-buffer ordering invariant.** `PipelineByproducts`
   ScoredEntries -> CompactedEntries -> RescoredEntries wrap the same `List` and mutate in
   place; safe only because the DAG consumes each milestone before the next mutation. Add a
   DEBUG-time assert that a milestone is consumed before the next in-place mutation, turning
   the documented-but-fragile invariant into a guarded one. (Open Q: if the no-copy hand-off
   is only precautionary, consider immutable snapshots instead -- confirm with Brendan; an
   assert is the low-risk default.)
3. **Retire `AbstractScoringTask`** (Brendan's call; rationale recorded). It is now a
   167-line plumbing-only base: 2 `internal const` (NUM_PIN_FEATURES, BASE_ID_MASK), the
   `internal static s_mzmlReadGate`, `FindNearestMs1`, `ExtractIsolationWindows`, and 3
   one-line forwarders to `ScoringPipeline`. The scoring BEHAVIOR already lives in
   `ScoringPipeline` (composition, PR 7); the base shares only plumbing (statics need no
   inheritance) and is an attractive nuisance for feature-envy. Move the gate + constants +
   `FindNearestMs1` + `ExtractIsolationWindows` to an `internal static` Tasks holder (or
   onto ScoringPipeline where they belong), have `PerFileScoringTask` / `PerFileRescoreTask`
   call `ScoringPipeline` directly (a `private readonly` field preserves bare-name
   ergonomics), and drop the base class (they extend `OspreyTask` directly).

## Out of scope
- The orchestration-monolith decompositions -> PR 8.

## Gates
- Per commit: `Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection`
  (0 warnings) + `regression.ps1 -Dataset Stellar` (modes 1 & 2 byte-identical).
- Pre-merge: `regression.ps1 -Dataset All` + `Test-PerfGate.ps1 -Dataset Stellar` +
  the HPC/cross-impl gates (`Compare-Stage7-Rehydration-Strict-CSharp.ps1`,
  `Compare-CrossImpl-Reference.ps1`) + `/pw-self-review`.

## Notes
- After PR 9, run the FINAL confirmatory blind `/pw-oop-review`; if clean, declare the
  OOP debt-paydown arc complete.
