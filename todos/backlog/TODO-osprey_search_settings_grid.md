# TODO-osprey_search_settings_grid.md

## Branch Information
- **Branch**: (to create: `Skyline/work/YYYYMMDD_osprey_search_settings_grid`)
- **Base**: `master` after PR #4925 merges (the Build Library Carafe wizard); until then, branch
  from `Skyline/work/20261026_build_library_carafe_wizard` and retarget after the squash-merge
  (`git merge origin/master`, the squash-merged-parent case in version-control-guide.md)
- **Created**: (pending)
- **Status**: Backlog, designed 2026-10-27 for a night session
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
- [ ] Decide the declaration source (design 1) and implement it on the Osprey side: the export,
      its regeneration test, the package's inclusion of it
- [ ] `OspreyAdditionalSettings`: build the `Setting` dictionary from the export, exclusions for
      form-bound arguments, tooltips from the usage text; unit tests over the export
- [ ] `OspreyConfig.AdditionalSettings` + `BuildCommandLine` append; refusal of form-bound names;
      unit tests in `OspreyHelpersTest` (or the existing command-line test)
- [ ] The button on `OspreySearchSettingsControl` and the grid, with tooltip support in
      `KeyValueGridDlg`; the Build Library pretrained-route entry (design 3)
- [ ] Persistence (design 4) and audit log (design 5)
- [ ] Functional tests: open the grid from both wizards, set a value, assert the command line
      carries it, a refused value, a form-bound name refused, persistence round trip, fr/ja
- [ ] Docs: the wizard's help text, the TODO, `ai/docs/osprey-development-guide.md` if the
      export changes how arguments are added (an argument added to Osprey must appear in the grid
      without Skyline work - say so where arguments are declared)

## Tests
- `OspreySearchTest`, `OspreySearchTuningTest`, `BuildLibraryCarafeWizardTest`,
  `AlphaPeptDeepUseGpuTest`, `CodeInspection`; Osprey's `OspreyCommandArgsTests`; the new ones.
- Osprey's `TestSubsetPrecursorTable` and `regression-parallel.ps1 -Dataset Stellar` if the
  command line Osprey receives changes shape.

## Progress Log

### 2026-10-27 - Written

From the precedent study of 2026-10-27 (files and counts above), with Brendan.
