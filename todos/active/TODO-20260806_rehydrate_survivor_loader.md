# Osprey: every resume hands Stage 6 the O(files) survivor buffer, untokened and unguarded

## Branch Information
- **Branch**: `Skyline/work/20260806_rehydrate_survivor_loader`
- **Worktree**: `C:\proj\pwiz-work1`
- **Base**: `Skyline/work/20260806_osprey_release_gate` (PR #4539) - **STACKED**
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

- **Test name**: `IOTest.TestRescoreCompactionUnionsActionsWithLocalFdrPredicate`
  (extended) + `ResidentPoolGuardTest.TestResidentPoolGuard` (KNOWN_UNFIXED
  pinning) + `regression.ps1` modes 3 and 5
- **Test project**: Osprey.Test + `regression.ps1`
- **Fails on master**: n/a for the unit tests - see the note below
- **Passes on fix**: yes. `Build-Osprey -RunTests -RunInspection` 576/576, zero
  inspections (net472 + net8.0). `regression.ps1 -Dataset All` 44/44 legs;
  final `-Dataset Stellar` after the robustness commit, 8/8 legs
  (`C:\proj\ai\.tmp\4536-regression-stellar-final.log`).

**Honest accounting of what the tests do and do not cover.** The unit tests pin
CONTRACTS, not the defect: `RetainedBaseIds` is the union and not an alias of
`GlobalFirstPassBaseIds`, and `resume-survivor-handoff` is gone from
`KNOWN_UNFIXED`. Neither would go red on master, because on master the property
they assert does not exist yet - that is the nature of a "this path was never
given a loader" defect rather than a wrong-answer one.

What actually would have caught a regression here is `regression.ps1` modes 3
and 5, which now traverse the streamed rehydrate arm with NO token: reverting the
loader makes mode 5 fail on the resident-handoff guard, and breaking the survivor
ORDER makes mode 3's blib diverge. Plus the gate's own
`Tokens REQUIRED by this gate: 0` line, which turns any future re-addition into a
visible diff rather than an environment variable nobody re-reads.

The memory property itself has no automatic verifier. The sweep is a manual
harness (`Measure-Stage6Rescore.ps1`); nothing standing would fail if the slope
regressed to 0.213 GB/file, and `Test-PerfGate.ps1` covers the straight-through
path, not this one. Worth a follow-up issue rather than pretending otherwise.

## Coordination

**STACKED ON #4539.** Brendan's call (2026-08-06): rebase onto it rather than
wait. This branch is based on `origin/Skyline/work/20260806_osprey_release_gate`
(`5fe225cf6c`), not master, so the PR must target that branch.

The `regression.ps1` conflict was real and is resolved: #4539 added the mode 6
help block immediately after the sentence this issue rewrites (mode 5's token
line). Both kept.

**Merge hazard - do NOT `--delete-branch` #4539 on squash-merge.** Deleting the
lower branch mid-cascade auto-closes this PR, unreopenably. Order: retarget this
PR to master, `git rebase --onto master <old-base>`, THEN delete branches.

`C:\proj\pwiz` still holds uncommitted edits to `regression.ps1` and
`Regression/README.md` on the #4539 branch. Those are not in this rebase (only
the pushed tip is), so whoever commits them will meet the same conflict again.

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

## Memory-evidence plan (Brendan's call: 16-file Astral slope)

Harness: `ai/scripts/Osprey/SEA-AD/Measure-Stage6Rescore.ps1`. It drives
`--task PerFileRescoring --input-scores <N parquets>`, which reaches
`FirstJoinTask.Rehydrate` through a WORKER-supplied bundle - a rehydrate arm
#4530 did NOT fix and this change now streams. So it measures the right buffer
on the right path, and the headline number is the post-GC
`[MEM reconciliation-resident] managed_heap=` probe rather than `--memstamp`
(which includes uncollected garbage).

**A/B on ONE binary, not two builds.** `OSPREY_STAGE6_STREAM_SURVIVORS=0`
(plus `OSPREY_ALLOW_UNFIXED_RESIDENT=compacted-entries-buffer`, the documented
oracle token) makes the same binary take the RESIDENT handoff - i.e. the
pre-#4536 behavior - while the default streams. Six points: 4/8/16 files x
resident/streamed. Resident should slope in file count; streamed should be flat.
This is a cleaner comparison than building the base commit separately, because
only the one flag differs.

Invocation (after the gate frees the machine, against a SNAPSHOT exe so the
build tree stays usable):

```
Measure-Stage6Rescore.ps1 -FileCounts 4,8,16 `
  -DataDir    'D:\test\Pilot-MTG-Tissue-May2026\Astral-DIA\mzml' `
  -LibraryDir 'D:\test\Pilot-MTG-Tissue-May2026\lib\regression' `
  -PhaseDir   '<FRESH scratch dir>' -Exe '<snapshot>\Osprey.exe'
