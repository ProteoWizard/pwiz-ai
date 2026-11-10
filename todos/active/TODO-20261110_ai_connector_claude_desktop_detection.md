# TODO-20261110_ai_connector_claude_desktop_detection.md

## Branch Information
- **Branch**: `Skyline/work/20261110_ai_connector_claude_desktop_detection`
- **Base**: `Skyline/skyline_26_1_1` (current Skyline-daily release branch)
- **Created**: 2026-11-10
- **Status**: In Progress - urgent, workshop participants blocked
- **GitHub Issue**: (none - reported live at a workshop)
- **Module**: `skyline`
- **PR**: [#5014](https://github.com/ProteoWizard/pwiz/pull/5014)
- **Checkout**: `C:\proj\pwiz`

## Objective

The AI Connector reported "Claude Desktop (not installed)" for most participants of the
2026-11-10 Skyline + Claude workshop, so they could not register the Skyline MCP server.

`ChatAppRegistry.IsClaudeDesktopInstalled()` tested only whether
`claude_desktop_config.json` existed. Current Claude Desktop builds do not create that file
until the user adds a local MCP server (a participant found this in Claude's documentation),
so on a fresh install the connector concluded Claude Desktop was absent.

## Approach

- `IsClaudeDesktopInstalled()` detects the app, not the config file: the data folder
  (`%APPDATA%\Claude`), a Windows Store package (`%LOCALAPPDATA%\Packages\Claude_*`), or the
  standalone installer folder (`%LOCALAPPDATA%\AnthropicClaude`).
- `ClaudeDesktopConfigPath` prefers an existing config file (standard, then Store-virtualized),
  then the data folder the app already created, then the standard path.
- `AddToClaudeDesktop()` already creates the file and its folder through `EditJsonFile`.
- Tool docs troubleshooting line no longer says launching Claude Desktop creates its config.

## Workaround for the old connector (participants who cannot update)

Create an empty config, then reopen Tools > AI Connector:

```
New-Item -ItemType Directory -Force "$env:APPDATA\Claude" | Out-Null; if (-not (Test-Path "$env:APPDATA\Claude\claude_desktop_config.json")) { Set-Content "$env:APPDATA\Claude\claude_desktop_config.json" '{}' }
```

Adding a stock connector under Settings > Customize > Connectors is not expected to help:
remote connectors are stored with the Claude account, not in this file. (Unverified.) Note the old Settings > Developer > Edit Config entry no longer exists in current Claude Desktop.

## Tasks

- [x] Fix detection and config path in `ChatAppRegistry.cs`
- [x] Update tool-inf docs troubleshooting text
- [x] Build `-Target AiConnector -Configuration Release`; ZIP, connector exe and server exe all 26.1.1.314 (above the posted 26.1.1.289)
- [x] Verified on Brendan's machine with the config set aside: new connector shows Claude Desktop
      enabled, registering creates the file, the checkbox persists across reopen, and Claude
      Desktop Settings > Customize > Connectors lists `skyline`
- [x] Verified the workaround one-liner on the 26.1.1.289 connector: checkbox enabled, registered, Claude Desktop restarted and listed `skyline`; Claude Desktop then added its own `preferences` block to the file and kept the entry
- [x] PR [#5014](https://github.com/ProteoWizard/pwiz/pull/5014) to `Skyline/skyline_26_1_1`
- [ ] Post updated ZIP (26.1.1.314) to the Tool Store (Brendan)
- [ ] `/code-review high 5014`
- [ ] Cherry-pick to master after merge

## Follow-ups (not in this fix)

- `GetClaudeDesktopProcesses()` only recognizes the Store build (`\WindowsApps\`), so a
  standalone-installer Claude Desktop is never seen as running and is not stopped before the
  config write.
- The Claude Code checkbox registers through the `claude` CLI on PATH. Participants using the
  Code tab inside Claude Desktop have `~/.claude.json` (checkbox enabled) but no `claude` on
  PATH, so registration would fail for them.
