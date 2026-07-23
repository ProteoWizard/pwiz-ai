# TODO-mcp_tutorial_view_layout.md — MCP screenshot-layout reproduction (view files + window verbs)

## Status

**Backlog** (undated; date it when it moves to a branch). Discovered during the
MCP tutorial-testing effort. Depends on the connector work in
[`TODO-20260609_native_file_dialog_automation.md`](../active/TODO-20260609_native_file_dialog_automation.md)
(PR #4313). See the deliverability analysis below — parts land on `pwiz:master`,
parts must ride the connector branch / a fast-follow.

## Motivation

The tutorial-testing runbook
(`ai/todos/active/TODO-20260609_native_file_dialog_automation-tests/`) proved the
MCP can drive a tutorial end-to-end, but **can't reproduce screenshots whose
layout is a hand-arranged dock composite**. Concretely, MethodRefine **s-21**
(`TEST-MethodRefine.md` Finding #1): the sub-agent loaded all the right data (5
scheduled replicates) and verified every graph's content individually, but the
tutorial docks Peak Areas to the right edge and RT-Comparison to the bottom by
**mouse drag** — and there is no MCP drag / drag-to-dock verb, so the composite
window can't be assembled (and a main-window capture with panes floating over it
redacts to cyan).

**Stop-gap that beats a drag verb for screenshot repro:** the TestTutorial tests
already persist the exact DigitalRune layout for these screenshots as `.view`
files and restore them. Deliver those through the MCP like the tutorial HTML, add
a verb to load one, and add a window resize/position verb. Deterministic,
fidelity-guaranteed (same assets that generate the reference shots), and no
per-tutorial drag automation to author. A general drag-to-dock verb remains the
longer-term flexible option but is lower priority given this.

## How the existing pieces work (verified in `pwiz-work2`)

- **View files:** `pwiz_tools/Skyline/TestTutorial/{Tutorial}Views.data/pNN.view`
  — XML `DockPanel` snapshots (full layout: dock portions, per-pane
  `PersistString`, floating/hidden). ~11 tutorials ship a `*Views.data` folder.
- **Load path:** `TestFunctional.RestoreViewOnScreen(int pageNum)` →
  `p{N:0#}.view` → `SkylineWindow.LoadLayout(stream)`. The `int` is a **tutorial
  page number**, "originally associated with Word docs/PDFs… could be any
  numbers" (code comment) — **decoupled from the screenshot number.**
- **Screenshot naming:** a shared `ScreenshotCounter` → `s-NN.png` via
  `_shotManager.ScreenshotDestFile(counter)`, advanced by every screenshot method
  (`PauseForScreenShot`, `PauseForScreenShot<T>`, `PauseForGraphScreenShot`, and
  the connector path `SaveMcpConnectorScreenShot`).
- **Window sizing (already exists):** `SetSkylineWindowSize(w,h)` (sets
  `SkylineWindow.Bounds`, centers it), `MaximizeSkylineWindow()`; cover shots
  assert 1200×800 @ 100% DPI.
- **Connector capture already exists:** `SaveMcpConnectorScreenShot` +
  `JsonTutorialTest` capture tutorials *through the JSON/MCP connector*. The
  mapping diagnostic can ride that recording path; the new verbs wrap
  already-tested product code (`LoadLayout`, `Bounds`).

**pNN→sNN is not a bijection.** A view load feeds the *first* screenshot after it
and is reused by later screenshots until the next load (e.g. `p09` → the
regression shot, then the 0.95-threshold and zoomed-out shots reuse it; `p13` →
one shot, then two reuse it). Some sections take screenshots with no preceding
load; cover-shot mode (`IsCoverShotMode`) loads `cover.view` and returns early.
Because `.view` files are **full** snapshots, the runner rule is simply: **for
`s-NN`, load the nearest preceding `s-≤NN.view`** — always the correct full
layout, no per-shot duplication needed.

## Deliverability / sequencing (the key question)

Split by what each part touches:

| Part | Touches | Branch-dependent? | Land on |
|------|---------|-------------------|---------|
| A. Mapping diagnostic + bulk rename `pNN.view`→`s-NN.view` + call-site/format-string edits | `TestFunctional.cs`, `TestTutorial/*.cs`, `*Views.data/` — all on master | **No** — independent of the connector | **`pwiz:master`**, but **after #4313 merges** (avoids conflicts with the branch's in-flight `*McpConnectorTest`/`JsonTutorialTest` test changes) |
| B. MCP verbs `skyline_load_view_layout` + `skyline_set_window_bounds` | connector (`IJsonToolService`/`JsonUiService`) + external MCP server (`SkylineTools.cs`, `EXPECTED_TOOL_COUNT`) | **Yes** — #4313 is actively bumping the tool count / `EXPECTED_TOOL_COUNT`; concurrent master edits to `SkylineTools.cs` would conflict | **On #4313** (if wanted for immediate testing) **or a fast-follow PR after it merges** |
| C. GitHub delivery of `s-NN.view` (fetch pinned to version, like `skyline_get_tutorial`) | MCP server | Same as B | With B |

