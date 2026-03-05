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

  - [x] Implement filtering in report definitions (filter array with 12 operations, "did you mean" errors)
  - [x] Implement sorting in get_report_from_definition (via RowFilter.ColumnSort, query-time only)
  - [x] Implement pivotReplicate and pivotIsotopeLabel flags in report definitions
  - [x] Implement `get_open_forms`, `get_graph_data`, and `get_graph_image` MCP tools
    - Extracted JsonUiService.cs from JsonToolServer (UI interaction service layer)
    - Three abstraction levels: primitives, UI patterns, complete operations
    - Shared temp dir/file path infrastructure (consolidated with tutorial tools)
    - Future? `get_available_graphs` and `open_graph`?
  - [x] Sync StartPage tutorial list to match wiki page exactly (see Session 18 design)
  - [x] Implement `get_available_tutorials`, `get_tutorial`, and `get_tutorial_image` (see Sessions 18-20)
    - [x] Created TutorialCatalog.cs as single master definition (section/tutorial list, pure data)
    - [x] Created JsonTutorialCatalog.cs in ToolsUI/ (MCP/JSON layer: FormatCatalog, FetchTutorial, FetchTutorialImage, ConvertHtmlToMarkdown)
    - [x] Refactored StartPage.PopulateTutorialPanel() to iterate TutorialCatalog (removed ~380 lines of per-tutorial boilerplate)
    - [x] Added GetAvailableTutorials/GetTutorial/GetTutorialImage thin delegates in JsonToolServer.cs
    - [x] Added skyline_get_available_tutorials, skyline_get_tutorial, skyline_get_tutorial_image MCP tools in SkylineTools.cs
    - [x] Added TutorialCatalogTest.cs (resource validation, format check, HTML-to-markdown)
    - [x] Fixed pre-existing .resx typos: PRMOrbitraip→PRMOrbitrap, DDSearch→DDASearch
    - [x] Fixed image resource name mismatches: GroupedStudies→GroupedStudy, PRM→TargetedMSMS
    - [x] Added missing DIA_TTOF text/image resources
    - [x] All 3 TutorialCatalog tests pass, end-to-end MCP tests verified
  - [x] Implement `get_form_image` MCP tool with screen capture and redaction (see Sessions 22-23)
    - [x] Extracted ScreenCapture.cs from TestUtil/ScreenshotManager.cs (DRY refactor)
    - [x] Added ScreenCapturePermissionDlg with session + persistent permission flow
    - [x] Added AllowMcpScreenCapture user setting
    - [x] PInvoke additions: Gdi32.GetDeviceCaps, User32.SetForegroundWindow, EnumWindows
    - [x] Redaction: enumerates non-Skyline windows above target in z-order via EnumWindows
    - [x] ScreenshotManager delegates to ScreenCapture for all shared methods
  - [x] Refactor form IDs from index-based (`graph:0`, `form:1`) to `TypeName:Title` format
  - [x] Add dialog support to `get_open_forms` and `get_form_image` (non-docked visible forms)
  - [x] Screen capture: fix DPI scaling for redaction (foreign window rects now scaled to physical pixels)
  - [x] Screen capture: change redaction color from gray to cyan for visibility
  - [x] Screen capture: add Thread.Sleep after permission dialog dismissal
  - [x] Implement unit tests of at least the Skyline side of the API
    - [x] Created JsonToolServerTest.cs functional test in TestFunctional/
    - [x] Tests 17 tool groups: document info, selection, locations, replicates, settings lists,
      report documentation, named reports, report definitions (filter/sort/pivot), document settings,
      tutorials catalog, CLI help, open forms, add report, small molecule insert, import properties,
      import FASTA, run command
    - [x] Uses FilesTreeFormTest.data (Rat_plasma.sky with 42 replicates) - no new test data needed
  - [ ] Expand test coverage to 80%+ (see Sessions 25-26)
    - [x] Created coverage file: `ai/todos/active/TODO-20260222_skyline_mcp-coverage.txt`
    - [x] Baseline coverage: 64.3% (1103/1716 statements)
    - [x] Added ScreenCapturePermissionDlg tests (deny, allow, allow+persist)
    - [x] Added ScreenCapturePermissionDlg.ResetSessionPermission() for test support
    - [x] Added DoNotAskAgain get/set property on ScreenCapturePermissionDlg
    - [x] Added GetFormImage test (capture, auto-path, error cases)
    - [x] Added graph data/image tests (GetGraphData, GetGraphImage, error cases)
    - [x] Added tutorial fetch tests using HttpClientTestHelper with real repo HTML
    - [x] Added tutorial error tests (404, DNS failure, cancellation, path traversal)
    - [x] Fixed ConvertHtmlToMarkdown bug: `@"\n"` (literal) → `NL` constant (real newline)
    - [x] Added ScreenCapturePermissionDlg to TestRunnerFormLookup.csv
    - [x] Removed CommandArgs.cs, CommandLine.cs, Text.cs from coverage file (large pre-existing files)
    - [x] Coverage after Session 25: 74.2% (1391/1874 core statements)
    - [x] Added GetSelectionText and GetSelectedElementLocator tests
    - [x] Expanded TestRunCommand: --version, report export, refine, FASTA import via CLI
    - [x] Added Immediate Window content verification using resource strings
    - [x] Added `GetImmediateWindowText()` helper for Immediate Window content assertions
    - [x] Added `keepEmptyProteins` parameter to ImportFasta API and SkylineWindow.ImportFasta
    - [x] Fixed TestImportFasta: tests both keepEmptyProteins=true and false paths
    - [x] Coverage after Session 28: 82.1% (1553/1892 statements)
    - [x] Coverage after Session 29: 82.4% (1561/1895 statements)
  - [ ] Update testing-patterns.md documentation (partially done)
  - [ ] Create PR

  ### Future enhancements (post-PR)

  - [ ] FloatingWindow composite capture: individual docked forms in a floating container all
    resolve to the full container rectangle via `GetDockedFormBounds`. Need to either return
    just the pane's bounds or document this as expected behavior.
  - [ ] Multi-form screenshot: Accept a list of form IDs and capture the union bounding box
    with redaction. Useful for capturing a dialog alongside its parent, or multiple related panels.
    The redaction infrastructure already handles non-Skyline content in the gaps.
  - [x] Multiple Skyline instances: per-instance `connection-{pipeName}.json` files
  - [ ] Self-contained publish for MCP server (eliminates .NET 8.0 runtime dependency)
  - [ ] Wire protocol modernization (replace BinaryFormatter in SkylineTool.dll)
  - [ ] RunCommand write operations need IDocumentContainer integration for full ModifyDocument flow
  - [ ] Immediate Window font: ASCII table borders don't align (proportional font)
  - [ ] Tool Store packaging and submission

  ## Session Log

  (Continued from phase 1, session 16)

  ### Session 17 (2026-03-03) - Filtering, sorting, and pivot support

  Added filtering, sorting, and pivot support to JSON report definitions:
  - **Filtering**: ParseFilterSpecs resolves columns against ColumnResolver.ResolveResult.ColumnIndex,
    validates ops via FilterOperations.GetOperation, builds FilterSpec/FilterPredicate. Filters can
    reference any column in the data model, not just selected ones. Part of ViewSpec (persisted).
  - **Sorting**: ParseSortSpecs builds RowFilter.ColumnSort objects applied via BindingListSource.RowFilter
    in ExportJsonDefinitionReport. Sort is query-time only (not part of report definition) because
    Skyline report definitions don't support persisted sort order.
  - **Pivot Replicate**: pivotReplicate=true sets SublistId to Root; false sets to replicate sublist.
  - **Pivot Isotope Label**: Delegates to PivotReplicateAndIsotopeLabelWidget.PivotIsotopeLabel().
  - ColumnResolver.ResolveResult now exposes ColumnIndex for filter column resolution.
  - ColumnResolver.FindSuggestions changed from private to internal for reuse in filter errors.
  - RowFactories.ExportReport gained overloads accepting IList<RowFilter.ColumnSort>.

