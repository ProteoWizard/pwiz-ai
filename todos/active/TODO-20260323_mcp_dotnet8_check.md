# SkylineMcpServer fails silently when .NET 8 Desktop Runtime is not installed

## Branch Information
- **Branch**: `Skyline/work/20260323_mcp_dotnet8_check`
- **Base**: `master`
- **Created**: 2026-03-23
- **Status**: In Progress
- **GitHub Issue**: [#4092](https://github.com/ProteoWizard/pwiz/issues/4092)
- **PR**: (pending)
- **Test Name**: TestSkylineMcp
- **Fix Type**: failure
- **Failure Fingerprint**: `5e096c9cf516077f`

## Objective

Fix silent failure of `SkylineMcpServer.exe` when .NET 8 Desktop Runtime is not installed. Add a runtime check in `SkylineAiConnector` and improve error reporting in `TestSkylineMcp`.

## Tasks

- [ ] SkylineAiConnector: Add .NET 8 runtime check at install/launch time with clear error message
- [ ] TestSkylineMcp: Capture stderr and exit code on failure, include in assert message

## Progress Log

### 2026-03-23 - Session Start

Starting work on this issue...
