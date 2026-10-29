# TODO-20261028_crosslink_left_peptide_mods.md

## Branch Information
- **Branch**: `Skyline/work/20261028_crosslink_left_peptide_mods`
- **Base**: `master`
- **Created**: 2026-10-28
- **Status**: Completed
- **PR**: [#4929](https://github.com/ProteoWizard/pwiz/pull/4929) (merged 2026-10-28),
  release cherry-pick [#4930](https://github.com/ProteoWizard/pwiz/pull/4930) (merged 2026-10-28)
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
- [x] Demonstrate on Alessio's tutorial data: replayed the tutorial's Library Explorer Add All
      (tutorial PDF pp. 11-13, which documents this as "IMPORTANT BUG") on the 26.1.1 release
      branch in C:\Dev\Backport with a throwaway functional test:
      - without fix: 4829 transitions, 152/488 XL peptides missing left CAM, 9 pyro-Glu dropped
      - with fix: 3650 transitions, 0 missing CAM, all 9 pyro-Glu kept
- [x] CodeInspection + /code-review medium (3 fixed: comment scope, exact-count asserts,
      null assert; 3 dropped: guard placement equivalent, variable-path rewrite is existing
      behavior, extra variable-path coverage)
- [x] PR #4929 opened with `skyline` + `Cherry pick to release` labels
- [x] Manual cherry-pick to Skyline/skyline_26_1_1 (.NET 4.7.2 daily): PR #4930 from
      C:\Dev\Backport, branch Skyline/work/20261028_crosslink_left_peptide_mods_release.
      PeptideDocNode.cs is CRLF-stored there (pre-#4789), so re-committed with a CRLF blob
- [x] `Cherry pick to release` label removed from #4929 (no auto pick to skyline_26_1);
      #4930 is the only release-line change
- [ ] Reply to Juan/Alessio (draft written in session; Brian sends); tutorial "IMPORTANT BUG"
      section can go once a daily with the fix ships

## Master vs release

The tutorial recipe does NOT reproduce on master (.NET 10): the matcher's mods happen to equal
the document's, so EnsureMods returns early. The .NET Framework release build (26.1.x, what users
run) reaches the defective path. EnsureMods is identical on both; the unit test reproduces the
defect on master by making matcher and document mods differ. Candidate runtime difference:
AbstractModificationMatcher.SearchPartialModMatches (Dictionary -> List change on master for the
.NET Core empty-array singleton) - not traced.

## Notes

- Tutorial library: 168 of 493 crosslinked entries have left-peptide mods that are all
  implicit (CAM / N-term pyro-Glu) and would lose them; 14 involve pyro-Glu.
- The shipped IFX_TNF_XLMS.sky already has the left mods corrected by hand, so it cannot
  show the bug; start from a fresh document with the same modifications.

## Progress Log

### 2026-10-28 - Merged

PR #4929 merged to master as commit 346c41a009; cherry-pick #4930 merged to
Skyline/skyline_26_1_1 as fa8b808116. `EnsureMods` now keeps static mods explicit on
crosslinked peptides, so the first peptide keeps Carbamidomethyl / pyro-Glu when added
from Library Explorer, pasted, or imported. Left open: the reply to Juan and Alessio, and
retiring the tutorial's "IMPORTANT BUG" workaround.
