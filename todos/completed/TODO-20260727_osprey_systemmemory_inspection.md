# Osprey: SystemMemory.cs reddens the local -RunInspection gate

## Branch Information
- **Branch**: `Skyline/work/20260727_osprey_systemmemory_inspection`
- **Base**: `master`
- **Created**: 2026-07-27
- **Status**: Complete - fixed in pwiz-ai tooling; no pwiz source change
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

## Source-level suppression is a DEAD END (measured, N=20)

The Skyline `MemoryInfo.cs` pattern below was applied and measured properly rather
than eyeballed on one run:

- `#pragma warning disable 649` around the 8 unassigned fields
- `// ReSharper disable once NotAccessedField.Local` directly above `dwLength`

Result: **4/20 RED (20%) - still flaking**, and the red runs still reported all 9,
including the 8 `UnassignedField.Compiler` the *compiler* pragma was supposed to
eliminate. So the racing context drops even a compiler `#pragma`, not just
ReSharper comment forms. Source change reverted; the file stays as-is on master.

This is the third suppression form to fail (region comments, `[SuppressMessage]`
attributes, compiler pragmas), which is consistent: the problem is not the form,
it is that the suppression pass is skipped entirely on a racing run.

## Working hypothesis (superseded - kept for the record)

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

- [x] Reproduce: confirmed 9 warnings via the gate, then built a repeat-run harness
- [x] Measure the flake rate instead of trusting a single run (pooled 20/43 RED)
- [x] Isolate the mechanism (multi-TFM suppression race; probe experiment)
- [x] Test the `MemoryInfo.cs` suppression pattern properly - REJECTED, 4/20 still red
- [x] Find a deterministic knob (TFM pin 0/30, `--jobs=1` 0/30)
- [x] Fix the gate: one inspectcode pass per target framework, results unioned
- [x] Negative control: gate still catches real warnings in BOTH branches
- [x] Validate at solution scope (0/10) and end-to-end through the real script
- [ ] Land on pwiz-ai master and close the issue

## The fix (landed in pwiz-ai, NOT pwiz)

`ai/scripts/Osprey/Build-Osprey.ps1` now runs `jb inspectcode` **once per target
framework** (`--target-framework=net472`, then `net8.0`) and unions the two result
sets, de-duplicating on file/line/rule/message. Each pass then sees exactly one
preprocessor context, so there is no cross-context merge to race.

`SystemMemory.cs` is unchanged - **no pwiz source change was needed**, so the pwiz
feature branch was discarded and the issue is closed by a pwiz-ai commit.

### Why per-framework and not `--jobs=1`

Both measured 0/30. Per-framework wins on cost, because it keeps inspectcode's
parallelism within each pass:

| | project scope | solution scope |
|---|---|---|
| unpinned (today, flaky) | 26s | 115s |
| `--jobs=1` | 41s | not measured, strictly worse |
| per-framework pass | 16s | 52s (so ~104s for both) |

Two per-framework passes cost about the same as today's single all-frameworks pass,
where `--jobs=1` serializes everything and is ~1.6x slower per pass. Per-framework
is also deterministic *by construction* rather than by making a race window small.

### Validation

- **Negative control (the important one)**: with a deliberate unused local added to
  *each* branch of the `#if`, the real gate reported **2 warnings** - one from the
  net472 pass, one from the net8.0 pass - and failed. So the union is faithful, both
  passes are live, and the green is not "inspected nothing".
- **End-to-end**: `Build-Osprey.ps1 -Configuration Debug -RunInspection` -> 0
  warnings, "Code inspection passed", 139s.
- **Solution scope, N=10**: 0/10 red.
- Coverage is preserved: a pinned net472 run reports the netfx branch's warning, a
  pinned net8.0 run reports the net8.0 branch's, and their union equals what an
  all-frameworks pass reports.

### Scope of the exposure

`SystemMemory.cs` is currently the *only* Osprey file with both inline ReSharper
suppressions and `#if` blocks, so it is the only file that can flake today. The
mechanism is general, though - any future inline suppression inside a conditional
block would hit it - which is the argument for fixing the gate rather than the file.

## Regression Test

- **Test name**: `ai/.tmp/Measure-InspectionFlake.ps1` (repeat-run harness) plus the
  gate itself, `Build-Osprey.ps1 -RunInspection`
- **Test project**: n/a - inspection gate, not an MSTest
- **Fails on master**: yes - 20/43 RED pooled, project scope, unmodified source
- **Passes on fix**: yes - 0/30 project scope, 0/10 solution scope, plus a green
  end-to-end gate run and a negative control that correctly fails

No unit test can cover this: the defect is in what the `jb inspectcode` CLI reports
about the source, not in runtime behavior. The verifier is therefore statistical,
and that is the real lesson of this issue - a single green run against a ~47% coin
is worthless, which is exactly how three earlier "fixes" were wrongly accepted or
wrongly rejected here.

