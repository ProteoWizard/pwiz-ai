# Analyzing LabKey Service Restarts on a Web Server

How to find out whether LabKey (Tomcat) or Apache restarted on one of our LabKey web
servers (e.g. panoramaweb.org), and when, how long each restart took, why it happened, and
whether the shutdown went cleanly. You run the analysis **on the web server itself**,
against its live logs, so you don't need to copy about 1 GB of syslog to your workstation.

The tooling lives in the private **maccosslab-agents** repository
(`https://github.com/uw-maccosslab/maccosslab-agents`, sibling checkout `../maccosslab-agents`):

| Piece | Path in maccosslab-agents | What it does |
|-------|---------------------------|--------------|
| `labkey-service-restarts` | `src/maccosslab_agents/service_restarts/` | Plain Python. Streams syslog and labkey.log and prints a table per restart. No Claude, no network, no API bill |
| `labkey-service-restarts` skill | `.claude/skills/labkey-service-restarts/SKILL.md` | Tells Claude how to run the script and interpret its output (causes, problems, columns) |
| `/pw-labkey-restarts` | `.claude/commands/pw-labkey-restarts.md` | Runs the skill and adds a written summary of each restart |
| `server/labkey-restarts.sh` | `server/` | Runs the script on the server: tables only |
| `server/labkey-restarts-claude.sh` | `server/` | Runs `/pw-labkey-restarts` headless with Claude, locked down in a sandbox |
| `server/verify-lockdown.sh` | `server/` | Checks that the lockdown holds |

The repository's `README.md` ("Running a Service Restarts analysis") is the source of truth
for the scripts and the lockdown design. This page is the step-by-step for a team member.

## Choose how to run it

| Option | Use when | Needs on the server |
|--------|----------|---------------------|
| **A. Tables only** (`labkey-restarts.sh`) | You want the facts quickly, Claude Code isn't installed on the server, or you will ask Claude about the output on your workstation | Checkout + `.venv` |
| **B. Headless Claude** (`labkey-restarts-claude.sh`) | You want the written summary (cause, evidence, impact on users) produced on the server | Checkout + `.venv` + Claude Code + token |

Both read the same logs and accept only `--since` and `--until` (`YYYY-MM-DD`, inclusive,
by the date a restart began).

## One-time setup (per account, per server)

Any account can run the analysis; nothing is tied to one user. Do this once in your own
account on each server.

1. **Check you can read the logs without root.** Both of these must work:

   ```bash
   ls /var/log/syslog*
   ls /data/labkey/logs
   ```

   If not, ask a server admin for read access (the scripts never use `sudo`).

2. **Clone the repository** into your home directory (you need access to the private
   `uw-maccosslab/maccosslab-agents` repository):

   ```bash
   git clone https://github.com/uw-maccosslab/maccosslab-agents.git
   cd maccosslab-agents
   ```

3. **Create the virtual environment** at the repository root, using the server's Python
   module (the system Python is too old; 3.11 or later is required):

   ```bash
   module load python/3.13.10
   python3 -m venv .venv
   .venv/bin/python -m pip install -e ".[dev]"
   ```

   The scripts check for `.venv/bin/labkey-service-restarts` and stop with an error if it
   is missing.

   Option A needs nothing more. For option B, continue:

4. **Install Claude Code** in your home directory (native installer, no root needed):

   ```bash
   curl -fsSL https://claude.ai/install.sh | bash
   ```

5. **Create a long-lived token.** On any machine where you are signed in to the Claude
   subscription, run `claude setup-token`. On the server, save the token where only you can
   read it:

   ```bash
   mkdir -p ~/.config/maccosslab-agents
   echo 'CLAUDE_CODE_OAUTH_TOKEN=<token>' > ~/.config/maccosslab-agents/env
   chmod 600 ~/.config/maccosslab-agents/env
   ```

   Never commit this file or paste the token anywhere else.

6. **Verify the lockdown** (once per server, and again after anyone changes the settings in
   `labkey-restarts-claude.sh`). Load the token first (see "Run it" below), then:

   ```bash
   server/verify-lockdown.sh
   ```

   It prints PASS or FAIL per check and exits 1 if any failed. Do not use option B on a
   server where a check fails; tell whoever maintains maccosslab-agents.

## Run it

Log in to the server and go to your checkout. Pull first, so you have the current parser
and skill:

```bash
cd ~/maccosslab-agents
git pull
```

