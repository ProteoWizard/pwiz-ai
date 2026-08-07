# Rename Osprey task classes to match their user-facing task Names

## Branch Information
- **Branch**: `Skyline/work/20260806_osprey_task_class_rename`
- **Base**: `master`
- **Created**: 2026-08-06
- **Status**: Completed
- **GitHub Issue**: [#4535](https://github.com/ProteoWizard/pwiz/issues/4535)
- **Module**: `osprey`
- **Labels**: `osprey`, `tech-debt`
- **PR**: [#4540](https://github.com/ProteoWizard/pwiz/pull/4540) (merged 2026-08-06 as `dce8841689`)
- **Checkout**: `C:\proj\pwiz`

## Objective

The Osprey pipeline tasks carry two different names each: the C# class name and the
user-facing task `Name` that is stamped into `.osprey.task` sidecars and logged as
`[TASK] <Name>:...`. For two of the four tasks they disagree:

| Task `Name` | C# class | Informal names in comments |
|---|---|---|
| `PerFileScoring` | `PerFileScoringTask` | Stages 1-4, per-file scoring |
| `FirstPassFDR` | `FirstJoinTask` | "the join", "first join", Stage 5 |
| `PerFileRescoring` | `PerFileRescoreTask` | Stage 6, rescore |
| `SecondPassFDR` | `MergeNodeTask` | "the merge node", Stage 7 |

Both `FirstPassFDR` and `SecondPassFDR` are joining tasks, so "the join" and "the
merge node" apply the same metaphor to two different tasks and distinguish nothing.
The mismatch has already produced a real bug: a private copy of
`Invoke-ResumeInvalidation` keyed off the class names, matched zero files, and
silently produced a "resume" run that invalidated nothing and passed green while
testing nothing. Today only a comment prevents a recurrence.

Rename the two classes so class name, sidecar stamp, and log token are one string.
No behavior change and no `Name` change, so `regression.ps1` must be green before
and after.

## Scope decisions

Two extensions to the issue's scope, both agreed during the session:

1. **The `HpcTask` enum members are renamed too** (`FirstJoin` -> `FirstPassFdr`,
   `MergeNode` -> `SecondPassFdr`). The enum was a THIRD divergent name set the
   issue does not list, and `Program.TaskCliName` carried a doc comment
   apologizing for it. The members are never parsed from user input -
   `ResolveTask` maps the CLI strings explicitly - so this is internal-only and
   behavior-free. `PerFileRescore` is left alone: it matches its class, and only
   its CLI Name (`PerFileRescoring`) differs.
2. **The terminology goes away completely**, not just the two class names. That
   means the informal prose too: "the merge node", "the join", "first join",
   "first-join", "second join", "merge-node". ~330 sites across `pwiz_tools/Osprey`
   and the `ai/` scripts and docs. Ordinary English uses of "join"/"merge" that
   describe a data operation rather than naming a task are kept (e.g. "join-wide
   base_id set", "the merge is order-independent" in `Calibrator`).

Two historical mentions of the old names are kept ON PURPOSE, both because the
text is about the rename itself and loses its meaning without them:
`docs/15-hpc-scoring-split.md` (the divergence note explaining why one name per
task) and `Regression/RegressionData.ps1` (the warning whose justification IS the
incident - a private copy that keyed off the class names and resumed nothing).

## Tasks

- [x] Rename `FirstJoinTask` -> `FirstPassFdrTask` (file, class, all references)
- [x] Rename `MergeNodeTask` -> `SecondPassFdrTask` (file, class, all references)
- [x] Rename `HpcTask.FirstJoin` -> `FirstPassFdr`, `HpcTask.MergeNode` -> `SecondPassFdr`
      (see Scope decisions)
- [x] Confirm the `Name` property values are UNCHANGED (`FirstPassFDR`,
      `SecondPassFDR`) - verified: the five `override string Name` sites are
      untouched by the diff
- [x] Sweep comments and docs for the informal metaphors
- [x] Check the `docs/` numbered design notes for the same terminology - 07, 09,
      11, 12, 13, 14, 15, 16, 20 and `README.md` updated; the stale
      "task names differ from the pipeline stage" divergence note in 15 rewritten
      to describe the resolved state
- [x] `Build-Osprey -RunTests -RunInspection` - build green, 576/576 tests,
      inspection 0 errors / 0 warnings
- [x] `regression.ps1 -Dataset Stellar` - PASSED, all 7 legs, and the blib is
      **25,407,488 bytes in every mode** (straight-through, HPC chain, resume,
      rehydrate): byte-identical, exactly as the issue predicted for a change with
      no behavior and no `Name` movement.

```
Stellar mode1 (vs golden): PASS          Stellar mode2 (resume cache hits):  PASS
Stellar mode3 (HPC chain==straight): PASS Stellar mode2 (resume==straight):   PASS
Stellar mode4 (warm re-run all cached): PASS
Stellar mode5 (rehydrate entered + cache hits): PASS
Stellar mode5 (rehydrate==straight): PASS
```

Modes 4 and 5 are the legs that read the `[TASK]` log tokens and assert
`-ExpectRan` / `-ExpectSkipped`, so they are what would have caught an accidental
`Name` change. Mode 4 completing in 0.1s ("a fully cached run does no work") is
the positive evidence that every existing `.osprey.task` sidecar still matched -
a moved stamp would have forced a recompute here instead.

The gate reports 1 required resident token (#4536 resume-survivor-handoff). That
is pre-existing, has its own open issue, and is untouched by this change.

Re-run AFTER the code-review fixes (which touched `regression.ps1` itself, so the
first green no longer covered the tree): all 7 legs PASS again, blib identical at
25,407,488, and mode 5 still enters its rehydrate arm - confirming the renamed
`$firstPassFdrRehydrateMarker` still matches the log line it asserts on.

## Code review (`/code-review max`) - findings and what came of them

The review earned its keep. Verified each finding against the code rather than
auto-applying; all the ones below reproduced.

**Two defects introduced by the sweep:**
* Dropped `deterministically` from the `--input-scores` help text, and the loss
  shipped in the generated `Documentation/Help/en/CommandLine.html`. Restored.
* `$firstJoinRehydrateMarker` became `$FirstPassFDRRehydrateMarker`. Root cause:
  the first PowerShell pass used `-replace`, which is case-INSENSITIVE in
  PowerShell, so it matched a camelCase identifier. Swept for other casualties -
  exactly one, now `$firstPassFdrRehydrateMarker` at both sites.

**Wrong task named.** The systematic error: substituting a task NAME where the
original word named a MODE, a PATH, or a node ROLE. Fixed by naming the actual
thing (`reconciled-input path`, `--input-scores validator`), not another task:
`Pass2FdrSidecar` x4 operator messages, `PipelineContext` (SecondPassFdrTask
publishes nothing; only PerFileRescoreTask publishes RescoredEntries),
`PerFileScoringTask` ("the SecondPassFDR lean path" is impossible -
`NeedsResidentPool` is true whenever `ExpectReconciledInput`).

**Incomplete sweep.** The first pass globbed only `.cs/.ps1/.md`, so it missed
`Osprey-workflow.html` - the shipped diagram that the renamed classes' XML docs
and the CLI help both link to - plus the `.csproj`, `1st-join` in
`regression.ps1`, and a `MergeNode / SecondPassFDR` pair in `docs/13` that
collapsed to `SecondPassFDR / SecondPassFDR`.

**Two false claims written into the docs**: that the enum values are "the same
names in PascalCase" (false for `PerFileRescore`), and that the `Fdr`/`FDR` split
is "what C# PascalCase requires" - `namespace pwiz.Osprey.FDR` exists, so all-caps
is legal; it is this codebase's TYPE convention (`FdrEntry`, `FdrController`).
Also fixed `docs/DIVERGENCES.md`, which still asserted "enum/classes by join
topology" and contradicted the new note in `docs/15`.

**Correctly refuted, recorded so it is not re-raised**: `ResidentPaths.HPC_MERGE
= "hpc-merge"` must NOT be renamed - it is an `OSPREY_ALLOW_UNFIXED_RESIDENT`
token value, pinned by `ResidentPoolGuardTest` precisely to stop a silent rename.

## The "flaky" test was not flaky

`TestCommandLineHelpDocumentation` regenerates
`Documentation/Help/en/CommandLine.html` from the CLI help text, fails when it is
stale, and WRITES the file - so it passes on the next run. The sweep changed the
help text, which is why it failed once and never again. It reproduced exactly when
the help text was edited a second time. Any future change to `OspreyCommandArgs`
help prose will do the same: run the tests twice and commit the regenerated HTML.

## A self-inflicted corruption, caught and repaired

While applying review fixes, a PowerShell call written as
`Repl 'file' 'the' + [char]10 + '...'` was parsed as positional arguments, so the
helper received `$from='the'`, `$to='+'` - replacing every "the" in
`RegressionData.ps1` and every "unless" in `PerFileScoringTask.cs`, including
inverting "refused unless named" to "refused + named". **Build, all 576 tests, and
ReSharper passed with the corruption in place**, because it was confined to
comments. It was caught by a post-edit diff scan, both files were reverted to the
committed state, and each edit re-applied individually. Lesson: green gates do not
cover comment prose - diff-read every scripted bulk edit.

## ai/ side: two live defects found and fixed

Sweeping `ai/scripts/Osprey/` turned up the issue's own failure mode still live in
two harnesses - both fixed here:

* `Compare-StraightThroughResume-CSharp.ps1:141` matched resume sidecars with
  `-like '*MergeNode*'`. Sidecars are named `*.SecondPassFDR.osprey.task`, so that
  clause matched zero files - exactly the bug the issue cites, in a second copy.
  (The companion `'output.blib*'` clause did catch the stamp, so the harness still
  worked; the clause was dead rather than damaging.)
* `Test-Snapshot.ps1` and `Compare-Stage7-Rehydration-Strict-CSharp.ps1` invoked
  `--task MergeNode` / `--task FirstJoin`. `Program.ResolveTask` accepts only
  `PerFileScoring | FirstPassFDR | PerFileRescoring | SecondPassFDR | SpectraCache`,
  so those invocations fail with "unknown task". Broken before this change, not by it.

## Regression Test

- **Test name**: none added - see rationale
- **Test project**: n/a
- **Fails on master**: n/a
- **Passes on fix**: `regression.ps1 -Dataset Stellar`, all 7 legs, blib
  byte-identical at 25,407,488 across all four run modes

**Why no new test.** This is a pure rename with no behavior change, so there is no
red->green test to write for it. The verification is the inverse - identical output
before and after - which the Stellar gate provides, and modes 4/5 specifically
assert the `[TASK]` tokens and sidecar cache hits that a botched rename would break.

**A durable guard was considered and deliberately NOT added.** The obvious one is a
unit assertion pinning each task class's `Name` to its literal, so a future
class/Name divergence fails a test instead of relying on a comment. It was rejected
because after this change it would assert almost nothing: the failure the issue
describes was a SEPARATE consumer (a PowerShell glob) keying off class names, and a
C# test comparing `FirstPassFdrTask.Name` to `"FirstPassFDR"` cannot see that
consumer at all. The real protection is that the two strings are now the same word,
plus the existing hard-failure guards in `Invoke-ResumeInvalidation` /
`Invoke-SecondPassOnlyInvalidation`, which throw when their patterns match zero
files - that is the check that actually catches a drifted token, and it already
exists. Worth revisiting if a third consumer ever grows its own copy.

## Progress Log

### 2026-08-06 - Session Start

Starting work on this issue. Branch created off current master; pwiz checkout
`C:\proj\pwiz`.

### 2026-08-06 - Merged

PR #4540 merged as commit `dce8841689`, closing #4535. Everything in the issue's
scope shipped, plus two agreed extensions: the `HpcTask` enum members were renamed
alongside the classes (they were a third divergent name set), and the informal
prose - "the join", "the merge node", "first join" - was eliminated rather than
just the two class names. Nothing was deferred.

Verification, in the order it was run: local build + 576/576 tests + ReSharper
0/0; `regression.ps1 -Dataset Stellar` green (7/7 legs, blib byte-identical at
25,407,488 across all four run modes); `/code-review max`; the gate re-run green
after the review fixes; TeamCity Perf/Regression on `pull/4540` SUCCESS, which is
what added **Astral** and the perf leg that the local Stellar-only runs could not
reach; then 17/17 PR checks.

Two mentions of the retired names survive ON PURPOSE, in `docs/15-hpc-scoring-split.md`
and `Regression/RegressionData.ps1` - both passages are about the rename itself and
the second's justification IS the original incident, so scrubbing them would leave a
guard with no stated reason.

Merge friction worth recording: branch protection refused the squash because the
head was behind master. The branch was updated by MERGE (not rebase - the PR had
been reviewed), which pulled in exactly one line of #4541 in a Skyline UI file.
`git diff edf6099cd7 HEAD -- pwiz_tools/Osprey` was empty, so the hour-long
Perf/Regression gate was deliberately NOT re-run: the tree it validated had not
changed by a byte. Re-running it per-commit is what previously produced a queue
that had to be hand-cancelled.

No follow-up issues filed. The one durable idea left on the table is a
`CanonicalPipeline`-walking round-trip test asserting `Name` <-> `ResolveTask` <->
`TaskCliName`, argued for by `/code-review` and not adopted here; the reasoning for
and against is under "Regression Test" above if anyone wants to revisit it.
