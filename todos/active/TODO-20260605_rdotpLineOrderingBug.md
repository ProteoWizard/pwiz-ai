# TODO-20260605_rdotpLineOrderingBug.md

## Branch Information
- **Branch**: `Skyline/work/20260605_rdotpLineOrderingBug`
- **Base**: `master`
- **Repo**: `pwiz2`
- **Created**: 2026-06-05
- **Status**: In Progress
- **GitHub Issue**: (none - from support thread 75064)
- **PR**: ProteoWizard/pwiz#4279

## Bug Report

skyline.ms support thread 75064 - "rdotp order in peak area plot"
(https://skyline.ms/home/support/announcements-thread.view?rowId=75064),
saved to `ai/.tmp/support-thread-75064.md`.

User (Shimin): peak-area replicate plot with **Normalized To: Heavy, Show Dot
Product: Line**. Changing the replicate **order** away from "Document" reorders
the bars but the **rdotp line does not follow** - it keeps document order.

Nick (reply): also when **Group By** is chosen, the bars aggregate into fewer
columns but the dot-product line still shows the original per-replicate rdotp
values in document order (does not aggregate/reorder to match the grouped bars).

## Root Cause

`AreaReplicateGraphPane.AreaGraphData.GetDotProductResults` (in
`pwiz_tools/Skyline/Controls/Graphs/AreaReplicateGraphPane.cs`).

The dot-product line data is built by iterating `ReplicateGroups` (display
positions) and calling `GetDotProductResults(nodeGroup, replicateGroupIndex)`.
Inside that method:

- **library / isotope_dist** path maps the position correctly:
  `ReplicateGroups[indexResult].ReplicateIndexes` -> actual replicate indexes,
  then averages. So idotp/dotp lines already follow ordering and grouping.
- **ratio_to_label (rdotp / "Normalized To: Heavy")** path does NOT: it calls
  `nodeGroup.GetChromInfoEntry(indexResult)` using the display-position index
  directly as a replicate index. In document order with no grouping the two
  coincide, so it looks correct; once replicates are reordered or grouped the
  index points at the wrong replicate - exactly the reported symptom (and Nick's
  grouping note).

Only the rdotp line is affected; library/isotope dotp lines are correct.

## Fix Plan

Unify `GetDotProductResults` so all three expected-value types resolve the
display position through `ReplicateGroups[indexResult].ReplicateIndexes` (with
the empty -> `{-1}` fallback already used by the library/isotope path) and
average across the group's replicates. Extract a small
`GetRatioDotProduct(nodeGroup, replicateIndex)` helper for the per-replicate
rdotp value (the existing ratio_to_label body, but indexed by an actual
replicate index). This fixes both the ordering and the grouping facets in one
change and keeps the three paths consistent.

## Tasks

- [x] Reproduce: extended `TestPeakAreaDotpGraph` (Heavy/rdotp scenario) to add a
      numeric `SortKey` replicate annotation that reverses the order, order by it,
      and re-verify via the position-aware `VerifyDotpLine`. Confirmed it FAILED on
      current code (Expected 0.62 for A1, Actual 0.53 = D2's value at A1's position).
- [x] Fix `GetDotProductResults` ratio_to_label path to map through
      `ReplicateGroups[indexResult].ReplicateIndexes` and average (mirrors the
      library/isotope path). Default (document-order, ungrouped) behavior preserved
      since each group is then a singleton.
- [x] Confirmed the reproduction passes; full `TestPeakAreaDotpGraph` green.
- [x] Added a Group By assertion (Nick's facet): adds a `PairGroup` text annotation
      pairing the four replicates into two groups, groups by it, and verifies the
      rdotp line shows each group's mean (expected means computed from the ungrouped
      line so display rounding matches exactly). Exercises the multi-replicate
      averaging path. Both facets pass.
- [x] QuickInspection before push - clean for my files (only the pre-existing
      `ExportMethodDlg.cs` ambiguous-reference errors from the master merge remain).
- [x] Committed (`b283594d24`), pushed, PR #4279 opened against master.
- [ ] Post-open review chain: Copilot auto-review, then `/pw-respond` / `/pw-self-review`.

## Session Log

### 2026-06-09 - Reproduced and fixed; both facets green

Root cause: `AreaReplicateGraphPane.AreaGraphData.GetDotProductResults` rdotp
(`ratio_to_label`) path indexed `nodeGroup.GetChromInfoEntry(indexResult)` by the
display position instead of mapping through `ReplicateGroups[indexResult].ReplicateIndexes`
(which the library/isotope path already did). Surgical fix: map through ReplicateIndexes
and average (mirrors the sibling path); document-order/ungrouped behavior preserved
(singleton groups). Extended `TestPeakAreaDotpGraph` with deterministic ordering
(SortKey number annotation reversing order) and grouping (PairGroup text annotation)
reproductions; confirmed red before fix (Expected 0.62/A1, Actual 0.53/D2), green after.
Build + `PeakAreaDotpGraphTest` pass. Not yet committed.

## Notes / Decisions

- `GetDotProductResults` carries `[MethodImpl(MethodImplOptions.NoOptimization)]`
  - preserve it through the refactor.
- Working tree carries unrelated WIP (staged `Skyline.csproj`, untracked
  `build_skyline_64.bat`, an MSFileReader manifest, a stray
  `pwiz_tools/Skyline/System.IO.IOException` file) - not part of this fix; leave
  alone and do not stage.
