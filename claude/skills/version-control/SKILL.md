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
is mandatory. Both Copilot and a fresh-context Claude agent are gates,
not options — they catch different classes of issue and we have seen
each catch real bugs the other missed:

1. **Wait for Copilot's review** (arrives within ~5 minutes).
   Copilot reviews every PR in this repo automatically. Treat the PR
   as not-yet-mergeable until it has reviewed and its findings are
   either addressed or explicitly dismissed.

2. **Run `/pw-respond <PR#>`** to address Copilot's comments in
   code and resolve the threads.

3. **Run `/pw-self-review <PR#>`** to launch a fresh-context Claude
   agent review on top of Copilot. This step is **required**, not
   optional. The agent runs in a fresh context so it doesn't inherit
   the author's blind spots, and it picks up issues Copilot
   systematically misses — particularly cross-implementation
   divergence in ports (where the agent can read source repos
   outside the current PR that Copilot does not see), correctness
   bugs the new tests don't cover, and hash-stability invariants.
   Decision rule:
   - **If a developer is present and waiting**, surface the agent's
     findings and ask which to address before merge.
   - **In autonomous mode** (developer asleep or unavailable),
     launch the agent automatically once Copilot threads are
     resolved and address its findings in a follow-up commit on the
     same branch. Don't skip this step because the PR "looks fine"
     after Copilot — every PR that's reached this skill so far has
     yielded at least one useful agent finding.

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
