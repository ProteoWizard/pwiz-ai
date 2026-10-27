# TODO-20261016_maccosslab_agents_labkey_restarts_headless.md

## Branch Information
- **Repository**: `uw-maccosslab/maccosslab-agents` (local checkout `~/dev/ai-dev/maccosslab-agents`)
- **Branch**: `work/20261016_labkey_restarts_headless`
- **Base**: `main`
- **Created**: 2026-10-16
- **Status**: Completed
- **PR**: [#6](https://github.com/uw-maccosslab/maccosslab-agents/pull/6) (merged 2026-10-27)
- **Objective**: Run `/pw-labkey-restarts` from the command line in a secure way, with the
  permission mode set to manual and the Bash sandbox enabled, so that it can be run on the
  web server itself (panoramaweb.org) against its live syslog and labkey.log.

## Background

The restart finder (`TODO-20261014_maccosslab_agents_service_restarts.md`, completed, PR #5)
runs on a workstation against copied logs. Running it on the web server avoids copying
about 1 GB of syslog, but a Claude Code session on a production server must not be able to
change the server, read secrets, or reach the network beyond what it needs.

Already in place:
- `labkey-service-restarts` is plain Python, reads logs only, and prints built descriptions
  (no raw lines, IPs, URLs, or LabKey usernames).
- `.claude/commands/pw-labkey-restarts.md` has
  `allowed-tools: Bash(.venv/bin/labkey-service-restarts:*)`, so the script needs no prompt.
- The scan runs inside the sandbox (workers start with `fork` on Linux; PR #5).
- On this branch, `.claude/settings.json` has `Skill(labkey-service-restarts)` in
  `permissions.allow` (no "Use skill" prompt) and a `sandbox` block that is off by default
  with `autoAllowBashIfSandboxed: false` and `allowUnsandboxedCommands: false`.

Command that works on the workstation (interactive, prompts for anything else):

```bash
claude --permission-mode manual --model claude-haiku-5-5 \
  --settings '{"sandbox": {"enabled": true}}' \
  "/pw-labkey-restarts --since 2026-10-09 --until 2026-10-10 --syslog-dir ../examples/panoramaweb.org/syslogs --labkey-dir ../examples/panoramaweb.org/labkey-logs"
```

## Tasks

- [x] Allow the `labkey-service-restarts` skill without a prompt; add the sandbox block
      (off by default) to `.claude/settings.json`
- [x] Decide the headless form: `claude -p` with `--permission-mode manual` and
      `--permission-prompts none` (anything not pre-approved is denied, not prompted)
- [x] Lock the session down: `--tools Bash,Skill`, `--strict-mcp-config`,
      `--setting-sources project`, `disableAllHooks`, `failIfUnavailable: true`,
      `allowUnsandboxedCommands: false`, `--no-session-persistence`
- [x] Sandbox boundary: `denyRead: ["/"]` with `allowRead` for system dirs, the checkout and
      the log dirs; `denyWrite` on src/.venv/server/.git/.claude; no network
      (`strictAllowlist`); token env vars denied to sandboxed commands
- [x] Log access: not tied to an account (developer's decision); any account that can read
      the logs runs it. LabKey logs are in `/data/labkey/logs`, now the `LABKEY_DIR` default
- [x] Wrapper script: `server/labkey-restarts-claude.sh` (renamed from
      `labkey-restarts-headless.sh` in `14fedb4` at the developer's request; `SYSLOG_DIR` default
      `/var/log`, `LABKEY_DIR` default `/data/labkey/logs`, a missing directory stops with
      an error, `MODEL` default Haiku, `--since`/`--until` only, `--settings-json` prints
      the settings)
- [x] Server setup notes in README.md ("Running on the web server")
- [x] Verify on the workstation: `server/verify-lockdown.sh` passed all checks; the report
      matched the workstation run (2026-10-09 06:42 LabKey restart, unattended upgrade)
- [x] Verify the token is hidden: with `~/.config/maccosslab-agents/env` loaded, the verify
      script passed, including "CLAUDE_CODE_OAUTH_TOKEN value not in the report", and
      `printenv` in the sandbox printed 0 characters
- [x] Web server environment modules: `server/server-env.sh` (sourced by all the server scripts) runs
      `module load python/3.13.10` and `module load bubblewrap/0.11.1`, and stops with an
      error if `module` is missing, a load fails, or `.venv` doesn't exist. `MODULES=` skips
      them. The venv Python's `sys.base_prefix` is added to `allowRead`. Failure paths tested
      with a fake `module` function; end-to-end runs passed with `MODULES=`
- [x] Verify on the server: the developer ran `server/verify-lockdown.sh` on the web server and it passed (first real `module load`;
      confirm socat is on PATH, and that the module Python's shared libraries are under its
      `sys.base_prefix`, else add their directory to `allowRead`)
- [x] Update README.md and CLAUDE.md; the skill and command needed no change. README keeps
      the "script only on the server" option alongside the headless one
- [x] Push the branch and open PR #6 (5 commits: `01f28a6`, `f6790e8`, `69f1767`,
      `42a3908`, `aca7d47`)
- [x] `server/claude-sandboxed.sh`: interactive `claude` in manual mode, sandbox required,
      token env vars denied to sandboxed commands. At first no allow/deny rules; then
      (`9012eb3`, developer's request) `enabledMcpjsonServers: ["access_log_review"]` and
      allow rules for `mcp__access_log_review`, the `labkey-service-restarts` skill and
      script, and `access-log-review --no-agent`. A full (billed) `access-log-review` run
      still prompts; the pipeline is not allowed
- [x] `server/labkey-restarts.sh`: `.venv/bin/labkey-service-restarts` with the headless
      script's directories, modules and `--since`/`--until`, no Claude (README "Script only")
- [x] Committed `c0e4a59` (both scripts, plus the developer's README reorganization, which
      left a duplicate "## Running Access Log Review" heading above "Service restarts";
      developer asked to commit it as is) and pushed to PR #6; PR description updated
- [x] Committed `14fedb4` (rename) and `9012eb3` (allow rules, plus the developer's README
      edit adding an `export $(grep ... | xargs)` way to load the env file) and pushed
- [x] After the server run: tick the last test plan item on PR #6, then merge
- [x] Slide deck on the sandbox for a team talk: `docs/claude-code-sandbox.html`
      (standalone HTML, 4 slides: sandboxing approaches, how it works with Manual/Auto
      mode, the settings, our setup with example commands; speaker notes on `N`). The
      developer reworded it for a human audience and checked it in a browser; do not edit
      it (committed as `69f1767`)

## Progress

### 2026-10-16 - Started

- Created branch `work/20261016_labkey_restarts_headless` with the `.claude/settings.json`
  change (skill allow rule, sandbox block off by default).
- Confirmed in the Claude Code docs: `--settings` enables the sandbox for one session
  without writing a settings file; `/sandbox` saves its mode to
  `.claude/settings.local.json`; `--permission-mode manual` is an alias for `default`;
  `Skill(name)` allow rules skip the "Use skill" prompt.
- The developer ran the command above (manual mode, Haiku, `--settings` sandbox) after
  the skill allow rule; the "Use skill" prompt was the only prompt they reported.
- Added `docs/claude-code-sandbox.html` (commit `f6790e8`), a 3-slide deck for presenting
  the sandbox. It replaced a claude.ai artifact version, which was deleted at the
  developer's request: the deck belongs in the repository as a plain HTML file. No browser
  on the WSL machine, so the layout is unchecked; slide 1's Auto mode card is the tightest.
- Facts gathered from the docs for the headless work:
  - Sandbox covers Bash, PowerShell and Monitor commands and their child processes only.
    Read/Edit/Write/WebFetch, hooks, MCP servers, LSP servers, and `!` commands run outside.
  - Default reads cover most of the machine, including `~/.ssh` and `~/.aws/credentials`:
    use `filesystem.denyRead` / `credentials` on the server.
  - Network: no direct route out; a proxy checks hosts against `allowedDomains` (empty by
    default). Manual mode prompts for other hosts; `dontAsk` refuses; `strictAllowlist`
    (user, managed or `--settings` only) refuses in every mode.
  - `allowUnsandboxedCommands: false` in `--settings` makes the sandbox admin-required
    (repository settings that loosen it are ignored), which may be what the server wants.
  - Manual-mode retry outside the sandbox prompts "Bash command (unsandboxed)"; `dontAsk`
    denies it.

### 2026-10-26 - Headless wrapper and verification

- Developer chose headless Claude on the server, keeping "script only" documented as an
  alternative.
- Findings from test runs (outputs in `ai/.tmp/sessions/20261026-headless/`):
  - `--restricted` stops project commands loading (Claude got `/pw-labkey-restarts` as
    plain text); `--setting-sources ""` also drops them (only the skill loaded).
    `--setting-sources project` loads the command; `--settings` outranks project settings.
  - `denyWrite` on the whole checkout makes bwrap fail ("Can't create file at
    .../.gitconfig: Read-only file system"): the sandbox mounts protective files in the cwd.
    Denying the code subdirectories instead works.
  - With `denyRead: ["/"]`, denied areas look empty and writes there succeed in a throwaway
    layer (Claude reported `touch ~/...` succeeded; nothing reached the disk), so the
    verify script checks the disk, not Claude's report.
  - Unapproved commands (`ls`, `git`) were denied without a prompt; the egress proxy
    refused example.com (curl exit 56).

- Committed the developer's deck edits as is (`69f1767`); the developer asked that the
  deck not be edited further.
- Token test: with `~/.config/maccosslab-agents/env` (mode 600) loaded, the session
  authenticated with `CLAUDE_CODE_OAUTH_TOKEN`, and the verify script confirmed sandboxed
  commands can't see it (added a check that the token's value is not in the report,
  without ever printing it).
- Web servers need `module load python/3.13.10` and `module load bubblewrap/0.11.1` before
  the run; the developer asked for a clear error and a stop if either fails or `.venv` is
  missing. Added `server/server-env.sh` for both scripts. It sources
  `/etc/profile.d/lmod.sh` or `modules.sh` if `module` isn't defined (an assumption about
  the servers). The tool shell is zsh, so fake-`module` tests ran under `bash -c` (zsh has
  no `export -f`).
- Developer: don't tie the setup to a specific account; LabKey logs are in
  `/data/labkey/logs` (now the default).
- Committed `42a3908` (runner, verify, env, docs) and `aca7d47` (log directory default),
  pushed, and opened PR #6 in the PR #5 format. `/code-review` was not run (skipped on past
  PRs in this repo).

### 2026-10-27 - More server scripts

- Added `server/labkey-restarts.sh` (no Claude) and `server/claude-sandboxed.sh`
  (interactive); renamed the headless runner to `labkey-restarts-claude.sh`.
- `claude-sandboxed.sh` tests: a `python3` write to `/var/tmp` failed with "Read-only file
  system"; the token was hidden (`printenv` 0 bytes); simulating a fresh server checkout
  (`--setting-sources project --permission-prompts none`), the MCP tool, `access-log-review
  --no-agent --help` and `labkey-service-restarts --help` all ran without a prompt.
- Testing gotchas: Claude Code's permission check refuses commands that name a path outside
  the working directory even when the command is allowed, so a sandbox write test must
  hide the path (e.g. inside `python3 -c`); `--allowedTools` takes several values and
  swallows a following prompt, so use `--allowedTools=...`. `verify-lockdown.sh` ignores
  arguments (`--help` starts a real run).
- Noted to the developer, not changed: the README has a duplicate "## Running Access Log
  Review" heading above "Service restarts"; the `export $(grep ... | xargs)` form breaks on
  values with spaces or quotes (fine for the token).

### 2026-10-27 - Merged

PR #6 merged as commit `a41bd6c`. Shipped: `server/labkey-restarts-claude.sh` (headless
`/pw-labkey-restarts`, locked down with the sandbox required), `server/labkey-restarts.sh`
(no Claude), `server/claude-sandboxed.sh` (interactive, sandbox required, access log MCP
and scripts allowed), `server/server-env.sh` (modules and `.venv` checks),
`server/verify-lockdown.sh`, the project sandbox settings, the sandbox slide deck, and the
README section on running on the web server. The developer ran `verify-lockdown.sh` on the
web server and it passed. Not confirmed in this session: the headless and no-Claude reports
on the server's live logs, and `claude-sandboxed.sh` on the server. Still open: whether to
run the report on a schedule with emailed results.

After the merge, added a CLAUDE.md pointer to this TODO on maccosslab-agents `main`
(`3e486a3`), as was done for PR #5.

## Next Steps (at merge)

1. On the web server, as any account that can read `/var/log/syslog*` and
   `/data/labkey/logs`: clone the branch, `module load python/3.13.10`, create `.venv`, put
   the token in `~/.config/maccosslab-agents/env`, then run `server/verify-lockdown.sh`.
   If it fails, likely causes: `module` init in another file, `socat` missing from PATH,
   the module Python's shared libraries outside its `sys.base_prefix` (add to
   `allowRead`), or the account can't read the logs.
