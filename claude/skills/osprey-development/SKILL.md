---
name: osprey-development
description: ALWAYS load when working in pwiz_tools/Osprey (C# port), on maccoss/osprey (Rust), or debugging Osprey-Rust parity issues.
---

# Osprey Development Context

Two trees, two convention sets:

- **Osprey** (`C:\proj\pwiz\pwiz_tools\Osprey`) - the C#
  implementation, now the path forward for the Osprey DIA proteomics
  search tool. Lives in the pwiz repo. **Follows Skyline conventions
  in full.**
- **Rust osprey** (`C:\proj\osprey` -> `maccoss/osprey`) - the
  original Rust implementation. Maintained for cross-impl parity
  validation against Osprey. Follows upstream osprey
  conventions, NOT Skyline's.

Which convention set applies depends on which tree you are touching.
The sections below are organized along that split.

## Osprey (C#) - Skyline Conventions Apply

When working in `pwiz_tools/Osprey`, all Skyline development
rules apply. Read the same files the `/skyline-development` skill
points at:

1. **`ai/CRITICAL-RULES.md`** - absolute constraints: NO async/await,
   resource strings for user-facing text, CRLF line endings,
   `_camelCase` private fields, helpers AFTER public methods that use
   them.
2. **`ai/STYLEGUIDE.md`** - C# coding conventions: file headers with
   AI attribution, using-directive ordering, `new[] { ... }` inferred
   array literals, control-flow rules.
3. **`ai/WORKFLOW.md`** - git workflow, TODO system, commit message
   format (past-tense title, `* ` bullets, `See ai/todos/...`,
   `Co-Authored-By: Claude` line). Osprey commits go through the
   pwiz repo workflow (feature branches under `Skyline/work/...`).
4. **`ai/TESTING.md`** - translation-proof tests, consolidated
   `[TestMethod]` structure, `AssertEx` over `Assert`.

Cross-impl parity work additionally needs:
- **`ai/docs/osprey-development-guide.md`** - steel-thread parity
  doctrine, Stage 1-5 diagnostic dumps, bisection methodology, and the
  **FDRBench entrapment validation** section (the independent
  correctness oracle -- read it before any change that moves the
  discovery set or reported q-values; the oracle wins over parity).
- **`ai/docs/osprey-crossimpl-validation-guide.md`** - validation
  guide for cross-impl test runs.
- **`ai/scripts/Osprey/Compare/README.md`** - the cross-impl
  bridge scripts (`Compare-EndToEnd-Crossimpl.ps1`), needed only for
  the rare "did this drift us from Rust?" check. Older per-stage
  comparators (`Compare-Percolator.ps1`, `Test-Features.ps1`) are
  archived under `Compare/archive/`.

Osprey and cross-impl TODOs live at
`ai/todos/active/TODO-*_osprey*.md`.

## Rust osprey - Upstream Conventions Apply

When working in `C:\proj\osprey`, Skyline rules do NOT apply. Read:

1. **`ai/docs/osprey-development-guide.md`** - the full Rust-side
   development guide. Workspace layout, build wrappers, HPC CLI
   flags, env-var reference, bisection methodology, determinism
   patterns, steel-thread parity doctrine, commit/PR conventions
   vs. Skyline.
2. **`C:\proj\osprey\CLAUDE.md`** - Rust-side project overview:
   architecture, CI requirements, critical invariants (fold splits
   keep target-decoy pairs together; protein FDR uses raw SVM score;
   etc.).
3. **`ai/WORKFLOW.md`** - read ONLY to understand what *differs* on
   the Rust side. Skyline's commit format, branch naming, and TODO
   conventions do NOT apply to maccoss/osprey work.

Rust-side key constraints:
- **`cargo fmt --check` + `clippy -D warnings` + `cargo test`** all
  gate the CI. Test modules must be the last item in their file
  (`clippy::items-after-test-module`).
- **LF line endings** - not CRLF. Do NOT run `fix-crlf.ps1` on the
  Rust tree. (CRITICAL-RULES.md's CRLF rule is Skyline / Osprey
  only.)
- **Upstream-style commit prose**, no Skyline 10-line cap, no
  `Co-Authored-By: Claude` unless maintainer opts in.
- **Parity gate after scoring/calibration changes**: confirm
  Osprey still matches Rust with the cross-impl gate
  `ai/scripts/Osprey/Compare/Compare-EndToEnd-Crossimpl.ps1`
  on Stellar + Astral; see `Compare/README.md` for the tolerance.
  (The former per-PIN-feature `Test-Features.ps1` is archived under
  `Compare/archive/`.)

Rust-only TODOs live at `ai/todos/active/TODO-OR-*.md`
(`OR` = osprey rust).

## Continuing Work on a TODO

1. Call `mcp__status__get_project_status()` to see branch state
   across `C:\proj\osprey` and the relevant pwiz worktree.
2. Rust-only TODOs: `ai/todos/active/TODO-OR-*.md`.
3. Osprey and cross-impl TODOs:
   `ai/todos/active/TODO-*_osprey*.md`.

## Build, Test, and Commit

You can and should build, test, and run Osprey yourself - the wrapper
scripts in `ai/scripts/Osprey/` exist for exactly that. Do not ask the
developer to build what you can run. `ai/scripts/Osprey/PRE-COMMIT.md`
and `README.md` are the authoritative gate references.

- **Osprey pre-commit** (build + tests + zero-warning inspection, ~30s):
  `pwsh -File ./ai/scripts/Osprey/Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`
- **C#-side refactor / algorithm-affecting changes** (scoring, calibration,
  LOESS/KDE, SVM, FDR, decoy generation, blib) and every OOP/structural
  refactor: pass two standing gates.
  - **Correctness** (output unchanged): the self-contained straight-through
    regression vs a committed C# golden + a resume leg, both at 1e-9 (no Rust
    checkout):
    `pwsh -File ./pwiz_tools/Osprey/regression.ps1 -Dataset Stellar`
    (`-Dataset All` before a behavior/perf-sensitive merge). Also the overnight
    TeamCity gate.
  - **Performance** (speed not degraded): a same-session A/B of the branch vs the
    pinned `pwiz-perfbase` baseline worktree (3-rep median, fails only on a real
    regression with non-overlapping bands):
    `pwsh -File ./ai/scripts/Osprey/Test-PerfGate.ps1 -Dataset Stellar`.
  `Test-Full-Regression.ps1` / `Test-Snapshot.ps1` are the stage-isolated
  bisection drill-down for WHERE a red correctness gate diverged, not the
  first-line gate. See `PRE-COMMIT.md`.
