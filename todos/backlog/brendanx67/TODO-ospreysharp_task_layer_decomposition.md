# TODO: OspreySharp Tasks-layer decomposition + encapsulation cleanup

**Status**: Backlog
**Priority**: Medium (no active defect; maintainability + parity-debugging cost that compounds as the pipeline grows)
**Complexity**: Large (multi-PR program; one task file or one concern per PR, each parity-gated)
**Created**: 2026-05-29
**Scope**: `C:\proj\pwiz\pwiz_tools\OspreySharp` (the `OspreySharp/Tasks/` layer in the exe project)

## Motivation

A 2026-05-29 OOP/architecture review found the OspreySharp *project*
graph genuinely strong (clean, acyclic, well-documented;
`OspreyDiagnostics`, `Program`, `AnalysisPipeline`, `OspreyConfig` all
cohesive) -- but the **task layer** carries the project's
accreting-monolith risk. This is itself the second step of a healthy
trajectory: the task architecture was a deliberate decomposition of a
former ~7,000-line `OspreyPipeline.cs`, and it is a clear improvement.
The next decomposition is *within* the tasks.

The first, lowest-risk slice (relocating stateless math out of
`AbstractScoringTask`) is being done as its own active PR:
`TODO-20260529_ospreysharp_extract_scoring_math.md`. This backlog item
captures the remainder, in recommended execution order.

## What needs to happen

### PR-A -- Make state ownership explicit (encapsulation) (~1 day)

`PerFileScoringTask`'s producer accessors hand out **live, mutable,
concrete collections** that downstream tasks mutate in place:

```csharp
public List<LibraryEntry> GetFullLibrary(PipelineContext ctx) { EnsureHydrated(ctx); return _fullLibrary; }
public Dictionary<uint, LibraryEntry> GetLibraryById(PipelineContext ctx) { ... return _libraryById; }
public List<KeyValuePair<string, List<FdrEntry>>> GetPerFileEntries(PipelineContext ctx) { ... return _perFileEntries; }
```
(`PerFileScoringTask.cs:128-132`)

`PerFileRescoreTask.ExecuteRescore` mutates `_perFileEntries` through
that shared reference, so "who owns this state" has no real answer.
Contrast `FirstJoinTask`, which correctly exposes `IReadOnly*` -- the
inconsistency shows the leak is an oversight.

- Return `IReadOnly*` views from `PerFileScoringTask`'s accessors.
- Convert the in-place rescore mutation into an explicit handoff
  method rather than a silent write through a "getter" return value.
- **Open question to resolve first**: is the in-place mutation a
  deliberate memory optimization for large runs (avoiding a copy of a
  big entry set)? If so, the fix must preserve ownership-transfer
  semantics, not introduce defensive copies. Confirm before coding.

Secondary, same theme (optional, low priority): `OspreyConfig` is
fully mutable (`{ get; set; }`) with a "don't mutate hash-affecting
fields after pipeline entry" invariant enforced only by prose
(`PipelineContext.cs:54-72`) + `ShallowClone` discipline. Consider
freezing the hash-affecting fields after entry so the type enforces
the contract.

### PR-B(n) -- Decompose the mega-methods (multi-PR, ~2-3 days each)

Each of the four task files is dominated by a single enormous method
with 5-7 levels of nesting -- the highest-leverage maintainability and
parity-debugging win, and the riskiest, so do it one method per PR
with a bit-identical parity gate each time:

- `FirstJoinTask.Run` ~650 lines (`FirstJoinTask.cs:184-841`)
- `PerFileScoringTask.Run` ~580 lines (`PerFileScoringTask.cs:182-761`);
  also `RunCalibrationScoringPass` (`:1571-1870`),
  `ScoreCalibrationEntry` (`:2050-2442`)
- `PerFileRescoreTask.ExecuteRescore` ~520 lines
  (`PerFileRescoreTask.cs:502-1022`)
- `MergeNodeTask.WriteBlibOutput` ~530 lines (`MergeNodeTask.cs:554-1084`)

The methods already log `[STAGE-WALL]` / phase boundaries that map
naturally to extractable private methods -- break along those seams.
Pure extraction, no numeric change; parity must stay bit-identical.

### PR-C -- Finish evacuating AbstractScoringTask (~1 day + parity)

After the active math-extraction PR lands, continue shrinking the god
base class (`AbstractScoringTask.cs:56`, 3,016 LOC):

