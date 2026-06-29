---
argument-hint: "[on|off|status] [github-login] [individual|team]"
description: Opt in or out of the daily team PR & TODO activity email
---

# PR & TODO Report Subscription: $ARGUMENTS

Opt this person **in** or **out** of the daily team PR & TODO activity email. Unlike the
usage tracker, this does **not** schedule anything on your machine — a single central host
(`Invoke-PRReport.ps1 -FanOut`) runs the report once each morning and emails everyone on the
shared roster. Opting in just adds (or updates) your row in that roster. Tooling:
`ai/scripts/PRReport`; background: `ai/scripts/PRReport/README.md`.

## Arguments

`$ARGUMENTS` is `[on|off|status] [github-login] [individual|team]`:
- **`on [github-login] [level]`** — subscribe (or update). `github-login` is the GitHub login
  the report is built for (review queue, your PRs, assigned issues). `level` is `individual`
  (default) or `team`. Your email auto-derives from the machine's Google account.
- **`off`** — unsubscribe (your roster row is kept as history, just marked inactive).
- **`status`** (or no argument) — show your current subscription; change nothing.

If the user runs `on` without a github-login, **ask** for it (and the level if not given)
before proceeding — don't guess the login.

## Levels

- **individual** (default) — just your slice: PRs awaiting your review, your open PRs (with a
  self pile-up warning if your non-draft open PRs ≥ 3), issues assigned to you, your TODOs.
- **team** — the full cross-team report (everyone's open PRs, pile-up callout, all recent
  activity, full TODO inventory), with your review queue on top.

## Preflight (always)

1. Confirm PowerShell 7: `pwsh -Command '$PSVersionTable.PSVersion'`.
2. Confirm the resolver finds the **shared** roster store (not a private duplicate). The real
   store carries a marker `TEAM-STORE-ID.txt` whose first line is `SKYLINE-TEAM-PRREPORT-STORE`:
   ```
   pwsh -Command '. "./ai/scripts/PRReport/PRReportStore.ps1"; (Test-PRReportStore | ConvertTo-Json -Compress)'
   ```
   - `"Ok":true` → proceed.
   - `"Ok":false` with a “does not exist / no Claude folder” reason → the shared Drive folder
     isn't synced. Fix sharing (below). Do not proceed for `on`/`off`.
   - `"Ok":false` with a marker mismatch → the resolver found a **private** `Claude\PRReport`
     the user made by hand. **Stop** — have them remove/rename it and join the shared one.

   **Sharing fix:** the owner (brendanx@proteinms.net) shares the `Claude` folder with edit
   access. In Google Drive on the **web**, right-click the shared **`Claude`** folder →
   **“Add shortcut to Drive”** → place it under **My Drive**, so it appears at
   `<drive>:\My Drive\Claude\PRReport` once Drive for Desktop syncs. **Do NOT create a
   `Claude\PRReport` folder by hand** — that produces the private-duplicate failure above.

## `on`

```
pwsh -File './ai/scripts/PRReport/Manage-PRReportRoster.ps1' -Action add -GitHubUser '<login>' -Level '<individual|team>'
```
(Email auto-derives; pass `-Email '<addr>'` to override.) Confirm the printed row shows
`active=true` with the right login and level. Tell the user they'll start receiving the email
at the next scheduled run (the central host sends around 9:30 AM Pacific) and can change level
anytime by re-running `on` with a different level.

## `off`

```
pwsh -File './ai/scripts/PRReport/Manage-PRReportRoster.ps1' -Action remove
```
This marks your row inactive (kept as history). You'll stop receiving the email at the next run.

## `status` (or no argument)

```
pwsh -File './ai/scripts/PRReport/Manage-PRReportRoster.ps1' -Action status
```
Report the row (login, level, active). To see the whole team roster, use `-Action list`.

## Related

- `ai/scripts/PRReport/README.md` — how the roster + central fan-out work
- `ai/scripts/Invoke-PRReport.ps1` — the report engine (`-FanOut` reads the roster)
- `.claude/commands/pw-usage-reporting.md` — the sibling opt-in for usage tracking
