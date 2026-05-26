# SkylineMcpServer fails silently when .NET 8 Desktop Runtime is not installed

## Branch Information
- **Branch**: `Skyline/work/20260323_mcp_dotnet8_check`
- **Base**: `master`
- **Created**: 2026-03-23
- **Status**: Complete
- **GitHub Issue**: [#4092](https://github.com/ProteoWizard/pwiz/issues/4092)
- **PR**: [#4093](https://github.com/ProteoWizard/pwiz/pull/4093)
- **Test Name**: TestSkylineMcp
- **Fix Type**: failure
- **Failure Fingerprint**: `5e096c9cf516077f`

## Objective

Fix silent failure of `SkylineMcpServer.exe` when .NET 8 Desktop Runtime is not installed. Add a runtime check in `SkylineAiConnector` and improve error reporting in `TestSkylineMcp`.

## Tasks

- [x] SkylineAiConnector: .NET 8 runtime check already implemented in McpServerDeployer.IsDotNet8Installed() and MainForm.DeployMcpServer() - manually verified shows correct dialog
- [x] TestSkylineMcp: Capture stderr and exit code on failure, include in assert message

## Progress Log

### 2026-03-23 - Implementation

- SkylineAiConnector already had the .NET 8 runtime check (IsDotNet8Installed + dialog in DeployMcpServer). Manually verified it shows the expected message.
- Updated TestSkylineMcp to capture stderr and exit code when MCP server exits unexpectedly: threaded mcpProcess through McpCall/McpToolCall/ReadJsonRpcResponse so the failure message now includes exit code and stderr content instead of the opaque "Unexpected end of MCP server output".
- Build succeeded, TestSkylineMcp passes.
- Addressed Copilot review: wait for process exit before reading stderr to avoid blocking.
- Used "terminated" instead of "killed" per feedback.

### 2026-03-23 - Merged

PR #4093 merged (commit `12675598`).

## Resolution

**Status**: Merged
**Summary**: Improved TestSkylineMcp error diagnostics when MCP server exits unexpectedly. Now reports exit code and stderr (e.g., missing .NET 8 runtime) instead of opaque "Unexpected end of MCP server output". SkylineAiConnector runtime check was already in place.