2. Run `server/labkey-restarts-claude.sh --since ... --until ...` and
   `server/labkey-restarts.sh` there and compare with the workstation report.
3. Try `server/claude-sandboxed.sh` there; the access log tools default to
   `logs/panoramaweb.org/{apache,tomcat}` in the checkout, so pass `--apache-dir` /
   `--tomcat-dir` if the server's logs are elsewhere.
4. Tick the PR #6 test plan item, merge, then `/pw-complete`.

## Open Questions

- (Resolved 2026-10-26) Is Claude needed on the server? Developer chose headless Claude;
  running the script alone stays documented in README as an alternative.
- (Resolved 2026-10-26) Model and account: Haiku by default (`MODEL` overrides), a
  subscription token from `claude setup-token`; not tied to a specific server account.
- Run on demand only, or on a schedule with the result emailed like the access log review?

## Success Criteria

- One documented command runs `/pw-labkey-restarts` on the web server, headless, in manual
  permission mode with the sandbox enforced, and fails rather than running unsandboxed
- The session cannot write outside its scratch directory, reach the network from Bash, or
  read secrets on the server (as built: writes to the code directories are denied, writes
  outside the checkout land in a throwaway layer, and the checkout root's other files stay
  writable because the sandbox needs to mount protective files there)
- The output contains no IPs, URLs, or LabKey usernames
