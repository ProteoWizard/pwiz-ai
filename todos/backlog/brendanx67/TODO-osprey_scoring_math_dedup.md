# TODO: Osprey — consolidate the duplicate scoring-math implementations

**Status**: Backlog — the last open slice of the (otherwise complete) Tasks-layer decomposition program.
**Priority**: Medium (no defect; parity-sensitive DRY — duplicate correlation/cosine math silently drifts if one copy is edited and the others aren't).
**Complexity**: Small-to-Medium, but **PARITY-SENSITIVE** (it changes the numbers; needs a patched-vs-unpatched measurement).
**Created**: 2026-05-29 · **Slimmed + renamed 2026-07-11** (the task-layer decomposition shipped in #4249–#4262; only this math-dedup bucket remains — the file was `TODO-osprey_task_layer_decomposition.md`).
**Scope**: `pwiz_tools/Osprey` — the duplicate Pearson / cosine / binary-search sites below.

## What's left (the only open work)

Do NOT drive-by merge — each item changes output and must pass the parity gate below.

1. **Add edge-case unit tests FIRST** for the Pearson range variants — the prerequisite gate
   (gap found in the #4249 self-review). Today `ScoringTest` / `MLTest` exercise only the
   full-array `Pearson`; neither range variant's edge behavior is pinned:
   - `ScoringMath.PearsonOverRange` (product-guard `< 1e-30`) vs
     `ScoringMath.PearsonCorrelationInRange` (sqrt-guard `< 1e-10`), plus `n < 3` / no-variance.
2. **Consolidate the duplicate correlation implementations** — `AbstractScoringTask`
   (`PearsonOverRange`, `PearsonCorrelation`), `Scoring/PearsonCorrelation.cs`, and
   `TukeyMedianPolish.cs` — plus the ~5 cosine-similarity sites. They differ in edge-case
   handling, so merging **changes numbers**: requires a patched-vs-unpatched parity measurement
   before claiming no impact ([[feedback_parity_vs_impact]], [[feedback_bit_parity_tolerance]]).
   Do NOT collapse without sign-off.
3. **Dedup the inline binary search** in `FragmentMath.HasTopNFragmentMatch` (duplicates
   `ScoringMath`'s lower-bound search).
4. *(Optional, low)* Freeze `OspreyConfig`'s hash-affecting fields after pipeline entry so the
   "don't mutate after entry" invariant is type-enforced rather than prose + `ShallowClone`
   discipline (the PR-A secondary item).

**Gate** ([[feedback_ospreysharp_csharp_regression_gate]]): the committed C# golden via
`regression.ps1` (Stellar → `-Dataset All` before merge) + the resume-path rehydrate parity gate
if resume is touched. Items 1–3 additionally need the patched-vs-unpatched measurement, since
these deliberately move the numbers.

## Completed — the decomposition program that this file used to track (2026-05-29 → 06-11)

All shipped and merged; kept here only as the context for why the dedup bucket is what's left:
- **PR-C** (#4249 / #4250 / #4251) — extracted stateless scoring math → `Osprey.Scoring.ScoringMath`;
  fragment helpers → `Core.FragmentMath` / `Scoring.FragmentOverlap`; `LoadLibrary` → `Osprey.IO`.
  `AbstractScoringTask` is now fully evacuated (later dead-code removal of `CosineSimilarity` +
  `TheoreticalIsotopeEnvelope`, 2026-06-11, `TODO-20260611_ospreysharp_decouple_abstractscoring`).
- **PR-B** (#4252 / #4254 / #4255 / #4256 / #4257 / #4258) — decomposed the four orchestration
  mega-methods; a 2026-06-01 blind 3-reviewer OOP re-review confirmed none remained flagged.
- **PR-A** (#4259) — read-only accessors tightened; the load-bearing `_perFileEntries`
  shared-buffer contract documented (not frozen — a copy each stage would regress perf).
- **PR-D** (#4261 / #4262) — Stage 6 writes its own `.scores-reconciled.parquet`; the
  `FirstJoinTask → MergeNodeTask` forward-reach deleted.

## Spun off / related
- **Next-iteration architecture (separate initiative):** the implicit, side-effecting inter-task
  dataflow (`GetTask<T>()` + lazy `EnsureHydrated`-triggers-`Run`) → an explicit, driver-owned
  task DAG — [[TODO-ospreysharp_declarative_pipeline_dataflow]]. That is the next structural push;
  this file is only the parity-sensitive math dedup.
- Assembly-count question **DECIDED** (keep all 8 DLLs): [[TODO-osprey_assembly_consolidation]],
  [[TODO-osprey_skyline_shared_scoring]].
- Memory: [[feedback_parity_vs_impact]], [[feedback_bit_parity_tolerance]],
  [[feedback_ospreysharp_csharp_regression_gate]].
