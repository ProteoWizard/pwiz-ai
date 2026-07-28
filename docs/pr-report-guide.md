# PR & TODO Activity Report Guide

Complete specification for the two-phase PR activity report: what it collects, how it
classifies, and how it renders. This is the knowledge base — the slash commands
`/pw-pr-research` and `/pw-pr-email` are thin entry points into it, and the wrapper
`ai/scripts/Invoke-PRReport.ps1` schedules it.

Everything needed to run the pipeline is here. Nothing in `ai/claude/` is required
reading to perform the task.

## Pipeline shape

Two phases, deliberately separable so a failed send never forces a re-collect:

| Phase | Does | Sends email |
|-------|------|-------------|
| **research** | Collects PR/issue/TODO data, writes findings + JSON to disk | **No** |
| **email** | Reads that output, composes HTML, sends | Yes |

```powershell
pwsh -File './ai/scripts/Invoke-PRReport.ps1' -Phase research -Date YYYY-MM-DD
pwsh -File './ai/scripts/Invoke-PRReport.ps1' -Phase email -Date YYYY-MM-DD
```

All output goes to `ai/.tmp/pr-report/YYYY-MM-DD/`. Write findings **progressively**
after each section — a session can terminate at any moment, and findings held only in
memory are lost.

## Thresholds — the single source of truth

Every threshold used anywhere in the pipeline. Do not restate these numbers in commands
or scripts; reference this table.

| Item | Threshold |
|------|-----------|
| Open PR with no update | **7 days** → stale |
| Active TODO with no commit | **14 days** → stale |
| Author "pile-up" | **3+ open non-draft PRs** |
| "Recent activity" window | **last 24 hours** |
| "Long-waiting" issue | opened **≥7 days** ago, **0 comments** |

**The pile-up threshold is one value with two renderings.** The team report lists an
author in the pile-up callout when their non-draft open PR count reaches it; an
individual report sets `in_pileup` on that person's own slice from the same count. They
must agree, so a recipient who sees "you're on the list" in their personal report finds
themselves on the team list too. Changing the number means changing it *here*.

## Repos in scope

- **PRs and issues**: `ProteoWizard/pwiz`
- **TODOs**: the working tree under `ai/todos/active/` and `ai/todos/backlog/`
  (the `ProteoWizard/pwiz-ai` repo — the wrapper pulls it before the run)

## Reporting levels

A recipient's **level** selects which sections they receive. The sections themselves are
identical building blocks; the level is purely a filter.

| Level | Contains |
|-------|----------|
| **individual** | Only the recipient's slice: PRs awaiting their review, their open PRs (with the self pile-up warning), issues assigned to them, their TODOs. No team-wide pile-up table, no other authors' PRs. |
| **team** | The full cross-team report — everyone's open PRs, the pile-up callout, all 24h activity, full TODO health — with that person's own review queue on top. |

The default differs by entry point, which is intentional: `/pw-pr-reporting` subscribes a
teammate at **individual**, while the legacy single-recipient report runs at **team**.

---

# Research phase

## Output files

| File | Contents |
|------|----------|
| `manifest.json` | File list + summary stats; read by the email phase |
| `pr-findings.md` | Narrative findings, written progressively |
| `prs-awaiting-review.json` | Raw `gh pr list` data for PRs needing review |
| `prs-open-all.json` | Raw `gh pr list` data for all open PRs |
| `issues-recent.json` | Raw `gh issue list` data for recent issues |
| `todos-inventory.json` | Per-file metadata for `active/` and `backlog/` TODOs |

## Step 0 — Setup

Determine the report date (argument or today) and create the output directory:

```bash
mkdir -p ai/.tmp/pr-report/YYYY-MM-DD
```

The focus GitHub user (`$GitHubUser`, default `brendanx67`) drives review-queue
filtering, assigned-issue lookup, and separating their own work from other developers'.

Capture the report date and a now-timestamp at the top of `pr-findings.md`, and compute
every "X days ago" from the **report date**, not from wall-clock time — otherwise a
backfilled run disagrees with the original.

## Step 1 — PRs awaiting review

Two queries; combine and dedupe by PR number.

