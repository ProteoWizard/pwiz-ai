# TODO-20260428_parquet_zstd.md

## Branch Information
- **Branch**: `Skyline/work/20260428_parquet_zstd`
- **Base**: `master`
- **Created**: 2026-04-28
- **Status**: In Progress
- **GitHub Issue**: [#4171](https://github.com/ProteoWizard/pwiz/issues/4171)
- **PR**: (pending)

## Objective

Upgrade Parquet.Net 3.0.0 → 5.5.0 in Skyline + OspreySharp so Parquet exports use Zstandard compression instead of Snappy.

## Task Checklist

### Completed
- [x] Refresh `pwiz_tools/Shared/Lib/Parquet/` with Parquet.Net 5.5.0 + 9 transitive deps (drop System.Reflection.Emit.Lightweight)
- [x] Bump 6 polyfill DLLs in `pwiz_tools/Shared/Lib/` (System.Memory, System.Buffers, System.Numerics.Vectors, System.Runtime.CompilerServices.Unsafe, System.Threading.Tasks.Extensions, Microsoft.Bcl.AsyncInterfaces) to the versions Parquet.Net 5.5.0 was compiled against
- [x] Update `Skyline.csproj` reference list (10 new refs in Lib/Parquet, 5 explicit polyfill refs in Lib/, drop System.Reflection.Emit.Lightweight)
- [x] Update three `app.config` files: rotate Parquet PKT `de28deb604dd91c9` → `d380b3dee6d01926`, version `3.0.0.0` → `5.0.0.0`, add 8 new bindingRedirects
- [x] Update installer `Product-template.wxs` and `FileList64-template.txt` (9 new entries, drop `System.Reflection.Emit.Lightweight.dll`)
- [x] Bump `OspreySharp.IO` / `OspreySharp.Test` `Parquet.Net` 3.10.0 → 5.5.0; bump `System.Memory` 4.5.5 → 4.6.3
- [x] Pin transitive NuGet versions in `CommonMsData.csproj` (7 new `<PackageReference>` entries) so older copies pulled by `Microsoft.Extensions.Http 9.0.4` don't clobber Lib/ during project-reference Copy Local into Skyline/bin
- [x] Rewrite `ParquetReportExporter.cs` for 5.5.0 async-only API using `.Result` / `.Wait()` instead of `async`/`await`; default compression set to `CompressionMethod.Zstd`
- [x] Rewrite `ParquetScoreCache.cs` for 5.5.0 (Parquet.Schema namespace, `ParquetWriter.CreateAsync(...).Result`, `WriteColumnAsync(...).Wait()`, `ReadColumnAsync(...).Result`, replace reflection metadata workaround with direct `writer.CustomMetadata` / `reader.CustomMetadata`); default compression `CompressionMethod.Zstd`
- [x] Update `TestFunctional/ParquetReportExporterTest.cs` for the new reader API and the dropped `DateTimeOffset` storage path
- [x] Skyline.sln + OspreySharp.sln build green in Release|x64

### In Progress
- [ ] Push branch and open draft PR

### Remaining
- [ ] Developer review (build in VS, run TestFunctional/ParquetReportExporterTest, run any OspreySharp parquet round-trip tests)
- [ ] Verify byte-level cross-impl compat of `.scores.parquet` written by OspreySharp.IO is still readable by Rust osprey (Stage 5/6 reconciliation paths)
- [ ] Run code inspection / pre-commit checks

## Key Files

### Library binaries
- `pwiz_tools/Shared/Lib/Parquet/` — 10 DLLs + ParquetNet.xml (was 3 files); ParquetNet.dll renamed from Parquet.dll because of conflict with C++ `arrow/parquet.dll`
- `pwiz_tools/Shared/Lib/{System.Memory,System.Buffers,System.Numerics.Vectors,System.Runtime.CompilerServices.Unsafe,System.Threading.Tasks.Extensions,Microsoft.Bcl.AsyncInterfaces}.dll` — bumped polyfills

### Project / config
- `pwiz_tools/Skyline/Skyline.csproj` — reference list update
- `pwiz_tools/Skyline/{app.config,TestRunner/app.config,TestFunctional/App.config}` — bindingRedirects
- `pwiz_tools/Skyline/Executables/Installer/{Product-template.wxs,FileList64-template.txt}` — installer payload
- `pwiz_tools/Shared/CommonMsData/CommonMsData.csproj` — pinned transitive NuGet versions
- `pwiz_tools/OspreySharp/{OspreySharp.IO,OspreySharp.Test}/*.csproj` — `Parquet.Net 3.10.0` → `5.5.0`, `System.Memory 4.5.5` → `4.6.3`

### Code
- `pwiz_tools/Skyline/Model/Databinding/ParquetReportExporter.cs` — rewrite for 5.5.0 API
- `pwiz_tools/Skyline/TestFunctional/ParquetReportExporterTest.cs` — test updates for new reader API and storage type
- `pwiz_tools/OspreySharp/OspreySharp.IO/ParquetScoreCache.cs` — rewrite for 5.5.0 API; reflection metadata workaround replaced with `writer.CustomMetadata` / `reader.CustomMetadata`

## Progress Log

### 2026-04-28 - Session 1

**Decided on Parquet.Net 5.5.0** (not 5.6.0 — 5.6.0 dropped netstandard2.0 and is therefore incompatible with net472; not 4.x — its zstd impl ships via the native `IronCompress` package while 5.5.0 uses fully-managed `ZstdSharp.Port`).

**API rewrite without `async`/`await`:** Skyline's `ai/CRITICAL-RULES.md` forbids the keywords. Used the equivalent sync wait pattern — e.g. `groupWriter.WriteColumnAsync(col).Wait()`, `ParquetWriter.CreateAsync(schema, stream).Result`, `groupReader.ReadColumnAsync(field).Result.Data`. The `QueueWorker<DataColumn[]>` background-write pipeline in `ParquetReportExporter.Export` survives unchanged because the consumer lambda was already plain sync.

**`DateTimeOffset` storage dropped:** Parquet.Net 5.x explicitly throws on `DateTimeOffset` ("support was dropped due to numerous ambiguity issues, please use DateTime from now on"). Storage type for `DateTime` columns moved from `DateTimeOffset?` to `DateTime?`. The existing code only ever wrapped `new DateTimeOffset(dt)` with the local-kind assumption, so this loses no real timezone information.

**`DataType` enum is gone in 5.x.** All `new DataField(name, DataType.X, hasNulls:..., isArray:...)` call sites were rewritten to `new DataField(name, typeof(T), isNullable:..., isArray:...)`. `DataType.ByteArray` → `typeof(byte[])`. `Schema` → `ParquetSchema`. `Parquet.Thrift` namespace → `Parquet.Meta`.

**OspreySharp metadata reflection workaround removed.** 5.5.0 makes `CustomMetadata` a public get/set property on both `ParquetWriter` and `ParquetReader`, so the ~70 lines of reflection-walking-`_footer`-and-`_fileMeta`-and-`Key_value_metadata` code in `ParquetScoreCache.SetWriterMetadata` collapsed to `writer.CustomMetadata = metadata;`. Reads similarly use `reader.CustomMetadata`.

**Strong-name key rotated.** Parquet.Net public key token went `de28deb604dd91c9` → `d380b3dee6d01926` between 3.x and 5.x. All `<assemblyIdentity name="Parquet" publicKeyToken=...>` entries had to be updated, not just versions.

**Polyfill version conflict trail:**
1. First build hit `CS1705` because `Microsoft.Extensions.Http 9.0.4` (referenced by `CommonMsData`) pulled in `Microsoft.Bcl.AsyncInterfaces 9.0.4` transitively, while Parquet.Net 5.5.0 references `10.0.0.1`.
2. Adding an explicit `<PackageReference Include="Microsoft.Bcl.AsyncInterfaces" Version="10.0.1">` to `CommonMsData.csproj` resolved the compile error but left runtime-time MSB3277 conflict warnings for 6 other DLLs (`System.Memory`, `System.Buffers`, `System.Numerics.Vectors`, `System.Text.Json`, `System.Text.Encodings.Web`, `Microsoft.IO.RecyclableMemoryStream`).
3. Root cause: project-reference Copy Local from `CommonMsData/bin/Release` was overwriting the newer Lib/ copies in `Skyline/bin`. Fixed by pinning all 7 transitive NuGet versions in `CommonMsData.csproj`.
4. Verified all 16 Parquet-closure DLLs in `Skyline/bin/x64/Release/` end up at the intended versions, no MSB3277 warnings remain.

**Default compression set to Zstd** in both `ParquetReportExporter.Export` and the two `WriteScoresParquet` overloads in `ParquetScoreCache`. Per-call override is still possible via `writer.CompressionMethod`.

## Context for Next Session

The branch builds clean against `Skyline.sln` and `OspreySharp.sln` in Release|x64. No compile errors, no MSB3277 warnings.

**What still needs validation:**
1. **Round-trip a parquet through `ParquetReportExporter`** — the existing TestFunctional test (`TestParquetArrays`) was updated and should work, but the developer should run it and verify the output file is readable.
2. **Run any OspreySharp parquet tests** — particularly cross-impl tests that round-trip files between Rust osprey and OspreySharp. Stage 5+8 byte-parity tests are the most likely to surface a problem; Stage 6 reconciliation reads the binary blob columns (`cwt_candidates`, `fragment_mzs`, etc.) which are still stored as nullable `byte[]` placeholders.
3. **The `byte[]` columns in OspreySharp's schema** may behave differently in 5.5.0 vs 3.10.0. The schema is now declared as `new DataField("name", typeof(byte[]), isNullable: true, isArray: false)`. If cross-impl byte-parity tests fail, this is the first place to look — Parquet.Net 5.x's encoding of nullable `byte[]` columns may have changed (logical type ConvertedType.BSON vs. raw BYTE_ARRAY).
4. **TestRunner ConcurrentVisualizer / leak tests** — bumping `Microsoft.Bcl.AsyncInterfaces` from 9.x to 10.x may surface new finalizer paths. Worth running the leak tracker once.
