# TODO-teamcity_mcp_server.md

## Branch Information (Future)
- **Branch**: Not applicable - Python MCP server lives in pwiz-ai (ai/) repo
- **Objective**: Build a custom TeamCity MCP server for monitoring PR builds

## Background

When code is pushed to a PR on GitHub, TeamCity runs required CI builds (Skyline, Core, Docker, etc.).
Currently, the developer must manually check TeamCity in a browser and paste failure details into
Claude Code. This MCP server will let Claude Code query TeamCity directly, from PR checks through
to individual test failure stack traces.

### What We Learned (2026-02-26)

We evaluated the third-party [itcaat/teamcity-mcp](https://github.com/itcaat/teamcity-mcp) server
(Go binary, v1.0.8). Findings:

- **`search_builds`** works well — can find builds by config ID, branch (`pull/<PR#>`), and state
- **`fetch_build_log`** is too coarse — returns raw log text, making it hard to isolate specific
  test failures from thousands of lines of output
- **`search_build_configurations`** works for discovering config IDs but returns empty for name searches
- **Missing entirely**: Structured test results (the `/app/rest/testOccurrences` endpoint) which is
  the most valuable data — gives test name, status, and failure details/stack traces directly

**Key discovery**: The TeamCity REST API endpoint `/app/rest/testOccurrences` provides exactly what
we need — structured test failure data with test names, status, and detailed stack traces. This is
what the TeamCity web UI shows on the "Tests" tab.

### End-to-End PR Monitoring Flow

The full workflow from code push to failure details:

1. **Git branch → PR number**: `gh pr list --head <branch> --json number`
2. **PR → pending checks**: `gh pr checks <PR#> --json name,state,bucket,description,link`
3. **Check name → TeamCity config ID**: Use reference table (see below)
4. **Config ID + branch → builds**: REST API `builds?locator=buildType:<id>,branch:pull/<PR#>`
5. **Build → test failures**: REST API `testOccurrences?locator=build:(id:<buildId>),status:FAILURE`

Steps 1-2 use `gh` CLI (already available). Steps 3-5 need the MCP server.

### TeamCity REST API Endpoints

Base URL: `https://teamcity.labkey.org/app/rest`
Auth: Bearer token (API token from TeamCity profile)

| Endpoint | Purpose | Example |
|----------|---------|---------|
| `builds?locator=buildType:{id},branch:{branch},state:running` | Find running builds | Find PR build in progress |
| `builds?locator=buildType:{id},branch:{branch},count:5` | Recent builds | History for a PR |
| `builds/{id}` | Build details | Status, agent, duration |
| `testOccurrences?locator=build:(id:{id}),status:FAILURE` | Failed tests | Test names + stack traces |
| `testOccurrences?locator=build:(id:{id})&fields=testOccurrence(name,status,details)` | Failed test details | Full failure output |
| `buildTypes?locator=project:ProteoWizard` | All build configs | Discover config IDs |

### Build Configuration ID Reference

All configs are under TeamCity project `ProteoWizard`.

**PR-Required Checks:**

| GitHub Check Name | Config ID |
|---|---|
| Skyline master and PRs (Windows x86_64) | `bt209` |
| Core Windows x86_64 | `bt83` |
| Core Linux x86_64 | `bt17` |
| Core Windows x86_64 (no vendor DLLs) | `bt143` |
| ProteoWizard and Skyline Docker (Wine x86_64) | `ProteoWizardAndSkylineDockerContainerWineX8664` |
| Skyline master and PRs TestConnected tests | `ProteoWizard_SkylineMasterAndPRsTestConnectedTests` |

**Other Useful Configs:**

| Name | Config ID |
|---|---|
| Skyline Code Inspection | `ProteoWizard_WindowsX8664msvcProfessionalSkylineResharperChecks` |
| Skyline PR Perf and Tutorial tests | `ProteoWizard_SkylinePrPerfAndTutorialTestsWindowsX8664` |
| Skyline debug + code coverage | `bt210` |

### Build Chain Dependencies

The Skyline PR build is part of a chain:
1. **Skyline Code Inspection** (ReSharper) — triggers first
2. **Skyline master and PRs (bt209)** — snapshot dependency on #1
3. **Docker container (Wine x86_64)** — snapshot dependency on bt209

This is why the Docker build shows "Expected — Waiting" on GitHub while bt209 runs.

## Task Checklist

### Phase 1: Core Server
- [ ] **Create `ai/mcp/TeamCityMcp/server.py`** — MCP server skeleton following LabKeyMcp patterns
  - stdio transport, Python `mcp` package
  - Auth via `~/.teamcity-mcp/config.json` (url + token)
  - Base HTTP client for TeamCity REST API with Bearer token auth
- [ ] **`search_builds` tool** — Find builds by config ID, branch, state (running/finished), count
  - Returns: build number, ID, status, state, branch, commit hash, start time, agent
- [ ] **`get_build_status` tool** — Detailed status for a single build
  - Returns: status, state, current step, percent complete, estimated time remaining
- [ ] **`get_failed_tests` tool** — Structured test failure data for a build
  - Uses `/app/rest/testOccurrences?locator=build:(id:{buildId}),status:FAILURE`
  - Returns: test name, status, failure details/stack trace
  - This is the most important tool — replaces manual TeamCity browsing

### Phase 2: PR Integration
- [ ] **`check_pr_builds` tool** — All-in-one PR status check
  - Input: PR number (or auto-detect from current branch)
  - Maps PR-required check names to config IDs (hardcoded reference table)
  - Queries each config for builds on `pull/<PR#>` branch
  - Returns consolidated status: which checks passed, which are running, which failed
  - For failures, includes test names and failure summaries
- [ ] **`get_build_log` tool** — Filtered build log access
  - Filter by step, severity, or regex pattern
  - Tail N lines option
  - Useful for build failures (compile errors) vs test failures

### Phase 3: Documentation & Polish
- [ ] **`ai/docs/mcp/team-city.md`** — Full documentation (replace current placeholder)
- [ ] **Update `ai/docs/new-machine-setup.md`** — Add TeamCity MCP setup steps
- [ ] **Add to `ai/claude/settings-defaults.local.json`** — Default permissions for TeamCity tools
- [ ] **Register command**: `claude mcp add teamcity -- python C:/proj/ai/mcp/TeamCityMcp/server.py`

## Implementation Notes

### Auth Pattern
Follow LabKeyMcp: read `~/.teamcity-mcp/config.json` at startup for url and token.
The config.json structure:
```json
{
  "url": "https://teamcity.labkey.org",
  "token": "<api-token>"
}
```

### Server Structure (following LabKeyMcp)
```
ai/mcp/TeamCityMcp/
  server.py          # MCP server entry point
  pyproject.toml     # Dependencies
  README.md          # Setup instructions
  tools/
    __init__.py
    common.py        # Base HTTP client, auth, config loading
    builds.py        # search_builds, get_build_status
    tests.py         # get_failed_tests
    pr.py            # check_pr_builds (Phase 2)
```

### Key Design Decisions
- **No Docker dependency** — pure Python, same as LabKeyMcp
- **Config ID table hardcoded** — the mapping rarely changes; easier than discovering dynamically
- **`~/.teamcity-mcp/` for credentials** — not in repo, consistent with `~/.gmail-mcp/`
- **Focus on test failures** — the primary value is structured test results, not raw logs
