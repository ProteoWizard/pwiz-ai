# MCP Server Documentation

This folder contains documentation for MCP (Model Context Protocol) servers used by Claude Code.

## MCP Servers

| Server | Purpose | Documentation |
|--------|---------|---------------|
| LabKey | skyline.ms data access (wiki, support, exceptions, tests) | See sections below |
| Gmail | Email sending for automated reports | [gmail.md](gmail.md) |
| ImageComparer | Screenshot diff review for tutorials | [image-comparer.md](image-comparer.md) |
| Status | System status, git info, active project | [status.md](status.md) |

---

# LabKey MCP Server

Access skyline.ms data via the LabKey MCP server.

## Data Sources

| Document | Container | Description |
|----------|-----------|-------------|
| [announcements.md](announcements.md) | (multiple) | General-purpose table: release notes, support, exceptions |
| [wiki.md](wiki.md) | `/home/software/Skyline` | Wiki pages, tutorials, documentation |
| [support.md](support.md) | `/home/support` | Support board threads and user questions |
| [exceptions.md](exceptions.md) | `/home/issues/exceptions` | User-reported crash reports |
| [nightly-tests.md](nightly-tests.md) | `/home/development/Nightly x64` | Automated test results |
| [issues.md](issues.md) | `/home/issues` | LabKey issue tracker tools |
| [files.md](files.md) | (multiple) | WebDAV file repository access |
| [status.md](status.md) | (local) | StatusMcp tools for developer workflow |

## Architecture

```
Claude Code
    │
    └── MCP Protocol (stdio)
            │
            └── LabKeyMcp Server (Python)
                    │
                    ├── labkey Python SDK (queries)
                    │       │
                    │       └── skyline.ms LabKey Server
                    │               ├── /home/software/Skyline (wiki)
                    │               ├── /home/support (announcements)
                    │               ├── /home/issues/exceptions
                    │               └── /home/development/Nightly x64
                    │
                    └── HTTP requests (updates, attachments)
```

## Authentication

Each developer uses a personal `+claude` account:
- **Team members**: `yourname+claude@proteinms.net`
- **Interns/others**: `yourname+claude@gmail.com`
- **Group**: "Agents" on skyline.ms

> **Important**: The `+claude` suffix only works with Gmail-backed email providers (@proteinms.net, @gmail.com). It will **not** work with @uw.edu or similar providers.

Credentials are stored in `~/.netrc`:
```
machine skyline.ms
login yourname+claude@domain.com
password <password>
```

## Tool Selection

**Important**: Start with PRIMARY tools - see [tool-hierarchy.md](tool-hierarchy.md) for:
- Which tools to use first (PRIMARY vs DRILL-DOWN vs DISCOVERY)
- Usage patterns and anti-patterns
- When to propose new tools

### Tool Docstring Format

Tools use minimal docstrings with category markers and doc file references:

```
[P] Daily nightly test report. → nightly-tests.md
```

| Marker | Category | Purpose |
|--------|----------|---------|
| `[P]` | PRIMARY | Daily reports, main entry points - use these first |
| `[D]` | DRILL-DOWN | Detailed queries for specific items |
| `[A]` | ANALYSIS | Compare, analyze, or correlate data |
| `[?]` | DISCOVERY | Explore schema structure |
| `[E]` | EXPLORATION | Raw page fetching |

The `→ docfile.md` reference points to detailed documentation. Read the doc file **once** when working with related tools - it covers multiple tools in that domain.

**Why minimal docstrings**: Tool definitions consume context tokens at session start. Minimal docstrings (~2k tokens for 40+ tools) vs verbose (~9k tokens) saves context for actual work. Full documentation loads on-demand when needed.

## Development

- [development-guide.md](development-guide.md) - Patterns for extending MCP capabilities
- [Server source code](../../mcp/LabKeyMcp/) - Python implementation
- [Query documentation](../../mcp/LabKeyMcp/queries/README.md) - Server-side queries

## Setup

See [Developer Setup Guide](../developer-setup-guide.md) for installation instructions.

## MCP Server Registration

### Configuration File Location

MCP servers are registered in **`~/.claude.json`** (your home directory). This single file stores all Claude Code configuration, including per-project MCP server definitions.

The structure for MCP servers (the project key is your actual project root path):
```json
{
  "projects": {
    "<your project root>": {
      "mcpServers": {
        "labkey": {
          "type": "stdio",
          "command": "python",
          "args": ["./ai/mcp/LabKeyMcp/server.py"],
          "env": {}
        },
        "gmail": {
          "type": "stdio",
          "command": "npx",
          "args": ["@gongrzhe/server-gmail-autoauth-mcp"],
          "env": {}
        }
      }
    }
  }
}
```

To register a server interactively: `claude mcp add <name>`
To list registered servers: `claude mcp list`

### Context Impact of MCP Servers

**Important**: Each registered MCP server consumes context tokens for tool definitions.

| Component | Approximate Tokens |
|-----------|-------------------|
| LabKey MCP (42 tools) | ~2k tokens (minimal docstrings) |
| Gmail MCP (19 tools) | ~13k tokens |
| **Total MCP overhead** | **~15k tokens (7.5% of 200k context)** |

This overhead is incurred at the start of every session where MCP servers are enabled.

**Note**: LabKey tools use minimal docstrings with doc file references to reduce token overhead. See "Tool Docstring Format" above.

### Recommended: Separate Directories for Different Workflows

To maximize coding context, consider maintaining **two separate checkouts**:

| Directory | Branch | MCP Servers | Purpose |
|-----------|--------|-------------|---------|
| `<project root>\ai` | `master` | LabKey + Gmail | Daily reports, documentation, scheduled tasks |
| `<project root>\pwiz` | `master` or feature | None | Active coding with maximum context |

**Why this helps**:
- Coding sessions get full 200k context for code, tests, and exploration
- Daily report sessions have the MCP tools they need
- No context wasted on unused tools

**Setup**:
1. Keep `ai/` checkout (pwiz-ai repo) with MCP servers for AI tooling and documentation work
2. Use a separate checkout (e.g., `pwiz`, `pwiz-feature`) without MCP registration for coding
3. The MCP servers are project-specific in `~/.claude.json`, so different directories can have different configurations

## Command-Line Automation

**Important**: MCP tools require explicit permission to work in non-interactive mode (`claude -p`).

**Wildcards do NOT work** - each tool must be listed by name in `.claude/settings.local.json`.

To configure permissions for a command-line operation:
1. Start an interactive Claude Code session
2. Describe the automation you need
3. Ask Claude to write the appropriate `permissions.allow` list
4. Review and remove any destructive tools you don't want auto-approved

See [Scheduled Tasks Guide](../scheduled-tasks-guide.md#critical-mcp-permissions-for-command-line-automation) for the complete example.
