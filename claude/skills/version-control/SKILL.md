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

Reported by <First>.

See ai/todos/active/TODO-YYYYMMDD_feature.md

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Rules:**
- Past tense title ("Added feature" not "Add feature")
- Bullet points use `* ` prefix (not `-`)
- `Reported by <First>.` (or `Requested by <First>.`) when the change came from a user report/request — see "Crediting reporters" below
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

Reported by <First>.

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

## Crediting reporters

When a change came from a user report or request, credit the originator by **first
name only** in both the commit message and the PR description: `Reported by
<First>.` / `Requested by <First>.` on its own line (it feeds the release notes).
Full rules — placement, looking the name up from a support thread, the Brendan
exception — in ai/docs/version-control-guide.md ("Crediting Reporters and
Requesters").

## Review chain: self-review first (local), then open the PR, then Copilot

Both the fresh-context Claude self-review and Copilot are **mandatory
gates** — they catch different classes of issue and each has caught
real bugs the other missed. The ORDER is deliberate: run the
self-review LOCALLY *before* opening the PR, so (a) the author fixes
its findings before anyone else sees the PR, and (b) Copilot's
automatic review lands LAST, on the final state, instead of being
immediately invalidated by the self-review fixes.

1. **`/pw-self-review` — local, before the PR.** As soon as coding is
   complete (tests may still be running), launch the fresh-context
   Claude agent on the local branch (diff vs base; no PR number
   needed). Running fresh, it doesn't inherit the author's blind
   spots and catches what Copilot systematically misses — cross-
   implementation divergence in ports (it can read source repos
   outside the change that Copilot can't see), correctness bugs the
   new tests don't cover, concurrency, and hash-stability invariants.
   Address its findings before posting.
   - **Developer present:** surface findings and agree which to fix.
   - **Autonomous:** address them in follow-up commits on the branch.
   Don't skip it because the change "looks fine" — every PR that has
   reached this skill yielded at least one useful agent finding.

2. **Open the PR** (`gh pr create`) once self-review findings are
   resolved and the build/tests are green.

3. **Wait for Copilot's review** (arrives within ~5 minutes; Copilot
   reviews every PR in this repo automatically). Treat the PR as
   not-yet-mergeable until it has reviewed and its findings are
   addressed or explicitly dismissed. Run **`/pw-respond <PR#>`** to
   address its comments and resolve the threads.

4. **For maximum rigor**, follow with `/ultrareview <PR#>` — a
   user-triggered, billed, multi-agent cloud review. Stronger than
   either of the above. Claude Code cannot launch this itself.

(`/pw-self-review` still accepts a `<PR#>` if you ever need to run it
after a PR exists — but local-first is the default.)

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
