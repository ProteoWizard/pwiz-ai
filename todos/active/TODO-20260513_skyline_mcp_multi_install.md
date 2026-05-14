# TODO-20260513_skyline_mcp_multi_install.md

## Branch Information
- **Branch**: `Skyline/work/20260513_skyline_mcp_multi_install`
- **Base**: `master`
- **Created**: 2026-05-13
- **Status**: In Progress
- **GitHub Issue**: (none yet — split from `ai/todos/backlog/brendanx67/TODO-skyline_mcp_followups.md` Item 5)
- **PR**: (pending)

## Purpose

Item 5 from `TODO-skyline_mcp_followups.md` (Seattle Claude Code Meetup
demo follow-ups). Today the LLM cannot:

- Enumerate which Skyline releases are installed on this machine
  (Skyline, Skyline-daily, plus their administrative installs at
  `C:\Program Files\Skyline[-daily]`).
- Launch a new Skyline GUI instance from MCP. The demo required the
  human to manually open a third Skyline window for the "new instance
  arrives" beat.

This TODO adds two MCP tools:

- `skyline_list_installed()` — enumerate installs with name, release,
  version, install scope, and executable path.
- `skyline_start_instance(release)` — launch the GUI for the named
  release, snapshot existing connection files, poll
  `~/.skyline-mcp/connection-*.json` for the new PID with a ~30 s
  timeout, return full instance info on success.

Items 9 (JsonServer alert capture) and 10 (CI for SkylineMcp.sln) stay
in the brendanx67 backlog file for separate PRs.

## Scope

- [ ] New `SkylineInstallation.cs` in `SkylineMcpServer` — POCO +
      static `FindAll()` mirroring `SharedBatch/SkylineInstallations`
      discovery logic without taking a project reference. Returns:
      `Name`, `Release` (Skyline | Skyline-daily), `Version`,
      `InstallScope` (user_clickonce | system_admin), `ExecutablePath`.
- [ ] New `LaunchAndWaitForConnection(release, timeoutSeconds)` helper
      in `SkylineConnection` (or sibling class) — snapshot existing
      connection file PIDs, launch via `Process.Start(exePath)` for
      admin installs or shell-execute the `.appref-ms` for ClickOnce,
      poll `FindConnectionFiles()` for a new PID, return the new
      `InstanceInfo` or a timeout message.
- [ ] New `skyline_list_installed` MCP tool in
      `SkylineMcpServer/Tools/SkylineTools.cs` — tab-separated output
      matching existing enumeration tools.
- [ ] New `skyline_start_instance` MCP tool in same file.
- [ ] Bump `EXPECTED_TOOL_COUNT` in `SkylineMcpTest.cs` (44 → 46).
- [ ] `TestSkylineMcp` coverage:
  - List-installed: verify the running instance's release (Skyline
    or Skyline-daily) shows up with a parseable version.
  - Start-instance: skipped by default unless explicitly enabled —
    launching a second Skyline mid-test may not be safe in CI.
- [ ] Rebuild `SkylineAiConnector.zip` per round-1 pattern.

## Design Notes

### Discovery code placement (decision)

New focused class inside `SkylineMcpServer`. Mirrors the SharedBatch
logic but returns a `List<SkylineInstallation>` POCO instead of writing
`Settings.Default`. SkylineMcpServer stays self-contained — no project
reference to `SharedBatch/`.

### Launch semantics (decision)

Launch + poll for connection, with a ~30 s timeout. The auto-connect
preference (`Settings.Default.EnableMcpAutoConnect` inside Skyline) is
per-user-per-release config; we can't query it from outside the new
Skyline process. So:

- If the user has enabled auto-connect for the chosen release, the new
  instance writes its connection file on startup and we return its full
  `InstanceInfo` within seconds.
- If auto-connect is off, the poll times out and we return the PID plus
  a hint: "If the AI Connector is not enabled at startup, click
  Tools > AI Connector in the new Skyline window."

This matches the existing `skyline_get_instances` behavior and reuses
`SkylineConnection.FindConnectionFiles()` (already private — may need
to expose).

### ClickOnce version reporting

For administrative installs, `FileVersionInfo.ProductVersion` on
`Skyline.exe` / `SkylineCmd.exe` gives the version directly.

For ClickOnce installs (`.appref-ms` shortcuts in
`%AppData%\Microsoft\Windows\Start Menu\Programs\MacCoss Lab, UW\` or
`Programs\<AppName>\`), the deployment URL embedded in the .appref-ms
file usually contains the version (e.g.
`.../skyline-23.1.0.380/Skyline.application`). Parse the version out
of that URL when available; otherwise label "ClickOnce (auto-update)".

Launching ClickOnce installs uses `Process.Start` with
`UseShellExecute = true` on the `.appref-ms` path — the spawned process
PID is not directly available, so the connection-file poll is what
identifies the new instance.

### Open scope decisions for review

- Should `skyline_list_installed` also flag which install is the
  *running* MCP-connected one? Probably yes — show an `[ACTIVE]` tag
  like `skyline_get_instances` does. Decide during impl.
- Should `skyline_start_instance` accept a document path to open?
  Useful, but matches what `skyline_run_command --in=...` already
  does on the *current* instance. Start without that, add later if
  needed.

## Files Expected to Change

- `pwiz/pwiz_tools/Skyline/Executables/Tools/SkylineMcp/SkylineMcpServer/SkylineInstallation.cs` (new)
- `pwiz/pwiz_tools/Skyline/Executables/Tools/SkylineMcp/SkylineMcpServer/SkylineConnection.cs` (extend with launch + poll)
- `pwiz/pwiz_tools/Skyline/Executables/Tools/SkylineMcp/SkylineMcpServer/Tools/SkylineTools.cs` (two new tools)
- `pwiz/pwiz_tools/Skyline/Executables/Tools/SkylineMcp/SkylineAiConnector/SkylineAiConnector.zip` (regenerated)
- `pwiz/pwiz_tools/Skyline/TestFunctional/SkylineMcpTest.cs` (EXPECTED_TOOL_COUNT bump + coverage)

## Related

- Round-1 umbrella TODO: `ai/todos/completed/TODO-20260512_skyline_mcp_fixes.md`
- Followups backlog: `ai/todos/backlog/brendanx67/TODO-skyline_mcp_followups.md`
- Reference (not referenced as a project dep):
  `pwiz/pwiz_tools/Skyline/Executables/SharedBatch/SharedBatch/SkylineInstallations.cs`
