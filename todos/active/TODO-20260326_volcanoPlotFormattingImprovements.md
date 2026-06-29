---
title: Independent Per-Trait Formatting for Volcano/Abundance Plots
branch: Skyline/work/20260326_volcanoPlotFormattingImprovements
repo: pwiz2
status: in_progress
---

## Objective

Allow users to control different formatting traits (color, symbol, size, label) independently
using separate match expressions. For example: color by protein name match, shape by p-value cutoff.

Currently, one `MatchRgbHexColor` rule sets all traits together (first full match wins).

## Approach

Single list of rules, but each trait is independently nullable. Application uses per-trait
first-match semantics: for each point, the first matching rule that has a given trait set
(non-null) wins for that trait. Rules no longer consume points exclusively.

## Changes Required

- [ ] `MatchRgbHexColor.cs` — make `PointSymbol?` and `PointSize?` nullable; `Color.Empty` = no color
- [ ] `GroupComparisonStrings.resx` + `.Designer.cs` — add "None" string for combo option
- [ ] `VolcanoPlotFormattingDlg.cs` — add "(None)" items to symbol/size combos; update pair classes
- [ ] `FoldChangeVolcanoPlot.cs` — per-trait resolution loop replacing exclusive matching
- [ ] `SummaryRelativeAbundanceGraphPane.cs` — same per-trait resolution

## Backward Compatibility

Existing XML with `symbol_type="Circle" point_size="normal"` deserializes to non-null values →
first-match-all-traits behavior preserved (all traits resolved by first match; later matches
have no effect since all traits already resolved).

## PR #4148 — agreed follow-up work (Brendan's 2026-06-26 comment)

Branch checked out in **pwiz2** at head `6a3e38bf17`. PR https://github.com/ProteoWizard/pwiz/pull/4148.
Feature is UNRELEASED (not merged to master) so precedence change is back-compat-safe. Two pieces agreed:

### 1. Reverse precedence to LAST-match-wins (per trait)
Brendan expects to define a general rule first, then refine with a more specific rule **below** that
overrides (CSS-cascade model). Currently first-match-wins.
- `DotPlotUtil.ResolvePointFormat` (DotPlotUtil.cs ~236): for color/symbol/size, drop the
  `resolved == null &&` guards and **overwrite** on each matching rule (last match wins); remove the
  early `break`; track the **last** contributing rule index. Rename the tuple element
  `firstRuleIndex` -> `lastRuleIndex` (or `ruleIndex`). `Labeled` stays an order-independent OR
  (false = unset, so a later rule can't un-label). Update the doc comment ("first" -> "last").
- Update callers: `FoldChangeVolcanoPlot.cs` and `SummaryRelativeAbundanceGraphPane.cs` use
  `resolved.Value.firstRuleIndex` in a local tuple and `GroupBy(...).OrderBy(g => g.Min(pf => firstRuleIndex))`.
  Keep `OrderBy(min ...)` ascending — with last-wins that draws higher-priority (later) rules on top.
- Tests: `VerifyTraitComposition` still passes (A=color-only, B=symbol-only set disjoint traits, so
  first/last give the same result). ADD a case with two overlapping rules that BOTH set color and
  assert the LATER rule's color wins. Update the PR description back-compat note to describe last-wins.

### 2. Delete/reorder toolbar on the rules grid
Mirror the existing Skyline control in **Customize Report** (`ChooseColumnsTab` /
`pwiz_tools/Shared/Common/DataBinding/Controls/Editor/ChooseColumnsTab.{cs,Designer.cs}` + `ListViewHelper.cs`):
a vertical button strip beside the list — red **X** delete, blue **up**, blue **down**.
- Add the three buttons next to `regexColorRowGrid1` in `VolcanoPlotFormattingDlg`; operate on the
  `_bindingList` (move selected row up/down, delete selected row). Reuse the same icon resources the
  ChooseColumnsTab buttons use. Enable/disable based on selection + position.
- After reordering, the live preview updates via the existing `_bindingList_ListChanged` -> `_updateGraph`.
- Add a functional test driving the move-up/down/delete on the binding list and asserting order/removal.

Context ran low (8%) before implementation; pick this up fresh from pwiz2.
