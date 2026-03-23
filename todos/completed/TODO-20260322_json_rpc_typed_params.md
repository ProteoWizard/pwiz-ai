## Branch Information
- **Branch**: `Skyline/work/20260322_json_rpc_typed_params`
- **Base**: `master`
- **Created**: 2026-03-22
- **Status**: Complete
- **PR**: [#4091](https://github.com/ProteoWizard/pwiz/pull/4091)

## Overview

Eliminate double JSON serialization in the JSON-RPC transport layer. Currently,
typed parameters (ReportDefinition, string[], bool) are serialized to JSON strings
by SkylineJsonToolClient, placed as string elements in the `params` array, then
serialized again as part of the JSON-RPC request. The server then deserializes the
request and deserializes each string param back to its typed object.

Change `params` from `string[]` to a mixed-type JSON array so typed parameters
are embedded directly as JSON objects, avoiding the double encoding.

This is the final wire format change before the first SkylineMcpServer release.
Follows PR #4088 which established JSON-RPC 2.0 and fully typed IJsonToolService.

## Current vs Target Wire Format

**Current** (double-encoded typed params):
```json
{
  "jsonrpc": "2.0",
  "method": "ExportReportFromDefinition",
  "params": ["{\"select\":[\"ProteinName\"],\"name\":\"Foo\"}", "/path/to/file", "invariant"],
  "id": 1
}
```

**Target** (typed params as JSON objects):
```json
{
  "jsonrpc": "2.0",
  "method": "ExportReportFromDefinition",
  "params": [{"select":["ProteinName"],"name":"Foo"}, "/path/to/file", "invariant"],
  "id": 1
}
```

## Affected Methods

Methods with typed parameters that currently double-encode:
- `ExportReportFromDefinition(ReportDefinition, string, string)` - ReportDefinition
- `AddReportFromDefinition(ReportDefinition)` - ReportDefinition
- `RunCommand(string[])` - string[] args
- `RunCommandSilent(string[])` - string[] args
- `SelectSettingsListItems(string, string[])` - string[] itemNames
- `AddSettingsListItem(string, string, bool)` - bool overwrite
- `ImportFasta(string, string)` - keepEmptyProteins is string but could be bool

## Key Files

- `SkylineTool/SkylineJsonToolClient.cs` - client-side: stop pre-serializing typed params
- `ToolsUI/JsonToolServer.cs` - server-side: Dispatch/DeserializeArg handle mixed param types
- `SkylineTool/JsonToolConstants.cs` - JsonRpcRequest.Params type change (string[] -> object[])
- `TestFunctional/JsonToolServerTest.cs` - update test request construction
- `TestFunctional/SkylineMcpTest.cs` - verify end-to-end

## Tasks

- [x] JsonToolServer: changed JsonRpcRequest.Params from string[] to JToken[]
- [x] JsonToolServer: replaced DeserializeArg with ConvertArg handling mixed JToken types
- [x] SkylineJsonToolClient: Call/CallTyped take object[] instead of string[]
- [x] SkylineJsonToolClient: typed params (ReportDefinition, string[], bool) passed directly
- [x] Tests: updated request construction to send objects, not JSON strings
- [x] Build and test all 4 test suites pass
- [x] Rebuilt SkylineAiConnector.zip and TestSkylineMcp passes

## Session Log

### Session 1 (2026-03-22)
- Created branch and TODO
- Implemented typed params: eliminated double JSON serialization
- All 4 test suites pass

### 2026-03-23 - Merged

PR #4091 merged (commit `264e3686`).

## Resolution

**Status**: Merged
**Summary**: Eliminated double JSON serialization in JSON-RPC transport. Typed parameters (ReportDefinition, string[], bool) are now embedded directly as JSON objects in the params array instead of being pre-serialized to strings. Final wire format change before first SkylineMcpServer release.
