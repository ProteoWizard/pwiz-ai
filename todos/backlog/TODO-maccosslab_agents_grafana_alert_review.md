# TODO-maccosslab_agents_grafana_alert_review.md

## Branch Information
- **Repository**: `uw-maccosslab/maccosslab-agents` (local checkout `~/dev/ai-dev/maccosslab-agents`)
- **Branch**: (not started)
- **Base**: `main`
- **Created**: 2026-10-07
- **Status**: Backlog
- **Objective**: Add a Claude Code slash command that takes a Grafana Cloud alert URL or ID,
  reviews the alert and its metrics in Grafana Cloud, and then either writes a short report or
  finds the window when the alert fired and runs `access-log-review-pipeline` on the
  panoramaweb.org access logs for that window

## Background

The daily access log review (`TODO-20260917_maccosslab_agents_access_log_review.md`,
completed) covers a fixed 24-hour window. When Grafana Cloud fires an alert for
panoramaweb.org (slow responses, high load, error spikes), someone has to open Grafana, work
out when the problem started and ended, and then dig through the logs for that window by hand.

This command closes that loop: given the alert, Claude reads the alert rule, its state history,
and the underlying metrics, decides whether the alert is explained by the metrics alone, and if
it points at traffic (bots, a slow page, a download storm), runs the existing access log
pipeline over the alert window.

## Proposed Behavior

`/grafana-alert-review <alert URL | alert rule UID>` (name to be decided), launched from the
`maccosslab-agents` checkout like `/access-log-review`:

1. **Resolve the alert.** Accept a Grafana Cloud alert rule URL (e.g.
   `https://<stack>.grafana.net/alerting/grafana/<uid>/view`), a bare rule UID, or a
   notification/silence link that carries one. Fetch the rule definition (query, threshold,
   evaluation interval, labels, annotations).
2. **Find the firing window.** From the rule's state history, find the most recent (or the
   requested) Pending -> Firing -> Normal transition. Window = firing start minus a lead-in
   margin to firing end (or now, if still firing) plus a margin.
3. **Review the metrics.** Query the rule's data source(s) over a wider span around the window
   (for baseline) and the window itself. Summarize: what crossed the threshold, by how much, for
   how long, and correlated series if cheap to fetch (CPU, memory, request rate, response time).
4. **Decide.**
   - **Short report** when the metrics explain the alert without needing logs (e.g. a
     scheduled job, a restart, disk filling, a blip under a few minutes, or a non-HTTP cause).
   - **Access log review** when the alert concerns HTTP load, latency, or errors on
     panoramaweb.org. Run the pipeline for the window and fold its findings into the report.
5. **Report.** Short Markdown summary to the terminal, plus a file in `reports/` (gitignored)
   that links the Grafana alert and, when run, the access log report paths.

## Tasks

- [ ] Choose how to reach Grafana Cloud (see Open Questions), add it to `.mcp.json` or a small
      Python client, and document the token setup (secret lives in
      `~/.config/maccosslab-agents/env`, never in the repo)
- [ ] Parse alert URL / UID input; handle unknown or ambiguous input with a clear error
- [ ] Fetch rule definition + state history; compute the firing window with margins
- [ ] Fetch metrics for baseline and window; keep any MCP tool result under
      `MAX_MCP_OUTPUT_TOKENS` (see the 25,000-token note in `maccosslab-agents/CLAUDE.md`)
- [ ] Decision rules for "short report" vs "run access log review" (written down, testable)
- [ ] Pipeline changes for ad-hoc windows (see Pipeline Gaps below)
- [ ] Slash command `.claude/commands/<name>.md` (and a subagent in `.claude/agents/` if the
      Grafana work should run with a restricted toolset, like `access-log-review`)
- [ ] Tests with a fake Grafana client and the existing fakes for `claude`, `git`, and SMTP;
      no test contacts Grafana, starts a real session, or sends mail
- [ ] Update `maccosslab-agents/CLAUDE.md` and `README.md` (module map, setup)

## Pipeline Gaps Found While Scoping

Checked `pipeline.py` on 2026-10-07; these need a decision before the command can call it:

- **Run directory collides with the daily run.** `run_dir = runs/<window end date>/`, so an
  alert run whose window ends today shares `manifest.json` with the scheduled daily run and
  can overwrite its phase results. Needs a distinct run directory for ad-hoc runs (e.g.
  `runs/alert-<uid>-<timestamp>/`) or a `--run-name` option.
- **`--hours` is an integer.** Alerts often span minutes. Either accept a start time
  (`--start`/`--end`) or fractional/minute durations.
- **Email phase.** `--phase all` emails the team. An alert run should probably use
  `--phase review` and let the command decide whether/where to send anything.
- **Log availability.** Logs are copied to `logs/panoramaweb.org/` by a separate daily
  process, so an alert from the last few hours may not be in the local logs yet. `validate`
  should catch that; the command should report "logs not yet available for this window"
  instead of a misleading empty review.
- **Billing/model.** The review phase starts a headless `claude -p` session. Confirm that
  running it on demand (rather than once a day) is acceptable, or run the review through the
  existing `/access-log-review` subagent path inside the current session instead.

## Open Questions

- **Grafana access**: Grafana's MCP server (`grafana/mcp-grafana`, which has alerting, Prometheus,
  and Loki tools) with a service account token, or a thin Python client over the Grafana HTTP API
  (alert rules, state history, data source query) exposed through our own MCP server? The MCP
  server is less code; our own client gives control over result size and what the agent sees.
- Which alert rules exist today for panoramaweb.org, and which data sources back them
  (Prometheus/Mimir, Loki, synthetic monitoring)? That determines what "review the metrics"
  means in practice.
- Alert URL formats to support: rule view URL only, or also alert-instance and notification
  links from email/Slack?
- Margins around the firing window (e.g. 30 minutes before, 15 after)?
- Should the command ever email, or terminal + `reports/` only?
- Later: trigger automatically from a Grafana contact point (webhook) instead of by hand?

## Success Criteria

- Given a real alert URL or UID, the command produces a correct firing window and a short
  metrics summary without manual Grafana browsing
- For an HTTP-related alert, it runs the access log review for exactly that window without
  disturbing the daily run's `runs/` directory or sending email unexpectedly
- No Grafana token, client IP, or LabKey username ends up in the repo; existing data-handling
  rules in `maccosslab-agents/CLAUDE.md` still hold
