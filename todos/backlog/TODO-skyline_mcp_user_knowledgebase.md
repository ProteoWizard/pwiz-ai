# TODO-skyline_mcp_user_knowledgebase.md

## Branch Information
- **Branch**: (to be created when work starts)
- **Base**: `master`
- **Created**: 2026-03-06
- **Status**: Backlog
- **PR**: (pending)
- **Objective**: Build an LLM-facing knowledgebase for Skyline users, served through the Skyline MCP

## Background

The pwiz-ai repository has proven effective for building progressive LLM documentation
for Skyline *developers* over 3+ months. Skills, guides, and context docs help Claude Code
work effectively on the codebase, and they improve organically based on real interactions.

The Skyline MCP (SkylineMcpServer) already serves tutorial content to LLMs by fetching
from GitHub (raw.githubusercontent.com), pinned to the running Skyline version. This same
mechanism can serve user-facing guidance to any LLM client — Claude Desktop, Claude Code,
Gemini CLI, VS Code Copilot, Cursor.

## Vision

A growing collection of markdown guides in `ai/docs/mcp/skyline-user/` that any LLM
connected via the Skyline MCP can discover and load on demand. Similar to how Claude Code
skills help developers, these guides help LLMs assist Skyline *users* with workflows,
settings, troubleshooting, and best practices.

## Architecture

### Content Location

```
ai/docs/mcp/skyline-user/
    index.md              # Topic index with descriptions (like tutorial index)
    getting-started.md    # What the MCP can do, how to ask for help
    plotting.md           # Graph types, customization, export
    importing-data.md     # Supported formats, common pitfalls
    settings-guide.md     # Transition settings, full-scan settings explained
    known-issues.md       # Version-specific issues, upgrade recommendations
    faq.md                # Common questions from support board
```

### Why pwiz-ai (not pwiz)

- Decoupled from Skyline release cycles — push to master daily
- User on Skyline 26.1 gets latest guidance without a Skyline update
- Same git-based workflow the team already uses
- Can reference specific Skyline versions when needed ("requires 26.2+")

### MCP Interface (new tools in SkylineMcpServer)

| Tool | Purpose |
|------|---------|
| `skyline_get_user_topics` | Returns index of available guides (like `skyline_get_available_tutorials`) |
| `skyline_get_user_guide` | Fetches a specific topic by name (like `skyline_get_tutorial`) |

Both fetch from `raw.githubusercontent.com/ProteoWizard/pwiz-ai/master/docs/mcp/skyline-user/...`

### Version-Aware Guidance

The MCP knows the running Skyline version (`skyline_get_version`). The LLM can
cross-reference `known-issues.md` and proactively advise users to upgrade when their
version has a known fix available. This is something static documentation cannot do.

### Versioning Strategy

Unlike tutorials (pinned to Skyline version tags), user docs should fetch from `master`
for the latest guidance. Consider a `stable` branch or tag system if bad pushes become
a risk as content grows.

## Parallel to Developer Documentation

| Audience | Location | Delivery | Grows via |
|----------|----------|----------|-----------|
| Developers | `ai/claude/skills/` | Claude Code skill system | Developer interactions |
| Users | `ai/docs/mcp/skyline-user/` | Skyline MCP tools | User support patterns |

## Implementation Plan

1. Create `ai/docs/mcp/skyline-user/` with `index.md` and 2-3 starter guides
2. Add `skyline_get_user_topics` and `skyline_get_user_guide` tools to SkylineMcpServer
3. Fetch from raw.githubusercontent.com (same pattern as tutorial fetching)
4. Test with Claude Desktop connected to Skyline via AI Connector
5. Expand guides based on real user interactions and support board patterns

## Open Questions

- Should `known-issues.md` be structured by version for easy cross-referencing?
- Should guides include inline references to tutorials (e.g., "see Tutorial X, step 5")?
- How to handle guides that reference features not yet in the user's Skyline version?
