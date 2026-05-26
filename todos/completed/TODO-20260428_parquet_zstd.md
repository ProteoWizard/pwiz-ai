# TODO-20260428_parquet_zstd.md

## Branch Information
- **Branch**: `Skyline/work/20260428_parquet_zstd` (squash-merged + deleted)
- **Base**: `master`
- **Created**: 2026-04-28
- **Status**: COMPLETE — squash-merged 2026-05-07
- **GitHub Issue**: [#4171](https://github.com/ProteoWizard/pwiz/issues/4171) (closed by merge)
- **PR**: [#4172](https://github.com/ProteoWizard/pwiz/pull/4172) (merged 2026-05-07)

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
- [x] Developer review (TeamCity green: Skyline 1621/1621, Core 308 + 293 + 271, Bumbershoot 5+5, OspreySharp 299/299; intermittent Docker-container build flakiness traced to a stale-`artifacts/` race in the prep script — pre-existing infra bug unrelated to this PR, flagged to Matt Chambers separately)
- [x] Verify byte-level cross-impl compat of `.scores.parquet` written by OspreySharp.IO with 4.25.0 is still readable by Rust osprey — Stages 1-4 (`Diff-Parquet`) 3/3, Stage 5 (`Compare-Stage5-AllFiles`) 3/3 across all four dumps, Stage 6 (`Compare-Stage6-Crossimpl`) 1/1, all on Stellar with both impls writing Zstd (no Snappy fallback in the cross-tool path)
- [x] Run code inspection / pre-commit checks (ReSharper 0 warnings on net472 + net8.0)
- [x] Push branch and update draft PR (PR #4172 squash-merged 2026-05-07)

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

### 2026-05-07 — Session 3 (Parquet.Net Thrift skip patch + cross-tool ZSTD validation + merge)

**Cross-impl read of Rust-emitted parquet broke under 4.25.0** with `InvalidOperationException: don't know how to skip type Uuid` thrown from `ThriftCompactProtocolReader.SkipField` while reading the file footer. Diagnosed as a Parquet.Net library bug, not a parquet-format issue: `SkipField(CompactType.Struct)` reads each nested field's header but never consumes the field's value (the loop body is empty), so once the auto-generated `ColumnMetaData.Read` falls back to `SkipField` for an unknown struct field the read cursor mis-aligns and a random byte's low nibble eventually matches `CompactType.Uuid` (0x0D, an unhandled case → throws). The trigger here is `parquet-rs >= 58` writing `ColumnMetaData.size_statistics` (field 16, struct), which Parquet.Net 4.25.0's auto-generated reader doesn't enumerate. Same bug present in upstream 5.6.1 and 6.0.1 — upgrading wouldn't fix it.

**Patched fork**: `maccoss-developers/skylinedev/Parquet.Net` (MIT, built from upstream tag 4.25.0). One-line fix in `ThriftCompactProtocolReader.SkipField`: recurse into `SkipField(nestedType)` inside the Struct-skip loop body so each nested field's value is consumed. Also implemented the previously commented-out Uuid case (16 raw bytes per Apache Thrift compact spec). `<LangVersion>12</LangVersion>` pin in `Parquet.csproj` to dodge a .NET 10 SDK / C# 14 `field` keyword collision in `StructField.cs`. `BUILD.md` documents the rebuild flags (`-p:NuGetAudit=false -p:Version=4.25.0-osprey1 -p:FileVersion=4.25.0 -p:AssemblyVersion=4.0.0`); `PATCH-NOTES.md` documents the patch and links the upstream PR. Built for netstandard2.0 (lowest common denominator for Skyline net472 + OspreySharp net472/net8.0). AssemblyVersion=4.0.0 matches stock 4.25.0 so the existing app.config binding redirects keep working unchanged.

**OspreySharp picks up the patched dll** via `pwiz_tools/OspreySharp/Directory.Build.targets` — a post-build target that copies `pwiz_tools/Shared/Lib/Parquet/ParquetNet.dll` over the NuGet-resolved `Parquet.dll` in each output directory. Skyline already references `Lib/Parquet/ParquetNet.dll` directly via `<Reference>` in `Skyline.csproj`, so it picks up the patched build automatically.

**IronCompress native binary deploy for OspreySharp.Test net472**: Exe projects (e.g. OspreySharp itself) get `nironcompress.dll` for free because the SDK's RuntimeIdentifier inference unwraps `runtimes/win-x64/native/*`, but library/test projects don't. Added an explicit `IronCompress` PackageReference with `GeneratePathProperty="true"` and a Content copy in `OspreySharp.Test.csproj` for net472. net8.0 resolves the native dep via deps.json automatically.

**Inspection cleanup** (8 ReSharper warnings) on pre-existing branch code that the prior pushes didn't catch (the session that pushed didn't run `-RunInspection`): defensive null checks on `col.Data` and `CustomMetadata` are dead code under Parquet.Net 4.x's non-null annotations.

**Final cross-tool validation on Stellar** (Generate-AllScoresParquet now calls Rust osprey without `--parquet-compression snappy`, so Rust defaults to its own Zstd codec; OspreySharp also writes Zstd):

| Stage | Harness | Result |
|---|---|---|
| 1-4 | `Diff-Parquet` (column byte-parity Rust vs OspreySharp) | 3/3 PASS, 0 diff cols |
| 5 | `Compare-Stage5-AllFiles` (4 dumps SHA-256 byte-identical) | 3/3 PASS |
| 6 | `Compare-Stage6-Crossimpl` (worker mode, hydration + rescored + parquet) | 1/1 PASS |

OspreySharp unit tests 299/299 on net472 + net8.0, ReSharper 0 warnings.

**Upstream PR filed**: [aloneguid/parquet-dotnet#747](https://github.com/aloneguid/parquet-dotnet/pull/747). Includes the SkipField fix, the Uuid case, and a focused regression test in `src/Parquet.Test/ThriftTest.cs` that constructs a 9-byte hand-crafted compact-protocol payload exercising the unknown-nested-struct case. Once #747 merges and a release ships, `pwiz_tools/Shared/Lib/Parquet/ParquetNet.dll` can be bumped to the stock NuGet release and the `Directory.Build.targets` post-build copy can be retired.

**Squash-merged as PR #4172 on 2026-05-07.** Closes #4171. Branch deleted on merge.

## See also

- `ai/todos/active/TODO-20260423_osprey_sharp.md` — Phase 4 umbrella (Stages 6-8). Session log updated 2026-05-07 to reflect the ZSTD-by-default state.
- `ai/todos/active/TODO-20260507_osprey_sharp_stage7.md` — next sub-sprint, queued.
- `maccoss-developers/skylinedev/Parquet.Net/{BUILD.md,PATCH-NOTES.md}` — patched-fork rebuild + patch summary.
- `aloneguid/parquet-dotnet#747` — upstream PR.
