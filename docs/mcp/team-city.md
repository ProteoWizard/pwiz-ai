# TeamCity MCP Server

**Status**: Not yet implemented. See [TODO-teamcity_mcp_server.md](../../todos/backlog/brendanx67/TODO-teamcity_mcp_server.md) for the full plan.

## Overview

A custom Python MCP server (following the LabKeyMcp pattern) for monitoring PR builds on `teamcity.labkey.org`. The primary value is structured test failure data — test names, status, and stack traces — via the TeamCity REST API's `testOccurrences` endpoint.

## Interim: Direct REST API Access

Until the MCP server is built, Claude Code can query TeamCity directly via `curl`:

```bash
# Auth header (token from ~/.teamcity-mcp/config.json)
TC_TOKEN="<token>"
TC_URL="https://teamcity.labkey.org"

# Find running builds for a PR
curl -s -H "Authorization: Bearer $TC_TOKEN" \
  "$TC_URL/app/rest/builds?locator=buildType:bt209,branch:pull/4038,state:running"

# Get failed test details for a build (the key endpoint)
curl -s -H "Authorization: Bearer $TC_TOKEN" \
  "$TC_URL/app/rest/testOccurrences?locator=build:(id:3867049),status:FAILURE&fields=testOccurrence(name,status,details)"
```

## PR Check → Config ID Reference

| GitHub Check Name | Config ID |
|---|---|
| Skyline master and PRs (Windows x86_64) | `bt209` |
| Core Windows x86_64 | `bt83` |
| Core Linux x86_64 | `bt17` |
| Core Windows x86_64 (no vendor DLLs) | `bt143` |
| ProteoWizard and Skyline Docker (Wine x86_64) | `ProteoWizardAndSkylineDockerContainerWineX8664` |
| Skyline master and PRs TestConnected tests | `ProteoWizard_SkylineMasterAndPRsTestConnectedTests` |

## Related

- [TODO-teamcity_mcp_server.md](../../todos/backlog/brendanx67/TODO-teamcity_mcp_server.md) — Full implementation plan
- [Tool Hierarchy](tool-hierarchy.md) — When to use MCP vs built-in tools
