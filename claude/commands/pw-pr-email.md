---
description: PR activity report email phase — compose and send enriched HTML email from research findings
---

# PR Activity Report — Email Phase

Read research findings from Phase 1, compose an enriched HTML email, and send it.

This is Phase 2 of the two-phase PR-report pipeline. The companion research command is [pw-pr-research.md](pw-pr-research.md).

## Arguments

- **Date**: YYYY-MM-DD (optional, defaults to today)
- **Recipient**: Email address (optional, defaults to `brendanx@proteinms.net`)

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

## Related

- [pw-pr-research.md](pw-pr-research.md) — Research phase (produces input for this)
- [pw-daily-email.md](pw-daily-email.md) — Sibling email command (nightly tests + exceptions)
