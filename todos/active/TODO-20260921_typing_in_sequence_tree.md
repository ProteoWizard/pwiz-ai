# AI Connector: typing in the Targets tree and choosing from the completion pop-up

## Branch Information
- **Branch**: `Skyline/work/20260921_typing_in_sequence_tree`
- **Checkout**: `I:\git_i\sky_typinginsequencetree`
- **Base**: `master`
- **Created**: 2026-09-21
- **Status**: In Progress
- **GitHub Issue**: [#4671](https://github.com/ProteoWizard/pwiz/issues/4671) (item 2 only)
- **Module**: `skyline`
- **PR**: (pending)

## Objective

A clean restart of #4671, scoped to item 2: typing into the Targets tree through the connector brings up
the `StatementCompletionForm`, and an item in it can be chosen. The earlier attempt
(`TODO-20260916_mcp_methodedit_gaps.md`, branch `Skyline/work/20260916_mcp_methodedit_gaps` in
`sky_tutorial`) covered all seven items of the issue and is abandoned; nothing is carried over from it.

## Root cause

`SequenceTree.OnKeyPress` began an edit for every character it received and passed the character on with
`SendKeys.Send`, which types into whichever window is in front. A user's first key starts the edit and the
rest go to the focused edit box, so it works for a user. The connector sends every WM_CHAR to the tree's
own window, so each character began another edit (one orphaned TextBox each) and the characters went to
the foreground application, in the wrong order.

## Design

Fix the tree, so the connector needs no typing verb of its own:

- `SequenceTree.OnKeyPress` starts an edit only when none is under way, and hands the character to the
  edit box with WM_CHAR instead of `SendKeys`. That also drops the CapsLock and SendKeys-escaping
  workarounds. `send_text` on the tree then works through the generic `ControlElement.SendTextNow`.
- `SequenceTreeElement.SendKeyStrokeNow` presses the key on the edit box while a label is being edited
  (Down/Up move through the pop-up, Enter accepts, Esc cancels), as the focus would route it for a user.
- `StatementCompletionListElement` for the pop-up's ListView: `get_options` lists the choices (name and
  description), `select_item` / `set_selected_index` raise the mouse-down a user's click makes, which
  accepts the item. The pop-up is an ordinary entry in `get_open_forms`.
- The `send_text` descriptions (UiActions, IJsonToolService, SkylineTools) no longer warn callers off the
  tree.

## Tasks

- [x] Tree fix, key strokes while editing, completion list element, descriptions
- [ ] Settle the API shape with Nick (build only until then; no commits, no tests)
- [x] Readiness: decided 2026-09-24 - the caller polls `get_open_forms` for the pop-up; `send_text` does not
      wait for it (see Progress Log).
- [ ] No functional test, at Nick's direction: the test is driving the MethodEdit tutorial through the MCP
      against a build of this branch (s-16/s-17: select the blank node, `send_text` "ybl087", pop-up
      listed, choose `YBL087C`; then the peptide `IQGPNYVPGK`).