```

**HAZARD, found with `-WhatIf`: never point `-PhaseDir` at a real run
directory.** Each measurement starts with
`rm *.2nd-pass.fdr_scores.bin *.scores-reconciled.parquet` in the phase dir, so
aiming it at
`runs\seaad-82files-libdecoy-r1.0-protein-compact-picklda` (a complete 301 GB
experiment) would delete that run's outputs. Reusing its artifacts by hard link
is equally unsafe: if the version/validity check rejects them the harness
re-runs prep and rewrites through the link. Fresh dir, let it prepare - roughly
1.5 h of Stage 1-5 for 16 Astral files, paid once for all six points.

Library confirmed present:
`D:\test\Pilot-MTG-Tissue-May2026\lib\regression\target+decoy+entrapment\`
(`carafe_spectral_library.tsv` 13.1 GB + `osprey_library_db_pairing.tsv`).

## Memory results - the A/B (2026-08-07)

**The scope item is answered: the rescore floor is flat in file count on a
rehydrate, and was not before.**

Same binary, same phase dir, same 16 SEA-AD Astral files; the only difference is
`OSPREY_STAGE6_STREAM_SURVIVORS`, which on this branch selects between the new
per-file refill and the pre-#4536 resident handoff.

```
Files   streamed GB   resident GB   Rescored
    4          2.07          2.82     231557
    8          2.22          3.73     465304
   16          2.31          5.37     931582

slope   0.020 GB/file   0.213 GB/file        (10.7x)
500-file projection    12.0 GB     108.2 GB
```

`Rescored` is identical at every point, so the two arms did the same work - the
difference is what they held while doing it. Across a 4x increase in files the
streamed arm grows 12% (2.07 -> 2.31 GB) while the resident arm grows 90%
(2.82 -> 5.37 GB).

**Wall cost, stated rather than buried.** The streamed arm is slower:

```
Files   streamed s   resident s   delta
    4          444          433    +2.5%
    8          775          697   +11.2%
   16         1947         1781    +9.3%
```

That is the documented trade - the loader re-reads each file's
`.scores.parquet` + sidecar instead of holding the survivors - and ~10% of
Stage 6 buys a 10x slope reduction against a path that OOMs at 163 files.
Caveat on strength of evidence: ONE run per point, no repeats, so treat ~10% as
indicative rather than established; the memory separation (2.31 vs 5.37 GB) is
far outside any plausible run-to-run variance and does not need that caveat.
`Test-PerfGate.ps1` covers the straight-through path, not this one, so nothing
standing would have caught the wall delta either way.

## Memory results - streamed arm detail (2026-08-07)

16 SEA-AD Astral files, 30 threads, r1.0 target+decoy+entrapment library, this
branch's snapshot exe. Headline is the post-GC
`[MEM reconciliation-resident] managed_heap=` probe, not `--memstamp`.
Log: `C:\proj\ai\.tmp\4536-stage6-sweep-streamed.log`.

```
Files  ResidentGB  Rescored  WallSec
    4        2.07    231557      444
    8        2.22    465304      775
   16        2.31    931582     1947

slope: 0.020 GB/file  ->  500-file projection 12.0 GB
```

The rescored-entry count scales 4x across the sweep (231 K -> 932 K) while
resident memory moves 2.07 -> 2.31 GB, i.e. +12%. The residual 0.020 GB/file is
not the survivor buffer - that is the term this issue removes - and 2 GB at four
files is a floor the buffer never explained anyway.

One-time costs, for anyone repeating this: Stage 1-4 prep 55:12, Stage 5 9:15.

Direct evidence the NEW path is what ran, from the 16-file log (preserved at
`C:\proj\ai\.tmp\4536-sweep-logs\streamed-16f.log` - the phase dir reuses
`stage6-<N>f.log` per arm, so the resident sweep overwrites them):

```
03:05:00  Bundle hydration: skipping first-pass Percolator (sidecar provides q-values).
03:05:02  First-pass compaction: 68132616 -> 12399532 entries (513529 passing base_ids; 0 action(s) dropped)
03:33:19  Rebuilding first-pass survivors from 16 file(s)...
```

Line 1 is the rehydrate arm. Line 3 is `MaterializeAllSurvivors`, which before
this change could not run on a rehydrate at all - the loader was null, so every
streamed branch was skipped. The 28 minutes between lines 2 and 3 are the rescore
itself, and the 12.4 M-entry survivor buffer is NOT resident across them. That
gap is the fix.

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

`regression.ps1 -Dataset Stellar` PASSED, all seven legs
(`C:\proj\ai\.tmp\4536-regression-stellar.log`):

```
  Stellar mode1 (vs golden): PASS
  Stellar mode3 (HPC chain==straight): PASS
  Stellar mode4 (warm re-run all cached): PASS
  Stellar mode2 (resume cache hits): PASS
  Stellar mode2 (resume==straight): PASS
  Stellar mode5 (rehydrate entered + cache hits): PASS
  Stellar mode5 (rehydrate==straight): PASS