### Session 18 (2026-03-03) - Tutorial tools design

Design discussion about how the Skyline MCP can help LLMs find and use tutorials.

#### Decision: GitHub raw content, served through MCP, file-based output

- **Source**: GitHub `raw.githubusercontent.com` with git hash from `skyline_get_version`
- **Why not skyline.ms wiki**: Tutorial pages use `<iframe>` + JS content population, fragile to extract
- **Why MCP fetches content**: Users can't be expected to have web fetch tools. Claude Desktop,
  Gemini CLI, Cursor don't guarantee web access. The Skyline MCP must be the gateway.
- **URL pattern**: `https://raw.githubusercontent.com/ProteoWizard/pwiz/{hash}/pwiz_tools/Skyline/Documentation/Tutorials/{name}/{lang}/index.html`
- **File-based output**: Large content written to temp file (like `skyline_get_report`), reducing
  context cost and network roundtrips. LLM reads sections from file with offset/limit as needed.
- **Version pinning**: The git hash in `skyline_get_version` (e.g., `26.1.1.061-6c3244bc0a`)
  ensures tutorial content always matches the user's Skyline version.

#### Prerequisite: Sync StartPage to wiki tutorials page

The wiki tutorials page (skyline.ms/...?name=tutorials) has 28 tutorials in 6 sections.
The StartPage currently has 26 tutorials in 5 sections. Differences:

**Wiki has but StartPage doesn't:**
- **Section**: "Introduction to Full-Scan Acquisition Data" (wiki has this as a separate section)
  - AcquisitionComparison ("Comparing PRM, DIA, and DDA") — entirely missing from StartPage
  - PRMOrbitrap and DIA are in this section on wiki, but in "Full-Scan" section in StartPage
- **Tutorial**: PeakBoundaryImputation-DIA ("Peak Boundary Imputation for DIA") — in wiki's
  Full-Scan section, missing from StartPage

**Tutorials on GitHub but NOT on wiki (stale, not for MCP):**
- ImportingAssayLibraries, ImportingIntegrationBoundaries, PRMOrbitrap-PRBB

**Changes needed:**
1. Add `Section_Intro_Full_Scan` to TutorialTextResources.resx
2. Add AcquisitionComparison entries to all 3 .resx files (Text, Link, Image)
3. Add PeakBoundaryImputation-DIA entries to all 3 .resx files
4. Restructure StartPage.cs `PopulateTutorialPanel()`:
   - Introductory (4): MethodEdit, MethodRefine, GroupedStudy, ExistingQuant
   - Intro Full-Scan (3): AcquisitionComparison, PRMOrbitrap, DIA
   - Full-Scan (7): MS1Filtering, DDASearch, TargetedMSMS, DIA_SWATH, DIA_PASEF, DIA_Umpire_TTOF, PeakBoundaryImputation
   - Small Molecules (5): SmallMolecule, SmallMoleculeMethodDevCEOpt, SmallMoleculeQuantification, HiResMetabolomics, SmallMolLibraries
   - Reports (2): CustomReports, LiveReports
   - Advanced (7): AbsoluteQuant, PeakPicking, iRT, OptimizeCE, IMSFiltering, LibraryExplorer, AuditLog
5. Commit to keeping StartPage and wiki in sync going forward

#### Tool 1: `skyline_get_available_tutorials`

Returns structured catalog from Skyline's .resx resources. No network needed.

**Parameters:** none

**Returns** (tab-separated, like other enumeration tools):
```
Category\tName\tTitle\tDescription\tWikiUrl\tZipUrl
Introductory\tMethodEdit\tTargeted Method Editing\t...\thttps://...\thttps://...
...
```

**Source data** (all in `Controls/Startup/`):
- `TutorialTextResources` — captions, descriptions, section names
- `TutorialLinkResources` — zip URLs, wiki URLs
- `StartPage.PopulateTutorialPanel()` — ordering and section grouping

**Implementation**: New method `GetAvailableTutorials()` in JsonToolServer.cs.
Build catalog from .resx resources. The ordering and section assignment should be
defined in a static data structure (array of tutorial descriptors) rather than
duplicating the StartPage's UI construction code.

#### Tool 2: `skyline_get_tutorial`

Fetches tutorial content from GitHub, converts HTML to markdown, writes to file.

**Parameters:**
- `name` (required) — tutorial folder name (e.g., "MethodEdit")
- `language` (optional, default "en")

**Behavior:**
1. Extract git hash from `Install.Version` (after the `-`)
2. Construct URL: `https://raw.githubusercontent.com/ProteoWizard/pwiz/{hash}/pwiz_tools/Skyline/Documentation/Tutorials/{name}/{lang}/index.html`
3. Fetch HTML via `WebClient` (sync, runs on pipe thread)
4. Convert HTML → markdown (see conversion spec below)
5. Write markdown to temp file
6. Parse headings to build table of contents with line numbers
7. Return: JSON with `file_path`, `title`, `toc` (array of {heading, level, line})

