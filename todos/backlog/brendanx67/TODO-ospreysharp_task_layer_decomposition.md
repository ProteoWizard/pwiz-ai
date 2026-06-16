# TODO: OspreySharp Tasks-layer decomposition + encapsulation cleanup

**Status**: Backlog
**Priority**: Medium (no active defect; maintainability + parity-debugging cost that compounds as the pipeline grows)
**Complexity**: Large (multi-PR program; one task file or one concern per PR, each parity-gated)
**Created**: 2026-05-29
**Scope**: `C:\proj\pwiz\pwiz_tools\OspreySharp` (the `OspreySharp/Tasks/` layer in the exe project)

## Progress (updated 2026-05-31)

Merged so far (master @ `9eee47851f`):

- **#4249** -- extracted stateless scoring math -> `OspreySharp.Scoring.ScoringMath` (PR-C, math portion).
- **#4250** -- relocated fragment helpers -> `Core.FragmentMath` + `Scoring.FragmentOverlap` (PR-C, domain-helper portion).
- **#4251** -- `LoadLibrary` -> `OspreySharp.IO.LibraryLoader` (PR-C, the logging-injection move). **`AbstractScoringTask` now references no I/O and holds no stray math** -- it's a clean scoring engine.
- **#4252** -- **PR-B #1**: decomposed `MergeNodeTask.WriteBlibOutput` (~530 LOC -> 27-line orchestrator + 10 helpers), byte-identical (C#-only multi-file gate).
- **#4253** -- removed the orphaned `OSPREY_DUMP_BLIB_QVALUES` diagnostic (Rust had already dropped its half; audit confirmed it was the only C#-only orphan dump).

Posted + **MERGED 2026-05-31** (autonomous night session; squash-merged to master;
all bit-identical at 1e-9 via the C#-only `-SkipRust` gate; Copilot addressed +
self-review clean for each):

- **#4254** -- `PerFileRescoreTask.ExecuteRescore` (~520 -> ~230 orchestrator + 5 helpers).
- **#4255** -- `FirstJoinTask.Run` (~657 -> ~165 + 4 helpers: LogFirstPassResults, CompactFirstPass, ReloadSecondPassOverlay, PlanStage6).
- **#4256** -- `PerFileScoringTask.Run` (~580 -> ~220 + 3 helpers: LoadLibraryAndDecoys, LoadJoinOnlyScores, HydrateRescoreBundleIfPresent).
- **#4257** -- `PerFileScoringTask.RunCalibrationScoringPass` (~480 -> ~150 + 4 phase helpers).
- **#4258** -- `PerFileScoringTask.ScoreCalibrationEntry` separable phases (~393 -> ~290 + 3 helpers); cohesive scoring core left intact.

**PR-B (mega-method decomposition) is COMPLETE** with the above. The three
originally-named methods (ExecuteRescore, FirstJoinTask.Run, PerFileScoringTask.Run)
plus the two large `PerFileScoringTask` calibration methods are all decomposed.
Left intact by design: `RunCalibration` (~244, cohesive 2-pass orchestrator) and
the `ScoreCalibrationEntry` core pipeline (tightly-coupled per-entry algorithm).

**Merged since (2026-05-31 -> 2026-06-01):**
- **#4259** -- PR-A (deflated): tightened the genuinely read-only `PerFileScoringTask`
  accessors to `IReadOnly*` + documented the load-bearing `_perFileEntries`
  shared-buffer contract (not frozen).
- **#4261** -- Stage 6 writes a separate `.scores-reconciled.parquet` instead of
  overwriting Stage 4's `.scores.parquet` (the root-cause fix that emerged from the
  PR-D investigation). See `todos/completed/TODO-20260531_ospreysharp_stage6_reconciled_parquet.md`.
- **#4262** -- PR-D: removed the `FirstJoinTask -> MergeNodeTask` forward-reach by
  DELETING the vestigial 2nd-pass overlay (MergeNode already owned the rehydrate). See
  `todos/completed/TODO-20260531_ospreysharp_stage5_drop_forwardreach.md`.

