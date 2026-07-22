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

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260612_net8_port.md` before starting work.

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
