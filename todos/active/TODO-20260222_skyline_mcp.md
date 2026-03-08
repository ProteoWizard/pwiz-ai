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

  ### MCP Tools (34 tools)

  **Document info:**
  - `skyline_get_document_path`, `skyline_get_version`, `skyline_get_document_status`
  - `skyline_get_document_settings`, `skyline_get_default_settings`

  **Navigation & selection:**
  - `skyline_get_selection`, `skyline_set_selection`
  - `skyline_get_replicate`, `skyline_get_replicate_names`, `skyline_set_replicate`
  - `skyline_get_locations` (group/molecule/precursor/transition, scoped enumeration)

  **Reports & data export:**
  - `skyline_get_report`, `skyline_get_report_from_definition` (filter/sort/pivot support)
  - `skyline_get_report_doc_topics`, `skyline_get_report_doc_topic`

  **Settings & configuration:**
  - `skyline_get_settings_list_types`, `skyline_get_settings_list_names`, `skyline_get_settings_list_item`

  **CLI & commands:**
  - `skyline_run_command`, `skyline_get_cli_help`, `skyline_get_cli_help_sections`

  **UI inspection & capture:**
  - `skyline_get_open_forms`, `skyline_get_graph_data`, `skyline_get_graph_image`, `skyline_get_form_image`

  **Tutorials:**
  - `skyline_get_available_tutorials`, `skyline_get_tutorial`, `skyline_get_tutorial_image`

  **Multi-instance:**
  - `skyline_get_instances`, `skyline_set_instance`

  **Document-modifying:**
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

  - [x] Multi-instance support: `skyline_get_instances` and `skyline_set_instance` MCP tools
    - `SkylineConnection.cs`: Added `TargetProcessId`, `GetAvailableInstances()`, `TryConnectToInstance()`
    - `SkylineTools.cs`: Added `GetInstances()` and `SetInstance()` tools
    - Per-instance connection files (`connection-{pipeName}.json`) already in place
    - Manually tested with two Skyline instances — working
    - **Needs commit** and code coverage check (connection file I/O likely uncovered)
  - [x] Fix ColumnResolver row source selection and path preference for report definitions
  - [ ] Add unit tests for multi-instance connection file writing/cleanup
  - [ ] Audit LlmInstruction usage: review all string literals in JsonToolServer.cs and
    SkylineMcpServer tools for consistency — error messages meant for LLM consumption
    should use `LlmInstruction()` wrapper, not bare string literals
  - [ ] Create PR

  ### Known Issues

  - **Report definition pivoting** (FIXED): `ColumnResolver` now tries all row sources and
    prefers the one with the shallowest SublistId. `IndexColumn` helper prefers paths with
    fewer collection steps. `IsCheckableParent` indexes AnnotatedDouble parent types.
    Result: `["PeptideSequence", "ReplicateName", "NormalizedAreaRaw"]` now correctly
    produces Peptide row source with `Results!*` sublist (546 rows, 3 columns).
  - **NormalizedArea column name** (FIXED): `NormalizedArea` now resolves. Root cause was
    that `IsNestedColumn` (ChildDisplayName attribute) took priority over `IsCheckableParent`
    in `TraverseColumns`, so the parent was never indexed. Fixed by checking both.
  - **Isotope label pivot not working in MCP export** (FIXED): Root cause was
    `RowFactories.ExportReport` uses a streaming path when layout is null and sortSpecs
    is null/empty, bypassing BindingListSource which processes PivotKey/PivotValue. Fix:
    when `viewSpec.HasTotals`, inject a sort on the first GroupBy column to force the
    BindingListSource path. See session 36.
  - **CV Histogram title**: View > Peak Areas > CV Histogram shows "Peak Areas - Histogram"
    instead of "Peak Areas - CV Histogram" (cosmetic, low priority)
  - ~~NormalizedArea column name~~ (FIXED in session 35)

  ### Future enhancements (post-PR)

  - [ ] Immediate Window font: ASCII table borders don't align (proportional font)
  - [ ] Tool Store packaging and submission
  - [ ] POCO marshalling layer: typed parameters/return values instead of all-string IJsonToolService

  ### Potential further future enhancements (post-PR)
  - [ ] FloatingWindow composite capture: individual docked forms in a floating container all
    resolve to the full container rectangle via `GetDockedFormBounds`
  - [ ] Multi-form screenshot: accept a list of form IDs and capture the union bounding box
  - [ ] Self-contained publish for MCP server (eliminates .NET 8.0 runtime dependency)
  - [ ] Wire protocol modernization (replace BinaryFormatter in SkylineTool.dll) - Issue: existing tools depend on it

  ## Session Log

  (Continued from phase 2, session 31)

  ### Session 32 (2026-03-07): Multi-instance implementation

  Implemented multi-instance Skyline MCP support (prior session, TODO not updated at the time):

  - **`SkylineConnection.cs`** — core multi-instance infrastructure:
    - Added `TargetProcessId` static property: when set, `TryConnect()` targets a specific
      Skyline process instead of the most-recently-connected one
    - Added `GetAvailableInstances()`: scans all `connection-{pipeName}.json` files, probes
      each live process for its document path, returns `List<InstanceInfo>`
    - Refactored pipe connection logic into `TryConnectToInstance(ConnectionInfo)` helper,
      shared by `TryConnect()` and `GetAvailableInstances()`
    - Added `InstanceInfo` class (ProcessId, SkylineVersion, ConnectedAt, DocumentPath, IsTargeted)
    - Automatic stale-target cleanup: if targeted process is dead, clears TargetProcessId
  - **`SkylineTools.cs`** — two new MCP tools:
    - `skyline_get_instances`: lists all connected Skyline instances with PID, version,
      document path, and active-target status
    - `skyline_set_instance(processId)`: targets a specific instance by PID; pass 0 to
      clear. Verifies reachability and reports version/document on success

  ### Session 33 (2026-03-07): Multi-instance testing, report pivoting investigation

  - Manually tested multi-instance support with two Skyline instances — working correctly:
    listed instances, switched between them, queried document status from each
  - Discovered report definition pivoting bugs during testing with real-world documents:
    - Simple single-column reports (e.g. just `PeptideSequence`) producing pivoted
      multi-column results — 3 columns instead of 1
    - Root cause: `ColumnResolver` selects `Protein` row source because all column paths
      go through collections. The `AllPathsThroughCollection` check defers to Replicate
      row source, but when Replicate can't resolve, it falls back to the Protein result
      which produces pivoted output
    - The `pivot_replicate` logic in `JsonToolServer.ResolveJsonReportDefinition` has
      issues: `false` (explicit) forces a replicate sublist that can break target-only
      queries; `null` (omitted) should default to unpivoted but doesn't intervene
    - Multiple fix attempts in `ColumnResolver.cs` (break→continue) and `JsonToolServer.cs`
      (else-if→else) made things progressively worse
    - All report-related changes reverted to committed baseline
    - Detailed findings documented in `ai/.tmp/handoff-report-pivoting.md`
  - Updated TODO with known issues and next steps

  ### Session 34 (2026-03-07): Fixed ColumnResolver row source and path selection

  - Deep research into ViewEditor column tree, ColumnDescriptor traversal, and how
    the UI maps checked columns to PropertyPaths
  - Fixed `ColumnResolver.Resolve()`: replaced `break` after first all-collection match
    with continuation through all row sources, preferring shallowest SublistId
  - Added `IndexColumn()` helper: when same invariant name resolves through multiple
    paths, prefers the one with fewer collection steps
  - Added `IsCheckableParent()`: indexes IAnnotatedValue parent types (AnnotatedDouble)
    so they can be used as column names, matching ViewEditor behavior
  - Added `CountCollectionSteps()`: counts `!*` lookups in a PropertyPath for comparison
  - Updated pivot test: expects 13 rows (Peptide level) instead of 5 (Protein level)
  - Verified via MCP: `["PeptideSequence","ReplicateName","NormalizedAreaRaw"]` now
    produces correct Peptide/Results!* report matching UI definition
  - Remaining: `NormalizedArea` parent name still doesn't resolve (invariant name issue)

  ### Session 36 (2026-03-08): Fixed report doc topics to match ViewEditor hierarchy

  - **Rewrote GetReportDocTopics/GetReportDocTopic** to use curated entity-level topics
    instead of raw ColumnResolver group names. Topics now match the ViewEditor hierarchy.
  - **Added `GetTopics()` to ColumnResolver**: Walks ColumnDescriptor tree from Protein,
    Replicate, and AuditLogRow roots. Uses `TOPIC_ENTITY_TYPES` ordered array as single
    source of truth for which entities get topics and in what order.
  - **Topic hierarchy**: Protein → ProteinResults → Peptides → PeptideResults → Precursors →
    PrecursorResults → PrecursorResultsSummary → Transitions → TransitionResults →
    TransitionResultsSummary → Replicate → AuditLog (12 topics)
  - **Sub-group folding**: QuantificationResult, CalibrationCurve, FiguresOfMerit, etc.
    fold into their parent topic. ResultFile folds into Replicate. AuditLogDetailRow
    folds into AuditLog.
  - **Dictionary collection handling**: `GetEntityType()` uses `ElementValueType` for
    dictionary collections (where `ElementType` is `KeyValuePair<K,V>`).
  - **Summary types as direct properties**: `DIRECT_PROPERTY_TOPIC_TYPES` set identifies
    PrecursorResultSummary and TransitionResultSummary, which are direct properties on
    their parent (not collections) but get their own topics.
  - **AuditLog naming**: Overrides "AuditLogRow" display name to "AuditLog" via
    `nameOverride` parameter on `AddEntityTopic`.
  - **Added AuditLogRow to TARGET_ROW_SOURCES**: Enables audit log column resolution in
    `Resolve()` for report definitions.
  - **Format change**: `GetReportDocTopics` now returns `Name\tCount` per line.
  - **Expanded `IsCheckableParent`**: Now includes `SkylineObject` (entity references like
    "Peptide" from Precursor context) and `ProteomicSequence` ("ModifiedSequence"), in
    addition to `IAnnotatedValue`. This makes entity reference columns and nested column
    parents resolvable, matching ViewEditor behavior where all non-collection nodes are
    checkable.
  - **Root entity indexing**: `BuildColumnIndex` and `AddEntityTopic` now index the root
    ColumnDescriptor (e.g., "Precursor" from Precursor row source), so the root entity
    display name is a valid column name.
  - **Isotope label pivot fix**: `RowFactories.ExportReport` uses a streaming path when
    layout is null and sortSpecs is null/empty, bypassing `BindingListSource` which
    processes PivotKey/PivotValue/GroupBy annotations. Fix: when `viewSpec.HasTotals`,
    inject a sort on the first GroupBy column to force the BindingListSource path.
    Verified: 125 rows pivoted by isotope label (light/heavy/all 15N) matching UI output.
  - **Test updates**: `TestReportDocumentation` validates 10-16 topics, Name\tCount format,
    hierarchy ordering, NormalizedArea discoverability, audit log presence, and column
    resolution spot-checks including entity references (Precursor, Peptide, ModifiedSequence).

  **Verified via MCP** (live Skyline with ABSciex CalCurve document):
  - `skyline_get_report_doc_topics` returns 12 ordered topics with column counts
  - `skyline_get_report_doc_topic("PrecursorResults")` returns 71 columns
  - `skyline_get_report_from_definition({"select":["Peptide","Precursor","ModifiedSequence"]})`
    successfully resolves all three columns (entity ref, root, nested parent)
  - Isotope label pivoting now works: 125 rows pivoted by label type (was 365 unpivoted)

  **Fixed: Isotope label pivot in MCP export**
  - Root cause: `RowFactories.ExportReport` skips `BindingListSource` (which processes
    pivot annotations) when layout is null and sortSpecs is null or empty, using a
    streaming path instead. An empty `List<ColumnSort>` still has Count==0.
  - Fix: when `viewSpec.HasTotals`, inject a sort on the first GroupBy column to force
    the BindingListSource path. This adds minimal overhead (sort on the group key which
    is already natural order) and ensures pivot processing occurs.

  **Files changed** (uncommitted):
  - `ColumnResolver.cs` — GetTopics(), TopicInfo, TOPIC_ENTITY_TYPES, DIRECT_PROPERTY_TOPIC_TYPES,
    AddEntityTopic, CollectTopicColumns, ListAllChildren, CollectNestedScalars, GetEntityType,
    expanded IsCheckableParent, root entity indexing, AuditLogRow in TARGET_ROW_SOURCES
  - `JsonToolServer.cs` — Rewrote GetReportDocTopics/GetReportDocTopic with GetTopicList/
    FindMatchingTopic, removed ROW_SOURCE_TYPES/GetAllAvailableColumns/FindMatchingGroup,
    HasTotals pivot fix in ExportJsonDefinitionReport
  - `JsonToolServerTest.cs` — Rewrote TestReportDocumentation, added entity reference resolution tests

  ### Session 35 (2026-03-08): Aligned report column discovery with resolution

  - **Fixed NormalizedArea resolution**: Root cause was `IsNestedColumn` (ChildDisplayName
    attribute) taking priority over `IsCheckableParent` in `TraverseColumns`. The parent
    AnnotatedDouble was never indexed because the nested branch didn't check for checkable
    parents. Fixed by adding `IsCheckableParent` check in the nested column branch.
  - **Added ColumnInfo with Group**: `ColumnResolver.ColumnInfo` now includes `Group`
    (entity type name), `Description`, and `TypeName` alongside `InvariantName` and
    `PropertyPath`. Groups match ViewEditor sections (Protein, PeptideResult,
    QuantificationResult, PrecursorResultSummary, etc.). Group name derived from
    `DataSchema.GetInvariantDisplayName()` so it respects proteomic vs small molecule
    UI mode (e.g., "Protein" vs "MoleculeList").
  - **Rewrote GetReportDocTopics**: Returns entity-type group names derived from
    ColumnResolver traversal of all row sources. Covers ~20 groups matching ViewEditor
    sections (Protein, Peptide, PeptideResult, PrecursorResultSummary, QuantificationResult,
    TransitionResult, Replicate, etc.).
  - **Rewrote GetReportDocTopic**: Returns only columns belonging to the requested group,
    not all columns from a row source. Column names guaranteed to resolve in ColumnResolver.
  - **Added `FlattenToSingleLine`**: `TextUtil` extension method for collapsing multi-line
    descriptions into single-line TSV fields. Collapses `\r\n`, `\n`, `\t`, and runs of
    spaces into single spaces.
  - **Test**: Spot-checks topic structure and case-insensitive matching. Verifies
    NormalizedArea appears in QuantificationResult group and resolves via ColumnResolver.
    Kept lightweight (~10s) by avoiding exhaustive per-column resolution.
  - **Removed dead code**: `GenerateReportDocHtml`, `StripHtmlTags` removed (no callers).
  - **Fixed magic strings**: `"PersistedViews"` → `nameof(PersistedViews)`.
  - **TODO added**: Audit all LlmInstruction usage for consistency before PR.

  **Files changed** (uncommitted):
  - `ColumnResolver.cs` — ColumnInfo with Group, NormalizedArea fix, GetAvailableColumns
  - `JsonToolServer.cs` — Rewrote GetReportDocTopics/GetReportDocTopic, removed dead code
  - `JsonToolServerTest.cs` — Updated TestReportDocumentation with group-based tests
  - `Text.cs` — Added FlattenToSingleLine extension method
