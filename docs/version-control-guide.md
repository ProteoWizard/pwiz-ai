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
from a report or request **outside the development team** — never for the
author's own work or a project developer's request. See "Crediting Reporters and
Requesters" below.

### Format Rules

| Element | Rule |
|---------|------|
| Title | Single line. The **action verb leads in past tense** ("Added", "Fixed", "Moved", "Improved" - NOT "Add", "Fix"). See "Tense" below - past tense is for the *action*, not for describing how the product behaves. |
| Bullets | 1-5 points, each starting with `* ` (asterisk + space) |
| TODO reference | `See ai/todos/active/TODO-YYYYMMDD_feature_name.md` |
| Co-authorship | Exactly `Co-Authored-By: Claude <noreply@anthropic.com>` |
| Reporter credit | `Reported by <First>.` on its own line when the change came from an outside-the-dev-team report/request; omit for the author's own work or a project developer's request (see below) |
| Total lines | Maximum 10 lines including blank lines (the reporter-credit line does not count against this) |
| Prohibited | Emojis, markdown links |

### Tense

Past tense applies to **the action the commit performs** - what was Fixed, Added, Changed,
Improved, Removed. This is a changelog convention: these titles become the release-notes email,
which lists the bugs fixed, features added, and behaviors changed in a version (see
`release-guide.md`). "Fixed a crash", "Added a save prompt", "Changed the default folder" all read
the way that email reads.

But **describe ongoing product behavior in the present tense** - what the software does from now
on, not the act of changing it. A single title or bullet often mixes the two on purpose: a
past-tense action verb, then a present-tense description of the resulting behavior.

- "Added a prompt **asking** which folder to save in" - *Added* is the action (past); the prompt
  *asks* every time from now on (present).
- "Fixed a crash by **checking** for a null document" - *Fixed* (past); the code *checks* on every
  run (present).

Do NOT force behavior into the past tense ("...a prompt that **asked** which folder", "...**checked**
for null") - that reads as a one-time event rather than how the product now works. The rule is about
the leading action verb, not every verb in the message.

### Example

```
Fixed alert dialog timeout in functional tests

* Added ShowWithTimeout method to catch unexpected dialogs
* Timer closes dialog after 10 seconds in test mode
* Throws TimeoutException with dialog message for debugging

See ai/todos/active/TODO-20251217_alert_timeout.md

Co-Authored-By: Claude <noreply@anthropic.com>
```

The title and the "Added…" bullet lead with a past-tense action; "Timer **closes**…" and
"**Throws**…" describe ongoing behavior in the present tense.

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
a report or request **outside the development team** — never for the author's own
work or a project developer's request. See "Crediting Reporters and Requesters"
below.

## Crediting Reporters and Requesters

When a change originates from a report or request from **outside the development
team** — a support-board thread, a GitHub issue, an email, or a conversation —
credit the originator in **both the
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
- **Never credit the PR's own author.** A developer describing what they built is
  not a reported request. If the person who would be credited is the one who wrote
  the change, there is no credit line.
- **Developers of the project are not credited either.** The line marks a request
  that arrived from *outside* the team building the code — a support-board user, a
  collaborator, a customer email. What a developer asks for on a project they
  develop is ordinary planning, not an outside request, so it gets no line.
  - **This is role-scoped, not person-scoped.** The same person can be an outside
    requester on one project and a developer on another, so decide per change.
    Mike, for example, has long been a frequent requester for **Skyline** (credit
    him there), but is now one of the primary developers of **Osprey** — an Osprey
    request from him is internal planning and gets **no** `Requested by` line.
- **Brendan is omitted** (he sends the release email) — consistent with the
  release-notes attribution rule.

## Pre-Review Workflow

**`/code-review <level>` is the AI review gate** before requesting human review.
It replaced `/pw-self-review`, retired 2026-07-25. That command was written when
an early session said it could not give an unbiased review of its own code;
`/code-review` is the native, upstream-maintained answer to exactly that, and it
gains capability without us maintaining prose to describe it.

**Run the review BEFORE opening the PR.** `/code-review` diffs `master...HEAD`,
so it does not need a PR to exist. Reviewing first is materially cheaper:

- **Copilot auto-reviews on PR open.** Measured on #4460: PR created 14:44:23,
  Copilot review submitted 14:46:57, nobody requested it. Open first and that
  billed pass is spent on code you are about to rewrite.
- **Every push re-runs CI.** Landing review fixes after opening costs extra
  TeamCity rounds on states that are obsolete within the hour. #4460 cost three
  before this ordering was adopted.
- Copilot then reviews already-hardened code, so it has less left to find and
  its findings are more likely to be worth acting on.

For **Osprey** there is no counter-argument to reordering: the expensive
Perf/Regression config is manual/overnight and does NOT trigger on PR open, so
opening early overlaps no long-running job. For a Skyline PR that does
auto-start something slow, weigh that overlap against the wasted Copilot pass.

**The order:**

1. **`/code-review <level>`** on the branch, before the PR exists. Fold the
   resulting fixes into the commits that will open the PR.
   - **Verify every finding before acting on it.** The reviewer can be
     confidently wrong. On #4460, 1 of 9 findings asserted that swapping two
     codec fields would leave every test green - but
     `TestEncodeMatchesRustByteLayout` pins each field to a distinct offset with
     a distinct literal value, so it does fail. Reproduce or refute each finding
     against the code. Pushing back with the reason is a legitimate outcome;
     auto-applying the list is not.
   - **Default to `max` for any code change.** The effort levels - `low`,
     `medium`, `high`, `xhigh`, `max` - all run locally against the Max
     subscription with **no extra billing**, so there is no cost reason to hold
     back. `max` is the highest effort available for free; use it. Step down
     only for genuinely trivial diffs (comment, doc, or rename-only), where the
     wall time is the only thing you are spending. For calibration, `xhigh` on
     #4460 took roughly 10.5 minutes and 138k tokens.
2. **Open the PR** once the branch is green (build + tests + zero-warning
   inspection) and the findings are settled. Copilot reviews it automatically;
   use **`/pw-respond <PR#>`** to address its comments and resolve the threads.

### Do not use `ultra` on pwiz

**`/code-review ultra`, and its deprecated alias `/ultrareview`, are NOT the top
of the effort ladder above** - they are a separate, **billed**, multi-agent
**cloud** review. pwiz is too large for it in practice: Brendan's attempts
repeatedly ran about half an hour, timed out, and produced no usable findings
while still incurring cost.

Recommendation for this project: **do not use it.** `max` is free under the
subscription, runs locally, and actually finishes on a repo this size. If a
change feels risky enough to want a third opinion, a human reviewer is the
better spend.

**The AI reviews do not stack.** Copilot plus `/code-review` is already two
independent passes; do not add a third by rote.

Request human review only after the findings are settled and TeamCity is green.
The goal is to spend reviewers' time on judgment calls, not on issues an AI pass
would have caught.

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
- [ ] `Reported by <First>.` line ONLY if the request came from outside the dev
      team (not the author, not a developer of the project being changed)
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
