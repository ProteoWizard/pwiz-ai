# Claude usage tracking (team)

Durable, shareable history of Claude Code token usage, reconstructed from each person's
local JSONL transcripts before Claude Code's 30-day retention deletes them.

**Tooling** (these scripts) is versioned here in **pwiz-ai** (`ai/scripts/Usage`) — everyone
gets it via `git pull`. **Data** lives in a shared **Google Drive** folder,
`<drive>:\My Drive\Claude\Usage`, which syncs across machines and teammates. The scripts
find that folder automatically (`Resolve-UsageStore` / a drive-letter scan), so no path is
ever hardcoded.

## Layout

```
ai/scripts/Usage/                    (pwiz-ai repo — the tooling)
  Resolve-UsageStore.ps1             # shared helper: find the Drive data store
  Snapshot-ClaudeUsage.ps1           # parse THIS machine's transcripts -> data/usage_<MACHINE>.csv
  Combine-ClaudeUsage.ps1            # union all usage_<MACHINE>.csv -> data/usage_combined.csv
  Register-ClaudeUsageTask.ps1       # install the daily snapshot task (every machine)
  UsageTask.ps1                      # shared helper: register a daily task, run it, log the result
  Setup-ThisMachine.ps1              # one-command onboarding (retention + task + first run)
  Update-ClaudeUsageGraphs.ps1       # combine + render charts (run on ONE host)
  Register-ClaudeUsageGraphTask.ps1  # install the daily graph task (ONE always-on host)
  usage_plots.R                      # ggplot2 charts -> <store>/plots
  README.md

<drive>:\My Drive\Claude\Usage\      (Google Drive — the data depository)
  data/  usage_<MACHINE>.csv, usage_combined.csv
  plots/ generated PNGs
```

## How it works

- **Transcripts are the source of truth** — each Claude API response records exact token
  counts (input / cache-write / cache-read / output) per model. Aggregated to daily × model.
- **The 30-day reaper** deletes raw transcripts, so each machine snapshots into a permanent
  CSV that outlives them. Dates still in transcripts are recomputed each run (today's partial
  total self-corrects); aged-out dates are preserved.
- **One CSV per machine** (machine name is the key — matches our nightly-test convention),
  with a `user` column (`<account>@proteinms.net`, derived from the Windows account name; the Drive volume label is checked for an email first, but current Drive labels it just `Google Drive`).
- **Shared machines** (several people, each under their own Windows account, e.g. MACS2): the
  first reporter keeps `usage_<MACHINE>.csv`; a later one who finds another person's rows there
  writes `usage_<MACHINE>_<account>.csv`, because each snapshot replaces every row for the dates
  it recomputes. The `machine` column stays `<MACHINE>`; the charts label a machine with more
  than one person as `MACHINE (Person)`.
- **est_cost_usd is MODELED** from public per-token rates (`$Rates` in the snapshot script) —
  a relative-trend signal, not a bill on a Max subscription.

## Per-machine setup (once per machine)

1. Make sure the Drive folder is synced locally (if shared with you, open it in Drive and
   **"Add shortcut to My Drive"** so it appears at `<drive>:\My Drive\Claude\Usage`).
2. Install PowerShell 7 (`pwsh`) if needed.
3. From your pwiz-ai checkout, run the one-command setup (365-day retention + daily task +
   first capture):
   ```powershell
   pwsh -File "C:\proj\ai\scripts\Usage\Setup-ThisMachine.ps1"
   ```
4. Charts: in RStudio, once `install.packages(c("tidyverse","scales"))`, then Source `usage_plots.R`.

`Setup-ThisMachine.ps1` backs up `settings.json` before editing and is safe to re-run.

## The scheduled task

- **Runs at 13:00 UTC on every machine**, which is 06:00 Pacific during daylight time and
  05:00 Pacific during standard time. The time is one fixed instant on purpose, not a local
  time: every machine, in any time zone, has reported before the charts are drawn at 13:30 UTC.
  `-At` takes another time, but a local value such as `06:00` is stored as the instant it
  names on the day of registration, which differs between summer and winter.
