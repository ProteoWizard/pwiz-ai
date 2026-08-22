# Version Control Guide

Detailed conventions for Git commits, PRs, and branch management in Skyline/ProteoWizard.

## Module Tagging

The `ProteoWizard/pwiz` repository carries three high-flow streams of work, and
every PR belongs to exactly one of them:

| Module | Covers | Typical paths |
|--------|--------|---------------|
| `skyline` | The Skyline application and everything shipped or tested with it | `pwiz_tools/Skyline`, `Test*/`, SkylineTester, SkylineNightly, `pwiz_tools/Shared` when consumed by Skyline |
| `pwiz` | ProteoWizard core: msconvert, the C++ libraries, vendor readers, BiblioSpec, the build system | `pwiz/`, `pwiz_aux/`, vendor reader code |
| `osprey` | Osprey / OspreySharp, the DIA proteomics search tool | `pwiz_tools/Osprey` |

These are the **same three labels already used on GitHub Issues** — the module
name, the label name, and the title prefix are all one string. There is no
mapping table to remember.

### Two carriers, because they serve different readers

Every pwiz PR gets the module recorded **twice**, and both are required:

1. **A GitHub label** on the PR (`skyline`, `pwiz`, or `osprey`). This is the
   machine-readable copy — it makes PRs filterable in the GitHub UI, in
   `gh pr list --label`, and in the daily PR report.
2. **A title prefix** on the PR title *and* the squash-merge subject
   (`skyline: Fixed …`). This is the copy that survives.

The prefix is not redundant with the label. **Git history has no labels.** Once
a PR is squash-merged, the label lives only on the PR; `git log --oneline`,
`git blame`, `git log --grep`, and every release-notes pass see nothing but the
subject line. That is exactly where the module signal is needed and exactly
where it is currently missing:

```
Fixed intermittent failures in TestSetItemMcpConnector and TestJsonToolServer (#4474)
Bumped BullseyeSharp submodule to pick up build-output .gitignore (#4432)
Warned on unrecognized rows during --import-peak-boundaries (#4440)
```

Nothing in those titles says which part of the repository was being worked on.
Osprey work is currently findable in the log only because the word "Osprey"
tends to appear in the prose by luck, not by rule.

### Format

```
<module>: <Title line in past tense> (#NNNN)
```

- Lowercase, exactly the label token, followed by a colon and one space
- The past-tense action verb still leads the title itself — the prefix sits in
  front of it and is not part of the sentence
- The ` (#NNNN)` suffix rule is unchanged; prefix and suffix compose

```
skyline: Fixed TestDiaToSrmTutorial failing in Japanese on English combo box literals (#4483)
osprey: Made the OspreySharp protein razor peptide rollup deterministic (#4442)
pwiz: Warned on unrecognized rows during --import-peak-boundaries (#4440)
```

### Where it is required

| Artifact | Module label | Title prefix |
|----------|--------------|--------------|
| GitHub Issue | **Required** (already the practice) | Not used |
| PR on `ProteoWizard/pwiz` | **Required** | **Required** |
| Squash-merge subject (`/pw-complete`) | n/a | **Required** |
| Cherry-pick PR to a release branch | **Required** (inherit from the original) | **Required** (inherit from the original) |
| Intermediate commits on a work branch | n/a | Optional |
| Commits on `pwiz-ai` (`ai/`) | Not used | Not used |

**Intermediate branch commits are optional** because squash-merge discards
them — tagging every WIP commit is typing that never reaches `master`. Tag the
two artifacts that persist: the PR title and the squash subject.

**`pwiz-ai` (`ai/`) is exempt entirely.** That repository is a single module —
AI tooling and documentation — so a prefix on every commit would carry no
information. It also has no module labels defined.

### Choosing the module

- **From a GitHub Issue**: use the issue's module label. `/pw-startissue`
  reads it and records it; see "Carrying the module through the workflow" below.
- **Without an issue**: pick from the paths the change touches, using the table
  above.
