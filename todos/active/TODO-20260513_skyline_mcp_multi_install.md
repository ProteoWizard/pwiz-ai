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
      `GuiPath`, `CliPath`, `RunnerPath`.
- [ ] Bundle `SkylineRunner.exe` + `SkylineDailyRunner.exe` (13.8 KB
      each, the same pre-built shims AutoQC and SkylineBatch ship) as
      `Content` files in `SkylineMcpServer.csproj` with
      `CopyToOutputDirectory=Always`. They flow into the
      `mcp-server/` folder of `SkylineAiConnector.zip` via the
      existing `PackageToolZip` target — no zip-packaging changes
      needed. MCP discovery code resolves their path via
      `AppContext.BaseDirectory`.
- [ ] New `skyline_list_installed` MCP tool in
      `SkylineMcpServer/Tools/SkylineTools.cs` — tab-separated output
      with all POCO columns. Description explains the CliPath vs
      RunnerPath choice and the `SkylineCmd --ui` escape hatch.
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

| Field | Admin install | ClickOnce install |
|---|---|---|
| `GuiPath` | `…\Skyline[-daily]\Skyline[-daily].exe` | `…\Skyline[-daily].appref-ms` |
| `CliPath` | `…\Skyline[-daily]\SkylineCmd.exe` | `null` |
| `RunnerPath` | `null` | bundled `…\mcp-server\Skyline[Daily]Runner.exe` |
| `Version` | `FileVersionInfo.ProductVersion` on the exe | parsed from `.appref-ms` deployment URL, else `"ClickOnce (auto-update)"` |
| `InstallScope` | `system_admin` | `user_clickonce` |

If both a ClickOnce and an administrative install of the same release
are present, both entries are returned. The LLM picks which to use.

### CliPath vs RunnerPath — when to use each (documented in tool description)

Every install has at least one CLI path; admin installs use
`SkylineCmd.exe`, ClickOnce installs use the bundled runner shim.

- **`CliPath` (admin installs only).** `SkylineCmd.exe` lives in the
  same folder as `Skyline.exe` and is the modern direct CLI entry
  point. Caveat: it uses a **separate `user.config`** from the GUI
  Skyline. Custom reports, default settings presets, and similar
  UI-saved state are not visible to `SkylineCmd.exe` until that
  config is populated. The LLM-friendly way to populate it: add the
  reports / tools / settings the script needs as CLI arguments and
  include `--save-settings`, which persists the in-memory
  `Settings.Default` at the end of the run so subsequent runs see the
  same state. (`SkylineCmd --ui` is the human escape hatch — opens a
  GUI the user can configure and close, persisting whatever they
  set.)
- **`RunnerPath` (ClickOnce installs only).** The bundled
  `SkylineRunner.exe` / `SkylineDailyRunner.exe` shims (13.8 KB each)
  find the user's ClickOnce-deployed `Skyline.exe`, launch it in
  headless CMD mode, and pipe stdout/stderr through. Because they go
  through the user's GUI Skyline binary, they share the GUI's
  `user.config` — custom reports etc. are visible. Note: the shims
  only know how to find ClickOnce installs; for admin installs the
  user should use `CliPath` (`SkylineCmd.exe`) directly.

The tool description spells this out so an LLM writing a batch script
picks the right path and explains the tradeoffs to its user.

### Runner-shim bundling

The 13.8 KB pre-built `SkylineRunner.exe` and `SkylineDailyRunner.exe`
binaries are already checked into the repo (last updated 2024-10-01)
and shipped with AutoQC and SkylineBatch via `Content Include`. This
PR copies them into `SkylineMcpServer/` and references them the same
way, so they land in `bin/<config>/net8.0-windows/win-x64/` alongside
`SkylineMcpServer.exe`. The existing `PackageToolZip` target in
`SkylineAiConnector.csproj` already globs `*.exe` from that bin dir
into `mcp-server/` of the zip, so no zip-packaging changes are needed.
At runtime, `SkylineInstallation.FindAll()` resolves the shim path via
`AppContext.BaseDirectory`.

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
- **No MCP-internal headless-CLI tool.** Considered absorbing
  SkylineRunner's pipe protocol into the MCP server itself, but the
  more useful pattern is having the LLM write user-runnable scripts
  (cron, CI, other machines) that reference real EXE paths. The
  bundled runner shims serve that use case directly.

## Files Expected to Change

- `pwiz/pwiz_tools/Skyline/Executables/Tools/SkylineMcp/SkylineMcpServer/SkylineInstallation.cs` (new)
- `pwiz/pwiz_tools/Skyline/Executables/Tools/SkylineMcp/SkylineMcpServer/SkylineMcpServer.csproj` (Content Include for both shims)
- `pwiz/pwiz_tools/Skyline/Executables/Tools/SkylineMcp/SkylineMcpServer/SkylineRunner.exe` (added, pre-built shim from AutoQC)
- `pwiz/pwiz_tools/Skyline/Executables/Tools/SkylineMcp/SkylineMcpServer/SkylineDailyRunner.exe` (added, pre-built shim from AutoQC)
- `pwiz/pwiz_tools/Skyline/Executables/Tools/SkylineMcp/SkylineMcpServer/Tools/SkylineTools.cs` (one new tool)
- `pwiz/pwiz_tools/Skyline/Executables/Tools/SkylineMcp/SkylineAiConnector/SkylineAiConnector.zip` (regenerated)
- `pwiz/pwiz_tools/Skyline/TestFunctional/SkylineMcpTest.cs` (EXPECTED_TOOL_COUNT bump + coverage)

## Related

- Round-1 umbrella TODO: `ai/todos/completed/TODO-20260512_skyline_mcp_fixes.md`
- Followups backlog: `ai/todos/backlog/brendanx67/TODO-skyline_mcp_followups.md`
- Reference (not referenced as a project dep):
  `pwiz/pwiz_tools/Skyline/Executables/SharedBatch/SharedBatch/SkylineInstallations.cs`
