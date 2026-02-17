# TODO: Skyline MCP Server

## Overview

Implement an MCP server that enables LLM applications (Claude Desktop, Claude Code) to interact with a running Skyline instance through natural language. This builds on the architecture established in PR #3989 (C# .NET MCP server) and Skyline's existing Interactive External Tool infrastructure.

## Architecture

```
┌─────────────────┐          ┌─────────────────────────┐
│ Claude Desktop  │──stdio──▶│ Skyline MCP Server      │
│ or Claude Code  │◀─stdio───│ (.NET 8.0-windows)      │
└─────────────────┘          └───────────┬─────────────┘
                                         │
                             reads ~/.skyline-mcp/connection.json
                                         │
                                         ▼
                             ┌───────────────────────┐
                             │ Named Pipe            │
                             │ (SkylineConnection)   │
                             └───────────┬───────────┘
                                         │
                                         ▼
                             ┌───────────────────────┐
                             │ Skyline.exe           │
                             │ (running instance)    │
                             └───────────────────────┘
```

### Two-Process Design

The MCP server and the Skyline connector are separate processes with different lifecycles:

- **SkylineMcpConnector** — .NET Framework 4.7.2 WinForms app, launched by Skyline's External Tools menu. Writes connection info so the MCP server can find the named pipe.
- **SkylineMcpServer** — .NET 8.0-windows console app, launched by Claude Code/Desktop as an MCP stdio server. Reads connection info, connects to Skyline via named pipe.

This separation is necessary because Skyline External Tools are launched from the UI thread and must be .NET Framework apps, while the MCP server must be a long-lived .NET 8.0 stdio process.

## Reference Materials

- **PR #3989**: https://github.com/ProteoWizard/pwiz/pull/3989 (ImageComparer MCP — working C# MCP reference)
- **C# MCP Pitfalls**: `ai/docs/mcp/development-guide.md` → "C# MCP Servers (.NET)" section
- **ImageComparer MCP docs**: `ai/docs/mcp/image-comparer.md`
- **Interactive Tool Support Doc**: https://skyline.ms/labkey/_webdav/home/software/Skyline/@files/docs/Skyline%20Interactive%20Tool%20Support-3_1.pdf
- **Example Interactive Tool**: `pwiz/pwiz_tools/Skyline/Executables/Tools/ExampleInteractiveTool/`
- **SkylineTool.dll**: `pwiz/pwiz_tools/Skyline/SkylineTool/` (provides SkylineToolClient)

## Wire Protocol: BinaryFormatter → JSON with POCOs

**SkylineTool.dll** targets .NET Framework 4.7.2 and uses `BinaryFormatter` for named pipe serialization (`RemoteBase.cs`). The MCP server targets .NET 8.0, where `BinaryFormatter` is **obsoleted and throws `PlatformNotSupportedException` by default**. This must be replaced.

### Decision: JSON with System.Text.Json (POCOs)

Replace `BinaryFormatter` with JSON serialization using typed POCO models, following the same direction as the Panorama JSON cleanup (see `TODO-panorama_json_typed_models.md`).

**Why JSON over protobuf:**
- The codebase already has many serialization formats (XML, protobuf, BinaryFormatter, SQLite/NHibernate, custom binary, JSON). Consolidating toward fewer paradigms is better than adding another protobuf usage area.
- JSON is already used for LabKey Server communication and the test framework. Increasing exposure in another area builds team familiarity with a format we're already committed to.
- `System.Text.Json` is built into .NET — zero new dependencies for either .NET Framework 4.7.2 (via NuGet) or .NET 8.0 (built-in).
- Human-readable — invaluable for debugging named pipe communication issues.
- The SkylineTool wire protocol is simple RPC (`RemoteInvoke { MethodName, Arguments }` → `RemoteResponse { ReturnValue, Exception }`), a natural fit for POCOs.
- Protobuf's schema enforcement and performance advantages don't matter for a local named pipe RPC with simple request/response shapes.

**Implementation approach:**
1. Create a multi-target `SkylineTool.Core` library (`net472;netstandard2.0`) with JSON-based `RemoteBase` replacement
2. Define POCO classes for `RemoteInvoke` and `RemoteResponse` with `[JsonPropertyName]` attributes
3. Both Skyline (server) and MCP server (client) reference SkylineTool.Core
4. Existing `SkylineTool.dll` external tools continue to work during migration via backward compatibility or phased rollout

**Related:** `ai/todos/backlog/brendanx67/TODO-panorama_json_typed_models.md` — same POCO pattern for Panorama JSON

## C# MCP Implementation Notes

All three pitfalls from ImageComparer MCP apply. See `ai/docs/mcp/development-guide.md`.

