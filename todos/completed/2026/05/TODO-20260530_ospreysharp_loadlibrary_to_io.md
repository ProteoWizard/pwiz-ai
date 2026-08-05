# TODO-20260530_ospreysharp_loadlibrary_to_io.md -- Relocate LoadLibrary into OspreySharp.IO

## Status

**Completed** -- PR [#4251](https://github.com/ProteoWizard/pwiz/pull/4251)
merged 2026-05-30 as `503e83929e`. Third PR of the multi-PR Tasks-layer
cleanup (PR1 #4249 = ScoringMath; PR2 #4250 = fragment helpers; backlog =
`TODO-ospreysharp_task_layer_decomposition.md`). See Merged log below.

## Branch Information

- **pwiz branch**: `Skyline/work/20260530_ospreysharp_loadlibrary_to_io`
  (off `master` @ c19e035b02)
- **PR**: https://github.com/ProteoWizard/pwiz/pull/4251 (merged 503e83929e)
- **ai branch**: `master`

## Background

`LoadLibrary` was the last non-scoring concern left on
`AbstractScoringTask` after PR1/PR2. All of its collaborators
(`LibraryCache`, `DiannTsvLoader`/`BlibLoader`/`ElibLoader`,
`LibraryDeduplicator`) already live in `OspreySharp.IO`, so it belongs
there. Unlike PR1/PR2 this is NOT a byte-verbatim move: `LoadLibrary`
logged through the instance `_ctx`, so logging is injected via
`Action<string>` callbacks to keep the new home free of any task-
framework dependency. The logic and log messages are otherwise unchanged.

## What shipped

- New `OspreySharp.IO/LibraryLoader.cs` -- `public static
  List<LibraryEntry> Load(OspreyConfig config, Action<string> logInfo,
  Action<string> logWarning)`; body relocated from
  `AbstractScoringTask.LoadLibrary`, `_ctx.LogInfo/LogWarning` ->
  `logInfo/logWarning`.
- Deleted `AbstractScoringTask.LoadLibrary` (the only IO consumer in
  that class) and the now-redundant `using pwiz.OspreySharp.IO` there.
- Single call site updated: `PerFileScoringTask.cs:194` ->
  `LibraryLoader.Load(config, ctx.LogInfo, ctx.LogWarning)`.
- Net effect: `AbstractScoringTask` no longer references the IO layer.

## Verification

- Build clean (net472 + net8.0); 345/347 tests; inspection 0/0
  (removing `LoadLibrary` surfaced the redundant IO using, now removed).
- Stellar 1-file cross-impl 1e-9 PASS (precursor delta 0; C# wall 02:05).
- **Astral 3-file C#-only multi-file gate PASS** -- precursor delta 0,
  Stage 7 + blib @ 1e-9 PASS. Run via
  `Compare-EndToEnd-Crossimpl -Dataset Astral -Files All -SkipRust`:
  reused the cached Rust reference (Rust wall 00:00), ran only C#
  straight-through (wall 17:16). This is the phase's regression gate --
  multi-file (reconciliation/consensus/gap-fill), no Rust re-run, ~17 min.
  See memory `feedback_ospreysharp_csharp_regression_gate`.
- **Perf A/B intentionally skipped**: `LoadLibrary` is a one-time
  Stage-1 call (cached via `.libcache`), not a hot loop -- the
  cross-assembly cost of a single call is unmeasurable.

## Follow-on

Next: the mega-method decomposition (backlog PR-B), recommended first
target `MergeNodeTask.WriteBlibOutput`. `AbstractScoringTask` is now a
clean scoring engine (no I/O, no stray math).

### 2026-05-30 - Merged

PR #4251 squash-merged to `master` as `503e83929e` (with `--admin`).
Review chain clean: Copilot's one finding (null-callback hardening on
the new public API) fixed in `44d54a99a4`; fresh-context self-review
APPROVE. Merged over one **unrelated** failing check --
`teamcity - ProteoWizard and Skyline Docker container (Wine x86_64)`
(a Skyline/Wine container build, nothing to do with this OspreySharp-only
relocation; all OspreySharp gates + `Skyline code inspection` passed),
per developer go-ahead. This PR also established the phase's C#-only
regression gate (`Compare-EndToEnd-Crossimpl -Files All -SkipRust`,
memory `feedback_ospreysharp_csharp_regression_gate`). Nothing deferred
from this PR's own scope; the broader LoadLibrary follow-ups (none) and
the mega-method decomposition continue in the backlog.

## Related

- PR1 `TODO-20260529_ospreysharp_extract_scoring_math.md` (#4249);
  PR2 `TODO-20260530_ospreysharp_relocate_domain_helpers.md` (#4250)
- Backlog: `TODO-ospreysharp_task_layer_decomposition.md`
- Memory: `feedback_bit_parity_tolerance`, `feedback_ospreysharp_precommit`,
  `project_ospreysharp_exe_and_shared`
