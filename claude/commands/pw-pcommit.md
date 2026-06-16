---
description: Propose commit message from diff and rules
---
Read ai\docs\version-control-guide.md for the exact commit message format, then review the staged changes (`git diff --staged`), and propose an appropriate commit message.

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

## Checklist
- [ ] **Past tense title** ("Added", "Fixed", "Moved" - not "Add", "Fix")
- [ ] **Bullet points** (1-5 points, each starting with `* `)
- [ ] **Reporter credit** (`Reported by <First>.`) if the change came from a user report/request — see ai/docs/version-control-guide.md, "Crediting Reporters and Requesters"
- [ ] **TODO reference** (`See ai/todos/active/TODO-YYYYMMDD_feature.md`)
- [ ] **Co-Authored-By** at the end
- [ ] **No emojis or markdown links**
- [ ] **≤10 lines total** (the reporter-credit line is exempt)

## Bug-fix gate

If the proposed title starts with `Fixed` (or the work is otherwise a bug fix — exception-fix or nightly-fix TODOs, exception report follow-ups, crash repros), verify before proposing the commit:

- Is there a test that fails on master and passes on this branch?
- Is the test included in the staged changes?
- Does a commit-message bullet or the TODO record point at the test by name?

A bug fix without a regression test is a fix that cannot be trusted to stay fixed. See [ai/docs/validation-cycle-principles.md](../../docs/validation-cycle-principles.md) — the permanent-verifier rule.

If no regression test is staged, stop and ask the developer why before proposing the commit. Acceptable answers exist (infrastructure-level fix no unit test could cover, a test that would require infrastructure not yet in place) — but the rationale must be acknowledged explicitly in the TODO and the commit message bullets, not silently omitted.
