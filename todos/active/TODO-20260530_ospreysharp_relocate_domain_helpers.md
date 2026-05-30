# TODO-20260530_ospreysharp_relocate_domain_helpers.md -- Relocate stateless domain helpers out of AbstractScoringTask

## Status

Active -- not yet started. Second PR of the multi-PR Tasks-layer
architecture cleanup (PR1 = `TODO-20260529_ospreysharp_extract_scoring_math.md`,
merged/in-review as PR #4249; backlog =
`TODO-ospreysharp_task_layer_decomposition.md`).

## Branch Information

- **pwiz branch**: `Skyline/work/20260530_ospreysharp_relocate_domain_helpers`
  (to be created off `master` after PR #4249 merges)
- **ai branch**: `master`

## Background

Continues evacuating the `AbstractScoringTask` god class
(`OspreySharp/Tasks/AbstractScoringTask.cs`, now 2,929 LOC after PR1)
using the same verbatim-relocation + dual-gate methodology PR1 proved
clean (build + 347 tests + inspection, then Stellar + Astral 1e-9
cross-impl bit-parity + a stage-wall perf A/B). Goal: move the
stateless *domain* helpers (fragment-m/z + isotope math) to their
correct layer so the class keeps shrinking toward a pure scoring
engine, which de-risks the eventual mega-method decomposition.

Decided 2026-05-30: do this safe relocation next rather than the
encapsulation fix (PR-A), which deflated once the code showed
`_perFileEntries` is a deliberately load-bearing shared mutable buffer
(mutated in place by FirstJoin compaction + PerFileRescore overlay to
avoid copying ~945K-entry sets) -- not a leak to freeze. See the
backlog for the rewritten PR-A.

## Objective

Relocate the stateless domain helpers verbatim, each to the correct
layer per its actual dependencies (Core is the leaf -- a helper can
only land there if it has NO Scoring/Chromatography/ML dependency).
Update call sites; arithmetic byte-for-byte unchanged.

### Helpers and their correct homes (verified by dependency)

**-> Core** (Core-typed only: `LibraryEntry`, `LibraryFragment`,
`FragmentToleranceConfig`, `ToleranceUnit`; no Scoring dep):

- `TheoreticalIsotopeEnvelope(double precursorMz, int charge)`
  -- `AbstractScoringTask.cs:2449`, pure math. Natural home: extend the
  existing `OspreySharp.Core/IsotopeDistribution.cs`.
- `GetTop6FragmentMzs(LibraryEntry)` -- `:1819`. **Carries a static
  memoization cache `_top6MzCache`** (ConcurrentDictionary keyed by
  `entry.Id`) that MUST move with it (confirm no other method uses the
  cache). Not pure -- it memoizes -- so the relocated home owns that
  static state; behavior (process-wide memoization) is preserved.
- `HasTopNFragmentMatch(LibraryEntry, double[], FragmentToleranceConfig)`
  -- `:1854`. Calls `GetTop6FragmentMzs`. NOTE: contains its own inline
  lower-bound binary search (`:1875`) duplicating
  `ScoringMath.BinarySearchLowerBound` -- **leave it inline/verbatim**;
  the dedup is parity-adjacent and belongs with the correlation-dedup
  backlog item, not here.
- `TopNFragmentMzs(IList<LibraryFragment>, int)` -- `:2848`, pure.

Suggested home for the fragment group: a new
`OspreySharp.Core/FragmentMath.cs` (or fold into an existing Core type).
Settle placement in review; don't let it block.

**-> Scoring** (has a Scoring dependency, so cannot go to Core):

- `CountTopNFragmentOverlap(IList<LibraryFragment>, IList<LibraryFragment>, int, double, ToleranceUnit)`
  -- `:2826`. Calls `ScoringMath.LowerBoundDouble` (moved to
  `OspreySharp.Scoring` in PR1) and `TopNFragmentMzs`. Home:
  `OspreySharp.Scoring` (next to `ScoringMath`, or a fragment helper
  there). If `TopNFragmentMzs` lands in Core, this still works
  (Scoring -> Core is allowed).

## Explicit non-goals / deferred

- **`LoadLibrary` -> `OspreySharp.IO` is NOT in this PR.** Its data
  dependencies (`LibraryCache`, `DiannTsvLoader`/`BlibLoader`/`ElibLoader`,
  `LibraryDeduplicator`) are all already in IO, but it logs via the
  instance `_ctx` field (`:170/:178/:184/:213/:219/:225`), so moving it
  to a static IO method needs **logging-callback injection** -- a
  signature change, not a verbatim move. That is a different kind of
  change; give it its own PR so this one stays a pure, parity-trivial
  relocation. (Recommend: separate `LoadLibrary` PR after this.)
- **Do NOT dedup** the inline binary search in `HasTopNFragmentMatch`
  against `ScoringMath`, nor merge any correlation/cosine variants --
  parity-sensitive, tracked in the decomposition backlog (PR-C dedup).
- No method decomposition, no encapsulation changes.

## Verification (same gate as PR1)

- `Build-OspreySharp.ps1 -RunInspection -RunTests` -- build clean,
  345/347 pass, inspection 0/0.
- Stellar 1-file AND Astral 3-file `Compare-EndToEnd-Crossimpl.ps1`
  cross-impl bit-parity @ 1e-9 -- PASS, precursor delta 0 (verbatim
  moves must be bit-identical; the `_top6MzCache` relocation must
  preserve memoization semantics exactly).
- Stage-wall perf A/B (Stellar, C#-only, 3 repeats, master vs branch)
  -- no regression. Watch stage1to4 (where these fragment helpers run).
  Cross-assembly note: `GetTop6FragmentMzs`/`HasTopNFragmentMatch` are
  per-candidate hot-path; moving them exe -> Core crosses an assembly
  boundary (same class of question PR1 answered as "no measurable
  cost", but re-measure since these run in a different inner loop).

## Follow-on

After this: a `LoadLibrary -> IO` PR (logging-injection), then the
mega-method decomposition (backlog PR-B) on a now-cleaner class.

## Related

- PR1: `TODO-20260529_ospreysharp_extract_scoring_math.md` (PR #4249)
- Backlog: `TODO-ospreysharp_task_layer_decomposition.md`,
  `TODO-ospreysharp_assembly_consolidation.md`
- Memory: `feedback_bit_parity_tolerance`, `feedback_parity_vs_impact`,
  `feedback_ospreysharp_precommit`, `project_ospreysharp_exe_and_shared`
