# AI Connector: gaps for completing the Method Editing tutorial through the MCP (round 2)

## Branch Information
- **Branch**: `Skyline/work/20260916_mcp_methodedit_gaps`
- **Checkout**: `I:\git_i\sky_tutorial`
- **Base**: `master`
- **Created**: 2026-09-16
- **Status**: In Progress
- **GitHub Issue**: [#4671](https://github.com/ProteoWizard/pwiz/issues/4671)
- **Module**: `skyline`
- **PR**: (pending)

## Objective

Round 2 of driving the Targeted Method Editing tutorial (`MethodEdit`) through the Skyline MCP
completed end-to-end, with 21 of 28 screenshots matching. The seven gaps below are what stands
between that and a run where a person following along sees the tutorial's screenshots. Full log
with every call: `todos/active/TODO-20260915_mcp_tutorial_testing/TEST-MethodEdit.md`. Round 1
was #4449, closed by PR #4452.

## Tasks

Ordered by the issue's value-for-effort.

- [x] **1. Window placement verb** - `SetWindowPlacement(formId, WindowPlacement)`, one verb for
      every window: the main window (formId null), a dockable form, a plain dialog, a native dialog.
      `WindowPlacement` is request and reply: Bounds (outer, screen px), WindowState, DockState,
      RelativeTo + Alignment (Left/Right/Top/Bottom/tab) + Proportion, Placement (maximize/center),
      Screen (reply). Empty request reads without un-maximizing; "maximize" fills the screen without
      `FormWindowState.Maximized`. Implemented per kind: `StandaloneForm.SetPlacementNow` (bounds,
      state, placement), `DockableStandaloneForm` (Show/FloatAt/portions), `NativeDialog`
      (SetWindowPos). Started as a main-window-only `set_window_bounds` (rebuilt from the lost
      2026-08-21 branch, `TODO-20260821_mcp_set_window_bounds.md`) and generalized at Nick's
      direction before commit; MCP tool `skyline_set_window_placement` merges partial edges by
      reading first.
- [x] **2. Targets tree auto-completion** - (a) `begin_edit` action on `SequenceTree` that calls
      `BeginEdit(false)` and exposes the edit box as a TextBox element so `send_text`/`set_value`
      raise `TextChanged` and the `StatementCompletionForm` shows; (b) `send_text` on the tree
      routes through that path or refuses; (c) `SequenceTree.BeginEditNode` commits/removes an
      existing `_editTextBox` before creating another.
- [ ] **3. `View > Libraries > Ion Types > B`** - `IonTypeMenuMcpConnectorTest` (#4313) already
      clicks the hosted "B" through `ClickMainMenuItem` and passes nightly, yet Brendan's run got
      "Menu item not found" and an empty `get_children`. Reproduce live against a debug Skyline
      before changing the walker; the same shape applies to `Charges`.
- [x] **4. `send_key_stroke` on the Targets tree** - fall back to the form's
      `ProcessCmdKey`/`ProcessDialogKey` when the control did not handle the key, so `Delete`
      (Edit > Delete shortcut) and arrow navigation work.
- [x] **5. Caption-less controls** - `set_form_value` accepts the internal Name that
      `get_controls` prints, and picks up a trailing label ("3 Peptides") as the caption.
- [ ] **6. Hover tip and drag verbs** - `show_node_tip(nodeText)` and `move_node(locator,
      beforeLocator)`; lowest priority, look-only steps.
- [x] **7. `get_tutorial_image` shared images** - resolve the `src` path from the tutorial HTML
      (or fall back to `shared/<lang>/` and `shared/`) so `../../shared/en/...` images fetch.

## Regression Tests

Each verb gets its own `McpConnectorTest` subclass in TestFunctional, the pattern
`IonTypeMenuMcpConnectorTest` set:

- **1**: `WindowBoundsMcpConnectorTest` (rebuilt; asserts the un-maximize guard both ways)
- **2**: tree begin-edit + completion popup test
- **3**: (existing) `IonTypeMenuMcpConnectorTest`; extend with `Charges` if the walker changes
- **4**: key-stroke fallback test (Delete removes the selected node)
- **5**: `set_form_value` by Name on `textPeptideCount`
- **7**: `get_tutorial_image` for a `shared/` image
- **Fails on master / passes on fix**: recorded per item in the Progress Log

## Key Files

- `pwiz_tools/Skyline/SkylineTool/IJsonToolService.cs`, `JsonToolModels.cs`,
  `SkylineJsonToolClient.cs`
- `pwiz_tools/Skyline/ToolsUI/UiElement.cs`, `JsonToolServer.cs`
- `pwiz_tools/Skyline/Executables/Tools/SkylineMcp/SkylineMcpServer/SkylineConnection.cs`,
  `Tools/SkylineTools.cs`
- `pwiz_tools/Skyline/Controls/SequenceTree.cs` (item 2c)
- `pwiz_tools/Skyline/Menus/ViewMenu.cs` (`UpdateIonTypeMenu`, item 3)

## Progress Log

### 2026-09-16 - Session start

- Identified #4671 as the issue; confirmed nothing for it has landed on master and no branch
  exists. The 2026-08-21 window-bounds branch is on no remote or local checkout (its checkout
  `sky_exportlayout` was deleted before a push); only its TODO survives.
- Found that item 3 contradicts a passing master test; scheduled a live reproduction first.
- Branch created; starting with item 1.
- Item 1 built as `set_window_bounds` (main window only), passed its test, then generalized to
  `SetWindowPlacement` at Nick's direction before committing. `WindowPlacementMcpConnectorTest`
  passes (main window + Document Grid floating/docked/split/tabbed), as do CodeInspection,
  TestGetControlsMcpConnector, TestNativeFileDialog, TestIonTypeMenuMcpConnector and
  TestPrmMcpConnector. The net8 SkylineMcpServer builds with 0 warnings. Committed locally.
- Items 7, 5, 2 and 4 committed locally, one commit each (7 and 5 separately, 2 and 4 together
  since they share TreeEditMcpConnectorTest). Verified: JsonTutorialCatalogTest (offline),
  SetFormValueMcpConnectorTest (Name + trailing label on the Library tab), TreeEditMcpConnectorTest
  (Down, Delete via Edit > Delete through Control.PreProcessMessage, begin_edit, typing into the
  tree, Enter, Esc, refusal on a peptide), plus TestJsonToolServer, TestGetControlsMcpConnector,
  TestPerformActionMcpConnector, TestPickChildrenMcpConnector, TestGridCellMcpConnector,
  TestClickControlMcpConnector and CodeInspection. The completion popup itself needs a background
  proteome, so the test pins the edit-box mechanics, not the suggestion list.
- Item 6 (hover tip, drag) not started. Item 3 still needs its live reproduction (see below).
- Live driving of a Debug Skyline from this checkout is not yet possible: the JSON service only
  starts with the AI Connector tool installed (from the checkout's SkylineAiConnector.zip) or
  auto-connect on. Item 3's live reproduction is parked on that; a test-based reproduction is
  the fallback.
