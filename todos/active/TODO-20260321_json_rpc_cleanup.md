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
and begin converting string return types to typed arrays.

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
- `pwiz_tools/Skyline/SkylineTool/SkylineJsonToolClient.cs` - reusable JSON-RPC client (NEW)
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

### Phase 3 Batch 1: string[] Return Types
- [ ] IJsonToolService: change GetReplicateNames return to string[]
- [ ] IJsonToolService: change GetSettingsListTypes return to string[]
- [ ] IJsonToolService: change GetSettingsListNames return to string[]
- [ ] IJsonToolService: change GetSettingsListSelectedItems return to string[]
- [ ] JsonToolServer: update implementations to return string[]
- [ ] SkylineJsonToolClient: update proxy methods to use CallTyped<string[]>
- [ ] SkylineTools: format string[] results for MCP display
- [ ] Tests: update assertions for array return types
- [ ] Build and test Phase 3

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
- All tests pass: TestJsonToolServer, TestJsonToolServerSettings, TestSkylineMcp