- [x] `rename_node` removed (2026-09-24, Nick): it set a name without the pop-up a user sees
- [x] `MethodEditTutorialTest` scaffolding removed (file restored to master's)
- [ ] Re-record nothing expected (no new menu item, CLI arg or report column)
- [ ] `/code-review max`, then PR with `Fixes` left off (the issue has six other items)

## Progress Log

### 2026-09-21 - Session start

- Branch created from a freshly fetched `origin/master`. First cut of the four pieces above written;
  building.

### 2026-09-21 - Live run through the MCP against the paused tutorial test

`MethodEditTutorialTest` now starts the tool service, writes the connection file
(`Program.StartToolService()` alone does not, so the MCP server cannot find the instance) and has a
`PauseTest` just before the first auto-complete with the blank node selected. Run with
`Run-Tests.ps1 -TestName TestMethodEditTutorial -ShowUI`. These test edits are scaffolding, not for the PR.

Driven with the real MCP tools, Skyline not the foreground window:
- `skyline_send_text` "ybl087" on `SequenceTree`: one edit box, text in order, pop-up listed;
  `get_options` on its ListView gave the one match; `select_item` "YBL087C" added the protein, closed the
  pop-up, left no edit box and the selection on `/Insert`.
- "eft2", then `send_key_stroke` Down and Enter on the tree: `YDR385W` added.
- "IQGP", `select_item` "IQGPNYVPGK": peptide added. Document 36/70/70/350, the tutorial's counts.
- "ybl0", Esc, Esc: first closes the pop-up, second cancels the edit; document unchanged.

### 2026-09-21 - Node tips: `hover_item`

Scope widened at Nick's direction to bringing up the Targets tree's node tips (issue item 6, first half).
`hover_item` takes no value: it rests the mouse on the SELECTED node (Nick: sufficient for every tutorial
scenario). `SequenceTreeElement.HoverItemNow` sets `SequenceTree.IgnoreFocus` (as
`MethodEditTutorialTest.ShowNodeTip` does), calls `MoveMouse` at the node's centre, and ends the hover
- `IgnoreFocus` off, mouse off every node - when the selection changes or the real mouse moves over the
tree. Verified live against the test paused before its first `ShowNodeTip`, with
`Settings.Default.AllowMcpScreenCapture = true` added to the test scaffolding: the tip came up for
`YBL087C` and for the `672.6716+++` precursor, and changing the selection took it down.

The tip is a `CustomTip : NativeWindow`, neither a form nor a "#32770", so `get_open_forms` dropped it and
`get_form_image` of the main window clipped it at the window edge. New `ToolsUI/TipWindow.cs`
(`TipWindow : StandaloneWindow`), recognised in `StandaloneWindow.GetTopLevelWindows` /
`NewStandaloneWindow` by `NativeWindow.FromHandle(hwnd) is CustomTip` while the window is visible. Id
`NodeTip:` (type name, no title), not modal, no controls, dismiss and set_value refuse, image captured by
handle, Message is `NodeTip.TipText` / `TipTable` when the tip has one (document node tips draw
themselves and have none). Verified live: listed about half a second after `hover_item`, gone from the
list after a selection change, `get_form_image("NodeTip:")` returned the whole protein tip and the whole
precursor tip (the s-21 / s-22 content). Any `CustomTip` is listed, so graph tips come along too.

Later the same day, at Nick's direction: the action is `show_tooltip` (`UiActions.ShowTooltip`,
`ITooltipElement.ShowTooltipNow`), not `hover_item`; and `StandaloneWindow.NewStandaloneWindow` asks in
turn `Control.FromHandle` (a Form, else null for a child control), then `NativeWindow.FromHandle` (a
`CustomTip`, else null for any other managed helper window), then `NativeDialog.Create`, as `if`
statements. `GetTopLevelWindows` now filters on `IsWindowVisible` and calls it, so the classification
exists once. `NativeWindow.FromHandle` is a lookup in WinForms' handle table: it creates nothing, returns
null for a fully native window (so it is no help with the Open/Save dialogs), and leaks nothing.
Re-verified live: `show_tooltip`, then `NodeTip:` listed beside the managed forms.

### 2026-09-21 - `show_tooltip` made generic

