# TODO-20260418_osprey_sharp_net8.md  -  OspreySharp .NET 8 POC

## Branch Information

- **Branch**: `Skyline/work/20260418_osprey_sharp_net8`
- **Branched from**: `Skyline/work/20260409_osprey_sharp`
  (current OspreySharp dev branch; NOT master)
- **Working directory**: `C:\proj\pwiz\pwiz_tools\OspreySharp\`
- **Created**: 2026-04-18
- **Status**: POC (do NOT merge back to parent branch until the path
  is proven end-to-end including Linux)

## Why a sub-branch of the OspreySharp dev branch

The parent branch has all the parity work that makes Stellar bit-
identical between Rust and C# (Sessions 1-18, 4,721-line
`AnalysisPipeline.cs`, 186 passing tests, etc.). Starting from master
would mean re-doing a month of work. Starting from the current
OspreySharp dev branch means we inherit the working implementation
and only change how it's packaged and what it depends on.

## Objective

Prove, in roughly 2-3 days of focused work, that OspreySharp can be
ported to .NET 8 with near-zero algorithmic change, and that the .NET
8 build produces bit-identical Stellar parity both on Windows and on
Linux. Two motivations:

1. **Lab-meeting concern resolved.** The colleague who preferred
   Osprey Rust because "it runs on Linux" gets an answer: OspreySharp
   runs on Linux too, without Wine and without a Skyline Docker
   container.
2. **Matt Chambers's .NET 8 `pwiz_data_cli` path becomes viable.**
   If Matt delivers a .NET 8 variant supporting mzML + Thermo RAW +
   Bruker raw, OspreySharp can adopt it as a `PackageReference` and
   get direct vendor-file reading on both OSes. Thermo covers ~80% of
   the market; Bruker timsTOF covers most of the remainder that
   matters to the MacCoss lab's focus areas.

**This TODO is a POC.** It does not commit OspreySharp to staying on
.NET 8. If the POC succeeds, a separate follow-up decides whether to
multi-target (net472 + net8.0) or migrate fully.

## Feasibility summary (from pre-port scan, 2026-04-18)

Good-news side:

- OspreySharp has ZERO dependencies on any Skyline/pwiz .NET
  Framework projects. It is standalone by design.
- No `AppDomain` isolation tricks, no `Thread.Abort`, no Remoting,
  no `BinaryFormatter`, no `System.Web`, no WinForms/WPF, no
  `System.Drawing`, no Win32 P/Invoke.
- All 8 projects use cross-platform APIs for file I/O. No hard-coded
  backslashes, no drive-letter checks, no registry access.
- Code is imperative and straightforward - no `Span<T>`, `Memory<T>`,
  or async/await complexity to worry about (neither present nor
  required).

What's actually in the way:

1. **All 8 `.csproj` files are legacy format** with
   `<TargetFrameworkVersion>v4.7.2</TargetFrameworkVersion>` and
   verbose per-configuration blocks (ex:
   `OspreySharp.IO/OspreySharp.IO.csproj:1-92`). Mechanical but 8
   files.
2. **System.Data.SQLite via HintPath** to
   `pwiz/libraries/SQLite/x64/System.Data.SQLite.dll`, which is a
   Framework-only build (`OspreySharp.IO.csproj:57-59`). Switch to
   `System.Data.SQLite.Core` NuGet (has .NET Standard 2.1 variant;
   same namespace, near-zero code change) OR
   `Microsoft.Data.Sqlite` (cleaner, small namespace rename). Path
   (a) for the POC to minimize diff.
3. **Parquet.Net 3.0.0.0 via HintPath** to
   `pwiz/pwiz_tools/Shared/Lib/Parquet/ParquetNet.dll`
   (`OspreySharp.IO.csproj:62-64`, confirmed via `app.config:8-9`
   binding redirect). The DLL itself is .NET Standard 2.0 and would
   run on .NET 8 as-is, BUT we should NuGet-upgrade to Parquet.Net
   4.x or 5.x for long-term support. Expect small API changes in
   `ParquetScoreCache.cs` around schema/reader-writer patterns.
   This is the one place with real unknowns.
4. **`System.Memory` / `System.Runtime.CompilerServices.Unsafe` /
   `System.Reflection.Emit.Lightweight`** HintPath refs
   (`OspreySharp.IO.csproj:65-73`). Built-in on .NET 8 - just delete
   the refs.
5. **`app.config`** (`OspreySharp/app.config:1-21`) only contains
   GC server/concurrent and Parquet/Memory binding redirects. Delete
   on .NET 8; server GC is default there.
6. **MSTest v1** (`OspreySharp.Test.csproj:55`,
   `Microsoft.VisualStudio.TestTools.UnitTesting`). Upgrade to
   MSTest v3 NuGet. Namespace stays; no code changes.
7. **JetBrains.Profiler.Api** in `OspreySharp/ProfilerHooks.cs` -
   available on NuGet with .NET Standard support. The try-catch
   guards in `ProfilerHooks.cs` already handle absence gracefully,
   so this is not a blocker.

**Estimated effort**: 2-3 days end-to-end including WSL2 validation.
Real Linux VM likely an additional half-day.

## Phases

### Phase 1 - Build .NET 8 on Windows (csproj surgery, no code changes)

Goal: `dotnet build OspreySharp.sln` and `dotnet test` both succeed on
Windows against .NET 8. No osprey.exe run yet.

Tasks:

- [ ] Convert all 8 csproj files to SDK-style format targeting
  `net8.0`:
  - `OspreySharp.Core.csproj`
  - `OspreySharp.IO.csproj`
  - `OspreySharp.Chromatography.csproj`
  - `OspreySharp.ML.csproj`
  - `OspreySharp.Scoring.csproj`
  - `OspreySharp.FDR.csproj`
  - `OspreySharp.csproj` (main / Program)
  - `OspreySharp.Test.csproj`
  Each becomes ~15 lines instead of ~90. Keep the existing
  `ProjectReference` graph intact.
- [ ] Delete duplicate `Properties/AssemblyInfo.cs` files (SDK-style
  auto-generates assembly-level attributes). Keep any
  `[InternalsVisibleTo("pwiz.OspreySharp.Test")]` - migrate to
  `<ItemGroup><InternalsVisibleTo Include="..."/></ItemGroup>` in
  the csproj or an `AssemblyAttributes.cs` file.
- [ ] Add PackageReferences (exact versions pinned at PR time):
  - `System.Data.SQLite.Core` (replaces HintPath DLL, IO project)
  - `Parquet.Net` 4.x or 5.x (replaces v3 HintPath, IO project;
    expect API diffs in `ParquetScoreCache.cs`)
  - `Newtonsoft.Json` (if used anywhere - currently referenced via
    Chromatography and Test, investigate and confirm)
  - `MathNet.Numerics` (ML, Scoring)
  - `JetBrains.Profiler.Api` (main OspreySharp project, for
    `ProfilerHooks.cs`)
  - `MSTest.TestFramework` + `MSTest.TestAdapter` +
    `Microsoft.NET.Test.Sdk` (Test project)
- [ ] Delete `OspreySharp/app.config` (redundant on .NET 8).
- [ ] Update `ai/scripts/OspreySharp/Build-OspreySharp.ps1` and
  related build scripts to detect / use `dotnet build` instead of
  msbuild for this branch. Keep the .NET Framework path compatible
  on the parent branch - this branch script diverges.
- [ ] Fix any code diffs required to compile (expected: Parquet.Net
  v3-to-v4/5 API migration in `OspreySharp.IO/ParquetScoreCache.cs`;
  possibly minor nullable-reference-type warnings to suppress for
  the POC via `<Nullable>disable</Nullable>` in csproj).

Exit gate: **`dotnet test` on the Test project passes all 186
existing unit tests**. Any skips or failures must be understood
(e.g., expected numerical drift in a Parquet round-trip test if the
new version changes compression defaults).

### Phase 2 - Run osprey.exe Stellar end-to-end on Windows .NET 8

Goal: `osprey --no-join` (or equivalent - maybe this POC just uses
the existing pipeline since `--no-join` is backlog) runs Stellar
data on Windows .NET 8 and produces the same per-file Parquet +
final blib as the net472 parent branch.

Tasks:

- [ ] `dotnet publish -c Release -r win-x64 --self-contained false
  OspreySharp/OspreySharp.csproj` - produces a runnable `osprey.exe`
  (or `osprey.dll` invoked via `dotnet osprey.dll`).
- [ ] Run against `D:\test\osprey-runs\stellar\` single-file first,
  then 3-file. Manually inspect the `.scores.parquet` files and
  final `.blib` for structural sanity.
- [ ] Run `Test-Features.ps1 -Dataset Stellar` using the new .NET 8
  build. Expect 21 PIN features bit-identical at 1E-06 against the
  Rust reference. If Parquet.Net upgrade shifted binary-cache byte
  order, the features should still match since features are read
  back as doubles.
- [ ] Bench: run `Bench-Scoring.ps1 -Dataset Stellar` (or equivalent)
  under .NET 8 and log wall-clock vs. net472 parent. Any regression
  > 10% is worth a note; > 30% is a blocker-level finding.

Exit gate: **Stellar 21 PIN features bit-identical on .NET 8
Windows** AND perf within 10% of the net472 branch.

### Phase 3 - WSL2 Ubuntu parity

Goal: Prove the .NET 8 port runs Linux-native, using WSL2 as the
fastest-to-set-up Linux environment on this machine.

Tasks:

- [ ] `dotnet publish -c Release -r linux-x64 --self-contained true
  OspreySharp/OspreySharp.csproj` on Windows. The self-contained
  flag avoids needing the .NET 8 runtime pre-installed on the WSL2
  side.
- [ ] Copy the publish output + the Stellar mzML + library files
  into a WSL2 Ubuntu home directory (or access via `/mnt/d/`).
- [ ] Run OspreySharp under WSL2. Compare the per-file
  `.scores.parquet` and the final `.blib` against the Windows
  .NET 8 outputs from Phase 2 (same inputs, same calibration, same
  OS-invariant code path). Expect bit-identical results. Any
  divergence is a cross-platform bug to root-cause before Phase 4.
- [ ] Note: WSL2 uses the Windows filesystem under `/mnt/`; for a
  fair Linux perf number, copy the inputs into the Linux ext4
  filesystem at `~/osprey-test/` or similar.

Exit gate: **WSL2 Stellar 21 PIN features bit-identical to the
Windows .NET 8 run from Phase 2**.

### Phase 4 - Real Linux VM validation

Goal: Confirm WSL2 success wasn't a quirk of the WSL2 kernel/libs;
run on a real Ubuntu or Rocky VM.

Tasks:

- [ ] Spin up a Linux VM (Hyper-V or VirtualBox - pick whichever is
  already installed). Ubuntu 22.04 LTS is the default target since
  it's the most common .NET 8 deployment target.
- [ ] Install .NET 8 runtime (or use self-contained publish output).
- [ ] Repeat the Phase 3 Stellar run. Compare to WSL2 and Windows
  outputs.
- [ ] Document any VM-specific setup gotchas (filesystem case
  sensitivity, file-permission issues on the mzML, missing
  `libicu` or `libssl` packages for self-contained runs, etc.) as
  an appendix here.

Exit gate: **Real Linux VM Stellar 21 PIN features bit-identical to
the WSL2 and Windows .NET 8 runs**. POC proven.

## Out of scope for this POC

- Astral dataset validation (Stellar is sufficient to prove the
  path; Astral just means longer wall-clock for the same test).
- `pwiz_data_cli` integration. Matt's .NET 8 variant doesn't exist
  yet; the POC is explicitly about proving OspreySharp runs on .NET
  8 / Linux with existing mzML-only input.
- Merging back to the parent OspreySharp branch. That's a separate
  decision after the POC lands: multi-target (net472 + net8.0) vs.
  full migration vs. parallel tracks.
- Integrating with Skyline (which is net472 and will stay that way
  for the foreseeable future).
- The HPC `--no-join` / `--join-only` work
  (`ai/todos/backlog/brendanx67/TODO-osprey_hpc_scoring_split.md`).
  Orthogonal; can land in either order.
- Upstreaming anything .NET-related to maccoss/osprey (Rust-only
  repo; no-op).

## Success criteria

- [ ] `dotnet build OspreySharp.sln` succeeds on Windows with
  net8.0 targets
- [ ] `dotnet test` passes all 186 existing unit tests on .NET 8
- [ ] `Test-Features.ps1 -Dataset Stellar` passes bit-identically on
  Windows .NET 8
- [ ] Same test passes bit-identically on WSL2 Ubuntu
- [ ] Same test passes bit-identically on a real Linux VM
- [ ] Perf on .NET 8 within 10% of net472 parent branch on Stellar
  single-file and 3-file parallel

## Risk register

- **Parquet.Net 3 → 4+ API breaks**. The reader/writer refactor in
  Parquet.Net 4 dropped the old `ParquetWriter`-based API in favor
  of a more functional pattern. Allow time in Phase 1 for a focused
  rewrite of `ParquetScoreCache.cs`. Parity gate will catch any
  subtle byte-order / precision shift.
- **Numerical drift on Linux from libm differences**. .NET uses its
  own math intrinsics, so this is usually a non-issue, but any
  transcendental function (exp/log/sin) could differ at ULP level
  on different CPU micro-architectures. The Stellar parity test
  already tolerates 1E-06 - if we see larger drift on Linux
  specifically, investigate with `OSPREY_DUMP_LDA_SCORES=1` and
  similar diagnostic env vars from the parent branch.
- **MathNet.Numerics LAPACK provider differences**. On Windows the
  MKL provider is common; on Linux the managed fallback is used
  unless Intel MKL is installed. If LDA or LOESS results drift, this
  is the first suspect. Fix by explicitly using the managed provider
  on both OSes via `MathNet.Numerics.Control.UseManaged()` early in
  startup.
- **File handle limits on Linux for large runs**. Stellar 3-file is
  fine; Astral or larger datasets might hit `ulimit -n` defaults on
  Linux. Not a POC blocker; document as a known operational gotcha.

## Rollback plan

If the POC hits a blocker deeper than 2 working days of effort, the
branch is abandoned on the POC branch and the parent branch is
unaffected. Document the blocker in a progress-log entry at the
bottom of this TODO so the next attempt has a head start.

## Quick reference - commands we'll need

```bash
# From C:\proj\pwiz (inside the POC branch)

# Build everything on .NET 8 (Windows)
dotnet build pwiz_tools/OspreySharp/OspreySharp.sln -c Release

# Run the test project
dotnet test pwiz_tools/OspreySharp/OspreySharp.Test/OspreySharp.Test.csproj -c Release

# Publish for Linux (self-contained, from Windows)
dotnet publish pwiz_tools/OspreySharp/OspreySharp/OspreySharp.csproj \
  -c Release -r linux-x64 --self-contained true \
  -o pwiz_tools/OspreySharp/OspreySharp/bin/publish/linux-x64

# Run the Stellar parity test (same PowerShell harness, new build)
pwsh -File './ai/scripts/OspreySharp/Test-Features.ps1' -Dataset Stellar
```

## Progress log

*(Each session working on this POC appends an entry here.)*

- 2026-04-18, Session 0: TODO drafted after pre-port feasibility
  scan; branch not yet created.
