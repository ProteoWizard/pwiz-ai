# Osprey: SystemMemory.cs reddens the local -RunInspection gate

## Branch Information
- **Branch**: `Skyline/work/20260727_osprey_systemmemory_inspection`
- **Base**: `master`
- **Created**: 2026-07-27
- **Status**: In Progress
- **Worktree**: `C:\proj\pwiz-work1`
- **GitHub Issue**: [#4379](https://github.com/ProteoWizard/pwiz/issues/4379)
- **PR**: (pending)
- **Requester/Reporter**: none (filed by Mike, an Osprey developer - no credit line per version-control-guide "Crediting Reporters and Requesters")

## Objective

`Build-Osprey.ps1 -RunInspection` (the local zero-warning pre-commit gate) reports
9 warnings in `pwiz_tools/Osprey/Osprey.Core/SystemMemory.cs` - 8x
`UnassignedField.Compiler` + 1x `NotAccessedField.Local` - on the P/Invoke
`MEMORYSTATUSEX` class, even though the fields already carry inline
`// ReSharper disable` / `restore` region comments. The ReSharper IDE honors those
comments; the `jb inspectcode` CLI does not. CI is unaffected (TeamCity runs
`regression.ps1`, not InspectCode) - this is a local-gate-only problem.

Make the local gate green without weakening it.

## What has already been tried (from the issue thread)

- `[SuppressMessage("ReSharper", "UnassignedField.Compiler")]` /
  `[SuppressMessage("ReSharper", "NotAccessedField.Local")]` class-level attributes -
  **did not work** (still 9 warnings; reverted).
- Updating the `jb` CLI 2025.3.1 -> 2026.1.4 - **did not work** (still 9 warnings on
  2026-07-08, PR #4394).

## Working hypothesis

Skyline's own `pwiz_tools/Skyline/Util/MemoryInfo.cs` declares a byte-identical
`MEMORYSTATUSEX` and is inspection-clean in a codebase that gates on ReSharper
cleanliness. It suppresses the two inspections *differently*:

- 8 unassigned fields -> **compiler** pragmas `#pragma warning disable 169 / 649`
  (`UnassignedField.Compiler` is the C# compiler's CS0649 surfaced through ReSharper)
- 1 assigned-but-never-read field (`dwLength`) -> `// ReSharper disable once
  NotAccessedField.Local` placed **directly above the declaration** (the `once`
  form, not a `disable`/`restore` region)

The 8+1 split matches the Osprey warning counts exactly. So the likely fix is to
adopt the proven in-repo pattern rather than invent a new one.

## Tasks

- [ ] Reproduce: `Build-Osprey.ps1 -RunInspection` on this branch, unmodified source, clean cache - confirm 9 warnings
- [ ] Apply the `MemoryInfo.cs` suppression pattern to `SystemMemory.cs`
- [ ] Re-run the gate on a clean cache several times - confirm 0 warnings and, given the reported run-to-run flakiness, that it is deterministic
- [ ] Confirm the net472 + net8.0 build still succeeds and the Osprey unit tests pass
- [ ] If the pattern does not green the gate, fall back to a file/inspection-scoped rule in the solution `.DotSettings` and record why

## Regression Test

- **Test name**: `Build-Osprey.ps1 -RunInspection` (the gate itself is the verifier)
- **Test project**: n/a - inspection gate, not an MSTest
- **Fails on master**: (to verify)
- **Passes on fix**: (to verify)

No unit test can cover this: the defect is in what the `jb inspectcode` CLI reports
about the source, not in runtime behavior. The inspection gate is the verifier, and
it must be run red-then-green with a cleared `.inspectcode-cache` on both sides. The
9-vs-0 flakiness reported in the issue means a single green run is NOT sufficient
evidence - repeat runs are required.

## Progress Log

### 2026-07-27 - Session Start

Starting work on this issue. Branch created in the `pwiz-work1` worktree; found the
Skyline `MemoryInfo.cs` precedent above as the leading candidate fix.