```bash
# Explicit reviewer, review still requested
gh pr list --repo ProteoWizard/pwiz --state open \
  --search "is:open review-requested:$GitHubUser" \
  --json number,title,author,createdAt,updatedAt,reviewDecision,isDraft,labels,headRefName,url \
  > ai/.tmp/pr-report/YYYY-MM-DD/prs-awaiting-review.json

# Previously commented on but still open — tracked informally, no formal request
gh pr list --repo ProteoWizard/pwiz --state open \
  --search "is:open commenter:$GitHubUser -author:$GitHubUser" \
  --json number,title,author,createdAt,updatedAt,reviewDecision,isDraft,labels,url
```

Write per PR, newest-first by request date, marking anything past the 7-day threshold
**STALE**:

```markdown
### Awaiting your review: PR #NNNN — title
- Author: @login
- Opened: YYYY-MM-DD (N days ago)
- Last update: YYYY-MM-DD (M days ago)
- Status: <reviewDecision or "no review yet">, <draft|ready>
- Labels: [list]
- URL: https://github.com/ProteoWizard/pwiz/pull/NNNN
```

## Step 2 — Open PRs by author (pile-up detection)

```bash
gh pr list --repo ProteoWizard/pwiz --state open --limit 100 \
  --json number,title,author,createdAt,updatedAt,reviewDecision,isDraft,labels,url \
  > ai/.tmp/pr-report/YYYY-MM-DD/prs-open-all.json
```

Group by `author.login`. **Exclude drafts when counting for pile-up** — a draft is not
waiting on anyone. Per author compute: total open (including drafts), non-draft open,
oldest open PR age from `createdAt`, and how many are stale.

```markdown
## Open PRs by author

### @login — N open (M non-draft)
- Oldest: PR #NNNN, opened YYYY-MM-DD (X days)
- Stale (>7d no update): K
- All open PRs:
  - PR #NNNN — title — opened YYYY-MM-DD, updated YYYY-MM-DD (status, [draft])
```

Then the pile-up callout, for authors at or above the threshold:

```markdown
## Pile-up — may need a nudge to land before starting next

- **@login** — N non-draft open PRs, oldest X days. Suggest checking in.
```

**Exclude the focus user from this callout** — their own work is surfaced elsewhere and
is not a "nudge someone else" candidate.

## Step 3 — Recent activity (last 24h)

```bash
gh pr list --repo ProteoWizard/pwiz --state open --limit 50 \
  --search "is:open created:>=$(date -d '1 day ago' +%Y-%m-%d)" \
  --json number,title,author,createdAt,url

gh pr list --repo ProteoWizard/pwiz --state merged --limit 50 \
  --search "is:merged merged:>=$(date -d '1 day ago' +%Y-%m-%d)" \
  --json number,title,author,mergedAt,url

gh issue list --repo ProteoWizard/pwiz --state open --limit 50 \
  --search "is:open created:>=$(date -d '1 day ago' +%Y-%m-%d)" \
  --json number,title,author,createdAt,labels,url

# Review activity: use the search API rather than pulling every PR comment and
# filtering by date afterwards.
gh search prs --repo ProteoWizard/pwiz \
  --updated ">=$(date -d '1 day ago' +%Y-%m-%d)" --state open \
  --json number,title,author,updatedAt,url --limit 50
```

`date -d '1 day ago' +%Y-%m-%d` works in Git Bash on Windows. If it does not, compute the
string in PowerShell or substitute an explicit `updated:>=YYYY-MM-DD`.

Render as three sub-lists: newly opened PRs, merged in last 24h, newly opened issues.

## Step 4 — Issue health

```bash
gh issue list --repo ProteoWizard/pwiz --state open --limit 50 \
  --assignee $GitHubUser \
  --json number,title,createdAt,updatedAt,labels,url

gh search issues --repo ProteoWizard/pwiz --state open \
  --created "<=$(date -d '7 days ago' +%Y-%m-%d)" \
  --comments 0 --json number,title,author,createdAt,url --limit 30
```

**When a subsection is empty, write `(none)` rather than omitting the heading.** The
email phase relies on stable section structure.

## Step 5 — TODO inventory

The most involved step. For every `.md` under `ai/todos/active/` and `ai/todos/backlog/`
— recursive, including per-developer subfolders:

```bash
# Last commit timestamp
git -C ai log -1 --format=%cI -- todos/active/TODO-XXX.md

# Creator (first add)
git -C ai log --diff-filter=A --format=%an --reverse -- todos/active/TODO-XXX.md | head -1
```

