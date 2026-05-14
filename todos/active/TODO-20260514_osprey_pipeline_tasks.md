# TODO-20260514_osprey_pipeline_tasks.md — Phase C: worker convergence + post-Phase-B cleanups

> Continuation of **[TODO-20260511_osprey_pipeline_tasks.md](../completed/TODO-20260511_osprey_pipeline_tasks.md)**
> (Phase B core: resume-on-restart capability, merged 2026-05-14 via
> ProteoWizard/pwiz #4199). Phase B history and design decisions live
> there; this file describes the remaining Phase C work and the small
> review-follow-up items deferred from #4199.
>
> **DRAFT.** The Phase C design needs a discussion before coding starts.
> The "Design questions to resolve before commit 1" section below lists
> what we should agree on first.

## Branch Information

- **Branch**: (not yet created) — will be `Skyline/work/20260514_osprey_pipeline_tasks` when work starts
- **Base**: `master` (post-#4199 squash)
- **Status**: design draft; awaits user review
- **PR**: (pending)

## Predecessor: Phase B core — merged

ProteoWizard/pwiz #4199 (merged 2026-05-14, squash). Headline mechanisms:

- Per-(output, task) `.osprey.task` JSON sidecars; `RunTask` skips any
  task whose outputs all exist with a matching `validity_key`
  (`SearchParameterHash` + `LibraryIdentityHash` + `ReconciliationParameterHash`
  where the rescore-affected tasks override).
- `StartAtTask` / `StopAfterTask` on `PipelineContext` route CLI flags
  to a subrange of the invariant 4-task pipeline (replaces the
  discarded `IsWorkerMode` flag-gate).
- Lazy-rehydrate accessors on every producer task; downstream consumers
  pulling state from a driver-skipped task get it from disk via the
  existing in-`Run` hydration paths.
- Per-file skip inside `PerFileScoringTask.Run` via `ScoreOrLoadForFile`
  closes the partial-completion gap (1000-mzML crash on file 487
  resumes by re-scoring only 487+).

Everything that landed already passed Stellar + Astral snapshot
regression at every stage and Stellar cross-impl Test-Regression at
every stage.

## Phase C scope

### 1. Worker convergence (the main job)

The stage6 worker path (`--join-at-pass=1 --no-join --input-scores`)
today still routes through `RescoreWorker.Run` → `PerFileRescoreTask.RunWorker`
rather than `AnalysisPipeline.Run`. After Phase C lands:

- `RescoreWorker.Run` becomes one line: `return new AnalysisPipeline().Run(config);`
- `PerFileRescoreTask.RunWorker` body deleted.
- `AnalysisPipeline.CanonicalPipeline()` static factory is the single
  source of truth for the 4-task list. `AnalysisPipeline.Run` is the
  only caller.
- CLI-mode branches inside task `Run`s (the `joinOnly` /
  `ExpectReconciledInput` / `NoJoin` checks) deleted where the
  StartAt mechanism + lazy-rehydrate subsumes them.

### 2. The hydration-unification problem

Converging the entry path requires unifying the disk-load semantics
that today live in two separate code paths. The key seam is
`PerFileScoringTask`'s `joinOnly` path (raw stubs + PIN features, no
overlay) vs `RescoreHydration.HydrateForRescore` (stubs with 1st-pass
SVM overlay + reconciliation.json parsing). Three modes feed the seam,
each with different on-disk inputs:

| Mode | On disk | Stubs need |
|------|---------|------------|
| stage5 (`--join-only --input-scores`) | `.scores.parquet` only | raw stubs + PIN features (run Percolator) |
| stage6 (`--no-join --input-scores`) | `.scores.parquet` + `.1st-pass.fdr_scores.bin` + `reconciliation.json` | stubs with 1st-pass overlay + reconciliation state |
| stage7 (`--join-at-pass=2 --input-scores`) | `.scores.parquet` + 1st + 2nd-pass + reconciliation.json | stubs with 2nd-pass overlay (FirstJoin does this today) |

The right design call is to have `PerFileScoring.joinOnly` dispatch on
"what sidecars are present" and produce the matching hydrated bundle;
`FirstJoinTask`'s lazy-rehydrate accessors then pull the reconciliation
half of the bundle from a shared seam on `PerFileScoringTask` (the
predecessor TODO's recommended option (a): `PerFileScoringTask` owns the
`RescoreInputs` bundle, exposes `GetRescoreInputs(ctx)`; `FirstJoinTask`'s
accessors read from it). The "straightforward to write but the
regression surface is non-trivial — all three modes' snapshot equality
has to hold byte-for-byte" caveat from the predecessor still stands.

### 3. Review-follow-up items from PR #4199

Small items called out in the Claude `/review` of #4199 but deferred
so the core PR could ship. None are blockers; bundle them with Phase C
or peel off into separate small commits as fits.

- **(P1)** Doc note in `PerFileScoringTask.ValidityKey` / `Outputs`
  explaining that the PerFileScoring sidecar's validity persists
  across PerFileRescore's in-place parquet overwrite, and why that's
  safe (re-running Percolator / FirstJoin on post-rescore stubs is
  deterministic; the snapshot regressions confirm this).
- **(P2)** `version` skew check in `TaskValiditySidecar.IsValid`. The
  sidecar writer stamps a `version` field already; the reader doesn't
  compare it. A version-major-skew check (mirroring the parquet
  metadata version rules) would catch the edge case of a sidecar from
  an older OspreySharp version falsely matching when `SearchParameterHash`
  happens to be invariant across the version change.
- **(P2)** Unit tests for `TaskValiditySidecar.Write` / `IsValid` /
  `Delete`. Copilot called this out (thread #3221935440, left
  unresolved as a tracker). Cover: round-trip, JSON-escape paths,
  malformed content rejection, missing-sidecar behavior.
- **(P3)** Replace the body-prologue `_runOrHydrated = true` in each
  producer task's `Run` with a try/finally (or move the set to the
  end of `Run`) so an exception during the body doesn't leave the
  task in a "hydrated" state that masks empty results from
  subsequent accessor calls.
