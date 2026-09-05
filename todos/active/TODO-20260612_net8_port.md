# TODO: Skyline → .NET 8 port + pwiz-sharp swap + Jamfile retirement

Branch: `Skyline/work/20260612_net8_port` (off `master`)
Worktree: `C:\dev\pwiz-net8\`

## The multi-target conversion pattern (proven on PortableUtil + CommonUtil)

The Skyline tree is large but the conversion of each csproj follows a repeatable
template. **Multi-target `net472;net8.0-windows`** — net472 keeps the legacy
Skyline build path working unchanged; net8.0-windows is the new path.

Template csproj (drop the legacy 600-line XML, replace with ~40 lines):

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <ProjectGuid>{...}</ProjectGuid>                 <!-- preserve from legacy -->
    <TargetFrameworks>net472;net8.0-windows</TargetFrameworks>
    <Platforms>AnyCPU;x64</Platforms>
    <LangVersion>latest</LangVersion>
    <Nullable>disable</Nullable>
    <ImplicitUsings>disable</ImplicitUsings>
    <RootNamespace>pwiz.X</RootNamespace>
    <AssemblyName>pwiz.X</AssemblyName>
    <UseWindowsForms>true</UseWindowsForms>           <!-- if WinForms used -->
    <Company>University of Washington</Company>
    <Copyright>Copyright (c) University of Washington 2026</Copyright>
    <GenerateAssemblyInfo>false</GenerateAssemblyInfo>  <!-- AssemblyInfo.cs already exists -->
    <GenerateResourceUsePreserializedResources>true</GenerateResourceUsePreserializedResources>
  </PropertyGroup>

  <ItemGroup>
    <!-- both targets -->
    <PackageReference Include="System.Resources.Extensions" Version="8.0.0" />
  </ItemGroup>

  <ItemGroup>
    <!-- net472-only assemblies the SDK doesn't add by default -->
    <Reference Include="System.Net.Http" Condition="'$(TargetFramework)' == 'net472'" />
    <Reference Include="System.Web" Condition="'$(TargetFramework)' == 'net472'" />
    <Reference Include="System.Security" Condition="'$(TargetFramework)' == 'net472'" />
    <!-- HintPath legacy DLLs, kept net472-only so the existing path uses
         exactly the binaries it always has -->
    <Reference Include="JetBrains.Annotations" Condition="'$(TargetFramework)' == 'net472'">
      <HintPath>..\Lib\JetBrains.Annotations.dll</HintPath>
      <Private>True</Private>
    </Reference>
  </ItemGroup>

  <ItemGroup Condition="'$(TargetFramework)' == 'net8.0-windows'">
    <!-- net8 equivalents via NuGet -->
    <PackageReference Include="JetBrains.Annotations" Version="2024.3.0" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\Dep\Dep.csproj" />
  </ItemGroup>
</Project>
```

**Source-code adjustments commonly needed:**

1. **`.Reverse()` on arrays** — net8 prefers `Span<T>.Reverse()` (void, in-place)
   over LINQ `Enumerable.Reverse()`. Use explicit `Enumerable.Reverse(arr)` so
   the same source picks the right overload on both targets.
2. **VS-tooling assemblies** (`Microsoft.ConcurrencyVisualizer.Markers`) — wrap
   in `#if NET472` blocks; net8 path becomes a no-op.
3. **Native deps with `$(PLATFORM)` substitution** (System.Data.SQLite) — switch
   to `Microsoft.Data.Sqlite` or `System.Data.SQLite.Core` NuGet package on net8.
4. **NHibernate** — versions ≥5.5 support net6+. Multi-target by package version
   if legacy needed.

## Status (2026-07-24, session: DIA-NN tutorial perf test CI failure -> DocDir move)

Resumed via `/pw-continue`. **The progress log had gone stale at the 07-23b `efe6f7824c` entry; HEAD had
advanced 8 commits** (all committed + dual-pushed to origin + `chambem2/pwiz-sharp`), logged only in
handoffs/memory until now:
- `3420b0e7aa` add `pwiz_tools/Skyline/tc-perftests.bat` (TeamCity entry point: build + stage + run
  `TestPerf.dll` and `TestTutorial.dll` with `perftests=on`; `SKYLINE_TEST_ARGS` escape hatch runs one scoped
  test instead). `3b6a1d552f` point the nightly smart-trigger's master Skyline perf/tutorial target at the net8
  config `ProteoWizard_SkylineWindowsNetPerfTutorialTests`.
- `7e0ec4487a`/`a8f0cac4b1` pin peptdeep to 1.5.0, re-record AlphaPeptDeep baselines, deterministic
  cross-machine fragment sort.
- `8a8653b6f2`/`102061978d`/`6ccaf02b29` vendor-reader finalizers (Bruker/Thermo/Sciex/Mobilion) + an
  undisposed-open regression guard in `VendorReaderTestHarness` (memory `reference_net8_vendor_reader_finalizers`).
- Main net8 CI (`ProteoWizard_SkylineWindowsNet`) green through #61 (`a8f0cac4b1`).

**DIA-NN tutorial perf test (`TestDiannSearchTutorial`) fixed -- committed + dual-pushed (`288e1d5f4b` fix,
`4aee5f1704` diagnostic removal; net change of the session = one line).** It failed CI-only in the new
perf/tutorial config (builds #0-#3 all red) with "Some results files are still missing" at the
ImportPeptideSearchDlg chromatograms page; passed locally. Root-caused with a scoped CI diagnostic
(`SKYLINE_TEST_ARGS=test=TestDiannSearchTutorial`, dumping doc-lib sources + FOUND/MISSING + CacheDir/DocDir
listings): the blib recorded **6 unfindable `.raw` source files** (the full 6-file ProteoBench set incl the
`_03` replicates the test never searches) while the 4 searched `.half.mzML` were correctly prefilled. The
`.half.mzML` subsets internally name their source `.raw` (`<sourceFile name="..._01.raw">`); `DiaNNSpecLibReader`'s
`stats.tsv` remap rewrites those to the disk name but only for runs in the current stats. The 6-run attribution
came from a **stale `diann-output-lib.parquet` in the test's persistent DocDir**
(`%LocalAppData%/SkylinePerfTests/DiannPerfDoc-stable`) on the CI agent from an earlier full-dataset run;
DIA-NN's `--use-quant --reanalyse` **reuses the output library and never rebuilds it** (deleting it just breaks
the search: "DIA-NN search did not produce a spectral library output" -- first fix attempt `93e296d58e`, reverted
`9562f64288`), so the poison was reused every run. Not a prefill bug; CacheDir was clean; LFQbench uses a
different DocDir. **Fix (Matt's call): `DocDir` -> `TestContext.GetTestResultsPath(@"DiannPerfDoc")` (ephemeral
per run)** so no stale lib persists; `.quant` + predicted library stay in the persistent CacheDir; the wizard's
real search of file[0] rebuilds the lib fresh. **Confirmed green: scoped CI build 4107764,
`TestDiannSearchTutorial-en` 0 failures / 1025s.** Memory: `reference_net8_diann_tutorial_docdir`.

**Still open (separate, NOT DIA-NN):** `TestDiaTtofDiaUmpireTutorial` red in the same perf run -- a `+/-2` count
drift (Expected 12221, Actual 12223, `DiaUmpireTutorialTest.cs:634` LibraryPeptideCount), an OOP-MSAmanda
re-baseline nit. No full net8 perf/tutorial sweep has run since the trigger repoint; the scoped/manual runs only
surfaced these two.

## Status (2026-07-23b, session: net8 BiblioSpec DIA-NN reader CI #57 fixes)

Resumed via `/pw-continue`; took the user's ask to fix CI build #57
(`ProteoWizard_SkylineWindowsNet` / PR #4178, commit `ff29f64323`), which had 2 failures
of 1715 -- both `DiannSearchTest` variants in the managed BlibBuild's DIA-NN reader.
(NOTE: this progress log had gone stale at 2026-07-15; true head/state was in
`ai/.tmp/handoff-20260723_net8_merge_aiconnector.md`. Sessions 07-17..07-23 were logged
only in handoffs, not here.)

**Both were faithful-port divergences from `DiaNNSpecLibReader.cpp` (introduced with the
`ff29f64323` parquet-report port, which only verified compilation). FIXED + VERIFIED,
committed + dual-pushed (`efe6f7824c`, origin + chambem2/pwiz-sharp).**

1. **`TestDiannSearch1_9_1` -- "not a parquet file, head: 46696c65".** DIA-NN 1.9.1 honours
   the literal `--out diann-output.parquet` filename Skyline passes (`DiannHelpers.cs:717`,
   version-agnostic) but writes a **TSV** report into it. The C# reader dispatched
   parquet-vs-TSV on the `.parquet` EXTENSION -> fed the TSV to Parquet.Net. cpp dispatches
   on CONTENT via `ParquetReader::is_parquet` (`arrow::OpenFile().ok()`, cpp:731/667). Fix:
   added `IsParquet()` content-sniff; routed `ReadDiannReport` / `HasRequiredHeaders` /
   `FindLibParquet` through it.
2. **`TestDiannSearch` (2.5.0) -- "could not find precursorId 'VTHAVVTVPAYFNDAQR3' in
   speclib".** DIA-NN reports precursors absent from the spectral library; cpp SKIPS them at
   the `psmByPrecursorId` lookup (cpp:1376-1380, PR #4189) and THROWS only at the
   `entryByModPeptideAndCharge` lookup (cpp:1418-1420). The port had these two swapped. Fix:
   restored cpp order.

One file (`DiaNNSpecLibReader.cs`, +53/-20). Verified green on net8 via real DIA-NN searches:
`TestDiannSearch`, `TestDiannSearch1_9_1`, and `TestDiannSearchEmptyResults1_9_1` (regression
guard) -- all 0 failures. A fresh CI run on `efe6f7824c` should clear #57's 2 failures.

**Perf-suite status re-checked (perf tests are NOT in the per-commit CI; build #57 = Test +
TestFunctional only).** Added `pwiz_tools/Skyline/tc-perftests.bat` (`3420b0e7aa`, origin +
chambem2) -- a TeamCity entry point that builds Skyline + TestPerf + TestTutorial + TestRunner
(+ best-effort native Hardklor), stages them, and runs `TestPerf.dll` and `TestTutorial.dll` with
`perftests=on` (each filtered to its own DLL so co-staged TestFunctional/TestUtil DLLs don't run).
Mirrors build.bat's flags/helpers + a SKYLINE_TEST_ARGS escape hatch; validated end-to-end (build ->
stage -> run). Next: create the TeamCity build config that calls it (`--i-agree-to-the-vendor-licenses
--automated`, optionally `--parallel`).

**CORRECTION to the 07-17/07-22 handoffs:** `TestSciexPrmCeOptimization` -- flagged there as THE open
product perf bug (wiff2 PRM `IsolationHalfWidth`=0) -- now PASSES on net8 (0 failures, ~25s, verified
twice this session). The SWATH isolation-halfwidth logic already in `WiffFile.cs:612` covers the PRM
case; `WiffFile.cs` was never the blocker by the time of the merge. Remaining perf non-passes are
environment-blocked only (`TestOrbiPrmArdia` = Ardia creds; `TestAlphaPeptDeepBuildLibrary` =
AlphaPeptDeep Python env), NOT product bugs. No fresh FULL perf sweep has been run yet -- the new
tc-perftests.bat is the way to get one under CI.

## Status (2026-07-15, session: DIA-Umpire FullFileset root-cause + rewirings + cache-reuse fix + engine experiment)

Resumed via `/pw-continue` from the 2026-07-14 DIA-Umpire recording handoff. Committed the held verified
batch first; then the FullFileset recording turned into a deep root-cause investigation.

**Committed + pushed (6 focused commits `97c34ee245..b9667e0769`, origin + `chambem2/pwiz-sharp`; reverted
`IsRecordMode=>false` first, built clean):** O(N^2)->binary-search clustering (`97c34ee245`), ilr progress
(`b8262875dd`), mz5->mzMLb+thread (`6da29cdbd0`), DIA-Umpire tutorial re-baseline + download-dialog +
per-instrument exemplar (`efa565bd4a`), EncyclopeDIA `#if` re-baseline (`993b3d9843`), Hardklor MSBuild
(`b9667e0769`). Only 2 of 4 DIA-Umpire tutorials recorded (TTOF + QE Extra); the 2 FullFileset variants were
still unrecorded (always timed out) -- root-caused below.

**ROOT CAUSE of the DIA-Umpire FullFileset 17%-gate timeout -- FIXED (uncommitted, CONFIRMED).** FullFileset
always timed out at `DiaUmpireTutorialTest.cs:601` (PercentComplete>17, ~24min). Instrumentation (external CPU
monitor + `dotnet-stack` of TestRunner during the stall) proved it was NOT the converter (each file converts
~3-5min); the killer was a ~13.5-min STALL BETWEEN files with TestRunner pegging one core in
`ProcessStreamReader.ReadLine`. Root cause: `pwiz_tools/Shared/CommonUtil/SystemUtil/ProcessStreamReader.cs`
buffered child output in a `List<string>` and the consumer pulled with `RemoveAt(0)` = O(N) -> O(N^2) draining
msconvert's verbose progress. **Fix: `List` -> `Queue` (Dequeue O(1)).** VERIFIED: all 6 files convert
back-to-back (~26min), the run passes the 17%-gate and reaches ValidateTargets. Genuine shared-CommonUtil bug,
both frameworks. (The `--verboseProgressPeriod` refactor below was from a DISPROVEN "progress flood" hypothesis
-- it does NOT fix the stall; the Queue fix does.)

**FullFileset DRIFT (finally measured, verify mode):** TTOF FullFileset library **33,997 (Jun-30 baseline) ->
16,447 (net8 OOP-MSAmanda) = ~52% drop** (`DiaUmpireTutorialTest.cs:634` LibraryPeptideCount). Whole-proteome
analog of the regular tutorial's ~25% drop; legitimate OOP-MSAmanda conservatism, amplified by the full
proteome. NOT recorded yet (verify-mode only; needs `IsRecordMode` + a full completing run).

**DIA-Umpire re-converts EVERY run (cache reuse broken) -- FIXED + VERIFIED (uncommitted).** The reuse check
(`DiaUmpireDdaConverter.cs:125`) rejected every cached `-diaumpire.mzML` -> ~25min reconvert each run. Diagnosed
with a temporary `### REUSE-CHECK` log: mismatch on `BoostComplementaryIon` (embedded `True` vs config `False`).
Root cause: the net8 msconvert-sharp `GetParameterMap()` (`pwiz-sharp/pwiz/src/Analysis/DiaUmpire/InstrumentParameter.cs:144`)
emitted only 23 of ~61 config params, omitting `BoostComplementaryIon` (+18); `GetConfigFromDiaUmpireOutput`
then read back the field DEFAULT (`true`) which never matched Skyline's explicit `false`. The engine RUNS
`false` correctly (`ParseBool` works -- NO result impact); only the mzML EMBED was incomplete. **Fix: added the
19 InstrumentParameter-backed params to `GetParameterMap`.** Verified standalone: output now embeds
`BoostComplementaryIon value="False"` (48 config userParams, was ~23). One-time reconvert after the fix ships
(old cache lacks the params), then reuse works.

**3 narrow rewirings applied + compile-verified (uncommitted; runtime verification deferred -- external deps):**
Koina RT (`Skyline.cs:GetScore`, removed stale `#if NET472` -> real `KoinaRetentionTimeModel.PredictSingle`);
Bruker timsTOF PRM metrics (`ExportMethodDlg.cs:ShowSchedulingGraph` un-gated -> managed
`Pwiz.Vendor.Bruker.PrmScheduling`, already referenced net8; needs a `.prmsqlite` template to verify); UNIFI
reader (`Reader_UNIFI` registered in `MsDataFileImpl.Vendors.cs` + `UNIFI.csproj` ProjectReference in
`ProteowizardWrapper.csproj`; needs WatersConnect creds to verify).

**`--verboseProgressPeriod` refactor (uncommitted, kept per Matt):** msconvert verbose progress iteration-period
is now a config option (default 100); Skyline sets 2500 (`DiaUmpireDdaConverter`, `#if !NET472`). Cuts search-log
spam 58k->2.3k lines but does NOT fix the stall. `Config.cs`/`Converter.cs`/`ArgParser.cs`/`ArgParserTests.cs`.

**Engine-comparison experiment (Matt: "what counts do MSFragger/Comet give?" -- TEMPORARY test edits, REVERT):**
MSFragger CRASHES on the pseudo-spectra (`ArrayIndexOutOfBoundsException` in `edu.umich.andykong.msfragger`) -- no
count. Comet runs but its **library is NOT FDR-filtered**: Percolator ran correctly (`testFDR 0.05` -> 87,264
target PSMs at q<=0.05 of 305,301 total, incl 64,920 at q>0.5), but the library got **161,235 peptides = unique
peptides of the ENTIRE unfiltered 305k-PSM set** -> garbage, NOT comparable to MSAmanda's FDR-correct 16,447.
The Comet->Percolator->library path drops the q<=0.05 cutoff (MSAmanda's path filters correctly); also ~8x
slower (68min vs 9min) building the bloated library. Cannot fairly compare Comet vs MSAmanda from this run; the
Comet library-FDR gap needs its own investigation (net8-specific? Comet-path bug? artifact of forcing Comet
through the MSAmanda-designed DIA-Umpire flow?).

**Uncommitted file inventory (12 files):**
- KEEPERS (verified / compile-clean product fixes): `ProcessStreamReader.cs` (Queue), `InstrumentParameter.cs`
  (GetParameterMap), `Skyline.cs` (Koina), `ExportMethodDlg.cs` (Bruker), `MsDataFileImpl.Vendors.cs` +
  `ProteowizardWrapper.csproj` (UNIFI).
- REFACTOR (keep per Matt): `Config.cs`, `Converter.cs`, `ArgParser.cs`, `ArgParserTests.cs`.
- MIXED -- `DiaUmpireDdaConverter.cs`: KEEP the `--verboseProgressPeriod 2500` arg; REVERT the `### REUSE-CHECK`
  `Console.WriteLine` diagnostic.
- REVERT ENTIRELY -- `DiaUmpireTutorialTest.cs`: all MSFragger/Comet experiment scaffolding (engine switch,
  deletion-block change, commented CutoffLabel asserts, download-dialog loop, LibraryPeptideCount print).

**Next session handoff**: For detailed startup protocol (revert scaffolding, split `DiaUmpireDdaConverter`,
commit plan, verification steps), read `ai/.tmp/handoff-20260715_net8_diaumpire_rootcause.md` before starting.

## Status (2026-07-14, session: DIA-Umpire net8 fixes + Sciex commit + Hardklor MSBuild)

Continued from the TestPerf-triage tail. HEAD started at `f320b4297a`.

**A -- Sciex SWATH isolation offsets COMMITTED (`3d3ef3cae6`, pushed origin + chambem2).** The held
`WiffFile.cs` fix (legacy-WIFF `IsolationLowerOffset/UpperOffset` computed from `FragmentBasedScanMassRange.IsolationWindow/2`,
cpp parity) verified green via `zzzNativeVsMz5_AbDiaChromatogramPerformanceTest` (native SWATH `.wiff` import,
0 failures) and committed on its own.

**D -- DIA-Umpire tutorial re-baseline: turned out to be 4 real net8 bugs, all fixed + verified.** Recording
`TestDiaTtof/QeDiaUmpireTutorial` baselines revealed the tutorials never completed on net8. Root causes + fixes
(all uncommitted; see memory `reference_net8_diaumpire_pipeline`):
  1. **mz5 writer missing** in pwiz-sharp (only mzMLb HDF5 writer wired). DIA-Umpire defaulted to `.mz5` spill ->
     NotImplementedException. Fix: net8 `DiaUmpireDdaConverter` routes `mz5`->`mzMLb` (per Matt: the other HDF5
     format, keep compact spill) at ctor + SetRequiredOutputFormat.
  2. **Progress ilr not wired**: `SpectrumListFactory.ParseDiaUmpire` passed no IterationListenerRegistry ->
     DIA-Umpire `[step N of M]` never printed -> Skyline's 17%-gate (`DiaUmpireTutorialTest.cs:593`) timed out
     (looked like a hang). Fix: thread `ilr` through `Wrap` to the diaUmpire builder + one shared registry in
     msconvert `Converter` ctor.
  3. **O(N^2) clustering (THE perf killer)**: `PeakCurveClusteringCorrKDtree.Run` linear-scanned all ~1.3M peak
     curves per target (flat list; cpp R-tree deferred "phase 5"). Fix: sort searchable by m/z once, binary-search
     each job's m/z window. Parity byte-identical. This is what let the tutorial finish (was stuck at step 5/7 of
     file 1 at 26 min).
  4. **Thread bump**: net8 sets `DiaUmpire.Config Parameters["Thread"]=ProcessorCount/2` (presets pin 1; managed
     slower than native). Verified deterministic (byte-identical multithreaded output). ~0 speedup until #3 fixed.
- After the fixes the TTOF tutorial RUNS to completion (~43 min, MSAmanda-dominated) and records. **Investigated the
  ~40% library-peptide drop thoroughly per Matt**: FDR verified correct (q<=0.05 applied, library max q=0.0499;
  0.01 would give 11234), DIA-Umpire faithful (471 pseudo-spectra = cpp reference), extraction stable
  (FinalTargetCounts ~unchanged). Full settings audit (net8 XML vs master in-process API): all match EXCEPT
  `WriteResultsTwice=true` which standalone MSAmanda 3.0.22.864 does NOT support (absent from its settings.xml +
  CLI). **Conclusion: legitimate OOP-MSAmanda re-baseline, not a bug.** Per Matt: **clobber the shared JSON**
  (net472 TestPerf retired on this branch), **record all 4 then commit**.
- Recording status: TestDiaTtofDiaUmpireTutorial.json recorded (TTOF, ~43 min). QE Extra hit a NEW re-baseline
  wrinkle: the hardcoded manual-review screenshot nav `FindNode("TDINQALNR")` (DiaUmpireTutorialTest.cs:768/774)
  failed -- TDINQALNR is no longer a net8 QE target. **Investigated the QE target divergence per Matt** (QE targets
  177->57, disproportionate to the library's 25% drop): NOT a target-selection bug -- digesting the 12-protein
  `DIA/target_protein_sequences.fasta` against the net8 library gives 84 candidate matches -> 57 non-ambiguous targets
  (the 84->57 gap = standard shared/ambiguous-peptide exclusion). The disproportion is uneven net8 SEARCH coverage of
  the QE tutorial's specific target proteins (esp. yeast: 0-1 lib peptides each), amplified by the tighter QE 10ppm
  tolerance -- same accepted OOP-MSAmanda cause. TDINQALNR is in the net8 QE library but correctly excluded as
  shared/ambiguous. **Fix: made the exemplar a per-instrument `AnalysisValues.ExemplarPeptide`** -- TTOF keeps
  `TDINQALNR` (unchanged, already recorded), QE uses **`AIDLIDEAASSIR`** (CLPB_ECOLI; verified excellent peak: both
  replicates, q 1.5e-5/2.7e-4, not truncated, b3 dominant 1.9e6, apex RT 48.16) + QE ChromatogramClickPoint ->
  (48.16f, 5.5e5f). QE re-run verifying. FullFileset exemplars (whole-proteome association) tentatively
  AIDLIDEAASSIR/TDINQALNR -- verify when recording (may be ambiguous in the full proteome). Then set
  `IsRecordMode=>false` and commit the batch.

**E -- Hardklor Jam->MSBuild port DONE (subagent, verified).** Submodules inited; corrected `Hardklor.vcxproj`
to match `Jamfile.jam` (XML_STATIC, casing, warning-disables, MultiByte, x64-only, self-extract zlib/expat
tarballs via bsdtar, v143+v145 fallback); wired `HardklorSearchEngine.cs` (PathEx.ResolveBundledExe),
`Skyline.csproj` Content, `build.bat` native step. `Hardklor.exe` builds (Release x64, 507 KB, runs). Remaining:
a full `build.bat Release` end-to-end check.

**Uncommitted batch** (record 3 more -> IsRecordMode false -> commit): DiaUmpireDdaConverter.cs,
SpectrumListFactory.cs, Converter.cs (msconvert), DiaUmpire.cs + PeakCluster.cs (pwiz-sharp), the 4 tutorial
.json baselines, DiaUmpireTutorialTest.cs/DiaUmpireVendorFormatTest.cs/EncyclopeDiaSearchTutorialTest.cs (held),
+ E's Hardklor files. Disk-guarded runs via `ai/.tmp/run_perf.sh`; persistent tutorial data at
`C:\test\Skyline\downloads\Tutorials\`. **2 of 4 recorded (TTOF + QE Extra); 2 FullFileset variants remain,
then revert `IsRecordMode=>false` and commit.**

**Next session handoff**: For detailed startup protocol (IsRecordMode-ON warning, FullFileset recording, exemplar
picking, build/stage/run recipe, commit plan), read `ai/.tmp/handoff-20260715_net8_diaumpire_recording.md` before
starting work.

## Status (2026-07-14, session: TestPerf triage)

### Worked the 7 TestPerf failure groups from the 2026-07-14 handoff via parallel investigation subagents

Resumed from `ai/.tmp/handoff-20260714_net8_testperf.md`. HEAD at start `56ecfc68b4`. Method (as the handoff
requested): spawned one read-only investigation subagent per failure GROUP (Agent tool, general-purpose,
background), each returning a precise fix spec; the master applied -> built (`dotnet build TestPerf -f
net8.0-windows -c Release`) -> staged (`Stage-Net8Tests.ps1 -Projects TestPerf`) -> ran each test serially,
**disk-guarded** (box has only ~24 GB free; the wrapper `ai/.tmp/run_perf.sh` pre-checks >=7 GB and kills the
run if free space drops under 5 GB mid-run, deleting `TestResults` between runs). All diagnostic fast-fails
used ~0 GB (they throw before extracting).

**Every group was a REAL bug; several were mislabeled in the handoff.** Fixes applied (uncommitted, all build
clean on net8):

- **Group 3-B `TestDiaNnPeakImputation` -- FIXED + VERIFIED (0 failures, 49s).** `Receiver.BeginInvoke`
  (`CommonUtil/SystemUtil/Caching/Receiver.cs`) posted to a SynchronizationContext whose UI thread had exited
  -> `InvalidAsynchronousStateException` on a background producer thread. Wrapped the `Post` itself in try/catch.
  Genuine robustness bug, net472-safe.
- **Group 7 `TestNonScoringTransitions` (mz5) -- FIXED + VERIFIED (0 failures, 14s).** Real error was
  `unsupported time unit in chromatogram: CVID_Unknown`, NOT the wraparound the handoff guessed. pwiz-sharp
  `Mz5ReferenceRead.FillParamContainer` APPENDED params where cpp `ReferenceRead_mz5.cpp:87` does clear-then-fill,
  so a pre-seeded unitless `MS_time_array` shadowed the real `MS_time_array(units=UO_minute)`. Added guarded
  `.Clear()` before each fill loop (cpp parity). Also fixed a genuine latent 32-bit SpectrumIndex wraparound
  omission in `Mz5SpectrumList.ReadUlongIndex` (cpp `SpectrumList_mz5.cpp:181-193`).
- **Group 3-A `TestDdaTutorial` -- FIXED + VERIFIED (0 failures, 142s full MSFragger search).** Data race
  (not the search): the UI thread (posted `ClickNextButton`->`EnsureRequiredFilesDownloaded`) and the test
  thread (`HasMissingDependencies`) both did check-then-`Add` on the shared global `Settings.Default.SearchToolList`
  (unsynchronized `MappedList`), corrupting the `Dictionary` ("same key Java already added"). Serialized the
  `SearchToolList` singleton (lock in the 4 mutators + the SearchToolType keyed accessors). Genuine product
  thread-safety bug, net472-safe, no async/await.
- **Group 2 `TestDiaPasefTutorial` -- FIXED + VERIFIED (0 failures, 57s, NO re-baseline).** Two layers:
  (1) `InvalidDataException: Isolation window Start > End` in the **ImportRanges UI path**: pwiz-sharp's combined
  non-centroid Bruker reader labels the mean-1/K0 array `MS_mean_ion_mobility_array` (MS:1002816) where C++ uses
  `MS_mean_inverse_reduced_ion_mobility_array` (MS:1003006); Skyline's `GetIonMobilityArray` only recognized
  1003006 -> `IonMobilities` null -> `isPasef=false` -> diaPASEF sort skipped -> `CalculateMargin` fabricated
  112.5 margins -> MEASUREMENT windows collapse. Fix (per Matt: support 2816 IN ADDITION to 3006): net8 wrapper
  `MsDataFileImpl.PwizSharp.GetIonMobilityArray` falls back to MS:1002816 for inverse_K0.
  (2) That unmasked a `ValidateCoefficients` mismatch (mProphet weights). Determined NOT a re-baseline but
  **Gap A**: pwiz-sharp `Reader_Bruker` never implemented `PassEntireDiaPasefFrame`, so net8 emitted per-window
  diaPASEF spectra where net472/C++ emit ONE whole-frame combined spectrum per frame -> subtly different feature
  values -> the LDA coefficients flipped. **Per Matt's call, fixed properly (not re-baselined): implemented
  whole-frame diaPASEF in pwiz-sharp** (6 Bruker files; ~200 lines, no new P/Invoke -- the SDK surface was
  already bound). `TdfData.cs` now builds a per-windowGroup active-scan/isolation cache and emits one whole-frame
  combined spectrum (all active scans' peaks + per-peak 1/K0, optional scanning-quadrupole isolation arrays)
  when `passEntireDiaPasefFrame`; per-window path unchanged for the flag off. Coefficients returned to the
  committed values -> **net8 diaPASEF extraction is now byte-identical to net472** (and the latent
  overlapping/diagonal-scheme misassignment risk is closed). Diagonal auto-detect left as a documented TODO in
  `Reader_Bruker` (a plain bool flag can't distinguish explicit-false from default; standard diaPASEF sets it
  explicitly so the tests don't need it). Gap B (`isolationWidth>0` guard) inert for this data -- not needed.
- **Sciex SWATH `TestDiaUmpireWiffFile` isolation-range gap -- FIXED (verify running).** Same class, different
  vendor: legacy `WiffSpectrum.IsolationLowerOffset/UpperOffset` (pwiz-sharp `Vendor/Sciex/WiffFile.cs`) were
  hardcoded to 0, so a SWATH `.wiff` emitted an isolation target but no offsets -> Skyline threw "Missing
  isolation range for isolation target 412.5 m/z". Now computes `FragmentBasedScanMassRange.IsolationWindow/2`
  from the experiment's first `MassRangeInfo` (cpp `WiffFile.cpp:766-776` / `SpectrumList_ABI.cpp:200-208`);
  wiff2 path already did this. net8-only, no new SDK binding. (The download-dialog mechanical fix itself is
  verified working -- this was a separate reader gap behind it.)
- **Group 5 `TestBullseyeSharp` -- FIXED + VERIFIED (0 failures, 38s).** Three layers: (1) managed
  `bullseye-sharp` `CKronik2.cs` wrote net8 shortest-round-trip floats -> pinned the 5 `.bs.kro` float columns
  to `G7`; (2) residual `.bs.kro` diffs were 7th-sig-fig drift (net8 vs net472 FMA) -> added an opt-in
  `relativeTolerance` param to `AssertEx.AreEquivalentDsvFiles` (default 0 = unchanged for other callers),
  test passes `5e-6`; (3) the `.ms2` `I TIC` line differed by shape (net472 `%.7g` "177994"/"1.130326e+07"
  vs net8 "177993.96875"/"11303264") -> extended `AssertEx.FieldsEqual`'s `allowForTinyNumericDifferences` to
  accept a mixed integer-vs-decimal/scientific field within a tight RELATIVE tolerance (1e-5), small values
  still strict. All net472-safe.
- **Group 1 DIA-Umpire download dialog (5 tests) -- mechanical fix applied.** net8 downloads MSAmanda on demand
  (a modal "Download MSAmanda" MultiButtonMsgDlg shown synchronously by `ClickNextButton`); the DIA-Umpire
  TestPerf files had no dialog handling. Added async-click + dismiss (`DiaUmpireTutorialTest.cs`,
  `DiaUmpireVendorFormatTest.cs`). `TestDiaUmpireWiffFile` needs no re-baseline; the 4 tutorials will need JSON
  re-recording (net8 OOP MSAmanda more conservative) -- pending run.
- **Group 6 `TestEncyclopeDiaSearchTutorialDraft` -- `#if`-conditional re-baseline applied** to
  `{362,684,684,4786}` (net8 C#-ported NNLS demux is slightly more conservative; net472 keeps
  `{369,719,719,5058}`). Verify pending.
- **Group 4 Hardklor -- DEFERRED per Matt.** Native `Hardklor.exe` isn't in managed net8 staging; a prebuilt
  x64 exe exists in sibling checkouts (`pwiz/.../Executables/Hardklor/obj/x64/Hardklor.exe`, PE32+ x64) if we
  revisit bundling.

**Verified GREEN this session: Group 3-B, Group 7, Group 3-A, Group 5** (+ Group 2 primary crash fixed).
Group 2 coefficient layer determined a legitimate re-baseline (NOT Gap A -- extraction verified correct; the
net472-C++-whole-frame baseline vs net8-managed-per-window reader shifts feature values enough to flip the
mProphet LDA coefficients; `ValidateCoefficients` is an over-strict exact assert). Re-baseline needs a
per-framework expected-values gating decision (recurring: PASEF + Group 1 tutorials) -- `#if NET8_0_OR_GREATER`
-> `.net8.json` (preserve net472) vs clobber the shared JSON if net472 TestPerf is retired on this branch.
**COMMITTED + PUSHED (5 focused commits `270358261f..f320b4297a`, origin + mirrored to chambem2/pwiz-sharp):**
mz5 (Group 7), Receiver (3-B), SearchToolList (3-A), bullseye (5), whole-frame diaPASEF (2). All verified green.

Still uncommitted / in progress (per Matt "commit verified batch, then continue"):
- **Sciex SWATH isolation-offset fix** (`Vendor/Sciex/WiffFile.cs`) -- genuine reader-parity fix (verified the
  "Missing isolation range" error is gone), but held: no end-to-end green test yet (`TestDiaUmpireWiffFile` now
  hits a 3rd layer -- a pre-existing net8 "A FASTA file is required for the DDA search" wizard page-flow issue at
  DiaUmpireVendorFormatTest.cs:265, unmasked by the isolation fix; needs its own investigation). The download-
  dialog mechanical fix (DiaUmpireTutorialTest.cs + DiaUmpireVendorFormatTest.cs) is verified working but held
  with the tutorials.
- **Group 6 EncyclopeDIA** `#if` re-baseline applied but held pending the count-guardrail check (its C# NNLS
  demux is a deliberate ~0.1-tol reimplementation, so likely a legit re-baseline unlike PASEF -- verify counts).
- **Group 1** 4 DIA-Umpire tutorials -- need count re-baselines (record runs + per-framework gating decision).
- `TestDiaPasefFullDatasetExtra` -- expected fixed by the committed whole-frame change; verify.
- Group 4 Hardklor deferred. Disk-guarded run wrapper: `ai/.tmp/run_perf.sh`.

**Next session handoff**: read `ai/.tmp/handoff-20260714_net8_testperf_tail.md` for the detailed startup
protocol + the remaining tail (Sciex fix commit-when-green, WiffFile FASTA logged-diagnostic, EncyclopeDIA
guardrail run, DIA-Umpire tutorial re-baselines + the per-framework gating decision). The working tree carries
4 intentional held files (the in-progress tail) -- do NOT discard them.

## Status (2026-07-08, session 4)

### Cleared the ENTIRE diagnosed-failure shortlist -- 9 net8 tests GREEN (overnight autonomous batch)

Worked the remaining diagnosed-failure shortlist from the session-3 handoff to zero. Fixed and committed
9 tests (each: reproduce -> root-cause -> fix -> verify 0-failures -> focused commit, all pushed to `origin`
+ mirrored to `chambem2/pwiz-sharp`). `TestJsonToolServer` was already passing (session-3 diagnosis didn't
reproduce), so it was dropped. Commits `8787075894..288c8647d7`.

**The first 5 I did directly; the last 4 (WatersConnect, Koina, ConsoleImportEi, ConstantNeutralLoss) I
delegated to 4 parallel investigation subagents** -- they read+reasoned in parallel and ran read-only
diagnostics (repro + `dotnet-dump` stack captures) on the current staged build, serialized by a shared
file-lock semaphore (`skyline-coord/with-skyline-lock.sh`, atomic `mkdir` lock, 30-min stale breaker) so
only one offscreen Skyline/TestRunner ran machine-wide at a time. Subagents did NOT edit tracked files or
build -- each returned a precise fix spec; the parent applied -> built -> staged+ran under the same lock ->
committed, iterating via SendMessage. This parallelized the expensive investigation while keeping builds
collision-free. Two subagents needed a second SendMessage round (WatersConnect: the error-scenario layer;
ConsoleImportEi: the reader was proven correct, redirected to the extraction layer). **Reusable finding:**
a stale incremental build can silently skip a just-edited file (WatersConnect Edit 5/6 didn't compile on
net8 but a stale `CommonFileDialogs.dll` made a "verify" pass look like a no-op) -- when a fix "does
nothing", force a clean rebuild of the edited assembly before trusting the result.

**Fixed + verified (first 5, done directly):**
- `TestTriggeredAcquisition` (`8787075894`, pwiz-sharp) -- an mzML integer array carrying a numpress term
  (intensity array tagged "32-bit integer" + "MS-Numpress positive integer / Pic") threw
  `NotImplementedException` in `BinaryDataEncoder.DecodeIntegers`. cpp parity (IO.cpp:2461-2478): for mzML
  (not mzMLb) a numpress array's integer type term is meaningless (numpress defines word size + format), so
  it's remapped to float and decoded as doubles into a BinaryDataArray. `MzmlReader.ReadBinaryDataArray`
  now flips `isInteger=false` when numpress is set on the base64 path (gated on no external HDF5 source).
- `TestImportFullScanNarrowScanWindows` (`a53855026c`, pwiz-sharp) -- HDF5 1.10's native H5Fopen/H5Fcreate
  take an ANSI `const char*`, so the Unicode "Utest" dir mangled the path and the open failed though
  File.Exists saw it. Feed `H5F.open`/`H5F.create` the 8.3 short name via `Filesystem.GetNonUnicodePath`.
- `TestDissociationMethod` (`1326a828c9`, pwiz-sharp + sandbox) -- `CVTermInfo.ShortName` was stubbed to
  return the full Name, and the sandbox MsDataFileImpl read the dissociation method via `.Name`, so it came
  through as "collision-induced dissociation"/"beam-type..." where the legacy pwiz.CLI reader produced
  "CID"/"HCD". Skyline's SpectrumClassFilter matches the short form -> net8 filter dropped every spectrum ->
  TryLoadChromatogram false. Implemented `ShortName` = shortest of Name + ExactSynonyms (cpp cv.inl:54; the
  OBO already loads "CID"/"HCD" as EXACT synonyms) and routed the two mechanical-port `.Name` sites
  (`GetCvParamName`, dissociation method) that stand in for cpp `shortName()` back to `.ShortName`.
- `TestSynchSiblingsSmallMolecules` (`74b9a39baa`, test-only) -- NOT a product regression. The molecule
  dialog stores the small-molecule adduct in formula form `[M+H]` (`EditCustomMoleculeDlg.OkDialog` ->
  `Adduct.NonProteomicProtonatedFromCharge`), not the proteomic charge-only `Adduct.SINGLY_PROTONATED`.
  The comparison passed on net472 only because MSTest v2's `Assert.AreEqual` used `object.Equals` ->
  `CustomMolecule.Equals` (ignores adduct); MSTest v3 (net8) uses `EqualityComparer<T>.Default` ->
  `IEquatable<CustomIon>.Equals` (compares adduct). Fix: build the expected CustomIon with `[M+H]`.
  **Reusable finding:** any net8 `Assert.AreEqual(a,b)` that "should be equal but isn't, same ToString" is
  likely MSTest v2->v3 honoring IEquatable where v2 used object.Equals -- check for a type whose
  `IEquatable<T>.Equals` is stricter than its (possibly inherited) `object.Equals`.
- `TestPasteMolecules` (`35a895b2e5`, product + test) -- net8 float/double `ToString()` shortest-round-trip
  in the small-molecule paste-validation errors (`delta "402.99658"` vs `"402.9966"`, mass
  `"503970013.01879007"` vs `"503970013.01879"`). Product fix: `SmallMoleculeTransitionListReader` m/z msg
  floats -> G7; `CustomMolecule.Validate` mass double -> G15. Test builds its expected strings through an
  `Mz7` helper applying the same G7 so they match on both frameworks. **A pure test-value change can't work
  here** -- the product's computed `(float)(mzCalc-mz)` and a rounded literal are adjacent floats that
  render differently, and net472 vs net8 differ, so the framework-agnostic fix is deterministic product
  formatting (G7 float / G15 double) + the test formatting its expected the same way.

**Fixed + verified (last 4, via parallel subagents):**
- `TestKoinaSkylineIntegration` (`1206df1689`, Skyline) -- NOT the Grpc.Net stall the handoff guessed. A
  `dotnet-dump` of the hung process showed the test thread parked in `WaitForConditionUI` with NO prediction
  or gRPC thread running. `GraphSpectrum.UpdateKoinaPrediction` (+ its `_koinaRequest` field + the CE-toolbar
  update) were still `#if NET472` mechanical-port stubs, so net8 returned null and never called `Predict()` ->
  the predicted spectrum never appeared -> infinite wait. Model/Koina is fully compiled on net8 and the
  already-working `KoinaPingRequest` proves the fake client + Grpc.Net wiring are fine, so the guards were
  stale; removed them.
- `TestWatersConnectExportMethodDlg` (`f06835cd5d`, CommonMsData + CommonFileDialogs + test) -- three layers:
  (1) test registered an empty WatersConnect account (blank username); IdentityModel 7 validates UserName
  client-side and throws before the token request reaches the mock -> give the dummy account a username.
  (2) `Authenticate()` runs on the UI thread; blocking `RequestPasswordToken/RefreshTokenAsync().Result`
  deadlocked the WinForms SynchronizationContext -> `Task.Run(...).Result`. (3) two `BaseFileDialogNE`
  blocks were stale `#if NET472` stubs (the single-account nav gate unconditionally navigated instead of
  gating on `SupportsMethodDevelopment`; the auth-exception handler threw `NotSupportedException`); restored
  the net472 logic and un-guarded the `pwiz.CommonMsData.RemoteApi.WatersConnect` using so it resolves on net8.
- `ConstantNeutralLossTest` (`ba405544d2`, pwiz-sharp Agilent) -- NOT an Agilent reader hang. A dump showed
  the load threw `NullReferenceException` (which Skyline's ImportResults/WaitForConditionUI silently turns
  into a hang). `ChromatogramList_Agilent.FillTic` guarded array creation on `times.Count > 0`, so the empty
  MS1-only TIC of an all-MS2 CNL `.d` got no time/intensity/ms-level arrays -- but the wrapper's
  `GetChromatogram` dereferences `GetTimeArray().Data` unconditionally. cpp always emplaces the arrays when
  binary data is requested; dropped the guard. (Also: the Agilent `.d` vendor test data was unextracted --
  `Reader_Agilent_Test.data.tar.bz2` -- a prerequisite for every Agilent test on this checkout.)
- `ConsoleImportEiTest` (`288c8647d7`, pwiz-sharp mzXML) -- the reader was PROVEN correct (decodes all 4572
  spectra); the failure was in extraction. `MzxmlReader.ReadOneScan` built the scan window only from
  startMz/endMz; this Agilent GC-EI mzXML omits those but carries lowMz/highMz, so the scan got no scan
  window -> Skyline couldn't synthesize the all-ions MS1 precursor (GetMs1Precursors needs ScanWindows) ->
  no isolation window -> empty ChromInfoList on every transition -> `t.Results[0][0]` IndexOutOfRange. cpp
  (SpectrumList_mzXML.cpp:483-490) falls back to lowMz/highMz; matched it.

**Full parallel run (post-fixes, `parallelmode=server workercount=8`, 1 host + 7 Docker):** 978 tests,
22 failures (97.7%, down from 45 / 95.4% in the 07-06 run). Had to fix a net8 TestRunner coordinator crash
first (`f10f89e4cd`): in parallel-server mode the per-worker connection threads wrote an unsynchronized
shared StreamWriter -> racing `StreamWriter.WriteLine` throws IndexOutOfRange on net8 -> the worker thread's
catch does `Environment.Exit`, aborting the whole run at ~375/978. Serialized the two WriteLine calls with a
lock (counters already Interlocked). Host-verified all 22: **14 are container/language false-failures**
(pass on host -- incl. my `TestImportFullScanNarrowScanWindows` + `TestPasteMolecules`; Docker workers run
non-en languages and a `c:\pwiz` mount where 8.3 short names are off), **2 are documented headless-hangers**
(`TestLabelLayoutDeterminism`, `TestPeakBoundaryCompare`), and **6 genuinely fail on the host in isolation --
NONE touch this session's changed files** (verified: no stack hits): `TestCommandLineExportThermoMethod`
(Thermo method export, the known double shortest-round-trip class), `TestToolService` (external-tool
config/download, environmental), `TestDocumentSharing`, `TestFilesTreeForm`, `TestMiscForms`,
`TestReplicatePivotGrid`. These 6 are the next shortlist; none are regressions from the 9 fixes.

**net8 build/stage/run recipe used** (host, offscreen), unchanged from session 3:
`dotnet build TestFunctional\TestFunctional.csproj -f net8.0-windows -c Release -p:IAgreeToVendorLicenses=true`
-> `pwsh -File .\Stage-Net8Tests.ps1 -Configuration Release -NoRuntime` -> from `bin\staging-net8\Release`:
`.\TestRunner.exe test=A,B,C parallelmode=off loop=1 language=en offscreen=on`. Wrap TestRunner in
`timeout <s>` when probing a possible hang; kill leftover `TestRunner.exe`/`Skyline-daily.exe` between runs.

## Status (2026-07-08, session 3)

### Committed the Tier-1 TestFunctional batch + drove TestManageLibraryRuns and TestLibraryBuild GREEN

Resumed on `Skyline/work/20260612_net8_port`. Everything committed + pushed to `origin` and mirrored to
`chambem2/pwiz-sharp` (PR #4178). 12 commits this session (through `6955d14f6f`).

**Tier-1 TestFunctional batch (7 commits `88621b8a90..7c6737a1a2`)** -- the prior session's uncommitted
8-file diff, re-verified (build clean + 5 representative tests 0 failures) and split into focused commits:
net8 Uri text-filter CONTAINS/STARTS_WITH (DataSchema IsValueType gate); Immediate Window WriteLine(string);
triggered-method export G15 + relative-exe ResolveToolPath; Parquet.Net 4.25.0; WinForms ModalMenuFilter
GC-leak release; SkylineCmd apphost companions; DdaSearch MSAmanda download path.

**TestManageLibraryRuns (`c04a760b04`)** -- real net8 lock race. DeleteDataFiles held the redundant-.blib
SQLite write connection across the BlibFilter shell-out; net8's provider keeps the handle where net472
released it -> BlibFilter File.OpenRead sharing violation ("cannot be opened"). Fixed by closing the
redundant connection before the Filter call. (+ BlibFilter.cs UTF-8 stream encoding to match BlibBuild.)

**TestLibraryBuild -> GREEN (5 commits)** -- a chain of independent net8/pwiz-sharp parity gaps, each
surfaced only after the previous was fixed:
- Mascot native deployment (`7846f50c6b`): MascotShim.dll + msparser.dll + msparser-config were not
  flowing from BlibBuild's runtimes\win-x64\native into the Skyline/test bins (the `**\*` Content glob
  drops files whose Link lands under runtimes\...\); deploy them flat next to BlibBuild.exe.
- Mascot score-filter parity (`749deef203`): managed MascotResultsReader let the shim pre-filter, so an
  all-filtered .dat created no source-file bucket and never emitted "No matches passed score filter";
  open the shim permissively and filter in managed after bucket creation (cpp MascotResultsReader.cpp:226).
- PwizReader native-id mismatch warning (`4ef8235fde`): ported SpectrumList.CheckNativeIdMatch
  (MSData.cpp:1170) to ISpectrumList/SpectrumListBase + the "Mismatch between spectrum id format" warning
  (PwizReader.cpp:224) in PwizSharpSpecFileReader.
- BlibMaker file-share (`7bfae56d3a`): VerifyFileExists probed with File.OpenRead (FileShare.Read), which
  cannot coexist with a writer; cpp uses std::ifstream (shares R+W) -> FileShare.ReadWrite. Fixes the
  score-types hang when Skyline holds an input .blib open as a loaded document library.
- BlibBuild/BlibFilter UTF-8 output (`6955d14f6f`): neither tool set Console.OutputEncoding, so under
  Skyline's non-UTF-8 console the non-ASCII input paths (Unicode "Utest" test dir + CJK .blib names) were
  written in the ANSI code page and read back mangled as UTF-8 -> the score-type result key failed to
  match the input file -> Build Library dialog hung. Set Console.OutputEncoding=UTF8 at both Main entries.

TestLibraryBuild now passes 0-failures/46s; regression-checked TestManageLibraryRuns + TestImportPeptideSearch
+ TestExportSpectralLibrary (all green, no collateral damage). **Reusable finding:** any BlibBuild/BlibFilter
shell-out over a Unicode path needs BOTH (a) the input not held by Skyline with a write-incompatible share
mode, and (b) UTF-8 console output on the child; this "held handle + non-UTF-8 child console" pair recurs
wherever net8 Skyline shells out to a managed CLI tool over non-ASCII paths.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260708_net8_libbuild_green.md` before starting work.

## Status (2026-07-06)

### Consolidated everything onto net8 + committed the whole port (branch is PR-ready)

The net8 branch (`Skyline/work/20260612_net8_port`) is now the single consolidated branch for PR #4178
("Port ProteoWizard core to .NET 8"). All previously-uncommitted work is committed in clean area commits:
- `8c2bf26972` net8 TestFunctional fixes + DOTNET_ROOT apphost resolution (this session's 9 files)
- `dc12600f3a` zh-CHS -> zh-Hans localization rename (332 files)
- `6961871dae` net8 test infrastructure + parallel runner
- `0e1cc18285` TestFunctional/TestData failure fixes (NHibernate/ProteomeDb/ChromLib/docs)
- `4149052421` Skyline/Common csproj multi-target + core net8 fixes
- `235a2aaf4c` merge of chambem2/pwiz-sharp WIP (ChargeFromIsotope parent cache + native tests + build infra)

net8 already contained the full pwiz-sharp port (via the earlier `c5ae2fd` merge of chambem2/pwiz-sharp), so
a single PR from net8 carries pwiz-sharp port + net8 Skyline port + the chambem2 WIP. The chambem2 WIP itself
was committed (`ec44c07ddc`) after validating the mascot BiblioSpec tests (15/15 green; the two mascot
`.check.observed` "discrepancies" were stale outputs, not real failures).

**BlibBuild deployment reconciliation (option A):** the merge conflicted on `Skyline.csproj` + `BlibBuild.cs`
because the two branches used different managed-BlibBuild layouts -- net8 deploys `BlibBuild.exe` to the base
dir (`CopyBiblioSpecTools` + `AppContext.BaseDirectory`), chambem2's newer WIP used a `BlibBuild-sharp/`
subdir. Resolved to net8's base-dir approach: took net8's `Skyline.csproj`/`BlibBuild.cs` and reverted the 3
installer files to net8's versions. Verified 0 `BlibBuild-sharp` references remain (consistent). chambem2's
unrelated work (ChargeFromIsotope cache, native tests, pwiz-sharp build/test infra) preserved.

**Follow-ups (not blocking):** (1) `TestExportMethodDlg` -- the ShowSchedulingGraph hang fix is committed but a
residual `double`-shortest-round-trip diff in a triggered export remains (same class as the G7/GetProductMz
fixes; needs the column pinned). (2) A full net8 suite run before flipping PR #4178 out of DRAFT would be the
belt-and-suspenders check -- the pieces were verified individually, and the final merge added only native/build
files (no Skyline .NET build inputs).

### Two remaining 750s hangs: one fixed, one root-caused (deeper)

The full run actually had FIVE ~750-790s tests (not two): UpgradeErrors (fixed earlier), LabelLayout
(headless-skip), TestPeakBoundaryCompare (passes single-process = parallel-only), plus these two genuine
single-process hangs:

- `TestExportMethodDlg` -- HANG FIXED. `ExportMethodDlg.ShowSchedulingGraph()` had its ENTIRE body wrapped
  in `#if NET472`, so on net8 it was a no-op -> the graph dialog never opened -> `ShowDialog<ExportMethodScheduleGraph>`
  hung 720s (ThermoTsqTest, ExportMethodDialogTest.cs:137). Only the Bruker timsTOF scheduling-METRICS
  gathering is net472-only (native PrmScheduling SDK); the graph itself + non-Bruker scheduling work on net8
  (`ExportMethodScheduleGraph` isn't gated -- uses the `Pwiz.Vendor.Bruker` net8 namespace). Fix: declare
  brukerTemplate/brukerMetrics as null outside the `#if`, keep only the metrics computation net472-gated, and
  run the dialog display on both frameworks. Verified: 720s hang -> 10s. **Caveat:** the fix unmasks a
  pre-existing latent failure in the same test -- a double shortest-round-trip diff `0.9456002044677735`
  (net8) vs `0.945600204467773` (net472) in a triggered Thermo method export. Same class as the G7/GetProductMz
  fixes; needs the specific exporter column pinned (a double written via bare `.ToString(CultureInfo)`). Not
  yet fixed -- follow-up.
- `TestImportPeptideSearch` -- HANG FIXED (in the managed BlibBuild). Hung at ImportPeptideSearchTest.cs:385
  `WaitForConditionUI(IsNextButtonEnabled)` after adding SpectrumSources.blib on the Build Spectral Library
  page. Chain: `BuildLibraryGridView.FilePaths` setter -> BackgroundWorker -> `GetScoreTypes` -> runs the
  managed `BlibBuild.exe -s -t` score-types query. Root cause (reproduced directly): the C# port's
  `BlibBuilder.DispatchReader` special-cased `.blib` to ALWAYS call `TransferLibrary`, which uses the output
  `BlibMaker.Db` -- but in score-lookup mode that Db is never opened, so it threw "Db not open. Call OpenDb
  first." The error flagged the file with a score-type error -> `Grid.IsReady` stayed false -> Next never
  enabled -> 720s. Fix (`pwiz-sharp/Tools/BiblioSpec/src/BiblioSpec/BlibBuilder.cs`): mirror cpp
  `BlibHandler::getScoreTypes` (BlibBuild.cpp:49-72) -- in score-lookup mode a `.blib` opens itself read-only
  and reports its own distinct `ScoreTypes` (fallback UNKNOWN), never touching the output Db. New
  `GetBlibScoreTypes(iLib)` + branch on `IsScoreLookupMode`. Verified: `BlibBuild.exe -s -t` on a .blib now
  emits a clean score-type row (no "Db not open"), and **TestImportPeptideSearch passes in 12s** (was 720s).
  NOTE: fix lives in the nested pwiz-sharp repo -- commit there separately.

Diagnostic used: temporary `SKYLINE_TRIAGE_FAST` env gate capping GetWaitCycles in TestFunctional.cs so hung
WaitFors fail in ~20s with their "Open forms" message. Reverted after triage.

### net8-candidate failures: triaged the 10, fixed the genuine format-class ones

Ran the 10 "genuine net8 candidate" failures single-process on the host. 3 pass single-process =>
parallel-flaky, set aside (`TestPeakBoundaryCompare`, `TestCrosslinkChromatograms`, `TestLocalizedResources`).
7 genuinely fail; root-caused all, fixed the two clean format-class ones (verified passing, no regression in
the export tests):

- `TestPeakScoringModel` -- FIXED. **Negative zero**: `TargetDecoyGenerator.GetPercentContribution` returns
  `meanWeightedDiff / meanDiffAll`, and `meanWeightedDiff` is `-0.0` when `meanDiff` is exactly 0 and the
  weight is negative (IEEE `0.0 * -x`). net8 formats that as "-0.0%" where net472 dropped the sign. Fix:
  normalize `-0.0`->`0.0` at the source (`return pct == 0 ? 0.0 : pct`) -- numerically identical, fixes grid +
  CommandLine displays.
- `TestOptimization` -- FIXED. **double shortest-round-trip** (the double analog of the chromatogram G7 fix):
  product m/z `524.216337` (net472) vs `524.2163370000001` (net8). Root cause is shared:
  `AbstractMassListExporter.GetProductMz(mz, step)` adds the optimization-step offset which re-introduces
  full precision, and ~8 export call sites `.ToString()` it raw. Fix: `PersistentMZ`-round inside
  `GetProductMz` (single point, covers all callers).

**Remaining 5 genuine failures -- deeper root-cause round:**
- `TestSynchSiblingsSmallMolecules` -- ROOT-CAUSED (needs owner decision, not a quick fix). Diagnostic dump
  showed identical formula+masses; the diff is the **adduct representation**: `compareIon` (built with
  `Adduct.SINGLY_PROTONATED`, the proteomic charge-only `z=1`) stays `'1'`, but the small-molecule the dialog
  adds now normalizes to the formula adduct `'[M+H]'` on net8 (net472 kept `'1'`). `Adduct.Equals` correctly
  distinguishes them. Need product-owner call on whether net8's `[M+H]` (arguably correct for a small molecule)
  or net472's `1` is right, and where the add-molecule pipeline diverges. Likely fix is either a normalization
  alignment or updating the test's expected adduct.
- `TestSkylineCmdInEmptyDirectory` -- ROOT-CAUSED (fiddly test-infra fix). Test copies ONLY `SkylineCmd.exe`
  to an empty dir and runs it expecting SkylineCmd's own "Skyline-daily.dll not found" error. On net8 the bare
  apphost dies at the runtime level ("application to execute does not exist: SkylineCmd.dll") before any managed
  code runs (the net8-adapted expected strings at SkylineCmdTest.cs:139-140 assume it got that far). Fix: copy
  the full apphost bundle (.exe + .dll + .runtimeconfig.json + .deps.json) minus Skyline-daily.dll so SkylineCmd
  launches (DOTNET_ROOT already handled by the TestRunner fix) and produces the intended error.
- `TestObjectFilterOperations` (CommonTest) -- `Uri` `OP_STARTS_WITH "urn:t"` returns 0 not 2. `StringFilterOperation.IsValidFor`
  requires the handler be `IFilterHandler.IContains`; on net8 the `Uri` column's handler apparently isn't, or the
  Uri->string path in `StartsWith` differs. Not yet fully root-caused.
- `TestPasteMolecules` -- "Unexpected value in paste dialog error window"; paste-validation error text mismatch. Signature only.
- `TestCommandLineNoJoin` (TestData) -- `Assert.IsTrue` on a `.raw` path existing after import. Signature only; possibly data/import.

### Full parallel run: 933/978 pass (95.4%) + two 750s hangs resolved

After the DOTNET_ROOT fix + environmental skip list, the full Test+TestData+TestFunctional parallel run
completed: **978 run, 933 pass, 45 fail (95.4%)**, ~50 environmental tests skipped, 0 apphost errors, 1
worker death (`TestDocumentSharing`, passed on requeue). The 45 failures break down as ~16 environmental
stragglers the skip-regex missed (Console*Import, Wiff, Thermo-method, Midas, EI -- several are the TODO's
known-hard items), ~6 known-flaky-parallel (07-04 list), ~5 already-triaged fast-failures, ~2 hangs (below),
and ~10 genuine net8 candidates (TestOptimization, TestPeakScoringModel, TestPasteMolecules,
TestObjectFilterOperations, TestSynchSiblingsSmallMolecules, TestPeakBoundaryCompare, TestCrosslinkChromatograms,
TestCommandLineNoJoin, TestSkylineCmdInEmptyDirectory, TestLocalizedResources). Full run log:
scratchpad/net8_parallel_run3.log.

**Two 750s hangs resolved (different in kind):**
- `UpgradeErrorsFunctionalTest` -- REAL net8 bug, FIXED. `UpgradeManager.updateCheck_Complete` special-cased
  `TrustNotGrantedException` (route to UpgradeDlg + manual install link) only under `#if NET472`, because the
  `System.Deployment.Application` `using` was net472-only. On net8 the trust case fell through to the generic
  "Failed attempting to check for an upgrade" MessageDlg, which the test didn't expect -> desync -> 720s
  timeout. Fix: un-guard the `using` (resolves to the net8 stub in SkylineNet8Stubs.cs) and the special-case
  block. Safe for production: net8 uses `NullDeployment` (IsNetworkDeployed=false, never throws this), so the
  path is only reachable by tests that inject a deployment. Now passes in 2s.
- `TestLabelLayoutDeterminism` -- NOT a net8 bug. Passes on the host single-process in 5s; hangs ONLY headless
  (Docker container). The GroupComparisonAvoidLabelOverlap layout (`LabelLayoutRunner`) needs real text metrics
  from `Graphics.FromHwnd(IntPtr.Zero)`; in a headless container those return zero-height, so the runner bails
  at its `if (!heights.Any(h => h > 0)) return;` guards before applying a layout -> pane._labelLayout stays
  null -> `WaitForConditionUI(EnableLabelLayout && Layout!=null && PointsLayout.Count>0)` never satisfies.
  Resolution: display-dependent test; add `~.*LabelLayout.*` to the container skip regex (same class as vendor/
  network). Needs a nightly box with a display to actually run. (Possible harness follow-up: make display-
  dependent tests fail-fast/self-skip headless instead of hanging 720s.)

### Docker-worker die-off root-caused + fixed (DOTNET_ROOT for spawned apphosts)

Running the full Test+TestData+TestFunctional suite under `parallelmode=server` (6 workers: 1 host +
5 Docker), workers died en masse within the first minute. Root cause (confirmed from the coordinator
log): tests spawn Skyline-built **.NET 8 tool apphosts** via `ProcessRunner` -- caught `BlibBuild.exe`
failing with `0x80008083` / "Failed to resolve hostfxr.dll" / ".NET location: Not found". The worker's
own `TestRunner.dll` launches through the staged `dotnet.exe` **muxer** (self-locating, 07-04 fix), but a
bare apphost the *test* spawns does not use the muxer -- it needs `DOTNET_ROOT` / a global install /
co-located `hostfxr.dll`, none of which exist in the container (no global .NET; the AlwaysUp `.\TestUser`
service session does not inherit `docker run -e` vars). The failed/hung child took its worker down, and
the coordinator does NOT relaunch dead workers -> 6 workers -> 1 in minutes.

**Fix** (`TestRunner/Program.cs`, `Main` + new `SetDotNetRootForChildApphosts()`): the worker sets
`DOTNET_ROOT` to the staged runtime (`<AppContext.BaseDirectory>\dotnet`, which ships
`dotnet\host\fxr\8.0.27\hostfxr.dll`) in **its own process environment** at startup. Child processes
inherit the process env (not the service session), so spawned apphosts (`BlibBuild.exe`, `BlibFilter.exe`,
`SkylineCmd.exe`, ...) resolve the runtime. No-op if `DOTNET_ROOT` is already set or the staged runtime is
absent (net472 / unstaged dev bins where a global install is used). Verified: re-run showed **0
hostfxr/app-launch errors** (was many within the first minute) and workers stopped dying from that cause.

**Remaining worker deaths are environmental, not net8 bugs:** the container lacks OS-install vendor SDKs
(Agilent MHDAC confirmed; Shimadzu/Waters likely) and downloaded tools (MSFragger/Comet/etc.), and network
(Panorama/Koina/AccessServer). These hang their worker (no relaunch). For a clean parallel pass-count they
are skipped via `skip=~.*Agilent.*,~.*Shimadzu.*,~.*Waters.*,~.*Unifi.*,~.*DdaSearch.*,~.*DiaSearch.*,~.*EncyclopeDia.*,~.*Koina.*,~.*Panorama.*,~.*AccessServer.*`
(TestRunner `skip=` supports `~regex` against `ClassName.MethodName`). They need a nightly machine with the
SDKs/tools to actually run. **Follow-up idea:** make these self-skip (Inconclusive) when the dependency is
absent instead of hanging, so containerized runs don't need the skip list.

### Fast-failure cluster: float/formatting export tests (4 fixed)

Worked the 2026-07-04 "fast assertion/exception failures" list. Root-caused and fixed the
formatting/tolerance cluster; each fix is minimal and framework-agnostic (green on net8, and
does not diverge net472). All uncommitted in `C:\dev\pwiz-net8`.

| Test | Root cause | Fix |
|---|---|---|
| `TestExportSpectralLibrary` | net8's SQLite provider returns the NHibernate-mapped `Standard` INTEGER column as a boxed `Int64`; `bool.Parse("1")` throws (net472 returned a `bool` whose ToString was "True") | `ExportSpectralLibraryTest.cs`: `Convert.ToBoolean(reader["Standard"])` (dispatches on the boxed type on both frameworks) |
| `TestExportIsolationListAsExplicitRetentionTimes` | **Test-side** check strings built from unrounded `t46 - halfWin` (=`56.79-1.2`); exporter rounds RT to 2 dp (`Prediction.GetRetentionTimeDisplay`). net472's lossy `"G"` printed "55.59" and hid it; net8's shortest-round-trip prints "55.589999999999996" | `ExportIsolationListTest.cs`: precompute `t46Start/t46End/t39Start/t39End = Math.Round(..., 2)` and use in all 10 `FieldSeparate` expectations |
| `TestExportChromatogram` (part 1: lines 2-3) | **Product-side** `ExportChromatograms.cs` formats `float` times/intensities/TIC via default `Convert.ToString`; .NET Core changed `float.ToString()` to shortest-round-trip (8 digits) vs net472's ~7 (`46.37717`->`46.377167`) | Added `FormatFloat(float,culture) => ToString("G7", culture)` helper (MS-recommended workaround; a float only carries ~7 sig digits) and routed the 4 float sites through it |
| `TestExportChromatogram` (part 2: line 4) | After G7, residual last-digit **numeric drift** in extracted intensities (~1e-6 relative; JIT FMA/accumulation-order). Test used the exact-string `FileEquals` overload | `ExportChromatogramTest.cs`: pass `ColumnTolerances(0.001, 1e-6)` + `AddTolerance(3, 0.0001, 1e-6)`, mirroring the existing `ChromatogramExporterTest` unit test. AssertEx already handles the comma-packed arrays element-wise |

**Reusable finding:** the `float`-`ToString` shortest-round-trip change (net472 ~7 digits ->
net8 8-9) will recur anywhere product code writes `float` via default `ToString`/`Convert.ToString`.
Fix = explicit `"G7"` (float) / `"G15"` (double), OR a column relative tolerance in the compare.
`AssertEx.ColumnTolerances` was purpose-built for this (see its net8 comments) and splits
comma-packed array columns.

**Remaining fast-failures reclassified as deeper (not formatting):**
- `TestDissociationMethod` — `MeasuredResults.TryLoadChromatogram` returns false for a precursor
  after importing `DissociationMethodTest.mzML` (`DissociationMethodTest.cs:222`). Data/analysis
  parity: dissociation-method spectrum filtering via pwiz-sharp, not a formatting bug.
- `ImmediateWindowTestMethod` — tool-add immediate-window command echoes its args instead of
  emitting the "<X> was added to the Tools Menu" confirmation (`ImmediateWindowTest.cs:57`).
  Immediate-window command execution/parse behavior on net8.

## Status (2026-07-04)

### Test-project ports + net8 parallel test infra + TestFunctional failure triage (MAJOR)

Two arcs this session: (1) finished porting the remaining test projects and built the
net8 parallel-test infrastructure end-to-end; (2) ran the full TestFunctional suite,
clustered the failures by root cause, and fixed 13 tests across 4 distinct causes.

**Test-project ports completed (SDK-style, multi-target net472;net8.0-windows):**
- ✅ `Test.csproj` — 413/0 on net8 (the 16 blockers from last session resolved: ModelsResources
  stub removed, AreNotEqual `(object)` casts, `Enumerable.Reverse`, ModificationMatcher `List<KVP>`,
  G15 + tolerance, SkylineCmd port).
- ✅ `TestFunctional.csproj` — builds; fixed CS0433 SkylineTool duplicate-types (excluded
  `SkylineTool\**` from Skyline glob + added ProjectReference), DigitalRune HintPath, KoinaTestUtil
  un-exclude + `Channel`→`ChannelBase`, `SpectrumNodeSelection`→`PeptidePrecursorNCE` operator ungated.
- ✅ `TestRunner` / `TestRunnerLib` — full port incl. NetMQ Docker-worker model.

**Net8 parallel test infrastructure — WORKING end-to-end (verified real workercount=2 + full run):**
- `Stage-Net8Tests.ps1` (NEW) — robocopies each project's `bin\<Config>\net8.0-windows` into one
  `bin\staging-net8\<Config>` (restores the legacy single-bin the runner/container assume) AND bundles
  a portable .NET 8 Desktop runtime into `<staging>\dotnet` (auto-picks highest 8.0.x; `-NoRuntime` opt-out).
- `TestRunner/Program.cs` — container mapping rewritten pwizRoot-relative (was fragile `pwiz_tools\Skyline\bin`
  anchor); `GetHostTestRunnerExe()` resolves the apphost `.exe` on net8 (Assembly.Location is the `.dll`);
  **Docker workers launch via the staged `dotnet.exe` muxer** (`dotnet.exe TestRunner.dll …`) which
  self-locates its runtime — needed because AlwaysUp runs the worker as a `.\TestUser` service that does
  NOT inherit `docker run -e` env vars (so DOTNET_ROOT never reached the apphost). `skipsystemheaps=on`
  passed as a **command-line arg** (not env, same reason) so container workers skip the `HeapWalk`/`HeapLock`
  system-heap walk that AVs against the Windows-container segment heap (fatal on net8).
- `RunTests.cs` — `SkipSystemHeaps` settable; `HandleEnumeratorWrapper` (C++/CLI TestDiagnostics) gated `#if NET472`.
- `InvokeSkyline.cs` — loads `Skyline-daily.dll` on net8 (the `.exe` is a native apphost).
- Verified: `workercount=2` (host worker + 1 Docker worker over NetMQ) runs real functional tests; full
  `TestFunctional.dll` parallel run with 4 Docker workers distributes + requeues correctly.

**Full TestFunctional run (168/417 before stopping) → clustered failures. 13 tests fixed across 4 root causes:**

| Cause | Fix | Tests |
|---|---|---|
| NHibernate 5.5.2 rejects duplicate-column mapping (`<many-to-one>`+`<property>` same col) | ChromLib `Precursor` mapping: `insert="false" update="false"` on redundant `PeptideId`/`SampleFileId` props | TestAddLibrary, TestAddMixedLibrary (2) |
| `KoinaConfig.xml` not embedded (Jamfile copied dev→xml; SDK build skipped it) | `Skyline.csproj` embed `KoinaConfig_development.xml` under the looked-up resource name (LogicalName) | TestEditCustomTheme, TestClearAllSettings (2) |
| `DocumentationGenerator.css` not embedded → empty stylesheet; **net8 SDK skips satellite for deprecated `zh-CHS` culture** → all Simplified Chinese localization missing | `Common.csproj` embed css; **renamed 327 `.zh-CHS.resx`→`.zh-Hans.resx`** (excl `Executables/`) + `Documentation/Help/zh-CHS`→`zh-Hans` + 8 code refs | 3 help-doc tests **+ restored Chinese localization app-wide** |
| `ProteomeDb.CloseDbConnection()` closes shared NHibernate `SessionFactory` but leaves the pooled `DatabaseResource` cached → next open reuses a closed factory → `ObjectDisposedException` (swallowed → loader never completes → WaitForCondition hangs) | `DatabaseResource.GetDbResource`: if cached `SessionFactory.IsClosed`, drop + recreate | BackgroundProteome, IrtBlib, CleavableCrosslink, ExplicitPeakScore, FullScanId, HighPrecMods (6) |

**4 "failures" were flaky/parallel-only** (pass in clean local single-process run): TestArrangeGraphs,
TestFullScanGraph, TestFullScanProperties, TestIgnoreSimScans.

**Remaining TestFunctional failures (from the enumeration, not yet fixed):**
- Cluster C leftovers (2, distinct larger areas): **ConstantNeutralLossTest** — hangs importing Agilent `.d`
  (vendor-reader/data-layer); **TestImportPeptideSearch** — hangs building a BiblioSpec spectral library.
- Cluster D (1): **TestExportMethodDlg** — `WaitForOpenForm(ExportMethodScheduleGraph)` never opens.
- Fast assertion/exception failures (not hangs): TestExportSpectralLibrary (`'1'` not valid Boolean —
  net8 stricter parse), TestExportChromatogram (output diff), TestDissociationMethod, ImmediateWindowTestMethod,
  TestImportFullScanNarrowScanWindows, TestExportHugeParquetReport, TestExportIsolationListAsExplicitRetentionTimes.
- Environmental (not net8 code bugs): TestAccessServer (network), TestDdaSearch* (tool downloads).

**Nothing committed this session** — all changes are uncommitted in the `C:\dev\pwiz-net8` worktree
(the earlier 4-commit net8 batch `f0ad715..02a6c78` was already pushed in a prior session).

**Next session handoff**: For detailed startup protocol, read `ai/.tmp/handoff-20260704_net8_test_fixes.md` before starting work.

## Status (2026-07-02)

### Cumulative progress (2026-07-02, end of two-day working session — MAJOR)

**TestData.csproj on net8: 161 pass / 5 fail / 0 hangs (97.0%) across 166 tests.** Started this session's arc at 78/186 (29.5%) with hand-hacked stubs. Full arc:

| Milestone | Rate |
|---|---|
| Session start (hand-hacked stubs) | 78/186 (29.5%) |
| First mechanical port (v13) | 129/34 (75.0%) |
| Post-fix cycles (v15–v21) | 152/11 (93.3%) |
| WatersMzXml + NHibernate + MProphet + LocalizedResources | 153/10 → 158/5 (96.9%) |
| MemoryDocumentContainer.IsFinal loosening (Waters unblock) | **161/5 (97.0%)** — all 166 tests running |

**Waters test-container race FIXED (task 264 closed).** `MemoryDocumentContainer.IsFinal` used to require `LastProgress.IsFinal && LastProgress.IsError` for the WaitForComplete loop to exit — so a loader that finished successfully but left `doc.IsLoaded == false` looped forever. Loosened to any final progress state; WatersCacheTest / WatersMultiReplicateTest / WatersMultiFileTest now pass in ~1s each. Also included in the fix chain: pwiz-sharp mzXML tolerance for missing `</scan>` tags (MassWolf-converted Waters mzXMLs), `NHibernate SessionFactory disposed` fix on `IonMobilityDb` + `OptimizationDb`, `SkylineCmd\**` glob-exclude for `TestLocalizedResources`, `MProphetResultsHandler` float pinning to `G7`, `DirectSerializer` Flush + Position resync around SafeFileHandle P/Invoke ops, `HandleExceptions` "Error:" prefix injection.

**Mechanical port `MsDataFileImpl.cs` (2,439 lines) is IN.** Script at `scratchpad/mechanical_port.py` reproducibly regenerates the sandbox `ProteowizardWrapper.PwizSharp/MsDataFileImpl.cs` from the legacy file via ~10 regex rules (see feedback_sandbox_is_mechanical_port memory). Vendor readers register via `[ModuleInitializer]` in a partial-class helper file. `.value` → `.Value.` for chained access, `.value` stripped for implicit-cast tail expressions.

**pwiz-sharp gaps closed this arc** (all committed in local pwiz-sharp working tree, uncommitted):
- `CVParam` / `UserParam` implicit conversions to `double/double?/int/float/bool/string`
- `ReaderConfig` fields `ReportSonarBins`, `IncludeIsolationArrays`, `CalibrationSpectraAreOmitted`
- `ReaderList` methods `FileExtensionsByType()`, `ReadIds(string)`, 4-arg `Read(path, msd, sampleIndex, config)`
- New `IMultiSampleReader` interface + `Reader_Sciex` implements `EnumerateSampleNames`
- `SpectrumList_PeakPicker` — vendor-only helpers + string-ctor for `msLevelsToPeakPick`
- `SpectrumList_IonMobility` — Sonar out-param overloads, `ProbeMzMl` uses `getBinaryData=false`
- `MSDataFile.Write(msd, path)` 2-arg convenience
- New `Pwiz.Data.MsData.ProteoWizardVersion.ToString()`
- New `VendorOnlyPeakDetector` — throws `"PeakDetector::NoVendorPeakPickingException"` message pattern that Skyline's `ChromCacheBuilder` catches
- `Reader_Thermo` + `ThermoRawFile` ctors dispose native handle on error
- pwiz-sharp `MzxmlReader` tolerates missing `</scan>` end tags; peaksCount attr advisory
- `TimeIntensityPairList` legacy alias

**csproj deployment fixes**:
- NHibernate `mapping.xml` embedded as resource in ProteomeDb + 6 Skyline models
- `Method\**\*` deployed via Skyline.csproj `<None>` (vendor method builders)
- `BlibBuild.exe` / `BlibFilter.exe` deployed via ProjectReference to `pwiz-sharp/Tools/BiblioSpec/src/{BlibBuild,BlibFilter}` with `Content Include` globs that flow through ProjectReference to downstream test assemblies
- BlibBuild.cs / BlibFilter.cs `EXE_*` resolved to `AppContext.BaseDirectory\BlibBuild.exe` (.NET 8's `Process.Start` no longer searches current dir, only PATH)
- `SkylineCmd\**` excluded from Skyline.csproj globs (TestLocalizedResources fix)
- `<GenerateTargetFrameworkAttribute>false</GenerateTargetFrameworkAttribute>` on Skyline.csproj (Test.csproj-driven incremental builds intermittently double-linked auto-gen AssemblyAttributes.cs)

**Skyline build/CI plumbing (new)**:
- `pwiz_tools/Skyline/build.bat` — mirrors pwiz-sharp's shape (dotnet restore + build + test, `--automated`, `--coverage`, TC message emission). Currently scoped to `Skyline.csproj` + `TestData\TestData.csproj` since those are the only ported-to-SDK-style-net8 projects. TestPerf/TestTutorial intentionally excluded.
- `pwiz_tools/Skyline/tcbuild.bat` — TC entry wrapper. `CleanSkyline.bat` → `build.bat` → post-build git hygiene (`git ls-files --deleted` + `git status --porcelain`).

**Test project ports (in-progress)**:
- ✅ `CommonTest.csproj` — SDK-style, multi-target. Builds clean. Fixed a latent legacy bug: it listed `FastaImporterWebData.json` but the actual filename is `FastaImporterTestWebData.json`.
- ✅ `SkylineTool.csproj` — SDK-style, multi-target. `System.Web.HttpUtility` is in the runtime on net8. Builds clean.
- ⏳ `Test.csproj` — csproj structure ported (SDK-style, 46 EmbeddedResources + 19 None enumerated, AssortResources source files linked, protoc PreBuild target for LegacySkylineDocumentProto, `ProtocolBuffers\tmp\` excluded from Compile). **Blocked on 16 real code errors**: 14× `ModelsResources` ambiguous in `AlphapeptdeepLibraryBuilderTest.cs` (refs both `AlphaPeptDeep.ModelsResources` and `Koina.Models.ModelsResources` — Koina was net8-cut but resource name kept); 2× `void` operator issues in `LibraryRankedSpectrumInfoTest.cs` / `SpectrumClassFilterTest.cs` (a Skyline API returning `void` on net8 where net472 returned `IEnumerable`).
- ⏳ `TestConnected.csproj` — not started.
- ⏳ `TestFunctional.csproj` — not started (largest — 816 lines).

**Remaining 5 TestData failures — all documented, unblocked path forward:**
- 2× `TestWiffCommandLineImport*` — Sciex Clearcore2 SDK version diff: current SDK returns comma-delimited sample names ("rfp9,after,h,1") where legacy returned underscores ("rfp9_after_h_1"). Verified via side-by-side `Batch.GetSampleNames()` + `Sample.Details.SampleName` + `GetBasicSampleInfos.SampleName` diagnostic — all three same. Blocked at pwiz-sharp layer; needs SDK downgrade or Skyline-side compat option.
- 1× `TestAsymCEOpt` — 90 vs 86 chromatogram count on `CB1_Step 2_CE_Sample 02.wiff`. Ran msconvert-sharp on the WIFF and cpp `ChromatogramList_ABI.cpp:349` review confirmed both emit 90. Difference is a Skyline-side suppression rule.
- 1× `ConsoleImportEiTest` — pwiz-sharp mzXML emits different data than pwiz.CLI for a 19MB EI file; some transitions get empty `ChromInfoList`. Needs data-level parity check.
- 1× `ConsoleImportPeptideSearchTest` — BlibBuild+Skyline lifecycle race for CiRT iRTs. `blank.blib` gets 204 spectra + 1267 RTs + CiRT peptides present, but Skyline's `IrtLibrary` table never created — `ImportPeptideSearch.CreateIrtDb` isn't called because `processedDbIrtPeptides.Any()` is false. Debug trace shows `SQLite error (5): database is locked in SELECT * FROM RefSpectra WHERE id % 4 = 3` — sharded parallel read couldn't grab the lock.

**Next session handoff**: For detailed startup protocol, read `ai/.tmp/handoff-20260702_test_project_ports.md` before starting work.

## Status (2026-06-30)

### Cumulative progress (2026-06-30, end of working session — substantial)

| Project | csproj converted | net8 builds | Notes |
|---|---|---|---|
| PortableUtil | yes (predates branch) | ✅ | template |
| CommonUtil | yes | ✅ | ConcurrencyVisualizer net472-only, Reverse() shadow fix |
| ZedGraph (fork) | yes | ✅ | Deterministic=false for AssemblyVersion("5.1.*") |
| MSGraph | yes | ✅ | trivial — only refs ZedGraph |
| Common | yes | ✅ | NHibernate via NoWarn NU1605; MathNet downgraded to 4.15 (5.0 dropped API); Control.LinearAlgebraProvider→Providers.LinearAlgebra.LinearAlgebraControl.Provider per-target; alglib_info/AssemblyInfo attribute dedup; SQLite NuGet swap |
| ProteomeDb | yes | ✅ | DotNetZip HintPath fix + Ionic.Zip→System.IO.Compression on net8; dev-only Forms/ excluded |
| PanoramaClient | yes | ✅ | trivial |
| **ProteowizardWrapper** | yes | ✅ **with pwiz-sharp** | the chokepoint — Compile Remove legacy MsDataFileImpl + 3 siblings on net8, Compile Include from ProteowizardWrapper.PwizSharp sandbox |
| CommonMsData (wrapper) | yes | ✅ | Unifi/WatersConnect remote API excluded on net8 (IdentityModel 7 rewrite deferred); 219 Skyline files import this namespace |
| CommonFileDialogs | yes | ✅ | one source fix for WatersConnect auth dispatch |
| BiblioSpec (wrapper) | yes | ✅ | trivial shell-out wrapper |
| TestUtil | no | n/a | next session |
| **Skyline.csproj** | no | n/a | the monolith — 1,311 Compile + 1,230 None/EmbeddedResource entries, 30+ HintPath refs. Its own multi-session conversion |
| TestData.csproj | no | n/a | goal target — depends on TestUtil + Skyline |

### Critical milestone reached: pwiz-sharp is the data layer on net8

ProteowizardWrapper.csproj's net8.0-windows path **builds against pwiz-sharp**
end-to-end. The 219 Skyline files importing `pwiz.CommonMsData` and the 74
importing `pwiz.ProteowizardWrapper` now link transitively against managed C#
data code on net8, with the legacy pwiz.CLI C++/CLI bindings preserved only
on net472. **The phase-2 data-layer swap is real, not just sandbox.** Skyline
itself isn't running yet (csproj cascade incomplete) but everything below it
is wired correctly.

### Known source-level fixes recurring across the cascade

1. **Reverse() on arrays** → `Enumerable.Reverse(arr)` explicit form.
2. **`Microsoft.ConcurrencyVisualizer.*`** → `#if NET472` wrap.
3. **AssemblyCompany/Product/Title/Copyright/Version/FileVersion duplicates** —
   wrap these in `Properties/AssemblyInfo.cs` and any vendor-shipped
   `*_info.cs` (e.g. alglib) in `#if NET472`; let the SDK generate them on net8.
4. **MathNet.Numerics 5.0 API changes** — `Properties.Resources` (substitute
   English literals), `Control.LinearAlgebraProvider` (renamed),
   plus likely more across the `DataAnalysis/` tree.
5. **NHibernate transitive NU1605** — add `<NoWarn>$(NoWarn);NU1605</NoWarn>`
   to projects that pull NHibernate.
6. **`$(PLATFORM)` SQLite HintPath** — net472 keeps the HintPath;
   net8 uses `System.Data.SQLite.Core` NuGet.
7. **net472-only BCL refs** — explicit `System.Net.Http` / `System.Web` /
   `System.Security` `<Reference Include>` with `Condition='net472'`.

### Realistic remaining work

The multi-target pattern is proven; each leaf takes ~30 min – 2 hours to convert
**plus iterative debug on per-project source-compat issues that depend on
the project's NuGet dep surface**. Skyline.csproj alone will take 2-3 full
sessions because the dep mass is large and the binding-redirect / app.config
story has to be replaced.

**Best estimate: 5-10 sessions of dedicated work to reach "TestData tests
running with pwiz-sharp".** Multi-session is explicitly supported by the user;
no shortcut available.

### Done
  pwiz-sharp. Originally 6 suspected pwiz-sharp gaps; verification dig closed 5
  — they're already present. 1 real gap (`ReaderConfig.PassEntireDiaPasefFrame`)
  added as an advisory flag; Bruker reader implementation deferred until a
  TestData fixture exercises it. See
  `pwiz_tools/Shared/ProteowizardWrapper/NET8-PORT-NOTES.md`.
- **Phase 2 proof-of-concept landed.** Refactored MsDataFileImpl built against
  pwiz-sharp lives at `pwiz_tools/Shared/ProteowizardWrapper.PwizSharp/` (net8
  SDK-style csproj). Smoke runner at `…PwizSharp.Smoke/`. Reads a real
  Thermo-origin mzML, walks 48 spectra and 19,914-point binary arrays, extracts
  the TIC chromatogram, decodes instrument config (`LTQ FT` /
  `electrospray ionization` / `FT-ICR` / `inductive detector`), exercises QC
  trace + static helper surface. **29/29 checks PASS.**

Ported MsDataFileImpl members (running list):
- Ctor + Dispose + FilePath + SampleIndex
- RunId, IsProcessedBy
- IsThermoFile / IsAgilentFile / IsWatersFile / IsShimadzuFile / IsABFile
- SpectrumCount, GetSpectrumCount, GetSpectrumIndex, GetSpectrumId
- IsCentroided, GetMsLevel, GetStartTime, GetSpectrum (mz+intensity overload)
- GetScanTimes
- ChromatogramCount, HasChromatogramData, GetChromatogramId, GetChromatogram
- GetQcTraces + QcTrace class + QcTraceQuality + QcTraceUnits
- GetInstrumentConfigInfoList + MsInstrumentConfigInfo POCO
- Write
- IsValidFile, SupportsMultipleSamples, GetNonUnicodePath
- IsNegativeChargeIdNullable, IsSingleIonCurrentId
- PREFIX_* / TIC / BPC constants

That's ~30 of ~80 members — the TestData-most-frequent slice + supporting types.

### Blocked / Open

- **Cannot reach "all TestData tests passing" in one session.** Even with the
  refactored MsDataFileImpl working, the path to running Skyline's TestData
  suite requires SDK-style conversion of: Skyline.csproj (7,536 lines), Common
  (206 .cs files), CommonUtil (109 .cs files), CommonMsData (~250 files via
  219 pwiz.CommonMsData consumers), MSGraph, ProteomeDb, PanoramaClient,
  CommonFileDialogs, BiblioSpec wrapper, TestUtil, TestData. Each conversion
  has its own per-project issues (designer files, packages.config →
  PackageReference, custom build targets, AssemblyInfo merge). Realistic
  estimate: 1-3 weeks of focused conversion + debugging work, not hours.
- The user-chosen "refactor MsDataFileImpl in place" decision (vs. shim)
  blocks Phase 2's original "ship before converting Skyline" path —
  the refactored types need Skyline's `SignedMz` / `IonMobilityValue` /
  `SpectrumMetadata` / `ImmutableList<T>`, which live in Common /
  CommonUtil. To refactor in place AND keep Skyline buildable means either
  net48 ProteowizardWrapper multi-targets to net8 (pwiz-sharp can't downport —
  uses file-scoped namespaces, primary constructors, init-only properties) OR
  Skyline converts to net8 in lockstep. The sandbox at
  `ProteowizardWrapper.PwizSharp/` sidesteps this by reproducing only the
  pwiz-side surface and using pwiz-sharp's types verbatim.
- Remaining MsDataFileImpl members (~50): rich `GetSpectrum(int) → MsDataSpectrum`,
  `GetPrecursors`, `MsDataSpectrum` POCO, `MsPrecursor` struct, ion-mobility
  accessors, DiaPASEF config inference, lockmass refining wrapping, SONAR
  helpers. All map mechanically using the same techniques shown in the sandbox.

### Recommended next steps (multi-session friendly)

**The proven path forward is multi-targeting `net472;net8.0-windows`.** Decision
is made: legacy Skyline.sln keeps building net472 unchanged while the same
sources also build net8.0-windows. When the cascade reaches Skyline.csproj
itself, both Skyline.exe and Skyline.Net8.exe can ship in parallel until net8
is fully validated, then net472 retires.

**Conversion order (each step is one commit; ~1 hour each for leaves, scaling up):**

1. ✅ PortableUtil — already SDK-style net472;net8.0 (done before this branch)
2. ✅ CommonUtil — done in this branch
3. **Next: MSGraph** (~30 .cs files, leaf dep of Common)
4. **Then: ZedGraph fork** (`pwiz_tools/Shared/zedgraph/`) — large but
   well-isolated; ZedGraph 6+ supports net6+
5. **Then: Common** (206 .cs files, depends on CommonUtil + MSGraph + ZedGraph,
   + NHibernate which needs ≥5.5 for net6+)
6. **Then: ProteomeDb** (SQLite proteome layer, no pwiz dep)
7. **Then: CommonFileDialogs, PanoramaClient, CommonMsData** (parallel-ish)
8. **Then: ProteowizardWrapper** — convert csproj AND retarget MsDataFileImpl
   to use pwiz-sharp instead of pwiz.CLI. The
   `pwiz_tools/Shared/ProteowizardWrapper.PwizSharp/` sandbox already proves
   ~30 of ~80 methods work; merge those ports into the real
   `ProteowizardWrapper/MsDataFileImpl.cs` under `#if NET8_0_OR_GREATER` and
   port the remaining ~50 using the same techniques (`pwiz.CLI.msdata` →
   `Pwiz.Data.MsData`, `pwiz.CLI.analysis` → `Pwiz.Data.MsData.Analysis`,
   `pwiz.CLI.cv` → `Pwiz.Data.Common.Cv`).
9. **Then: BiblioSpec wrapper** — retarget to pwiz-sharp's BiblioSpec port
10. **Then: TestUtil** (test infrastructure)
11. **Then: Skyline.csproj** — the monolith (7,536 lines legacy → ~80 SDK)
12. **Then: TestData.csproj** + run TestData tests
13. Repeat for other Test* projects, SkylineCmd, SkylineTester, Executables/*

**At each step:**
- Build both `net472` and `net8.0-windows` targets, both must be green
- Run any project-local tests (if present)
- Commit before moving to the next project

**Source-code adjustments that recur across projects** (consolidated from the
CommonUtil pass):
- `.Reverse()` on arrays — use `Enumerable.Reverse()` explicit form
- `Microsoft.ConcurrencyVisualizer.*` — `#if NET472` wrapper
- `System.Net.Http` / `System.Web` / `System.Security` — net472-only assembly
  Reference; net8 picks them up via TargetFramework
- `$(PLATFORM)` SQLite — switch to NuGet on net8


## Objective

Three coupled migrations in one branch:

1. **Skyline (and its ~60 csproj satellite tree) ports from .NET Framework 4.7.2 to
   .NET 8.0 (`net8.0-windows`).** All projects convert from the legacy MSBuild
   csproj format to the SDK style at the same time.
2. **Skyline's vendor-data ingestion swaps from the native `pwiz.CLI` C++/CLI
   bindings to the managed `pwiz-sharp` C# port** sitting at `pwiz-sharp/` in
   this same repo.
3. **The Jam / `quickbuild.sh` orchestration is retired for Skyline-side builds
   in favor of plain `dotnet build` / `msbuild Skyline.sln`.** pwiz C++ retains
   Jam for `msconvert` and the vendor SDKs that Skyline no longer needs to ship.

End state: a Skyline you can clone, `dotnet restore`, `dotnet build`, and run
on a vanilla Windows 11 box with the .NET 8 desktop runtime — no Boost, no
bjam, no C++/CLI roundtrip, no native pwiz.dll deployment.

## State of the territory (survey, 2026-06-30)

### Framework

- ~78 csprojs under `pwiz_tools/Skyline/`. **48 are legacy v4.7.2** in old
  MSBuild csproj format — this is the dominant bucket and covers every "real"
  Skyline project. The handful already on `net8.0` are peripheral dev tools.
- The monolith: `Skyline.csproj` — **7,536 lines** of old-style csproj XML
  (every .cs file enumerated explicitly). Conversion to SDK-style is a delete-
  most-of-the-file operation but a big diff to review.
- Other big-ticket conversions: `TestFunctional.csproj` (802 lines),
  `Test.csproj` (473), `TestUtil.csproj` (348), `TestData.csproj` (319),
  `TestPerf.csproj` (286), `TestRunner.csproj` (161), `SkylineCmd.csproj` (140).
- Legacy v4.0 Client Profile (7 projects) for older ancillary tools: these
  may not migrate cleanly because v4.0 Client Profile types were removed.
  Decide per-project: kill, leave on .NET Framework, or rewrite.

### pwiz binding surface

Direct `pwiz.CLI.*` usage in Skyline is intentionally narrow — **only 5 .cs
files** touch it directly. The real coupling is via three managed Shared
wrappers:

| Namespace | .cs files | Role |
|---|---|---|
| `pwiz.CommonMsData` | 219 | Skyline's actual import / chromatogram surface |
| `pwiz.ProteowizardWrapper` | 74 | Thin facade over pwiz.CLI's `MSDataFile` |
| `pwiz.BiblioSpec` | 21 | Library build / DDA search results |

Critically: **`pwiz.CommonMsData` has zero direct `pwiz.CLI` references** — it's
already pure managed code sitting on top of `ProteowizardWrapper`. The actual
C++/CLI boundary lives in 4 files under `pwiz_tools/Shared/`:
`ProteowizardWrapper/MsDataFileImpl.cs`, `MsDataFileInfo.cs`,
`IterationListenerToMonitor.cs`, `DiaUmpire.cs`.

**This is the leverage point.** Re-pointing those 4 files at pwiz-sharp lets
the 219 `pwiz.CommonMsData` consumers and the 74 `pwiz.ProteowizardWrapper`
consumers in Skyline stay untouched modulo namespace renames.

Top consumer clusters: `Skyline.cs` / `SkylineFiles.cs` / `CommandLine.cs`
(top-level), `Model/Results/Chromatogram.cs` / `ChromCacheBuilder.cs` /
`SpectraChromDataProvider.cs` / `ScanProvider.cs` (chromatogram extraction +
cache), `Model/Lib/Library.cs` / `BiblioSpecLite.cs` (library), the import
dialogs (`OpenDataSourceDialog`, `ManageResultsDlg`, `FileUI/*Import*`), and
the test harness (~80 hits).

### pwiz-sharp's current surface

Verified present and net8.0-ready (already shipped):

- **MsData abstractions:** `MSData`, `MSDataFile`, `ISpectrumList`,
  `IChromatogramList`, `BinaryDataArray`, `BinaryDataEncoder`, `Spectrum`,
  `Precursor`, `Run`, `SourceFile`, `IReader`, `DefaultReaderList`,
  `IIonMobilitySpectrumList`, `IVendorCentroidingSpectrumList`,
  serializers/readers for mzML, mzXML, MGF, MSn, mz5, mzMLb, mzPeak.
- **Vendor readers (all 10):** Thermo, Agilent, Bruker (+TDF/TSF +
  PrmScheduling), Sciex (Wiff1+Wiff2), Waters, Shimadzu, UNIFI/WatersConnect,
  UIMF, Mobilion. Each as `Reader_*` + `SpectrumList_*` + `ChromatogramList_*`.
  Vendor harness round-trip green across all of them
  (`TODO-20260616_pwiz_sharp_mzpeak.md` 114/114).
- **Analysis layer (~60 files):** SpectrumListFactory / ChromatogramListFactory,
  peak picker, smoother, lockmass refiner, ion-mobility, charge-state
  calculators, MZRefiner, demultiplexer, filters, **full DiaUmpire port** (15
  files), **Msx + Overlap demultiplexers** (direct map onto Skyline's
  `MsxDemultiplexer` / `OverlapDemultiplexer`), CWT/LocalMax/Savitzky-Golay
  peak picking, Ms2Deisotoper / ETD precursor / MS2 noise filters.
- **Common:** CV table (`CVID.generated.cs`), CVParam/UserParam/ParamContainer,
  Unimod, OboParser, full `Proteome/` (Fasta, Digestion, ProteomeData,
  ProteinList).
- **BiblioSpec:** Full managed port — BlibBuild/Filter/Search/ToMs2 programs,
  ~30 file-format readers (PepXML, MzIdentML, Mascot, MaxQuant, Hardklor,
  DiaNN, MSF, OSW, Pride, Proxl, Percolator, ProteinPilot, ShimadzuMLB,
  Tandem, MzTab, TSV, SQT, SSL, WatersMse), `BlibMaker`, `BlibBuilder`,
  `BlibFilter`, `BlibSearch`, `PwizSharpSpecFileReader` (bridges BiblioSpec
  to pwiz-sharp MsData), `MascotShimInterop` (P/Invoke to Matrix Science
  msparser).

### Notable gaps

These need pinning down before mass-rewiring:

- **No drop-in `MsDataFileImpl` facade.** pwiz-sharp exposes the canonical
  `MSDataFile` shape, but `MsDataFileImpl` was hand-crafted with extra
  Skyline-shaped helpers (chromatogram pulls, scan-range queries, ion-
  mobility access, predicate caching). Either retarget consumers at
  `MSDataFile` directly or write a thin shim that preserves the public surface.
- **`ProteomeDb` / proteome SQLite layer** has no pwiz-sharp equivalent
  surfaced. Likely stays in Skyline (it's not really a pwiz concern), but
  verify before assuming.
- **`MsDataFileInfo` / `IterationListenerToMonitor`** — small surface to swap.
- **`DiaUmpire.cs` wrapper** in Shared talks to pwiz.CLI; pwiz-sharp's
  DiaUmpire port is present but the C# wrapper needs rebinding.

### Build orchestration

Jamfiles total **1,281 lines across 6 files** under `pwiz_tools/Skyline/`,
dominated by one 689-line `Jamfile.jam` at the Skyline root. SkylineTester
doesn't reference Jam directly (grep clean). CI is single-track:
`.github/workflows/build_and_test.yml` and `appveyor.yml` both call
`./quickbuild.sh ... pwiz executables` (bjam-based).

## Strategy: leverage the wrapper chokepoint

The 4-file `Shared/ProteowizardWrapper` chokepoint changes the size of this
project dramatically. Plan:

1. **Don't try to rewrite 219 + 74 + 21 callers.** Re-implement the public
   surface of `ProteowizardWrapper.MsDataFileImpl` (and its 3 siblings) as a
   shim delegating to pwiz-sharp. Same namespace and class names; same method
   signatures; new internals.
2. **Same for `BiblioSpec` wrapper.** pwiz-sharp's BiblioSpec port is already
   structured to be a drop-in.
3. **csproj modernization is independent of the binding swap** — they could be
   sequenced separately. But they overlap in the projects they touch, so
   doing them in one branch keeps the diff coherent.

## Phases

### Phase 1 — Reconnaissance and gap fill (2-3 days)

- Catalogue every public member of `ProteowizardWrapper.MsDataFileImpl` and
  its 3 siblings. Diff against `pwiz-sharp/pwiz/src/MsData` to find what's
  missing on the pwiz-sharp side.
- Add any missing helpers to pwiz-sharp (likely small — chromatogram pulls
  by id, scan-range queries, predicate caching for repeated calls).
- Decide: shim vs. wholesale retarget. Recommend shim — keeps blast radius
  contained, lets the 293 consumer files stay byte-identical apart from
  package references.
- Smoke-test the shim against a handful of representative imports
  (Thermo .raw, Agilent .d, Bruker .d, Waters .raw, mzML, mzMLb).

**Success:** `MsDataFileImpl` shim builds against pwiz-sharp; produces
identical `SpectrumList` / `ChromatogramList` contents to today's CLI binding
on 3+ vendor fixtures.

### Phase 2 — Swap the wrappers, still on .NET Framework (3-5 days)

- Re-point `pwiz_tools/Shared/ProteowizardWrapper/MsDataFileImpl.cs` and 3
  siblings at pwiz-sharp internals via the shim.
- Same for `pwiz_tools/Shared/BiblioSpec` consumers — pwiz-sharp's BiblioSpec
  port replaces the C++ BlibBuild.
- Keep Skyline on .NET Framework throughout this phase. The shim builds as
  net472 + net8.0 multi-target so both consumer worlds stay live during the
  transition.
- Run Skyline's full functional suite to catch regressions early.

**Success:** Skyline.exe still builds under MSBuild/Jam, but its only pwiz
dependency is pwiz-sharp.dll. The native `pwiz.dll` / `pwiz_data_msdata.dll`
chain leaves the Skyline runtime payload.

### Phase 3 — SDK csproj migration in dependency order (5-7 days)

Convert projects bottom-up. Each conversion swaps:
- Old `<TargetFrameworkVersion>v4.7.2</TargetFrameworkVersion>` → SDK style
  `<TargetFramework>net8.0-windows</TargetFramework>`.
- File globbing replaces the explicit file list.
- `packages.config` → `<PackageReference>` per project.
- AssemblyInfo metadata moves into csproj `<PropertyGroup>`.

Order (rough):
1. Util libraries (DotZLib, Common, MSGraph, ZedGraph fork) — leaf nodes.
2. `Shared/ProteomeDb` — leaf-ish, SQLite consumer.
3. `Shared/ProteowizardWrapper` + `Shared/CommonMsData` + `Shared/BiblioSpec`
   — the wrappers swapped in Phase 2.
4. `SkylineCmd.csproj` — smaller commandline tool, good shakedown.
5. `Skyline.csproj` — the monolith. 7.5k-line diff but largely a delete.
6. Test projects: `TestUtil`, `Test`, `TestData`, `TestFunctional`,
   `TestPerf`, `TestTutorial`, `TestConnected`, `TestRunner`, `TestRunnerLib`.
7. `SkylineTester` (`SkylineTester.csproj` + `SkylineTesterAA.csproj`).
8. Executables tree — convert what's worth converting, leave the rest on
   .NET Framework or retire.

**Success:** `dotnet build pwiz_tools/Skyline/Skyline.sln` produces a runnable
Skyline.exe targeting net8.0-windows. All tests compile (passing them is
Phase 4+ work).

### Phase 4 — Build orchestration retire (2-3 days)

- Replace the Skyline-rooted Jamfile.jam (689 lines) with a thin
  `Build-Skyline.ps1` (probably already exists in some form via the ai/scripts
  tree — there's a `Build-Skyline.ps1` referenced in MEMORY.md) that drives
  `dotnet build` + content-staging.
- Wire `pwiz_tools/Skyline/Executables/Installer` (WiX) into MSBuild as the
  installer target. WiX 4 supports net8.0.
- Carry forward the small per-tool Jamfiles only if their target hasn't been
  retired (`ResourcesOrganizer`, `Hardklor`, `TutorialLocalization`,
  `TestDiagnostics`, `Installer`). Convert the simple ones; leave Hardklor
  on Jam if it's truly C++.
- SkylineTester's runtime configuration shouldn't change — it shells to
  TestRunner.exe, not Jam.

**Success:** `dotnet build` (or `Build-Skyline.ps1`) is the only command
required for a Skyline build. No Boost, no bjam, no `quickbuild.sh` for the
Skyline-side payload.

### Phase 5 — CI swap (1-2 days)

- Add a new GitHub Actions workflow `.github/workflows/skyline_dotnet.yml`
  that runs `dotnet build` + `dotnet test` on a windows-latest runner.
- Run it alongside the existing `build_and_test.yml` (bjam) for at least one
  release cycle so regressions can be caught before retiring the old lane.
- Update Appveyor similarly or retire it.

**Success:** Green CI on the dotnet lane for ≥1 PR cycle without falling back
to the Jam lane for Skyline-side validation.

### Phase 6 — Long tail (1-2 weeks, parallelisable)

- Native interop audit: every `[DllImport]` and `LoadLibrary` in Skyline and
  Shared. Vendor SDK packaging audit — pwiz-sharp's vendor readers already
  pin SDK versions; align Skyline's installer payload with that pinning.
- ZedGraph / NHibernate / SQLite / log4net / Crystal Reports compatibility
  pass. ZedGraph is the riskiest — Skyline forks it and that fork needs
  net8 retargeting.
- WinForms-on-net8 edge cases: GDI+ printing, IME, accessibility,
  System.Drawing primitives, designer round-trip on Visual Studio.
- Test suite reds: any test that hard-codes a pwiz.CLI type name or asserts
  on a stack trace through C++/CLI will need updating.
- Performance regression sweep: import a representative .raw and compare
  pre/post import wall-clock and peak memory. Tolerance to be set after a
  baseline run, but expect parity within 10% or investigate.

## Open questions (need answers before Phase 2 begins)

1. **Drop net48 outright, or dual-target during migration?** Dual-target makes
   the wrappers backward-compatible during Phase 2 but doubles the build
   matrix and surfaces analyzer pain. Recommend net48 + net8.0 only during
   Phase 2; single-target net8.0 from Phase 3 onward.
2. **Wholesale retarget of `MsDataFileImpl` callers, or shim that preserves
   the public API?** Recommend shim (per the strategy section). The cost of
   touching 293 files with byte-identical edits is not free, even if
   mechanical.
3. **Stays in Skyline or moves to pwiz-sharp:** `ProteomeDb` (SQLite proteome
   layer); `MsDataFileInfo` (lightweight pre-open metadata probe); the
   `IterationListenerToMonitor` progress shim. Recommend leaving all three in
   Skyline — they're not pwiz concerns, they're Skyline UI concerns.
4. **ZedGraph fork:** retarget to net8 in place, or replace with a different
   charting library? Replace is out of scope here; in-place retarget then.
5. **Vendor SDK packaging:** Skyline today ships pwiz's bundled vendor DLLs
   inside `Skyline\bin\<config>\<sdk>\`. pwiz-sharp's bundling is per-project.
   Reconcile on a single layout — recommend Skyline's installer aligns with
   pwiz-sharp's runtimes/<rid>/native layout.
6. **Microsoft.Office.Interop usage:** Skyline ships Excel export via Office
   interop. Office PIAs work on net8 but require modernized references; flag
   for Phase 6.
7. **Crystal Reports:** does Skyline still need it? If yes, the SAP runtime
   has net8 support; if no, retire.

## Risks and tradeoffs

- **Performance.** Skyline's import is hot — vendor reads + chromatogram
  extraction can take many minutes per file. pwiz-sharp's vendor readers must
  match throughput. Profile early on a representative Thermo and Bruker
  fixture before committing to the swap.
- **Vendor SDK ABI drift.** pwiz native bindings call vendor SDKs through
  C++; pwiz-sharp calls through P/Invoke or interop assemblies. The
  marshalling boundaries are different — expect a long tail of
  vendor-specific issues (Thermo IRawFileThreadManager lifecycle, Bruker
  timsdata 32-bit handles, Waters MassLynx COM apartment threading).
- **Designer round-trip.** WinForms designer files in Skyline reference
  ZedGraph + custom controls; some break on the SDK-style csproj move
  because the designer expects the legacy file list. Plan for a manual fix
  pass.
- **Test runtime divergence.** TestRunner spawns Skyline.exe and SkylineTester
  shells to TestRunner. Both need to survive the framework swap; the
  spawn-and-wait helpers may need exit-code handling tweaks.
- **Diff size.** Phase 3 alone is ~7,500 lines of Skyline.csproj going away
  plus 60 other csprojs. Code review will be hard if it lands as a single
  commit. Split per-project and merge incrementally on the branch.
- **Boost / Jam still required for `msconvert`.** This plan doesn't retire
  Jam for pwiz C++ — `msconvert` and its vendor SDK orchestration stay on
  Jam. Skyline just stops needing it. State that clearly to anyone reviewing.

## Verification

```powershell
# Phase 1
dotnet build pwiz-sharp\Pwiz.sln
pwsh -File pwiz-sharp\scripts\Run-Tests.ps1 -TestName MsData

# Phase 2 (on .NET Framework still)
msbuild pwiz_tools\Skyline\Skyline.sln /p:Configuration=Debug
# expect pwiz.CLI references gone from the bin output

# Phase 3
dotnet build pwiz_tools\Skyline\Skyline.sln
.\pwiz_tools\Skyline\bin\Debug\net8.0-windows\Skyline.exe   # smoke

# Phase 4
pwsh -File ai\scripts\Skyline\Build-Skyline.ps1
pwsh -File ai\scripts\Skyline\Run-Tests.ps1 -TestName <fast subset>

# Phase 6 — perf
# Time a representative Thermo + Bruker import end-to-end and compare to
# baseline captured before Phase 2.
```

## Key files

- `pwiz_tools/Shared/ProteowizardWrapper/MsDataFileImpl.cs` — the chokepoint.
- `pwiz_tools/Shared/CommonMsData/` — already pure managed, mostly leave alone.
- `pwiz_tools/Skyline/Skyline.csproj` — the monolith.
- `pwiz_tools/Skyline/Jamfile.jam` — the orchestration to retire.
- `pwiz-sharp/pwiz/src/MsData/` — the new ingestion layer.
- `pwiz-sharp/Tools/BiblioSpec/` — the new library-build layer.
- `.github/workflows/build_and_test.yml` — the bjam CI to replace.

## Out of scope

- pwiz C++ side of the world: `msconvert`, the vendor SDK builds, `IDPicker`,
  `Bumbershoot`, anything under `pwiz/` proper. Jam stays for these.
- Skyline's web extensions / SkylineRunner / external Tools store.
- Linux/macOS support for Skyline (still Windows-only; net8.0-windows).

## References

- `ai/todos/active/TODO-20260616_pwiz_sharp_mzpeak.md` — recent pwiz-sharp
  work; vendor harness state.
- `ai/docs/version-control-guide.md` — commit/PR format.
- `ai/WORKFLOW.md` — branch lifecycle.

---

## Progress Log

### 2026-07-07 — net8 CI pipeline brought fully green through the test phase; first real test run; WIFF reader bug fixed

Worktree: `C:\dev\pwiz-net8`, branch `Skyline/work/20260612_net8_port`. PR **#4178**
(head branch `chambem2/pwiz-sharp`; both refs pushed together each commit).
CI config: **`ProteoWizard_SkylineWindowsNet`** runs `pwiz_tools/Skyline/tcbuild.bat`
→ `build.bat` (dotnet restore/build/test under dotCover). Watched via TeamCity
guestAuth REST (`https://teamcity.labkey.org/guestAuth/...`) since the TC MCP
disconnected mid-session.

**Cleared the entire build→test pipeline, one blocker at a time (all committed):**
1. SmartBuildTrigger `KeyError` for base-branch-only targets — `smartBuildTrigger.py`
   now records `building[]` for triggered base-branch targets.
2. `build.bat` rejected the TeamCity vendor flags (`--i-agree-to-the-vendor-licenses`,
   `--require-vendor-support`) — mirrored pwiz-sharp/build.bat's arg parsing.
3. **153 protobuf/gRPC compile errors** — `ProtocolBuffers/GeneratedCode/*.cs` is
   git-ignored; wired a `GenerateProtobufCode` MSBuild target (runs `generatecode.bat`,
   injects the .cs into `@(Compile)`) into Skyline.csproj + Test.csproj.
4. **142k-line build log** (99% warnings) — CA1416 was 98.7%. `Directory.Build.targets`
   suppresses CA1416 only where `TargetPlatformIdentifier==Windows` (GUI stays quiet,
   platform-neutral net8.0 model/CLI keeps the check); `Directory.Build.props` NoWarns
   CS8981/SYSLIB0003 + demotes MSB3825. Log → ~1k lines.
5. Missing `pwiz_tools/Skyline/.config/dotnet-tools.json` (dotcover) — added.
6. **Debug/Release mismatch → 0 tests but green (false pass)** — `build.bat` built
   Release but `dotnet test`/`dotnet dotcover` passed no `-c`, looked in `bin\Debug`.
   Added `-c %CONFIG%` + a snapshot-existence guard so "0 tests ran" fails.
7. **TeamCity `teamcity` vstest logger not found** — `TeamCity.VSTest.TestAdapter 1.0.40`
   delivers its logger DLLs to net-family TFMs but NOT `net8.0-windows`; also Skyline's
   test projects only set `IsTestProject` implicitly (TFM-conditioned) so the shared
   `Directory.Build.targets` package never restored. Fix: set `<IsTestProject>true`
   explicitly in TestData/Test csproj + copy the logger DLLs to output on Windows test
   builds. (pwiz-sharp's test projects set IsTestProject explicitly — the tell.)

**First real net8 test run (build #10, aa742bc8b9): 575 passed / 4 failed** — TeamCity
now shows the full per-test tree with suite/class organization (no importData flattening).

**The 4 failures + status:**
- `CommandLineWiffTest.TestWiffCommandLineImport` + `...SingleReplicate` — **FIXED**
  (`9dfdb632a1`, pending CI confirmation — build queued). Root cause: the Clearcore2
  .NET SDK returns Sciex sample names comma-form (`rfp9,after,h,1`) where cpp
  `getSampleNames()` returns underscore (`rfp9_after_h_1`); Skyline builds the requested
  sample path from the *escaped* underscore name, so the reader's run id
  (`<wiff>-<sampleName>`) never matched → `HasResults=false`. Fix: normalize `,`→`_`
  in `WiffFile.cs` (`NormalizeSampleName`, applied in `EnumerateSampleNames` + per-sample
  id). Verified with a direct Sciex-reader harness.
- `Results.AsymCEOptTest.TestAsymCEOpt` — **NOT STARTED**. Value diff: expected 86
  transitions, got 90 (Agilent/Sciex CE-optimization; imports a Sciex .wiff).
- `CommandLineEiTest.ConsoleImportEiTest` — **INVESTIGATED, NOT FIXED**. Crash
  `IndexOutOfRangeException` at `t.Results[0][0]` because *every* transition's
  `ChromInfoList` is empty (r0count=0) — net8 EI full-scan import extracts zero
  chromatograms. **Definitively ruled out the reader/wrapper**: mzXML reader returns
  4572 spectra, level=1, ~700 peaks, RT `UO_second` correct; `MsDataFileImpl` (the
  class Skyline calls) returns `level=1, rt=4.69–34.99 min, 698 peaks` — perfect data.
  So the bug is in **Skyline's full-scan extraction/matching algorithm on the net8
  runtime** (same code, correct input, no chrom infos). Signature = a chromatogram→
  transition *matching* miss; prime suspect is the known net8 float-`ToString`
  (shortest-round-trippable vs G7/G15) or `Dictionary`/`HashSet` ordering change in the
  matching key. Needs interactive debugging / instrumenting the full-scan matcher.

**Build-infra bugs fixed along the way (enabling local `TestData` iteration):**
- **MascotShim wouldn't copy** (`33a1df75fe`): `BuildMascotShim` used a config-agnostic
  `Outputs=build\.stamp`, so a prior Debug build skipped the Release build → MSB3030.
  Pointed `Outputs` at the per-config artifact. Verified: clean Release BiblioSpec build
  now runs cmake (auto-located via vswhere → VS 18's bundled CMake, no separate install)
  and copies `MascotShim.dll`. CMake provisioning was never the problem.
- **Recursive-glob disk bug** (`64e5a0884f`): `TestData.csproj` `<None Include="**\*.zip">`
  (with `EnableDefaultNoneItems=false`) re-copied `bin` into `bin\Release\...\bin\Debug\...`
  deeper each incremental build → filled C: to 100%. Added `Exclude="bin\**;obj\**"`.

**Local iteration recipe (MascotShim/msparser not needed for non-Mascot tests):**
`dotnet build TestData/TestData.csproj -f net8.0-windows -c Release -p:IAgreeToVendorLicenses=true -p:MascotSupport=false`
then `dotnet test ... --no-build --filter "FullyQualifiedName~<Test>" --logger "console;verbosity=normal"`.
Harness pattern: a net8.0-windows console app with a `ProjectReference` to
`ProteowizardWrapper.csproj` (or `Sciex.csproj`) reproduces the reader/wrapper layer
outside the MascotShim-blocked full `TestData` build.

Latest commit: **33a1df75fe**. WIFF-fix CI build was still queued at session end.


### 2026-07-08 - Sciex reader fixes landed; TestFunctional parallel run triaged (22 net8-wide + 20 container-only)

**Sciex reader fixes (committed + pushed to PR #4178, both refs):**
- `27490eac86` - TestAsymCEOpt: `WiffFile.GetSic` now requests the full experiment cycle
  range (`StartCycle=0` / `EndCycle=RetentionTimeToExperimentScan(lastTicTime)` /
  `UseStartEndCycle=true`), matching cpp `ExperimentImpl::getSIC` with
  `ignoreScheduledLimits=true` (hardcoded in `ChromatogramList_ABI.cpp`). The SDK-default
  (scheduled-window) SIC omitted out-of-window zero points, so Skyline's `delimitByMinimumLevel`
  set different integration boundaries -> areas + forced-integration flags differed (got 90 vs 86).
  Verified byte-identical to cpp msconvert SIC.
- `1126ecb7ed` - CommandLineWiffTest (+SingleReplicate): multi-sample WIFF import intermittently
  threw "used by another process" in `ReaderList.ReadHead`'s `File.OpenRead` - the Sciex SDK frees
  a prior sample's `.wiff` handle only after finalization + an SDK-internal async native close.
  ReadHead now forces finalization then polls the open up to 5s on IOException. (Forcing GC in
  `WiffFile.Dispose` does NOT help - the instance is still reachable during its own Dispose.)
- CI build #12 pending on both fixes.

**TestFunctional health check (net8, Docker parallelmode=server, 10 workers, 617 tests):** 42 failures.
Re-ran all 42 on the HOST (`parallelmode=off`) to separate real regressions from Docker-container
artifacts -> **22 net8-wide (fail/hang on host), 20 container-only (pass on host).** The 3 Sciex
fixes hold everywhere (AsymCEOpt / WIFF / MultiSampleImport green on host and in-container).

**22 net8-wide (real backlog):**
- Dialog-never-opens / WaitFor timeout (6): TestExportMethodDlg, TestWatersConnectExportMethodDlg,
  TestManageLibraryRuns, TestLibraryBuild, TestKoinaSkylineIntegration, ConstantNeutralLossTest
  (Agilent `.d` import hang).
- Dependency / native (3): TestParquetArrays + TestExportHugeParquetReport (Parquet.NET
  `DataField..ctor` MissingMethod = version mismatch), TestImportFullScanNarrowScanWindows
  (`HDF.PInvoke.H5E` type-init threw = HDF5/mzMLb native).
- Known (3): ConsoleImportEiTest (the CI EI IndexOutOfRange), ImmediateWindowTestMethod (tool menu),
  TestDdaSearch (MSAmanda on-demand-download dialog not auto-handled offscreen).
- Assorted assertion / logic (10): TestDissociationMethod, TestJsonToolServer, TestLiteDropdownList,
  TestObjectFilterOperations, TestPasteMolecules, TestReportErrorDlg, TestSkylineCmdInEmptyDirectory,
  TestSynchSiblingsSmallMolecules, TestTriggeredAcquisition, TestZedGraphClipboard.

**20 container-only (pass on host - TRACK DOWN LATER: there should be NO missing DLLs/exes/data):**
- Waters cluster (native `MassLynxRaw` DLL not resolvable in container): WatersCacheTest,
  WatersFileTypeTest, WatersMultiFileTest, WatersMultiReplicateTest.
- TestExportMethodShimadzu (`BuildShimadzuMethod.exe` not in container).
- Console* imports (missing `.raw` / `M:\` share in container): ConsoleBadRawFileImportTest,
  ConsoleImportNonSRMFile, ConsoleMethodTest, ConsoleMultiReplicateImportTest.
- Graph/UI that differ in container: TestFullScanGraph, TestFullScanProperties, TestIgnoreSimScans,
  TestArrangeGraphs, TestSplitGraph, TestScientificNotationGraph, TestTreeRestoration,
  TestLabelLayoutDeterminism, TestManageResults, TestPeakBoundaryCompare, TestCommandLineNoJoin.

**Container-artifact cleanup (separate task):** the Docker parallel workers lack native DLLs
(MassLynxRaw), exes (BuildShimadzuMethod), and data (.raw, M: share) present on the host - fix the
container mount/staging (Stage-Net8Tests + the `docker run -v` mounts) so nothing is missing, then
those 20 stop being false failures. Full traces: `ai/.tmp/tf_parallel.log` (container) +
`ai/.tmp/tf_host*.log` (host).

**Corrections:** the full-scan value-diff cluster (FullScanGraph/Properties/IgnoreSimScans) is
container-only, NOT the EI bug. Waters/Shimadzu "packaging gaps" are container-only (present on host).

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260708_net8_testfunctional_triage.md` before starting work.

### 2026-07-08 (session 2) - Root-caused all 22 net8-wide failures; fixed + host-verified 9

Worktree `C:\dev\pwiz-net8`, branch `Skyline/work/20260612_net8_port`, PR #4178. **All edits are
uncommitted** (8-file working tree) pending review - nothing pushed this session.

**Investigation:** fanned out 6 parallel read/diff investigators over the 22 net8-wide TestFunctional
failures (host stack traces in `ai/.tmp/tf_host*.log` + product code + `git diff origin/master...HEAD`,
no test runs). Collapsed 22 failures into ~13 distinct root causes across 4 themes (harness/infra,
dependency pins, net8 BCL/runtime behavior, pwiz-sharp reader gaps). Then implemented the Tier-1
(cheap/high-confidence) fixes and host-verified each with `TestRunner ... parallelmode=off offscreen=on`.

**Fixed + verified (9 tests):**
- **GC-LEAK triad** (TestLiteDropdownList, TestZedGraphClipboard, TestReportErrorDlg): net8 WinForms
  `ToolStripManager.ModalMenuFilter._lastActiveWindow` (a `HandleRef<HWND>` whose Wrapper roots the
  Form) retains the last active window after menu mode exits; net472 tracked a bare HWND. Root-caused
  with a full-memory dump (`MiniDump`) at the leak moment + `dotnet-dump gcroot`. Fix: reflectively
  release that field in `AbstractFunctionalTest.EndTest()` (TestUtil/TestFunctional.cs), net8-gated,
  beside the existing `ClipboardEx.Release()`. One release clears all three. (Clusters D/E's
  "forced-GC guard" hypothesis was FALSIFIED by the dump - it is a real retention, not GC timing.)
- **TestParquetArrays + TestExportHugeParquetReport**: Skyline.csproj pinned Parquet.Net 4.23.5 but
  the graph loads bundled 4.25.0 (DataField ctor gained a 6th param) -> MissingMethodException. Fix:
  bump pin to 4.25.0 (matches Osprey/BiblioSpec).
- **ImmediateWindowTestMethod**: net8 added `TextWriter.WriteLine(StringBuilder)`, which routes through
  the unimplemented `Write(char)` on TextBoxStreamWriter -> output dropped. Fix: `CommandStatusWriter`
  passes `message.ToString()`.
- **TestExportMethodDlg**: TWO net8 issues. (1) `Process.Start` no longer resolves a relative exe path
  -> `MethodExporter.ExportMethod` now resolves via `AppContext.BaseDirectory` (`ResolveToolPath`,
  single choke-point for all vendor method builders). (2) exposed a `double.ToString` diff in the AB
  Sciex triggered CSV RT-window column -> format with explicit `G15` (net472 default) so net8 matches.
- **TestObjectFilterOperations**: `System.Uri` implements `IFormattable` on net8 (not net472), so
  `DataSchema.GetFilterHandler` routed it to the no-Contains handler. Fix: require `type.IsValueType`
  (numbers/dates get WITHOUT_CONTAINS; reference types like Uri keep WITH_CONTAINS).
- **TestSkylineCmdInEmptyDirectory**: net8 SkylineCmd.exe is a native apphost needing its managed
  companions to bootstrap; the test copied only the exe. Fix: copy SkylineCmd.dll/.runtimeconfig.json/
  .deps.json (but NOT Skyline*.dll, which must stay missing).

**Correct but env-blocked (1): TestDdaSearch** - guard fix (`!= MSFragger` so MSAmanda uses the generic
download path) is correct and the test now reaches the download, but the tool mirror
(`ci.skyline.ms/skyline_tool_testing_mirror/latest.zip`) returns 403 on this host. Needs CI/networked
verification.

**Secondary:** removed the net8 `#if NET472` guard around `FlushMemory()` in
`GarbageCollectionTracker`'s retry loop (it was a GC-less no-op on net8). Not required by the real fix;
droppable for a minimal diff.

**Files changed (uncommitted):** TestUtil/TestFunctional.cs, Model/Export.cs, Skyline.csproj,
Shared/PortableUtil/SystemUtil/CommandStatusWriter.cs, TestFunctional/DdaSearchTest.cs,
TestFunctional/SkylineCmdTest.cs, TestRunnerLib/GarbageCollectionTracker.cs,
Shared/Common/DataBinding/DataSchema.cs. Clean CRLF, no new trailing whitespace.

**Remaining 13 net8-wide (diagnosed, not yet fixed):**
- pwiz-sharp reader gaps: TestTriggeredAcquisition (numpress integer-array decode unimplemented,
  `pwiz-sharp/pwiz/src/MsData/BinaryDataEncoder.cs:376`); ConsoleImportEiTest (non-indexed mzXML ->
  zero chromatograms; probe `SpectraChromDataProvider.cs:1221`; also the lone CI/TestData failure);
  ConstantNeutralLossTest (Agilent CNL reader hang; needs a stack dump); TestImportFullScanNarrowScanWindows
  (HDF5 1.10 can't open the harness `Ütest` path; `MzMlbConnection.cs:78` short-path or HDF.PInvoke 1.14).
- threading/async: TestWatersConnectExportMethodDlg (sync-over-async `.Result` deadlock, IdentityModel7
  `WatersConnectAccount.cs:234-270`); TestJsonToolServer (async IW `BeginInvoke` write vs immediate read;
  add a flush/wait barrier); TestKoinaSkylineIntegration (FakeKoina float-hash match miss vs Grpc.Net
  migration; needs a host run to disambiguate).
- native subprocess encoding: TestManageLibraryRuns + TestLibraryBuild (ProcessRunner sets no
  StandardOutput/ErrorEncoding, so `Ütest` -> `?` reaches BlibFilter/BlibBuild.exe).
- uncertain premise: TestSynchSiblingsSmallMolecules (MSTest v1->v3 makes Assert.AreEqual honor
  IEquatable, so CustomIon.Equals now compares Adduct - unclear if the y1 ion adduct is a real
  regression or over-strict comparison; needs domain confirmation before touching); TestPasteMolecules
  (net8 float.ToString in an error-message string; align test/product formatting); TestDissociationMethod
  (empty filtered chromatogram; needs a per-molecule TryLoadChromatogram + per-spectrum DissociationMethod probe).

**Next session handoff**: read `ai/.tmp/handoff-20260708_net8_tier1_fixes.md`.

### 2026-07-09/10 - Two CI run-killers fixed; suite now completes; 6 genuine failures fixed; MS Amanda standalone DDA made to work end-to-end

Worktree `C:\dev\pwiz-net8`, branch `Skyline/work/20260612_net8_port`, PR #4178. Everything below is
**committed + pushed to origin and mirrored to `origin HEAD:chambem2/pwiz-sharp`** (standing directive).
Local verification used `TestRunner ... parallelmode=off offscreen=on`; DDA tests need `originalurls=on`.

**Build/test harness reworked (91b26945e2, f10f89e4cd):** `build.bat`/`tcbuild.bat` now run the WHOLE
suite (Test + TestData + TestFunctional) through the staged Skyline **TestRunner** harness, not
`dotnet test` (which can't run the UI/functional tests). Default = sequential host run
(`parallelmode=off`); `--parallel` / `SKYLINE_TEST_PARALLEL=1` spreads across Docker workers
(`parallelmode=server`). No skip list - a test opts out of parallel with `[NoParallelTesting("reason")]`.
Fixed a parallel-coordinator `StreamWriter` race (logWriteLock).

**Run-killer #1 - segment-heap AccessViolation (CI builds #22-25).** TestRunner's leak-tracking
`GetProcessHeapSizes` walks process heaps with HeapLock/HeapWalk, which fault with a fatal,
**uncatchable** AV on a Windows **Segment Heap** (default on Windows Server + Windows containers = the
TC build agents + Docker workers). Dead ends tried and rejected (each burned a CI build): blanket
skip-on-net8 (kills the leak number the user relies on); `HeapCompatibilityInformation==3` detection
(segment heaps report 0/2, not 3 - proven in a real Server container); per-heap `0xDDEEDDEE` signature
whitelist (a classic `HEAP_NO_SERIALIZE` heap has the classic 0xFFEEFFEE sig but a null lock and STILL
AVs on HeapLock - build #25). **Final fix (0700f4cb9d): on net8 NEVER walk - read committed/reserved via
`HeapSummary` (kernelbase.dll), which never traverses a heap and works on every heap type; net472 keeps
the historically-safe walk.** Verified end-to-end by running the real staged net8 TestRunner INSIDE a
`mcr.microsoft.com/windows/server:ltsc2022` container (segment heaps by default) - no AV. See memory
`reference_net8_segment_heap_detection`.

**Run-killer #2 - System.Private.CoreLib FailFast (CI build #26).** `AbstractUnitTestEx.GetSystemResourceString`
fetched BCL error strings via `new ResourceManager(assembly.GetName().Name, coreLib)`. On net8 that
assembly is System.Private.CoreLib, whose strings live in the embedded `System.Private.CoreLib.Strings`
resource - ResourceManager groveled for a missing stream and the runtime called `Environment.FailFast`
("...CoreLib.resources couldn't be found!"), uncatchably terminating the whole sequential TestRunner
mid-suite. **Fix (b959da223c): read the `System.Private.CoreLib.Strings.resources` manifest stream
directly (returns null, never FailFast); translate the mscorlib dotted ids to net8's underscored form
(`IO.FileNotFound_FileName` -> `IO_FileNotFound_FileName`).** Added `Test/SystemResourceStringTest.cs`
regression guard. See memory `reference_net8_corelib_resource_failfast`.

**With both run-killers cleared, CI build #27 COMPLETED the full suite** (~50 min, 32k log lines) with
**14 failures** (up from #26's 4 only because the whole suite now runs). Buckets: 5 DDA/DIA tool-download
infra (403 / dialog timeout), 2 DIA-Umpire `msconvert` conversions, 1 intentional net8 deferral
(TestEncyclopeDiaSearch throws "not available on .NET 8"), 1 Thermo-SDK/agent (below), 5 genuine
product failures (below).

**5 genuine pre-existing failures fixed + host-verified (en+fr):**
- **TestDocumentSharing** (159cd83145): net8 SDK csproj re-lists NHibernate mapping .xml as EmbeddedResource
  but missed `Model\Lib\BlibData\mapping_redundant.xml` -> null mapping stream -> NRE building a minimized
  .blib. Added the one entry (all 7 Model mapping files now embedded).
- **TestFilesTreeForm** (e22746a585): net8 `Path.GetFullPath` no longer throws on invalid chars (and dropped
  `"`,`<`,`>` from `GetInvalidPathChars`), so `FileSystemUtil.Normalize` stopped returning null. Restored by
  an explicit invalid-char check.
- **TestMiscForms** (1875500adb): net8 added `MessageBoxButtons.CancelTryContinue` (=6); the test iterates all
  enum values and the unsupported one renders a buttonless dialog -> AcceptButton null NRE. Skip values past
  RetryCancel (numeric compare, compiles on net472).
- **TestReplicatePivotGrid** (e497b40769): net8 `double.ToString("R")` = shortest round-trip (16 digits) vs
  net472 G15-else-G17 (17). One cell differed. Fixed in `DsvWriter` by emulating net472's "R" (G15-else-G17,
  G7-else-G9 for float). NOTE: a blanket G15 is WRONG here (regresses legit 16-17 digit values). Latent same
  bug in `Xml.cs` .sky serialization. Memory `reference_net8_roundtrip_format`.
- **TestToolService** (2472a95635): TWO net8 issues. (1) legacy SkylineTool IPC uses BinaryFormatter, disabled
  by default on net8 -> tool crashed on connect. Re-enabled globally via `EnableUnsafeBinaryFormatterSerialization`
  in `pwiz_tools/Directory.Build.props` (net472 ignores it; temporary until the JSON tool protocol migration;
  gone in net9). (2) net8 throws IOException writing the report to a tool that never reads stdin -> swallow it
  on the report-to-stdin write only (product hardening too).

**Thermo test fixed (4ed5a1dc1e): TestCommandLineExportThermoMethod** - NOT a Thermo-SDK problem (the test is
designed to run without OrbitrapAstral and expects BuildThermoMethod.exe to fail with the registry error). It
only failed the command-line-echo check: it pinned the relative `Method\Thermo\BuildThermoMethod -t OrbitrapAstral`,
but net8 emits the absolute `...\BuildThermoMethod.exe` (because `Export.ResolveToolPath` roots the path -
.NET 8 Process.Start no longer searches cwd). Updated the assertion to match the `.exe` tail.

**MS Amanda standalone DDA integration - TestDdaSearch now GREEN end-to-end** (supersedes session-2's
"env-blocked" note; the wrapper was already OOP+download but never actually produced usable output). Fixes:
- **Wrapper (e10ff1300c, `Model/DdaSearch/MSAmandaSearchWrapper.cs`):** SupportedExtensions = { .mzml } +
  convert others (the standalone reads only mzML); set `WorkingDirectory` to the exe's dir (else "Cannot find
  enzymes.xml!"); MSAmanda writes `.mzid.gz` directly (don't expect a plain .mzid then gzip); the `-e` settings
  file must end in `.xml` (a `.tmp` was rejected); clean up MSAmanda side files.
- **Distinctive mirror/cache name (2bce8ab314, `Util/UtilInstall.cs`):** added `FileDownloadInfo.MirrorFilename`
  (defaults to URL last segment) so MS Amanda's generic GitHub `latest.zip` maps to `MSAmanda-<ver>.zip` on the
  S3 mirror + cache instead of a collision-prone `latest.zip`. The user asked for this specifically.
- **BiblioSpec reader (39558abff3, `pwiz-sharp/.../BiblioSpec/MzIdentMLReader.cs`):** the standalone's mzid has
  items with only `Amanda:AmandaScore` (no percolator q-value) and references spectra as `spectrumID="index=N"`.
  `GetScore` now returns null (skip the item) instead of throwing "unsupported score type" (whole-file error
  only if NO item scored); an `index=N` id sets `PSM.SpecIndex` + `LookUpBy=IndexId`. Diverges from
  MzIdentMLReader.cpp (net472 uses the retired in-process MS Amanda) - cpp parity is a follow-up.
- **Re-recorded** TestDdaSearch counts to `(79, 192, 241, 723, 93)` (lower than the retired in-process
  integration: only percolator-validated PSMs enter the library; zero spectra missed, so legit).

**Follow-ups / open:**
1. **S3 mirror upload (infra):** for CI to pass WITHOUT `originalurls`, `MSAmanda-<ver>.zip` (and the other DDA/DIA
   tool zips - MSFragger, MSAmanda for the DIA tests) must be uploaded to `ci.skyline.ms/skyline_tool_testing_mirror/`.
   The 5 DDA/DIA download failures in #27 are all this (403). Not code.
2. **cpp parity** for the MzIdentMLReader score-skip + index= changes (native build; not in the net8 path).
3. **Remaining #27 failures** not yet touched: the 2 DIA-Umpire `msconvert diaUmpire` conversion failures
   (120s WaitForConditionUI timeout), and TestEncyclopeDiaSearch (intentional net8 feature deferral - likely
   should be skip-guarded on net8).
4. Session-2's "Remaining 13 net8-wide (diagnosed, not yet fixed)" list above - status unknown vs #27; several
   may already be fixed (e.g. ConsoleImportEi, WatersConnect landed in commits 288c8647d7 / f06835cd5d).

**Build gotcha (cost real time, now in memory `reference_net8_bibliospec_staging`):** the BiblioSpec assembly
is `Pwiz.Tools.BiblioSpec.dll` (NOT `BiblioSpec.dll`), and incremental `dotnet build` does NOT propagate a
BiblioSpec change into the Skyline staging dir (ReferenceOutputAssembly=false + Content-copy). To test a reader
change fast: build `BiblioSpec.csproj` then `cp` the fresh `Pwiz.Tools.BiblioSpec.dll` over the staged one. A
clean build.bat propagates correctly.

**Next session handoff**: read `ai/.tmp/handoff-20260612_net8_port.md`.

### 2026-07-10 (session 5) - 4 more net8 tests green: TestPivotEditor + EncyclopeDIA + both DIA-Umpire searches; msconvert-sharp bundled with Skyline

Worktree `C:\dev\pwiz-net8`, branch `Skyline/work/20260612_net8_port`, PR #4178. Commits `f2e97b3ced`
(TestPivotEditor) + `c1657ec892` (msconvert-sharp + EncyclopeDIA + DIA-Umpire), **pushed to origin and
mirrored to `origin HEAD:chambem2/pwiz-sharp`**. All four tests verified locally (parallelmode=off
offscreen=on; the DDA/DIA ones with originalurls=on).

**TestPivotEditor (f2e97b3ced) - the missing half of session-4's DsvWriter "R" fix.** The earlier fix made
invariant report EXPORTS emulate net472's "R" (G15-else-G17) on net8, but the invariant grid DISPLAY still
used net8's native shortest-round-trip "R". TestPivotEditor compares a live grid preview against a live
export, so they diverged (grid `0.2796261731540983` vs export `0.27962617315409832`). Extracted the emulation
into a shared `RoundTripFormat` helper (`pwiz_tools/Shared/Common/DataBinding/RoundTripFormat.cs`); `DsvWriter`
delegates to it and `BoundDataGridView.OnCellFormatting` applies it to "R"-formatted double/float cells so
grid display == export == net472 baseline. Extends the `reference_net8_roundtrip_format` family (that memo
also flagged a latent `Xml.cs` .sky instance - still open).

**EncyclopeDIA un-deferred + msconvert-sharp bundled with Skyline (c1657ec892).** User directive: fix
EncyclopeDIA on net8, don't skip-guard it. The only deferral was a `#if NET472 ... #else throw "feature
deferred"` guard in `SkylineFiles.ShowEncyclopeDiaSearchDlg` (from the 90db5edf4e "make it compile" commit);
all EncyclopeDIA infra (Koina/Grpc.Net, Java jar download, out-of-process invoke) was already net8-ready.
Removing the guard exposed the real blocker: the 4 Skyline msconvert call sites shell out to a bare
"msconvert" that the SDK build doesn't produce, and **net8 Process.Start no longer searches cwd** (same class
as the Thermo BuildThermoMethod fix). Per user direction, wired up the managed **msconvert-sharp** port:
- **Skyline.csproj**: net8-only ProjectReference + Content deploy of msconvert next to Skyline (mirrors the
  BlibBuild/BlibFilter pattern). net472 keeps native msconvert from Jam.
- **`PathEx.ResolveBundledExe`** roots a bundled tool exe to an absolute path in the app dir; the 4 msconvert
  sites + `Export.ResolveToolPath` (method builders) use it.
- **Full rename** (user-approved) `AssemblyName msconvert-sharp -> msconvert` in pwiz-sharp, plus
  installer/build.ps1, Installer.Tests, ArgParser usage text, build.bat coverage filter to keep pwiz-sharp CI
  coherent.

**Three msconvert-sharp behavior fixes (surfaced by actually running the conversions on net8):**
1. **`ArgParser` accepts `--runIndex`** - native msconvert (boost::program_options) takes it as an unambiguous
   prefix-abbreviation of `--runIndexSet`; msconvert-sharp did exact matching and rejected the abbreviated form
   Skyline's EncyclopeDIA path passes.
2. **`SpectrumListFactory.TakeKeyValue` is now quote-aware** - it whitespace-split the filter args, truncating
   a quoted `params=` value that contains a space (`diaUmpire params="...\TestRunner results\...params"` ->
   `params file "...\TestRunner not found`). The DIA tests use adversarial paths (spaces + `~&TMP ^` + unicode).
3. **DiaUmpire temp-dir leak** - `DiaUmpire.Impl.Run` nulled `Msd.Run.SpectrumList` mid-run as a memory
   optimization (literal cpp port, where that field is the raw input list). In pwiz-sharp that field is the
   `SpectrumList_DiaUmpire` wrapper that owns the per-window spill temp dir, so nulling it ORPHANED the wrapper
   -> `MSData.Dispose` never disposed it -> spill dir left behind -> test's leftover-temp-files guard failed.
   Root-caused via stderr diagnostics on `Run.Dispose` (showed `SpectrumList type = null`). Fix: drop the
   `Msd.Run.SpectrumList = null` line; the input is already freed by `Sl = null`. Verified 0 leftover dirs.

**Reusable findings:**
- A managed msconvert-sharp needs to accept native msconvert's boost prefix-abbreviated options + quote-honoring
  filter-arg parsing to be a true drop-in; running the real Skyline conversions is what surfaces these.
- C++ RAII vs C# dispose: a cpp filter that resets `run.spectrumListPtr` for memory must NOT be ported literally
  when the sharp side has a disposable wrapper in `Run.SpectrumList` - it orphans the wrapper's cleanup.
- Build/deploy: Skyline's net8 Content glob deploys the fixed `Pwiz.Analysis.dll` + `msconvert.exe`; for fast
  local iteration on a pwiz-sharp change, `dotnet build MsConvert.csproj` then `cp` the fresh DLL into
  `bin/staging-net8/Release` (incremental Skyline build won't re-copy Content). A clean build propagates.

**Open (not touched this session):** the 5 DDA/DIA tool-download 403s (S3 mirror infra - human action, not
code; note the EncyclopeDIA Java JRE + jar and the DIA-Umpire MSFragger/JRE zips ARE already on the mirror,
only the MSAmanda/MSFragger DDA zips 403); latent `Xml.cs` "R" round-trip instance.

### 2026-07-10 (session 6) - CI board 10->4 (all remaining are download-403 infra); TestConnected ported + wired into CI; TestTutorial + TestPerf ported

Worktree `C:\dev\pwiz-net8`, branch `Skyline/work/20260612_net8_port`, PR #4178. All four commits below are
**pushed to origin and mirrored to `origin HEAD:chambem2/pwiz-sharp`** (standing directive). Local verification:
`dotnet build <proj> -f net8.0-windows -c Release`, `Stage-Net8Tests.ps1 -NoRuntime -Projects <X>`, then
`bin/staging-net8/Release/TestRunner.exe test=<Name> offscreen=on parallelmode=off` (+ `originalurls=on` for
DDA/DIA/tutorial downloads, `perftests=on` for TestPerf).

**CI board: TeamCity `ProteoWizard_SkylineWindowsNet` build #32 (commit c1657ec8) has only 4 failures**
(down from #29's 10). All 4 (`TestDdaSearchMsFragger`, `...BadFasta`, `TestDiaSearchFixedWindows`,
`TestDiaSearchVariableWindows`) are the **S3-mirror download-403 infra** issue (Download dialog timeout) -
NOT code. The 6 genuine failures + the Thermo test cleared. My PivotEditor/EncyclopeDIA/DIA-Umpire fixes all
dropped off the board.

**`f2e97b3ced` - TestPivotEditor (the missing half of session-4's "R" fix).** Session 4 made invariant report
EXPORTS emulate net472's "R" (G15-else-G17) but the invariant grid DISPLAY still used net8's shortest-round-trip.
TestPivotEditor compares a live grid preview against a live export, so they diverged. Extracted the emulation to a
shared `RoundTripFormat.FormatOrNull` (`pwiz_tools/Shared/Common/DataBinding/RoundTripFormat.cs`); `DsvWriter`
delegates and `BoundDataGridView.OnCellFormatting` applies it. See `reference_net8_roundtrip_format` (updated).

**`c1657ec892` - Bundle msconvert-sharp with Skyline on net8; restore EncyclopeDIA + DIA-Umpire.** User directive:
fix EncyclopeDIA, don't skip-guard. Removed the `#if NET472 ... #else throw "feature deferred"` guard in
`SkylineFiles.ShowEncyclopeDiaSearchDlg`. Real blocker was msconvert: the 4 Skyline call sites shell out to bare
`"msconvert"` (net8 Process.Start ignores cwd). Wired up the managed **msconvert-sharp** port:
- `Skyline.csproj` net8-only ProjectReference + Content deploy of msconvert (mirrors BlibBuild); `PathEx.ResolveBundledExe`
  roots it to an absolute path (4 msconvert sites + `Export.ResolveToolPath`); full rename `AssemblyName
  msconvert-sharp -> msconvert` in pwiz-sharp + installer/tests/CLI to match.
- Three msconvert-sharp fixes surfaced by running the conversions: `ArgParser` accepts legacy `--runIndex` (boost
  prefix-abbrev of `--runIndexSet`); `SpectrumListFactory.TakeKeyValue` now quote-aware (quoted `params=` path with
  spaces); `DiaUmpire.Impl.Run` no longer nulls `Msd.Run.SpectrumList` (a literal cpp port that orphaned the
  disposable wrapper -> spill-dir temp leak). See `reference_net8_msconvert_sharp_bundling`. Fixes
  TestEncyclopeDiaSearch + both TestDiaSearchVariableWindows{MsFragger,MsgfPlus}.

**`a00c8676be` - TestConnected ported to net8 + wired into CI + net8 fixes.** Converted the legacy `v4.7.2` csproj
to multi-target SDK (needs explicit `DigitalRune.Windows.Docking` ref on net8 for GraphChromatogram/GraphFullScan);
added to `build.bat` BUILD_TARGET + `Stage-Net8Tests.ps1`. net8 fixes: `UnifiFunctionalTest` network-error asserts
now derive the expected text from `SocketException` at runtime (locale-safe, matches net8 HttpClient's raw socket
message; net472 keeps WebException wording) + target the selected replicate's GraphChromatogram (net8 eagerly
creates the WinForms handle for every per-replicate graph, so `FindOpenForm<GraphChromatogram>` over-counts);
`WatersConnectAccount.HandleAuthenticationException` surfaces the raw (non-localized) identity-server error for
`invalid_scope`/`invalid_grant` (net8's IdentityModel 7 populates `TokenResponse.Raw`, routing them through
classified branches that left the message blank). **Blocker:** WatersConnect/Unifi results import throws
`No registered reader recognized the file` (`pwiz-sharp/pwiz/src/MsData/DefaultReaderList.cs:139`) - the
UNIFI/waters_connect reader isn't in pwiz-sharp's net8 reader list yet (see `project_unifi_watersconnect_port`).
Also `TestUnifi` has a pre-existing test-structure NRE (`_testAccount as WatersConnectAccount` is null for a
UnifiAccount). Both credentialed tests self-skip on CI (no creds). Locally Koina + Panorama tests PASS.

**`9b3fa41e53` - TestTutorial + TestPerf csproj ports.** Both legacy `v4.7.2` -> multi-target SDK (same template).
Build clean on net8, 0 errors, **no source changes**. TestPerf `<Compile Remove>`s the orphan `BullseySharpTest.cs`
(duplicate class the legacy explicit list never compiled). Kept OUT of build.bat's standard suite (separate CI
configs per convention). Local sampling: TestTutorial 4/8 pass (`CustomReports`, `LibraryExplorer`, `AuditLog`,
`GroupedStudies`); 4 fail with net8 runtime NRE/assertion diffs (`MethodRefinement`, `Irt`, `PeakPicking`,
`SmallMoleculesQuantification`). TestPerf `TestAreaCVHistogramQValuesAndRatios` passes (with `perftests=on`).

**Reusable findings (also in memories):** managed msconvert-sharp must accept native msconvert's boost
prefix-abbreviated options + quote-honoring filter parsing to be a drop-in; a cpp filter that resets
`run.spectrumListPtr` for memory must NOT be ported literally where the sharp side has a disposable wrapper in
`Run.SpectrumList`; net8 eagerly creates WinForms handles for hidden docked forms (breaks `FindOpenForm<T>` that
counts `Created`); net8 network-error assertions should derive from `SocketException`/framework, never hardcode
English (locale + CRITICAL-RULES). `Stage-Net8Tests` robocopy `/XO` sometimes fails to overwrite a staged DLL held
by a prior offscreen run - force-`cp` the fresh DLL into `bin/staging-net8/Release` for fast iteration.

**Next up (per priority):** (1) TestTutorial runtime triage - the 4 net8 NRE/assertion failures above (same flavor
as the TestFunctional net8 triage). (2) pwiz-sharp `waters_connect` reader registration in `DefaultReaderList` -
unblocks TestConnected's WatersConnect/Unifi import path. (3) broader TestPerf sampling (needs `perftests=on` +
large vendor data). (4) `TestUnifi` pre-existing NRE. (5) latent `Xml.cs` "R" instance. (6) the 5 DDA/DIA
download-403s (S3 mirror upload - human/infra).

**Next session handoff**: For detailed startup protocol, read `ai/.tmp/handoff-20260710_net8_testconnected_ports.md`
before starting work.

### 2026-07-13/14 (session 7) - All 9 TestTutorial net8 failures fixed + committed; DIA-Umpire + Bullseye fixed; TestPerf triage started

Worktree `C:\dev\pwiz-net8`, branch `Skyline/work/20260612_net8_port`, PR #4178. All commits pushed to origin
AND mirrored to `origin HEAD:chambem2/pwiz-sharp` (standing directive).

**TestTutorial: all 9 net8 failures fixed + verified (full suite 25/25 + ExistingExperiments pass).** Commits
`269f2b2529` (A/B/D/E/G/H) + `18c47b7cec` (F). Buckets:
- **A Excel-reader NRE** - net8 TestUtil.csproj referenced the Framework-only `Excel.4.5.dll` whose `AsDataSet()`
  NREs on net8; migrated the net8 target to modern `ExcelDataReader`+`.DataSet`+`System.Text.Encoding.CodePages`,
  conditional `using` in TestFunctional. Fixed Irt/GroupedStudies1/SmallMoleculesQuantification/SRM.
- **B Dia audit-log "R" float** - routed `AuditLogToStringHelper` "R" through `RoundTripFormat`; also taught
  `FrameworkRoundTrip` to accept a G15 form within 1 ULP (net472's imprecise parser). The latent Xml.cs/audit-log
  instance the older entries flagged.
- **C Sciex .wiff** - (1) `pwiz-sharp DefaultReaderList.ReadHeadOnce` opened FileShare.Read only, colliding with a
  live Clearcore2 write handle on GraphFullScan reopen -> `FileShare.ReadWrite|Delete`. (2) `SpectrumList_Sciex.CreateIndex`
  did a full per-cycle GetSpectrum read on every open (port-only probe) -> removed (cpp checks only BPC/TIC intensity),
  fixing a >360s open (Ms1 481s->63s) and halving Sciex import.
- **D RT scheduling graph pane** - a **dangling `#if NET472`** in `RTGraphController.OnUpdateGraph` compiled out
  `RTScheduleGraphPane` creation on net8 (blank pane for real users). Removed. FOLLOWUP: audit other dangling
  `#if NET472` from the make-it-compile commit `90db5edf4e`.
- **E EditPeakScoringModelDlg dispose NRE** - net8 raises grid `SelectionChanged` during Dispose; the form's
  Disposing/IsDisposed are still false there (components disposed before base.Dispose), so guard on the GRID's
  `IsDisposed||Disposing` + null-check the cell.
- **F mzXML O(N^2)** (`18c47b7cec`) - `silac_1_to_4.mzXML` has no `</scan>` end tags, so the net8 lazy
  `SpectrumList_Mzxml.GetSpectrum`/`ReadOneScan` `Skip()`ed to EOF per scan (~50min). Bounded each scan's parse to
  its indexed byte range via a MemoryStream slice (mirrors cpp). Full walk 50min->2.45s; ExistingExperiments 24min
  hang -> 31s. Added MsData.Tests regression test.
- **G DDA/DIA CI download** - **NOT a mirror 403** (downloads succeed - CI-log proven). A test-harness
  engine-exclusion guard skipped dismissing the "Download <engine>" dialog: `DdaSearchTest.cs` excluded MSFragger
  (broke its Java/Crux deps), `DiaSearchTest.cs` excluded MSAmanda. Removed exclusions at all 3 sites. CI build
  #34 confirms MSFragger DDA tests pass. **Correct any "download-403 infra" note in memory - it was wrong.**
- **H x87/SSE numeric baselines** - RT-regression slopes differ 16-19 ULP between 32-bit-x87 net472 (baselines)
  and 64-bit-SSE2 net8. Added a **numeric-tolerant audit-log comparison** (`AssertEx.AreAuditLogsEquivalentWithNumericTolerance`,
  ~1e-9 rel tol on float tokens, exact non-numeric+integers) so one baseline serves both runtimes. Fixed Irt +
  MethodRefinement's residual slope diffs.

**DIA-Umpire MSAmanda (`1f94f282a6`).** On net8 the OOP MSAmanda derives a scan number from each spectrum's mzML
native id, but DIA-Umpire pseudo-spectra use `merged=N` ids -> MSAmanda skips ALL spectra -> empty mzid -> BlibBuild
"No spectra". (MsFragger/MsgfPlus don't need a parseable scan id; net472's retired in-process MSAmanda read by
index.) Fix in `MSAmandaSearchWrapper.cs` (net8-only): rewrite `merged=N` ids -> `scan=<index>` before invoking
MSAmanda. Fixes TestDiaSearchFixedWindows + VariableWindows; clears CI #34's 2 DIA failures. **Re-baselined**
VariableWindows Final `{85,92,103,927}`->`{48,53,64,576}` - investigated + confirmed genuine OOP-MSAmanda
conservatism (settings correct, rewrite clean, Percolator not degenerating, mc=2 experiment shows scoring-limited;
MsFragger~94/MsgfPlus~38 reproduce on same data). Counts asserted 64-bit-only so net472 unaffected.

**Bullseye net8 bundling (`56ecfc68b4`).** net8 shelled out to bare `"BullseyeSharp"` (not deployed + net8
Process.Start ignores cwd). Bundled managed `bullseye-sharp` (AssemblyName is `bullseye-sharp`) via Skyline.csproj
ProjectReference+Content (mirrors msconvert/BlibBuild) + `ResolveBundledExe`; guarded the bare-name launch in
HardklorSearchEngine.cs + BullseyeSharpTest.cs with `#if NET472`. Exe now deploys+runs. REMAINING: TestBullseyeSharp
fails on a bullseye-sharp output float-precision diff; Hardklor.exe (native, no managed port) still not deployed.

**TestPerf triage (29/39 ran before a disk crash; 15 pass, 14 fail - all real).** Failure GROUPS for next session
(work in parallel, subagents PROPOSE fixes, master APPLIES+TESTS serially):
1. **G-class download dialog (5)** DiaQeDiaUmpire{Extra,FullFileset}, DiaTtofDiaUmpire{,FullFileset}, DiaUmpireWiffFile
   - "Download MSAmanda" not dismissed; same exclusion bug as bucket G but in the TestPerf DIA tests. TRACTABLE.
2. **PASEF isolation-window Start>End (2)** DiaPasef{FullDatasetExtra,Tutorial}.
3. **net8 threading races (2)** DdaTutorial (non-concurrent collection concurrent-update), DiaNnPeakImputation
   (Control.Invoke to dead thread). Harder, maybe flaky.
4. **Hardklor.exe not deployed (2)** FeatureDetection{SIMscans,TutorialFuture} - native tool, no managed port; DECISION.
5. **bullseye-sharp float-precision (1)** TestBullseyeSharp (B/H family).
6. **EncyclopeDIA count re-baseline (1)** EncyclopeDiaSearchTutorialDraft (~5% lower, likely OOP conservatism).
7. **mz5/HDF5 import (1)** NonScoringTransitions.
Passed (15): DiaSearchQe/StellarTutorialDraft, DiaTtof{FullSearchExtra,Tutorial}, DriftTimePredictor x2, HiResMetab,
HighEnergyIonMobility, HugeAssociateProteins, ImportHundredsOfReplicates, ImportMassOnlyMolecules, MinimizeResults,
MobilIon, Ms3Chromatograms, OrbiPrmArdia. ~10 didn't run (disk crash): Thermo FAIMS trio, Qe/Ttof/PasefData,
SciexPrmCeOpt, PeakPerf, PerfTicArea, OrbiPrmTutorial, etc. (AlphaPeptDeep = env-gated Python/NVIDIA, not code.)

**!!! DISK IS THE BOTTLENECK.** The full TestPerf run cannot complete on this box - hit 0 GB twice (multi-GB perf
datasets in `C:\test\Skyline\downloads` + extracted into `pwiz_tools\Skyline\TestResults`). Run TestPerf tests
INDIVIDUALLY, deleting `TestResults` between them; the parallel-copy-to-temp trick FAILED (extra 3.6GB copy +
concurrent downloads + shared %APPDATA% state filled the disk and corrupted the run). A disk guard (<6GB alert)
saved the uncommitted tree once.

**Gotchas:** an unexpected set of `pwiz_aux/sfcap/old/peaks_tools_temp/*` deletions appeared in the tree this
session (not from net8 work; possibly disk-full fallout) - `git restore`d. **Reusable findings (memory candidates):**
G's download failure was a test-harness bug not a 403; DIA-Umpire merged=N scan-id rewrite; OOP-MSAmanda conservatism
re-baseline pattern; dangling `#if NET472` audit; the disk/parallel-copy constraint.

**Next session handoff** (SUPERSEDED): `ai/.tmp/handoff-20260714_net8_testperf.md`.

---

## 2026-07-17 — Perf sweep completed; 5 genuine failures fixed + pushed; Sciex CE-opt root-caused

Resumed from the 2026-07-14 TestPerf triage. Disk freed to ~150 GB (deleted extracted perf-dataset
DIRS in `C:\test\Skyline\downloads`, KEPT the `.zip` caches — disk-guarded run wrappers in `ai/.tmp/`).

**Rewirings confirmed + committed** (Koina→Grpc.Net, Bruker→P/Invoke, UNIFI/waters_connect) — 6 focused
commits verified against their tests. (net472 compile intentionally not chased — user directive.)

**Comet/Tide library FDR bug FIXED (`b311d488ba`).** `FixPercolatorPepXml` (Comet+Tide engines) only
emitted a `percolator_qvalue` for Percolator-matched PSMs; unmatched PSMs kept pepProb=0 so BlibBuild's
`scorePasses(0)` always passed → libraries kept FDR-failing PSMs (TTOF lib 161,235 vs search 13,822).
Fix: else-branch emits `percolator_qvalue=1` for unmatched PSMs (mirrors MSFragger). Added
`CometPercolatorPepXmlTest`. Re-baselined `TestDdaSearchComet` Final 145→106 (verified dropped 39 have
q>0.01). Tide baseline unchanged (the 3-test co-run showing 145→106 was in-process state pollution, not real).

**All 5 genuine net8 product perf-failures FIXED + pushed** (origin + chambem2/pwiz-sharp, at `aec97caad0`):
- **FAIMS trio** `52e02a7f9f` — pwiz-sharp `SpectrumList_Thermo.cs` didn't emit `MS_FAIMS_compensation_voltage`;
  parse scan-filter `cv=` token → cvParam. Fixes TestThermoFAIMS / NegativeFAIMS / SureQuantFAIMS.
- **SIMscans** `f2b1e23a67` — managed `BullseyeSharp/CKronik2.cs` lacked PR #4054's reader-side SIM/boxcar
  window skip (native Hardklor.exe writes the columns; submodule already has the fix). Ported
  scanWinLower/Upper + non-covering-scan skip in both look-left/right loops + `MzFromMassCharge`.
- **TutorialFuture** `aec97caad0` — benign net8 float32 FMA drift; widened `ColumnTolerances` to (0.00015, 5e-6).

**DIA "cache-artifact" fails RESOLVED — NOT net8 regressions.** DiaTtof/QeTutorial + both FullSearchExtra
failed at `DiaSwathTutorialTest.cs:798` (`DiaFiles.Contains(selectedFile)`): leftover `-diaumpire.mzML`
files in the shared `.../DIA` dirs (from this session's DIA-Umpire runs); `SelectAllFileType(.mzML)` picks
them up and they aren't in expected `DiaFiles`. Test only cleans `*-diaumpire.*` in screenshot mode, not
offscreen. Deleted them → all 4 PASS. (Robustness idea: clean them in offscreen mode too.)

**TestSciexPrmCeOptimization ROOT-CAUSED — fix pending (the one open product bug).** `GetBestOptimizationStep(LVGTPAEER)`
returns null (`!HasResults` = zero chromatograms; assert stops at index 0 so likely ALL 4 PRM groups → systemic).
msconvert-sharp on `110922 PCM_40f RT CEOpt A1.wiff2`: CE ramps CORRECT (LVGTPAEER 19/21/23/25/27/29/31 =
steps −3..+3 incl −1), but ZERO isolation offsets (`MS:1000828/829`) anywhere + Q1 rounded to 2 decimals
(491.27). → Skyline sees a zero-width window at 491.27 that doesn't contain the group's full-precision
precursor 491.26559 → no match → no chromatograms. Native emits real ±half-width so net472 passes.
`WiffSpectrum.IsolationHalfWidth` (`pwiz-sharp/pwiz/src/Vendor/Sciex/WiffFile.cs:612`) returns 0 for this
wiff2 Product exp (its `_exp.Details.MassRangeInfo[0]` isn't a `FragmentBasedScanMassRange` w/ `IsolationWindow>0`).
There is NO `Wiff2Spectrum` class — both wiff1/wiff2 use `WiffSpectrum`; the comment at WiffFile.cs:611
("wiff2 already computes them") is WRONG. Same bug class as the 2026-07-14 SWATH `.wiff` isolation-offset gap.
Recorded in memory `project_net8_sciex_reader_parity`. Extracted test data kept at scratchpad `.../ceopt/`.

**Reconciliation with 2026-07-14 triage groups:** Group 4 ("Hardklor.exe not deployed" — FeatureDetection
SIMscans/TutorialFuture) was MISLABELED; actually SIMscans = missing managed CKronik SIM logic, TutorialFuture
= float32 tol. Both FIXED. `TestHardklorBullseyeSharp` now PASSES in the fresh sweep.

**Remaining perf failures (only Sciex is a product bug):**
- 🔴 `TestSciexPrmCeOptimization` — root-caused above; fix = wire `WiffSpectrum.IsolationHalfWidth` to the
  correct wiff2 SDK isolation source (needs a diagnostic build to identify it) + use full-precision centerMz.
- 🟡 `TestOrbiPrmArdia` — Ardia cloud credentials (env, not code).
- 🟡 `TestAlphaPeptDeepBuildLibrary` — `SkylineProcessRunner.exe` not in staging + AlphaPeptDeep Python env (harness).
- 🟡 `TestDiaTtofDiaUmpireTutorial` (fr, ja) — non-EN audit-log recording, not yet root-caused.

**Next session handoff** (SUPERSEDED — see 2026-07-22 below): For the Sciex-reader fix brief, read
`ai/.tmp/handoff-20260717_net8_perf_sciex.md`.

---

## 2026-07-22 — App-tier ports done; net8 per-commit CI GREEN (#51 1706/1706); loader + Thermo-French fixes; audit-log tolerance (WIP)

**The net8 per-commit TeamCity build (`ProteoWizard_SkylineWindowsNet`) is GREEN — build #51 (`3d526a3470`)
= 1706/1706, 0 failures**, running pass0 (French, no-vendor mzML) + pass2 (full English suite, real vendor
readers) + ja/zh import + a pass1 functional subset. It was RED at #50; the loader fix below flipped it.

**App-tier ports completed** (all multi-target net472;net8.0-windows, committed + mirrored to
`chambem2/pwiz-sharp`): SkylineProcessRunner (`1662fd219a`), SkylineRunner/SkylineDailyRunner
(`653cbc0be4`), SkylineTester (`7e97746fa2`), SkylineBatch+SharedBatch (+SkylineBatchTest 38/38,
`6f06a355d9`), SkylineNightly+Shim (`805fae1e55`), AutoQC+AutoQCStarter+AutoQCTest (`8c4dd63005`). Gotchas
in memory `reference_net8_app_port_gotchas`. **LaunchBatch DEFERRED** — trivial to multi-target but only
launches ClickOnce `.appref-ms` refs, so blocked on the ClickOnce-replacement decision.

**CI test policy rewritten in `build.bat`/`tcbuild.bat`** (`ce747ae461`, `07d1525866`, `77fcf2af73`) to
mirror the old net472 per-commit check: the full English suite (pass2) PLUS three extra modes — French
pass0 build-check over CommonTest+Test+TestData, `~\.TestImport` under ja/zh, and a pass1 functional subset
(TestInstrumentInfo/TestQcTraces/TestTicChromatogram/TestDiaSearchFixedWindows). All modes run even if an
earlier one has failing tests (only a compile error short-circuits); a `SKYLINE_TEST_ARGS` escape hatch
runs a single custom TestRunner. Added CommonTest to BUILD_TARGET + Stage-Net8Tests default projects.

**ThermoFormatsTest (pass0) FIXED — net8 loader-checkpoint regression (`3d526a3470`).** NOT
French/reader/matcher: the net8 port loosened `MemoryDocumentContainer.IsFinal` (to stop WatersCacheTest
hanging) to return final on ANY `LastProgress.IsFinal`. Multi-file loading posts a final status per file
while parking the doc at a checkpoint (commit partial cache, re-trigger for the next file), so
`SetDocument(wait:true)` returned before importing the 2nd file (mzXML) → empty infoSet. Refined IsFinal to
distinguish by "are any files still uncached" (checkpoint→keep waiting; Waters→all cached, fail-fast).
Memory `reference_net8_isfinal_multifile_checkpoint`. `ConsoleImportEiTest` re-checked and confirmed
ALREADY PASSING (stale TODO note — fixed earlier by the mzXML lowMz/highMz fallback `288c8647d7`).

**Thermo French-culture SRM import FIXED (`ae1c95ccfa`, pwiz-sharp).** With a proper vendor build,
importing Thermo `.raw` under French threw `InvalidFilterFormatException` — the managed RawFileReader SDK
parses the period-decimal SRM filters pwiz builds under the thread culture. Wrapped
`ChromatogramList_Thermo.GetChromatogram`'s SDK dispatch in InvariantCulture (restore in finally). 13
Thermo/ConsoleImport tests now pass fr+en. CI never caught it (only English+vendor or French+no-vendor).
Memory `reference_net8_dotnetbuild_vendor_staging`: a bare `dotnet build`+Stage staging ALSO pulls a
mismatched Thermo SDK → the SAME exception even in English; use build.bat/CI, not dotnet build, for
vendor-reader test runs.

**Suite results (proper vendor build):** TestData clean (my local "151/166" was the dotnet-build staging
artifact; CI #51 pass0+pass2 both green). TestTutorial **en 26/26**; **fr** had 3 audit-log-baseline
failures (TestIrtTutorial/TestMethodRefinementTutorial/TestPeakPickingTutorial) — net8's `double.ToString`
emits shortest-round-trip (17 sig figs) where net472 emitted ~15, and the two frameworks differ by ~1 ULP
right at the 15th figure (e.g. slope `0,151543213352228` vs `0,15154321335222853`).

**✅ AUDIT-LOG NUMERIC TOLERANCE — REWORKED + COMMITTED (`fcf2ea59f7`).** The initial WIP added a parallel
`NumbersEquivalentWithinFloatNoise` (1e-13) to the SHARED `NoDiff` path; a `/code-review` flagged 7 findings
(fix at the wrong altitude). REWORKED: reverted the NoDiff addition and instead extended the existing
audit-log-scoped `AreAuditLogsEquivalentWithNumericTolerance` to be culture-aware (numeric regex accepts
`.`/`,`; `IsIntegerToken` treats `,` as a decimal separator; value parse via
`CommonTextUtil.TryParseDoubleUncertainCulture`), reusing its established 1e-9/1e-12 tolerance + exact
integer/zero-floor guards. Findings: 5 fixed, 2 skipped (`IsFinal` final-but-uncached-no-error edge = design
trade-off; Thermo ctor index-build InvariantCulture wrap = latent). Verified: fr TestTutorial **26/26**, en
`TestAuditLogTutorial` green. Original review findings, kept for the record:
  1. It's in the SHARED `NoDiff` path (~38 callers: transition-list/koina/EncyclopeDIA CSV exports, .sky
     docs, XSDs), so ALL now silently tolerate 1e-13 numeric drift, bypassing the opt-in `columnTolerances`
     design → scope it to audit logs (or an opt-in param).
  2. 1e-13 is 4 orders tighter than the EXISTING `AUDIT_LOG_NUMERIC_RELATIVE_TOLERANCE = 1e-9` used by
     `AreAuditLogsEquivalentWithNumericTolerance` — reuse/reconcile that (a 3rd parallel impl; the sibling
     `CommonTextUtil.LinesEquivalentIgnoringTimeStampsAndGUIDs` used by CompareDocuments is left unpatched).
  3. Integers ≥~14 digits differing by 1 are tolerated (contradicts the "integers still match" comment);
     `scale==0` rejects equal zeros formatted differently ("0" vs "0,0"). (Finding 7: the Thermo culture
     wrap covers only extraction, not the ctor's index-building SDK calls — latent.)

**Still open / next (working tree CLEAN at `fcf2ea59f7`, CI green):** (1) port remaining net472-only
projects (SkylineAiConnector, the 8 arg-collectors under Executables/Tools, the dev/build utilities);
(2) LaunchBatch (deferred, ClickOnce); (3) `TestSciexPrmCeOptimization` isolation-halfwidth — verify current
status vs the 2026-07-17 handoff; (4) non-EN audit-log baselines for TestDiaTtofDiaUmpireTutorial (fr/ja) —
the culture-aware tolerance may now clear these; (5) optional low-pri review follow-ups: `IsFinal`
final-but-uncached edge, Thermo ctor index-build InvariantCulture wrap. Live status-map artifact:
https://claude.ai/code/artifact/eb82129b-c56b-440a-acf7-52343461dce2

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260722b_net8_auditlog_reworked.md` before starting work.

## 2026-07-22 (session c) — Sciex CE-opt RESOLVED (stale, not a reader bug); Thermo ctor culture wrap committed; IsFinal left as-is

Worked the 3 low-pri follow-ups from session b's next-steps (items 3/5a/5b). Item 4 (fr/ja
DIA-Umpire audit-log baselines) deferred by request.

**Item 3 — `TestSciexPrmCeOptimization` (TestPerf): ALREADY RESOLVED at HEAD — verified passing
(en, 24s, 0 failures). NOT a reader bug; the 2026-07-17 root-cause was wrong on every count.**
Investigated the Skyline layer per request and found the test already green, then traced *why*
the reader was never the problem (memory `project_net8_sciex_reader_parity` corrected in full):
- `.wiff2` is read via the MODERN SCIEX.Apis SDK on BOTH frameworks — C++ `WiffFile::create`
  (`WiffFile.cpp:1053`, `iends_with(".wiff2")→WiffFile2Impl`) and managed `AbstractWiffFile.Open`
  (`.wiff2→Wiff2File` plugin) dispatch identically. There IS a `Wiff2Spectrum` class
  (`Vendor/Sciex/Wiff2/Wiff2File.cs:336`); the handoff's "no Wiff2Spectrum, fix
  `WiffSpectrum.IsolationHalfWidth`" pointed at the legacy `.wiff` path that is never hit.
- Raw SDK ground truth (diagnostic dump of 60 Product/TOFMSMS spectra): `IsolationWindowTarget=491.27`
  (2-dec rounded), `LowerOffset=UpperOffset=0` — the SDK provides NO Q1 width. Managed `Wiff2Spectrum`
  faithfully ports C++ `WiffFile2::getIsolationInfo` (`WiffFile2.ipp:744-746`) + `SpectrumList_ABI.cpp:200-208`,
  so net472 and net8 emit IDENTICAL mzML (target 491.27, no offsets). A reader change would DIVERGE from net472.
- The "zero-width window can't contain 491.26559" reasoning is a RED HERRING: for `acquisition_method="PRM"`
  Skyline IGNORES the file's offsets and re-matches with width `2*MzMatchTolerance` around the target
  (`SpectrumFilter.FindFilterPairs` PRM branch). doc2.sky `mz_match_tolerance=0.055` >> Δ0.0044, so it matches.
- Fixed by an intervening commit after 2026-07-17 `aec97caad0` (not pinned; candidates: wiff2 non-ASCII
  reader-robustness `f9d574d75d`, or the CommandLineWiff file-handle ReadHead retry). **No code change; TODO
  item retired.** Lesson: RUN a stale "open failure" before diagnosing.

**Item 5b — Thermo constructor InvariantCulture wrap: COMMITTED `9aefc1e79d` (origin + chambem2).**
The extraction fix `ae1c95ccfa` only wrapped `GetChromatogram`; the ctor's SIM/SRM index-building
(`GetFilterForScanNumber(...).ToString()` matched as dict keys vs period-formatted `GetAutoFilters()`)
had the same latent French gap → empty SIM/SRM index. Extracted the culture save/set/restore into a
shared `RunInvariant` helper and wrapped the ctor. Latent (CI never runs French+vendor). Verified no
regression: `ThermoQuantTest` suite (8 methods incl. SRM `.raw` imports ThermoFormatsTest/ThermoRatioTest/
ThermoMixedPeptidesTest) passes fr+en with real vendor readers (ran by swapping the rebuilt reader into
today's vendor staging — the Thermo SDK dll is byte-identical, avoiding the bare-staging SDK-mismatch trap
`reference_net8_dotnetbuild_vendor_staging`).

**Item 5a — `MemoryDocumentContainer.IsFinal` final-but-uncached-no-error edge: LEFT AS-IS (recommend no
change).** The hang only triggers if a loader posts a final error-free status yet leaves a file uncached
AND never re-triggers — a loader bug already surfaced by `WaitForComplete`'s 1-hour diagnostic. Any
timeout/no-progress hardening risks reintroducing the ThermoFormatsTest regression `3d526a3470` fixed
(bailing before a slow checkpoint re-trigger). The /code-review already classified it a design trade-off.

**Still open / next (working tree CLEAN at `9aefc1e79d`, CI expected green):** (1) port remaining net472-only
projects (SkylineAiConnector, the 8 arg-collectors under Executables/Tools, dev/build utilities); (2)
LaunchBatch (deferred, ClickOnce); (3) item 4 — non-EN audit-log baselines for TestDiaTtofDiaUmpireTutorial
(fr/ja): re-run under language=fr/ja to see if the culture-aware tolerance now clears them (deferred this
session). Items 3/5a/5b above are closed.

## 2026-07-22 (session c cont.) — net472-only project ports: arg collectors + DevTools (21 projects, 6 commits)

Worked the "port remaining net472-only projects" backlog (memory `reference_net8_app_port_gotchas` +
`project_net8_port_peripheral_scope`). All converted to SDK-style multi-target, all build BOTH TFMs, all
committed + dual-pushed (origin + chambem2). HEAD `31acfc5308`.

**Arg collectors (9) — commit `3c9d80724b`:** QuaSAR, SProCoP, MS1ProbeArgsCollector,
ProteinTurnoverArgCollector, TestArgCollector, ExampleArgCollector, MSStatArgCollectors, MSstats/TestHarness,
TFExportTool. Pattern: SDK multi-target net472;net8.0-windows + UseWindowsForms + System.Resources.Extensions;
dropped vestigial System.Deployment/System.Net.Http; renamed the Chinese satellite resx **zh-CHS -> zh-Hans**
(12 files, branch standard); ja + zh-Hans satellites verified building. Specifics: ProteinTurnover/MSStat use
Microsoft.VisualBasic.FileIO.TextFieldParser (net472 framework ref; net8 via WindowsDesktop); TFExportTool
references the bundled net40 CsvHelper.dll for both TFMs (old CsvConfiguration API predates modern NuGet) +
embeds icon.ico; TestHarness -> MSStatArgCollectors project ref.

**DevTools (12) — commits `38b494fcb0` (6 console), `adc9292974` (UniMod+Ipi), `6f4d0e400c` (ImageComparer
pair), `268ec8cd9f` (AssortResources), `31acfc5308` (TutorialLocalization):**
- Pure-console -> net472;net8.0 (plain, no -windows): ImportPerf, ParseIsotopeAbundancesFromNIST,
  OpenSwathConvert, PeakViewConvert, SortRESX, BindingRedirectGenerator, IpiToUniprotMapCompiler,
  TutorialLocalization.
- WinForms/CommonUtil/ResX -> net472;net8.0-windows: UniModCompiler (CommonUtil proj ref), AssortResources
  (System.Resources.ResXFileRef + StronglyTypedResourceBuilder -> UseWindowsForms; System.Design net472-only),
  ImageComparer (+ added a net8.0-windows target to ImageComparer.Core with System.Drawing.Common 8.0.10).
- Dep handling: DotNetZip net472 HintPath + net8 NuGet 1.16.0 (Ipi; **fixed a stale 3-up HintPath -> 4-up**);
  TutorialLocalization's 5 real deps (CommandLine/CsvHelper/DotNetZip/F23.StringSimilarity/HtmlAgilityPack) are
  pure-managed on-disk libs referenced for BOTH TFMs, with the BCL polyfill shims (System.Memory etc.)
  net472-only (built into net8).

**New reusable gotchas** (added to `reference_net8_app_port_gotchas`): embedded-`.cs` code-gen templates need
`Compile Remove` + `EmbeddedResource`; old net40/net461 pure-managed vendor DLLs (CsvHelper/CommandLine) are
net8-loadable so reference them for both TFMs rather than a source-breaking NuGet upgrade; ResX tooling
(ResXFileRef / StronglyTypedResourceBuilder) resolves via UseWindowsForms on net8, needs System.Design on
net472; Microsoft.VisualBasic.FileIO.TextFieldParser is on the net8 WindowsDesktop framework (no ref).

**DEFERRED follow-up (not blocking the source port):** the SHIPPED tool artifacts still carry the old
net472 zh-CHS builds - checked-in `Executables/Tools/QuaSAR/QuaSAR.dll`, `MSstats/MSstats.zip`,
`Turnover/TurnoveR.zip`, etc. Rebuilding + repackaging those (and wiring net8 external-tool deployment /
in-process loading of a net8-built arg-collector DLL) is a separate step.

**Remaining net472-only port backlog:** interactive tools (ExampleInteractiveTool,
TestCommandLineInteractiveTool, TestInteractiveTool, SkylineIntegration/XLTCalc, MPPExport, SkyGadget),
AdvancedEditingCommands + ToolServiceTestHarness (net7 -> net8), SetupDeployProject (Installer - verify it's a
normal SDK project vs a VS deploy/WiX project). Deferred: LaunchBatch (ClickOnce).
**NOT a port target - permanently net472 legacy:** `pwiz_tools/Skyline/BullseyeSharp/BullseyeSharp.csproj`
compiles the Bullseye source against the C++/CLI `pwiz_data_cli.dll` (no net8 equivalent) and is built only by
the net472 Jam toolchain; net8 Skyline already uses the managed `pwiz-sharp/Tools/BullseyeSharp/src`
(AssemblyName `bullseye-sharp`, `bullseye-sharp.exe`) via a net8-only ProjectReference in Skyline.csproj
(lines ~287-297). BullseyeSharp is the GENUINE un-portable case (C++/CLI); the Build*Method builders turned
out to be portable and are now ported (see below). SkylineAiConnector already net8.

## 2026-07-22 (session c cont.) — Build*Method vendor builders: feasibility PROVEN + all 10 ported (`2fff27594f`)

Matt asked to test whether the "out of scope" vendor method builders can port to net8 (reason: a future
Windows may not ship .NET Framework 4.7.2). **They can — all 10 ported + committed (`2fff27594f`, dual-pushed).**

**Compile (both TFMs):** the 7 managed-vendor-DLL builders (Thermo, Sciex, Agilent, Bruker, Shimadzu, Waters =
net472;net8.0-windows; AgilentMH12 = **net48**;net8.0-windows - its `Agilent.MSDrivers.LCQuadrupole.*` DLLs
target .NET 4.8, which 4.7.2 can't reference) build via `dotnet build`. The 3 COM-interop Analyst-family
builders (BuildAnalystMethod stdole `<COMReference>`, + its ProjectReference dependents AnalystFullScan/QTRAP)
build via full **`MSBuild.exe`** only - dotnet's Core MSBuild lacks the `ResolveComReference` task (**MSB4803**);
the Skyline .sln pipeline uses full MSBuild so that's fine. Per-project net8 fixes: dropped a dead
`using System.Runtime.Remoting.Messaging` in BuildWatersMethod (Remoting removed in net8); excluded the embedded
MSTest-v1 `Test\` folders from AnalystFullScan/QTRAP (`Compile Remove` - that framework has no net8 build; the
builder EXE is the deliverable); added `System.Configuration.ConfigurationManager` for QTRAP's Settings.

**Runtime CONFIRMED (this is the important part):** `TestExportMethodShimadzu` (TestData) **PASSED (0 failures)**
after deploying the net8-built `BuildShimadzuMethod.exe` into the staging `Method\Shimadzu\` - net8 Skyline
shelled out to it, it loaded the net8 runtime + the net472 Shimadzu vendor DLLs and converted a bundled `.lcm`
template into a method file. Also: net8 `BuildThermoMethod.exe` runs, loads + executes the net472 `Thermo.TNG.*`
DLLs, failing only on a missing instrument-software registry key (identical on net472). So the net472-targeted
vendor DLLs run under the net8 runtime; the only builders that truly need instrument hardware/software to run
their tests (Analyst/Sciex - `Process.Start(Analyst.exe/SciexOs.exe)`) can't be exercised on a dev box either way.

**Architectural note:** Skyline invokes all builders as separate-process exes (`MethodExporter.ExportMethod` ->
`Process.Start`), so a net8 Skyline shells out to net472 OR net8 builder exes interchangeably. The value of the
net8 port is future-proofing (Windows without net472), not a functional requirement today. New gotchas recorded
in [[reference_net8_app_port_gotchas]]. **Only genuinely-unportable project left: BullseyeSharp (C++/CLI).**

**Next session handoff**: For detailed startup protocol (port recipe, build/verify commands incl. the
full-MSBuild path for COM projects, remaining backlog, vendor-test deployment steps), read
`ai/.tmp/handoff-20260722c_net8_project_ports.md` before starting work.

## 2026-07-23 - SkylineAiConnector port + merge master + C++->C# BiblioSpec port + DIA-Umpire audit-log re-baseline

Resumed via `/pw-continue` at HEAD `2fff27594f`. Four focused pieces, all committed + dual-pushed
(origin + `chambem2/pwiz-sharp`); HEAD now **`732197a686`**, working tree clean.

**A - SkylineAiConnector -> net8 (`7a7bef4c72` + `0907f39e6b`).** Ported the MCP AI-Connector tool
(`Executables/Tools/SkylineMcp/SkylineAiConnector`) **single-target net8.0-windows** (NOT multi-target):
its `SkylineMcpServer` is already net8 and the tool's own `info.properties` mandates the .NET 8 Desktop
Runtime, so a net472 build has no purpose. Two real fixes beyond the TFM: (1) the `PackageToolZip` glob
copied only `*.exe;*.dll;*.config`, dropping the net8 apphost's `runtimeconfig.json`/`deps.json` -> the
connector exe couldn't launch; added `*.json`. (2) the version stamp read an uncommitted
`Properties/AssemblyInfo.cs` and silently emitted an empty `Version` -- fixed by extracting a **central
`pwiz_tools/Skyline/SkylineVersion.targets`** (the YEAR.ORDINAL.BRANCH.DOY composition lifted out of
Skyline.csproj, verified byte-identical) that BOTH Skyline.csproj and the connector import, so the
tool-store version tracks Skyline automatically (now 26.1.1.203). `TestSkylineMcp` passes end-to-end
(47-tool protocol). **Interactive-tools tail SURVEYED but not ported** (Matt redirected to the AI
connector): ExampleInteractiveTool, TestInteractiveTool, TestCommandLineInteractiveTool (2 have
functional tests that install checked-in net472 zips -> porting the csproj is inert to those tests
unless the zips are rebuilt), SkyGadget, MPP Export, SkylineIntegration (4 third-party Tool-Store
contributions). Still backlog.

**B - Merged origin/master -> net8 branch (`546db8fd96`).** 60 commits (2026-06-30 merge-base ..
`8a32095c52`), bringing the DIA-NN search wizard, Osprey pass-2, mProphet ReplicateName, full-scan
viewer. 299 files auto-merged; **13 conflicts** resolved (full playbook in [[reference_net8_master_merge]]):
csprojs -> ours (net8 SDK globs master's new `<Compile>` items; carried TestPerf's `System.IO.Compression`
net472 refs; dropped master's win-x86 RIDs); PathEx.cs kept both sides' new methods; MProphetResultsHandler.cs
+ GroupComparisonStrings.zh-Hans.resx were whole-file LF-vs-CRLF conflicts fixed via EOL-normalized
`git merge-file` (some net8-branch files are accidentally LF). **One semantic gap the build caught:**
master added `MsDataFileImpl.CaptureOtherParams` to the legacy reader; ported it (~165 lines) into the
net8 pwiz-sharp sandbox `ProteowizardWrapper.PwizSharp/MsDataFileImpl.cs` (PascalCase pwiz-sharp API,
`spectrum.Params.CVParams`, no native `using` disposal). Verified: net8 TestFunctional build 0 errors;
`TestFullScanProperties` (exercises CaptureOtherParams) + `TestSkylineMcp` pass; CommonUtil net472 builds.
**NOTE:** the net472 *Skyline* build is pre-existingly broken (unconditional net8-only BlibBuild/BlibFilter
ProjectReference at Skyline.csproj:218) -- byte-identical pre-merge, NOT a merge regression; flagged, not fixed.

**C - BiblioSpec C++ -> C# port (`ff29f64323`).** The merge's ONLY C++ delta (core `pwiz/` C++ untouched
by master since 2026-06-10, already in the branch) was 2 BiblioSpec files; Matt asked to mirror them in
the pwiz-sharp C#. `BlibMaker.cs`: empty-result-build (DIA-NN 0 precursors) file-lock hardening --
non-throwing `File.Delete` in Init()/AbortCurrentLibrary() + `Verbosity.Warn` (parity with cpp error_code
`bfs::remove`; `_db.Dispose()` with the connection's Pooling=false = the managed `sqlite3_close_v2`).
`DiaNNSpecLibReader.cs`: tolerate DIA-NN 1.9.1's missing `Flags` column (nullable `FindDataField` defaulting
to 0; every other column stays required via `MustFindParquetField`). BlibBuild builds 0 errors.

**D - DIA-Umpire tutorial audit-log re-baseline (`732197a686`).** Ran the 4 non-EN audit-log tutorials Matt
flagged. **3 (TestIrtTutorial / TestMethodRefinementTutorial / TestPeakPickingTutorial) already pass in fr**
-- the culture-aware tolerance (`fcf2ea59f7`) clears the net8 shortest-round-trip number-format diffs, no
re-record needed. **TestDiaTtofDiaUmpireTutorial was a different, genuine re-baseline** (NOT culture/formatting):
its audit-log "Peptides mapped" count was stale at 101 in ALL 5 languages; net8's more-conservative OOP-MSAmanda
maps 97 (Peptide targets 102->98). Re-recorded en/fr/ja/tr/zh via `recordauditlogs=on perftests=on`
(~13 min/lang, conversion cache NOT reused across langs, ~67 min total) + re-verified fr passes a normal
(non-record) comparison. Only the 2 counts changed; localized text unchanged. The `.json` target counts already
pass on net8 (that's why the run reached the audit-log step). Legit re-baseline per [[reference_net8_rebaseline_vs_fix]].

**Status-map artifact refreshed** (https://claude.ai/code/artifact/eb82129b-c56b-440a-acf7-52343461dce2):
brought current to HEAD `732197a686` -- ported 36->67, method builders moved out of "out of scope", backlog
trimmed to ~10 (interactive tools + net7 + SetupDeployProject), BullseyeSharp the sole permanent net472, and
the tutorial audit-log item marked resolved.

**Remaining backlog:** interactive tools (6, above), net7->net8 (AdvancedEditingCommands, ToolServiceTestHarness),
SetupDeployProject (verify it's a normal SDK project vs VS-deploy/WiX first), LaunchBatch (deferred, ClickOnce).
Non-blocking follow-ups: fresh CI run on the merged head `732197a686`; the pre-existing net472 Skyline BlibBuild
reference (gate to net8 if the net472 Skyline build is wanted); rebuild shipped arg-collector artifacts
(QuaSAR.dll / MSstats.zip / TurnoveR.zip still net472 zh-CHS).

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260723_net8_merge_aiconnector.md` before starting work.

---

## 2026-07-30 — CI greening on the new AWS agent fleet; Waters TIC root-caused

Branch head `6fd75a5e16`. Core Windows .NET went from 13 failures to 2; every remaining failure is
understood. Everything below is pushed to both `Skyline/work/20260612_net8_port` and `chambem2/pwiz-sharp`.

**A - Bruker DDA-PASEF IM-range (`bea9869f81`).** `TdfData.FillSpectrum` gated the `ion mobility
lower/upper limit` userParams on `preferCentroid && tag.Combined`, but cpp `SpectrumList_Bruker.cpp:382-387`
emits them for EVERY combined TDF spectrum, independent of centroid and before the FullData block. The
test doc is `precursor_mass_analyzer="tof"`, so Skyline never requests vendor-centroided MS1 and the range
was dropped; `SpectrumFilterPair.IsOutsideSpectraRangeIM` then could not tell "library IM outside the
instrument ramp (no value)" from "no signal in range (zero)" and mis-filtered row 0 of the report
(heavy `ILDDLSPR`, library IM 0.825 vs ramp min 0.8505). Verified: `BrukerPrmPasefImportTest` passes.

**B - Core-build Bruker references (`b46ec2709c`).** The reader emits the canonical 4-field combined-IMS
native id (`merged=N frame=F scanStart=S scanEnd=E`, cpp `:785`, upstream since 597f6124ab/2019); the
*profile* combineIMS reference mzMLs in `Reader_Bruker_Test.data.tar.bz2` still had plain `merged=N` AND
lacked the IM-range userParams, while the `-centroid` siblings were already correct. That archive is
gitignored + extracted at build time, so the fix is the sanctioned per-project override:
`pwiz-sharp/pwiz/test/Bruker.Tests/Reference/` (plus a `None Update="Reference\*.mzML"` item, a README, and
the hardcoded `TimsBinaryDataSmokeTests` assertion). **Remove once the .tar.bz2 is regenerated.**

**C - Agilent x11: VC++ 2013 runtime (`fd93d30f57`).** Every Agilent test failed on a fresh agent with
`Could not load ... BaseTof.dll. The specified module could not be found.` That is ERROR_MOD_NOT_FOUND
(0x8007007E) = a missing DEPENDENCY, not a missing file (0x80070002). `BaseTof.dll` is the only
mixed-mode (C++/CLI) DLL in Agilent's MHDAC set - its PE import table lists MSVCR120/MSVCP120 - while the
others are pure managed, which is why the tests reached `CalibrationMgr..ctor()` first. Now staged
app-local from the copies pwiz already vendors (`pwiz_tools/Shared/Lib/Microsoft.VC120.CRT/x64`). These
also flow into MsConvert's output, so `installer/Setup.iss`'s StagingDir glob ships them to END USERS.
Verified on a bare AWS agent: 11/11 pass.

**D - Inno Setup bootstrap (`3b338d3805`).** `jrsoftware.org/download.php/is.exe` no longer redirects to
the binary - it lands on the `isdl.php` HTML page (10 KB `text/html`, first bytes `3C 21`). The script
saved that as `.exe` and failed to launch it ("file or directory is corrupted"). Now pins the official
GitHub release (innosetup-6.7.3.exe) and VALIDATES every download (size, PE `MZ` magic, Authenticode)
with retries. Confirmed in CI: ISCC installs and the installer compiles.

**E - Linux port committed + scripts (`544af26cb6`, `77c67ff184`, `3651d8dcf2`).** Committed another
agent's Linux work after review: central `$(SevenZaExe)` (7za.exe/7zz per OS), new
`$(NativeVendorsAvailable)` (= licenses AND Windows; Thermo's SDK is managed/cross-platform, the rest wrap
native Windows DLLs), forward-slash paths, `lockmassRefiner` gating, plus two real bug fixes (POSIX
`file:///` parsing that silently dropped every MS_SHA_1; a `WiffFile` finalizer null-guard). Added
`pwiz-sharp/build.sh` + `tcbuild.sh` (mode 100755) mirroring the .bat files minus the Windows-only legs
(installer, NativeAOT/CTest, dotCover), with dotnet-location probing.
**CAUTION learned the hard way:** commit `51606950e1` shipped half of that agent's change (an
auto-normalized `Agilent.csproj` that DROPPED the `SevenZaExe` property) without the
`Directory.Build.props` half -> empty 7-zip command -> exit 9009 -> 0 tests -> test-count guard failed BOTH
agents. Always diff the whole working tree against the last good commit before committing someone else's
edits.

**F - `41a3558634` regression fix.** My own E commit broke Waters/Bruker/Sciex on Windows: the Linux
`file:///` fix assumed 3 slashes, but Waters/Bruker/Sciex emit `file://` + path (cpp is inconsistent), so
`C:\dir` fell into the POSIX branch as `/C:\dir` and every MS_SHA_1 vanished. Handles all three shapes now.
Waters 13->0 failed, Bruker 3->0, Sciex 7->0.

**G - Waters TIC discrepancy: ROOT-CAUSED, fix not yet written.** `ATEHLSTLSEK_LM_684/785` spectrum[5]
`MS_TIC` = ours `1.63409e05` vs reference `1.63408e05` on CI, but PASSES locally at the same commit.
Falsified in order: (1) formatter tie-break - an Agilent tie (`163526.5` -> ref `163527`) proves cpp rounds
away-from-zero, which `PwizFloat` already does, and switching to half-to-even fixed Waters but broke
Agilent; (2) the lossy `value / Math.Pow(10, exp)` mantissa division in `PwizFloat.Format` - real (it turns
the exact tie 163408.5 into 1.63408500000000000973) but NOT the cause, since away-from-zero yields 163409
either way; (3) wrong TIC branch - a diagnostic showed BOTH machines take source A with identical
`defaultArrayLength=1154`. **Actual cause:** we read the scan stat as TEXT
(`WatersRawFile.GetScanItem` -> `TryParseDouble`) and MassLynx's own float->string formatting puts
`163408.5` on a rounding tie, so the SDK returns `"163408"` on one machine and `"163409"` on another
(every non-tie scan matches byte-for-byte). **cpp is immune because it reads the value numerically:**
`pwiz/data/vendor_readers/Waters/SpectrumList_Waters.cpp:240` uses
`GetScanStat<double>(..., MassLynxScanItem::TOTAL_ION_CURRENT)`. That is why bt83/bt17 pass on the SAME
AWS agents against the SAME reference mzML.
**=> The fix is to add a typed numeric scan-stat accessor to `WatersRawFile` and use it instead of parsing
the SDK's formatted string** (`SpectrumList_Waters.cs:471-483` also reads base peak m/z, base peak
intensity and PeaksInScan the same lossy way). NOT a `DiffPrecision` loosening and NOT a re-baseline -
both would paper over a genuine port defect. `TicSourceDiagnostic.cs` (`67b9b2ed68` + `6fd75a5e16`) is
TEMPORARY and must be deleted with that fix.

**H - VCS trigger (`6fd75a5e16`).** `pwiz-sharp/.*` now triggers Core Linux .NET as well as Core Windows
.NET (was Windows-only, so cross-platform regressions only surfaced by luck).

**Agent-fleet findings (not code):** a stale AWS Windows instance had only SDK 9.0.311 while
`pwiz-sharp/global.json` pins `8.0.100` with `rollForward: latestFeature` (rolls forward only inside
8.0.x, NOT to 9.x) -> build dies before compiling, 0 tests, test-count guard fails. The Linux agents have
NO dotnet at all (probed /usr/bin, /usr/local/bin, /usr/share/dotnet, /usr/lib/dotnet, $DOTNET_ROOT,
~/.dotnet - and no dangling symlink either), so `build.sh`/`tcbuild.sh` are still unvalidated end-to-end.
The Linux VCS checkout dir is literally `/home/teamcity/agent/work/C:/pwiz` (a `C:` directory on Linux).

**Also investigated, do NOT redo:** Waters MassLynx SDK 5.0.0 was trialled and REVERTED (archive
byte-identical to HEAD). It does not fix the TIC (both 4.9.0.0 and 5.0.0 return the same scan-stat), and
it requires a Waters license key (`createRawReaderFromPath` gained a `userLicense` arg; without it every
read fails "License invalid"), removes 12 exports the cpp tree links against (`centroidRaw` etc.), drops
`cdt.dll`, and newly fails 2 tests by returning `SET_MASS` at full float precision. Benchmarked PR #4500
(cpp `toString` round-trip) at **+1.4-1.8% (~3-4 s on 221 s)** for a 2.5 GB Thermo DIA .raw->mzML.

**Current CI:** Core Windows .NET 414/416 (only the 2 Waters TIC). Core Linux .NET blocked on dotnet.
Full local pwiz-sharp suite is green on the branch as pushed.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260730_net8_aws_agents_waters_tic.md` before starting work.

---

## 2026-08-03 -- Core Linux .NET green end-to-end; Waters runs on Linux

Branch head `6622504f53`. **Both CI legs green on the same commit: Core Linux .NET 329/329
and Core Windows .NET 418/418.** Core Linux went from "cannot compile" to running eight test
suites including two vendor suites. Everything below is pushed to both
`Skyline/work/20260612_net8_port` and `chambem2/pwiz-sharp`.

**A - Waters TIC closed properly (`331f1b77dd`).** The previous session's root cause was wrong:
cpp is NOT immune by reading the stat numerically. `GetScanStat<double>` (WatersRawFile.hpp:344)
calls the string overload then lexical_casts, and `MassLynxParameters::Get` bottoms out in the
same `getParameterValue` we P/Invoke, so both read the identical formatted string. There is no
numeric accessor to switch to. The real difference: `Reader_Waters_Test.cpp:71` sets
`config.diffPrecision = 1e-5` on the base config every variant copies, and the C# port dropped
it, leaving the default 1e-6. The SDK's own float->string is not reproducible across hardware
for tie values -- the committed diagnostic showed `GetScanItem(func=1,scan=2,TIC)` returning
"163408" here and "163409" on CI from the same call on the same file -- and 1/163408 = 6.1e-6
sits between the two tolerances. Restoring 1e-5 is porting cpp's declared tolerance, not
loosening ours. As in cpp, that precision also governs binary-array comparison (Diff.cpp:355).

**B - Waters SDK 5.0.0 + Linux .so (`6b905b4039`).** Diffing export tables against our 62
P/Invoke entry points (honouring the one `EntryPoint` override, `getChannelDesciption` -- the
vendor's own typo) showed exactly one missing symbol in 5.0.0, `getVersionInfo`, declared but
never called. The 12 removed exports that would break the cpp build (`centroidRaw`, the status
API) are irrelevant to P/Invoke. Archive goes in `pwiz-sharp/vendor-archives/` like Thermo, NOT
over the cpp copy. `createRawReaderFromPath` gained a mandatory `userLicense`; the key ships in
the encrypted archive (user's call: decrypting it requires the password, which is the act of
agreeing to the vendor licenses). cdt.dll is gone -- folded into MassLynxRaw.

**C - Linux build fixes.** Checkout dir was literally `.../work/C:/pwiz`; a `C:` directory
breaks MSBuild's wildcard glob (reproduced with a hello-world project) -- fixed agent-side.
Then, in order: hardcoded `7za.exe` in Waters/Bruker/Mobilion (`138fdbe772`); backslash 7z
member patterns that make 7zz match nothing and still exit 0; `pwsh` on the compile path
replaced by `build/VendorPinsGenerator` + `build/vendor-sdk-pins.json`; `NativeVendorsAvailable`
gating applied to the six Windows-only vendors; `Reader_Shimadzu` not compiling in no-vendor
mode (`5c3636e150`, latent -- every Windows build sets the licence flag so that path was never
compiled); MsConvert's Sciex staging under the wrong gate (`d0d6aed52e`).

**D - `dotnet test` "invalid argument" was a missing assembly (`1e8fe49e78`).** All 8 suites died
with `The argument .../Util.Tests.dll is invalid`. That is what vstest prints when the source
does not EXIST -- build.sh only built MsConvert + Thermo, never the test projects, then ran
`--no-build`. Two commits chased the arguments first (`7199507440`, `afa86a3cbe`); the argv echo
added there is what settled it, by showing the invocation was identical to one that passes.
Results now reach TeamCity via `##teamcity[importData type='vstest']` per suite (user's
suggestion) -- no build-config change needed, and it works where `--logger:teamcity` does not.

**E - mz5 use-after-free (`9b607858c5`).** `Mz5ReferenceRead.Fill` reclaimed the HDF5 vlen CVRef
strings "now that all param-container fills are done", but the spectrum/chromatogram lists
constructed three lines earlier resolve CVIDs lazily at GetSpectrum time. Windows passed by
luck (freed block still held "MS"); glibc reuses it, so every lazily-resolved param came back
CVID_Unknown, stripping MS_m_z_array/MS_intensity_array and reading every spectrum as empty.
Resolve the whole table into the memo before reclaiming, then drop the array. Also
`f89282e5f2`: 14 `H5T.NATIVE_ULONG` declarations backed 4-byte uints -- fine on Windows LLP64,
8 bytes on LP64.

**F - Waters on Linux, 21/21 (`bc91058a5f`, `6622504f53`).** With the agents on Ubuntu 22.04 the
SDK loads (it needs GLIBC_2.32 / GLIBCXX_3.4.29; 20.04 fails with "cannot open shared object
file", which is dlopen reporting an unmet DEPENDENCY -- same trap as Agilent's
ERROR_MOD_NOT_FOUND). Then 8 failures, three causes: MassLynx writes `_FUNC001.DAT` but
`_func001.cdt`, so deriving the .cdt name found nothing on a case-sensitive filesystem and IMS/
SONAR silently switched off (6 tests) -- all .raw lookups now go through `WatersRawDirectory`;
`PtrToStringAnsi` is UTF-8 off-Windows so the "<degree>C" analog unit became U+FFFD and the
channel was typed EMR-radiation instead of temperature (1 test) -- explicit CP1252 now; and the
SDK's own centroid algorithm returns different peak COUNTS on Linux vs Windows (3789 vs 3791),
which no tolerance can absorb, so that variant is compared on Windows only.

**Also:** `0a1ec40724` test data extracted with system tar off-Windows (`bsdtar.exe` gave "Exec
format error", swallowed by IgnoreExitCode while the sentinel was touched anyway -- that is why
one Thermo fixture was missing and its test Inconclusive). `443cb8042c` consolidated
`Reader_ThermoTests` into `ReaderThermoTests` (Thermo was the only vendor with two reader test
classes); 15/15 unchanged. `9fb039d4a7` fixed `--` inside XML comments in ExtractTestData.targets
which broke every importer on BOTH platforms -- a .targets file parses fine until something
imports it, so always build an importer after editing one.

**Local Linux repro (important for the next session).** WSL Ubuntu 20.04 was replaced with
22.04 (`wsl --install -d Ubuntu-22.04 --no-launch`, .NET 8.0.423 under /root/.dotnet). Two
conditions must BOTH hold to reproduce agent behaviour: 22.04 for glibc, and a case-sensitive
filesystem -- `/mnt/c` is DrvFs and case-INSENSITIVE, so the .cdt bug cannot reproduce through
it. Build on /mnt/c, then copy the fixtures + bin onto ext4 preserving
`<root>/pwiz/data/...` beside `<root>/pwiz-sharp/pwiz/test/...` (FindTestDataRoot walks up for
it). Script: `ai/.tmp/` handoff has the path. This loop is far more reliable than CI right now:
the Linux agents cancel with "Could not connect to build agent ... didn't respond within 60
seconds" fairly often, which the user confirms is a known unexplained problem.

**Open / next:** Bruker on Linux is the obvious follow-on -- a `libtimsdata.so` (18 MB) exists at
`D:\Downloads\FragPipe-22\fragpipe\tools\diann\1.8.2_beta_8\linux`, bundled by DIA-NN. Bruker is
currently gated Windows-only via `NativeVendorsAvailable`. Provenance/redistribution needs a
decision before vendoring a third-party bundle's copy rather than one obtained from Bruker.
Also still inconsistent: `Bruker.Tests` / `Sciex.Tests` / `BiblioSpec` gate on
`IAgreeToVendorLicenses` where the products they test now gate on `NativeVendorsAvailable` --
harmless only because build.sh does not build them on Linux.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260803_net8_linux_green_waters.md` before starting work.

## 2026-08-03b -- Bruker on Linux; BAF path tested for the first time

Follows straight on from the entry above. **Bruker.Tests 11/11 green on Linux (ext4,
case-sensitive) and 11/11 on Windows**, up from 10 tests / Windows-only. NOT COMMITTED -- the
user asked to hold until the vendor-archive layout was settled, and it now is (see A).

**A - Two archives, one per OS (user's call).** The Linux `.so` files go in a NEW
`pwiz_aux/msrc/utility/vendor_api_Bruker_linux.7z` (6.1 MB) beside the untouched Windows
`vendor_api_Bruker.7z` (10.7 MB); `Bruker.csproj` selects by `$(OS)`. Both `.so` compress to
~6.1 MB whichever shape is used, so size did not decide it -- the reason is that nobody should
download 32 MB of binaries for a platform they are not building for. (I had argued for the split
on a different ground -- `Jamroot.jam:620` extracts the Windows archive **wholesale**, `x -aoa`
with no member list, so folding the `.so` in would unpack 32.4 MB into every cpp build -- but the
user notes the cpp side is being sunset before this branch merges, so that argument does not
carry.) Internal layout mirrors the Windows one: `vendor_api/Bruker/linux_x64/`.

**B - SDK provenance is clean for timsdata, weaker for baf2sql.** `libtimsdata.so` comes from
Bruker's own `tdf-sdk-2.21` download, whose `redist.txt` *explicitly* permits redistributing
`linux64/libtimsdata.so` provided `THIRD-PARTY-LICENSE-README.txt` ships with it (it does, in the
archive). Decisive check: that download's `win64/timsdata.dll` is **byte-identical (sha256) to
the timsdata.dll already in our Windows archive**, and its license readme is byte-identical to
ours -- so the `.so` is the exact Linux sibling of what we already ship, no version skew. This
supersedes the previous session's FragPipe/DIA-NN `libtimsdata.so` idea, which had no redist
grant. `libbaf2sql_c.so` came from the third-party `gtluu/pyBaf2Sql` repo (user's call to ship
it); it exports all 10 baf2sql_c functions, exactly matching the archive's `baf2sql_c.h`, but has
no equivalent redist grant. Worth replacing with Bruker's own baf2sql SDK if one turns up.

**C - BAF was completely untested, and was broken.** `Baf2SqlData.cs` was a full port but no test
touched it (`BrukerFormat.cs` even called BAF "Not ported yet"), while an unused BAF fixture
`CsI_Pos_0_G1_000003.d` + reference mzML sat in the tree. Added
`Reader_Bruker_CsI_Pos_0_G1_000003`; it failed immediately on Windows with 3 metadata diffs. The
reader itself was fine -- `Reader_Bruker.cs` hardcoded the **timsTOF** metadata shape: always
`TIMS_SDK` software and always a 5-component quad/TOF/MCP/PMT chain. cpp switches both on
sub-format and instrument family. Ported properly: `AddApiSoftware` (BAF2SQL / TIMS_SDK /
CompassXtract, per `Reader_Bruker.cpp:126-149`), plus `TranslateInstrumentFamily` (raw metadata
code -> SDK enum; 512 -> FTMS), `TranslateInstrumentSeries` and `AnalyzerAndDetectorComponents`
(ports of `createInstrumentConfigurations` + `translateAsInstrumentSeries`). CsI is an apex
FT-ICR: BAF2SQL + apex series + ESI/FT-ICR/inductive-detector, 3 components. **The timsTOF
fixtures were unregressed because all three report family=9** -- the old hardcoding was right for
timsTOF and wrong for everything else.

**D - Two genuine Linux product bugs, both in the source-file SHA-1 path.** The single remaining
Linux diff was `sourceFile[...\Analysis.baf]: cvParam b-only: MS_SHA_1`, on all 4 reader tests:
1. `Reader_Bruker.AddPairedSourceFiles` built the location as
   `"file://" + analysisDir.Replace('/', '\\')` -- a Windows-ism that turns a POSIX path into one
   unusable filename. cpp uses `bfs::path::string()`, i.e. the *native* separator. Now conditional
   on `Path.DirectorySeparatorChar`.
2. pwiz records the canonical spelling `Analysis.baf` while Bruker writes `analysis.baf` on disk
   (cpp hardcodes the capital A at `SpectrumList_Bruker.cpp:631`, and probes *both* spellings when
   opening -- `Reader_Bruker_Detail.cpp:115`). `File.Exists` matches either on Windows and neither
   on Linux, so the checksum was **silently skipped** rather than failing loudly.
This is a product bug, not a harness artifact: `MSDataFile.CalculateSourceFileSha1` has the same
logic, so msconvert would quietly omit SHA-1 for Bruker on Linux. Fixed with a shared
`Filesystem.FindFileIgnoringCase` (exact-match fast path, then a case-insensitive scan) used by
both the product and `VendorReaderTestHarness`. Same bug class as Waters' `_func001.cdt`.

**E - Runtime env: `libgomp1` is REQUIRED on Linux agents.** `libbaf2sql_c.so` links
`libgomp.so.1` (OpenMP); `libtimsdata.so` does not. Without it the BAF test fails with
`libgomp.so.1: cannot open shared object file`, which -- exactly as the previous session warned --
is dlopen reporting an unmet **dependency**, not a missing file. `libtimsdata.so` is otherwise
far less demanding than the Waters `.so`: GLIBC_2.14 max and no libstdc++ link at all, so it
would even run on 20.04. **Unverified whether the TeamCity Linux agents have libgomp1** -- if the
CsI test is the only red one in CI, that is the cause.

**Two false leads worth not repeating.** (i) The `libdl.so: cannot open shared object file` spew
is **noise, not a failure**: System.Data.SQLite's pre-loader tries the `win-x64` interop first,
fails via `DllImport("libdl")` (glibc >= 2.34 ships only `libdl.so.2`), then falls back and
succeeds. `No_PreLoadSQLite=1` changes nothing; I briefly mistook it for the blocker.
(ii) Verifying the no-vendor gate is booby-trapped twice over: `Directory.Build.user.props` is
gitignored and sets `IAgreeToVendorLicenses=true` **machine-wide**, so a "no licence" build
silently has the licence on -- pass `-p:IAgreeToVendorLicenses=false` explicitly. Both gates are
now verified cold on both OSes (Linux: false -> exit 0, nothing staged; true -> exit 0, exactly
the two `.so` and none of the Windows DLLs).

**Local repro**: `<scratchpad>/bruker_ext4.sh` (modes: summary / raw / detail / deps) and
`bruker_novendor.sh`. Work dir is **`/root/b`, not `/tmp`** -- the distro shuts down between `wsl`
invocations and /tmp is cleared on restart, which silently destroys the staged tree and makes
diagnostics like `ldd $BIN/foo.so` quietly "succeed" on a path that does not exist. The scripts
now assert staging, case-sensitivity and unmet `.so` deps before drawing any conclusion.
msconvert cannot be built from WSL here: Vendor.Common's pins generator shells out to git and
this checkout is a Windows git **worktree** (`.git` -> `C:/dev/pwiz/.git/worktrees/pwiz-net8`,
meaningless inside WSL). Local-environment limit only; CI builds from a normal clone.

**Open / next:**
1. **Native vendor SDKs are unreachable at runtime in the installed MSI (pre-existing, affects
   Waters today).** `VendorSdkLoader` hooks only `AssemblyLoadContext.Default.Resolving`, which
   fires for **managed** binds; there is no `SetDllImportResolver` / `ResolvingUnmanagedDll`
   anywhere in pwiz-sharp. Bruker's `timsdata`/`baf2sql_c` and Waters' `MassLynxRaw` are native,
   bound by `DllImport`, which goes to the OS loader instead. Meanwhile `vendor-sdk-pins.json`
   lists those native prefixes and `installer/build.ps1:103-108` **strips** any matching
   `.dll`/`.exe` from the MSI -- so the installed product should throw `DllNotFoundException` on
   both. Unseen because `AssertMsconvertSmokes` only exercises Thermo, which is managed.
   Fix = `NativeLibrary.SetDllImportResolver` routing through the already-`public`
   `VendorSdkLoader.EnsureExtracted`; **and per the user, add Waters + Bruker smoke tests to the
   installer so the native DLL-finding path is actually exercised.** That work also needs a pins
   entry for the new `vendor_api_Bruker_linux.7z` (currently unlisted).
2. Confirm `libgomp1` on the Linux agents (see E).
3. Carried over: restore the `NET8-PORT TEMP` blocks in
   `scripts/misc/vcs_trigger_and_paths_config.py` (bt83 / bt17) before merge; drop
   `Bruker.Tests/Reference/` once `Reader_Bruker_Test.data.tar.bz2` is regenerated; the
   `Sciex.Tests` / `BiblioSpec` gate inconsistency (Bruker's is now resolved -- it gates on
   `IAgreeToVendorLicenses` like the product does).

### Ported-but-untested audit (dotCover over all 18 Windows-runnable suites, 439 tests green)

Prompted by the BAF find: if one whole ported class could sit untested and broken, what else?
Snapshot merged from every suite incl. the vendor ones. **927 statements in the core port have
never executed.** Scripts: `<scratchpad>/Run-Coverage.ps1` + `parse_coverage.py` (and
`coverage_survey.py` for the static fixture/name pass).

Method notes, because two passes produced numbers that were wrong before they were right:
- A static "type name never appears in a test" pass over-reports badly - `Mz5ReferenceRead` and
  `TdfData` are reached only through interfaces yet are demonstrably exercised. Only
  instrumentation separates "reached via a factory" from "never runs". Use dotCover, not grep.
- That static pass ALSO under-reports: it initially cleared `Baf2SqlData` purely because a
  *comment* names it. Strip comments from the test side before harvesting identifiers.
- First dotCover run reported `Pwiz.Vendor.UNIFI` at **1%**; that was an omitted suite
  (`UNIFI.Tests`, 44 tests), not a coverage gap. Corrected it reads **62%**, and the
  never-executed total fell 4528 -> 927. Enumerate test projects from disk, do not hand-list.

**Never executed, worth acting on:**
- **`SpectrumList_ChargeFromIsotope` - 675 statements, zero.** With its helpers in the same file
  (`ParentSpectrumCache` 24, `CachedParent` 7, `RtimeMap` 5, `MsvcRand` 5) that is ~716
  statements. NOT dead code: it is the user-facing **`turbocharger`** msconvert filter, wired up
  at `SpectrumListFactory.ParseTurbocharger` (`SpectrumListFactory.cs:972`). Highest-value gap in
  the port by a wide margin, and precisely the BAF shape - a large, plausible-looking port that
  nothing has ever run.
- `Proteome.EnumerateNonOrSemiSpecific` (32) - non/semi-specific digestion never exercised.
- `DiaUmpire.LinearInterpolation` (47); `PeakPicking.Peak` (10); `Diff.DiffResult<T>` (12);
  `Obo.RelationEntry` (6); `IdentData.DatabaseTranslation` (5).
- `MsConvert.Program` + `ConsoleProgressListener` (27) - the CLI entry point is never run
  in-process; MsConvert.Tests exercises the library beneath it.
- `VendorSupportNotEnabledException` (6) - the NO_VENDOR_SUPPORT error path has no test, on any
  vendor. Cheap to add and it guards a user-visible message.
- Vendor odds and ends: `WatersPusherInterval` (13), `UimfDriftScanInfo` (14), PrmScheduling
  `CollisionEnergyRamp` (12) + `VisualizationDataPoint` (9).

**Barely covered (<25%, >=20 statements):** `Util.ModificationList` 20%, `Util.ModificationMap`
24%, `Common.Diff` 12%.

**Assembly statement coverage, lowest first:** PrmScheduling 41%, msconvert 57%, UNIFI 62%,
Thermo 64%, Bruker 68%, Sciex 72%, Shimadzu 73%, Analysis 74%, TraData 75%, Util 75%,
Agilent 77%, Common 78%, UIMF 81%, Mobilion 82%, MsData 83%, Waters 85%, IdentData 92%.

**Unused vendor fixtures already on disk (free tests, same as CsI was):**
- **`ThyroglobMRM000003.d` - a TDF fixture with 11 reference mzMLs and no test at all.** The
  direct analogue of the CsI find, and bigger. Do this one next.
- `100 fmol BSA` (FID) and `Sample_1-A,1_01_985.d` (YEP) are correctly untested - neither format
  is ported (YEP needs CompassXtract, COM and Windows-only forever).
- Reference variants present but not exercised by fixtures that DO have tests: Bruker
  `Hela_QC_PASEF` 6 of 13 and `20percLaser` 1 of 3 (both already noted in code comments);
  Agilent 11 configs across `ImsSynthAllIons` (4), `ImsSynthCCS` (3), `ImsSynth_Chrom` (3),
  `GFb_4Scan` (1). Waters is 13/13 complete.
- False positive to ignore: `diaPASEF.d` reads as 0 configs because `TimsBinaryDataSmokeTests`
  asserts directly instead of going through the harness's `ctx.Run(`.

### ThyroglobMRM000003 fixture added -- 1 product bug (Bruker.Tests now 12/12 both OSes)

Acting on the audit's top find. `Reader_Bruker_ThyroglobMRM000003` runs the **6** configs C++
still runs for a TDF, all against git-tracked references. The CsI pattern repeated: a ported
path nothing had ever executed was wrong.

**Bug - collision energy emitted where C++ emits none.** We put `MS_collision_energy = 33.0 eV`
on every MS2 precursor. For a plain MS2 frame - neither PASEF nor DIA-PASEF - C++ constructs its
`IsolationInfo` with the energy **hardcoded to 0** (`TimsData.cpp:1180`) and only emits the
cvParam when non-zero (`SpectrumList_Bruker.cpp:367`), so nothing reaches the mzML even though
`FrameMsMsInfo.CollisionEnergy` holds a real value. Looks like a C++ oversight, but the
references encode it. Evidence is unambiguous and *tracked*: the four tracked Thyroglob
references carry 550 precursors between them and **zero** collision-energy params. Fixed in
`TdfData.cs`; the PASEF/DIA paths there already matched C++ and were left alone.

**IMPORTANT - which references are authoritative.** `Reader_Bruker_Test.cpp:131` sets
`config.peakPicking = true` and **never clears it**, so every narrowed config C++ runs today
writes a `-centroid` reference. C++ therefore does not generate `-ms1`, `-ms2`, `-combineIMS`,
`-combineIMS-ms1` or `-combineIMS-ms2` at all - those are leftovers in the `.tar.bz2` from an
older revision of the test, which is exactly why C++ master is green despite their contents
disagreeing with their own tracked siblings (chromatogram presence, and in `-ms2` the
ion-mobility values, shifted one TIMS scan). The cpp data dir is gitignored wholesale
(`.gitignore:409`) and **the force-added set is precisely the set C++ still produces** - that
correspondence is the cheapest way to tell an authoritative reference from a stale one.

**Two things this corrected, both mine, both caught by Matt asking "why would these tests pass
on C++ in current master?":**
1. I had "fixed" the chromatogram-list suppression rule to also cover `preferOnlyMsLevel`,
   claiming verification against all 32 references. That verification was worthless: the
   *suppress* half of the rule came entirely from the stale files, and **no tracked reference
   distinguishes the old rule from the new one**. It was a product-behaviour change (msconvert
   output) justified by an artifact C++ no longer emits - the re-baseline-vs-fix trap in
   `reference_net8_rebaseline_vs_fix`. Reverted, with a comment at the site explaining why not to
   redo it.
2. I had generated corrected `-combineIMS` / `-combineIMS-ms2` / `-ms2` overrides. Dropped -
   testing a hand-corrected copy of a reference nothing generates asserts our own output back at
   us. The profile-combined path stays covered by Hela's pre-existing overrides, and
   `-combineIMS-ms1` only "passed" because its spectrum list is empty. `Reference/` is unchanged
   from master.

**Harness improvement (kept):** the diff failure message now leads with the reference filename
(`[<file>.mzML] MSData diff: ...`). With many configs per fixture the old message named only the
`.d` directory; I mis-attributed a failure because of it before adding this.

Regression: Bruker 12/12 Windows AND Linux; MsData 70, Analysis 132, Thermo 15, Waters 21,
Agilent 11, Sciex 7, MsConvert 16 - all green.

**Follow-up for the audit's section C:** the "unexercised reference variants" it counted for
Bruker and Agilent are mostly these stale non-centroid files. Before treating any of them as a
coverage gap, check the vendor's `Reader_*_Test.cpp` for where it sets `peakPicking` - the
tracked-vs-untracked split in the data dir tells you the same thing faster.

### Native vendor SDKs now resolve at runtime; libgomp bundled; installer smokes widened

Closes the gap found during the Bruker Linux work. Three parts, all verified by experiment
rather than by inspection.

**1 - `VendorSdkLoader` now hooks native resolution.** It only ever hooked
`AssemblyLoadContext.Resolving`, which fires for **managed** binds; Bruker's `timsdata` /
`baf2sql_c` and Waters' `MassLynxRaw` are native, bound by `DllImport`, which goes straight to
the OS loader. Meanwhile `installer/build.ps1` strips every `.dll`/`.exe` matching a
`vendor-sdk-pins.json` prefix - including those three - so the installed MSI could not read
Bruker or Waters at all, while Thermo/Sciex/Agilent worked. Added
`RegisterNativeResolver(Assembly)` over `NativeLibrary.SetDllImportResolver`, matching the same
pin table and falling back to `EnsureExtracted`. `RegisterAssemblyResolver` now auto-registers
it for every `Pwiz.Vendor.*` assembly via the `AssemblyLoad` event plus a sweep of what is
already loaded, so a new vendor reader is covered the day it is added - deliberately, since this
bug existed because the native half was overlooked. The resolver returns `IntPtr.Zero` (defer to
default probing) whenever the library is already staged, so dev/CI builds are unaffected.

**Verified end-to-end without building an MSI:** `<scratchpad>/Verify-NativeResolver.ps1` applies
the installer's own strip rule to a real msconvert build (86 vendor binaries removed, including
all three natives) and converts a fixture per vendor. Waters converts with 9 spectra despite
`MassLynxRaw.dll` being gone, and `%LOCALAPPDATA%\ProteoWizard\vendor\Waters-6b905b4039ce\
MassLynxRaw.dll` confirms where it came from.

**2 - libgomp bundled + preloaded, so Linux agents no longer need `libgomp1`.**
`libbaf2sql_c.so` links `libgomp.so.1`; `libtimsdata.so` does not. The 298 KB library (GPLv3
**with the GCC Runtime Library Exception**, which is what permits shipping it beside a non-GPL
app - its copyright file travels in the archive) now rides in
`vendor_api_Bruker_linux.7z`. Bundling alone is NOT enough and this was proven, not assumed:
the vendor built `libbaf2sql_c.so` with an `RPATH` pointing at their Jenkins workspace and no
`$ORIGIN`, so the loader never searches the app directory for dependencies. `NativeInit`
preloads it by absolute path, which puts it in the process under its soname for the later
`dlopen` to resolve against. Hiding the system copy: bundled+preloaded gives 12/12, removing the
bundled copy too gives the original `libgomp.so.1: cannot open shared object file`.
Hooked from `NativeMethods`'s **static constructor**, not `[ModuleInitializer]` - CA2255 rejects
module initializers in libraries (they run on any use of the assembly), while a static ctor is
guaranteed to run immediately before the first P/Invoke on that type, which is exactly the right
moment. Note the bundled build needs GLIBC 2.34 (higher than either Bruker library); on an older
distro the preload silently fails and the system copy is used, so bundling can only help.

**3 - Installer smoke tests cover the native vendors.** `AssertMsconvertSmokes` ran only a
Thermo fixture - a **managed** SDK - which is precisely why the native gap survived. It now
converts one fixture per resolution path: Thermo (managed), Waters `Minimal_DDA.raw`
(MassLynxRaw), Bruker `20percLaser_100fold_1_0_H6_MS.d` (timsdata/TSF) and
`CsI_Pos_0_G1_000003.d` (baf2sql_c/BAF); both Bruker fixtures are needed because the two natives
are stripped independently. A missing fixture skips just that vendor and only an empty run is
Inconclusive, so one absent checkout can no longer pass the rest off as verified. Fixture lookup
generalised to `TryFindVendorFixture` with a `PWIZ_<VENDOR>_TEST_DATA` directory override
(replaces the Thermo-only `PWIZ_THERMO_FIXTURE`, which nothing referenced) and now accepts
directories, since Waters `.raw` and Bruker `.d` fixtures are directories.

**4 - Deadlock in `VendorSdkLoader.ExtractArchive` (found by the above, fixed).** It set
`RedirectStandardOutput` + `RedirectStandardError` and then called `WaitForExit()` **before**
reading either stream - the textbook pipe deadlock. 7za prints a line per extracted file, and
once that fills the OS pipe buffer (a few KB) 7za blocks writing while we block waiting, and
neither side moves again. The archives that had ever been extracted at runtime hid it: Thermo and
Waters hold a handful of files each and fit in the buffer. Bruker's holds **89** and hangs every
time - the extraction sat at exactly 50,743 KB with msconvert alive but making no progress, which
is what "slow" turned out to be. It stayed latent because pwiz-sharp's Bruker reader is pure
P/Invoke with no managed Bruker assemblies, so the managed resolver never triggered a Bruker
extraction; the new native resolver is the first code to do so. Fixed with event-driven
`BeginOutputReadLine` / `BeginErrorReadLine` before the wait (no async/await).

Worth remembering as a class: any archive big enough to be worth caching is big enough to
overflow a pipe buffer, so `Process` + redirect + `WaitForExit`-then-read is always wrong here.

Note the first Bruker resolve on an installed machine costs a 10.7 MB download plus a **63 MB**
unpack (the archive is mostly the Windows-only CompassXtract/BDal stack; the two libraries
actually needed are timsdata.dll at 2.9 MB and baf2sql_c.dll at 16.9 MB), so Installer.Tests'
3-minute per-conversion timeout has less headroom for Bruker than for the others.

### Linux packages, and two more Windows-only assumptions on the same path

Everything below is committed and **pushed to both refs** (branch head `c5486d2a68`).

**Bruker Linux pin + OS-aware lookup (`5be232205b`).** The resolver could not fetch Bruker
natives on Linux: only `vendor_api_Bruker.7z` was pinned and it holds Windows DLLs, so Linux
worked solely because build.sh stages the `.so` files at build time. A second pin needs the
lookup narrowed, since both archives answer to the same prefixes and the old `FirstOrDefault`
would have downloaded 10.7 MB of Windows DLLs on Linux. `VendorSdkPin` gains an optional `Os`
and `FindPin` prefers an OS-specific entry over a generic one - which means **no existing entry
had to be relabelled**: on Windows the linux pin is filtered out and the unlabelled Bruker pin is
all that remains. Both resolvers share `FindPin`, so managed and native binds cannot disagree
about which archive a vendor uses. **Waters needed nothing**: its single archive carries both
platforms, so the existing pin already resolves `libMassLynxRaw.so` through the flatten and the
`lib<name>.so` probe - which is a further argument for having left that archive combined.

**Linux packages (`fa9ac5d1aa`).** `installer/build-linux.sh` mirrors `installer/build.ps1`:

| Windows | Linux | |
| --- | --- | --- |
| `ProteoWizard-Sharp-Setup-<ver>.exe` | `ProteoWizard-Sharp-linux-x64-<ver>.tar.gz` | 37.9 MB self-contained |
| `...-NoNetRuntime-Setup-<ver>.exe` | `...-NoNetRuntime-linux-x64-<ver>.tar.gz` | 5.7 MB framework-dependent |

`NoNetRuntime` is kept verbatim (it means the same thing on both); `Setup` gives way to the RID
because a tarball is not an installer. Version derivation, output dir, `installer-version.txt`
and the size/SHA-256 report all follow build.ps1. build.sh invokes it where build.bat invokes the
installer - vendor-only, warning-not-fatal. Only msconvert ships; MSConvertGUI and SeeMS are
`net8.0-windows` + WinForms.

**The counter-intuitive bit, which I got wrong first: build with licences ON, then strip.**
Publishing with `-p:IAgreeToVendorLicenses=false` bakes in `NO_VENDOR_SUPPORT`, so `Read()`
throws no matter what the resolver later fetches - the payload looks right and is inert. That is
why build.bat gates the installer on `IAGREE==1`. The strip is also an assertion now: packaging
aborts if a vendor binary survives, because the failure mode is redistributing a licensed SDK,
not an oversized artifact. It matches `lib<name>.so` as well as `<name>.so`, since the DllImport
name is `timsdata` but the file is `libtimsdata.so`. Related: `$(OS)` in MSBuild is the BUILD
HOST, not the target RID, so a licences-on `linux-x64` publish from Windows stages Windows DLLs -
the Linux packages must be built on Linux.

**Platform 7-Zip + failure diagnostics (`c5486d2a68`).** Runtime extraction could never have
worked off-Windows: `ExtractArchive` hardcoded `7za.exe` (a Windows PE) and Vendor.Common shipped
it in every payload, so on Linux the download and SHA-256 check succeeded and only the unpack
failed, leaving a cached `.7z` beside an empty extract dir. Now per-platform (`7za.exe` / `7zz`,
mirroring `$(SevenZaExe)`), with the exec bit set if missing. Both resolvers also report *why*
they could not supply a library - vendor, archive URL, cache dir, and an explicit "the load error
below is a consequence, not the cause" - to stderr as well as Trace, because console apps attach
no Trace listener. Without it the only visible symptom is `Unable to load shared library
'timsdata'` plus a probe list, which points at the wrong layer; that cost two diagnosis cycles.

**Pattern worth naming.** Three latent Windows-only assumptions surfaced on this one path - the
`WaitForExit`-before-read pipe deadlock, the missing Linux pin, and `7za.exe` - all for the same
reason: **nothing on Linux had ever called `EnsureExtracted`**, because the Linux build stages
natives at build time. Native SDK resolution is the first code to walk it. Expect any remaining
runtime-download code to be equally untested off-Windows.

**Verified from the packaged tarballs on Linux:** both Bruker natives convert (TSF via timsdata,
BAF via baf2sql_c) in both variants, fetching `libtimsdata.so` + `libbaf2sql_c.so` into
`~/.local/share/ProteoWizard/vendor/Bruker-linux-<sha>/`; BAF still converts with the system
libgomp hidden. The self-contained package runs under `env -i` with no .NET present; the
framework-dependent one needs `DOTNET_ROOT` or a standard install - **`PATH` alone is not
enough**, the apphost never consults it, which is worth documenting for users. Windows
unaffected: Bruker 12, Waters 21, Thermo 15, Agilent 11, Sciex 7, MsData 70, Analysis 132,
MsConvert 16.

**Local gotcha:** do not run a Windows `dotnet` build and a WSL build against this tree at the
same time - they share `obj`/`bin` under `/mnt/c` and produce a payload with mismatched assembly
versions (symptom: `Could not load file or assembly 'Pwiz.Data.MsData'` from an otherwise fine
package).

### CI verdict on `c5486d2a68` (2026-08-04) - all three configs green

| config | build | result |
| --- | --- | --- |
| Core Windows .NET | #280 | SUCCESS, 419 passed / 0 failed |
| Core Linux .NET | #41 | SUCCESS, **341/341** (up from 329: the 12 Bruker tests now run there) |
| Skyline Windows .NET | #98 | SUCCESS, **1715/1715**, unchanged from #97 |

Both items flagged for watching came back clean:
- **`Install_PerUser_DeploysAndConvertsVendorFile` passed in 19 s**, against 5 s at baseline when
  it converted Thermo alone. So native SDK resolution works in a genuinely installed product on a
  CI agent, not only in the local strip-simulation, and Bruker's resolve is nowhere near the
  3-minute per-conversion timeout. Caveat: the log does not say whether that agent's vendor cache
  was already warm, so the cold path may still be unmeasured on CI - clearing the agent cache is
  the only way to know.
- **build-linux.sh ran and produced both artifacts** (37.1 MB / 6.4 MB), stripping 40 files each
  with no ABORT, and stamped the real version `4.0.26216-c5486d2` rather than the `4.0.0-dev`
  fallback seen locally (WSL cannot read this Windows worktree's git). Worth checking explicitly
  every time: that step is warning-not-fatal, so silence is not success.

**Windows shows 419 passed of 420, and that is not a regression.**
`Install_PerMachine_DeploysAndConvertsVendorFile` skipped with "Per-machine install requires
elevation". It is agent-dependent: baseline #278 ran on `EC2AMAZ-HH9KVFB` as Administrator and
passed it in 3 s, while #280 landed on `MacCoss TeamCity Agent 1` unelevated. The +2 on the total
is exactly the two new Bruker tests, both passing.

**Open / next:**
1. `libgomp1` on the Linux agents is no longer required - the library is bundled and preloaded -
   but the bundled build wants GLIBC 2.34, so on an older distro the preload fails and the system
   copy is used instead.
2. From the ported-but-untested audit, the largest single gap is
   **`SpectrumList_ChargeFromIsotope`: 675 statements, never executed**. It is the user-facing
   `turbocharger` msconvert filter (`SpectrumListFactory.cs:972`), not dead code. Same shape as
   the BAF find, and roughly the same size as everything else on the list combined.
   **DONE 2026-08-04b - see below.**
3. Carried over: restore the `NET8-PORT TEMP` blocks in
   `scripts/misc/vcs_trigger_and_paths_config.py` (bt83 / bt17) before merge; drop
   `Bruker.Tests/Reference/` once the archive is regenerated; the `Sciex.Tests` / `BiblioSpec`
   gate inconsistency.

## 2026-08-04b -- turbocharger test ported; the port was right, one CV-param units bug

Acting on the audit's top find (`SpectrumList_ChargeFromIsotope`, 675 statements, zero executed).
Ported `SpectrumList_ChargeFromIsotopeTest.cpp` to
`Analysis.Tests/SpectrumProcessing/SpectrumList_ChargeFromIsotopeTests.cs` with all 10 cpp
fixtures. NOT COMMITTED - stopping before commit for review.

**The port itself was correct, unlike BAF/Thyroglob.** All 10 cases produce the same charge as
cpp, and the same refined monoisotopic m/z to full precision. The 675 statements were untested,
not wrong. Worth recording because it is the first item off that audit list that did not turn up
an algorithm bug - "never executed" is not by itself evidence of "broken".

**The one real bug is in the write-back, and it is a `set()` units default.** cpp does
`selectedIon.set(MS_selected_ion_m_z, assignedMZ)` (cpp:484) with the units parameter defaulted to
`CVID_Unknown`. `ParamContainer::set` overwrites units as well as value, so this **clears** the
`MS_m_z` unit that `SelectedIon(double)` put there, and cpp's mzML carries the refined precursor
m/z with no `unitAccession`. The C# port passed `CVID.MS_m_z` explicitly and kept the unit. Only
reachable through `--filter turbocharger`, which is why nothing caught it. Fixed to match cpp; a
mutation check (put `CVID.MS_m_z` back, watch the test go red) confirms the assertion is a real
guardrail rather than a passing accident.

**Case 10 asserts nothing in cpp, and that is now pinned rather than inherited.** cpp's assertions
live *inside* its `BOOST_FOREACH` over the emitted charge CV params, so a case that emits no charge
passes vacuously. Case 10 is exactly that - it declares `trueCharge = 2` that has never been
checked. Verified by instrumenting the cpp test binary (added printf, reverted; the objects were
already built in `C:\dev\pwiz` so it was a one-minute incremental relink): **cpp emits nothing for
case 10 either**. Mechanism: its survey scan yields only three CWT peaks, the weakest is dropped as
the running minimum, and the single surviving 2-peak chain - right charge, right m/z - scores a K-L
p-value of 0.39 against the 0.30 significance gate. The C# test pins "no assignment" as the
expected result so the parity is asserted instead of silently assumed.

**That dead fixture then bought the default-charge fallback its first test.** The
`defaultChargeMin > 0` branch only runs when no isotope chain is found, so case 10 is the only
fixture that can reach it. Re-ran cpp with case 10's `defaultMinCharge/defaultMaxCharge` set to
2/3: cpp emits `possible charge state` 2 and 3 and leaves the precursor m/z (units included)
alone. `EmitsDefaultChargesWhenNoIsotopeFound` asserts exactly that.

**Fixture layout.** cpp holds the 10 spectra as ~56 KB of string literals in the test source; here
they are 20 files (94 KB) under `SpectrumList_ChargeFromIsotopeTest.data/`, found by walking up
from `AppContext.BaseDirectory` exactly like the neighbouring `SavitzkyGolayTest.data`. Extractor:
`<scratchpad>/extract_turbocharger_cases.py`.

**Verification approach worth reusing.** The C# internals are private, so the scoring was diagnosed
from a throwaway console project *outside* the repo (`<scratchpad>/turbodiag/`) referencing
`Analysis.csproj`, plus a temporary env-gated dump in the product file.

**CA2263: a false alarm, chased down and dropped. No code change.** Mid-session,
`dotnet build`/`dotnet test` of Analysis.Tests started failing with **error CA2263** ("prefer the
generic overload") on `Assert.IsInstanceOfType(x, typeof(T))` - an error rather than a warning
because `TreatWarningsAsErrors=true` and `WarningsNotAsErrors` lists only `CS1591;CA1859`. Four
sites exist (`Analysis.Tests/DiaUmpire/SpectrumList_DiaUmpireTests.cs:56`,
`MsData.Tests/MzxmlRoundTripTests.cs:190,240`, `MsData.Tests/MzMlbWriterLazyRoundTripTest.cs:58`).
I changed all four to `Assert.IsInstanceOfType<T>(x)`, then **reverted them** once the diagnosis
held up: it is **not reproducible from any clean state**. With the original code restored and the
tree cleaned, all four of these are green -
`dotnet build Pwiz.sln`, `dotnet build Analysis.Tests.csproj`, the same with `--no-incremental`,
and `dotnet test` after deleting that project's `bin`/`obj`. It only ever fired against the
pre-existing `obj/` that was already in my working tree, so the likely culprit is a stale
generated analyzer config there (`obj/**/*.GeneratedMSBuildEditorConfig.editorconfig` carries
`AnalysisLevel` / `EnableNETAnalyzers`), which any clean regenerates.

**Two explanations I asserted before checking, both wrong - worth recording as method, not just
outcome.** (i) "CI is on an older SDK band": the log says CI runs **8.0.423**, *newer* than the
local 8.0.420. (ii) "CI builds incrementally on a persistent agent checkout, so it never
recompiled the project": the checkout *is* persistent (`agent side checkout` into `C:\pwiz`,
cleaned `NON_IGNORED_ONLY`), but **`tcbuild.bat:78` calls `clean.bat` before every build**, so CI
compiles everything from scratch every time - visible at log line 127, `pwiz-sharp clean.bat`.
Both stories were plausible and neither survived a five-minute check against the actual build log.
The rule that would have caught both: **read tcbuild.bat before theorising about what CI does.**

Regression: Analysis.Tests 135/135 (132 + 3 new), MsData.Tests 70/70, MsConvert.Tests 16/16,
Thermo.Tests 15/15, and `dotnet build Pwiz.sln -c Release` (CI's own build line) 0 errors, with no
suppression flags anywhere.

### clean.sh added; clean.bat had three dead branches

Prompted by the CA2263 finding above - the fix for "a green build proves nothing about untouched
projects" is to be able to force a real full build, and cpp has had `clean.bat` + `clean.sh` at the
root for years. pwiz-sharp had only `clean.bat`, and parts of it did not work.

**`pwiz-sharp/clean.sh` (new)** mirrors clean.bat exactly - same `--all` / `-a` flag, same
keep-the-caches default. It is the missing half of the pair now that pwiz-sharp builds on Linux
(`build.sh` / `tcbuild.sh` already exist). Mode 100755, and `.gitattributes`'s `*.sh text eol=lf`
gives it LF on checkout like `build.sh`.

**Three things clean.bat was silently not cleaning**, all found by diffing it against
`pwiz-sharp/.gitignore` - which is the right spec, since everything the build writes is ignored:
1. `vendor-assemblies/` under `--all` walked `%SCRIPT_DIR%\src\Vendor`, a path that does not exist
   (the projects are under `pwiz\src\Vendor`), looking for per-project `vendor-assemblies` dirs.
   There is one such dir and it is top-level, per `$(PwizVendorAssembliesPath)`. So `--all` had
   never once cleared the vendor cache.
2. `TestResults/` only at the top level, leaving the ~18 per-project dirs `dotnet test` writes
   under `pwiz/test/*/`.
3. `Tools/BiblioSpec/native/**/build/` (MascotShim's cmake tree) and `installer/staging/` were
   never listed at all.

**The trap that shapes both scripts: two things next to the artifacts are tracked source.**
`vendor-archives/` sits beside `vendor-assemblies/` and looks equally cache-like, but it is IN GIT
and is a build *input* - deleting it needs a fresh checkout to recover. And the top-level `build/`
holds `ExtractTestData.targets`, `PwizVersion.targets` and the VendorPinsGenerator/AgilentPatcher
projects, so the cmake sweep must stay scoped to named subtrees; a bare "find any dir named build"
would delete the build system. Both are called out in the header comments of both scripts.

**Verified rather than eyeballed.** Dry-ran the deletion set (143 targets) against `git ls-files`
first: zero tracked files intersected - and note it correctly removes `build/AgilentPatcher/bin`
while keeping the tracked sources beside it. Then `clean.sh --all` -> `git status` shows no
deletions -> full `dotnet build Pwiz.sln -c Release` -> **0 errors**, 56 warnings -> Analysis.Tests
135/135, MsData.Tests 70/70, Thermo.Tests 15/15 (the last confirms the vendor test-data extraction
still runs). Then the same round trip through `clean.bat`. The `bsdtar.exe: Error exit delayed from
previous errors` lines in a clean build are expected, not a regression: `libraries/bsdtar.exe` is
libarchive 2.7, which exits 1 merely for reporting skipped files, and `ExtractTestData.targets`
sets `IgnoreExitCode="true"` with a sentinel check for genuine failures.

### Measured: what `--all` actually costs per commit (answer: ~2 s, plus a 56 MB download)

`tcbuild.bat:78` already calls `clean.bat` (default mode) before every CI build, so **bin/obj/
TestResults are already wiped per-commit** and CI is already a from-scratch compile. The only
question `--all` raises is whether to also drop the two caches. Timed on this machine, clean tree
to fully built solution:

| | wall clock |
| --- | --- |
| `clean.bat` + `dotnet build Pwiz.sln -c Release` | **14.4 s** |
| `clean.bat --all` + same build | **16.4 s** |

So re-extracting `vendor-assemblies/` - 171 MB across 7 vendors, out of the checked-in 7z archives
by the `ExtractVendorAssemblies` targets - costs about **2 seconds**. The header comment in both
clean scripts claiming `--all` costs "~60s of re-download / re-extract" is wrong about the extract
half and should be corrected to the measured figure.

The other half is not a re-extract but a **network fetch**: `installer/cache/` holds
`windowsdesktop-runtime-win-x64.exe`, pulled from `https://aka.ms/dotnet/8.0/windowsdesktop-runtime-win-x64.exe`
by `installer/build.ps1:131` to embed in Setup.exe. Dropping it re-downloads ~56 MB on the next
installer build. That is the real per-commit cost of `--all`, and it is a *reliability* cost as
much as a time one - it puts an external endpoint on the critical path of every build.

**Recommendation: leave tcbuild.bat on the default clean.** Both caches are content-addressed
(vendor archives by SHA-256 via the pins table; the runtime by a fixed versioned URL), so they
cannot drift commit-to-commit, and the thing `--all` would protect against - stale build state -
is already handled by the default clean that runs every build. If a periodic paranoia reset is
wanted, put `--all` on a nightly config rather than the per-commit one, where the 56 MB fetch is
amortised and a flaky download does not red a PR.

### Digestion specificity: a real product bug, and a pre-existing test that encoded it

Next item off the audit. `Proteome.EnumerateNonOrSemiSpecific` (32 statements) was a true gap -
verified, not assumed: **nothing in pwiz-sharp or the Skyline tree ever constructed a `Digestion`
with anything but `FullySpecific`** (the only other `SemiSpecific` hits are IdentData's *Enzyme*
metadata enum, a different type). Ported cpp's `testBSADigestion` scenarios into
`Common.Tests/ProteomeTests.cs::Digestion_SemiAndNonSpecific_BSA`: semi-specific, non-specific,
and semi-specific-with-Met-clipping, each over both the predefined agent and the equivalent regex,
as cpp does. BSA sequence extracted from the cpp source rather than retyped.

**The bug: clip-N-terminal-methionine was implemented as a discount instead of a cleavage site.**
cpp does two things for a leading M (`Digestion.cpp:440-442`): it **inserts offset 0 into the
sites list**, *and* applies a missed-cleavage decrement. The port had only the decrement. Offset 0
being a real site is what makes a peptide starting at offset 1 have a **specific N-terminus** and
makes bare `M` a fully-specific product. Consequences, both silent:
- semi-specific digests **dropped clipped-Met peptides entirely** - e.g. `KWVTFISLLLLFSSAYSR`,
  which cpp emits with specificTermini=2;
- missed-cleavage counts were low across the N-terminal window (`MKWVT`: 0 vs cpp's 1).
One-line-ish fix in `ComputeSites` (plus threading `DigestionConfig` into it, since the rule is
config-gated). After it, all three cpp scenarios pass over both agent forms.

**`Digestion_Trypsin_FullySpecific_NoMissedCleavages` was asserting the port's own wrong output.**
It passed before this change and had to be re-baselined. Ground truth from an instrumented cpp
`DigestionTest` binary (added printf, reverted): for `MAKMKRGHRPKGG` with trypsin and
`Config(0,1,50)`, cpp emits **`M, MAK, AK, MK, R, GHRPK, GG`** - all 0 missed cleavages, all
specificTermini=2. The old expectation was `MAK, MAKMK, MK, R, GHRPK, GG`: missing `M` and `AK`,
and wrongly including `MAKMK` (which spans sites 0 and 2, so one missed cleavage after the
discount, over the limit). Exactly the `reference_net8_rebaseline_vs_fix` trap in its other
direction - a test written from the reimplementation's output instead of the reference's, which
then defends the bug. Worth checking for elsewhere: **a green port test proves nothing if its
expectations were harvested from the port.**

Regression: Common.Tests 49/49, IdentData.Tests 6/6, Analysis.Tests 135/135, MsData.Tests 70/70,
`dotnet build Pwiz.sln -c Release` 0 errors. No product code consumes `Digestion` yet, so the
blast radius is limited to the library API its future BiblioSpec/search callers will use.

### Audit: port tests whose expectations came from the port, not from cpp

Follow-up to the digestion find. Swept the 76 test files in the algorithm-bearing projects
(Analysis, Common, MsData, Util, TraData, IdentData) for the same shape. Filters used: explicit
"differs from cpp" admissions; decimal literals in the C# test that appear nowhere in its cpp
counterpart; cpp-vs-C# assertion counts; and whether every ported class has a test at all.

**Main find - `SpectrumList_ChargeStateCalculator`: 27 of cpp's 43 cases were dropped, and the
whole ETD path with them.** cpp's table carries an `inputActivationTypeArray` column - 29 CID,
**9 ETD, 5 CID+ETD** - and `PrecursorAndChargeFilterTests.ChargeStatePredictor` has no such column
at all: it hardcodes `MS_collision_induced_dissociation` on every one of its 16 rows. ETD changes
charge determination materially, and none of it is exercised. A coverage gap, not a wrong
expectation.

**No divergence in the 16 that were ported.** Worth stating because the first signal said
otherwise: tightening the C# assertion to exact-set equality fails cases 06/07, which expect
`{3,4,5}` while the port emits `{3,4}`. Instrumenting the cpp binary shows **cpp emits `[p3 p4]`
too** - its expected column is a permissive superset, not a prediction. The port is right and the
table is loose; do not "fix" the port here.

**Both tests inherit cpp's vacuous assertion shape**, the same one turbocharger case 10 had: the
checks live inside a loop over the emitted charge params, so a case emitting none passes, and the
membership test is subset-only, so a case emitting *fewer* charges than expected passes too. That
is what let the loose `{3,4,5}` sit unnoticed.

**cpp quirks any tightened port would have to encode** (from the instrumented run): cases
13/26/27/28 emit `[p2 p3 p1]` - charge 1 last, not sorted - and case 31 emits `[p2 p3 p2]`, the
same possible-charge-state **twice**. Both would fail a naive sorted-set assertion.

**Checked and clean:**
- `SpectrumList_PeakFilterTest`: every decimal expectation in the C# test also appears in cpp's.
- `SpectrumList_ScanSummerTest`: 9 assertions each side; the only C# decimals absent from cpp are
  comparison tolerances.
- `BinaryDataEncoderTests`: the `"AAAAAAAA8D8="` expectation is IEEE-754 + base64, derivable from
  the spec rather than from any implementation.
- `SpectrumList_IonMobility_Test`: all eight C# decimals are absent from cpp, which looked alarming
  but they are fixture *inputs*; the assertions are unit-classification outcomes that follow from
  cpp's dispatch logic.
- **No ported filter is wholly untested.** An early pass suggested `SpectrumList_MZWindow`,
  `SpectrumList_3D` and `PrecursorRecalculator` had zero coverage; that was a naming artifact - the
  port renames them (`SpectrumListMzWindow`), and `SpectrumList_3D` / `PrecursorRecalculator` are
  not ported at all. All 21 ported `SpectrumList*` classes have at least one test file.

**Method note for the next sweep.** Decimal-literal diffing is noisy - it cannot tell a fixture
input from an expected output, and it flagged IonMobility while missing ChargeStateCalculator
entirely. What actually found the gap was comparing **cpp's test-case count against the port's**,
and reading cpp's table *columns* for parameters the port dropped. Do that first next time.

### All 43 charge-state cases ported; the missing-SVM gap is now asserted (`8caca4697b`)

Acting on the audit item above. All 43 cpp rows now run in cpp's order with the activation-type
column restored, so ETD-activated spectra reach `SpectrumList_ChargeStateCalculator` for the first
time. Expectations are the instrumented-cpp emissions, and the assertion is an **exact ordered
sequence** - a set comparison would silently accept both of cpp's oddities (p1 emitted last in the
no-override rows; case 31 emitting p2 twice).

**33 rows match cpp exactly. The other 10 are cases 15-24**, where cpp resolves the charge with the
libsvm model the port deliberately does not carry (documented at
`SpectrumList_ChargeStateCalculator.cs:18`). Those rows carry an `SVM:` prefix holding cpp's answer
and assert the port's documented fall-through - enumerate `[minCharge, maxCharge]` - so the feature
gap is asserted rather than invisible, and cpp's values are already in place for whoever ports the
SVM.

**The gap is narrower than "ETD".** Cases 27, 33, 35 and 40 are ETD too and match cpp exactly, so
only those 10 ever consult the model - worth knowing before anyone scopes the SVM port as "all ETD
spectra are wrong".

Fixtures: the ten spectra behind rows 15-41 run 122-1213 peaks, so they live in
`SpectrumList_ChargeStateCalculatorTest.data/` (172 KB, 22 files), deduplicated by content since
cpp reuses one 141-peak spectrum across rows 25-41. Generator:
`<scratchpad>/gen_chargestate_cases.py`. Analysis.Tests 162 (135 + 27), Pwiz.sln builds clean.

### SpectrumListFilter: 4 missing cpp scenarios ported, and a renumbering bug (`244da33565`)

Acting on the 0.38x ratio from the audit. cpp's `SpectrumList_FilterTest` has 13 scenario
functions; the port carried 9. The four missing ones - `testEven`, `testEvenMS2`,
`testSelectedIndices`, `testHasBinaryData` - are exactly the ones exercising the **Predicate
interface itself** rather than a built-in filter spec, and porting the first surfaced a product bug
immediately.

**The bug: filtered spectra were not renumbered.** cpp rewrites the copied identity's index to the
position in the filtered list (`SpectrumList_Filter.cpp:112`) and stamps the same value onto a copy
of the spectrum (`:151`). The port returned the inner list's identity and spectrum untouched, so a
filtered list reported the *original* indices - sparse and non-ascending. That value is what mzML
writes as `<spectrum index="...">`, which has to be dense. It also made the filter inconsistent with
its own sibling `SpectrumListSorter`, which already renumbers and explains why in a comment - so the
fix pattern (`ProxiedSpectrumIdentity`) was already in the tree. The identity is copied rather than
mutated because `SpectrumIdentity` is a reference type.

**Three existing tests were defending the bug** - the same harvested-from-the-port shape as the
digestion find, third instance now. `Polarity_KeepsRequestedPolarity` and
`Wrap_IdentityFilters_IndexScanNumberAndId` read `SpectrumIdentity(i).Index` to mean "which input
survived", and the shared `KeptIndices` helper did the same for 28 assertions. All now key off the
native id, which is what cpp's own filter tests assert on; `KeptIndices` recovers the original index
from the id, so the expected arrays did not change.

**One porting trap worth remembering:** `testHasBinaryData` cannot run against `SpectrumListSimple`.
It holds fully-populated spectra and ignores `DetailLevel`, so a `SuggestedDetailLevel` gate is
invisible and the test passes vacuously at 10/10. cpp round-trips its tiny example through mzML for
precisely this reason. The port needs the file + `MzmlReaderAdapter` route to get a lazy
`SpectrumList_Mzml` (its constructors are internal). Same answers as cpp then: 0 at FullMetadata,
4 at FullData.

Analysis.Tests 166, MsData 70, Common 49, MsConvert 16, Thermo 15, `Pwiz.sln` clean.

### SpectrumListSorter ported, and wrappers no longer renumber the list they wrap (`04fb85fead`)

The last big ratio from the audit (cpp 66 assert sites against one scan-time case). cpp's very
first assertion - "assert that the original list is unmodified" - found the bug.

**Both `SpectrumListSorter` and `SpectrumListFilter` were renumbering the inner list's spectra.**
They stamped the new position onto the object the inner list returned, and `SpectrumListSimple`
hands out its *stored* instance. So enumerating a sorted view rewrote the indices of the list
underneath it: a three-spectrum list read back as `scan=1#2, scan=2#1, scan=3#0`, and a filtered
view corrupted its source the same way. cpp copies the Spectrum before renumbering
(`SpectrumList_Filter.cpp:150-151`) precisely so it cannot. Added `Spectrum.ShallowCopy()` - new
identity, shared params/scan list/binary arrays, since only the index changes. **Note the filter
inherited this from the sorter in `244da33565`, one commit earlier**; following an existing
in-repo convention propagated a latent bug, which is worth remembering as a review reflex.

**`stable` flag added to the sorter**, defaulting to false as cpp does. `Array.Sort` is introsort,
so the stable path breaks ties on the original position. Only cpp's own test uses it (msconvert's
`sortByScanTime` takes the default), but it is public API on both sides and cpp's scenario cannot
be ported without it.

Four scenarios ported: original-list-unmodified, defaultArrayLength ordering with cpp's
renumbering and monotonicity checks, stable-vs-unstable msLevel sorting, and the nested
sorter-over-sorter. The stable order matches cpp on all four positions cpp pins.

**Two of cpp's comments in that test are stale** - it calls scan=22 interchangeable with the MS1s
(scan=22 is MS2), and calls scan=19 and scan=22 interchangeable by array length (15 vs 10). The
port's tiny example was verified field-for-field against cpp's before pinning any order, so the
comparison is sound and the comments are simply wrong.

Analysis.Tests 170, MsData 70, Common 49, MsConvert 16, Thermo 15.

### dotCover re-run (2026-08-05): never-executed 927 -> 172, and CI is missing four suites

Re-ran via the project's own supported path, `build.bat Release --i-agree-to-the-vendor-licenses
--coverage` (dotCover 2023.3.3 from `.config/dotnet-tools.json`), rather than reconstructing the
previous session's ad-hoc scripts. 474 tests, 0 failures. Snapshot at
`pwiz-sharp/TestResults/coverage.dcvr`, HTML at `TestResults/coverage-report/`; the summary comes
from re-reporting that snapshot as `--ReportType=DetailedXML` and parsing it
(`<scratchpad>/parse_coverage.py`, which reproduces the audit's three sections).

**Never-executed statements: 927 -> 172, across 33 types.** The drop is almost entirely this
session's work: turbocharger (~716 with helpers) plus digestion's `EnumerateNonOrSemiSpecific`
(32) accounts for 748 of the 755. Overall statement coverage is **78.2% (27,449/35,109)**.

| assembly | now | previous audit |
| --- | --- | --- |
| Pwiz.Vendor.Common | 38.4% | (not listed) |
| Pwiz.Vendor.UNIFI | 61.6% | 62% |
| Pwiz.Vendor.Thermo | 63.9% | 64% |
| Pwiz.Vendor.Bruker | 69.3% | 68% |
| Pwiz.Vendor.Sciex | 71.6% | 72% |
| Pwiz.Vendor.Shimadzu | 73.2% | 73% |
| Pwiz.Util | 74.7% | 75% |
| Pwiz.Vendor.Agilent | 77.2% | 77% |
| Pwiz.Data.Common | 80.5% | 78% |
| **Pwiz.Analysis** | **80.8%** | **74%** |
| Pwiz.Data.MsData | 83.7% | 83% |
| Pwiz.Vendor.Waters | 85.2% | 85% |
| Pwiz.Data.IdentData | 92.3% | 92% |

Biggest never-executed remaining: `DiaUmpire.LinearInterpolation` 47, `UimfDriftScanInfo` 14,
`WatersPusherInterval` 13, `Diff.DiffResult<T>` 12, `PeakPicking.Peak` 10, then a tail of 6-and-under
including `VendorSupportNotEnabledException`. Barely covered is unchanged: `Common.Diff.Diff` 13%,
`Util.Proteome.ModificationList` 20.5%, `ModificationMap` 24.4%.

**The bigger find is in the measurement, not the numbers.** `build.bat:159-160` sets `TEST_TARGET`
as a **hand-maintained list of 17 projects**, and four built test suites are not on it:

| omitted suite | tests | state |
| --- | --- | --- |
| `TraData.Tests` | 4 | all pass |
| `Bruker.PrmScheduling.Tests` | 3 | all pass |
| `BiblioSpec.Tests` | 142 | 67 pass / **69 fail** / 6 skip |
| `MsConvertGUI.Tests` | ? | not run (net8.0-windows WinForms) |

`tcbuild.bat` calls `build.bat`, so **CI has never run any of them** - which also explains why
`Pwiz.Data.TraData`, `Pwiz.Vendor.Bruker.PrmScheduling` and `Pwiz.Tools.BiblioSpec` are absent from
this report while the previous audit had numbers for them (its own runner enumerated projects from
disk, which is exactly the lesson that audit recorded: *do not hand-list*). `msconvert` is absent
for a different and deliberate reason - `COVER_FILTERS` excludes it.

The 69 BiblioSpec failures look environmental rather than product: the ones sampled are
`Could not find file .../BiblioSpec/tests/inputs/demo.ssl` and `BlibBuild ... exited 1`. That
inputs directory is gitignored (`.gitignore:392`) and populated by the cpp build; it holds 103
files here but is missing `demo.ssl` and `OMSSA.pep.xml`, so it is partially extracted. Not
diagnosed further - it needs its own session.

**Open / next:**
1. Decide what to do about the four omitted suites. `TraData.Tests` and
   `Bruker.PrmScheduling.Tests` are 7 passing tests and could join `TEST_TARGET` immediately;
   `BiblioSpec.Tests` needs its input data sorted out first or it would red CI; `MsConvertGUI.Tests`
   needs a check that it can run headless. Better still, have `build.bat` discover
   `**/test/**/*.Tests.csproj` from disk so the list cannot silently drift again.
2. Remaining audit items, all much smaller and none clearly a true gap:
   `DiaUmpire.LinearInterpolation` (47) and `MsConvert.Program` + `ConsoleProgressListener` (27)
   are both reachable but exercised only outside the pwiz-sharp unit suites (Skyline's
   TestPerf/TestTutorial, and out-of-process msconvert respectively) - confirm before spending
   effort. Genuinely cheap: `VendorSupportNotEnabledException` (6, guards a user-visible message),
   `WatersPusherInterval` (13), `UimfDriftScanInfo` (14), PrmScheduling `CollisionEnergyRamp` (12)
   + `VisualizationDataPoint` (9).
2. Re-run the dotCover audit before picking further targets - the snapshot predates the
   turbocharger test, the CsI/Thyroglob fixtures and this digestion work. The higher-value axis is
   now the assembly percentages (PrmScheduling 41%, msconvert 57%, UNIFI 62%, Thermo 64%,
   Bruker 68%), which are far larger in absolute statements than anything left on the
   never-executed list.
3. Audit other port tests for expectations harvested from the port rather than from cpp (see the
   `Digestion_Trypsin_FullySpecific` find above). The cheap filter: any test whose expected values
   could not have been read off a cpp run or a tracked reference file.
4. Carried over from 08-04: cold Bruker resolve unmeasured on CI; the `NET8-PORT TEMP` blocks in
   `scripts/misc/vcs_trigger_and_paths_config.py`; `Bruker.Tests/Reference/`; the `Sciex.Tests` /
   `BiblioSpec` gate inconsistency.

### Test discovery globbed; BiblioSpec 69 failures fixed (`2929103309`)

Closes the measurement hole the coverage re-run exposed. `build.bat` now discovers
`*.Tests.csproj` under `pwiz\test\` and `Tools\` instead of carrying a hand-maintained
`TEST_TARGET`. Vendor gating stays an explicit list - it is not derivable from the csproj
(`Analysis.Tests` references a vendor project but runs ungated; `Installer.Tests` references none
yet needs licences) - but it is now an **exclusion**, so an unregistered new vendor suite fails
loudly rather than silently never running.

**BiblioSpec.Tests: 69/142 red -> 142/142, all of it missing input data, no product defects.**
`pwiz_tools/BiblioSpec/tests/inputs.tar.bz2` had never been unpacked. The directory is gitignored
yet ~100 files in it are force-added to git and are the authoritative modern fixtures; the archive
is the older cpp-era set and the two overlap in only 3 names, so its 98 unique files (`demo.ssl`,
`demo.sqt`, `OMSSA.pep.xml`, the Mascot `.dat`s) were absent. `BiblioSpec.Tests.csproj` now imports
`ExtractTestData.targets` like the vendor suites.

**The extraction must not overwrite, and that is load-bearing.** For the 3 overlapping names the
tracked copies are newer and the archive's are stale; `ExtractTestData.targets` already uses
`bsdtar -xkf` / skip-old-files, which is exactly right. Forcing the archive's
`waters-mobility.final_fragment.csv` over the tracked one turns `Mse_Mobility` red with a genuine
content diff, and `Filter_Mobility` with it (it calls `Mse_Mobility` directly). If those two ever
fail, check that file first. Also: `tiny-v2.msf` / `tiny-v2-filtered.pdResult` can linger as 0-byte
untracked placeholders that the keep-existing flag honours - `git clean -fx` the directory to clear
them. And XML comments cannot contain a literal double hyphen, so the csproj cannot spell the
skip-old-files flag out; same MSB4025 that `9fb039d4a7` fixed inside the targets file itself.

Verified from clean: `git clean -fx tests/inputs` leaves 97 tracked files, `dotnet build` extracts
to 197, suite is 142/142, no tracked file modified. Full `build.bat`: **21 suites, 626 tests, 625
passed, 0 failed, 1 skipped** (the per-machine installer test, which needs elevation and skips on
CI too). Previously 17 suites / 474 tests.

**Open / next:**
1. Watch the next CI run on `2929103309` - it is the first to execute TraData.Tests,
   Bruker.PrmScheduling.Tests, BiblioSpec.Tests and MsConvertGUI.Tests. BiblioSpec depends on the
   agent unpacking `inputs.tar.bz2` (tracked, 54 MB) via the new target; `tests/reference/` is
   tracked (131 files) so that side is fine.
2. Re-run coverage once CI is green - the 08-05 numbers exclude the four newly-added suites, so
   `Pwiz.Data.TraData`, `Pwiz.Vendor.Bruker.PrmScheduling` and `Pwiz.Tools.BiblioSpec` are still
   unmeasured.

## 2026-08-05b - coverage re-run, the perf-test cascade explained, master merge, and a silent build.bat

### CI on `2929103309` is green, and all four new suites really ran

Build #285 of `ProteoWizard_CoreWindowsNet`: **584 reported / 583 passed / 0 failed**. Per-suite counts
in the agent log are identical to local and sum to **626 in 21 suites**, so `TraData.Tests` (4),
`Bruker.PrmScheduling.Tests` (3), `BiblioSpec.Tests` (142) and `MsConvertGUI.Tests` (3) all executed on
the agent, and it did unpack `inputs.tar.bz2` through the newly imported `ExtractTestData.targets`.
That was the one genuinely uncertain thing from the previous session.

**The 626-vs-584 gap is not a missing suite - it is TeamCity aggregating by test name.**
`PrecursorAndChargeFilterTests.ChargeStatePredictor` carries 43 `[DataRow]` rows under one name, so 42
collapse into a single reported test. Verified by parsing the run's `.trx` files: 626 results, 582
distinct class+method names, and the collapse is entirely inside `Analysis.Tests`. Worth folding those
43 rows into one table-driven `[TestMethod]` (also the house preference over long `[DataRow]` lists),
which would make the CI count honest as a side effect.

### Coverage re-run: 77.6% over 20 assemblies, and BiblioSpec is the new frontier

`build.bat Release --i-agree-to-the-vendor-licenses --coverage`, 21 suites, 626 tests, 0 failures.
Snapshot `pwiz-sharp/TestResults/coverage.dcvr`; parser rewritten at `ai/.tmp/parse_coverage.py` (now
takes `--baseline` so future runs diff assembly percentages directly).

**Overall 77.6% (36,119/46,553).** Not comparable to the previous 78.2% (27,449/35,109): the measured
surface grew ~11.4k statements because three assemblies entered the report for the first time.

| assembly | now | prev | note |
| --- | --- | --- | --- |
| Pwiz.Tools.BiblioSpec | 75.5% (9064/12006) | - | newly measured, now the largest assembly in the report |
| Pwiz.Data.TraData | 73.4% (681/928) | - | newly measured |
| Pwiz.Vendor.Bruker.PrmScheduling | 41.3% (90/218) | - | newly measured, lowest real assembly |
| Pwiz.Data.MsData | 86.3% | 83.7% | +2.6, the new suites exercise it |
| Pwiz.Analysis | 81.5% | 80.8% | last session's ports |
| Pwiz.Vendor.UNIFI | 60.1% | 61.6% | only regression; unexplained, small |

Never-executed: **380 statements over 70 types** (was 172/33 pre-BiblioSpec), of which BiblioSpec is
194. The new top of the list is all BiblioSpec: `MzTabReader` **1 of 280 statements**,
`LoadSpecLibFromParquetAsync` 91, `CompositeReadStream` 33, `AlphaPepDeepReader` 6/74, `SqliteRoutine`
18/102. The parquet loader is notable - it is exactly the DIA-NN path whose faithful-port divergences
reddened CI #57, covered by Skyline's `DiannSearchTest` but by nothing in the pwiz-sharp suites.

**`MzTabReader` is an upstream gap, not a porting oversight.** cpp has `mzTabReader.cpp` but no mzTab
fixture anywhere in `pwiz_tools/BiblioSpec/tests/` either, so there is no cpp test to port and no
reference output to check against. Testing it means authoring an mzTab fixture from the spec.

### The 18 perf-test failures are one leaked stream, and the branch did not cause it

`ProteoWizard_SkylineWindowsNetPerfTutorialTests` #26 (`04fb85fead`): 115 tests, 18 failed, every one
"Streams left open". **All 18 report the identical stream** - globalIndex 55643469,
`PerfMinimizeResultsTest\...v1.skyd` - including tests that never touch that file. The end-of-test
check is process-global, so one leak fails every subsequent test in the process. Only
`TestMinimizeResultsPerformance` is a real failure; 17 are collateral. (Same shape as the ~27-test
cascade in `TODO-20260715_open_doc_from_zip.md`.)

**Root cause is a race in Skyline's own code.** The pool's event log:

```
02:35:54.230  DisconnectWhile   FileSaver.Commit <- ChromatogramCache.OptimizeToPath <- SkylineWindow.OptimizeCache
02:35:54.234  Connect           ChromatogramCache.CallWithStream <- GraphChromatogram.DisplayPeptides <- timer tick
```

`SaveDocument(includingCacheFile: true)` runs `OptimizeCache` on the LongWaitDlg worker thread;
`ChromatogramCache.cs:1533` calls `fs.Commit(ReadStream)` (disconnects the pooled `.skyd`), and `:1535`
returns a **new** cache via `ChangeCachePath`. `LongWaitDlg.ShowDialog` keeps pumping messages, so a
`GraphSpectrum.UpdateManager` timer tick reaches `ReadTimeIntensities` -> `CallWithStream` ->
`GetConnection`. `ConnectionPool` locks on `this`, so that call waits the 4 ms and reconnects the
instant `DisconnectWhile` releases, reviving the old cache's stream just before the document swaps to
the new one. Nothing owns the old instance afterwards, so nothing ever disconnects it.

**Not caused by this branch.** The 15 commits between the last test-producing perf build (#24
`c48d6bd0`, 115/115 green) and #26 touch **zero files** under `pwiz_tools/Skyline` or
`pwiz_tools/Shared` - a path-filtered `git log` over the range is empty. A pwiz-sharp change can shift
timing but cannot create this path. Builds #25 and #23 were red with no test data at all
(infrastructure, before the test step). Caveat: only #21/#22/#24 produced test data recently, so a long
green history for this specific race cannot be shown.

**Master does not fix it either** (checked at Matt's request): none of the 37 incoming commits touch
`ChromatogramCache`, `GraphChromatogram`, `UtilIO`/`ConnectionPool` or the leak check, and the one
race-adjacent file master did change, `SkylineFiles.cs`, only gained a `ShowOpenFileDialog` factoring
at ~line 188. Perf retriggered on the merged head as build 4122155 to measure how often it reproduces.

### Merged master, 37 commits (`611cd6c465`)

No C++ deltas this cycle, so no cpp->C# porting leg; incoming work is Osprey, the AI Connector
native-dialog automation, and a batch of intermittent-test fixes. 5 conflicts, all csproj, resolved to
ours. Two things globbing could not supply, carried over by hand:

- **`SkylineTool` ProjectReference into `TestPerf` and `TestUtil`.** Master added `McpConnectorTest.cs`
  to TestUtil, which our globs now compile, and it needs SkylineTool. That project already
  multi-targets, so the reference is unconditional.
- **The RT-precision fix (`72e0401523`) ported into the sandbox `MsDataFileImpl`.** `GetStartTime`
  converted a value already recorded in minutes to seconds and back, which is not an identity in
  floating point. The sandbox is a mechanical port, so it takes every behavioural change the original
  gets: `param.Units == CVID.UO_minute` -> `param.ValueAs<double>()`.

Verified: all seven net8 projects build with 0 errors; `TestFullScanProperties` and `TestSkylineMcp`
pass. The latter is what caught the merge - it pins `EXPECTED_ZIP_VERSION` against the installed
`SkylineAiConnector.zip`, and master bumped both.

### build.bat was skipping its entire build step, silently (`d47eca4cb1`)

The merge verification "passed" against binaries dated **Jul 23**. All six `.bat` entry points were
stored **LF-only**. cmd.exe tracks its position in a batch file by byte offset and that accounting
drifts on LF files, so after enough `call :label` returns the label search starts from the wrong place:

```
The system cannot find the batch label specified - build_one     (x7, one per BUILD_TARGET project)
```

`build.bat` skipped `dotnet build` for all seven projects, staged whatever was already in
`bin\Release`, ran the tests against it, and **exited 0**. The earlier labels resolve fine
(`:build_hardklor` and `:restore_one` both ran), which is what makes it so quiet - the failure needs a
few calls of accumulated drift. CI was immune because those checkouts have `core.autocrlf=true`; this
worktree holds the files as originally authored. Fixed with `*.bat text eol=crlf` in `.gitattributes`
beside the existing `*.sh` rule, so it no longer depends on anyone's git config. The `.bat` blobs
normalize identically, so the commit is the attribute alone. After the fix `dotnet build` runs per
project, 0 errors x7.

Also `121edcc4a1`: CA1859 on `SpectrumListWrapperTests.MsLevelOf`, introduced by `04fb85fead` and
visible on CI; typed to `SpectrumListSorter` (its only call site). Analysis.Tests back to 0 warnings.

**Open / next:**
1. Perf build 4122155 on the merged head - does the `TestMinimizeResultsPerformance` stream leak
   reproduce? If it does, the fix is to stop `GraphChromatogram`'s read path reviving a cache that
   `OptimizeCache` is handing off. Pre-existing Skyline code, outside the port's scope, so it is Matt's
   call whether to fix here or file it.
2. `MzTabReader` coverage (1/280) - needs an authored mzTab fixture, since cpp has none.
3. Re-run coverage after any further suite changes; the 08-05b numbers are the first to include
   BiblioSpec/TraData/PrmScheduling.
4. Fold the 43 `ChargeStatePredictor` `[DataRow]` rows into one table-driven test.
5. Carried over: cold Bruker resolve unmeasured on CI; the `NET8-PORT TEMP` blocks in
   `scripts/misc/vcs_trigger_and_paths_config.py` before merge; `Bruker.Tests/Reference/`; the
   `Sciex.Tests` / `BiblioSpec` gate inconsistency (they gate on `IAgreeToVendorLicenses` where the
   products now gate on `NativeVendorsAvailable`).

## 2026-08-06 - cpp-parity audits: nine product bugs, and three environment traps

One method all day: **replace expectations the port authored with expectations cpp authored**, then
run. Nineteen commits, all pushed to `origin` and `chambem2/pwiz-sharp`, head `f84deb7bb8`.
`ProteoWizard_CoreWindowsNet` #298 green on that head.

### Product bugs found and fixed

| area | what was wrong | commit |
| --- | --- | --- |
| `ThresholdFilter` | comparison inclusive where cpp's is strict; cutoff ignored ties and read `LeastIntense` as the complement; `Count` discarded a tie inside the kept set | `6bd98ceeba` |
| `mzShift` | only named params were shifted, so lowest/highest observed m/z never moved | `aee92ac2bd` |
| `zeroSamples` | `removeExtra` dropped the flanking zeros peak picking needs on profile data | `4fd002245d` |
| `TraDataDiff` | counted every list, compared the contents of five; **8 of 17** changes unreported | `126c4c5506` |
| `MSDataDiff` | contacts, samples and the spectrum's sourceFile/dataProcessing refs never compared | `f3668d4d04` |
| `Reader_Agilent` | never emitted `sampleList`; cpp reads "Sample Name" from `AcqData/sample_info.xml` | `f3668d4d04` |
| MSn binary | a file stopping mid-record threw instead of ending at the last complete spectrum | `26df336484` |
| MSn text | space-delimited EZ lines ignored, silently losing charge + accurate mass | `26df336484` |
| `SpectrumListBase.Find` | no `scan=`/`index=` translation, so nothing could find a spectrum in an MGF list by scan | `f84deb7bb8` |

### Audits that found nothing, which is also the answer

`identdata` DiffTest (46 mutations), `proteome` DiffTest, the binary encoder against cpp's 14 stored
base64 regressions, the isotope calculator against cpp's independent multinomial at 1e-10, the
factory's 34 filter-name parses, and re-serialising the mzML cpp wrote. All faithful. These are worth
as much as the bugs: they are the parts we no longer have to wonder about.

### The pattern worth carrying forward

A test that round-trips the port through itself cannot see a reader and writer that agree with each
other and disagree with pwiz. Every bug above was invisible to one. The cheap filter is still: *could
this expected value have been read off a cpp run or a tracked reference file?* Two refinements from
today: a **mutation** test is only as good as its mutations actually mutating (three "misses" in
identdata were no-op mutations of my own), and cpp's **test configuration** matters as much as its
data (the encoder's numpress regressions set tolerance 0; at the shared 2e-9 default both
implementations correctly fall back).

Also: cpp's fixtures are not always current. `example_data/tiny.pwiz.1.1.mzML` holds four spectra
ending `cycle=22` while cpp's `examples::initializeTiny` now builds five ending `scan=22`/`cycle=23`,
and the port's `Examples.InitializeTiny` matches cpp's *source* exactly. The file is a reader fixture,
not a reference for the example.

### Three environment traps, none of them product code

1. **`build.bat` was skipping its entire build step** (`d47eca4cb1`). All six `.bat` entry points were
   stored LF-only; cmd tracks position by byte offset and loses `call :label` after enough calls, so
   `dotnet build` never ran for any of the seven projects, stale binaries were staged, and it exited
   0. A merge got "verified" against Jul 23 binaries. Fixed with `*.bat text eol=crlf`. CI was immune
   (`core.autocrlf=true`), which is why it survived.
2. **C# 14 `field` keyword** (`839f0eaa6b`) broke `ProteoWizard_SkylineWindowsNet` #108. A loop
   variable named `field` inside a property accessor binds to the synthesized backing field from C# 14
   on. Local SDK compiled it at an older language version. `-p:LangVersion=preview` reproduces CI.
3. **cpp-derived fixtures were being EOL-rewritten on checkout** (`2ef5a4b2c3`); pinned with `-text`.

### Merged master (`611cd6c465`)

37 commits, no C++ deltas. Five csproj conflicts resolved to ours. Carried over by hand: `SkylineTool`
ProjectReference into TestPerf/TestUtil, and cpp's RT-precision fix (`72e0401523`) ported into the
sandbox `MsDataFileImpl` - `timeInSeconds()/60` is not an identity in floating point.

### Perf CI

Build 4122155 on the merged head: 37 tests, 36 passed, 1 failed - `TestDiaFragPipeTutorial`
GC-leak, after a 403 on the `ci.skyline.ms` copy of `Webinar26.zip`. The
`TestMinimizeResultsPerformance` stream-leak cascade did **not** recur, but that run only reported 37
tests against the earlier 115, so it did not cover the same set. The race analysis stands: no master
commit touches `ChromatogramCache`/`GraphChromatogram`/`ConnectionPool`.

**Open / next:**
1. Watch `ProteoWizard_SkylineWindowsNet` build 4123349 (triggered on `f84deb7bb8`) - the first
   Skyline run since the `field` fix; #108 failed on it and nothing has rebuilt since.
2. Vendor file-lock probe flakes intermittently on CI (Thermo `FT_HCD_MSX`, Bruker `CsI_Pos`,
   "unreleased file locks after Dispose"). Passes standalone; CI auto-enables dotCover, which
   perturbs finalizer timing. Worth a proper look - it is now the main source of red that is not a
   real failure.
3. `PrmSchedulerTests` is the weakest test in the tree - 9 assertions, none able to catch a wrong
   value, in the 41.3%-coverage assembly, and it drives real instrument method export. There IS a cpp
   oracle: `pwiz/utility/bindings/CLI/timstof_prm_scheduler/PrmSchedulerTest.cpp`, 690 lines
   comparing scheduling entries field-by-field. Highest-yield remaining port.
4. The **CLI bindings test tree** is unexamined and is exactly the layer pwiz-sharp replaces. Includes
   three more DiffTests (msdata 241, proteome 98, tradata 96) and the unported `IsolationWindowFilter`
   peak filter (only consumer is SeeMS).
5. `MzTabReader` coverage (1/280) - needs an authored mzTab fixture, since cpp has none either.
6. Fold the 43 `ChargeStatePredictor` `[DataRow]` rows into one table-driven test; it is also why
   TeamCity reports 42 fewer tests than a local run.
7. Carried over: perf stream-leak race (Skyline-side, Matt's call); re-run coverage; cold Bruker
   resolve unmeasured on CI; `NET8-PORT TEMP` blocks in `scripts/misc/vcs_trigger_and_paths_config.py`
   before merge; `Bruker.Tests/Reference/`; the `Sciex.Tests`/`BiblioSpec` gate inconsistency.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260806_net8_cpp_parity_audits.md` before starting work.

## 2026-08-06b - PrmSchedulerTest.cpp ported: the port is faithful, and one new oracle

The weakest test in the tree is now the strongest test of the Bruker PRM scheduling bindings.
`PrmSchedulerTests` had 9 assertions, none able to catch a wrong value, in the 41.3%-coverage
assembly that drives real timsTOF method export. It now runs cpp's whole `test()` over cpp's own
four reference tables.

### What was ported

`pwiz/utility/bindings/CLI/timstof_prm_scheduler/PrmSchedulerTest.cpp` -> the single
`EndToEnd_AddTargets_GetScheduling_ProducesExpectedSchedule` test (three shape-only `[TestMethod]`s
folded into one, per the consolidation rule). Copied row for row:

| table | rows | compared |
| --- | --- | --- |
| `testTargets` | 100 | the input, added with cpp's external ids and midpoint 1/K0 + RT |
| `testSchedulingEntries` | 134 | `time_segment_id`, `frame_id`, `target_id`, in order |
| `testTimeSegments` | 197 | begin/end, exactly (cpp's epsilon is 0) |
| `testConcurrentFrames` | 47 | x, y at 1e-8 |

Plus cpp's cancellation case (`ShowProgressCancelAt50`): returning true past 50% must stop the
scheduler and never call back again, and the managed `GetScheduling` swallows the native "user
request" error, so the lists come back empty.

**No product bugs.** Every value matched on the first run. cpp's setup has two details that are
load-bearing and are now commented as such: it sets only `ms1_repetition_time` (leaving
`default_pasef_collision_energies` false - the old test set it true), and it compares its tables as
a *prefix* of the results, because the tail was truncated when they were captured.

### The gap cpp's test cannot see, and the oracle for it

Mutation-testing the new tables found four of five mutations detected and one missed: changing a
target's isolation m/z changed nothing anyone compares. That is not a flaw in the port of the test -
it is true of cpp's test too. **The schedule is computed from RT and mobility alone**, so isolation
m/z, isolation width, collision energy, charge, and both apex values could each be marshaled into
the wrong native field of `PrmInputTarget` with every assertion still passing, while an exported
instrument method fragmented the wrong ion.

Those fields resurface in the `.prmsqlite` the scheduler writes. The checked-in
`timstof_prm_scheduler.prmsqlite` turns out to be a *written copy of cpp's own run* - 100 targets,
197 time segments, 5563 scheduling rows, `MS1RepetitionIntervalSeconds` 10.0, and
`PrmTargetAdditionalCharacteristics` row 0 holding `OneOverK0` 1.03565 and `TimeInSeconds`
46.800000000000004, exactly the midpoints cpp computes. So the test now reads the file back after
`Dispose` and checks all nine persisted fields per target, and pins the four `PrmGlobalMethodInfo`
values (`MobilityGap` 0.006, `FramesPerSecond` 10, 1/K0 0.7-1.2) that `GetPrmMethodInfo` returns.

Reading it after `Dispose` also means the test fails if the native handle keeps a lock on the file.

### The trap in verifying a round trip

The first mutation run reported the write-back check missing an isolation-m/z mutation, which looked
like proof the check was a tautology reading stale template rows. It was not: **a round-trip check
cannot be tested by mutating the data, because the same table is the input and the expectation.**
The right mutation is to the code under test. Swapping `isolation_mz` and `isolation_width` in
`NativeStructs.cs` fails with `Expected:<784.8662>. Actual:<3>. target 1: IsolationMz`, from the
write-back check alone - the schedule assertions pass straight through that swap. Swapping
`monoisotopic_mz` and `time_in_seconds` is caught too.

This is the second cousin of "mutations that do not mutate" from earlier today. Both come down to
the same question: *what would have to be broken for this assertion to fail?*

Remaining blind spot, deliberately: cpp sets `monoisotopic_mz` equal to `isolation_mz`, so swapping
those two is invisible. Sending different values would strengthen it but would no longer be cpp's
fixture.

### Files

- `pwiz-sharp/pwiz/test/Bruker.PrmScheduling.Tests/PrmSchedulerTests.cs` - the port
- `pwiz-sharp/pwiz/test/Bruker.PrmScheduling.Tests/Bruker.PrmScheduling.Tests.csproj` - stages the
  `.prmsqlite` from `$(PwizCppRoot)` beside the test binary (replacing a directory walk that looked
  for a sibling cpp checkout), and adds `System.Data.SQLite.Core` 1.0.119 for the read-back, the
  same version Bruker/UIMF/BiblioSpec already use

0 warnings, ASCII-only, CRLF. TeamCity will report 2 fewer tests in this assembly.

## 2026-08-06c - The one red test on CI: net8 silently swapped every folder browser

`ProteoWizard_SkylineWindowsNet` #103-#109 all failed the same way -
`TestLibraryBuild`, `WaitForLibrary` expecting 3 spectra and getting 12 - and it is not the
`field` keyword, which #109 (on the fix commit) proved compiles. #102 was 1715/1715 green, so the
break arrived with the master merge.

### Root cause

`FolderBrowserDialog` is not the same dialog on the two frameworks. .NET Framework only ever shows
the classic `SHBrowseForFolder` tree. **.NET 8 defaults `AutoUpgradeEnabled` to true and shows the
newer `IFileDialog` folder picker instead.** Nobody chose that; it came with the runtime, and it
applies to all 17 folder browsers in the Skyline tree - Import Results, Export Method, Tools, share
missing files, AutoQC, SkylineBatch, SkylineTester.

Master's `a840067e8d` (AI-connector native-dialog automation) rewrote `LibraryBuildTest` to add its
input directory by driving the real dialog, through `NativeFolderBrowserDialog` - which steers the
classic tree with `BFFM_SETSELECTION`. A probe of the actual net8 dialog:

```
AutoUpgradeEnabled: True
dialog class      : #32770
has ctrl id 1148  : False   <- IsOpenFileDialog keys on this
has SysTreeView32 : True    <- IsFolderBrowserDialog keys on this
classified as     : NativeFolderBrowserDialog
OK button (id 1)  : found
asked for         : ...\Skyline\TestUtil
dialog returned   : ...\Skyline\TestFunctional
=> automation was IGNORED; got the default folder
```

The picker still classifies as a folder browser (no control 1148, and its navigation pane is a
tree), so the test finds it and clicks OK successfully. But `BFFM_SETSELECTION` means nothing to it,
so it returned its default folder - `Settings.Default.LibraryResultsDirectory`, the test-files root
from an earlier step. `FindInputFiles` then recursed over the whole test folder instead of `cpas`,
and the library was built from every search result under it: 12 peptides, not 3.

`NativeFolderBrowserDialog` is used in exactly one place in the tree, which is why exactly one test
went red.

### Fix

`FormUtil.CreateFolderBrowserDialog()` (CommonUtil, one `#if !NET472`) returns a browser with
`AutoUpgradeEnabled = false`, so both frameworks show the classic tree. All 17 sites go through it,
except `SkylineNightly` and `ImageComparer`, which reference nothing shared and get the same guard
inline. Each site carries a TODO: the newer picker is the better dialog, and adopting it should be a
deliberate UI decision plus a rewrite of the folder-browser automation - not something inherited
silently from a framework upgrade.

Open/Save are unaffected: `FileDialog.AutoUpgradeEnabled` has defaulted to true since .NET 2.0 SP1,
so those are the same modern dialog on both frameworks. `FolderBrowserDialog` is the one that
changed, because net472's has no upgrade path at all.

`AddInputDirectoryThroughDialog` now also asserts the files it added live under the directory it
asked for, so a folder browser that ignores the automation fails there rather than 400 seconds later
on a spectrum count.

Verified locally on the net8 build: `TestLibraryBuild` **0 failures in 73 sec**, where it had been
failing at 397 sec. All seven affected projects (Skyline, SkylineTester, SkylineNightly, AutoQC,
SharedBatch, SkylineBatch, ImageComparer) compile on net8.

## 2026-08-06d - net8 build warnings: a batch of obsoletions, and the one that was a live bug

CRITICAL-RULES asks for a zero-warning build. The net8 leg was not close, and one warning turned out
to be hiding a product regression.

### Install.Is64Bit was answering "no" on every 64-bit net8 build

`Is64Bit` asked whether *our own assembly* was AnyCPU:
`ProcessorArchitecture.MSIL == AssemblyName.GetAssemblyName(location).ProcessorArchitecture`. .NET 8
obsoleted that property and always returns `None`, which a probe confirms: on a 64-bit net8 process
`Install.Is64Bit` is **false**. Consequences shipping in the port today:

- `SrmDocument._maxTransitionCount` took the 32-bit branch - **1,000,000 transitions instead of
  5,000,000**
- audit-log entries lost their `(64-Bit)` version marker (net472 records it)
- error reports and analytics reported `32bit`

Now `Environment.Is64BitProcess`, which is also the more truthful question: an AnyCPU assembly says
nothing about how the process was actually launched, so the old test was wrong on net472 too for a
32-bit run.

### TestDir: the compiler's suggested fix would have broken every test that uses it

`TestContext.TestDir` is deprecated in favour of `TestRunDirectory` (13 call sites). They are not the
same property - they read different keys - and Skyline's `TestRunnerContext` only ever seeded
`Properties["TestDir"]`. A probe against MSTest 3.2.0:

```
Properties["TestDir"] only -> TestDir=C:\seeded-by-TestRunner | TestRunDirectory=<null>
```

So a mechanical rename would have handed every caller a null under TestRunner. `RunTests.SetTestDir`
now seeds both keys - under VSTest the adapter fills them in, under TestRunner we are the adapter -
and the call sites moved.

### The rest

| warning | sites | what was done |
| --- | --- | --- |
| `SYSLIB0021` | 7 | `new SHA1/MD5CryptoServiceProvider()` -> `SHA1.Create()` / `MD5.Create()`; same algorithms, so audit-log hashes are unchanged |
| `SYSLIB0051` | 4 | `#pragma`, not `#if`: removing a serialization constructor changes the type's shape and breaks subclasses that chain to it, which is exactly what `CommonException<TDetail>` did when tried |
| `SYSLIB0012` | 2 | `Assembly.CodeBase` -> `Location`. AutoQC's copy hand-trimmed a `file://` URL and never percent-decoded it, so an install under "C:\Program Files" came back as "C:/Program%20Files" |
| `CS0108` | 1 | .NET 8's `ToolStripItem` has its own `Command`; `ToolMenuItem.Command` renamed to `ToolCommand` rather than `new`, which would have traded CS0108 on net8 for CS0109 on net472 |
| `CS0618` (NHibernate) | 1 | `IStatelessSession.Transaction` is an obsolete *interface member* we implement, and `GetCurrentTransaction()` has different null semantics - suppressed and delegated verbatim |
| `CA2255` | 1 | module initializer in a library is deliberate here (vendor readers must register before `MsDataFileImpl`'s static `ReaderList` snapshot); suppressed with that reason |
| `CS0219` | 1 | dead `activationArgs` in the net8 branch of the ClickOnce guard |

### Left, deliberately

- `SYSLIB0013` `Uri.EscapeUriString` (4). **Not** a rename to `EscapeDataString`: two sites build
  `NormalizationMethod` names that are persisted in .sky documents, and the two functions escape
  different character sets. Doing this properly means a compat helper reproducing the old escaping,
  verified by a net472 test comparing it against the framework across the character range.
- `SYSLIB0014` `WebRequest`/`WebClient` (5 in Skyline + Ardia; more in SkylineBatch/SkylineNightly) -
  a real migration to HttpClient with proxy/timeout/error-handling risk.
- `NU1902` log4net 2.0.17, `NU1903` DotNetZip 1.16.0 - vulnerable packages, a dependency decision.
- `CA1859` / `CS1591` in pwiz-sharp - that tree's own analyzer settings.

Note for whoever picks these up: an incremental build under-reports. The second `Assembly.CodeBase`
site only appeared once the build was `--no-incremental`.

### Verification

Clean `--no-incremental` build of all 16 net8 projects: 0 errors. Nine tests covering every changed
path, all passing: `TestConfigureToolsDlg` (the ToolCommand rename), `TestAuditLogSaving` (the hash
swap and the audit-log version string), and `TestListClustering`, `TestExportDiaList`,
`TestExplicitVariable`, `TestFindNode`, `TestStartPageImport`, `TestStartPagePeptideSearch`,
`TestStartPageShowFromSkyline` (the TestRunDirectory move). The rest is compile-only.

Warnings remaining in the Skyline tree afterwards: `SYSLIB0014` x13, `CA1859` x15 and `CS1591` x11
(pwiz-sharp), `SYSLIB0013` x4, plus the two NuGet advisories.

## 2026-08-06e - First AWS-agent run: MS Amanda's percolator was missing one DLL

The queue unpaused and `ProteoWizard_SkylineWindowsNet` #110 came back **1743/1743 green** on
`0546065373` - the branch's first green Skyline run since #102, confirming the folder-browser fix on
CI. Then #111 ran the same commit on an **AWS agent** and failed four tests.

### The four failures

`TestDdaSearch`, `TestDiaSearchFixedWindows`, `TestDiaSearchVariableWindows`, and the Pass1
leak-detection copy of the last - every MS Amanda search in the suite, all with:

```
ERROR: .mzid file contains an unsupported score type
```

Skyline writes `RunPercolator` into MS Amanda's settings, and per `39558abff3` only the PSMs
Percolator scores carry a q-value (`MS:1001491` / `MS:1002354`); the rest carry
`Amanda:AmandaScore`, which BiblioSpec skips. That error is raised only when **no** item had a
recognised score - so Percolator contributed nothing.

**`percolator.exe` imports `vcruntime140_1.dll`, and MS Amanda's package does not ship it.** It
bundles `vcruntime140`, `msvcp140`, `concrt140`, `vcomp140` and `xerces-c_3_1` beside the exe, but
not that one. Where the VC++ 2015-2022 x64 redistributable is installed the loader finds it in
System32; on a freshly provisioned agent it does not, percolator never starts, MS Amanda carries on,
and the only symptom appears two steps later in the reader.

Four legs of evidence: TCA1 green on the commit; this dev box green (and it has the DLL in
System32); the AWS agent red; and percolator's own import table. Same shape as the Agilent BaseTof
runtime gap - `Agilent.csproj` already deploys the VC120 runtime app-local for exactly this reason.

### Fix (`5bde3552a9`)

`Skyline.csproj` ships `vcruntime140_1.dll` from the vendored `Shared/Lib/Microsoft.VC140.CRT/x64`,
and `MSAmandaSearchWrapper.StagePercolatorRuntime()` copies it beside `percolator.exe` after the
tool is unzipped - the tool lives in a **downloaded** directory, so no build-time copy can reach it.
Best-effort: a machine that already has the redistributable is unaffected.

The search also now checks its own output for a q-value accession and fails naming Percolator if
there is none. This matters past CI: a user without the redistributable was getting a DDA search
that quietly lost its FDR scoring.

Verified: the DLL lands in the unzipped tool directory, both search tests still pass, and a new
`TestPercolatorQValueDetection` covers what a machine with the redistributable cannot - an mzIdentML
with only `Amanda:AmandaScore`, one with no scores, and q-values past and straddling the reader's
64K chunk boundary.

**Not confirmed directly**: nobody has logged into the AWS agent to verify the redistributable is
absent. That is inference from the failure signature plus the import table. The new check will now
say so in plain terms on the next AWS run either way.

### Also seen in the wild

That build's own error report reads `Skyline (32-bit : automated build) 26.1.1.218 (0546065)` on a
64-bit agent - the `Install.Is64Bit` regression, fixed the same day in `c4a59bc8ca`, which was not
yet in that build.

### CI state at end of session

- #110 `0546065373` SUCCESS 1743/1743 (TCA1)
- #111 `0546065373` FAILURE 1735/1739 (AWS) - the four above
- #112 cancelled (redundant third run of the same commit)
- #113 `bf96de22ed` running on a second AWS agent; expect the same four failures, since the
  percolator fix landed after it started

## 2026-08-06f - Correction: the missing DLL was not the cause

The entry above concluded that MS Amanda's percolator failed on AWS agents because its package does
not ship `vcruntime140_1.dll`. **Build #115, on the commit that stages that DLL app-local, still
reports no q-values from all three MS Amanda searches.** So the missing DLL was not the cause, or not
the only one.

What was actually established, and still stands: percolator.exe does import `vcruntime140_1.dll`;
MS Amanda's package does not ship it; it resolves from System32 on every machine where these tests
pass. What did *not* follow is that this is why percolator produced nothing on the agent - that was
inference from a failure signature, and staging the DLL disproved it.

The half that worked is the loud failure. All four tests now stop at the search with a message
naming Percolator instead of a reader error two steps downstream:

> MS Amanda produced no Percolator q-values in `Rpal_..._02.mzid.gz`, so no library can be built from
> this search.

`73f1467d8a` replaces the guess in that message with an answer: when there are no q-values, run
percolator.exe and report what happens. A negative exit code is an NTSTATUS from the Windows loader
(`0xC0000135` = a DLL it imports cannot be found), which is otherwise indistinguishable from a search
that matched nothing, because a loader failure writes no output at all. If percolator runs fine, it
says so, which moves the next person off the dependency theory.

Also confirmed by #115: the `Install.Is64Bit` fix works - its error report reads
`Skyline (64-bit : automated build) 26.1.1.218 (5bde355)` where the previous commit said `32-bit`.

### The unit test covered nothing, twice

`TestPercolatorQValueDetection` also failed on CI - it wrote fixtures into
`TestContext.TestRunDirectory`, which does not exist on a fresh agent. Fixed by testing the stream
(`5bcc598bd4`).

Worse, its "straddles a read boundary" case never straddled anything. The accession landed at ~65600,
past the 64K seam, so the carry between reads - the only non-trivial code in the method - had no
coverage. The first repair "swept" offsets around 64K, which moved the same miss by 32 characters.
A mutation run that deletes the carry entirely passed both times.

The mistake was aiming at a boundary the test cannot see: `StreamReader` decides where a read stops.
`17ea16111e` makes the buffer size a parameter (64K in production, unchanged) so the test can use 64
characters and walk the accession through every possible split. Removing the carry now fails it.

Both of today's testing lessons are the same one, and it is the one from the PrmScheduler write-back
check this morning: **a test that passes proves nothing until something has made it fail.**

## 2026-08-07 - Percolator's second missing DLL, and vendor test data the build never unpacked

Both AWS-agent failures are now fixed and the branch is one green run away from clean on that
fleet. Build #120 on `d11a068320`, on a clean agent: **1744 of 1745 passing**, the only failure
being the vendor-data one that `82570c8480` then fixed.

### Correction to the entry above

The previous entry concluded "the missing DLL was not the cause". **That was wrong in the other
direction.** A missing DLL *was* the cause - the set was just incomplete. Reading the import
directories rather than guessing a second time:

```
percolator.exe   -> xerces-c_3_1.dll, msvcp140.dll, vcomp140.dll,
                    vcruntime140.dll, vcruntime140_1.dll, api-ms-win-crt-*
xerces-c_3_1.dll -> msvcr100.dll          <- VC++ 2010, the one that was still missing
msvcp140.dll     -> vcruntime140.dll, vcruntime140_1.dll
```

`vcruntime140_1.dll` was genuinely needed (two binaries import it); it just left
`msvcr100.dll` unresolved, and the loader reports the same `0xC0000135` either way. MS Amanda's
package ships xerces but not the 2010 runtime it was built against. `msvcr100.dll` now sits in
`Shared/Lib/Microsoft.VC100.CRT/x64` beside the VC90/VC110/VC120/VC140 runtimes the repo already
vendors, and `MSAmandaSearchWrapper.StagePercolatorRuntime` stages both next to `percolator.exe`
after the tool unzips - the tool lives in a downloaded directory, so no build-time copy reaches it.

What made the second attempt land instead of being another guess: `73f1467d8a` replaced the
speculation in the error message with a probe that runs percolator and reports its exit status. The
answer came back as a fact (`0xC0000135`) rather than a hypothesis.

### Vendor test data was never unpacked by this build

`ConstantNeutralLossTest` failed on every AWS agent with `RS080806_NL_448.2_001.d does not exist`.
That fixture is not in git - the raw `.d`/`.raw` data ships inside `Reader_<Vendor>_Test.data.tar.bz2`
beside the reference mzMLs. pwiz-sharp's reader test projects unpack it through
`build/ExtractTestData.targets`; nothing in the Skyline net8 path ever did.

Where the data existed, another configuration sharing that checkout had put it there. That is luck,
not design, and **`clean.bat` deletes it**: `.gitignore`'s blanket `*.d` rule (meant for C/C++
dependency files) covers the extracted directories, so its `git clean -X` removes them. TCA1 was one
`clean.bat` away from the same failure - this was never a fresh-agent quirk.

Fixed in the projects that consume the data, not in `build.bat` (the first attempt, `15640972aa`,
put it there and was reverted): `build.bat` is only the CI path, so a developer running the test
from Visual Studio after a clean would still have hit it. `ExtractTestData.targets` now also takes a
`VendorTestArchives` item group, because Skyline's `TestData` reads Agilent, Bruker and Thermo in one
assembly and the existing property pair names one archive; the single-property form folds into the
same list, so the five pwiz-sharp importers are untouched. `TestData` declares Agilent/Bruker/Thermo,
`TestFunctional` declares Agilent.

Two things ruled out along the way, both of which looked plausible: partial extraction (bsdtar
unpacks all 10 `.d` dirs even against pre-seeded files; its exit-1 is only skip reporting), and
`TestTicChromatogram` proving the data present (it runs only in pass0, where `NoVendorReaders`
returns before touching a file - "Running 1 tests..." in the pass1 subset gave it away).

**Worth remembering**: the extraction is incremental against
`obj/.../vendor-test-data.extracted`. A machine that loses its fixtures without the archive changing
gets a green "Build succeeded" and no extraction. Delete that sentinel before concluding anything
about whether fixtures are being unpacked.

### Also settled today

- `Install.Is64Bit` confirmed fixed in the wild: #115's error report said `32-bit` on a 64-bit
  agent, #117 onward say `64-bit`.
- The unit test added for the q-value gate broke CI (wrote into `TestContext.TestRunDirectory`,
  absent on a fresh agent) and its "boundary" cases covered nothing - twice. Both caught only by
  mutation runs; see `17ea16111e`, which makes the scan's buffer size injectable so the seam is
  where the test puts it.

### CI state at end of session

| build | commit | agent | result |
| --- | --- | --- | --- |
| #120 | `d11a068320` | AWS | 1744/1745 - only the vendor-data failure, fixed since |
| #119 | `d11a068320` | TCA1 | 1745/1745 |
| #118 | `17ea16111e` | AWS | 5 failures (pre-fix) |

No run yet on `15640972aa` or `82570c8480`.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260807_net8_percolator_vendordata.md` before starting work.

## 2026-08-07b - The perf suite's one failure: a tool tip timer holding the window

`ProteoWizard_SkylineWindowsNetPerfTutorialTests` #29 (`d11a068320`) had exactly one failure,
`TestDiaFragPipeTutorial-en`: **"Objects not garbage collected after test: SkylineWindow,
SrmDocument"**. Same failure in #27; #28 failed with no failed tests. Fixed.

### What roots the window

Reproduced locally (the test needs the 4 GB `Webinar26.zip`; `SKYLINE_DOWNLOAD_PATH` points at
`C:\test\Skyline\downloads`, and a file already there is not re-downloaded). Then answered by a
dump rather than by inference - `GarbageCollectionTracker` now writes a full-memory dump at the
leak moment when `SKYLINE_GC_LEAK_DUMP=<dir>` is set, before it pins the survivors so the only
roots in it are the real ones. `dotnet-dump analyze ... -c "dumpheap -type
pwiz.Skyline.SkylineWindow" -c "gcroot <addr>"` returned one path:

```
(strong handle) -> ToolTip+ToolTipTimer            _interval 5000, _enabled 1
                -> ToolStripDropDownMenu           (the timer's Host)
                -> ToolStripMenuItem
                -> EventHandlerList -> EventHandler
                -> pwiz.Skyline.Menus.ChromatogramContextMenu
                -> pwiz.Skyline.SkylineWindow
```

WinForms shows a tool tip for the drop-down item being selected and arms the owning ToolTip's
5-second auto-pop timer to take it down again. `Timer.Start()` roots the timer with a GCHandle, and
`ToolTipTimer.Host` is the drop-down, whose owner item's Click handler holds a Skyline menu class,
which holds SkylineWindow. A user's mouse leaving the item hides the tool tip and stops the timer.
**A test drives menus without a mouse, so nothing hides it, and the UI message pump ends with the
test before the timer could fire on its own** - so the handle is never released. In the app it
self-heals five seconds later; in a test it cannot.

That is also why it only showed up here: the tool tip has to appear at all, which takes the item
staying selected past the initial delay. A scratch test that drove the same verbs (native Open
dialog, Edit > Find, the peak-area graph's right-click *Normalize To > Default (None)* submenu)
against a small document did **not** leak - everything completed too fast. The 75 MB / 10-replicate
FragPipe document loses that race: **10 tool tip timers were still armed** when it ended.

### Fix

`AbstractFunctionalTest.EndTest` now calls `ReleaseToolStripToolTips()` beside the existing
`ReleaseModalMenuFilterWindow()` (same `#if !NET472` block, same reason, same reflection
constraint - `ToolStripManager`'s ToolStrip list is thread-static, so it runs on the UI thread).
It walks that list and does what `ToolTip.StopTimer()` does to any armed timer. Where the earlier
helper returns silently if WinForms moved a field, this one asserts: a GC-leak failure in an
unrelated test is a long way from the rename that caused it.

Verified by making it fail: with the call commented out the test fails again on the same machine
with the same cached data; with it, `TestDiaFragPipeTutorial` passes twice in a row (20s, 15s), and
26 menu/connector/dialog functional tests (all `*McpConnector*`, `TestLiteDropdownList`,
`TestZedGraphClipboard`, `TestReportErrorDlg`, `TestNativeFileDialog`, `TestNativeMessageBox`,
`TestAlertWatch`) plus `CodeInspection` still pass.

### Two things seen on the way

- ~~`ci.skyline.ms` returns **403** for `webinars/Webinar26_data/Webinar26.zip`~~ **Mirrored the same
  day.** The whole `webinars/` prefix was empty - no webinar data had ever been mirrored - so the 403
  was an anonymous "not there". `ci.skyline.ms` is **`s3://mc-tca-01/`**; the bucket is not named for
  the host, and the mapping was proved by matching `tutorials/MethodEdit.zip` at 44,891,249 bytes on
  both. Uploaded to `webinars/Webinar26_data/Webinar26.zip` as STANDARD (existing objects are
  STANDARD_IA, but IA carries per-GB retrieval charges and a lifecycle rule, if any, will transition
  it anyway). The bucket policy does cover that prefix: an anonymous HEAD returns 200 with the right
  length and a ranged GET returns `PK\x03\x04`. **Gotcha for next time**: the CI service user
  (`svc-teamcity-server`) can read objects but is denied `GetObjectAcl`, `GetBucketPolicy` and
  `GetLifecycleConfiguration`, so public-read and storage-class conventions can only be confirmed
  empirically from outside.
- On CI (not locally) cleanup warns `Could not find a part of the path
  'c:\skyline-downloads\Webinar26_data\Webinar26'`. `PersistentFilesDirTotalSize` is only set when
  that directory exists at extraction time, so it existed then and was gone by cleanup - something
  on the agent removes it mid-run. Harmless to the test, but it means the 4 GB is re-extracted
  every time.

### Reusable

`SKYLINE_GC_LEAK_DUMP` is kept in `GarbageCollectionTracker` (env-gated; unset costs one
environment read per detected leak). This is the second time the dump-the-leak-moment probe has
been needed - the ModalMenuFilter root was found the same way - and last time it had to be
rebuilt from scratch.

## 2026-08-11/12 - msconvert-sharp cpp parity: 95 -> 298 identical files

Drove the C++-vs-C# `msconvert` corpus parity sweep from 95 identical files to 298, and closed the
last "format not ported" gap. 14 commits, `a2d02bf31e`..`ec3f617de2`.

### The measurement, and two traps in it

The sweep converts every corpus input under 100 MB (492 files, 7.1 GB) with both binaries using
identical flags and compares the mzML semantically. Durable notes are in the
`reference_msconvert_parity_sweep` memory. Results: `G:\parity\results-20260810.jsonl` (baseline)
and `results-20260811.jsonl` (current).

| status | 10 Aug | 12 Aug |
| --- | ---: | ---: |
| identical | 95 | **298** |
| differs | 320 | 124 |
| cs-failed | 8 | **1** |

**Trap 1 - the comparator pairs records POSITIONALLY** and labels each pair with the C++ id. When
the two sides emit different record SETS it reports unrelated records as differing. Most of the
original "defaultArrayLength" findings were really record-set differences, and the fix belonged in
index construction. `MS:1000511 ms level` appearing to differ 2.0 vs 1.0 was this artifact in all
16 cases. Always diff `(id -> value)` keyed by id before trusting a per-record number.

**Trap 2 - per-file diff lists cap at 60**, and 213 of 492 files hit the cap: 40,197 diffs reported,
13,907 retained. File counts are sound; hit counts are floors. The Thermo work re-measured with a
key-based comparator and found ion injection time was 15,210 hits, not the 253 the sweep showed.

### Bruker YEP / FID now read, via CompassXtract COM (`465ded2ce7`)

The last unported format. A prior session had proved .NET 8 can drive the COM server
registration-free; this builds the reader on that. Three things had to be right:

- **Activation context is per-THREAD** and must be entered per operation, not once at open - a
  reader opened on one thread is read on others, and the manifest's `comInterfaceExternalProxyStub`
  entries are what let an EDAL pointer marshal across apartments.
- **CompassXtract's own object factory resolves its plugin DLLs relative to the host EXE's
  directory.** Neither the activation context's assembly directory nor `PATH` satisfies it - the
  vendor cache alone yields `TypeNotInFactory` for `BDal.CCO.Transformation`. The payload is
  therefore copied from the cache next to the host on first use, marker-gated on the pin; where
  that directory is not writable the user is told to run one conversion elevated. This is the one
  vendor SDK the download-to-cache model cannot serve on its own.
- `EDAL.IsolationModes` is named in `GetIsolationData`'s FieldMarshal blob and the CLR resolves that
  name in the assembly holding the signature. Under `EmbedInteropTypes` the compiler embeds only
  interop types it SEES USED, and nothing referenced the enum. `GetFragmentationData` survived the
  identical descriptor only because `SetActivation` happened to switch on its enum.

Two cpp quirks reproduced deliberately (`getChargeState`'s word branches are expression statements
with no `return`; `getIsolationWidth` truncates through an `int`), and a third that is load-bearing
in the other direction: `MSSpectrumParameterIterator::equal` terminates on a one-based index, so an
enumeration never yields the LAST parameter - and `MS(n) Isol Width` is the last one. cpp therefore
never reads it and emits no isolation offsets; matching that needs the same off-by-one.

VC90 CRT/MFC/OpenMP ship beside the reader and are mirrored into the cache. The vendored
`Microsoft.VC90.OpenMP.manifest` declared no `<file>`, i.e. it was the WinSxS variant rather than
the app-local redistributable one, so a private `vcomp90.dll` could never have been found - repaired
for x86 and x64, which the C++ and Skyline trees share.

### The parity fixes, by shape

**Wrong SOURCE, not wrong arithmetic** - the most common shape:

- Sciex collision energy (`a7659e330b`): cpp reads the experiment's "CE" ramp parameter; we read
  `MassSpectrumInfo.CollisionEnergy`, the instrument's rolling readback. Method-programmed 10.0 vs
  measured 35.78. Three unrelated defects on one cvParam plus a fourth in the opposite direction.
- Sciex BPC time axis (`679c6c79b6`): cpp pairs the TIC's X axis with the BPC's intensities and
  never reads the BPC's own X. On DMS/SelexION the SDK indexes that chromatogram by COMPENSATION
  VOLTAGE - our BPC ran -5.0, -4.75, -4.5 where cpp has retention times. Every value wrong.
- Thermo scan window (`aa2b173c97`): cpp uses ScanStatistics LowMass/HighMass; we used the filter's
  ranges, which state what was REQUESTED (2000.0 vs an acquired 2000.00005).

**A fix that existed in one place and was never swept to the others:**

- Bruker duplicate `dataProcessing` (`80a6248d85`) - Thermo had already dropped its second entry.
- Agilent all-ions promotion (`ec3f617de2`) - already ported into the IM path, never into the main
  one, so `AE_30Apr19_negESI_0001.d` came out as 723 ms-level-1 spectra with no precursorList where
  cpp emits 723 at ms level 2. cpp's guard `1==msLevel || (2==msLevel && isIonMobilityScan)` has its
  two halves on the two different code paths.

**Dead CLI wiring** - `--ignoreMissingZeroSamples` and `--acceptZeroLengthSpectra` were parsed and
never copied to `ReaderConfig`, and the readers that consume them in cpp mostly had no branch to
reach. Skyline passes `--acceptZeroLengthSpectra` in four DDA/DIA paths and was silently not getting
it.

**The formatter** (`af894d3f0b`): `PwizFloat` rounded in the DECIMAL domain
(`Math.Round(v, 12, AwayFromZero)`), which .NET implements by scaling the whole value - losing low
bits and manufacturing ties that do not exist in binary. karma splits with `modf`, scales only the
FRACTIONAL part, and takes `floor(x+0.5)` in the number's own type. ~6,400 values. Ported
`real_inserter::call_n` generic over `IFloatingPointIeee754` so `float` rounds in SINGLE precision -
cpp instantiates the whole generator on `float` and widening is not equivalent. Validated against a
C++ generator built on the same boost headers over 433,604 values: zero differences.

### Test blind spots this exposed - the theme worth carrying

Three separate bugs survived because the tests are shaped not to see them:

- `MSDataDiff.DiffChromatogram` never compared `Precursor`/`Product`, unlike cpp `Diff.cpp:584-585`,
  so chromatogram-level collision energy was invisible to EVERY vendor reference test. Now compared.
- The vendor harness compares cvParams **numerically with tolerance**, so a last-digit text
  difference cannot fail a reference test. That is why the formatter bug lived so long.
- The Bruker combineIMS references are the only ones run for that config and they have NO
  chromatogram list, so the whole chromatogram path was untested. `Reader_Bruker_Test.cpp:131` sets
  `peakPicking` before every combineIMS tier and never clears it, so cpp only ever writes the
  `-centroid` references; the non-centroid ones are leftovers nothing generates or checks. We had
  been asserting against them, and matching them had forced a reader-level suppression that made
  ordinary `--combineIonMobilitySpectra` differ from msconvert.

`IsRunningInTestRunner` was `#if`'d to a hardcoded `false` on net8 (`7e58e83d67`), so
`SkipWiff2TestInTestExplorer` skipped `FileTypeTest` and `Wiff2ResultsTest` everywhere - the wiff2
path had no Skyline-level coverage at all, which is how a 12-sample `.wiff2` converting only its
first sample went unnoticed.

### Environment gotchas

- **SDK resolution follows the WORKING DIRECTORY.** `global.json` (pinning 8.0.100) lives in
  `pwiz-sharp/`, not the repo root. Building from the root silently selects a newer SDK whose
  analyzers reject existing code - `MsData.Tests` "does not build" is that, not a breakage.
- **`dotnet build -o <dir>` is NOT equivalent to the normal output layout.** It omits the `wiff2`
  plugin subdirectory, so every `.wiff2` fails to load its SDK. This produced a phantom 8 -> 44
  `cs-failed` regression in the sweep. Bit twice.
- Reproduce the Linux CI configuration on Windows with
  `-p:IAgreeToVendorLicenses=true -p:NativeVendorsAvailable=false`. Dropping the license flag is NOT
  equivalent - that also defines `NO_VENDOR_SUPPORT`, so `Read` throws before reaching the
  CompassXtract stub and the build passes without exercising it.
- The corpus buckets vendor by top-level directory under `D:\test`, and at least three "Mobilion"
  `.d` are Agilent MassHunter. Confirm format from the mzML header, not the path.

### Where it stands

492/492 swept. 298 identical, 124 differ, 1 `cs-failed` (a Sciex `no-spectra` file). Sciex 174/188
and Thermo 89/98 identical. Note the sweep predates the last five commits, so Bruker (18 files),
`arrayLength` (10), Thermo scan windows and the Agilent all-ions file are not yet reflected in it.

Largest remaining category is **17 Agilent files needing the unported non-MS device chromatograms** -
cpp's `translateAsChromatogramType` (`Reader_Agilent_Detail.cpp:231`) maps pumps, samplers and
detectors to flow-rate/pressure/generic chromatograms; our port covers only UV/DAD absorption, and
its own header says so. That is a feature port, bounded by cpp's switch statement, not a defect.

Unexplained and worth a look: three files moved from `cpp-failed` into `both-failed` between the two
sweeps.

## 2026-08-12 - Agilent non-MS device chromatograms; the `both-failed` three explained

Closed the largest remaining parity category and answered the one metric that had moved the wrong
way. The 17 Agilent files flagged `extra C++ records` are now 16 identical and 1 left with
pre-existing TIC floating-point noise; the whole Agilent bucket went **8 identical -> 25**. All 20
pwiz-sharp suites pass (646 tests, 0 failures), in both the normal and the
`-p:NativeVendorsAvailable=false` (Linux CI) configuration.

### The port was reading the wrong source, not computing the wrong thing

The recurring shape again. `ChromatogramList_Agilent` enumerated signals from
`INonmsDataReader.GetSignalInfo(device, Chromatograms)` and joined descriptions in from the signal
table. cpp `MassHunterDataImpl::getSignals` (`MassHunterData.cpp:592`) does the opposite: the
**signal TABLES are the enumeration**, one `Signal` per row of `GetSignalTable(dev,
Chromatograms)` *and* one per row of `GetSignalTable(dev, InstrumentCurves)`; `GetSignalInfo` only
populates a name-keyed map used later to fetch data. Four things followed from that:

- **`InstrumentCurves` was never read at all** - which is where pump traces live. Both of
  `enolase-02.d`'s LowflowPumps are in it.
- Pumps and samplers had no classification. cpp keys them off the *description*
  (`icontains "flow"` -> flow rate, `"pressure"` -> pressure), and its sampler cases fall through
  into the pump cases with no body of their own.
- `isInstrumentCurve` was not modelled, so detector instrument curves - which cpp suppresses -
  would have come through as absorption chromatograms once the table was read.
- Pressure and flow needed their own intensity units and cpp's scale factors (`1e5`, `1e-6`).
  Neither factor is dimensionally what its cpp comment claims; both are reproduced verbatim, and
  the emitted binaries match cpp bit for bit.

Ported as `AgilentRawData.Signals` / `GetSignal(AgilentSignal)` mirroring cpp's own split, so the
classification table in `ChromatogramList_Agilent` is a line-by-line port of
`translateAsChromatogramType` (`Reader_Agilent_Detail.cpp:231`). `enolase-02.d`: 106 -> 110
chromatograms, **zero semantic diffs vs cpp**.

### The guardrail caught what the target file could not

Re-running the full 50-file Agilent bucket (not just the 17) showed one file *gaining* records:
`Dorrestein_GnPS_*.d` picked up `BinPump1 A: Pressure` / `B: Flow` that cpp does not emit. Reason:
ion-mobility files go through `MidacDataImpl`, whose `getSignals()` returns a member vector that is
**declared and never populated** (`MidacData.hpp:81,107`), and whose `getSignal()` returns null. So
cpp emits no non-MS chromatogram for any IMS file, however many pump curves the `.d` holds.
`EnsureSignalsLoaded` now returns early on `HasIonMobilityData`.

Worth keeping as a habit: the fix verified perfectly on its target file and regressed a different
one. Only the whole-bucket re-run showed it.

### Test coverage for the half no fixture reaches

No shipped `.d` fixture has a pump or sampler signal - the reference mzMLs cover exactly one device
chromatogram, a DAD absorption trace - so the pump/sampler/instrument-curve half of the table
cannot be covered by the reference tests at all. `TranslateAsChromatogramType` is now `internal`
(`InternalsVisibleTo`, as Thermo and Waters already do) with one table-driven test over all four
buckets. Note `Agilent.csproj`'s SDK `<Reference>` items are not transitive, so the test project
needs its own reference to `BaseCommon` for the `DeviceType` enum - and it must keep
`<Private>true</Private>`: declaring the reference with `Private=false` takes over how the DLL
reaches the output and breaks *every* fixture test with "Could not load file or assembly".

### Empty `spectrumList` is now omitted, as cpp does

`MzmlWriter.WriteRun` wrote `<spectrumList count="0"/>` where cpp gates both lists on
`ptr && size() > 0` (`IO.cpp:3261`). Chromatogram-only files (`enolase-02.d` and every other
SRM-only `.d`) carried an element cpp never writes. The mzMLb spectrum-index block is already
guarded on `offsets.Count > 0`, so nothing consumes the end-of-list anchor that is now unset.

### The three `cpp-failed` -> `both-failed` files: an artifact, and a real build bug behind it

There are **four**, not three, all Sciex `.wiff2`, and all four convert fine today - C++ still fails
on them identically, so the honest 11 Aug tally is `cpp-failed` 34 / `both-failed` 33 and **no
metric moved the wrong way**.

The cause was a build defect, now fixed. `MsConvert.csproj` staged the wiff2 plugin into
`$(OutputPath)wiff2` by string concatenation. MSBuild's trailing-slash normalization of
`OutputPath` cannot touch a *global* property, so `dotnet build -o <dir>` left it slash-less and the
directory landed at the **sibling** `<dir>wiff2`. `Wiff2LoadContext` then found no plugin directory,
fell back to the default-ALC SQLite/Unity, and every `.wiff2` failed to open. `G:\parity\`
still holds both stray sibling directories, timestamped one second after the builds that made them.
The sweep was resumed mid-run after the directory was hand-created, which is why only the 4 files
converted before the fix stayed failed - and why `cs-failed` also dropped 8 -> 1. Fixed with
`$([MSBuild]::EnsureTrailingSlash(...))` in `MsConvert.csproj` and `Sciex.Tests.csproj`, verified by
rebuilding with `-o` and converting `OnyxTOFMS.wiff2` (no stray sibling, exit 0).

This is the second time `dotnet build -o` has cost this project a day; the handoff had it as a
"remember to `cp` the wiff2 dir" workaround, which is now unnecessary.

### Two things worth knowing next time

- **`extra C# records` in `mzml_compare.py` is not necessarily about spectra.** The comparator zips
  two positional streams that carry header elements, spectra *and* chromatograms; a chromatogram
  count difference reports as `spectra_only_cs` with `where: "run"`. Count records per kind before
  reading the label. (Companion to the existing positional-pairing trap.)
- **cpp itself is nondeterministic on some Agilent files.** `QTOF/20fmolBSA-centroid.d` gives
  different `lowest/highest observed m/z` on consecutive runs (143.083066394823 vs 143.083066479,
  143 lines of 124,585); C# is byte-identical run to run. That file's ~80 `cvParam value differs`
  cannot go to zero, and its diff count wobbles between runs for that reason alone.

### Still open in Agilent

`cvParam value differs` (the IM `instrument model` / serial-number header block, several files),
`child count (precursor)` on `PreCursor Ion Scan Neg C6.d`, and the benign TIC binary noise. Both
`13APR002.D` and `16026.d` fail on both sides.

## Sweep of 2026-08-12: 334/492 identical

`G:\parity\results-20260812.jsonl`, snapshot built at HEAD + the Agilent chromatogram work.
**The two Sciex empty-spectra fixes landed after the snapshot**, so the five files they fix are
still counted as `differs` here; verified separately at 0 diffs each.

| status | 10 Aug | 11 Aug | 12 Aug |
| --- | ---: | ---: | ---: |
| identical | 95 | 298 | **334** |
| differs | 320 | 124 | 87 |
| cs-failed | 8 | 1 | 1 |
| cpp-failed | - | 34 | 35 |
| both-failed | - | 33 | 33 |

Per vendor (identical / differs / failed): Sciex 173/14/39, Thermo 89/9/11, Waters 26/26/4,
Agilent 25/23/2, Bruker 17/1/2, Shimadzu 0/10/13, Mobilion 3/4/0, PerkinElmer 1/0/0.

37 inputs newly identical. Exactly one moved off `identical`, and it is not ours:
`wiff vs wiff2 peaks\22_0430_006_SSL2_ND_Inj_29_01-wiff1.wiff` is now `cpp-failed` because the
C++ binary hit the harness's 420 s cap (the C# side finished the same file in 253.8 s, and the
machine was running the test suite at the time).

Biggest remaining buckets: **Waters 26 differs** (untouched all session, now the largest),
**Shimadzu 0 identical of 23** - 13 of which fail on both sides - and Agilent's 23.

## Standing record: where C# emits MORE than cpp

A C#-side **deficit** is usually "not ported yet" and explains itself. A C#-side **surplus** never
does: either we are inventing data cpp never emits, or cpp deliberately drops something - an
unreachable branch, an off-by-one that suppresses the last item, a suppression rule - that we
failed to reproduce. Both are defects, and they are the ones the suite structurally cannot see:
every vendor reference mzML is generated by cpp, so extra C# output only surfaces in a corpus
sweep. Two already caught this way: Agilent pump chromatograms emitted for IMS files where cpp's
MIDAC path emits none (fixed 2026-08-12), and Bruker's duplicate `dataProcessing` (fixed
`80a6248d85`).

The mirror case - where **cpp** emits more and we have decided not to reproduce it - is recorded
in "Standing record: cpp-side defects we deliberately do not reproduce" at the end of this file.
Check both before treating any `differs` file as unexplained.

`ai/.tmp/parity-scripts/cs_surplus.py <results.jsonl>` classifies every diff by direction and
prints the surplus files by vendor and category. **Run it after every sweep and refresh the table
below** - it is a few seconds of work and it is the only inventory of this class.

Inventory below is from `results-20260812.jsonl`: **16 of 492 inputs**, down from 37 on 11 Aug.
Resolved since then: Bruker `dataProcessingList` x18 (`80a6248d85`) and the Sciex empty spectra
x5 (both fixes below; the Sciex one landed after the sweep snapshot, so those five files still
read `differs` in the raw results).

**A per-record number is only meaningful when the two record streams are aligned.** If a file
also shows `spectrum/@id` diffs, the comparator is pairing record N against record N+k and every
length it prints compares unrelated spectra. Reading those literally turned "834 extra empty
spectra" into a phantom **"45,402 extra peaks"** that does not exist - every shared id had a
byte-identical array. `cs_surplus.py` now flags such files `[OFFSET STREAMS]` and counts only the
id-independent categories for them; use `arraylen_by_id.py` to get their real surplus.

| where | files | what C# adds |
| --- | ---: | --- |
| Sciex MRM3 `child count (precursor)` + `extra cvParam` | 2 | `220124_095/096_MRM3_*.wiff2`, 12 each. An extra precursor child per spectrum. Largest remaining. |
| Agilent `child count (precursor)` | 1 | `PreCursor Ion Scan Neg C6.d`, 30. Still open. |
| Agilent `extra cvParam` | 9 | Mostly the IM header block (`instrument serial number` we emit, cpp does not) plus `20fmolBSA-centroid.d` x11 and `AE_30Apr19_negESI_0001.d` x12. |
| Bruker tsf `componentList/@count` | 1 | `0.1HCOOH_H20_NoTIMS_Pos.d`, 4 extra components. |
| Thermo `extra cvParam` | 1 | `MAT95XP-File001.RAW`, 2. |
| Sciex `extra cvParam` | 2 | `UV/_Sample_Run_004.wiff` x1, plus 2 on files already listed above. |
| Agilent `extra cvParam` (instrument class) | all | **Deliberate, 2026-08-18.** The MS:1003761 instrument class term. Ours until the cpp change lands upstream - see the 2026-08-18 entry. |

### Sciex: empty spectra we index and cpp does not (2026-08-12)

cpp `SpectrumList_ABI::createIndex` (`SpectrumList_ABI.cpp:314`) keeps a cycle only when **both**
the per-cycle BPC (fallback TIC) intensity is `> 0` **and**
`getSpectrum(...)->getDataSize(false, true) > 0`. The C# port had dropped the second condition on
the reasoning that the first implies it - and on the real perf grounds that the probe reads the
file's whole spectral payload at index-build time, which on .NET 8 made a large TripleTOF `.wiff`
exceed GraphFullScan's scan-load reopen timeout. The reasoning half of that is false. Two distinct
populations of cycle pass the BPC test with nothing to read:

1. **Sentinel base peak.** `wine yeast sampleA_2.wiff` has 834 MS2 cycles reporting base peak
   `1.0` at m/z `2.35e-07` with cycle TIC `0.0`. **Fixed**: the index now also requires the cycle
   TIC `> 0`. That array is `Spectrum::getSumY` (cpp `WiffFile.cpp:740`), a sum over the very
   points `getDataSize` counts, and it is already materialized by the BPC fetch - so this
   reproduces cpp's intent at zero I/O. The file went from **87 diffs to 0** (32,583 spectra, id
   sets and every array length identical). `Sciex.Tests` 8/8.
2. **Plausible-looking but unreadable.** `20061108_CPTAC_1B468.wiff` has 448 cycles with TIC
   `7543.0` and base peak `3.0` at a real m/z that still read back zero points;
   `201208-378803.wiff` has 61, `trap25_9031_A7_A8.wiff` 3. No chromatogram-level value
   distinguishes these, so only cpp's actual per-spectrum read does. **Fixed behind a flag**:
   new `ReaderConfig.VerifyNonEmptySpectraAtIndex`, defaulting **off**, which msconvert-sharp
   turns on unconditionally in `Converter.BuildReaderConfig` and Skyline leaves alone. Not a cpp
   config field - cpp always probes; it is optional here purely because of the .NET 8
   GraphFullScan reopen timeout that caused the probe to be removed in the first place. No CLI
   option: a conversion always wants cpp's spectrum set.

**All five files are now byte-for-byte semantically identical to cpp**, 2,613 diffs -> 0:

| file | diffs before | after | spectra |
| --- | ---: | ---: | ---: |
| `wine yeast sampleA_2.wiff` | 87 | 0 | 32,583 |
| `alan-race/msconvertIndexOutOfBounds.wiff` | 2272 | 0 | 92 |
| `trap25_9031_A7_A8.wiff` | 87 | 0 | 8,841 |
| `20061108_CPTAC_1B468.wiff` | 84 | 0 | 3,011 |
| `201208-378803.wiff` | 83 | 0 | 2,235 |

Note how much rode on the record offset: each file's 80-odd `cvParam value differs`,
`child count (spectrum)` and `binary values` entries were all the comparator lining up
neighbouring spectra, and they vanished with the alignment.

**Cost of the probe**, measured while the corpus sweep was running (so an upper bound):
`20061108_CPTAC_1B468.wiff` 13.1s -> 19.7s, `201208-378803.wiff` 1.7s -> 2.9s. cpp does the same
probe and converts the first in 13.7s, so we are ~45% slower than cpp at the identical work -
a pre-existing gap in the read path, not something this flag introduced.

---

## 2026-08-17/18: peakPicking sweep, four vendor fixes, Skyline distro zips

### Default-path parity fixes (four parallel vendor investigations)

All uncommitted in `pwiz-net8`. Every change is backed by its vendor reader test; 98/98 across
Sciex/Agilent/Shimadzu/Common/Mobilion/Thermo.

**Shimadzu - msconvert-sharp was FABRICATING 12,884 spectra.** On
`20200929_QC(100x)_022.lcd`, `ShimadzuRawData.TryGetEventLastScanNumber` returned `0` for both
"SDK call failed" and "SDK succeeded, no scan near endTime". The caller treated any `0` as
failure and tripped the net8 `SumScanCountsFromTics` fallback, which estimates a scan count from
TIC point counts and duplicated SRM chromatogram data as spectra. cpp
(`ShimadzuReader.cpp:277-279`) treats `S_OK` + scan 0 as normal and ends with `scanCount_ == 0`
and no `spectrumList`. Fixed with an explicit `out bool callFailed` so the genuine-failure
fallback (net8 `QtflRawDataMain` binder flakiness, TC 3975296) is preserved. This is wrong
OUTPUT, not a parity nit. Also fixed: two files missing `precursorList` entirely (C# gated on
`msLevel > 1` and read only `GetMSSpectrumInfo`; cpp resolves in three tiers and gates purely on
`precursorMz > 0`, the missing tier being `MassSpectrumObject.AcqModeMz`, the parked Q1 mass of a
product-ion scan), and 59 empty MS2 scans missing `binaryDataArrayList` from a `totalPoints > 0`
guard cpp does not have. All 10 Shimadzu corpus files are now `startTimeStamp`-only.

**Agilent - the TIC came from the wrong source.** `FillTic` walked scan records
(`IMSScanRecord.Tic`); cpp reads the SDK's `GetChromatogram(TotalIon)`. On centroided QTOF runs
those disagree by up to **84% relative** - `BSA-ms2-centroid.d` had 426/587 values wrong,
max_abs 2.97e6. Also fixed: `fileContent` representation terms now come from MIDAC's
`TfsMsDetails.MsStorageMode` on IM files (cpp `MidacData.cpp:244-247`), not the MassSpec SDK's
`SpectraFormat` - the two disagree in BOTH directions.

**Shared writer bug (`MzmlWriter.cs`)**: `<isolationWindow>` was written unconditionally; cpp
guards on non-empty at `IO.cpp:1216` / `:1339`. An Agilent precursor-ion scan puts the isolation
window on the PRODUCT, so C# emitted a bare empty isolationWindow on all 2946 spectra. Verified
cross-vendor: Thermo 57/57 windows 0 diffs, Sciex 1591/1591.

**Shared formatting bug (`PwizFloat.cs`)**: cpp renders cvParam doubles through
`boost::spirit::karma`, whose `test_negative` for floating point is specialised on
**`core::signbit`**, not `n < 0`. The quiet NaN both runtimes circulate
(`0xFFF8000000000000`, i.e. .NET's `double.NaN`) has the sign bit set, so karma writes `-nan`.
Our karma port returned bare `"nan"` and dropped the sign, though the `-inf` line below it
already did the signbit test. 612 occurrences on one file, 82 diffs to 1. NOTE: that file
(`2020-12-28-...NISTmAbOxidized[1].d`) is **Agilent**, not Mobilion - the sweep buckets by
parent directory name.

**Sciex** - MRM3 wiff2 MS-level (cpp switches on experiment type alone, not msLevel),
precursor-ion scans emitting `productList` not `precursorList`, and the UV `scan start time`
fallback removed.

### Sciex regression the sweep caught, and why divergences are dangerous

The Sciex `chromatogram/@id` work introduced a **deliberate divergence** that regressed 19
previously-identical files. cpp passes its 1-BASED sample number to the 0-BASED
`Batch::GetSample` (`WiffFile.cpp:449`), so it reads the NEXT sample's software version and
throws on the last, leaving `hasHalfSizeRTWindow` false. That off-by-one is **load-bearing for
single-sample files**: with one sample cpp's read always throws, so it always takes the
half-width branch. Reading this sample's real version flipped them to full width and renamed
every scheduled SRM chromatogram (`start=1.01 end=2.01` became `start=0.51 end=2.51`, 60
ids/file). Restored cpp's behaviour as `SampleNumber < SampleCount` at the call site rather than
opening a second `Sample` (native-handle leak risk). Result is strictly better than either prior
state: the 15-sample file now matches cpp on **all 15** samples. Lesson: four agents each
reported clean local verification; only the full corpus caught it.

### Comparator bug (`mzml_compare.py`) - two halves, one dangerous

`NaN != NaN` is true in IEEE, so every both-NaN slot counted as differing; and `max(0, nan)` is
`0`, so the magnitude never rose. Two failure modes: identical-but-NaN-containing arrays reported
as differing with the tell-tale `max_abs=0 max_rel=0` signature, and - the quiet one - **a slot
where one side is NaN and the other a real number ALSO reported `max_abs=0`**, reading as
negligible. Fixed: both-NaN is equal, differing sign bit counted separately, NaN-vs-number and
infinities report `inf`. `test_mzml_compare_nan.py` covers both halves, 11 checks. Two Agilent IM
files were never really differing on binary data.

### peakPicking sweep - FIRST EVER run (492/492 complete)

The corpus sweep had only ever run one configuration, so **every vendor's centroiding path was
unexercised** - covered only by the ~31-file-per-vendor reference harness. Added `--peak-picking`
to `run_parity2.py` (own `work2-pp` scratch dir, stamps `peakPicking: true` into each record).
Filter is `peakPicking vendor msLevel=1-`, placed AHEAD of the index slice because msconvert
applies filters in command-line order.

`G:\parity\results-20260817-peakpicking.jsonl`: **identical 274 | differs 108 | cs-failed 29 |
both-failed 60 | cpp-failed 19 | different-output-files 2**

| vendor | identical | differs | cs-failed |
| --- | ---: | ---: | ---: |
| Sciex | 127 | 57 | 1 |
| Thermo | 95 | 2 | 1 |
| Waters | 34 | 9 | 1 |
| Bruker | 17 | 1 | 0 |
| Agilent | **0** | 29 | 19 |
| Shimadzu | **0** | 10 | 0 |

**The cs-failed cluster is a filter-semantics divergence, not a missing vendor implementation.**
Neither implementation can vendor-centroid Agilent - cpp's own warning names it
(`SpectrumList_PeakPicker.cpp:158`: "not available for this file (non-vendor, UNIFI, **Agilent**
or Waters IMS format); falling back to ..."). cpp ALWAYS constructs a fallback detector
(`SpectrumListFactory.cpp:377-392`: `CwtPeakDetector` or `LocalMaximumPeakDetector(3)`) and
treats `vendor` as a preference. C# made `vendor` mean vendor-or-throw - its own docstring at
`SpectrumListFactory.cs:324-328` documents the divergence. Fix is small: construct the fallback
for `vendor` as cpp does. Note `peakPicking true` already falls back on both sides, so the
sweep's 29 cs-failed partly reflect the chosen filter spelling.

Also new under peakPicking: `processingMethod` says `user:vendor-only peak picker` where cpp says
`user:Agilent/MassHunter peak picking`.

### Skyline: build, distro zips, and a fatal config bug

**`Skyline-daily.exe` would not start at all** - `Unrecognized configuration section system.data`
aborting `ClientConfigurationSystem.EnsureInit`. `system.data` is a built-in section on .NET
Framework (registered by machine.config); .NET 8 ships no machine.config, so an undeclared
section is a hard parse error that takes down the WHOLE configuration system on first access.
The block registered a `DbProviderFactories` entry for System.Data.SQLite that nothing reads -
every call site does `new SQLiteConnection(...)` directly. Fixed with `App.net8.xslt`, applied
via `_GenerateNet8AppConfig` in `Skyline.csproj`, stripping `system.data`, `startup` and
`runtime` from the net8 leg only (Skyline multi-targets net472 off the SAME 46 KB App.config, so
forking a copy would drift). Verified: GUI launches with `MainWindowTitle: 'Start Page'`, from
both the build output and inside SkylineTester.zip.
**Why nothing caught it**: the entire functional suite runs through TestRunner, which loads
Skyline as a LIBRARY. The build was green and the app would not start. Worth a smoke test that
actually launches the exe.

**Distro zips restored.** `tcbuild.bat`/`build.bat` built none of
`SkylineTester.zip` / `SkylineNightly.zip` / `BiblioSpec.zip` - the Jamfile's
`create_skyline_zips` rule (`Jamfile.jam:362-381`) had no net8 equivalent. Now: any bare `*.zip`
argument to `build.bat` is forwarded to a `DistroZips` target in `SkylineTester.csproj` (a target
cannot be NAMED for the artifact - MSBuild rejects `.` in target names, MSB5016 - and `-p:` treats
both `;` and `,` as property separators, so the list is passed escaped as `%3B` and unescaped in
the target). Artifacts land in `pwiz_tools/Skyline/bin/staging-net8/<Config>/` (gitignored, so
tcbuild's `git status` hygiene check stays clean; TeamCity artifact paths would need updating).

- `SkylineTester.zip` **313.6 MB** (was >4 GB). Root cause was NOT the missing
  `UseZip64WhenSaving` first added: on net8 **TestRunner executes FROM the staging dir the zip
  is built from**, so "add every subdirectory" swept up 564 `Tools_*`/`Toools_*` per-test tool
  installs (13.9 GB), `CachedDownloadsForTests` (1 GB), 333 per-test `.zip` (1.6 GB) and stale
  `DotNetZip-*.tmp`. Excluded via `IsTestRunResidue`. DotNetZip writes `<name>.tmp` and renames
  on success, so every failed attempt leaves a multi-GB file for the NEXT run to sweep in.
- `SkylineNightly.zip` **661 KB**, verified runnable from the extracted zip. Its member list
  needed porting: net8 emits `<name>.dll.config` not `.exe.config`, and the `.exe` is an apphost
  that cannot start without its `.dll` / `.deps.json` / `.runtimeconfig.json`.
- `BiblioSpec.zip` **18.5 MB**. net472 could name its members; the net8 ports are
  framework-dependent (**86 assemblies for BlibBuild alone**), so the distro is now assembled
  from each tool's `.deps.json`. Two things deps.json cannot see and which stay explicit: the
  native vendor DLLs (`MassLynxRaw`, `timsdata`, `baf2sql_c`, `cdt`, `msparser`) which are
  P/Invoked by name, and the msparser schemas which moved to a `msparser-config` subdir.
  `BlibToMs2` is now a declared prerequisite (it was fetched from the C++ `obj\x64` tree).
- `pwiz/Version.cpp` is generated by the net8 build (`_GenerateVersionCpp`) from the same git
  facts as Jamroot's rule, including using the COMMIT date so the revision is reproducible.
  SkylineNightly reads `Version::Branch` out of the zip (`Nightly.cs:500`) to identify the branch.

**`global.json` moved to the repo root.** It lived at `pwiz-sharp/global.json`, and SDK
resolution walks UP - so Skyline built with **10.0.400** while pwiz-sharp was pinned to 8.0.423.
All four locations now resolve to 8.0.423.

### cpp side (C:\dev\pwiz-waters) - all verified, NONE pushed

Both branches rebased onto upstream master `012816cc5`; `parity-integration` merges them and is
what the sweeps measured. `origin` there is the **pete-reay-waters fork**, not ProteoWizard - the
rebase target came from `upstream`.

- `Skyline/work/20260813_waters_sdk_50` (2 commits) - MassLynx 4.9 to 5.0 + 31 regenerated
  reference mzMLs. `Reader_Waters_Test` exit 0.
- `Skyline/work/20260814_cpp_uninit` (3 commits) - Thermo `ScanInfoImpl` uninitialised members,
  two Agilent out-of-bounds reads. `Reader_Thermo_Test` + `Reader_Agilent_Test` pass.

Rebase conflict worth knowing: master turned `ActivationType activationType_` into
`vector<ActivationType> precursorActivationTypes_` in the same block the uninit commit rewrote.
Resolved toward master's declarations with the initialisers re-applied; resolving the other way
would have silently reverted an upstream change.

### Decisions taken

- **Agilent instrument serial number is KEPT as deliberate C#-side surplus.** cpp omits it only
  because `MidacDataImpl::getDeviceType()` hard-codes `DeviceType_Unknown`, so its `Devices.xml`
  search is for type 0 and never matches. The values are real (`SG1812C101`, `SG1928C201`).
  Recorded at the call site; costs ~6 IM files never comparing byte-identical.
- **Shimadzu ~15s `startTimeStamp` skew is ACCEPTABLE** (user call). 6 files are timestamp-only.
- Two residual Sciex diffs are **cpp bugs** deliberately not reproduced: a karma 12-digit
  rounding carry rendering `99999999.99999972` as `1.0e09`, and the 1-based/0-based `GetSample`
  off-by-one. Those files can never reach `identical` without replicating the bugs.
- **`--ignoreUnknownInstrumentError` implemented** (was parsed but never copied into
  `ReaderConfig` - dead wiring, same failure mode as `--ignoreMissingZeroSamples`). All 5 cpp
  call sites mirrored. It surfaced that **ZenoTOF 8600 System** is missing from BOTH mapping
  tables - cpp fails on that file too.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260612_net8_port.md` before starting work.

## 2026-08-18: Agilent instrument class - the SDK's one reliable answer, finally emitted

The `instrument model` cluster (12 corpus files) turned out to be **one Agilent bug, not two
vendors**. The four files bucketed as Mobilion are Agilent `.d` directories (they contain
`AcqData/`) sitting under `D:\test\Mobilion\` - the sweep buckets by parent directory, the same
trap already recorded for the `-nan` file. C#'s Mobilion reader reads `acq-ms-model` exactly as
cpp does and was never involved.

### Root cause: a different source, not a different spelling

For ion mobility `.d`, cpp goes through `MidacDataImpl::getDeviceName` (`MidacData.cpp:203`),
which **ignores its `deviceType` argument entirely** and returns `imsReader_->FileInfo->InstrumentName`
- the operator-assigned name the file carries (`IM-MS QTOF`, `Instrument 1`, `IMS 11`,
`Agilent 6545XT`, `<unknown>`). C# called the MassSpec SDK's `FileInformation.GetDeviceName(deviceType)`,
which answers with the generic device-TYPE name (`QTOF` / `IM-QTOF`). Same call shape, different API.

### The CV grew the terms this reader always needed

`psi-ms.obo` 4.1.232 carries `MS:1003761 instrument class` with 16 children, already generated
into both `CVID.generated.cs:11842+` and cpp's `cv.hpp:11930+`. Ten are new (`MS:1003762-71`);
six are pre-existing mass-analyzer terms that gained a second parent. Note `QIT` (`MS:1000082`)
and `LIT` (`MS:1000291`) are **not** instrument-class terms - both are `is_a MS:1000264 ion trap`
and nothing else, so `MS:1000264` is the class term covering them.

Until now cpp's `translateAsInstrumentModel` (`Reader_Agilent_Detail.cpp:119`) was a stub: it took
`deviceType` and returned `MS_Agilent_instrument_model` unconditionally, discarding it. So the SDK's
one reliable answer was thrown away while the unreliable free-text name was what got emitted.

### Both params now sit alongside each other (user call)

cpp branch `Skyline/work/20260818_agilent_instrument_class` off `upstream/master 012816cc5`
(NOT off parity-integration - see the build trap below). New
`translateAsInstrumentClass(DeviceType, bool hasIonMobilityData)`; ion mobility wins over the
device type and is the only route to `Q-IMS-TOF`, since MIDAC reports `DeviceType_Unknown`.
C# mirrors it, and `GetDeviceName` now reads `FileInfo.InstrumentName` on the IM path. The
userParam is also now emitted **unconditionally**, as cpp does - the old non-empty guard was a
C#-side divergence.

Assignments across the 22 reference fixtures: 13 Q-IMS-TOF, 8 triple quadrupole, 1 time-of-flight.
`GFb_4Scan_TimeSegs_1530_100ng-combineIMS-*` correctly stays triple quadrupole - `combineIMS` is a
config, `hasIonMobilityData()` is a property of the file.

### Do NOT regenerate the Agilent references with `--generate-mzML`

It passes, and it silently rewrites far more than the change:
- every `sourceFile location` from the committed `C:/pwiz.git/pwiz/...` to the local checkout path;
- `cv` versions MS 4.1.197 -> 4.1.232 and UO `09:04:2014` -> `releases/2026-01-16` (22 files);
- **135 binary arrays in `RS080806_NL_448.2_001.mzML` flipped 64-bit float -> 32-bit float** -
  unrelated drift the committed reference predates.

The references are written **unindexed** (`VendorReaderTestHarness.cpp:778` sets
`writeConfig.indexed = false`) and carry no `fileChecksum`, so a surgical one-line insert is safe.
That is what landed **in the cpp checkout only**: 22 files, **22 insertions, 0 deletions**,
`Reader_Agilent_Test` green. The harvested cvParam line per file came from a throwaway
`--generate-mzML` run that was then reverted. The net8 branch touches **no** `pwiz/` path -
see the trigger analysis in the 2026-08-18b entry for why that matters, and why the C# tests
do not need it.

### The harness cannot see userParams at all

Removing the `GetDeviceName` fix and re-running left **all 13 Agilent tests passing**. The
reference diff ignores userParams entirely, so the reader read the device name from the wrong SDK
through every green run of the suite. New `AgilentInstrumentMetadataTests` closes it: the mapping
table, plus the CommonInstrumentParams block for one IM and one non-IM fixture. Negative control
confirmed - reverting the fix fails with `Expected:<IM-MS QTOF>. Actual:<IM-QTOF>`, exactly the
corpus diff. Agilent 15/15; Sciex 8, Shimadzu 2, Thermo 15, Mobilion 2, Common 58 all still green.

### Status and the surplus this creates

Until the cpp change ships upstream and `G:\parity\msconvert-cpp-snapshot` is rebuilt, **every
Agilent file in the corpus carries a C#-side surplus cvParam** - recorded in the standing table
above. The next default sweep will show it; that is expected, not a regression.

**cpp build trap**: `msconvert.exe` built on a branch off `upstream/master` against a
`build-nt-x86` tree previously built from `parity-integration` dies at startup with
`0xC0000139 STATUS_ENTRYPOINT_NOT_FOUND` - stale DLL exports, not a code fault. A cross-binary
corpus check needs a clean rebuild of that tree first. Verification here instead came from the
cpp-generated references (which C# is diffed against) plus a direct msconvert-sharp emission
showing `MS:1003767` + `instrument model = IM-MS QTOF`.

## 2026-08-18b: CI triggers, a second harness blind spot, and four review fixes

### What a changed path actually triggers (measured, not guessed)

`scripts/misc/smartBuildTrigger.py` uses `re.match`, first-match-wins, and has **no catch-all** -
an unmatched path triggers nothing. Resolving the real config with its own `merge()` and the
master-branch promotion step:

| path | pattern | fires |
| --- | --- | --- |
| `global.json` | *(no match)* | **nothing** |
| `pwiz/**` (incl. reference mzMLs) | `pwiz/.*` | **bt209** - the old cpp/MSVC Skyline build |
| `pwiz-sharp/**` | `pwiz-sharp/.*` | CoreWindowsNet + CoreLinuxNet |
| `pwiz_tools/Skyline/**` | `pwiz_tools/Skyline/.*` | SkylineWindowsNet |

So **moving `global.json` to the repo root does not trigger a cpp build** - but it now matches no
pattern at all, so a change to the SDK pin triggers **no CI whatsoever** (under `pwiz-sharp/` it
used to fire CoreNet). Worth a `("global.json", targets['CoreNet'])` entry before the merge.

The cpp Core/Linux/Bumbershoot/Container targets are commented out for the duration of the port,
but `SkylineWithTestConnected` still carries a live `bt209`, which is what `pwiz/.*` reaches.
**Anything under `pwiz/` on this branch triggers a C++ build**; keep cpp work in the cpp checkout.

### The C# harness ignores the whole paramGroup, not just userParams

Deleting the 22 reference edits from the net8 checkout and re-running left Agilent **15/15**
green. `Diff.cs` has no `ParamGroups` handling at all, so the C# vendor harness cannot see the
instrument class cvParam, the instrument serial number, or the instrument model userParam -
everything in `CommonInstrumentParams`. cpp's `Diff` *does* compare it, which is why the cpp test
failed and the C# one never would have. Two consequences:

- the reference-mzML edits belong **only** in the cpp checkout (and would have tripped bt209 here);
- `AgilentInstrumentMetadataTests` is the only thing covering any of it on the C# side.

### Review fixes (all verified, not just applied)

1. **`ReaderConfig.UnknownInstrumentIsError` defaulted `true`; cpp defaults it FALSE**
   (`Reader.cpp:47`). Only msconvert tightens it, by negating its own flag
   (`msconvert.cpp:507-508`, already mirrored in `Converter.cs:471`). Every other consumer -
   Skyline, the hosted C API - was getting a hard `IOException` on vendor files cpp and net472
   open with a warning. Now defaults false; `ReaderConfigDefaultsTests` pins both directions.
2. **`RuntimeClosureFromDeps` skipped `runtimeTargets`**, so BiblioSpec.zip shipped without
   `SQLite.Interop.dll` - BlibBuild cannot write a `.blib` without it. Now included, filtered to
   Windows RIDs (the section lists every platform; taking bare names would have asked for
   `libhdf5.so`). Verified: **106 -> 110 entries, 17.7 -> 22.0 MB**, all four natives present,
   no `.so`/`.dylib` leakage.
3. **`--no-restore` on never-restored projects.** SkylineTester is not in `BUILD_TARGET`, so the
   restore loop skipped it; `_StageDistroZipPrereqs` likewise ran `Targets="Build"` with no
   restore. Reproduced live as NETSDK1005. Both fixed - and the prereq restore needs
   `RemoveProperties="TargetFramework"`, because build.bat drives this with `-f net8.0-windows`
   and that global would otherwise restore the wrong TFM (the first attempt at the fix did
   exactly that).
4. **Detached HEAD.** `git rev-parse --abbrev-ref HEAD` prints the literal `HEAD` on the commit
   checkouts CI uses. Confirmed in a throwaway detached worktree; `git name-rev` returns the real
   branch there. Fixed with a name-rev fallback plus a build warning if both fail.

Also removed a stale duplicate REM block in `build.bat` that claimed the zip work lived in
"targets named after the artifacts", which MSB5016 makes impossible.

### Version.cpp retired in favour of assembly metadata (user call)

The net8 build was synthesising a **C++ source file** purely to carry one string for
SkylineNightly. It now stamps the same git facts into SkylineTester's own assembly:

- `SkylineTester.csproj` gains `GenerateAssemblyInfo=true` (it had none - the assembly stamped
  `0.0.0.0`; note `pwiz.Common.dll` already stamped `1.0.0+<sha>`, so the SDK machinery was
  there, this project had just opted out) and a `_StampBuildVersion` target setting
  `Version`/`FileVersion` to the same `3.0.<yyddd>` revision Jamroot's rule produces, and
  `InformationalVersion` to `<version>+<sha>.branch.<branch>`.
- `IncludeSourceRevisionInInformationalVersion=false` so the SDK does not append a second `+sha`.
- `Nightly.cs` reads it via `FileVersionInfo.ProductVersion` on `SkylineTester Files\SkylineTester.dll`
  - no assembly load, so the reader does not need to match the build's framework. The delimiter is
  `.branch.` because a branch name contains `/` and cannot be the last dot-separated token.
- `pwiz\Version.cpp` is no longer generated and no longer a zip member.

Verified end to end: `SkylineTester.zip` still **313.6 MB / 1927 entries**, contains no
`Version.cpp`, and SkylineNightly's exact read path recovers
`Skyline/work/20260612_net8_port` from the assembly inside the zip.

### tcbuild.bat now always builds the distro zips

It never requested any - it forwards `%*` to `build.bat` and passed nothing of its own, so a
standard `tcbuild.bat Release --automated` produced **zero** zips. The Jamfile rule it replaced
(`Jamfile.jam:361-381`) produced three unconditionally, so tcbuild now appends
`SkylineTester.zip SkylineNightly.zip BiblioSpec.zip` (user call: always on, not behind a flag).

Two properties that make this safe: the zips land in `bin/staging-net8/<Config>`, which is
gitignored, so the `git status --porcelain` hygiene gate stays clean; and the zips block ends at
`build.bat:212` while `TestRunner.exe` runs at `:283`, so TC gets its artifacts even from a build
whose tests failed. Verified the forwarded arg string parses by appending a bogus trailing
argument - only that one was rejected, at parse time, with nothing built.

**Cost**: `SkylineTester.zip` is 313.6 MB and takes minutes to assemble, on every per-commit run.
**Still to do on the TC side**: artifact paths must point at `bin/staging-net8/<Config>/*.zip`.

### Test state

pwiz-sharp: Agilent 15, Sciex 8, Shimadzu 2, Thermo 15, Mobilion 2, Bruker 14, Common 58,
MsData 81, Waters 21 - all green. cpp `Reader_Agilent_Test` green in the cpp checkout.

## 2026-08-19/20: both sweeps re-run, and three fixes the sweeps could not see

### Sweep results

Both sweeps from the 08-17/18 entry were re-run against refreshed snapshots
(`G:\parity\msconvert-snapshot` 08-19, `msconvert-cpp-snapshot` 08-18).

| sweep | identical | differs | cs-failed | cpp-failed | both-failed |
| --- | --- | --- | --- | --- | --- |
| default, 08-14 (baseline) | 383 | 39 | 1 | 33 | 34 |
| default, 08-18 | **399** | 23 | 1 | 19 | 48 |
| peakPicking, 08-17 | 274 | 108 | 29 | 19 | 60 |
| peakPicking, 08-19 | **379** | 28 | 3 | 19 | 61 |

`G:\parity\results-20260818-default.jsonl`, `G:\parity\results-20260819-peakpicking.jsonl`.

**Default: +16 identical, every one of them `differs -> identical`** - Agilent 6, Sciex 6,
Mobilion 4. That is the four vendor parity fixes plus the Sciex `hasHalfSizeRTWindow`
regression fix, measured for the first time; the 08-17 default run was stopped at 246/492
and never saw them.

**The other 14-file move is parity gained, not lost.** `cpp-failed` fell 33 -> 19 while
`both-failed` rose 34 -> 48, and all 14 are C# now refusing a file cpp already refused.
Before, C# silently converted `OnyxTOFMS.wiff2`, `250814_ZTScan_100spd_A_3_G1.wiff2` and
nine Shimadzu `.lcd` files that cpp aborts on with "unable to determine instrument model"
/ "unable to parse instrument model". That is `UnknownInstrumentIsError` reaching the
readers, so `both-failed` is the correct destination and the bucket name reads worse than
the result is.

**peakPicking: +105 identical**, from the vendor-fallback fix (`6634981b45`). 91 moved
`differs -> identical` and 14 `cs-failed -> identical`: Sciex 55, Agilent 39, Waters 8,
Mobilion 3. `cs-failed` 29 -> 3. A further 12 moved `cs-failed -> differs` - files that
now convert but do not yet match - which is why `differs` did not fall as far as
`cs-failed` did.

Remaining default `differs` (23): Shimadzu 10, Agilent 9, Thermo 2, Bruker 1, Sciex 1;
164 `cvParam value differs`, 17 `cvParam extra in C#`, 12 binary values, 10
`run/@startTimeStamp`. Remaining peakPicking `differs` (28) add Mobilion 4 and Waters 1
and are a different family: 577 `spectrum/@defaultArrayLength` and 56
`child count (spectrum)` dominate, so the peakPicking remainder is a spectrum-count and
array-length problem, not the metadata problem the default remainder is.

The three peakPicking `cs-failed` that remain:

- `ABI\no-spectra\2020-06-09 BAK 270 optimization.wiff` - `Idx - could not be found`
  (`STG_E_FILENOTFOUND`). Also the default sweep's only `cs-failed`, where C# writes 4 of
  the 10 runs cpp writes and then aborts.
- `Thermo\20May24_P3_LHS_line_003.raw` - NullReferenceException, with msconvert
  suggesting `--continueOnError`.
- `Waters\T0016P01_Gly_11122019_1.raw` - throws inside `Converter.WriteOutput`.

### build.bat was parking MSBuild nodes that later builds mis-evaluated (`979660e18c`)

The native Hardklor step runs Visual Studio's `MSBuild.exe`; every .NET project after it
is built by the SDK's own MSBuild. With node reuse on, the first step parks worker
processes the later `dotnet` builds connect to, and a node from one MSBuild version
evaluating a project for another mis-evaluates items: the SDK's default `**/*.resx` glob
reaches `GenerateResource` unexpanded and `Skyline.csproj` dies with MSB3552, **but only
when built as a project reference**.

The symptom is worth recording because every obvious isolation test says the opposite.
It failed inside the script every time, at TestRunner - the last project, and the one
whose reference to Skyline triggers the rebuild - while building that same project
standalone passed, and building all seven by hand in the same order with the same
arguments also passed, because that sequence has no Hardklor step. Standalone runs fail
only when a stale node happens to be alive. **The nodes outlive the build**: one on this
machine was 6.9 days old, so a CI agent accumulates them across runs and sees
intermittent MSB3552. Verified by running the full suite with `MSBUILDDISABLENODEREUSE`
unset, so the flag alone was doing the work.

### SkylineCmd could not load Skyline at all on net8 (`fb541bf0c3`)

`SkylineCmd.exe` failed on **every** invocation, not just under test: even `--version`
died with "Could not load file or assembly 'Skyline-daily'" while `Skyline-daily.dll` sat
in the same directory. `TestCmdLineAssociateProteins` and the four `Console*`
command-line tests were reporting a broken CLI, not a broken feature.

The port had corrected the file NAME - the `.exe` is an apphost, so it loads
`Skyline-daily.dll` - but kept `Assembly.Load(AssemblyName)`, whose own comment states
the assumption it inherited: "probing finds the .exe next to this one". .NET does not
probe the application directory. It resolves through the RUNNING app's `deps.json`, and
Skyline is deliberately not a dependency of SkylineCmd; it is discovered at run time. So
the name-based load could never have succeeded.

Fixing that exposed the same problem one level down: `Skyline-daily` loaded and then
failed on `pwiz.PortableUtil`, because loading an assembly by path does not bring its
dependency graph with it. `AssemblyDependencyResolver` reads `Skyline-daily.deps.json`,
the only thing that knows that graph, and feeds `AssemblyLoadContext.Default.Resolving`.
Loading into the DEFAULT context keeps everything in one context - what net472 got from
probing, without the mark-of-the-web refusal that ruled out `LoadFrom` there. net472 is
untouched. `TestCmdLineAssociateProteins`, `ConsoleBadRawFileImportTest`,
`ConsoleImportNonSRMFile`, `ConsoleMultiReplicateImportTest` and `TestCommandLineNoJoin`
now pass in English and French.

### The net8 output directory was not self-contained: no VC++ runtime (`843bb777ec`)

The vendor readers are native and P/Invoked by name, and they import the VC++
redistributable: `MassLynxRaw`, `hdf5` and `MascotShim` all need `msvcp140`,
`vcruntime140` and `vcruntime140_1`. `Jamroot.jam` has always handed the C++ build the
same set as `.msvcrt-x64` `<assembly-dependency>` entries; the net8 build had no
equivalent, so its output was only self-contained on a machine that happened to have the
redistributable installed.

The parallel test workers are exactly such a machine: they run Skyline straight out of
the bind-mounted host tree inside a Windows container with no redistributable, which is
why every Waters, mzMLb and Mascot test failed there while passing on the host - **23 of
the 24 failures in the last full-suite run**. The error is `ERROR_MOD_NOT_FOUND` (126),
which names neither the missing dependency nor the DLL that wanted it, so it reads as the
vendor DLL being absent when it is present and its dependency is not. Same class as the
Agilent `BaseTof.dll` finding, now generalised.

`VendorNativeCrt.targets` carries the same 50 files as Jamroot's `.msvcrt-x64` and is
imported by Skyline and by msconvert, which needs them for the same reason. It lives next
to the DLLs it copies so it self-locates and importers need no root property. **Keep it in
sync with `Jamroot.jam`.** Verified by loading all three DLLs inside a container with the
same bind mount: `ERROR_MOD_NOT_FOUND` before, `err=0` after. The check must use
`LOAD_WITH_ALTERED_SEARCH_PATH` - a plain `LoadLibrary` resolves dependencies against the
CALLING process's directory, not the DLL's, so it fails even when the CRT is staged
correctly.

### Still open

- **`TestAiFolderIsSubmodule` is the one red test in the local pass0 run** (08-20,
  `ai/.tmp/pass0-repro.log`, one failure across 623 tests). `C:\dev\pwiz-net8\ai` exists
  but holds only `.tmp\`, and `AiFolderTest` fails any `ai` folder without a `.git` inside
  it. `ai` is not in `.gitmodules` - it is a nested clone - so this is worktree setup, not
  product. Clone `ai` into the net8 worktree or move the scratch folder.
- **`global.json` still triggers no CI.** It matches no pattern in
  `scripts/misc/vcs_trigger_and_paths_config.py`, so a change to the SDK pin builds
  nothing. Add `("global.json", targets['CoreNet'])` before the `pwiz-sharp/.*` entry
  (line 131).
- **`MsData.Tests` cannot build** - pre-existing CA2022/CA2263 analyzer errors in three
  untouched test files. Still blocking the natural regression suite for shared-writer
  changes.
- **Instrument-model translation**: Agilent landed in the 08-18 entry; Mobilion
  (`Agilent 6545` -> `QTOF`) is still unowned.
- **TeamCity artifact paths** must point at `bin/staging-net8/<Config>/*.zip`.
- **The cpp branches in `C:\dev\pwiz-waters`** still have no decision on how they go up.

## 2026-08-20b: the container-only graph/UI cluster root-caused - the DockPanel never fills

### The cluster is 11 tests, container-only, and it is not new

The full-suite run at `843bb777ec` had 11 English failures, all of them on parallel
clients 0/1/2 - **none on the host worker**. TeamCity `ProteoWizard_SkylineWindowsNet`
build #143 on that same commit is **1755/1755 green**, because CI runs sequentially and
never enters a container. The same 11 were already listed on 2026-07-08 as "Graph/UI that
differ in container" and never root-caused; today's list is that list, minus
`TestCommandLineNoJoin` (fixed by the SkylineCmd loader change `fb541bf0c3`) plus
`TestSmallMolMethodDevCEOptTutorial`.

**They are not a parallel-contention artifact.** `TestSplitGraph` and `TestArrangeGraphs`
fail identically in a **standalone** container with no other workers running:

```
docker run --rm -m 4g -v "%USERPROFILE%\Downloads":c:\downloads -v "C:\dev\pwiz-net8":c:\pwiz ^
  chambm/always_up_runner ^
  "c:\pwiz\...\staging-net8\Release\dotnet\dotnet.exe c:\pwiz\...\staging-net8\Release\TestRunner.dll ^
   test=TestSplitGraph parallelmode=off loop=1 language=en offscreen=on log=c:\pwiz\TestRunner-probe.log"
```

Note the harness passes the command as a single quoted argument to the image's entrypoint,
which hands it to AlwaysUp's `InstallService`; **the executable needs a full path**
(a bare `powershell` gives "Unable to access executable/application").

### What actually differs, measured

Instrumenting `SplitGraphTest` to dump geometry at the failing assert:

| | container | host |
| --- | --- | --- |
| screen | 1024x768 | 2560x1440 |
| SkylineWindow bounds | 742x541 | 872x632 |
| **ClientSize** | 856x593 | 856x593 |
| **DockPanel size** | **233x123** | **859x520** |
| DockLeft / DockRight pane | 54x123 | 210x520 |
| Document pane (GraphChromatogram) | 115x100 | 429x494 |
| ZedGraph chart rect | **-5.3 x -145.5** | 325.7 x 271.5 |
| XAxis Scale.Max / MajorStep | **50 / 50** | 35 / 5 |

The assertion `Assert.AreEqual(...XAxis.Scale.Max, 35.0, 1.0)` fails as "expected 50, actual
35" because the chart rect is degenerate, so ZedGraph picks a single 50-unit step.

**Two independent differences, and only the second one matters.**

1. **No theme in the container session.** `SystemFonts.MessageBoxFont` is
   `Microsoft Sans Serif 8.25` there vs `Segoe UI 9` on the host (`SystemFonts.DefaultFont`,
   installed fonts, `Graphics.MeasureString` and DPI are all identical - fonts are NOT
   missing). `SkylineWindow` is `AutoScaleMode.Font` with `AutoScaleDimensions = 7,15`, so
   the container scales the whole form down: 742x541 instead of 872x632.
   Pinning `Application.SetDefaultFont(new Font("Segoe UI", 9f))` in `Program.Init()` makes
   the container's window 864x620 and its **ClientSize exactly equal to the host's**.
   It does **not** fix any of the tests.

2. **The DockPanel never gets sized to fill its parent.** `panel1` is `Dock=Fill` and is
   correctly 856x519 in both. The `dockPanel` inside it is anchored
   `Top, Bottom, Left, Right` at `Location (-1,0)` with `Size 736x444` **from
   `Skyline.resx`** (`resources.ApplyResources(this.dockPanel, "dockPanel")`,
   `Skyline.Designer.cs:183`). On the host it ends up 859x520. In the container it sits at
   **233x123 = `Control`'s default 200x100, font-scaled** - i.e. `ApplyResources` set
   `Anchor` and `Location` (both verified correct at runtime) but the control never took the
   736x444 `Size`, so its anchor deltas are computed from 200x100 and it can never grow.

**Nothing re-triggers the layout.** `SkylineWindow.PerformLayout()`, `panel1.PerformLayout()`,
`dockPanel.ResumeLayout(true)` and a +1px/-1px form resize nudge all leave it at 233x123.

**Forcing the size fixes the test outright.** In the container:

```
SkylineWindow.DockPanel.Size = SkylineWindow.DockPanel.Parent.ClientSize;
SkylineWindow.DockPanel.PerformLayout();
```
gives `graphFormBounds 426x496`, `chartRect 322x273`, **`xMax = 35`** - matching the host's
429x494 / 326x271 / 35. That is the whole cluster in one line.

### The one open link

Why `ApplyResources` applies `Anchor` and `Location` but not `Size`, **deterministically per
environment** (container fails 100%, host passes 100%), is not yet explained. It is not a
resource-loading failure: a direct
`new ComponentResourceManager(typeof(SkylineWindow)).GetObject("dockPanel.Size")` returns
`736x444` **inside the container**, with `uiCulture=en-US`, `culture=en-US`,
`invariantMode=False`. So the value is present and readable; it just does not reach the
control. Next probe: log `dockPanel.Size` immediately after `InitializeComponent()` in both
environments to find whether it is never set or set and then reset.

### Fix options (not yet chosen)

- **Size the dock panel explicitly** at startup (`dockPanel.Size = panel1.ClientSize`, or
  switch it from `Anchor` to `Dock=Fill`). Verified to fix the symptom; `Dock=Fill` is what
  the anchor is emulating anyway and would remove the dependency on `ApplyResources` order.
- **Pin the WinForms default font** for determinism (`Application.SetDefaultFont`). Makes
  host and container agree on window/client size; on the host it is a no-op (already
  Segoe UI 9). Not sufficient alone. net8-only API - needs `#if !NET472`.
- **Exclude the 11 with `[NoParallelTesting]`.** Lowest effort, loses container coverage,
  and leaves a real layout bug in the product.

### Also settled today

- **`TestAiFolderIsSubmodule` was already fixed and the handoff was stale.**
  `C:\dev\pwiz-net8\ai` is a **junction to `C:\dev\pwiz-ai`** created at **10:29:34 on
  08-20** - one minute after the handoff that describes it as broken was written. The
  junction target has a `.git`, so the test passes now. It is not a stub holding only `.tmp`.
- **The junction is invisible inside the containers.** `-v "C:\dev\pwiz-net8":c:\pwiz` cannot
  follow a junction whose target is outside the mount, so `c:\pwiz\ai` does not resolve.
  Anything staged under `ai/` is unreachable from a worker - put container-visible scratch
  files elsewhere in the tree.

## Standing record: cpp-side defects we deliberately do not reproduce

The mirror of the C#-surplus record above. When cpp emits something C# does not, the default
reading is a porting gap - and it usually is. The exception is a cpp output that is demonstrably
wrong AND that cpp itself contradicts depending on how it is invoked. Reproducing those would
mean porting a defect to turn a corpus cell green, which is the wrong trade: the sweep exists to
find real differences, not to make the numbers agree.

**Do not chase anything in this list.** These inputs will read `differs` until the cpp fix ships,
and that is the expected state, not a regression. Anything added here needs the same standard of
evidence as the entry below: the full extent measured with the diff budget lifted, and a
demonstration that cpp disagrees with itself.

### IMS vendor-fallback emits a fabricated leading zero sample (2026-08-20)

Under `--filter "peakPicking vendor ..."`, Agilent and Mobilion ion-mobility data make cpp emit
one extra **zero-intensity** point at the FRONT of every spectrum that has a leading zero to pad.
It is the entire remaining difference on those files.

| input | reader | spectra | cpp has 1 extra leading zero | identical |
| --- | --- | ---: | ---: | ---: |
| `ImsSynthCCS.d` | Agilent | 701 | **701** | 0 |
| `...NISTmAbOxidized[DC5].d` | Mobilion | 237,206 | **237,202** | 4 |

Nothing else differs in the binary data - not one value, not one m/z. The only other diff on the
Agilent file is the `MS:1000529 instrument serial number` cvParam already recorded above as a
deliberate C# surplus.

**Why this is cpp's defect and not our gap.** The extra sample is synthesized by
`ZeroSampleFiller`'s left-padding: on `ImsSynthCCS.d` it lands at m/z 174.0201, one sample step
BELOW the file's own observed minimum of 174.02766, carrying intensity 0. cpp is reporting a data
point that does not exist in the acquisition and that falls outside the m/z range cpp itself
declares. Decisively, **cpp only does this on one of its two peak-picking paths**:

| filter | cpp | C# |
| --- | ---: | ---: |
| `peakPicking false 1-` | 66 | 66 - byte-identical |
| `peakPicking vendor msLevel=1-` | **67** | 66 |

Same file, same spectrum, same detector. cpp agrees with us exactly when the vendor attempt is
skipped, and gains a fabricated point when it is attempted and declined (Agilent and Mobilion IMS
cannot vendor-centroid; cpp prints its own "falling back to local maximum peak picker" warning).
A tool that contradicts itself between two spellings of the same request is not stating a
convention.

**Everything shared was cleared by measurement first**, so this is not a shortcut around an
unfound bug:

| suspect | verdict | how |
| --- | --- | --- |
| `ZeroSampleFiller` | exonerated | cpp's own 7 oracle vectors ported to `ZeroSampleFiller_FillsInteriorGapsAndTermini`; all pass |
| backward-pass `oob` (`y.size()` vs grown `yFilled.Count`) | irrelevant | a faithful transcription of cpp's source, run on the real spectrum under BOTH semantics, gives 66 either way |
| `LocalMaximumPeakDetector` | exonerated | same window (`LocalMaximumPeakDetector(3)`); sources byte-identical between checkouts |
| `TrimProfileZeros` | exonerated | raw unpicked arrays identical - n=71, same leading zero, same m/z |

Note the transcription of cpp's source produces **66**, matching C#. The C# port implements the
documented algorithm correctly; it is the cpp binary that departs from it.

**Decision (user, 2026-08-20): keep C# as-is and fix cpp.** The cpp branches are in
`C:\dev\pwiz-waters` (`origin` there is the pete-reay-waters fork - use `upstream`). Until that
ships, ~10 corpus inputs stay in `differs` on the peakPicking sweep for this reason alone: 7
Agilent (`ImsSynthCCS/AllIons/Chrom.d`, `mulATM4.d`, `mulATM4.d.DeMP.d`, `Test_BsaFromUimf.d`,
`Dorrestein_...Min20_1.d`) and 3 Mobilion. The two Agilent files WITHOUT the +1
(`20fmolBSA-centroid.d`, `Neg_MS_002.d`) are the non-IMS ones and are unrelated.

**The sweep understates this by two orders of magnitude.** `mzml_compare.compare()` takes
`budget=80` and `break`s out of the comparison loop on reaching it, and `run_parity2.py:153`
stores only `diffs[:60]` - so the `diff list truncated` marker, which lands at index 80, is never
written to the jsonl and a truncated file is indistinguishable from a fully compared one. For
`ImsSynthCCS.d` the sweep recorded `spectra=75` against an actual 701; for the Mobilion file, ~76
against 237,206. **15 of 28** peakPicking `differs` files hit the budget (all 8 Agilent, all 4
Mobilion, plus Bruker, Shimadzu and Waters), as do 3 of 23 on the default sweep. Every
"remaining differs" count for those vendors is a floor from a partial comparison, and the
per-category totals in earlier entries are sums over truncated lists.

**Fixed 2026-08-20 in `mzml_compare.py` + `run_parity2.py`.** The cap conflated "how much to
compare" with "how much to record". `compare()` now always scans the whole file and separates the
two: `stats["categories"]` carries the TRUE count per category, and the returned list keeps only
the first `examples_per_category` (3) of each. `budget` is still accepted, because several scripts
pass it, but now caps only the retained examples and never the scan. Also added
`records_compared`, `records_truncated` and `diff_total`, and removed `MAX_BINARY_REPORT`, whose
stripping is what made `binary_diffs: 1402` print alongside 4 reported binary diffs.
`run_parity2.py` stores the example list whole and takes `diff_count` from `diff_total`.

Measured on the same pair: `ImsSynthCCS.d` now reports `spectra=701` (was 75) and
`diff_total=2104` (was 81) from **7** retained examples; the Mobilion `[DC5].d` reports 237,206
spectra and 711,606 diffs from **6** examples. Self-comparison is clean (0 diffs, 710 records) and
`test_mzml_compare_nan.py` still passes 11/11. **Cost**: a full scan of that 1.6 GB pair takes
90 s. Only `differs` files pay it - an identical file never reached the old budget, so it was
always scanned in full.

Numbers in entries ABOVE this line predate the fix and remain floors; do not compare them
directly against post-fix sweeps.

### The fix: dockPanel.Dock = Fill (uncommitted, under review)

`Dock=Fill`, set **in code** in `Skyline.Designer.cs` after `ApplyResources`, with
`dockPanel.Anchor` / `.Location` / `.Size` removed from all three `Skyline[.<lang>].resx`.

**The conservative variant does not work, and that corrects the 08-20b diagnosis.** Keeping the
four-sided anchor and setting `Anchor`/`Location`/`Size` explicitly in code (so nothing depends
on `ApplyResources`) put every container failure straight back. So the size is **not** "never
applied" - it is applied and then reset by something later. `Dock=Fill` survives that because it
re-establishes the size on every layout pass; an explicit size does not. What resets it is still
unidentified, and is now the only open thread here.

**`Dock=Fill` caused exactly one regression, on the HOST.** `ArrangeGraphsTest` normalizes the
graph area to 736x443 (`ArrangeGraphsTest.cs:56-57`, *"so dimensions get set the same each run"*)
by assigning `Parent.Parent.Parent.Width/Height` - a no-op on a `Dock=Fill` control. It kept
passing in the container only by coincidence: the unthemed container font happens to make the
filled panel ~736x444 there. Replaced with a `SetGraphAreaSize` helper that resizes
`SkylineWindow` by the difference, which is deterministic in both environments.

**Two real product/test bugs fell out, both pre-existing:**

- `ComparePeakPickingDlg.zedGraphFiles_Resize` dereferenced `_axisLabelScaler`, which is
  constructed on the line *after* `InitializeComponent()` - and Resize fires from inside it.
  Identical NRE stack before and after the layout change; it only became reachable in passing
  once the panes actually resized. Null-guarded. Took `TestPeakBoundaryCompare` 385s -> 13s.
- `UnifiFunctionalTest` shares one `DoTest` between `TestUnifi` (a `UnifiAccount`, line 67) and
  `TestWatersConnect` (line 84), but lines 127-131 did `(_testAccount as WatersConnectAccount)!`
  unconditionally - the `!` silences the compiler, `as` yields null, NRE. The client
  id/secret/scope checks are waters_connect-only; guarded with `is WatersConnectAccount`.

### Verification

| run | result |
| --- | --- |
| the 11, standalone container | **11/11 pass** |
| the 11, host | **11/11 pass** |
| full suite via `build.bat --parallel` (4 workers) | **1 failure: `TestUnifi`** |
| pass0 build check (French) | **0 failures** (was 8) |
| import ja/zh, pass1 subset | 0 failures |

All 11 also pass inside the full parallel run, i.e. on the Docker workers. **pass0's 8 failures
are gone too** - both the `TestAiFolderIsSubmodule` environmental and the 7-test
`Site20_Study9p.skyd` pooled-stream cascade the previous handoff attributed to unproven
cross-phase state.

**Watch the exit code, not the notification.** `build.bat` correctly exited **1**; a trailing
`; echo $?` in the wrapper masked it as 0. The script does print
`##teamcity[message ... 'TestRunner reported failures in: full-suite' status='ERROR']`, and each
phase logs its own `if N NEQ 0 (set TESTS_FAILED=1 ...)` line - that per-phase flag is the
reliable way to attribute a failure to a phase.

`TestUnifi` is **not** a regression: it was **skipped** in the pre-fix run (0 sec, no FAILED
marker) and actually ran this time (9 sec), which is how the latent cast NRE surfaced. With the
guard it gets much further and then times out after 360s in `WaitForConditionUI` on
`OpenDataSourceDialog`, waiting for a remote directory listing - it needs a live, populated UNIFI
server, so it cannot be driven green here. It is a `TestConnected` test and runs in its own CI
configuration (`ProteoWizard_SkylineMasterAndPRsTestConnectedTests`), not the net8 per-commit gate.

Changed files (uncommitted): `Skyline.Designer.cs`, `Skyline{,.ja,.zh-Hans}.resx`,
`TestFunctional/ArrangeGraphsTest.cs`, `EditUI/ComparePeakPickingDlg.cs`,
`TestConnected/UnifiFunctionalTest.cs`.

## 2026-08-21/24: the centroid msLevel gate, and the last two cs-failed

Six msconvert-sharp fixes, all measured against the cpp corpus. Four came out of the
first sweep run with the fixed comparator; two came out of chasing the remaining
`cs-failed` into the vendor SDKs.

### One root cause, three symptoms: the vendor centroid path had no MS-level gate

cpp gates centroiding INSIDE each reader - `doCentroid = msLevelsToCentroid.contains(msLevel)`
(`SpectrumList_Waters.cpp:219`, `_Agilent.cpp:313`, `_ABI.cpp:157`, `_Shimadzu.cpp:123`,
`_Thermo.cpp:365`, `_Bruker.cpp:426`). C# centroided FIRST and checked the level after:

```csharp
var spec = _vendorCentroidPath(index, getBinaryData);   // centroids
int msLevel = spec.Params.CvParamValueOrDefault(CVID.MS_ms_level, 0);
if (!_msLevels.Contains(msLevel)) return spec;          // gate - too late
```

The gate cannot live at that call site: a spectrum's MS level is only known by reading it,
and by then the vendor centroid has been applied. Three consequences, all live:

| symptom | file | effect |
| --- | --- | --- |
| non-MS spectra centroided to nothing | Waters `QCsynapt_#021_040319_A1Dnp_01.raw` | 834/1000 spectra emitted with `defaultArrayLength=0`, labelled `centroid spectrum`, where cpp emits 311 profile points |
| conversion aborted outright | Waters `T0016P01_Gly_11122019_1.raw` | `cs-failed` - listed as an unexplained crash "inside `Converter.WriteOutput`" |
| contradictory spectrum type | Shimadzu `MIDAZOLAM STANDARD_009.lcd` | every spectrum tagged BOTH `profile spectrum` and `centroid spectrum` |

The Waters spectra are DiodeArray/UV traces (`electromagnetic radiation spectrum`, no MS
level): MassLynx cannot centroid an absorbance-vs-wavelength trace and returns nothing.
The Shimadzu spectra report `ms level = 0` on both sides - it is what the file says.

**The Shimadzu case is a mislabel, not a surplus.** The data is unambiguously centroid: zero
zero-intensity points in 1995, irregular m/z gaps, arrays byte-identical to cpp's. Readers
set both terms ON PURPOSE (`SpectrumList_Shimadzu`, mirroring cpp `:217`+`:244`) to tell the
picker the source was profile; the picker owns stripping the contradiction, and its cleanup
sat after the early return. `cvParam extra in C#` disguised it, because the comparator
matches by accession and `MS:1000128` simply has no cpp counterpart - do not read that
category as "additive" without checking whether the OTHER term is also present.

**Fix**: `IVendorCentroidingSpectrumList.GetCentroidSpectrum` now takes an `IntegerSet
msLevelsToCentroid` and every reader gates internally where cpp does. Placement is
load-bearing in two of them: Waters promotes MSe survey scans to level 2 and Agilent
promotes on collision energy, both BEFORE cpp's gate, so gating at the entry point would
test the pre-promotion level and diverge on exactly the affected files. Also closes an
unreported case: `msLevel=2-` would have vendor-centroided MS1 spectra before gating.

### Zero-length binaryDataArrayList: the shape the 08-17/18 handoff said to look for

Three readers guarded `SetMZIntensityArrays` on a non-zero peak count, so a zero-point
spectrum lost its `<binaryDataArrayList>` entirely: `SpectrumList_Agilent.cs` (non-IM path),
`Baf2SqlData.cs`, `TsfData.cs`. cpp calls it unconditionally inside `DetailLevel_FullData`
and then fills the vectors (`_Agilent.cpp:416`, `_Bruker.cpp:428`). All three trace to the
bulk port commit `5369889358`, not to any later deliberate fix. Bruker
`0.1HCOOH_H20_NoTIMS_Pos.d` was 1,160 `child count (spectrum)` diffs - one per spectrum.

### The last two cs-failed were NOT SDK-boundary problems

Both looked like ".NET 8 vs the Framework SDK" and neither was. `ilspycmd` and
`dotnet-script` settled both in minutes after reasoning from the outside had stalled;
reach for them first on this class of problem.

**Sciex `2020-06-09 BAK 270 optimization.wiff`** - `Idx -  could not be found
(STG_E_FILENOTFOUND)`, 4 of 11 runs written. The message is `name + " - " + ex.Message`
with an empty COM message; the stream wanted is plain `"Idx"`. A probe showed
`GetNumberOfSamples`, `GetBasicSampleInfos` AND cpp's `batch.GetSampleNames()` all report the
same **11** samples, index 4 being `isocratic wash` (first of a duplicate pair), which has no
`Idx` stream. Both sides fail on it. cpp survives because `Reader_ABI.cpp:244-269` wraps
EACH sample in try/catch, logs, and keeps the other ten. We aborted the file.
Fixed in `Converter.ConvertOne` with a read-only tolerance on the convert-every-run path.
**Scoped deliberately**: `WriteOutput` still aborts, because the Thermo failure below
surfaces while the writer pulls spectra and swallowing it would turn a loud failure into a
silently truncated file. Note cpp's skip COMPACTS its run list, so cpp's run 4 is our run 5;
output filenames match (same ten) but `--runIndexSet N` still means different runs.

**Thermo `20May24_P3_LHS_line_003.raw`** - NullReferenceException on spectrum 2 of 188. It is
an SDK bug: `Scan.ToCentroid` builds one `Fragment(i)` per segment, `Fragment` returns NULL
for any segment with fewer than 2 points, and `MergeSegments` dereferences that null
unguarded. Scan 2 is an ITMS MS3 with `SegmentSizes [0]` - an empty scan. cpp never meets it
because XRawfile's `GetMassListFromScanNum` does its own centroiding and returns zero peaks;
cpp emits that spectrum with `defaultArrayLength=0`. Fixed by guarding the PRECONDITION
(`CanFragmentEverySegment`) rather than catching the exception, so an unexpected NRE still
surfaces; the empty scan falls through to the segmented stream and emits the same
`defaultArrayLength=0` cpp writes.

### Verification

| input | before | after |
| --- | --- | --- |
| Waters `QCsynapt_#021...raw` | 7,506 diffs | **0 diffs / 28,804 spectra** |
| Waters `T0016P01_Gly_11122019_1.raw` | `cs-failed` | **identical** |
| Sciex `BAK 270 optimization.wiff` | `cs-failed`, 4 of 11 runs | **10 runs, 0 diffs**, same file set as cpp |
| Thermo `20May24_P3_LHS_line_003.raw` | `cs-failed` | **0 diffs / 188 spectra** |
| Shimadzu `MIDAZOLAM STANDARD_009.lcd` | 1,507 diffs | **1** (`run/@startTimeStamp`) |
| Bruker `0.1HCOOH_H20_NoTIMS_Pos.d` | 1,164 diffs | **4** (instrument model + componentList) |

Sweep `results-20260821-peakpicking.jsonl` (first run with BOTH a current binary and the
fixed comparator): identical 379 -> **381**, differs 28 -> 27, cs-failed 3 -> 2. It predates
the last two fixes, so a rerun should now show **cs-failed 0**. Three Sciex status moves in
that run are 420 s-timeout noise, not regressions - two moved AWAY from `identical` because
cpp timed out that run and had not the run before.

### Tests, and why the probe is the one that matters

`VendorReaderTestHarness.ProbeCentroidMsLevelGate` - a sibling of `ProbeFinalizers`, run from
`FixtureRunContext.Check` for every vendor on whatever fixtures it already has. The property
is deliberately data-agnostic: **with an EMPTY msLevel set, `GetCentroidSpectrum` must return
exactly what `GetSpectrum` returns.** No knowledge of any fixture's contents, and it is the
whole gate in one assertion. Comparison goes through the regular diff code via a new
`MSDataDiff.DescribeSpectrum`, so cvParams, array lengths and binary values all come free.

**Mutation-verified**: reverting Shimadzu to the pre-fix behaviour fails
`Reader_Shimadzu_10nmol_Negative_MS_ID_ON_055` on spectrum 0 of the first fixture with
`defaultArrayLength: 339 vs 56` + `cvParam b-only: MS_centroid_spectrum`. A probe that
returns silently when no fixture matches looks exactly like a passing one - mutate it or do
not trust it. Sampling is head AND tail (25 each) because Waters interleaves its DAD spectra
from index 0 while Agilent appends them after the whole MS run.

It deliberately does NOT assert "an included msLevel must change the spectrum" (Thermo only
has a centroid stream for FTMS, Agilent will not centroid quadrupoles - declining is legal),
nor "never both profile and centroid" (readers set both on purpose). The second belongs to
the picker, and lives in `VendorCentroidGateTests.PeakPicker_OnlyVendorCentroidsSelectedMsLevels`
- a stub-based test needing no SDK or data, so it guards the ordering on a CI leg built
without vendor archives.

### Four things noticed in passing

- **`--continueOnError` does not do what its message says.** It only decides whether the
  INPUT-FILES loop breaks (`Converter.Run`), so with a single input it does nothing at all -
  while the failure path still prints "re-run with --continueOnError".
- **`Reader_UNIFI_HarnessAgainstReferenceUrls` makes LIVE calls** to
  `democonnect.waters.com` and went red on a `500 Internal Server Error` mid-session. That
  suite cannot distinguish our bug from Waters being down.
- **31 stale MSBuild worker nodes** (`/nodemode:1`) survived a build that exited through the
  test-failure path - the accumulation `979660e18c` added `MSBUILDDISABLENODEREUSE` to stop.
- **`Deny-DirectBuildTest.ps1` false-positives on `dotnet build-server shutdown`** - its
  `dotnet\s+(build|test|...)\b` pattern matches `build-server`, which is daemon cleanup.
- A Waters lockmass test failed once with `MassLynx open SCAN reader failed (code 6)` and did
  NOT reproduce on rerun; transient file contention, recorded so the next sighting is a
  second data point rather than a first.

## 2026-08-20/24: Sciex ZT Scan, and the nightly finally runs on this branch

Two unrelated threads. The Sciex work is a new acquisition mode; the SkylineNightly work
is why nothing on this branch had ever produced a nightly result.

### ZT Scan is a scanning quadrupole - structurally Waters SONAR, not SWATH

`D:\test\ABI\ZTscan` is a **ZenoTOF 8600** run (SCIEX OS 4.0.0.4907, method
`EvoSep-100SPD_588DaS-5_9Da-10msAccTime-Cycle0_969sec_40C`). Both containers present it as
**430 experiments x 699 cycles = 300,570 spectra**: experiment 0 is `TOF MS (400-900)`, and
1..429 are `TOF PI` with `IsSwath=True`, each a quad bin.

The bins **exactly tile** `[392.760634, 899.778995]` - `upper[k] == lower[k+1]` bit for bit -
in steps of 1.181866 Da, widths alternating 1.18000/1.18373 (Q1 DAC quantization). The window
for a given experiment index is identical in every cycle, i.e. a fixed bin <-> quad-position
map, exactly like a SONAR bin.

The reported 1.18 Da bin is NOT the physical isolation width. Profiling fragment and
surviving-precursor intensities across consecutive bins (cycle 350) gives a smooth,
near-Gaussian curve of **FWHM ~10 bins ~= 11.8 Da**, >10% across ~15 bins. Method says
`Q1 width = 5.9 Da`, so the effective transmission is ~2x the nominal setting - reported, not
explained. Either way each precursor spans ~10-15 bins, which is the extra dimension SONAR
gives you.

One thing better than SONAR: the profile apex lands on the bin whose *reported* centre is
nearest the precursor (9 of 10 measured, within +/-1 bin). **No lag calibration needed** -
SONAR requires `_sonar.inf` for exactly this.

Method parameters, and where they live:

| | `.wiff` (Clearcore2) | `.wiff2` (SCIEX.Apis.Data.v1) |
|---|---|---|
| mode flag | sample custom field `Is ZT Scan` | `IMsMethod.Experiments[].GroupName == "ZTScan"` |
| quad window | `FragmentBasedScanMassRange.FixedMasses[0]` + `IsolationWindow` | `IExperiment.MassRanges[0].IsolationWindow` (absolute edges) |
| CE ramp | only `CE ∓ CES` -> 18..42 | `CERampStart`/`CERampStop` -> 18..43 |

`IExperiment.ScanType` is just `'TOFMSMS'` - nothing ZT-specific. **Neither API says the 429
bins belong to one sweep**; that only follows from the method (`Total MSMS scan time 0.86015`
= one experiment spanning the whole sweep) or from the tiling geometry.

### Is the 4-array (SONAR) representation suitable? Yes structurally, but it is not needed

Populating `MS:1003157`/`MS:1003158` is *easier* than for SONAR - both SDKs hand over the quad
bounds per spectrum, and bin<->m/z is arithmetic (`bin = floor((mz - 392.760634) / 1.181866)`)
with no calibration file. But:

- **Nothing is lost today.** Sciex already gives one spectrum per bin with a proper
  `precursor/isolationWindow`. The 4-array form exists because Waters/Bruker bundle many quad
  positions into one frame that pwiz must split or merge.
- **Cost.** A combined frame is ~1.4 M centroided points (~3 M profile) per cycle vs ~200 k for
  a SONAR frame - ~10x - and there are 699 of them.
- **It discards the per-bin scan start time** (2.010 ms apart across the sweep), which is real.
- **The payoff is Skyline**, not mzML: `eIonMobilityUnits.waters_sonar`, `SonarMzToBinRange`,
  `SonarBinToPrecursorMz`, the SONAR heatmap. If we want that, generalize
  `IonMobilityEquipment::WatersSonar` to a vendor-neutral scanning-quadrupole type rather than
  reusing the Waters names.

**Implementation trap if that happens:** `mzToBinRange(mz, tol)` must widen by the
*transmission* width (~11.8 Da measured), NOT the *encoded* bin width (1.18 Da). Otherwise you
extract 1 of the ~10 bins that actually carry the precursor's fragments.

### What was actually fixed: per-bin collision energy, and the ZenoTOF 8600 model

Neither SDK records a per-bin CE - both report the ramp MIDPOINT (30 eV) on **all 429 bins**,
off by up to 12 eV at either end. `ZtScanBin` carries the endpoints and interpolates on the
bin's **ordinal** (the quadrupole scans at constant Da/s, so ordinal and quad m/z are
equivalent, and the ordinal needs no method parameter that only one API exposes).

Contrast with ordinary SWATH, which is where the diagnosis came from
(`Hoofnagle_10xDil_SWATH_01.wiff`): there `CE` really is rolled per window
(`0.0625*mz - 3.48`, the Sciex 2+ equation) and `CES=5` is a genuine within-window spread. ZT
reuses the same CES hardware ramp but scoped to the whole sweep, so CE/CES = 30/12 is a lossy
projection of `CERampStart/Stop` = 18/43 (note 42 != 43 - that asymmetry is what proves which
pair is authoritative).

- cpp: **PR #4598** -> master. C# mirror: `5b2f51111c` on this branch.
- ZenoTOF 8600 (`MS:1003443`, already in the CV): cpp needs the enum+name match in **two**
  places - `WiffFileImpl` AND `WiffFile2Impl` each carry their own copy of the model-name
  ladder. C# maps it once in `Reader_Sciex_Detail`. Patching only the first passed
  `Reader_ABI_Test` (it validates enum->CV, never name matching against a real string) and was
  caught only by running msconvert on the file.
- Verified cpp vs C# **digit-identical, 0 of 14 spectra differing on both containers**;
  `.wiff2` 18.0->43.0, `.wiff` 18.0->42.0 (the 1 eV gap is the legacy container's limit, not an
  implementation divergence). `Sciex.Tests` 8/8, `Reader_ABI_Test` passed.

**Open:** the ramp being LINEAR is an assumption - the files state only endpoints. Documented
in the `ZtScanBin` doc comment pointing at the single accessor that would change. No ZT fixture
exists (source file is 8.6 GB), so nothing regression-guards this.

### The nightly could not build this branch at all - five defects

Commits `73eea63fed`, `588c9359e5`, `0f2cd65f35`, `9950ebe589`.

1. **Built via bjam, not the net8 entry point.** `TabBuild.CreateBuildCommands` hardcoded
   `pwiz_tools\build-apps.bat` + bjam target `pwiz_tools/Skyline//Skyline.exe`, which still
   declares `pwiz_data_cli` and `install-native-dependencies` - so every run rebuilt the whole
   native tree (HDF5 etc.) and never produced a usable Skyline. Now calls
   `pwiz_tools\Skyline\build.bat`. Added `--no-tests` to build.bat (it runs the suite itself;
   SkylineTester runs the tests afterwards under its own budget).
2. **`GetPossibleBuildDirs` left the Nightly slot null on net8.** Only a slot resolved by
   walking up from `ExeDir` to an ancestor named `Skyline` - but under the nightly SkylineTester
   runs from a `SkylineTester Files` folder that is a **sibling** of the checkout.
   `TabNightly.Stop` explicitly selects `BuildDirs.nightly64`, so this produced "No Skyline build
   containing TestRunner.exe was found" and **zero tests even when the build succeeded**.
3. **`git pull` had no `--progress`**, so a long fetch logged nothing and looked like a hang.
   The clone alongside it already passed it for this reason.
4. **`--reuse-checkout`** - the checkout lives INSIDE the SkylineTester folder that is wiped
   each run. Guarded by `IsUsableCheckout` (`.git/index` + a tracked file): an interrupted clone
   leaves a large `.git` with an EMPTY working tree, and reusing that makes `git pull` backfill
   the whole object store.
5. **`--local`** - installs a locally built `SkylineTester.zip` instead of downloading from
   TeamCity. **Covers only the SkylineTester artifact**; the source tree always comes from git,
   so a `build.bat` change still has to be pushed before a nightly sees it.

**Result: 9,480 tests, 13 failures, 13 leaks, 540 minutes** - the first successful nightly on
this branch.

### Triage of the 13

- **7 are credentialed/remote**: 5x `TestArdia*`, `TestUnifi`, `TestWatersConnectExportMethodDlg`
  (the last is already fixed on master by `ecf53f8859`).
- **`AaantivirusTestExclusion`** passed on rerun - flaky/environmental.
- **`TestAssayLibraryImportAsSmallMolecules`** reports itself skipped
  (`RunSmallMoleculeTestVersions=False`) yet still increments the failure count - looks like
  harness accounting, and means 13 may overstate the real number.
- **The remaining 4** (`RefineConvertToSmallMoleculeMassesAndNamesTest`,
  `RefineConvertToSmallMoleculesTest`, `TestCommandLineWarnings`, `TestImmediateWindowWarnings`)
  **pass on the current branch head and fail on the Aug 21 build** - same machine, minutes
  apart, so it tracks the build, not the environment. Which commit fixed them is NOT
  established: the only product delta is the pwiz-sharp mzML reader (cherry-picked #4590) and
  pwiz-sharp Sciex, neither of which touches small-molecule conversion or warning text. The
  failure shape was the MSTest v3 `IEquatable` signature (identical `ToString()` on both sides
  of `Assert.AreEqual`).

### Open: the nightly staging lacks the Bruker native stack

The nightly's staging has no `BDal.*`, `CompassXtractMS.dll`, `hdf5.dll` etc., while a fresh
local staging does. **Both checkouts have `pwiz-sharp/vendor-assemblies/Bruker` populated
identically**, so the source is present in both and something in the nightly's build is not
propagating them. That means the 9,480-test run had no Bruker natives. Not yet chased.

### clean.bat now keeps the C++ build (`9950ebe589`)

The C++ sections (`build-nt-x86*`, extracted boost/libraries, `Version.cpp`, vendor dlls,
vendor test data) dominate rebuild cost and are almost never what you want cleaned. Skipped by
default, gated behind `-cpp` (alias `-all`). Arg parsing became a loop, which also fixes
`-quiet`/`-q` only having worked as the first argument. Uses `goto` rather than a parenthesized
`if` block - several of those lines carry redirections and embedded parens that do not survive
nesting. The C++ pieces are gated together on purpose: deleting vendor dlls while keeping
`build-nt-x86` leaves a tree linked against dlls that no longer exist.

**Measured on this machine:** `clean.bat` (C#-only) **19.2 s**; full `build.bat` rebuild after
it **3.09 min**. (`clean-apps.bat` only walks `pwiz_tools/*`, so `pwiz-sharp` bins survive and
that 3 min excludes them.)

### Two measurement traps that cost time today

- **Staging is never cleaned.** `Stage-Net8Tests.ps1` copies *into* the directory without
  clearing it, so a long-lived checkout accumulates: 1502 files before the clean, 766 after.
  A stale assembly there can make a test pass locally that fails in CI.
- **Copied files keep their ORIGINAL mtime.** `BDal.BCO.dll` is dated `Nov 26 2018` in a staging
  built minutes ago. Reading a preserved timestamp as staleness led to a wrong conclusion that
  the nightly staging was fine - it is not (see above). Use file *size*/content, not dates.
- **.NET builds are not byte-reproducible** - all 54 managed assemblies differ between any two
  builds, so hashing them isolates nothing. Size is the usable signal.
- **Swapping a single assembly between staging dirs does not isolate a regression** - it
  produced a *different* assertion failure, because the rest of the tree was compiled against
  the other build.

### Also open

- **Nightly results never reach skyline.ms**: the POST fails with
  `NumberFormatException: For input string: "unknownDate.5e6dff72a"`. `Nightly.GetRevision`
  builds `"unknownDate." + <short sha>` and the LabKey server does `Integer.parseInt` on it.
  Pre-existing, unrelated to any of the above. The run's XML survives locally in `Summary.log`.
- **The 4 cpp ZT Scan files are deliberately uncommitted on this branch** pending #4598's merge;
  committing them here would collide with the same change arriving via a master merge.
- **Master is 10+ commits ahead**, including `ecf53f8859`.
- `chambem2/pwiz-sharp` and this branch are mirrored again (both at the same commit) after
  cherry-picking #4590 and one force-with-lease push.

## 2026-08-24: Merged master, and ported the disordered-m/z fix to pwiz-sharp

Merge of `origin/master` (9 commits, merge-base `43b5aaf064`) into the branch, plus the C#
mirror of the one incoming C++ product change.

### The merge itself was cheap; the C++ delta was not

Three conflicts, all csproj (`Skyline`, `TestData`, `TestFunctional`), all whole-file - the net8
SDK csprojs share no context with master's enumerated ones. Master's change to each was a single
`<Compile>`/`<None>` item addition (`ToolsUI\GraphElement.cs`, `UnsortedMzArraysMzml.zip`,
`LayoutExportImportTest.cs`), every one of which the net8 csprojs glob. Resolved to **ours** per
the standing playbook, with the three files confirmed present in the tree.

The four uncommitted ZT Scan cpp files were verified **byte-identical to `origin/master`** before
being discarded - PR #4598 landed as `66b7be6d1e`, so the merge brings them back unchanged.

### `641602c20d` (disordered m/z arrays on read) needed a real port

cpp added `SpectrumListBase::ensureMzAscending` + the free `hasNonMzOrderingAxis`, called from the
mzML/mzXML/mz5/MGF/MSn/BTDX lists. Mirrored into `SpectrumListBase` (`ISpectrumList.cs`) with the
same two-verdict asymmetry (one out-of-order spectrum condemns a file; only a spectrum with more
than 10 peaks may vouch for one), the same exemption list, and a stable sort that carries every
per-peak array - double and integer - along with the m/z axis. `boost::atomic` became
`Interlocked` over an int; `sort_together` became a tie-broken-on-index `Array.Sort` permutation.

**Three places the port is not a transcription:**

- **The mzML parallel-decode batch path.** cpp calls `ensureMzAscending` once at the end of
  `spectrum()`; the port's `ReadOne` returns spectra whose binary arrays are still empty, because
  `FillBatch` defers every decode to `DecodeInParallel`. A call there would read no peaks, learn
  nothing and reorder nothing, so it goes at each of `GetSpectrum`'s three exits instead.
- **The eager fallbacks.** cpp's mzML/mzXML lists build their own index when a file has none, so
  one lazy list covers both cases. The port instead parses the whole file into a
  `SpectrumListSimple` when there is no index footer - and **the Skyline fixture
  `DataConvert5_unsorted_mz.mzML` is not indexed**, which is exactly the shape a third-party
  writer emits. Added `EnsureMzAscendingThroughout` and called it from the mzML, mzXML and mzMLb
  eager paths. Without it the fix would have missed the very files it exists for.
- **MGF/MSn/BTDX are materialised up front** rather than served lazily, so the repair happens as
  each spectrum is added (MSn, BTDX) or on access (MGF, where re-checking is bounded because a
  repaired array now ascends and stops at the first test).

**One deliberate cpp divergence, verified harmless.** cpp's `Spectrum::getMZArray()` matches
`MS_wavelength_array` as well as `MS_m_z_array`, which is why `hasNonMzOrderingAxis` needs a
wavelength arm. The port's `GetMZArray()` matches only `MS_m_z_array`, so a diode-array trace
stops one step earlier - at having no m/z array at all. **Same outcome** (left alone, settles
nothing), so the arm is kept for the day `GetMZArray` is brought in line, and both the method's
doc comment and the test say so. This surfaced as the single red case on the first test run.

**`DiffConfig::ignorePeakOrder` was NOT ported.** It exists in cpp to keep its own mz5/MGF
round-trip tests green once reads are reordered - mz5's delta encoding and MGF's ten-significant-
digit m/z each destroy ties that existed on the other side. All 85 `MsData.Tests` pass without it,
so nothing in the port needs it yet; noted here rather than ported speculatively.

### The exclusion hid one real product bug, and three genuine gaps

`TestData.csproj` excluded `PwizFileInfoTest.cs` wholesale on net8 for a `GetScanDescription`
gap. That reason is **stale** - the sandbox wrapper has since grown it (`MsDataFileImpl.cs:1919`)
and `TestScanDescription` passes. But the exclusion was doing more than its comment claimed: it
was also swallowing master's brand-new `TestUnsortedMzArrays`, which is why the first attempt to
run that test reported "No tests found" rather than a failure - a much more confusing signal.

Compiling the file back in and running all seven: **4 pass, 3 fail**, and the three name three
distinct gaps.

**Fixed - Mobilion was never registered at all.** `TestInstrumentInfo` first died on *No
registered reader recognized the file: ...mbi*. `MsDataFileImpl.Vendors.cs` registers vendor
readers into `ReaderList.AdditionalReaders` from a `[ModuleInitializer]`, and its list had Thermo,
Waters, Sciex, Shimadzu, Agilent, Bruker, UIMF and UNIFI - **but not Mobilion**, which
`ProteowizardWrapper.csproj` also never referenced. Nothing marked the omission deliberate; the
reader exists and builds. **Skyline on net8 could not open a `.mbi` file at all**, and the only
test that would have said so was excluded from the build. Fixed with the missing
`ProjectReference` plus one `TryAdd`; `TestInstrumentInfo` now gets past the `.mbi` file.

**Still open - three gaps, left excluded rather than left red:**

1. **Reader type-name parity** (`TestAgilentSourceType`). pwiz-sharp reports `"Agilent"` where cpp
   reports `"Agilent MassHunter"`, and `MsDataFileImpl.IdentifyReaderType` hands that string
   straight to `DataSourceUtil`. Not a one-word rename - a systematic divergence:

   | pwiz-sharp | cpp |
   |---|---|
   | `Agilent` | `Agilent MassHunter` |
   | `Sciex` | `Sciex WIFF`, `Sciex WIFF2` |
   | `Bruker` | `Bruker Analysis/BAF/TDF/TSF/YEP/FID/U2` |
   | `Waters` | `Waters RAW` |
   | `Mobilion` | `Mobilion MBI` |
   | `MGF` | `Mascot Generic` |
   | `MSn` | `MS1`, `MS2` |
   | `mz5` | `MZ5` |

   pwiz-sharp folds cpp's per-format readers into one reader per vendor, so there is no 1:1
   mapping: the format-specific name has to be derived from the file that was identified. This is
   the same class of bug as issue #4510 (Bruker FID source type), so it is user-visible in the
   import dialogs, not just in a test.
2. **mzXML instrument model comes back empty** (`TestInstrumentInfo`) for the MzWiff-generated
   `051309_digestion-s3.mzXML`; expected `4000 Q Trap`.
3. **TIC chromatogram count** (`TestTicChromatogram`): a vendor file reports 15 chromatograms
   where 1 is expected.

The exclusion was restored with all of the above written into the csproj comment, so the next
person to look does not have to rediscover it. The cost is that master's `TestUnsortedMzArrays`
does not run on net8; the behavior it covers is covered instead by pwiz-sharp's own
`MzOrderingTests`, which is the layer the repair actually lives at.

Worth generalising: an exclusion added to get a suite green stops being a to-do the moment nobody
re-checks it. This one outlived its stated reason, and in the meantime absorbed both a new
upstream test and a shipped-product gap.

### Verification

- `MsData.Tests`: **85/85**, including the new `MzOrderingTests` mirroring all eleven cpp cases
  from `SpectrumListBaseTest.cpp` (consolidated into one `[TestMethod]` per the testing rules).
- Skyline net8 build: clean, 0 errors.
- Skyline **pass0 build check (CommonTest + Test + TestData): 624 tests, 0 failures** - the real
  regression surface for a reader change, and it includes `CodeInspection` (green, so no line
  ending / BOM / style violations in any of the edits).
- `TestUnsortedMzArrays` passes when compiled in, with the warning firing at
  `channel=2 process=0 spectrum=2 scan=2` - i.e. the short ordered first spectrum correctly failed
  to settle the file and the disorder was caught on the next one.

### Two harness traps worth recording

- **`cmd /d /c "cd /d <dir> && call foo.bat"` through the Bash tool silently ran nothing** - it
  returned exit 0 having printed only the CLINK banner. Writing a `.bat` in the session temp dir
  and invoking it via the PowerShell tool works. The handoff's `/d` advice is necessary but not
  sufficient when the command crosses Git Bash quoting.
- **cmd here does not search the current directory for executables.** `TestRunner.exe ...` after a
  `cd /d` gives "not recognized"; `.\TestRunner.exe` works. That failure mode reads exactly like
  the sandbox blocking `.bat` files, which is what sent the first diagnosis the wrong way.
- **`ai/scripts/fix-crlf.ps1 -Path <file in a sibling checkout>` reported "All converted to CRLF"
  and converted nothing.** Verify with a byte count, not the script's own summary.

## 2026-08-25: A stale test exclusion was hiding eight bugs

Continuation of the merge session above. Re-enabling one excluded test file turned into eight
pwiz-sharp fixes, and the way each stayed hidden is more instructive than the fixes themselves.

### `Spectrum.GetMZArray` now matches cpp

cpp's `getMZArray()` returns a `MS_wavelength_array` as well as an `MS_m_z_array`
(MSData.cpp:757-766); the port matched only m/z. Brought in line, which turned the
`MS_wavelength_array` arm of `HasNonMzOrderingAxis` from unreachable code into a live guard -
a diode-array trace now reaches the test that exempts it instead of stopping earlier at
"no m/z array". Same observable outcome either way, which is why it was invisible; the arm is
only correct *because* GetMZArray now behaves like cpp's.

### `PwizFileInfoTest`: one stale exclusion, six gaps under it

`TestData.csproj` excluded the file for a `GetScanDescription` gap that the sandbox wrapper had
since closed. Compiling it back in exposed, in order of discovery:

1. **Mobilion was never registered as a vendor reader.** `MsDataFileImpl.Vendors.cs` lists eight
   vendors from a `[ModuleInitializer]` and omitted it; `ProteowizardWrapper.csproj` never
   referenced the project either. **Skyline on net8 could not open a `.mbi` file at all.**
2. **Reader type names did not match cpp.** `Agilent`->`Agilent MassHunter`, `Waters`->`Waters
   RAW`, `Mobilion`->`Mobilion MBI`, `mz5`->`MZ5`, `MGF`->`Mascot Generic`, plus `IdentifyType`
   overrides for the two readers that fold several cpp readers into one (`Sciex WIFF`/`WIFF2`,
   `MS1`/`MS2`), following the pattern `Reader_Bruker` already used. `IdentifyReaderType` hands
   these straight to `DataSourceUtil`, so this is user-visible in the import dialogs - the same
   class as issue #4510.
3. **Bruker global TIC ignored `GlobalChromatogramsAreMs1Only`.** cpp builds its CompassData
   handle with `preferOnlyMsLevel` and passes only the MS1-only flag to `getTIC`/`getBPC`, so the
   two compose. The port used the spectrum filter alone: a 6-frame PASEF run reported 15 TIC
   points where Skyline expects 1.
4. **mzXML instrument model was stored where no consumer looks** - on a `ParamGroup`, but
   `UserParam(name)` is non-recursive in both cpp and C#, so Skyline's fallback found nothing.
   Now mirrors `LegacyAdapter_Instrument::manufacturerAndModel`.
5. **mzXML instrument categories were left as vendor shorthand** - ionization read `ESI` where
   every other format reports `electrospray ionization`. Ported `LegacyAdapter_Instrument::Impl::set`.
6. **`GetNonUnicodePath` never shortened a Unicode file name** - it gated on `Directory.Exists`
   where cpp gates on `bfs::exists` and PathEx checks both. The one case the conversion exists for.

`DataFileMemoryLeakTest` was excluded beside it for a `ConfigInfo` gap that was *also* closed.
Both tests pass. **`TestData.csproj` now has zero `Compile Remove` entries.**

### Two more found only by running in parallel

7. **Thermo had the same TIC bug as Bruker.** No source file under `src/Vendor/Thermo/`
   referenced `GlobalChromatogramsAreMs1Only`. cpp expresses it as a scan filter - `"Full ms"`
   vs `""` (ChromatogramList_Thermo.cpp:400-401) - so the port sets
   `ChromatogramTraceSettings.Filter` the same way. A 99-scan file reported 99 TIC points where
   30 MS1 scans are expected.
8. **The VC++ runtime did not reach a plugin subfolder.** Sciex's `wiff2/SQLite.Interop.dll`
   failed with `0x8007007E` in the containers. `VendorNativeCrt.targets` already stages the CRT,
   and it *was* in the output root - but .NET loads a native library given a full path with
   `LOAD_WITH_ALTERED_SEARCH_PATH`, which substitutes the DLL's own directory for the application
   directory in the search order, so the root copy is never searched from `wiff2/`. Both wiff2
   staging targets now copy `@(VendorNativeCrtFile)` in beside it (3 -> 53 files); the rule is
   documented in `VendorNativeCrt.targets` for the next plugin folder.

### `ignorePeakOrder` did need porting after all

Judged unnecessary on the evidence of 85/85 `MsData.Tests` - too narrow a basis. The Bruker
combined-IMS **MGF round trip** is its motivating case: MGF drops the mobility array, so the
re-read copy is repaired into m/z order while the vendor-read original is deliberately left
alone. Ported the config flag and cpp's value-based peak pairing; Bruker went 11/14 -> 14/14. It
also covers a case cpp's flag does not: Sciex `simAsSpectra` through the port-only mzMLb round
trip, since SIM-as-spectra is transition-ordered and pwiz deliberately does NOT exempt it.

### The lesson worth keeping: green is not the same as run

**Four of `PwizFileInfoTest`'s eight tests early-return under `Program.NoVendorReaders`, and
pass0 sets it.** In every `pass0=on` run they reported "0 failures" while executing nothing -
which is how a claim that all eight passed got made on the strength of runs where half of them
no-opped. `TestTicChromatogram`'s Thermo bug survived two layers of this: excluded from the
build, then a no-op once compiled. It surfaced only in the pass1 leg of a parallel run, which
runs those tests with vendor readers live.

A test-disabling survey of the whole Skyline tree found the net8 port had disabled remarkably
little - the perf skiplist, the ~18 commented-out `[TestMethod]`s and every `NoNightlyTesting`
attribute are byte-identical to master, and there are no `[Ignore]` attributes anywhere. The
compile-time exclusions were the small part. **The runtime skip guards are the ones that hide
things**, because a no-op reports as a pass:
`SkipSmallMoleculeTestVersions()` (16 sites), `NoVendorReaders` (4), `EnableArdiaTests` (7),
`HasKoinaServer()` (4), `IsRunningOnWine` (2) - all upstream, none net8-added.

Also worth knowing: `TestPerf` and `TestTutorial` build and target net8 but are **not** in
`build.bat`'s `BUILD_TARGET`, so per-commit CI never runs them.

### Code review triage (9 applied, 2 rejected)

A `/code-review` over the working tree surfaced 11 findings. Nine were applied; two were wrong
and are recorded here so they are not "re-found" next time.

**Two real correctness bugs.**

1. *mzXML `LTQ Orbitrap XL` was being given the wrong analyzer term.* The CV lists `FTMS` as an
   exact synonym of `MS_FT_ICR`, so translating the raw `msMassAnalyzer` string stamped FT-ICR on
   an orbitrap. cpp guards this with an explicit rewrite of `FTMS` -> `orbitrap` for that model,
   applied *after* the model is set - which is why `ReadInstrument`'s ordering had to change too
   (components appended, then manufacturer/model, then the legacy category translations). This
   turned a missing term into a *wrong* term, which is worse than the gap it replaced.
2. *`WarnOnce` was not thread-safe.* `HashSet<int>.Add` from the mzML parallel decode threads can
   tear. Now under `lock (_warned)` with the add's return value read inside the lock.

**One structural fix.** The eager peak-order repair was living in the three reader *adapters*, so
anything calling `MzmlReader.Read` / `MzxmlReader.Read` directly bypassed it - including the
vendor test harness. cpp puts its single call inside `SpectrumList_mzML::spectrum`, serving
indexed and non-indexed alike; moved into the readers to match. A comment of mine asserting the
adapters were the only entry point was simply false.

**~45 lines of dead code removed.** `DiffConfig.IgnorePeakOrder` (the property, not the feature)
was never set by anything, and had it been wired it would have compared *unpermuted* charge/SNR
arrays against *permuted* m/z. Deleted along with `PairPeaksForComparison` / `Reordered`. The
live path is `TryPairPeaks`, reached through `DescribeSpectraDataOnly(..., ignorePeakOrder)`.

**Rejected, with evidence:**

- *"Only Bruker and Thermo honour `GlobalChromatogramsAreMs1Only`."* False - Agilent
  (`Reader_Agilent.cs:258`), Sciex (`Reader_Sciex.cs:248`), Shimadzu (`Reader_Shimadzu.cs:63`)
  and Waters (`Reader_Waters.cs:61`) all read it.
- *"Bruker's msLevel array desyncs from the chromatogram when the MS1-only flag is set."* That is
  cpp's own behaviour: it keys `msLevelArray->data[i-1]` positionally off `getMSSpectrum(i)` too,
  and explicitly suppresses its own count-match assertion when the flag is set. Changing it would
  diverge from the reference mzMLs the vendor tests compare against.

The Bruker flag is *composed*, not substituted: `_globalChromatogramsAreMs1Only && _preferOnlyMsLevel != 2 ? 1 : _preferOnlyMsLevel`.
An earlier version had it replace `preferOnlyMsLevel` outright, which broke the `-ms1-centroid`
tiers (50 chromatograms where 20 were expected).

### Two defects the post-review test run found

**1. The review's own reader fix regressed `Reader_Sciex_..._simAsSpectra` (7/8).** Moving the peak
repair out of the adapters and into `MzmlReader` also caught the harness reading its *golden
reference*, so the reference was sorted on read while the vendor side under test kept the vendor's
order. Decoding the reference settles what happened:

    on disk:        m/z [127, 249, 195, 131, 153]   <- SIM transition order, 5 peaks
    after repair:       [127, 131, 153, 195, 249]   -> data[1] = 131
    vendor read:                                       data[1] = 249

The reader change is right - cpp's `hasNonMzOrderingAxis` exempts SRM and CRM and *deliberately not
SIM*, so cpp sorts this file too. The fix is on the harness side: `MzmlReader.RepairPeakOrder`,
default true, set false only for reading golden references. A reference is compared **as stored**;
normalizing it both breaks legitimately transition-ordered fixtures and costs the test the ability
to notice a vendor reader that *started* sorting output the reference says is unsorted.
`DiffConfig.IgnorePeakOrder` was deliberately NOT reinstated - ignoring order accepts any
permutation and loses more than it buys.

It took **two** sites. Fixing the reference read moved the failure to the mzXML round-trip leg,
which repairs the round-tripped copy the same way; `ignorePeakOrder` there was keyed on
`CombineIonMobilitySpectra` only. The mzMLb leg already had `|| config.SimAsSpectra` - the mzXML
leg was missed when that was first added. MGF needs no entry (MS2+ only, and SIM is MS1).

**2. `TestImportFullScanNarrowScanWindows` fails on the Docker workers, and predates this work.**
`Unable to load DLL 'hdf5' or one of its dependencies (0x8007007E)`. `ERROR_MOD_NOT_FOUND` is a
missing *dependency*: hdf5.dll's import table (dumped from the staged binary, not assumed) lists
`VCRUNTIME140.dll` plus the UCRT apisets, and the container has no redistributable. HDF.PInvoke
ships it as a NuGet native asset under `runtimes\win-x64\native\`, and `LOAD_WITH_ALTERED_SEARCH_PATH`
searches *that* folder rather than the output root where the CRT lives - the same subfolder rule
`VendorNativeCrt.targets` already documents for Sciex's `wiff2\`. That targets file now copies
`@(VendorNativeCrtFile)` into `runtimes\win-x64\native\` too.

Note the targets file's comment claims the root-level CRT copy fixed mzMLb in containers. It cannot
have: there is no `hdf5.dll` in the output root at all, only under `runtimes\`. The comment
overstates what was fixed, and this test has most likely been red on the workers ever since. CI is
sequential, so it never showed there - the same blind spot that hid the Thermo TIC bug.

### Verification

Re-run end to end after the code review and the two defects above (2026-08-25):

- Skyline full suite (parallel, 8 Docker workers): **1100 tests, 0 failures**, 11m42s.
- Skyline pass0 build check (French, small-molecule versions on): **634/634**.
- Skyline localized ja/zh import: **36 runs, 0 failures**. pass1 functional subset: **59 runs,
  0 failures** - including `TestTicChromatogram` and `TestInstrumentInfo`, the leg that originally
  exposed the Thermo `GlobalChromatograms` and SQLite CRT bugs, so those hold with vendor readers
  live. `build.bat` exited 0 on all four legs.
- pwiz-sharp: Sciex **8/8**, MsData 85, Analysis 173, Waters 67, Bruker 43, Agilent 36, Thermo 21,
  MsConvert 17, Common 58, and the rest green.
- The hdf5/mzMLb fix was confirmed **inside a worker container** rather than inferred from the
  suite: `docker run ... chambm/always_up_runner ... test=TestImportFullScanNarrowScanWindows`
  passes (fr + en) where it previously threw `DllNotFoundException: hdf5`. The suite passing is
  not sufficient evidence on its own - the test can land on the host worker, which has the
  redistributable installed and passes either way.
- Environmental, not product: 69 BiblioSpec tests whose inputs are absent and untracked here, and
  the UNIFI harness against Waters' live demo server.
- One `!!! TestInstrumentInfo LEAKED 36192 Managed bytes` in pass1 leak detection, which did not
  fail the leg (TestRunner responded by running it 28 times instead of 21). Not seen in the
  previous run; 36 KB, and every iteration reported 0 failures.

### Open

- **`RefineConvertToSmallMoleculesTest` is flaky** - 2 of 5 runs, always `AssertEx.SettingsCloned`
  comparing two `PeptideLibraries` with identical `ToString()` (the net8 MSTest v3 `IEquatable`
  shape). Predates this work, undiagnosed.
- ~~**`BullseySharpTest.cs` should be deleted from master**~~ - DONE upstream, deleted in the
  commits that landed on `chambem2/pwiz-sharp` on 2026-08-26. It was a typo-named stale
  duplicate of `BullseyeSharpTest.cs` declaring the same class with a different base; master's
  enumerated csproj never compiled it, so an edit to it was silently a no-op.
- The cpp `VendorReaderTestHarness::assertMzAscending` companion is not ported.
- ~~**`Skyline/work/20260612_net8_port` no longer exists on origin**~~ **RESOLVED 2026-08-31.**
  It was absent at ~16:30 UTC on 2026-08-26, which is when this was written, but PR **#4619**
  ("Port ProteoWizard core to .NET 8") was opened on that branch at 19:38 UTC the same day and
  the ref has existed since. Nothing was deleted - the branch was simply pushed a few hours
  after the check. **The standing "push to both" directive has two live targets again**, and
  both were pushed in sync on 2026-08-31 (`f436051512`). Re-check with `git ls-remote` rather
  than trusting this line; a negative ls-remote result is only true as of the minute it ran.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260612_net8_port.md` before starting work.

## 2026-08-26: peakPicking sweep reaches cs-failed 0, and an installer finding

Addendum to the 2026-08-21/24 entry. The six fixes recorded there are now measured
together, and the msconvert-sharp branch state is captured for whoever picks it up.

### The sweep the six fixes were aiming at

`results-20260824-peakpicking.jsonl` - first run carrying ALL six fixes plus the eight
commits that arrived from the parallel session. cpp snapshot unchanged (Aug 18), so it is
directly comparable to `results-20260821-peakpicking.jsonl` on status.

| status | 08-21 | 08-24 |
| --- | ---: | ---: |
| identical | 381 | **382** |
| **cs-failed** | 2 | **0** |
| differs | 27 | 27 |
| cpp-failed | 18 | 19 |
| both-failed | 62 | 62 |

**Every input the C# converter could not handle now converts.** Both `cs-failed ->
identical` moves are the two files fixed: `2020-06-09 BAK 270 optimization.wiff` (per-run
read tolerance) and `20May24_P3_LHS_line_003.raw` (Thermo empty-scan guard).

Of the three other transitions, two are the known Sciex 420 s timeout files
(`221111_Ullrich_220697_1/_2`) that flip buckets run to run. The third is worth not
mis-crediting: `250814_ZTScan_100spd_A_3_G1.wiff2` moved `both-failed -> cpp-failed`, i.e.
**C# now succeeds where it previously failed** - that is `5b2f51111c` (ZT Scan collision
energy), not anything in this thread.

No sign of regression from `a8bf6e85d9`'s opt-in parallel mzML decoding: `differs` held at
exactly 27 and nothing moved away from `identical` except the one timeout flip.

The remaining 27 `differs` are unchanged and still dominated by the cpp-side IMS defect in
the standing record above. Net of those: 10 Shimadzu (timestamp only), 2 Thermo, 1 Bruker,
1 Sciex, 1 Waters.

### Installer: an install-time side-by-side/updating choice is cheaper than it looks

Asked whether the installer could offer side-by-side vs auto-updating at install time. Two
findings, both verified rather than assumed:

- **`AppId={code:GetAppId}` compiles.** Inno evaluates it at run time; it only demands
  `UsePreviousLanguage=no` alongside, and says so at compile time. Verified by compiling a
  probe .iss with the local ISCC. That was the one thing that could have made this
  impossible, since `AppId` is what Inno keys every install on and today it is a
  compile-time `{#MyAppVersion}` substitution. `DefaultDirName` and `DefaultGroupName`
  already accept `{code:...}`, so all three switch together.
- **No elevation or signing is required for the per-user path.** `Setup.iss` already sets
  `PrivilegesRequired=lowest` with `Root: HKA`, so the default install is per-user under
  `%LOCALAPPDATA%\Programs` with HKCU verbs. An update rewriting that directory needs no
  UAC, and SmartScreen keys off Mark-of-the-Web, which a self-updater downloading via
  HttpClient does not set. The unsigned-installer warning in `installer/NOTES.md` is about
  the browser-download path and exists with or without auto-update.

What actually costs: **replacing files that are running** (Windows locks loaded images), and
the fact that `IsKnownLeakySdkPath` documents vendor SDKs holding native handles until ALC
unload - i.e. until the process exits. So the swap belongs in a helper AFTER exit, not in a
shutdown handler. Do it as two directory renames on one volume (`install -> install.old`,
`staged -> install`), which fails cleanly before touching anything rather than halfway
through a file copy. `VendorReaderTestHarness.AssertFilesUnlocked` is the same rename probe
inverted and carries the retry tuning (5 x 100 ms, after GC + WaitForPendingFinalizers) that
such a swap will need in PRODUCT code, not just in tests.

Nothing decided or built here - recorded so the feasibility work is not repeated.

### Branch state

Five commits on `chambem2/pwiz-sharp` in `C:\dev\pwiz-msconvert-pr`, **rebased onto
`0f2cd65f35` and still UNPUSHED**:

```
318d6e29fd  Fixed an empty scan crashing the Thermo vendor centroider
f6f73b9759  Fixed one unreadable run aborting a whole multi-run file
52e5e47ddf  Fixed vendor centroiding to honour the caller's MS levels
05a0feda45  Fixed zero-point spectra losing their binaryDataArrayList
5c0a1e116e  Added ZeroSampleFiller coverage from the reference implementation's vectors
```

origin has since taken a master merge, so the branch is **17 behind**. The five are
unpushed and touch no file the incoming commits touch (checked before the last rebase), so
re-syncing should be routine.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-parity.md` before starting work.

## 2026-08-26b: The five landed on origin, and both sweeps re-run together

Continuation of the entry above. That entry's "Branch state" section is now superseded:
the five commits are **pushed**, not unpushed.

### Re-sync and push

Rebased the five onto the new origin tip (`06f55b4b72`, which carries a master merge) and
pushed: `06f55b4b72..5f30a9d5cd`. Fast-forward, no force.

The previous entry claimed the five "touch no file the incoming commits touch". **That was
stale.** Two files are touched by both sides:

| file | incoming | mine |
| --- | ---: | ---: |
| `MsData/Diff/MSDataDiff.cs` | +119 / -7 | +18 |
| `TestHarness/VendorReaderTestHarness.cs` | +33 / -4 | +102 |

Git merged both without conflict and my delta is purely additive, so the prediction's
conclusion held while its reasoning had gone stale. Verified after the rebase that
`DiffSpectrum(Spectrum, Spectrum, Context)` still has the signature `DescribeSpectrum` calls
and that `FixtureRunContext`'s `_reader`/`_root`/`_predicate` fields the gate probe uses are
intact. The full build+test run is what actually settled it. **Re-derive that overlap with
`git diff --name-only` each time rather than trusting a previous session's claim.**

`Skyline/work/20260612_net8_port` did not exist on origin at the time of this session -
`git ls-remote` showed only `chambem2/pwiz-sharp` (and `chambem2/pwiz-sharp-mzpeak`) - so only
`chambem2/pwiz-sharp` was pushed. **This was a timing artifact, not a deletion**: PR #4619 was
opened on that branch at 19:38 UTC the same day, ~3 h after the check, and both refs are live
again. Do not conclude a branch is gone from one `ls-remote`; it is only true for that minute.

### Build gate

`build.bat Release --i-agree-to-the-vendor-licenses`: **Build succeeded**, and every test
project green except one:

- `UNIFI.Tests` 43/44. `Reader_UNIFI_HarnessAgainstReferenceUrls` failed on a LIVE call to
  `democonnect.waters.com` - HTTP 500 whose body is `ORA-04031: unable to allocate 62536
  bytes of shared memory ("large pool", ...)`. Waters' demo server's Oracle backend is out
  of shared pool. Server-side, unrelated to these commits, and the same test the previous
  entry already flagged as externally flaky.
- `Installer.Tests` 1 passed / 1 skipped - `Install_PerMachine_...` needs elevation.
  Pre-existing skip, `Test Run Successful`.

Totals across the other 18 projects: Analysis 175, BiblioSpec 142, MsData 85, Common 58,
Util 36, Waters 21, MsConvert 17, Agilent 15, Thermo 15, Bruker 14, NativeAot 10, Sciex 8,
IdentData 7, TraData 6, MsConvertGUI 3, Shimadzu 2, Mobilion 2, UIMF 2, Bruker.PrmScheduling 1.

**The UNIFI client mislabels that failure.** A 500 with an Oracle OOM body surfaces as
`authentication error: incorrect hostname, username, or password?`. Nobody reading that
message would look for a server-side memory problem. Small separate defect, unfixed.

### `cmd /c build.bat` silently does nothing - exit 0

Running `cmd /c "build.bat Release ..."` from the Bash tool produced a **three-line log**
(Windows banner + a clink prompt) and **exit 0**. Clink intercepted it and opened an
interactive shell; no compilation happened. Trusting the exit code here would have "verified"
a build that never ran - and, worse, a subsequent snapshot refresh would have copied stale
binaries into the sweep.

This is the same class as the CRLF `call :label` bug already recorded (`build.bat` exited 0
having skipped `dotnet build` x7). **Run `build.bat` through the PowerShell tool**
(`Set-Location <dir>; .\build.bat ...`), and always confirm the log contains
`Build succeeded` and per-project test blocks before believing a green exit.

### Snapshot refresh: overwrite, do not `rm -rf`

`run_parity2.py`'s header comment says to refresh the C# snapshot with `rm -rf` + `cp -r`.
That is wrong for this directory. `G:\parity\msconvert-snapshot` is a **superset** of the
build output: 263 files vs 230, the extra 33 being the Bruker CompassXtract SDK
(`BDal.*.dll`, `CompassXtractMS.dll`, the `Compressor_*.dll` set, the vc90 boost DLLs and the
`BrukerCompassXtract-*.installed` marker) which is extracted at runtime, not produced by the
build. `comm` confirms build-output ⊂ snapshot. Copied over it with `-Force` instead.

Smoke-tested per the previous entry's warning: `20May24_P3_LHS_line_003.raw` with the
peakPicking filter converts, exit 0, 2,087,193-byte mzML. The empty-scan guard is live in the
snapshot, so it is genuinely fresh.

### Both sweeps running concurrently

`run_parity2.py` puts a peakPicking run in `work2-pp` and a default run in `work2` precisely
so the two can run together, so both were started at once rather than serially:

- `G:/parity/results-20260826-peakpicking.jsonl` - the regression check on the master merge
- `G:/parity/results-20260826-default.jsonl` - **the first default sweep since 08-18**, which
  is what finally measures the zero-length `binaryDataArrayList` fixes

**Read the Sciex 420 s timeout files with extra suspicion in this pair.** They already flip
`identical`/`cpp-failed`/`both-failed` run to run, and running two sweeps concurrently
contends for CPU and for D:/G: I/O, which can only push borderline conversions further toward
the timeout. A timeout transition in either file is not evidence of a regression.

Early confirmation that the standing record's cpp-side IMS defect is peakPicking-specific:
`ImsSynthCCS.d` reports `binary values x1402, spectrum/@defaultArrayLength x701` under
peakPicking but only the one deliberate instrument-class `cvParam` under default.

### The Core Windows .NET timeout: quadratic peak pairing (2026-08-26)

`ProteoWizard_CoreWindowsNet` #337 and #338 both failed with **`Execution timeout`** after 60
minutes. The headline error - *"number of tests 0 is 620 less than 620 in build #336"* - is a
**consequence, not a cause**: the step was killed before any results were reported. #336, the build
immediately before the merge, did all 620 tests in **15 minutes**, so this was a hang, not a budget
that finally ran out.

The thread dump TeamCity prints on termination named the culprit in both builds: the still-running
process was `dotnet test Waters.Tests`.

**Root cause.** `MSDataDiff.TryPairPeaks` matched greedily on nearest intensity across a sliding m/z
window. That is near-linear only while m/z values are distinct. A **combined ion mobility spectrum
repeats the same m/z once per mobility bin**, so `windowStart` could not advance past a long
within-precision run and the inner loop rescanned it - already-`bTaken` entries included - for every
peak. Quadratic on precisely the data the path exists to compare.

It had been latent. The merge is what reached it: passing
`ignorePeakOrder: config.CombineIonMobilitySpectra` into the round-trip diffs put Waters' **ten**
combined-IMS configs through the pairing for the first time. Under dotCover, where every statement
is instrumented, ~3x on top of that blew the hour.

**Fix.** Both sides hold the same peaks in a different order, so canonicalize each by
`(m/z, intensity)` and read them in lockstep - position k names the same peak on both. O(n log n),
30 lines replacing 49. The intensity tie-break is what pairs peaks sharing an m/z, which is exactly
the quadratic case. Where the multisets genuinely differ the values do not line up and the
comparison reports it, unchanged.

`Reader_Waters_HDMSe_Short_noLM`: **4m26s -> 2s**, same assertions. Verified with 397 tests across
Waters, Bruker, Sciex, MsData, Agilent, Thermo, Mobilion, Shimadzu, UIMF, Common and Analysis.
Commit `14e8820ac5`.

#### How it was found, including the wrong turn

The first hypothesis was wrong and cost the most time: that the *peak-order repair* was the cost,
because the review had just moved `EnsureMzAscendingThroughout` into the eager readers and the
mzXML/MGF round-trips - unlike mzMLb - are not behind `skipRoundTripForProfiler`. A fix gating them
was written and then **reverted**: disabling the repair outright moved the fixture from 4m26s to
4m20s. No effect. Suppressing those legs would have hidden the problem rather than fixed it, and CI
had run them fine in 15 minutes before.

What settled it was **`dotnet-stack report` against a live run** - the single CPU-bound thread was
parked in `TryPairPeaks` under `RunMzmlbRoundTrip`. The same tool is already cited in the harness's
own profiler comment. For a hang or an unexplained slowdown, sample the stack before theorizing;
three hypotheses cost more than one stack dump.

**A measurement that lied.** An attempt to neuter the repair with `if (true) return;` failed to
compile - CS0162 unreachable code, warnings-as-errors - so `dotnet test --no-build` re-ran the
**previous** binary and produced a perfectly plausible 4m28s. It was discarded and redone with an
env-var gate that compiles. Same family as [[reference_batch_crlf_label_skip]] and the
staging-staleness traps: **a number that looks like evidence but came from code that never ran.**
When an experiment yields "no change", check the build succeeded before believing it.

**Reading the failure.** "0 tests" against a test-count anchor means the run died, not that tests
vanished; go to the termination thread dump for the process that was still alive.

### Triage of the 27 `differs`: 25 already accounted for, 2 genuinely open

The previous entry called these "all small and unexamined" and broke them down as 10 Shimadzu,
2 Thermo, 1 Bruker, 1 Sciex, 1 Waters. **That breakdown was wrong** - there is no Waters file in
`differs`, and it omitted the 13 IMS files entirely. Actual vendors on the 08-24 baseline:
Agilent 9, Shimadzu 10, Mobilion 4, Thermo 2, Bruker 1, Sciex 1. (Note also a 6th status the
tables above never mention: `different-output-files`, 2 files. 382+27+62+19+2 = 492.)

Cross-referencing each against the two standing records leaves only two open:

| group | n | status |
| --- | ---: | --- |
| Agilent + Mobilion IMS | 13 | cpp-side fabricated leading zero sample; standing record; decision is to fix cpp |
| Shimadzu `run/@startTimeStamp` | 10 | ~15 s skew, **accepted user call** (see the 2026-08-1x entry, line ~4463) |
| Thermo filter string | 2 | **not ours** - see below |
| Bruker `componentList` | 1 | already in the C#-surplus record, still open |
| **Sciex TIC 10x on one spectrum** | **1** | **recorded nowhere; genuinely unexplained** |

**Thermo: a rounding pattern that is not our rounding.** All four diffs across the two Thermo
files are precursor m/z in the filter string, and every one is an exact `.XX5` midpoint where cpp
rounds half-away-from-zero and C# rounds half-to-even: 678.125 -> `678.13` vs `678.12`, likewise
1245.625, 995.625, 598.125. That looks exactly like a banker's-rounding defect in our formatter,
and it is not. `SpectrumList_Thermo.cs:592-597` already records the investigation: **both sides
call `IScanFilter.ToString()`**, and cpp ships RawFileReader 5.0.0.93 against our 8.0.6.0, with
v8's `GetScanEventStringForScanNumber` agreeing with its own `ToString()`. The difference is
inside the SDK and cannot be closed from this side while the trees ship different versions.
Worth flagging because the midpoint pattern is a persuasive false lead - check the code comment
before re-deriving it.

**Sciex `QTRAP_010_0133_T_11102006_A074_DJ_120min_IDA.wiff` is the one real lead.** One spectrum
(`sample=1 period=1 cycle=2470 experiment=2`) reports `MS:1000285 total ion current=1.0e09` in
cpp and `1.0e08` in C# - exactly 10x. The isolation is what makes it interesting:

- `records_truncated: 0` - the comparison was complete, not budget-limited, so this is the whole
  story for the file and not a truncated view.
- `binary_diffs: 0` over 6,148 spectra / 6,156 records - **every binary array is byte-identical**.
  The peak data agrees; only the summary cvParam disagrees, and only on one spectrum.
- Stable in **every** sweep since 08-11, default and peakPicking alike, always `n=1` with this
  same value pair. Not a regression from the six fixes; it is the last surviving diff on a file
  that had 81 on 08-10 before the collision-energy fix.
- `mzml_compare` does not reformat numbers, so `1.0e09`/`1.0e08` are the literal strings in the
  two mzMLs.

Not investigated further this session: root-causing it means converting the file with both
binaries, and starting a third concurrent msconvert while two sweeps are running is exactly the
CPU/IO contention that pushes the borderline Sciex files into their 420 s timeout. Deferred until
the sweeps finish rather than risk corrupting their comparability.

### FINAL sweep results - both configurations, 492/492, cs-failed 0

Both sweeps completed. cpp snapshot unchanged (Aug 18) in both, so they are directly comparable
to their predecessors on status.

| | identical | differs | cpp-failed | both-failed | diff-output-files | **cs-failed** |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| peakPicking | 382 | 28 | 19 | 61 | 2 | **0** |
| default | **397** | 23 | 22 | 48 | 2 | **0** |

**`cs-failed` is 0 in the default configuration for the first time** - the previous entry had only
ever demonstrated it under peakPicking. `2020-06-09 BAK 270 optimization.wiff` moved
`cs-failed -> identical` here too, confirming the per-run read tolerance fix outside peakPicking.

**Nine status transitions across both sweeps, none a regression.** Five are pure timeout-boundary
artifacts of running the two sweeps concurrently, which inflated runtimes ~15% and tipped files
that already sat within ~10% of the 420 s cap:

| file | cpp 08-18 -> 08-26 | C# 08-18 -> 08-26 |
| --- | --- | --- |
| `Ellis_033_2700_261_07.wiff` | 426.8 -> 424.3 | 366.4 -> **421.7** (crossed) |
| `22_0430_006_SSL2_ND_Inj_29_01.wiff` | 395.4 -> **420.8** (crossed) | 289.7 -> 329.6 |
| `221111_Ullrich_220697_1.wiff` | 406.7 -> **424.0** (crossed) | 317.2 -> 377.2 |

Note C# is FASTER than cpp on all three. The rest: `092612Sample16.wiff` and
`250814_ZTScan_100spd_A_3_G1.wiff2` improved (C# now completes), `221111_Ullrich_220697_2.wiff` is
the known flipper, and `210319_004_MRMoptim13.wiff2` is the non-reproducible timestamp below.

**Concurrency cost, for the record:** the concurrent run bought ~2x wall-clock and produced 5 of
the 9 transitions as noise. A serial pair would have been cleaner to read. Worth weighing next
time rather than defaulting to concurrent.

### A real C#-side gap the status columns could not see: C# is not vendor-centroiding two files

`cs_surplus.py` on the peakPicking results reports `spectrum/@defaultArrayLength` **6570** - by far
the largest surplus category - and following it back found something the transition analysis
structurally cannot surface, because these files were `differs` before AND after.

**`Neg_MS_002.d` (Agilent QTOF, non-IMS) and
`2020-12-28-18-21-56-20201228_PeptideMap-NISTmAbOxidized[1].d` (Mobilion) share one signature:**

```
spectrum/@dataProcessingRef   cpp=None   cs=pwiz_Reader_Agilent_conversion
spectrum/@defaultArrayLength  cpp=233    cs=2336      (Neg_MS_002.d)
spectrum/@defaultArrayLength  cpp=3      cs=8         (Mobilion)
cvParam missing in C#         cpp emits "user:centroided min/max"; C# does not
```

cpp centroids; C# emits the raw profile. The decisive tell is the third line: `user:centroided
min/max` is the userParam cpp writes *when it has centroided*, and it is absent on our side. Both
files go through the Agilent reader.

**This is not caused by this thread's centroid msLevel gate.** `cpp=233 / cs=2336` is stable in
every peakPicking sweep back to **08-19**, before the gate landed (08-24). It is long-standing and
was never characterised - the standing record noted `Neg_MS_002.d` as "non-IMS and unrelated" to
the IMS defect and stopped there.

The likely shape: the C# Agilent reader declines to vendor-centroid more aggressively than cpp
does. `VendorReaderTestHarness` deliberately does NOT assert that an included MS level must change
the spectrum (declining is legitimate for quadrupole data), so the harness cannot catch an
over-eager decline either. **That is a test blind spot in the same family as the ones recorded
above, and it is why a corpus sweep is not optional.**

### Corrected triage of the 28 peakPicking `differs`

The earlier triage in this entry lumped all 9 Agilent files into the IMS bucket. Wrong - two of
them are not IMS. Accurate breakdown:

| group | n | status |
| --- | ---: | --- |
| IMS cpp-side fabricated zero sample (7 Agilent + 3 Mobilion) | 10 | standing record; fix cpp |
| **C# not vendor-centroiding** (`Neg_MS_002.d`, Mobilion `[1].d`) | **2** | **NEW - real gap, above** |
| `20fmolBSA-centroid.d` extra cvParam x23 + 3 binary | 1 | recorded C# surplus |
| Shimadzu `run/@startTimeStamp` | 10 | accepted user call |
| Thermo filter string | 2 | Thermo SDK 5.0.0.93 vs 8.0.6.0; not closable |
| Bruker `componentList` | 1 | recorded C# surplus, open |
| Sciex TIC 10x | 1 | **unexplained** |
| Sciex `210319_004_MRMoptim13.wiff2` 1 s timestamp | 1 | non-reproducible, below |

### The default sweep's other find: the comparator was hiding an Agilent precision gap

Three Agilent files show huge `diff_count` jumps vs 08-18 - 81 -> 2740, 81 -> 3783, 83 -> 485.
**Not new breakage.** Every sweep before 08-26 reported them at exactly `n=81`, pinned at the old
comparator's 80-diff budget, with the spectra actually compared varying by where it tripped:

| sweep | n | spectra compared (of 1196) |
| --- | ---: | ---: |
| 08-10 | 81 | 43 |
| 08-11 | 81 | 56 |
| 08-12/13 | 81 | 58 |
| 08-14 | 81 | 72 |
| 08-18 | 81 | 47 |
| **08-26** | **2740** | **1196** |

`BSA050-r001.d` was judged on 47 of its 1196 spectra and never reached its chromatograms. The old
records have no `records_compared` / `records_truncated` / `categories` keys at all. This is the
"understates by two orders of magnitude" failure the standing record predicted, now closed.

**The content is Agilent profile m/z precision, agreeing to 9 significant figures:**

```
cpp: MS:1000528 lowest observed m/z=300.271912178283
cs : MS:1000528 lowest observed m/z=300.271912163348
     binary: 206/212 values differ, max_abs=2.89e-07 max_rel=1.9e-10
```

0.19 ppb, ~3e-7 Da at m/z 300 - orders of magnitude below any instrument's accuracy. Large in
COUNT, negligible in MAGNITUDE. **Confined to profile data**: under peakPicking
`AE_30Apr19_negESI_0001.d` and `BSA050-r001.d` are `identical` and `20fmolBSA-centroid.d` falls
3783 -> 26. Peak picking collapses both onto the same centroids and hides it, which is why eight
default sweeps never characterised it and no peakPicking sweep could. Not root-caused; likely a
different order of operations in the m/z axis computation.

### C#-surplus inventory refreshed (the standing directive)

| sweep | files with surplus | categories |
| --- | ---: | --- |
| default | **8 of 492** (was 16 on 08-12) | extra cvParam 10, componentList 4+4 |
| peakPicking | 10 of 492 | defaultArrayLength 6570, extra cvParam 13, componentList 4+4 |

Sciex MRM3 (2 files x12) and Thermo `MAT95XP-File001.RAW` surpluses are **gone**;
`20fmolBSA-centroid.d` fell from x11 to x3; `AE_30Apr19_negESI_0001.d` cleared entirely. The
peakPicking `defaultArrayLength` 6570 is not a surplus in the "we invent data" sense - it is the
not-centroiding gap above (6556 from `Neg_MS_002.d`, 14 Mobilion).

### `210319_004_MRMoptim13.wiff2`: a transition that does not reproduce

`identical` in **13 consecutive sweeps** - including the 08-26 DEFAULT sweep, same binaries, same
day - and `differs` only in the 08-26 peakPicking run, on a 1-second `run/@startTimeStamp`
(cpp `22:49:45Z` vs C# `22:49:46Z`). That pattern points straight at this thread's centroid-gate
change. **It is not that.** Converted in isolation 6x per binary under peakPicking: `22:49:46Z`
12 times out of 12, *including cpp*, whose snapshot has not changed since Aug 18 and which the
sweep recorded as `:45Z`.

**Most likely the concurrent sweeps themselves.** Both drive the SAME manifest, so both can open
the same vendor input simultaneously, and vendor SDKs in this codebase are known to write state
into the input directory (the Waters `lmgt.inf` precedent). Concurrency costs same-input
contention, not merely CPU and timeouts. **Treat isolated single-file transitions in this pair as
suspect until reproduced serially.**

### Open

1. **C# not vendor-centroiding `Neg_MS_002.d` and the Mobilion `[1].d` file** - the highest-value
   item here. Real, long-standing (>= 08-19), 2 corpus files, and invisible to both the vendor
   harness and the status columns. Start at the Agilent reader's decline condition and compare it
   to cpp's.
2. **Sciex TIC 10x** - `QTRAP_010_0133_T_11102006_A074_DJ_120min_IDA.wiff`, spectrum
   `sample=1 period=1 cycle=2470 experiment=2`, cpp `1.0e09` vs C# `1.0e08`. `records_truncated: 0`,
   `binary_diffs: 0` over 6,148 spectra - every array byte-identical, one summary cvParam wrong.
   Stable since 08-11 in both configurations. Convert with both binaries and trace where C#
   sources it.
3. **Agilent profile m/z precision** (~1.9e-10 relative) - decide whether to chase or record as
   accepted, as was done for the Shimadzu timestamp skew.
4. Bruker `componentList` surplus on `0.1HCOOH_H20_NoTIMS_Pos.d`.
5. The UNIFI client reporting an Oracle-OOM 500 as an authentication error.

## 2026-08-27: Two parity gaps closed - one ours, one cpp's

Both were on the previous entry's Open list. They turned out to be opposite kinds of defect, which
is the point worth carrying: "C# differs from cpp" is not a synonym for "C# is wrong".

### Agilent `Neg_MS_002.d`: a null argument that meant the opposite of what the comment said

**2151 diffs -> `diff_total: 0`.** Byte-identical to cpp, 247 records compared, 0 truncated,
0 binary diffs.

`AgilentRawData.GetSpectrumByRow` passed `null, null` for MHDAC's two peak-filter arguments,
under a comment asserting that "passing null for the peak filters means no filtering". It does
not. **Null means "do not centroid"** - handed null, MHDAC ignores
`DesiredMSStorageType.PeakElseProfile` and returns whatever the file stores. cpp always
constructs a default-valued `MsdrPeakFilter` for that call (`MassHunterData.cpp:712-724`, via
`msdrPeakFilter()` at `:54-64`) and passes null only for the quadrupole devices MHDAC cannot
centroid at all. The C# now does the same, with the device gate repeated in the reader exactly
as cpp repeats it.

**Why it hid for months, and why no test could have caught it.** The missing filter is invisible
on any file that stores centroided data alongside profile: there `PeakElseProfile` returns the
STORED peaks and no on-the-fly centroiding is needed, so a null filter changes nothing. It only
bites a file that stores profile ONLY. Exactly one corpus input qualifies:

| file | `mspeak.bin` | outcome before the fix |
| --- | --- | --- |
| `Neg_MS_002.d` | **absent** | profile returned; picker re-picked 3629 -> 2336 pts vs cpp's 233 |
| `BSA050-r001.d` | present | stored peaks returned; already identical |
| `20fmolBSA-centroid.d` | present | stored peaks returned; already identical |

The vendor reference harness could not catch it either - there is no profile-only Agilent
fixture, and `ProbeCentroidMsLevelGate` deliberately does not assert that a selected MS level
must CHANGE a spectrum, because declining is legitimate for quadrupole data. So the guard is a
unit test on the decision itself (`AgilentPeakFilterTests`), needing neither SDK nor data file.

**One root cause, four symptoms.** The single fix closed `defaultArrayLength`,
`spectrum/@dataProcessingRef`, the `cvParam` values, and the missing `user:centroided min/max`
userParam together. The `dataProcessingRef` one is worth understanding: cpp's peak picker returns
early for an already-centroided spectrum WITHOUT setting `dataProcessingPtr`
(`SpectrumList_PeakPicker.cpp:252-268`), and the C# has the identical early return. Once the
reader genuinely centroided, C# stopped writing the attribute by itself. A related suspicion -
that the picker mislabels its dataProcessing as vendor when it falls back - was **checked and
withdrawn**: cpp sets that userParam per-file at construction the same way, so C# matches.

**Measured, not assumed.** Agilent + Mobilion sweep, all 57 inputs, peakPicking:

| file | before | after |
| --- | ---: | ---: |
| `Neg_MS_002.d` | differs 2151 | **identical 0** |
| Mobilion `...NISTmAbOxidized[1].d` | differs 54055 | differs **278** (-99.5%) |
| other 55 | - | unchanged |

The Mobilion file shares the Agilent reader path. Its residual 278 is now `binary_diffs: 0` and
entirely `MS:1000527 highest observed m/z` emitted where cpp emits none - a **new C#-side
surplus** for the standing record, not a leftover of this bug. The IMS files
(`[DC5].d` 711606, the two `.d` at 3000) are untouched, as expected: IMS returns from its own
branches before reaching this code.

### Bruker `0.1HCOOH_H20_NoTIMS_Pos.d`: the C# was already right

The previous entry filed this as a C#-side surplus (5 components vs cpp's 1, plus
`MS:1003123 timsTOF series` where cpp writes `MS:1000122 instrument model`). **It is a cpp
defect.** The file is a `timsTOF fleX MALDI 2` whose BAF `Properties` table stores
`InstrumentFamily = 9`; C# maps 9 -> timsTOF and emits precisely what cpp's own timsTOF case
would produce.

cpp's `translateInstrumentFamily` lives in an **anonymous namespace**, so each Bruker reader
compiles its own copy - and the BAF copy never got `case 9`:

| copy | `case 9` |
| --- | --- |
| `TimsData.cpp:42` | timsTOF |
| `TsfData.cpp:43` | timsTOF |
| `Baf2Sql.cpp:41` | **absent -> falls to `default: Unknown`** |

So the same instrument resolves to timsTOF through TDF/TSF and to Unknown through BAF.

**The obvious objection - that `9` might simply MEAN something different in BAF, which would make
three separate tables deliberate - was tested and does not hold.** Three independent lines of
evidence:

1. **9 is not remapped in the BAF copy, it is missing.** A container-specific meaning would show
   up as `case 9` returning some other family. All three tables are otherwise character-identical:
   same seven codes, same families, same order. A strict subset differing by one line is the
   signature of an un-mirrored edit, not a different encoding.
2. **The data says 9 means timsTOF in BAF too.** Every BAF file in the corpus pairs its family
   code with the instrument name the shared table predicts - 1 micrOTOF, 2 micrOTOF-Q II,
   7 impact II / maXis impact, 8 compact, 512 apex-Qe, 513 solariX XR - and **both** BAF files
   carrying family 9 name a timsTOF: `timsTOF Pro` (`Dunn_016_4380_3172_03_...`) and
   `timsTOF fleX MALDI 2` (`0.1HCOOH_H20_NoTIMS_Pos.d`). Those names are Bruker's own metadata,
   independent of pwiz. TDF files with family 9 name timsTOF Pro / HT / SCP / Ultra - identical
   meaning.
3. **The history shows the mechanism.** `34f38e1eb0` (2018-08-17, "fixed instrument
   configurations for timsTOF") applied the same `InstrumentRevision` plumbing to `Baf2Sql.cpp`
   and `TimsData.cpp` **in one commit, side by side**, and added `case 9` to `TimsData.cpp`
   only. It was harmless then - timsTOF was TDF-only in 2018; TSF did not exist until
   `04a0e8c215` (2022), and `TsfData.cpp` was written by copying `TimsData.cpp`, inheriting the
   case. Nothing deliberate distinguishes the BAF copy.

The three copies exist because the function sits in an anonymous namespace and was duplicated per
translation unit, not because the formats disagree.

**A second corpus file confirms it is not a one-file quirk.**
`D:\test\Bruker\Dunn_016_4380_3172_03_Slot1-16_1_661.d`, a timsTOF Pro writing BAF, shows the
identical signature - cpp `MS:1000122` + `componentList count="1"` against C# `MS:1003123` +
`count="5"`. It never appeared in a sweep because at 1330 MB it is excluded by
`manifest_lt100.json`'s 100 MB cutoff.

**Method note for next time:** the first pass at this check read the three tables out of the
WORKING TREE, which already contained the `case 9` fix, and so showed all three agreeing. Read
comparison baselines with `git show HEAD:<path>` when your own edit is in the file.

Fixed at source: `case 9: return InstrumentFamily_timsTOF;` added to `Baf2Sql.cpp`. That closes
all four diffs on the file at once - the series cvParam and the componentList come off the same
switch. **Not compile-verified**: the C++ msconvert build is separate and long and was not run.

Also corrected a false comment in `BrukerInstrumentFamily.cs`, which had rationalised the
divergence as "no timsTOF instrument writes BAF". Two corpus files are counterexamples. The unified
C# table is right; only its stated reason was wrong. `BrukerInstrumentFamilyTests` now pins the
whole code->family table so nobody "fixes" C# to match cpp's omission.

### Correction to the 08-26 entry: the Agilent precision gap is partly cpp instability

The previous entry recorded three Agilent files whose diffs are m/z agreeing to 9 significant
figures (`max_rel ~1.9e-10`) and guessed at "a different order of operations in the m/z axis
computation" on our side. The re-measured default sweep moved `BSA050-r001.d` from 2740 to 2713
diffs, which the fix cannot explain - under the default config `preferProfile` is true, so
`NeedsPeakFilter` returns false and the call is byte-for-byte the old one.

Running each binary repeatedly against the same input settled it:

| binary | 3 runs, same `-o` | verdict |
| --- | --- | --- |
| C# | 3 identical SHA-256 | **deterministic** |
| cpp | 2 distinct outputs (and a 3rd hash seen in another trial) | **NOT deterministic** |

Two cpp runs of the same file differ from each other by 6 diffs with exactly the signature
attributed to our port: `lowest observed m/z=300.290854986054` vs `...966788`, `max_rel=2.03e-10`.

**But this does not dissolve the gap.** C# compared against BOTH cpp variants gives 2713 either
way, so we are not simply matching one of cpp's two answers - on individual spectra we sometimes
agree with one variant, but the file-level disagreement stands. The honest statement is: the
Agilent profile precision difference is real and still unexplained, cpp's own output wobbles by a
few counts run to run, and **any measured diff count for these files carries that noise band**.
Do not read a ±30 movement on them as a regression.

**Two methodology traps this cost.** First, an initial determinism test compared outputs written
to DIFFERENT `-o` directories and read the hash mismatch as nondeterminism - C# embeds the full
command line, including `-o`, in its `command-line parameters` cvParam, so the hashes must differ.
(cpp does not embed it, which is itself an unrecorded difference the comparator ignores.) Use the
SAME output directory, or compare semantically. Second, this whole class is invisible to status
columns: `Neg_MS_002.d` was `differs` before and after, so the transition analysis showed nothing.
It surfaced only by following `cs_surplus.py`'s largest category back to a file.

### Verification

`pwiz-sharp/build.bat Release --i-agree-to-the-vendor-licenses`: build succeeded, **every test
project green except the two known externals** - `UNIFI.Tests` 43/44 on a LIVE
`democonnect.waters.com` call (this time a 400 whose body is again
`ORA-04031: unable to allocate ... shared memory`; it fails identically on builds predating these
changes) and `Installer.Tests` 1 pass / 1 skip (`Install_PerMachine_...` needs elevation).

Agilent 16/16 and Bruker 15/15, each one higher than before - the two new tests:

- `AgilentPeakFilterTests.PeakFilter_SuppliedExactlyWhenAskingTheSdkToCentroid`
- `BrukerInstrumentFamilyTests.InstrumentFamilyCode_MapsIdenticallyForEveryContainerFormat`

Both run without a vendor SDK or a data file, which is the point: neither bug was reachable by
the reference-mzML harness. Also green: Analysis 175, BiblioSpec 142, MsData 85, Common 58, Util
36, **Waters 21**, MsConvert 17, Thermo 15, NativeAot 10, Sciex 8, IdentData 7, TraData 6,
MsConvertGUI 3, Mobilion 2, Shimadzu 2, UIMF 2, Bruker.PrmScheduling 1.

Corpus: Agilent + Mobilion, all 57 inputs, **both** configurations - peakPicking 2 improvements
/ 0 regressions, default 1 movement (the cpp-noise one above) / 0 regressions.

**Two builds failed spuriously before this one, both self-inflicted:** a second `build.bat` was
started while the first was still in its test phase, so the new compile overwrote the bin
directories under test (`Analysis.Tests` reported 175/175 passed AND exit 1), and the leftover
processes then held `TestResults\test-stdout\Waters.Tests.log` open, which
`Run-Tests-Parallel.ps1` reports as a bare file-lock error. Never overlap two builds; kill stray
`dotnet`/`testhost` and delete `TestResults\` before re-running.

### An `Installer.Tests` flake, four dead hypotheses, and one real defect found beside it

`Install_PerUser_DeploysAndConvertsVendorFile` failed once with
`Thermo RAW file reports IsError: ...FT-HCD-MSX.raw` (`ThermoRawFile.cs:74-75`, the Thermo SDK's
own flag after `CreateThreadAccessor()`), then passed on the next two runs. Recorded because the
investigation is more useful than the outcome: **every mechanism proposed for it was wrong**, and
the ruled-out list is what stops the next session re-deriving them.

| hypothesis | how it died |
| --- | --- |
| Two processes opening the same `.raw` conflict (`Installer.Tests` and `Thermo.Tests` both use `FT-HCD-MSX.raw`) | **516 conversions, 0 failures** - see the matrix below. Read-only vendor SDK opens coexist fine; the shared fixture is a coincidence |
| A race extracting the vendor SDK into the shared cache | Nothing extracted: the Thermo cache entries carry `.ok` markers dated Aug 3 and May 12 |
| A per-machine cache root pointing at an incomplete shared cache | No `%PROGRAMDATA%\ProteoWizard\vendor-cache-root.txt`; the populated per-user cache is in use |
| The fixture is damaged | Converts standalone, exit 0, 28 KB mzML |
| A regression from this session's changes | No Thermo code touched; `Thermo.Tests` 15/15 green in the very run that failed |

**Reproduction matrix - 516 conversions of the same fixture, zero failures:**

| shape | exe | result |
| --- | --- | --- |
| 8 concurrent | build output (SDK app-local) | 0 failures |
| 8 concurrent | staged install (SDK from cache) | 0 failures |
| 100 concurrent | staged install | 0 failures, peak 67 live |
| **100 iterations x 4 concurrent** | staged install | **0 failures**, 49 s |

The two exe shapes matter and were nearly missed: the staged install has vendor SDKs **stripped**
(only `Pwiz.Vendor.Thermo.dll` ships; `ThermoFisher.CommonCore.*` load from the cache via
`VendorSdkLoader`), while the build output carries them app-local. The first reproduction used the
build output and therefore never exercised the failing configuration at all.

**The sample size settles more than "no failures".** The installer test failed 1 run in 3. If the
trigger were present in the standalone reproduction, 400 conversions should have produced well
over a hundred failures. Zero means the trigger is not concurrency and not repetition - it is
something about the installer test's own context. The one difference never reproduced: the test
runs the real Inno Setup installer `/VERYSILENT`, executes an `msconvert.exe` written to disk
seconds earlier, then uninstalls; every reproduction reused the long-lived
`installer/build/stage/` copy instead. Getting a real failure rate means looping
install -> convert -> uninstall, not run because it repeatedly installs software on the machine.

**Determinism, measured on the way past:** with fixed-width output slots reused across all 100
iterations, each slot produced a byte-identical mzML every time (4 distinct hashes, one per slot,
x100 each). msconvert-sharp's Thermo path is deterministic. Note the 4 hashes are the `-o` path
again - equal LENGTH is not enough, the path text itself is embedded.

**Status: unexplained.** Not a regression - 516 clean conversions plus a passing re-run - but the
mechanism is unknown, and both mechanisms asserted earlier are withdrawn.

**The defect found while looking, unrelated to the flake:**
`VendorSdkLoader.EnsureExtracted` is not safe across processes. It guards on a `.ok` marker
*inside* the destination, extracts **in place** into that final directory, and writes the marker
only afterwards - with no cross-process lock:

```csharp
string marker = Path.Combine(dest, ".ok");
if (!File.Exists(marker))
{
    Directory.CreateDirectory(dest);
    DownloadIfMissing(entry, archivePath);   // shared archive path in the same root
    ExtractArchive(archivePath, dest);       // in place
    File.WriteAllText(marker, ...);          // completion recorded last
}
```

Two processes that both miss the marker extract into the same directory simultaneously, and a
killed extraction leaves a partial directory that still reads as "not done". Harmless on this
machine because every SDK was cached weeks ago; on a **cold cache with a parallel test run** it is
a real hazard. The fix shape is the one already used for the download a few lines below - extract
to a temp sibling and `Directory.Move` it into place, which is atomic on one volume.

**Two measurement traps re-confirmed here**, both of which produced a wrong conclusion before
being caught:

- **Never diff msconvert-sharp outputs written to different `-o` directories.** C# embeds the full
  command line, including `-o`, in its `command-line parameters` cvParam, so byte sizes and hashes
  differ by path length alone. The 100-run produced three distinct mzML sizes - 28057 x9, 28058
  x90, 28059 x1 - matching `o1`-`o9`, `o10`-`o99`, `o100` exactly. It looks like nondeterminism
  and is not. (cpp does NOT embed the path, so this asymmetry only bites the C# side; the
  comparator ignores the param, so sweeps never show it.)
- **Read a log's freshness before reading its contents.** A "it failed again" conclusion came from
  grepping `TestResults\test-stdout\Installer.Tests.log` before the new run had overwritten the
  previous run's copy.

### Still open

1. Sciex TIC 10x - unchanged, still the cleanest unexplained diff.
2. Agilent profile m/z precision (~1.9e-10) on 3 files, now known to sit on top of cpp-side
   run-to-run instability.
3. **New**: Mobilion `...NISTmAbOxidized[1].d` emits `MS:1000527 highest observed m/z` on 278 of
   6141 spectra where cpp emits none. C#-side surplus; inventory it per the standing directive.
4. cpp `Baf2Sql.cpp` `case 9` needs a C++ build to verify, and the cpp-side IMS zero-sample fix
   is still outstanding from 2026-08-20.
5. The UNIFI client reporting an Oracle-OOM 500 as an authentication error.

## 2026-08-28: Retargeted the whole tree to .NET 10, dropped net472, cleared every CVE

Seven commits landed on `Skyline/work/20260612_net8_port` (also mirrored to
`chambem2/pwiz-sharp` per the standing directive):

| commit | what |
| --- | --- |
| `b882847f21` | net8 -> net10 across Skyline + pwiz-sharp (147 files) |
| `5c5bed5fd4` | Linux agents install the pinned SDK when the image lacks it |
| `4cd1e0b21d` | third-party C++ warnings silenced in Release, kept in Debug |
| `b53aa3bd63` | .NET Framework leg removed entirely (124 files, -1437 lines) |
| `5e8919f2a4` | Native AOT publish fixed (IL2091) |
| `bb07b808da` | DotNetZip -> PROdotnetzip |
| `e7288cc495` | remaining package advisories cleared |
| `81955b29b3` | merge of master into the branch (someone else's merge, integrated) |
| `df188772e9` | removed a UTF-8 BOM this work introduced |

### The retarget was much larger than the 2026-08-20 handoff estimated

That handoff said "14 files, mostly SDK policy noise". It had scoped pwiz-sharp
only. Skyline takes ProjectReferences on pwiz-sharp and a net8 consumer cannot
reference a net10 assembly (CS1705, no downgrade path), so both legs had to move
together: **122 files / 307 occurrences** mechanical, plus 18 files of deliberate
edits. Four blockers it never found, none of which a TFM sweep can reach:

1. **Skyline has the same BinaryFormatter problem as Shimadzu.**
   `EnableUnsafeBinaryFormatterSerialization` is inert on net9+; `RemoteBase.cs`
   still calls `new BinaryFormatter()` for the legacy tool IPC. Compiles fine,
   throws only at runtime. The switch is a `RuntimeHostConfigurationOption`, so
   setting it on a *library* does nothing - it now lives in
   `pwiz-sharp/Directory.Build.targets` conditioned on `OutputType`, because
   transitive collection proved unreliable (msconvert picked it up, BlibBuild did
   not, despite a direct ProjectReference).
2. **`Stage-Tests.ps1` bundled a private runtime chosen by `$RuntimeMajorMinor = '8.0'`** -
   a bare version string with no `net8.0` token. The Docker workers have no .NET
   at all and reach it via `DOTNET_ROOT`, so every shell-out test died with
   "You must install or update .NET".
3. **WFO1000 is 785 sites, not 3, and ships at Error severity** - so
   `WarningsNotAsErrors` cannot demote it. Needs an `.editorconfig` override in
   *both* configs, since `pwiz-sharp/.editorconfig` is `root = true` and does not
   govern the ZedGraph sources under `pwiz_tools/`. **Deferred to master** by
   decision; the demotion currently in the branch is load-bearing (without it
   neither solution builds) and its comment is factually wrong about where the
   rule fires - fix the comment when the real work happens.
4. **`SkylineAiConnector.zip` is a checked-in binary** whose runtime a source
   retarget cannot touch. Regenerating it exposed that the tool could not stamp
   its own version at all: `Generate*VersionAttribute` were `false`, so no
   `-p:Version=` could take effect (verified), and `BuildMcpServer` never
   forwarded the computed version. Both now fixed; `EXPECTED_ZIP_VERSION` must be
   bumped in lockstep with any future ZIP rebuild.

### net472 is gone

67 projects, 93 `#if NET472` blocks across 47 files, 47 conditioned project
elements. Nothing built it: `build.bat` builds an explicit list with
`-f net10.0-windows`, and two of its projects could not compile at all
(BiblioSpec calls `OperatingSystem.IsWindows`, absent from .NET Framework;
ProteowizardWrapper needs `pwiz_data_cli.dll`, a bjam product not in the
checkout). `dotnet build Skyline.sln` went from **178 errors to 0**, so the
solution now opens cleanly in Visual Studio.

Two things that changed meaning rather than vanishing:

- Osprey's vendor-reader capability is now unconditionally off. It required
  `pwiz_data_cli`, which only ever existed for net472, so the property could
  never have been true on net10 - the code now says so plainly.
- `AdvancedEditingCommands` and `ToolServiceTestHarness` were still net7.0-windows
  and ProjectReference SkylineTool; with SkylineTool net10-only they would fail
  restore (NU1201), so both were bumped.

The legacy `BullseyeSharp.csproj` was removed from `Skyline.sln`. It is a
**non-SDK project using `<TargetFrameworkVersion>v4.7.2</TargetFrameworkVersion>`**,
which is why a `TargetFrameworks` search never saw it. Nothing ProjectReferences
it and Skyline shells out to pwiz-sharp's managed `bullseye-sharp.exe` instead.
The directory is still on disk - deleting it is a separate call.

### Both solutions are now CVE-clean

| package | severity | resolution |
| --- | --- | --- |
| `System.Drawing.Common` 4.7.0 | Critical | fell out with DotNetZip |
| `DotNetZip` 1.16.0 | High | -> PROdotnetzip 1.20.0 |
| `Snappier` 1.1.6 | High | pinned 1.3.1 |
| `Cryptography.Pkcs` 6.0.1 | High | ServiceModel -> 8.1.2 |
| `Cryptography.Xml` 8.0.2 | High | pinned 8.0.4 |
| `log4net` 2.0.17 | Moderate | -> 3.4.0 |

Three traps worth keeping:

- **DotNetZip is deprecated with no fixed version** - 1.16.0 is both the
  vulnerable release and the last one. PROdotnetzip is a maintained fork with the
  same `Ionic.*` namespaces (verified by reflection), so **no C# changed**. Its
  deflate output was compared byte-for-byte against DotNetZip across 4 payloads x
  3 levels because Osprey's `.blib` blobs must stay byte-identical to Skyline's
  BlibData writer and Rust osprey's `flate2`. Identical. The assembly *filename*
  changes, so the hand-maintained manifests in `SkylineNightlyShim` and
  `CreateZipInstallerWindow` had to move with it.
- **Only Snappier 1.3.1 is clean** - 1.2.0 and 1.3.0 still carry the advisory,
  and NuGet resolves a range to its LOWEST match, so bumping IronCompress alone
  would have looked right and fixed nothing.
- **The first ServiceModel fix traded one High for another.** 8.1.2 fixes Pkcs but
  pulls `Cryptography.Xml 8.0.2`, itself vulnerable (8.0.0-8.0.3 all are). Only
  caught by re-scanning after each change rather than at the end.

`NuGetAuditMode=direct` is required (the .NET 9+ `all` default fails RESTORE under
`TreatWarningsAsErrors`) but hides transitive advisories - `--include-transitive`
is mandatory when auditing this tree.

### Native AOT: IL2091 (`5e8919f2a4`)

`ProteoWizard_CoreWindowsNet` failed with all tests passing and exit 1. .NET 10
annotates `Marshal.PtrToStructure<T>` with `DynamicallyAccessedMembers`;
`Mz5SpectrumList.ReadHvlArray<T>` forwarded its own `T` without the same
annotation, so ILC refused it. Only the AOT leg catches this - the managed build
and the whole suite are unaffected. Confirmed deterministic before fixing:
identical failure on two agents with two ILCompiler versions (10.0.8 and 10.0.3).

### Still open: the net10 GDI+ failures on the MacCoss agent

**This is the one unresolved item and the most important thing to hand over.**

Twelve tests fail on `MacCoss TeamCity Agent 1` only. They look unrelated but are
**one defect** - unwrapping the `ThreadExceptionDialog` messages, all of them
carry an identical inner stack:

```
ExternalException (0x80004005): A generic error occurred in GDI+.
  Graphics.FillRectangle(Brush, Rectangle)
  SplitContainer.RepaintSplitterRect()
  SplitContainer.ResizeSplitContainer()
  SplitContainer.OnLayout(...)      <- Form.WmShowWindow -> OnVisibleChanged
```

The failing tests map onto the four Skyline dialogs that contain a
`SplitContainer`: `EditIrtCalcDlg` (the six `Irt*` plus `TestAddIrtStandards`),
`ViewLibraryDlg` (`TestAddLibrary`, `TestAddMixedLibrary`),
`AddModificationsDlg` (`TestAddAllPeptidesWithModifications`).

**It is a real net10 regression, not a bad agent**: the same machine PASSED this
configuration on net8 (build #165, whose `Skyline.csproj` reads
`net8.0-windows` - verified). The AWS agents never produce a GDI+ error on either
framework, which is why the failing set looked like it was moving around.

**Twelve hypotheses tested and eliminated, each by measurement, not argument:**

| tested | result |
| --- | --- |
| offscreen coordinates, to (-100000,-100000) | no failure |
| degenerate splitter rects (0x0, negative w/h) | GDI+ accepts them |
| disposed brush | raises `ArgumentException`, not `ExternalException` |
| runtime 10.0.8 (the agent's) vs 10.0.11 | byte-identical |
| SDK 10.0.204 vs 10.0.400 | identical |
| monitor count (1 vs 2) | no failure |
| per-process GDI/USER exhaustion | peaks at 164 against a 10000 limit |
| test ordering (full sequential 1168-test run) | no failure |
| console vs remote session | no failure |
| **agent display layout** (via the new diagnostic) | **structurally identical to a dev box** |
| **WinForms default DPI awareness, net8 vs net10** | **both `UNAWARE`, identical** |
| session/desktop-heap exhaustion | disproved: failures are deterministic |

The display-layout diagnostic added in `3651dd669b` (log-only, beside the
existing session diagnostic) reported from the agent:

```
# Screen: \\.\DISPLAY2 bounds={X=0,Y=0,Width=1920,Height=1080} PRIMARY
# Screen: \\.\DISPLAY1 bounds={X=1920,Y=0,Width=1280,Height=1024}
# Offscreen point: {X=-1920,Y=-1080}
```

Nothing pathological: secondary to the right, `min origin = (0,0)`, offscreen
point exactly `-primarySize` - the same shape as a dev box that passes. That
killed the `GetOffscreenPoint()` theory, which had been the leading one.

**A correction worth recording**: an earlier read claimed Skyline declares system
DPI awareness via `<dpiAware>true</dpiAware>`. It does **not** - that line is
inside a `<!-- -->` block in all three manifests (Skyline, TestRunner,
SkylineTester) and has been commented since it was added in 2020. Skyline sets no
`HighDpiMode`, calls no `ApplicationConfiguration.Initialize()`, and emits no DPI
switch into its runtimeconfig; awareness is purely the framework default, which a
probe showed is `UNAWARE` on **both** net8 and net10.

**Failure counts are deterministic**, which rules out resource drift:

| build | commit | failures |
| --- | --- | --- |
| #174 | `e7288cc495` pre-merge | 7 |
| #178 | `81955b29b3` post-merge | 12 |
| #182 | `df188772e9` post-merge | 12, identical set |

The 7 -> 12 jump tracks the **master merge**, not session state - it widened
exposure to the same bug (the merge carried test-infrastructure changes #4617,
#4618, #4623). #178 and #182 are byte-identical in outcome: 980 tests run, 37
GDI+ errors, same 12 failures.

**Two loose threads for whoever picks this up:**

1. Every post-merge build runs **980 of 1796 tests** - a third of the suite does
   not execute, stably. Nobody has explained that yet; it may be the same defect
   truncating the run.
2. The next diagnostic would be to log the splitter rect and control state at the
   moment `RepaintSplitterRect` throws, since the trigger is not reproducible off
   that agent. That is a real change to shared test infrastructure and was left
   for a decision rather than pushed.

### Other pre-existing failures, confirmed NOT ours

- `GMDLoadLibrary` / `TestInvalidPeptidesInLibrary` fail on the **AWS** agents
  only. Not reproducible locally in six configurations (isolation, full
  `Test.dll`, parallel 1168, sequential 1168, and both on runtime 10.0.8).
  `TestInvalidPeptidesInLibrary` expects a library with 3 entries and sees 2 -
  the signature of stale externally-provisioned test data, the same class as the
  0-byte BiblioSpec inputs found on this dev box.
- `ThermoCancelImportTest-fr` fails on other people's PRs too.
- BiblioSpec `Tiny_V2_Msf` / `Tiny_V2_Filtered_PdResult` fail locally because
  `pwiz_tools/BiblioSpec/tests/inputs/tiny-v2.msf` and `tiny-v2-filtered.pdResult`
  are **0 bytes** on this machine. That directory is gitignored - externally
  provisioned data that arrived as empty stubs. Cannot pass on any framework.
- `TestAlphaPeptDeepBuildLibrary` was a pip-install hang; fixed upstream by #4624.

### Deliberately not done

- **WFO1000** (785 sites) - deferred to master by decision.
- **The staging rename's prose**: ~48 `net8` mentions remain in comments in
  `build.bat`, `tc-perftests.bat`, `SkylineTesterWindow.cs`, `TestRunner/Program.cs`
  and `SkylineTester.csproj`, plus the version-stamping identifiers
  `StampNet8InformationalVersion` and `Net8Version.g.cs`. Different concept from
  staging, left alone.
- **~26 `net8`-vs-net472 prose comments** in `.cs` files describe behavior
  *measured* on those frameworks; rewriting them to "net10" would assert
  something nobody has measured.
- The `pwiz-ai` scripts needed a companion commit (`47847c0` on that repo) -
  their TFM detection is now regex-based rather than a literal `net8.0`, and both
  staging blocks were changed from fail-open to fail-loud.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260612_net8_port.md` before starting work.

## 2026-08-29: The GDI+ failures root-caused and fixed - a .NET 9 regression, not .NET 10

`40fd787ff5` on `Skyline/work/20260612_net8_port` (mirrored to `chambem2/pwiz-sharp`).
Diagnosed on TCA1, where it reproduces; it does not reproduce on any dev box or AWS agent.

**Two corrections to the 2026-08-28 entry and to commit `3651dd669b`:**

1. **The regression is .NET 9, not .NET 10.** A minimal repro fails identically on
   net9 and net10 and passes on net8. Every statement in the previous entry framing
   this as "net10-only" is wrong about the framework boundary, though right that net8
   passed.
2. **The display layout is not the cause.** It reproduces at (100,100), fully on the
   primary screen, and at every coordinate swept. `3651dd669b`'s own logging is what
   disproved the hypothesis it was added to test - which is the outcome that diagnostic
   was for, so it did its job.

### Root cause: one defect behind all twelve failures and the crash

`SplitContainer.ResizeSplitContainer` -> `RepaintSplitterRect` calls
`Graphics.FillRectangle` from `OnLayout`, which `Form.Show()` reaches via
`OnVisibleChanged` while the window is still handling `WM_SHOWWINDOW`. There
`IsWindowVisible` is false and the window DC's clip region is NULLREGION, so the fill
genuinely fails at the GDI level. **.NET 8 ignored that GDI+ status; .NET 9 began
throwing `ExternalException`.**

The cascade explains the crash and the truncation together: exception ->
`ThreadExceptionDialog` per test -> the dialog storm force-closes forms mid-teardown ->
a `TreeView` handle destroyed inside its own `WndProc` -> `0xC0000005` -> TestRunner
dies at test 2.288. **That is the answer to the "980 of 1796" loose thread from the
previous entry** - the run was not being truncated by a separate defect, it was being
killed by this one.

Fixed upstream by dotnet/winforms#14565, milestone .NET 11 preview7. No net9/net10
backport, so Skyline works around it.

### The three changes

| file | change |
| --- | --- |
| `Program.cs` | `ThreadExceptionEventHandler` ignores this exception via new `IsBenignSplitterRepaintFailure()` - `ExternalException` whose stack contains `RepaintSplitterRect` |
| `Program.cs` | `Init()` re-attaches the `ThreadException` handler on **every** call, not once under the `_initialized` guard |
| `AvailableFieldsTree.cs` | `OnDrawNode` catches `ExternalException` - the same empty-clip failure in Skyline's own TreeView custom draw, which surfaced only once the process stopped crashing |

**Why the handler re-attach matters, and why it is broader than the GDI+ filter.**
WinForms drops the `ThreadException` subscription when a message loop ends, and a
functional run calls `Application.Run` once per test. Subscribing once meant only the
**first** test in a run routed UI-thread exceptions to the handler; every later test got
WinForms' default dialog. Verified in isolation: three successive `Application.Run`
calls on one thread fire the handler only on the first; with the re-subscribe, all
three. Without it, the GDI+ filter fixed only the first test.

This also fixes the escape already documented at `TestFunctional.cs:3113`. Reviewed
for blast radius before landing, and it **cannot turn a passing test into a failing
one**: both paths that can observe such a dialog (`HangDetection.cs:244` and the
teardown at `TestFunctional.cs:3113`) already call `AddTestException`, and the dialog is
modal on the UI thread, so no test could ever run to completion past one. What changes
is *which* exception is recorded - the real one instead of a wrapper saying a dialog
appeared - and that the storm and its timeout cost are gone.

Also confirmed while reviewing: `Init()` and `Main()` both run on the **main** thread
(`TestFunctional.cs:2421`/`2431`; the test logic runs on a separate `WaitForSkyline`
thread), so the re-subscribe binds to the thread that actually runs `Application.Run`.
`Program.Main` calls `Init()` a second time (`Program.cs:242`), which is why the `-=`
before the `+=` is load-bearing rather than decorative. The two tests that touch this
machinery are unaffected: `ReportErrorDlgTest` calls `Program.ReportException` directly
with `TestExceptions` nulled, and `UnattendedDialogTimeoutTest` removes an exception
recorded through the watchdog path - whose own comment independently describes this
same defect.

### Three deliberate differences from what was verified on TCA1

- The benign path **logs** (`Messages.WriteAsyncDebugMessage`) rather than returning
  silently, so a future real regression in this area is not invisible. It is
  `Trace.TraceInformation` underneath; 37 lines a run costs nothing.
- A `StackTrace != null` guard, and the literal is verbatim `@"RepaintSplitterRect"`
  per the non-localized-string convention, so `CodeInspectionTest` stays quiet.
- Both sites cite dotnet/winforms#14565 and cross-reference each other, with a note to
  remove the pair once Skyline targets a runtime carrying the fix.

**Matching on the stack rather than per-dialog is what makes it complete**: 25 forms in
the tree contain a `SplitContainer`, not the 3 the failing set happened to expose.

### Verification

- On TCA1: all 13 affected tests pass, exit code 0 (the 12 from build #182 plus
  `TestAlphabeticalReportEditor`, the crasher).
- Here: `Skyline.sln` builds with **0 errors**; a full parallel run put **1164 tests**
  through with **all 13 passing**, no truncation and no access violation. Its only
  failures are the eight `TestArdia*` / `TestUnifi*` / `TestWatersConnectListContents`
  tests that need live credentials and already fail on this box.

### Still open

- **Why TCA1 and not the AWS agents or dev boxes.** Untouched by the fix - the
  workaround is unconditional. The leading suspect is that TCA1 has two heterogeneous
  display adapters (a Virtual Display Driver as primary 1920x1080 plus a Matrox G200eW3
  BMC adapter at 1280x1024). A standalone 40-line reproducer (bare Form +
  SplitContainer, no Skyline code, builds for net8/net9/net10, exit 0 = OK) is on TCA1
  under `gdirepro/` with a RUNME.md. Running it on a dev box and an AWS agent settles it
  in a minute: if net9/net10 pass there, the variable is the display environment, not
  the framework.
- **The full suite has not run on TCA1 since the fix.** Build #182 died at 2.288, so 816
  tests never ran there and may hide further instances of the same pattern - any
  `FillRectangle` reachable from a paint or layout path on a not-yet-visible control.
  Those will now fail loudly rather than crash the run. Candidate sites, from a sweep of
  custom-draw paths: `TreeViewMS.cs:354` `OnPaint` (base of `SequenceTree`, and used by
  `ViewLibraryDlg` - highest traffic), `SrmTreeNode.cs:214,216`,
  `ViewLibraryDlg.cs:1431`, `FindResultsForm.cs:172`,
  `StatementCompletionForm.cs:124,134`, and lower-traffic `CustomTip.cs`,
  `EditNoteDlg.cs`, `StripePainter.cs`, `Dendrogram{Control,Scale}.cs`.

## 2026-08-31: Core Linux .NET - a guard that measured a different directory than the build

`ProteoWizard_CoreLinuxNet` was red on five builds (#143/#144/#147/#148/#154, all `pull/4587`),
every one with the same signature and **no failed tests** - it died at Step 2/5:

```
Requested SDK version: 10.0.100
global.json file: .../pwiz-sharp/global.json     <- NESTED, not the repo root
Installed SDKs: 8.0.423
```

### Finding it at all: the TeamCity branch locator hides builds

`search_builds(build_type_id, branch="pull/4619")` returned 14 consecutive SUCCESS and the PR's
own checks were all green, which led to reporting the config as healthy. **It was not** - the
newest build overall was failing. Only `branch="default:any"` shows builds across branches;
`branch=master` and a bare branch name both return "No builds found" for this config. The
give-away was already visible and missed: the build numbers on `pull/4619` skip (132-134,
142-144, 147-148), and a gap in build numbers means builds on other locators.

### Root cause

Both Linux entry points `cd "$SCRIPT_DIR"` (pwiz-sharp) and then did:

```bash
ensure_dotnet_sdk "$SCRIPT_DIR/.."                    # guard probes the repo ROOT
dotnet --version || fail "dotnet --version failed"    # guarded command runs in pwiz-sharp/
```

`global.json` resolution walks **up**, so probing a PARENT cannot see a pin sitting below it.
With the pin at `pwiz-sharp/global.json`, nothing governed the root, `dotnet` returned the
newest installed SDK (8.0.423), and the guard reported **satisfied** - then the very next line
died on the 10.0.100 pin the guard never looked at. A guard and the command it guards have to
run in the same directory or the guard is measuring something else.

### Fix (`f436051512`) - two halves, both required

- `ensure_dotnet_sdk` now takes *the directory the build runs in*; callers pass `$SCRIPT_DIR`,
  not `$SCRIPT_DIR/..`. This is what fixes the nested-pin layout.
- `pwiz_required_sdk_channel` resolves `global.json` by walking up, as dotnet does, instead of
  reading one fixed path. This is what keeps the root-pin layout working under the new contract.

Renaming the parameter `repo_root` -> `governed_dir` initially left two stale `$repo_root`
references in the post-install verification, which under `set -u` is an unbound-variable error.
Caught by grepping the whole function after the rename, not by reading the diff.

### Verification

| check | result |
| --- | --- |
| new `scripts/test-ensure-dotnet.sh`, 7 cases | green on the fix, **red on the original** |
| stub-`dotnet` repro of the CI bug | old contract reports SATISFIED; new contract detects |
| root-pin layout (4619) under the new contract | detected - no regression |
| real WSL run, no matching SDK | detected -> downloaded -> installed -> post-install check passed |
| real WSL run, repo + 10.0 pin | guard satisfied AND `dotnet --version` -> 10.0.400; they agree |

The test is wired into `tcbuild.sh` (sub-second, no network, optional-if-absent like `clean.sh`)
because a guard nobody runs is the same defect over again.

**A measurement trap worth remembering:** an early "real" end-to-end run reported `need .NET 8.0`
against a tree pinned to 10.0.100, which looked like a resolver bug. It was quoting - Git Bash
expanded `$PWD` before handing the command to WSL, so the probe ran against
`C:\dev\pwiz-msconvert-pr` (whose global.json still pins 8.0.100). When crossing Git Bash -> WSL,
put the script in a file; nested `$(...)`/`$PWD` inside `wsl bash -c "..."` is not worth debugging.

### The two global.json layouts were both deliberate, and are now one

The first diagnosis - "4587 was cut before the retarget" - was **wrong**. 4587 is *downstream* of
4619, and `2cb66ee39d` (brendanx67, 08-21) deliberately moved `global.json` to `pwiz-sharp/`:
back then the root pin was **8.0.100**, which capped the whole repo at the 8.0.4xx band and so at
**C# 12**, breaking Osprey's publish (`PickLdaModel.cs` binds `SequenceEqual` to
`MemoryExtensions`, C# 14 only). Moving it let the root float to 10.0.400.

`b882847f21` then retargeted that pin to **10.0.100**, which inverts the argument: a root pin now
*grants* C# 14 instead of capping it. So the split was obsolete, and `6949d389` moves the pin back
to the root on 4587. Checked first, as asked: the two files were **byte-identical** (the original
move was recorded `R100`, a pure rename), and `global.json` cannot pin a language version at all -
it pins the SDK, and the SDK decides what `LangVersion=latest` resolves to. Osprey and pwiz-sharp
both use `latest`; pwiz-sharp is `net10.0` on both branches, so Brendan's "target framework stays
net8.0" premise is also spent.

**Deleting the file outright would have been wrong** - that leaves the tree with no pin, so the
root floats to whatever SDK the agent has, which is C# 12 on an 8.x-only agent and reintroduces
exactly the Osprey breakage. Moving it back to the root removes the separate file *and* makes the
band deterministic.

**Worth being honest about:** with the pin back at the root, 4587's Linux build would pass even
without `f436051512`, since the guard probes the root and finds it there. The guard fix is not
load-bearing for this symptom; it is what stops the next layout divergence failing silently
instead of loudly, which is what turned one bad assumption into five red builds.

### Method notes

- Update a PR from its base with `gh api -X PUT repos/<r>/pulls/<n>/update-branch`, not a local
  worktree - pwiz is far too large to check out for a one-commit merge. The call is async: re-fetch
  and confirm with `git merge-base --is-ancestor`.
- A rename can be committed without any checkout at all via the Git Data API (create tree with
  `base_tree` + the new path + the old path with `"sha": null`, create commit, PATCH the ref).
  GitHub reported the result as a single `renamed` file.

## 2026-09-03: dotCover CI fix, NHibernate leak (already fixed upstream), and an IdentityModel 7 backport to master

### dotCover coverage tab (`7457371f59`, pushed)

Both Core and Osprey Windows .NET builds ended coverage runs with "No available .NET Coverage
report generator for type 'dotcover'" - moving TeamCity build steps into the build scripts
removed the "Install dotCover (.NET)" step's provisioning but not the dependency: TeamCity's own
coverage-report generator needs a dotCover of its own, previously supplied by that step.
`Ensure-DotCover.ps1` now emits `##teamcity[dotNetCoverage dotcover_home=...]` pointing at the
copy it just restored. That home needs `dotCover.exe`, which the 2026.1 console runner no longer
ships (managed-only `dotCover.dll`, no HTML report type) - Osprey moved from 2026.1.1 to the
2023.3.3 that Core/Skyline already use. Verified end to end on AWS agents that have no bundled
dotCover (the case that was failing): Osprey #558, Core #381, both green with the coverage tab
populated (Core: 78.08% statement coverage).

### NHibernate session-factory leak - investigated, found already fixed by #4629

Root-caused the SerializeIonMobilityTest/TestFilesTreeForm/TestCrosslinkIms pass-1 leaks:
undisposed NHibernate `ISessionFactory` objects rooted forever by the static
`SessionFactoryObjectFactory.Instances` dictionary (IonMobilityDb/OptimizationDb dropped their
disposing `using` when NHibernate 5.5 started throwing ObjectDisposedException on a later
OpenSession call). Independently confirmed via dotnet-dump (540 live factories against 10 live
IonMobilityDb objects) before discovering Brendan had already fixed it in `5c046bdb7a` (#4629,
landed mid-investigation) with the same fix shape. Re-measured on the corrected head:
SerializeIonMobilityTest/TestFilesTreeForm/TestCrosslinkIms all clean now; FileTypeTest
(~29 KB/run) and TestGroupedStudies1Tutorial (native heap, +933 KB/run) are NOT fixed by #4629
and remain open.

Full investigation (method, dead ends, the `build.bat --no-tests` staging trap that produced two
wrong conclusions along the way) is in
`ai/todos/active/TODO-20260902_net10_nhibernate_factory_leak.md` - keep that file for the method
notes even though the headline leak is fixed.

### build.bat: build all test projects, add pass-1 leak detection (uncommitted)

- `build.bat` was building only 5 of 7 test projects (TestPerf/TestTutorial excluded from
  compilation, but `Stage-Tests.ps1` stages them regardless, so a `--no-tests` build silently
  left stale binaries in the staged test run). Now builds all 7.
- Fixed the `--no-tests` doc comment, which claimed "Build and stage" when it actually returns
  *before* the staging step - this exact gap produced two separate wrong conclusions during the
  IdentityModel-7 work below before I found it (see that TODO's "staging trap" note).
- Added the pass-1 leak-detection subset: SerializeIonMobilityTest, TestFilesTreeForm,
  TestCrosslinkIms, TestGroupedStudies1Tutorial, FileTypeTest, IrtDocumentFunctionalTest
  alongside the original four. Confirmed under `buildcheck=1` a leak now genuinely aborts the
  build - an earlier claim in the leak TODO that leaks were purely informational was wrong and
  has been corrected there.
- **Uncommitted** in `C:\dev\pwiz-net8`.

### VCS smart-build trigger: stale RemoteApi path (uncommitted, cherry-picked from #4632)

`scripts/misc/vcs_trigger_and_paths_config.py` still routed on
`pwiz_tools/Skyline/Model/Results/RemoteApi/.*`, which stopped matching anything when #3170
moved that tree to `pwiz_tools/Shared/CommonMsData/RemoteApi/.*` in June 2025 - so changes to
WatersConnectAccount/UnifiAccount/ArdiaAccount weren't triggering TestConnected/Container CI on
either master or this branch. Cherry-picked `48dff2020d` (a clean, standalone commit on #4632's
branch) onto both. **Uncommitted** in both `C:\dev\pwiz-net8` and `C:\dev\pwiz-im7`.

### PR #4619 (this branch -> master): still CONFLICTING, merge not done

Master has moved on; #4619 is `CONFLICTING`/`DIRTY`. Six files conflict, centered on master's
#4613 (HttpClientWithProgress) landing against this branch's own waters_connect work. Drafted a
resolution (keep master's HttpClientWithProgress shape; port the three deleted `TokenResponse`
constructors onto IdentityModel 7's `ProtocolResponse.FromHttpResponseAsync`/`FromException`,
no `async`/`Task.Run`). **Not executed** - the branch was moving too fast under active pushes to
risk a merge commit without explicit go-ahead. See the handoff for the concrete conflict list.

### PR #4631 (`Skyline/work/20260901_smallmol_library_load_race`) - closed, not merged

Fixed a real race in `AsSmallMoleculeTestUtil.ConvertToSmallMolecules`: it read
`Libraries.IsLoaded` before the library loader had actually finished, so whichever
`RefineConvertToSmallMolecules*Test` ran first in a process silently skipped library conversion
and then failed comparing against the other test's (library-converted) result. Verified
reproducing on master, fixed, addressed Copilot review feedback, all green. **Closed 2026-09-02
with "Not needed with #4629 fixes."** Worth flagging rather than silently dropping: a later
re-verification (after finding and fixing the `build.bat --no-tests` staging bug above, which had
produced a false "already fixed" reading the first time) showed the race still reproduces on
`5c046bdb7a` without #4631's fix. Not re-litigated further - recording the discrepancy for
whoever picks this up next.

### IdentityModel 7 backport to master - new branch/worktree, substantial progress, not landed

New worktree `C:\dev\pwiz-im7` on branch `Skyline/work/20260902_identitymodel7` (base:
`origin/master`), started to remove the recurring #4619 merge conflict at its root: land
IdentityModel 7 (on top of master's own `HttpClientWithProgress` shape from #4613) on master
directly, so this branch's next merge finds master already compatible instead of refighting the
same six files.

**Full detail in the new `ai/todos/active/TODO-20260902_identitymodel7_master_backport.md`** -
this is substantial, standalone work with its own open questions (a competing PR #4632, a
native-rebuild-or-not decision, one still-open test failure). Read that file before continuing
this thread; don't try to reconstruct it from this summary alone.
## 2026-09-03/04: Managed leak tooling, and the first non-wiff2 leak root-caused and fixed

Two nights of leak checking on this branch. The 13-hour run of 2026-09-03 finished **zero test
failures** across 644 leak-checked tests, with 13 tests reporting leaks. Log archived to
`D:\test\nightly-logs\SkylineTester-20260904-net10-13hr-0failures-leaks.log`.

### The measurement finding: managed is signal, native heap mostly is not

Reproducing each non-wiff2 leaker in isolation (10 tests, 37 min total, median 1.4 min each):
**only 2 of 10 reproduced.** Five of six *heap* leakers did not merely fail to reproduce, they
went strongly negative - `TestSrmSmallMoleculeChromatograms` reported +89.4 KB/run in the nightly
and -522.8 KB/run alone. The managed axis behaved oppositely: every test landed in a tight
3.1-7.6 KB band, and the one real leak reproduced to within 0.7 KB (11.4 -> 12.1).

Confirmed by regressing 100-iteration runs. On the *same runs*, managed gave R2 = 1.00 while heap
gave R2 of 0.00, 0.07 and 0.63. **A real leak is almost perfectly linear**; the wiff2 leak held
0.035 MB/run across 12,000 runs. Variance that happens to trip the gate's 8-run minimum window has
low R2 and a slope whose confidence interval spans zero.

Consequence: `HeapMemory = 20 * KB` in `TestRunner/Program.cs` is set roughly an order of magnitude
below the measured noise floor on that axis, which is why five of seven heap reports evaporated.
Worth either raising it or requiring a heap leak to reproduce twice before being reported -
otherwise every long run keeps producing heap findings that cost an hour each to disprove.

### The 8 KB gate hides real leaks

`TestAddIrtStandards` (5.89 KB/run) and `IrtRedundantDbFunctionalTest` (4.40 KB/run) are perfectly
linear unbounded leaks at R2 = 1.00 that the gate **never reports**, because they sit under the
threshold. They surfaced only because they were pulled in as near-misses. Any test leaking 1-8
KB/run is currently invisible and accumulates just as surely.

### Root cause: SortableBindingList never told the BindingSource to stop

Six tests with "Irt" in the name all leaked managed memory. One cause:

`SortableBindingList<T>` did not implement `IRaiseItemChangedEvents`. `BindingList<T>` answers
**false** there whenever T lacks `INotifyPropertyChanged` - which `DbIrtPeptide` does - and a
BindingSource that gets false calls `PropertyDescriptor.AddValueChanged(item, handler)` for
**every item in the list**. Those subscriptions live in
`ReflectPropertyDescriptor._valueChangedHandlers`, keyed by the item and rooted through
TypeDescriptor's static provider cache. Nothing but an explicit `RemoveValueChanged` releases them:
not disposing the grid, not disposing the BindingSource, not dropping the list. Every row every
one of these dialogs ever bound stayed reachable for the life of the process.

`BindingListView` already answers true here, with a comment describing exactly this behaviour.
`SortableBindingList` simply never got the same treatment.

Measured before -> after, 100 iterations each:

| Test | Before | After |
|---|---|---|
| IrtDocumentFunctionalTest | 12.68 KB/run, R2 = 1.00 | 0.00, R2 = 0.00 (noise) |
| TestAddIrtStandards | 5.89 KB/run, R2 = 1.00 | -0.11, R2 = 0.30 (noise) |
| IrtRedundantDbFunctionalTest | 4.40 KB/run, R2 = 1.00 | -0.01, R2 = 0.03 (noise) |

**Not yet regression tested beyond a smoke run.** `SortableBindingList` is bound by 15 files
including `EditIsolationSchemeDlg`, `EditPeakScoringModelDlg`, `EditOptimizationLibraryDlg`,
`EditRTDlg`, `EditIonMobilityLibraryDlg`, `RenameProteinsDlg`, `ComparePeakPickingDlg`,
`ImportTransitionListErrorDlg`, `SpectrumLibraryInfoDlg` and `BuildLibraryGridView`. The contract
being asserted is that the LIST raises ListChanged for item edits - true where grids edit through
the grid or repopulate wholesale, but a dialog that mutates a bound item's property from code and
expects the grid to refresh itself would now not refresh. **A full functional run is required
before this ships.**

### New tooling: managed leak diagnosis without a GUI

`TestRunnerLib/GcHeapHistogram.cs` (new) captures a per-type histogram of the managed heap after a
full collect and diffs two captures. It pairs with the existing `GcRootReporter`: histogram answers
*what is growing*, root reporter answers *what is holding it*. Driven by an environment variable so
nothing has to be threaded through TestRunner, SkylineTester and the wrapper scripts:

```
SKYLINE_HEAP_HISTOGRAM=<warmup>,<span>[,<topCount>]
SKYLINE_HEAP_HISTOGRAM_ROOTS=<comma-separated type names>   # optional; overrides the automatic pick
```

`GcRootReporter` gained **field names** on every chain link, which is what makes the output
actionable - `_valueChangedHandlers` is a searchable fact, `ConcurrentDictionary` is not. Repeated
links collapse to `Type.field xN` so a walk through a linked list does not consume the length
budget before reaching the object that identifies the leak. Verified against known ground truth on
the wiff2 leak:

```
Timer._timer -> TimerHolder._timer -> TimerQueueTimer._associatedTimerQueue
  -> TimerQueue._longTimers -> TimerQueueTimer._next x10
  -> TimerQueueTimer._timerCallback -> TimerCallback._target -> SampleDataProviderServer
```

**Honest assessment of the tool's first case:** it did not close it. It correctly named the growing
types and produced correct chains, but without field names the chain was easy to misread, and it
manufactured one false lead - a phantom `String` leak that was its own baseline snapshot's key
strings being counted as growth (fixed by interning type names in a pool shared across captures).
dotMemory plus a screenshot from Brendan supplied `_valueChangedHandlers`, and that is what led to
the fix. The field-name and interning work exists so the next case can be closed unaided; that
remains to be demonstrated.

### wiff2 leak: diagnosed, deliberately not fixed

Root cause established: every `MsDataFileImpl` open of a `.wiff2` leaves a
`Clearcore2.RFLight.SampleDataProvider.SampleDataProviderServer` rooted by its own periodic Timer,
~24 KB per open, because `CreateSampleDataApi` is called per file and the SDK exposes no shutdown
(`ISampleDataApi` and `DataApiFactory` are both non-disposable; `CloseFile` closes a file, not the
server). Sharing the api process-wide is what cpp does (`WiffFile2.ipp:64`) and eliminates the leak
- but cpp keeps one reader per FILE while this port keeps one per SAMPLE, so sharing needs ownership
arbitration cpp never needed. A shared-api attempt was **reverted** after a test proved it caused
`ObjectDisposedException: SQLiteConnection` under concurrent readers on one path - silent data loss
in Skyline's 12-way parallel import, worse than the leak. Two regression tests were kept:
`Reader_Sciex_wiff2_SecondReaderSurvivesFirstReaderDispose` and
`Reader_Sciex_wiff2_ConcurrentReadersSurviveChurnOnSamePath` (the latter fails on the shared-api
version, passes on current code). Deferred by decision; four tests still leak 26-36 KB/run from it.

Two pre-existing wiff2 defects were filed rather than fixed: [#4638](https://github.com/ProteoWizard/pwiz/issues/4638)
(retry latch blames AddFramingZeros for any SDK failure) and [#4639](https://github.com/ProteoWizard/pwiz/issues/4639)
(profile data stamped MS_centroid_spectrum after the centroid latch trips).

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260612_net8_port.md` before starting work.