Every `NodeTip` owner that has items (Targets tree, Files tree, `PopupPickList`, `ViewLibraryDlg` peptide
list, `ImportTransitionListColumnSelectDlg` grid) drives its tip from the control's mouse-move, so the
gesture moved to `ControlElement.ShowTooltipAt(itemBounds)`: raise `OnMouseMove` off the control, then at
the item's centre. `ITooltipElement` is implemented by `TreeViewElement` (selected node),
`ListControlElement` (a ListBox's selected item) and `GridElement` (current cell); each takes the tip
down (`HideTooltip`) on its own selection-changed event. `SequenceTreeElement` has no tip code left.

- Tried giving the control the real focus in place of `IgnoreFocus`: the tip did NOT come up with Skyline
  in the background, so the gate has to be bypassed. New `IFocusTipDisplayer : ITipDisplayer`
  (`IgnoreFocus`) in NodeTip.cs, implemented by `SequenceTree`, `FilesTreeForm` (both had the property)
  and `PopupPickList` (added; `AllowDisplayTip` honours it). The connector finds it on the control or its
  form, sets it, and clears it on the first real mouse move or on `HideTooltip`.
- Bug found live: `JsonUiService.CaptureNativeWindow` calls `SetForegroundWindow`, and activating a tip
  deactivates its owner, which hid the pick list's tip and closed the pick list. `TipWindow.CaptureImage`
  now uses the new `CaptureWindowRect` (screen copy only; a tip is topmost already).
- Verified live: Targets tree tip through the generic path; pick-list item tip shown, listed, and captured
  whole by `NodeTip:` with the pick list still open afterwards.
- Not tried: Files tree, library explorer list, import-columns grid. Not covered: graph tips (no selected
  item; would need a data point) and standard WinForms `ToolTip`s (shown by the native tooltip control from
  real mouse messages, not from `OnMouseMove`). Two tips open at once share the id `NodeTip:`; the topmost
  wins.

### 2026-09-21 - `IgnoreFocus` removed: the control really gets the focus (Nick's direction)

`IFocusTipDisplayer` and `PopupPickList.IgnoreFocus` are gone again; the Skyline-side classes are back to
`ITipDisplayer`. `ControlElement.ShowTooltipAt` now calls `ScreenCapture.ActivateForm(Control)` (which is
`SetForegroundWindow` + `Form.Activate`), then `Control.Focus()`, and throws an instruction to have the
user click on Skyline if `Control.Focused` is still false (Windows can refuse a foreground change). The
earlier failed attempt had called `Focus()` alone, without activating: that is what does nothing while
Skyline is in the background. No real-mouse handler is needed any more; the tip comes down as it does for
a user, plus on the element's selection change.

Verified live, Skyline not in front beforehand: Targets tree tip shown and captured whole; then the pick
list's item tip shown and captured, pick list still open. With real focus the tree's tip came down by
itself when the pick list took the focus, so only one `NodeTip:` was listed (the two-tips id clash did not
arise). Uncommitted at the time of writing (commit `01fd42e86` still has `IFocusTipDisplayer`).

Nick also raised making Skyline less focus-dependent for accessibility (a keyboard path to the tip); proposed
as separate work.

Readiness gap seen live (completion pop-up): `get_open_forms` issued together with `send_text` did not list the pop-up yet;
the next read did. Still the open question above.

### 2026-09-24 - Readiness decided: the caller polls

Master merged (already up to date). Nick's decision on the completion pop-up: `send_text` returns once the
characters are typed and does NOT wait for the background query; the caller polls `get_open_forms` until the
pop-up is listed. Reason: while a tutorial step depends on a person watching for a pop-up, keeping the focus
where it belongs and coping with a busy machine, the model should have to take the same care. The fix belongs
in Skyline - an accessible way to do the step, which the tutorial then describes - not in a connector wait.
The considered alternative (a `waitCondition` through `DialogWatcher.PerformActionAndWait`, with a pending
query counted as progress by the watchdog) is not to be built. `IJsonToolService.SendText` now says, as
the MCP description already did, that the pop-up opens a moment after the call returns.

### 2026-09-24 - `rename_node` and the test scaffolding removed

At Nick's direction: the `rename_node` action (on master since before this branch) is gone -
`IRenameNodeElement`, `SequenceTreeElement.RenameNodeNow`, `UiActions.RenameNode` and its mentions in
the MCP `perform_action` descriptions. Nothing else used it. `MethodEditTutorialTest.cs` is back to
master's copy (tool-service start, `WriteConnectionInfo`, `AllowMcpScreenCapture`, `PauseTest`).
Release build of Skyline and of the MCP server both clean. Uncommitted.

### 2026-09-24 - MethodEdit walkthrough; arrow keys; `ResizeWindow`

- Drove the whole MethodEdit tutorial through the MCP against the Release build and committed the result
  (`48b6c43084`): `pwiz_tools/Skyline/Documentation/McpTutorialSteps/MethodEdit/MethodEdit-mcp-steps.md`
  plus 34 captures. Final document 36/71/71/355, five CSVs, 355 rows. Its opening table lists every step that
  did not work on this branch and what stood in for it.
- Arrow keys on the Targets tree (Nick): `SequenceTreeElement.SendKeyStrokeNow`, when no label is being
  edited, sends an unmodified Up/Down/Left/Right to the tree as `WM_KEYDOWN`, so WinForms raises KeyDown and
  the native tree then moves the selection / collapses / expands. Verified live: Down protein -> peptide,
  Right + Down -> precursor, Left collapses, Up back. One Up gave a two-node selection once and did not
  reproduce: `TreeViewMS` reads the live `ModifierKeys`, so a real Shift/Ctrl held at that moment makes it a
  range/disjoint select, as it would for a user. Delete and Home still go through KeyDown only.
- `TestMethodEditTutorial` both sizes windows (`SkylineWindow.Size = 1035x511`, Insert Peptides
  `Height = 437`, Unique Peptides `Height = 292`) and loads `.view` files (`MethodEditViews.data/p07.view`,
  `p21.view`: dock portions and tree expansion). At Nick's direction: a size verb for the first, File >
  Import > Window Layout for the second.
- New `IJsonToolService.ResizeWindow(formId, width, height) -> WindowSize` (size only, Nick's choice over
  bounds; named for the gesture, not `SetWindowSize`, since a min/max size can win), MCP
  `skyline_resize_window`. `StandaloneForm` restores a maximized/minimized form, sets the
  outer size, reports what it got; refuses a `DockableFormEx` (points to Window Layout) and a fixed-border
  form; `StandaloneWindow` base refuses (native dialogs, tips). Release Skyline and MCP server build clean.
  Not yet driven: the MCP tool needs the connector rebuilt. Build only, not committed (API iteration).
- Moved the key routing into Skyline at Nick's direction: public `SequenceTree.PressKey(Keys)` sends the key
  where a user's would go (edit box while a label is being edited, via a private `LabelTextBox : TextBox` that
  raises its own KeyDown; an unmodified arrow as `WM_KEYDOWN` to the tree; anything else the tree's
  `OnKeyDown`). `SequenceTreeElement.SendKeyStrokeNow` is now one line calling it; the reflection and the
  `User32` call left UiElement.cs. Rebuilt and re-verified live: Down/Right/Down/Up on the tree; with the
  completion pop-up up, Down stayed in the pop-up (selection still `/Insert`), Esc closed it, Esc cancelled the
  edit, document unchanged. One earlier try committed `ybl0`: that capture came back all cyan (another window
  was in front), and a label edit commits when Skyline loses the focus, as for a user.
