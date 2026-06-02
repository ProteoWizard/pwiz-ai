# TODO-20260529_ospreysharp_extract_scoring_math.md -- Extract stateless numeric helpers out of AbstractScoringTask

## Status

**Completed** -- PR [#4249](https://github.com/ProteoWizard/pwiz/pull/4249)
merged 2026-05-30 as `9a68ac5`. First PR of a multi-PR Tasks-layer
architecture cleanup (see backlog
`TODO-ospreysharp_task_layer_decomposition.md` for the deferred
remainder; next active PR is
`TODO-20260530_ospreysharp_relocate_domain_helpers.md`). See Progress
Log for results.

## Branch Information

- **pwiz branch**: `Skyline/work/20260529_ospreysharp_scoring_math_extract`
  (created off `master`)
- **PR**: https://github.com/ProteoWizard/pwiz/pull/4249
- **Commits**: `c63e4bcf7a` (MLTest.cs pre-existing inspection cleanup),
  `e9a4c19932` (scoring-math relocation)
- **ai branch**: `master`

## Background

An OOP/architecture review of `pwiz_tools/OspreySharp` (2026-05-29)
found the task layer to be the highest accreting-monolith risk in an
otherwise cleanly-layered project. The single worst separation-of-
concerns violation is `AbstractScoringTask`
(`OspreySharp/Tasks/AbstractScoringTask.cs`, 3,016 LOC): an abstract
base class -- inherited by `PerFileScoringTask`, `PerFileRescoreTask`,
and `FirstJoinTask` -- that mixes file I/O, decoy generation, XIC
extraction, feature computation, AND a cluster of **stateless numeric
primitives** that share no state with the pipeline and have no reason
to live on a "task" base class.

This is the chosen *first* PR because it is the lowest-risk, most
self-contained win: a pure code relocation with **zero behavior
change**, immediately verifiable by bit-identical cross-impl parity
plus the existing 347-test suite. It also de-risks the larger
mega-method decomposition (deferred to backlog) by removing ~200 lines
of unrelated math noise from the god class first.

## Objective

Relocate the unambiguously stateless numeric/search helpers out of
`AbstractScoringTask` into `OspreySharp.Scoring`, preserving each
implementation **verbatim** (byte-for-byte same arithmetic, same
edge-case handling), and update all call sites. The exe project
already references `OspreySharp.Scoring`, and the helpers are pure
(`double[]` in, `double`/`int` out), so no new project dependencies
are introduced.

### Helpers to move (in scope)

Confirmed stateless and parity-safe to relocate as-is:

- `PearsonOverRange(double[] x, double[] y, int start, int end)`
  -- `AbstractScoringTask.cs:467` (already `static`)
- `PearsonCorrelation(double[] x, double[] y, int start, int end)`
  -- `AbstractScoringTask.cs:2531` (instance, but uses no instance
  state -- make `static` on relocation)
- ~~`CosineSimilarity(double[] a, double[] b)` -- `AbstractScoringTask.cs:2505`~~
  **EXCLUDED during implementation**: found to be dead code (zero call
  sites anywhere in the tree). Relocating a dead private method into a
  new *public* class (cross-assembly calls force `public`) would just
  expand surface for something unused. Left untouched in
  `AbstractScoringTask`; flagged for the PR-C dead-code pass in the
  decomposition backlog.
- `BinarySearchLowerBound(double[] sortedArray, double value)`
  -- `AbstractScoringTask.cs:3001` (already `static`)
- `LowerBoundDouble(double[] arr, double v)`
  -- `AbstractScoringTask.cs:2925` (already `static`)

### Proposed home

A single new static class in `OspreySharp.Scoring`, e.g.
`ScoringMath.cs`. Standard license/AI-attribution header per
`STYLEGUIDE.md` (match the header already on the sibling
`OspreySharp.Scoring/PearsonCorrelation.cs`).

Open placement question to settle in review: a lone `ScoringMath`
grab-bag risks becoming a new dumping ground -- the exact smell this
cleanup targets. The alternative is to distribute by concept
(correlation methods alongside the existing `PearsonCorrelation`
class; binary-search helpers into a small `ArraySearch`). Pick one
during implementation; do not let it block the PR.

Forward-looking, do NOT act on it here: OspreySharp stays its own EXE
(out-of-process from Skyline), and future Skyline<->OspreySharp code
sharing is expected to go through `pwiz_tools\Shared` (the `Common*`
projects / `ProteoWizardWrapper` / `BiblioSpec` neighborhood). These
stateless helpers are plausible eventual migrants to a `Shared`
Common* project, but that is a separate future PR driven by a real
sharing need -- land them in `OspreySharp.Scoring` now.

## Explicit non-goals (keep this PR tight and parity-safe)

These are deliberately deferred to the backlog TODO:

- **Do NOT merge the duplicate Pearson implementations.**
  `PearsonOverRange` (`:467`) and `PearsonCorrelation` (`:2531`) are
  two distinct range-correlation routines with *different* edge-case
  handling (e.g. `n < 3` -> `NaN` vs different denom thresholds), and
  the project also has `OspreySharp.Scoring/PearsonCorrelation.cs:38`
  and `TukeyMedianPolish.cs:537`. Consolidating them changes numbers
  and is a cross-impl-parity hazard -- it needs a deliberate
  patched-vs-unpatched parity measurement (see memory
  `feedback_parity_vs_impact`, `feedback_bit_parity_tolerance`), not a
  drive-by merge. Relocate each verbatim; flag the dedup for backlog.
- **Do NOT move domain-specific helpers in this PR.** Fragment-m/z
  helpers (`GetTop6FragmentMzs`, `TopNFragmentMzs`,
  `CountTopNFragmentOverlap`, `HasTopNFragmentMatch`),
  `TheoreticalIsotopeEnvelope`, and `ComputeCosineAtScan` are more
  entangled with domain types and have natural homes in `Core`
  (`IsotopeDistribution`) or a fragment-math helper. Evaluate
  separately so PR1 stays a clean, obvious relocation.
- No method decomposition, no encapsulation changes, no signature
  changes to public/protected task members.

## Verification

NOTE: the parity harness moved since the guide was written --
`Test-Features.ps1` (1e-6 PIN features) is archived; the current
cross-impl gate is `Compare/Compare-EndToEnd-Crossimpl.ps1`, which runs
both impls straight-through and compares Stage 7 protein FDR + blib SQL
at per-column **1e-9**.

- `Build-OspreySharp.ps1 -RunInspection -RunTests` -- build clean
  (net472 + net8.0); inspection 0/0 after the MLTest.cs cleanup (see
  below); **345/347 tests pass, 2 skip** (exact baseline).
- **Bit-parity (Stellar 1-file, 1e-9): PASS** -- precursors
  rust=cs=46115 (delta 0); Stage 7 protein FDR PASS; blib content PASS.
  Since master already matched Rust at this gate, a verbatim relocation
  still matching Rust at 1e-9 confirms zero numeric drift.
- **Bit-parity (Astral 3-file, 1e-9): PASS** -- precursors
  rust=cs=167285 (delta 0); Stage 7 protein FDR PASS; blib content
  PASS. C# wall 17:08 vs Rust 25:44.
- **Performance (Stellar, C#-only, 3-repeat A/B, master vs branch):**
  no detectable regression. stage1to4 (the stage exercising the moved
  helpers) median 90.4s master vs 88.7s branch -- branch marginally
  faster, delta inside ~15-20% run-to-run noise; all other stages
  identical. Evidence the JIT inlines the helpers across the
  `exe -> Scoring.dll` boundary fine (feeds
  `TODO-ospreysharp_assembly_consolidation`).
- Commit message: standard Skyline format; emphasize "no behavior
  change, pure relocation" so the reviewer knows numeric identity is
  the contract; flag the MLTest.cs cleanup as a separate pre-existing fix.

## Implementation notes

- New file `OspreySharp.Scoring/ScoringMath.cs` (`public static class
  ScoringMath`) holds the 4 relocated helpers, bodies verbatim. The
  former instance `PearsonCorrelation` was renamed to
  `PearsonCorrelationInRange` on relocation (made `static`) to avoid a
  confusing name echo with the sibling `PearsonCorrelation` *type*;
  arithmetic unchanged. Call sites: 4x `PearsonCorrelationInRange`,
  7x `BinarySearchLowerBound`, 1x `LowerBoundDouble` in
  `AbstractScoringTask`; 1x `PearsonOverRange` + 1x
  `BinarySearchLowerBound` in `PerFileScoringTask`. Both files already
  `using pwiz.OspreySharp.Scoring`.
- `AbstractScoringTask.cs` shrank 3,016 -> 2,929 LOC.
- Bundled a pre-existing inspection cleanup (unrelated to this PR, from
  merge #4246) in `OspreySharp.Test/MLTest.cs`: disambiguated an
  ambiguous `Train` doc cref and removed one redundant `(double)` cast
  (double-division behavior preserved). Cleared the 6 warnings the
  inspection gate was already reporting on master.

## Follow-on

Once merged, pull the next slice from
`ai/todos/backlog/brendanx67/TODO-ospreysharp_task_layer_decomposition.md`
into active (recommended next: the encapsulation fix -- return
read-only views from `PerFileScoringTask` accessors -- as a
self-contained PR, before the larger per-task mega-method
decomposition).

## Review chain (PR #4249)

- **Copilot:** 1 inline finding -- `PearsonOverRange` XML doc claimed
  NaN-on-no-variance but code returns 0.0. Fixed (comment-only) in
  `6a6e64f3ad`; thread replied + resolved.
- **Fresh-context self-review agent:** clean pass -- no blockers, no
  should-fix. Independently re-verified the high-risk call-site routing
  between the two range-Pearson variants (faithful), verbatim
  arithmetic, dead `CosineSimilarity`, statelessness, the MLTest cast,
  and cross-checked both Pearson guards against Rust upstream
  (`osprey-scoring/src/lib.rs:1285/1305` and `:1877-1882`). One
  [CONSIDER]: document the orphaned dead `CosineSimilarity` -> done in
  `75d0d7e58f`. One follow-up Q on a future-PR-C test gap -> captured in
  the decomposition backlog (add range-variant unit coverage before the
  consolidation merge).
- Commits: `c63e4bcf7a`, `e9a4c19932`, `6a6e64f3ad`, `75d0d7e58f`.

### 2026-05-30 - Merged

PR #4249 squash-merged to `master` as commit `9a68ac5`. All 22 CI
checks green (CodeQL, g++, Skyline code inspection, TeamCity Core +
Bumbershoot + BiblioSpec + Docker/Wine, Skyline suite 1628 tests + 18
TestConnected). Shipped exactly as scoped: verbatim relocation of the
four stateless helpers into `ScoringMath`, the Copilot doc fix, the
self-review dead-code annotation, and the bundled MLTest.cs inspection
cleanup. Nothing deferred from this PR's own scope. Follow-on relocation
work proceeds in `TODO-20260530_ospreysharp_relocate_domain_helpers.md`.

## Related

- PR: https://github.com/ProteoWizard/pwiz/pull/4249
- 2026-05-29 OOP review (conversation transcript at time of creation)
- Backlog: `TODO-ospreysharp_task_layer_decomposition.md`,
  `TODO-ospreysharp_assembly_consolidation.md`
- Memory: `feedback_bit_parity_tolerance`, `feedback_parity_vs_impact`,
  `feedback_ospreysharp_precommit`
