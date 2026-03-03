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

  ## Phase 1 History

  See [TODO-20260222_skyline_mcp-phase1.md](TODO-20260222_skyline_mcp-phase1.md) for full
  design, architecture, session logs, and implementation details from sessions 1-16
  (2026-02-22 through 2026-03-03).

  ## Architecture Summary (from phase 1)

  **2-tier direct JSON pipe:**
  ```
  AI App ──stdio──> SkylineMcpServer (.NET 8.0)
                        │ JSON over named pipe
                        v
                    Skyline.exe (JsonToolServer -> ToolService methods)
  ```

  **Three processes:**
  | Process | Framework | Role |
  |---------|-----------|------|
  | **Skyline.exe** | .NET Framework 4.7.2 | Hosts JsonToolServer (JSON pipe) + ToolService |
  | **SkylineMcpConnector** | .NET Framework 4.7.2 | UI shell: reads connection.json, deploys MCP server, registers with AI apps |
  | **SkylineMcpServer** | .NET 8.0-windows | MCP stdio server, connects to Skyline's JSON pipe |

  **Source location:** `pwiz_tools/Skyline/Executables/Tools/SkylineMcp/`

  ## What's Working (end of phase 1)

  ### MCP Tools (25 tools)

  **Read-only:**
  - `skyline_get_document_path`, `skyline_get_version`, `skyline_get_document_status`
  - `skyline_get_selection`, `skyline_get_replicate`, `skyline_get_replicate_names`
  - `skyline_get_report` (named reports, file-based), `skyline_get_report_from_definition` (JSON)
  - `skyline_add_report` (save JSON report definition to Skyline's report list)
  - `skyline_get_document_settings`, `skyline_get_default_settings`
  - `skyline_get_settings_list_types`, `skyline_get_settings_list_names`, `skyline_get_settings_list_item`
  - `skyline_get_cli_help_sections`, `skyline_get_cli_help`
  - `skyline_get_report_doc_topics`, `skyline_get_report_doc_topic`
  - `skyline_get_locations` (document tree enumeration)

  **Navigation:**
  - `skyline_set_selection` (with multi-selection support)
  - `skyline_set_replicate`

  **Document-modifying:**
  - `skyline_insert_small_molecule_transition_list` (CSV with column headers)
  - `skyline_import_fasta` (standard FASTA format)
  - `skyline_import_properties` (annotations via ElementLocator CSV)
  - `skyline_run_command` (full SkylineCmd CLI with undo + audit logging)

  ### Connector Features
  - Deploys MCP server to `~/.skyline-mcp/server/`
  - One-click registration for 5 AI apps: Claude Desktop, Claude Code, VS Code, Cursor, Gemini CLI
  - Skyline version check (minimum 26.1.1.061)
  - Auto-close when Skyline exits

  ### Key Architectural Decisions
  - Reflection-based dispatch in JsonToolServer (auto-discovers public string methods)
  - ColumnResolver for JSON report definitions (maps display names to PropertyPaths)
  - LlmInstruction type for text intended for LLM consumers
  - RunCommand applies changes back to SkylineWindow with single undo record
  - ToolService.cs has zero diff against master (all MCP code in JsonToolServer)

  ### Commits (14 on branch)
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
  ```

  ## Remaining Work

  ### Near-term (phase 2)

  - [ ] Implement sorting and filtering in report definitions for get and add report by definition
  - [ ] Implement `get_open_graphs` (available open graphs), `get_graph_data`, and `get_graph_screenshot`
    - Future? `get_available_graphs` and `open_graph`?
  - [ ] Implement `get_available_tutorials` and `get_tutorial_url`
  - [ ] Implement unit tests of at least the Skyline side of the API
  - [ ] Test ImportProperties end-to-end with annotation workflow from conversation
  - [ ] Create PR

  ### Future enhancements (post-PR)

  - [ ] Multiple Skyline instances: `connection-{GUID}.json` pattern
  - [ ] Self-contained publish for MCP server (eliminates .NET 8.0 runtime dependency)
  - [ ] Wire protocol modernization (replace BinaryFormatter in SkylineTool.dll)
  - [ ] RunCommand write operations need IDocumentContainer integration for full ModifyDocument flow
  - [ ] Immediate Window font: ASCII table borders don't align (proportional font)
  - [ ] Tool Store packaging and submission

  ## Session Log

  (Continued from phase 1, session 16)
