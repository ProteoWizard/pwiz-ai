# TODO-20260821_mcp_set_window_bounds.md - MCP verb: set the Skyline window bounds

## Branch Information
- **Branch**: `Skyline/work/20260821_mcp_set_window_bounds`
- **Checkout**: `I:\git_i\sky_exportlayout`
- **Module**: `skyline`
- **Base**: `master`
- **Created**: 2026-08-21
- **Status**: Superseded - branch never pushed and its checkout deleted; rebuilt under TODO-20260916_mcp_methodedit_gaps.md (#4671)
- **GitHub Issue**: (none)
- **PR**: (not yet opened)

## Objective

One MCP verb, `skyline_set_window_bounds`, that moves and resizes the main Skyline window and
reports where it ended up.

## Why this exists

Phase 2 of `ai/todos/backlog/TODO-20260803_layout_export_import.md` - MCP screenshot-layout
reproduction. Two things the connector could not do:

- **Give a screenshot a known, reproducible window size.** Tutorial tests have
  `SetSkylineWindowSize` / `MaximizeSkylineWindow`; an MCP client driving a live Skyline had no
  equivalent, so a captured image was whatever size the window happened to be.
- **Move Skyline out from under an overlapping window** - the cyan-overlap capture failure.

The other Phase 2 items (the `pNN.view` -> `s-NN.view` rename, fetching view files from GitHub)
are untouched by this branch. `skyline_load_view_layout` stays dropped: File > Import > Window
Layout (PR #4575) is drivable through `skyline_click_main_menu_item` plus the native file
dialog automation.

## What is here

### The verb

`SetWindowBounds(left, top, width, height, placement)`, all optional. The chain is the usual
one, no new plumbing:

| Layer | File |
|-------|------|
| Contract | `SkylineTool/IJsonToolService.cs` |
| Model (`WindowBounds`, reusing the existing `Rectangle`) | `SkylineTool/JsonToolModels.cs` |
| Client proxy | `SkylineTool/SkylineJsonToolClient.cs` |
| Implementation | `ToolsUI/UiElement.cs` (`SkylineStandaloneForm`) |
| Server dispatch | `ToolsUI/JsonToolServer.cs` |
| MCP wrapper + tool | `SkylineMcp/SkylineMcpServer/{SkylineConnection.cs,Tools/SkylineTools.cs}` |

The implementation sits on `SkylineStandaloneForm` next to `SetUndoRedoPosition`, which is the
established place for a verb's main-window work; `JsonToolServer` just calls it through
`CallOnMainWindow`.

The rectangles are the tool service's existing `Rectangle` (`Left`/`Top`/`Right`/`Bottom`,
doubles), which `GetGraphZoom` / `ZoomGraphTo` / `ClickGraph` already use. A first pass added a
`ScreenRectangle` of its own with a width and a height - it was written against a stale
`origin/master` that did not have `Rectangle` yet. Two things to know about the reuse:

- The doubles hold whole screen pixels fine, but callers convert: a window is naturally a
  position and a size, and `Rectangle` gives edges. The MCP message and the test both have small
  `Width`/`Height` helpers for that.
- `Rectangle`'s doc describes GRAPH axes, where `Top` is the *larger* Y. In screen pixels it is
  the smaller one. `WindowBounds` says so, since the same type now means both.

### Three decisions worth keeping

**1. Raw outer bounds, not the tutorial capture-size convention.** `SetSkylineWindowSize(w, h)`
does *not* set `Bounds` to w x h - it adds a 14x7 margin and centers, so the captured *image*
comes out w x h. That convention was deliberately NOT built into the verb, at the developer's
choice: the verb sets `SkylineWindow.Bounds` exactly as asked, and a caller reproducing a
tutorial capture size does its own arithmetic. The doc comment says the bounds are the outer
ones, including the border, so this is not a trap.

**2. "maximize" fills the screen WITHOUT `FormWindowState.Maximized`.** A genuinely maximized
window refuses every later resize, so a caller could set a screenshot size once and then
silently get the same image forever. Same reason `MaximizeSkylineWindow` avoids the state.

Measured while checking the test's teeth: a genuinely maximized window's `Bounds` overhangs its
screen by the invisible border (`Expected:<0>. Actual:<-8>. left`), so `Bounds == screen bounds`
is itself evidence the state was avoided. The state assertion is checked *first* anyway, so a
regression reports what went wrong rather than an off-by-eight.

**3. No arguments at all is a read, not a write.** The distinction is real rather than
cosmetic: any call that changes bounds first restores the window to `Normal` (a maximized or
minimized window keeps the bounds it is given but does not show them, so the caller would be
told a size the window is not at). Without the guard, *asking where the window is* would
un-maximize it. `TestRestoresFromMaximizedState` pins both halves.

## Task Checklist

### Completed
- [x] `WindowBounds` / `ScreenRectangle` models, interface member, client proxy
- [x] `SkylineStandaloneForm.SetWindowBounds` + `JsonToolServer` dispatch
- [x] `SkylineConnection` delegation and the `skyline_set_window_bounds` MCP tool
- [x] `WindowBoundsMcpConnectorTest` - its own class deriving `McpConnectorTest`, at the
      developer's direction: it shares no test code with `JsonToolServerTest`, and that file is
      being split on `Skyline/work/20260821_jsontoolserver_test_split` right now
- [x] Teeth verified by removing each fix in turn:
      - guard removed -> `Expected:<Maximized>. Actual:<Normal>. Reading the bounds un-maximized the window.`
      - un-maximize removed -> `Expected:<Normal>. Actual:<Maximized>.`
      - "maximize" using the maximized state -> fails (and prompted reordering the asserts)
- [x] Build clean; `TestWindowBoundsMcpConnector` (x3), `CodeInspection`, `TestJsonToolServer`,
      `TestPrmMcpConnector`, `TestGetControlsMcpConnector`, `TestNativeFileDialog` all pass

### Remaining
- [ ] Drive the verb over the MCP against a running Skyline - nothing here has exercised the
      real MCP tool, only the `IJsonToolService` beneath it
- [ ] `/code-review max`
- [ ] Push branch and open PR
- [ ] Decide whether a matching `skyline_get_window_bounds` is worth having. Deliberately not
      added: a no-argument call already reads the bounds and reports the screen, so a second
      verb would be a second name for it.

## Key Files

- `pwiz_tools/Skyline/SkylineTool/IJsonToolService.cs`, `JsonToolModels.cs`,
  `SkylineJsonToolClient.cs`
- `pwiz_tools/Skyline/ToolsUI/UiElement.cs`, `JsonToolServer.cs`
- `pwiz_tools/Skyline/Executables/Tools/SkylineMcp/SkylineMcpServer/SkylineConnection.cs`,
  `Tools/SkylineTools.cs`
- `pwiz_tools/Skyline/TestFunctional/WindowBoundsMcpConnectorTest.cs`

## Notes for whoever builds this

`dotnet build SkylineMcp.sln` fails on `SkylineTool.csproj` with
`'Json' does not exist in the namespace 'System.Text'` - that is the net472 project being built
without its packages.config restore, and it reproduces on a clean checkout with no changes
stashed in. `SkylineMcpServer` itself builds, and `Build-Skyline.ps1` builds `SkylineTool.dll`
fine. Not a symptom of anything in this branch.

## Progress Log

### 2026-08-21 - Session 1
- Started while reviewing what was left over from PR #4575's original scope. Four unchecked
  review findings on `TODO-20260813_export_import_layout.md` were dropped at the developer's
  direction (including one claiming the test should call `TestContext.EnsureTestResultsDir()`,
  which is wrong - 11 call sites in the whole tree, and `AbstractFunctionalTest` handles it).
- Implemented the verb, built, tested, verified the teeth of each assertion.
- Started on the #4575 branch, then moved to a branch of its own at the developer's direction
  (stash / branch / pop; no conflicts - #4575 touches none of these files except
  `TestFunctional.csproj`, in a different region).
- **That branch was cut from a stale `origin/master`** - the remote-tracking ref had never been
  fetched this session, so it was 12 commits behind. Fetched and rebased at the developer's
  direction. The stale base is also why the first pass invented `ScreenRectangle`: the
  `Rectangle` it should have reused arrived in master with the graph click/zoom verbs (#4452),
  which the old base predates. **Fetch before branching, not after.**

## References

- Phase 2 source: `ai/todos/backlog/TODO-20260803_layout_export_import.md`
- The menu items that made `skyline_load_view_layout` unnecessary: PR #4575,
  `ai/todos/active/TODO-20260813_export_import_layout.md`
