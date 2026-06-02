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
- [ ] Add resource strings for any user-visible text (none currently needed — no user-visible strings)
- [ ] (Idea/low priority) Add a ruler selector control to the spectrum toolbar, allowing the user to manually show a ruler for any ion type, charge, and neutral loss combination — complementary to the mouse-over/pin workflow

## Notes / Decisions

- Residue positioned at midpoint between adjacent theoretical ion m/z values
- abc and xyz blocks both drawn at top; xyz stacks below abc
- Exact stacking order of sequence row vs. individual series lines within a block: TBD during prototyping
- Label crowding for short peptides or wide modifications: TBD
- **Drop-line X uses the theoretical (predicted) ion m/z, not the observed peak m/z** — the ruler is a theoretical ladder, so anchoring drop lines to predicted positions is the intended semantic. At very high zoom (a few m/z visible), peaks with non-trivial mass error appear visually offset from their drop lines. This is accepted behavior, not a bug.
