---
description: PR activity report email phase — compose and send enriched HTML email from research findings
---

# PR Activity Report — Email Phase

Read the research findings, compose an enriched HTML email, send it.
Phase 2 of two. The research phase is `/pw-pr-research`.

**Read**: [ai/docs/pr-report-guide.md](../../docs/pr-report-guide.md) — section order,
inline-style rules, link conventions, badges, reporting levels, fan-out loop.

## Arguments

- **Date**: YYYY-MM-DD (default: today)
- **Recipient**: email address (default: `brendanx@proteinms.net`)
- **Level**: `individual` or `team` (default: `team` for the single-recipient report)

## Quick reference

1. Load `ai/.tmp/pr-report/YYYY-MM-DD/manifest.json` — missing entirely → error email
2. Read the findings listed in `manifest.files`; take header counts from `manifest.summary`
3. Compose HTML — **inline styles only**, Gmail strips `<style>` blocks when printing
4. `send_email(...)` with `mimeType="multipart/alternative"` and a plain-text fallback

**Never call Gmail modify or archive tools** — unlike the daily report, this pipeline has
no inbox dependency.

**Partial data**: `research_completed: false` → render what exists, add a notice naming
the phases that finished, and do not fabricate the rest.

## Related

- `/pw-pr-research` — research phase (produces this input)
- `/pw-daily-email` — sibling email command (nightly tests + exceptions)
