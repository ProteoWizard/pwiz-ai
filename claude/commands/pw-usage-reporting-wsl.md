---
argument-hint: "[on|off|status]"
description: Opt this WSL2 machine in or out of team Claude usage reporting
---

# Claude Usage Reporting (WSL2): $ARGUMENTS

WSL2 counterpart of `/pw-usage-reporting` for Claude Code sessions running **inside WSL2**
(transcripts in the Linux `~/.claude`, not Windows `%USERPROFILE%\.claude`). Uses bash,
Python 3 and a systemd user timer instead of `pwsh` and a Windows Scheduled Task. Writes the
same `data/usage_<MACHINE>.csv` format to the same shared Google Drive store, so WSL and
Windows machines combine into one team dataset. Tooling: `ai/scripts/Usage/wsl/`.

Run all commands from the project root (the folder containing `ai/`).

## Arguments

- **`on`** — set transcript retention, install the daily `claude-usage-snapshot.timer`, take a
  first capture.
- **`off`** — remove the timer. Collected history in the shared store is left untouched.
- **`status`** (or no argument) — report the current state; change nothing.

## Preflight (always)

1. Tools: `python3 --version`, `jq --version`, and systemd must be PID 1
   (`ps -p 1 -o comm=` prints `systemd`). If not, the user adds `[boot]` / `systemd=true` to
   `/etc/wsl.conf` and runs `wsl --shutdown` from Windows.
2. The Google Drive letter must be mounted in WSL. WSL auto-mounts only fixed disks, not
   Drive for Desktop's virtual drive. If `ls /mnt/*/"My Drive"` finds nothing:
   ```
   sudo mkdir -p /mnt/g && sudo mount -t drvfs G: /mnt/g
   ```
   and, so it survives WSL restarts (the timer needs it), add to `/etc/fstab`:
   `G: /mnt/g drvfs defaults,uid=1000,gid=1000 0 0`. Substitute the actual Drive letter.
3. Resolve the store and confirm it is the **shared** team store:
   ```
   python3 ./ai/scripts/Usage/wsl/claude_usage.py resolve
   ```
   - **Exits with "Could not find..."** → Drive not mounted (step 2) or folder not synced
     (sharing fix in `pw-usage-reporting.md`). Do not proceed for `on`.
   - **`NOT THE SHARED STORE`** → a private `Claude/Usage` without the `TEAM-STORE-ID.txt`
     marker. Writing there tracks only this user, invisible to the team. **Stop and tell the
     user.** Proceed only if they explicitly choose to use the private folder for now; then
     pass `--allow-unshared-store` to setup (below).
   - **`OK shared store`** → proceed.

   A shared folder joined via "Add shortcut to Drive" appears as `My Drive/Claude.lnk`. From
   WSL that `.lnk` is unreadable and `.shortcut-targets-by-id` is traverse-only, so the resolver
   follows the shortcut through `powershell.exe` (Windows interop). Setup bakes the resolved
   path into the service as `--store`, since interop is unavailable inside systemd services.
   If the store moves, re-run `on`.

## `on`

```
bash ./ai/scripts/Usage/wsl/setup-this-machine.sh
```
Add `--allow-unshared-store` only with the user's explicit consent (see preflight). The script
is idempotent and:
1. Sets `cleanupPeriodDays = 365` in `~/.claude/settings.json` (backup: `settings.json.bak`).
2. Writes `~/.config/systemd/user/claude-usage-snapshot.{service,timer}` and enables the timer
   (daily 06:00, `Persistent=true` so a run missed while WSL was stopped happens at next start).
   The service runs `claude_usage.py snapshot` then `combine`.
3. Starts the service once and prints its output.

Identity is resolved at setup time (Windows interop is unavailable inside systemd services)
and baked into the service unit:
- **machine** = Windows `%COMPUTERNAME%` + `-WSL` (e.g. `BDCONNOL-UW1-WSL`). The suffix keeps
  this CSV separate from the same PC's Windows-side `usage_<COMPUTERNAME>.csv`, whose
  transcripts are a different set.
- **user** = email in the Drive volume label, else `<windows-user>@proteinms.net` (same rule
  as the PowerShell snapshot). Override with `--user` / `--machine`.

Report the `machine`/`user` values and the row/day count line from the first capture.

**Charts:** do not set up chart rendering here. That runs on one central Windows host
(`Register-ClaudeUsageGraphTask.ps1`), unchanged.

## `off`

```
systemctl --user disable --now claude-usage-snapshot.timer
rm -f ~/.config/systemd/user/claude-usage-snapshot.service ~/.config/systemd/user/claude-usage-snapshot.timer
systemctl --user daemon-reload
```
Leave the per-machine CSV in the store — it is the durable history. `cleanupPeriodDays` is
left as-is; mention the user can lower it in `~/.claude/settings.json` if they want.

## `status` (or no argument)

Report, without changing anything:
```
systemctl --user list-timers claude-usage-snapshot.timer --all --no-pager
systemctl --user show claude-usage-snapshot.service -p Result,ExecMainStatus,ExecMainExitTimestamp
journalctl --user -u claude-usage-snapshot.service -n 10 --no-pager -o cat
jq .cleanupPeriodDays ~/.claude/settings.json
python3 ./ai/scripts/Usage/wsl/claude_usage.py resolve
grep -o -- '--allow-unshared-store' ~/.config/systemd/user/claude-usage-snapshot.service
```
If the service carries `--allow-unshared-store` but `resolve` now prints `OK shared store`,
the user has joined the team folder: re-run `on` without the flag, and move their
`usage_<MACHINE>.csv` from the private folder's `data/` into the shared store's `data/`
(the resolver prefers the marker-bearing store when both exist).

## Manual use

```
python3 ./ai/scripts/Usage/wsl/claude_usage.py [--allow-unshared-store] snapshot --machine <M> --user <U>
python3 ./ai/scripts/Usage/wsl/claude_usage.py [--allow-unshared-store] combine
```
Pricing is read from `ai/scripts/Usage/Snapshot-ClaudeUsage.ps1` (`$Rates`), so edit rates
there only. Output is byte-identical to the PowerShell snapshot for the same transcripts.
