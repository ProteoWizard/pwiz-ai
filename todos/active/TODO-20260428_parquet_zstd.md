# TODO-20260428_parquet_zstd.md

## Branch Information
- **Branch**: `Skyline/work/20260428_parquet_zstd`
- **Base**: `master`
- **Created**: 2026-04-28
- **Status**: In Progress
- **GitHub Issue**: [#4171](https://github.com/ProteoWizard/pwiz/issues/4171)
- **PR**: [#4172](https://github.com/ProteoWizard/pwiz/pull/4172) (draft)

## Objective

Upgrade Parquet.Net 3.0.0 → 4.25.0 in Skyline + OspreySharp so Parquet exports use Zstandard compression instead of Snappy.

(Originally targeted 5.5.0; pivoted to 4.25.0 — see Session 2 progress log.)

## Task Checklist

### Completed (5.5.0 attempt — superseded by 4.25.0 pivot, see Session 2)
- [x] ~~Refresh `Lib/Parquet/` with Parquet.Net 5.5.0 + 9 transitive deps~~ — re-done for 4.25.0 closure
- [x] ~~Bump 6 polyfill DLLs in `Lib/` to Parquet.Net 5.5.0's versions~~ — reverted to master (4.25.0 doesn't need bumps)
- [x] ~~Pin 7 transitive NuGet versions in `CommonMsData.csproj`~~ — reverted to master
- [x] Rewrite `ParquetReportExporter.cs` for the 5.x async-only API — kept (4.25.0 has same API)
- [x] Rewrite `ParquetScoreCache.cs` for the 5.x API + `CustomMetadata` simplification — kept (4.25.0 has same API)
- [x] Update `TestFunctional/ParquetReportExporterTest.cs` for the new reader API and dropped `DateTimeOffset` — kept

### Completed (4.25.0)
- [x] Refresh `pwiz_tools/Shared/Lib/Parquet/` with Parquet.Net 4.25.0 closure (10 files): `ParquetNet.dll` 4.0.0.0, `IronCompress.dll` 1.0.0.0, native `nironcompress.dll` (win-x64), `Snappier.dll` 1.1.6, `ZstdSharp.dll` 0.8.1 (`ZstdSharp.Port`), `Microsoft.IO.RecyclableMemoryStream.dll` 3.0.1, `System.Text.Json.dll` 8.0.5 + `System.Text.Encodings.Web.dll` 8.0.0, `System.Reflection.Emit.Lightweight.dll` 4.0.0.0, `ParquetNet.xml`. ParquetNet.dll renamed from `Parquet.dll` (still collides with C++ `arrow/parquet.dll`).
- [x] Restore `Lib/` polyfill DLLs to master state (`git checkout master -- ...`); 4.25.0 references are satisfied by master versions, no Lib/ bumps needed.
- [x] Update `Skyline.csproj`: 8 explicit Parquet-closure refs (ParquetNet, IronCompress, System.Reflection.Emit.Lightweight, Microsoft.IO.RecyclableMemoryStream, Snappier, System.Text.Encodings.Web, System.Text.Json, ZstdSharp) + Content entry for native `nironcompress.dll` with `CopyToOutputDirectory=PreserveNewest`. Polyfill refs from the 5.5.0 attempt removed (no longer needed).
- [x] Update three `app.config` files for the 4.25.0 closure: Parquet `codeBase version=4.0.0.0`, IronCompress redirect, polyfill redirects targeting master Lib/ versions (Microsoft.Bcl.AsyncInterfaces 9.0.0.4, System.Buffers 4.0.3.0, System.Memory 4.0.1.2, System.Numerics.Vectors 4.1.4.0, System.Runtime.CompilerServices.Unsafe 6.0.0.0, System.Threading.Tasks.Extensions 4.2.0.1, System.Text.* 8.0.0.0). PKT `d380b3dee6d01926` (4.x and 5.x share the same key — only 3.x → 4.x rotated).
- [x] Update installer `Product-template.wxs` + `FileList64-template.txt`: drop CommunityToolkit/K4os/Bcl.HashCode/IO.Pipelines, add IronCompress.dll + nironcompress.dll + System.Reflection.Emit.Lightweight.dll, keep RecyclableMemoryStream/Snappier/Encodings.Web/System.Text.Json/ZstdSharp.
- [x] Bump `OspreySharp.IO` / `OspreySharp.Test` `Parquet.Net` 5.5.0 → 4.25.0; restore `System.Memory` pin 4.6.3 → 4.5.5.
- [x] Revert `CommonMsData.csproj` to master state (drop the 7 transitive NuGet pins).
- [x] Skyline.sln builds green in Release|x64; `Skyline-daily.exe`, `TestRunner.exe`, all test DLLs land in `bin/x64/Release/`. Native `nironcompress.dll` lands too.
- [x] **`TestParquetArrays` PASSES** — 0 failures, ~1 sec, parquet write+read round-trip with zstd compression confirmed working.

### In Progress
_(none — both solutions build green and `TestParquetArrays` passes)_

### Remaining
- [ ] Developer review (build in VS, full TestFunctional run if desired)
- [ ] Verify byte-level cross-impl compat of `.scores.parquet` written by OspreySharp.IO with 4.25.0 is still readable by Rust osprey (Stage 5/6 reconciliation paths). 4.25.0's IronCompress→ZstdSharp.Port path may produce slightly different framing than 5.5.0's direct ZstdSharp.Port, but the parquet-level encoding should match.
- [ ] Run code inspection / pre-commit checks
- [ ] Push branch and update draft PR

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

### 2026-04-30 - Session 2 (pivot 5.5.0 → 4.25.0)

**TestParquetArrays failed at runtime** with `System.NotImplementedException` thrown from `Parquet.Extensions.StreamExtensions.<CopyToAsync>d__11.MoveNext()` during `DataColumnWriter.CompressAndWriteAsync` → `ParquetRowGroupWriter.WriteColumnAsync`. Compile-time clean; runtime broken.

**Root cause: upstream bug in Parquet.Net 5.5.0's netstandard2.0 build.** `StreamExtensions.cs` defines two new `CopyToAsync` extension helpers (`Stream→Memory<byte>` and `Memory<byte>→Stream`) wrapped in `#if !NETSTANDARD2_0 ... #else throw new NotImplementedException(); #endif`. The netstandard2.0 stub was never implemented; `CompressAndWriteAsync` always calls `pageData.Memory.CopyToAsync(_stream)` so every write throws on net472. The helpers were added in 5.5.0 alongside the IronCompress→ZstdSharp.Port migration; 5.4.0 does not contain them.

**Confirmed [parquet-dotnet#710](https://github.com/aloneguid/parquet-dotnet/issues/710)** — exact same exception, opened 2026-02-12, closed 2026-03-23 as **NOT_PLANNED** by maintainer aloneguid: *"I'm really sorry but I'm deprecating .net standard support, the minimum .net supported version is 8.0."* No fix coming. 5.6.0 dropped netstandard2.0 entirely.

**Pivot to Parquet.Net 4.25.0.** Last release on a long, mature 4.x line (~16 minor/patch releases between 2023-08 and 2024-09 vs. 5 releases on 5.x in the same window). 4.25.0 already has the same 5.x-style API surface we rewrote against:
- `Parquet.Schema.ParquetSchema` class (same name, same namespace).
- `DataField(string, Type clrType, bool? isNullable, bool? isArray, ...)` constructor (identical signature).
- Public `CustomMetadata` property on both `ParquetWriter` (`IReadOnlyDictionary<string,string>` setter; `Dictionary` is implicitly assignable) and `ParquetReader` (`Dictionary<string,string>`).
- Async-only API (`ParquetWriter.CreateAsync`, `WriteColumnAsync`, `ReadColumnAsync`).
- `CompressionMethod.Zstd` enum value.

So `ParquetReportExporter.cs`, `ParquetScoreCache.cs`, `ParquetReportExporterTest.cs` all compile against 4.25.0 unchanged.

**Compression backend:** 4.25.0 uses `IronCompress 1.5.2` for zstd, which P/Invokes a bundled native `nironcompress.dll` for performance. IronCompress 1.5.2 also pulls in managed `Snappier 1.1.6` and `ZstdSharp.Port 0.8.1` and falls back to managed implementations if the native lib fails to load (per upstream issue #574). Trade vs 5.5.0's fully-managed `ZstdSharp.Port`: native-binary deployment cost, but a working code path.

**Closure differences vs the 5.5.0 attempt:**
- Drop: `CommunityToolkit.HighPerformance.dll`, `K4os.Compression.LZ4.dll`, `Microsoft.Bcl.HashCode.dll`, `System.IO.Pipelines.dll`.
- Add: `IronCompress.dll`, `nironcompress.dll` (native, win-x64), `System.Reflection.Emit.Lightweight.dll`.
- Keep: `ParquetNet.dll` (now 4.0.0.0), `Microsoft.IO.RecyclableMemoryStream.dll`, `Snappier.dll`, `System.Text.Encodings.Web.dll`, `System.Text.Json.dll`, `ZstdSharp.dll`.
- Snappier downgraded 1.3.0 → 1.1.6 and ZstdSharp 0.8.7 → 0.8.1 to match the versions IronCompress 1.5.2 was compiled against.
- System.Text.Json 10.x → 8.0.5 + System.Text.Encodings.Web 8.0.0 (4.25.0 references the 8.0.0 line).

**Polyfills reverted to master state.** The 5.5.0 work bumped 6 polyfill DLLs in `Lib/` (Microsoft.Bcl.AsyncInterfaces 9→10, System.Memory 4.0.1.2→4.0.5.0, System.Buffers 4.0.3→4.0.5, System.Numerics.Vectors 4.1.4→4.1.6, System.Runtime.CompilerServices.Unsafe 6.0.0→6.0.3, System.Threading.Tasks.Extensions 4.2.0.1→4.2.4.0). 4.25.0 references the older versions; restoring `Lib/` to master eliminates the Skyline.csproj polyfill ref churn and the `CommonMsData.csproj` transitive-version pinning needed for 5.5.0. `git checkout master --` for those 7 files.

**Public key token unchanged.** 3.x → 4.x rotated `de28deb604dd91c9` → `d380b3dee6d01926`. 4.x → 5.x kept the same token. So the app.config `<assemblyIdentity name="Parquet" publicKeyToken=...>` updates from the 5.5.0 attempt remain correct; only the `version` changed `5.0.0.0` → `4.0.0.0`.

**Strong-name shape sanity check.** `ParquetNet.dll` 4.25.0 reports `Parquet, Version=4.0.0.0, Culture=neutral, PublicKeyToken=d380b3dee6d01926` and `AssemblyInformationalVersionAttribute = 4.25.0+687fbb462e94eddd1dc5a0aa26f33ba8e53f60e3`.

## Context for Next Session

**What still needs validation:**
1. **Round-trip a parquet through `ParquetReportExporter`** — `TestParquetArrays` should now pass. Confirm with `pwsh -File ./ai/scripts/Skyline/Run-Tests.ps1 -TestName TestParquetArrays`.
2. **Confirm `nironcompress.dll` lands in `Skyline/bin/x64/Release/`** alongside `IronCompress.dll`. If not, IronCompress falls back to managed Snappier/ZstdSharp.Port at a perf cost but writes still work.
3. **Run any OspreySharp parquet round-trip tests** — particularly Stage 5/6/8 cross-impl tests that round-trip files between Rust osprey and OspreySharp. The `byte[]` columns in OspreySharp's schema (`cwt_candidates`, `fragment_mzs`, etc.) are declared as `new DataField("name", typeof(byte[]), isNullable: true, isArray: false)`; if byte parity fails, check Parquet.Net 4.x's encoding of nullable `byte[]` columns (raw BYTE_ARRAY vs ConvertedType.BSON).
