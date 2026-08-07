# Osprey: every resume hands Stage 6 the O(files) survivor buffer, untokened and unguarded

## Branch Information
- **Branch**: `Skyline/work/20260806_rehydrate_survivor_loader`
- **Worktree**: `C:\proj\pwiz-work1`
- **Base**: `master`
- **Created**: 2026-08-06
- **Status**: In Progress
- **GitHub Issue**: [#4536](https://github.com/ProteoWizard/pwiz/issues/4536)
- **Module**: `osprey`
- **Other labels**: `performance`
- **PR**: (pending)
- **Requester/Reporter**: none (filed by Brendan, developer of Osprey — no credit line)

## Objective

Give `FirstJoinTask.Rehydrate` its own per-file survivor loader so
`FirstPassSurvivorSource` is non-null on BOTH arms. Stage 6 then streams on a
resume exactly as it does on a computed run, `Stage6ResidentHandoffGuardError`
starts covering that path for free, and the interim
`OSPREY_ALLOW_UNFIXED_RESIDENT=resume-survivor-handoff` token (added by #4537)
plus its warning are deleted.

Today `_survivorLoader` has exactly one assignment, reachable only from `Run`'s
projection path, so `Rehydrate` publishes null and every streamed branch in
`PerFileRescoreTask` is skipped. Stage 6 keeps `ctx.Get<CompactedEntries>()`
live — the all-files survivor set #4526 measured at 88,875,901 entries /
28.17 GB, held 5.5 hours at 163 files.

**This is design work, not wiring.** The per-file loader needs the passing
base_id set, which only a computed Stage 5 produces today. A resume must derive
it from the reconciliation envelopes' `first_pass_base_ids` (v3 required field,
already used by `RescoreCompaction`); reconstructing the loader's contract from
that needs designing and pinning.

## Context from #4537 (merged 2026-08-06)

#4537 landed the interim state this issue removes:
* The resume path is now **refused unless tokened** —
  `OSPREY_ALLOW_UNFIXED_RESIDENT=resume-survivor-handoff`, dedicated (not
  shared with `compacted-entries-buffer`), pinned both directions in
  `ResidentPoolGuardTest`.
* `regression.ps1` prints outstanding gaps in every run summary and requires
  exactly 1 token today (target: 0).
* `regression.ps1` mode 5 is the only leg reaching the own-sidecar bundle
  loader, i.e. the rehydrate arm this issue fixes.

## Tasks

- [ ] Derive the passing base_id set on the rehydrate path (from the v3 envelopes)
- [ ] Build a `FirstPassSurvivorLoader` for `Rehydrate` and publish it
- [ ] Confirm `Stage6ResidentHandoffGuardError` now fires on that path when
      `OSPREY_STAGE6_STREAM_SURVIVORS=0` (i.e. the token becomes required, as on `Run`)
- [ ] Delete the interim warning + `resume-survivor-handoff` token in
      `FirstJoinTask.Rehydrate` / `ResidentPaths`, and the note on
      `Stage6ResidentHandoffGuardError` explaining why its justification had lapsed
- [ ] Drop the token from the `regression.ps1` outstanding-gaps list (back to 0 required)
- [ ] Byte-identity A/B: resume blib streamed vs resident, at 1e-9
- [ ] Memory evidence at scale: `--timestamp --memstamp` + `ai/scripts/perfviz.py`,
      showing the rescore floor flat in file count on a RESUME
- [ ] `regression.ps1 -Dataset All` (mode 5 exercises the rehydrate arm)
- [ ] `Build-Osprey -RunTests -RunInspection`
- [ ] `/code-review max` before opening the PR

## Regression Test

- **Test name**: (filled in once written — expected: extend `ResidentPoolGuardTest`
  for the now-covered rehydrate path, plus `regression.ps1` mode 5)
- **Test project**: Osprey.Test + `regression.ps1` mode 5
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

## Coordination

`C:\proj\pwiz` is on `Skyline/work/20260806_osprey_release_gate` (PR #4539)
with uncommitted edits to `pwiz_tools/Osprey/regression.ps1` and
`Regression/README.md` — the same files this issue touches when the token count
drops to 0. Sequence: let #4539 land first, or rebase this branch onto it before
editing those two files.

## Design

The issue expected the hard part to be "derive the passing base_id set on the
rehydrate path (from the v3 envelopes)". Reading the code, that set is already
derived on that path - twice - and the real design question is **which** set,
because there are two and they are not the same:

* `RescoreInputs.GlobalFirstPassBaseIds` - the v3 envelope's
  `first_pass_base_ids`, i.e. the join-wide local-FDR + protein-rescue predicate.
* The set compaction actually **retains**: that one UNION the base_ids of every
  entry the planner emitted a reconciliation action for. `RescoreCompaction.Apply`
  computes the union (step 2), and `HydrateCompactedStreaming` computes the same
  union in its envelope-only pass 1 so it can pre-filter per file.

A loader filtered on `GlobalFirstPassBaseIds` alone would silently drop
cross-file-rescued entries on the rebuild - the exact ~200-rows-per-file blib
divergence `RescoreCompaction`'s union step exists to prevent. So the loader has
to filter on the union.

**Chosen source: `RescoreCompaction.Apply`.** It already holds both terms, it is
the single authority the streaming pre-filter is checked against
(`RescoreCompaction.cs` invariant "the streamed bundle was pre-compacted to a
different set than Apply re-derives"), and it runs on **every** bundle arm -
worker-supplied, own-sidecar batch, own-sidecar streaming. Taking the set from
there means the rebuilt list equals the buffer by construction on all three,
instead of re-deriving one term at the call site. `Apply` now publishes it as
`RescoreInputs.RetainedBaseIds`.

Everything else the loader needs (`PerFileParquetPaths`, config) is already
published on the rehydrate path, so with the set in hand the loader is a
constructor call.

### Ordering - the one residual risk

`FirstPassSurvivorLoader.Load` sorts by `FdrEntry.CANONICAL_ORDER`; the rehydrate
buffer is parquet order after an order-preserving `RemoveAll`, and the planner's
`vec_idx` values are mapped against THAT order. If the two differ, a streamed
refill would re-index the reconciliation actions onto the wrong entries.

Expected benign: the pre-compaction buffer is entry_id-sorted before the parquet
is written (`DeduplicatePairs`, per `PercolatorEngine`'s sort comment), the
projection path loads from the same parquet through the same loader, and #4530
proved that byte-identical against the legacy in-memory compaction. The
`regression.ps1` mode 5 blib-vs-straight-through comparison at 1e-9 is the oracle
that settles it rather than an argument.

## Progress Log

### 2026-08-06 - Session Start

Starting work on this issue. Branch created in `C:\proj\pwiz-work1` off master
at `a40c7ebd08`, which already contains #4537 (`4169f844c2`).

### 2026-08-06 - Implementation

* `RescoreInputs.RetainedBaseIds` added; set by `RescoreCompaction.Apply`.
* `FirstJoinTask.TryBuildResumeSurvivorLoader` builds the loader on the rehydrate
  path and `Rehydrate` publishes it into `FirstPassSurvivorSource`, then releases
  the per-file survivor contents exactly as `Run` does after planning (consensus
  targets are computed off the full buffer immediately before, and are its last
  all-files reader).
* `Stage6ResidentHandoffGuardError` now called from `Rehydrate` too - the same
  call `Run` makes. A resume reaches it with streaming AVAILABLE, which is what
  made the interim guard removable.
* Deleted: `PerFileScoringTask.ResumeResidentHandoffGuardError`,
  `NeedsResidentPoolForRun`, `ResidentPaths.RESUME_SURVIVOR_HANDOFF`, the interim
  warning in `Rehydrate`, and the lapsed-justification note on
  `Stage6ResidentHandoffGuardError`.
* `regression.ps1`: `$knownResidentGaps` is now empty (summary prints "none"),
  mode 5 no longer sets a token; help text + `Regression/README.md` updated.
* Tests: `ResidentPoolGuardTest` pins the shrunk `KNOWN_UNFIXED` (both
  `mdiag-full-resume` and `resume-survivor-handoff` gone) and drops
  `AssertResumeHandoffGuard`; `IOTest.TestRescoreCompactionUnionsActionsWithLocalFdrPredicate`
  now pins `RetainedBaseIds == {1,2,3}` against `GlobalFirstPassBaseIds == {1}`,
  so the two cannot quietly become aliases.

Gate so far: `Build-Osprey -RunTests -RunInspection` green - 576/576 tests, 0
inspection warnings/errors across net472 + net8.0 (109.5s inspection pass).
`regression.ps1 -Dataset Stellar` running; log at
`C:\proj\ai\.tmp\4536-regression-stellar.log`.