- **A change spanning two modules**: pick the **primary** one — where the intent
  of the change lives, not merely where the most lines moved. A Skyline feature
  that needs a one-line fix in a pwiz reader is `skyline`. Apply the additional
  label too if it genuinely helps triage, but **the title carries exactly one
  prefix.**

### Carrying the module through the workflow

The module is decided at the *start* of the work and must still be known at
`gh pr create` and at squash-merge — often many hours and a context compaction
later. The TODO file is the carrier:

```markdown
## Branch Information
- **Branch**: `Skyline/work/YYYYMMDD_<description>`
- **Module**: `skyline` | `pwiz` | `osprey`
- ...
```

Every command that opens a PR or writes a squash subject reads the `Module`
field from the TODO rather than re-deriving it from the diff. Re-deriving is
where the module silently drifts between the issue, the PR, and the commit.

### One prefix, not two

The log already contains ad-hoc sub-area prefixes — `OspreySharp:`,
`msconvert:`, `ColorGrid:`, `Volcano plot:`, `SkylineNightlyShim:`. **These are
retired.** Exactly one prefix, always a module. The sub-area belongs in the
prose, where it reads better and does not compete with the title for length:

- ❌ `osprey: OspreySharp: Made the protein razor rollup deterministic`
- ✅ `osprey: Made the OspreySharp protein razor peptide rollup deterministic`
- ❌ `skyline: Volcano plot: Allowed per-trait formatting`
- ✅ `skyline: Allowed independent per-trait formatting in the volcano plot`

### What this does not change

- **Branch naming is unaffected.** `Skyline/work/YYYYMMDD_<name>` is a
  repository-level namespace, not a module marker, and TeamCity configurations
  key off it. Osprey and pwiz work both use `Skyline/work/` branches. Do not
  "helpfully" rename branches to match the module.
- **Release notes are unaffected, and get easier.** `release-guide.md` builds
  Skyline-daily notes from `git log --oneline` and must exclude everything not
  user-visible. The prefix lets that pass drop `osprey:` wholesale and
  concentrate on `skyline:` and `pwiz:`. Step 2 rewrites each line into
  user-facing prose anyway, so the prefix never reaches a user.
- **History is not retroactively fixed.** Commits already on `master` keep
  their untagged titles; this convention only improves the log going forward.

## Commit Message Format

All commits MUST follow this exact format:

```
<Title line in past tense>

* <bullet point 1>
* <bullet point 2>
* <bullet point 3>

Reported by <First>.

See TODO-YYYYMMDD_feature_name.md in pwiz-ai/todos

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
| TODO reference | `See TODO-YYYYMMDD_feature_name.md in pwiz-ai/todos` |
| Co-authorship | Exactly `Co-Authored-By: Claude <noreply@anthropic.com>` |
| Reporter credit | `Reported by <First>.` on its own line when the change came from an outside-the-dev-team report/request; omit for the author's own work or a project developer's request (see below) |
| Total lines | Maximum 10 lines including blank lines (the reporter-credit line does not count against this) |
| Prohibited | Emojis, markdown links |

**The TODO reference carries no path, on purpose.** A TODO moves through
`todos/active/` -> `todos/completed/` -> `todos/completed/YYYY/MM/` by design: `/pw-uptodos-complete`
makes the first move when the PR merges, and `/pw-archivetodos` makes the second, keeping only
the most recent two months at the root. So an `active/` path is wrong from the merge onward and
a `completed/` path expires about two months later - either way the message is wrong shortly
after it is written and stays wrong forever in a public log. Measured on 2026-08-22: of 204 TODOs referenced by recent pwiz
master commits, 3 were still where the message said and 197 were not. The filename is
the durable identifier and `todos` is the deepest folder that is true at every stage;
GitHub's file finder locates the file by name in one step. This applies to the
squash-merge body too, which is the only message that reaches master.

**Do not infer the format from `git log`.** These rules are the format; the history is
not. Messages in the log were written under earlier versions of this guide, or by
sessions that drifted from it, and a single long-lived branch can make one person's
style look like a team norm - in August 2026 a feature branch accumulated 147 commits
with 20-34 line bodies while this cap said 10. Treat a mismatch as a question to raise,
not a licence to follow the majority.

**Strip trailers the tooling appends on its own.** Claude Code ends commit messages with a
`Claude-Session: https://claude.ai/code/session_...` line. Remove it. The URL resolves only
for the developer whose session it was - opening a colleague's gives "This session could not
be found ... you may not have access". **Both pwiz and pwiz-ai are public**, so that is a
permanent link in an open source log which reads as a citation, resolves for one person, and
is dead for every other reader on the internet. The `See TODO-*.md in pwiz-ai/todos` reference
is the supported way to point at the reasoning: pwiz-ai is public too, so it resolves for
anyone. As of 2026-08-22, 45 commits on pwiz-ai master already carry the trailer, exposing 12
session ids; squash-merge has kept it off pwiz master. Existing ones stay - rewriting pushed
public history is not worth it - but do not add more.

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

