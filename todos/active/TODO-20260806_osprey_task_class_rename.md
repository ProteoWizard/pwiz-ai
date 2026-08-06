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

## Tasks

- [ ] Rename `FirstJoinTask` -> `FirstPassFdrTask` (file, class, all references)
- [ ] Rename `MergeNodeTask` -> `SecondPassFdrTask` (file, class, all references)
- [ ] Confirm the `Name` property values are UNCHANGED (`FirstPassFDR`,
      `SecondPassFDR`) - the stamps and logs must not move, or every existing
      `.osprey.task` sidecar on disk is invalidated and `regression.ps1`'s cache
      assertions break
- [ ] Sweep comments and docs that say "the join" / "the merge node" / "first join"
      and replace with the task Name, keeping the class name as a parenthetical
      where it helps. Known sites: `regression.ps1` (modes 3 and 4 blocks),
      `Regression/RegressionData.ps1`, `Regression/README.md`,
      `ai/docs/osprey-development-guide.md`
- [ ] Check the `docs/` numbered design notes for the same terminology
- [ ] `Build-Osprey -RunTests -RunInspection`
- [ ] `regression.ps1 -Dataset Stellar` (modes 4 and 5 read the `[TASK]` log tokens,
      so they are the legs that would catch an accidental `Name` change)

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
