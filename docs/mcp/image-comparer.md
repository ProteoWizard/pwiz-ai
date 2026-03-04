# ImageComparer MCP Server

Compare tutorial screenshots against git HEAD to review visual changes. Built as a C# MCP server — a proof-of-concept for future Skyline MCP integrations (e.g., SkylineTool named-pipe IPC).

## Problem Statement

After running a tutorial test in auto-screenshot mode, developers need to review visual changes across many screenshots. The existing ImageComparer GUI app works for manual review, but Claude Code needs programmatic access to:
- List which screenshots changed
- Generate diff images highlighting pixel differences
- Review changes autonomously and flag issues

## Tools

| Tool | Purpose |
|------|---------|
| `list_changed_screenshots` | Scan tutorials folder for screenshots modified vs git HEAD |
| `generate_diff_image` | Generate a diff visualization for one screenshot |
| `generate_diff_report` | Generate diffs for all changed screenshots in batch |
| `revert_screenshot` | Revert a screenshot to its git HEAD version |

### Diff Modes

`generate_diff_image` and `generate_diff_report` support four visualization modes:

| Mode | Description |
|------|-------------|
| `highlighted` | Changed pixels blended (semi-transparent red) onto the new image |
| `diff_only` | Changed pixels on white background |
| `amplified` | Expanded diff regions on the new image (radius 1-10) |
| `amplified_diff_only` | Expanded diff regions on white background |

## CRITICAL: Path Format

**Always use forward slashes in paths passed to this server.**

```
CORRECT:  C:/proj/pwiz/pwiz_tools/Skyline/Documentation/Tutorials
WRONG:    C:\proj\pwiz\pwiz_tools\Skyline\Documentation\Tutorials
```

**Why:** MCP uses JSON-RPC over stdio. In JSON, backslashes are escape characters (`\n`, `\t`, etc.). Unescaped Windows paths like `C:\proj` contain invalid JSON escape sequences (`\p`), causing silent deserialization failures in the MCP SDK. Forward slashes work natively on Windows and avoid this entirely.

## Installation

### Prerequisites

- .NET 8.0 SDK installed
- ImageComparer.Core and ImageComparer.Mcp projects built

### Build

```bash
cd pwiz_tools/Skyline/Executables/DevTools/ImageComparer.Mcp
dotnet build
```

The server exe is at:
```
pwiz_tools/Skyline/Executables/DevTools/ImageComparer.Mcp/bin/Debug/net8.0-windows/win-x64/ImageComparer.Mcp.exe
```

### Configure Claude Code

```bash
claude mcp add imagecomparer -- C:/proj/pwiz/pwiz_tools/Skyline/Executables/DevTools/ImageComparer.Mcp/bin/Debug/net8.0-windows/win-x64/ImageComparer.Mcp.exe
```

## Typical Workflow

1. **Run a tutorial test with auto-screenshots:**
   ```bash
   pwsh -Command "& './ai/scripts/Skyline/Run-Tests.ps1' -TestName TestAbsoluteQuantificationTutorial -TakeScreenshots"
   ```

2. **List changed screenshots:**
   ```
   list_changed_screenshots(tutorialsPath="C:/proj/pwiz/pwiz_tools/Skyline/Documentation/Tutorials")
   ```

3. **Generate diff images for review:**
   ```
   generate_diff_image(screenshotPath="C:/proj/pwiz/pwiz_tools/Skyline/Documentation/Tutorials/AbsoluteQuant/en/s-01.png")
   ```
   Diff images are saved to `ai/.tmp/` with descriptive filenames including pixel count.

4. **Review the diff image:** Claude reads the saved PNG to visually inspect changes.

5. **Revert unwanted changes:**
   ```
   revert_screenshot(screenshotPath="C:/proj/pwiz/pwiz_tools/Skyline/Documentation/Tutorials/AbsoluteQuant/en/s-01.png")
   ```

## Architecture

```
Claude Code
    │
    └── MCP Protocol (stdio, JSON-RPC)
            │
            └── ImageComparer.Mcp (.NET 8.0, ModelContextProtocol SDK)
                    │
                    └── ImageComparer.Core (netstandard2.0 + net472)
                            │
                            ├── ScreenshotDiff — pixel comparison + visualization
                            ├── ScreenshotFile — tutorial path parsing
                            ├── GitFileHelper — git show/status/checkout operations
                            └── ScreenshotInfo — image metadata
```

### Key Design Decisions

- **Multi-target Core DLL** (`net472` + `netstandard2.0`): Shared between the .NET Framework 4.7.2 ImageComparer GUI and the .NET 8.0 MCP server
- **stdin isolation**: Child `git` processes use `RedirectStandardInput=true` + immediate close to prevent inheriting the MCP server's stdin (which would cause deadlocks)
- **Logging disabled on stdout**: `builder.Logging.ClearProviders()` prevents .NET hosting logs from corrupting the JSON-RPC transport
- **No pixel diffing in list**: `list_changed_screenshots` only runs `git status` (fast); pixel comparison happens on demand via `generate_diff_image`

## C# MCP Server Notes

Lessons learned for building MCP servers in C#:

1. **Clear all logging providers** — `Host.CreateApplicationBuilder` adds console logging to stdout by default, which corrupts the JSON-RPC transport
2. **Isolate child process stdin** — Any subprocess (git, etc.) will inherit the MCP server's stdin. Set `RedirectStandardInput = true` and close it immediately
3. **Forward slashes for paths** — JSON backslash escaping makes Windows paths problematic; accept forward slashes and normalize internally if needed
4. **`[JsonPropertyName]` on POCOs** — `System.Text.Json` is case-sensitive by default; snake_case JSON keys won't match PascalCase properties without explicit attributes
5. **NuGet package**: `ModelContextProtocol` version 0.8.0-preview.1 (Anthropic + Microsoft joint effort)

## Source Files

| File | Project | Purpose |
|------|---------|---------|
| `ImageComparer.Mcp/Program.cs` | MCP server | Entry point, stdio transport setup |
| `ImageComparer.Mcp/Tools/ScreenshotDiffTools.cs` | MCP server | Tool implementations |
| `ImageComparer.Core/ScreenshotDiff.cs` | Core DLL | Pixel comparison algorithm |
| `ImageComparer.Core/ScreenshotFile.cs` | Core DLL | Tutorial screenshot path parsing |
| `ImageComparer.Core/GitFileHelper.cs` | Core DLL | Git operations (show, status, checkout) |
| `ImageComparer.Core/ScreenshotInfo.cs` | Core DLL | Image metadata classes |

All source under: `pwiz_tools/Skyline/Executables/DevTools/`
