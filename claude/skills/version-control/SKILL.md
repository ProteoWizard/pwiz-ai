---
name: version-control
description: ALWAYS load before git commit, push, or PR - team-specific commit format differs from standard conventions.
---

# Version Control for Skyline/ProteoWizard

Before any Git or GitHub operation, read the relevant documentation:

## Required Reading

- **ai/docs/version-control-guide.md** - Commit message format, PR format, branch naming
- **ai/docs/release-cycle-guide.md** - Current release phase, cherry-pick policy
- **ai/WORKFLOW.md** - Git workflows, TODO system, branch lifecycle

## Pre-Commit Gate: Build and Test

**NEVER commit code that has not been built and tested.** This is a hard gate.

Before staging and committing, verify:
1. The code compiles without errors
2. Relevant tests pass

If the LLM has not built/tested the code itself, ask the developer: "Has this been built and tested since the last change?" Do not skip this step even for small fixes - even a small change can introduce a build error or break a test.

## Commit Message Format

```
<Title in past tense>

* bullet point 1
* bullet point 2

See ai/todos/active/TODO-YYYYMMDD_feature.md

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Rules:**
- Past tense title ("Added feature" not "Add feature")
- Bullet points use `* ` prefix (not `-`)
- TODO reference required for feature branches
- Co-Authored-By required when LLM contributed
- Maximum 10 lines total
- No emojis, no markdown links

**pwiz-ai repository (ai/)**: Omit TODO reference for documentation-only changes

## Amending Commits

**Nearly all PRs get squash-merged**, so multiple commits on a branch are fine.

**NEVER amend after a PR has been reviewed.** When addressing review feedback (from humans or Copilot), always create a NEW commit. This preserves the review history and makes it easy to see what changed in response to feedback. A commit message like "Addressed Copilot review suggestions" or "Fixed issues from code review" is appropriate.

**When amending is acceptable:**
- Immediately after creating a PR, before any review or interaction
- Local commits not yet pushed

**When amending is NOT acceptable:**
- After a PR has been reviewed (even if just by Copilot)
- After anyone has clicked "Update branch" on GitHub
- After any merge commits from master

The commits will be squashed on merge anyway, so there is no cost to having multiple commits.

## PR Description Format

```
## Summary

* bullet point 1
* bullet point 2

Fixes #XXXX

## Test plan

- [x] TestName - description

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Rules:**
- Use `Co-Authored-By: Claude <noreply@anthropic.com>` at the end (not emoji "Generated with" lines)
- Bullet points use `* ` prefix in Summary
- Test plan uses `- [x]` checkboxes
- No emojis

## After a PR Is Opened

Once `gh pr create` returns the PR URL, the post-open review chain
runs in this order:

1. **Expect a Copilot review within ~5 minutes.** Copilot
   automatically reviews every PR in this repo; its findings consistently add
   value and addressing them is part of the standard development
   process. Treat the PR as not-yet-mergeable until Copilot has
   commented and its findings are addressed.

2. **Run `/pw-respond <PR#>`** once Copilot's review lands to
   address its comments in code and resolve the threads.

3. **Optionally launch a fresh-context agent review on top of
   Copilot.** Copilot and a Claude agent catch different classes of
   issue (Copilot: idiomatic / API / language; Claude agent: logic /
   cross-impl / spec conformance), so the second pass is additive.
   Use `/pw-self-review <PR#>` for the canned framing, or invoke the
   Agent tool directly with `subagent_type: "general-purpose"` and a
   thorough-review prompt. The agent runs in a fresh context so it
   doesn't inherit the author's blind spots. *Not* a substitute for
   Copilot or `/ultrareview` — strictly additive.

4. **For maximum rigor**, follow with `/ultrareview <PR#>` — a
   user-triggered, billed, multi-agent cloud review. Stronger than
   either of the above. Claude Code cannot launch this itself.

## Branch Naming

`Skyline/work/YYYYMMDD_feature_name`

## Cherry-Pick to Release

When in FEATURE COMPLETE or patch mode, bug fix PRs should be cherry-picked to the release branch:

1. Check current release phase in `ai/docs/release-cycle-guide.md`
2. If fixing a bug during FEATURE COMPLETE: add label `Cherry pick to release`
3. The cherry-pick happens automatically after PR merge

**Current release branch**: `Skyline/skyline_26_1` (check release-cycle-guide.md for updates)

## Commands

Use `/pw-pcommit` or `/pw-pcommitfull` for guided commits.

See ai/docs/version-control-guide.md for complete specification.
