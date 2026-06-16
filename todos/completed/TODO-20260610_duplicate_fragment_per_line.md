# TODO-20260610_duplicate_fragment_per_line.md

## Branch Information
- **Branch**: `Skyline/work/20260610_duplicate_fragment_per_line`
- **Base**: `master`
- **Created**: 2026-06-10
- **Status**: Completed
- **GitHub Issue**: [#4284](https://github.com/ProteoWizard/pwiz/issues/4284) (closed)
- **PR**: [#4286](https://github.com/ProteoWizard/pwiz/pull/4286) (merged 2026-06-15 as 33c132f5)
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
- [x] `CreateTransitionLossToChildMap` left strict (unhandled-exception backstop preserved).
- [x] Error names the offending column: `See column N "Header"` (`GetColumnDescription` + abstract
  `GetColumnName` returning the dialog-assigned/localized label; a label is always available).
- [x] New message strings in `Model/ModelResources.resx` (moved there from `Properties/Resources.resx`
  per code inspection; designer kept at the repo builder version to avoid churn).
- [x] Test `PasteMoleculesTest.TestDuplicateFragmentOnLine` - two scenarios covering both guard paths
  (new-molecule `GetMoleculeTransitionGroup` and existing-molecule `AddFragmentTransitions`); red->green
  verified for each. Translation-proof (asserts the localized column-name resource); green en + zh.
- [x] Build + `TestPasteMolecules` + `CodeInspection` green.

### Review
- [x] `/pw-self-review` x3 - findings addressed (resource placement, GetColumnName doc/abstract,
  AddFragmentTransitions test coverage). Final pass run.
- [x] Copilot x4 - all threads resolved; latest review clean (no comments).

### Remaining
- [x] Human review + CI; merge
- [x] Support thread #74731 reply (done by author)

## Files
- `pwiz_tools/Skyline/Model/SmallMoleculeTransitionListReader.cs`
- `pwiz_tools/Skyline/Model/ModelResources.resx` (+ `ModelResources.designer.cs`)
- `pwiz_tools/Skyline/Properties/Resources.resx` (+ `Resources.Designer.cs`) (string removed)
- `pwiz_tools/Skyline/TestFunctional/PasteMoleculesTest.cs`

## Progress Log

### 2026-06-15 - Merged

PR #4286 merged as commit 33c132f5 (squash), auto-closing issue #4284. Approved by
brendanx67. Final follow-up: corrected the `AddFragmentTransitions` call-site comment
(it returns true when a fragment was not added — absent first fragment or a duplicate
reported as a row error) and credited the reporter (Eva) in the PR/issue. Reporter
identified from support thread #74731. No cherry-pick: POST-RELEASE PATCH phase, and
this is a non-critical guard on relatively-new master-only multi-fragment-per-line code.
