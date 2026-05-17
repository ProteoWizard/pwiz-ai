# Add inline image return for screenshot / graph MCP tools

## Branch Information
- **Branch**: `Skyline/work/20260516_mcp_inline_image_return`
- **Base**: `master`
- **Created**: 2026-05-16
- **Status**: In Progress
- **GitHub Issue**: [#4220](https://github.com/ProteoWizard/pwiz/issues/4220)
- **PR**: (pending)

## Objective

Add a `returnFormat` parameter to the three image-producing MCP tools — `skyline_get_form_image`, `skyline_get_graph_image`, and `skyline_get_tutorial_image` — so the model can receive the PNG directly in the tool response via MCP's `ImageContentBlock` instead of a file path it then has to Read. Mirrors the validation-loop motivation behind `get_report_rows` / `get_report_from_definition_rows`: same MCP call, model sees the image, no file round-trip.

The new path must default to inline (fastest for clients that support it) with a clear escape hatch back to file-on-disk for clients that don't render image content or when the payload exceeds the server-side cap.

## Tasks

### Design surface (per issue)
- [ ] `returnFormat` parameter added to `skyline_get_form_image`, `skyline_get_graph_image`, `skyline_get_tutorial_image`
  - `"auto"` (default): inline, fall back to file on cap-exceeded OR version-skew "Unknown method"
  - `"inline"`: always inline, error on cap-exceeded, surface version-mismatch error
  - `"file"`: existing behavior (back-compat)
- [ ] `filePath` honored only on `file` / auto-fell-back-to-file paths; ignored elsewhere with a one-line note

### IJsonToolService additions
- [ ] `GetFormImageBytes`, `GetGraphImageBytes`, `GetTutorialImageBytes` returning `ImageBytesMetadata`
- [ ] New POCO `ImageBytesMetadata { byte[] Data, string FilePath, string MimeType, int? OriginalBytes }` in `JsonToolModels.cs` (link-compiled into both NF472 and .NET 8)
- [ ] Refactor `JsonUiService.GetFormImage` / `GetGraphImage` and `JsonTutorialCatalog.FetchTutorialImage` so bitmap-producing core is separate from the file-writing tail

### MCP server wrappers (`SkylineTools.cs`)
- [ ] Wrappers convert `ImageBytesMetadata.Data` to `ImageContentBlock` for inline; emit `TextContentBlock` with file-path note for fallback
- [ ] Return type changes from `string` to whichever content-block shape ModelContextProtocol 0.8.0-preview.1 exposes (`IList<ContentBlock>` likely)
- [ ] Server-side size cap (~500 KB base64, internal static int with `InternalsVisibleTo("TestFunctional")`, same pattern as `MaxResponseChars`)
- [ ] MIME type always `image/png` in v1

### Version-skew handling
- [ ] `returnFormat="auto"` catches "Unknown method" from new bytes JSON-RPC call and falls back to existing `GetFormImage(formId, filePath)` call
- [ ] `returnFormat="inline"` surfaces the version-mismatch error so caller can decide

### Tests
- [ ] Inline return: bitmap → base64 → MIME `image/png`, byte length matches file form for the same source
- [ ] Size-cap fallback (lower cap via test-only knob): response carries `FilePath`, file on disk matches in-memory bitmap
- [ ] Version-skew fallback: simulate "Unknown method" on bytes call; `auto` falls back, `inline` errors
- [ ] Explicit `inline` over cap → error response (not silent fallback)
- [ ] Explicit `file` → matches today's behavior exactly (regression)
- [ ] Permission denial → same behavior across all `returnFormat` values
- [ ] `SkylineMcpTest` end-to-end: wire format actually emits `ImageContentBlock` JSON

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