- **Opens no window.** The task launches PowerShell through `conhost.exe --headless`.
- **Read the run log, not the task's Last Run Result.** The headless launch always reports
  exit code 0 to Task Scheduler, so each run appends one line to
  `ai\.tmp\usage\<TaskName>.log` instead: the start time, `OK` or `FAILED`, the duration, and
  either the scripts that ran or the error with its file and line. Warnings are added to the line.
  ```
  2026-11-21 06:00:02  OK        20.8 s  Snapshot-ClaudeUsage.ps1, Combine-ClaudeUsage.ps1
  ```
- **A machine set up before this behavior existed keeps its old task** until the task is
  registered again: it shows a console window and writes no run log. Its time is whatever
  06:00 local was on the day it was set up. For a Pacific machine set up during daylight time
  that is the same 13:00 UTC; one set up during standard time runs at 14:00 UTC, after the
  charts, so its numbers are a day behind there. Run `/pw-usage-reporting on` (or
  `Setup-ThisMachine.ps1`) once more on a machine to refresh it. The same applies to the
  charting host and `Register-ClaudeUsageGraphTask.ps1`.

**WSL2:** Claude Code running inside WSL2 keeps its transcripts in the Linux `~/.claude`, so
use `wsl/` instead (Python port + systemd user timer; same CSV format, pricing read from
`Snapshot-ClaudeUsage.ps1`). See `/pw-usage-reporting-wsl` or run
`bash ai/scripts/Usage/wsl/setup-this-machine.sh`. The machine key gets a `-WSL` suffix.

## Daily charts (one host only)

Each machine's snapshot task already runs `Combine` at 13:00 UTC, so `usage_combined.csv` stays
fresh. Rendering the **charts** is centralized on ONE always-on machine (a workstation, not a
sleeping laptop), half an hour later (13:30 UTC) so it folds in what has synced:

```powershell
pwsh -File "C:\proj\ai\scripts\Usage\Register-ClaudeUsageGraphTask.ps1" -RunNow
```

That host needs R (Rscript) with `tidyverse`, `scales` and `plotly`, installed as the account
the task runs under:
`Rscript -e 'install.packages(c("tidyverse","scales","plotly"), repos = "https://cloud.r-project.org")'`.
`plotly` draws `plots/claude_usage.html`: every chart on one page, where clicking a legend entry
hides that person, machine or model. The page is self-contained (~4 MB, plotly.js inlined), so a
downloaded or emailed copy works on its own; Drive's web preview does not run it. Without `plotly`
the PNGs and PDF are still written and the run log (`ai\.tmp\usage\ClaudeUsageGraphs.log`) warns
that the page was skipped.

Data is eventually consistent — a machine that was asleep at
chart time appears in the next day's charts; no run-time offset can fix a sleeping machine. The
`plots/` folder is shared: automated charts use the `01`–`08` names and `claude_usage.*`, so keep any ad-hoc
analysis on other names (or a subfolder) to avoid clobbering.

## Manual use

```powershell
pwsh -File "C:\proj\ai\scripts\Usage\Snapshot-ClaudeUsage.ps1"   # capture now
pwsh -File "C:\proj\ai\scripts\Usage\Combine-ClaudeUsage.ps1"    # rebuild combined
```

## Notes & limits

- Tracks **absolute work (tokens) per machine/person** — richer than the Claude UI. It does
  **not** capture the UI's account-wide "% of plan" numbers (no documented API; they reset on
  rolling windows). Overlay those by logging a periodic manual reading.
- **Shared logins:** the `user` column comes from the Windows account name,
  which is wrong for a shared account (e.g. SKYLINE-DEV6 under `maccoss`). Add a row to
  `<store>\user_overrides.csv` (`machine,user,from,to`, inclusive dates, blank = open-ended);
  `Combine` re-attributes matching rows (every row for that machine, so on a shared machine
  limit the dates to the shared login's period). Editing the machine's own CSV does not stick — its
  daily snapshot rewrites every date still in its transcripts.
- `<synthetic>` rows are Claude Code placeholders (zero real cost); dated model ids collapse
  to base.
- **Sharing:** the data folder currently sits in one person's *My Drive*, shared with edit
  access — fine for a small team. Moving `Claude/Usage` to a Google **Shared Drive** later
  needs no code change (the resolver already checks Shared drives).
