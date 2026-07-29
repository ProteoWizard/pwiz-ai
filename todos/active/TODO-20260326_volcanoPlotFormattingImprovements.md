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

### 1. Reverse precedence to LAST-match-wins (per trait) — DONE (built + tests pass)
Implemented in pwiz2 on `_v2`. `DotPlotUtil.ResolvePointFormat` now overwrites per matching rule
(last wins), no early break, tracks `lastRuleIndex` (renamed from `firstRuleIndex`); `Labeled` stays
an OR; doc comment updated. Both callers updated (tuple element + `OrderBy(Min lastRuleIndex)` kept
ascending so later/higher-priority rules draw on top). Added `VerifyLastMatchWins` test (two
overlapping color rules; later Magenta wins over earlier Cyan). `TestVolcanoPlotFormatting` +
siblings pass; `VerifyTraitComposition` still passes (disjoint traits → first/last identical).
STILL TODO: update the PR #4148 description back-compat note to describe last-wins.

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

### 2. Delete/reorder toolbar on the rules grid — DONE (built + tests pass)
Implemented in pwiz2 on `_v2`, modeled on `MetadataRuleSetEditor` (a DataGridView + binding-list +
vertical toolstrip — closer analog than the ListView-based ChooseColumnsTab). Added a vertical
`toolStripFormatting` (anchored Top,Right) beside `regexColorRowGrid1` with `btnDeleteRule` (red X,
`Resources.Delete`), `btnMoveRuleUp` (`up_pro32`), `btnMoveRuleDown` (`down_pro32`). Grid width shrunk
638->606 in the .resx to make room. Buttons operate on `_bindingList` via `ListViewHelper.MoveItems`/
`IsMoveEnabled`/`MoveSelectedIndexes`; reorder/delete rebuild the list with one `ResetBindings()` so the
live preview refreshes through the existing `_bindingList_ListChanged` -> `_updateGraph`. Enablement
updates on grid selection/cell change and on list change. Tooltips/accessible names are 3 new
`GroupComparisonStrings` entries (Delete rule / Move rule up / Move rule down) set in the ctor.
Added functional test `VerifyRuleToolbar` (boundary enablement + move up/down + delete, asserted by
reference against the added rules) — passes. NOTE: toolstrip geometry/config is set in Designer.cs code
(not the .resx); tooltips localize via GroupComparisonStrings. Visual layout NOT yet eyeballed in the
running app, and QuickInspection not yet run (do both before push per workflow).

Mirror the existing Skyline control in **Customize Report** (`ChooseColumnsTab` /
`pwiz_tools/Shared/Common/DataBinding/Controls/Editor/ChooseColumnsTab.{cs,Designer.cs}` + `ListViewHelper.cs`):
a vertical button strip beside the list — red **X** delete, blue **up**, blue **down**.
- Add the three buttons next to `regexColorRowGrid1` in `VolcanoPlotFormattingDlg`; operate on the
  `_bindingList` (move selected row up/down, delete selected row). Reuse the same icon resources the
  ChooseColumnsTab buttons use. Enable/disable based on selection + position.
- After reordering, the live preview updates via the existing `_bindingList_ListChanged` -> `_updateGraph`.
- Add a functional test driving the move-up/down/delete on the binding list and asserting order/removal.

Context ran low (8%) before implementation; pick this up fresh from pwiz2.

## 2026-06-26 update — both follow-ups DONE, pushed, PR updated

Both agreed follow-ups (last-match-wins precedence + delete/reorder toolbar) implemented in pwiz2 on
`_v2`, built, and covered by passing functional tests (VerifyLastMatchWins, VerifyRuleToolbar).
Committed as `d98f7fcb5f` and pushed. PR #4148 description rewritten to describe last-match-wins and
the toolbar, with a test plan. Visual layout confirmed by Rita.

### TeamCity on d98f7fcb5f — 1 real regression, fixed in dee09812c1

Pulled via the (now-registered) TeamCity MCP. 3 red builds, all tracing to ONE real failure:
- **bt209** (Skyline tests): `PeakAreaRelativeAbundanceGraphTest.TestFormattingDialog` — a PRE-EXISTING
  test that implicitly asserted FIRST-match precedence. It adds QE->Diamond then GQ->Triangle rules;
  one peptide matches BOTH, so last-match-wins moved it Diamond->Triangle. Updated expected counts
  (diamonds 2->1 / triangles 2->3 lists-excluded; 4->3 / 3->4 lists-included). Now passes locally.
- **Docker (Wine)**: red only via snapshot dependency on bt209 — cascades green once bt209 passes.
- **Perf** `TestAlphaPeptDeepBuildLibrary`: infra (python get-pip.py install failed), NOT ours.
LESSON: `DotPlotUtil.ResolvePointFormat` is shared by the volcano AND relative-abundance panes; changing
its precedence needs BOTH VolcanoPlotFormattingTest and PeakAreaRelativeAbundanceGraphTest run locally.

### Self-review (fresh-context agent) on the PR — resolved in 0bb04bdb11

Agent flagged 3 issues:
- [MEDIUM] draw-order: the `OrderBy(Min(lastRuleIndex))` ascending + my comment disagreed. Investigated:
  ZedGraph CurveList.Draw paints lower indices on top; AddPoints appends. Tried OrderByDescending to put
  higher-priority (last) rules on top, but that REVERSES matched-curve order, which `AssertVolcanoPlotCorrect`
  (VolcanoPlotFormattingTest) deliberately pins to rule-list order -> test failed (Expected Blue, Actual Red).
  DECISION (Rita): keep ascending/rule-list order, fix ONLY the misleading comment (no behavior change, no
  test churn). Done in 0bb04bdb11 (comment-only). Curve order = rule-list order; earlier rules drawn on top.
- [LOW] selected-point symbol from selectedPoints[0] only — DISMISSED (documented, sound tradeoff: single
  index-0 curve keeps cutoff-line/MatchedPointsStartIndex math valid).
- [LOW] _symbolDropdownFont disposed in OnHandleDestroyed — DEFERRED (pre-existing feature code; modal dialog
  doesn't recreate handle).
Pre-push gate now run per the team rule: CodeInspection test PASSED + VolcanoPlotFormattingTest +
PeakAreaRelativeAbundanceGraphTest PASSED. (Saved memory: run CodeInspection test before push, not just QuickInspection.)

REMAINING:
- Confirm TeamCity goes green on 0bb04bdb11 (bt209 + Docker; perf may stay red on the unrelated infra issue).
- Optional billed extra rigor: Copilot review / ultrareview. Then request human review.
- Pre-existing inspection noise: QuickInspection flagged 3 ReSharper "ambiguous reference
  textTemplateFile.ToolTip" errors in `FileUI/ExportMethodDlg.cs` — NOT touched by this work (came in
  via an earlier commit/merge on the branch). Out of scope here, but watch for TeamCity CodeInspection.
