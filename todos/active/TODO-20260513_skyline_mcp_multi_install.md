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
demo follow-ups). Today the LLM cannot enumerate which Skyline releases
are installed on this machine — Skyline, Skyline-daily, and their
administrative installs at `C:\Program Files\Skyline[-daily]`.

This TODO adds one MCP tool:

- `skyline_list_installed()` — return a structured list with enough
  info to either launch the GUI (`GuiPath`) or invoke the CLI
  (`CliPath`) for each detected install.

The bigger motivation, surfaced during design discussion: with
`CliPath` in hand, an LLM can write shell or Python scripts to run
SkylineCmd in batch — exactly the workflow Skyline Batch was built to
serve but that struggled to land with users unfamiliar with batch
scripting. LLMs flip that ergonomic gap.

`skyline_start_instance` was dropped from this PR — once
`skyline_list_installed` returns `GuiPath`, the LLM can launch via its
own shell. If "launch + wait for connection file" turns into a
recurring pattern, add it back as a generalized helper in a follow-up.

Items 9 (JsonServer alert capture) and 10 (CI for SkylineMcp.sln) stay
in the brendanx67 backlog file for separate PRs.

## Scope

- [ ] New `SkylineInstallation.cs` in `SkylineMcpServer` — POCO +
      static `FindAll()` mirroring `SharedBatch/SkylineInstallations`
      discovery logic without taking a project reference. POCO:
      `Name`, `Release` (Skyline | Skyline-daily), `Version`,
      `InstallScope` (user_clickonce | system_admin),
      `GuiPath`, `CliPath`.
- [ ] New `skyline_list_installed` MCP tool in
      `SkylineMcpServer/Tools/SkylineTools.cs` — tab-separated output
      with all POCO columns, matching existing enumeration tools.
- [ ] Bump `EXPECTED_TOOL_COUNT` in `SkylineMcpTest.cs` (44 → 45).
- [ ] `TestSkylineMcp` coverage: verify at least one install entry
      with non-empty `GuiPath` is returned on a developer machine
      (since the test runs inside Skyline, the running release must
      be installed).
- [ ] Rebuild `SkylineAiConnector.zip` per round-1 pattern.

## Design Notes

### Discovery code placement (decision)

New focused class inside `SkylineMcpServer`. Mirrors the SharedBatch
logic but returns a `List<SkylineInstallation>` POCO instead of writing
`Settings.Default`. SkylineMcpServer stays self-contained — no project
reference to `SharedBatch/`.

### What gets reported per install (decision)

**Administrative installs** (`C:\Program Files\Skyline\` and
`C:\Program Files\Skyline-daily\`):

- `GuiPath` = `Skyline.exe` / `Skyline-daily.exe` in the install dir
- `CliPath` = `SkylineCmd.exe` in the same dir
- `Version` = `FileVersionInfo.ProductVersion` on the exe
- `InstallScope` = `system_admin`

**ClickOnce installs** (detected via `.appref-ms` shortcuts under
`%AppData%\Microsoft\Windows\Start Menu\Programs\MacCoss Lab, UW\` or
`Programs\<AppName>\`):

- `GuiPath` = the `.appref-ms` (shell-execute it to launch)
- `CliPath` = `null` in this PR (see Settings Context caveat below)
- `Version` = parsed from deployment URL inside the `.appref-ms` if
  present; otherwise `"ClickOnce (auto-update)"`
- `InstallScope` = `user_clickonce`

If both a ClickOnce and an administrative install of the same release
are present, both entries are returned. The LLM picks which to use.

### Settings context caveat (documented in tool description)

`SkylineCmd.exe` (admin) and `Skyline.exe` (admin or ClickOnce) use
**separate `user.config` files**. Custom report definitions, default
settings presets, and similar UI-created configuration live in the GUI
Skyline's `user.config` and are not visible to `SkylineCmd.exe` until
the user runs `SkylineCmd --ui` once to populate that config.

`SkylineRunner.exe` / `SkylineDailyRunner.exe` (small shims) avoid the
caveat by proxying to the user's installed Skyline.exe in its own
settings context. Bundling those shims with the MCP server's
`SkylineAiConnector.zip` would let ClickOnce installs expose a working
`CliPath` — deferred to a follow-up PR. For now, `CliPath = null` for
ClickOnce and the LLM has to fall back to the GUI MCP tools (or ask
the user to install the admin variant) for batch-style CLI use of a
ClickOnce-only Skyline.

The tool description spells the caveat out so an LLM writing a batch
script for a user knows when to expect missing reports.

### ClickOnce version reporting

The `.appref-ms` file contains a deployment URL that usually carries
the version (e.g.
`.../skyline-23.1.0.380/Skyline.application`). Parse the version out
of the URL when present; otherwise label `"ClickOnce (auto-update)"`.
ClickOnce paths are user-readable text (with a UTF-16 BOM in some
cases) — read with `File.ReadAllText` and a `Encoding.Unicode` fallback.

### Decisions deferred to keep this PR small

- **No `[ACTIVE]` flag** mapping installs to running connected
  instances. There can be many running instances per install; a clean
  representation would need both a list of installs and a separate
  pointer to "current target." Leaving the correlation to the LLM
  (using `skyline_get_instances` alongside `skyline_list_installed`)
  avoids designing a structure we'd have to redo later.
- **No `skyline_start_instance`.** LLM launches via Bash using the
  returned `GuiPath`. Add a generalized launch+wait helper later if
  the pattern recurs.
- **No bundled SkylineRunner shims.** Future PR. Tracked here so the
  ClickOnce-CliPath gap doesn't get forgotten.

## Files Expected to Change

- `pwiz/pwiz_tools/Skyline/Executables/Tools/SkylineMcp/SkylineMcpServer/SkylineInstallation.cs` (new)
- `pwiz/pwiz_tools/Skyline/Executables/Tools/SkylineMcp/SkylineMcpServer/Tools/SkylineTools.cs` (one new tool)
- `pwiz/pwiz_tools/Skyline/Executables/Tools/SkylineMcp/SkylineAiConnector/SkylineAiConnector.zip` (regenerated)
- `pwiz/pwiz_tools/Skyline/TestFunctional/SkylineMcpTest.cs` (EXPECTED_TOOL_COUNT bump + coverage)

## Related

- Round-1 umbrella TODO: `ai/todos/completed/TODO-20260512_skyline_mcp_fixes.md`
- Followups backlog: `ai/todos/backlog/brendanx67/TODO-skyline_mcp_followups.md`
- Reference (not referenced as a project dep):
  `pwiz/pwiz_tools/Skyline/Executables/SharedBatch/SharedBatch/SkylineInstallations.cs`
