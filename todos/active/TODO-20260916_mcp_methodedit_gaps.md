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
- [x] **6. Hover tip and drag verbs** - `show_node_tip` action on the SequenceTree (simulated hover
      with IgnoreFocus, returns the tip text via `SequenceTree.NodeTipText`) and
      `skyline_reorder_elements` (the existing `ReorderElements` service, now an MCP tool) in place
      of a drag verb. No tests, at Nick's direction: verified by driving the tutorial live.
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
- Item 6 committed without tests (Nick: test by driving the tutorial). Work switched to the Release
  configuration: `Build-Skyline.ps1 -Configuration Release` and `dotnet build -c Release` for the
  MCP server both clean. Next: Nick rebuilds the connector and turns on auto-start of the tool
  service, then the MethodEdit tutorial is driven end-to-end through the MCP against
  `bin\x64\Release\Skyline-daily.exe`, which also settles item 3.
- Live driving of a Debug Skyline from this checkout is not yet possible: the JSON service only
  starts with the AI Connector tool installed (from the checkout's SkylineAiConnector.zip) or
  auto-connect on. Item 3's live reproduction is parked on that; a test-based reproduction is
  the fallback.

### 2026-09-16 - Live MethodEdit run (Release build, Nick's connector rebuild, auto-started service)

Driven end to end through the MCP from a blank document: `MethodEditTutorial.sky` with
36/71/71/355 and five `Yeast_list_000N.csv` (75+75+75+75+55 = 355 rows). Every document count
matched the tutorial at every checkpoint (35/25/25/75, 35/28/31/155, 35/182/219/1058, 19/47/47/223,
24/58/58/278, 25/70/70/338, 35/70/70/338, 64 peptides, 34/63/63/315, 36/70/70/350, 355). New verbs
that carried steps Brendan could not drive: window placement (main window 1049x518 centered, docked
pane widths 415/280), Home/Down/Up/Delete on the Targets tree, typing into the tree with the
completion popup (s-16/s-17/s-18), "Peptides"/"product ions" trailing labels, show_node_tip
(s-21/s-22 rendered), reorder_elements for the drag step, shared tutorial images.

Findings, fixed in the same session (uncommitted until built and tested):
1. **Ion Types submenu empty until an ion-type settings change (item 3 root cause).**
   `ViewMenu.ProteomicsEnabled` starts false and is only set by `EnableProteomicIons`, which
   `SkylineGraphs` calls only when the transition filter's ion types change. Before Transition
   Settings changed y -> y,b the walker saw `[]` under Ion Types and "B" was not found; after,
   `View > Libraries > Ion Types > B` worked. Charges never had the problem (fixed 1-4 panel).
   Fix: `ViewMenuDropDownOpening` derives both flags from the document.
2. **perform_action by label did not fall back to the internal Name** (get_value on `tbxStatus`
   failed): the path walk (`GetChild`) matched visible text only. Now it falls back to Name.
3. **Toolbar item "Find" only matched as "Find (Ctrl + F)"**: `TextMatches` now also compares
   with a trailing parenthesized hint stripped.
4. **show_node_tip threw "has no data tip" for custom-drawn tips** although the tip was shown
   (document node tips draw themselves; only text/table tips have text). Now it refuses only a
   node with no tip provider, returns the text or empty, and hiding takes no value or an empty one.
Design note for the PR: Name matching (item 5 and finding 2) is kept only because the issue asked
for it. Nick's preference is that verbs address controls by what the user can see (caption, label
beside the field, kind); the trailing-label rule alone drives the tutorial's count boxes. Do not
extend Name matching further.
Notes, not code: `get_document_status` can read stale counts right after a settings change
(background document update; re-read); Enter on the completion popup right after typing can commit
the raw text if the popup's first population has not focused a row yet (Down first, or re-read
the popup, makes it deterministic); protein order after typed additions can differ from the
tutorial (reorder_elements fixes it).

