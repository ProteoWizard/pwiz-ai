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
  Register-ClaudeUsageTask.ps1       # install the daily Scheduled Task
  Setup-ThisMachine.ps1              # one-command onboarding (retention + task + first run)
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
  with a `user` column (`<account>@proteinms.net`, auto-derived from the Drive account label).
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

## Manual use

```powershell
pwsh -File "C:\proj\ai\scripts\Usage\Snapshot-ClaudeUsage.ps1"   # capture now
pwsh -File "C:\proj\ai\scripts\Usage\Combine-ClaudeUsage.ps1"    # rebuild combined
```

## Notes & limits

- Tracks **absolute work (tokens) per machine/person** — richer than the Claude UI. It does
  **not** capture the UI's account-wide "% of plan" numbers (no documented API; they reset on
  rolling windows). Overlay those by logging a periodic manual reading.
- `<synthetic>` rows are Claude Code placeholders (zero real cost); dated model ids collapse
  to base.
- **Sharing:** the data folder currently sits in one person's *My Drive*, shared with edit
  access — fine for a small team. Moving `Claude/Usage` to a Google **Shared Drive** later
  needs no code change (the resolver already checks Shared drives).