**Assembly-count question: DECIDED -- keep all 8 DLLs as-is.** The Scoring/FDR seams are
scaffolding for a possible shared Skyline<->Osprey scoring core; revisit with that
direction. See [[TODO-ospreysharp_assembly_consolidation]] +
[[TODO-ospreysharp_skyline_shared_scoring]].

**Remaining -- the only open items from the review** (all in the parity-sensitive math
dedup bucket; do NOT drive-by merge):
1. **Add edge-case unit tests FIRST** for the Pearson range variants
   (`ScoringMath.PearsonOverRange` product-guard `<1e-30` vs
   `PearsonCorrelationInRange` sqrt-guard `<1e-10`, plus `n<3`/no-variance) -- the
   prerequisite gate (gap found in #4249 self-review).
2. **Consolidate the duplicate correlation impls** -- `AbstractScoringTask`
   (`PearsonOverRange`, `PearsonCorrelation`), `Scoring/PearsonCorrelation.cs`,
   `TukeyMedianPolish.cs` -- plus the ~5 cosine sites. Changes numbers: requires a
   patched-vs-unpatched parity measurement before claiming no impact
   (`feedback_parity_vs_impact`, `feedback_bit_parity_tolerance`).
3. **Dedup the inline binary search** in `FragmentMath.HasTopNFragmentMatch`
   (duplicates `ScoringMath`).
4. ~~**Retire dead `CosineSimilarity`** in `AbstractScoringTask` (no callers tree-wide) --
   the one SAFE, trivial cleanup; can go on its own or with the consolidation.~~
   **DONE 2026-06-11** in Stage 1 of `TODO-20260611_ospreysharp_decouple_abstractscoring`
   (removed both `CosineSimilarity` and `TheoreticalIsotopeEnvelope`; a later dead-code
   pass should not expect them).
5. *(Optional, low)* Freeze `OspreyConfig` hash-affecting fields after pipeline entry
   (PR-A secondary item) -- make the "don't mutate after entry" invariant type-enforced.

**Gate** (`feedback_ospreysharp_csharp_regression_gate`): C#-only straight-through
multi-file `-SkipRust` (~17 min Astral) + the in-memory-vs-HPC rehydrate parity gate for
anything touching the resume path. Items 1-3 additionally need the patched-vs-unpatched
measurement.

### Second OOP review (2026-06-01) — iteration 1 confirmed; next iteration identified

Ran a fresh, blind 3-reviewer OOP review (no knowledge of this program). Tight
consensus: **"Solid-with-issues," maintainability 5-6/10, Modularity unanimously
Strong.** Key result: **none of the three flagged the orchestration mega-methods** that
were the 2026-05-29 review's #1 concern — confirming PR-B landed. Freed from that, all
three independently converged on the **next-dominant issue**: the implicit,
side-effecting inter-task dataflow (`GetTask<T>()` + lazy `EnsureHydrated`-triggers-`Run`)
and prescribed making the task DAG **explicit and driver-owned** (the deferred "option C"
/ Brendan's 2008 instinct). Captured as its own initiative:
[[TODO-ospreysharp_declarative_pipeline_dataflow]] (with scoring-engine extraction,
immutable `OspreyConfig`, and injected diagnostics as partner refactors). The fresh group
was also less forgiving than the first on `OspreyConfig` + `OspreyDiagnostics` (the first
called both "cohesive"). The parity-sensitive correlation/cosine dedup above remains the
only open item *from iteration 1*.

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

### PR-D -- Stage 7 owns its 2nd-pass rehydrate; Stage 5 clean of forward knowledge

**RESOLVED 2026-05-31 -> 2026-06-01 (two PRs, #4261 then #4262).** The investigation
reframed the root coupling: stages overwriting prior stages' artifacts (Stage 6
overwriting Stage 4's `.scores.parquet`), with the overlay/forward-reach machinery
existing to reconstruct what the overwrite destroyed.
- **#4261** stopped the overwrite (Stage 6 writes a separate `.scores-reconciled.parquet`).
- **#4262** then removed the Stage 5->7 forward-reach itself: on inspection
  `FirstJoinTask.ReloadSecondPassOverlay` turned out **vestigial** (MergeNode already
  owns the 2nd-pass rehydrate before protein FDR + blib), so PR-D shipped as a clean
  DELETION rather than the originally-planned relocation. Stage 5 now holds zero forward
  knowledge of Stage 7.
The original PR-D "relocate" analysis is kept below for history (it predates realizing
MergeNode had subsumed the overlay).

**DECISION 2026-05-31 (brendanx): do the proper fix, NOT the band-aid hoist.**
Stage 5 must have zero knowledge of what comes after it.

Today `FirstJoinTask` (Stage 5) reaches *forward* to `MergeNodeTask` (Stage 7):
it borrows MergeNode's `ValidityKey` + `Name` to validate the
`.2nd-pass.fdr_scores.bin` sidecars and overlays them onto the post-compaction
`_perFileEntries`. That logic now lives in `FirstJoinTask.ReloadSecondPassOverlay`
(extracted verbatim in #4255). It is a resume/distributed/test cache -- a **no-op
in a straight-through run** (no 2nd-pass sidecars exist yet when Stage 5 runs).

**Fix:** relocate the 2nd-pass-sidecar rehydrate from FirstJoin into MergeNodeTask,
so Stage 7 owns its own prior-output rehydration. Afterward FirstJoin references
neither `MergeNodeTask` nor any 2nd-pass sidecar.

**Why it's parity-safe:** the cross-impl gate only requires the load *ORDER*
(2nd-pass overlay AFTER first-pass compaction, BEFORE Stage-7 protein-FDR/blib
consumption) -- NOT which task does it. MergeNode runs after compaction and is the
consumer, so it is the correct home and the order is preserved. The forward-reach
was a structural accident of where the port dropped the load-point, not a parity
requirement.

**Investigate FIRST (fresh context):**
- `FirstJoinTask.ReloadSecondPassOverlay` + its caller in `FirstJoinTask.Run`
  (the block to remove from Stage 5).
- `MergeNodeTask` ALREADY touches 2nd-pass sidecars: probe ~`:149`, write
  `Pass.SecondPass` ~`:329-339`, `TryReadOverlay(..., Pass.SecondPass)` ~`:402-412`.
  Understand how FirstJoin's overlay relates to MergeNode's existing handling
  (redundant? complementary? different mode?) BEFORE moving -- the fix may be
  partly *consolidation* with MergeNode's logic, not a raw lift.
- Confirm nothing between Stage 5 and Stage 7 (Stage 6 PerFileRescore) consumes
  the 2nd-pass-overlaid scores in the modes where the overlay fires (resume /
  `--join-at-pass=2` / worker / test-freeze) -- in those, Stage 6 is skipped or
  the parquet is already reconciled.

**Verification:** C#-only `-SkipRust` gate (1e-9) AND an explicit resume-path
check -- run straight-through once to produce 2nd-pass sidecars, then re-run (or
`--join-at-pass=2`) and confirm the overlay still kicks in and output is
bit-identical. The straight-through gate ALONE will NOT exercise the moved code
(overlay is a no-op there) -- this is the one PR where the standard gate is
insufficient on its own.

The `GetTask<T>()` service-locator (`PipelineContext.cs:179`) stays -- its payoff
is the lazy-rehydrate accessors that unify worker-mode and straight-through. Not a
removal target. (The broader driver-owned-skip model -- "option C" -- remains a
separate, larger future initiative.)

**Next-session handoff:** read `ai/.tmp/handoff-20260531_ospreysharp_prd_forwardreach.md`
before starting.

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