Grep each file for `PR #NNNN`, `pull/NNNN`, or `#NNNN`, and resolve each reference:

```bash
gh pr view NNNN --repo ProteoWizard/pwiz \
  --json number,state,mergedAt,closedAt,title,url \
  --jq '{number, state, mergedAt, closedAt, title, url}'
```

### Classification

| Classification | Criteria |
|----------------|----------|
| **active-fresh** | Active TODO, commit ≤14d ago |
| **active-stale** | Active TODO, commit >14d ago |
| **ready-to-complete** | Active TODO, all referenced PRs merged |
| **abandoned** | Active TODO, referenced PR(s) closed unmerged |
| **backlog** | In `backlog/` — no staleness check; these are parked by design |

### `todos-inventory.json` schema

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

URL helpers, used in both phases:

- `github_url` = `https://github.com/ProteoWizard/pwiz-ai/blob/master/<path>`
- `githack_url` = `https://raw.githack.com/ProteoWizard/pwiz-ai/master/<path>`
  (raw markdown; the recipient has the Markdown Reader extension to render it)

Narrative summary sections: ready-to-complete, stale, abandoned, fresh (**count only** —
names omitted to keep the email tight), and a backlog count.

## Step 6 — Manifest

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
    "prs_awaiting_review": 0, "prs_open_total": 0, "prs_stale": 0,
    "pile_up_authors": [], "new_prs_24h": 0, "merged_prs_24h": 0,
    "new_issues_24h": 0, "issues_assigned_to_user": 0, "long_waiting_issues": 0,
    "todos_ready_to_complete": 0, "todos_active_stale": 0,
    "todos_active_abandoned": 0, "todos_active_fresh": 0
  }
}
```

If the session hits its turn limit mid-run, write the manifest with
`research_completed: false` and list only the phases that finished. The email phase still
sends what exists.

## Failure conditions

**Fail the research** when `gh pr list --repo ProteoWizard/pwiz --state open --limit 1`
returns an auth or network error, or `ai/todos/` is inaccessible. Write a manifest with
`research_completed: false` and a note describing the failure; the email phase detects
this and sends an error notification rather than an empty report.

---

# Email phase

## Prerequisites

Research must have run. If `manifest.json` is missing entirely, send the error email
(below) rather than an empty report.

## Composition rules

**Subject**: `Skyline PR & TODO Activity - Month DD, YYYY`

**Inline styles only.** Gmail strips `<style>` blocks when printing. The Markdown Reader
extension is not involved in the email itself — it only renders the `.md` files at the
linked raw.githack URLs.

Use `manifest.summary` for header counts so the email agrees with the research phase's
view of "stale" and "pile-up".

### Header

A one-line summary, then a quick-stats strip:

```html
<p style="font-family:Arial,sans-serif; color:#333; margin:0 0 8px 0">
  <strong>Skyline PR &amp; TODO Activity</strong> — Month DD, YYYY
</p>
<table style="font-family:Arial,sans-serif; font-size:13px; border-collapse:collapse; margin-bottom:12px">
  <tr>
    <td style="padding:4px 12px 4px 0"><strong>Awaiting your review:</strong> N</td>
    <td style="padding:4px 12px"><strong>Stale PRs:</strong> N</td>
    <td style="padding:4px 12px"><strong>Pile-up authors:</strong> N</td>
    <td style="padding:4px 12px"><strong>New (24h):</strong> N PRs / M issues</td>
    <td style="padding:4px 12px"><strong>Stale TODOs:</strong> N</td>
    <td style="padding:4px 0 4px 12px"><strong>Ready to complete:</strong> N</td>
  </tr>
</table>
```

### Section order

1. **🔔 Awaiting your review** — table with PR#, title, author, days since requested, label chips
2. **⏳ Stale PRs** — open PRs past the 7-day threshold, grouped by author, each linked
3. **👥 Pile-up — may need a nudge** — authors at the pile-up threshold, oldest age, total count
4. **🆕 Recent activity (last 24h)** — new PRs, merged PRs, new issues
5. **📨 Issue health** — issues assigned to the recipient, long-waiting issues
6. **📋 TODO health** — ready to complete, stale active, abandoned

**A section with nothing to report renders its heading with a grey "(none)"** rather than
being omitted — this keeps the email's shape predictable when skimmed across days.

### Visual style

```html
<h2 style="color:#2c3e50; border-bottom:2px solid #3498db; padding-bottom:4px; margin-top:16px; font-family:Arial,sans-serif">
  Section title
