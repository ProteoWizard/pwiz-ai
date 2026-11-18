# TODO-20261113_mcp_show_full_scan.md

## Branch Information
- **Branch**: `Skyline/work/20261113_mcp_show_full_scan`
- **Base**: `master`
- **Created**: 2026-11-13
- **Status**: Completed
- **GitHub Issue**: (none)
- **Module**: `skyline`
- **PR**: [#5031](https://github.com/ProteoWizard/pwiz/pull/5031) (merged 2026-11-18); screenshots in nickshulman/pr-assets `pwiz/5031-show-full-scan`
- **Checkout**: `I:\git_i\sky_clicktobringupfullscangraph`

## Objective

Add an MCP tool, requested by Brendan, that brings up the Full-Scan graph for a retention time:
`skyline_show_full_scan(retentionTime, replicateName?, transitionLocator?)`.

- Replicate defaults to the active one.
- With a transition: select it, put the chromatogram selection circle on its curve, zoom the
  Full-Scan graph to it.
- Without one: selection left alone, circle on the transition most intense at that time, graph
  zoomed to it (changed 2026-11-18; the first version left it unzoomed).

"Circle" = the selected-scan marker GraphChromatogram draws (FULLSCAN_SELECTED_INDEX), not the
mouse tracking dot.

## Done

- [x] `GraphChromatogram.ShowFullScan` picks the curve and fires the same event a click fires
- [x] `JsonUiService.PrepareFullScan` / `ShowFullScan`, `JsonToolServer.ShowFullScan`,
      `IJsonToolService`, client, `SkylineConnection`, MCP `skyline_show_full_scan`
- [x] Driven live over MCP (Release build, TargetedMSMSMzml TOF PRM data, 2 replicates):
      default, zoom button, transition + replicate, error cases
- [x] CodeInspection passes

## Decisions (Brendan, 2026-11-18)

- The tool no longer turns the persisted Zoom to Selection setting off: both forms zoom to the
  transition the circle is on, matching a click with the default setting (MS1Filtering s-25/s-26).
- A given transition is selected in the Targets tree (kept: it makes the zoom target right).
- No long blocking: wait at most 10 s for the spectrum, then report what is shown or that it is
  still loading - never return as if done when it is not.

## Remaining

- [x] Settle the API shape with Brendan
- [x] `/code-review medium`: fixed the tool returning before the spectrum loaded; dropped the rest
- [x] Test coverage: `ShowFullScanJsonToolTest` (new; a focused functional test rather than
      JsonToolServerTest)

## Progress log

### 2026-11-18 - Finished by Brendan's session for merge

Tested live over the MCP at PauseTest() pauses in MS1Filtering, IMS Filtering (Agilent) and Small
Molecule IMS Libraries; see the PR's approving review for the details. Commits on the branch:
- `98282d8b52` Default call zooms; fixed IndexOutOfRange on dense (IMS) chromatograms
  (`curve.Points` is screen-binned once drawn - read `ChromGraphItem.Points`); waits up to 10 s
  and reports what is shown or "still loading"; `FireClickedChromatogram` returns bool; Full-Scan
  wrench tooltip fixed (resx keyed `propertyBtn`, designer `propertiesBtn`) as "Spectrum
  Properties"; `ShowFullScanJsonToolTest`
- `8520ce1924` merge of master; `a12fb4ad60` SkylineAiConnector.zip 26.1.2.322 +
  EXPECTED_ZIP_VERSION
Follow-ups filed for Nick: #5049 property sheets, #5050 toolbar combos, #5051 docking (overlaps
#4671's window verbs), #5052 silent timeouts. Design guide draft:
`ai/docs/skyline-mcp-design-guide.md` (for Brendan and Nick to review).

### 2026-11-18 - Merged

PR #5031 merged as commit 1d51837d27. Shipped `skyline_show_full_scan`: shows the Full-Scan graph
for the scan at a measured retention time through the chromatogram click path, with the selection
circle on the given transition or the one most intense at that time, zoomed to it; returns within
10 s with a description of what is shown or "still loading, read again shortly"; and the Full-Scan
properties button got its tooltip back ("Spectrum Properties"). SkylineAiConnector.zip 26.1.2.322.
All 17 checks green, including the full Skyline Windows run. Follow-ups filed for Nick: #5049
(property sheets as text), #5050 (toolbar combos and item state), #5051 (docking; overlaps #4671),
#5052 (silent timeouts), #5053 (MCP vs external-tool callers). Design guide:
`ai/docs/skyline-mcp-design-guide.md` (awaiting Nick's review).
