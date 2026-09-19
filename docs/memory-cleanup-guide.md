# Memory Cleanup Guide

How to review Claude Code auto-memory on a machine, move what is durable into `ai/`,
and delete the rest. Driven by `/pw-cleanup-memory`.

## Why this needs a command

Claude Code keeps a per-machine, per-developer memory directory and loads its index
(`MEMORY.md`) into every session. Memories are written at the moment of learning,
before the finding is consolidated into a doc, a completed TODO, or code - and nothing
retires them afterward. So they accumulate, each session pays to load them, and they
are invisible to everyone else: no diff, no review, no history, and they do not follow
the developer to another machine.

The first sweep (2026-09-18, one machine) is the reason this exists:

| | Before | After |
|---|---|---|
| memory files | 126 | 15 |
| `MEMORY.md` index | 21 KB | 2.6 KB |

About 55 files were already fully covered by `ai/` docs or completed TODOs, another 55
held team-wide guidance that was not in `ai/` at all, and five contradicted current code
or docs. One over-generalized rule ("never `cd`") had shaped every session on that
machine for a month and was caught within minutes of appearing in a tracked diff.

Run it on **every machine you work on** - memory does not travel. Suggested cadence:
monthly, after a long sprint, or whenever `MEMORY.md` passes about 5 KB or 30 files.

## Where memory lives

The session's system prompt names the directory ("You have a persistent file-based
memory at ..."). Use that path; do not guess. Its shape is
`%USERPROFILE%\.claude\projects\<project dir with ':' and '\' replaced by '-'>\memory\`
(so `C:\proj` becomes `C--proj`). Each memory is one file with frontmatter (`name`,
`description`, `type: user | feedback | project | reference`); `MEMORY.md` is a one-line
index of them and is what every session loads.

## Phase 1 - Inventory (measure first)

```bash
pwsh -File './ai/scripts/Get-MemoryInventory.ps1'
```

The script prints counts, sizes, the type breakdown, one line per memory (date, type,
size, name, description), and two consistency checks: index lines whose file is missing,
and files missing from the index. Record the before numbers so the result can be stated
as a before and after.

## Phase 2 - Back up

Copy every file to `ai/.tmp/sessions/<session>/memory-backup/` before touching anything.
Every later step deletes; the backup is what makes that reversible.

## Phase 3 - Classify every memory

This is the judgment step, and it is per file. Read the memory, then look for the same
rule or fact in the durable places:

- `CLAUDE.md` (project root), `ai/CLAUDE.md`, `ai/CRITICAL-RULES.md`, `ai/MEMORY.md`,
  `ai/WORKFLOW.md`, `ai/STYLEGUIDE.md`, `ai/TESTING.md`
- `ai/docs/*.md`, `ai/claude/skills/*/SKILL.md`, `ai/claude/commands/*.md`
- `ai/todos/completed/**` (a completed TODO is a durable record) and `ai/todos/backlog/`
- product docs in the code repo (`pwiz_tools/Osprey/docs/*.md`) and script headers in
  `ai/scripts/`
- the code itself, when the memory names a symbol, flag, path, or default

Then give each file one verdict:

| Verdict | Meaning |
|---|---|
| **DELETE** | already captured in one of the places above (cite file and section); or history-only ("RESOLVED", "FIXED", "SUPERSEDED", a session log); or the premise is gone (the flag, path, branch, or plan no longer exists) |
| **MOVE** | team-wide guidance not yet in `ai/` (or only partly). Name the exact target file and section. The memory is deleted in the same step the move lands |
| **UPDATE** | still useful, partly stale; say what changes |
| **KEEP-LOCAL** | this-machine state, a personal preference, or an active exception with a revisit trigger; still true |

Be skeptical in both directions. A doc or TODO that *mentions* the fact is not the
same as one that *states the rule*; read the passage. And a memory that states a rule
confidently can be wrong: check it against the code and against the doc it would land
in. Flag every case where two memories contradict each other or a memory contradicts a
current doc - those become the decision list, not a silent pick.

Also flag: date-bound statements ("as of ...") that will rot, and files far longer than
one fact (session logs masquerading as memories).

**Fan out when there are more than about 25 files.** Partition by type or alphabet so
no two reviewers touch the same file, give each the list above, and have each return a
table: file, verdict, one-line reason, target. This is judgment work, so run it on the
session model and say so; a cheaper model tends to trust a number match as "fixed".

## Phase 4 - Report, then interview the developer

Write `ai/.tmp/sessions/<session>/memory-review.md` with these sections:

- **A. Decisions** - every contradiction (memory vs memory, memory vs doc, memory vs
  code), with both texts quoted
- **B. Contradicts current state** - memories that would mislead a session if recalled
- **C. Delete** - the redundant set, each with the place that already covers it
- **D. Move** - grouped by target file so the edits can be partitioned
- **E. Keep local** - with any trims

Then put the decisions to the developer one at a time with `AskUserQuestion`. Assume
they have not read the memories: explain each conflict in plain prose, quote the two
texts, and put the recommended option first with the reason. Do not execute a move that
depends on an undecided item.

## Phase 5 - Execute

1. **Deletes first** (section C). No information is lost; the backup exists.
2. **Moves** (section D), partitioned by target file - never two writers on one doc.
   Write in the target doc's voice: the rule, the why in a clause, how to apply. No
   session anecdotes, no dates unless they carry the rule, no memory names, no
   `[[links]]`. Extend an existing section rather than duplicating it. If the target
   already contradicts the rule, fix the target and report it. Delete the memory in the
   same step.
3. **Trim** the keep-locals and rebuild `MEMORY.md` from the survivors, one line each.
4. **Verify**: re-run the inventory script (index and files must agree); grep the edited
   `ai/` files for banned phrases and for `[[...]]` links; spot-check the three or four
   highest-impact rewrites.
5. **Commit `ai/` by path** - not `git add -A`, the checkout is shared - with the message
   in a file and `git commit -F`, then `git pull --rebase` and push. Anything whose home is
   the code repo (product docs, a script default) goes into a normal PR there; keep those
   memories until that PR lands.

## What legitimately stays local

- This-machine state: installed tool versions, paths that differ per machine, a local
  git config
- The developer's own preferences that are not team policy
- An active exception with a named end ("until PR N merges") - and delete it when the
  end arrives
- Items waiting on a code-repo PR, with a note saying so

## Ongoing hygiene

The sweep is cheap only if it stays small. The rule that prevents regrowth is in
`documentation-maintenance.md`, "Personal memory vs team docs": before writing a memory,
ask whether it is team-wide (then it goes in `ai/`), and when a finding lands in a doc
or a completed TODO, delete the memory that held it in the same step.
