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
concrete collections** (`PerFileScoringTask.cs:128-132`).

**REVISED 2026-05-30 after reading the code (the original "open
question" is now answered).** The headline `GetPerFileEntries` case is
NOT a fixable leak: `_perFileEntries` is a **deliberately load-bearing
shared mutable buffer**. The same `List<KeyValuePair<string,
List<FdrEntry>>>` reference flows Scoring -> FirstJoin -> PerFileRescore
and is mutated in place at each stage to avoid copying very large entry
sets (Astral ~945K entries):
- `FirstJoinTask` (`:217`) compacts it (drops non-passing rows) and
  overlays 2nd-pass sidecar scores onto the compacted inner lists.
- `PerFileRescoreTask` (`:167`) overlays rescored entries
  (`fdrEntries[idx] = ...`), appends gap-fill rows (`fdrEntries.Add`,
  `:908/:969`), and resets `FdrEntry` fields.

Returning `IReadOnlyList` for `GetPerFileEntries` would force a full
copy at each boundary -- a real perf regression, exactly what the
parity/perf gates guard against. So this PR is **deflated** to:

- Tighten ONLY the genuinely read-only accessors (`GetFullLibrary`,
  `GetLibraryById`, `GetPerFileParquetPaths`, `GetPerFileCalibrations`)
  to `IReadOnly*` -- after confirming no consumer mutates them. Low
  value, but cheap and correct.
- For `_perFileEntries`: do NOT freeze it. Instead **make the
  shared-buffer contract explicit and documented** -- rename/annotate
  so it reads as "Scoring owns this buffer; the pipeline mutates it in
  place by design," not as an innocent getter. Clarity, not structure.

This is now a small item; it can ride along with another PR or be
skipped if the documentation is judged sufficient.

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

Continue shrinking the god base class. Split into smaller PRs as the
relocation work has proven less uniform than PR1:

- **Domain-helper relocation -- NOW ACTIVE as
  `TODO-20260530_ospreysharp_relocate_domain_helpers.md`.** Note the
  homes are NOT uniform (verified 2026-05-30): `TheoreticalIsotopeEnvelope`,
  `GetTop6FragmentMzs` (+ its static `_top6MzCache`), `HasTopNFragmentMatch`,
  `TopNFragmentMzs` are Core-typed -> `Core`; but `CountTopNFragmentOverlap`
  calls `ScoringMath.LowerBoundDouble` so it must go to `Scoring`, not
  Core. `HasTopNFragmentMatch` also has an inline binary search
  duplicating `ScoringMath` -- left verbatim, dedup deferred here.
- **`LoadLibrary` -> `OspreySharp.IO` -- its own follow-up PR.** Not a
  verbatim move: it logs via the instance `_ctx`, so it needs
  logging-callback injection (signature change). Its data deps
  (`LibraryCache`, the loaders, `LibraryDeduplicator`) are already in IO.
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
