# Version Control Guide

Detailed conventions for Git commits, PRs, and branch management in Skyline/ProteoWizard.

## Commit Message Format

All commits MUST follow this exact format:

```
<Title line in past tense>

* <bullet point 1>
* <bullet point 2>
* <bullet point 3>

Reported by <First>.

See ai/todos/active/TODO-YYYYMMDD_feature_name.md

Co-Authored-By: Claude <noreply@anthropic.com>
```

The `Reported by <First>.` line is included only when the change originated
from a user report or request — see "Crediting Reporters and Requesters" below.

### Format Rules

| Element | Rule |
|---------|------|
| Title | Single line, **past tense** ("Added", "Fixed", "Moved" - NOT "Add", "Fix") |
| Bullets | 1-5 points, each starting with `* ` (asterisk + space) |
| TODO reference | `See ai/todos/active/TODO-YYYYMMDD_feature_name.md` |
| Co-authorship | Exactly `Co-Authored-By: Claude <noreply@anthropic.com>` |
| Reporter credit | `Reported by <First>.` on its own line when the change came from a user report/request (see below) |
| Total lines | Maximum 10 lines including blank lines (the reporter-credit line does not count against this) |
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

Reported by <First>.

Fixes #XXXX

## Test plan
- [x] Test that was run
- [x] Another test that was run

See ai/todos/active/TODO-YYYYMMDD_feature_name.md

Co-Authored-By: Claude <noreply@anthropic.com>
```

The `Reported by <First>.` line is included only when the change originated from
a user report or request — see "Crediting Reporters and Requesters" below.

## Crediting Reporters and Requesters

When a change originates from a user report or request — a support-board thread,
a GitHub issue, an email, or a conversation — credit the originator in **both the
commit message and the PR description**. This is standard practice: the
attribution feeds the release notes, where reporters are acknowledged (see
`ai/docs/release-guide.md`, "Generating Skyline-daily Release Notes", which
harvests requester/reporter info from the commit body). Capturing it at authoring
time is the only reliable way to get it there.

**Rules:**

- **First name only.** "Reported by Jane", never "Reported by Jane Doe". Full
  names feel exposing in public history; first names match how the team refers to
  users and match the release-notes style (`(reported by Lillian)`).
- **Placement.** A line on its own — `Reported by <First>.` (a feature request is
  `Requested by <First>.`) — above the `See ai/todos/...` / `Co-Authored-By:`
  lines, separated by a blank line. Not inside a bullet, not woven into prose.
- **Both records.** Put it in the commit message *and* the PR description (the
  squash-merge uses the PR description, so it carries into git history either way;
  include it in both so neither path loses it).
- **Look it up when it isn't obvious.** The reporter is often a support-board user
  even when the GitHub issue/PR was filed by a team member. Find the name from the
  linked thread — `mcp__labkey__get_support_thread` on the thread's `rowId`; the
  reporter is the original poster — and credit them even though they aren't the
  issue author. See the `GitHub ID to Name Mapping` table in `release-guide.md`
  for team-member first names.
  - **If the thread shows only a numeric user id** (external posters come through
    as e.g. `From: 41337`, not a name), resolve it via the `core.Users` table:
    `mcp__labkey__fetch_labkey_page(view_name="query-executeQuery.view",
    container_path="/home/support", params={schemaName:"core",
    "query.queryName":"Users", "query.UserId~eq":<id>})` and read the **Display
    Name** column (e.g. `41337` → `james41337` → credit "James"). `get_support_thread`,
    `query_support_threads`, and the rendered thread page all anonymize external
    posters to the id — the `core.Users` query is the step that yields the name.
- **Full identity stays in the link.** The support-thread URL or GitHub issue can
  carry the full name and context; the prose credit is first-name only.
- **Brendan is omitted** (he sends the release email) — consistent with the
  release-notes attribution rule.

## Pre-Review Workflow

**`/pw-self-review` is the mandatory AI review gate** before requesting human
review — a fresh-context Claude pass that catches logic / cross-impl / spec-
conformance bugs and can read source repos outside the change. It is required
on every PR.

**Copilot review is now OPTIONAL and billed.** It used to be free and ran
automatically on every PR (which is why self-review was once sequenced to land
before it). Copilot review now carries a per-use cost — the same category as
`/ultrareview` — so it is opt-in for extra rigor, not a standing gate. This
removes the reason to withhold the PR until self-review is done.

**The order, updated for that policy:**

1. **Open the PR early** (`gh pr create`) as soon as the build is green and
   tests pass — *before* self-review. Opening the PR kicks off the first round
   of **TeamCity** CI, so that runs in parallel while self-review proceeds.
   (Safe now that Copilot no longer auto-reviews on open: there is no automatic
   pass to waste on a state you are about to change.)
2. **`/pw-self-review`** — the primary AI gate. Run it on the branch (it diffs
   `master...HEAD`; a `<PR#>` also works now the PR exists). Address its findings
   in NEW commits (see "Amending Commits"); PRs are squash-merged, so extra
   commits cost nothing and preserve the review history.
   - Developer present: surface findings and agree which to fix.
   - Autonomous: fix the agreed set in follow-up commits.
3. **Optional, billed — extra rigor when warranted:**
   - **Copilot review** — now opt-in (billed). Trigger it deliberately when the
     change wants idiomatic / API / language scrutiny; then **`/pw-respond <PR#>`**
     to address comments and resolve threads.
   - **`/ultrareview <PR#>`** — user-triggered, billed, multi-agent cloud review;
     stronger than either pass above. Claude Code cannot launch it itself.

Only after self-review is clean (and any optional reviews triggered are
addressed) on the latest commit, with TeamCity green, should you request human
review. The goal is to spend reviewers' time on judgment calls, not on issues
the AI passes would have caught.

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
- [ ] `Reported by <First>.` line if the change came from a user report/request
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