If the pull changed `pyproject.toml`, rerun the `pip install -e ".[dev]"` line from setup.

### Option A: tables only

```bash
server/labkey-restarts.sh --since 2026-10-09 --until 2026-10-10
```

Leave out `--since`/`--until` to cover everything still in the logs. It takes about 15
seconds per GB of gzipped syslog. To get Claude's written summary afterwards, copy the
output to your workstation and paste it into any Claude session, or run
`/pw-labkey-restarts` there from a maccosslab-agents checkout.

### Option B: headless Claude

Load the token into the shell, then run:

```bash
set -a; . ~/.config/maccosslab-agents/env; set +a
server/labkey-restarts-claude.sh --since 2026-10-09 --until 2026-10-10
```

It prints the `/pw-labkey-restarts` report: a line saying whether LabKey and Apache
restarted in the covered period, the restart tables, and a paragraph per restart on cause,
outage length, and shutdown problems. It uses `claude-haiku-5-5` by default (`MODEL=...` to
change). Nothing is saved: copy the report from the terminal if you need to keep it.

What the lockdown means for you: Claude can run only the restart script, can read only the
checkout, the two log directories, and system libraries, has no network beyond the Claude
API itself, and cannot see your token from its commands. Anything else it tries is denied
without a prompt. Details are in the README ("Design").

### Settings you can override

Both scripts are set up for MacCoss Lab web servers. Override with environment variables:

| Variable | Default | Meaning |
|----------|---------|---------|
| `SYSLOG_DIR` | `/var/log` | Directory with `syslog` and `syslog-*.gz` |
| `LABKEY_DIR` | `/data/labkey/logs` | Directory with `labkey.log` and `labkey.log.N` |
| `MODULES` | `python/3.13.10 bubblewrap/0.11.1` | Environment modules loaded first. `MODULES=` loads none (e.g. on a machine without environment modules) |
| `MODEL` | `claude-haiku-5-5` | Option B only |

Example: `LABKEY_DIR=/other/labkey/logs server/labkey-restarts.sh --since 2026-10-01`.

## Reading the output

Start with the **coverage** lines: they give the time span of each log source, and so the
period that "no restarts" actually covers. labkey.log only keeps about two weeks, but
LabKey also logs to syslog, so LabKey phases are available for the whole syslog span.

Each restart has two durations; the outage users saw is the two added together:

| Column | From | To |
|--------|------|----|
| Shutdown | stop requested (`Stopping labkey...`) | systemd `Stopped labkey.` |
| Startup | `Stopped labkey.` | LabKey `Module startup complete` (fully ready). `(systemd)` means LabKey's own lines were missing and systemd `Started` was used, which is about 15 seconds early |

Apache reloads (from logrotate and puppet) are not restarts and are not listed.

**Probable cause** is a best guess from syslog activity around the restart, in priority
order: unattended package upgrade, puppet, ansible (a LabKey tarball download means a deployment/upgrade),
manual `sudo systemctl..`,host reboot, OOM killer, unplanned stop (crash?),  or not found.
Check the evidence lines the script lists before treating it as fact.

**Problems** to look for:

- `graceful shutdown aborted after 30s with requests still active`: in-flight requests
  (downloads, imports) were dropped and those users got errors.
- `slow shutdown`: over 60 seconds from stop to stopped; usually LabKey's own shutdown
  hooks.
- `stop timed out (SIGTERM), killing`: systemd killed LabKey.
- `no start found after the stop` / `no stop found before the start`: the restart runs off
  the edge of the logs, or LabKey is still down, or it crashed.

The full list and what each means is in the skill
(`.claude/skills/labkey-service-restarts/SKILL.md` in maccosslab-agents).

## Looking closer at one restart

On the server you can read syslog around one restart directly. Use a narrow time pattern
and exclude the noisy sources. Example for a restart at 2026-10-09 06:42:

```bash
zgrep -h "^Oct  9 06:4[0-4]" /var/log/syslog-2026-10-11.gz | grep -vE "postgres\[|java\[" | cut -c1-200 | head -80
```

A rotated `syslog-YYYY-MM-DD.gz` holds lines up to that date, so look in the first file
dated after the restart.

## Related

- [Uptime Monitoring & Alerts](uptime-monitoring.md) - the Grafana checks that usually
  notice a restart first
- [panoramaweb.org access logs](panoramaweb.org/access-logs.md) - server architecture and
  log formats
- maccosslab-agents `README.md` - all agents, local (workstation) runs, and the sandbox
  design
