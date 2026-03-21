## Branch Information
- **Branch**: `Skyline/work/20260321_json_rpc_cleanup`
- **Base**: `master`
- **Created**: 2026-03-21
- **Status**: In Progress
- **PR**: (pending)

## Overview

Solidify the JSON tool service transport layer before the first release of
SkylineAiConnector and SkylineMcpServer. Replace the custom wire protocol with
JSON-RPC 2.0, eliminate all JObject/JToken property lookup in production code,
create SkylineJsonToolClient as the reusable typed IJsonToolService client,
and convert IJsonToolService to a fully typed interface.

This continues the IJsonToolService cleanup from PR #4065. Nick wants
IJsonToolService to eventually replace the legacy IToolService which uses
BinaryFormatter (deprecated in .NET, removed in .NET 9). No backward
compatibility concerns -- nothing has been released yet.

## Architecture

**Wire protocol** (JSON-RPC 2.0):
```
Request:  {"jsonrpc": "2.0", "method": "GetVersion", "params": [], "id": 1, "_log": true}
Response: {"jsonrpc": "2.0", "result": "26.1.1.238", "id": 1, "_log": "..."}
Error:    {"jsonrpc": "2.0", "error": {"code": -32601, "message": "..."}, "id": 1}
```

**Client architecture:**
```
SkylineTools (MCP tool methods)
    -> SkylineConnection (MCP instance management, logging)
        -> SkylineJsonToolClient (JSON-RPC pipe client, IJsonToolService impl)
            -> JsonToolServer (Skyline process, named pipe server)
```

**Key files:**
- `pwiz_tools/Skyline/SkylineTool/IJsonToolService.cs` - shared contract + JSON_RPC enum
- `pwiz_tools/Skyline/SkylineTool/JsonToolModels.cs` - POCO models
- `pwiz_tools/Skyline/SkylineTool/SkylineJsonToolClient.cs` - reusable JSON-RPC client
- `pwiz_tools/Skyline/ToolsUI/JsonToolServer.cs` - server implementation
- `pwiz_tools/Skyline/Executables/Tools/SkylineMcp/SkylineMcpServer/SkylineConnection.cs` - MCP wrapper
- `pwiz_tools/Skyline/Executables/Tools/SkylineMcp/SkylineMcpServer/Tools/SkylineTools.cs` - MCP tools
- `pwiz_tools/Skyline/TestFunctional/JsonToolServerTest.cs` - tests
- `pwiz_tools/Skyline/TestFunctional/JsonToolServerSettingsTest.cs` - settings tests

## Tasks

### Phase 1: JSON-RPC 2.0 Wire Protocol + Eliminate JObject
- [x] Update JsonToolConstants: add JSON_RPC enum, JSON-RPC constants, clean JSON enum
- [x] JsonToolServer: add JsonRpcRequest/JsonRpcResponse/JsonRpcError POCOs
- [x] JsonToolServer: replace HandleRequest JObject.Parse with JsonConvert.DeserializeObject
- [x] JsonToolServer: replace SerializeResult/SerializeError with JsonRpcResponse POCO
- [x] JsonToolServer: replace WriteConnectionInfo/CleanupStaleConnectionFiles JObject usage
- [x] JsonToolServer: replace DeserializeArg JToken with JsonConvert.DeserializeObject
- [x] JsonToolServer: remove ParseArgs, AppendLog, Newtonsoft.Json.Linq using
- [x] JsonToolServer: add ShouldSerialize methods for JSON-RPC 2.0 compliance
- [x] JsonToolServer: add JsonRpcException with error codes for method-not-found/invalid-params
- [x] SkylineConnection: update Call() for JSON-RPC 2.0 request/response format
- [x] Tests: update buildRequest helper and response assertions for JSON-RPC 2.0
- [x] Build and test Phase 1

### Phase 2: SkylineJsonToolClient + Typed Proxy
- [x] Created SkylineJsonToolClient in SkylineTool/ (link-compiled, System.Text.Json)
- [x] SkylineJsonToolClient implements IJsonToolService with JSON-RPC pipe transport
- [x] Link-compiled into SkylineMcpServer.csproj
- [x] SkylineConnection thinned to MCP connection management, delegates to client
- [x] SkylineTools: replaced Call(nameof(...)) with direct interface method calls
- [x] Build and test Phase 2 (all 3 test suites pass)

### Phase 3 Batch 1: string[] Return Types + groupName Parameter
- [x] GetReplicateNames: string -> string[]
- [x] GetSettingsListTypes: string -> string[]
- [x] GetSettingsListNames: string -> string[], added groupName parameter for PersistedViews
- [x] GetSettingsListSelectedItems: string -> string[]
- [x] Removed "# Main" / "# External Tools" headers from GetPersistedViewNames data
- [x] Updated all layers: JsonToolServer, SkylineJsonToolClient, SkylineConnection, SkylineTools
- [x] Updated tests for array return types
- [x] Build and test (TestJsonToolServer + TestJsonToolServerSettings pass)