**LLM workflow:**
1. Call `get_available_tutorials` → browse catalog, recommend tutorials
2. Call `get_tutorial("MethodEdit")` → get file path + TOC
3. Use `Read` tool with offset/limit to read specific sections as needed
4. Guide user through steps, answer questions about specific sections

#### HTML-to-markdown conversion spec

Tutorial HTML is well-structured (no dynamic content, JS is presentational only):

| HTML | Markdown |
|------|----------|
| `<h1 class="document-title">` | `# Title` |
| `<h1>` | `# Section` |
| `<h2>` | `## Subsection` |
| `<p>` | paragraph with blank line |
| `<ol>/<li>` | `1. numbered list` |
| `<ul>/<li>` | `- bullet list` |
| `<table>` | markdown table |
| `<img src="s-01.png">` | `[Screenshot: s-01.png]` |
| `<b>/<strong>` | `**bold**` |
| `<i>/<em>` | `*italic*` |
| `<a href="...">text</a>` | `[text](url)` |
| `<style>, <script>` | dropped |
| `<br>` | newline |

Implementation: Regex-based converter in JsonToolServer.cs. The existing `StripHtmlTags()`
helper handles simple cases; extend with a more structured `ConvertHtmlToMarkdown()` method.
No external dependencies needed — tutorial HTML is regular enough for regex.

#### Graceful degradation

If GitHub is unreachable (no internet, corporate firewall):
- Return error with wiki URL and zip URL as fallbacks
- LLM can direct user to those URLs for manual access

#### Future potential (post-PR)

- **Lesson plans**: LLM creates structured learning paths from tutorial catalog based on
  user's experience level and goals (professor use case)
- **Section-level Q&A**: User asks about a concept, LLM finds relevant tutorial section
- **Tutorial-guided workflows**: LLM reads tutorial steps and helps execute them in Skyline
  using other MCP tools (e.g., "set up like step 3 of the Method Editing tutorial")
- **Localized tutorials**: `language` parameter already supports ja, zh-CHS

### Session 19 (2026-03-03) - Tutorial tools implementation

Implemented `get_available_tutorials` and `get_tutorial` MCP tools with a shared
`TutorialCatalog` class as the single authoritative tutorial definition.

#### Architecture: TutorialCatalog as single source of truth

Brendan pointed out the initial approach duplicated the tutorial list across StartPage.cs
and JsonToolServer.cs. Refactored to a shared `TutorialCatalog` class in Controls/Startup/:

- **`TutorialCatalog.cs`** — Master tutorial list (28 tutorials, 6 sections), shared helpers:
  - `TutorialInfo` struct: Section (resource key), ResourcePrefix, FolderName
  - `TutorialInfo` properties: Caption, Description, ZipUrl, WikiUrl, SkyFileInZip, Icon
    (all via ResourceManager lookups from .resx files)
  - `SectionOrder` array defining section display order
  - `GetSectionDisplayName()` — localized section name (with `Assume.IsNotNull` validation)
  - `GetSectionDisplayNameInvariant()` — English section name for LLM consumers
  - `FormatCatalog()` — tab-separated catalog using invariant strings (for MCP)
  - `FetchTutorial(name, language)` — GitHub fetch + HTML-to-markdown + file output
  - `ConvertHtmlToMarkdown(html)` — regex-based converter for tutorial HTML

- **StartPage.cs** — Refactored `PopulateTutorialPanel()` from ~380 lines of per-tutorial
  boilerplate down to ~50 lines iterating `TutorialCatalog.Tutorials`. Section ordering
  (proteomic vs small molecule mode) preserved via dictionary of section controls.

- **JsonToolServer.cs** — Thin 2-line delegates: `GetAvailableTutorials()` and
  `GetTutorial(name, language)` both call into TutorialCatalog.

- **SkylineTools.cs** — MCP tool definitions with descriptions, parameter docs, and
  friendly formatting of the GetTutorial JSON result (shows TOC with line numbers).

#### Localization considerations

- Section constants use .resx resource keys (e.g., `Section_Introductory`), not display text
- `GetSectionDisplayName()` returns localized name (for StartPage UI)
- `GetSectionDisplayNameInvariant()` returns English name (for MCP/LLM output)
- `FormatCatalog()` uses invariant culture for all lookups — LLMs work best in English
- Missing resource keys fail with `Assume.IsNotNull` rather than silent fallback

#### Test coverage

- `TutorialCatalogTest.cs` validates all resource entries exist for every tutorial:
  captions, descriptions, zip/pdf URLs, start icons, section membership, no duplicates
- `TestTutorialCatalogFormat()` validates FormatCatalog produces correct tab-separated structure
- `TestConvertHtmlToMarkdown()` validates HTML-to-markdown conversion for key patterns

#### New/modified files
- **New**: `Controls/Startup/TutorialCatalog.cs`, `Test/TutorialCatalogTest.cs`
- **Modified**: `StartPage.cs` (major refactor), `JsonToolServer.cs` (+11 lines),
  `SkylineTools.cs` (+64 lines), `Skyline.csproj`, `Test.csproj`

### Session 20 (2026-03-04) - Tutorial resource fixes, image tool, end-to-end testing

#### .resx resource fixes (pre-existing bugs found by TutorialCatalogTest)

Fixed 3 typos and 5 missing resources that prevented the test from passing:

- **Typos**: `PRMOrbitraip_Description` → `PRMOrbitrap_Description` (all 3 locales + Designer),
  `DDSearch_Description` → `DDASearch_Description` (all 3 locales + Designer),
  `DDSearch_pdf` → `DDASearch_pdf` (link resources + Designer)
- **Image name mismatches**: Renamed `GroupedStudies_start` → `GroupedStudy_start`,
  `PRM_start` → `TargetedMSMS_start` (to match ResourcePrefix convention)
- **Missing resources**: Added `DIA_TTOF_Caption`, `DIA_TTOF_Description`, `DIA_TTOF_start`

#### Tutorial image tool (`skyline_get_tutorial_image`)

Added third tutorial MCP tool for downloading screenshot images referenced in tutorial
markdown (e.g., `[Screenshot: s-01.png]`). Uses same GitHub raw URL pattern as get_tutorial.

