# Add inline image return for screenshot / graph MCP tools

## Branch Information
- **Branch**: `Skyline/work/20260516_mcp_inline_image_return`
- **Base**: `master`
- **Created**: 2026-05-16
- **Status**: Completed
- **GitHub Issue**: [#4220](https://github.com/ProteoWizard/pwiz/issues/4220)
- **PR**: [#4222](https://github.com/ProteoWizard/pwiz/pull/4222) (merged 2026-05-17)

## Objective

Add a `returnFormat` parameter to the three image-producing MCP tools — `skyline_get_form_image`, `skyline_get_graph_image`, and `skyline_get_tutorial_image` — so the model can receive the PNG directly in the tool response via MCP's `ImageContentBlock` instead of a file path it then has to Read. Mirrors the validation-loop motivation behind `get_report_rows` / `get_report_from_definition_rows`: same MCP call, model sees the image, no file round-trip.

The new path must default to inline (fastest for clients that support it) with a clear escape hatch back to file-on-disk for clients that don't render image content or when the payload exceeds the server-side cap.

## Tasks

### Design surface (per issue)
- [x] `returnFormat` parameter added to `skyline_get_form_image`, `skyline_get_graph_image`, `skyline_get_tutorial_image`
  - `"auto"` (default): inline, fall back to file on cap-exceeded OR version-skew "Unknown method"
  - `"inline"`: always inline, error on cap-exceeded, surface version-mismatch error
  - `"file"`: existing behavior (back-compat)
- [x] `filePath` honored only on `file` / auto-fell-back-to-file paths; ignored elsewhere with a one-line note

### IJsonToolService additions
- [x] `GetFormImageBytes`, `GetGraphImageBytes`, `GetTutorialImageBytes` returning `ImageBytesMetadata`
- [x] New POCO `ImageBytesMetadata` in `JsonToolModels.cs` (link-compiled into both NF472 and .NET 8). Shipped fields: `byte[] Data, string FilePath, string MimeType, string Message`. Dropped the planned `int? OriginalBytes` (cap-comparison is wrapper-side; original byte count is reported in the cap-fallback text). Added `Message` field during Copilot review for structured non-image responses (screen-capture denial, desktop unavailable).
- [x] Refactor `JsonUiService.GetFormImage` / `GetGraphImage` and `JsonTutorialCatalog.FetchTutorialImage` so bitmap-producing core is separate from the file-writing tail

### MCP server wrappers (`SkylineTools.cs`)
- [x] Wrappers convert `ImageBytesMetadata.Data` to `ImageContentBlock` for inline; emit `TextContentBlock` with file-path note for fallback
- [x] Return type changed from `string` to `ModelContextProtocol.Protocol.CallToolResult`
- [x] Server-side size cap (~500 KB raw, tunable via `SKYLINE_MCP_INLINE_IMAGE_CAP_BYTES` env var). Implementation deviates from the planned `InternalsVisibleTo("TestFunctional")` pattern: an env var was used because the test runs the MCP server as a subprocess and so cannot reach into wrapper internals via reflection.
- [x] MIME type `image/png` for form/graph captures; tutorial images use the source filename extension (so JPEG / GIF tutorial assets pass through correctly)

### Version-skew handling
- [x] `returnFormat="auto"` catches JSON-RPC `ERROR_METHOD_NOT_FOUND` from the bytes call and falls back to the existing file-based JSON-RPC method
- [x] `returnFormat="inline"` surfaces the version-mismatch error so caller can decide
- Detection upgraded during self-review to match on the typed `JsonRpcException.Code` rather than message-text substring grep

### Tests
- [x] Inline return: bitmap → base64 → MIME `image/png`, byte length matches file form for the same source
- [x] Size-cap fallback (lower cap via env var on a second subprocess): response carries the saved file path; file on disk is a valid PNG
- [x] Version-skew fallback: typed-exception assertion via raw-pipe JSON-RPC probe; verifies `JsonRpcException.Code == ERROR_METHOD_NOT_FOUND` and message names the unknown method
- [x] Explicit `inline` over cap → error response (not silent fallback)
- [x] Explicit `file` → matches today's behavior exactly (regression)
- [ ] Permission denial path NOT covered by functional test — screen-capture denial requires interactive dialog and the test machine pre-grants permission. Production code path is in place: `GetFormImageBytes` returns structured `ImageBytesMetadata.Message`, and the file-mode wrapper detects denial responses via `IsScreenCaptureDenial`. Deferred to a follow-up if/when a non-interactive denial seam is added.
- [x] `SkylineMcpTest` end-to-end: wire format emits `ImageContentBlock` JSON (PNG signature verified after base64 decode)

### Out of scope (per issue)
- Removing/changing file-based response when `returnFormat="file"`
- Multi-image responses in one tool call
- Formats other than PNG
- Client capability negotiation beyond best-effort

## Regression Test

- **Test name**: `TestSkylineMcp` (extended) — `ValidateImageInlineAndFileModes` + `ValidateImageCapFallback` + `ValidateGetGraphImageBytesPipe`
- **Test project**: TestFunctional
- **Fails on master**: yes by construction (the new MCP return shape, the bytes JSON-RPC method, the cap-fallback wrapper logic, and the env-var cap knob do not exist on master)
- **Passes on fix**: yes — 0 failures, 6-8 sec, no GC-LEAK (verified locally)

Coverage:
- File mode: response is a `TextContentBlock` with the file path and a PNG on disk whose first 8 bytes are the PNG signature (regression check for the existing contract).
- Auto / inline mode (image fits cap): response is an `ImageContentBlock` with `mimeType=image/png` and base64 bytes that also decode to a PNG signature.
- Auto mode (image over cap, second subprocess with `SKYLINE_MCP_INLINE_IMAGE_CAP_BYTES=100`): response is a `TextContentBlock` containing "exceeded inline cap" and a path that exists on disk and is a valid PNG.
- Inline mode (image over cap, same subprocess): response is a `CallToolResult` with `isError=true` and an error text containing "exceeded inline cap".
- Direct JSON-RPC pipe call to the new `GetGraphImageBytes` method confirms `ImageBytesMetadata` round-trips bytes + suggested file path across the Newtonsoft (server) / System.Text.Json (client) boundary.

## Related

- Non-blocking screen-capture permission prompt (separate issue) — touches the same `GetFormImage` flow. Whichever lands first should leave a clean seam for the other.
- Precedent for tool surface: `get_report_rows` / `get_report_from_definition_rows` (chose companion tools because parameter sets differ; here a single `returnFormat` parameter is sufficient).

## Progress Log

### 2026-05-16 - Session Start

Starting work on this issue. Branch created from master, TODO scaffolded with the design surface and version-compatibility plan copied from the issue. Next: locate the three image-producing tools in the MCP server / `JsonUiService` / `JsonTutorialCatalog`, sketch the `ImageBytesMetadata` POCO, and write the failing `SkylineMcpTest` assertion before any production-code changes.

### 2026-05-16 - Implementation complete

- Added `ImageBytesMetadata` POCO to `JsonToolModels.cs` (link-compiled into both NF472 and .NET 8).
- Added `GetGraphImageBytes` / `GetFormImageBytes` / `GetTutorialImageBytes` to `IJsonToolService.cs` and implemented them across `SkylineJsonToolClient.cs` (client), `JsonToolServer.cs` (server dispatch), `JsonUiService.cs` (graph + form bitmap producers), and `JsonTutorialCatalog.cs` (HTTP download to memory). `SkylineConnection.cs` delegates the new methods.
- Refactored `GetGraphImage` and `GetFormImage` so the bitmap-producing core is reusable: `RenderGraphBitmap` / `CaptureFormBitmap` are now the shared cores. `FetchTutorialImage` shares helpers `ResolveTutorial` / `ValidateTutorialImageFilename` / `BuildTutorialImageUrl` with its bytes companion.
- MCP wrappers for the three image tools (`SkylineTools.cs`) now return `CallToolResult` and accept a `returnFormat` parameter (`auto`/`inline`/`file`). Added `InvokeContent` (CallToolResult counterpart of `Invoke`), `InvokeImage` (returnFormat dispatch + cap fallback + version-skew fallback), and supporting helpers. Cap is set to ~500 KB raw bytes by default, tunable via the `SKYLINE_MCP_INLINE_IMAGE_CAP_BYTES` environment variable.
- Server-side cap is intentionally deferred to the MCP wrapper so the JSON-RPC layer stays pure transport. The wrapper writes bytes to the server-suggested fallback path when the cap is exceeded in `auto` mode.
- Version-skew: when an older Skyline lacks the bytes method, `Invoke()` enriches the "Unknown method:" error with the Skyline version. The wrapper catches this in `auto` mode and falls back to the existing file-based JSON-RPC method; `inline` mode surfaces the error explicitly with retry guidance.
- Tests: extended `SkylineMcpTest` with three new validation blocks across two subprocess scenarios (default cap and 100-byte cap). Validation closes the opened Peak Areas graph at end of each scenario so the GC-leak tracker stays clean.
- Build: Skyline.sln + SkylineMcp.sln both green. TestSkylineMcp passes (~8 s, 0 failures, no GC-LEAK). CodeInspection passes (~14 s).

### 2026-05-16 - Post-PR review pass complete

PR #4222 opened. Copilot autoreviewed; addressed five inline findings in commit 175a802 (file-mode form-image denial pass-through, tutorial-image not-found back to non-error, GetFormImageBytes denial via structured `Message` field instead of throw, MimeType doc updated, "exceeded inline cap" extracted to `JsonToolConstants.MSG_INLINE_CAP_EXCEEDED`).

Fresh-context Claude agent self-review surfaced three [important] + three [nit] findings. Addressed in commit a7dd4e2:

- Threaded JSON-RPC error code through `SkylineJsonToolClient.Call` via new public `JsonRpcException` (derives from `InvalidOperationException` for back-compat). Version-skew detection now matches on `code == ERROR_METHOD_NOT_FOUND` instead of grepping "Unknown method:" message text. Resolves the tutorial-image dead-code nit as a side effect since server-side `IOException` now flows back as `JsonRpcException` not raw `IOException`.
- Wrapped `WriteBytesToDisk` in cap-fallback with a tight try/catch that surfaces real disk-error messages instead of being mistranslated as "Skyline disconnected".
- Wrapped both new test scenarios in try/finally so graph cleanup runs even when an assertion fails; without this, a real assertion failure would be masked behind a GC-LEAK failure.
- Extended `TestVersionMismatchError` with a typed-exception assertion: `JsonRpcException` with `Code == ERROR_METHOD_NOT_FOUND` and message naming the unknown method.

Deferred: positional-arg back-compat concern (no in-tree callers; MCP/JSON callers always use named args) and the timestamp-resolution collision in `GetMcpTmpFilePath` (existing property of the file-on-disk path, out of scope).

### 2026-05-17 - Test refactor + Merged

Post-PR test cleanup commit (`67793ac`): replaced JObject indexer chains in the new test code with typed POCOs (`JsonRpcResponse<TResult>`, `McpCallToolResult`, `McpContentBlock`, `McpListToolsResult`) and a generic `McpCall<T>` deserializer. Eliminated all ReSharper "Possible System.NullReferenceException" warnings that TeamCity's Skyline Code Inspection config flagged. Side effects: shrunk `TestVersionMismatchError` by half (no more manual JSON-RPC envelope parsing), gave the project a typed seam if other MCP tests want it later.

PR #4222 merged 2026-05-17 as commit `41a9230b`. Four commits squashed into one on master: initial implementation, Copilot fixes, self-review fixes, test-typed refactor. Shipped everything in scope; one explicit gap (functional-test coverage of the screen-capture denial path) acknowledged above. Two follow-up concerns surfaced during review and explicitly deferred: positional-arg back-compat for any future in-process C# callers, and second-resolution timestamp collision in `GetMcpTmpFilePath` (pre-existing in the file-on-disk path).
