---
description: PR activity report research phase — collect PR/issue/TODO data, write findings (no email)
---

# PR Activity Report — Research Phase

Collect developer activity (PRs, issues, TODOs) and write findings to disk.
Phase 1 of two. **Do NOT send email** — that is `/pw-pr-email`.

**Read**: [ai/docs/pr-report-guide.md](../../docs/pr-report-guide.md) — thresholds,
every `gh` invocation, TODO classification, JSON schemas, fan-out slices.

## Arguments

- **Date**: YYYY-MM-DD (default: today)
- **GitHubUser**: focus user (default: `brendanx67`)
- **Fan-out**: when the wrapper signals team mode, build team-wide data **once** plus a
  personal slice per subscriber — see the guide's "Fan-out mode".

## Quick reference

1. `mkdir -p ai/.tmp/pr-report/YYYY-MM-DD`; anchor all "days ago" to the report date
2. PRs awaiting review — two queries, combine, dedupe by number
3. Open PRs by author — pile-up detection, drafts excluded from the count
4. Recent activity (24h) — new PRs, merged PRs, new issues
5. Issue health — assigned, and long-waiting with zero comments
6. TODO inventory — classify, resolve PR references, write `todos-inventory.json`
7. Write `manifest.json`

**Write `pr-findings.md` progressively after each section.** The session can end at any
moment; findings held only in memory are lost.

Empty subsections render `(none)` rather than being omitted — the email phase depends on
stable section structure.

## Related

- `/pw-pr-email` — email phase (consumes this output)
- `/pw-daily-research` — sibling research command (nightly tests + exceptions)
- `/pw-uptodos-complete` — manual sweep for ready-to-complete TODOs
