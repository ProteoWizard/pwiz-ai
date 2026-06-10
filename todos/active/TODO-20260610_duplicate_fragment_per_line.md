# TODO-20260610_duplicate_fragment_per_line.md

## Branch Information
- **Branch**: `Skyline/work/20260610_duplicate_fragment_per_line`
- **Base**: `master`
- **Created**: 2026-06-10
- **Status**: PR open, awaiting Copilot review
- **GitHub Issue**: [#4284](https://github.com/ProteoWizard/pwiz/issues/4284)
- **PR**: [#4286](https://github.com/ProteoWizard/pwiz/pull/4286)
- **Worktree**: `C:\Dev\DupFragLine`

## Objective

A small-molecule transition list with a duplicated fragment-oriented column (e.g. two `Product Charge`
columns but a single `Product m/z` column) made the multiple-fragments-per-line importer fill-forward
the single `Product m/z` into two identical transitions on one line, crashing the post-import
small-molecule automanage refinement with an unhandled `ArgumentException` from
`TransitionGroupDocNode.CreateTransitionLossToChildMap`. Report this as a normal row import error
instead of crashing. Origin: skyline.ms support thread #74731 (Sciex ZenoTOF 7600 MRM-HR).

## Progress

### Completed
- [x] Root-caused: `GetFragmentCount` counts repeated *modifier* columns (Product Charge/Adduct), inflating
  the fragment count; `GetProductColumnForFragment` then fill-forwards the single Product m/z → identical
  transition; no within-line duplicate check, so it crashed later in automanage.
- [x] `SmallMoleculeTransitionListReader.IsDuplicateFragmentOnLine` - detects two identical transitions
  declared on one line (keyed on `tran.Transition`, the same identity `TransitionLossKey` uses) and reports
  a row error via `ShowTransitionError` (surfaced by "Check For Errors" and on import). No silent dedup.
- [x] Applied in both per-line paths (`GetMoleculeTransitionGroup` new-molecule branch, `AddFragmentTransitions`).
- [x] `GetProductColumnForDuplicateFragment` - points the error at the offending repeated column (e.g. the
  second Product Charge), not the fill-forwarded Product m/z.
- [x] New resource string in `Properties/Resources.resx` (+ Designer).
- [x] `CreateTransitionLossToChildMap` left strict (unhandled-exception backstop preserved).
- [x] Test `PasteMoleculesTest.TestDuplicateFragmentOnLine` - asserts the error message and that it flags
  the correct column. Red->green verified (without the fix, Check For Errors reports "No errors").
- [x] Build + `TestPasteMolecules` green.

### Remaining
- [x] `/pw-self-review` (findings addressed: resource rename, doc comment; tolerate-errors asymmetry documented as intentional)
- [x] Added column name to the error message: `See column N "Header"`
- [x] Commit (ai/ TODO + pwiz code), open PR #4286 (`Fixes #4284`)
- [ ] Address Copilot review (`/pw-respond 4286`)
- [ ] Merge; reply to support thread #74731

## Files
- `pwiz_tools/Skyline/Model/SmallMoleculeTransitionListReader.cs`
- `pwiz_tools/Skyline/Properties/Resources.resx` (+ `Resources.Designer.cs`)
- `pwiz_tools/Skyline/TestFunctional/PasteMoleculesTest.cs`