</h2>
```

```html
<table style="font-family:Arial,sans-serif; font-size:13px; border-collapse:collapse; width:100%; margin:6px 0">
  <thead>
    <tr style="background:#f6f8fa">
      <th style="text-align:left; padding:6px 8px; border-bottom:1px solid #d0d7de">PR</th>
      <th style="text-align:left; padding:6px 8px; border-bottom:1px solid #d0d7de">Title</th>
      <th style="text-align:left; padding:6px 8px; border-bottom:1px solid #d0d7de">Author</th>
      <th style="text-align:right; padding:6px 8px; border-bottom:1px solid #d0d7de">Age</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td style="padding:6px 8px; border-bottom:1px solid #eaecef"><a href="https://github.com/ProteoWizard/pwiz/pull/NNNN">#NNNN</a></td>
    </tr>
  </tbody>
</table>
```

### Link conventions

**Every reference is a hyperlink — never a bare number.**

| Reference | URL pattern |
|-----------|-------------|
| PR #NNNN | `https://github.com/ProteoWizard/pwiz/pull/NNNN` |
| Issue #NNNN | `https://github.com/ProteoWizard/pwiz/issues/NNNN` |
| `@login` | `https://github.com/login` |
| TODO (GitHub view) | `https://github.com/ProteoWizard/pwiz-ai/blob/master/<path>` |
| TODO (raw, for Markdown Reader) | `https://raw.githack.com/ProteoWizard/pwiz-ai/master/<path>` |

For TODO entries the **raw.githack URL is primary** (the recipient prefers rendered
markdown), with a secondary "(view on GitHub)" link so the email still works if the
extension is unavailable:

```html
<li style="margin:2px 0">
  <a href="https://raw.githack.com/ProteoWizard/pwiz-ai/master/todos/active/TODO-XXX.md">TODO-XXX.md</a>
  — "Title" — last commit YYYY-MM-DD (N days ago)
  <span style="color:#666">— <a href="https://github.com/ProteoWizard/pwiz-ai/blob/master/todos/active/TODO-XXX.md" style="color:#666">view on GitHub</a></span>
</li>
```

### Badges

```html
<span style="background:#fee; color:#a00; padding:2px 6px; border-radius:3px; font-size:11px">STALE</span>
<span style="background:#ffe9b3; color:#7a4d00; padding:2px 6px; border-radius:3px; font-size:11px">14d</span>
<span style="background:#e6f4ea; color:#1e6e3d; padding:2px 6px; border-radius:3px; font-size:11px">READY</span>
```

### Self pile-up warning (individual level)

When the recipient's own `my_open_prs.in_pileup` is true, render this inside the
**👤 Your open PRs** section so they see themselves as the team report would. When it is
false, **omit the callout entirely** — do not render an "all clear" banner.

```html
<div style="background:#fff4e5; border-left:4px solid #f0ad4e; padding:8px 12px; margin:6px 0; font-family:Arial,sans-serif; font-size:13px">
  <strong>⚠ Pile-up:</strong> you have <strong>N</strong> open non-draft PRs (oldest X days).
  That puts you on the team pile-up list — consider landing some before starting new work.
</div>
```

## Sending

```
send_email(
    to=["<recipient>"],
    subject="Skyline PR & TODO Activity - Month DD, YYYY",
    body="<plain text fallback summarizing each section>",
    htmlBody="<full HTML body>",
    mimeType="multipart/alternative"
)
```

Default recipient is `brendanx@proteinms.net`. The plain-text fallback is a terse list of
the same items with the same URLs (clients linkify them).

**This report has no inbox dependency** — unlike the daily report, never call Gmail
modify or archive tools.

## Error and partial handling

**Manifest missing entirely** — subject
`[ERROR] Skyline PR & TODO Activity - Month DD, YYYY - Research Phase Incomplete`, body
explaining research data was not found and suggesting the backfill:

