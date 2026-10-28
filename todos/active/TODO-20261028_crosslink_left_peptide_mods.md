# TODO-20261028_crosslink_left_peptide_mods.md

## Branch Information
- **Branch**: `Skyline/work/20261028_crosslink_left_peptide_mods`
- **Base**: `master`
- **Created**: 2026-10-28
- **Status**: In Progress
- **Module**: `skyline`
- **Checkout**: `C:\Dev\UIbug`

## Objective

Fix crosslinked peptides losing every structural modification on the first (left-hand)
peptide when added from Library Explorer, pasted, or imported from another document.
Reported by Juan and Alessio (email thread "trouble with Carbamidomethyl on cross-linked
peptides", 2026-10-26..28).

## Root cause

`PeptideDocNode.EnsureMods` drops explicit static mods that match the target document's
implicit mods (`newExplicitStaticMods = null`). For a crosslinked peptide it still rebuilds
`ExplicitMods` with `ChangeCrosslinkStructure`, which turns a null static list into an empty
explicit list, because crosslinked peptides never receive implicit mods. Linked peptides
live in `CrosslinkStructure` and are untouched, so only the left peptide loses its mods.
Library Explorer hits it every time because its matcher settings differ from the document's.

## Tasks

- [x] Failing test: `CrosslinkModTest.TestCrosslinkEnsureModsKeepsFirstPeptideMods`
      (Library Explorer path and paste/import path)
- [x] Fix in `EnsureMods`: keep static mods explicit on crosslinked peptides
- [x] Related tests green: crosslink unit + functional, CopyPaste, ImportDoc, Paste,
      ModificationMatcher, LibraryExplorer, RescoreImportDocument, PasteMolecules
- [ ] Demonstrate on Alessio's tutorial data (IFX_TNF_XLMS_q_0_05.blib): Library Explorer
      Add of e.g. AC[+57]EVTHQGLSSPVTKSF-KVEPK keeps CAM and matches its spectrum
- [ ] CodeInspection + /code-review, then PR

## Notes

- Tutorial library: 168 of 493 crosslinked entries have left-peptide mods that are all
  implicit (CAM / N-term pyro-Glu) and would lose them; 14 involve pyro-Glu.
- The shipped IFX_TNF_XLMS.sky already has the left mods corrected by hand, so it cannot
  show the bug; start from a fresh document with the same modifications.