#### The leading verb is what the DEVELOPER did, not what the code does

This is the trap that being past tense does not catch on its own. A *behavior* verb conjugated
into the past is still grammatically past tense, so it satisfies the rule as written while
describing the product instead of the work. The result reads like a feature narrating itself and
never says what changed.

| Behavior verb in past tense | Developer action |
|---|---|
| "**Judged** each pass-2 decoy against its own q system's boundary" | "**Fixed** pass-2 decoy acceptance to judge each decoy against its own q system's boundary" |
| "**Stripped** Carafe's per-peptide accessions at library load" | "**Added** pre-processing to strip Carafe's per-peptide accessions at library load" |
| "**Reported** the stratum split in the diagnostics panel" | "**Added** a diagnostics row reporting the stratum split" |

Note what happens to the behavior verb in the fixed column: it moves to the **present tense**,
after the action, exactly as the section above prescribes ("Fixed ... **to judge** ...", "Added
pre-processing **to strip** ..."). The two rules compose.

The test: ask **"what did I do?"** The answer is always one of a small set - Added, Fixed,
Removed, Changed, Improved, Refactored, Moved, Renamed, Documented, Enabled, Disabled. If the
leading verb is not one of those, it is almost certainly the feature describing itself, and the
release-notes reader learns nothing about what shipped.

### Example

```
Fixed alert dialog timeout in functional tests

* Added ShowWithTimeout method to catch unexpected dialogs
* Timer closes dialog after 10 seconds in test mode
* Throws TimeoutException with dialog message for debugging

See TODO-20251217_alert_timeout.md in pwiz-ai/todos

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

See TODO-20251217_alert_timeout.md in pwiz-ai/todos

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

## Pull Request Format

**Title**: `<module>: <Title line in past tense>` — see "Module Tagging" above.
**Label**: the matching module label (`skyline`, `pwiz`, or `osprey`).

```bash
gh pr create \
  --title "skyline: Fixed alert dialog timeout in functional tests" \
  --label skyline \
  --body "$(cat <<'EOF'
...
EOF
)"
```

Body:

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

See TODO-YYYYMMDD_feature_name.md in pwiz-ai/todos

Co-Authored-By: Claude <noreply@anthropic.com>
```

If the PR is already open and missing its label, add it without reopening the
description:

```bash
gh pr edit <N> --add-label skyline
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
  `Requested by <First>.`) — above the `See TODO-...` / `Co-Authored-By:`
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
It replaced `pw-self-review`, retired 2026-07-25. That command was written when
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
- [ ] Module prefix (`skyline: ` / `pwiz: ` / `osprey: `) on a PR title or
      squash-merge subject — optional on intermediate branch commits, never on
      `pwiz-ai` commits
- [ ] Module label applied to the PR, matching the prefix
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
gh pr create --base Skyline/skyline_XX_X \
  --title "<module>: Cherry-pick: <title>" \
  --label <module> \
  --body "..."
```

### Cherry-Pick PR Format

**A cherry-pick inherits the original PR's module** — both the label and the
prefix. The prefix leads, before `Cherry-pick:`, so the release branch's log
sorts and greps the same way `master` does:

```
skyline: Cherry-pick: Fixed a NullReferenceException in the chromatogram totals graph
```

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
