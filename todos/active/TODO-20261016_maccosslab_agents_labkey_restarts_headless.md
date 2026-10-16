# TODO-20261016_maccosslab_agents_labkey_restarts_headless.md

## Branch Information
- **Repository**: `uw-maccosslab/maccosslab-agents` (local checkout `~/dev/ai-dev/maccosslab-agents`)
- **Branch**: `work/20261016_labkey_restarts_headless`
- **Base**: `main`
- **Created**: 2026-10-16
- **Status**: In Progress
- **PR**: (pending)
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
- [ ] Decide the headless form: `claude -p` with `--permission-mode manual` and
      `--permission-prompts none` (anything not pre-approved is denied, not prompted)
- [ ] Lock the session down: `--tools` limited to what the command needs (Skill, Bash),
      `--strict-mcp-config` with no MCP servers, `failIfUnavailable: true` so it refuses to
      run unsandboxed, and no `dangerouslyDisableSandbox` retry
- [ ] Sandbox boundary on the server: deny reads of secrets (home directories, LabKey
      config with database credentials, SSH keys), no writes outside a scratch directory,
      no network for sandboxed commands (the script needs none)
- [ ] Log access: which account runs it and how it reads `/var/log/syslog*` and the
      LabKey log directory (e.g. `adm` group) without root
- [ ] Wrapper script or documented command line (default log directories on the server,
      model, `--since`/`--until` pass-through)
- [ ] Server setup notes: Claude Code install, `bubblewrap` and `socat`, authentication
      (`CLAUDE_CODE_OAUTH_TOKEN` from `claude setup-token`, stored mode 600)
- [ ] Verify: denied actions are denied (write outside the scratch dir, network access,
      reading a denied path), and the report is the same as on the workstation
- [ ] Update README.md, CLAUDE.md, and the skill/command docs

## Progress

### 2026-10-16 - Started

- Created branch `work/20261016_labkey_restarts_headless` with the `.claude/settings.json`
  change (skill allow rule, sandbox block off by default).
- Confirmed in the Claude Code docs: `--settings` enables the sandbox for one session
  without writing a settings file; `/sandbox` saves its mode to
  `.claude/settings.local.json`; `--permission-mode manual` is an alias for `default`;
  `Skill(name)` allow rules skip the "Use skill" prompt.

## Open Questions

- Is Claude needed on the server at all? `.venv/bin/labkey-service-restarts` alone gives
  the tables with no Claude, no network, and no bill; Claude adds only the written summary.
  Alternative: run the script on the server and interpret its output elsewhere.
- Which model and account (subscription token vs API key) for server runs?
- Run on demand only, or on a schedule with the result emailed like the access log review?

## Success Criteria

- One documented command runs `/pw-labkey-restarts` on the web server, headless, in manual
  permission mode with the sandbox enforced, and fails rather than running unsandboxed
- The session cannot write outside its scratch directory, reach the network from Bash, or
  read secrets on the server
- The output contains no IPs, URLs, or LabKey usernames
