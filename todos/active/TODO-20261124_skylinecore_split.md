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

#### Pre-existing gaps noticed, NOT fixed (outside scope)
- Installer lists satellites under `zh-CHS\`, build emits `zh-Hans\`; PanoramaClient's
  satellites are not listed at all; zh-CHS list lacks CommonUtil/CommonBaseUI.
- `LocalizedResourcesTest` never covered pwiz.Common or PanoramaClient until now (now does, passes).

### Phase 1 - SkylineCore project
- [ ] `pwiz_tools/Skyline/SkylineCore/SkylineCore.csproj`, RootNamespace `pwiz.Skyline`,
      embedded resources (mapping.xml, iRT .sky, KoinaConfig) and protobuf generation move with it
- [ ] git mv Model/, CommandLine.cs, CommandArgs.cs (+usage resx), ProtocolBuffers, non-UI Util
- [ ] Split mixed files: UtilIO, ILongWaitForm, Util.cs, Settings.cs + list classes
- [ ] Core-side replacement for the `Program` members the core uses (UI members stay in Program)
- [ ] Replace `SkylineWindow` uses in Model with an interface the UI implements
- [ ] Split `Properties/Resources`: strings to core, images stay in the exe
- [ ] Settings: one `pwiz.Skyline.Properties.Settings` type must stay one type so user.config
      keeps its section; move the UI-typed enums it persists into core rather than splitting it

### Phase 2 - SkylineCmd
- [ ] Reference SkylineCore, call CommandLine directly; drop the reflection loader and
      UseWindowsForms; target net10.0
- [ ] `--ui` and the `CMD<guid>` pipe mode stay in Skyline.exe

### Phase 3 - guardrails and packaging (lessons from #4587)
- [ ] CodeInspection rule scoped by PATH to SkylineCore/** (the TFM does most of it)
- [ ] Test projects reference SkylineCore; LocalizedResourcesTest/ResourcesTest sentinels;
      P/Invoke allowlist test reaches the new assembly
- [ ] Installer file lists (Inno Setup `installer/`, any WiX templates) gain SkylineCore.dll
      and its ja/zh-CHS satellites
- [ ] Docs: build-and-test guide, skyline-development skill

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
