# TeamCity MCP Server

Monitors builds on `teamcity.labkey.org` — PR builds, release branch builds, Docker publishing, test failures, and build logs.

## Setup

See [setup.md](setup.md#teamcity-mcp) for installation instructions.

**Auth**: `~/.teamcity-mcp/config.json` with `url` and `token` fields.

## Available Tools

| Tool | Description |
|------|-------------|
| `search_builds` | Find builds by config ID, branch, state (running/finished/queued) |
| `get_build_status` | Detailed status for a single build (progress, step, agent) |
| `get_failed_tests` | Structured test failures with names and stack traces |
| `get_test_summary` | Pass/fail/muted test counts for a build |
| `get_build_log` | Search or tail the build log (regex search with context) |

## PR Build Monitoring Workflow

### Step 1: Identify PR and pending checks

```bash
cd /c/proj/pwiz
gh pr list --head $(git branch --show-current) --json number,title
gh pr checks <PR#> --json name,state,bucket,description,link
```

### Step 2: Query TeamCity for running/finished builds

```
search_builds(build_type_id="bt209", branch="pull/4038", state="running")
search_builds(build_type_id="bt209", branch="pull/4038", count=3)
```

**Important**: `search_builds` defaults to finished builds only. Pass `state="running"` to find in-progress builds.

### Step 3: Investigate failures

```
# Structured test failure data (test names + stack traces)
get_failed_tests(build_id=3867049)

# Search build log for diagnostics not captured in test results
get_build_log(build_id=3867235, search="Could not load|Caught exception")
```

The `get_failed_tests` tool returns what the TeamCity "Tests" tab shows. For failures where the test result is minimal (e.g., "Exit status: 1"), use `get_build_log` with a search pattern to find the actual diagnostic output in the surrounding log.

## Build Configuration Reference

### PR and Master Builds

| Build Name | Config ID |
|---|---|
| Skyline Code Inspection | `ProteoWizard_WindowsX8664msvcProfessionalSkylineResharperChecks` |
| Skyline master and PRs (Windows x86_64) | `bt209` |
| Skyline master and PRs (Windows x86_64 debug, with code coverage) | `bt210` |
| Skyline master and PRs TestConnected tests | `ProteoWizard_SkylineMasterAndPRsTestConnectedTests` |
| Skyline PR Perf and Tutorial tests (Windows x86_64) | `ProteoWizard_SkylinePrPerfAndTutorialTestsWindowsX8664` |
| ProteoWizard and Skyline Docker (Wine x86_64) | `ProteoWizardAndSkylineDockerContainerWineX8664` |
| Core Windows x86_64 | `bt83` |
| Core Linux x86_64 | `bt17` |
| Core Windows x86_64 (no vendor DLLs) | `bt143` |

### Release Branch and Docker Builds

| Build Name | Config ID |
|---|---|
| ProteoWizard and Skyline (release branch) Docker container (Wine x86_64) | `ProteoWizard_ProteoWizardAndSkylineReleaseBranchDockerContainerWineX8664` |
| Publish Docker image (Skyline-daily) | `ProteoWizard_ProteoWizardPublishDockerForSkylineDaily` |
| Publish Docker image (Skyline Release Branch) | `ProteoWizard_ProteoWizardPublishDockerAndSingularityImagesSkylineReleaseBranch` |
| Publish Docker image (Skyline-release-daily) | `ProteoWizard_ProteoWizardPublishDockerImageSkylineReleaseDaily` |

**Docker publishing workflow** (see [release-guide.md](../release-guide.md)):
- **Skyline-daily (beta)**: Use `ProteoWizard_ProteoWizardPublishDockerForSkylineDaily`
- **Release candidates**: Use `ProteoWizard_ProteoWizardPublishDockerImageSkylineReleaseDaily`
- **Patch releases**: Use `ProteoWizard_ProteoWizardPublishDockerAndSingularityImagesSkylineReleaseBranch`

Before publishing, verify the release branch Docker container build succeeded:
```
search_builds(build_type_id="ProteoWizard_ProteoWizardAndSkylineReleaseBranchDockerContainerWineX8664", count=3)
```

## Build Chain Dependencies

The Skyline PR build is part of a chain:
1. **Skyline Code Inspection** (ReSharper) - triggers first
2. **Skyline master and PRs (bt209)** - snapshot dependency on #1
3. **Docker container (Wine x86_64)** - snapshot dependency on bt209

This is why the Docker build shows "Expected - Waiting for status" on GitHub while bt209 runs.

## Related

- [setup.md](setup.md#teamcity-mcp) - Installation instructions
- [TODO-20260226_teamcity_mcp_server.md](../../todos/active/TODO-20260226_teamcity_mcp_server.md) - Implementation plan (Phase 2: PR integration)
- [Tool Hierarchy](tool-hierarchy.md) - When to use MCP vs built-in tools
