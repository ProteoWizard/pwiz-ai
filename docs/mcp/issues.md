# LabKey Issue Tracker

This document describes the system for querying legacy issues from the skyline.ms LabKey issue tracker using Claude Code.

> **Note**: This documents the LabKey issue tracker at skyline.ms/home/issues, NOT GitHub Issues. Most active development now uses GitHub Issues. See [ai/WORKFLOW.md](../../WORKFLOW.md) for current workflows.

## Overview

The LabKey issue tracker contains historical issues (defects, TODOs) from before the project moved to GitHub. These issues include:
- Issue type, priority, area, and status
- Assignee and milestone tracking
- Full comment history
- File attachments

Claude Code can query this data via an MCP server for historical research and issue triage.

## Architecture

```
Claude Code
    |
    +-- MCP Protocol (stdio)
            |
            +-- LabKeyMcp Server (Python)
                    |
                    +-- labkey Python API
                            |
                            +-- skyline.ms LabKey Server
                                    |
                                    +-- issues schema
                                        (issues_list, issue_with_comments)
```

## Components

### MCP Server

**Location**: `ai/mcp/LabKeyMcp/`

| File | Purpose |
|------|---------|
| `server.py` | MCP server entry point |
| `tools/` | Tool modules by domain |
| `tools/issues.py` | Issue tracker tools |
| `tools/common.py` | Shared utilities and discovery tools |
| `queries/` | Server-side query documentation |
| `pyproject.toml` | Python dependencies |
| `test_connection.py` | Standalone connection test |
| `README.md` | Setup instructions |

### Available MCP Tools

| Tool | Type | Description |
|------|------|-------------|
| `save_issues_report(status)` | [P] Primary | Generate issue summary, save to `ai/.tmp/issues-report-{status}-YYYYMMDD.md` |
| `query_issues(status, issue_type, max_rows)` | [D] Drill-down | Browse issues with filters, returns summary table |
| `get_issue_details(issue_id)` | [D] Drill-down | Full issue with comments, save to `ai/.tmp/issue-{id}.md` |

### Authentication

Each developer uses a personal `+claude` account for MCP access:
- **Team members**: `yourname+claude@proteinms.net`
- **Interns/others**: `yourname+claude@gmail.com`
- **Group**: "Agents" on skyline.ms
- **Permissions**: Read-only access to most containers

See [exceptions.md](exceptions.md#authentication) for full authentication details.

## Data Schema

Issue data lives at:
- **Server**: `skyline.ms`
- **Container**: `/home/issues`
- **Schema**: `issues`
- **Queries**: `issues_list`, `issues_by_status`, `issue_with_comments`

### Key Columns

| Column | Description |
|--------|-------------|
| `IssueId` | Unique issue identifier |
| `Title` | Issue summary |
| `Status` | open, resolved, closed |
| `Type` | Defect, Todo |
| `Priority` | 1 (highest) to 4 (lowest) |
| `Area` | Functional area (Protein, Results Grid, etc.) |
| `Milestone` | Target version/milestone |
| `AssignedTo` | Developer assigned to issue |
| `Created` | When issue was created |
| `Modified` | Last modification time |
| `Resolved` | When issue was resolved |
| `Closed` | When issue was closed |
| `CreatedBy` | User who created the issue |
| `ResolvedBy` | User who resolved the issue |
| `EntityId` | UUID for attachment lookups |

## Setup

See [exceptions.md](exceptions.md#setup) for installation and credential configuration. The same MCP server and credentials provide access to both exception and issue data.

## Usage

After setup, Claude Code can query issues directly:

**Generate issues report:**
> "Show me all open issues"

**Query with filters:**
> "List all open defects"

**Get specific issue:**
> "Get details for issue #47502"

## Primary Report: save_issues_report

Use the primary report for comprehensive issue analysis:

```
save_issues_report(status="open")
```

This saves a full report to `ai/.tmp/issues-report-open-YYYYMMDD.md` with:
- Summary by type (Defect, Todo)
- Summary by priority (1-4)
- Summary by area
- Summary by assignee
- Summary by milestone
- Age analysis (time since last modified)
- Full listing of defects and TODOs

### Drill-Down Tools

Use drill-down tools for specific investigation:

**Browse issues with filters:**
```
query_issues(status="open", issue_type="defect", max_rows=20)
```

**Get full issue with comments:**
```
get_issue_details(issue_id=47502)
```

**Check for attachments:**
```
list_attachments(entity_id="<EntityId>", container_path="/home/issues")
```

## Issue Types

| Type | Description |
|------|-------------|
| Defect | Bug report - something broken |
| Todo | Enhancement or task |

## Priority Levels

| Priority | Meaning |
|----------|---------|
| 1 | Critical - must fix |
| 2 | High - should fix soon |
| 3 | Medium - fix when possible |
| 4 | Low - nice to have |

## Related Documentation

- [MCP Development Guide](development-guide.md) - Patterns for extending MCP capabilities
- [Exceptions](exceptions.md) - Exception triage system
- [Nightly Tests](nightly-tests.md) - Test results data access
- [Support](support.md) - Support board access
- [LabKey MCP Server README](../../mcp/LabKeyMcp/README.md) - Setup instructions
- [Query Documentation](../../mcp/LabKeyMcp/queries/README.md) - Server-side query reference
