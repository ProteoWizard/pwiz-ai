---
name: osprey-development
description: ALWAYS load when working on Rust osprey (maccoss/osprey checkout at C:\proj\osprey), opening PRs against maccoss/osprey, touching OspreySharp C# code for cross-impl parity, or debugging Rust-vs-OspreySharp divergence.
---

# Osprey (Rust) Development Context

When working on any Rust osprey task — or on the cross-impl parity
harness between Rust osprey and the OspreySharp C# port — consult
these documentation files for essential context.

## Core Files (Read for Every Task)

1. **`ai/docs/osprey-development-guide.md`** — the full development
   guide. Workspace layout, build wrappers, HPC CLI flags, env-var
   reference, bisection methodology, determinism patterns,
   steel-thread parity doctrine, commit/PR conventions vs. Skyline.
2. **`C:\proj\osprey\CLAUDE.md`** — Rust-side project overview:
   architecture, CI requirements, critical invariants (fold splits
   keep target-decoy pairs together; protein FDR uses raw SVM score;
   etc.).
3. **`ai/WORKFLOW.md`** — Skyline conventions. Useful ONLY to
   understand what *differs* on the Rust side (different product,
   different rules — see the guide for the delta table).

## Continuing Work on a TODO

1. Call `mcp__status__get_project_status()` to see branch state
   across `C:\proj\osprey` and the relevant pwiz worktree.
2. osprey-Rust-only TODOs live at `ai/todos/active/TODO-OR-*.md`
   (`OR` = osprey rust).
3. OspreySharp + cross-impl TODOs live at
   `ai/todos/active/TODO-*_osprey_sharp.md`.

## When to Read What

- **Before writing code**: the guide's workspace + build-wrapper
  sections. Raw `cargo` is fragile; use `Build-OspreyRust.ps1`.
- **Before adding a diagnostic dump**: the guide's "Environment
  variable reference" and "Determinism" sections.
- **Before touching Stage 5**: the guide's "Bisection walk order"
  (Stages 1-4 dumps + Stage 5 dumps + `Compare-Percolator.ps1`).
- **Before committing**: run
  `pwsh -File ./ai/scripts/OspreySharp/Build-OspreyRust.ps1 -Fmt -Clippy -RunTests`.
  That mirrors the maccoss/osprey CI gates.
- **Before a PR**: read the guide's "Commit and PR conventions" —
  do NOT use Skyline's 10-line past-tense / `Co-Authored-By` format;
  osprey follows upstream-style prose.

## Key Constraints (Quick Reference)

- **`cargo fmt --check` + `clippy -D warnings` + `cargo test`** all
  gate the CI. Test modules must be the last item in their file
  (`clippy::items-after-test-module`).
- **LF line endings** — not CRLF. Do NOT run `fix-crlf.ps1` on the
  Rust tree.
- **Upstream-style commit prose**, no Skyline 10-line cap, no
  `Co-Authored-By: Claude` unless maintainer opts in.
- **Parity gate after scoring/calibration changes**: Stellar +
  Astral `Test-Features.ps1` must pass at 1e-6 per PIN feature.

## Key Repositories

- `C:\proj\osprey` → `maccoss/osprey` (SSH). Primary. New branches
  and PRs go here (`gh pr create --repo maccoss/osprey`).
- `C:\proj\osprey-fork` → `brendanx67/osprey`. Retired; do not extend.

## Slash Commands Available

Type `/pw-` to see project-wide commands. Most are Skyline-focused;
no osprey-specific slash commands yet.
