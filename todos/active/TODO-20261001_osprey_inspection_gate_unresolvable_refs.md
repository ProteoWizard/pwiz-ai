# TODO: The Osprey inspection gate reports 427 phantom errors and can never go green

## Branch Information
- **Branch**: not started
- **Base**: `Skyline/work/20260612_net8_port` (PR #4619)
- **Created**: 2026-10-01
- **Status**: Diagnosed, not fixed. Reproduced on the clean tip in two independent worktrees.
- **Module**: `osprey`
- **PR**: none

## The problem

`Build-Osprey.ps1 -RunInspection` always fails:

```
Inspection completed in 162.5s
  Errors:   427
  Warnings: 20
Code inspection FAILED - 447 issue(s) found
```

So the gate the `osprey-development` skill documents as the Osprey pre-commit -

```
pwsh -File ./ai/scripts/Osprey/Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection
```

- **cannot go green in any Osprey worktree today**, on any branch, including an untouched tip.

## It is not caused by any change - verified twice, independently

| where | state | result |
|---|---|---|
| `pwiz-net10b` | clean tip `ed25627d81`, detached, script printed "No modified/added files found" | **427 errors / 20 warnings**, same per-file breakdown |
| `pwiz-net10b` | branch with 1 commit on top | 427 / 20, identical |
| `pwiz-parqread` | rebased branch | 427 / 20 |
| `pwiz-parqread` | same worktree with the commit absent | 427 / 20, identical per-file breakdown |

Branch delta is **zero** in every case, and not one finding sits in a file any of those
branches touched.

## Root cause: unresolved cross-project references, not code defects

All 427 are `CSharpErrors` of the form `Cannot resolve symbol 'X'`:

```
TypeId="CSharpErrors" File="Osprey\OspreyCommandArgs.cs" Line="30" Message="Cannot resolve symbol 'Common'"
TypeId="CSharpErrors" File="Osprey\OspreyCommandArgs.cs" Line="66" Message="Cannot resolve symbol 'ArgUsage'"
TypeId="CSharpErrors" File="Osprey\OspreyCommandArgs.cs" Line="92" Message="Cannot resolve symbol 'ShortName'"
```

and `jb inspectcode` prints, for roughly seventeen projects, before it starts:

```
Referenced project 'CommonUtil' not found in the solution, it's output assembly wasn't found either.
Warning: Unable to resolve reference Common: Project 'Common' or its output assembly was not found
... (ProteowizardWrapper, Analysis, IdentData, MsData, Util, Agilent, Bruker, Vendor.Common,
     Mobilion, Sciex, Shimadzu, Thermo, UIMF, UNIFI, Waters, ...)
```

The symbols it cannot resolve live in exactly those projects (`ArgUsage` / `ShortName` are
`pwiz.CommonUtil`). **The compiler builds the same tree clean** - `Build succeeded`, no errors -
so these are the inspector failing to load references, not real defects.

The concentration matches: the top files are the ones that lean hardest on CommonUtil -
`OspreyCommandArgs.cs` (117), `OspreyCommandArgsTests.cs` (117), `SubsetPipelineTest.cs` (72),
`ProgramTests.cs` (55), `CommandLineErrorTest.cs` (41), `Program.cs` (20).

The 20 warnings are real but trivial and also pre-existing: 11 `RedundantUsingDirective`,
8 `InvalidXmlDocComment`, 1 `RedundantExplicitArrayCreation`.

## Why it matters

The failure mode is the expensive kind: the gate is **red for a reason that has nothing to do
with your change**, so it carries no signal, and a session that trusts it spends its time
chasing 427 phantoms. It also means nobody can satisfy the documented pre-commit gate, so in
practice the inspection leg gets skipped - which is how the 20 genuine warnings survive.

## What to investigate

1. `Osprey.sln` does not appear to carry the pwiz-sharp / `CommonUtil` / `ProteowizardWrapper`
   projects in a form `jb inspectcode` can resolve, even though MSBuild resolves them. Compare
   what the solution lists against what the `.csproj` files reference.
2. `Build-Osprey.ps1` runs the inspection per declared target framework. Check whether it
   points `jb inspectcode` at the solution without first ensuring the referenced projects'
   output assemblies exist where the inspector looks (the message offers both alternatives:
   "Project 'X' or its output assembly was not found").
3. Decide the contract: either the inspection must resolve those references, or it should be
   scoped to the projects it CAN resolve and the gate's documentation updated to say so. A gate
   that cannot pass is worse than no gate, because it trains people to ignore a red.
4. While in there, clear the 20 real warnings so the leg has a clean baseline to defend.

## Evidence on disk

`ai/.tmp/OspreyInspect-pwiz-net10b.net10.0.xml` holds the full issue list from the clean-tip
run (it is overwritten per run, so re-run to regenerate). The session log with both worktrees'
numbers side by side is in `ai/.tmp/night-session-budget.md` (2026-09-30/10-01 night session).
