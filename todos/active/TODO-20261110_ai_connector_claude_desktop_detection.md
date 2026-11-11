# TODO-20261110_ai_connector_claude_desktop_detection.md

## Branch Information
- **Branch**: `Skyline/work/20261110_ai_connector_claude_desktop_detection`
- **Base**: `Skyline/skyline_26_1_1` (current Skyline-daily release branch)
- **Created**: 2026-11-10
- **Status**: In Progress - fixes posted to the Tool Store, PR awaiting review
- **GitHub Issue**: (none - reported live at a workshop)
- **Module**: `skyline`
- **PR**: [#5014](https://github.com/ProteoWizard/pwiz/pull/5014)
- **Checkout**: `C:\proj\pwiz`

## Objective

Make the AI Connector connect Claude Desktop to Skyline for the participants of the
2026-11-10/11 Skyline + Claude workshop. Three problems surfaced, in order:

1. **"Claude Desktop (not installed)"** for most participants. `IsClaudeDesktopInstalled()` tested
   only whether `claude_desktop_config.json` existed, and current Claude Desktop builds do not
   create that file until the user adds a local MCP server (a participant found this in Claude's
   documentation).
2. **Registered, but Claude Desktop never showed `skyline`** on Windows Store installs. Those read
   their config from the package's virtualized `%LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude\`
   folder, and the connector had written `%APPDATA%\Claude\`, preferring it whenever it existed.
3. **Claude Code checkbox enabled for people without Claude Code.** The Code tab in Claude Desktop
   creates `~/.claude.json` using an embedded `claude.exe` that is not on PATH, so
   `IsClaudeCodeInstalled()` said yes and registration (`claude` from PATH) would fail. That tab
   already sees the servers registered with Claude Desktop, so those users need only the Claude
   Desktop box.

## Approach

- `IsClaudeDesktopInstalled()` detects the app: any data folder (Store `LocalCache` or
  `%APPDATA%\Claude`), a Store package, or the standalone installer folder (`%LOCALAPPDATA%\AnthropicClaude`).
- `ClaudeDesktopConfigPaths` returns every existing config file, Store package copy first; with
  none, the first existing data folder (Store copy first), else `%APPDATA%\Claude`.
  `AddToClaudeDesktop` writes all of them, `RemoveFromClaudeDesktop` cleans every existing one,
  `IsRegisteredInClaudeDesktop` reads the first.
- `IsClaudeCodeInstalled()` also requires `claude.exe` on PATH, matching what `RunClaudeCli` runs.
- `GetClaudeDesktopProcesses()` also matches `\AnthropicClaude\`, so a standalone-installer Claude
  Desktop is closed before the config write.
- Docs: troubleshooting gives the empty-config workaround; the setup section says the Code tab
  uses the Claude Desktop registration.

## Versions posted to the Tool Store

| Version | Contents | Commit |
|---|---|---|
| 26.1.1.314 | Detection fix (1) | fc57278868 |
| 26.1.1.315 | + Store fix (2), review fixes | never committed; the Tool Store refused a rebuilt 315 |
| 26.1.1.316 | + Claude Code check (3) | 1c8d713591 |

The version comes from the generated, untracked `Properties\AssemblyInfo.cs`, which Jam stamps
from the HEAD commit's date (day of year). 315 and 316 were stamped by hand a day ahead so the
Tool Store would accept them, so **the next official connector build needs a commit dated
2026-11-13 or later** (day 317) to be accepted.

## Workaround for the old connector (participants who cannot update)

Create an empty config, then reopen Tools > AI Connector (does not help Store installs that
virtualize their config):

```
New-Item -ItemType Directory -Force "$env:APPDATA\Claude" | Out-Null; if (-not (Test-Path "$env:APPDATA\Claude\claude_desktop_config.json")) { Set-Content "$env:APPDATA\Claude\claude_desktop_config.json" '{}' }
```

Settings > Developer > Edit Config no longer exists in current Claude Desktop.

## Tasks

- [x] Detection fix (1); verified on Brendan's machine with the config set aside, and the workaround verified on 26.1.1.289
- [x] PR [#5014](https://github.com/ProteoWizard/pwiz/pull/5014) to `Skyline/skyline_26_1_1`
- [x] `/code-review high 5014`: fixed standalone-installer process detection, Remove creating a config file, docs workaround. Dropped: false positive after uninstall (old code had it too), install-location refactor (out of scope for a hotfix), stale "(not installed)" label (affects every client), Packages enumeration cost (negligible). The dropped AppData folder-order finding turned out to be problem (2).
- [x] Store fix (2): 26.1.1.315 posted; all but one participant connected
- [x] Claude Code check (3): verified in the 26.1.1.316 binary (true with `claude` on PATH, false without)
- [ ] Post 26.1.1.316 to the Tool Store (Brendan)
- [ ] Cherry-pick to master after merge

## Not fixed: locked-down machine (2026-11-11)

One participant's machine showed a Windows prompt for his password to access `~\.skyline-mcp`
(the deployed server and Skyline's `connection-*.json` files). It was resolved in the room
without code. If it recurs, the candidate change is moving that folder to `%LOCALAPPDATA%`, which
every app must be able to write and where Skyline itself runs as a ClickOnce app; not Documents,
which Controlled Folder Access protects by default and OneDrive often redirects. Skyline
(`JsonToolServer`), the server (`SkylineConnection`) and the connector (`McpServerDeployer`) all
use `JsonToolConstants.GetConnectionDirectory()`, so it needs a Skyline-daily release too, with
the server reading both locations.
