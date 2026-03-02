  ## Branch Information
  - **Branch**: `Skyline/work/20260222_skyline_mcp`
  - **Base**: `master`
  - **Created**: 2026-02-22
  - **Status**: In Progress
  - **GitHub Issue**: (pending)
  - **PR**: (pending)

  ## Overview

  Implement an MCP server that enables LLM applications (Claude Desktop, Claude Code) to interact with a running
  Skyline instance through natural language. This builds on the architecture established in PR #3989 (C# .NET MCP
  server) and Skyline's existing Interactive External Tool infrastructure.

  ## PR Scope

  Phase 1 (Connector) + Phase 2 (MCP Server) + Phase 3a (Read-Only Tools). This gives an end-to-end demo: user
  launches connector from Skyline, then queries Skyline from Claude.

  ## Architecture: Direct JSON Pipe (2-Tier)

  Skyline hosts a JSON named pipe server (`JsonToolServer`) directly in the Skyline process,
  eliminating the connector as a protocol bridge. The connector is now a thin UI shell that
  reads `connection.json` and deploys the MCP server.

  **Before (3-tier, sessions 1-4):**
  ```
  MCP Server <-> JSON pipe <-> Connector (bridge) <-> BinaryFormatter <-> Skyline
  ```

  **After (2-tier, session 5+):**
  ```
  Claude Code ──stdio──> SkylineMcpServer (.NET 8.0)
                             │ JSON over named pipe
                             v
                         Skyline.exe (JsonToolServer -> ToolService methods)
  ```

  ### Why Direct Instead of Bridge

  - **2 files per new method** instead of 5 (JsonToolServer.cs + SkylineTools.cs)
  - **No SkylineTool.dll dependency** in connector - eliminates Release/Debug DLL mismatch
  - **IToolService untouched** - reverted to master; MCP methods live exclusively in JsonToolServer
  - **Direct access to Install.Version** - returns dots + git hash (e.g. `25.1.1.417-66d74a0772`)
  - **Future: file-based reports** - JsonToolServer can write temp files directly from Skyline
  - **ToolService keeps implementations** - RunCommand, settings list methods remain as public
    non-interface methods callable by JsonToolServer

  ### Three-Process Design

  | Process | Framework | Lifecycle | Role |
  |---------|-----------|-----------|------|
  | **Skyline.exe** | .NET Framework 4.7.2 | User-launched | Hosts JsonToolServer (JSON pipe) + ToolService |
  | **SkylineMcpConnector** | .NET Framework 4.7.2 | Launched from Skyline External Tools | UI shell: reads connection.json, deploys MCP server |
  | **SkylineMcpServer** | .NET 8.0-windows | Launched by Claude Code/Desktop | MCP stdio server, connects to Skyline's JSON pipe |

  ## Reference Materials

  - **PR #3989**: https://github.com/ProteoWizard/pwiz/pull/3989 (ImageComparer MCP - working C# MCP reference)
  - **C# MCP Pitfalls**: `ai/docs/mcp/development-guide.md` -> "C# MCP Servers (.NET)" section
  - **ImageComparer MCP docs**: `ai/docs/mcp/image-comparer.md`
  - **ImageComparer MCP source**: `pwiz_tools/Skyline/Executables/DevTools/ImageComparer.Mcp/` (Program.cs pattern,
   csproj, tool structure)
  - **ImageComparer Core source**: `pwiz_tools/Skyline/Executables/DevTools/ImageComparer.Core/` (multi-target
  netstandard2.0+net472 pattern)
  - **Interactive Tool Support Doc**: https://skyline.ms/labkey/_webdav/home/software/Skyline/@files/docs/Skyline%2
  0Interactive%20Tool%20Support-3_1.pdf
  - **Example Interactive Tool**: `pwiz_tools/Skyline/Executables/Tools/ExampleInteractiveTool/` (tool-inf pattern,
   SkylineToolClient usage, .csproj reference pattern)
  - **SkylineTool.dll source**: `pwiz_tools/Skyline/SkylineTool/` (SkylineToolClient.cs, RemoteBase.cs,
  RemoteClient.cs, RemoteService.cs, IToolService.cs)

  ## C# MCP Implementation Notes

  All three pitfalls from ImageComparer MCP apply. See `ai/docs/mcp/development-guide.md`.

  1. **Clear logging providers** - `builder.Logging.ClearProviders()` before `AddMcpServer()`
  2. **Isolate child process stdin** - If the MCP server ever shells out, use `RedirectStandardInput=true` +
  `Close()`. Not needed for JSON pipe communication, but important if SkylineCmd integration is added later.
  3. **Forward-slash paths** - `GetDocumentPath()` returns backslash paths. Any path returned to the MCP client
  needs `path.Replace('\\', '/')`.

  ## JSON Pipe Protocol

  Simple JSON-over-named-pipe protocol between the MCP server and the connector bridge.

  ### Message Framing

  Uses `PipeTransmissionMode.Message` on Windows named pipes. Each JSON message is sent as UTF-8 bytes in a single
  pipe message. The pipe handles message boundaries natively (via `IsMessageComplete`).

  ### Request Format

  ```json
  {"method": "GetDocumentPath", "args": []}
  {"method": "GetReport", "args": ["Peak Area"]}
  {"method": "GetSelectedElementLocator", "args": ["Molecule"]}
  ```

  ### Response Format

  ```json
  {"result": "C:/path/to/document.sky"}
  {"result": 12345}
  {"result": null}
  {"error": "Skyline is busy or showing a modal dialog"}
  ```

  ### Dispatch Table (JsonToolServer -> ToolService)

  | JSON method | ToolService call | Return type | JSON result type |
  |-------------|-----------------|-------------|-----------------|
  | `GetDocumentPath` | `GetDocumentPath()` | string | string (forward slashes) |
  | `GetVersion` | `Install.Version` (direct) | string | string "25.1.1.417-hash" |
  | `GetDocumentLocationName` | `GetDocumentLocationName()` | string | string |
  | `GetReplicateName` | `GetReplicateName()` | string | string |
  | `GetProcessId` | `GetProcessId()` | int | number |
  | `GetReport` | `GetReport("MCP", args[0])` | string | string (CSV directly) |
  | `GetReportFromDefinition` | `GetReportFromDefinition(args[0])` | string | string (CSV directly) |
  | `GetSelectedElementLocator` | `GetSelectedElementLocator(args[0])` | string | string |
  | `RunCommand` | `RunCommand(args[0])` | string | string |
  | `GetSettingsListTypes` | `GetSettingsListTypes()` | string | string (TSV) |
  | `GetSettingsListNames` | `GetSettingsListNames(args[0])` | string | string |
  | `GetSettingsListItem` | `GetSettingsListItem(args[0], args[1])` | string | string (XML) |

  Note: ToolService.GetReport() already returns CSV as a string. No IReport-to-CSV conversion needed.

  ---

  ## Phase 1: SkylineMcpConnector

  ### Project Location
  `pwiz_tools/Skyline/Executables/Tools/SkylineMcpConnector/`

  ### Files to Create

  ```
  SkylineMcpConnector/
  +-- SkylineMcpConnector.sln
  +-- SkylineMcpConnector.csproj       (net472 WinForms)
  +-- Program.cs                        (entry point)
  +-- MainForm.cs                       (UI + lifecycle)
  +-- MainForm.Designer.cs              (designer)
  +-- MainForm.resx                     (resources)
  +-- ConnectionInfo.cs                 (POCO for connection.json)
  +-- JsonPipeServer.cs                 (JSON named pipe server - bridge)
  +-- Properties/
  |   +-- AssemblyInfo.cs
  +-- tool-inf/
      +-- info.properties
      +-- SkylineMcpConnector.properties
  ```

  ### Tasks

  - [ ] Create `SkylineMcpConnector.csproj` - net472 WinForms, reference SkylineTool.dll from
  `..\..\..\..\bin\$(Platform)\$(Configuration)\SkylineTool.dll`, NuGet reference `System.Text.Json` for JSON on
  .NET 4.7.2. Follow ExampleInteractiveTool.csproj pattern for platform configs (x86, x64, AnyCPU).
  - [ ] Create `Program.cs` - `[STAThread] Main(string[] args)`, standard WinForms Application.Run(new
  MainForm(args))
  - [ ] Create `ConnectionInfo.cs` - POCO with PipeName, ProcessId, ConnectedAt, SkylineVersion, DocumentPath.
  Serialize with `System.Text.Json.JsonSerializer`.
  - [ ] Create `MainForm.cs` - On load: create SkylineToolClient(args[0], "Skyline MCP Connector"), query metadata
  (GetDocumentPath, GetSkylineVersion, GetProcessId), start JsonPipeServer, write connection.json. UI: "Connected
  to Skyline" label, document path, version, "Disconnect" button. On close: stop server, delete connection.json,
  dispose client.
  - [ ] Create `JsonPipeServer.cs` - Background thread named pipe server. Creates `NamedPipeServerStream` with
  message mode. Accepts connections in a loop. Reads JSON request, dispatches to SkylineToolClient method, writes
  JSON response. The SkylineToolClient ref is passed in constructor. Method dispatch via switch on method name
  string.
  - [ ] Create `tool-inf/info.properties` and `tool-inf/SkylineMcpConnector.properties`
  - [ ] Create `SkylineMcpConnector.sln`

  ### Connection File

  **Location**: `%LOCALAPPDATA%\Skyline\mcp\connection.json` (follows Skyline conventions)

  ```json
  {
    "pipe_name": "SkylineMcpBridge-{GUID}",
    "process_id": 12345,
    "connected_at": "2026-02-22T10:30:00Z",
    "skyline_version": "24.2.0.0",
    "document_path": "C:/path/to/document.sky"
  }
  ```

  Note: `pipe_name` is the BRIDGE pipe (JSON protocol), NOT Skyline's BinaryFormatter pipe. The MCP server connects
   to this bridge pipe.

  ### Connection Lifecycle

  - **Stale files on crash**: If the connector crashes, connection.json remains. MCP server validates by checking
  if `process_id` is alive before attempting pipe connection.
  - **Multiple instances**: Current design overwrites connection.json. Future enhancement: use
  `connection-{GUID}.json` pattern.
  - **Cleanup**: On normal close/disconnect, delete connection.json.

  ### tool-inf/info.properties

  ```
  Name = Skyline MCP Connector
  Version = 1.0
  Author = Brendan MacLean
  Description = Connects Skyline to Claude AI via MCP protocol
  Organization = MacCoss Lab, UW
  Languages = C#
  Provider = https://skyline.ms
  Identifier = URN:LSID:proteome.gs.washington.edu:SkylineMcpConnector
  ```

  ### tool-inf/SkylineMcpConnector.properties

  ```
  Title = Connect to Claude
  Command = SkylineMcpConnector.exe
  Arguments = $(SkylineConnection)
  ```

  ### Key Implementation Details

  **SkylineTool.dll reference**: Same pattern as ExampleInteractiveTool - `HintPath` to
  `..\..\..\..\bin\$(Platform)\$(Configuration)\SkylineTool.dll` with `SpecificVersion=False`.

  **System.Text.Json on .NET 4.7.2**: Available as NuGet package `System.Text.Json` (version 8.0.x). Requires
  `System.Memory`, `System.Buffers`, `System.Runtime.CompilerServices.Unsafe` as transitive dependencies. These are
   handled automatically by NuGet.

  **JsonPipeServer threading**: The server runs on a background thread. Each client connection is handled on the
  accepting thread (one at a time, since the MCP server makes sequential requests). Uses `NamedPipeServerStream`
  with `PipeDirection.InOut`, `maxNumberOfServerInstances: 1`, `PipeTransmissionMode.Message`.

  **SkylineToolClient thread safety**: SkylineToolClient methods dispatch to Skyline's UI thread via named pipe
  RPC. The 1-second timeout applies. The JsonPipeServer can call SkylineToolClient methods directly from its
  background thread - the named pipe handles the cross-process marshaling.

  ---

  ## Phase 2: SkylineMcpServer

  ### Project Location
  `pwiz_tools/Skyline/Executables/Tools/SkylineMcpServer/`

  ### Files to Create

  ```
  SkylineMcpServer/
  +-- SkylineMcpServer.sln
  +-- SkylineMcpServer.csproj          (net8.0-windows)
  +-- Program.cs                        (MCP server setup)
  +-- SkylineConnection.cs              (reads connection.json, JSON pipe client)
  +-- Tools/
      +-- SkylineTools.cs               (MCP tool implementations)
  ```

  Plus setup script: `ai/mcp/SkylineMcp/Setup-SkylineMcp.ps1`

  ### Tasks

  - [ ] Create `SkylineMcpServer.csproj` - net8.0-windows, RuntimeIdentifier win-x64, NuGet ModelContextProtocol
  0.8.0-preview.1 + Microsoft.Extensions.Hosting 8.0.1. Follow ImageComparer.Mcp.csproj pattern.
  - [ ] Create `Program.cs` - ClearProviders, AddMcpServer, WithStdioServerTransport, WithToolsFromAssembly. Note:
  `await` is acceptable here - this is a .NET 8.0 standalone app, NOT Skyline code (the no-async rule applies to
  `pwiz_tools/Skyline/` Skyline code).
  - [ ] Create `SkylineConnection.cs` - Reads `%LOCALAPPDATA%/Skyline/mcp/connection.json`, validates PID is alive,
   connects to bridge pipe, provides `Call(method, args)` method that sends JSON request and returns parsed
  response.
  - [ ] Create `Tools/SkylineTools.cs` - MCP tool implementations for Phase 3a tools. Each tool creates/reuses a
  SkylineConnection, calls the appropriate method, formats the response.
  - [ ] Create `Setup-SkylineMcp.ps1` - Script to register MCP server with Claude Code: `claude mcp add skyline --
  path/to/SkylineMcpServer.exe`
  - [ ] Create `SkylineMcpServer.sln`

  ### SkylineConnection.cs Key Design

  ```
  static Connect() -> SkylineConnection
    1. Determine path: %LOCALAPPDATA%/Skyline/mcp/connection.json
    2. If file missing -> throw with "Launch 'Connect to Claude' from Skyline's External Tools menu"
    3. Deserialize ConnectionInfo
    4. Check Process.GetProcessById(processId) is alive -> if dead, throw "Skyline process {pid} is no longer
  running. Please reconnect."
    5. Create NamedPipeClientStream to pipe_name with 5-second timeout
    6. Set ReadMode = PipeTransmissionMode.Message
    7. Return SkylineConnection wrapping the pipe

  Call(string method, params string[] args) -> string
    1. Serialize {"method": method, "args": args} to UTF-8 bytes
    2. Write to pipe
    3. Read response (using ReadAllBytes loop with IsMessageComplete)
    4. Parse JSON response
    5. If "error" field present, throw exception
    6. Return "result" field as string
  ```

  ### Error Messages

  | Condition | Message |
  |-----------|---------|
  | No connection.json | "Skyline is not connected. Launch 'Connect to Claude' from Skyline's External Tools menu."
   |
  | Stale PID | "Skyline process {pid} is no longer running. Launch 'Connect to Claude' from Skyline to reconnect."
   |
  | Pipe timeout | "Skyline is not responding. It may be busy processing data or showing a dialog. Try again in a
  moment." |
  | Pipe broken | "Connection to Skyline was lost. Launch 'Connect to Claude' from Skyline to reconnect." |

  ---

  ## Phase 3a: Read-Only MCP Tools

  ### Tool Implementations

  All tools are in `Tools/SkylineTools.cs` as `[McpServerToolType]` class with `[McpServerTool]` methods.

  | MCP Tool | Description (for LLM) | Connector Method | Notes |
  |----------|----------------------|-----------------|-------|
  | `skyline_get_document_path` | "Get the file path of the currently open Skyline document" | `GetDocumentPath` |
  Normalize backslash -> forward slash |
  | `skyline_get_version` | "Get the version of the running Skyline instance" | `GetVersion` | Returns
  "Major.Minor.Build.Revision" |
  | `skyline_get_selection` | "Get the currently selected element in Skyline (protein, peptide, precursor, etc.)" |
   `GetDocumentLocationName` | May be empty if nothing selected |
  | `skyline_get_replicate` | "Get the name of the currently active replicate in Skyline" | `GetReplicateName` |
  May be empty |
  | `skyline_get_report` | "Run a named Skyline report and save results to CSV file. Returns row count, column
  names, preview rows, and file path." | `GetReport` | **File-based pattern** |
  | `skyline_get_report_from_definition` | "Run a custom Skyline report from XML definition and save results to CSV
   file." | `GetReportFromDefinition` | **File-based pattern** |

  ### File-Based Report Pattern

  Reports can return thousands of rows. Following `ai/docs/mcp/development-guide.md`:

  1. Call connector `GetReport(reportName)` -> returns CSV string
  2. Save CSV to `ai/.tmp/skyline-report-{name}-{timestamp}.csv`
  3. Parse first few rows for preview
  4. Return to Claude:
     ```
     Report: {reportName}
     Rows: {count}
     Columns: {col1}, {col2}, {col3}, ...

     Preview (first 5 rows):
     {col1}  {col2}  {col3}
     val1    val2    val3
     ...

     Full data saved to: ai/.tmp/skyline-report-{name}-{timestamp}.csv
     Use Read or Grep tools to explore the full dataset.
     ```

  ### ai/.tmp Path Discovery

  The MCP server needs to find `ai/.tmp/`. Options:
  - Environment variable (set by setup script)
  - Hardcoded relative to known path
  - Convention: look for `ai/.tmp/` relative to the Skyline document path (walking up)

  **Decision**: Use environment variable `SKYLINE_MCP_TMP_DIR` set in the setup script, with fallback to
  `%LOCALAPPDATA%/Skyline/mcp/tmp/`.

  ---

  ## Wire Protocol: BinaryFormatter -> JSON (Future PR)

  Deferred to a follow-up PR. The plan from the original design is preserved here for reference.

  **SkylineTool.dll** targets .NET Framework 4.7.2 and uses `BinaryFormatter` for named pipe serialization
  (`RemoteBase.cs`). The MCP server targets .NET 8.0, where `BinaryFormatter` is obsoleted and throws
  `PlatformNotSupportedException` by default.

  ### Original Plan (deferred)

  1. Create a multi-target `SkylineTool.Core` library (`net472;netstandard2.0`) with JSON-based `RemoteBase`
  replacement
  2. Define POCO classes for `RemoteInvoke` and `RemoteResponse` with `[JsonPropertyName]` attributes
  3. Both Skyline (server) and MCP server (client) reference SkylineTool.Core
  4. Existing `SkylineTool.dll` external tools continue to work during migration

  ### Why Deferred

  The bridge pattern in this PR avoids the wire protocol change entirely. The Connector (.NET 4.7.2) uses the
  existing SkylineToolClient with BinaryFormatter to communicate with Skyline, and exposes a simple JSON pipe for
  the MCP server. This eliminates the need to modify Skyline core or create SkylineTool.Core.

  When the wire protocol is modernized in a future PR:
  - The bridge can be eliminated (MCP server connects directly to Skyline's JSON pipe)
  - Or the bridge can remain as a useful isolation layer

  ### Wire Protocol Research Notes

  **Types flowing through BinaryFormatter** (from RemoteBase.cs analysis):
  - `RemoteInvoke` [Serializable]: `string MethodName`, `object[] Arguments`
  - `RemoteResponse` [Serializable]: `object ReturnValue`, `Exception Exception`

  **Argument/return types in IToolService.cs**:
  - Most methods use primitives: `string`, `int`, `string[]`
  - `Version` [Serializable]: 4 ints (Major, Minor, Build, Revision)
  - `DocumentLocation` [Serializable, Obsolete]: `IList<int>` IdPath, nullable ints
  - `Chromatogram` [Serializable, Obsolete]: contains `System.Drawing.Color` (problematic for JSON)
  - `IReport`: returned as string by SkylineToolClient (already converted to CSV internally)

  **Message framing**: `PipeTransmissionMode.Message` on Windows named pipes. `ReadAllBytes()` loops with 65KB
  buffer until `IsMessageComplete`. No explicit length prefix needed.

  ---

  ## Full SkylineToolClient API Surface

  Verified by reading source at `pwiz_tools/Skyline/SkylineTool/SkylineToolClient.cs`:

  ### Methods Exposed via Bridge (this PR)
  - `GetReport(string reportName)` -> IReport (converted to CSV string)
  - `GetReportFromDefinition(string reportDefinition)` -> IReport (converted to CSV string)
  - `GetDocumentLocationName()` -> string
  - `GetReplicateName()` -> string
  - `GetDocumentPath()` -> string
  - `GetSkylineVersion()` -> Version (converted to string)
  - `GetProcessId()` -> int
  - `GetSelectedElementLocator(string elementType)` -> string

  ### Available for Future Phases (not in this PR)
  - `ImportFasta(string textFasta)` - adds proteins from FASTA text
  - `InsertSmallMoleculeTransitionList(string textCSV)` - adds small molecules
  - `AddSpectralLibrary(string libraryName, string libraryPath)` - adds spectral library
  - `DeleteElements(string[] elementLocators)` - deletes document elements
  - `ImportProperties(string propertiesCsv)` - imports custom properties
  - `ImportPeakBoundaries(string peakBoundariesCsv)` - imports peak boundaries
  - `GetDocumentLocation()` / `SetDocumentLocation()` - obsolete but functional
  - `GetChromatograms(DocumentLocation)` - obsolete
  - `DocumentChanged` / `SelectionChanged` events

  ### Not in API (would need Skyline changes or SkylineCmd)
  - Importing results files
  - Modifying instrument/transition/full-scan settings
  - Saving document
  - Undo/redo operations

  ---

  ## Implementation Order

  1. **SkylineMcpConnector scaffolding** - csproj, sln, Program.cs, AssemblyInfo.cs
  2. **ConnectionInfo.cs** - POCO + JSON serialization
  3. **MainForm** - UI, SkylineToolClient connection, connection file lifecycle
  4. **JsonPipeServer** - Bridge: JSON pipe server dispatching to SkylineToolClient
  5. **tool-inf/** - Tool metadata for Skyline External Tools menu
  6. **SkylineMcpServer scaffolding** - csproj, sln, Program.cs
  7. **SkylineConnection.cs** - Connection file reader + JSON pipe client
  8. **SkylineTools.cs** - MCP tool implementations (Phase 3a)
  9. **Setup-SkylineMcp.ps1** - Claude Code registration script

  ---

  ## Verification

  ### Manual Test Flow
  1. Build SkylineMcpConnector (`dotnet build` or VS)
  2. Install as Skyline External Tool (add ZIP, or copy to Tools folder)
  3. Open Skyline with a document, launch "Connect to Claude" from External Tools menu
  4. Verify connection.json written to `%LOCALAPPDATA%/Skyline/mcp/`
  5. Build SkylineMcpServer (`dotnet build`)
  6. Register with Claude Code: `claude mcp add skyline -- C:/proj/pwiz/.../SkylineMcpServer.exe`
  7. In Claude Code: "What document is open in Skyline?" -> should return forward-slash path
  8. "What version of Skyline is running?" -> should return version string
  9. "Show me a Peak Area report" -> should save CSV to ai/.tmp/ and return summary
  10. Close Skyline -> try tool call -> should get "process no longer running" error
  11. Without connector running -> try tool call -> should get "Launch Connect to Claude" error

  ### Example Prompts to Validate (ASMS 2026 demo)

  - "What document is open in Skyline?" -> `skyline_get_document_path`
  - "What peptides are in this document?" -> `skyline_get_report` with appropriate report
  - "What version of Skyline is running?" -> `skyline_get_version`
  - "Show peptides with CV above 20% in QC samples" -> `skyline_get_report_from_definition` + LLM analysis

  ### Future Phase Prompts (stretch goals, not this PR)
  - "Please add APOA1 to the document" -> LLM provides FASTA, calls `ImportFasta`
  - "Add Acetyl-CoA to the document" -> LLM provides CSV transition list, calls `InsertSmallMoleculeTransitionList`

  ---

  ## Success Criteria for ASMS 2026 (June)

  Minimum viable demo (achievable with this PR):
  1. User installs Claude Desktop + registers Skyline MCP server
  2. User opens Skyline document, clicks "Connect to Claude" in External Tools
  3. User asks Claude: "What peptides are in this document?"
  4. Claude queries Skyline via MCP and responds with peptide list
  5. User asks: "Show me which have CV > 20%"
  6. Claude generates report and interprets results

  ---

  ## Session Log

  ### 2026-02-22: Initial planning session
  - Explored full API surface, wire protocol, ExampleInteractiveTool and ImageComparer.Mcp patterns
  - Key decisions: Bridge pattern (no Skyline core changes), connection file at %LOCALAPPDATA%, JSON pipe protocol
  - Created branch and TODO

  ### 2026-02-27: Implementation session
  - Reset branch to current master head (7b1a2a7bcb)
  - Implemented all Phase 1 + Phase 2 + Phase 3a code:
    - SkylineMcpConnector: SDK-style net472 csproj, Program.cs, MainForm, ConnectionInfo, JsonPipeServer, tool-inf
    - SkylineMcpServer: net8.0-windows csproj, Program.cs, SkylineConnection, Tools/SkylineTools
    - Setup script: ai/mcp/SkylineMcp/Setup-SkylineMcp.ps1
  - Build issues resolved:
    - Old-style csproj with PackageReference doesn't work with `dotnet build` — converted to SDK-style `net472`
    - `SkylineTool.Version` vs `System.Version` ambiguity — use `var`
    - .NET SDK 10 does not enable implicit usings — add explicit `using System;` etc.
  - Both projects build cleanly with zero warnings
  - Installed connector into Skyline via External Tools (ZIP package)
  - Registered MCP server with Claude Code via setup script
  - End-to-end test: connector writes connection.json, bridge pipe responds correctly
  - **Bug found**: `System.Text.Json` case-sensitive deserialization — MCP server's `ConnectionInfo`
    POCO lacked `[JsonPropertyName("pipe_name")]` attributes, so `PipeName` deserialized as empty string.
    The connector writes snake_case JSON keys but the server expected PascalCase.
    Fix applied but not yet rebuilt/tested (exe locked by running Claude Code process).

  ### 2026-02-27: End-to-end verification (session 2)
  - Rebuilt SkylineMcpServer with JsonPropertyName fix
  - **End-to-end working!** All basic tools verified:
    - `skyline_get_version` → `26,1,0,57`
    - `skyline_get_document_path` → returns full path with forward slashes
    - `skyline_get_selection` → returns selected protein name
    - `skyline_get_replicate` → returns active replicate name
  - `skyline_get_report` fails with generic error — needs debugging (deferred)
  - **Architecture discussion**: Reports should NOT flow through the named pipe as escaped JSON.
    Skyline should write reports directly to disk (CSV or parquet), returning only the file path
    through the pipe. Current pipe-based approach works as proof of concept but won't scale.
    Nick's parquet export support makes this even more compelling.
  - **Deployment architecture decision**: The tool must be self-contained for Tool Store users.
    The `ai/mcp/SkylineMcp/Setup-SkylineMcp.ps1` pattern is wrong — that's for developer tools.
    SkylineMcp targets Skyline users who never get the pwiz repo. Single .sln, single tool ZIP,
    connector handles MCP server deployment to `~/.skyline-mcp/`.

  ### 2026-02-27: Phase 4 reorganization (session 3)
  - Restructured into single `SkylineMcp/` parent with `SkylineMcp.sln`
  - Added `McpServerDeployer.cs` — copies MCP server from `mcp-server/` to `~/.skyline-mcp/`
  - Updated connector UI: "Claude Code Setup" section with copyable `claude mcp add` command
  - Added MSBuild `PackageToolZip` target — builds both projects, stages into `SkylineMcp/` dir
    under `bin/`, zips to `SkylineMcp.zip` (developer can also manually zip the staging dir)
  - Deleted `ai/mcp/SkylineMcp/Setup-SkylineMcp.ps1` (wrong pattern for user-facing tool)
  - End-to-end verified: install ZIP → launch connector → deploy MCP server → register → query Skyline
  - Initial commit pushed to branch

  ### 2026-02-28: RunCommand and --help sections (session 4)
  - **RunCommand implemented end-to-end** across all layers:
    - `IToolService.cs`: Added `string RunCommand(string args)` to interface
    - `ToolService.cs`: Implementation uses `CommandLine.ParseArgs()` + `CommandLine.Run()` with
      a TeeTextWriter that captures output AND echoes to Immediate Window
    - `CommandLine.cs`: Added optional `SrmDocument doc` parameter to constructor so the
      currently open document can be passed in (avoids "Use --in" error)
    - `CommandStatusWriter.cs`: Added `Write(string)` override — was missing, causing
      text to go through `Write(char)` which TextBoxStreamWriter couldn't handle
    - `SkylineToolClient.cs`: Added `RunCommand(string args)` wrapper
    - `JsonPipeServer.cs`: Added `RunCommand` dispatch case
    - `SkylineTools.cs`: Added `skyline_run_command` MCP tool
  - **Threading**: RunCommand runs on the pipe server background thread (not UI thread).
    Immediate Window echoing uses `Invoke` for initial show/echo (must complete before
    accessing Writer), then TeeWriter handles cross-thread writes via TextBoxStreamWriter's
    built-in BeginInvoke. UI stays responsive during long commands.
  - **Immediate Window audit trail**: Commands are echoed as if the user typed them,
    followed by output. Users can copy command lines into `--batch-commands` files
    for reproducibility.
  - **--help=sections**: Lists all 27 ArgumentGroup titles (compact for LLM context)
  - **--help=<section-name>**: Shows matching section(s) using case-insensitive substring
    match with ASCII table formatting. E.g. `--help=report` shows "Exporting reports" section.
    - Added `HasValueChecking = true` to `ARG_HELP` so arbitrary section names pass validation
    - Added resource string for "no section found" error message
    - Uses `ARG_VALUE_ASCII` formatting for section help (Unicode box chars don't display
      in Immediate Window, but ASCII `+|-` borders do). Note: Immediate Window uses
      proportional font so tables still don't look great — consider `no-borders` instead.
  - **Connector bug**: `SkylineToolClient.Dispose()` throws `IOException` when Skyline is
    killed. Added try/catch in `MainForm.Cleanup()` to handle broken pipe gracefully.
  - **Verified working**: `--version`, `--report-name="Precursor Areas" --report-file=...`,
    `--help=sections`, `--help=report`, `--help=foobar` (error message)

  #### Remaining issues from this session
  - Immediate Window uses proportional font — ASCII table borders don't align well.
    Consider using `no-borders` format, or making section help just list args without tables.
  - CommandLine `_doc` is set from `SkylineWindow.Document` for read-only operations.
    Write operations (import, refine, etc.) need `IDocumentContainer` integration so
    `ModifyDocument()` flows through `SkylineWindow.ModifyDocument()` for proper
    audit log and undo/redo. This is a future enhancement.
  - The connector IOException fix needs rebuilding and testing.
  - Not yet committed — all changes are uncommitted on the branch.

  ### 2026-02-28: Rearchitect to 2-tier direct JSON pipe (session 5)
  - **Major architecture change**: Moved JSON pipe server from connector into Skyline process
  - Created `JsonToolServer.cs` in `ToolsUI/` - hosts JSON named pipe directly in Skyline,
    dispatches to ToolService methods without BinaryFormatter serialization
  - Reverted `IToolService.cs` and `SkylineToolClient.cs` to master HEAD - no MCP methods
    on the external tool interface. RunCommand, settings list methods stay as public
    non-interface methods on ToolService, callable by JsonToolServer directly.
  - Simplified connector `MainForm.cs` - now just reads connection.json and deploys MCP server.
    Removed SkylineToolClient, JsonPipeServer, and SkylineTool.dll dependency entirely.
  - `Program.cs` creates/disposes JsonToolServer alongside ToolService in Start/StopToolService()
  - **Version improvement**: GetVersion now returns `Install.Version` directly (dots + git hash,
    e.g. `25.1.1.417-66d74a0772`) instead of comma-separated `SkylineTool.Version.ToString()`
  - **connection.json lifecycle**: JsonToolServer writes on Start(), deletes on Dispose().
    Connector also cleans up on exit as a safety net.
  - Both Skyline and SkylineMcp solutions build cleanly
  - All MCP tools verified working end-to-end through the new direct pipe
  - **Design discussion**: Reports (GetReport, GetReportFromDefinition) should be redesigned
    for MCP. Current in-memory pipe approach doesn't scale. Next round will:
    1. Make reports write to files natively in JsonToolServer
    2. Add report field documentation access (like --help=sections for CLI)
    3. Design a simplified JSON query format for LLMs (abstraction over XML report format)
  - Deleted stale `TODO-20260222_skyline_mcp-revised.md`

  #### Key files changed
  - NEW: `pwiz_tools/Skyline/ToolsUI/JsonToolServer.cs`
  - REVERTED: `pwiz_tools/Skyline/SkylineTool/IToolService.cs` (master HEAD)
  - REVERTED: `pwiz_tools/Skyline/SkylineTool/SkylineToolClient.cs` (master HEAD)
  - MODIFIED: `pwiz_tools/Skyline/Program.cs` (JsonToolServer lifecycle)
  - MODIFIED: `pwiz_tools/Skyline/Skyline.csproj` (added JsonToolServer.cs)
  - MODIFIED: `SkylineMcpConnector/MainForm.cs` (simplified, no more bridge)
  - MODIFIED: `SkylineMcpConnector/SkylineMcpConnector.csproj` (removed SkylineTool.dll ref)
  - DELETED: `SkylineMcpConnector/JsonPipeServer.cs` (moved into Skyline as JsonToolServer)

  ---

  ## Phase 4: Project Reorganization and Deployment

  ### Problem

  Current structure has two separate .sln files and requires a developer setup script
  (`ai/mcp/SkylineMcp/Setup-SkylineMcp.ps1`) to register the MCP server. This works for a
  developer with the pwiz repo, but fails completely for the target audience: a Skyline user
  who downloads the tool from the Skyline Tool Store and has never seen the pwiz repository.

  ### Goal

  A Skyline user installs from Tool Store, clicks **Tools > Connect to Claude**, and gets
  guided through the complete setup. No scripts, no repo, no manual file copying.

  ### New Folder Structure

  ```
  pwiz_tools/Skyline/Executables/Tools/SkylineMcp/
  ├── SkylineMcp.sln                          (single solution, both projects)
  ├── SkylineMcpConnector/
  │   ├── SkylineMcpConnector.csproj          (net472 WinForms)
  │   ├── Program.cs
  │   ├── MainForm.cs                         (updated: deployment + setup UI)
  │   ├── MainForm.Designer.cs
  │   ├── MainForm.resx
  │   ├── ConnectionInfo.cs
  │   ├── JsonPipeServer.cs
  │   └── tool-inf/
  │       ├── info.properties
  │       └── SkylineMcpConnector.properties
  └── SkylineMcpServer/
      ├── SkylineMcpServer.csproj             (net8.0-windows)
      ├── Program.cs
      ├── SkylineConnection.cs
      └── Tools/
          └── SkylineTools.cs
  ```

  ### Tasks

  #### 4.1: Restructure folders
  - [ ] Create `SkylineMcp/` parent directory
  - [ ] Move `SkylineMcpConnector/` and `SkylineMcpServer/` under it
  - [ ] Delete individual `.sln` files from each project
  - [ ] Create `SkylineMcp.sln` containing both projects
  - [ ] Verify both projects build from the new .sln
  - [ ] Update SkylineMcpConnector.csproj `HintPath` for SkylineTool.dll (relative path changes)

  #### 4.2: MCP server deployment logic in connector
  - [ ] On startup, connector deploys MCP server to `~/.skyline-mcp/`:
    - Determine MCP server source: same directory as connector exe (Skyline installs
      the tool ZIP contents to its tools folder, so the MCP server binaries will be there)
    - Target: `%USERPROFILE%/.skyline-mcp/` (following `.gmail-mcp`, `.teamcity-mcp` pattern)
    - Copy `SkylineMcpServer.exe` + all its dependencies to the target directory
    - Only copy if missing or version differs (compare file dates or assembly version)
  - [ ] The MCP server binaries must be included in the tool ZIP alongside the connector.
    This means the build/package step needs to collect both sets of outputs.

  #### 4.3: Update connector UI for setup help
  - [ ] Add MCP registration status detection:
    - Check if `~/.claude.json` or `~/.claude/` contains a skyline MCP entry
    - Or simply show the registration command always with a note
  - [ ] Add a "Setup" section to the UI:
    - Copyable command: `claude mcp add skyline -- C:/Users/{user}/.skyline-mcp/SkylineMcpServer.exe`
    - "Copy to Clipboard" button
    - Brief instructions: "Paste this command in your terminal, then restart Claude Code"
  - [ ] Future: When MCP installation file format ships, generate/point to that file instead

  #### 4.4: Tool ZIP packaging
  - [ ] The tool ZIP for Skyline Tool Store must contain:
    ```
    tool-inf/
        info.properties
        SkylineMcpConnector.properties
    SkylineMcpConnector.exe           (net472)
    SkylineMcpConnector.exe.config
    SkylineTool.dll
    System.Text.Json.dll              (+ transitive deps for net472)
    mcp-server/                       (subfolder for net8.0 binaries)
        SkylineMcpServer.exe
        SkylineMcpServer.dll
        SkylineMcpServer.deps.json
        SkylineMcpServer.runtimeconfig.json
        ModelContextProtocol.dll
        Microsoft.Extensions.*.dll
        ... (all net8.0 dependencies)
    ```
  - [ ] The `mcp-server/` subfolder keeps the two runtimes' DLLs from colliding
    (both have System.Text.Json but different versions for net472 vs net8.0)
  - [ ] Connector's deployment logic copies from `mcp-server/` subfolder to `~/.skyline-mcp/`

  #### 4.5: Clean up old artifacts
  - [ ] Delete `ai/mcp/SkylineMcp/Setup-SkylineMcp.ps1` (wrong pattern for user-facing tool)
  - [ ] Delete old `SkylineMcpConnector.zip` and `_package/` from working tree
  - [ ] Remove `SkylineMcpConnector.sln` and `SkylineMcpServer.sln` (replaced by SkylineMcp.sln)

  #### 4.6: Update info.properties for new packaging
  - [ ] Consider renaming the tool identifier to reflect the combined package
  - [ ] Update version, description as needed

  ### Deployment Flow (User Perspective)

  ```
  1. User finds "Skyline MCP Connector" in Skyline Tool Store
  2. User clicks Install → Skyline downloads ZIP, extracts to tools directory
  3. User sees "Connect to Claude" in Tools > External Tools menu
  4. User clicks "Connect to Claude":
     a. Connector launches, connects to Skyline via SkylineToolClient
     b. Connector deploys MCP server to ~/.skyline-mcp/ (first time or update)
     c. Connector starts JSON bridge pipe, writes connection.json
     d. UI shows: "Connected to Skyline" + version + document
     e. UI shows: "MCP Setup" section with copy-paste command for Claude Code
  5. User copies the `claude mcp add` command, pastes in terminal
  6. User restarts Claude Code
  7. User asks Claude: "What document is open in Skyline?" → works!
  ```

  ### Open Questions

  - **Tool Store packaging**: How are Tool Store ZIPs built today? Is there an existing build
    target or script, or do we just create the ZIP manually? Need to understand the current
    process.
  - **MCP server prerequisites**: The MCP server requires .NET 8.0 runtime. Should the
    connector check for this and give a helpful message if missing? Or will the MCP server
    exe itself give a good enough error?
  - **Self-contained publish**: Should we publish the MCP server as self-contained
    (`dotnet publish -r win-x64 --self-contained`) to avoid the .NET 8.0 runtime dependency?
    This increases the ZIP size (~60-80MB) but eliminates the user needing .NET 8.0.
    An alternative is a trimmed self-contained publish which could be much smaller.
  - **Multiple Skyline instances**: Current design uses a single `connection.json`. If the
    user has multiple Skyline instances, only one can connect. Future: use
    `connection-{GUID}.json` pattern and let the MCP server discover/list them.

  ---

  ## Phase 5: Report Architecture (Future)

  ### Problem

  Current report flow pipes entire CSV through the JSON named pipe as an escaped string
  attribute. For a 100K-row report, this means:
  1. Skyline builds IReport in memory
  2. SkylineToolClient serializes via BinaryFormatter over pipe
  3. Connector deserializes, converts to CSV string in memory
  4. CSV gets JSON-escaped and sent over JSON pipe as `{"result": "...giant CSV..."}`
  5. MCP server receives, unescapes, saves to disk

  The entire report exists in memory multiple times. This won't scale.

  ### Solution

  Add a bridge command that tells Skyline to write the report directly to a file:
  - Bridge command: `ExportReport(reportName, filePath, format)`
  - Skyline writes progressively to disk (never fully in memory)
  - Pipe response: just `{"result": "C:/Users/.../report.csv"}` (the path)
  - MCP server returns the path to Claude, which reads it with the Read tool
  - Formats: CSV initially, parquet when Nick's export is available

  This requires either:
  - A new SkylineToolClient API method (needs Skyline core change), or
  - Using SkylineCmd as an alternative for report export (already supports file output)

  ### Temporary Path Convention

  Reports should be written to `ai/.tmp/` when running from a dev environment, or to a
  user-configurable location. The MCP tool should accept an optional output path parameter,
  defaulting to `~/.skyline-mcp/tmp/` for Tool Store users.

  ---

  ## Phase 6: SkylineToolClient API Expansion

  The existing SkylineToolClient API is limited to specific methods (GetReport, ImportFasta, etc.).
  Three new capabilities would massively expand what the MCP server can do.

  ### 6.1: RunCommand — Full CLI access

  Add `RunCommand(string commandLine)` to `IToolService`/`SkylineToolClient`.

  **How it works**: The Immediate Window (`ImmediateWindow.cs`) already does this:
  ```csharp
  string[] args = CommandLine.ParseArgs(lineText);
  CommandLine commandLine = new CommandLine(new CommandStatusWriter(writer));
  commandLine.Run(args, true);
  ```
  The `CommandLine` class (`CommandLine.cs`) processes the full CLI argument set — the same
  1,371-line help output from `SkylineCmd --help`. This includes imports, exports, settings
  changes, refinement, report-to-file, everything.

  **Key design points**:
  - Output should stream back progressively (progress, errors, completion)
  - The `CommandStatusWriter` captures all output as text
  - The `--report-name --report-file` CLI args solve report-to-file natively
  - No `--in` needed since the document is already open in the running instance
  - The Immediate Window proves this pattern works against a running Skyline with live UI

  **Reference files**:
  - `pwiz_tools/Skyline/Controls/ImmediateWindow.cs` — `RunLine()` method
  - `pwiz_tools/Skyline/CommandLine.cs` — `Run()`, `ProcessDocument()`, `ParseArgs()`
  - `pwiz_tools/Skyline/CommandArgs.cs` — all argument definitions (28+ groups)
  - `ai/.tmp/skylinecmd-help.txt` — full CLI help output captured for reference

  ### 6.2: GetSettingsListNames — Query named settings

  Add `GetSettingsListNames(string listType)` → `string[]` to `IToolService`.

  Skyline stores ~28 `SettingsList<T>` types in `Settings.Default`. All items implement
  `IKeyContainer<string>` so `item.GetKey()` returns the name. The `listType` parameter
  is just the class name (e.g., "ReportSpecList", "EnzymeList").

  **Known list types** (from Settings.cs):
  - `ReportSpecList` — report definitions (most important for MCP)
  - `EnzymeList` — enzymes (Trypsin, etc.)
  - `SpectralLibraryList` — loaded spectral libraries
  - `StaticModList` / `HeavyModList` — modifications
  - `PeakScoringModelList` — mProphet models
  - `AnnotationDefList` — custom annotation definitions
  - `ToolList` — external tools
  - `ServerList` — Panorama servers
  - `CollisionEnergyList`, `RetentionTimeList`, `MeasuredIonList`, etc.
  - ~28 total, all following the same pattern

  **Implementation**: Look up the property on `Settings.Default` by class name,
  iterate the list, return `item.GetKey()` for each.

  ### 6.3: GetSettingsListItem — Inspect items as XML

  Add `GetSettingsListItem(string listType, string name)` → `string` (XML).

  Since every item implements `IXmlSerializable`, serialize it and return XML text.
  Claude can inspect report definitions, enzyme rules, modification definitions, etc.

  **Future extension**: `AddSettingsListItem(string listType, string xml)` — parse XML,
  validate, add to the list. Claude could create custom reports, add modifications, etc.

  ### 6.4: Keep GetReportFromDefinition — Ad-hoc query power

  The existing `GetReportFromDefinition(string xml)` API should be maintained and improved,
  not replaced by RunCommand. It is essentially a **query language** over the SrmDocument —
  Claude constructs XML on the fly to query anything Skyline has in memory.

  **Report definition XML format** (modern format):
  ```xml
  <views>
    <view name="MyQuery"
          rowsource="pwiz.Skyline.Model.Databinding.Entities.Transition"
          sublist="Results!*">
      <column name="Precursor.Peptide.Protein.Name" />
      <column name="Precursor.Peptide.ModifiedSequence" />
      <column name="Results!*.Value.Area" />
      <filter column="Results!*.Value.Area" opname="isnotnullorblank" />
    </view>
  </views>
  ```

  **Queryable root types** (rowsource):
  - `pwiz.Skyline.Model.Databinding.Entities.Protein`
  - `pwiz.Skyline.Model.Databinding.Entities.Peptide`
  - `pwiz.Skyline.Model.Databinding.Entities.Precursor`
  - `pwiz.Skyline.Model.Databinding.Entities.Transition`
  - `pwiz.Skyline.Model.Databinding.Entities.Replicate`
  - Also: `ProteinResult`, `PeptideResult`, `PrecursorResult`, `TransitionResult`

  **Property paths**: Dot notation with `!*` for collections:
  - `Precursor.Peptide.Protein.Name` — navigate hierarchy
  - `Results!*.Value.Area` — expand across replicates
  - `Files!*.FileName` — expand across result files

  **User-facing field documentation**: https://skyline.ms/tips/docs/25-1/Help/en/Reports.html
  (Nick's Live Reports framework — very fast materialization of SrmDocument into tabular data)

  **Vision**: Claude queries Skyline data on the fly, writes CSV, then generates R/Python
  scripts with ggplot2 visualizations — same pattern already proven with LabKey Server data.

  ### Implementation Order

  1. ~~`RunCommand` — highest impact, unlocks entire CLI including report-to-file~~ **DONE (session 4)**
     - Read-only operations working. Write operations need IDocumentContainer integration.
  2. `GetSettingsListNames` — enables discovery (what reports exist? what enzymes?)
  3. `GetSettingsListItem` — enables inspection (what does this report query?)
  4. Improve `GetReportFromDefinition` — file-based output, not pipe-based

  With the 2-tier architecture, new methods only need JsonToolServer.cs + SkylineTools.cs (2 files).

  ### Extensibility Mechanism

  The `RemoteService` dispatch uses **reflection** (`GetType().GetMethod(remoteInvoke.MethodName)`)
  — NOT interface-based dispatch. This means:
  - **Adding new methods is safe** — old tools never call them, new tools find them by name
  - **No versioned interfaces needed** (no IToolService2, etc.)
  - Just add the method to `IToolService`, implement in `ToolService`, add wrapper in `SkylineToolClient`
  - If a new tool calls a method on an old Skyline, `GetMethod()` returns null → catch and
    show "please update Skyline" message
  - **Never change existing method signatures** — that would break reflection lookup

  ---

  ## Session Log

  ### 2026-02-28: LLM documentation access tools (session 8)
  - **4 new MCP tools** for LLM-friendly documentation access:
    - `skyline_get_cli_help_sections` — lists CLI help section names
    - `skyline_get_cli_help(section)` — detailed help for a section with `--help=no-borders`
    - `skyline_get_report_doc_topics` — lists report entity types (21 topics)
    - `skyline_get_report_doc_topic(topic)` — column docs (name, description, type) for an entity
  - **Silent RunCommand**: Added `RunCommandSilent` pipe method and `silent` parameter to
    `ToolService.RunCommand()`. CLI help tools use silent mode so documentation queries
    don't pop up the Immediate Window or echo commands.
  - **Report doc implementation**: `GenerateReportDocHtml()` reuses `DocumentationGenerator`
    with `IncludeHidden = false`. HTML is parsed with regex to extract sections and converted
    to tab-separated plain text for LLM consumption.
  - **Two-pass topic matching**: Exact match on qualified type name or display name first,
    then partial substring match. Space normalization allows "Transition Result" to match
    "TransitionResult".
  - **DirectoryEx.CreateForFilePath()**: New helper in `UtilIO.cs` that validates
    `Path.GetDirectoryName()` is non-null before creating directory. Fixes ReSharper warning
    in report export methods.

  #### Files changed
  - `SkylineMcpServer/Tools/SkylineTools.cs` — 4 new MCP tool methods
  - `ToolsUI/JsonToolServer.cs` — `RunCommandSilent`, `GetReportDocTopics`, `GetReportDocTopic`
    dispatch + helpers, `DirectoryEx.CreateForFilePath()` fix
  - `ToolsUI/ToolService.cs` — `RunCommand(args, silent)` parameter
  - `Util/UtilIO.cs` — `DirectoryEx.CreateForFilePath()` helper

  ---

  ## Phase 7: Connector Lifecycle, Deploy Layout, and Chat App Registration

  ### 7.1: ~~Auto-close when Skyline exits~~ DROPPED

  **Dropped.** Lifecycle timer was over-engineered. Stale connection.json is already
  handled by consumers: MCP server checks `Process.GetProcessById()` before connecting
  and gives a clear error. JsonToolServer.Dispose() cleans up when Skyline exits normally.
  No background process needed just to remove a JSON entry.

  ### 7.2: Deploy directory reorganization

  Move server files to `server/` subdirectory and connection.json to `~/.skyline-mcp/`.

  **New layout:**
  ```
  ~/.skyline-mcp/
    connection.json
    server/
      SkylineMcpServer.exe
      ... (all dependencies)
  ```

  - [x] `McpServerDeployer.cs`: Add `ServerDir` property, deploy files to `server/`
  - [x] `ConnectionInfo.cs`: Delegate to `McpServerDeployer.DeployDir` (no duplicate path)
  - [x] `SkylineConnection.cs`: Update path with constants
  - [x] `JsonToolServer.cs`: Update path with constants
  - [x] String literal discipline: each magic string appears exactly once as a constant per assembly

  ### 7.3: Main form redesign - compact + setup expander

  **Compact state (~145px):** Status labels + two buttons (Setup >>, Close)
  **Expanded state (~290px):** Setup panel with chat app registration checkboxes

  - [x] Compact layout with Setup >> and Close buttons
  - [x] Setup >> / << Setup toggle expands/collapses form
  - [x] Close just closes the form (no lifecycle timer, no Hide vs Close confusion)
  - [x] Dropped Quit/Disconnect button — single Close is sufficient

  ### 7.4: Chat app registration via direct JSON editing

  **Dropped the .mcpb bundle approach.** Claude Desktop does not yet support MCPB manifest
  version 1 on Windows. More importantly, the user journey starts in Skyline (Tool Store),
  not in the chat app's extension store, so running code to directly edit config JSON is
  both simpler and more reliable.

  **UI design:** Checkboxes for each chat app, plus a status label.

  ```
  |  Register Skyline MCP server with:           |
  |                                              |
  |  [ ] Claude Desktop                          |
  |  [x] Claude Code                             |
  |                                              |
  |  Claude Code: Registered successfully.       |
  |  Restart Claude Code to activate.            |
  ```

  **Detection/registration logic** (new `ChatAppRegistry.cs`):
  - For each app: detect installation, check if skyline MCP is registered, add/remove
  - **Claude Desktop**: Direct JSON edit of `%APPDATA%\Claude\claude_desktop_config.json`,
    key `mcpServers.skyline` with `command` pointing to deployed exe
  - **Claude Code**: Delegates to `claude mcp add/remove -s user skyline` CLI.
    User-scope registration (top-level `mcpServers` in `~/.claude.json`) makes Skyline
    available in all projects. Detection reads top-level `mcpServers.skyline` from JSON.
  - Checkbox checked = add entry. Unchecked = remove entry.
  - Status label shows feedback after action. Disabled + "(not installed)" when app missing.

  **Tasks:**
  - [x] Create `ChatAppRegistry.cs` — detect/add/remove for Claude Desktop (JSON) and Claude Code (CLI)
  - [x] Replace tab control in setup panel with checkbox UI + status label
  - [x] Delete `McpBundleBuilder.cs` and compression references from .csproj
  - [x] Wire checkbox CheckedChanged events to registry add/remove
  - [x] On expand, probe system and set initial checkbox/status state
  - [x] Handle JSON parsing gracefully (file missing, empty, malformed)
  - [x] Suppress CheckedChanged during probe to avoid spurious add/remove

  ### 7.5: Clean up

  - [x] Remove old flat files from `~/.skyline-mcp/` (DLLs at top level from pre-server/ layout)
  - [x] Verify McpServerDeployer only deploys to `server/` subdirectory

  ---

  ### 2026-03-01: Connector lifecycle, deploy layout, and chat app registration (session 9)

  **Deploy directory reorganization:**
  - Server files now deploy to `~/.skyline-mcp/server/`
  - connection.json moved from `%LOCALAPPDATA%\Skyline\mcp\` to `~/.skyline-mcp/`
  - All 4 files with path references updated. String literals consolidated to constants.
  - `ConnectionInfo` delegates path to `McpServerDeployer.DeployDir` (no duplicate computation)

  **Main form redesign (3 iterations):**
  1. First: tabs (Claude Desktop / Claude Code) + Close/Quit/Setup buttons + lifecycle timer
  2. MCPB bundle tested — Claude Desktop error "does not support MCPB manifest version 1"
  3. Final: checkboxes + status label, single Close button, no lifecycle timer

  **Key design decisions:**
  - **Dropped .mcpb bundle** — user journey starts in Skyline Tool Store, not chat app store.
    Direct JSON/CLI registration is simpler and more reliable.
  - **Dropped lifecycle timer** — stale connection.json handled by consumers (MCP server
    checks process ID). No background process needed just to clean up a JSON entry.
  - **Dropped Close vs Quit** — single Close button. No Hide behavior. Form just closes.
  - **Claude Code uses CLI** — `claude mcp add/remove -s user` for user-scope registration.
    Discovered that user-scope MCPs go in top-level `mcpServers` in `~/.claude.json`,
    separate from per-project entries. This is the right scope for Skyline.
  - **Claude Desktop uses direct JSON edit** — simple flat `mcpServers` object in
    `%APPDATA%\Claude\claude_desktop_config.json`.

  **ChatAppRegistry.cs** — new static class:
  - `IsClaudeDesktopInstalled()` / `IsRegisteredInClaudeDesktop()` / `Add` / `Remove`
  - `IsClaudeCodeInstalled()` / `IsRegisteredInClaudeCode()` / `Add` / `Remove`
  - Claude Desktop: `JsonNode` manipulation of config file
  - Claude Code: `Process.Start("claude", "mcp add/remove -s user skyline -- <path>")`

  #### Files changed
  - `SkylineMcpConnector/MainForm.cs` — expand/collapse, checkbox handlers, no lifecycle timer
  - `SkylineMcpConnector/MainForm.Designer.cs` — compact layout, checkboxes, Setup + Close buttons
  - `SkylineMcpConnector/McpServerDeployer.cs` — `ServerDir`, deploy to `server/` subdir
  - `SkylineMcpConnector/ConnectionInfo.cs` — delegate path to McpServerDeployer.DeployDir
  - NEW `SkylineMcpConnector/ChatAppRegistry.cs` — detect/add/remove for Claude Desktop and Code
  - `SkylineMcpServer/SkylineConnection.cs` — updated connection.json path with constants
  - `ToolsUI/JsonToolServer.cs` — updated connection.json path with constants
  - DELETED `SkylineMcpConnector/McpBundleBuilder.cs` — .mcpb approach dropped

  #### Remaining work (from session 9)
  - [x] Test end-to-end: deploy from Skyline, checkbox registration for both apps
  - [x] Clean up old flat DLLs from `~/.skyline-mcp/` top level (pre-server/ layout)
  - [x] Update existing `skyline` MCP entry in `C:/proj` project scope (currently points
    to old flat path `~/.skyline-mcp/SkylineMcpServer.exe`, needs `server/` prefix)
  - [ ] Consider: should connector also update connection.json `command` path for
    existing Claude Code project-scope registrations? Or just let user re-register?

  ### 2026-03-01: Claude Desktop process management and UI polish (session 10)

  **E2E testing results:**
  - Claude Code: checkbox registration works perfectly, MCP server connects to running
    Skyline session on first use. Confirmed user-scope registration via `claude mcp add -s user`.
  - Claude Desktop (Chat mode): works after config written while app is fully stopped.
    Successfully ran Skyline reports and exported data from Chat tab.
  - Claude Desktop (Cowork mode): connection errors during initial testing, but Chat mode
    validates the config format is correct.

  **Critical discovery: Claude Desktop overwrites config on exit.**
  The app keeps `claude_desktop_config.json` in memory and writes it back on shutdown,
  erasing any external edits. All 8 WindowsApps processes must be stopped before writing.
  Distinguished from Claude Code processes (`.local\bin\`, `AppData\Roaming\Claude\claude-code\`)
  by checking for `\WindowsApps\` in the executable path.

  **New process management in ChatAppRegistry.cs:**
  - `IsClaudeDesktopRunning()` — filters `claude.exe` processes by WindowsApps path
  - `StopClaudeDesktop()` — kills all Claude Desktop processes
  - `GetClaudeDesktopProcesses()` — private helper using `Process.MainModule.FileName`

  **MainForm: two-stage dialog before writing config:**
  1. "Please close Claude Desktop, then click OK" (user tries manual close)
  2. Re-check; if still running: "Would you like to stop it now?" (force kill)
  3. Reverts checkbox if user cancels at either stage

  **UI polish (by Brendan):**
  - Replaced panel with GroupBox titled "Register Skyline MCP server with:"
  - Form designed at expanded size for designer usability, collapsed on init
  - Format string placeholders in labels ("Version: {0}", "Document: {0}")
  - Mnemonics: &Setup, &Desktop, &Code
  - Dynamic height calculation from control positions (DPI-safe)
  - CancelButton = buttonClose (Escape to close)
  - Extracted `RevertCheckbox()` helper

  #### Files changed
  - `SkylineMcpConnector/ChatAppRegistry.cs` — added process detection/kill for Desktop
  - `SkylineMcpConnector/MainForm.cs` — EnsureClaudeDesktopStopped dialog flow, UI polish
  - `SkylineMcpConnector/MainForm.Designer.cs` — GroupBox, mnemonics, designer-friendly layout

  #### Remaining work
  - [x] Clean up old flat DLLs from `~/.skyline-mcp/` top level (pre-server/ layout)
  - [x] Form icon (16x16 corner + taskbar size) — currently default Windows icon
  - [x] Tool Store icon for Skyline MCP
  - [ ] Consider renaming menu text to "Connect to Chat" (less Claude-specific)
  - [ ] Test Cowork mode more thoroughly (Chat mode works, Cowork had connection issues)

  ## Phase 8: Document-Modifying MCP Tools

  ### Motivation

  Enable LLMs to add targets to a Skyline document through conversation, replacing manual
  workflows that currently require specialized tools (LipidCreator), external spreadsheets
  (glycan formula calculation), copy-paste from databases (UniProt FASTA), or external LLM
  sessions (ChatGPT for chemical formulas). The LLM's domain knowledge bridges the format
  gap — the user says what they want to measure, and the LLM generates the right format.

  **Demo target:** 4-day lipidomics course (2026-03-05). Show adding cholesteryl esters to
  Skyline by conversation, replacing the LipidCreator workflow from the PRM tutorial.

  ### Use cases

  1. **Small molecules / lipids / glycans** via `InsertSmallMoleculeTransitionList`:
     - "Add CE 16:0, CE 18:1, CE 18:2, CE 20:4, CE 22:6 as ammoniated adducts for PRM"
     - LLM generates CSV with headers: MoleculeGroup, PrecursorName, PrecursorFormula,
       PrecursorAdduct, PrecursorMz, ProductMz, ProductName, etc.
     - Skyline parses headers and inserts — same as Edit > Insert > Transition List paste

  2. **Proteins / peptides** via `ImportFasta`:
     - "Add human insulin and glucagon to my document"
     - LLM generates FASTA text from knowledge or constructs it
     - Skyline digests with current enzyme settings and adds peptides/transitions

  3. **Annotations / sample properties** via `ImportProperties`:
     - "Label the first 9 replicates as 'control' and the rest as 'treatment'"
     - LLM exports a report to understand document structure, then constructs columnar
       text with Location specifiers to set annotations on targets or replicates

  ### Implementation plan

  All three follow the same pattern as existing read-only tools: add method to JsonToolServer,
  wire the named pipe call in SkylineConnection, expose as MCP tool in SkylineTools.

  **Key difference from read-only tools:** These methods modify the document and are called
  via `Program.MainWindow.Invoke()` to run on the UI thread. The named pipe call must wait
  for the Invoke to complete before returning. The existing `ToolService` implementations
  are void methods, so our JsonToolServer wrappers should return a success/error message
  rather than void, giving the LLM feedback to retry with corrected input.

  #### 8.1: InsertSmallMoleculeTransitionList (highest demo priority)

  **JsonToolServer.cs:**
  - Add `InsertSmallMoleculeTransitionList` to `AVAILABLE_METHODS`
  - Handler receives CSV text as the parameter
  - Calls `_skylineWindow.InsertSmallMoleculeTransitionList(textCSV, description)` via Invoke
  - Returns success message or error text

  **SkylineConnection.cs / SkylineTools.cs:**
  - Add `InsertSmallMoleculeTransitionList(string textCSV)` pipe call
  - MCP tool `skyline_insert_small_molecule_transition_list` with description documenting
    the CSV format and available column headers

  **Column headers for tool description** (from `SmallMoleculeTransitionListColumnHeaders`):
  ```
  MoleculeGroup, PrecursorName, ProductName, PrecursorFormula, ProductFormula,
  PrecursorMz, ProductMz, PrecursorCharge, ProductCharge, PrecursorAdduct,
  ProductAdduct, PrecursorRT, PrecursorRTWindow, LabelType, CAS, InChiKey,
  InChi, HMDB, SMILES, Note, PrecursorNote, MoleculeNote, MoleculeListNote
  ```

  - [x] Add to JsonToolServer AVAILABLE_METHODS and dispatch
  - [x] Add MCP tool with format documentation in description
  - [x] Wire through SkylineConnection
  - [x] Test with lipid transition list from conversation

  #### 8.2: ImportFasta

  **JsonToolServer.cs:**
  - Add `ImportFasta` to `AVAILABLE_METHODS`
  - Handler receives FASTA text as the parameter
  - Calls ToolService-style logic via Invoke
  - Returns success message or error text

  **MCP tool:** `skyline_import_fasta` — description explains standard FASTA format
  (>header lines followed by sequence lines)

  - [x] Add to JsonToolServer
  - [x] Add MCP tool
  - [x] Wire through SkylineConnection
  - [x] Test with protein FASTA from conversation

  #### 8.3: ImportProperties

  **JsonToolServer.cs:**
  - Add `ImportProperties` to `AVAILABLE_METHODS`
  - Handler receives CSV text with Location column + annotation columns
  - Calls `_skylineWindow.ImportAnnotations()` via Invoke
  - Returns success message or error text

  **MCP tool:** `skyline_import_properties` — description explains the format: first column
  is an ElementLocator (from report export), remaining columns are annotation names with
  values. The LLM should first export a report to learn the document structure and locators.

  - [x] Add to JsonToolServer
  - [x] Add MCP tool
  - [x] Wire through SkylineConnection
  - [ ] Test with annotation workflow from conversation

  #### 8.4: Error handling pattern

  The existing ToolService methods are void — they throw on failure but return nothing on
  success. For the MCP tools, we need the LLM to know whether its input was accepted:

  - Wrap the Invoke call in try/catch
  - On success: return "Successfully inserted N molecules" or similar (if we can count)
  - On failure: return the exception message so the LLM can fix headers and retry
  - The retry loop is natural for LLMs — send CSV, get error about unknown header,
    fix the header name, resend

  ### Session 9 — Phase 8 implementation (2026-03-01)

  Implemented all three document-modifying MCP tools. Each follows the same pattern:
  JsonToolServer dispatches to SkylineWindow methods on the UI thread via `InvokeOnUiThread`
  helper, which catches exceptions and returns OK or error message for LLM retry.

  **Tested successfully:**
  - Inserted 3 cholesteryl esters (CE 16:0, CE 18:1, CE 18:2) as [M+NH4]+ with C27H45 product
  - Imported insulin FASTA — produced 1 peptide (GIVEQCCTSICSLYQLENYCN) with y11 fragment
  - Imported APOA1 FASTA — produced 12 peptides with multiple y-ion transitions
  - ImportProperties wired but deferred testing pending supporting tools

  **Bugs found and fixed during deployment testing:**
  - Deploy script (`Deploy-SkylineMcp.ps1`) was copying to `~/.skyline-mcp/` instead of
    `~/.skyline-mcp/server/` — files never reached the running MCP server
  - `McpServerDeployer` timestamp-only check missed updates when ZIP extraction preserved
    original timestamps — added file size comparison
  - `MainForm.DeployMcpServer()` swallowed IOException into `Debug.WriteLine` when DLL was
    locked by running MCP server — now kills SkylineMcpServer processes and retries, shows
    MessageBox on final failure
  - Changed unsaved document display from "(none)" to "(unsaved)" in both connector UI and
    MCP tool response

  #### Files changed
  - `ToolsUI/JsonToolServer.cs` — 3 methods in AVAILABLE_METHODS, 3 case handlers, InvokeOnUiThread helper
  - `SkylineMcpServer/SkylineConnection.cs` — 3 CallSkyline convenience methods
  - `SkylineMcpServer/Tools/SkylineTools.cs` — 3 [McpServerTool] methods, fixed "(unsaved)" text
  - `SkylineMcpConnector/MainForm.cs` — deploy retry with process kill, "(unsaved)" text
  - `SkylineMcpConnector/McpServerDeployer.cs` — file size check in Deploy()
  - `SkylineMcpConnector/SkylineMcpConnector.ico` — updated icon
  - `ai/scripts/Skyline/Deploy-SkylineMcp.ps1` — fixed target path to server/ subdirectory

  ## Phase 9: Document Status and Settings Tools + Connector Lifecycle

  ### Session 10 — Phase 9 implementation (2026-03-01)

  Added 3 lightweight MCP tools for document inspection without running full reports,
  plus connector lifecycle improvements.

  **New tools:**
  - `skyline_get_document_status` — returns doc type, target counts, replicate count, file path
  - `skyline_get_document_settings` — exports current settings XML (stripped of MeasuredResults)
  - `skyline_get_default_settings` — exports default settings XML for comparison

  **Utility improvements:**
  - Added `PathEx.ToForwardSlashPath()` extension method in CommonUtil to replace scattered
    `Replace('\\', '/')` calls — used in 5 places in JsonToolServer.cs
  - Added `SerializeSettingsToFile()` helper using XmlSerializer + FileSaver pattern

  **Connector lifecycle:**
  - Added Skyline process monitor: 2-second timer polls Process.GetProcessById(), closes
    connector when Skyline exits (Phase 7.1 was previously dropped, now restored)
  - Added MessageBox notification when MCP server is killed during deployment update,
    telling user to restart Claude Code/Desktop
  - Removed stale "restart Claude Desktop" status label (Desktop config is now edited only
    when Desktop is stopped)

  #### Files changed
  - `Shared/CommonUtil/SystemUtil/PathEx.cs` — added ToForwardSlashPath() extension method
  - `ToolsUI/JsonToolServer.cs` — 3 new methods, SerializeSettingsToFile helper, ToForwardSlashPath usage
  - `SkylineMcpServer/Tools/SkylineTools.cs` — 3 new MCP tools, GetTempSettingsPath helper
  - `SkylineMcpConnector/MainForm.cs` — Skyline process monitor timer, deploy update MessageBox

  ## Phase 10: JSON-Based Report Definitions

  ### Session 11 — JSON report API + ColumnResolver + LlmInstruction (2026-03-02)

  Replaced the XML-based `ExportReportFromDefinition` with a JSON-based API where the LLM
  just lists column display names and the server infers row source, sublist, and property paths.

  **JSON format:**
  ```json
  {"name": "optional name", "select": ["ProteinName", "PrecursorMz", "Area"]}
  ```

  **New types introduced:**

  - `ColumnResolver` (`Model/Databinding/ColumnResolver.cs`) — public class that maps invariant
    column display names to PropertyPaths by traversing ColumnDescriptor trees. Tries row sources
    shallowest first (Protein, Peptide, Precursor, Transition), falls back to Replicate. Throws
    `UnresolvedColumnsException` with structured data (column name + suggestions per column).

  - `LlmInstruction` (`Util/Extensions/Text.cs`) — readonly struct marking text intended as
    instruction for an LLM consumer, not for direct display to end users. Distinguished from
    user-facing text (must be in .resx) and debug text (developer-only). Implicit conversion
    to string. Future seam for LLM prompt localization.

  - `TextUtil.SingleQuote()` (`Util/Extensions/Text.cs`) — extension method complementing
    existing `Quote()`, wraps text in single quotes for identifier formatting in error messages.

  **New MCP tool:**
  - `skyline_add_report` — saves a JSON report definition to the user's PersistedViews so it
    appears in Skyline's report list. `name` field required. Uses same ColumnResolver as export.

  **Row source resolution bug fix:**
  When ALL resolved paths go through `Results!*` (e.g., `{"select": ["ReplicateName"]}`), the
  resolver was picking Protein as the shallowest match, producing a pivoted cross-join instead
  of one row per replicate. Fixed by deferring to the Replicate row source when all paths are
  Results-only. The target match is kept as fallback if Replicate can't resolve all columns.

  **Build dependency fix:**
  `SkylineMcpConnector.csproj` had no build dependency on `SkylineMcpServer`. The `PackageToolZip`
  post-build target copied from the server's output directory, but MSBuild didn't know to build
  the server first. Added a `BuildMcpServer` target using `<MSBuild>` task (cross-targeting
  prevents normal `<ProjectReference>` from net472 to net8.0).

  **Architectural decisions:**
  - ColumnResolver lives in `Model.Databinding` (general-purpose, near RowFactories) not in
    JsonToolServer (API layer). Returns structured errors; formatting is the API layer's job.
  - LlmInstruction lives in TextUtil.cs (small type, Skyline-only scope). Not in Common
    (no consumer outside Skyline). English for now but marked distinctly for future localization.
  - String formatting uses positional replacement (`string.Format(@"..{0}..", arg)`) not
    concatenation, per project convention for .resx migration readiness.

  #### Files changed
  - `Model/Databinding/ColumnResolver.cs` — NEW: column resolution algorithm + structured errors
  - `Skyline.csproj` — added ColumnResolver.cs Compile entry
  - `Util/Extensions/Text.cs` — LlmInstruction struct, SingleQuote() method
  - `ToolsUI/JsonToolServer.cs` — ExportJsonDefinitionReport, AddJsonDefinitionReport,
    ResolveJsonReportDefinition, FormatUnresolvedColumnsError; removed nested ColumnResolver
  - `SkylineMcpServer/Tools/SkylineTools.cs` — JSON parameter for report_from_definition,
    new skyline_add_report tool
  - `SkylineMcpConnector/SkylineMcpConnector.csproj` — BuildMcpServer target

  #### Remaining work (from session 11)
  - [x] Fix `0` prefix in column headers for paths through indexed collections (session 12)
  - [x] Verify `Results!*` sublist detection works for cross-level queries (session 12)
  - [x] Test `skyline_add_report` end-to-end (add report, verify it appears in Skyline's list)
  - [x] Clean up old flat DLLs from `~/.skyline-mcp/` top level (pre-server/ layout)
  - [x] Form icon (16x16 corner + taskbar size)
  - [x] Tool Store icon for Skyline MCP

  ### Session 12 — SublistId fix + error handling (2026-03-02)

  Fixed the "0" prefix in column headers and added consistent error handling to MCP tools.

  #### SublistId fix (ColumnResolver)
  - Replaced hard-coded `Results!*` string check with general `FindDeepestSublist()` algorithm
  - Uses same approach as `ReportSpecConverter`: walks each PropertyPath up to find the deepest
    unbound collection lookup (`!*`), takes the deepest across all paths as SublistId
  - `ResolveResult` now carries `PropertyPath SublistId` instead of `bool NeedsResultsSublist`
  - Renamed `AllPathsThroughResults` to `AllPathsThroughCollection` — checks `IsUnboundLookup`
    instead of string-matching `Results!*`
  - `JsonToolServer.ResolveJsonReportDefinition` uses `result.SublistId.IsRoot` check
  - Tested: `{"select": ["ReplicateName", "FilePath"]}` now produces clean headers (42 rows,
    SublistId=`Files!*`), cross-level queries like ProteinName+Area work (32K rows,
    SublistId=`Results!*`), custom annotations resolve correctly

  #### Error handling
  - `JsonToolServer.HandleRequest`: changed `ex.Message` to `ex.ToString()` for full stack traces
  - `SkylineTools`: wrapped every MCP tool in `Invoke(Func<string>)` that catches exceptions
    and returns them as text so the LLM always sees error details instead of generic framework error
  - Added `ErrorDetail` enum (Message, Full) with `ErrorDetailLevel` property defaulting to Full
  - Verified: unknown column "PeptideModifiedSequence" now returns full stack trace with
    "Did you mean" suggestions instead of opaque "An error occurred invoking..."

  #### Files changed
  - `Model/Databinding/ColumnResolver.cs` — FindDeepestSublist, AllPathsThroughCollection,
    PathContainsCollection, ResolveResult.SublistId
  - `ToolsUI/JsonToolServer.cs` — ex.ToString() in HandleRequest, result.SublistId.IsRoot
  - `SkylineMcpServer/Tools/SkylineTools.cs` — Invoke wrapper, ErrorDetail enum, all tools wrapped

  #### Remaining work
  - [x] Test `skyline_add_report` end-to-end (add report, verify it appears in Skyline's list)
  - [x] Clean up old flat DLLs from `~/.skyline-mcp/` top level (pre-server/ layout)
  - [x] Form icon (16x16 corner + taskbar size)
  - [x] Tool Store icon for Skyline MCP