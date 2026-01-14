# Status MCP Server

Provides system status information to Claude Code including current time, git status, and active project tracking.

## Problem Statement

Claude Code lacks access to basic information that humans see at a glance:

| Information | Human Access | Claude Access |
|-------------|--------------|---------------|
| Current time | Clock on screen | Must guess or fabricate |
| Git branch | IDE status bar | Must run `git branch` |
| Modified files | IDE indicators | Must run `git status` |
| Active project | Terminal prompt | Unclear in multi-repo setups |

This leads to:
- **Fabricated timestamps** when Claude needs to name files with dates
- **Unnecessary tool calls** just to get basic context
- **Stale assumptions** about repository state

## Solution

A minimal MCP server with two tools:
- `get_status` - Returns timestamp and git info for one or more directories
- `set_active_project` - Sets the active project for statusline display

## Installation

### Prerequisites

- Python 3.10+ installed
- mcp package: `pip install mcp`

No build step required - Python is interpreted.

### Configure Claude Code

```bash
claude mcp add status -- python C:/proj/ai/mcp/StatusMcp/server.py
```

Or add to your MCP settings manually:

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

## Usage

### get_status

```
Tool: get_status
Arguments: {}

# Or with multiple directories:
Arguments: { "directories": ["C:/proj/ai", "C:/proj/pwiz", "C:/proj/skyline_26_1"] }
```

Response:

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
    }
  ]
}
```

### set_active_project

```
Tool: set_active_project
Arguments: { "path": "C:/proj/pwiz" }
```

Response:

```
Active project set to: pwiz (C:/proj/pwiz)
```

This writes to `C:/proj/ai/.tmp/active-project.json`, which is read by `statusline.ps1` to show the correct repository in Claude Code's status line.

## When to Use

Claude should call `get_status` when:

1. **Starting a session** - Get initial context
2. **Before creating timestamped files** - Get accurate time
3. **Before git operations** - Verify branch and status
4. **When uncertain about context** - Quick refresh

Claude should call `set_active_project` when:

1. **Switching focus between repositories** - Update statusline display
2. **Starting work in a specific repo** - Make it visible to user

## Implementation Details

The server uses:
- `subprocess.run` for git commands with 5-second timeout
- Standard library `datetime` with timezone awareness
- JSON state file for active project persistence

All commands are run synchronously to provide a consistent snapshot.

## Source Code

- Server: [ai/mcp/StatusMcp/server.py](../../mcp/StatusMcp/server.py)
- Full documentation: [ai/mcp/StatusMcp/README.md](../../mcp/StatusMcp/README.md)

## Related

- [MCP Development Guide](development-guide.md) - Patterns for MCP servers
- [Tool Hierarchy](tool-hierarchy.md) - When to use MCP vs built-in tools
