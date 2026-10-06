# TODO-20261005_McpForwardCompatibility.md

## Branch Information
- **Branch**: `Skyline/work/20261005_McpForwardCompatibility` (checkout `I:\git_i\sky_chatgpt`)
- **Base**: `Skyline/work/20261005_CodexMcp` (PR [#4772](https://github.com/ProteoWizard/pwiz/pull/4772)), itself on
  `Skyline/work/20260612_net8_port`
- **Created**: 2026-10-05
- **Status**: In progress (local commits only, nothing pushed)
- **Module**: `skyline`
- **PR**: (none yet)

## Objective

There is one Tool Store, so Skyline 26.2 release users and Skyline-daily users run the same AI Connector. A new
connector must be safe to publish even when it has tools the released Skyline does not support: the MCP server
should offer each user only what their running Skyline can do, and never send a call an older Skyline would
misread.

After 26.2 ships, existing `IJsonToolService` methods are frozen in behavior (external tools depend on them), so
the signatures in a Skyline's `SkylineTool.dll` fully describe what it supports. New behavior arrives as new
methods.

## Design
- **Read the running Skyline's interface, not a version number.** Release and daily diverge and cherry-picks
  cross between them, so version comparisons cannot say which methods exist. `JsonToolServer` builds its dispatch
  table from `typeof(IJsonToolService).GetMethods()`, so the interface in the running Skyline's `SkylineTool.dll`
  is exactly what it accepts, including parameter names, types and defaults. Same idea as
  `ToolServiceTestHarnessForm.btnUpdateMethods_Click`.
- **Use `System.Reflection.MetadataLoadContext`** to read the signatures without loading or running the other
  `SkylineTool.dll` (the server compiles in its own `IJsonToolService`; this avoids type-identity clashes).
- **Locate the DLL** through a new install-folder field Skyline writes into `connection-*.json`, falling back to
  `Process.MainModule` for older dailies (MainModule fails when Skyline runs elevated and the server does not).
- **Filter the tool list**: each MCP tool declares the Skyline methods it calls (attribute); after connecting or
  switching instances the server hides tools whose methods are missing and sends `notifications/tools/list_changed`
  (ModelContextProtocol 0.8.0-preview). With no Skyline connected, list everything. Clients that ignore list changes
  still get the existing "not available in <version>" error (-32601 path in `SkylineTools.Invoke`).
- **Enforce the declarations**: in test mode (`SKYLINE_MCP_TEST`), `SkylineConnection` fails any call to a method
  the calling tool did not declare; `TestSkylineMcp` exercises the tools.
- **Never send an argument the target signature lacks.** `JsonToolServer.Dispatch` checks too-few arguments but
  silently drops extra ones, so an older Skyline would ignore a newer optional parameter and return wrong results.
  With the signature known, the server omits (or refuses) such arguments. Also make `Dispatch` reject extra
  arguments with ERROR_INVALID_PARAMS, ideally before 26.2 branches.

## Tasks
- [x] Remove `QueryAvailableMethods` (Dispatch special case + `JsonToolServerTest` call): d4db7dfe98, superseded by
  reading the interface. Older dailies still answer it; nothing calls it.
- [ ] `Dispatch`: reject calls with more arguments than the method has
- [ ] Install folder in the connection file; server-side lookup with MainModule fallback
- [ ] MetadataLoadContext reader for `IJsonToolService` signatures
- [ ] Per-tool method declarations + test-mode enforcement
- [ ] Tool-list filtering and list_changed on connect/switch
- [ ] Argument trimming/refusal against the target signature
- [ ] Verify against a release-like and a daily-like Skyline (method sets differ)
