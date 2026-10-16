# TODO-20261014_maccosslab_agents_service_restarts.md

## Branch Information
- **Repository**: `uw-maccosslab/maccosslab-agents` (local checkout `~/dev/ai-dev/maccosslab-agents`)
- **Branch**: none (merged to `main`; was `work/20261014_labkey_service_restarts`)
- **Base**: `main`
- **Created**: 2026-10-14
- **Status**: Completed
- **PR**: [#5](https://github.com/uw-maccosslab/maccosslab-agents/pull/5) (merged 2026-10-16,
  `4a5992d`; pre-PR `/code-review` skipped at the developer's request)
- **Objective**: Find out from a server's syslog and labkey.log whether the LabKey (Tomcat)
  or Apache service restarted, when, how long the shutdown and startup took, the probable
  cause, and whether the shutdown had problems. Delivered as a plain Python script, a skill,
  and a slash command.

## Background

Restarts on panoramaweb.org (deployments, unattended upgrades, puppet package changes) were
found by reading syslog by hand. syslog is about 1 GB gzipped for six weeks, too large to
read in a Claude session, so the parsing is a script and Claude only interprets its output.
Sample logs: `examples/panoramaweb.org/{syslogs,labkey-logs}/` in the ai-dev root (not in
any repository).

## Tasks

- [x] `service_restarts/` package (stdlib only, no Claude, no API bill):
      `sources.py` (16 MB block reads, `bytes.find` needles, one worker process per file;
      year from the rotated file name, else mtime, else `--year`), `events.py`,
      `episodes.py` (systemd state machine, LabKey phases, cause and problems),
      `report.py` (Markdown tables and JSON), `cli.py`
- [x] Console script `labkey-service-restarts` (`--logs-dir`, `--syslog-dir`,
      `--labkey-dir`, `--since`, `--until`, `--year`, `--json`)
- [x] Columns `Began | Shutdown duration | Startup duration | Probable cause | Problems`.
      Shutdown: `Stopping` to `Stopped`. Startup: `Stopped` to LabKey `Module startup
      complete` (Apache: systemd `Started`); `(systemd)` marks LabKey restarts without
      LabKey's own lines. JSON also keeps `down_seconds` and `ready_seconds`.
      (Changed from the planned "show all phases" columns at the developer's request.)
- [x] Probable cause, in priority order: reboot, OOM, crash, unattended upgrade / systemd
      re-exec, puppet (related packages only), ansible, sudo, not found
- [x] Apache reloads ignored (developer's decision)
- [x] `.claude/skills/labkey-service-restarts/SKILL.md` and
      `.claude/commands/pw-labkey-restarts.md` (with
      `allowed-tools: Bash(.venv/bin/labkey-service-restarts:*)`, added by the developer)
- [x] Runs in the Claude Code sandbox: on Linux the worker processes start with `fork`,
      because Python 3.14's default forkserver needs a Unix socket and the sandbox blocks
      Unix sockets. Falls back to a one-process scan if workers still can't start
      (about 40 s instead of about 13 s)
- [x] Tests: 174 pass (sample restarts, gz files, year rollover, crash, OOM, sudo, reloads
      ignored, date filters, missing labkey.log, parallel vs serial scan, sandbox fallback,
      no request lines in output)
- [x] README.md (agents row, usage, module map) and CLAUDE.md ("Service restarts")

## Progress

### 2026-10-16 - Merged

PR #5 merged as commit `4a5992d`. Two commits: `09cfa3a` (the restart finder) and
`eeca7d8` (sandbox fix). The developer ran `/pw-labkey-restarts` in a sandboxed session and
confirmed it works. No follow-up issues filed.

Results on the sample logs (Sep 1 to Oct 11, 2026), checked by hand against the logs:
- LabKey 2026-09-01 05:44:05: shutdown 1m 08s, startup 31s. Ansible deploying
  `LabKey26.7Beta-56-panoramaweb.tar.gz`.
- Apache 2026-10-08 12:37:55: shutdown 10s, startup 0s. Puppet upgrading httpd
  2.4.52-1ubuntu4.23 to .24 (puppet logs the package change after the restart).
- LabKey 2026-10-09 06:42:28: shutdown 1m 24s, startup 24s. Unattended `apt-daily-upgrade`
  followed by a systemd re-exec.
- Both LabKey restarts had the graceful shutdown aborted after 30s with requests still
  active. On Oct 9 about 40 s of the shutdown was the pipeline's ActiveMQ/Mule shutdown
  (06:43:08 to 06:43:49).

### Sandbox setup (this workstation, 2026-10-16)

- Ubuntu 24.04 on WSL2: installed `bubblewrap` and `socat`. No AppArmor user-namespace
  fix was needed under the WSL kernel.
- `.claude/settings.local.json` (gitignored) has
  `"sandbox": {"enabled": true, "autoAllowBashIfSandboxed": false}`.
- The sandbox is session-wide; Claude Code has no per-skill or per-command sandbox
  setting. Not done: adding the `sandbox` block to the shared `.claude/settings.json`
  so it applies to everyone using the repository.

## Open Questions

- Turn the sandbox on for the whole repository in `.claude/settings.json`
  (`enabled`, `allowUnsandboxedCommands: false`, `failIfUnavailable`)? It affects every
  Bash command in the checkout, including pytest, pip, and git push.
- Should the copy job that fetches the access logs also copy syslog and labkey.log to
  `logs/panoramaweb.org/syslog/` and `labkey/`, the script's default directories?
