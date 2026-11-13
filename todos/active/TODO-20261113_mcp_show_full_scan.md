# TODO-20261113_mcp_show_full_scan.md

## Branch Information
- **Branch**: `Skyline/work/20261113_mcp_show_full_scan`
- **Base**: `master`
- **Created**: 2026-11-13
- **Status**: Draft PR
- **GitHub Issue**: (none)
- **Module**: `skyline`
- **PR**: [#5031](https://github.com/ProteoWizard/pwiz/pull/5031) (draft); screenshots in nickshulman/pr-assets `pwiz/5031-show-full-scan`
- **Checkout**: `I:\git_i\sky_clicktobringupfullscangraph`

## Objective

Add an MCP tool, requested by Brendan, that brings up the Full-Scan graph for a retention time:
`skyline_show_full_scan(retentionTime, replicateName?, transitionLocator?)`.

- Replicate defaults to the active one.
- With a transition: select it, put the chromatogram selection circle on its curve, zoom the
  Full-Scan graph to it.
- Without one: circle on the transition most intense at that time, graph unzoomed, but the
  zoom (magnifier) button zooms to that transition.

"Circle" = the selected-scan marker GraphChromatogram draws (FULLSCAN_SELECTED_INDEX), not the
mouse tracking dot.

## Done

- [x] `GraphChromatogram.ShowFullScan` picks the curve and fires the same event a click fires
- [x] `JsonUiService.PrepareFullScan` / `ShowFullScan`, `JsonToolServer.ShowFullScan`,
      `IJsonToolService`, client, `SkylineConnection`, MCP `skyline_show_full_scan`
- [x] Driven live over MCP (Release build, TargetedMSMSMzml TOF PRM data, 2 replicates):
      default, zoom button, transition + replicate, error cases
- [x] CodeInspection passes

## Open questions (for Brendan)

- The tool sets the magnifier (a persisted setting, AutoZoomFullScanGraph) every call. OK?
- A given transition is selected in the Targets tree. Alternative: require it to be displayed.

## Remaining

- [ ] Settle the API shape with Brendan
- [ ] `/code-review medium` before marking ready
- [ ] JsonToolServerTest coverage, if wanted once the shape is settled
