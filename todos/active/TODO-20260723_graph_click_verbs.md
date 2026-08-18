# TODO-20260723_graph_click_verbs.md - Graph click/zoom and keyboard verbs for the AI connector

## Branch Information
- **Branch**: `Skyline/work/20260723_graph_click_verbs`
- **Checkout**: `I:\git_i\sky_mcpconnector`
- **Module**: `skyline`
- **Base**: `master`
- **Created**: 2026-07-23
- **Status**: In Review
- **GitHub Issue**: #4449
- **PR**: https://github.com/ProteoWizard/pwiz/pull/4452

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
- [x] `PasteDlg.TryPasteIntoGrid` for the resolving grids
- [x] `SequenceTree.OnKeyPress` off `SendKeys`
- [x] `FindElement` type fallback, with ambiguity refused
- [x] Connector ZIP rebuilt, `EXPECTED_ZIP_VERSION` matching
- [ ] Decide whether the `graphId` -> `formId` rename is acceptable as a breaking change

## Not addressed

- Drag-to-dock (MethodRefine s-21) and the tree pop-up pick-lists / hover data-tips /
  drag-reorder (MethodEdit s-19-22).
- Stepping the statement-completion pop-up to a LATER match. The two-protein test proteome
  cannot produce a multi-match list, so `Down` would assert nothing; only `Enter` is sent.
- `PasteDlg.TryPasteIntoGrid`'s resolving branch under test. It needs a document with a
  background proteome; `Rat_plasma.sky` has none, so a paste there fills cells and proves
  nothing about the branch this adds.

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

## References

- Issue #4449
- Cross-OS file-dialog doc: `ai/docs/native-file-dialog-automation.md`