```powershell
pwsh -File './ai/scripts/Invoke-PRReport.ps1' -Phase research -Date YYYY-MM-DD
```

followed by the same command with `-Phase email`.

**`research_completed: false` but some files exist** — render the sections that have
data, add a notice at the top ("Research phase ended early — only [phases] are reported
below"), and **do not fabricate the missing sections**.

---

# Fan-out mode (team roster)

`Invoke-PRReport.ps1 -FanOut` sends a separate, personalized email to every subscriber in
one session. Research runs **once**; only the personal slices are per-person.

## Roster

`ai/.tmp/pr-report/YYYY-MM-DD/roster-active.json`:

```json
[ { "email": "jdoe@proteinms.net", "github_login": "jdoe", "level": "individual" } ]
```

## Research in fan-out

Steps 1–6 become **login-agnostic**: gather the raw superset once (`prs-open-all.json`,
`issues-recent.json`, `todos-inventory.json`, recent activity, the per-author pile-up
table) so any subscriber's slice derives from it. Do **not** key Step 1 to a single user;
produce one review queue per subscriber instead.

For each subscriber write
`ai/.tmp/pr-report/YYYY-MM-DD/subscribers/<github_login>.json`. Only the review queue and
assigned issues need a per-login query:

```bash
gh pr list --repo ProteoWizard/pwiz --state open \
  --search "is:open review-requested:<login>" \
  --json number,title,author,createdAt,updatedAt,reviewDecision,isDraft,labels,headRefName,url

gh issue list --repo ProteoWizard/pwiz --state open --limit 50 --assignee <login> \
  --json number,title,createdAt,updatedAt,labels,url
```

### Per-subscriber slice schema

```json
{
  "github_login": "jdoe",
  "awaiting_review": [ { "number": 0, "title": "", "author": "", "requested_days": 0, "stale": false, "url": "" } ],
  "my_open_prs": {
    "total": 0, "non_draft": 0, "oldest_days": 0, "stale": 0,
    "in_pileup": false,
    "prs": [ { "number": 0, "title": "", "isDraft": false, "updated_days": 0, "url": "" } ]
  },
  "my_assigned_issues": [ { "number": 0, "title": "", "opened_days": 0, "url": "" } ],
  "my_todos": [ { "path": "", "title": "", "classification": "", "url": "", "githack_url": "" } ]
}
```

- **`in_pileup`** comes from `prs-open-all.json` — filter `author.login == <login>`,
  exclude drafts, compare against the pile-up threshold in the thresholds table. It must
  use that same value so "you're on the list" matches the team callout exactly.
- **`my_todos`** filters `todos-inventory.json` by creator mapping to this person, or by
  a `todos/active/<login>/` subfolder. Mapping a git author name to a GitHub login is
  best-effort — **when unsure, omit rather than misattribute**.
- An empty slice is fine; the render shows "(none)".

Add a `subscribers` array to `manifest.json` listing the logins produced, alongside the
team-wide `summary`.

## Email in fan-out

For each subscriber: load their slice, compose at **their level**, send one message.

| Level | Subject | Renders |
|-------|---------|---------|
| `individual` | `Skyline PR & TODO Activity (you) - Month DD, YYYY` | Personal sections only, including the self pile-up warning |
| `team` | `Skyline PR & TODO Activity - Month DD, YYYY` | Full report with their `awaiting_review` on top |

Same inline styles, link conventions and badges as the single-recipient report.

**If a subscriber's slice is missing but team findings exist, send them a `team`-level
report** — do not skip them silently; note in the plain-text fallback that their personal
slice was unavailable.

**If `manifest.json` is missing entirely**, send the error email to **each** subscriber so
everyone knows the run failed, then stop.

## Roster store

Subscription management (`/pw-pr-reporting`) reads and writes a **shared** roster store on
Google Drive, identified by a `TEAM-STORE-ID.txt` marker whose first line is
`SKYLINE-TEAM-PRREPORT-STORE`. Setup, the private-duplicate failure mode, and the
Drive-sharing fix are documented in `../scripts/PRReport/README.md`, which owns that
material.

## Related

- `daily-report-guide.md` — the sibling nightly-tests/exceptions pipeline this mirrors
- `scheduled-tasks-guide.md` — how these reports are scheduled
- `../scripts/PRReport/README.md` — roster store, central host, Drive sharing
