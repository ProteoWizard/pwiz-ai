# TODO-20261005_McpForwardCompatibility.md

## Branch Information
- **Branch**: `Skyline/work/20261005_CodexMcp` (checkout `I:\git_i\sky_chatgpt`). Started as
  `Skyline/work/20261005_McpForwardCompatibility`, fast-forwarded into the Codex branch and deleted (never pushed);
  PR #4772 now covers Codex support and compatibility with earlier Skyline-dailies.
- **Base**: `Skyline/work/20260612_net8_port`
- **Created**: 2026-10-05
- **Status**: Completed (Remaining items deferred, see Progress Log)
- **Module**: `skyline`
- **PR**: [#4772](https://github.com/ProteoWizard/pwiz/pull/4772) (merged 2026-10-08; also see TODO-20261005_CodexMcp.md)

## Objective

There is one Tool Store, so Skyline 26.2 release users and Skyline-daily users run the same AI Connector. A new
connector must be safe to publish even when it has tools the released Skyline does not support: the MCP server
should offer each user only what their running Skyline can do.

After 26.2 ships, existing `IJsonToolService` methods are frozen in behavior (external tools depend on them), so
the methods in a Skyline's `SkylineTool.dll` fully describe what it supports. New behavior arrives as new methods.

## Design (as built)
- **Minimum version** `MainForm.MIN_SKYLINE_VERSION` = 26.1.1.083, the first released daily with the JSON-RPC
  `IJsonToolService` (replaced checks of 061 in the message and 070 in code). Nick's call: easy to test against;
  it need not work perfectly there, and no code is added just for old dailies.
- **Hand-coded declarations**, not call-graph analysis (a tool may later prefer a new method and fall back, which
  analysis would over-report). `[RequiresJsonToolServiceMethod(nameof(IJsonToolService.X))]` (AllowMultiple) names
  the newest method a tool needs beyond the minimum; methods are only ever added. 25 tools declared; image tools and
  `new_document` (SetUiMode only when uiMode is passed) left undeclared on purpose.
- **`ToolAvailability`**: reads the targeted Skyline's `SkylineTool.dll` (folder of the process's MainModule) with
  System.Reflection.Metadata, collecting `SkylineTool.IJsonToolService` method names; cached per path + timestamp.
  Unreadable or no Skyline -> no filtering (the -32601 "not available in <version>" error still applies).
- **Program.cs**: list-tools filter hides unsupported tools; call-tool filter sends `notifications/tools/list_changed`
  once when the target's method set differs from what the client last listed. Continuations, no async/await.
- `SkylineConnection.GetTargetProcessId()` mirrors TryConnect's choice without connecting (does not reproduce its
  skip-to-next-instance on a failed connect).
- `QueryAvailableMethods` removed (d4db7dfe98): names only, no parameters; nothing called it.

## Verified
- [x] TestSkylineMcp, TestJsonToolServer, CodeInspection pass
- [x] Stdio probe of the deployed server with 083 running: listChanged=true, 41 of 66 tools listed
- [x] Live in Claude Code with 083, 209, 265 running: 41 / 60 / 65 tools; `skyline_set_instance` to 083 dropped 24
  tools via list_changed without reconnecting, `skyline_set_instance(0)` restored them

## Findings
- Released dailies with the interface: 083 (36 methods), 097 (41), 159 (46), 209 (61), 265 (66); 058 has none.
  Pre-freeze signature changes: ImportFasta/ImportProperties/SelectSettingsListItems void -> ActionResult (through
  159; `DescribeAction` NREs on null there, accepted), graphId -> formId rename (same meaning).
- Deployment is shared: one `~/.skyline-mcp/server`, a connector copy per Skyline install. `McpServerDeployer`
  compares the apphost exe's timestamp and size; the apphost is 162,304 bytes in every build, so only the
  timestamp decides. Installed copies keep ZIP (build) timestamps, so an older connector normally does not
  downgrade, but nothing guarantees it. When files are locked it kills running servers (`StopMcpServerProcesses`).

## Remaining
- [ ] Deploy by FileVersion (only when the connector's server is newer) instead of apphost timestamp/size
- [ ] `Dispatch`: reject calls with more arguments than the method has (silent drop today), before 26.2 branches
- [ ] Test: relaunching AI Connector in an older Skyline makes it most recent -> next call re-filters
- [ ] Test: targeted Skyline exits -> fallback and tools restored
- [ ] Possibly: install folder in the connection file (MainModule fails for an elevated Skyline)
- [ ] Possibly: argument trimming against target signatures (needs parameter metadata, not just names)
- [x] Update the PR title/description for the broader scope when pushing

## Progress Log

### 2026-10-08 - Merged

PR #4772 merged to master as commit 93c1b9a5 (admin override). Shipped `RequiresJsonToolServiceMethod` on 25 tools,
`ToolAvailability` filtering with `tools/list_changed`, a single `MIN_SKYLINE_VERSION` (26.1.1.083), and removal of
`QueryAvailableMethods`. The other unchecked Remaining items were not done and are deferred: FileVersion-based
deployment, `Dispatch` rejecting extra arguments (wanted before 26.2 branches), the two re-filter tests, the install
folder in the connection file, and argument trimming.
