# TODO-20260416_spectrumSequenceRuler.md

## Branch Information
- **Branch**: `Skyline/work/20260416_spectrumSequenceRuler`
- **Base**: `master`
- **Repo**: `pwiz1`
- **Created**: 2026-04-16
- **Status**: In Progress
- **GitHub Issue**: (pending)
- **PR**: (pending)

## Objective

Add sequence rulers to the spectrum viewers (`GraphFullScan` for measured spectra,
`GraphSpectrum` for library spectra) that display the peptide amino acid sequence
aligned with the fragment ion m/z positions.

## Design Reference

See `ai/.tmp/screenshots/sessions/clipboard_20260416_174221.png` — inspiration screenshot
showing rulers from another tool (ETD spectrum, c/z ion series).

## Desired Behavior

- When a peptide is selected and the spectrum graph is showing MS/MS data, sequence rulers
  appear at the **top** of the chart area
- Rulers are organized into two **blocks**:
  - **abc block**: sequence reads left-to-right (N→C)
  - **xyz block**: sequence reads right-to-left (C→N), stacked below abc block
- A block is **hidden entirely** if none of its ion series are enabled in the existing
  annotated-ions setting (same setting that controls peak annotation)
- Within each block, the **peptide sequence is shown once** — residues are shared across
  all ion series in the block (a/b/c share one sequence row; x/y/z share one sequence row),
  because ions of the same order within a block fall at similar m/z positions
- Each residue label is positioned at the **midpoint of the interval** between the two
  flanking theoretical ion m/z values (between ion[i-1] and ion[i])
- Labels use Skyline's **modified sequence** notation (e.g. `M[+16]`, `S[+80]`) —
  labels are variable width; layout must handle this
- All residue labels use the same font and style — no highlighting or greying by match status
- One ruler **line** per active ion series within the block (e.g. separate lines for b and c)
- On **mouse-over of an individual ruler line** (one ion series):
  - That ruler line is highlighted by thickness or color change
  - Residue character labels are unchanged
  - All peaks annotated to that ion series are highlighted in the spectrum
- Rulers update when the user selects a different peptide or charge state

## Key Files

- `pwiz_tools/Skyline/Controls/Graphs/GraphFullScan.cs` — measured spectrum viewer (primary target)
- `pwiz_tools/Skyline/Controls/Graphs/GraphSpectrum.cs` — library spectrum viewer
- `pwiz_tools/Skyline/Controls/Graphs/SpectrumGraphItem.cs` — graph item that renders spectrum peaks
- `pwiz_tools/Skyline/Model/Lib/LibraryRankedSpectrumInfo.cs` — ranked spectrum info with ion assignments

## Tasks

- [ ] Prototype ruler rendering in `GraphFullScan`
- [ ] Implement abc block (left-to-right sequence, b/a/c ion series lines)
- [ ] Implement xyz block (right-to-left sequence, y/x/z ion series lines)
- [ ] Connect visibility to existing annotated-ions setting
- [ ] Implement mouse-over highlighting (ruler line + corresponding peaks)
- [ ] Handle modified sequence notation (variable-width residue labels)
- [ ] Handle edge cases: no peptide selected, small molecules, very short/long peptides
- [ ] Apply to `GraphSpectrum` library viewer as well
- [ ] Add functional test
- [ ] Add resource strings for any user-visible text

## Notes / Decisions

- Residue positioned at midpoint between adjacent theoretical ion m/z values
- abc and xyz blocks both drawn at top; xyz stacks below abc
- Exact stacking order of sequence row vs. individual series lines within a block: TBD during prototyping
- Label crowding for short peptides or wide modifications: TBD
