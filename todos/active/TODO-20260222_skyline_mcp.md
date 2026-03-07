  ## Branch Information
  - **Branch**: `Skyline/work/20260222_skyline_mcp`
  - **Base**: `master`
  - **Created**: 2026-02-22
  - **Status**: In Progress
  - **GitHub Issue**: (pending)
  - **PR**: (pending)

  ## Overview

  Implement an MCP server that enables LLM applications (Claude Desktop, Claude Code, VS Code
  Copilot, Cursor, Gemini CLI) to interact with a running Skyline instance through natural
  language. Uses Skyline's Interactive External Tool infrastructure with a direct JSON named
  pipe from the MCP server to JsonToolServer hosted in the Skyline process.

  ## Phase History

  See [TODO-20260222_skyline_mcp-phase1.md](TODO-20260222_skyline_mcp-phase1.md) for
  design, architecture, and sessions 1-16 (2026-02-22 through 2026-03-03).

  See [TODO-20260222_skyline_mcp-phase2.md](TODO-20260222_skyline_mcp-phase2.md) for
  sessions 17-31 (2026-03-03 through 2026-03-06): filtering/sorting/pivot, tutorial tools,
  screen capture, functional tests (82.4% coverage), auto-connect, IJsonToolService shared contract.

  ## Architecture Summary

  **2-tier direct JSON pipe:**
  ```
  AI App --stdio--> SkylineMcpServer (.NET 8.0)
                        | JSON over named pipe
                        v
                    Skyline.exe (JsonToolServer -> ToolService methods)
  ```

  **Three processes:**
  | Process | Framework | Role |
  |---------|-----------|------|
  | **Skyline.exe** | .NET Framework 4.7.2 | Hosts JsonToolServer (JSON pipe) + ToolService |
  | **SkylineMcpConnector** | .NET Framework 4.7.2 | UI shell: connects to Skyline, deploys MCP server, registers with AI apps |
  | **SkylineMcpServer** | .NET 8.0-windows | MCP stdio server, connects to Skyline's JSON pipe |

  **Shared contract:** `SkylineTool/IJsonToolService.cs` contains `IJsonToolService` (28-method
  interface) and `JsonToolConstants` (enums, constants, connection file helpers). Linked-compiled
  into SkylineMcpServer to bridge .NET 4.7.2 and 8.0.

  **Source location:** `pwiz_tools/Skyline/Executables/Tools/SkylineMcp/`

  ## What's Working (end of phase 2)

  ### MCP Tools (25 tools)

  **Read-only:**
  - `skyline_get_document_path`, `skyline_get_version`, `skyline_get_document_status`
  - `skyline_get_selection`, `skyline_set_selection`
  - `skyline_get_replicate`, `skyline_get_replicate_names`, `skyline_set_replicate`
  - `skyline_get_locations` (group/molecule/precursor/transition, scoped enumeration)
  - `skyline_get_report`, `skyline_get_report_from_definition` (filter/sort/pivot support)
  - `skyline_get_settings_list_types`, `skyline_get_settings_list_names`, `skyline_get_settings_list_item`
  - `skyline_get_report_doc_topics`, `skyline_get_report_doc_topic`
  - `skyline_run_command`, `skyline_get_cli_help`, `skyline_get_cli_help_sections`
  - `skyline_get_open_forms`, `skyline_get_graph_data`, `skyline_get_graph_image`, `skyline_get_form_image`
  - `skyline_get_document_settings`, `skyline_get_default_settings`
  - `skyline_get_available_tutorials`, `skyline_get_tutorial`, `skyline_get_tutorial_image`

  **Write:**
  - `skyline_add_report`, `skyline_import_fasta`, `skyline_import_properties`
  - `skyline_insert_small_molecule_transition_list`

  ### Infrastructure
  - Per-instance connection files (`connection-{pipeName}.json`)
  - Resilient MCP server (survives Skyline restarts, per-call connection lifecycle)
  - Auto-connect at startup (checkbox in AI Connector, `EnableMcpAutoConnect` setting)
  - Screen capture with non-Skyline window redaction and permission flow
  - Multi-app registration (Claude Desktop, Claude Code, Gemini CLI, VS Code, Cursor)

  ### Test Coverage
  - JsonToolServerTest: 82.4% coverage (1561/1895 statements)
  - Coverage file: `ai/todos/active/TODO-20260222_skyline_mcp-coverage.txt`

  ### Commit History (15 commits)
  ```
  e150430 Added SkylineMcp bridge for Claude Code integration with running Skyline
  4963875 Added RunCommand MCP tool and --help=sections for LLM-friendly CLI access
  5e62bec Add settings list enumeration to Skyline MCP server
  5275725 Moved MCP JSON pipe server from connector into Skyline process
  bb35e58 Replaced pipe-based report export with file-based export in JsonToolServer
  60a9dd1 Added LLM documentation tools for CLI help and report columns
  9b1ff2a Added chat app registration UI and Claude Desktop process management
  338be46 Add icon for SkylineMcpConnector tool
  65f74a1 Added document-modifying MCP tools and fixed server deployment
  934ce6b Added document status and settings MCP tools with connector lifecycle monitor
  6f35824 Added JSON report definitions, ColumnResolver, and MCP error handling
  6c3244b Added RunCommand document apply-back with undo and audit logging
  6de7c4d Renamed to AI Connector and added Gemini CLI, VS Code, Cursor support
  9f215ce Added reflection dispatch, selection symmetry, and document navigation aids
  e447331 Made MCP server resilient to Skyline restarts with per-instance connection files
  f9e5c74 Added IJsonToolService interface, JsonToolConstants, and auto-connect checkbox
  ```

  ## Remaining Work

  ### Pre-PR

  - [ ] Update testing-patterns.md documentation (partially done in Session 25)
  - [ ] Create PR

  ### Future enhancements (post-PR)

  - [ ] POCO marshalling layer: typed parameters/return values instead of all-string IJsonToolService
  - [ ] FloatingWindow composite capture: individual docked forms in a floating container all
    resolve to the full container rectangle via `GetDockedFormBounds`
  - [ ] Multi-form screenshot: accept a list of form IDs and capture the union bounding box
  - [ ] Self-contained publish for MCP server (eliminates .NET 8.0 runtime dependency)
  - [ ] Wire protocol modernization (replace BinaryFormatter in SkylineTool.dll)
  - [ ] RunCommand write operations need IDocumentContainer integration for full ModifyDocument flow
  - [ ] Immediate Window font: ASCII table borders don't align (proportional font)
  - [ ] Tool Store packaging and submission

  ## Session Log

  (Continued from phase 2, session 31)
