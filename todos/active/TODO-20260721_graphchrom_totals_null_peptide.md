# TODO: GraphChromatogram totals NRE on stale peptide path

**Branch**: `Skyline/work/20260721_graphchrom_totals_null_peptide`
**Checkout**: C:\Dev\bugfix
**Source**: skyline.ms exception report #75292 (NullReferenceException, 26.1.0.057)

## Objective

Fix a `NullReferenceException` in `GraphChromatogram.GetColorIndex` thrown while
displaying peptide totals.

## Root cause

`DisplayTotals` resolves the color for each transition group via
`DocumentUI.FindNode(_groupPaths[i].Parent)`. During a document-change dispatch the
graph can update while the tree selection still references a peptide that has just
been removed from the current document, so `FindNode` returns null and
`GetColorIndex` dereferences `peptideDocNode.TransitionGroups`. The unguarded deref
was introduced in 2023 (#2450) when `GetColorIndex` began taking a `PeptideDocNode`.

## Fix

`GraphChromatogram.DisplayTotals`: skip (`continue`) the group when
`FindNode(...)` returns null — matching the existing null tolerance in
`IsCacheCurrent`. The next update redraws against the current selection.

## Test

Folded into `ChromGraphTransformTest.TestChromGraphTotal` as `TestStaleSelection()`:
seeds the equivalent stale state (cached `_nodeGroups` intact, `_groupPaths` pointed
at an absent peptide) and calls `UpdateUI()`, asserting no throw and 0 rendered
curves. Red/green verified — reproduces the exact NRE without the guard.

## Status

- [x] Fix implemented
- [x] Regression test (red/green verified)
- [x] CodeInspection test passes
- [x] Full ReSharper inspection clean (no issues in changed regions)
- [x] Self-review clean ("ship it")
- [ ] PR opened
- [ ] Cherry-pick to `Skyline/skyline_26_1`? (patch mode - crash fix, maintainer call)
