# TODO-20261118_mcp_propertygrid_expand.md

## Branch Information
- **Branch**: `Skyline/work/20261118_mcp_propertygrid_expand` (checkout `C:\Dev\MCP`)
- **Base**: `master`
- **Created**: 2026-11-18
- **Module**: `skyline`
- **Status**: In progress
- **GitHub Issue**: partly addresses #5049 (assigned to Nick)
- **PR**: https://github.com/ProteoWizard/pwiz/pull/5056 (opened 2026-11-18)

## Objective

Let the AI Connector (Skyline MCP) expand and collapse items of a property sheet (`PropertyGrid`),
so a session can open the Full-Scan graph's "Other Metadata" node for a screenshot without a
person clicking it.

## Context

Found while capturing the #4422 demo deck (2026-11-18): the Other Metadata node of the Full-Scan
Spectrum Properties pane could only be expanded by hand. `UiElement.CreateElement` had no case for
`PropertyGrid` (a `ContainerControl`, not a `UserControl`), so it fell to `default` and was not an
element at all.

Scope kept to listing the grid and expand/collapse. #5049's other half (reading a property sheet's
values as text through `get_value`) is left for Nick, who owns that issue.

## Done
- `PropertyGridElement` in `ToolsUI/UiElement.cs`: implements `IExpandCollapseElement`; path of item
  labels or indexes, categories transparent; expanding also expands every ancestor so the item is in
  view; clear `LlmInstruction` errors for an empty sheet, a non-expandable item, no match (lists the
  available names).
- `CreateElement` case for `PropertyGrid`, so the grid is listed by `get_children` on `MsGraphExtension`.
- `TreeViewElement.ToTreePath` made internal and shared.
- `UiActions.Expand`/`Collapse` descriptions mention property sheets (`get_actions` reports them).
- `FullScanPropertiesTest` now derives from `McpConnectorTest` and expands/collapses Other Metadata
  through the connector.

## Remaining
- ReSharper gate (`tcinspect.ps1`) before the PR.
- Decide whether to update the MCP server's `skyline_perform_action` description (needs the
  connector ZIP rebuilt and `EXPECTED_ZIP_VERSION` bumped). `get_actions` already reports the new
  descriptions, so this is optional.
- Try it live over the MCP on a paused Full-Scan test (design guide section 7).
- Push the branch and open the PR (awaiting approval).

## Progress Log

### 2026-11-18 - Started
Branch created from master in a new checkout `C:\Dev\MCP` (local clone of SmartCV, origin reset to
GitHub, upstream unset so a bare push cannot target master).

Committed `01a774d77e` (local, not pushed). Full Skyline build clean (0 warnings, 0 errors).
`TestFullScanProperties`, `TestSetItemMcpConnector` and CodeInspection pass.

`/code-review medium`: 10 findings; fixed 5 in `199446f198` (sheet toolbar stayed reachable - was a
regression; category headings nameable; bare-string path; leaf mid-path error; reuse
`ListItems.BestMatch`). Dropped 5 as consistent with TreeViewElement (first match wins, collapse
expands intermediates) or not worth it (RootItem duplicate, ToTreePath location, test label source).
Pushed and opened #5056 with tcinspect still running.
