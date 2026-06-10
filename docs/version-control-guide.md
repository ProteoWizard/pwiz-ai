# Version Control Guide

Detailed conventions for Git commits, PRs, and branch management in Skyline/ProteoWizard.

## Commit Message Format

All commits MUST follow this exact format:

```
<Title line in past tense>

* <bullet point 1>
* <bullet point 2>
* <bullet point 3>

See ai/todos/active/TODO-YYYYMMDD_feature_name.md

Co-Authored-By: Claude <noreply@anthropic.com>
```

### Format Rules

| Element | Rule |
|---------|------|
| Title | Single line, **past tense** ("Added", "Fixed", "Moved" - NOT "Add", "Fix") |
| Bullets | 1-5 points, each starting with `* ` (asterisk + space) |
| TODO reference | `See ai/todos/active/TODO-YYYYMMDD_feature_name.md` |
| Co-authorship | Exactly `Co-Authored-By: Claude <noreply@anthropic.com>` |
| Total lines | Maximum 10 lines including blank lines |
| Prohibited | Emojis, markdown links |

### Example

```
Fixed alert dialog timeout in functional tests

* Added ShowWithTimeout method to catch unexpected dialogs
* Timer closes dialog after 10 seconds in test mode
* Throws TimeoutException with dialog message for debugging

See ai/todos/active/TODO-20251217_alert_timeout.md

Co-Authored-By: Claude <noreply@anthropic.com>
```

### Creating Commits with HEREDOC

Use HEREDOC for proper formatting:

```bash
git commit -m "$(cat <<'EOF'
Fixed alert dialog timeout in functional tests

* Added ShowWithTimeout method to catch unexpected dialogs
* Timer closes dialog after 10 seconds in test mode
* Throws TimeoutException with dialog message for debugging

See ai/todos/active/TODO-20251217_alert_timeout.md

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

## Pull Request Format

```markdown
## Summary
- Bullet point summarizing change 1
- Bullet point summarizing change 2
- Bullet point summarizing change 3

## Test plan
- [x] Test that was run
- [x] Another test that was run

See ai/todos/active/TODO-YYYYMMDD_feature_name.md

Co-Authored-By: Claude <noreply@anthropic.com>
```

## Pre-Review Workflow

Before requesting human review, a change should clear two AI review passes —
a fresh-context Claude self-review and GitHub Copilot. They catch different
classes of issue (Claude: logic / cross-impl / spec conformance, and it can
read source repos outside the change; Copilot: idiomatic / API / language),
and each has caught real bugs the other missed, so both are mandatory.

**The ORDER is deliberate — self-review runs LOCALLY, before the PR exists:**

1. **`/pw-self-review` — local, before opening the PR.** As soon as coding is
   complete (tests may still be running), run it on the local branch (it diffs
   `master...HEAD`; no PR number needed). Address its findings first.
   - Developer present: surface findings and agree which to fix.
   - Autonomous: fix the agreed set in follow-up commits.
2. **Open the PR** (`gh pr create`) once self-review findings are resolved and
   build/tests are green.
3. **Copilot reviews automatically** within ~5 min of the PR opening. Because
   self-review already landed, Copilot reviews the FINAL state instead of being
   immediately invalidated by self-review fixes. Run **`/pw-respond <PR#>`** to
   address its comments and resolve the threads.
4. **Optional — `/ultrareview <PR#>`** for maximum rigor (user-triggered,
   billed, multi-agent cloud review; stronger than either pass above).

Why local-first: opening the PR is what triggers Copilot's automatic review, so
posting before self-review wastes that pass on a state you are about to change.
Run self-review first; let Copilot land last.

Address each round in a NEW commit (see "Amending Commits" below); PRs are
squash-merged, so extra commits cost nothing and preserve the review history.
Only after both AI reviewers are clean on the same commit should you request
human review.

The goal is to spend reviewers' time on judgment calls, not on issues the AI
passes would have caught.

## Branch Naming Convention

**Format**: `Skyline/work/YYYYMMDD_feature_name`

- Use today's date (YYYYMMDD)
- Use snake_case for feature name
- Examples:
  - `Skyline/work/20251217_alert_timeout`
  - `Skyline/work/20251218_files_view_fix`

## Finding Current TODO

```bash
# Get branch name
git branch --show-current
# Output: Skyline/work/20251217_feature_name

# TODO location: ai/todos/active/TODO-20251217_feature_name.md
```

## Amending Commits

**NEVER amend after a PR has been reviewed.** When addressing review feedback (from humans or Copilot), always create a NEW commit. This preserves the review history and makes it easy to see what changed in response to feedback. PRs are squash-merged, so extra commits have zero cost.

Amending is only acceptable for:
- Local commits not yet pushed
- Small updates (TODO PR link, typo fix) immediately after creating a PR, before any review

```bash
git add <files>
git commit --amend --no-edit
git push --force-with-lease
```

## Slash Commands

| Command | Purpose |
|---------|---------|
| `/pw-pcommit` | Propose commit message from staged changes |
| `/pw-pcommitfull` | Full pre-commit with TODO update and message proposal |
| `/pw-uptodo` | Update current branch TODO with progress |

## Checklist Before Commit

- [ ] Title in past tense
- [ ] 1-5 bullet points with `* ` prefix
- [ ] TODO reference included
- [ ] Co-Authored-By line at end
- [ ] No emojis or markdown links
- [ ] ≤10 total lines

## Cherry-Picking to Release Branch

During FEATURE COMPLETE phase, bug fixes often need to go to both master and the release branch. See `ai/docs/release-cycle-guide.md` for current release state.

### Automatic Cherry-Pick (Preferred)

Add the **"Cherry pick to release"** label to your PR before merging. The bot will create a cherry-pick PR automatically.

### Manual Cherry-Pick

Use `/pw-cptorelease <PR#>` when:
- Automatic cherry-pick failed (branch deleted too early, merge commits in history)
- You forgot to add the label before merging
- You want a more informative PR description

**Manual cherry-pick steps:**
```bash
# 1. Find the merge commit
git fetch origin master
git log --oneline origin/master | grep "#<PR#>"

# 2. Create branch from release branch
git checkout -b Skyline/work/YYYYMMDD_feature_release origin/Skyline/skyline_XX_X

# 3. Cherry-pick
git cherry-pick <merge-commit-hash>

# 4. Push and create PR
git push -u origin Skyline/work/YYYYMMDD_feature_release
gh pr create --base Skyline/skyline_XX_X --title "Cherry-pick: <title>" --body "..."
```

### Cherry-Pick PR Format

```markdown
## Summary

Cherry-pick of #<original-PR> to release branch `Skyline/skyline_XX_X`.

<Optional: reason for manual cherry-pick>

**Original changes:**
<Brief summary of what the PR did>
```

### Common Gotchas

1. **Deleting PR branch too early** - Wait for the cherry-pick PR to be created before deleting your branch
2. **Merge commits in history** - Use `git pull --rebase` or `/rebase` comment before squash-and-merge