- `TutorialCatalog.FetchTutorialImage()` — validates filename (path traversal prevention),
  downloads image to temp or caller-specified path
- Images stored in `{tmpDir}/images/{tutorial}/{lang}/` subdirectory structure
- All 3 tutorial tools accept optional `filePath` parameter (matching report/settings pattern)

#### WebClient → HttpClientWithProgress migration

Replaced deprecated `WebClient` with `HttpClientWithProgress` (co-authored by Claude) in both
FetchTutorial and FetchTutorialImage. Better error reporting for network failures.

#### End-to-end testing

All 3 MCP tools verified working against running Skyline:
- `get_available_tutorials` — 28 tutorials, 6 sections, correct captions/descriptions/URLs
- `get_tutorial("DIA-TTOF")` — fetched HTML, converted to 833-line markdown, TOC extracted
- `get_tutorial_image("DIA-TTOF", "s-01.png")` — downloaded screenshot, viewable by Claude
- Custom `filePath` tested: `ai/.tmp/s-01.png` saves to approved location (no manual approval needed)

#### TutorialCatalog → JsonTutorialCatalog refactoring

Separated MCP/JSON concerns from pure catalog data:
- **`Controls/Startup/TutorialCatalog.cs`** — Pure data only: TutorialInfo struct, Tutorials[],
  SectionOrder[], section constants, GetSectionDisplayName/Invariant, FindTutorial. No JSON, HTTP,
  or temp file code. Consumed by StartPage UI.
- **`ToolsUI/JsonTutorialCatalog.cs`** (NEW) — MCP serialization layer: FormatCatalog,
  FetchTutorial, FetchTutorialImage, ConvertHtmlToMarkdown, GitHub URL construction, temp file
  management. Wraps TutorialCatalog. Consumed by JsonToolServer.
- Updated JsonToolServer.cs to call JsonTutorialCatalog (removed Controls.Startup import)
- Updated TutorialCatalogTest.cs to reference JsonTutorialCatalog for format/markdown tests

#### New/modified files
- **New**: `TutorialCatalog.cs`, `JsonTutorialCatalog.cs`, `TutorialCatalogTest.cs`
- **Modified**: `StartPage.cs` (major refactor), `JsonToolServer.cs` (+delegates),
  `SkylineTools.cs` (+3 MCP tools), `Skyline.csproj`, `Test.csproj`,
  9 .resx/.Designer.cs files (typo fixes + missing resources)

### Session 21 (2026-03-04) - Graph MCP tools and JsonUiService extraction

Implemented three new graph-related MCP tools and extracted a JsonUiService static class
from JsonToolServer to separate UI interaction concerns.

#### JsonUiService.cs (NEW)

Extracted UI interaction code into a dedicated static service class, following the same
pattern as JsonTutorialCatalog. Three abstraction levels:

1. **Primitives**: `InvokeOnUiThread(Action)` and `InvokeOnUiThread(Func<string>)` — UI
   thread marshaling with error capture
2. **UI patterns**: `CreateImmediateWindowTee()` — tees output to capture writer + Immediate
   Window. `TeeTextWriter` private class moved here from JsonToolServer.
3. **Complete operations**: `GetSelection`, `SetSelection`, `SetReplicate`, `GetOpenForms`,
   `GetGraphData`, `GetGraphImage`

Shared infrastructure consolidated from duplicate code in JsonTutorialCatalog:
- `GetMcpTmpDir()` — respects `SKYLINE_MCP_TMP_DIR` env var, public static
- `GetMcpTmpFilePath(prefix, title, extension)` — timestamped file path generation
- JsonTutorialCatalog updated to use `JsonUiService.GetMcpTmpDir()` (removed duplicate)
- `ToForwardSlashPath()` extension method used consistently (replaced manual `Replace('\\', '/')`)

#### Graph MCP tools

- **`skyline_get_open_forms`**: Enumerates all visible docked forms via `DockPanel.Contents`.
  Reports form type, title, ZedGraph presence, dock state, and stable identifier.
- **`skyline_get_graph_data`**: Extracts tab-separated data via
  `CopyGraphDataToolStripMenuItem.GetGraphData(MasterPane)`. Saves to file (TSV) for
  ggplot2/matplotlib publication-quality plot workflow.
- **`skyline_get_graph_image`**: Renders PNG via `MasterPane.GetImage()`. Uses `FileSaver`
  for atomic writes.

Form-specific `ZedGraphControl` access via `TryGetZedGraphControl()` switch:
GraphSummary.GraphControl, GraphChromatogram.GraphControl, GraphSpectrum.ZedGraphControl,
GraphFullScan.ZedGraphControl, CalibrationForm.ZedGraphControl.

#### Style cleanup

Fixed 14 braceless multi-line `if` bodies across JsonUiService.cs (2) and
JsonToolServer.cs (12). Updated ai/STYLEGUIDE.md to document the rule: braceless `if`
is only allowed when the body is a single line.

#### DRY improvements

- Replaced tab character literals with `TextUtil.SEPARATOR_TSV` in JsonTutorialCatalog
- Added `EXT_PNG` and `GRAPH_FILE_PREFIX` constants
- Used `TextUtil.EXT_TSV` for graph data file extension

#### New/modified files
- **New**: `ToolsUI/JsonUiService.cs` (~380 lines)
- **Modified**: `ToolsUI/JsonToolServer.cs` (extracted UI code to thin wrappers, braces cleanup),
  `ToolsUI/JsonTutorialCatalog.cs` (shared tmp dir, ToForwardSlashPath, TSV separator),
  `SkylineMcpServer/Tools/SkylineTools.cs` (+3 MCP tools),
  `Skyline.csproj` (+JsonUiService.cs), `ai/STYLEGUIDE.md` (braceless if rule)

### Session 22 (2026-03-04) - Form ID refactor, dialog support, screen capture fixes

Refactored form identifiers from fragile index-based (`graph:0`, `form:1`, `dialog:2`)
to stable `TypeName:Title` format (e.g., `GraphSummary:Peak Areas - Replicate Comparison`,
`PeptideSettingsUI:Peptide Settings`). Added dialog visibility and fixed screen capture bugs.

#### Form ID refactor (JsonUiService.cs)