**The harness is deliberately left in `ai/.tmp/` (gitignored), not committed.** It
is a diagnostic for a tooling bug that is now fixed, not a standing gate; anyone
re-opening this should recreate or ask for it rather than maintain it. If the flake
ever returns, the reproduction recipe is: run the inspection N>=20 times on
unmodified source and count, never once.

## Root cause (measured 2026-07-27)

**It is a race between the two target-framework analysis contexts, not a bad
suppression form.** Osprey multi-targets `net472;net8.0`, so inspectcode analyzes
`SystemMemory.cs` twice, once per TFM. The 9 issues are reported only under
`TargetFramework="net472"` (the `#if NETFRAMEWORK` branch). Whether the inline
`// ReSharper disable` region gets applied to that result set is nondeterministic.

Measured with `ai/.tmp/Measure-InspectionFlake.ps1` (repeat-run harness, project
scope, ~20-30s/run, jb 2026.1.4), all on **unmodified master source**:

| Arm | Result |
|---|---|
| unpinned, batch 1 (N=20) | 5/20 RED (25%) |
| unpinned, batch 2 (N=20) | 13/20 RED (65%) |
| unpinned, batch 0 (N=3) | 2/3 RED |
| **pooled baseline** | **20/43 RED (~47%)** |
| `--properties=TargetFramework=net472` (N=10) | 0/10 RED |
| `--jobs=1` (N=10) | 0/10 RED |
| **TFM pinned, confirmation (N=30)** | **0/30 RED** (median 16s/run) |
| **`--jobs=1`, confirmation (N=30)** | **0/30 RED** (median 41s/run) |

At the pooled baseline rate, 30 consecutive greens has probability
`0.53^30 ~= 3e-9`, so both are deterministic rather than lucky.

Note both were measured at *project* scope; the gate runs *solution* scope, so the
chosen fix has to be re-validated there before it ships (a fix validated only on a
proxy is not validated).

Two facts that pin the mechanism down:

1. **Always exactly 0 or 9, never partial.** The suppression region is applied
   wholesale or not at all - a binary race, not a per-field analysis difference.
2. **Probe experiment**: adding a deliberate unused local to *each* preprocessor
   branch showed both probes reported on **every** run (`net472x1,net8.0x1`),
   while the 9 came and went on top (4/6 runs). So both TFM contexts are always
   analyzed - nothing is being skipped. Only *suppression application* races.
   The probes also prove a pinned run really analyzes the file (a pinned net472
   run reports `probeUnusedNetFx`, a pinned net8.0 run reports `probeUnusedNet80`),
   so a pinned green is a real green, not "analyzed nothing".

Confirmed by the CLI's own documented defaults (`jb inspectcode --help`):

- `--jobs (-j)`: "Run up to N jobs in parallel. **0 means as many as possible
  (default: 0)**" - the gate runs at maximum parallelism.
- `--target-framework (-tf)`: "Analyse for a specific framework ...
  **(default: all frameworks)**" - so an unpinned run does analyze both.

**The flake rate is unstable (25% -> 65% between identical batches) and moves with
machine load.** This has a sharp consequence for this issue's history: every prior
conclusion in the thread was a single-run or 5-run observation against a ~50% coin,
so none of them are conclusive - neither "`[SuppressMessage]` did not work", nor
"jb 2026.1.4 fixed it (5/5 clean)", nor "2026.1.4 did not fix it". They are all
consistent with pure noise. Any claim here needs an N and a same-window control.

## Progress Log

### 2026-07-27 - Session Start

Starting work on this issue. Branch created in the `pwiz-work1` worktree; found the
Skyline `MemoryInfo.cs` precedent above as the leading candidate fix.

### 2026-07-27 - Root cause measured

Built the repeat-run harness first (see Root cause above) because the issue's own
history shows single-run evidence is worthless here. Reproduced, quantified, and
isolated the mechanism to the multi-TFM suppression race. Both a TFM pin and
`--jobs=1` suppressed it in N=10 screens; verifying candidates at higher N with
same-window controls before claiming anything.

### 2026-07-27 - Fixed and validated

Confirmed both knobs at N=30, chose the per-framework pass on cost grounds, and
changed `Build-Osprey.ps1` to inspect once per TFM and union the results. Verified
with a negative control (probes in both `#if` branches are caught and fail the
gate), a green end-to-end run, and 0/10 at solution scope. Also corrected
`PRE-COMMIT.md`, which claimed the inspection took ~20 seconds and the whole gate
under 30 - it was already ~115s before this change and is ~2-3 minutes now.

The pwiz branch `Skyline/work/20260727_osprey_systemmemory_inspection` was created
before the root cause was known and ends up empty; deleted rather than merged.
