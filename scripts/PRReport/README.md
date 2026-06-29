# Team PR & TODO activity report (opt-in fan-out)

A daily email about PR / Issue / TODO activity, customizable per teammate. One central host
runs the report **once** each morning and emails everyone who has opted in — each person gets
a report built for *their* GitHub login at *their* reporting level. Teammates run nothing
locally; they just register in a shared roster (like the usage tracker, but the roster — not a
per-machine scheduled task — is what each person manages).

## How it differs from the usage tracker

| | Usage tracker (`ai/scripts/Usage`) | PR report (`ai/scripts/PRReport`) |
|---|---|---|
| What each machine runs | A daily snapshot task (every machine) | **Nothing** — only the central host runs a task |
| What opt-in does | Registers a local scheduled task | Adds your row to a **shared roster** |
| Shared Drive data | `Claude\Usage\data\*.csv` | `Claude\PRReport\roster.csv` |
| Heavy work (`claude -p`) | None (just parses transcripts) | Central host only (1 research + 1 email session/day) |

This split is deliberate: the report's research is ~80% team-wide (everyone's open PRs,
pile-up, recent activity, TODO inventory) and only a thin slice is personal, so running it once
centrally and fanning out personalized emails is far cheaper than every machine running its own
Opus session.

## Layout

```
ai/scripts/PRReport/                 (pwiz-ai repo — tooling)
  PRReportStore.ps1                  # library: resolve the shared store + read/write the roster
  Manage-PRReportRoster.ps1          # CLI: add / remove / list / status (what /pw-pr-reporting drives)
  README.md
ai/scripts/Invoke-PRReport.ps1       # the report engine; -FanOut reads the roster and emails each subscriber

<drive>:\My Drive\Claude\PRReport\   (Google Drive — shared data)
  TEAM-STORE-ID.txt                  # marker: first line "SKYLINE-TEAM-PRREPORT-STORE"
  roster.csv                         # email, github_login, level, active, added, updated, added_by, machine
```

The store is resolved at runtime (drive-letter scan + Drive shortcut following), so no path is
hardcoded. `$env:PRREPORT_STORE` overrides it for testing.

## For teammates — subscribe

From your pwiz checkout (interactive Claude Code session):

```
/pw-pr-reporting on <github-login>            # individual level (default)
/pw-pr-reporting on <github-login> team       # full cross-team report
/pw-pr-reporting status                        # show your subscription
/pw-pr-reporting off                           # unsubscribe
```

Prerequisite: the shared `Claude` folder must be synced to your machine — in Google Drive on
the web, right-click it → **“Add shortcut to Drive”** under My Drive. Do **not** create a
`Claude\PRReport` folder by hand (that makes a private duplicate the resolver will reject).

Or drive the CLI directly:

```powershell
pwsh -File "C:\proj\ai\scripts\PRReport\Manage-PRReportRoster.ps1" -Action add -GitHubUser <login> -Level individual
pwsh -File "C:\proj\ai\scripts\PRReport\Manage-PRReportRoster.ps1" -Action list
```

## Reporting levels

- **individual** (default) — your slice only: PRs awaiting your review, your open PRs (with a
  **self pile-up warning** when your non-draft open PRs ≥ 3, the same threshold as the team
  pile-up callout), issues assigned to you, your TODOs.
- **team** — the full cross-team report, with your review queue on top.

## Central host (one machine — the owner)

The owner machine runs the daily fan-out. Schedule it from an elevated prompt (after the 8:05
daily report; the legacy single-recipient task is replaced by `-FanOut`):

```powershell
pwsh -File "C:\proj\ai\scripts\Invoke-PRReport.ps1" -FanOut -Schedule "9:30AM"
```

Manual run / preview:

```powershell
pwsh -File "C:\proj\ai\scripts\Invoke-PRReport.ps1" -FanOut -DryRun     # show who would be emailed
pwsh -File "C:\proj\ai\scripts\Invoke-PRReport.ps1" -FanOut             # run research once + email everyone
```

`-FanOut` runs research **once** (team-wide raw data + a personal slice per subscriber), then a
single email session loops the roster and sends each person their customized message. An empty
roster is a no-op. The central host needs `gh` auth, the Gmail MCP, and `claude` on PATH — all
mail sends from its Gmail account.

## One-time store setup (owner)

Create the marker and seed the roster once:

```powershell
$store = Join-Path (& { . "C:\proj\ai\scripts\PRReport\PRReportStore.ps1"; Resolve-ClaudeStore }) 'PRReport'
New-Item -ItemType Directory -Force -Path $store | Out-Null
"SKYLINE-TEAM-PRREPORT-STORE" | Set-Content (Join-Path $store 'TEAM-STORE-ID.txt') -Encoding UTF8
pwsh -File "C:\proj\ai\scripts\PRReport\Manage-PRReportRoster.ps1" -Action add -GitHubUser brendanx67 -Level team
```

Then share the `Claude` folder (edit access) with the team — they add a shortcut and run
`/pw-pr-reporting on`.

## Notes & limits

- **GitHub login → email** is recorded explicitly in the roster (login for queries, email for
  delivery); login → git-author-name for TODO attribution is best-effort and omitted when
  ambiguous.
- The roster row is keyed by **email** (lower-cased). Re-running `on` updates login/level in
  place; `off` keeps the row as history (`active=false`).
- All emails send from the central host's Gmail account — fine for an internal report.
