---
description: Daily report email phase — compose and send enriched email from research findings
---

# Daily Report — Email Phase

Read research findings from Phase 1, compose an enriched HTML email with investigation results and suggested actions, and send it.

**Read**: [ai/docs/daily-report-guide.md](../../ai/docs/daily-report-guide.md) for email format instructions.

## Arguments

- **Date**: YYYY-MM-DD (optional, defaults to auto-calculated)
- **Recipient**: Email address (optional, defaults to brendanx@proteinms.net)

## Prerequisites

The research phase (`/pw-daily-research`) should have run first. After research, a consolidation step moves output into per-date folders. Files are found in this priority order:

**New location** (after consolidation into `daily/YYYY-MM-DD/`):
- `ai/.tmp/daily/YYYY-MM-DD/manifest.json` — Manifest listing all output files
- `ai/.tmp/daily/YYYY-MM-DD/nightly-report.md` — Nightly test data
- `ai/.tmp/daily/YYYY-MM-DD/exceptions-report.md` — Exception data
- `ai/.tmp/daily/YYYY-MM-DD/support-report.md` — Support data
- `ai/.tmp/daily/YYYY-MM-DD/suggested-actions.md` — Investigation findings
- `ai/.tmp/daily/YYYY-MM-DD/failures.md` — Detailed failure data
- `ai/.tmp/daily/summaries/daily-summary-YYYYMMDD.json` — Summary data

