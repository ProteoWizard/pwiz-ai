# PerFileRescoring ends with a whole-run join that rebuilds the buffer its own streaming just discarded

## Branch Information
- **Branch**: `Skyline/work/20260820_osprey_perfilerescore_no_join`
- **Base**: `master`
- **Created**: 2026-08-20
- **Status**: In Progress
- **GitHub Issue**: [#4597](https://github.com/ProteoWizard/pwiz/issues/4597)
- **Module**: `osprey`
- **Worktree**: `C:\proj\pwiz-work1`
- **PR**: [#4600](https://github.com/ProteoWizard/pwiz/pull/4600)
- **Requester/Reporter**: none — raised by Brendan (project developer), no credit line

## Objective

`PerFileRescoreTask` is a per-file HPC task (`NoJoin` in `Program.cs`), yet on the
straight-through path it ends with whole-run join work: `MaterializeAllSurvivors` +
`OverlayReconciledIntoAllFiles` re-read every file's artifacts to rebuild the complete
in-memory buffer `SecondPassFDR` consumes — the same buffer the streamed rescore
deliberately dropped file-by-file to keep memory bounded.

Move the pool construction to its consumer (`SecondPassFDR`), which already builds it on
the `--task SecondPassFDR` path, and let the lazy `PipelineContext.Get<TInfo>()` pull
materialize it instead of the `SecondPassFdrWillRun` predicate guarding eager work.

Measured cost of the join block on the 82-file SEA-AD run
(`seaad-82files-libdecoy-r1.0-protein-compact-p2-pickrun3-ours-n82`): **16 min 20 s**
(10.2% of PerFileRescoring), managed heap **5.9 GB → 27.0 GB** resident with a 49.9 GB
transient touch; total process 18.8 GB → 41.6 GB entering Stage 7.

## Tasks

- [ ] `PerFileRescoring` ends with no join work, so its shape matches the HPC exit point
      it already is
- [ ] `SecondPassFDR` builds its own global survivor pool — which it already does on the
      `--task SecondPassFDR` path (`Rehydrate`, `ExpectReconciledInput`)
- [ ] `SecondPassFdrWillRun` predicate removed rather than maintained: a worker skips the
      work because nothing pulls it, not because a predicate said so
- [ ] Check (not necessarily fix) the two recorded latent HPC risks while in here:
      `--input-scores` order sensitivity in multi-file FirstJoin, and straight-path global
      compaction vs HPC worker per-file compaction

## What must NOT be lost

- **`ResetRescoredTargets` may only touch files rescored in THIS process.** Scores are
  in-memory only (`ReconciledParquetWriter` persists boundaries/area/features, not
  scores); under frozen-model modes an off-stratum survivor keeps its 1st-pass q, so the
  difference reaches the report. Recorded miss: Stellar straight-through reported 31,583
  precursors against golden 29,364. Resetting resume-skipped files is the mirror error.
- **`canonicalize: false` on the streamed rebuild is deliberate.** Cold rescore appends
  gap-fill at the end and never re-sorts; sorting changes the buffer order Stage 7 writes
  2nd-pass sidecars in, which changes the protein-compact competition and the reported
  set. The resume path passes `true` deliberately (`PerFileRescoreTask.cs:1840-1862`).

## Regression Test

- **Test name**: `TestDeferredMilestoneBuildsOnFirstValueRead`,
  `TestUndeferredMilestoneReadsStraightThrough` (`Osprey.Test/ByproductContextTest.cs`)
- **Test project**: Osprey.Test, plus the behavioral gate `regression.ps1`
- **Fails on master**: n/a — these pin a mechanism master does not have (the deferring
  `RescoredEntries` constructor), so they cannot be red before the change. What they DO
  catch is the two ways the deferral silently un-defers later: a `Publish`-time read of
  `Value` (the DEBUG milestone-ordering guard did exactly that before this change) and a
  second read re-running a non-idempotent overlay.
- **Passes on fix**: yes — 588 Osprey.Test tests green, zero-warning ReSharper inspection

The real failure mode of the move is a wrong COUNT, not a crash, so the deciding gate is
behavioral: `regression.ps1` modes 1/2/3 cover all three `RescoredEntries` build paths
(straight-through cold, straight-through resume, `--task SecondPassFDR` node), and
`-Dataset All` plus the TeamCity Perf/Regression gate before merge.

## Files

- `pwiz_tools/Osprey/Osprey.Tasks/PerFileRescoreTask.cs`
- `pwiz_tools/Osprey/Osprey.Tasks/Pass2FdrSidecar.cs`
- `pwiz_tools/Osprey/Osprey.Tasks/SecondPassFdrTask.cs`
- `pwiz_tools/Osprey/Osprey/Program.cs`

## Progress Log

### 2026-08-20 - Session Start

Starting work on this issue. Branch created in `C:\proj\pwiz-work1`.

### 2026-08-20 - Implemented: the milestone carries the join, the pull runs it

**Design.** The seam is the milestone itself. `RescoredEntries` gained a second
constructor taking an `Action` that runs on the first `Value` read
(`PipelineByproducts.cs`), and `PerFileRescoreTask.Run` publishes it that way, handing it
`BuildRescoredPool` — the former tail block, unchanged in content and order:
`MaterializeAllSurvivors` → `ResetRescoredTargets` → `OverlayReconciledIntoAllFiles(canonicalize: false)`.
`SecondPassFdrTask.Run`'s existing `ctx.Get<RescoredEntries>().Value` is what runs it, so
Stage 7 — the stage that needs a global pool — is where the work lands.

Why not move the body into `SecondPassFdrTask`: the build needs Stage-6 knowledge
(`PerFileRescoreTask.ValidityKey`, the planner byproducts, and which of `canonicalize`
true/false this path requires), and it shares its body with the resume `Rehydrate`. This
matches the precedent the issue itself cites — on the `--task SecondPassFDR` path the code
already lives in `PerFileRescoreTask.Rehydrate` and SecondPassFDR's pull is what triggers it.

**Also in the change**

* `SecondPassFdrWillRun` deleted. A worker skips the join because nothing pulls it.
* The self-gated no-op path's eager refill is deferred too, through the same
  `BuildRescoredPool` with `_rescoredFiles` still null — refill, no overlay, which is what
  keeps `OSPREY_STAGE6_STREAM_SURVIVORS=0` a byte-identity oracle on that path.
* `MaterializeAllSurvivors` throws `InvalidDataException` instead of returning false: a
  deferred build has no bool channel back to the driver loop (the `RehydrateFailedException`
  precedent), and a refill that quietly gave up would hand Stage 7 an empty pool.
* New non-forcing `PerFileEntries.BackingBuffer`, used by the DEBUG milestone-ordering
  guard. Without it `Publish` itself would materialize the deferred milestone in Debug
  builds — before the rescore that fills it has run.
* The `OSPREY_DUMP_RESCORED` cross-impl dump now reads the milestone (a pull), so it still
  dumps the whole-run buffer.
* `regression.ps1`'s known-resident-gaps table said "resident from the end of Stage 6";
  updated to say the pull builds it and that this moves who pays, not how big it is.

**Not changed, deliberately**: the pool still exists and is still O(survivors) resident
through Stage 7. This is a shape change, not a saving — on the straight-through path the
same ~16 min / ~27 GB at 82 files simply lands at the start of Stage 7 instead of the end of
Stage 6, which will show as stage6 wall time moving to stage7. What it buys: no per-file
worker can pay it, and a resume whose Stage 7 outputs are already valid no longer builds a
pool nothing reads.

**Latent HPC risks the issue asked to check while in here** (not fixed, unchanged by this):
`--input-scores` order sensitivity in multi-file FirstJoin, and straight-path global
compaction vs the HPC worker's per-file compaction. Neither is touched — `BuildRescoredPool`
iterates the same per-file collections in the same order the tail block did; only its
position in the run moved.

**Gates**

* `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`: 588 tests pass, 0
  inspection warnings.
* `regression.ps1 -Dataset Stellar`: **PASSED** — mode1 (vs golden), mode1c, mode3 (per-file
  sidecars == straight, 2,443,597 records; HPC chain == straight), mode4, mode2 (resume
  cache hits + resume == straight), mode5, mode6. Log:
  `C:\proj\ai\.tmp\regr-4597-stellar-2.log`.
* First Stellar attempt aborted in mode 3 **phase 1** (`--task PerFileScoring`, exit -1) —
  a phase that runs none of the changed code, and the identical rerun passed it. Treated as
  environmental; `-Dataset All` is the re-confirmation.
* Pending: `Test-PerfGate.ps1 -Dataset Stellar`, `regression.ps1 -Dataset All`,
  TeamCity Perf/Regression (ask first).

### 2026-08-20 - /code-review max: one real regression in the move, fixed

15 findings; 12 fixed, 2 dropped, 1 handed back as pre-existing. The one that mattered:

**The overlay's validity gate must not move past `WriteTaskSidecars`.** `AnalysisPipeline`
stamps this run's validity key onto EVERY declared output that merely `File.Exists` once
`Run` returns, with no check that this run produced it (`AnalysisPipeline.cs:238-249`), and
`PerFileRescoreTask.Outputs` declares a reconciled parquet per input file. Deferring the
overlay to the Stage-7 pull put its `PerFileResumeDriver.IsCurrent` test AFTER that stamp,
so a `.scores-reconciled.parquet` from a run under a different validity key - one this run
rejected as stale, `ClearStale` deleting the sidecar but not the parquet, and never rewrote -
came back as "current" and its boundaries were overlaid into this run's blib. Silent, exit 0.
No `regression.ps1` mode covers it: modes 1-6 all run within a single validity key, while
`OspreyEnvironment.cs:449-454` promises switching modes within one output directory is safe.

Fix: `RescoredPoolPlan`. `Run` DECIDES (which parquets are current, which files were
rescored, the planner byproducts) while the answers are still true, and only the answers
travel to the pull. Deferring the decision as well as the work was the actual mistake.

Also fixed: `Lazy<bool>` (ExecutionAndPublication) so a failed build stays failed instead of
leaving a half-filled pool flagged built, and two threads cannot both run a non-idempotent
overlay; `MaterializeAllSurvivors` logs the file and sets `ExitCode` before throwing; a
`[STAGE-WALL] survivor-pool` line (the ~16 min had landed in NO bucket, so a perf A/B would
have read a fabricated Stage 6 win); the `stage7-inherited` probe taken BEFORE the pull with
a new `stage7-pool` probe after it (#4486 comparability); `BackingBuffer` narrowed to an
opaque `BufferIdentity`; the self-referential `ctx.Get` inside `Run` replaced by the token;
`PipelineContext.Tasks` deleted (its only reader was the deleted predicate); six stale
comments including a live justification at `FirstPassFdrTask.cs:672` and
`Regression/README.md`; three added tests (non-forcing identity read on a DEFERRED milestone,
the two-milestones-over-one-buffer shape, and a throwing build that must not retry).

Dropped: a `--task PerFileRescoring` worker under `OSPREY_DUMP_RESCORED` now pays the join
and dumps the full buffer rather than the drained one (a `-d`-only path, and the fuller dump
is the correct one), and a speculative DEBUG assert on the milestone-consumed bit.

**Handed back, NOT fixed here**: the stamp itself. `WriteTaskSidecars` stamping outputs the
run never produced is a pre-existing defect that still exposes the resume `Rehydrate` path
exactly as before this branch. This change no longer widens it; closing it is its own issue.

Gates after the fixes: 589 unit tests, 0 inspection warnings, `regression.ps1 -Dataset
Stellar` PASSED again (all ten checks, identical blibs) - `C:\proj\ai\.tmp\regr-4597-stellar-3.log`.

Exe snapshots for the SEA-AD 82-file run: `D:\test\osprey-runs\_bin\4597-deferred-pool`
(pre-review, 26.1.1.231) and `D:\test\osprey-runs\_bin\4597-deferred-pool-r2` (post-review,
26.1.1.232 - the one to use).

### 2026-08-20 - PR #4600 open, -Dataset All green, Copilot addressed

* **`regression.ps1 -Dataset All`: PASSED** - 56 checks across all four datasets, including
  the Astral leg (mode3 per-file sidecars == straight over 9,685,318 records, HPC chain ==
  straight) and every mode 1/1b/1c/2/3/4/5/6/7. Log: `C:\proj\ai\.tmp\regr-4597-all.log`.
* Copilot review: two comments. Its `InternalsVisibleTo` claim was WRONG (declared at
  `Osprey.Tasks.csproj:8-11`, which is how the pre-existing tests in that same file already
  reach `PipelineContext`) - refuted with evidence rather than acted on. Its second was right:
  the `!_materialize.Value` branch was unreachable, since the `Lazy` factory returns true or
  throws; simplified to `_ = _materialize?.Value;` (commit `0bb06c9023`, 589 tests + zero
  inspection warnings after). Provably equivalent, so the `-Dataset All` result stands.
* Perf gate deliberately NOT run: Brendan's 82-file SEA-AD run has the machine, and a 3-rep
  median cannot share a box. Outstanding before merge: `Test-PerfGate.ps1 -Dataset Stellar`
  and the TeamCity Perf/Regression config (ask first, `branch=pull/4600`).

### 2026-08-20 - End of evening: state and the morning checklist

**Where it stands.** PR [#4600](https://github.com/ProteoWizard/pwiz/pull/4600) is open and
green on every gate run so far: 589 unit tests, zero inspection warnings,
`regression.ps1 -Dataset Stellar` twice (before and after the review fixes) and
`-Dataset All` once (56 checks, all four datasets). Both Copilot threads are resolved - one by
the fix in `0bb06c9023`, one by refutation with evidence. Follow-up #4601 is filed.

**Running overnight**: TeamCity build 4144779, Osprey Windows .NET Perf/Regression Tests,
`branch=pull/4600`, pinned to MacCoss TeamCity Agent 1.
https://teamcity.labkey.org/build/4144779

**TeamCity 4144779 came back RED - and the evidence says it is NOT this branch.** Posted to the
PR as issue comment 5365899988. The case, in the order it was established:

* **What failed**: `StellarLibDecoy` and `StellarGenDecoyEntrap`, modes 1 / 1b / 5 / 7. Not
  tolerance drift - a different discovery set (`RefSpectra: 12 key(s) only in golden`,
  `11 only in run`; `nTarget golden=247012 run=241551`).
* **What passed**: `Stellar`, straight-through blib **25,358,336 bytes** - byte-for-byte the
  size produced locally. Same agent, same commit, same mzMLs, identical result.
* **Local `-Dataset All` passes those exact legs on this code** (`regr-4597-all.log:110` and
  `:125`), 56 checks green.
* **Master has not moved**: `43b5aaf064` IS current master, so the branch carries master's
  exact goldens. Same code + same goldens + different result => the variable is input data.
* **The two failing datasets are exactly the two sharing**
  `stellar-libdecoy/carafe_spectral_library.tsv` (`regression.ps1:355-383`). Stellar uses a
  different library. That file is not in git.
* **THE ANCHOR: the last green run of this config was build #121 on 2026-07-08** (commit
  `9f87c5c5d1`). The goldens have been rebaselined four times since - most recently
  `78a214a9db` (#4585) on 2026-08-17. So this config has never run against the current
  goldens on this agent, and there is no green baseline for this PR to have broken.
* **Most likely cause**: `regression.ps1:314-318` documents the trap - acquisition is
  skip-if-present ON THE EXTRACTED ROOT, so re-publishing `osprey-testfiles-mzML-v2.zip` under
  the same name "would never reach a machine that already has the tree". Locally the resolved
  libdecoy library is dated Jun 30 (2,535,647,081 bytes) and matches the goldens; a newer
  `stellar-libdecoy-v3/carafe_spectral_library.tsv` (Aug 19, 2,487,665,003 bytes) sits beside
  it, staged but NOT wired into the dataset table. The agent's copy is unknown and unreadable
  from here - the TC log is only the 316-line console stream, and run dirs are deleted.

**FINAL TALLY (build finished 23:46), and it sharpens the case decisively:**

* **Astral: EVERY check PASS** - and to the record, `mode3 (per-file FDR sidecars==straight):
  PASS (9,685,318 records)` and `mode1c: 19,008 of 3,449,774 shared records moved; 8,800
  gap-fill`. Identical figures to the local `-Dataset All`. **Stellar: PASS.** Three of four
  datasets reproduced on the agent exactly; the two that differ are the two sharing the
  libdecoy library.
* **On the failing datasets, ONLY the vs-golden comparisons fail.** Every self-consistency mode
  passes: `mode3 (per-file FDR sidecars==straight): PASS (3,809,205 records)`,
  `mode3 (HPC chain==straight): PASS`, `mode2 (resume==straight): PASS`,
  `mode2 (resume cache hits): PASS`, `mode4 (warm re-run all cached): PASS`,
  `mode1b (FDR sanity bounds): PASS`. Modes 2 and 3 are EXACTLY the paths this PR changes - the
  resume rehydrate and the `--task` worker chain, both exercising the deferred pool build - and
  they agree with straight-through across 3.8 M records. A defect in the change reds those
  first. "Agrees with itself everywhere, disagrees only with a stored baseline" is a
  baseline/input mismatch, not a code defect.
* **The perf leg never ran.** Step 3/5 aborted at the regression failure; steps 4/5 and 5/5 are
  disabled. This build produced NO perf verdict, so the local A/B is the only perf gate and is
  now more important, not less.

**Morning checklist, in order:**

1. ~~Trigger this config on `master` as a change-immune anchor.~~ **RETRACTED - cause is known.**
   Brendan identified it directly: a script on PR #4593 overlaid a v3 stellar-libdecoy library
   onto the v2 tree by OVERWRITING the v2 library IN PLACE. That session has since rewritten
   the script (which is why this machine passes - here the resolved
   `stellar-libdecoy/carafe_spectral_library.tsv` is still the Jun 30 v2, with v3 quarantined
   in a `stellar-libdecoy-v3/` subfolder), but MacCoss Agent 1 still holds the overwritten
   tree. An older branch cannot detect this: its script just runs the wrong library and reds
   against goldens it never disagreed with. #4593 is now adding self-healing, and its TC run
   is what repairs the agent's disk. A master baseline run would burn an hour of the shared
   agent to confirm what is already known.

   **Open question for that session before treating their run as the unblock**: #4593
   rebaselines 47 golden files, including BOTH `stellar-libdecoy/` and
   `stellar-gendecoy-entrap/`, but does NOT touch `regression.ps1` - so the dataset table still
   resolves the same path. Both PRs therefore need the SAME content at
   `stellar-libdecoy/carafe_spectral_library.tsv`: #4600 needs v2, and #4593's new goldens need
   whatever they were generated against. If v2 (likely - that is what resolves on this
   machine), the healing satisfies both. If v3, no single file satisfies both and #4600 stays
   red until #4593 merges and this branch rebases.

   Residual: this branch's `Regression/RegressionData.ps1` predates the fix (last touched by
   #4540), so it has neither the healing nor any staleness DETECTION. Until that reaches
   master, every older branch stays defenseless against a re-corruption.

2. After #4593's run repairs the agent, **re-trigger 4600's Perf/Regression** - ASK FIRST.
3. Once Brendan's 82-file SEA-AD run has released the machine, run the local perf A/B:
   `pwsh -File ./ai/scripts/Osprey/Test-PerfGate.ps1 -Dataset Stellar` from `C:\proj\pwiz-work1`.
4. `/pw-complete` on #4600 - ONLY after the agent is repaired and 4600 is green there. If
   #4593 merges first, rebase #4600 onto master and re-run: this PR's claim is byte-identical
   output, so it is golden-agnostic and needs no golden work of its own, but its green should
   be against the goldens it actually merges with. Squash subject keeps the prefix:
   `osprey: Moved the PerFileRescoring whole-run join to the consumer that needs it (#4600)`.

**Do not**: merge on the current red, and do not run anything CPU-heavy while the 82-file run
owns the box.

### 2026-08-20 - Filed #4601 for the artifact contract

The stamp defect I handed back turned out to be the smaller half. Brendan reframed it from the
HPC workflow-engine side: the artifact layout IS the engine's API, and encoding "nothing to do"
as a missing file means the engine cannot tell "not done" from "done, nothing to do" - so it
must allocate a node and stage that file's inputs just to let a planner discover there was no
work. Filed as [#4601](https://github.com/ProteoWizard/pwiz/issues/4601), cross-linked from
#4600.

The shape of it, for whoever picks it up:

* **The input side already does this right.** `FirstPassFdrTask.cs:1802-1815` writes a
  `reconciliation.json` for EVERY file, empty lists and all. Only the output side encodes
  nothing-to-do as absence. The marker is the missing half of an existing convention.
* **Two artifacts missing, not one.** A work manifest from the join (Stage 5 computes the work
  set and discards it; `reconciliation.json` cannot substitute because it carries actions +
  gap-fill but NOT the multi-charge consensus targets, so an empty one does not mean no work),
  and a per-unit completion marker carrying the validity key and a recorded `rescored` fact.
* **Marker always beats the stamp fix** because it closes the channel the stamp cannot:
  `AnyReconciledParquet` and `EffectiveScoresPathFromScoresPath` are bare `File.Exists`, so a
  stale parquet is read for features with no sidecar involved. Writing every declared output
  means there is no leftover to find.
* **Watch on landing**: the `total_rescored > 0` C#/Rust parity (#4395) is currently ENCODED as
  presence, so it must move to a recorded fact rather than be dropped; the strict
  `--task SecondPassFDR` gate must stay an attestation, not a bypass; `regression.ps1:1179/1199`
  copies a reconciled parquet per stem unconditionally and only works because every file in all
  four datasets has work; and an honest `Outputs()` makes the coarse `CanRehydrate` skip start
  firing (modes 4/5). The verification leg does not exist yet and needs a dataset with a
  no-work file.
