# TODO-20260625_pr_report_team_optin.md

## Repo / Branch
- **Repo**: pwiz-ai (`ai/`) — committed directly to `master`, no feature branch (doc/tooling).
- **Created**: 2026-06-25
- **Status**: Completed (2026-07-10) — opt-in live (3 subscribers); daily fan-out runs on BRENDANX-UW6
- **PR**: (none — pwiz-ai master)

# Team opt-in for the PR & TODO activity report (central fan-out)

**Goal**: let teammates opt in to a daily PR/Issue/TODO email, the way they opt in to usage
tracking — but without each machine running its own heavy `claude -p` report.

## Decisions (locked with brendanx, 2026-06-25)
- **Architecture: central fan-out.** One host (brendanx's) runs research **once** daily, then a
  single email session loops a **shared roster** and sends each subscriber a personalized email.
  Teammates run nothing locally — opt-in just writes a roster row. (The report's research is
  ~80% team-wide, so per-machine full runs would be wasteful.)
- **Reporting level per subscriber**: `individual` = personal slice only (awaiting your review,
  your open PRs, assigned issues, your TODOs); `team` = the full cross-team report.
- **Self pile-up warning** in the individual report when the recipient's non-draft open PRs
  **≥ 3** — the *same* threshold as the team-wide pile-up callout (so "you're on the list"
  matches exactly). Brendan: keep the threshold at **3** (not 4).
- **Default level for a new opt-in: `individual`.**
- **Roster keyed by email** (lower-cased); `off` keeps the row as history (`active=false`).
- Shared data lives in `Claude\PRReport\` (sibling of `Claude\Usage`); marker first line
  `SKYLINE-TEAM-PRREPORT-STORE` proves the shared store vs a private duplicate.

## Done (code complete)
- [x] `ai/scripts/PRReport/PRReportStore.ps1` — library: `Resolve-ClaudeStore` /
      `Resolve-PRReportStore` (drive scan + Drive-shortcut following, `$env:PRREPORT_STORE`
      override), `Test-PRReportStore` (marker check), roster read/write
      (`Get-PRReportRoster -ActiveOnly`, atomic `Save-PRReportRoster`, `Set-PRReportSubscriber`
      upsert, `Disable-PRReportSubscriber`), `Resolve-DefaultUserEmail`.
- [x] `ai/scripts/PRReport/Manage-PRReportRoster.ps1` — CLI: `add|remove|list|status`, email
      auto-derive, shared-store preflight on writes. Smoke-tested (add/upsert/list/status/remove).
- [x] `ai/scripts/Invoke-PRReport.ps1` — added `-FanOut`: resolves the active roster, writes
      `roster-active.json` to the date folder, no-ops on empty roster, turn budgets scale with
      roster size (research `80+12N≤250`, email `30+15N≤220`), fan-out-aware prompts, and
      `-Schedule -FanOut` registers **"PR Report - Fanout"** (removing the single-recipient tasks
      so a machine never runs both). Single-recipient mode unchanged (back-compat). Dry-runs pass.
- [x] `.claude/commands/pw-pr-research.md` — **Fan-out mode** section: gather team-wide raw once
      + per-subscriber `subscribers/<login>.json` slice (review queue, open PRs + `in_pileup`,
      assigned issues, TODOs), `subscribers` list in manifest.
- [x] `.claude/commands/pw-pr-email.md` — **Reporting levels** + self pile-up callout + **Fan-out
      mode** loop (one personalized email per subscriber at their level).
- [x] `.claude/commands/pw-pr-reporting.md` — `/pw-pr-reporting on|off|status` (mirrors
      `/pw-usage-reporting`; preflight on shared-store marker; writes the roster, schedules nothing).
- [x] `ai/scripts/PRReport/README.md` + `ai/docs/scheduled-tasks-guide.md` updates.

## Remaining
- [x] **Seed the live shared store**: `Claude\PRReport\TEAM-STORE-ID.txt`
      (`SKYLINE-TEAM-PRREPORT-STORE`) created 2026-06-25; brendanx67 added at `team` level.
- [x] **Migrate the schedule**: the `-FanOut` fan-out task runs daily on **BRENDANX-UW6** (the
      single owner machine), so no dev box runs the heavy report.
- [x] **End-to-end test**: confirmed live — the daily fan-out produces the per-subscriber slices
      and sends each subscriber their email from BRENDANX-UW6.
- [x] **Share the `Claude` folder** + announce `/pw-pr-reporting on`: done — bspratt and chambm
      opted in from their own machines (2026-06-30 / 07-06).
- [ ] Run `ai/scripts/Generate-TOC.ps1` — deferred to the weekly sync (the TODO's sanctioned
      option), which will land the new `ai/scripts/PRReport/` files in TOC.md.

## Refs
- Pattern mirrored: `ai/scripts/Usage/` (Resolve-UsageStore, Setup-ThisMachine,
  `.claude/commands/pw-usage-reporting.md`).
- Engine: `ai/scripts/Invoke-PRReport.ps1`; command files `pw-pr-research.md` / `pw-pr-email.md`.

## Resolution

**Completed 2026-07-10.** The central fan-out PR/TODO activity report is live: teammates opt in
with `/pw-pr-reporting on`, which writes a row to the shared roster at
`G:\My Drive\Claude\PRReport\roster.csv` (3 active subscribers — brendanx67 + bspratt at `team`,
chambm at `individual`). The daily `-FanOut` research + per-subscriber email loop runs on
**BRENDANX-UW6** (the single owner machine), so no dev box runs the heavy report. Only leftover is
letting the weekly sync refresh `TOC.md` with the new `ai/scripts/PRReport/` files.
