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
have SkylineConnection implement IJsonToolService as a typed client proxy, and
begin converting string return types to typed arrays.

This continues the IJsonToolService cleanup from PR #4065. Nick wants
IJsonToolService to eventually replace the legacy IToolService which uses
BinaryFormatter (deprecated in .NET, removed in .NET 9). No backward
compatibility concerns -- nothing has been released yet.

## Architecture

**Current wire protocol** (custom):
```
Request:  {"method": "GetVersion", "args": [], "log": true}
Response: {"result": "26.1.1.238", "log": "..."}
Error:    {"error": "System.ArgumentException: ..."}
```

**Target wire protocol** (JSON-RPC 2.0):
```
Request:  {"jsonrpc": "2.0", "method": "GetVersion", "params": [], "id": 1, "_log": true}
Response: {"jsonrpc": "2.0", "result": "26.1.1.238", "id": 1, "_log": "..."}
Error:    {"jsonrpc": "2.0", "error": {"code": -32601, "message": "..."}, "id": 1}
```

**Key files:**
- `pwiz_tools/Skyline/SkylineTool/IJsonToolService.cs` - shared contract
- `pwiz_tools/Skyline/SkylineTool/JsonToolModels.cs` - POCO models
- `pwiz_tools/Skyline/ToolsUI/JsonToolServer.cs` - server implementation
- `pwiz_tools/Skyline/Executables/Tools/SkylineMcp/SkylineMcpServer/SkylineConnection.cs` - client
- `pwiz_tools/Skyline/Executables/Tools/SkylineMcp/SkylineMcpServer/Tools/SkylineTools.cs` - MCP tools
- `pwiz_tools/Skyline/TestFunctional/JsonToolServerTest.cs` - tests
- `pwiz_tools/Skyline/TestFunctional/JsonToolServerSettingsTest.cs` - settings tests

## Tasks

### Phase 1: JSON-RPC 2.0 Wire Protocol + Eliminate JObject
- [ ] Update JsonToolConstants: remove unused/protocol JSON enum members, add JSON-RPC constants
- [ ] JsonToolServer: add private JsonRpcRequest/JsonRpcError POCOs
- [ ] JsonToolServer: replace HandleRequest JObject.Parse with JsonConvert.DeserializeObject
- [ ] JsonToolServer: replace SerializeResult/SerializeError JObject with anonymous type serialization
- [ ] JsonToolServer: replace WriteConnectionInfo/CleanupStaleConnectionFiles JObject usage
- [ ] JsonToolServer: replace DeserializeArg JToken usage with JsonConvert.DeserializeObject
- [ ] JsonToolServer: remove ParseArgs, AppendLog(JObject), Newtonsoft.Json.Linq using
- [ ] SkylineConnection: update Call() for JSON-RPC 2.0 request/response format
- [ ] Tests: update buildRequest helper and response parsing for JSON-RPC 2.0
- [ ] Build and test Phase 1

### Phase 2: SkylineConnection Implements IJsonToolService
- [ ] SkylineConnection: implement IJsonToolService interface with method delegates
- [ ] SkylineConnection: make Call/CallTyped private
- [ ] SkylineTools: replace Call(nameof(...)) with direct interface method calls
- [ ] Build and test Phase 2

### Phase 3 Batch 1: string[] Return Types
- [ ] IJsonToolService: change GetReplicateNames return to string[]
- [ ] IJsonToolService: change GetSettingsListTypes return to string[]
- [ ] IJsonToolService: change GetSettingsListNames return to string[]
- [ ] IJsonToolService: change GetSettingsListSelectedItems return to string[]
- [ ] JsonToolServer: update implementations to return string[]
- [ ] SkylineConnection: update proxy methods to use CallTyped<string[]>
- [ ] SkylineTools: format string[] results for MCP display
- [ ] Tests: update assertions for array return types
- [ ] Build and test Phase 3

## Session Log

### Session 1 (2026-03-21)
- Created branch and TODO
- Starting Phase 1: JSON-RPC 2.0 wire protocol
