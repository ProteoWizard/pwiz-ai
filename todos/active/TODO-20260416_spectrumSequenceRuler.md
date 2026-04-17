# TODO-20260416_spectrumSequenceRuler.md

## Branch Information
- **Branch**: `Skyline/work/20260416_spectrumSequenceRuler`
- **Base**: `master`
- **Created**: 2026-04-16
- **Status**: In Progress
- **GitHub Issue**: (pending)
- **PR**: (pending)

## Objective

Add a sequence ruler to the spectrum viewer (`GraphSpectrum`) that displays the peptide
amino acid sequence as a labeled axis aligned with the observed fragment ion peaks.

The ruler should make it visually obvious which fragment ions correspond to which residues,
similar to how sequence coverage tools overlay sequence onto spectra.

## Desired Behavior

- When a peptide is selected and the spectrum graph is showing MS/MS data, a ruler appears
  along the top (or bottom) of the spectrum pane showing the amino acid sequence
- Each residue is positioned at the x-coordinate of its corresponding b/y ion (or the
  midpoint between adjacent ions)
- The ruler should update as the user selects different peptides or charge states
- Residues with matched ions could be highlighted differently from unmatched ones
- Should work for both forward (b-ions) and reverse (y-ions) directions

## Key Files

- `pwiz_tools/Skyline/Controls/Graphs/GraphSpectrum.cs` — main spectrum graph form
- `pwiz_tools/Skyline/Controls/Graphs/SpectrumGraphItem.cs` — graph item that renders spectrum
- `pwiz_tools/Skyline/Model/Lib/LibraryRankedSpectrumInfo.cs` — ranked spectrum info with ion assignments

## Tasks

- [ ] Explore `GraphSpectrum.cs` and `SpectrumGraphItem.cs` to understand current rendering
- [ ] Understand how fragment ion x-coordinates are computed (m/z axis)
- [ ] Design ruler: ZedGraph `GraphObj` overlay or custom axis band
- [ ] Implement sequence ruler rendering in the spectrum pane
- [ ] Handle edge cases: no peptide selected, small molecules, wide/narrow window
- [ ] Add functional test
- [ ] Add resource strings for any user-visible text

## Notes / Decisions

- TBD: ruler position (top vs. bottom of chart area)
- TBD: how to handle overlapping residue labels at high charge state / dense spectra
- TBD: whether to show b-series, y-series, or both (possibly toggleable)
