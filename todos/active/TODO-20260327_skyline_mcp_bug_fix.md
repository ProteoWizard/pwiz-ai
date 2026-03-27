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
- [x] Replaced with reflection: finds any public property returning `ZedGraphControl`
- [x] Removed unused `using` directives (`Controls.Graphs`, `Controls.Graphs.Calibration`)

### Updated MCP server package
- [x] Rebuilt SkylineAiConnector.zip with fixes
- [x] Updated minimum version requirement in info.properties

## Progress Log

### 2026-03-27 - Discovery and fixes

Found both issues while testing PR #3847 (label layout optimization). Wanted Claude Code to interact directly with a TestRunner-hosted Skyline instance to inspect volcano plot and relative abundance graphs.

**TestRunner fix**: `SkylineConnection.IsSkylineProcess()` checked `process.ProcessName.StartsWith("Skyline")` which excluded TestRunner.exe. Added "TestRunner" as an accepted prefix.

**Graph export fix**: `JsonUiService.TryGetZedGraphControl()` had a switch with 5 explicit types (GraphSummary, GraphChromatogram, GraphSpectrum, GraphFullScan, CalibrationForm). Replaced with reflection that finds any public `ZedGraphControl` property on the form. Automatically supports all current and future graph forms.

Verified: GraphSummary (peak areas, histograms, regressions, relative abundance), GraphSpectrum (library match), GraphChromatogram all continue to work. FoldChangeVolcanoPlot and FoldChangeBarGraph now also work.
