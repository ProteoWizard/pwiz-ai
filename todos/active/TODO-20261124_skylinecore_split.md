# SkylineCore: move all non-UI Skyline code into a plain net10.0 DLL

## Branch Information
- **Checkout**: `I:\git_i\sky_separateui`
- **Branch**: `Skyline/work/20261124_skylinecore_split` (from `origin/master` @ `62b9748240`)
- **Created**: 2026-11-24
- **Status**: In progress - Phase 0 (shared libs) committed locally as `60321a0c1a`, not pushed;
  Phase 1 (SkylineCore) next
- **Module**: `skyline`
- **Supersedes**: T2 and T6 of `ai/todos/backlog/TODO-ui_free_model_phase2.md`
- **Template**: `ai/todos/completed/2026/08/TODO-20260818_commonutil_winforms_split.md`
  (CommonUtil -> CommonBaseUI: move types, KEEP namespaces, pay only in project references)

## Goal

`Skyline(-daily).exe` references both `SkylineCore.dll` (non-UI) and the UI code it keeps;
`SkylineCmd.exe` references `SkylineCore.dll` only and runs on Linux.

## Decisions (Nick, 2026-11-24)

| Question | Decision |
|---|---|
| TFM of the new DLL | **plain `net10.0` from day one** - the compiler is the verifier. Shared libs it needs get split/retargeted first. |
| Layout | **Move files into a new project folder** `pwiz_tools/Skyline/SkylineCore/`, namespaces unchanged |
| Assembly name | **`SkylineCore.dll`** (same in both channels) |

## Measured state (2026-11-24, before any edits)

Skyline .cs files touching WinForms, by folder: Model 1/593, Util 23/70, Properties 6/7,
Controls 173/197, SettingsUI/EditUI/FileUI/ToolsUI/Alerts/Menus nearly all.

Shared projects Skyline references:

| Project | TFM now | WinForms/Drawing files | Needed by core? |
|---|---|---|---|
| CommonUtil | net10.0 | 0 | yes |
| ProteowizardWrapper | net10.0 | 0 | yes |
| BiblioSpec.IO | net10.0 | - | yes |
| CommonMsData | net10.0-windows | **0 of 49** | yes - retarget only |
| BiblioSpecUtil | net10.0-windows | **0 of 4** | yes - retarget (check its refs) |
| ProteomeDb | net10.0-windows | 2 of 21 (`Forms/ProteomeDbForm`) | yes - move the form out |
| PanoramaClient | net10.0-windows | 7 of 12 (3 picker forms) | yes - split pickers out |
| Common | net10.0-windows | **60 of 208** | yes (DataBinding etc.) - real split |
| CommonBaseUI, CommonFileDialogs, MSGraph, ZedGraph | -windows | UI by design | no |
| CarafeSharp.Core/.Proteome, SkylineTool, Bruker.PrmScheduling | TBD | TBD | check |

### Dependency probe (throwaway csproj, not committed)

