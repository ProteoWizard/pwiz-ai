---
description: PR activity report email phase — compose and send enriched HTML email from research findings
---

# PR Activity Report — Email Phase

Read research findings from Phase 1, compose an enriched HTML email, and send it.

This is Phase 2 of the two-phase PR-report pipeline. The companion research command is [pw-pr-research.md](pw-pr-research.md).

## Arguments

- **Date**: YYYY-MM-DD (optional, defaults to today)
- **Recipient**: Email address (optional, defaults to `brendanx@proteinms.net`)
- **Level**: `individual` or `team` (optional, defaults to `team` for the single-recipient
  legacy report). Controls how much of the report a recipient sees — see
  [Reporting levels](#reporting-levels) and [Fan-out mode](#fan-out-mode-team-roster).

## Prerequisites

The research phase (`/pw-pr-research`) must have run first. Findings live in:

- `ai/.tmp/pr-report/YYYY-MM-DD/manifest.json` — File list + summary stats
- `ai/.tmp/pr-report/YYYY-MM-DD/pr-findings.md` — Narrative findings
- `ai/.tmp/pr-report/YYYY-MM-DD/prs-awaiting-review.json`
- `ai/.tmp/pr-report/YYYY-MM-DD/prs-open-all.json`
- `ai/.tmp/pr-report/YYYY-MM-DD/issues-recent.json`
- `ai/.tmp/pr-report/YYYY-MM-DD/todos-inventory.json`

If `manifest.json` is missing entirely, send a short error email (see Step 6 below).

---

## Step 1 — Determine date and load manifest

Same logic as research: use today's date unless an explicit date argument is given.

Read `ai/.tmp/pr-report/YYYY-MM-DD/manifest.json`.

- If `research_completed` is `false`, note which phases finished and still send a partial report.
- If the manifest is missing entirely, jump to Step 6 (error email).

## Step 2 — Read research findings

Load every file listed in `manifest.files`. The narrative `pr-findings.md` is the primary input; the JSON files are there if you need structured data (e.g., to format a table of stale PRs, or to count entries for the header).

Use `manifest.summary` for header counts so the email matches the research phase's view of "stale", "pile-up", etc.

## Step 3 — Compose the HTML email

**Subject**: `Skyline PR & TODO Activity - Month DD, YYYY`

**CRITICAL**: Use **inline styles only**. Gmail strips `<style>` blocks when printing the email, and the Markdown Reader Chrome extension is not involved in the email itself — it only renders the `.md` files at the linked raw.githack URLs.

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

1. **🔔 Awaiting your review** (if any) — table with PR#, title, author, days since requested, label chips
2. **⏳ Stale PRs** (open PRs with no update >7d) — grouped by author, each entry linked
3. **👥 Pile-up — may need a nudge** — authors with 3+ open non-draft PRs, oldest age, total count
4. **🆕 Recent activity (last 24h)** — three sub-lists: New PRs, Merged PRs, New issues
5. **📨 Issue health** — open issues assigned to you, long-waiting issues
6. **📋 TODO health** — ready to complete, stale active, abandoned (referenced PR closed unmerged)

If a section has nothing to report, render the heading with a grey "(none)" rather than omitting — keeps the email shape predictable when you skim it across days.

### Recommended visual style

Use the same color palette as the daily report:

```html
<h2 style="color:#2c3e50; border-bottom:2px solid #3498db; padding-bottom:4px; margin-top:16px; font-family:Arial,sans-serif">
  Section title
</h2>
```

Tables for any tabular section:

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
      ...
    </tr>
  </tbody>
</table>
```

### Link conventions (CRITICAL)

Every reference must be a hyperlink — never a bare number.

| Reference | URL pattern |
|-----------|-------------|
| PR #NNNN | `https://github.com/ProteoWizard/pwiz/pull/NNNN` |
| Issue #NNNN | `https://github.com/ProteoWizard/pwiz/issues/NNNN` |
| `@login` (GitHub user) | `https://github.com/login` |
| TODO file (GitHub view) | `https://github.com/ProteoWizard/pwiz-ai/blob/master/<path>` |
| TODO file (raw, for Markdown Reader) | `https://raw.githack.com/ProteoWizard/pwiz-ai/master/<path>` |

For each TODO entry, prefer the raw.githack URL as the **primary** link (the user has Markdown Reader installed and prefers rendered markdown). Include a secondary "(view on GitHub)" link to the github.com URL so the email is still useful if the extension is unavailable.

Example TODO row:

```html
<li style="margin:2px 0">
  <a href="https://raw.githack.com/ProteoWizard/pwiz-ai/master/todos/active/TODO-XXX.md">TODO-XXX.md</a>
  — "Title" — last commit YYYY-MM-DD (N days ago)
  <span style="color:#666">— <a href="https://github.com/ProteoWizard/pwiz-ai/blob/master/todos/active/TODO-XXX.md" style="color:#666">view on GitHub</a></span>
</li>
```

### Stale / urgency badges

Use inline-styled spans:

```html
<span style="background:#fee; color:#a00; padding:2px 6px; border-radius:3px; font-size:11px">STALE</span>
<span style="background:#ffe9b3; color:#7a4d00; padding:2px 6px; border-radius:3px; font-size:11px">14d</span>
<span style="background:#e6f4ea; color:#1e6e3d; padding:2px 6px; border-radius:3px; font-size:11px">READY</span>
```

## Step 4 — Send the email

```
send_email(
    to=["<recipient>"],
    subject="Skyline PR & TODO Activity - Month DD, YYYY",
    body="<plain text fallback summarizing each section>",
    htmlBody="<full HTML body>",
    mimeType="multipart/alternative"
)
```

Recipient: use the argument if provided, otherwise default to `brendanx@proteinms.net`.

Plain-text fallback should be a terse list of the same items (no HTML), suitable for clients that don't render HTML. Include the same hyperlinks (clients will linkify URLs).

## Step 5 — Do NOT archive any inbox emails

Unlike the daily report, this report has no inbox dependency. Do not call any modify or archive Gmail tools.

## Step 6 — Error email (manifest missing)

If `manifest.json` is missing entirely or no findings files exist:

- Subject: `[ERROR] Skyline PR & TODO Activity - Month DD, YYYY - Research Phase Incomplete`
- Body: Short note explaining that research data wasn't found and suggesting:
  ```
  pwsh -File 'ai/scripts/Invoke-PRReport.ps1' -Phase research -Date YYYY-MM-DD
  ```
  to backfill, followed by `-Phase email -Date YYYY-MM-DD`.

Send to the same recipient as a normal report.

## Step 7 — Partial-data handling

If `research_completed` is `false` but some files exist:

- Render whatever sections have data.
- Add a small notice at the top of the email body:
  ```
  Research phase ended early — only [phases that completed] are reported below.
  ```
- Do **not** fabricate missing sections.

---

## Reporting levels

A recipient's **level** controls how much of the report they get. The sections are the same
building blocks described above; the level just selects which ones to render.

| Level | What it contains |
|-------|------------------|
| **team** | The full cross-team report: everyone's open PRs, the pile-up callout, all 24h activity, full TODO health — plus that person's own “awaiting your review” at the top. This is the legacy single-recipient report. |
| **individual** | Just the recipient's own slice: 🔔 awaiting your review, 👤 your open PRs (with the self pile-up warning), 📨 issues assigned to you, 📋 your TODOs. No team-wide pile-up table or other authors' PRs. |

### Self pile-up warning (individual level)

In an individual report, if the recipient's own `my_open_prs.in_pileup` is `true` (their
non-draft open PRs ≥ 3 — the same threshold as the team pile-up callout), render a callout in
the **👤 Your open PRs** section so they see themselves the way the team report would:

