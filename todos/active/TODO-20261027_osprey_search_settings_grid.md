# TODO-20261027_osprey_search_settings_grid.md

## Branch Information
- **Branch**: `Skyline/work/20261027_osprey_search_settings_grid`
- **Base**: `master` (PR #4925 merged 2026-10-27, b68aa96d5f)
- **Created**: 2026-10-27
- **Status**: In Progress (night session 2026-10-27)
- **Module**: `skyline` (with an `osprey` piece if the declarations are exported from Osprey)
- **PR**: (pending)
- **Objective**: Expose the complete option set of Osprey and Carafe behind an "Additional
  settings..." button, as the other search engines do, in both places that run Osprey: the Osprey
  Search wizard and Build Library's Carafe source (the fine-tune pages and the pretrained route).
- **Requested by**: Brendan, 2026-10-27, after reviewing PR #4925: "I don't think enough of the
  settings are exposed. There is already a solid precedent for how to expose the complete
  settings list for a search engine in a name-value pair grid form."

## The precedent (found 2026-10-27)

**The pattern**: a search engine holds `IDictionary<string, AbstractDdaSearchEngine.Setting>`
`AdditionalSettings` (`Model/AbstractDdaSearchEngine.cs:64-205`: a typed name/value with min/max
or a list of valid values, `Validate`, `IAuditLogObject`). An "Additional settings..." button
(`PeptideSearchResources.SearchSettingsControl_Additional_Settings`) opens
`Alerts/KeyValueGridDlg.Show(parent, title, settings, valueToString, stringToValue, validate,
validValues)`: a scrolling two-column grid, keys sorted, a text box or a combo per value, an
invalid value refused with its message and restored.

| Engine | Where | Settings in the grid |
|---|---|---|
| MSFragger | `SearchSettingsControl.btnAdditionalSettings_Click` (ImportPeptideSearchDlg, DDA) | 59, hand-listed in `MsFraggerSearchEngine.cs` with ranges |
| Comet | same | 78, hand-listed |
| MS Amanda | same | 5 |
| MSGF+ | same | none |
| DIA-NN | `DiannSearchDlg.ShowAdditionalSettings` | 4 only (`DiannHelpers.DefaultAdditionalSettings`: MinPepLen, MaxPepLen, Min/MaxPrecursorCharge); the rest of DIA-NN's command line is not exposed |
| EncyclopeDIA | `EncyclopeDiaSearchDlg.btnAdditionalSettings_Click` | `EncyclopeDiaConfig.Parameters` |
| msconvert | `ConverterSettingsControl` | its own |

So Matt's design is in ImportPeptideSearchDlg for the DDA engines, DIA-NN has it in form only
(4 values), and the Osprey Search wizard, built on the DIA-NN wizard, has none.

**Persistence and presets**: the DDA engines' additional settings travel in
`SearchSettingsPreset` (`Model/DdaSearch/SearchSettingsPreset.cs`: `AdditionalSettingsXml`,
`SerializeAdditionalSettings` / `ApplyAdditionalSettings`), a named, persisted list with import
from an engine's params file (`SearchSettingsParamsFileParser`, the Import settings... button).
The Osprey wizard persists nothing today (no `Settings.Default.Osprey*`).

**What Osprey has that the others do not**: a declarative argument table.
`pwiz_tools/Osprey/Osprey/OspreyCommandArgs.cs` declares 64 `OspreyArgument`s (name, value
kind: flag / path / listed values / number / variadic, group, `DescriptionArgs`) plus ~23
CarafeSharp declarations it hosts (`CarafeCommandLine.cs`: digest, modifications, fragments,
acquisition, NCE, instrument, RT model, ...), with localized usage text in
`OspreyCommandArgUsage.resx` and generated help pages
(`pwiz_tools/Osprey/Documentation/Help/<culture>/CommandLine.html`, 87 rows), kept current by
`OspreyCommandArgsTests.TestCommandLineHelpDocumentation`. MSFragger's 59 settings are a
hand-copied list that drifts from the engine; Osprey's need not be.

**What Skyline exposes today** (`OspreyHelpers.OspreyConfig`, `BuildCommandLine`): data files,
library/FASTA/precursor table, model, training inputs, device, torch runtimes, resolution,
fragment tolerance and unit, run/experiment/protein FDR, threads, enzyme, missed cleavages,
peptide length, charges, max variable mods, fixed and variable modification ids, culture,
timestamp. The form pages: Search Settings (resolution, tolerance, three FDRs, threads), FASTA
(file, enzyme, missed cleavages), Modifications, Library Model (model, Use GPU, runs).

## Design

1. **One source of truth: the declared Arguments, extended** (Brendan, 2026-10-27). The
   `Argument<TContext>` declarations (`pwiz_tools/Shared/CommonUtil/CommandLine/Argument.cs`,
   used by `OspreyCommandArgs` and the CarafeSharp declarations Osprey hosts) already carry a
   list of acceptable values. Extend them with:
   - a **property name**, the label the grid shows, stored in RESX so it localizes (beside the
     usage text in `OspreyCommandArgUsage.resx` and CarafeSharp's);
   - a **property type** (number with range, boolean flag, listed values, path, text), which
     decides the grid's control and validation;
   - **whether the argument is exposed** on the Additional settings page: not every argument is
     (`--help`, the inputs and outputs the form binds), but everything a user could want access
     to should be, through the Argument instances themselves, so an argument added to Osprey
     appears in the grid without Skyline work.
   Skyline then **enumerates the exposed declarations** - either in code, by sharing the
   declarations (only if that pulls no torch dependency into Skyline), or by asking the
   installed Osprey, for example `Osprey --help properties`, which prints the exposed arguments
   with their localized property names, types, values and defaults in a machine-readable form
   that Skyline parses once per package and caches beside it. The session decides between
   the two by what each costs: the in-code route needs the declarations in a TorchSharp-free
   assembly; the `--help properties` route needs a stable format and a parse on the Skyline side.
   The usage text is the tooltip either way (KeyValueGridDlg has no tooltip today; add one).
2. **Form-bound arguments stay out of the grid** (as `SearchSettingsControl` leaves its form
   fields out): everything `OspreyConfig` sets from a control is excluded or shown read-only;
   the grid holds the rest. A grid value for a form-bound name is refused with a message naming
   the control. `OspreyConfig` gains `AdditionalSettings` (name -> Setting) that
   `BuildCommandLine` appends after the form-bound arguments, flags as bare switches, lists as
   repeated values.
3. **Where the button lives**: the shared `OspreySearchSettingsControl` (both wizards' Search
   Settings page), which keeps the two wizards in step. For Build Library's pretrained route,
   which never reaches that page, the Carafe prediction options (NCE, instrument, RT model, the
   ones Mike wants reachable) need a way in that does not add to page 1's default path: an
   "Additional settings..." button in the Carafe group box, enabled for every route, is the
   candidate; Brendan's rule - "streamline the default case, reach the rest off that path" -
   decides the shape. Mock it over the MCP first (`Run-Tests.ps1 -AiConnector`, the demo pause
   pattern of `BuildLibraryCarafeWizardTest`) if there is any doubt.
4. **Persistence**: a named preset list for Osprey (`SearchSettingsPreset` has `SearchEngine`;
   add Osprey, or a parallel `OspreySettingsPreset` if the DDA shape does not fit), so a lab's
   settings survive and travel; at minimum the last-used additional settings in
   `Settings.Default`. Import from a saved Osprey command line or `.osprey.task` is a later item.
5. **Audit log**: `Setting` is `IAuditLogObject`; the search's audit entry should carry the
   non-default additional settings as the DDA search does (check `ImportPeptideSearchDlg.cs:487`).
6. **Out of scope**: the training-run metadata flag (`ApplyTrainingRunMeta`, for Mike); feature 3
   of the Carafe wizard TODO; the one-command stage decomposition.

## Tasks
- [x] Decide the declaration source (design 1) and implement it on the Osprey side: the export,
      its regeneration test, the package's inclusion of it
- [x] `OspreyAdditionalSettings`: build the `Setting` dictionary from the export, exclusions for
      form-bound arguments, tooltips from the usage text; unit tests over the export
- [x] `OspreyConfig.AdditionalSettings` + `BuildCommandLine` append; refusal of form-bound names;
      unit tests in `OspreyHelpersTest` (or the existing command-line test)
- [x] The button on `OspreySearchSettingsControl` and the grid, with tooltip support in
      `KeyValueGridDlg`; the Build Library pretrained-route entry (design 3)
- [x] Persistence (design 4: last-used on the branch, named presets on nightlywork/osprey_settings_presets) and audit log (design 5: commit 4)
- [x] Functional tests: open the grid from both wizards, set a value, assert the command line
      carries it, a refused value, a form-bound name refused, persistence round trip, fr/ja
- [x] Docs: the wizard's help text (tooltips), the TODO, `ai/docs/osprey-development-guide.md` if the
      export changes how arguments are added (an argument added to Osprey must appear in the grid
      without Skyline work - say so where arguments are declared)

## Tests
- `OspreySearchTest`, `OspreySearchTuningTest`, `BuildLibraryCarafeWizardTest`,
  `AlphaPeptDeepUseGpuTest`, `CodeInspection`; Osprey's `OspreyCommandArgsTests`; the new ones.
- Osprey's `TestSubsetPrecursorTable` and `regression-parallel.ps1 -Dataset Stellar` if the
  command line Osprey receives changes shape.

## Progress Log

### 2026-10-27 - Written

From the precedent study of 2026-10-27 (files and counts above), with Brendan. PR #4925, the
Build Library Carafe wizard this builds on, merged the same day (b68aa96d5f), so the work
branches from master.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20261027_night_osprey_settings_grid.md` before starting work.

### 2026-10-27 night - Implemented end to end (uncommitted at this entry; see the next)

**Decision, design 1**: the declaration source is `Osprey --help properties`, JSON on stdout generated
from the Argument declarations. The in-code route was rejected: `OspreyCommandArgs` lives in the
executable with handlers over `Osprey.Tasks`/`IO`/`ML`, so sharing it would pull the pipeline (and
torch) into Skyline. The exe route costs ~100 ms per launch (Debug build: `--help sections` 86 ms,
`--version` 124 ms), so Skyline runs it once per (exe path, UI culture) and caches in memory - no
shipped file, no package change, no drift from the installed exe. An older Osprey answers with its
"No help section" text, which Skyline reports as "Osprey at {0} did not report its settings: {1}".

**Declarations extended** (`pwiz_tools/Shared/CommonUtil/CommandLine/ArgumentBase.cs`): `PropertyName`
(Func, null = not a property), `PropertyType` (`ArgumentPropertyType`: flag/text/path/integer/number/list,
with `EffectivePropertyType` inferring flag and list from the declaration), `DefaultValue` (Func, invariant
text, null = Osprey names none), `MinValue`/`MaxValue`; all copied by the hosting ctor.
- Osprey (`OspreyCommandArgs.cs`): `OspreyArgument.Scope` (`OspreyPropertyScope`: search/library/digest/
  tuning) marks an argument as a property and derives its label from `OspreyCommandArgUsage.resx` under
  `<usage key>_property` (31 new entries, Designer updated). 29 of Osprey's own arguments are properties;
  the 25 that are not (inputs, outputs, commands, HPC, log plumbing, entrapment) are pinned by name in
  `TestPropertiesExport`, so a new argument must be classified. `Host()` gives CarafeSharp's hosted
  arguments the scope of their section (digest/library/tuning).
- CarafeSharp (`CarafeCommandLine.cs`): a static ctor's `DeclareProperties()` table sets type, default
  (from the settings classes' constants) and range for the 38 hosted arguments; labels in
  `CarafeCommandArgUsage.resx` (`_nce_property`, ...; that resx has no per-key Designer), read by
  `GetPropertyName`. `PROPERTY_SUFFIX` is shared with Osprey's label lookup.
- `OspreyProperties.cs` (Osprey exe): `Generate()` writes the JSON (System.Text.Json); `--help properties`
  prints it; the `--help` usage text names the format (help pages regenerated by the drift test).
- Tests: `TestPropertiesExport` (69 properties; every one labeled, described, grouped, scoped, typed; a
  list default among its values; a number default within range; the export through `PrintUsage` equals
  `Generate()`; the ja export keeps every property). `TestEveryArgIsGroupedAndDescribed` now accepts
  `_property` keys and requires one per property. Osprey gate: 12/12 command-args tests, full suite +
  inspection green (`ai/.tmp/sessions/20261027-settings-grid/osprey-gate1.log`).

**Skyline**:
- `Model/Lib/OspreyProperties.cs`: `OspreyProperty` (CreateSetting: flag -> bool Setting; list -> string
  Setting with a blank first choice when there is no default; else string), `Validate(text)` (numbers
  parsed in the UI culture then invariant, ranges, lists; an optional-value integer takes blank, `auto`
  or a count), `ToArgumentValue` (invariant), `Tooltip` (argument + usage text); `OspreyProperties.Load
  (exe, culture)` runs the exe, caches, `Parse` (Newtonsoft), `ClearCache` for tests.
- `Model/Lib/OspreyAdditionalSettings.cs`: the `Setting` dictionary by argument name, minus
  `OspreyHelpers.FormBoundArguments` (the 18 the pages set: resolution, tolerance+unit, 3 FDRs, threads,
  device, decoys-in-library, enzyme, miss-c, lengths, charges, fix/var-mod, max-var); `ScopesFor(config)`;
  `GetGridValues(scopes)` (label-keyed view of the same objects); `Validate`/`GetTooltip` for the grid;
  `AppendArguments(sb, scopes)` (non-defaults only, flags bare, `auto` bare, paths quoted, help order);
  `ToXml`/`ApplyXml` in `SearchSettingsPreset`'s AdditionalSettings XML (a form-bound or invalid value
  is refused by name); `ApplyLastUsed`/`SaveLastUsed` through `Settings.Default.OspreyAdditionalSettings`.
- `OspreyConfig.AdditionalSettings`; `BuildCommandLine` appends after the pages' arguments, before
  `--culture`; `BuildPredictLibraryCommandLine(..., additionalSettings)` appends the library scope.
- `KeyValueGridDlg.Show(..., tooltipForValue)`: a ToolTip on each row's label and control.
- `OspreySearchSettingsControl`: `AdditionalSettings` (lazy: Load + last used, a refusal reported),
  `TryGetAdditionalSettings` (reports an Osprey that cannot answer), `GetScopes` (the host's Func),
  `ShowAdditionalSettings()` (the grid), the button (control grew to 565x215); `ValidatePage` loads the
  settings so last-used values reach a run whose grid was never opened; `ApplyTo` sets
  `config.AdditionalSettings` and saves last used. `OspreySearchDlg` supplies
  `GetScopes = () => ScopesFor(GetSearchConfig())`; `BuildLibraryDlg` supplies tuning ? all : library,
  adds `btnCarafeAdditionalSettings` in the Carafe box (Predict-for row, right-aligned; design 3's
  "reach the rest off the default path" - one button, no new page), `ShowCarafeAdditionalSettings()`
  (EnsureInstalled first), and `CreateCarafeBuilder` loads/saves them for both routes;
  `CarafeLibraryBuilder.AdditionalSettings` feeds the pretrained route's command line.
- Strings: `ModelResources` (4), `PeptideSearchResources` (1), button texts in the two control resx.
- Tests: `Test/OspreyAdditionalSettingsTest` (sample JSON: parse, settings, grid by scope, validation,
  arguments through both command lines, fr-FR comma input, persistence round trip and refusals, scopes,
  bad export) - green. `OspreySearchTest`: grid opened on the Search Settings page in both runs (nce
  present only with a predicted library, threads never), verbose + `--nce 30` set, persisted into the
  second wizard, command line asserted; refusals. `BuildLibraryCarafeWizardTest`: the page's grid on the
  fine-tune route (seed present, `--verbose` in the one command) and the Carafe box's on the saved-model
  route (seed/verbose absent, `--nce 30` in the prediction command line).

**Not done / open**: design 5 (audit log) - the DDA precedent has no audit entry for additional settings
either (ImportPeptideSearchDlg:487 is the preset serialization); design 4's named preset list (last-used
only); group header rows in the grid (flat, help order within the export order); `entrapment` and
`export-library` left unexposed (Skyline handles entrapment itself; export-library is an output); the
osprey-development-guide note on adding an argument.

### 2026-10-27 night - Committed, reviewed, grouped

- Commit 1 `cc871c53e0`: everything in the entry above (31 files). Gates before it: Osprey build +
  646 tests + inspection green; Skyline build; `OspreyAdditionalSettingsTest`; `OspreySearchTest` (0
  failures, 11 s - the subset searches take seconds); `BuildLibraryCarafeWizardTest` (30 s);
  `CodeInspection`; `OspreySearchTest` in all five languages (the `--culture ja-JP` export path).
- Visual check over the MCP demo: page 1's `Additional Settings...` sits right of "Predict for:" in the
  Carafe box; the Search Settings page's under Threads. The grid itself cannot be paused on in the demo
  (`MultiButtonMsgDlg.ShowWithTimeout` fails a test after 10 s), so it was not captured; it is the DDA
  engines' `KeyValueGridDlg`.
- `/code-review medium`: 10 findings, 9 fixed in commit 2, 1 dropped (the synchronous process start on
  the first Next: measured ~100 ms, once per session). Fixed: a text property with a default cleared to
  blank was emitted as a bare switch (blank now always leaves the argument out); stdout+stderr both
  redirected and read in sequence (deadlock; stderr no longer redirected); the paramName overload of
  `ArgumentOutOfRangeException`; raw grid text persisted (a `0,05` typed under fr-FR; `SetValue` now
  stores numbers invariant); `SaveLastUsed` as a side effect of `ApplyTo` (moved to `ValidatePage`, the
  run); the refusal message's reason and its MessageDlg from a getter (now from the UI thread, reworded);
  `FormBoundArguments` mixing prefixes (now `FORM_BOUND_ARGUMENTS`, bare names); a list default outside
  its values (offered first); the properties cache keyed on the path alone (now the file's write time too).
- Commit 2: group headers in the grid (a sub-agent's change): `KeyValueGridDlg.Show(..., groupForValue)`
  keeps the dictionary's order and introduces each help section with a bold spanning label; without the
  callback the grid is unchanged (alphabetical). `OspreySearchTest` asserts the header and the order;
  `DdaSearchTest` (an existing user of the grid) stayed green.
- Still open: design 5 (audit log; note the search's full command line, additional settings included, is
  recorded in the .blib's metadata by Osprey), design 4's named presets, translations of the new labels.

### 2026-10-27 night - Older Osprey tolerated; presets on a side branch

- Commit 3 `438616321a`: an Osprey from before `--help properties` (what a developer build downloads
  from TeamCity master until this merges, and the release-pinned 26.1.1.296) is reported once and the
  wizards run without additional settings, as before the grid; `ValidatePage` and `CreateCarafeBuilder`
  no longer block on it. **Before a release pins Osprey**, the pin must move past this PR's Osprey
  build, or the grid reports that message on every machine with the pinned package.
- No Osprey pipeline change (declarations' metadata and help text only): the default command lines
  Skyline writes are unchanged, so `regression.ps1` was not run; the Osprey gate (646 tests +
  inspection) was.
- Design 4 (named presets) is being built by a sub-agent on the local branch
  `nightlywork/osprey_settings_presets` (from commit 3), mirroring the DIA-NN wizard's preset combo:
  `OspreySettingsPreset`/`OspreySettingsPresetList` in `Settings.Default.OspreySettingsPresets`, a
  "Settings preset:" combo on the Search Settings page. Take it (merge the branch into the work
  branch) or leave it; the work branch does not depend on it. Its report is in the handoff.

### 2026-10-27 night - Presets landed on the side branch (22:35)

`nightlywork/osprey_settings_presets` @ `523b2bd319` (local, from commit 3; 8 files, +741/-30), all gates
green there (new `OspreySettingsPresetTest`, `OspreySearchTest`, `BuildLibraryCarafeWizardTest`,
`CodeInspection`). The shape mirrors the DIA-NN wizard: a "Settings preset:" combo driven by
`SettingsListComboDriver` over `OspreySettingsPresetList : SerializableSettingsList` (so `<Edit list...>`,
with import/export as `.skyosp`), a "Save..." button that names the current page through `PresetNameDlg`
(overwrite confirmed with the existing string), the page opening with no preset chosen. A preset holds
resolution, tolerance + unit, the three FDRs and the additional settings' XML (not Threads); choosing one
resets the additional settings to Osprey's defaults and applies the preset's. `OspreyAdditionalSettings`
gained `ResetToDefaults()`. Not reviewed by `/code-review` (the work branch's three commits were). To
take it: `git merge nightlywork/osprey_settings_presets` on the work branch (a fast-forward).

Open for the morning: whether to take the presets branch; design 5 (audit log); the ja/zh-Hans labels
(English fallback); the Osprey pin before a release; opening the PR (not pushed overnight).

### 2026-10-27 night - Design 5 done (22:50)

Commit 4 `b9b0c8e94d`: the precedent search found that no DDA engine logs its AdditionalSettings, but the
DIA-Umpire converter's non-default `Setting`s are `[Track]`ed inside the import wizard's
`imported_peptide_search` entry (`ConverterSettingsControl.DdaConverterSettings`). Osprey follows that:
`OspreySearchSettings` (resolution, tolerance + unit, three FDRs, threads, the non-default additional
settings in the run's scopes), built from the config the search ran with, is handed to
`ImportPeptideSearchDlg` by the Osprey wizard and `[TrackChildren]`ed in `ImportPeptideSearchSettings`
(null for every other route). The entry reads "Import Peptide Search > Osprey search settings > Osprey
non-default settings : contains nce = 30 / verbose = True"; 9 `PropertyNames` entries added (English;
ja/zh trail as the file's practice). `OspreySearchTest` checks the entry for both runs (the
library-scope `nce` is logged only with the predicted library); `TestAuditLogLocalization`,
`DdaSearchTest` (10 tests), `BuildLibraryCarafeWizardTest`, `CodeInspection` green.

Every designed item is now built except the morning decisions: take the presets side branch
(`nightlywork/osprey_settings_presets`, based on commit 3, so merging it is a merge, not a fast-forward;
both touch `OspreySearchTest.cs` in different places), the Osprey pin before a release, the ja/zh-Hans
labels, and opening the PR.
