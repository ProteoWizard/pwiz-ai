# ImageComparer MCP Server

A C# MCP server that exposes screenshot diff capabilities to Claude Code, enabling automated review of tutorial screenshot changes.

## Quick Start

```bash
pwsh -Command "& './ai/mcp/ImageComparerMcp/Setup-ImageComparerMcp.ps1'"
```

This builds the project and registers it with Claude Code. Restart Claude Code after running.

## Prerequisites

- **.NET 8.0+ SDK** — [download](https://dotnet.microsoft.com/download)
- **pwiz repository** checked out (default: `C:/proj/pwiz`)

## Source Code

The server source lives in the pwiz repository:

```
pwiz_tools/Skyline/Executables/DevTools/
├── ImageComparer.Core/      # Shared library (netstandard2.0 + net472)
│   ├── ScreenshotDiff.cs    # Pixel comparison algorithm
│   ├── ScreenshotFile.cs    # Tutorial path parsing
│   ├── GitFileHelper.cs     # Git operations
│   └── ScreenshotInfo.cs    # Image metadata
├── ImageComparer.Mcp/       # MCP server (.NET 8.0)
│   ├── Program.cs           # Entry point, stdio transport
│   └── Tools/
│       └── ScreenshotDiffTools.cs  # Tool implementations
└── ImageComparer/            # GUI app (.NET Framework 4.7.2, references Core)
```

ImageComparer.Core is shared between the GUI app and the MCP server via multi-targeting (`net472` + `netstandard2.0`).

## Tools

| Tool | Description |
|------|-------------|
| `list_changed_screenshots` | List screenshots modified vs git HEAD |
| `generate_diff_image` | Generate a diff visualization (highlighted, diff_only, amplified, amplified_diff_only) |
| `generate_diff_report` | Batch generate diffs for all changed screenshots |
| `revert_screenshot` | Revert a screenshot to git HEAD |

## IMPORTANT: Use Forward Slashes

All path arguments **must** use forward slashes:

```
CORRECT:  C:/proj/pwiz/pwiz_tools/Skyline/Documentation/Tutorials
WRONG:    C:\proj\pwiz\pwiz_tools\Skyline\Documentation\Tutorials
```

Backslashes are JSON escape characters and cause silent failures in MCP JSON-RPC deserialization.

## Typical Workflow

1. Run a tutorial test with auto-screenshots:
   ```bash
   pwsh -Command "& './ai/scripts/Skyline/Run-Tests.ps1' -TestName TestAbsoluteQuantificationTutorial -TakeScreenshots"
   ```

2. List what changed:
   ```
   list_changed_screenshots(tutorialsPath="C:/proj/pwiz/pwiz_tools/Skyline/Documentation/Tutorials")
   ```

3. Generate and review diffs:
   ```
   generate_diff_image(screenshotPath="C:/proj/pwiz/.../AbsoluteQuant/en/s-01.png")
   ```

4. Revert unwanted changes:
   ```
   revert_screenshot(screenshotPath="C:/proj/pwiz/.../AbsoluteQuant/en/s-01.png")
   ```

## Unregister

```bash
pwsh -Command "& './ai/mcp/ImageComparerMcp/Setup-ImageComparerMcp.ps1' -Unregister"
```

## Documentation

- [ai/docs/mcp/image-comparer.md](../../docs/mcp/image-comparer.md) — Full architecture and C# MCP lessons learned
- [ai/docs/mcp/development-guide.md](../../docs/mcp/development-guide.md) — General MCP development patterns
