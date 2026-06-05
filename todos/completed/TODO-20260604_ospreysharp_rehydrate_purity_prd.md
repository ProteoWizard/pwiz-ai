# TODO: PR-D — make Rehydrate pure (eliminate the Run-inside-Rehydrate deferrals)

**Status**: **Completed** — PR [#4269](https://github.com/ProteoWizard/pwiz/pull/4269) merged
2026-06-05 as `acd0cd54`. Successor to PR-C (#4267, the byproduct cache).

## Progress (2026-06-05 night session)
- All THREE deferrals eliminated (Sites 1/2/3): PerFileScoring `RehydrateFromOwnOutputs`
  (loads own .scores.parquet via TryLoadStubsAndCalibration); FirstJoin `LoadOwnReconciliationBundle`
  (rebuilds the post-Stage-5 bundle from own .1st-pass.fdr_scores.bin + .reconciliation.json, nulls
  features, flows through the existing bundle-adopt path; `ConsensusTargetsFromBundleOrEmpty` ->
  `ConsensusTargetsFromBundle(ctx, bundle)`); PerFileRescore reads CompactedEntries + publishes
  RescoredEntries inline.
- **publish-or-throw**: KEPT the `&& ExitCode != 0` discriminator (the TODO's design question).
  Reason: Site 1's RehydrateFromOwnOutputs still routes through FinalizeAndCheck, which has the
  legitimate `--no-join`/empty-scores success-stops (false + ExitCode 0). The worker --input-scores
  Rehydrate path does too. So dropping the discriminator would wrongly throw on benign stops.
- **Test fold-ins**: added 4 ByproductContextTest methods (dup-producer ctor throw, MarkMaterialized
  suppression, one-shot Demand guard, forgetful-producer -> UnknownByproduct). SKIPPED milestone
  ref-equality (the wrapper types are internal to OspreySharp; the no-copy contract lives in the
  task code, and the proposed test would only re-assert Publish/Get round-trip).
- **Gates ALL GREEN**: Build -RunTests -RunInspection (361 tests, ReSharper clean). Worker-mode
  strict **Stellar OVERALL PASS** AND **Astral OVERALL PASS** (in-memory vs HPC chain bit-parity at
  every stage boundary, net8.0). New resume gate `Compare/Compare-StraightThroughResume-CSharp.ps1`
  added (FAILs on the pre-existing resume-RT bug, by design — see below).
- **Self-review** (fresh-context, ran locally — no PR yet): NO HIGH/MEDIUM findings; independently
  confirmed bundle==null reachability, shared-buffer aliasing, ConsensusTargetsFromBundle neutrality,
  PerFileRescore-inline == old-Run-self-gate. Its one actionable follow-up (unit gate for
  "Rehydrate never calls Run") added as commit e32ab45c1c (TestDemandDrivesRehydrateNeverRun).
- **Commits**: afb0e2c280 (the 3 pure-load paths + 4 fold-in tests), e32ab45c1c (self-review test).
- **PR #4269 MERGED 2026-06-05 as `acd0cd54`.** Copilot (1 comment: strict-load messaging, fixed
  in 84be512c1e), fresh-context self-review (no HIGH/MED), and /ultrareview (no findings) all clean;
  22/22 CI checks green. Merged behavior-preserving (option A) per the reviewer note.

### 2026-06-05 — Merged

PR #4269 merged as `acd0cd54`. Shipped the three pure-load resume Rehydrate paths (PerFileScoring /
FirstJoin / PerFileRescore) — eliminating the last Run-inside-Rehydrate deferrals so Run is
outer-loop-only — plus the ByproductContext cache-invariant tests (incl. a Rehydrate-never-Run unit
gate) and the straight-through-resume parity gate. Gated by build/361 tests/inspection + worker-mode
strict bit-parity on Stellar AND Astral. **Deferred (by design):** the pre-existing straight-through
resume 1st-pass-RT bug is NOT fixed here — PR-D is behavior-preserving and the new resume gate
deliberately FAILs on it. Follow-up is **PR-E** (load own .scores-reconciled.parquet in PerFileRescore's
resume Rehydrate); recipe + parity traps recorded in
[[TODO-ospreysharp_straightthrough_resume_1stpass_rt]] and ai/.tmp/prd-implementation-map.md.
- **DELIBERATE SCOPE CALL — Site 3 behavior-preserving; the resume-RT bug is NOT fixed here.**
  The resume smoke surfaced (byte-exact) the pre-existing straight-through-resume RT bug
  ([[TODO-ospreysharp_straightthrough_resume_1stpass_rt]]). Fixing it = load own
  .scores-reconciled.parquet in Site 3, which has HIGH parity risk (a fresh OverlayRescoredEntries
  PRESERVES the original ParquetIndex at PerFileRescoreTask.cs:1013; gap-fill rows carry
  ParquetIndex=uint.MaxValue). That belongs in its own PR-E, not bolted onto this structural refactor.
  Recipe saved in `ai/.tmp/prd-implementation-map.md` + the Site-3 sub-agent map.

---
*Original plan below.*

**Status (original)**: Active — not started. Successor to PR-C (#4267, the byproduct cache). Start in a
FRESH session.
**Priority**: Medium-strategic — closes the ONE remaining violation of the declarative-dataflow
initiative's decisive design constraint. No defect (the resume path loads correctly today), but
the abstraction is leaky and the headline goal isn't fully met until this lands.
**Branch (to create)**: `Skyline/work/<YYYYMMDD>_ospreysharp_rehydrate_purity` in `C:\proj\pwiz`.
**Origin**: surfaced by PR-C's `/pw-self-review` (2026-06-04) and Brendan's catch that the
side-effect model the refactor set out to kill is still partly alive.

## The constraint being violated

The umbrella spec (`ai/todos/completed/TODO-20260601_ospreysharp_declarative_pipeline_dataflow.md`,
lines 173-176, 199, 226-227) states it as **"the decisive design constraint"**:

> `Run` is called from the outer loop AND NOWHERE ELSE. Compute is never a hidden side-effect of
> requesting state. The only lazy action is `Rehydrate` (load), never `Run` (compute).

The current code violates it with **three `Rehydrate -> return Run(ctx)` deferrals**:

| site | guard (when it defers) | what a pure rehydrate should load instead |
|------|------------------------|-------------------------------------------|
| `PerFileScoringTask.cs:359` | `InputScores` empty (straight-through resume) | its own `.scores.parquet` + `.calibration.json` |
| `FirstJoinTask.cs:326`      | `bundle == null` (straight-through resume)   | its own `.1st-pass.fdr_scores.bin` + `.reconciliation.json` |
| `PerFileRescoreTask.cs:343` | `!ExpectReconciledInput` (straight-through resume) | its own `.scores-reconciled.parquet` |

## Why it exists / why it survived

PR-B introduced the Run/Rehydrate split but took a pragmatic shortcut for the
straight-through-RESUME case: when the driver skips a task because its outputs are already valid
on disk (`CanRehydrate`) and a downstream task then `Demand`s it, the task has no *pure*
load-my-own-outputs path, so `Rehydrate` falls back to `Run` (whose per-file `ScoreOrLoadForFile`
loads the valid parquets rather than recomputing). PR-C's scope was the byproduct cache and did
not touch these; the PR-C deferred-items list omitted them. So the constraint was never reached
across PR-A -> PR-B -> PR-C.

In practice the parquets are valid so `Run` *loads* rather than computes -- but `Run` *contains*
the compute path; it only happens to load. The leak: a reader can no longer trust that
`Demand`/`Get` never computes, and the "Run is outer-loop-only" invariant the whole driver model
rests on is broken.

## The fix

Give each task a true **rehydrate-from-its-own-verified-valid-outputs** path, decoupled from `Run`:

- **PerFileScoring**: generalize the existing `LoadJoinOnlyScores` (today gated on `--input-scores`)
  so the no-InputScores resume case loads the task's OWN `.scores.parquet` stems. The load logic
  already exists; it just needs to point at own-outputs instead of supplied `--input-scores`.
- **FirstJoin**: load its `.1st-pass.fdr_scores.bin` + `.reconciliation.json` into the same
  post-Stage-5 state the bundle-adopt path produces (the bundle path is already a real rehydrate;
  the `bundle == null` resume case needs the from-own-sidecars equivalent).
- **PerFileRescore**: load its `.scores-reconciled.parquet` (the merge-mode Rehydrate already does
  a disk-load; generalize for the resume case).

Each must produce **byte-identical in-memory state** to what `Run` would have loaded.

## Gates (this is the resume path -- gate it like B0-B6)

- `Build-OspreySharp.ps1 -RunTests -RunInspection`.
- Worker-mode strict bit-parity on **Stellar AND Astral** (the existing
  `Compare-Stage7-Rehydration-Strict-CSharp.ps1`), Stage-5 truth hash `0C353A72CBCC` must hold.
- **A straight-through-RESUME smoke** -- the known gate-coverage gap. The deferrals exist ONLY for
  resume, so a resume run (produce outputs, delete an in-memory consumer's trigger, re-run, demand
  the skipped task) must be byte-identical with the deferral removed. See the related resume-RT bug.

## Fold in (from PR-C's /pw-self-review, 2026-06-04 -- PR-D touches this exact surface)

- **Test gaps** in `ByproductContextTest.cs` (the risky, currently-untested invariants):
  - single-producer ctor throw (`_producerByByproduct` duplicate -> `ArgumentException`).
  - `MarkMaterialized` suppressing a second `Rehydrate` (the driver-Run vs lazy-Rehydrate guard).
  - **milestone reference-equality** (no-copy contract): `ScoredEntries`/`CompactedEntries`/
    `RescoredEntries` are the SAME backing list -- a test that asserts reference-equality after a
    simulated compaction locks in the no-copy contract a future `.ToList()` could silently break.
  - `UnknownByproductException` when a producer runs but forgets to publish.
- **LOW**: `PerFileRescoreTask.cs:200,355` -- `RescoredEntries` is published *before* the
  overlay/compaction mutates the buffer; safe (same list, read only at MergeNode) but strengthen
  the one-line comment that the publish is intentionally pre-mutation.
- **LOW**: `PipelineContext.cs:215` -- `_materialized.Add` precedes `Rehydrate`, so a producer that
  self-`Get`s its own byproduct mid-rehydrate throws a confusing `UnknownByproductException`
  instead of recursing. Latent (no producer does this); add a cheap clear assert.
- **Design question to settle**: should a `false` return from a lazily-demanded `Rehydrate` be
  ALWAYS fatal ("publish-or-throw") rather than only when `ExitCode != 0`? Once the deferrals are
  gone, `Rehydrate` no longer routes through `Run`'s legitimate success-but-stop returns, so the
  publish-or-throw contract becomes clean and the `ExitCode != 0` discriminator could be dropped.
  This is the natural place to make that call.

## Related
- `ai/todos/active/TODO-20260604_ospreysharp_byproduct_context_prc.md` (PR-C — predecessor)
- `ai/todos/completed/TODO-20260601_ospreysharp_declarative_pipeline_dataflow.md` (umbrella; the
  decisive constraint at lines 173-176)
- `ai/todos/backlog/TODO-ospreysharp_straightthrough_resume_1stpass_rt.md` (resume-RT bug; same
  straight-through-resume path PR-D must gate)
