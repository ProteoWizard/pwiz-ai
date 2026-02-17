# ImageComparer MCP Server for Claude Code Screenshot Review

## Branch Information
- **Branch**: `Skyline/work/20260216_imagecomparer_mcp`
- **Base**: `master`
- **Created**: 2026-02-16
- **Status**: PR open, awaiting merge
- **GitHub Issue**: (pending)
- **PR**: [#3989](https://github.com/ProteoWizard/pwiz/pull/3989)

## Objective

Build a C# MCP server that exposes ImageComparer's screenshot diff capabilities to Claude Code, enabling autonomous review of tutorial screenshot changes after auto-screenshot test runs.

Also a proof-of-concept for C# MCP servers in the Skyline ecosystem.

## Architecture

```
ai/mcp/ImageComparerMcp/              Setup script + README (committed)
    └── Setup-ImageComparerMcp.ps1    Builds and registers with Claude Code

pwiz_tools/Skyline/Executables/DevTools/
├── ImageComparer.Core/               Shared library (net472 + netstandard2.0)
│   ├── ScreenshotDiff.cs             Pixel comparison + visualization
│   ├── ScreenshotFile.cs             Tutorial path parsing
│   ├── GitFileHelper.cs              Git operations (stdin isolation for MCP)
│   └── ScreenshotInfo.cs             Image metadata classes
├── ImageComparer.Mcp/                MCP server (.NET 8.0-windows)
│   ├── Program.cs                    Entry point (logging cleared, stdio transport)
│   └── Tools/ScreenshotDiffTools.cs  4 tools + NormalizePath for forward slashes
└── ImageComparer/                    GUI app (refactored to use Core)
    ├── ScreenshotDiffExtensions.cs   ShowBinaryDiff extension method
    └── ImageComparerWindow.cs        Added using ImageComparer.Core
```

## Tasks

### Phase 1: Extract ImageComparer.Core DLL — COMPLETE
- [x] Multi-target `net472;netstandard2.0` class library
- [x] Extracted ScreenshotDiff, ScreenshotFile, ScreenshotInfo, GitFileHelper
- [x] Refactored ImageComparer GUI to use Core DLL
- [x] ShowBinaryDiff as extension method (UI-dependent code stays in GUI)

### Phase 2: ImageComparer.Mcp Server — COMPLETE
- [x] .NET 8.0-windows project with ModelContextProtocol 0.8.0-preview.1
- [x] 4 tools: list_changed_screenshots, generate_diff_image, generate_diff_report, revert_screenshot
- [x] All build with zero warnings, zero errors

### Phase 2.5: Debugging & Hardening — COMPLETE
- [x] Fixed stdout logging corruption (`builder.Logging.ClearProviders()`)
- [x] Fixed child process stdin inheritance deadlock (`RedirectStandardInput + Close`)
- [x] Fixed JSON backslash path issue (forward slashes at API boundary, `NormalizePath` at entry)
- [x] Removed expensive pixel diffing from list operation (git status only)
- [x] Documented all three C# MCP pitfalls in `ai/docs/mcp/development-guide.md`

### Phase 3: Integration & Testing — COMPLETE
- [x] Added `-TakeScreenshots` parameter to Run-Tests.ps1 (pause=-3, implies -ShowUI)
- [x] MCP server registered and responding via Claude Code
- [x] `list_changed_screenshots` — all 16 AbsoluteQuant files found
- [x] `generate_diff_image` — all modes tested (highlighted, diff_only), color/alpha params work
- [x] `generate_diff_report` — all 16 diffs generated to correct path
- [x] `revert_screenshot` — s-01 reverted, count dropped from 16 to 15
- [x] Fixed diff_only checkerboard artifact (pre-blend highlight color with white background)
- [x] Fixed `GetAiTmpFolder` path (save to `C:\proj\ai\.tmp` not `C:\proj\pwiz\ai\.tmp`)
- [x] Updated UI `SaveDiffImage` to save current view mode (respects diff-only/amplify settings)
- [x] Updated `ImageComparer.sln` to include all 3 projects (GUI, Core, Mcp)
- [x] GUI builds and runs correctly with Core DLL refactoring
- [x] Created `ai/mcp/ImageComparerMcp/` with README.md and Setup-ImageComparerMcp.ps1
- [x] Created `ai/docs/mcp/image-comparer.md` — full documentation
- [x] Updated `ai/docs/mcp/development-guide.md` — C# MCP section
- [x] Updated `ai/docs/mcp/README.md` — server table

### Deferred
- [ ] Refactor TestUtil `ScreenshotInfo.cs` to use Core DLL (not blocking MCP)

## Key Lessons Learned (C# MCP Servers)

1. **Clear logging providers** — .NET hosting writes info logs to stdout, corrupting JSON-RPC
2. **Isolate child stdin** — Subprocess inherits MCP stdin, causing deadlocks. `RedirectStandardInput=true` + `Close()`
3. **Forward-slash paths** — JSON backslash escaping makes `C:\path` invalid JSON. Normalize at API boundary.

See `ai/docs/mcp/development-guide.md` → "C# MCP Servers (.NET)" for full guide.

## Progress Log

### 2026-02-16 (session 2) — PR created, Copilot review addressed

Committed pwiz-ai docs/scripts to master. Committed pwiz code on branch, pushed, created PR #3989. Copilot reviewed with 12 comments — fixed 5 (BlendWithWhite DRY helper, hex validation, commented-out case, preview package comment, alpha2 rename), dismissed 7 with explanations. Strengthened no-amend-after-review guidance in version-control skill and guide. Wrote handoff file for next session: review of Skyline MCP server TODO.

### 2026-02-16 (session 1) — All phases complete, ready for commit

Built ImageComparer.Core (multi-target DLL) and ImageComparer.Mcp (MCP server with 4 tools). Discovered and fixed three critical C# MCP pitfalls: stdout logging, stdin inheritance, JSON path escaping. Added `-TakeScreenshots` to Run-Tests.ps1. Ran AbsoluteQuant tutorial generating 16 changed screenshots. All 5 MCP tools tested end-to-end via Claude Code. Fixed diff_only checkerboard artifact (alpha blending), GetAiTmpFolder path resolution, and UI SaveDiffImage to respect current view mode. Updated ImageComparer.sln with all 3 projects. GUI verified working with Core DLL refactoring.

## Related

- `ai/docs/mcp/image-comparer.md` — Full MCP server documentation
- `ai/docs/mcp/development-guide.md` — C# MCP section with pitfall guide
- `ai/mcp/ImageComparerMcp/README.md` — Setup instructions
- `ai/todos/backlog/TODO-automated_screenshot_review.md` — Original vision doc