1. **Clear logging providers** — `builder.Logging.ClearProviders()` before `AddMcpServer()`
2. **Isolate child process stdin** — If the MCP server ever shells out (e.g., to SkylineCmd), use `RedirectStandardInput=true` + `Close()`. The SkylineToolClient itself uses named pipes (not subprocess), so this is less critical for Phase 3 but important for SkylineCmd integration.
3. **Forward-slash paths** — `GetDocumentPath()` returns backslash paths. Any path returned to the MCP client needs `path.Replace('\\', '/')`. Accept forward slashes in path parameters and normalize with `NormalizePath()` at API boundary.

## Phase 1: Skyline Connector Tool (.NET Framework 4.7.2)

A minimal Skyline External Tool that writes the connection info for the MCP server.

### Tasks

- [ ] Create new project in `pwiz/pwiz_tools/Skyline/Executables/Tools/SkylineMcpConnector/`
- [ ] Target .NET Framework 4.7.2 (must match Skyline's runtime)
- [ ] Reference `SkylineTool.dll`
- [ ] Accept `$(SkylineConnection)` argument from Skyline (passed as `args[0]`)
- [ ] Write connection file to `~/.skyline-mcp/connection.json`:
  ```json
  {
    "pipe_name": "SkylineTool-{GUID}",
    "process_id": 12345,
    "connected_at": "2026-02-06T10:30:00Z",
    "skyline_version": "24.2.0.0",
    "document_path": "C:/path/to/document.sky"
  }
  ```
- [ ] Include `process_id` (from `SkylineToolClient.GetProcessId()`) for staleness detection
- [ ] Include `document_path` (from `GetDocumentPath()`) for identification
- [ ] Display simple UI with "Connected to Skyline" status and "Disconnect" button
- [ ] On disconnect/close, delete the connection file
- [ ] Create `tool-inf/` folder with tool definition (see ExampleInteractiveTool for pattern)

### Connection Lifecycle Issues to Address

- **Stale files on crash**: If Skyline crashes, the connector doesn't clean up. MCP server should validate by checking if `process_id` is alive before attempting pipe connection.
- **Multiple instances**: Current design overwrites connection.json. Future: use `connection-{GUID}.json` pattern and let MCP server list available instances.
- **File location**: Consider `%LOCALAPPDATA%/Skyline/mcp/` instead of `~/.skyline-mcp/` to follow Skyline conventions.

### Files to create

- `SkylineMcpConnector.csproj` (net472 WinForms)
- `Program.cs` / `MainForm.cs`
- `tool-inf/info.properties`
- `tool-inf/SkylineMcpConnector.properties` (Arguments = `$(SkylineConnection)`)

## Phase 2: MCP Server Core (.NET 8.0-windows)

Build the MCP server using ModelContextProtocol NuGet package, based on PR #3989 patterns.

### Tasks

- [ ] Create new project `pwiz/pwiz_tools/Skyline/Executables/Tools/SkylineMcpServer/`
- [ ] Target `net8.0-windows` with `ModelContextProtocol` NuGet package
- [ ] Clear logging providers (pitfall #1)
- [ ] Read connection file on tool invocation
- [ ] Connect to Skyline's named pipe using pipe name from connection file
- [ ] Validate connection: check `process_id` is alive, attempt pipe with short timeout
- [ ] Handle no connection file → return helpful error ("Launch 'Connect to Claude' from Skyline's External Tools menu")
- [ ] Handle stale connection → return error with suggestion to reconnect
- [ ] Handle pipe timeout → return error ("Skyline may be busy or showing a modal dialog")
- [ ] Normalize all paths returned to client (backslash → forward slash)
- [ ] Setup script in `ai/mcp/SkylineMcp/Setup-SkylineMcp.ps1`

### Wire Protocol Prerequisite

Requires the JSON wire protocol work (see "Wire Protocol: BinaryFormatter → JSON with POCOs" section above). The `SkylineTool.Core` multi-target library must be created first, replacing `BinaryFormatter` with `System.Text.Json` POCOs in `RemoteBase`.

## Phase 3: MCP Tools

### Phase 3a: Read-Only Tools

These map directly to existing SkylineToolClient methods:

| Tool | SkylineToolClient Method | Notes |
|------|-------------------------|-------|
| `skyline_get_document_path` | `GetDocumentPath()` | Normalize path to forward slashes |
| `skyline_get_version` | `GetSkylineVersion()` | Returns Version object |
| `skyline_get_selection` | `GetDocumentLocationName()` | Current protein/peptide/precursor |
| `skyline_get_replicate` | `GetReplicateName()` | Active replicate |
| `skyline_get_report` | `GetReport(reportName)` | **Large data — use file-based pattern** |
| `skyline_get_report_from_definition` | `GetReportFromDefinition(reportXml)` | **Large data — use file-based pattern** |

**Report data volume**: Reports can return thousands of rows. Use file-based pattern from `development-guide.md`: save to `ai/.tmp/skyline-report-{name}.csv`, return summary + path.

### Phase 3b: Navigation Tools

| Tool | Method | Notes |
|------|--------|-------|
| `skyline_select_element` | `SetDocumentLocation()` | Obsolete but functional |

### Phase 3c: Document Modification Tools (Already Supported!)

These are **already in the SkylineToolClient API** — no Skyline extensions needed:

| Tool | SkylineToolClient Method | Notes |
|------|-------------------------|-------|
| `skyline_import_fasta` | `ImportFasta(string textFasta)` | Add proteins from FASTA text |
| `skyline_add_small_molecules` | `InsertSmallMoleculeTransitionList(string textCSV)` | CSV format transition list |
| `skyline_add_spectral_library` | `AddSpectralLibrary(name, path)` | Path needs normalization |
| `skyline_delete_elements` | `DeleteElements(string[] elementLocators)` | Delete proteins/peptides/etc. |
| `skyline_import_peak_boundaries` | `ImportPeakBoundaries(string csv)` | Custom peak boundaries |
| `skyline_import_properties` | `ImportProperties(string csv)` | Custom annotation properties |

**ASMS demo implication**: The stretch goals ("Add APOA1", "Add Acetyl-CoA") are achievable with existing API — no Skyline modifications needed.

### Phase 3d: SkylineCmd Integration (Future)

For operations not in the Interactive Tool API (import results, modify settings, save document), SkylineCmd offers 231 command-line arguments. Could expose as MCP tools that operate on .sky files directly without a running Skyline instance.

| Tool | SkylineCmd Args | Notes |
|------|----------------|-------|
| `skyline_import_results` | `--in file.sky --import-file data.raw --save` | Requires stdin isolation (pitfall #2) |
| `skyline_refine` | `--in file.sky --refine-* --save` | 40+ refinement options |
| `skyline_export_report` | `--in file.sky --report-name X --report-file out.csv` | Works without running Skyline |

**Trade-off**: SkylineCmd operates on files, not the running instance. Changes won't be visible in Skyline until the document is reloaded.

## Full SkylineToolClient API Surface

Verified by reading source at `pwiz_tools/Skyline/SkylineTool/SkylineToolClient.cs`:

### Already Known (in original TODO)
- `GetReport(string reportName)` → `IReport`
- `GetReportFromDefinition(string reportDefinition)` → `IReport`
- `GetDocumentLocation()` / `SetDocumentLocation()` — obsolete but functional
- `GetReplicateName()` → `string`
- `GetChromatograms(DocumentLocation)` → `Chromatogram[]` — obsolete
- `GetDocumentPath()` → `string`
- `GetSkylineVersion()` → `Version`
- `DocumentChanged` / `SelectionChanged` events

### Discovered During Review (not in original TODO)
- `ImportFasta(string textFasta)` — **adds proteins from FASTA text**
- `InsertSmallMoleculeTransitionList(string textCSV)` — **adds small molecules**
- `AddSpectralLibrary(string libraryName, string libraryPath)` — adds spectral library
- `DeleteElements(string[] elementLocators)` — deletes document elements
- `GetSelectedElementLocator(string elementType)` → `string` — gets selection as locator
- `ImportProperties(string propertiesCsv)` — imports custom properties
- `ImportPeakBoundaries(string peakBoundariesCsv)` — imports peak boundaries
- `GetProcessId()` → `int` — Skyline's PID (useful for connection validation)
- `GetDocumentLocationName()` → `string` — non-obsolete selection accessor

### Not in API (would need Skyline changes or SkylineCmd)
- Importing results files
- Modifying instrument/transition/full-scan settings
- Saving document
- Undo/redo operations

## Phase 4: Testing

### Manual Testing

- [ ] Start Skyline, open a document
- [ ] Launch SkylineMcpConnector from External Tools menu
- [ ] Verify connection.json is written with pipe_name, process_id, document_path
- [ ] Test MCP server with Claude Code: `claude mcp add skyline ...`
- [ ] Verify read-only tools: "What document is open in Skyline?"
- [ ] Verify reports: "Show me peak areas for all peptides" (check file-based output)
- [ ] Verify navigation: "Go to peptide DIDISSPEFK"
- [ ] Verify import: "Add APOA1 to the document" (LLM provides FASTA)
- [ ] Verify small molecules: "Add Acetyl-CoA" (LLM provides CSV transition list)
- [ ] Test stale connection: close Skyline, try a tool call
- [ ] Test modal dialog: open a Skyline dialog, try a tool call (should timeout gracefully)

### Example Prompts to Validate

From the ASMS abstract:

- "What document is open in Skyline?" → `skyline_get_document_path`
- "What peptides are in this document?" → `skyline_get_report` with appropriate report
- "Please add APOA1 to the document" → LLM provides FASTA, MCP calls `ImportFasta`
- "Add Acetyl-CoA to the document" → LLM provides CSV, MCP calls `InsertSmallMoleculeTransitionList`
- "Show peptides with CV above 20% in QC samples" → `skyline_get_report_from_definition` + LLM analysis

## Phase 5: Packaging (Deferred)

Desktop Extension packaging (`mcpb pack`, `manifest.json`) should be deferred until the format stabilizes. Focus on Claude Code registration via setup script for now.

## Notes

### Named Pipe Communication

Skyline uses `NamedPipeClientStream` / `NamedPipeServerStream` in message mode with `BinaryFormatter` serialization. The `SkylineToolClient` class handles protocol details. Each RPC call opens a new pipe connection with a 1-second timeout.

### Timeout and Threading Concerns

- Named pipe default timeout is 1 second. If Skyline is busy (importing data, long operation), calls will fail.
- SkylineToolClient dispatches to Skyline's UI thread via `Program.MainWindow.Invoke()`. A modal dialog will block indefinitely.
- MCP tool implementations should wrap pipe calls with configurable timeouts and return user-friendly error messages.

### Event-Driven Updates

The API has `DocumentChanged` and `SelectionChanged` events. MCP is request/response (no server push). These events could be used for:
- State invalidation (clear cached report data)
- Logging (track document changes during a session)
- Future: MCP notifications if the spec adds push support

### Connection Discovery Alternative

Instead of file-based discovery, the MCP server could enumerate Windows named pipes matching `SkylineTool-*` and probe each with `GetDocumentPath()` to identify instances. This eliminates the connector tool entirely but adds complexity. Worth investigating if the file-based approach proves fragile.

## Success Criteria for ASMS 2026 (June)

Minimum viable demo:

1. User installs Claude Desktop + registers Skyline MCP server
2. User opens Skyline document, clicks "Connect to Claude" in External Tools
3. User asks Claude: "What peptides are in this document?"
4. Claude queries Skyline via MCP and responds with peptide list
5. User asks: "Show me which have CV > 20%"
6. Claude generates report and interprets results

Stretch goals (now achievable without API extensions):

- "Add APOA1 to the document" → LLM provides FASTA sequence, `ImportFasta`
- "Add Acetyl-CoA" → LLM provides formula/transition list, `InsertSmallMoleculeTransitionList`
- Report visualization in Claude's response
- Multi-turn workflow assistance

## Review Notes (2026-02-16)

Design reviewed against ImageComparer MCP implementation (PR #3989). Key findings:

1. **API gaps were overstated** — `ImportFasta`, `InsertSmallMoleculeTransitionList`, and 6 other methods were already in SkylineToolClient but not listed
2. **BinaryFormatter must be replaced** — .NET 8.0 blocks it by default. Decision: JSON with POCOs via System.Text.Json, aligning with Panorama JSON cleanup direction. Nick suggested protobuf (already in codebase), but JSON consolidates the team toward fewer serialization paradigms and adds zero dependencies.
3. **C# MCP pitfalls were not addressed** — all three from ImageComparer apply
4. **Connection lifecycle needs hardening** — stale files, crash recovery, PID validation
5. **Report data volume** — must use file-based pattern to avoid context overflow
6. **Phase 5 (packaging) is premature** — deferred until format stabilizes

See `ai/docs/mcp/development-guide.md` and `ai/docs/mcp/image-comparer.md` for implementation patterns.

### Review session details

- Explored full SkylineToolClient API surface (SkylineToolClient.cs, IToolService.cs, RemoteClient.cs, RemoteBase.cs)
- Explored ExampleInteractiveTool connection pattern (tool-inf/, $(SkylineConnection) macro)
- Explored SkylineCmd capabilities (231 command-line args, operates on .sky files directly)
- Investigated protobuf history: adopted Feb-Mar 2017 for chromatogram compression and hybrid document format, added for Koina gRPC in 2024. Usage is central to data persistence but oriented toward binary density, not IPC.
- Discussed serialization format with developer: JSON chosen over protobuf for wire protocol because it consolidates toward fewer formats, aligns with Panorama POCO cleanup direction, and is the clear trajectory for interchange protocols.