`ai/.tmp/sessions/20261124-separateui/probeA/probeA.csproj` compiles Model/**, Util/**,
Properties/**, ProtocolBuffers/GeneratedCode, CommandLine.cs, CommandArgs.cs against the built
Release DLLs (WinForms allowed), so errors = what that set needs from Skyline's own UI.
Roslyn reports declaration-level errors only until those are clean, so each pass shows one layer.

- Pass 1 (`winforms-true.log`): 47 errors, all in Util/Properties `using` of UI namespaces
  plus 2 `SkylineWindow` in Model signatures.
- Pass 2 (`pass2.log`, 31 UI-touching Util/Properties files excluded via `exclude.props`):
  122 errors. Missing types: `IPooledStream` 34, `ILongWaitBroker` 17, `IStreamManager` 16,
  `FileSaver` 9, `ConnectionPool`/`Server` 3, `TemporaryDirectory` 2, Settings list classes.
  i.e. the knots are `Util/UtilIO.cs`, `Util/ILongWaitForm.cs`, `Properties/Settings.cs` +
  `*List.cs`, not Model.
- Not yet seen (body layer): `Program.*` from core files (~100 uses, 16 Model files: Log,
  EXIT_CODE_*, UnitTest, ReportException, MainWindow, FunctionalTest, Name, ModeUI, ...);
  `SkylineWindow` in 28 Model files, mostly databinding link actions via
  `SkylineDataSchema.SkylineWindow` plus statics (`FindChromInfo`, `CreateDeleteNodesEntry`,
  `GetViewFile`); `Properties.Resources` (strings needed by core, images are not).

## Plan

### Phase 0 - shared prerequisites (core can only reference plain net10.0) - DONE `60321a0c1a`
- [x] CommonMsData -> net10.0. CA1416 (on for plain TFMs via Directory.Build.targets) flagged
      DPAPI: `CommonTextUtil.Encrypt/DecryptString` now guard `OperatingSystem.IsWindows()` and
      throw PlatformNotSupportedException, instead of [SupportedOSPlatform] which would have
      spread to RemoteAccount -> Settings -> all of core. Windows behavior unchanged.
- [x] BiblioSpecUtil -> net10.0 (no code change)
- [x] ProteomeDb -> net10.0 (`Forms/ProteomeDbForm` was already Compile-Removed)
- [x] PanoramaClient -> net10.0; pickers + folder browser + unused Settings/App.config -> new
      `PanoramaClientUI` (RootNamespace `pwiz.PanoramaClientUI`, forms keep `pwiz.PanoramaClient`)
- [x] Common -> net10.0; UI half -> new `CommonUI` (pwiz.CommonUI.dll, RootNamespace pwiz.Common)
- [x] CarafeSharp.Core/.Proteome and Bruker.PrmScheduling are already net10.0. SkylineTool is
      net10.0-windows without WinForms - check when core needs it.
- [ ] Inventory Windows-only APIs the core keeps using - CA1416 will report these in Phase 1

#### How the Common split was done (reusable for Skyline)
- Moved: `Controls/**`, `DataBinding/Controls/**`, `Graph/**`, `Resources/**` (images + DPI
  icons), and DataBinding `AbstractViewContext`, `IViewContext`, `EventTaskScheduler`,
  `SortableBindingList`, `Filtering/IFilterAutoComplete`, `Internal/BindingListView`,
  `Internal/QueryRequestor`.
- `RowItemValues` stays (Model's CellLocator uses it); its two grid methods became
  `BoundDataGridView.GetRowItemValues(Type)` / `GetSelectedRowItems()` (7 call sites).
- 8 DataBinding.Internal types made public (QueryResults, QueryParameters, IQueryRequest,
  RowSourceWrapper, TransformResults, Abstract/Foreground/BackgroundQuery). NOT
  InternalsVisibleTo: that would expose Common's internal Resources to CommonUI -> CS0436.
- Resources: classified each entry by which tree uses it (scripts in
  `ai/.tmp/sessions/20261124-separateui/`: resx_usage.py, split_resources.py,
  move_resource.py). Common keeps an INTERNAL `pwiz.Common.Properties.Resources` (71 strings);
  CommonUI owns the one PUBLIC class of that name (images + UI strings) so DpiIcons'
  `<ns>.Properties.Resources` discovery still works. PanoramaClient's class stays public
  (Skyline and CommandLineTest use it), so PanoramaClientUI's is
  `pwiz.PanoramaClientUI.Properties.Resources`.
- Gotcha: the usage scan missed a `Resources\n    .Name` split across lines, and strings used
  by Skyline itself. The compiler caught both; re-run classification with that in mind.
- Wiring: CommonUI/PanoramaClientUI references added next to every Common/PanoramaClient
  reference (Skyline, 8 test projects, CommonTest, SkylineBatch + test); both .sln files;
  installer `Product-template.wxs` + `FileList64-template.txt`; CodeInspection scan roots;
  `LocalizedResourcesTest` + `ResourcesTest` sentinels (ResourcesTest's Common sentinel was
  `typeof(ViewEditor)`, which moved - the #4587 silent-drop pattern); SkylineTester Forms tab
  DLL list; IconBuilder `common.manifest` output path.

#### Installer: nothing to do for new assemblies
The .NET 10 installer is Inno Setup (`Executables/Installer/build.ps1` + `Setup.iss`): it
stages the WHOLE Skyline build output (skipping only doc XMLs and non-Windows runtimes) and
packages it recursively, so new DLLs and satellites ship automatically. The WiX
`Product-template.wxs` / `FileList64-template.txt` are read only by the unused net472
`SetupDeployProject` - dead, per Nick "we don't care about wix anymore". Edits to them in
`60321a0c1a` reverted in `040c420294`. Deleting the WiX files is separate cleanup, not this branch.

#### Other
- `LocalizedResourcesTest` never covered pwiz.Common or PanoramaClient until now (now does, passes).

### Phase 1 - SkylineCore project - DONE `62b02cc88b` (local)

Solution, TestTutorial, TestPerf, SkylineTester all build. SkylineCore is plain net10.0 with
CA1416 clean. Moved (git mv): Model/, ProtocolBuffers/ (+ .gitignore paths), CommandLine.cs,
CommandArgs.cs, CommandArgUsage.*, SkylineResources.*, Properties/{Settings*, *List.cs,
Resources.* (strings), PropertiesResources.*}, ~50 non-UI Util files.

Design decisions taken (worth review):
- **Resources**: core keeps public `pwiz.Skyline.Properties.Resources` (1117 strings, ~1290 refs
  unchanged). The 148 images are `Properties/ImageResources` in the exe; ~360 refs rewritten
  (`Resources.X` -> `ImageResources.X`). `DpiIcons` discovery also accepts
  `*.Properties.ImageResources.resources`; `DpiUtil` and the icon tests use `ImageResources`.
- **Settings lists**: core lists keep data/defaults/Title/Label/CopyItem. Their 31
  EditItem/EditList/AcceptList overrides (+ ServerList's 4 dialog helpers) moved verbatim into
  exe `Properties/SettingsListEditors.cs`: a registry by list type + extension methods of the
  same names, so the ~75 callers did not change. `EditListDlg`/`SettingsListComboDriver` get
  editors via `SettingsListEditors.GetItemEditor<T>(list)` (type tests `as IItemEditor<T>`
  broke silently - caught by TestAccessServer etc.). `IItemEditor<T>` moved to exe
  `Util/ListEditors.cs`; `IListEditor<T>` deleted (no users left).
- **Program**: core `ProgramContext` holds what core needs (test flags, exit codes, Name, CLI
  import options, TestExceptions, ReportException, ModeUI, RunLongOperation) + optional
  `IProgramUI UI` that exe `Program.Init` installs (ModeUI, MainWindow, ActiveDocument,
  ReportException -> dialog, RunLongOperation -> LongOperationRunner, UserLogin). Null in
  SkylineCmd, as Program.MainWindow was. 189 refs renamed. TestRunnerLib's InvokeSkyline
  reflects on Program then ProgramContext (it sets FunctionalTest/UseOriginalURLs by name).
- **SkylineWindow from Model**: core `ISkylineDocumentWindow` (SkylineWindow implements;
  `ShowCalibrationForm(bool singleBatch)`, `ZoomChromatogramToPeak`, explicit impls).
  `SkylineDataSchema.SkylineWindow` is that interface; UI uses `GetSkylineWindow()` extension.
  Static helpers moved: `SkylineViewFile.GetViewFile/EXT_VIEW`,
  `AuditLogEntry.CreateDeleteNodesEntry`, `TransitionGroupDocNode.FindChromInfo`.
- **Split mixed files**: LongWaitBroker.cs (ILongWaitBroker, ProgressWaitBroker,
  ProgressUpdateEventArgs, IWebHelpers, new SilentLongWaitBroker), Server.cs, UiModes /
  UiModeChoices, PeptideToMoleculeTextMapper / ModeUIHelpers.FormTextMapper (exe `Helpers`
  partial renamed `ModeUIHelpers`: partial classes cannot span assemblies; 82 refs),
  ExceptionUtilUI, FileSaver.CanSave(IWin32Window) extension, PanoramaShareVersions (CLI
  Panorama version negotiation), BatchModifyInfo, GraphTypeSummary enum (persisted in
  Settings; namespace kept), CarafeModelChoice -> Model/Lib/AlphaPeptDeep.
- **ZedGraph out of Model**: dead `bootstrapCurves` param deleted; SampleType symbol table
  moved to CalibrationGraphControl; Bruker scheduling points are `(double X, double Y)`.
- **Annotations**: `ColorBrush` (name kept - .skyl audit logs refer to it) is a Color;
  audit text identical (`RgbHexColor.GetHex`); UI `AnnotationBrushes` caches brushes.
- **Report export**: RowFactories used BindingListSource (WinForms) for sorted/pivoted reports;
  now `SynchronousQuery.GetReportResults` in Common (same query pipeline, calling thread).
- **Windows-only APIs guarded** (CA1416): DPAPI throws off Windows; audit user =
  `Environment.UserName` off Windows; portable settings ownership = not owned off Windows;
  process-tree kill via `Process.Kill(true)` off Windows; Thermo/ProteinPilot/DIA-NN registry
  lookups return "not installed". Windows behavior unchanged in all.
- SkylineTool -> plain net10.0; pipe transport classes `[SupportedOSPlatform("windows")]`.
- Version stamping shared via `SkylineAssemblyVersion.targets` (Install reads SkylineCore).
- `InternalsVisibleTo` as attributes (`SkylineCore/Properties/InternalsVisibleTo.cs`):
  GenerateAssemblyInfo=false silently disables `<InternalsVisibleTo>` items.

Found, NOT fixed (pre-existing):
- CodeInspection's `InspectMisplacedResources` has been a no-op since Skyline.csproj went
  SDK-style: AssortResources reads `<Compile Include>` items and there are none. Repointed to
  SkylineCore's Resources.resx so it still runs.

Phase 2 notes:
- app.config (app-scoped settings: InstallUrl, ProductName...) is the exe's; SkylineCmd needs
  its own copy or equivalent once it stops loading Skyline.

### Phase 1b - immutable settings lists (Nick, 2026-11-24) - DONE `de6b7eb330` (local)

Request: the lists stored in Settings should be immutable; listen on Settings property changes,
not list events; with immutable values Settings itself is thread-safe.

Done (builds: Solution, TestTutorial, TestPerf, MSConvertGUI):
- `XmlMappedList` immutable: read-only keyed list (`IReadOnlyMappedList` in CommonUtil, which
  `MappedList` also implements), built only while reading XML / in `ChangeItemsWith` on a copy.
  Deliberately NOT `IList<T>`: tried read-only IList with throwing mutators (as
  System.Collections.Immutable does) and `ShareListDlg` compiled and threw at run time
  (TestShareSettings). Read-only consumers take `IEnumerable`/arrays instead.
- `XmlMappedListChanges`: `ChangeAdd/AddRange/Items/Insert/ItemAt/Remove/RemoveAt/RemoveKey/
  Clear/Value/Replace/AddDefaults`, same semantics as the old mutators. Typed through
  `ISelfTypedList<TList, TItem>`, which each concrete list class declares naming itself
  (inferring TItem from the argument failed for subclass items, e.g. RCalcIrt).
- `SettingsListNotifying` + `ListChanged` deleted; RTLinearRegressionGraphPane and ViewLibraryDlg
  listen to `Settings.Default.PropertyChanged`. SearchToolList's lock workaround deleted.
- Editing split from storage: drivers/EditListDlg edit a copy and store the result through
  `Settings.SetSettingsList(list)` (property found by list type; `IsSettingsList` says whether
  a driver's list came from Settings). Getter `EnsureDefault` returns a list, stored if changed.
- ~300 mutation sites rewritten (script for `Settings.Default.X.Op(...)` statements, the rest
  by hand). Aliasing bug found by PasteTest: `ImportDocumentXml` was given the stored mod lists
  and added to them itself; its two list params are gone, it reads them after updating.
  JsonToolServer.AddSettingsListItem reflected for `Add` (TestJsonToolServerSettings).
- New `SettingsListPropertiesTest`: one property per list type; list classes name themselves;
  setting each list property raises PropertyChanged under the property's name.

Not yet immutable (needed before Settings is actually thread-safe): UniqueList<GraphTypeSummary>
x4 (with CollectionChanged hooks), List<string> x3+, SerializableDictionary x3, PersistedViews,
StringCollection x2, OpenDataSourceState (settable POCO). ~200 uses. Not doing it: Nick
2026-11-24, "Don't worry about making other values thread safe."

### Phase 1 - original checklist
- [ ] `pwiz_tools/Skyline/SkylineCore/SkylineCore.csproj`, RootNamespace `pwiz.Skyline`,
      embedded resources (mapping.xml, iRT .sky, KoinaConfig) and protobuf generation move with it
- [ ] git mv Model/, CommandLine.cs, CommandArgs.cs (+usage resx), ProtocolBuffers, non-UI Util
- [ ] Split mixed files: UtilIO, ILongWaitForm, Util.cs, Settings.cs + list classes
- [ ] Core-side replacement for the `Program` members the core uses (UI members stay in Program)
- [ ] Replace `SkylineWindow` uses in Model with an interface the UI implements
- [ ] Split `Properties/Resources`: strings to core, images stay in the exe
- [ ] Settings: one `pwiz.Skyline.Properties.Settings` type must stay one type so user.config
      keeps its section; move the UI-typed enums it persists into core rather than splitting it

### Phase 2 - SkylineCmd - DONE `536d3c39b8` (local)
- [x] Reference SkylineCore, call CommandLine directly; drop the reflection loader and
      UseWindowsForms; target net10.0 (runtimeconfig: Microsoft.NETCore.App only)
- [x] SkylineCmd `--ui` removed (Nick: "get rid of the --ui argument"). Skyline.exe's own
      `--ui` (CommandLineUI, used by DevTools/ImportPerf) and the `CMD<guid>` pipe mode stay.
- [x] Core `CommandLineProgram`: InitializeProcess (shared with Program.Main) + Run
- [x] A SkylineCore.dll missing beside SkylineCmd fails as Run is JIT-compiled; Run is kept out
      of Main (NoInlining) so Main reports it. TestSkylineCmdInEmptyDirectory asserts that.
- [x] Linux (WSL Ubuntu 24.04, runtime in ~/.dotnet via dotnet-install.sh): `--version`, and
      open .sky + import 2 mzML + save + export report gives a report identical to Windows.
      Fixed on the way (raw P/Invokes CA1416 does not see): IsRunningOnWine, GetTempFileName
      (managed CreateTempFile), DirectSerializer direct I/O (managed path off Windows),
      MemoryInfo (GC info), cache copy with progress, hard links (copy), 8.3 paths,
      Downloads folder (OSVersion.Major >= 6 is true on Linux 6.x kernels).
      Script: ai/.tmp/sessions/20261124-separateui/linux_import.sh
- Not Linux-capable by nature: vendor method export (Advapi32 registry lookups),
  FileLockingProcessFinder (rstrtmgr), vendor raw files.

### Phase 3 - guardrails and packaging (lessons from #4587)
- [ ] CodeInspection rule scoped by PATH to SkylineCore/** (the TFM does most of it)
- [ ] Test projects reference SkylineCore; LocalizedResourcesTest/ResourcesTest sentinels;
      P/Invoke allowlist test reaches the new assembly
- [ ] Installer: none needed (Inno stages the whole output). Check only that build.ps1's
      test-file guard does not trip on SkylineCore
- [ ] Docs: build-and-test guide, skyline-development skill

### Phase 3 - guardrails - DONE `9cb5060f76` (local)
- [x] Windows P/Invokes in the plain net10.0 assemblies are `[SupportedOSPlatform("windows")]`
      (CommonUtil Advapi32/Gdi32/Kernel32/Shell32/Shlwapi, FileLockingProcessFinder, SkylineCore
      Kernel32Unsafe + GetTempFileName + GlobalMemoryStatusEx), so CA1416 (an error locally)
      flags any unguarded caller at build time. It found what Phase 2 found at run time, plus:
      NaturalFilenameComparer (StrCmpLogicalW -> managed natural compare off Windows), vendor
      method export lookups (off Windows = "not installed"), FileLockingProcessFinder, FastRead/
      FastWrite (throw BulkReadException off Windows = managed path).
- [x] `Kernel32.FormatExitCode`/`NtStatus` (pure managed) moved to `ProcessExitCode` so Kernel32
      can be marked whole.
- [x] `PlatformNeutralPInvokeTest`: every [DllImport] in SkylineCore, SkylineTool, pwiz.Common*,
      PanoramaClient, ProteomeDb, ProteowizardWrapper, BiblioSpec* must be platform-marked.
      Checked it fails when a mark is removed. Pwiz.* (pwiz-sharp/vendors) out of scope.
- [x] A path-scoped CodeInspection rule for SkylineCore: not needed - the net10.0 TFM already
      makes WinForms uncompilable there, and CA1416 + the test above cover Win32.
- [x] Installer: build.ps1's test-file guard matches exact names, SkylineCore passes; the
      bundled Windows Desktop runtime includes Microsoft.NETCore.App, which SkylineCmd needs.
- [ ] Docs: land the draft below as ai/docs/architecture-skylinecore.md when the PR merges
      (ai docs are shared by all branches; master does not have SkylineCore yet), and link it
      from build-and-test-guide.md and the skyline-development skill.

#### Draft: ai/docs/architecture-skylinecore.md
> **SkylineCore and SkylineCmd.** Skyline is three assemblies. `SkylineCore.dll`
> (pwiz_tools/Skyline/SkylineCore, plain `net10.0`) holds the model, CommandLine, Settings and
> its lists, string resources and non-UI utilities. `Skyline(-daily).dll` (`net10.0-windows`)
> holds every form, control and image, and references SkylineCore. `SkylineCmd.exe` (plain
> `net10.0`) references only SkylineCore and runs on Linux and macOS.
>
> **Where code goes.** Anything SkylineCmd can reach goes in SkylineCore and must compile
> without WinForms or System.Drawing. Core code reaches the UI only through
> `ProgramContext.UI` (`IProgramUI`, null in SkylineCmd) and `ISkylineDocumentWindow`.
> Namespaces did not change with the move, so a type's namespace does not say its assembly.
>
> **Windows-only calls.** CA1416 is active (as an error) in plain `net10.0` projects. Guard
> Windows APIs with `OperatingSystem.IsWindows()` and give a managed path elsewhere. Mark every
> P/Invoke `[SupportedOSPlatform("windows")]` - the analyzer cannot see an unmarked one, which
> then fails only at run time on Linux; `PlatformNeutralPInvokeTest` enforces the mark.
>
> **Settings lists are immutable.** Change one by setting its Settings property:
> `Settings.Default.StaticModList = Settings.Default.StaticModList.ChangeAdd(mod)`. Listen with
> `Settings.Default.PropertyChanged`. List editors store into the property holding that list
> type (`Settings.SetSettingsList`).
>
> **Running SkylineCmd on Linux (WSL).** Install the runtime without sudo:
> `bash dotnet-install.sh --channel 10.0 --runtime dotnet --install-dir ~/.dotnet`, then
> `~/.dotnet/dotnet <bin>/SkylineCmd.dll --in=doc.sky ...` against the Windows build output.
> Vendor raw files and vendor method export need Windows; mzML and the rest work.

### Phase 4 - verification
- [ ] Build-Skyline.ps1 -VendorLicenses green, CodeInspection green
- [ ] Full test pass (parallel)
- [ ] SkylineCmd runs a real import/export on Linux (container or WSL)

## Progress Log

### 2026-11-24 - planning and measurement
Measured coupling (above), got decisions, created branch.

### 2026-11-24 - Phase 0 committed (`60321a0c1a`, local only)
Verified before commit: Build-Skyline.ps1 -Configuration Release -VendorLicenses green
(Solution + TestTutorial + TestPerf + SkylineTester); SkylineBatch.sln and AutoQC.sln green.
Tests green: CodeInspection, CheckForMissingResources, TestLocalizedResources(+GetAssemblies,
GetTypes), TestDpiIconLookup, TestEmbeddedIconSizes, TestEmbeddedCommonIconSizes, TestPanorama,
TestPublishToPanorama, TestRowActions, TestAlphabeticalReportEditor, TestDocumentGridExport,
TestEditablePivot, TestGroupComparisonPivotEditor, TestEditSpectrumFilter, TestAnnotations,
ConsoleShareZipTest, ConsoleRemoveResultsTest. Logs: pwiz_tools/Skyline/bin/staging/Release/*.log.
Not yet run: full suite, ja/zh languages.

### 2026-11-24 - Phase 1 (`62b02cc88b`) and 1b (`de6b7eb330`) committed, local only
1b verified: Solution + TestTutorial + TestPerf + MSConvertGUI build; Test.dll 447, TestData.dll
182, CodeInspection, 58 functional/tutorial tests (EditListDlg users + every touched test file)
all pass. Logs: ai/.tmp/sessions/20261124-separateui/imm2*.log. Next: Phase 2.

### 2026-11-24 - Phase 2 committed (`536d3c39b8`, local only)
Solution builds; Test.dll 447, TestData.dll 182, CodeInspection, TestSkylineCmd(+InEmptyDirectory)
pass. Linux run as in Phase 2. Next: Phase 3 (guardrails, docs) and Phase 4 (full suite, languages).

### 2026-11-24 - Phase 3 committed (`9cb5060f76`, local only)
Solution builds; Test.dll 448, TestData.dll 182, CodeInspection, PlatformNeutralPInvokeTest,
SkylineCmd tests pass. Linux: fresh import (no .skyd) gives a report identical to Windows.
Next: Phase 4 (full suite, ja/zh) and the docs draft at merge.
