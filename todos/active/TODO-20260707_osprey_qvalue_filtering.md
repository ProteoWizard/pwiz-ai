# TODO: Osprey q-value filtering — enforce run∧experiment on the emitted q

## Branch Information
- **Branch**: `Skyline/work/20260707_osprey_qvalue_filtering`
- **Base**: `master` (`31168db37b`)
- **Created**: 2026-07-07
- **Status**: Design / not started
- **Worktree**: `C:\proj\pwiz`
- **Requested by**: Brendan (with Mike's blib observation)

## The problem
Osprey can report a peptide at experiment-level q < 1% that has **no run** passing run-level
q < 1%. Mike sees this in Skyline as blib ID lines that "shouldn't be possible" — the
compaction rule is *supposed* to guarantee every reported peptide clears run-level FDR in at
least one run. Same root issue makes the **Pass-1 experiment-wide** FDP calibration
anti-conservative (~2% at 1% q) while **Pass-2** (post-compaction) is ~0.9%: the calibration
"benefit" of Pass 2 is really just that the run-level gate got applied to the pool.

## Why it happens (verified in code)
The run-level requirement is enforced **once, indirectly, at the wrong place**:
1. **Compaction** (`FirstJoinTask.cs:605`) keeps a base_id iff `RunPeptideQvalue ≤ config.RunFdr`
   in ≥1 run — using **Pass-1** q-values, and only as a *pool* filter (a memory optimization).
2. **Pass-2 Percolator** (`Pass2FdrSidecar`, `--protein-fdr`) **recomputes** run-q and
   experiment-q from rescored features but **never re-applies** that gate. A peptide compacted
   in on its Pass-1 run-q can end up with every Pass-2 run-q > 1% yet still be reported.
3. The blib gates the reported set on **experiment-q only** (`MergeNodeTask.ComputePassingPeptides`),
   never re-checking run-q; the writer then gives the best (failing) run an ID line as a
   fallback (`BlibOutputWriter.cs:288-313`), which is what surfaces the violation.
4. **Level mismatch** (can fire even without `--protein-fdr`): compaction gates on run-**peptide**
   q, but "passed run-level" for the ID line uses `EffectiveRunQvalue(Both)` = max(precursor,
   peptide). A peptide can clear peptide-level run-q while no run clears Both.

Why experiment-q can beat every run-q at all: run-level and experiment-level are **independent**
target-decoy competitions; experiment-level dedups to each precursor's **best** observation (a
selection advantage), so it is optimistic by construction. The run gate corrects that bias.

## The fix (Brendan)
Replace the hard-0.01, pool-only, Pass-1-only rule with a **uniform per-precursor effective q**:

> **effective_exp_q = max( experiment_q , min-over-runs run_q )**

A precursor is only as confident as the *weaker* of (its experiment evidence, its best single
run). Gating any output on this at any threshold enforces "reported ⇒ some run genuinely passed"
by construction — killing the artifact and calibrating Pass 1 the same as Pass 2, independent of
whether/when Pass-2 Percolator recomputed q.

## Where to implement — options
- **(A) Just before blib** (`MergeNodeTask`/`BlibOutputWriter`): localized, but the plots,
  compaction, and any other consumer still see the raw q → duplication + drift.
- **(B) Just after the 2nd Percolator run** (`Pass2FdrSidecar`): fixes the reported set but not
  Pass-1 views, and only on the `--protein-fdr` path.
- **(C) Inside `PercolatorFdr` as part of calibration — emit q this way (RECOMMENDED).**
  After it computes per-run and experiment q, set the emitted experiment q to
  `max(experiment_q, min-over-runs run_q)` per base_id before returning. Then **every** consumer
  (Pass-1 plot, Pass-2 plot, blib gate, and even compaction if repointed) is automatically
  consistent — DRY, single source of truth, fixes all paths at once. It has all the per-run q's
  in hand already (it computes them), so the min-over-runs is free.

## Open design questions
- **Levels.** min-over-runs at which scope — run-Both (to match the ID-line semantics) or
  per-level (adjust exp-precursor by min-run-precursor, exp-peptide by min-run-peptide)? Match
  whatever `EffectiveRunQvalue`/the ID line use so the invariant is exact.
- **Compaction.** Keep it as a pool/memory optimization on raw run-q (still valid), or repoint
  it to the effective q? At minimum the *reported* gate must use effective q; compaction can stay
  looser without reintroducing the artifact.
- **Gap-fill / zeroed reconciled rows.** Confirm appended gap-fill and Stage-6-zeroed
  observations get a sane run-q so min-over-runs isn't accidentally 1.0 for a real precursor.
- **Cross-impl parity.** This intentionally changes emitted q vs Rust (Rust doesn't do this). It
  will move the committed golden and break the C#/Rust equality signal — a *wanted* divergence
  (Mike flagged it). Coordinate: re-baseline `regression.ps1` golden, decide whether Rust mirrors
  (see [[project_osprey_parity_removal_sprint]]).

## Validation
- **FDRBench oracle via `--fdrbench-pass both`** (PR #4386 [[TODO-20260707_osprey_fdrbench_pass_both]]):
  after the fix, the **Pass-1 experiment-wide** curve should drop from ~2% to ~0.9%, matching
  Pass 2 — the direct proof the run-gate is now on the emitted q.
- **Invariant test**: assert no reported (blib) peptide has *every* run's `EffectiveRunQvalue(Both)`
  > `config.RunFdr`. This is exactly Mike's finding as a regression guard.
- Standing gates: `regression.ps1` (expect a golden re-baseline), `Build-Osprey.ps1 -RunInspection -RunTests`.

## Related
- [[project_osprey_pass2_gate_divergence]], [[project_osprey_pass2_recalibration_inflates_fdr]]
  (the same Pass-2-recompute-without-re-gate family; TRIC is the sibling fix for *scores*, this
  is the fix for the *gate*).
- [[TODO-osprey_assumption_failure_detection]] (the run-count / reproducibility filter Brendan
  raised is a complementary, separate lever).
