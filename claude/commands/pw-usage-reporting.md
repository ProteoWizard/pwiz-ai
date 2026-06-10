---
argument-hint: "[on|off|status]"
description: Opt this machine in or out of team Claude usage reporting
---

# Claude Usage Reporting: $ARGUMENTS

Turn this machine's participation in the team's Claude Code usage tracking **on** or
**off**. Tooling lives in `ai/scripts/Usage` (this repo); data lives in the shared Google
Drive folder `<drive>:\My Drive\Claude\Usage`. Background: `ai/scripts/Usage/README.md`.

## Arguments

`$ARGUMENTS` is one of:
- **`on`** — start contributing this machine's usage (sets transcript retention, installs the
  daily snapshot task, takes a first capture).
- **`off`** — stop contributing (removes the daily snapshot task). Already-collected history
  in the shared store is left untouched.
- **`status`** (or no argument) — just report the current state; change nothing.

## Preflight (always)

1. Confirm PowerShell 7 is available: `pwsh -Command '$PSVersionTable.PSVersion'`.
2. Resolve the store **and confirm it is the SHARED team store, not a private duplicate.**
   The real team store contains a marker file `TEAM-STORE-ID.txt` whose first line is
   `SKYLINE-TEAM-USAGE-STORE`. A folder the user accidentally created themselves will not have
   it — and writing there silently tracks only that one person, invisible to the team. Check:
   ```
   pwsh -Command '. "./ai/scripts/Usage/Resolve-UsageStore.ps1"; $s = Resolve-UsageStore; $m = Join-Path $s "TEAM-STORE-ID.txt"; if ((Test-Path $m) -and ((Get-Content $m -TotalCount 1) -eq "SKYLINE-TEAM-USAGE-STORE")) { "OK shared store: $s" } else { "NOT THE SHARED STORE: $s" }'
   ```
   - **Throws** (no `My Drive\Claude\Usage` at all) → Drive folder isn't synced. See the
     sharing fix below. Do not proceed for `on`.
   - **`NOT THE SHARED STORE`** → the resolver found a *private* `Claude\Usage` the user made
     by hand. **Stop** — do not run setup. Have them remove/rename that folder and join the
     shared one (sharing fix below), then re-run.
   - **`OK shared store`** → proceed.

   **Sharing fix (how to join the team store correctly):** the owner (brendanx@proteinms.net)
   has shared `Claude` / `Claude\Usage` with edit access. In Google Drive on the **web**,
   right-click the shared **`Claude`** (or `Claude\Usage`) folder → **"Add shortcut to Drive"**
   → place it under **My Drive**, so it appears at `<drive>:\My Drive\Claude\Usage` once Drive
   for Desktop syncs. **Do NOT create a new `Claude\Usage` folder by hand** — that produces the
   private-duplicate failure above. Re-run the check until it prints `OK shared store`.

## `on`

Run the one-command onboarding (idempotent; backs up `settings.json` first):
```
pwsh -File './ai/scripts/Usage/Setup-ThisMachine.ps1'
```
This (1) sets `cleanupPeriodDays = 365` in `~/.claude/settings.json` so raw transcripts
survive long enough to backfill, (2) registers the daily `ClaudeUsageSnapshot` task at 06:00,
and (3) takes a first capture. Confirm `LastResult: 0x0`, then verify the per-machine CSV was
written:
```
pwsh -Command '$s = . "./ai/scripts/Usage/Resolve-UsageStore.ps1"; Get-Item (Join-Path (Resolve-UsageStore) ("data\usage_{0}.csv" -f $env:COMPUTERNAME))'
```
Report the row/day count printed by the script.

**Note on charts (do NOT do this for a teammate):** the daily chart-rendering task
(`ClaudeUsageGraphs`, via `Register-ClaudeUsageGraphTask.ps1`) runs on exactly **one**
always-on host and requires R. Participation only needs the snapshot task above. Only register
the graph task if the user explicitly says this machine should be the central charting host.

## `off`

Remove the snapshot task so this machine stops contributing:
```
pwsh -Command 'Unregister-ScheduledTask -TaskName ClaudeUsageSnapshot -Confirm:$false'
```
Leave the per-machine CSV in the shared store in place — it is the durable history and should
not be deleted. Transcript retention (`cleanupPeriodDays`) is left as-is (harmless); mention
the user can lower it back via `/config` or by editing `~/.claude/settings.json` if they want.
If this host also has the `ClaudeUsageGraphs` task, point that out and ask before removing it —
that's the team's central charting host, separate from this machine's participation.

## `status` (or no argument)

Report, without changing anything:
```
pwsh -Command 'Get-ScheduledTask -TaskName ClaudeUsage* -ErrorAction SilentlyContinue | Get-ScheduledTaskInfo | Select-Object TaskName, LastRunTime, @{n="LastResult";e={"0x{0:X}" -f $_.LastTaskResult}}, NextRunTime'
```
Also report `cleanupPeriodDays` from `~/.claude/settings.json` (the transcript-retention
horizon) and whether the Drive store resolves.