**Recommended order:**
1. Let **#4313 merge** (near-complete).
2. **A** — rename PR on `pwiz:master` (developable now on `pwiz-work1`, which has
   fresh master). This finalizes the `s-NN.view` naming the verb keys on.
3. **B + C** — MCP verbs + delivery on `pwiz:master` (connector now merged; naming
   final).

**If the verbs are wanted before #4313 merges** (to test the s-21 fix
immediately): add **B** to #4313 itself, keyed initially by `pNN` (or an inline
mapping), and do **A** afterward. Downside: bloats an already-large PR.

**Do NOT** develop A or B on `pwiz:master` *concurrently* with #4313 — A conflicts
with the branch's TestTutorial edits; B conflicts on `SkylineTools.cs`/tool count.

## Work breakdown

**A. Derive the mapping + rename**
1. Instrument the shared `ScreenshotCounter` increment and `RestoreViewOnScreen`
   to emit, per tutorial, `(pageNum → s-NN of the first screenshot after the
   load)`. Run all tutorial tests in record mode; collect the tables. The
   diagnostic is authoritative — it resolves cover-mode early-return, reused-view
   runs, and any counter-vs-tutorial-HTML drift at optional/skipped sections
   (e.g. MethodRefine s-03).
2. Bulk-rename `pNN.view`→`s-NN.view` in every `*Views.data/` (Git-light: content
   unchanged). Update `RestoreViewOnScreen` call-site args (`pNN`→`s-NN`) and the
   format string `p{0:0#}`→`s-{0:0#}` (keep `cover.view` as-is). Confirm the
   tutorial tests still pass (identical layout content, renamed key).
   - Verify the mapping is **language-independent** (layout, not text; the counter
     order should match across en/ja/zh) so one rename serves all languages.

**B. MCP verbs**
3. `skyline_load_view_layout` — wraps `SkylineWindow.LoadLayout(stream)`. For the
   runner: keyed by tutorial + screenshot id, applies the nearest-preceding
   `s-NN.view`. Scope it as a **test/repro** capability (a general assistant
   should not auto-apply these — they target one graph for one shot).
4. `skyline_set_window_bounds` (size and/or position; option to center /
   maximize-without-maximized-state) — wraps `SkylineWindow.Bounds` /
   `SetSkylineWindowSize`. Dual purpose: screenshot fidelity **and** positioning
   Skyline so nothing overlaps the capture (fixes the cyan-overlap failure).

**C. Delivery + integration**
5. Fetch `s-NN.view` from the pwiz GitHub repo pinned to the running version
   (mirror `skyline_get_tutorial`); fold fetch+apply into `load_view_layout` or a
   sibling `get_tutorial_view`.
6. Update the tutorial-testing README §4: at a screenshot checkpoint, set window
   bounds, load the nearest-preceding `s-NN.view` if one exists, then capture;
   note this resolves MethodRefine Finding #1. Re-run MethodRefine s-21 to confirm
   a pixel-faithful composite (the live Skyline is currently parked in the exact
   pre-s-21 state — a ready bench).

## Open questions / verify first

- Confirm the base connector (`IJsonToolService`/`JsonUiService`/`JsonToolServer`)
  and `SkylineMcpServer`/`SkylineTools.cs` locations vs #4313 to lock the table
  above (the tool-count coupling is the deciding factor).
- Confirm `.view` load is safe when the document's open panes differ from what the
  view references (LoadLayout is a full replace — reaching the right *data* state
  first is required; the runner already does).
- Decide whether reused-view screenshots stay file-less (nearest-preceding rule,
  recommended) or get duplicate `s-NN.view` copies for self-containment.

## References

- Need discovered: `ai/todos/active/TODO-20260609_native_file_dialog_automation-tests/TEST-MethodRefine.md` (Finding #1), README Finding lists.
- Connector dependency: `TODO-20260609_native_file_dialog_automation.md` (Phase 3).
- Code: `pwiz_tools/Skyline/TestUtil/TestFunctional.cs` (`RestoreViewOnScreen`,
  `ScreenshotCounter`, `SaveMcpConnectorScreenShot`, `SetSkylineWindowSize`);
  `pwiz_tools/Skyline/TestTutorial/*Views.data/`, `MethodRefinementTutorialTest.cs`.