- `skyline_resize_window` driven live after Nick's connector rebuild: main window 1035x511 (capture came back
  1021x504, the size less the invisible border); Insert dialog 812x437; 50x50 on it gave 136x50 (Windows'
  minimum title-bar width, reported as such); `SequenceTreeForm:Targets` refused with the Window Layout
  pointer; Peptide Settings refused as fixed-size. Not tried: restoring a maximized window (nothing drives
  maximize), a modal blocking the window. Screen captures after this relaunch came back all cyan: Windows
  would not bring Skyline to the front.
- Committed the arrow keys + `ResizeWindow` (`3bf5a5bb9e`, CodeInspection passed on Release), then re-drove the
  whole tutorial against it from `MethodEdit_20260924b` and committed the refreshed walkthrough
  (`9bf6fe074a`): 1035x511 main window, p07/p21 through File > Import > Window Layout, tree navigation by
  arrows + Ctrl+Home/End (Ctrl+Home/End are `SequenceTree.OnKeyDown`'s own), Insert Peptides at 821x437
  (s-12 807x430 = the tutorial's size). s-04 and s-11 differ from the tutorial's images in 0.7% / 2.8% of
  pixels. Unique Peptides at the test's 292 px cuts off details and buttons without its `SplitHeight = 58`
  (no splitter verb), so s-15 is at the dialog's own size. Ion Types > B worked this time only because the
  process had opened a b-ion document earlier (#4671 item 3 unchanged). The pick-list funnel state persists
  across pick-lists: read `get_options` before clicking it. All 35 captures scanned: no cyan.
- Splitter (Nick's design, no new UiAction): `SplitterElement : ControlElement<SplitContainer>, IValueElement`.
  get_value/set_value is `SplitterDistance` (pixels from the top for panels one above the other, from the
  left for side by side); a value outside Panel1MinSize..(length - SplitterWidth - Panel2MinSize) is refused
  with the range. Its panels flatten to the form like a TabControl's pages (`GetDescendants`), so
  get_controls still lists the controls inside. Verified live on Unique Peptides: listed as `SplitContainer`,
  330 -> 58 read back, 5000 refused ("between 25 and 224"), then 719x292. Captures of it came back all cyan:
  the relaunched Skyline was refused the foreground. s-15 not re-captured yet. Build only, not committed.