- Move `LoadLibrary` (`:157`) toward `OspreySharp.IO`.
- Move domain-specific helpers to their natural homes: fragment-m/z
  helpers (`GetTop6FragmentMzs`, `TopNFragmentMzs`,
  `CountTopNFragmentOverlap`, `HasTopNFragmentMatch`) and
  `TheoreticalIsotopeEnvelope` -> `Core`/`IsotopeDistribution` or a
  fragment-math helper.
- **Parity-sensitive, gate carefully**: consolidate the duplicate
  correlation implementations -- `PearsonOverRange`
  (`AbstractScoringTask.cs:467`), `PearsonCorrelation` (`:2531`),
  `OspreySharp.Scoring/PearsonCorrelation.cs:38`, and
  `TukeyMedianPolish.cs:537` -- which differ in edge-case handling.
  Cosine similarity appears in ~5 places likewise. Merging changes
  numbers: requires patched-vs-unpatched parity measurement before
  claiming no impact (memory `feedback_parity_vs_impact`,
  `feedback_bit_parity_tolerance`). Do NOT collapse without sign-off.
  - **Add unit coverage FIRST (gap found in PR #4249 self-review).**
    Today `ScoringTest.cs`/`MLTest.cs` exercise only the full-array
    `PearsonCorrelation.Pearson` -- *neither* range variant
    (`ScoringMath.PearsonOverRange` product-guard `< 1e-30` vs
    `ScoringMath.PearsonCorrelationInRange` sqrt-guard `< 1e-10`) has a
    unit test pinning its no-variance / `n < 3` edge behavior. Before
    consolidating, add tests that lock each variant's edge semantics so
    the merge is guarded by a fast unit gate, not only the slow
    end-to-end 1e-9 cross-impl run.
- While here, retire the now-documented dead `CosineSimilarity`
  (`AbstractScoringTask.cs`, no callers tree-wide) flagged in the
  active extraction PR.

### PR-D -- Eliminate the forward-reach (small, ~half day)

`FirstJoinTask` reaches *forward* to the downstream `MergeNodeTask`
for a `ValidityKey` (`FirstJoinTask.cs:422`), inverting the pipeline's
own ordering. Hoist the shared validity-key derivation so neither task
reaches across the ordering boundary.

The `GetTask<T>()` service-locator itself (`PipelineContext.cs:179`)
should be **kept** -- it is a conscious choice whose payoff is the
lazy-rehydrate accessors that let worker-mode and straight-through
runs share one code path. Not a target for removal.

## Out of scope / explicitly decided to keep

- **Project structure**: the acyclic 8-project graph is the strong
  part; leave it. The earlier "concrete tasks live in the exe rather
  than the `OspreySharp.Tasks` library" wrinkle is **resolved as a
  non-issue**: OspreySharp is intended to stay its own EXE, run
  out-of-process from Skyline (2026-05-29 decision). It does not need
  to be embeddable, so the concrete tasks living in the exe is fine.
  - Forward-looking placement note (do NOT act on yet): future code
    sharing between OspreySharp and Skyline is expected to go through
    `pwiz_tools\Shared` (where the `Common*` projects,
    `ProteoWizardWrapper`, and `BiblioSpec` already live), not through
    in-process embedding. The stateless math helpers (active PR) and
    the `Core` value types are the most likely eventual migrants to a
    `Shared` Common* project. Keep that direction in mind when
    choosing homes during PR-C, but do not prematurely relocate into
    `Shared` -- land the helpers in `OspreySharp.Scoring` now; a move
    to `Shared` is its own future PR driven by an actual sharing need.
- `OspreyDiagnostics` (2,013 LOC): large but cohesive; not a target.

## Why this is backlog, not immediate

- No observed defect; this is compounding maintenance cost, not a bug.
- The mega-method decomposition is voluminous and parity-risky -- it
  must be sequenced one method per PR behind the cheap, safe
  extraction PR, not bundled.
- Stepping back to ask the "will this scale another year" question for
  the first time (2026-05-29); right venue is a deliberate cleanup
  program, not the active scoring/parity sprint.

## Related

- Active first PR: `ai/todos/active/TODO-20260529_ospreysharp_extract_scoring_math.md`
- 2026-05-29 OOP review (conversation transcript at time of creation)
- Adjacent cleanup also touching these files:
  `TODO-unstable_sort_cleanup_sweep.md`
- Memory: `feedback_bit_parity_tolerance`, `feedback_parity_vs_impact`,
  `feedback_ospreysharp_precommit`