```html
<div style="background:#fff4e5; border-left:4px solid #f0ad4e; padding:8px 12px; margin:6px 0; font-family:Arial,sans-serif; font-size:13px">
  <strong>⚠ Pile-up:</strong> you have <strong>N</strong> open non-draft PRs (oldest X days).
  That puts you on the team pile-up list — consider landing some before starting new work.
</div>
```

When `in_pileup` is `false`, omit the callout entirely (don't render an "all clear" banner).

## Fan-out mode (team roster)

When the wrapper runs in **team fan-out** mode (`Invoke-PRReport.ps1 -FanOut`), you send a
**separate, personalized email to each subscriber** in one session.

### Inputs

- `ai/.tmp/pr-report/YYYY-MM-DD/roster-active.json` — `[{ email, github_login, level }, ...]`
- The shared team findings (`manifest.json`, `pr-findings.md`, the team JSONs) — as usual
- `ai/.tmp/pr-report/YYYY-MM-DD/subscribers/<github_login>.json` — that person's personal slice

### Loop

For **each** subscriber in `roster-active.json`:

1. Load their `subscribers/<github_login>.json` personal slice.
2. Compose the HTML email at **their `level`**:
   - `individual` → render only the personal sections from their slice (awaiting review, your
     open PRs + self pile-up warning, your assigned issues, your TODOs). Subject:
     `Skyline PR & TODO Activity (you) - Month DD, YYYY`.
   - `team` → render the full report exactly as the single-recipient version, with their
     `awaiting_review` at the top. Subject: `Skyline PR & TODO Activity - Month DD, YYYY`.
3. `send_email(to=[their email], ...)` — one message per subscriber.

Keep the same inline-styled HTML, link conventions, and badges as the single-recipient report.
If a subscriber's slice file is missing but team findings exist, send them a `team`-level
report (don't skip them silently — note in the plain-text fallback that their personal slice
was unavailable).

### Errors in fan-out

If `manifest.json` is missing entirely (research never ran), send the Step 6 error email **to
each subscriber** so everyone knows the run failed, then stop.

## Related

- [pw-pr-research.md](pw-pr-research.md) — Research phase (produces input for this)
- [pw-daily-email.md](pw-daily-email.md) — Sibling email command (nightly tests + exceptions)
