---
description: PR activity report research phase — collect PR/issue/TODO data, write findings (no email)
---

# PR Activity Report — Research Phase

Collect data on developer activity (PRs, issues, TODOs) and write all findings to files.
This is Phase 1 of the two-phase PR-report pipeline. **Do NOT send email.**

The companion email phase is [pw-pr-email.md](pw-pr-email.md).

## Arguments

- **Date**: YYYY-MM-DD (optional, defaults to today)
- **GitHubUser**: Focus user for review queue and authored items (default: `brendanx67`)
- **Fan-out** (optional): when the wrapper signals team fan-out mode, you build the team-wide
  data **once** plus a personal slice for every subscriber in the roster. See
  [Fan-out mode](#fan-out-mode-team-roster) at the end — do the normal steps below first, then
  the per-subscriber step.

## Output

All files go directly into `ai/.tmp/pr-report/YYYY-MM-DD/`:

- `manifest.json` — File list + summary stats (read by the email phase)
- `pr-findings.md` — Narrative findings, written progressively
- `prs-awaiting-review.json` — Raw `gh pr list` data for PRs needing your review
- `prs-open-all.json` — Raw `gh pr list` data for all open PRs
- `issues-recent.json` — Raw `gh issue list` data for recent issues
- `todos-inventory.json` — Per-file metadata for active/ and backlog/ TODOs

Write findings to `pr-findings.md` **progressively** after each section completes. The session may terminate at any moment — never accumulate findings only in memory.

---

## Stale Thresholds (defaults)

These thresholds are referenced throughout the workflow. Keep them consistent in `pr-findings.md` so the email phase can render them.

| Item | Stale threshold |
|------|-----------------|
| Open PR with no update | **7 days** |
| Active TODO with no commit | **14 days** |
| Author "pile-up" | **3+ open non-draft PRs** |
| "Recent activity" window | **last 24 hours** |
| "Long-waiting" issue | **opened ≥7 days ago, no comment** |

---

## Repos in scope

- **PRs and Issues**: `ProteoWizard/pwiz` (the Skyline / pwiz codebase)
- **TODOs**: working tree under `ai/todos/active/` and `ai/todos/backlog/` (the `ProteoWizard/pwiz-ai` repo, already pulled by the wrapper script)

---

## Step 0 — Setup

Determine the report date (argument or today). Create the output directory if missing:

```bash
mkdir -p ai/.tmp/pr-report/YYYY-MM-DD
```

The focus GitHub user (`$GitHubUser`, default `brendanx67`) is used for:
- Filtering PRs awaiting their review
- Identifying issues assigned to them
- Marking their own PRs/TODOs separately from other developers'

Time-anchor: capture the report date and now-timestamp at the top of `pr-findings.md`. Use the report date for all "X days ago" computations.

---

## Step 1 — PRs awaiting your review

Two queries — combine results, dedupe by PR number.

```bash
# PRs where you are an explicit reviewer and review is still requested
gh pr list --repo ProteoWizard/pwiz --state open \
  --search "is:open review-requested:$GitHubUser" \
  --json number,title,author,createdAt,updatedAt,reviewDecision,isDraft,labels,headRefName,url \
  > ai/.tmp/pr-report/YYYY-MM-DD/prs-awaiting-review.json

# PRs you previously reviewed/commented on but that are still open (you may be
# tracking them informally without a formal review request)
gh pr list --repo ProteoWizard/pwiz --state open \
  --search "is:open commenter:$GitHubUser -author:$GitHubUser" \
  --json number,title,author,createdAt,updatedAt,reviewDecision,isDraft,labels,url
```

For each PR awaiting your review, write to `pr-findings.md`:

```markdown
### Awaiting your review: PR #NNNN — title
- Author: @login
- Opened: YYYY-MM-DD (N days ago)
- Last update: YYYY-MM-DD (M days ago)
- Status: <reviewDecision or "no review yet">, <draft|ready>
- Labels: [list]
- URL: https://github.com/ProteoWizard/pwiz/pull/NNNN
```

Sort newest-first by request date. Mark anything older than the stale threshold as **STALE**.

---

## Step 2 — Open PRs by author (pile-up detection)

```bash
gh pr list --repo ProteoWizard/pwiz --state open --limit 100 \
  --json number,title,author,createdAt,updatedAt,reviewDecision,isDraft,labels,url \
  > ai/.tmp/pr-report/YYYY-MM-DD/prs-open-all.json
```

Read the JSON, group by `author.login`, exclude drafts when counting for pile-up.

Compute per author:
- Total open PRs (incl. drafts)
- Non-draft open PRs
- Oldest open PR age (in days from `createdAt`)
- Number stale (no update >7 days)

Write to `pr-findings.md`:

```markdown
## Open PRs by author

### @login — N open (M non-draft)
- Oldest: PR #NNNN, opened YYYY-MM-DD (X days)
- Stale (>7d no update): K
- All open PRs:
  - PR #NNNN — title — opened YYYY-MM-DD, updated YYYY-MM-DD (status, [draft])
  - ...
```

After the per-author list, write a **Pile-up callout** section listing any author with **3+ non-draft open PRs**. This is the "may need a nudge" list:

```markdown
## Pile-up — may need a nudge to land before starting next

- **@login** — N non-draft open PRs, oldest X days. Suggest checking in.
```

Exclude the focus user (`$GitHubUser`) from the pile-up callout — their own work isn't a "nudge" candidate, it's surfaced elsewhere.

---

## Step 3 — Recent activity (last 24 hours)

```bash
# Newly opened PRs
gh pr list --repo ProteoWizard/pwiz --state open --limit 50 \
  --search "is:open created:>=$(date -d '1 day ago' +%Y-%m-%d)" \
  --json number,title,author,createdAt,url

# Recently merged PRs (last 24h)
gh pr list --repo ProteoWizard/pwiz --state merged --limit 50 \
  --search "is:merged merged:>=$(date -d '1 day ago' +%Y-%m-%d)" \
  --json number,title,author,mergedAt,url

# Newly opened issues
gh issue list --repo ProteoWizard/pwiz --state open --limit 50 \
  --search "is:open created:>=$(date -d '1 day ago' +%Y-%m-%d)" \
  --json number,title,author,createdAt,labels,url

# Recent PR review activity — pulls *every* PR comment, then filter by date in code.
# Use the search API instead for efficiency:
gh search prs --repo ProteoWizard/pwiz \
  --updated ">=$(date -d '1 day ago' +%Y-%m-%d)" --state open \
  --json number,title,author,updatedAt,url --limit 50
```

(On Windows in git-bash, `date -d '1 day ago' +%Y-%m-%d` works. If it doesn't,
compute the date string in PowerShell or fall back to `--search "updated:>=YYYY-MM-DD"`
with the explicit date.)

Write to `pr-findings.md`:

```markdown
## Recent activity (last 24h)

### Newly opened PRs
- PR #NNNN — title — @author — URL

### Merged in last 24h
- PR #NNNN — title — @author — URL

### Newly opened issues
- Issue #NNNN — title — @author — URL
```

---

## Step 4 — Issue health

```bash
# Issues assigned to focus user, any state
gh issue list --repo ProteoWizard/pwiz --state open --limit 50 \
  --assignee $GitHubUser \
  --json number,title,createdAt,updatedAt,labels,url

# Long-waiting open issues (≥7 days old, no comments yet)
gh search issues --repo ProteoWizard/pwiz --state open \
  --created "<=$(date -d '7 days ago' +%Y-%m-%d)" \
  --comments 0 --json number,title,author,createdAt,url --limit 30
```

Write to `pr-findings.md`:

```markdown
## Issue health

### Open issues assigned to you (@$GitHubUser)
- Issue #NNNN — title — opened YYYY-MM-DD — labels: [...]

### Long-waiting issues (≥7d old, no comments)
- Issue #NNNN — title — @author — opened YYYY-MM-DD (X days ago)
```

If no items in a subsection, write `(none)` rather than omitting the heading — the email phase relies on stable section structure.

---

## Step 5 — TODO inventory

This is the most code-heavy step. For each `.md` file under `ai/todos/active/` and `ai/todos/backlog/` (recursive, including the `brendanx67/` and similar developer subfolders):

1. **Last commit timestamp** for the file:
   ```bash
   git -C ai log -1 --format=%cI -- todos/active/TODO-XXX.md
   ```

2. **Creator** (first add):
   ```bash
   git -C ai log --diff-filter=A --format=%an --reverse -- todos/active/TODO-XXX.md | head -1
   ```

3. **PR references inside the TODO file** — grep the file for `PR #NNNN`, `pull/NNNN`, or `#NNNN`. For each reference, check the PR state:
   ```bash
   gh pr view NNNN --repo ProteoWizard/pwiz \
     --json number,state,mergedAt,closedAt,title,url \
     --jq '{number, state, mergedAt, closedAt, title, url}'
   ```

Classify each TODO:

| Classification | Criteria |
|----------------|----------|
| **active-fresh** | Active TODO, commit ≤14d ago |
| **active-stale** | Active TODO, commit >14d ago |
| **ready-to-complete** | Active TODO, all referenced PRs merged |
| **abandoned** | Active TODO, referenced PR(s) closed unmerged |
| **backlog** | In backlog/ — no staleness check (they're parked by design) |

Save the inventory to `ai/.tmp/pr-report/YYYY-MM-DD/todos-inventory.json` as a list of objects:

```json
[
  {
    "path": "todos/active/TODO-20260219_precision_filtering.md",
    "title": "Precision filtering",
    "classification": "active-stale",
    "creator": "Brendan MacLean",
    "last_commit": "2026-04-12T15:30:00-07:00",
    "days_since_commit": 35,
    "pr_references": [{"number": 3812, "state": "OPEN", "url": "..."}],
    "github_url": "https://github.com/ProteoWizard/pwiz-ai/blob/master/todos/active/TODO-20260219_precision_filtering.md",
    "githack_url": "https://raw.githack.com/ProteoWizard/pwiz-ai/master/todos/active/TODO-20260219_precision_filtering.md"
  }
]
```

URL helpers:
- `github_url` = `https://github.com/ProteoWizard/pwiz-ai/blob/master/<path>`
- `githack_url` = `https://raw.githack.com/ProteoWizard/pwiz-ai/master/<path>` (raw markdown; the user has Markdown Reader installed to render this)

Then write a narrative summary to `pr-findings.md`:

```markdown
## TODO health

### Ready to complete (PRs already merged)
- todos/active/TODO-XXX.md — "Title" — merged by PR #NNNN
  - GitHub: <github_url>
  - Render: <githack_url>

### Active TODOs — stale (>14d no commit)
- todos/active/TODO-XXX.md — "Title" — last commit YYYY-MM-DD (N days ago) — @creator

### Active TODOs — abandoned (referenced PR closed unmerged)
- todos/active/TODO-XXX.md — "Title" — PR #NNNN closed YYYY-MM-DD

### Active TODOs — fresh (≤14d)
- (count only — N TODOs, names omitted to keep the email tight)

### Backlog summary
- N TODOs in shared backlog/, M in per-developer subfolders.
```

---

## Step 6 — Write the manifest

After all sections are written, save `ai/.tmp/pr-report/YYYY-MM-DD/manifest.json`:

```json
{
  "date": "YYYY-MM-DD",
  "github_user": "brendanx67",
  "research_completed": true,
  "phases_completed": ["awaiting_review", "open_prs_by_author", "recent_activity", "issue_health", "todo_inventory"],
  "files": {
    "findings": "ai/.tmp/pr-report/YYYY-MM-DD/pr-findings.md",
    "prs_awaiting_review": "ai/.tmp/pr-report/YYYY-MM-DD/prs-awaiting-review.json",
    "prs_open_all": "ai/.tmp/pr-report/YYYY-MM-DD/prs-open-all.json",
    "issues_recent": "ai/.tmp/pr-report/YYYY-MM-DD/issues-recent.json",
    "todos_inventory": "ai/.tmp/pr-report/YYYY-MM-DD/todos-inventory.json"
  },
  "summary": {
    "prs_awaiting_review": 0,
    "prs_open_total": 0,
    "prs_stale": 0,
    "pile_up_authors": [],
    "new_prs_24h": 0,
    "merged_prs_24h": 0,
    "new_issues_24h": 0,
    "issues_assigned_to_user": 0,
    "long_waiting_issues": 0,
    "todos_ready_to_complete": 0,
    "todos_active_stale": 0,
    "todos_active_abandoned": 0,
    "todos_active_fresh": 0
  }
}
```

If the session hits its turn limit mid-investigation, write the manifest with `research_completed: false` and list only the phases that completed. The email phase will still send what's available.

---

## Critical validation

**FAIL the research if:**
- `gh pr list --repo ProteoWizard/pwiz --state open --limit 1` returns an authentication or network error
- The working tree at `ai/todos/` is not accessible

Write a manifest with `research_completed: false` and a brief note describing what failed; the email phase will detect this and send an error notification.

---

## Fan-out mode (team roster)

When the wrapper runs in **team fan-out** mode (`Invoke-PRReport.ps1 -FanOut`), the report is
sent to multiple teammates, each customized to *their* GitHub login and reporting level. You
run **once** and produce: (a) the same team-wide findings as above (gathered exactly once),
and (b) a small **personal slice** for each subscriber.

### Inputs

Read `ai/.tmp/pr-report/YYYY-MM-DD/roster-active.json` — an array of active subscribers:

```json
[ { "email": "jdoe@proteinms.net", "github_login": "jdoe", "level": "individual" }, ... ]
```

The team-wide steps (1–6 above) are **login-agnostic** in fan-out mode: gather the raw
superset once (`prs-open-all.json`, `issues-recent.json`, `todos-inventory.json`, recent
activity, and the per-author pile-up table) so any subscriber's slice can be derived from it.
Do **not** key Step 1 (“awaiting your review”) to a single user — instead produce one review
queue per subscriber below.

### Per-subscriber slice

For **each** subscriber, write `ai/.tmp/pr-report/YYYY-MM-DD/subscribers/<github_login>.json`.
Derive most of it from the raw data you already gathered; only the review queue and assigned
issues need a per-login `gh` query:

```bash
# Awaiting THIS person's review (combine + dedupe, same as Step 1 but per login)
gh pr list --repo ProteoWizard/pwiz --state open \
  --search "is:open review-requested:<login>" \
  --json number,title,author,createdAt,updatedAt,reviewDecision,isDraft,labels,headRefName,url

# Open issues assigned to this person
gh issue list --repo ProteoWizard/pwiz --state open --limit 50 --assignee <login> \
  --json number,title,createdAt,updatedAt,labels,url
```

Each `<github_login>.json` has this shape:

```json
{
  "github_login": "jdoe",
  "awaiting_review": [ { "number": 0, "title": "", "author": "", "requested_days": 0, "stale": false, "url": "" } ],
  "my_open_prs": {
    "total": 0, "non_draft": 0, "oldest_days": 0, "stale": 0,
    "in_pileup": false,                // true when non_draft >= 3 (matches the team pile-up threshold)
    "prs": [ { "number": 0, "title": "", "isDraft": false, "updated_days": 0, "url": "" } ]
  },
  "my_assigned_issues": [ { "number": 0, "title": "", "opened_days": 0, "url": "" } ],
  "my_todos": [ { "path": "", "title": "", "classification": "", "url": "", "githack_url": "" } ]
}
```

Notes:
- **`in_pileup`** is the self pile-up warning: `my_open_prs.non_draft >= 3`. Compute it from
  `prs-open-all.json` (filter `author.login == <login>`, exclude drafts) — same threshold as
  the team-wide pile-up callout, so “you’re on the list” matches exactly.
- **`my_todos`**: filter `todos-inventory.json` to TODOs whose `creator` maps to this person,
  or that live under a `todos/active/<login>/` (or matching name) subfolder. Mapping git author
  name → GitHub login is best-effort; when unsure, omit rather than misattribute.
- A subscriber with an empty slice everywhere is fine — render still shows “(none)”.

### Manifest

Add a `subscribers` array to `manifest.json` listing the logins you produced slices for, e.g.
`"subscribers": ["jdoe", "brendanx67"]`, alongside the normal team-wide `summary`.

## Related

- [pw-pr-email.md](pw-pr-email.md) — Email phase (reads this output; renders per level in fan-out)
- [pw-daily-research.md](pw-daily-research.md) — Sibling research command (nightly tests + exceptions)
- [pw-uptodos-complete.md](pw-uptodos-complete.md) — Manual sweep for ready-to-complete TODOs