**Fallback** (if consolidation hasn't run):
- `ai/.tmp/daily-manifest-YYYYMMDD.json`
- `ai/.tmp/nightly-report-YYYYMMDD.md`
- `ai/.tmp/exceptions-report-YYYYMMDD.md`
- `ai/.tmp/support-report-YYYYMMDD.md`
- `ai/.tmp/suggested-actions-YYYYMMDD.md`
- `ai/.tmp/failures-YYYYMMDD.md`

If neither location has files, fall back to reading whatever exists for today's date.

---

## Step 1: Determine Date

Same logic as research phase:
- Current time before 8 AM -> yesterday's date; after 8 AM -> today's date
- Or use the date argument if provided

## Step 2: Read Manifest

Try the consolidated location first, then fall back:

1. Try `ai/.tmp/daily/YYYY-MM-DD/manifest.json` (new location)
2. Fall back to `ai/.tmp/daily-manifest-YYYYMMDD.json` (old location)

**If manifest exists:**
- Check `research_completed` — if false, note which phases are missing
- Read all files listed in `files` section (paths may point to either location)
- Use `summary` for quick stats

**If manifest is missing:**
- Log a warning but continue
- Try to read files from new location first, then old:
  - `ai/.tmp/daily/YYYY-MM-DD/nightly-report.md` or `ai/.tmp/nightly-report-YYYYMMDD.md`
  - `ai/.tmp/daily/YYYY-MM-DD/exceptions-report.md` or `ai/.tmp/exceptions-report-YYYYMMDD.md`
  - `ai/.tmp/daily/YYYY-MM-DD/support-report.md` or `ai/.tmp/support-report-YYYYMMDD.md`
  - `ai/.tmp/daily/YYYY-MM-DD/suggested-actions.md` or `ai/.tmp/suggested-actions-YYYYMMDD.md`
  - `ai/.tmp/daily/YYYY-MM-DD/failures.md` or `ai/.tmp/failures-YYYYMMDD.md`
  - `ai/.tmp/daily/summaries/daily-summary-YYYYMMDD.json`
- If none of these exist, the research phase likely didn't run — send a minimal error email

## Step 3: Read Research Findings

Read all available files from the manifest (or fallback list).

**Key files to incorporate:**
- **suggested-actions**: Investigation findings, root cause analyses, GitHub issues created
- **failures**: Detailed failure data with fingerprints
- **daily-summary JSON**: Pattern analysis, counts, classifications

## Step 4: Read Inbox Emails

```
search_emails(query="in:inbox from:skyline@proteinms.net newer_than:2d")
```

Read each email to extract summary statistics from TestResults emails. These provide the primary numbers for the email header.

## Step 5: Compose HTML Email

Follow the email format from [daily-report-guide.md](../../ai/docs/daily-report-guide.md).

**Subject**: `Skyline Daily Summary - Month DD, YYYY`

**CRITICAL**: Use inline styles only (Gmail strips `<style>` blocks when printing).

### Section Order

1. **Header + Quick Status** (one line)
2. **Action Items** (if any urgent items — include links)
3. **Investigation Findings** (from suggested-actions — NEW section)
4. **Support Board**
5. **Exceptions**
6. **Nightly Testing** (failures, leaks, infrastructure)

### Investigation Findings Section (NEW)

If `suggested-actions-YYYYMMDD.md` exists and has content, add an "Investigation Findings" section after Action Items. This is the key enrichment from the research phase.

Format:
```html
<h2 style="color:#2c3e50; border-bottom:2px solid #3498db; padding-bottom:4px; margin-top:16px">
  Investigation Findings
</h2>
<p style="color:#666; font-size:12px; margin:4px 0 8px 0">
  Automated analysis from research phase
</p>
```

For each finding in suggested-actions:
- **GitHub issues created**: Show issue number + title with link
- **Root cause analyses**: Brief summary with key insight
- **Already-fixed items**: Note the PR that fixed it
- **Items needing attention**: Highlight with suggested next step

Keep this section concise — the full details are in the suggested-actions file. Link to the file path for reference.

### Standard Sections

Follow the existing format from daily-report-guide.md:
- **Support**: Threads needing response with linked titles
- **Exceptions**: Table with linked issues, location, version, status
- **Nightly Testing**: Failures, leaks, missing computers

**Enrich exceptions and failures** with investigation data:
- If a finding in suggested-actions matches an exception, add the root cause summary
- If a GitHub issue was created, add the issue link
- If marked as "already fixed", show the FIXED badge with PR link
- If an exception has both a tracked issue AND a fix PR, show both (e.g., "Tracked in #3979, FIXED by PR#3985 + cherry-pick PR#3988")

**CRITICAL: Link all issue and PR references to GitHub.** Every `#XXXX` must link to
`https://github.com/ProteoWizard/pwiz/issues/XXXX` and every `PR#XXXX` must link to
`https://github.com/ProteoWizard/pwiz/pull/XXXX`. Never render bare numbers without hyperlinks.

### Email Recipient

- Use the provided recipient argument, or default to `brendanx@proteinms.net`
- Use `mimeType="multipart/alternative"` with both `body` and `htmlBody`

### Error Email

If research data is completely missing (no nightly report, no MCP data):
- Subject: `[ERROR] Skyline Daily Summary - Month DD, YYYY - Research Phase Incomplete`
- Body: Explain what's missing and suggest running research phase manually

## Step 6: Send Email

```
send_email(
    to=["recipient"],
    subject="Skyline Daily Summary - Month DD, YYYY",
    body="Plain text fallback",
    htmlBody="<full HTML>",
    mimeType="multipart/alternative"
)
```

## Step 7: Archive Processed Emails

Archive the inbox emails that were read in Step 4:

```
batch_modify_emails(messageIds=[...], removeLabelIds=["INBOX"])
```

Only archive emails that were successfully incorporated into the report.

---

## Critical Validation

**Send error email if:**
- No nightly report data exists for today (research phase failed)
- All data files are missing

**Still send partial report if:**
- Some data exists but research was incomplete
- Suggested-actions file is missing (just skip Investigation Findings section)
- Pattern analysis didn't run (skip pattern insights)

## Related

- [ai/docs/daily-report-guide.md](../../ai/docs/daily-report-guide.md) — Full email format instructions
- [pw-daily-research.md](pw-daily-research.md) — Research phase (produces input for this)
- [pw-daily.md](pw-daily.md) — Combined command for interactive use
