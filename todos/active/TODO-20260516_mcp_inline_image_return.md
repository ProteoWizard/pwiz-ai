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

- **Test name**: (filled in once written — likely additions in `SkylineMcpTest` and a new functional test covering size-cap + version-skew fallbacks)
- **Test project**: TestFunctional (plus SkylineMcpTest for wire-format coverage)
- **Fails on master**: (to verify — the new behavior doesn't exist on master, so a test that asserts `ImageContentBlock` emission will naturally fail there)
- **Passes on fix**: (to verify)

The test should be the first deliverable on the branch: write the `SkylineMcpTest` end-to-end assertion that the three tools emit `ImageContentBlock` JSON for `returnFormat="inline"` (or default `"auto"`), watch it fail on master, then implement.

## Related

- Non-blocking screen-capture permission prompt (separate issue) — touches the same `GetFormImage` flow. Whichever lands first should leave a clean seam for the other.
- Precedent for tool surface: `get_report_rows` / `get_report_from_definition_rows` (chose companion tools because parameter sets differ; here a single `returnFormat` parameter is sufficient).

## Progress Log

### 2026-05-16 - Session Start

Starting work on this issue. Branch created from master, TODO scaffolded with the design surface and version-compatibility plan copied from the issue. Next: locate the three image-producing tools in the MCP server / `JsonUiService` / `JsonTutorialCatalog`, sketch the `ImageBytesMetadata` POCO, and write the failing `SkylineMcpTest` assertion before any production-code changes.
