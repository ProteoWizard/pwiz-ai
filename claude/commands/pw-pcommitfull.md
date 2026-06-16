---
description: Full pre-commit with TODO update and message proposal
---
Perform full pre-commit workflow:
1. Read ai\docs\version-control-guide.md for exact commit message format
2. Review the complete diff of staged changes (`git diff --staged`)
3. Update the current branch TODO file with progress (per /pw-uptodo)
4. Propose commit message in required format (title + bullets + TODO + co-authorship)

## Required Format
```
<Title in past tense>

* bullet 1
* bullet 2
* bullet 3

Reported by <First>.

See ai/todos/active/TODO-YYYYMMDD_feature.md

Co-Authored-By: Claude <noreply@anthropic.com>
```

Include the `Reported by <First>.` line only when the change came from a user
report or request — see ai/docs/version-control-guide.md, "Crediting Reporters and
Requesters".

## Bug-fix gate

If the proposed title starts with `Fixed` (or the work is otherwise a bug fix — exception-fix or nightly-fix TODOs, exception report follow-ups, crash repros), verify before proposing the commit:

- Is there a test that fails on master and passes on this branch?
- Is the test included in the staged changes?
- Does a commit-message bullet or the TODO record point at the test by name?

A bug fix without a regression test is a fix that cannot be trusted to stay fixed. See [ai/docs/validation-cycle-principles.md](../../docs/validation-cycle-principles.md) — the permanent-verifier rule.

If no regression test is staged, stop and ask the developer why before proposing the commit. Acceptable answers exist (infrastructure-level fix no unit test could cover, a test that would require infrastructure not yet in place) — but the rationale must be acknowledged explicitly in the TODO and the commit message bullets, not silently omitted.

## Troubleshooting

**CRLF Warning**: If git shows `LF will be replaced by CRLF the next time Git touches it`:
```powershell
pwsh -Command "& './ai/scripts/fix-crlf.ps1'"
git add <fixed-files>
```
This ensures consistent line endings before commit.
