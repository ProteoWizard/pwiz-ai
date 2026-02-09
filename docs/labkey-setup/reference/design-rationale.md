# Design Rationale

The original LabKey setup guide was a single 1,150-line, 51KB document. Every
time Claude Code started or resumed the workflow, the entire file had to be
loaded — about 12,000 tokens per read. With 2–3 terminal restarts typical
during setup, that added up to 36,000+ tokens. This repository restructures
that guide into small phase files loaded one at a time, with a JSON state file
for tracking progress, bringing total token usage down to roughly 6,800 — about
an 80% reduction.

## What drove the restructuring

Three specific costs made the monolithic approach expensive for an LLM-driven
workflow:

- **Resume cost.** After each terminal restart, the entire document had to be
  re-read to recover context. There was no lightweight checkpoint.
- **Reference bloat.** Troubleshooting, Gradle commands, and module references
  were all inline — loaded every session even when not needed.
- **Maintenance.** Changing one phase meant editing a 1,150-line file, with
  risk of unintended side effects elsewhere.

## How it's structured now

**Phase files** (`phases/phase-N-*.md`): Each phase is 50–100 lines. Claude
reads one at a time and moves to the next only when the current phase
completes. This keeps per-step token cost at 400–700 instead of 12,000.

**State file** (`state.json`): Tracks current phase, completed steps, version
choices, and deferred items. On resume after a terminal restart, Claude reads
this ~200-byte file to know exactly where to pick up — no full-document
re-read needed.

**Reference docs** (`reference/`): Troubleshooting, Gradle commands, and
module info are separate files loaded on demand. In a smooth setup run with no
issues, they are never loaded at all.

## Token comparison

|                        | Monolithic    | Modular              |
|------------------------|---------------|----------------------|
| Initial load           | 12,000 tokens | 700 (README only)    |
| Resume after restart   | 12,000 tokens | ~200 (state.json)    |
| Full setup workflow    | 36,000+ tokens| ~6,800 tokens        |

## Maintainer notes

- **Update a phase**: edit the single phase file; other phases are unaffected.
- **Add a phase**: create a new file in `phases/`, add it to the Workflow
  Phases list in README.md.
- **Add troubleshooting**: append to `reference/troubleshooting.md`.
- **Change assistant behavior** (message ordering, state management rules):
  edit README.md.
