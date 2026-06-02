---
name: osprey-development
description: ALWAYS load when working in pwiz_tools/OspreySharp (C# port), on maccoss/osprey (Rust), or debugging OspreySharp-Rust parity issues.
---

# Osprey Development Context

Two trees, two convention sets:

- **OspreySharp** (`C:\proj\pwiz\pwiz_tools\OspreySharp`) - the C#
  implementation, now the path forward for the Osprey DIA proteomics
  search tool. Lives in the pwiz repo. **Follows Skyline conventions
  in full.**
- **Rust osprey** (`C:\proj\osprey` -> `maccoss/osprey`) - the
  original Rust implementation. Maintained for cross-impl parity
  validation against OspreySharp. Follows upstream osprey
  conventions, NOT Skyline's.

Which convention set applies depends on which tree you are touching.
The sections below are organized along that split.

## OspreySharp (C#) - Skyline Conventions Apply

When working in `pwiz_tools/OspreySharp`, all Skyline development
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
   `Co-Authored-By: Claude` line). OspreySharp commits go through the
   pwiz repo workflow (feature branches under `Skyline/work/...`).
4. **`ai/TESTING.md`** - translation-proof tests, consolidated
   `[TestMethod]` structure, `AssertEx` over `Assert`.

Cross-impl parity work additionally needs:
- **`ai/docs/osprey-development-guide.md`** - steel-thread parity
  doctrine, Stage 1-5 diagnostic dumps, `Compare-Percolator.ps1`,
  bisection methodology.
- **`ai/docs/osprey-crossimpl-validation-guide.md`** - validation
  guide for cross-impl test runs.

OspreySharp and cross-impl TODOs live at
`ai/todos/active/TODO-*_osprey_sharp.md`.

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
  Rust tree. (CRITICAL-RULES.md's CRLF rule is Skyline / OspreySharp
  only.)
- **Upstream-style commit prose**, no Skyline 10-line cap, no
  `Co-Authored-By: Claude` unless maintainer opts in.
- **Parity gate after scoring/calibration changes**: Stellar +
  Astral `Test-Features.ps1` must pass at 1e-6 per PIN feature.

Rust-only TODOs live at `ai/todos/active/TODO-OR-*.md`
(`OR` = osprey rust).

## Continuing Work on a TODO

1. Call `mcp__status__get_project_status()` to see branch state
   across `C:\proj\osprey` and the relevant pwiz worktree.
2. Rust-only TODOs: `ai/todos/active/TODO-OR-*.md`.
3. OspreySharp and cross-impl TODOs:
   `ai/todos/active/TODO-*_osprey_sharp.md`.

## Before You Commit

- **OspreySharp**: run
  `pwsh -File ./ai/scripts/OspreySharp/Build-OspreySharp.ps1 -RunTests -Summary`
  (mirrors the Skyline pre-commit gate for the OspreySharp solution).
- **Rust osprey**: run
  `pwsh -File ./ai/scripts/OspreySharp/Build-OspreyRust.ps1 -Fmt -Clippy -RunTests`
  (mirrors maccoss/osprey CI gates).
- **After scoring or calibration changes (either side)**: run
  `Test-Features.ps1` on Stellar + Astral; 1e-6 per PIN feature must
  hold.

## Key Repositories

- `C:\proj\pwiz\pwiz_tools\OspreySharp` - the C# implementation.
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
and apply to OspreySharp work as well (commit, TODO, build wrappers,
review). They do NOT apply to Rust osprey work - the Rust side does
not use the Skyline TODO system or commit format.
