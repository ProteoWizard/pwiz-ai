# TODO-20260530_ospreysharp_decompose_writeblib.md -- Decompose MergeNodeTask.WriteBlibOutput

## Status

**Completed** -- PR [#4252](https://github.com/ProteoWizard/pwiz/pull/4252)
merged 2026-05-31 as `293d3d4724`. First PR of the mega-method
**decomposition** phase (PR-B in
`TODO-ospreysharp_task_layer_decomposition.md`), after the three
relocation PRs (#4249 ScoringMath, #4250 fragment helpers, #4251
LoadLibrary). See Merged log below.

### 2026-05-31 - Merged

PR #4252 merged to `master` as `293d3d4724`; all CI green. Review chain
clean: Copilot's one comment was a false positive (a verbatim-moved
LogInfo line it read as new -- replied + resolved); fresh-context
self-review APPROVE, zero findings (line-by-line diff vs the pre-PR
blob confirmed verbatim lifts, no RunFdr/ExperimentFdr swap, preserved
call order + log order). Shipped exactly as scoped: pure extraction of
`WriteBlibOutput` into a 27-line orchestrator + 10 named helpers.
Self-review's follow-up (the OSPREY_DUMP_BLIB_QVALUES diagnostic is
self-marked temporary) is now actioned as a dedicated follow-up:
Rust has no counterpart (already removed) and the peptide-q drift is
resolved, so a follow-up PR deletes the orphaned C# diagnostic.

## Branch Information

- **pwiz branch**: `Skyline/work/20260530_ospreysharp_decompose_writeblib`
  (off `master` @ 503e83929e)
- **PR**: https://github.com/ProteoWizard/pwiz/pull/4252
- **Commit**: `992bbbc5db` (+249/-247, balanced -- pure extraction)
- **ai branch**: `master`

## Verification (all green)

- Build clean (net472 + net8.0); 345/347 tests; inspection 0/0.
- **C#-only multi-file gate PASS** -- Astral 3-file
  `Compare-EndToEnd-Crossimpl -Files All -SkipRust`: cached Rust reused
  (00:00), C# straight-through (17:46), precursor delta 0, Stage 7
  protein FDR + blib content byte-equal at 1e-9. Confirms the extraction
  is byte-identical on the full reconciliation -> blib path.
- Result: `WriteBlibOutput` ~530 LOC -> ~27-line orchestrator + 10
  named helpers; `WriteBlibFile` ~170 LOC.

## Background

`MergeNodeTask.WriteBlibOutput` is ~530 lines
(`MergeNodeTask.cs:554-1084`) with 5-7 levels of nesting -- the worst of
the mega-methods, and the safest place to establish the decomposition
pattern because `MergeNodeTask` is the pipeline's final sink (no
downstream task reads its internals) and it does not extend
`AbstractScoringTask`.

This is a **pure extraction**: break the method along its existing
phase seams into private helpers, threading the same locals through.
**No logic, arithmetic, ordering, or log-output change.** The two-stage
FDR gate, the dedup/q-value/boundary/cross-file dictionaries, and the
SQLite emission are all kept byte-identical; only their statements move
into named methods.

## Plan -- extract along the seams (each a verbatim lift)

Orchestrator `WriteBlibOutput` keeps ALL the `_ctx` logging at its
original positions (so log order is preserved exactly) and calls, in
order:

1. `ComputePassingPeptides(perFileEntries, config)` -> `HashSet<string>`
   (Stage 1 gate; static).
2. `ComputePassingPrecursors(perFileEntries, config, passingPeptides, out int nFallback)`
   -> `HashSet<(string,byte)>` (Stage 2 + best-charge fallback; static).
   Orchestrator logs the fallback line from `nFallback`.
3. `CollectPassingEntries(perFileEntries, passingPrecursors)` ->
   `List<KeyValuePair<string,FdrEntry>>` (static).
4. `BuildBestByPrecursor(passingEntries)` -> dedup dict (static).
5. `BuildBestExpPrecursorQ(perFileEntries, passingPrecursors)` -> dict (static).
6. `BuildSharedBoundaries(perFileEntries, passingPrecursors)` -> dict (static).
7. `BuildCrossFileObservations(perFileEntries, out int n)` -> dict (static).
8. `MaybeDumpBlibQValues(bestByPrecursor)` -> the `OSPREY_DUMP_BLIB_QVALUES`
   diagnostic dump (instance; env-gated).
9. `WriteBlibFile(config, perFileEntries, libraryById, bestByPrecursor,
   bestExpPrecursorQ, sharedBounds, entriesByPrecursor)` -> the
   `BlibWriter` block (static). Internally extracts
   `WriteRetentionTimes(writer, refId, observations, sourceFileIds,
   sharedBounds, fdrThreshold)` (the self-contained per-observation
   RetentionTimes loop, ~60 lines).

Net: ~530-line method -> ~40-line orchestrator + named phase helpers;
`WriteBlibFile` ~170 lines (cohesive SQLite emission).

## Explicit non-goals

- **No further splitting of the parallel pre-compress + RefSpectra
  write loop** -- they are coupled through the `blibMzBlobs`/`blibIntBlobs`/
  `blibNumPeaks` index arrays; splitting risks a messy parameter web for
  no real gain. Leave inside `WriteBlibFile` this PR.
- **No logic/threshold/ordering change.** All comment blocks (the Rust
  `pipeline.rs:NNNN` parity notes) move verbatim with their code.
- No touching `RunProteinFdr` or `Run` (later decomposition PRs).

## Verification

- `Build-OspreySharp.ps1 -RunInspection -RunTests` -- build clean,
  345/347 tests, inspection 0/0.
- **C#-only multi-file gate (the phase standard, no Rust re-run):**
  `Compare-EndToEnd-Crossimpl -Dataset Astral -Files All -SkipRust`
  -- byte/1e-9 equality on Stage 7 + blib, precursor delta 0. This is
  THE gate for a blib-write decomposition (it exercises the whole
  multi-file reconciliation -> blib path). See memory
  `feedback_ospreysharp_csharp_regression_gate`. Stellar 1-file
  cross-impl as a quick secondary if useful.
- Perf A/B: the parallel pre-compress is unchanged; the C#-gate wall is
  the sanity check (no regression expected from pure extraction).

## Follow-on

Next decomposition targets (separate PRs): `FirstJoinTask.Run` (~650),
`PerFileScoringTask.Run` (~580) + its calibration methods,
`PerFileRescoreTask.ExecuteRescore` (~520).

## Related

- Backlog: `TODO-ospreysharp_task_layer_decomposition.md` (PR-B)
- Prior PRs: #4249, #4250, #4251
- Memory: `feedback_ospreysharp_csharp_regression_gate`,
  `feedback_bit_parity_tolerance`, `feedback_ospreysharp_precommit`
