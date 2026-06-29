# TODO-20260416_spectrumSequenceRuler.md

## Branch Information
- **Branch**: `Skyline/work/20260416_spectrumSequenceRuler`
- **Base**: `master`
- **Repo**: `pwiz1`
- **Created**: 2026-04-16
- **Status**: In Progress
- **GitHub Issue**: (pending)
- **PR**: ProteoWizard/pwiz#4158

## Objective

Add sequence rulers to the spectrum viewers (`GraphFullScan` for measured spectra,
`GraphSpectrum` for library spectra) that display the peptide amino acid sequence
aligned with the fragment ion m/z positions.

## Design Reference

See `ai/.tmp/screenshots/sessions/clipboard_20260416_174221.png` — inspiration screenshot
showing rulers from another tool (ETD spectrum, c/z ion series).

## Desired Behavior

- The ruler is **hidden by default** and appears only on **mouse-over of an annotated peak**
  (either the stick or its label); it disappears when the mouse moves to an unannotated peak
  or leaves the graph
- One ruler is shown at a time, for the **ion type and charge** of the hovered peak
- The ruler is drawn at the **top of the chart area** (`y = 0.04` chart fraction) using
  `AminoAcidLadderObj`, a `ZedGraph.GraphObj` subclass
- **Residue labels** are drawn at the midpoint of each fragment-ion interval in a font
  slightly smaller than the spectrum font, using Skyline's modified-sequence notation
  (e.g. `C[+57]`); the N-terminal residue is omitted for b/a/c series, the C-terminal
  residue for y/x/z series, because those residues have no inner boundary ion
- **Tick marks** appear at every fragment-ion boundary and at both endpoints (ordinal-1 ion
  and molecular ion)
- **Drop lines** extend vertically from each tick down to the top of the matched peak, or
  all the way to the x-axis when no peak is present at that ordinal; drop lines are drawn
  in light grey (lighter than unannotated peaks)
- The horizontal ruler line and ticks use the **ion-type color** (same color as the
  annotated peaks for that series)
- The ruler is **transparent to hit-testing** (`PointInBox` returns false) so it never
  blocks tooltip activation on the peak labels beneath it
- Rulers update when the user selects a different peptide or charge state

- User should be able to pin the ruler using the context menu, so that it remains visible when the mouse moves away from the peak.
- Other rulers might be shown as user moves the mouse over other peak types and those rulers can be pinned as well.
- Multiple rulers should be grouped by the direction (N or C end) and charge, each group sharing single set of sequence annotations. Each ruler group should be represented by a single AminoAcidLadderObj and can have multiple ion types with the same direction and charge.
- The rulers logic should also be able to support neutral loss peaks. Eacn newtral loss series should have its own ruler, since they do not align well.

## Key Files

- `pwiz_tools/Skyline/Controls/Graphs/GraphFullScan.cs` — measured spectrum viewer (primary target)
- `pwiz_tools/Skyline/Controls/Graphs/GraphSpectrum.cs` — library spectrum viewer
- `pwiz_tools/Skyline/Controls/Graphs/SpectrumGraphItem.cs` — graph item that renders spectrum peaks
- `pwiz_tools/Skyline/Model/Lib/LibraryRankedSpectrumInfo.cs` — ranked spectrum info with ion assignments

## Tasks

