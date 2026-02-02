# Status MCP Server

A minimal MCP server that provides system status information to Claude Code, solving the problem of Claude not knowing the current time or context without executing commands.

## Purpose

Claude Code lacks access to basic status information that would help it:
- Know the **current time** (instead of guessing or making up timestamps)
- See **git status** without running commands
- Track the **active project** in multi-repo setups

This server provides three tools:
- `get_status` - Returns timestamp and git info for one or more directories
- `get_last_screenshot` - Gets screenshot from clipboard or Pictures/Screenshots folder
- `set_active_project` - Sets the active project for statusline display

## Installation

```bash
pip install mcp Pillow
```

No build step required - Python is interpreted.

## Configuration

Register with Claude Code:

```bash
claude mcp add status -- python C:/proj/ai/mcp/StatusMcp/server.py
```

Or add to your Claude Code MCP settings manually:

```json
{
  "mcpServers": {
    "status": {
      "command": "python",
      "args": ["C:/proj/ai/mcp/StatusMcp/server.py"]
    }
  }
}
```

## Tool: get_status

Returns current system status as JSON, supporting multiple directories.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `directories` | string[] | No | Directories to check (defaults to cwd) |

### Response

```json
{
  "timestamp": "2026-01-13T06:15:30.123456+00:00",
  "timezone": "Pacific Standard Time",
  "platform": "Windows AMD64",
  "pythonVersion": "3.13.1",
  "directories": [
    {
      "path": "C:\\proj\\ai",
      "name": "ai",
      "git": {
        "branch": "master",
        "remote": "git@github.com:ProteoWizard/pwiz-ai.git",
        "modified": 0,
        "staged": 2,
        "untracked": 0,
        "ahead": 1,
        "behind": 0
      }
    },
    {
      "path": "C:\\proj\\pwiz",
      "name": "pwiz",
      "git": {
        "branch": "Skyline/work/20260113_feature",
        "remote": "git@github.com:ProteoWizard/pwiz.git",
        "modified": 0,
        "staged": 0,
        "untracked": 0,
        "ahead": 0,
        "behind": 0
      }
    }
  ]
}
```

### Fields

| Field | Description |
|-------|-------------|
| `timestamp` | Current time in ISO 8601 format (UTC) |
| `timezone` | System timezone name |
| `platform` | OS and architecture |
| `pythonVersion` | Python version |
| `directories[].path` | Absolute path to directory |
| `directories[].name` | Directory basename |
| `directories[].git.branch` | Current git branch name |
| `directories[].git.remote` | Remote origin URL |
| `directories[].git.modified` | Count of modified (unstaged) files |
| `directories[].git.staged` | Count of staged files |
| `directories[].git.untracked` | Count of untracked files |
| `directories[].git.ahead` | Commits ahead of upstream |
| `directories[].git.behind` | Commits behind upstream |

## Tool: set_active_project

Sets the active project for statusline display in multi-repo setups.

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `path` | string | Yes | Path to the project directory |

### Response

```
Active project set to: pwiz (C:/proj/pwiz)
```

This writes to `ai/.tmp/active-project.json` (path derived from the server's script location), which is read by `statusline.ps1` to show the correct repository in Claude Code's status line.

## Usage Examples

### Check multiple repositories

```
Tool: get_status
Arguments: { "directories": ["C:/proj/ai", "C:/proj/pwiz", "C:/proj/skyline_26_1"] }
```

### Check current directory only

```
Tool: get_status
Arguments: {}
```

### Switch active project

```
Tool: set_active_project
Arguments: { "path": "C:/proj/pwiz" }
```

### Get screenshot from clipboard

```
Tool: get_last_screenshot
Arguments: {}
```

This eliminates the need to run `git status`, `date`, or other commands just to get context.

## Tool: get_last_screenshot

Retrieves the most recent screenshot, checking clipboard first then the Screenshots folder.

### Parameters

None.

### Response

```json
{
  "path": "C:\\proj\\ai\\.tmp\\screenshots\\clipboard_20260114_153022.png",
  "filename": "clipboard_20260114_153022.png",
  "source": "clipboard",
  "modified": "2026-01-14 15:30:22",
  "size_bytes": 45678,
  "instruction": "Use the Read tool to view this image file"
}
```

### Behavior

1. **Clipboard first**: Checks Windows clipboard for an image (Win+Shift+S, PrintScreen, Snipping Tool)
2. **Saves to temp**: Clipboard images are saved to `ai/.tmp/screenshots/clipboard_YYYYMMDD_HHMMSS.png`
3. **Falls back**: If no clipboard image, checks `~/Pictures/Screenshots/` for the most recent PNG
4. **Returns path**: Claude can then use the Read tool to view the image

### Platform Notes

- **Windows 10**: Win+Shift+S copies to clipboard only (no auto-save)
- **Windows 11**: Win+Shift+S may auto-save to Pictures/Screenshots
- **Requires Pillow**: `pip install Pillow` for clipboard image capture
