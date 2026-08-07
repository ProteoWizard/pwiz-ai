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

## Progress Log

### 2026-08-06 - Session Start

Starting work on this issue. Branch created in `C:\proj\pwiz-work1` off master
at `a40c7ebd08`, which already contains #4537 (`4169f844c2`).
