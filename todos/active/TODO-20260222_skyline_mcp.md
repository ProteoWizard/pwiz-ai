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

  ## Architecture: Bridge Pattern

  The Connector acts as a JSON-to-BinaryFormatter bridge, requiring **zero changes to Skyline core**. The wire
  protocol modernization (SkylineTool.Core with JSON replacing BinaryFormatter) is deferred to a follow-up PR.

  ```
  Claude Code ──stdio──> SkylineMcpServer (.NET 8.0)
                             │ JSON over named pipe
                             v
                         SkylineMcpConnector (.NET 4.7.2, bridge)
                             │ BinaryFormatter over named pipe (existing SkylineToolClient)
                             v
                         Skyline.exe (running instance)
  ```

  ### Why Bridge Instead of Direct JSON Wire Protocol

  - **No Skyline core changes** - lower risk, easier to merge
  - **Uses existing SkylineToolClient** - proven, tested code for BinaryFormatter IPC
  - **Faster to ship** - ASMS 2026 deadline is June
  - **The connector is already long-lived** - it shows UI and manages connection lifecycle, so acting as a proxy is
   a natural extension
  - **Wire protocol change is independent** - can be done in a focused follow-up PR that replaces BinaryFormatter
  in RemoteBase with JSON, then eliminates the bridge

  ### Three-Process Design

  | Process | Framework | Lifecycle | Role |
  |---------|-----------|-----------|------|
  | **Skyline.exe** | .NET Framework 4.7.2 | User-launched | Hosts RemoteService (BinaryFormatter named pipe
  server) |
  | **SkylineMcpConnector** | .NET Framework 4.7.2 | Launched from Skyline External Tools menu | Bridge: JSON pipe
  server + BinaryFormatter pipe client via SkylineToolClient |
  | **SkylineMcpServer** | .NET 8.0-windows | Launched by Claude Code/Desktop | MCP stdio server, connects to
  connector's JSON pipe |

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

  ### Dispatch Table (Connector)

  | JSON method | SkylineToolClient call | Return type | JSON result type |
  |-------------|----------------------|-------------|-----------------|
  | `GetDocumentPath` | `GetDocumentPath()` | string | string (forward slashes) |
  | `GetVersion` | `GetSkylineVersion()` | Version | string "Major.Minor.Build.Revision" |
  | `GetDocumentLocationName` | `GetDocumentLocationName()` | string | string |
  | `GetReplicateName` | `GetReplicateName()` | string | string |
  | `GetProcessId` | `GetProcessId()` | int | number |
  | `GetReport` | `GetReport(args[0])` | IReport | string (CSV: header + rows) |
  | `GetReportFromDefinition` | `GetReportFromDefinition(args[0])` | IReport | string (CSV: header + rows) |
  | `GetSelectedElementLocator` | `GetSelectedElementLocator(args[0])` | string | string |

  ### IReport to CSV Conversion

  The SkylineToolClient `GetReport()` returns an `IReport` with `ColumnNames` (string[]) and `Cells` (string[][]).
  The connector converts to CSV:
  - Header row: column names comma-separated
  - Data rows: cell values comma-separated, quoted if containing commas
  - The `SkylineToolClient.Report` class already has a `ReadDsvLine()` CSV parser, but for output we just need
  simple CSV serialization

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

  ### Next steps
  - Rebuild SkylineMcpServer (requires Claude Code restart to release exe lock)
  - Verify end-to-end: "What version of Skyline?" returns version string
  - Remove temporary `skyline_ping` tool added during debugging
  - Test remaining tools: get_document_path, get_selection, get_replicate, get_report
  - Consider combining both projects into a shared .sln (like ImageComparer.sln)