- [x] Implement `AminoAcidLadderObj` — ruler rendering with residue labels, ticks, and drop lines
- [x] Implement mouse-over activation in `GraphSpectrum` (library viewer)
- [x] Handle modified sequence notation (`C[+57]`, etc.)
- [x] Handle edge cases: small molecules, crosslinks, missing `SrmSettings`
- [x] Fix hit-testing interference (`PointInBox` → false)
- [x] Fix repaint loop when hovering peak labels (compare by ion series, not object identity)
- [x] Apply to `GraphFullScan` (measured spectrum viewer)
- [x] Apply to Library Explorer dialog (`ViewLibraryDlg`)
- [x] Disable ruler functionality entirely in small molecule mode (no defined AA sequence) — added `SpectrumGraphItem.RulersApplicable` (proteomic, non-crosslink, settings present); gated rendering, hover, and Pin/Unpin menu items on it in GraphFullScan, GraphSpectrum, and ViewLibraryDlg (also fixed a latent NRE in the old render guard)
- [x] Incorporate neutral loss series into ruler functionality (each neutral loss series gets its own ruler)
- [x] Add functional test — `TestFunctional/SpectrumSequenceRulerTest.cs` covers all three hosts (GraphFullScan, GraphSpectrum, ViewLibraryDlg) in one `[TestMethod]` with the EAD doc loaded once. Verifies hover→correct ruler, pin persists after hover clears, multi-ruler grouping, selective unpin, and unpin-all. Drives public test seams (`HoverRulerPeak`/`PinHoveredRuler`/`UnpinRuler`/`UnpinAllRulers`/`RulerGraphItem`) added to each host since mouse and context menu can't be synthesized. Consolidated the duplicated peak→`IonSeriesKey` (min-mass-error) mapping into a public `SpectrumGraphItem.GetBestSeriesKey` shared by all three hosts. Added `GraphFullScan.ShowAnnotations(bool)` so the test can switch the full-scan into annotated mode (rulers don't apply in target-only mode).
- [x] Add resource strings for any user-visible text — the "Pin Ruler", "Unpin Ruler", and "Unpin All Rulers" context-menu labels were hard-coded literals (caught by Copilot review). Moved them into `GraphsResources.resx`/`.designer.cs` as `SequenceRulerMenu_PinRuler` / `SequenceRulerMenu_UnpinRuler` / `SequenceRulerMenu_UnpinAllRulers`, referenced from all three hosts.
- [x] Add a master "Enable Rulers" / "Disable Rulers" context-menu toggle (from oral UI review) — a single item whose label reflects the current state. When disabled, all rulers (hovered and pinned) stop rendering, hover is inert, and the Pin/Unpin/Unpin-All items disappear; only "Enable Rulers" remains so the feature can be turned back on. Backed by a persisted global preference `Settings.Default.SpectrumSequenceRulersEnabled` (default true), exposed via static `SpectrumGraphItem.RulersEnabled` + `RulerToggleMenuText`. Gated rendering (`AddPreCurveAnnotations`), hover (`UpdateHoveredPeak`), and the menu in all three hosts. New resource strings `SequenceRulerMenu_EnableRulers` / `SequenceRulerMenu_DisableRulers`. Disabling clears the host's pinned rulers (via a public `ToggleRulersEnabled()` seam per host), so re-enabling shows no rulers until the user hovers/pins again. Test extended (step 6) to verify the pinned state clears on disable and does not return on re-enable.
- [ ] (Idea/low priority) Add a ruler selector control to the spectrum toolbar, allowing the user to manually show a ruler for any ion type, charge, and neutral loss combination — complementary to the mouse-over/pin workflow
- [x] Preserve pinned rulers across annotation-display toggles in `GraphSpectrum` — added the `_lastPrecursorId` pattern (already used by `GraphFullScan` and `ViewLibraryDlg`): removed the unconditional `_pinnedSeriesKeys.Clear()` from `ClearGraphPane`, added the precursor-change check at the top of `MakeGraphItem`, and re-sync pinned keys to the freshly built `GraphItem` so pins survive annotation-toggle redraws.
- [ ] (Deferred from Copilot review #10) Extract a shared `SpectrumRulerHost` helper from `GraphSpectrum`, `GraphFullScan`, and `ViewLibraryDlg` so the ruler context-menu, pin/hover state machine (`_pinnedSeriesKeys`, `_lastPrecursorId`, `_contextMenuOpen`), `PinRuler`/`UnpinRuler`/`UnpinAllRulers`/`PinHoveredRuler`, and `BuildMenuItems` live in one place. Composition-based (each host holds a `SpectrumRulerHost` field constructed with `() => GraphItem` + `() => graphControl.Invalidate()`). Mouse-event wiring stays per-host. Larger refactor; deferred from the current PR to keep correctness fixes focused — full plan in `ai/todos/backlog/TODO-spectrum_ruler_host_extraction.md`.

## Notes / Decisions

- Residue positioned at midpoint between adjacent theoretical ion m/z values
- abc and xyz blocks both drawn at top; xyz stacks below abc
- Stacking order resolved: each pinned ruler group (and the hovered ruler last) occupies its own slot below the previous one at `yLine = 0.04 + slot * RULER_SLOT_HEIGHT` (~7% chart height per slot). Within a single group, the horizontal ruler line, the per-series ion-type-colored ticks, and the residue labels (from the reference series — `b` for N-terminal, `y` for C-terminal) all share the same `yLine`; drop lines are drawn beneath everything else.
- Label crowding for short peptides or wide modifications: known limitation, not actively handled. Residue labels are drawn centered at the midpoint of each fragment-ion interval and can overlap at very narrow zoom widths or with long modification text (e.g. `C[+57]`). Workaround is zooming out; revisit if user feedback warrants explicit handling.

## Session Log

### 2026-06-09 — Added master Enable/Disable rulers toggle (oral UI review)

Added a single context-menu toggle ("Disable Rulers" when on, "Enable Rulers"
when off) per oral UI review feedback. Single source of truth is a persisted
global preference `Settings.Default.SpectrumSequenceRulersEnabled` (default
true), surfaced via static `SpectrumGraphItem.RulersEnabled` and
`RulerToggleMenuText`. When disabled: `AddPreCurveAnnotations` short-circuits
(no ladders), each host's `UpdateHoveredPeak` ignores hover, and the menu
builders drop Pin/Unpin/Unpin-All so only "Enable Rulers" shows. Disabling also
clears the host's pinned rulers (per-host `ToggleRulersEnabled()` method, which
the menu item and the test both call) so they do not return on re-enable.