- **(P3)** Comment the dead `--no-join + --input-scores` branch in
  `AnalysisPipeline.DeriveStartAtTask` as Phase-C-staging (today it
  returns `PerFileRescoreTask` but the CLI path doesn't route through
  `AnalysisPipeline.Run` yet; the branch is correct when convergence
  lands).
- **(P3)** Backport the `$aiRoot`-based fix-crlf invocation to
  `Build-Skyline.ps1`. The Build-Skyline version uses
  `git rev-parse --show-toplevel + ai\` join, which silently no-ops
  in the sibling-repo layout. Build-OspreySharp now uses `$aiRoot`
  directly. Tiny, independent.

### 4. Style / DRY cleanup pass (post-Phase-C)

The user explicitly flagged that Phase B PR added code that violates
`ai/STYLEGUIDE.md` (single-line `if` statements) and has DRY
opportunities. Holding the cleanup until after the rearchitecture is
complete is intentional ("rearchitecture followed by stylistic
refactor / clean-up"). When Phase C is in, do a focused pass:

- `ScoreOrLoadForFile`'s 3 near-duplicate scoring branches (single-file,
  sequential, parallel) can probably collapse into one.
- The `EnsureHydrated` pattern is repeated verbatim across
  PerFileScoringTask, FirstJoinTask, PerFileRescoreTask. Promote it to
  a shared helper on `OspreyTask` (or a small mixin).
- The `foreach (var output in Outputs(ctx)) TaskValiditySidecar.Delete(...)`
  boilerplate at the start of FirstJoin / MergeNode / PerFileRescore
  Runs is identical; same factoring opportunity.
- Single-line `if` statements added in Phase B (per styleguide).

Track this as its own commit or its own follow-up TODO depending on
size when we get there.

## Design questions to resolve before commit 1

Before writing code, agree on:

1. **`RescoreInputs` ownership.** Is option (a) from the predecessor
   TODO (PerFileScoringTask owns the bundle; FirstJoinTask reads via
   `GetRescoreInputs(ctx)`) actually preferred, or is option (b)
   (memoize inside `RescoreHydration.HydrateForRescore`) cleaner now
   that we've seen how the lazy-rehydrate accessors landed? The user's
   instinct in the predecessor was (a); confirm.
2. **How does `PerFileScoring.joinOnly` decide which hydration shape
   to produce?** Probe-the-disk dispatch ("does
   `.1st-pass.fdr_scores.bin` exist for these `--input-scores` paths?")
   is the natural answer but mixes mode-detection with hydration.
   Alternative: thread the mode through from CLI as an enum
   (`Stage5Raw` / `Stage6Reconciliation` / `Stage7TwoPass`). Discuss.
3. **Are PerFileRescore's outputs the right `Outputs(ctx)` set in
   stage6 worker mode?** Today it declares `.scores.parquet` per file.
   Stage6 overwrites them in place. The validity_key tagging is
   correct; the question is whether the user wants the same task to
   also write a stage6-completion marker that downstream tools can
   look for.
4. **Test-coverage commit sequencing.** Do we land
   `TaskValiditySidecar` unit tests as commit 1 of Phase C (so they
   underwrite the refactor that's about to happen), or as a follow-up
   commit after convergence (so they cover the final shape)?
   Recommend the former — they're independent of the convergence work
   and de-risk it.
5. **Single-PR vs split.** Phase B was carved into 4+1 commits in one
   PR. Phase C is smaller in line count but touches the seam that
   gates correctness across three CLI modes. Same one-PR-with-small-commits
   shape, or split convergence from cleanups?

## Implementation plan (preliminary, pending design discussion)

Numbers are rough; revise after the design discussion.

1. `TaskValiditySidecar` unit tests (P2). Independent of convergence;
   land first.
2. `AnalysisPipeline.CanonicalPipeline()` factory + `RescoreWorker.Run`
   collapse to one-liner. `PerFileRescoreTask.RunWorker` stays for now
   (the body's hydration logic moves elsewhere in step 3).
3. Hydration unification on `PerFileScoringTask.joinOnly`: produce the
   right `RescoreInputs` shape based on which sidecars are present.
   `FirstJoinTask` lazy-rehydrate accessors read from
   `PerFileScoringTask.GetRescoreInputs(ctx)`.
4. Delete `PerFileRescoreTask.RunWorker` and the CLI-mode branches in
   task Runs subsumed by StartAt + lazy-rehydrate.
5. P1-P3 follow-ups (doc notes, version skew check, try/finally,
   dead-branch comment, Build-Skyline.ps1 backport).

## Validation gates (per commit)

- Build green; OspreySharp unit tests pass (303+).
- Stellar 3-file snapshot regression PASS at every stage.

## PR-open gates

- Astral 3-file snapshot regression PASS at every stage.
- Cross-impl Test-Regression with Mike's Rust osprey PASS.
- Manual: stage6 worker invocation (`--no-join --input-scores ...`)
  produces byte-identical output as today's `RescoreWorker.Run` path.
- No code in the pipeline mentions `IsWorkerMode` by any flag; the
  word "worker mode" survives only in doc comments describing CLI
  semantics.

## Phase C success criteria

- `RescoreWorker.Run` is one line: `return new AnalysisPipeline().Run(config);`
- `PerFileRescoreTask.RunWorker` body deleted.
- `AnalysisPipeline.CanonicalPipeline()` is the single source of truth
  for the 4-task list.
- CLI-mode branches inside task Runs (the `ExpectReconciledInput` /
  `NoJoin` / `joinOnly` checks) deleted where the StartAt mechanism
  + lazy-rehydrate subsumes them.
- All Phase B success criteria continue to hold (resume + snapshot +
  cross-impl gates green).
