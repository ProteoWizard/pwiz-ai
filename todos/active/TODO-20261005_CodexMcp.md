# TODO-20261005_CodexMcp.md

## Branch Information
- **Branch**: `Skyline/work/20261005_CodexMcp` (checkout `I:\git_i\sky_chatgpt`)
- **Base**: `Skyline/work/20260612_net8_port` (the connector is net10 there; master's connector is net472,
  where `ProcessStartInfo.ArgumentList` does not exist)
- **Created**: 2026-10-05
- **Status**: PR open, awaiting human review and a live checkbox test
- **Module**: `skyline`
- **PR**: [#4772](https://github.com/ProteoWizard/pwiz/pull/4772)

## Objective

Let OpenAI Codex use the Skyline MCP server: add Codex to the AI Connector's client registrations alongside
Claude Desktop, Claude Code, Gemini/Antigravity, VS Code and Cursor. Codex (the agent) started the work as
uncommitted changes on the port branch; Claude finished, reviewed and opened the PR.

## Design
- **Writes through the CLI**: `codex mcp add skyline -- <deployed exe>` / `codex mcp remove skyline`, run with
  `ArgumentList` and cwd = user profile (so no project-level Codex config is picked up).
- **Reads the file**: installed = `$CODEX_HOME` (default `~/.codex`) exists; registered = a
  `[mcp_servers.skyline]` line in its `config.toml`. Same split as the Claude Code client. An earlier version
  probed with `codex mcp list --json` on the UI thread; review showed that loads auth/cloud config, can refresh
  tokens over the network, and could disable the checkbox on failure.
- **Finding codex.exe** (only when the box is toggled): PATH `codex.exe`, else an npm `codex.cmd` on PATH resolved
  to `node_modules\@openai\codex*\...\<target triple>\codex.exe` for the OS architecture, else the newest
  `%LOCALAPPDATA%\OpenAI\Codex\bin\<hash>\codex.exe` bundled with the desktop app.

## Findings
- Codex requires approval for every MCP tool call by default; `codex exec` (approval never) refuses them.
  `default_tools_approval_mode` under `[mcp_servers.skyline]` accepts `auto | prompt | writes | approve`;
  `approve` let `codex exec` call `skyline_get_instances`. The connector deliberately does not set it
  (no other client gets pre-approved tools).
- Codex 0.160 `codex mcp list --json` returns an array of `{name, enabled, transport, ...}`; `mcp add` writes a
  plain `[mcp_servers.skyline]` table with `command = '<path>'`.

## Gates
- [x] Connector builds (dotnet build, 0 warnings); ZIP 26.1.1.278 = `EXPECTED_ZIP_VERSION`
- [x] TestSkylineMcp passes (net10 Release, `Run-Tests.ps1 -SourceRoot I:\git_i\sky_chatgpt -Configuration Release`)
- [x] Detection + remove/add round trip via reflection against the real Codex desktop bundle
- [x] `codex exec` launched SkylineMcpServer and called a tool
- [x] `/code-review max` triaged; fixes in 5c614d7be5
- [x] Copilot threads (localization only) answered and resolved: the connector has no localized resources
- [ ] Toggle the Codex checkbox in a live AI Connector with Skyline running

## Dropped review items
- Shared runner for `RunClaudeCli`/`RunCodexCli`; `RunClaudeCli` ignores its 10 s WaitForExit result. Pre-existing,
  candidate for separate work.
- `startup_timeout_sec`, stale status label, managed/cloud-layer skyline entries, Kill() of a shim's child tree:
  edge cases, not worth the code.
