# Rename Osprey task classes to match their user-facing task Names

## Branch Information
- **Branch**: `Skyline/work/20260806_osprey_task_class_rename`
- **Base**: `master`
- **Created**: 2026-08-06
- **Status**: In Progress
- **GitHub Issue**: [#4535](https://github.com/ProteoWizard/pwiz/issues/4535)
- **Module**: `osprey`
- **Labels**: `osprey`, `tech-debt`
- **PR**: (pending)
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
- [ ] `regression.ps1 -Dataset Stellar` (modes 4 and 5 read the `[TASK]` log tokens,
      so they are the legs that would catch an accidental `Name` change)

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

- **Test name**: (filled in once written)
- **Test project**: Osprey unit tests / regression.ps1
- **Fails on master**: (n/a - see note)
- **Passes on fix**: (pending)

Note: this is a pure rename with no behavior change, so there is no red->green test
to write for the rename itself. The verification is the inverse: `regression.ps1`
output must be byte-identical green before and after, and any diff means the rename
moved something it should not have. If a cheap unit assertion can pin each task
class's `Name` to its expected literal (making a future class/Name divergence a test
failure rather than a comment), add it - that is the durable guard the issue is
really asking for. Decide and record the outcome here.

## Progress Log

### 2026-08-06 - Session Start

Starting work on this issue. Branch created off current master; pwiz checkout
`C:\proj\pwiz`.
