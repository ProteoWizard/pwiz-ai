# Skyline MCP server bug fixes from real-world testing

## Branch Information
- **Branch**: `Skyline/work/20260327_skyline_mcp_bug_fix`
- **Base**: `master`
- **Created**: 2026-03-27
- **Status**: In Progress
- **PR**: (pending)

## Objective

Fix bugs found during real-world testing of the Skyline MCP server (first public release). Testing involved using Claude Code to interact with a Skyline instance running inside TestRunner.exe to review a visual feature PR (label layout optimization).

## Tasks

### MCP server cannot connect to Skyline inside TestRunner
- [x] `IsSkylineProcess()` rejects processes not named "Skyline*"
- [x] TestRunner-hosted Skyline writes connection file, but MCP server deletes it as stale
- [x] Added "TestRunner" to accepted process name prefixes in `SkylineConnection.cs`

### Graph image export fails for group comparison plots
- [x] `FoldChangeVolcanoPlot` and `FoldChangeBarGraph` report `HasGraph=False`
- [x] `TryGetZedGraphControl()` had hardcoded whitelist of 5 graph form types
- [x] Replaced with reflection: finds any public property assignable to `ZedGraphControl`
- [x] Used `IsAssignableFrom` to handle subclasses like `MSGraphControl` (chromatograms, spectra)
- [x] Removed unused `using` directives (`Controls.Graphs`, `Controls.Graphs.Calibration`)

### Updated MCP server package
- [x] Rebuilt SkylineAiConnector.zip with fixes
- [x] Updated minimum version requirement in info.properties

## Progress Log

### 2026-03-27 - Discovery and fixes

Found both issues while testing PR #3847 (label layout optimization). Wanted Claude Code to interact directly with a TestRunner-hosted Skyline instance to inspect volcano plot and relative abundance graphs.

**TestRunner fix**: `SkylineConnection.IsSkylineProcess()` checked `process.ProcessName.StartsWith("Skyline")` which excluded TestRunner.exe. Added "TestRunner" as an accepted prefix.

**Graph export fix**: `JsonUiService.TryGetZedGraphControl()` had a switch with 5 explicit types (GraphSummary, GraphChromatogram, GraphSpectrum, GraphFullScan, CalibrationForm). Replaced with reflection that finds any public `ZedGraphControl` property on the form. Automatically supports all current and future graph forms.

Initial reflection used exact type match (`== typeof(ZedGraphControl)`), which broke chromatograms and spectra because their properties return `MSGraphControl` (a subclass). Fixed with `IsAssignableFrom`.

**Verified graph types** (all via `skyline_get_graph_image`):
- GraphSummary: peak areas (replicate comparison, relative abundance, histogram), retention times (replicate comparison, scheduling, score-to-run regression), detection replicates
- GraphChromatogram: chromatogram replicates
- GraphSpectrum: library match
- GraphFullScan: full scan (ion mobility heatmap)
- FoldChangeVolcanoPlot: volcano plot (NEW - previously failed)
- FoldChangeBarGraph: fold change bar graph (NEW - previously failed)

## Future Enhancements

- **EMF/vector export**: ZedGraph has `PaneBase.GetMetafile()` and `SaveEmfFile()` — could extend `skyline_get_graph_image` to support `.emf` output for vector graphics
- **Graph data for group comparison plots**: `skyline_get_graph_data` support for volcano plot and bar graph
- **Non-DockableFormEx graphs**: Some dialogs contain ZedGraph controls (e.g., `AllChromatogramsGraph` for import progress, `ExportMethodScheduleGraph` for method scheduling) but inherit from `FormEx` rather than `DockableFormEx`, so they are not scanned by `TryGetZedGraphControl`. Could be extended if needed, but these are transient dialogs not typically used for analysis.
