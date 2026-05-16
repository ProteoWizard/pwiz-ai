# Add get_report_rows / get_report_from_definition_rows MCP tools for inline validation

## Branch Information
- **Branch**: `Skyline/work/20260516_report_rows_mcp`
- **Base**: `master`
- **Created**: 2026-05-16
- **Status**: In Progress
- **GitHub Issue**: [#4218](https://github.com/ProteoWizard/pwiz/issues/4218)
- **PR**: [#4219](https://github.com/ProteoWizard/pwiz/pull/4219)

## Objective

Add two MCP tools that return report rows directly to the model with a bounded
token cap, complementing the existing `get_report` and `get_report_from_definition`
tools (which write to file). This closes the LLM validation loop on a Skyline
document: the model can verify the effect of an edit without a file round-trip.

The reports surface is the most flexible MCP validation mechanism, but the
existing tools always write to file -- correct for huge results (50K transitions
x 100 replicates), wasteful for small validation reads (10 peptides x 5 columns)
that need a two-call round-trip every time. A windowed inline variant fits the
small case cleanly while the file tools remain right for batch / export / R /
Python use.

Server-side token cap is mandatory: Claude has been observed blowing context
against other MCP servers when an underlying query returned long-text columns,
so a misjudged window must not be able to blow context.

## Tasks

### Tool surface
- [ ] `get_report_rows(report_name, offset=0, count, columns?, filter?, include_max_length=false)`
- [ ] `get_report_from_definition_rows(definition, offset=0, count, include_max_length=false)`
  - Does NOT accept `columns` / `filter` -- those go in the definition.
- [ ] `count` is required (no default) on both -- a default silently truncates or silently degrades data calls to schema calls.
- [ ] `count = 0` returns shape only (total_rows, columns + types, empty rows). Document the idiom in the tool description.

### Response shape
- [ ] Fields: `report`, `total_rows`, `columns` (name/type/optional max_observed_length/max_length_sampled), `rows`, `window` (offset/count/truncated), `truncated_at`.
- [ ] Symmetric between `count = 0` and `count > 0`.
- [ ] Column types read from the report's column schema, not inferred from cells.

### Server-side token cap (always on)
- [ ] Cap serialized response at ~25K tokens (tune in implementation).
- [ ] Step 1: truncate long string cells first with explicit `"..."` suffix.
- [ ] Step 2 (if still too large): return fewer rows than requested; set `window.truncated = true` and `truncated_at = next row index` so caller can resume with `offset = truncated_at`.

### include_max_length semantics
- [ ] Default off -- keeps hot path cheap.
- [ ] When true: scan filtered result set, populate `max_observed_length` (characters, not bytes) on string columns; non-string columns omit the field.
- [ ] If full materialization is expensive: sample first K rows (K=200), set `max_length_sampled = true`.

### Implementation
- [ ] Locate existing `get_report` / `get_report_from_definition` in the Skyline MCP server under `pwiz_tools/Skyline/`.
- [ ] Reuse their report execution path; new tools differ only in *what they do with the materialized result* (window + serialize inline vs write to file).
- [ ] Document "no snapshot isolation across paginated calls" in tool descriptions.

### Tests
- [ ] `count = 0`: total row count + columns + types, empty rows array; no string scan when `include_max_length = false`.
- [ ] `count = N < total_rows`: returns N rows, correct window metadata.
- [ ] `count = N > total_rows`: returns all rows, `window.truncated = false`.
- [ ] `offset = total_rows - N, count = N`: returns last N rows (tail pattern).
- [ ] `include_max_length = true`: populates `max_observed_length` on string columns; non-string columns omit field; sampled mode sets `max_length_sampled = true`.
- [ ] Server-side cap: oversize request returns truncated cells / fewer rows with markers and `truncated_at`.
- [ ] `get_report_rows` filter: filtering reduces returned rows; `total_rows` reflects filtered count.
- [ ] `get_report_from_definition_rows`: does NOT accept `columns` / `filter`.

### Out of scope
- Removing or changing `get_report` / `get_report_from_definition`.
- Snapshot isolation across paginated calls.
- Server-side caching of report results across calls.

## Regression Test

- **Test name**: `JsonToolServerTest.TestReportRows` and `JsonToolServerTest.TestReportFromDefinitionRows`
  (server-direct coverage), plus inline-roundtrip checks in `SkylineMcpTest.TestMcpServerEndToEnd`
  exercising both new MCP tools through the named-pipe + stdio transport.
- **Test project**: `TestFunctional`
- **Fails on master**: Yes by construction -- the tests call
  `server.GetReportRows` / `server.GetReportFromDefinitionRows` and the MCP tools
  `skyline_get_report_rows` / `skyline_get_report_from_definition_rows`, none of
  which exist on master.
- **Passes on fix**: Yes -- TestJsonToolServer, TestSkylineMcp, and CodeInspection
  all green on this branch.

## Progress Log

### 2026-05-16 - Session Start

Starting work on this issue. Branch created, TODO copied from issue, ownership
signaled on the issue thread. Next: locate the existing report MCP tools in
`pwiz_tools/Skyline/` and identify the materialization seam to reuse.

### 2026-05-16 - Implementation complete

- Models: `ReportRowsResult`, `ReportRowsColumn`, `ReportRowsWindow` added to
  `JsonToolModels.cs` (link-compiled into both .NET Framework 4.7.2 and .NET 8).
- Interface: `GetReportRows` and `GetReportFromDefinitionRows` added to
  `IJsonToolService`, with matching wrappers in `SkylineJsonToolClient` and
  `SkylineConnection`.
- Server: `MaterializeReportRows` in `JsonToolServer` mirrors the file-export
  flow (streaming when possible, BindingListSource for pivots / row transforms),
  windows rows by `[offset, offset+count)`, applies an always-on token cap with
  per-cell truncation and tail-row trimming (`truncated_at` for resume), and
  optionally scans string-column max lengths over the first 200 rows
  (`max_length_sampled` when the dataset is larger).
- Filter on named reports resolves filter columns via a fresh `ColumnResolver`
  rooted at the report's `RowSource`, merges with `ViewSpec.Filters`, and is
  applied via the existing layout pipeline.
- MCP tools `skyline_get_report_rows` and `skyline_get_report_from_definition_rows`
  expose the surface to the LLM, serializing `ReportRowsResult` as snake_case
  JSON. Tool count check bumped from 45 to 47.
- New helper `RowFactories.TryGetRowSource(name, out source, out type)` exposes
  the registered factory needed for in-memory materialization.
- Tests: `TestReportRows` and `TestReportFromDefinitionRows` cover count=0
  introspection, in-window / oversize / tail patterns, `include_max_length`
  behavior, filter reduces totals, column projection, cell-cap enforcement, and
  error paths. `SkylineMcpTest` exercises the wire path end-to-end. All green
  locally: TestJsonToolServer, TestSkylineMcp, CodeInspection.
