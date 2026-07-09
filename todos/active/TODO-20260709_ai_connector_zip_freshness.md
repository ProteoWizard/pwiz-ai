# TODO-20260709_ai_connector_zip_freshness.md

## Branch Information
- **Branch**: `Skyline/work/20260709_ai_connector_zip_freshness`
- **Base**: `master`
- **Created**: 2026-07-09
- **Status**: In Progress
- **GitHub Issue**: none
- **PR**: [#4403](https://github.com/ProteoWizard/pwiz/pull/4403)

## Motivation

Philip Remes (Thermo) asked how to locate SkylineCmd.exe for a ClickOnce Skyline
install. While tracing that, the running AI Connector (installed from the Tool Store)
did not expose newer MCP tools (e.g. `skyline_list_installed`) that current Skyline-daily
provides. Root cause: the committed `SkylineAiConnector.zip` had been stuck at version
`26.1.1.077` across many rebuilds. The version stamping froze (it wandered 083 -> 070 ->
084 and settled at 077, then stayed there), while the bundled binaries kept advancing from
current source. So the *code* in the package was current but its *version number* was stale,
and the posted Tool Store package lagged behind Skyline.

`SkylineMcpTest` did not catch this: it installs from the committed ZIP and drives the
bundled server, but nothing asserted the package's stamped version, and the tool-surface
check only compared a hard-coded count (47), which never changed.

## What changed

1. **Rebuilt and reposted the package** at `26.1.1.159` (built from the
   `Skyline-daily-26.1.1.159` tag). The new ZIP is committed here and has already been
   uploaded to the Tool Store on skyline.ms.
2. **SkylineMcpTest version guards** (`EXPECTED_ZIP_VERSION = "26.1.1.159"`, a hand-entered
   constant, deliberately NOT the live Skyline version which is day-of-year derived and
   changes daily):
   - `tool-inf/info.properties` `Version` (the Tool Store's displayed version) must match.
   - Bundled `SkylineMcpServer.exe` FileVersion must match.
   Bumping the constant in lockstep with a rebuild is the discipline gate for a forgotten
   rebuild.
3. **Tool-surface check** now derives the expected set by parsing the
   `[McpServerTool(Name = "...")]` attributes in `SkylineTools.cs` (no hand-maintained
   list) and asserts the server's `tools/list` matches exactly.

## Verification

- `SkylineMcpTest` passes with the rebuilt `26.1.1.159` ZIP.
- Both version checks were confirmed (uncommented in sequence) to fail against the old
  `26.1.1.077` ZIP; the tool-surface check passes against both, since the 077 package
  already carried the full 47-tool set (only the version number was stale) - confirming the
  version check, not the tool-surface check, is what catches this class of regression.

## Follow-ups (separate)

- **release-guide.md**: add an optional step to the Skyline-daily release workflow to
  rebuild + repost the AI Connector ZIP and bump `EXPECTED_ZIP_VERSION` when the MCP
  interface changed since the last release.
- **Why the version stamping froze** (the 083/070/084/077 wandering) is not fully diagnosed;
  the test now catches the symptom. A stuck version stamper is a deeper build-process issue.
- Philip's original question (finding SkylineCmd.exe for a ClickOnce install) is answered via
  the tool API (`GetProcessId` today, or a possible `GetExecutablePath`) rather than the
  filesystem; tracked separately.
