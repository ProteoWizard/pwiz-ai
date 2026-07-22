# TODO: GraphChromatogram totals NRE on stale peptide path

**Status**: Completed
**Branch**: `Skyline/work/20260721_graphchrom_totals_null_peptide`
**Checkout**: C:\Dev\bugfix
**PR**: [#4443](https://github.com/ProteoWizard/pwiz/pull/4443) (merged 2026-07-21 as 0cf7ef2)
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
- [x] PR opened and merged (#4443)
- [x] Copilot review addressed (hoisted guard above the peak-window merge)
- [x] `Cherry pick to release` label applied; auto cherry-pick to `Skyline/skyline_26_1` pending

### 2026-07-21 - Merged

PR #4443 merged as commit 0cf7ef2. Shipped the null guard in
`GraphChromatogram.DisplayTotals` (skips a transition group whose cached path no
longer resolves to a peptide in the current document) plus the `TestStaleSelection`
regression coverage folded into `ChromGraphTransformTest`. Copilot's one comment led
to hoisting the guard to the top of the loop so a stale group can't influence
auto-zoom; re-inspected, re-self-reviewed, and re-verified red/green at the new
placement — all clean.

### 2026-07-22 - Cherry-picked and cleaned up

Cherry-pick PR #4444 merged to `Skyline/skyline_26_1` as commit 80b5225. Work branch
`Skyline/work/20260721_graphchrom_totals_null_peptide` deleted (local + remote).
Exception #75292 (fingerprint 12e70ba8d154fc90) recorded fixed on the dashboard for
both master (#4443) and release (#4444).