### 2026-09-16 - Second live run from `E:\Users\nicksh\git_e\sky_automation` (Release)

Drove the tutorial end to end again on the Release build at `3ab0f36039`, after the four fixes
above landed, to see what was still missing. Same result: 36/71/71/355 and five
`Yeast_list_000N.csv` totalling 355 rows, every document count matching the tutorial. Item 3
(Ion Types) confirmed fixed live - `View > Libraries > Ion Types > B` resolved before any
transition-settings change and rendered b-ions, so the `ViewMenuDropDownOpening` fix holds.
s-12 and s-16..s-22 all matched, so findings 1 and 7 of `TEST-MethodEdit.md` are closed.

Two further gaps found and fixed (commit `d5a2d8cbb5`), both on the Build Library input-file grid:

8. **A grid was not addressable by the Label `get_controls` reports for it.**
   `get_controls(BuildLibraryDlg:Build Library)` prints
   `BuildLibraryGridView  Input Files  True  gridInputFiles`, but `perform_action(label="Input
   Files", ...)` failed with "No control found matching the path" - `GridElement.MatchesText`
   matched only `Control.Name`, so the adjacent-label caption that `ControlElement.Label` derives
   ("&Input Files:" over the grid) was never a valid address. It now also matches the base Label,
   so whatever the enumeration prints resolves. This is the caption path, not Name matching - it
   does not extend the item-5 Name rule.
9. **`grid[column,row]` rejected a column header.** The tutorial step is "In the Score Threshold
   field, enter 0.95"; the locator's regex required `-?\d+` for the column, so the header name fell
   through to the control lookup and failed with the misleading "No control matching
   'dataGridViewRules[Pattern,0]' supports the action 'set_value'". The column token is now parsed
   as text and resolved by `GridElement.ColumnIndex`: all digits still mean the zero-based
   visible-column index, anything else matches a column header (exact preferred over
   symbol-insensitive), and a miss names the columns that exist. `skyline_set_form_value` and
   `IJsonToolService.SetFormValue` document it.

`GridCellMcpConnectorTest` covers both; each half was confirmed to fail without its own fix, with
exactly the two errors above. All 22 `*McpConnectorTest` tests and CodeInspection pass in Debug and
Release except `PickChildrenMcpConnectorTest`, which fails `GC-LEAK (SkylineWindow, SrmDocument)`
**identically on unmodified `3ab0f36039`** - pre-existing, worth its own investigation.

Still open after this run, none blocking: the Enter-vs-Down divergence on the completion popup
(already noted above - the tutorial's s-16 text says Enter alone, which commits the literal text);
`get_value` returns nothing for a TreeView or a ListBox despite its description; no verb resizes a
grid column (s-10's header-drag step, cosmetic); nothing on the tool surface reveals that `Space`
opens a pick-list (found only by reading `SequenceTree.OnKeyDown`, so the earlier run concluded
s-19/s-20 were unreachable) - worth a `show_pick_list` action or a mention in the tree's action
descriptions; and screen-capture consent still needs a one-time human grant.

Tutorial-text staleness worth its own issue: protein metadata is populated now (s-10, s-15, s-21)
where the text says those columns "will be empty"; the `Fasta.txt` paste raises an Empty Proteins
prompt the text never mentions (Keep is the answer that gives s-04's 35 proteins); and the
reference spreadsheet's SCIEX DP/CE (76.2/31) no longer match the current equations (80/29.3),
though every m/z does.

Walkthrough: `pwiz_tools/Skyline/Documentation/WalkThroughs/MethodEdit/` (commit `ca7e81c29f`) -
every tutorial step paired with the MCP call that performed it and a screenshot, 32 captures.
Note for anyone repeating this: screen capture redacts to solid cyan wherever another window
overlaps Skyline, so the first pass was unusable (the session terminal sat over the window) and
had to be redone raising Skyline before each capture - except for a pick-list, which raising the
main window dismisses, so Skyline must be raised *before* `Space`.