- **Rust osprey**:
  `pwsh -File ./ai/scripts/Osprey/Compare/Build-OspreyRust.ps1 -Fmt -Clippy -RunTests`
  (mirrors maccoss/osprey CI gates).
- **Cross-impl drift check** (rare; "did we drift from Rust?", e.g. after porting
  a Rust algorithm change):
  `pwsh -File ./ai/scripts/Osprey/Compare/Compare-EndToEnd-Crossimpl.ps1 -Files All`
  on Stellar + Astral (re-runs Rust). This replaces the old `-SkipRust` routine
  use, which `regression.ps1` superseded. See `Compare/README.md`.

## TeamCity Perf/Regression gate (manual - trigger it yourself)

The **Osprey Windows .NET Perf/Regression Tests** config
(`ProteoWizard_OspreyWindowsNetPerfRegressionTests`) runs `regression.ps1`
mode1/2/3 on **Stellar AND Astral** (straight-through, HPC chain, resume) plus a
perf leg - about an hour. It is deliberately **manual / overnight**, NOT triggered
on every commit or push, so opening or pushing a PR does **not** start it. When a
PR is otherwise ready (self-review clean, the `Osprey Windows .NET` unit build
green), it must run before human review / merge.

**First check whether you can actually trigger it.** The TeamCity MCP server is not
configured on every machine -- on Mike's it is absent (`~/.claude.json` defines only
`labkey`), and `ai/claude/settings.json` pre-approves three read-only teamcity tools
(`get_build_log`, `get_build_status`, `search_builds`) for a server that does not exist.
`trigger_build` is not even in that allow-list. If `mcp__teamcity__*` does not resolve,
say so plainly and hand the trigger to a maintainer rather than claiming the gate is
pending on nothing.

Where the MCP *is* connected, trigger via:
`mcp__teamcity__trigger_build(build_type_id="ProteoWizard_OspreyWindowsNetPerfRegressionTests", branch="pull/<N>")`

**Always use `branch="pull/<N>"` (the PR number), NEVER the named
`Skyline/work/...` branch.** The Osprey configs watch PR refs
(`refs/pull/<N>/head`); a named branch is not recognized and TeamCity **silently
falls back to building master** - a green result that tested the wrong commit. (The
MCP now refuses a named branch for Osprey configs and tells you to use `pull/<N>`.)
The local Stellar gates (`regression.ps1 -Dataset Stellar` +
`Compare-EndToEnd-Crossimpl`) already cover Stellar; this CI gate's unique value is
the **Astral** legs, which are too slow to run locally each session.

## Key Repositories

- `C:\proj\pwiz\pwiz_tools\Osprey` - the C# implementation.
  Lives in `ProteoWizard/pwiz`. Branches and PRs follow Skyline
  conventions (`Skyline/work/YYYYMMDD_*`, past-tense title,
  Co-Authored-By).
- `C:\proj\osprey` -> `maccoss/osprey` (SSH). Primary Rust repo. New
  Rust branches and PRs go here
  (`gh pr create --repo maccoss/osprey`).
- `C:\proj\osprey-fork` -> `brendanx67/osprey`. Retired; do not
  extend.

## Slash Commands Available

Type `/pw-` to see project-wide commands. Most are Skyline-focused
and apply to Osprey work as well (commit, TODO, build wrappers,
review). They do NOT apply to Rust osprey work - the Rust side does
not use the Skyline TODO system or commit format.
