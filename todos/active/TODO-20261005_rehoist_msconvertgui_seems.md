# TODO-20261005_rehoist_msconvertgui_seems.md

## Branch Information
- **Checkout**: `C:\dev\pwiz-retire` (git worktree, switched from the retirement branch)
- **Branch**: `Skyline/work/20261005_rehoist_msconvertgui_seems`
- **Base**: `Skyline/work/20260910_retire_cpp_tree` (PR #4658), stacked
- **Created**: 2026-10-05
- **Status**: In review
- **GitHub Issue**: (none)
- **Module**: `pwiz`
- **PR**: [#4783](https://github.com/ProteoWizard/pwiz/pull/4783)

## Objective

The C++ retirement (#4658) landed the pwiz-sharp copies of MSConvertGUI and SeeMS on top of
`pwiz_tools/MSConvertGUI` and `pwiz_tools/SeeMS`. Those copies were taken in May 2026 and lived
apart from the originals, which was never the intent: there should be one MSConvertGUI and one
SeeMS, continuing their own history. Re-hoist both so each is the current legacy app plus the
mechanical .NET 10 / C# library re-targeting, with nothing the legacy app had left behind.

## What differs (measured on the base branch, whitespace-insensitive)

- **MSConvertGUI** copied 2026-05-12 (`1a8b16ef68`). The port's own changes are mechanical
  (31 of 42 shared files identical; `Compat.cs` re-exposes the pwiz.CLI names). The legacy app
  moved on afterwards and the port has none of it: #4099 waters_connect support (Shared
  `CommonFileDialogs` open dialog, `RemoteAccountEditForm`, `SplitButton`,
  `MSConvertRemoteAccountServices`; `UnifiBrowserForm`/`LoginForm`/`NetworkSource` removed),
  #4244 zlib-checkbox fix, #4282 waters_connect paths, #4637 IdentityModel 7, two build fixes.
- **SeeMS** copied 2026-05-01 (`1e1e880936`). Legacy changed only its project file since. The
  port compiles 13 fewer source files (open-data-source dialog, both heatmaps, annotation and
  processing panels/forms, data point table, about box, select-columns dialog, `Annotation.cs`,
  `Processing.cs`), standing in `PortStubs.cs` / `Stubs.*.cs`.

## Plan

- [x] MSConvertGUI: 3-way merge per file (base = legacy at the fork, ours = the hoisted port,
      theirs = legacy at the base tip); bring in the legacy-only files; drop the ones legacy
      deleted; reference Shared `CommonFileDialogs`/`CommonMsData`/`ProteowizardWrapper` (all
      net10.0-windows); port the test changes
- [x] SeeMS: compile the 13 excluded files with mechanical substitutions; delete the stubs
- [x] Build `Pwiz.sln`; MsConvertGUI.Tests; launch both apps on a vendor fixture
- [x] Runbook: record that the GUI ports were re-hoisted onto the current legacy apps

## Progress

- **MSConvertGUI**: 22 files merged 3-way (conflicts only in MainForm/MainLogic `using` blocks and the
  rewritten MainLogicTest, which keeps the port's in-process design plus a new table test for
  #4244's `--zlib=off`); `LoginForm`/`UnifiBrowserForm`/`NetworkSource` deleted with legacy; the
  four #4099 files added (one `pwiz.CLI` reference re-pointed at `Compat.ReaderList`); the port's
  stub `UnifiBrowserForm` removed from `Compat.cs`; references to Shared `CommonFileDialogs` +
  `CommonMsData`; `CustomDataSourceDialog` deleted (no consumer left outside the archived
  Bumbershoot). Legacy `TestConnected` became `MsConvertGUI.TestConnected` (not `*.Tests`, so CI
  skips it; all 7 passed live here with the UNIFI/WC credentials). MsConvertGUI.Tests 4/4.
- **SeeMS**: the 13 files compile; stubs deleted. Port defects fixed against legacy: the blanket
  `(T) x.Value` -> `x.ValueAs<T>()` rewrite on grid cells / up-downs, `Map<>` -> `Dictionary<>`
  (sorted -> unsorted; restored in 6 files), the `SpectrumList` property renamed to
  `ISpectrumList`, `ReaderList.Default` (no vendors) where legacy used the full list, the dropped
  `CommonUtil` reference. Restored legacy `Properties/Resources` (toolbar/menu icons) and
  `Misc/EventSpy.cs`; `MemoryCache` (was a .NET 4.0 DLL from the C++ UNIFI SDK dir) is now a
  small LRU; `MSDataList` reads every run and disposes vendor handles; `AboutForm` used
  `Assembly.ReflectionOnlyLoad` (throws on .NET Core). SeeMS now reads Shimadzu/UIMF/UNIFI/
  Mobilion too. `getPrecursorSpectrum` (threw NotImplemented) restored.
- **Library** (C# had no port): `IsolationWindowFilter` (+ tests), for SeeMS's precursor-spectrum
  commands. `WhittakerSmoother` was ported too, then removed: SeeMS's menu has not offered it since
  2009 and msconvert never exposed smoothing, so nothing could reach it.
- **Smoke** (UI Automation + screenshots): SeeMS opens Thermo and Shimadzu files, data
  processing / annotation panels and About open; MSConvertGUI's Browse opens the shared Open
  Data Source dialog with Remote Accounts.
- `PORT-NOTES.md` deleted (described the separate port; nearly all of it no longer true).
- **Code review** (2026-10-06): fixed the bugs in the newly compiled SeeMS dialogs. One came from the
  port: the Open dialog's TIC preview read through `ReaderList.Default` (no vendor readers), so clicking
  any vendor file threw. The rest are legacy:
  - annotation and processing Remove deleted the wrong entries, or threw on select-all; the processing
    "–" button was never enabled, and its menu item had no handler
  - "Override global processing" stored the spectrum's own list, so clearing it wiped that spectrum's processing
  - the override mode started as Before while the menu showed Replace
  - Look-in folder entries were tagged with their parent's path, so choosing one did nothing
  - the replaced background loader never stopped
  - a scan time with a single drift scan threw in the heatmap
  - the data point table paired processed points with raw mobility values

  Starting in Replace also needed the list layout to ignore the mode while no override is set (Replace
  with an empty override hid the spectrum's own processing; legacy only escaped this by starting in Before).
  Verified with UI Automation on a Thermo fixture: TIC preview and Look-in (both failed against the old
  lines), processing Remove on a multi-selection, and override then clear.
- **Ion mobility heatmap on timsTOF** (2026-10-06):
  - per-scan spectra: the heatmap walked the spectrum grid's rows, which unshares (clones) each one. On
    the DIA-PASEF tutorial file (1.49M spectra) that hung with 5+ GB and climbing; it now reads the
    bound data rows and opens within seconds of the 1.7-minute load
  - combined spectra: never opened the heatmap. Rows are built from metadata-only spectra, which have
    no arrays, and "merged=" ids were not classed as ion mobility. Also accepted the "mean ion mobility
    array" term the C# Bruker reader writes for profile combined spectra
  - both modes now draw MS1 and MS2 heatmaps on the tutorial file, and per-scan on the perf-test and
    diaPASEF.d fixtures
  - `SingleInstanceHandler` seeded its mutex and pipe names with `string.GetHashCode()`, which is
    per-process on .NET Core, so simultaneous launches no longer merged into one window; now a SHA-256
    of the path
  - MSConvertGUI converted only the first sample of a multi-sample WIFF: its Compat `ReaderList.read`
    read one MSData where cpp/CLI filled the list with every sample. Ported cpp
    `ReaderList::read(filename, vector<MSDataPtr>&)` to the library (a sample that fails to open is
    skipped with a stderr line, as Reader_ABI does); MSConvertGUI and SeeMS's `MSDataList` both use it.
    Tests: ReaderListTests (fake multi-sample reader) and MainLogicTest (Enolase WIFF -> 10 mzML;
    fails with 1 against the old read)
  - MSConvertGUI showed `user:password@` URLs as typed in the file box, file list, job grid and Show
    Command Line (#4099 dropped the old credential split). New `CredentialUrl` keeps them for the
    reader and leaves them out of everything shown, as the conversion log already did
  - the remote-account dev pre-fill keyed on an exe folder named `msvc-*` or `bin`; SDK builds run
    from bin\Debug|Release\net10.0-windows, so it never fired. Now matches that layout (DataSourceTest)
  - left alone: the heatmap title's "isolation m/z 0" (it parses "[lo-hi]" as a number; legacy),
    per-scan TIC equal to the frame TIC (C++ `TimsSpectrum::getTIC` does the same), and
    `TimeMzHeatmapForm`'s own grid-row walk