- Added `GetFormTitle(Form)` — returns display title using Text, TabText, or type name fallback
- Added `GetFormId(Form)` — returns `TypeName:Title` format
- Replaced `FindGraphForm(string)` and `FindForm(string)` with unified `FindFormById(string)`
  that parses `TypeName:Title`, searches docked forms then non-docked dialogs
- `GetGraphData`/`GetGraphImage` now cast `FindFormById` result to `DockableFormEx` with
  null check for graph validation (cleaner error: "Not a graph form")
- `GetFormImage` uses `GetFormTitle(form)` for file path instead of `form.Text ?? form.TabText`
- Added `using System.Windows.Forms` (needed for explicit `Form` type references)

#### Dialog support

- `GetOpenForms` dialog loop now uses `GetFormId()` instead of `dialog:N` indexing
- `FindFormById` searches both docked forms and `FormUtil.OpenForms` dialogs
- Dialogs shown with DockState=Dialog (e.g., `PeptideSettingsUI:Peptide Settings`,
  `EditEnzymeDlg:Edit Enzyme`, `EditListDlg`2:Edit Enzymes`)
- `FloatingWindow` containers also appear — kept for now, future work to handle composites

#### Screen capture: DPI scaling fix

- **Bug**: `GetWindowRectangle` scales capture rect to physical pixels, but `GetWindowRect`
  (Win32 API) returns logical coordinates. At 125% scaling, foreign window rects were
  misaligned, causing redaction in wrong positions.
- **Fix**: Added `var scalingFactor = GetScalingFactor()` in `GetForeignWindowRects`, applied
  `rect.Rectangle * scalingFactor` to each foreign window rect before intersection.

#### Screen capture: redaction color

- Changed from `Color.FromArgb(0xF0, 0xF0, 0xF0)` (near-white gray) to `Color.Cyan`
- Gray was indistinguishable from dialog background, making redaction invisible
- Cyan makes redaction obvious and unmistakable

#### Screen capture: permission dialog delay

- Added `out bool wasFirstPrompt` to `EnsurePermission()` to report whether dialog was shown
- Added `Thread.Sleep(1000)` after `ActivateForm` when permission dialog was just dismissed
- Prevents the permission dialog from appearing in the first screenshot of a session

#### MCP tool descriptions (SkylineTools.cs)

- Updated all four tool descriptions with `TypeName:Title` format examples
- `skyline_get_open_forms`: mentions Dialog dock state
- `skyline_get_graph_data`/`get_graph_image`: example `'GraphSummary:Peak Areas - ...'`
- `skyline_get_form_image`: examples `'SequenceTreeForm:Targets'`, `'PeptideSettingsUI:...'`

#### Observations for future work

- **FloatingWindow composites**: When multiple graphs are docked into a single floating
  container, each `GraphSummary` resolves to the full container rect via `GetDockedFormBounds`
  (because `Pane.Parent` is the container). The `FloatingWindow` entry captures the same rect.
  Need to either return individual pane bounds or accept this as container-level capture.
- **Multi-form screenshots**: A list of form IDs with union bounding box + redaction would
  cleanly solve the composite case and enable parent+dialog captures.

#### Modified files
- **`ToolsUI/JsonUiService.cs`**: Form ID refactor, dialog support, permission delay
- **`Util/ScreenCapture.cs`**: DPI scaling fix, cyan redaction, EnsurePermission out param
- **`SkylineMcpServer/Tools/SkylineTools.cs`**: Updated descriptions and examples

### Session 23 (2026-03-04) - Screen capture implementation (initial session)

Implemented the `get_form_image` MCP tool with screen capture and non-Skyline window
redaction. This session created the initial implementation; Session 22 (a parallel session)
then refined the form ID format and fixed DPI/color issues.

#### New files
- **`Util/ScreenCapture.cs`** — Production capture class extracted from ScreenshotManager:
  PointFactor, PointAdditive, GetWindowRectangle, GetDockedFormBounds, GetFramedWindowBounds,
  FindParent, GetScalingFactor, CaptureScreen, CaptureAndRedact, ActivateForm, SaveToFile,
  EnsurePermission (session + persistent permission flow)
- **`Alerts/ScreenCapturePermissionDlg.cs/.Designer.cs`** — Permission dialog with
  Allow/Deny buttons, "Do not ask me again" checkbox, strings in AlertsResources.resx

#### PInvoke additions
- **Gdi32.cs**: Added `DeviceCap` enum and `GetDeviceCaps` (replaces test-only `Gdi32Test`)
- **User32.cs**: Added `SetForegroundWindow`, `EnumWindows`/`EnumWindowsProc`

#### Redaction approach (evolved during session)
1. **v1**: Excluded Skyline form rects from capture rect — no-op for form screenshots
   (the capture IS a Skyline form, so nothing gets redacted)
2. **v2**: Enumerated all non-Skyline windows via `EnumWindows` — over-redacted because
   maximized background windows still report as "visible"
3. **v3 (final)**: Walk windows in z-order (EnumWindows returns top-to-bottom), stop at
   target Skyline window via `FormUtil.FindTopLevelOwner`. Only foreign windows ABOVE
   target in z-order are redacted. Diagnostic `.log` file written alongside `.png`.

#### ScreenshotManager refactor (DRY)
- Replaced duplicated implementations with delegates to ScreenCapture
- PointFactor/PointAdditive subclass ScreenCapture versions for backward compat
- ActiveWindowShot/RectangleShot use ScreenCapture.GetWindowRectangle/GetScalingFactor
- SaveToFile delegates to ScreenCapture.SaveToFile
- Removed `using TestRunnerLib.PInvoke` for Gdi32Test (now uses production Gdi32)
- Kept `using TestRunnerLib.PInvoke` for SetForegroundWindow/HideCaret extension methods

#### Settings and resources
- Added `AllowMcpScreenCapture` bool setting (user-scoped, default false)
- Added 5 AlertsResources strings for permission dialog

#### Modified files
- **`Shared/CommonUtil/SystemUtil/PInvoke/Gdi32.cs`**: +DeviceCap, +GetDeviceCaps
- **`Shared/CommonUtil/SystemUtil/PInvoke/User32.cs`**: +SetForegroundWindow, +EnumWindows
- **`Alerts/AlertsResources.resx/.Designer.cs`**: +5 ScreenCapturePermissionDlg strings
- **`Properties/Settings.settings/.Designer.cs`**: +AllowMcpScreenCapture
- **`ToolsUI/JsonUiService.cs`**: +GetFormImage, +FindForm (later refactored in Session 22)
- **`ToolsUI/JsonToolServer.cs`**: +GetFormImage thin wrapper
- **`SkylineMcpServer/Tools/SkylineTools.cs`**: +skyline_get_form_image MCP tool
- **`TestUtil/ScreenshotManager.cs`**: Delegates to ScreenCapture, removed duplication
- **`Skyline.csproj`**: +ScreenCapture.cs, +ScreenCapturePermissionDlg.cs/.Designer.cs

### Session 24 (2026-03-04) - JsonToolServer functional test

Created comprehensive functional test for JsonToolServer handler methods, calling them
directly without the named pipe transport layer.

#### Test architecture
- Constructs `ToolService` + `JsonToolServer` in the test, calls handler methods directly
- Uses `FilesTreeFormTest.data/Rat_plasma.sky` (42 replicates, proteins, peptides, results)
- Single `[TestMethod]` with 17 private helper methods (Skyline test convention)

#### Tools tested (17 groups)
- **Document info**: GetDocumentPath, GetVersion, GetDocumentStatus, GetProcessId
- **Selection**: GetSelection, SetSelectedElement (with locator navigation)
- **Locations**: GetLocations at group/molecule/precursor/transition levels, scoped enumeration
- **Replicates**: GetReplicateName, GetReplicateNames, SetReplicate (+ error case)
- **Settings lists**: GetSettingsListTypes, GetSettingsListNames, GetSettingsListItem (using EnzymeList.GetDefault())
- **Report documentation**: GetReportDocTopics, GetReportDocTopic (+ case-insensitive matching)
- **Named reports**: ExportReport with JSON metadata validation
- **Report definitions**: ExportReportFromDefinition with filter (PrecursorMz > 500 verified per-row), sort (descending order verified), pivotReplicate (column expansion verified), error suggestions
- **Document/default settings**: GetDocumentSettings, GetDefaultSettings (XML comparison)
- **Tutorials**: GetAvailableTutorials (catalog format, field count)
- **CLI help**: RunCommandSilent
- **Open forms**: GetOpenForms (SequenceTreeForm presence)
- **Add report**: AddReportFromDefinition (persisted to PersistedViews)
- **Small molecule insert**: InsertSmallMoleculeTransitionList (group count increase)
- **Import properties**: ImportProperties with annotation definition + ElementLocator CSV
- **Run command**: RunCommand with report export (file creation verified)

#### Code quality patterns applied
- Constants for repeated strings: LEVEL_GROUP, COL_PROTEIN_NAME, CULTURE_INVARIANT, etc.
- `nameof(EnzymeList)` instead of string literals for settings list types
- `BuildSelectJson()` / `BuildSelectPivotJson()` helpers for JSON report definitions
- `GetRowCount()` helper for metadata parsing
- `Helpers.CountLinesInString()`, `TextUtil.ReadLines()`, `.ParseDsvFields()` instead of manual splits
- `EnzymeList.GetDefault()` for invariant enzyme assertions
- Exact row count assertions instead of `> 0`

#### ImportFasta test (commented out)
ImportFasta requires the SequenceTree insert node to be selected and has UI thread
complications when called through the ToolService path. Needs further investigation.

#### New/modified files
- **New**: `TestFunctional/JsonToolServerTest.cs` (~525 lines)
- **Modified**: `TestFunctional/TestFunctional.csproj` (+1 Compile Include)

### Session 25 (2026-03-05) - Code coverage and test expansion

Goal: establish coverage baseline, expand tests toward 80%, fix bugs found by tests.

#### Coverage infrastructure
- Created `ai/todos/active/TODO-20260222_skyline_mcp-coverage.txt` listing 11 production
  files to measure coverage for
- Baseline coverage: **64.3%** (1103/1716 statements) across core MCP files

#### ScreenCapturePermissionDlg tests
- Added `DoNotAskAgain` get/set property (was get-only expression body)
- Added `ScreenCapture.ResetSessionPermission()` to reset static session state for tests
- Added `ScreenCapturePermissionDlg` to `TestRunnerFormLookup.csv`
- Tests three flows: deny (CancelDialog), allow (OkDialog), allow+DoNotAskAgain (persist)
- Tests session permission caching (no dialog on subsequent calls after allow)

#### GetFormImage tests
- Pre-grants `AllowMcpScreenCapture` to test capture without dialog
- Verifies file creation, non-zero size, valid image dimensions
- Tests auto-generated path (null filePath parameter)
- Tests error case: invalid form ID

#### Graph data/image tests
- Finds GraphSummary from GetOpenForms (Rat_plasma.sky opens with graphs)
- Tests GetGraphData: TSV export, file creation, auto-generated path
- Tests GetGraphImage: PNG export, valid image verification
- Tests error cases: invalid graph ID, non-graph form ID

#### Tutorial fetch tests (HttpClientTestHelper, no network)
- Reads real tutorial HTML from `Documentation/Tutorials/MethodEdit/en/index.html`
- Serves via `HttpClientTestHelper.SimulateSuccessfulDownload()` — exercises full
  FetchTutorial pipeline without network access
- Verifies JSON metadata (tutorial name, language, TOC entries, line count)
- Verifies markdown output (headings, screenshot placeholders)
- Tests FetchTutorialImage with real PNG from repo served via HttpClientTestHelper
- Error tests: unknown tutorial (ArgumentException), HTTP 404 (IOException),
  network failure (IOException), user cancellation (IOException),
  path traversal prevention (ArgumentException for `../` and `\` in filenames)

#### Bug fix: ConvertHtmlToMarkdown literal `\n`
- **Bug**: All regex replacements used `@"\n"` (verbatim string = literal backslash + n)
  instead of actual newline characters. Headings, list items, paragraphs, and table rows
  all got literal `\n` instead of real newlines.
- **Impact**: TOC extraction found zero headings because no lines started with `# `.
  The end-to-end MCP test coincidentally worked because the original HTML already has
  real newlines between tags, making the literal `\n` invisible noise.
- **Fix**: Added `private const string NL = "\n"` constant, replaced all `@"\n"`
  replacement strings with `NL` throughout `ConvertHtmlToMarkdown`.

#### Documentation updates
- Updated `ai/docs/testing-patterns.md` with three new subsections:
  - "Exposing Dialog Controls for Testing" — `#region Test support` convention,
    public get/set properties wrapping private controls
  - "Resetting Static State for Tests" — pattern for session-level state reset methods
  - "Testing Accept and Cancel Paths" — `ShowDialog<T>()` + `CancelDialog()`/`OkDialog()`
    pattern for testing both accept and deny flows
- Updated method listing to include `CancelDialog(Form)` alongside `OkDialog(Form)`

### Session 26 (2026-03-05): Test expansion, ImportFasta API, Immediate Window verification

#### Test cleanup and coverage baseline
- Fixed null file path cleanup: auto-generated paths wrapped in try/finally with `FileEx.SafeDelete()`
- Added null guards to prevent `FileEx.SafeDelete(null)` crash
- Error cases now pass `TestFilesDir.GetTestPath()` paths instead of null
- Removed CommandArgs.cs, CommandLine.cs, Text.cs from coverage file (large pre-existing,
  not worth including — they dragged coverage from 74.7% down to 31.6%)
- Confirmed core coverage baseline: **74.2%** (1391/1874 statements)

#### New test coverage
- **GetSelectionText**: Tests human-readable location name from selection
- **GetSelectedElementLocator**: Tests getting locator for selected element by type ("Molecule")
- **TestRunCommand expanded** with 4 operations:
  - `--version` via RunCommandSilent: verifies both parts of version string match GetVersion()
  - Report export via RunCommand: verifies file creation and Immediate Window output
  - Refine (`--refine-min-peptides=100`): verifies document modification, Undo with `Assert.AreSame`
  - FASTA import (`--import-fasta` + `--keep-empty-proteins`): verifies ALBU_BOVIN protein
    added by name, Undo with `Assert.AreSame`
- **Immediate Window verification**: All RunCommand calls verify IW content using localized
  resource strings (SkylineResources/Resources) — translation-proof assertions
- **GetImmediateWindowText() helper**: Reads `SkylineWindow.ImmediateWindow.TextContent`
  on UI thread (reads the actual textbox, not the TextBoxStreamWriterHelper.Text property)

#### ImportFasta API enhancement
- **Problem**: `ImportFasta` via SkylineWindow.ImportFasta() shows `EmptyProteinsDlg` when
  imported proteins have no peptides matching document filter criteria — blocks LLM usage
- **Solution**: Added `bool? keepEmptyProteins = null` optional parameter to
  `SkylineWindow.ImportFasta()` in SkylineFiles.cs
  - When specified: bypasses `HandleEmptyPeptideGroups` dialog, directly keeps or removes
    empty proteins using `ImportPeptideSearch.RemoveProteinsByPeptideCount()`
  - When null: preserves existing behavior (shows dialog)
  - Preserves LongWaitDlg progress UI for large FASTA imports
- Added `keepEmptyProteins` string parameter to `JsonToolServer.ImportFasta()` (optional,
  parsed to bool via dispatch)
- **TestImportFasta re-enabled**: Tests both keepEmptyProteins=true (protein present) and
  keepEmptyProteins=false (empty protein removed), with `Assert.AreSame` after Undo

#### Key decisions
- **Coverage file trimmed**: CommandArgs (2532 stmts), CommandLine (3366 stmts), Text (467 stmts)
  are pre-existing files with minimal branch changes — not worth measuring
- **Immediate Window assertions use resource strings**: `SkylineResources.CommandLine_ExportLiveReport_*`,
  `Resources.CommandLine_RefineDocument_*`, `Resources.CommandLine_ImportFasta_*` — won't break
  on zh-CHS/ja test runs
- **ImportFasta uses SkylineWindow path, not RunCommand**: Preserves LongWaitDlg progress UI
  instead of using silent command-line path (which loses progress and requires temp file)

#### Build status
- Build and tests passing after all changes

#### Coverage results (end of session 26)
- **76.6%** (1449/1892 statements)
- JsonToolServer: 70.3%, JsonUiService: 87.1%, JsonTutorialCatalog: 88.4%
- ColumnResolver: 92.8%, RowFactories: 73.3%, ScreenCapture: 55.1%

### Session 27 (2026-03-05): Selection API expansion, insertion node support

#### Selection API improvements
- **Insertion node support**: Added `INSERT_NODE_LOCATOR` (`"/Insert"`) constant to
  `JsonUiService` for representing the SequenceTree insertion point
- `GetSelection()` now outputs `"/Insert"` when the insertion node is selected
- `SetSelection()` now handles `"/Insert"` as primary or additional locator
- This enables LLMs to select the insertion point before operations like ImportFasta

#### TestSelection expanded
- **Multi-selection**: Tests selecting 3 molecules simultaneously via `SetSelectedElement`
  with `additionalLocators` parameter, verifies `GetSelection()` returns all 3
- **Insertion node round-trip**: `SetSelectedElement("/Insert")` → `GetSelection()`
  returns `"/Insert"`, proving API can represent the insertion point

#### TestImportFasta updated
- Uses `server.SetSelectedElement(JsonUiService.INSERT_NODE_LOCATOR)` before importing
  to ensure FASTA appends at end (matching `--import-fasta` command-line behavior)
- Removed previous `insertPath` approach from SkylineFiles.cs — selection is the correct
  way to control insertion position, and now the API supports it

#### Reverted from session 26
- Removed `IdentityPath insertPath` parameter from `SkylineWindow.ImportFasta()` —
  not needed now that SetSelection supports the insertion node
- Removed `Controls` using from `JsonToolServer.cs` — no longer needed

#### Coverage: 76.6% (1449/1892)
- Need ~65 more covered statements to reach 80%
- Easy wins identified: `GetPersistedViewNames` (17), `GetPersistedViewItem` (7),
  `SerializeViewSpec` (10), `Dispatch` (19), `HandleRequest` (15), `ParseArgs` (13)
- Hard/infra: `ServerLoop` (32), `Start` (4), pipe I/O — require real pipe connection

#### Modified files
- **Modified**: `TestFunctional/JsonToolServerTest.cs` (expanded TestSelection, TestImportFasta)
- **Modified**: `ToolsUI/JsonUiService.cs` (INSERT_NODE_LOCATOR, GetSelection/SetSelection)
- **Modified**: `SkylineFiles.cs` (keepEmptyProteins only, reverted insertPath)
- **Modified**: `ToolsUI/JsonToolServer.cs` (reverted insertPath changes)

### Session 28 (2026-03-05): Coverage push to 82.1%, dispatch testing, race condition fix

#### Coverage target achieved: 82.1% (1553/1892)
- Started at 76.6%, needed ~65 more statements for 80%
- Added tests in 3 areas to reach 82.1%

#### TestDispatch — HandleRequest/Dispatch path testing
- Made `HandleRequest` public for testing (was private)
- Tests simulate MCP server JSON requests over the named pipe protocol
- Exercises: `HandleRequest` (15 stmts), `ParseArgs` (13), `Dispatch` (19),
  `SerializeResult` (4), plus error handling paths
- Cases: successful 0-arg call, 1-arg call, `QueryAvailableMethods`,
  unknown method error, too few args error, malformed JSON, null args array

#### PersistedViews coverage
- Added `GetSettingsListNames("PersistedViews")` — exercises `GetPersistedViewNames` (17 stmts)
- Added `GetSettingsListItem("PersistedViews", ...)` — exercises `GetPersistedViewItem` (7)
  + `SerializeViewSpec` (10)
- Added error case for nonexistent persisted view

#### Report definition filter/sort coverage
- Sort ascending ("asc" path in `ParseSortDirection`)
- Unary filter ("isnotnullorblank" path in `ParseFilterSpecs`)
- Invalid JSON error (`ParseJsonDefinition` catch path)
- Unknown filter column, unknown filter op, missing value for binary op,
  invalid sort direction error paths

#### Race condition fix: ProteinMetadataManager
- `AssertEx.DocumentCloned` was failing intermittently because
  `ProteinMetadataManager` resolves protein metadata on a background thread
- After FASTA import, one document could have `accession`/`preferred_name`/
  `websearch_status` attributes while the other didn't yet
- Fix: `WaitForProteinMetadataBackgroundLoaderCompletedUI()` after both
  `ImportFasta` and `RunCommand("--import-fasta")` calls
- Confirmed stable across 6+ passes in all 5 languages (en, zh, fr, ja, tr)

#### Remaining uncovered (acceptable)
- Pipe infrastructure: `ServerLoop` (32), `Start` (4), `ReadAllBytes` (12),
  connection file I/O (24) — require real named pipe
- `ScreenCapture` (79) — offscreen test limitations
- `RowFactories` (36) — report export overloads not on critical path
- `JsonUiService` (41) — UI operations not exercised by current test document

### Session 29 (2026-03-05): Resilient MCP server, multi-instance support

Goal: MCP server survives Skyline restarts without requiring Claude Code restart.

#### Resilient connection architecture
- `SkylineConnection.Connect()` (threw exceptions) replaced with `TryConnect()` returning
  `(connection, error)` tuple — returns helpful message when not connected instead of throwing
- `SkylineTools.Invoke()` changed from `Func<string>` to `Func<SkylineConnection, string>` —
  connection established per-call and disposed after each call
- Broken pipe (`IOException`) caught specially with reconnect-friendly message
- `GetConnectionStatus()` added for lightweight status checks

#### Per-instance connection files
- Single `connection.json` replaced with `connection-{pipeName}.json` per Skyline instance
- `FindConnectionFiles()` scans `connection-*.json` + legacy `connection.json`
- Sorts by `connected_at` descending to prefer most recent instance
- `CleanupStaleFiles()` removes connection files for dead Skyline processes
- `IsProcessAlive()` validates process IDs before attempting pipe connection

#### Connector as gatekeeper (design correction)
- Moved connection file writing from `JsonToolServer.Start()` to the Connector —
  only explicit user action (Tools > AI Connector) advertises Skyline to MCP clients
- Previously any `$(SkylineConnection)` tool (XLTCalc, LipidCreator, etc.) would
  trigger connection file creation via `StartToolService()`
- JSON pipe name derived from legacy ToolService GUID: `"SkylineMcpJson-" + guid.Replace("-", "")`
  — both sides use same convention, no IToolService changes needed
- `JsonToolServer.Dispose()` still deletes connection file (safety net on Skyline exit)
- Connector `ConnectionInfo.Save()` writes the file; `Delete()` can remove it

#### Live document path in Connector
- Connector queries `GetDocumentPath` via legacy `RemoteClient` on timer tick (every 2s)
- Shows live document path instead of static value from connection file
- Label says "Document: path" or "Document: (unsaved)", updates as user opens files

#### UI and metadata improvements
- Menu title changed: "Connect to AI" to "AI Connector" (consistent with title bar)
- Version label changed: "Version: {0}" to "Skyline Version: {0}" (unambiguous)
- `info.properties` description expanded with full feature list
- `GetDocumentStatus` labels now mode-dependent: proteomic shows "Proteins/Lists" + "Peptides",
  small_molecules shows "Lists" + "Molecules", mixed shows "Proteins/Lists" + "Peptides/Molecules"

#### Manual integration testing (verified end-to-end)
- Start Skyline + AI Connector → MCP tools work
- Close Connector → MCP tools still work (connection file persists)
- Close Skyline → "No Skyline instance is connected" message (no crash)
- Reopen Skyline + AI Connector → MCP tools reconnect without restarting Claude Code
- Two Skyline instances → two connection files, MCP connects to most recent
- Close one instance → stale file cleaned up, MCP falls through to remaining instance

#### Coverage: 82.4% (1561/1895)
- Slight increase from 82.1% due to new `GetDocumentStatus` mode-labeling code

#### Modified files
- **Modified**: `ToolsUI/JsonToolServer.cs` (derived pipe name, removed WriteConnectionInfo)
- **Modified**: `Program.cs` (pass legacyToolServiceName to JsonToolServer)
- **Modified**: `TestFunctional/JsonToolServerTest.cs` (updated constructor call)
- **Modified**: `SkylineMcpServer/SkylineConnection.cs` (complete rewrite: TryConnect, multi-instance)
- **Modified**: `SkylineMcpServer/Tools/SkylineTools.cs` (Invoke takes connection, IOException handling)
- **Modified**: `SkylineMcpConnector/ConnectionInfo.cs` (Save, Delete, Create, Load multi-instance)
- **Modified**: `SkylineMcpConnector/MainForm.cs` (writes connection file, live doc path, RemoteClient)
- **Modified**: `SkylineMcpConnector/MainForm.Designer.cs` (Skyline Version label)
- **Modified**: `SkylineMcpConnector/tool-inf/SkylineMcpConnector.properties` (AI Connector title)
- **Modified**: `SkylineMcpConnector/tool-inf/info.properties` (expanded description)