Files: `Settings.settings`/`.Designer.cs`, `GraphsResources.resx`/`.designer.cs`
(2 new strings), `SpectrumGraphItem.cs`, `GraphSpectrum.cs`, `GraphFullScan.cs`,
`ViewLibraryDlg.cs`, and `SpectrumSequenceRulerTest.cs` (new step 6).

Per developer: setting is persisted and global; disabling clears pinned state.

Follow-ups this session:
- Added a label assertion (RulerToggleMenuText reflects state) after a coverage
  run showed that getter was the only new logic left uncovered.
- Fixed topmost-ruler residue labels clipping at the chart top in short panes
  (`AminoAcidLadderObj.Draw` now reserves one label-height above the line and
  shifts the whole ruler down). Verified visually.
- Rebased the three commits onto the remote (someone had clicked "Update branch",
  adding a master merge `a794462086`); rebuilt + retested green, then pushed.
  Pushed tip: `103403aa60`. Posted a method-level coverage report as a PR comment.
- Coverage summary: all new decision logic 100% (toggle action, render/hover
  gates, RulersEnabled, label getter); menu builders and `Draw` are 0% (GUI-only,
  not synthesizable / not unit-testable) - consistent with the seam-based pattern.

### 2026-06-05 — Code review complete, PR in human-review queue

PR #4158 passed two automated review gates (Copilot × 2, fresh-context
`/pw-self-review`). All inline threads either resolved with fixes or deferred
to tracked backlog TODOs. Final HEAD: `c4b2aca511`.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260416_spectrumSequenceRuler.md` before starting work.
- **Drop-line X uses the theoretical (predicted) ion m/z, not the observed peak m/z** — the ruler is a theoretical ladder, so anchoring drop lines to predicted positions is the intended semantic. At very high zoom (a few m/z visible), peaks with non-trivial mass error appear visually offset from their drop lines. This is accepted behavior, not a bug.
