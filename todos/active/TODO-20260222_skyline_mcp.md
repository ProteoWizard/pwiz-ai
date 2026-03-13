  ## Branch Information
  - **Branch**: `Skyline/work/20260222_skyline_mcp`
  - **Base**: `master`
  - **Created**: 2026-02-22
  - **Work started**: 2026-02-27
  - **Status**: In Progress
  - **PR**: [#4065](https://github.com/ProteoWizard/pwiz/pull/4065)

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

  ### MCP Tools (35 tools)

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

  **Multi-instance & diagnostics:**
  - `skyline_get_instances`, `skyline_set_instance`, `skyline_set_logging`

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
  - [x] Clean up stale connection files and fix shutdown cleanup
  - [x] Audit LlmInstruction usage: review all string literals in JsonToolServer.cs and
    SkylineMcpServer tools for consistency — error messages meant for LLM consumption
    should use `LlmInstruction()` wrapper, not bare string literals
  - [x] Add LlmName attribute for user-friendly settings list names
  - [x] Create PR — [#4065](https://github.com/ProteoWizard/pwiz/pull/4065)

  ### Known Issues

  - **Report export streaming bypasses pivot processing** (UPSTREAM):
    `RowFactories.ExportReport` streaming path skips `BindingListSource` when layout has no
    RowTransforms and columnSorts is null/empty, even when `viewSpec.HasTotals`. Affects
    File > Export > Report and named-report API. Document Grid UI unaffected. Our
    `ExportJsonDefinitionReport` has a workaround (inject sort on first GroupBy column).
    Filed as [#4062](https://github.com/ProteoWizard/pwiz/issues/4062), assigned to Nick.
    Pick up fix into our branch before merge.
  - **Report definition pivoting** (FIXED): `ColumnResolver` now tries all row sources and
    picks the one that minimizes total collection steps across all resolved paths. This
    matches `DocumentViewTransformer.ConvertFromDocumentView` which picks the deepest entity
    level any column touches. E.g., `[PeptideModifiedSequence, PrecursorMz, Area]` now
    correctly resolves to Transition (1 collection step for Results!*) instead of Peptide
    (4 collection steps through Precursors!*.Transitions!*.Results!*). Replicate row source
    is still preferred when all paths go through collections (replicate-centric queries).
  - **NormalizedArea column name** (FIXED): `NormalizedArea` now resolves. Root cause was
    that `IsNestedColumn` (ChildDisplayName attribute) took priority over `IsCheckableParent`
    in `TraverseColumns`, so the parent was never indexed. Fixed by checking both.
  - **Isotope label pivot not working in MCP export** (FIXED): Root cause was
    `RowFactories.ExportReport` uses a streaming path when layout is null and sortSpecs
    is null/empty, bypassing BindingListSource which processes PivotKey/PivotValue. Fix:
    when `viewSpec.HasTotals`, inject a sort on the first GroupBy column to force the
    BindingListSource path. See session 36.
  - **Report doc topics use MemoryDataSchema, not SkylineWindow UI mode**: `GetReportDocTopics`
    and `GetReportDocTopic` create a `MemoryDataSchema` with `DataSchemaLocalizer.INVARIANT`,
    which doesn't have a `SkylineWindow` reference. The `DefaultUiMode` falls through to
    `mixed` regardless of the actual window mode. This means topic names and column counts
    don't change when switching between Proteomics/Molecule/Mixed modes. The column names
    returned as "invariant" are actually mode-dependent. Low priority since column resolution
    works correctly for the current mode, but the doc topics may confuse an LLM that sees
    molecule-mode names when the user is in proteomic mode or vice versa.
  - ~~CV Histogram title~~ (Filed as [#4064](https://github.com/ProteoWizard/pwiz/issues/4064), not related to this branch)
  - ~~NormalizedArea column name~~ (FIXED in session 35)

  ### Future enhancements (post-PR)

  - [ ] Immediate Window font: ASCII table borders don't align (proportional font)
  - [ ] Tool Store packaging and submission
  - [x] POCO marshalling layer: typed parameters/return values instead of all-string IJsonToolService
    - Phase 1 (Foundation) and Phase 2 (Reports) completed in session 45
    - Phase 3 (Version mismatch errors) and Phase 4 (Tutorial methods) completed in session 46
  - [ ] Phase 5: Structured list methods (`GetLocations` -> `LocationEntry[]`, `GetOpenForms` -> `FormInfo[]`)

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

  ### Session 37 (2026-03-08): Added diagnostic logging infrastructure

  - **ToolLog class** in JsonToolServer: request-scoped log accumulator with elapsed-ms
    timestamps. Created only when `"log": true` in request JSON; zero overhead otherwise.
  - **`Log()` protected method**: no-op null check when logging off, safe to call from
    any tool method unconditionally.
  - **HandleRequest lifecycle**: creates ToolLog per-request, clears in finally block.
    SerializeResult/SerializeError include log content when present.
  - **`log` added to JSON enum** in IJsonToolService.cs (shared contract).
  - **SkylineConnection**: `LoggingEnabled` and `LastLog` static properties. `Call()` sends
    `"log": true` when enabled and extracts log field from response.
  - **`skyline_set_logging` MCP tool**: toggle for enabling/disabling logging.
  - **`Invoke()` in SkylineTools**: appends `--- Diagnostic Log ---` section to tool
    results when log content is present.
  - **Log calls added to**: `ResolveJsonReportDefinition` (column names, resolution result,
    filters, pivot settings), `AddReportFromDefinition` (save), `ExportNamedReport` (entry),
    `ExportJsonDefinitionReport` (pivot sort injection, export).
  - **Test**: `TestDiagnosticLogging` covers log absent when not requested, absent when no
    Log() calls, and present with content for ExportReportFromDefinition.
  - **nameof() cleanup**: Replaced string literal method names in TestDispatch and
    TestDiagnosticLogging with `nameof(IJsonToolService.MethodName)`.
  - **Manual MCP testing**: Verified with live Skyline instance — logging shows timing for
    column resolution, pivot application, filter application, and export.
  - **Filed [#4062](https://github.com/ProteoWizard/pwiz/issues/4062)**: Report export
    streaming path in RowFactories bypasses pivot processing (affects File > Export > Report
    and named-report API). Assigned to Nick.

  ### Session 38 (2026-03-09): Fixed ColumnResolver row source selection to match ViewEditor

  - **Rewrote row source selection algorithm** in `ColumnResolver.Resolve()`:
    - Old: tried row sources shallowest-first, early-returned on first non-all-collection
      match, or preferred shallowest SublistId for all-collection matches
    - New: tries all row sources and picks the one minimizing total collection steps across
      all resolved paths. Ties broken by first (shallowest) match. Replicate still preferred
      when all paths go through collections.
    - This matches `DocumentViewTransformer.ConvertFromDocumentView` which checks deepest
      entity level first. From the correct row source, entity columns resolve via navigation
      up (no collections), only result columns traverse Results!*.
    - Example: `[PeptideModifiedSequence, PrecursorMz, Area]` now resolves to Transition
      (1 step: Results!*) instead of Peptide (4 steps: Precursors!*.Transitions!*.Results!*)
  - **Added `TotalCollectionSteps()` helper**: sums `CountCollectionSteps` across all paths.
  - **Added `uimode` support for saved reports**:
    - Added `uimode` to `REPORT` enum in `IJsonToolService.cs`
    - `ResolveJsonReportDefinition` now sets `ViewSpec.UiMode` from explicit JSON `uimode`
      parameter, or defaults to `UiModes.FromDocumentType(Program.MainWindow.ModeUI)`
    - Reports created via JSON now get correct `uimode` attribute, matching ViewEditor
  - **Added row source selection tests** in `JsonToolServerTest.cs`:
    - `VerifyRowSource` helper method
    - Tests: Area->Transition, TotalArea->Precursor, PeptideModifiedSequence->Peptide,
      ProteinName+ProteinDescription->Protein
  - **MCP validation** with ABSciex CalCurve document (8 reports at all entity levels):
    - All row sources correct (Protein, Peptide, Precursor, Transition)
    - All column paths use navigation up (short paths), no downward collection traversal
    - All sublists shallow (Results!* or empty)
    - XML definitions match UI-created reports (verified Peptide and Precursor levels)
  - **Discovered**: `MemoryDataSchema` doesn't reflect `SkylineWindow.ModeUI` for report
    doc topics. Topic names and counts don't change between modes. Recorded as known issue.
  - **Updated `ai/docs/build-and-test-guide.md`**: Added "Interactive MCP Testing" workflow
    section documenting the --opendoc launch, edit-build-test cycle, and the critical rule
    to stop Skyline before building.

  **Files changed** (uncommitted):
  - `ColumnResolver.cs` — TotalCollectionSteps, rewrote Resolve() selection algorithm
  - `IJsonToolService.cs` — Added uimode to REPORT enum
  - `JsonToolServer.cs` — uimode handling in ResolveJsonReportDefinition
  - `JsonToolServerTest.cs` — VerifyRowSource helper, 4 row source selection assertions
  - `ai/docs/build-and-test-guide.md` — Interactive MCP Testing workflow section

  ### Session 39 (2026-03-09): Added LlmName attribute and LlmInstruction cleanup

  - **Added `[LlmName]` attribute** to `IJsonToolService.cs` (shared contract): simple
    `[AttributeUsage(AttributeTargets.Class)]` attribute providing culture-invariant,
    user-friendly names for settings list classes (e.g., "Isotope Modifications" for
    `HeavyModList`)
  - **Applied `[LlmName("...")]`** to all 30 settings list classes: 25 in Settings.cs,
    plus ListDefList, GroupComparisonDefList, RemoteAccountList, MetadataRuleSetList,
    and PersistedViews
  - **Rewrote `GetSettingsListTypes()`**: returns sorted single-column LlmName values
    instead of tab-separated property name + localized title
  - **Updated `GetSettingsListNames()`/`GetSettingsListItem()`**: accept LlmName as
    `listType` parameter, fall back to property name for backward compatibility
  - **Added `GetSettingsListName<T>()`**: public static helper for test code to get
    LlmName from type without string literals
  - **LlmInstruction cleanup** across JsonToolServer, JsonTutorialCatalog, JsonUiService:
    wrapped all bare LLM-facing string literals in error messages and return values,
    used new static helpers (`LlmInstruction.Format()`, `.SpaceSeparate()`,
    `.TabSeparate()`) to replace verbose `new LlmInstruction(string.Format(...))` patterns
  - **Build script safety**: excluded `SkylineMcpServer` from process detection and
    suggested kill command to avoid breaking active MCP sessions during builds
  - **Updated `build-and-test-guide.md`**: warning about `Skyline*` glob matching
    `SkylineMcpServer.exe`

  **Files changed:**
  - `IJsonToolService.cs` — LlmNameAttribute class
  - `Settings.cs` — [LlmName] on 25 classes
  - `ListDefList.cs`, `GroupComparisonDefList.cs`, `RemoteAccountList.cs`,
    `MetadataRuleSetList.cs` — [LlmName] attributes
  - `PersistedViews.cs` — [LlmName("Reports")]
  - `JsonToolServer.cs` — BuildLlmNameMap, ResolveLlmListType, GetSettingsListName<T>,
    sorted output, LlmInstruction cleanup
  - `JsonTutorialCatalog.cs` — LlmInstruction cleanup
  - `JsonUiService.cs` — LlmInstruction.Format cleanup
  - `Text.cs` — LlmInstruction.Format, SpaceSeparate, TabSeparate static helpers
  - `JsonToolServerTest.cs` — Updated for LlmName-based API, backward compat tests
  - `Build-Skyline.ps1` — Exclude SkylineMcpServer from process kill
  - `build-and-test-guide.md` — MCP server warning

  ### Session 40 (2026-03-09): Cleaned up stale connection files and fixed shutdown cleanup

  - **Moved stale cleanup into `FindConnectionFiles()`** in SkylineConnection.cs: checks each
    file's PID with `IsSkylineProcess()` as it's loaded, only returns files with live Skyline
    processes, deletes the rest. Every code path (TryConnect, GetAvailableInstances,
    GetConnectionStatus) now cleans up stale files automatically.
  - **Replaced `IsProcessAlive()` with `IsSkylineProcess()`**: checks both that the PID exists
    AND that the process name starts with "Skyline" (case-insensitive). Handles Windows PID
    reuse where a stale file's PID gets recycled to a non-Skyline process.
  - **Removed `CleanupStaleFiles()` method**: no longer needed since FindConnectionFiles handles it.
  - **Simplified callers**: removed stale-tracking lists from TryConnect (~10 lines),
    GetAvailableInstances (~5 lines), and GetConnectionStatus (complete rewrite to 4 lines).
  - **Removed legacy `connection.json` handling**: no legacy files exist (pre-PR branch code).
  - **Added `CleanupStaleConnectionFiles()` to JsonToolServer.cs**: called at end of
    `WriteConnectionInfo()`, so Skyline instances clean up stale files from dead instances at
    startup even when no MCP server is running. Duplicates `IsSkylineProcess` (different runtimes).
  - **Diagnosed shutdown cleanup failure**: used printf debugging to trace form lifecycle.
    Found `SkylineWindow.OnHandleDestroyed` calls `Process.GetCurrentProcess().Kill()` — a
    legacy hack to avoid "invalid string binding" errors from native vendor DLLs. This kills
    the process before `Application.Run()` returns, so `StopToolService()` in Program.Main
    never executed.
  - **Moved `StopToolService()` call** from after `Application.Run()` in Program.cs to
    `OnHandleDestroyed` in Skyline.cs, before the `Process.Kill()` hack. Added clear comments
    warning that code after `Application.Run()` will never run.

  **Files changed:**
  - `SkylineConnection.cs` — IsSkylineProcess, TryDeleteFile, simplified callers, removed legacy
  - `JsonToolServer.cs` — CleanupStaleConnectionFiles, IsSkylineProcess
  - `Program.cs` — Removed StopToolService call, added warning comments
  - `Skyline.cs` — Added StopToolService call in OnHandleDestroyed, improved HACK comment

  ### Session 41 (2026-03-10): Document-level operations via IDocumentOperations

  - **Added `IDocumentOperations` interface** (`CommandLine.cs`): three methods —
    `OpenDocument`, `NewDocument`, `SaveDocument` — abstracting document-level file
    operations so they can be overridden for SkylineWindow-hosted execution.
  - **`CommandLine` implements `IDocumentOperations`** directly: default implementation
    wraps existing `OpenSkyFile`, `NewSkyFile`, and `SaveDocument` methods. Constructor
    sets `DocumentOperations = this`. No separate nested class needed.
  - **`SkylineWindowDocumentOperations`** in `JsonToolServer.cs`: overrides that delegate
    to `SkylineWindow.OpenFile()`, `NewDocument(true)`, and `SaveDocument()` via
    `Invoke()` on the UI thread. Shows LongWaitDlg progress, properly updates
    `DocumentFilePath` and `_savedVersion` (clean state).
  - **Refactored `RunInner` and `ProcessDocument`**: always delegate through
    `DocumentOperations` — no if/else branching. Output messages ("Opening file...",
    "File saved.") moved to callers so both implementations get identical output.
  - **`RunCommandImpl` updated**: passes `DocumentFilePath` as initial `_skylineFile` to
    `CommandLine` constructor. Apply-back check skips when host already has the current
    doc (from `SkylineWindowDocumentOperations`).
  - **`--save` null path fix**: `SkylineWindowDocumentOperations.SaveDocument` falls
    back to `Program.MainWindow.SaveDocument()` (no-arg) when `saveFile` is null, which
    uses the window's current `DocumentFilePath`. Previously caused a hang by passing
    null to `FileSaver`.
  - **CLI synonyms** (`CommandArgs.cs`): `--open` (synonym for `--in`) and `--save-as`
    (synonym for `--out`) with resource strings in `CommandArgUsage.resx/.Designer.cs`.
    Visible in `--help` output for LLM discoverability.
  - **`--opendoc=path` syntax** (`Program.cs`, `Skyline.cs`): now supports both
    `--opendoc path` (space-separated) and `--opendoc=path` (equals-separated).
  - **Added `Saved` field to `GetDocumentStatus`**: shows `yes` or `no (unsaved changes)`
    based on `SkylineWindow.Dirty`, placed after the Document path line.
  - **Added `TestDocumentOperations`** in `JsonToolServerTest.cs`: exercises `--new`,
    `--save`, `--save-as`, `--open`, `--in`, and combined `--open + --refine + --out`.
    Verifies DocumentFilePath updates, dirty state, round-trip data integrity.
  - **MCP-tested interactively**: all operations produce correct output, update
    DocumentFilePath, and set clean state properly.

  **Known issue (minor)**: `--new` followed by its implicit `--save` shows
  `Saved: no (unsaved changes)` immediately after. Likely `NewDocument(true)` sets
  `_savedVersion`, then `SaveDocument` applies the doc via `ModifyDocument` which
  increments `UserRevisionIndex` before saving. Not a blocker — file is actually saved.

  ### Session 42 (2026-03-10): Test fixes and code style cleanup

  - **Fixed path quoting in tests**: `ParseArgs` splits on spaces, so test paths
    containing spaces (SkylineTester directories) must be `.Quote()`d when passed
    through `Argument + value` operator.
  - **Fixed `NewDocument` not setting `DocumentFilePath`**: `SkylineWindowDocumentOperations
    .NewDocument` now calls `SaveDocument(skylineFile)` after `NewDocument(true)` so
    that `DocumentFilePath` is set for subsequent `--save` commands.
  - **Stronger test assertion**: `TestDocumentOperations` saves original document
    first (`--save`) so on-disk state matches in-memory, enabling exact group count
    assertion when re-opening with `--in`.
  - **Refactored `TestRunCommand` to use `CommandArgs.ARG_*` constants**:
    replaced raw string literals (`@"--version"`, `@"--refine-min-peptides=100"`, etc.)
    with `CommandArgs.ARG_VERSION.ArgumentText`, `CommandArgs.ARG_REFINE_MIN_PEPTIDES + value`,
    `TextUtil.SpaceSeparate()` — consistent style with `TestDocumentOperations`.
  - **Tests passing**: `JsonToolServerTest` (16s) and all 44 `CommandLineTest` tests (60s).

  **Files changed** (10 files, +285 −41):
  - `CommandLine.cs` — IDocumentOperations interface, CommandLine implements it,
    refactored RunInner/ProcessDocument, constructor accepts skylineFile, moved
    output messages to callers
  - `CommandArgs.cs` — ARG_OPEN, ARG_SAVE_AS synonyms
  - `CommandArgUsage.resx` — _open, _save_as descriptions
  - `CommandArgUsage.Designer.cs` — _open, _save_as properties
  - `JsonToolServer.cs` — SkylineWindowDocumentOperations, updated RunCommandImpl,
    Saved field in GetDocumentStatus
  - `JsonToolServerTest.cs` — TestDocumentOperations, refactored TestRunCommand
  - `Program.cs` — --opendoc=path support
  - `Skyline.cs` — --opendoc=path parsing
  - `IJsonToolService.cs` — using System.IO cleanup
  - `JsonUiService.cs` — removed unused using, simplified cast

  ### Session 43 (2026-03-11): Tool Store improvements and getting-started documentation

  - **Tool Store download URL fix**: `ToolStoreItem` now stores `DownloadUrl` from the
    JSON API response. `GetToolZipFileWithProgress` uses server-provided URL when available,
    falling back to LSID-based URL construction. Fixes download failures when Tool Store
    container path doesn't match hardcoded URL.
  - **Windows Store Claude Desktop detection**: `ClaudeDesktopConfigPath` now checks both
    standard `%APPDATA%\Claude\` and Windows Store sandbox path
    `%LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude\`.
  - **Auto-expand setup panel**: `MainForm` auto-expands the AI client registration panel
    on first launch when no clients are registered (`ChatAppRegistry.AnyClientRegistered()`).
  - **Getting-started documentation**: Created `tool-inf/docs/` with `index.html` (12 screenshots)
    covering installation from Tool Store, AI client registration, connection verification,
    and first interaction via Claude Desktop.
  - **LabKey SkylineToolsStore fix**: Wrapped `recordToolDownload` in `ignoreSqlUpdates()`
    to fix dev-mode mutating SQL assertion on GET download action.

  **Files changed:**
  - `ChatAppRegistry.cs` — Windows Store config path, AnyClientRegistered()
  - `MainForm.cs` — Auto-expand setup panel
  - `ToolStoreDlg.cs` — DownloadUrl property, server-provided download URL support
  - `ToolUpdatesDlg.cs` — Updated IToolUpdateHelper signature
  - `ToolStoreDlgTest.cs`, `ToolUpdatesTest.cs` — Updated test implementations
  - `tool-inf/docs/` — index.html, SkylineStyles.css, 12 screenshots (s-01 through s-12)

  ### Session 44 (2026-03-11): Tool description, .NET 8 prereq check, document loading fix

  - **Expanded `info.properties` description**: Rewrote as a 3-paragraph abstract of the
    getting-started documentation: what it is and how to set up, capabilities list, and
    prerequisites. Uses `\` line continuation following the MSstats pattern.
  - **Added .NET 8.0 Desktop Runtime prerequisite check**: `McpServerDeployer.IsDotNet8Installed()`
    checks for `Microsoft.WindowsDesktop.App 8.*` in `%ProgramFiles%\dotnet\shared\`.
    `MainForm.DeployMcpServer()` checks before deploying and offers to open the download page
    if missing, preventing a confusing failure when the server can't start.
  - **Fixed RunCommand creating spurious undo entries on --open/--new**: Root cause was
    `SkylineWindowDocumentOperations.OpenDocument()`/`NewDocument()` returning before
    background loaders finished. By the time `RunCommandImpl` compared `commandLine.Document`
    against `Program.MainWindow.Document`, background loading had advanced the MainWindow
    document past the returned snapshot, causing `ModifyDocument` to push a stale document
    back and create a dirty state with an undo entry. Fix: added `WaitForDocumentLoaded()`
    that subscribes to `SkylineWindow.DocumentChangedEvent` and waits until
    `Document.IsLoaded` before returning, matching the contract of the command-line
    `IDocumentOperations` implementation. Also fixes potential data correctness issues
    with compound commands like `--open --import-file`.
  - **Known issue resolved**: The `--new` dirty state issue noted in Session 41 (line 511-514)
    is fixed by the same `WaitForDocumentLoaded()` change.
  - **Tests**: `JsonToolServerTest` passes (10s).

  **Files changed:**
  - `McpServerDeployer.cs` — IsDotNet8Installed(), DotNetDownloadUrl
  - `MainForm.cs` — .NET 8.0 check in DeployMcpServer()
  - `JsonToolServer.cs` — WaitForDocumentLoaded() in SkylineWindowDocumentOperations
  - `info.properties` — Expanded description

  ### Session 45 (2026-03-12): Typed POCO interface — Phase 1 (Foundation) & Phase 2 (Reports)

  Implemented the typed POCO marshalling layer for IJsonToolService, replacing the all-string
  pattern with typed parameters and return values. JSON remains the wire format; the dispatch
  layer handles serialization/deserialization automatically.

  **Phase 1 — Foundation:**
  - **`JsonToolModels.cs`** — New file with POCOs: `ReportMetadata`, `ReportDefinition`,
    `ReportFilter`, `ReportSort`, `TutorialMetadata`, `TocEntry`, `TutorialImageMetadata`.
    PascalCase properties mapped to snake_case JSON via naming policies. Link-compiled into
    both .NET 4.7.2 (SkylineTool.csproj) and .NET 8.0 (SkylineMcpServer.csproj).
  - **`JsonToolServer.cs`** — Added `_snakeCaseSerializer` (Newtonsoft SnakeCaseNamingStrategy).
    Method discovery changed from `this.GetType()` to `typeof(IJsonToolService)`. `Dispatch()`
    handles typed params via `DeserializeArg()`. `SerializeResult()` handles typed returns via
    `JToken.FromObject()`.
  - **`SkylineConnection.cs`** — `Call()` handles structured results (Object/Array → GetRawText).
    Added `CallTyped<T>()` with `_snakeCaseOptions` (System.Text.Json SnakeCaseLower).

  **Phase 2 — Report methods:**
  - **`IJsonToolService.cs`** — `ExportReport` and `ExportReportFromDefinition` return
    `ReportMetadata`. `ExportReportFromDefinition` and `AddReportFromDefinition` take
    `ReportDefinition` parameter.
  - **`JsonToolServer.cs`** — `BuildReportMetadata` returns POCO. `ResolveJsonReportDefinition`
    consumes `ReportDefinition` POCO directly (no JObject parsing). `ParseFilterSpecs` and
    `ParseSortSpecs` consume typed arrays.
  - **`SkylineTools.cs`** — `GetReport` and `GetReportFromDefinition` use `CallTyped<ReportMetadata>`.
    `FormatReportResult` takes typed POCO with direct property access.
  - **`JsonToolServerTest.cs`** — All report tests updated for typed API.

  ### Session 46 (2026-03-13): Typed POCO interface — Phase 3 (Version errors) & Phase 4 (Tutorials)

  **Phase 3 — Version mismatch error enrichment:**
  - **`JsonToolServer.cs:129`** — Changed `Install.Version` to `Install.ProgramNameAndVersion`
    in `WriteConnectionInfo()`. Connection file now contains rich identity string (e.g.,
    "Skyline-daily (64-bit) 26.1.1.238 (6c3244bc0a)") instead of bare version.
  - **`SkylineConnection.cs`** — Added `SkylineVersion` property on connection instance,
    populated from connection file during `TryConnectToInstance()`. Readable after Dispose
    for error enrichment.
  - **`SkylineTools.cs`** — Restructured `Invoke()` to declare `connection` outside try block.
    Added catch logic detecting "Unknown method:" errors from Skyline and enriching with the
    Skyline identity string: "This method is not available in {skylineVersion}. A newer
    version of Skyline may be required."

  **Phase 4 — Tutorial methods:**
  - **`IJsonToolService.cs`** — `GetTutorial` returns `TutorialMetadata`, `GetTutorialImage`
    returns `TutorialImageMetadata`.
  - **`JsonTutorialCatalog.cs`** — `FetchTutorial` returns `TutorialMetadata` POCO (builds
    `List<TocEntry>` instead of JArray). `FetchTutorialImage` returns `TutorialImageMetadata`.
    Removed `Newtonsoft.Json.Linq` dependency entirely.
  - **`JsonToolServer.cs`** — Updated delegate methods to match new return types.
  - **`SkylineTools.cs`** — Tutorial tools use `CallTyped<TutorialMetadata>` and
    `CallTyped<TutorialImageMetadata>` with direct property access. Added `FormatTutorialResult`
    helper. Removed unused `System.Text.Json`, `REPORT`, and `TUTORIAL` imports.
  - **`JsonToolServerTest.cs`** — Updated tutorial test assertions to use typed POCO properties
    instead of `JObject.Parse`/indexer access. Removed unused `TUTORIAL` alias.
  - **Build**: Both projects (Skyline .NET 4.7.2 + SkylineMcpServer .NET 8.0) build clean.
  - **Tests**: `TestJsonToolServer` passes (35s).

  **Files changed** (committed as c7719d59):
  - `IJsonToolService.cs` — Typed tutorial return types
  - `JsonToolModels.cs` — POCOs (new file from session 45)
  - `SkylineTool.csproj` — JsonToolModels.cs added
  - `SkylineMcpServer.csproj` — JsonToolModels.cs link-compiled
  - `JsonToolServer.cs` — _snakeCaseSerializer, typed dispatch, ProgramNameAndVersion
  - `JsonTutorialCatalog.cs` — POCO returns, removed JObject dependency
  - `SkylineConnection.cs` — SkylineVersion, CallTyped<T>, structured result handling
  - `SkylineTools.cs` — Typed tutorial/report calls, version error enrichment, FormatTutorialResult

  ### Session 47 (2026-03-13): Fixed InvokeOnUiThread threading and intermittent test failure

  Fixed an intermittent `Win32Exception: The handle is invalid` in `TestScreenCapturePermissionDlg`
  caused by calling `InvokeOnUiThread` from the UI thread. The test used `ShowDialog<T>` which
  runs the action via `SkylineBeginInvoke` (UI thread), but `InvokeOnUiThread` is designed for
  background-thread callers only (pipe server thread in production).

  - **`JsonUiService.cs`** — Added `Assume.IsTrue(Program.MainWindow.InvokeRequired)` to
    `InvokeOnUiThread`. Catches misuse immediately rather than producing a transient
    `Win32Exception` that manifests as a `ThreadExceptionDialog` and 360s test timeout.
  - **`JsonToolServerTest.cs`** — Fixed 6 call sites that ran server methods on the UI thread:
    - 3 `ShowDialog<ScreenCapturePermissionDlg>` calls replaced with `ActionUtil.RunAsync` +
      `WaitForOpenForm` — matches real-world threading (pipe server thread → UI marshal)
    - 3 `WaitForConditionUI` calls with server methods replaced with `WaitForCondition` —
      server calls must not run on the UI thread
  - **`JsonToolModels.cs`** — Converted floating XML doc comment (not attached to any type)
    to regular comments, fixing ReSharper warning on TeamCity.
  - **Tests**: `TestJsonToolServer` passes (45s).