### Phase 3 Batch 2: POCO Return Types + RunCommand Parameter
- [x] GetAvailableTutorials: string -> TutorialListItem[] (Category, Name, Title, Description, WikiUrl, ZipUrl)
- [x] GetReportDocTopics: string -> ReportDocTopicSummary[] (Name, ColumnCount)
- [x] GetOpenForms: string -> FormInfo[] (Type, Title, HasGraph, DockState, Id)
- [x] GetLocations: string -> LocationEntry[] (Name, Locator)
- [x] RunCommand: string commandArgs -> string[] args (match Main(string[] args) pattern)
- [x] RunCommandSilent: string commandArgs -> string[] args (same)
- [x] Defined POCOs in JsonToolModels.cs: TutorialListItem, ReportDocTopicSummary, FormInfo, LocationEntry
- [x] Updated all layers: JsonToolServer, JsonTutorialCatalog, JsonUiService, SkylineJsonToolClient, SkylineConnection, SkylineTools
- [x] Consistent TSV header rows in all MCP tool outputs
- [x] Updated tests (JsonToolServerTest, TutorialCatalogTest, added SkylineTool ref to Test.csproj)
- [x] Build and test (all 4 test suites pass)

### Phase 3 Batch 3: Remaining POCOs + Void Actions + Scope Rename
- [x] GetDocumentStatus: string -> DocumentStatus POCO
- [x] GetSelection: string -> SelectionInfo POCO
- [x] GetReportDocTopic: string -> ReportDocTopicDetail with ColumnDefinition[]
- [x] Renamed ReportDefinition.Scope to DataSource throughout (Nick feedback)
- [x] 8 action methods changed from string to void (decouple LLM presentation from service)
- [x] InvokeOnUiThread(Action) now propagates exceptions via WrapAndThrowException
- [x] MCP tools craft their own confirmation messages
- [x] Build and test (all 4 test suites pass)

### Phase 4: Developer-Facing Cleanup
- [x] Added SkylineJsonToolClient.cs to SkylineTool.csproj (compiled into SkylineTool.dll)
- [x] Added System.Text.Json NuGet to SkylineTool.csproj (PackageReference with RestoreProjectStyle)
- [x] Split IJsonToolService.cs: moved JsonToolConstants + LlmNameAttribute to JsonToolConstants.cs
- [x] IJsonToolService.cs reorganized by category with XML doc comments on every method
- [x] SkylineJsonToolClient.cs has XML doc with usage examples for .NET 4.7.2 and .NET 8.0
- [x] Added SkylineMcp to Sync-DotSettings.ps1 for shared ReSharper settings
- [x] Zero ReSharper warnings in both Skyline.sln and SkylineMcp.sln
- [x] Build and test all 4 test suites pass

## Session Log

### Session 1 (2026-03-21)
- Created branch and TODO
- Completed Phase 1: JSON-RPC 2.0 wire protocol
  - Added JSON_RPC enum with nameof() for all protocol field names
  - Eliminated all JObject/JToken/JArray from JsonToolServer.cs
  - Removed Newtonsoft.Json.Linq dependency from server
  - JsonRpcResponse POCO with ShouldSerialize for spec compliance
  - Standard error codes (-32601, -32602, -32603) via JsonRpcException
- Completed Phase 2: SkylineJsonToolClient + typed proxy
  - Created SkylineJsonToolClient in SkylineTool/ as reusable IJsonToolService client
  - Future replacement for legacy SkylineToolClient (BinaryFormatter)
  - SkylineConnection now delegates to SkylineJsonToolClient
  - SkylineTools uses typed interface methods (compile-time safe)
- Completed Phase 3 Batch 1: string[] return types
  - Four methods return string[] instead of formatted strings
  - Added groupName parameter to GetSettingsListNames for PersistedViews groups
  - Removed presentation headers from data layer (moved to MCP formatting)
- All tests pass: TestJsonToolServer, TestJsonToolServerSettings
- TestSkylineMcp requires SkylineAiConnector.zip rebuild
- Completed Phase 3 Batch 2: POCO return types + RunCommand string[] args
  - Four new POCOs: TutorialListItem, ReportDocTopicSummary, FormInfo, LocationEntry
  - GetAvailableTutorials, GetReportDocTopics, GetOpenForms, GetLocations return typed arrays
  - RunCommand/RunCommandSilent take string[] args (no more command-line parsing on server)
  - Made InvokeOnUiThread generic (was string-only)
  - Consistent TSV header rows in all MCP tool outputs
  - Updated TutorialCatalogTest, added SkylineTool reference to Test.csproj
- All tests pass: TestJsonToolServer, TestJsonToolServerSettings, TestTutorialCatalog, TestSkylineMcp
- Completed Phase 3 Batch 3: remaining POCOs + void actions + Scope rename
  - DocumentStatus, SelectionInfo, ReportDocTopicDetail + ColumnDefinition POCOs
  - Renamed Scope -> DataSource throughout (ReportDefinition, GetReportDocTopics, GetReportDocTopic)
  - 8 action methods changed to void: LLM presentation decoupled from IJsonToolService
  - InvokeOnUiThread(Action) propagates exceptions via WrapAndThrowException
  - MCP tools craft their own confirmation messages
- All tests pass: TestJsonToolServer, TestJsonToolServerSettings, TestSkylineMcp
- Completed Phase 4: developer-facing cleanup
  - SkylineJsonToolClient compiled into SkylineTool.dll with System.Text.Json NuGet
  - Split IJsonToolService.cs: JsonToolConstants + LlmNameAttribute moved to JsonToolConstants.cs
  - IJsonToolService.cs is now clean developer-facing API with XML doc on every method
  - SkylineJsonToolClient has usage examples for both .NET 4.7.2 and .NET 8.0 tools
  - Added SkylineMcp.sln.DotSettings via Sync-DotSettings.ps1 (shared ReSharper settings)
  - Zero ReSharper warnings, all 4 test suites pass
