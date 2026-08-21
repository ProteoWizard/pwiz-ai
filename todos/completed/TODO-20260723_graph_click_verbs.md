# TODO-20260723_graph_click_verbs.md - Graph click/zoom and keyboard verbs for the AI connector

## Branch Information
- **Branch**: `Skyline/work/20260723_graph_click_verbs`
- **Checkout**: `I:\git_i\sky_mcpconnector`
- **Module**: `skyline`
- **Base**: `master`
- **Created**: 2026-07-23
- **Status**: Completed
- **GitHub Issue**: #4449
- **PR**: [#4452](https://github.com/ProteoWizard/pwiz/pull/4452) (merged 2026-08-21)

## Objective

Let an AI client do two things it could not do at all: **act on a graph**, and **use the
keyboard**. Both are things a user does constantly and the connector had no answer for, so
tutorial steps that depend on them had to be faked with `set_selection` workarounds or
skipped.

- `GetGraphZoom` / `ZoomGraphTo` / `ClickGraph` - work in graph DATA coordinates.
- `SendText` / `SendKeyStroke` - deliver characters, and press one key with modifiers.

## Why the rectangle is un-normalized

`SkylineTool.Rectangle` stores exactly what it is given, even when Right < Left. A gesture
has a DIRECTION: the mouse goes down at Left/Top and comes up at Right/Bottom. Normalizing
would throw that away, and equal corners would stop being distinguishable as a single
click. A zoom, which has no direction, normalizes at the point of use instead.

## Why the gesture is synthesized, not simulated

`ZedGraphControl` grew public `PerformMouseDown/Move/Up/Click` (in the spirit of
`IButtonControl.PerformClick`), so a synthesized gesture runs the very handlers the OS
invokes. Every `MouseDown`/`MouseMove`/`MouseUp` subscriber AND ZedGraph's own zoom/pan
state machine then behave exactly as they would for a real press - which is the only way a
click on the RT-regression graph selects a peptide, or a drag below the axis moves a peak
boundary.

Consequence worth remembering: a press now ARMS that state machine. `ClickChromatogram`
had to start releasing the mouse, or `_isZooming`/`_dragPane` stay set and every later
move in the test draws a rubber band instead of tracking.

## Why typing and pressing a key are separate verbs

They are separate intents. `SendText` takes LITERAL text, so no character needs escaping.
`SendKeyStroke` takes ONE key named with its modifiers, so no key can be left held down.
Merging them would have meant inventing an escape syntax for ordinary text.

## Two behavior fixes that came out of this

- **`SequenceTree.OnKeyPress`** handed each typed character to `SendKeys.Send` - an
  asynchronous post to whatever window holds the FOCUS. Characters could land in another
  application or arrive out of order. They now go straight into the statement-completion
  edit box.
- **The Insert Proteins/Peptides grid** paste is not a fill: it RESOLVES what is pasted
  against the background proteome, which is the whole point of the form. The connector's
  paste now routes through `PasteDlg`'s own paste with the supplied text, so pasted
  peptides get their proteins - no clipboard, no Ctrl+V.

## Review findings fixed (2026-08-17/18)

- `EXPECTED_ZIP_VERSION` was stale against the rebuilt ZIP.
- **`skyline_get_graph_image` was broken end to end.** Renaming the MCP parameter
  `graphId` -> `formId` meant the rebuilt server could not bind the argument
  `SkylineMcpTest` was sending, and every call failed with a bare "an error occurred".
  **This is a breaking change to the shipped tool surface** - any client still passing
  `graphId` to `skyline_get_graph_data` / `_image` breaks the same way.
- **Digit key strokes.** `Enum.TryParse` reads a number as the enum's underlying VALUE, so
  `"1"` parsed as `Keys.LButton` (a mouse button) and `"0"` as `Keys.None`, while every
  tool description advertised "A-Z, 0-9". Digits are aliased to `D0`-`D9` now, and an
  all-digit segment is rejected before `Enum.TryParse` sees it.
- `CheckImageToolPreflight` was left unreferenced when the graph verbs moved to
  `GraphElement`; deleted.
- LLM-facing text that this branch's own `SequenceTree` fix made false ("DO NOT type into
  the Targets tree"), plus references to the renamed `skyline_send_keys`.

## FindElement matches on type (2026-08-18)

A caption-less control could not be named at all: `controlId` matched the visible label
only (`GridElement` matching on control Name is a deliberate exception). But a user told to
click "the tree" or type in "the text box" picks it out on sight, so the connector should
be able to name it the same way - and the tool descriptions already claimed it could.

`FindElement` now falls back to the control's TYPE when nothing carries that label. A label
always wins, so a type can never shadow a control captioned that; and a type must pick
exactly ONE control, otherwise it is refused rather than acting on whichever the walk
reached first.

**Do not hoist the candidate walk above the label lookup.** Building every element twice on
the common path leaves the extra set behind and leaks `SkylineWindow` - caught by
`TestMethodEditTutorial`'s leak check, which only fires when that test runs alongside
another.

## Task Checklist

- [x] Graph verbs on `GraphElement`, reached through `UiActions` like every other control
- [x] `SendText` / `SendKeyStroke` on `IKeyboardElement`
- [x] `PasteDlg.PasteIntoGrid` for the resolving grids, choosing the grid by which one is showing
- [x] `FindElement` type fallback, with ambiguity refused
- [x] An action value that is missing or of the wrong kind refused in `SimpleActionImpl`
- [x] Connector ZIP rebuilt, `EXPECTED_ZIP_VERSION` matching
- [x] `graphId` -> `formId` rename settled: not a breaking change, since the pipe carries positional
      parameters and an MCP client reads the schema fresh on every connect
- [ ] ~~`SequenceTree.OnKeyPress` off `SendKeys`~~ - reverted, see below

## Not addressed

- Drag-to-dock (MethodRefine s-21) and the tree pop-up pick-lists / hover data-tips /
  drag-reorder (MethodEdit s-19-22).
- **Typing into the Targets tree.** An earlier revision rewrote `SequenceTree.OnKeyPress`
  off `SendKeys` so the connector could type there. That is product code changed to serve
  automation, and it cost two user-facing regressions: typing over a protein name appended
  to it rather than replacing it, and the CapsLock correction (which only ever cancelled
  SendKeys re-applying the live CapsLock state) lowercased every letter typed with CapsLock
  on. It was reverted; `OnKeyPress` matches master. The verb descriptions say not to type
  into the tree, and point at `rename_node`.
- Two review findings left open, both in the click path and both able to act wrongly while
  reporting success:
  - `GraphElement.Click` transforms both corners against `FirstPane()` but delivers raw
    pixels, and ZedGraph re-resolves the pane from the point. On a split chromatogram, a Y
    below pane 0's axis - which the tool description recommends for a peak-boundary drag -
    can land in pane 1 and drag the WRONG precursor's boundary.
  - `isDrag` is decided by exact double inequality in data space while the gesture is
    delivered in rounded pixels, so two corners that differ in data yet round within 4
    pixels suppress the click and are then rejected as a sub-5-pixel drag. Nothing happens
    and `Completed` is true.
- The full review write-up, including what was verified and what was refuted, is at
  `ai/.tmp/pr4452-code-review-findings.md`.

## Key Files

- `pwiz_tools/Skyline/ToolsUI/GraphElement.cs` - new; all graph work
- `pwiz_tools/Skyline/ToolsUI/UiElement.cs` - `IKeyboardElement`, `ParseKeyStroke`, `FindElement`
- `pwiz_tools/Skyline/ToolsUI/UiActions.cs` - the new actions and their LLM instructions
- `pwiz_tools/Shared/zedgraph/ZedGraph/ZedGraphControl.Events.cs` - `PerformMouse*`, `ZoomPaneToScale`
- `pwiz_tools/Skyline/EditUI/PasteDlg.cs` - paste split from the clipboard read
- `pwiz_tools/Skyline/Controls/SequenceTree.cs` - the `SendKeys` fix
- `pwiz_tools/Skyline/TestFunctional/JsonToolServerTest.cs` - graph interaction, keyboard verbs, statement completion

## Progress Log

- **2026-07-23** - Graph verbs, keyboard verbs, grid paste routing, `SendKeys` fix; graph
  operations moved onto `UiActions`
- **2026-07-25** - Author headers on the two new files
- **2026-08-14** - `Simulate*` renamed to `Perform*`
- **2026-08-17** - ZIP rebuilt; review findings fixed (version, `formId` argument, digit
  keys, dead pre-flight, stale LLM text); `ClickChromatogram` releases the mouse;
  `click_graph` asserted to actually select
- **2026-08-18** - Control named by label not by Name in tests; statement completion
  covered end to end through `send_text` + `send_key_stroke`; `FindElement` type fallback
  (and the double-walk leak it first introduced); ZIP rebuilt again
- **2026-08-19** - `/code-review max`: three defects fixed (the edit box appended instead
  of replacing, the CapsLock correction inverted, a comma-separated key stroke read as a
  bitwise OR); comment and assertion style brought in line with STYLEGUIDE

### 2026-08-21 - Merged

PR #4452 merged as commit 51ec80a. Shipped the graph geometry verbs (`get_graph_zoom`,
`zoom_graph_to`, `click_graph`) on a new `GraphElement`, the keyboard verbs (`send_text`,
`send_key_stroke`), the connector's paste routed through `PasteDlg`'s own resolving paste,
public `PerformMouse*` / `ZoomPaneToScale` entry points on ZedGraph, and a `FindElement`
fallback that matches a caption-less control by its type.

Two contract changes reach beyond the new verbs. `SimpleActionImpl` now refuses an action
value that is missing or of the wrong kind, where such a value used to become
`default(TArg)` - a null string for most actions - so any action handed a JSON number did
nothing and reported success. And a zoom reads an EQUAL edge pair as "no zoom in this
direction", which is also what stops it writing `Min == Max` onto an axis whose auto flags
it has just cleared.

Deferred: typing into the Targets tree (the `OnKeyPress` rewrite was reverted - see Not
addressed), drag-to-dock, the tree pop-up pick-lists, and two open review findings in the
click path. No follow-up issues were filed for those; they are recorded above and in
`ai/.tmp/pr4452-code-review-findings.md`.

## References

- Issue #4449
- Cross-OS file-dialog doc: `ai/docs/native-file-dialog-automation.md`
