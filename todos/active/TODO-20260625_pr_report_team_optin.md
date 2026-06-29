# TODO-20260625_pr_report_team_optin.md

## Repo / Branch
- **Repo**: pwiz-ai (`ai/`) — committed directly to `master`, no feature branch (doc/tooling).
- **Created**: 2026-06-25
- **Status**: In Progress (code complete; live store seeding + scheduling migration pending)
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
- [ ] **Seed the live shared store (owner machine)**: create `Claude\PRReport\` +
      `TEAM-STORE-ID.txt` (`SKYLINE-TEAM-PRREPORT-STORE`), add brendanx67 at `team` level. (One-time
      setup block is in the README. Touches the shared Drive — do with the user.)
- [ ] **Migrate the schedule**: replace the current single-recipient "PR Report - Both" task with
      `Invoke-PRReport.ps1 -FanOut -Schedule "9:30AM"` (elevated). Verify with `-FanOut -DryRun`.
- [ ] **End-to-end test** before relying on it: `-FanOut` run with a 1–2 person roster, confirm
      research writes per-subscriber slices and each person gets the right level + pile-up line.
- [ ] **Share the `Claude` folder** with the team (edit access) and announce `/pw-pr-reporting on`.
- [ ] Run `ai/scripts/Generate-TOC.ps1` (or let the weekly sync) so the new files land in TOC.md.

## Refs
- Pattern mirrored: `ai/scripts/Usage/` (Resolve-UsageStore, Setup-ThisMachine,
  `.claude/commands/pw-usage-reporting.md`).
- Engine: `ai/scripts/Invoke-PRReport.ps1`; command files `pw-pr-research.md` / `pw-pr-email.md`.