=== Known O(files) resident paths this gate still traverses ===
  none
```

Every blib 25,407,488 bytes; straight-through, HPC chain, resume and rehydrate
all compared at 1e-9.

**The ordering risk is settled empirically, not by argument.** Modes 3 and 5 are
the two legs that reach the rehydrate arm, and both now take the streamed
per-file refill where they previously kept the resident buffer. If the loader's
canonical sort had disagreed with the parquet order the hydrate's
`MapPlannedActions` indexed against, mode 3 would have applied reconciliation
actions to the wrong entries and its blib would have diverged. It does not.

"Known O(files) resident paths ... none" is the standing rule from #4537 reaching
its target: the gate now requires zero tokens.

### 2026-08-06 - Resident A/B and the rebase onto #4539

Ran the whole Stellar gate a second time under
`OSPREY_STAGE6_STREAM_SURVIVORS=0` + `OSPREY_ALLOW_UNFIXED_RESIDENT=compacted-entries-buffer`
(`C:\proj\ai\.tmp\4536-regression-stellar-resident-ab.log`): all seven legs PASS,
blib 25,407,488 bytes - the same size the streamed run produced. Since both arms
compare equal to the straight-through blib at 1e-9, streamed == resident on the
resume path transitively. That is the "resume blib streamed vs resident" scope
item, done on Stellar.

Committed as `fadf1951e9`, then rebased onto
`origin/Skyline/work/20260806_osprey_release_gate` -> `4a8d660c59`. One conflict
in `regression.ps1` (see Coordination), resolved keeping both sides. Rebuilt on
the rebased tree: 576/576 tests, 0 inspection warnings/errors.
`regression.ps1 -Dataset All` re-launched against the rebased tree - the earlier
`All` run was stopped, because a gate result on a tree that no longer exists is
not evidence about the tree that ships.

### 2026-08-07 - Full gate green, memory sweep started

`regression.ps1 -Dataset All` **PASSED** on the rebased tree, all 44 legs across
Stellar / StellarLibDecoy / StellarGenDecoyEntrap / Astral, including #4539's new
mode 6 (`C:\proj\ai\.tmp\4536-regression-all.log`). Every dataset's mode 5
(rehydrate == straight, diagnostics vs golden, FDR sanity bounds) and mode 3 (HPC
chain == straight) is green - those are the two legs that reach the rehydrate arm
this change rewires, and they pass with NO token:

```
=== Known O(files) resident paths this gate still traverses ===
  none
```

Exe snapshotted to `D:\test\osprey-runs\_bin\4536-rehydrate-loader\` so the build
tree stays usable during the sweep. Branch pushed
(`4a8d660c59`, based on `5fe225cf6c`).

Stage-6 memory sweep started, streamed arm first, into a FRESH phase dir
`D:\test\Pilot-MTG-Tissue-May2026\Astral-DIA\runs\stage6\stage6-16files`
(log `C:\proj\ai\.tmp\4536-stage6-sweep-streamed.log`).

### 2026-08-07 - Self-review pass

`/code-review` is user-invocable only (`disable-model-invocation`), so Brendan
has to run `/code-review max` before the PR opens. Own pass in the meantime
produced one fix and one investigated non-issue.

**Fixed (`def9f62bd7`): a null retained set was a silent fallback.**
`TryBuildResumeSurvivorLoader` returned a null loader whenever
`bundle.RetainedBaseIds` was null, on the reasoning that `CompactFirstPass`
skips `RescoreCompaction.Apply` only for an empty join. True today, and
unverified - and a null loader is invisible downstream, because
`Stage6ResidentHandoffGuardError` reads it as "this run could not stream" and
EXEMPTS the run. So any later change that gave `Apply` a second skip would put
Stage 6 back on the resident buffer with nothing raised: the same
undetected-regression shape this issue was filed about. Now a null set with
files joined is a hard error.

**Investigated, not a defect: the library release uses a different base_id set
than the loader.** `Rehydrate` sets
`_firstPassBaseIds = bundle.GlobalFirstPassBaseIds` for
`ReleaseUnscorableLibraryFragments`, while the loader filters on the union with
the planner's action targets. If an action target sat outside the global set it
would survive compaction, be rescored, and find its library fragments already
released. It cannot: on the computed path the planner runs AFTER compaction, so
its targets are a subset of the base_id set the envelope then records, and the
resume reads that same envelope. The union is a no-op in practice and is kept
because it is what compaction actually applies - filtering the rebuild on
anything else would be right only by coincidence. Pre-existing code either way;
this change does not alter which entries survive.
