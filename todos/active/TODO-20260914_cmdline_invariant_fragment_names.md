# TODO-20260914_cmdline_invariant_fragment_names.md

## Branch Information
- **Branch**: `Skyline/work/20260914_cmdline_invariant_fragment_names`
- **Base**: `master`
- **Created**: 2026-09-14
- **Status**: In Progress
- **GitHub Issue**: [#4668](https://github.com/ProteoWizard/pwiz/issues/4668)
- **Module**: `skyline`
- **PR**: [#4669](https://github.com/ProteoWizard/pwiz/pull/4669)

## Objective

Make `--tran-product-start-ion` and `--tran-product-end-ion` accept the invariant
fragment-finder names (`ion 3`, `last ion`, `3 ions`, ...) in any UI language, as sent
by external tools like FragPipe, while continuing to accept localized labels.

Reported by Daopu (Skyline 26.1.0.057, FragPipe 24.0, Chinese UI):
https://skyline.ms/home/support/announcements-thread.view?rowId=75563

## Root Cause

- `CommandArgs.cs` value lists for both arguments contain only localized labels, and
  `NameValuePair.cs:164` rejects values not in the list before parsing.
- `TransitionFilter.GetStartFragmentNameFromLabel` / `GetEndFragmentNameFromLabel`
  matched `Label` only.
- `ConsoleNewDocumentTest` built args from `.Label`, so it passed in every language.

## Tasks

- [x] Failing test: `ConsoleNewDocumentTest` passes invariant `.Name` values; red in zh-CHS
      (`值“ion 1”对于参数 --tran-product-start-ion 无效`), green in en
- [x] Name lookups accept invariant `Name` (OrdinalIgnoreCase) or `Label` (CurrentCultureIgnoreCase)
- [x] Both args use `HasValueChecking = true` + `ParseFragmentFinderName` helper throwing `ValueInvalidException`
- [x] Test still covers localized labels (later command uses `ION_3.Label` / `IONS_4.Label`)
- [x] `ConsoleNewDocumentTest` passes in en + zh; CodeInspection passes
- [x] Commit and push branch (84c67c4ee2)
- [x] Audit other args with localized value lists (see "Settings-list arguments" below)
- [x] Failing tests for settings-list args (red in zh), fix, green in en + zh
- [x] Commit settings-list fix
- [x] All-language run (en, fr, tr, ja, zh): ConsoleNewDocumentTest, ConsoleChangePredictTranSettingsTest,
      ConsoleArgumentInvalidValuesTest, CommandLineUsageTest, CommandLineUsageDescriptionsTest,
      ConsoleArgumentValidationTest, ConsoleSettingsArgumentsTest, TestSkylineCmd, TestJsonToolServer
- [ ] Code review, Copilot review ([#4669](https://github.com/ProteoWizard/pwiz/pull/4669))
- [ ] Reply to support thread once fix ships

## Settings-list arguments

Same class of bug in `--tran-predict-ce`, `--tran-predict-dp`, `--tran-predict-cov`,
`--tran-predict-optdb` and `--full-scan-precursor-isotope-enrichment`:

- Value lists came from `GetDisplayNames`, which localizes the None / Default items
  (`无`, `默认`), while `CommandLine` looks items up by invariant key (`None`, `Default`).
- `--tran-predict-ce=None` was rejected in zh; `ConsoleChangePredictTranSettingsTest` built
  its values from the localized display name, so it passed in every language.
- `IsotopeEnrichmentsList.GetDisplayText` localizes only when `ReferenceEquals(item, DEFAULT)`,
  so a reloaded list shows `Default` and the localized `默认` was rejected; with a never-reloaded
  list the invariant form would be rejected and the localized one silently set no enrichments.
- Fix: `GetDisplayNamesAndKeys` adds invariant keys and default display names to the value list,
  and `ParseSettingsListKey` maps either form to the key.
- Tried first: `HasValueChecking` + honoring it in `ArgumentBase.GetArgumentTextWithValue` - reverted,
  because `ConsoleArgumentInvalidValuesTest` relies on that method rejecting values outside `Values`.

## Code review round (uncommitted, awaiting developer review)

- `/code-review max` (two runs) findings verified; redesign: `ArgumentBase.AcceptedValues` + `IsValidValue`
  (help/errors stay localized, invariant names accepted), single `ParseKey` resolver in `CommandArgs`
  (exact key > exact display > ci key > ci display; only defaults still in the user's list),
  `TransitionSettings` label methods back to exact-label.
- Tests forced to ja via `CallWithCulture`; verified red in en against origin/master (ION 3, None) and
  against d9882f2d4f (deleted SCIEX accepted, ja help diff), green with redesign.
- Copilot thread on #4669 (tests only red in ja/zh): addressed by the ja-culture tests - reply + resolve after commit.

## Reporter follow-up (2026-09-21)

Daopu reports the Tools > Options > Language workaround did NOT help; only changing the Windows
system language did. Root cause: `Program.cs:222` returns `CommandLineRunner.RunCommand` before the
`Settings.Default.DisplayLanguage` block at `:251`, so SkylineCmd always runs in the OS UI culture.
The fix on this branch makes the arguments work in any culture, so no workaround is needed once it ships.

## Follow-up (not in this PR unless decided otherwise)

- Fragment-finder args list only localized labels in `--help` / errors (invariant names accepted but unlisted)
- `--reintegrate-model-name`: built-in model key is localized (`LegacyScoringModel.DEFAULT_NAME`), so
  `--reintegrate-model-name=Default` fails in ja/zh; error also prints `{0}` literally (CommandLine.cs ~2868)
- `--full-scan-isolation-scheme`: `IsolationSchemeList.GetDefaults` stores localized names as keys
  (e.g. `結果のみ`), so `Results only` is rejected for lists first created in a ja/zh UI
- Legacy fragment names (`y3`, `last y-ion`) not accepted on the command line (never were; nit)
- Filed as [#4696](https://github.com/ProteoWizard/pwiz/issues/4696) (all three pre-existing items, verified):
  - `--tran-product-add-special-ion` stores `p.Value` verbatim after a culture-insensitive check, while
    `GetMeasuredIonByName` is ordinal, so e.g. `tmt-127l` stores a null `MeasuredIon` that
    `ChangeMeasuredIons` does not filter (dereferenced at `TransitionSettings.cs:860/871`, written at `:1113`)
  - `--report-name` fails in ja/zh: `PersistedViews.GetDefaults` renames built-in views to localized
    resource names (one-way map, `PersistedViews.cs:160-185`), but `CommandLine.cs:3712` matches exactly
  - `TransitionFullScan.ChangePrecursorIsotopes` reads the pre-change `IsotopeEnrichments` (confirm intent first)
- Idea: model argument values once as (invariant key, localized label) pairs on `ArgumentBase`, with
  `Values`/`IsValidValue`/resolver derived from it, instead of `AcceptedValues` beside `Values`
- Idea: a public command-line argument for language selection. One already exists internally:
  `ARG_INTERNAL_CULTURE` (`CommandArgs.cs:143`, `--culture=en|fr|ja|zh-CHS...`), whose `SetCulture`
  (`:165`) sets `CurrentCulture` and `CurrentUICulture` and re-inits the thread, but it is
  `InternalUse = true` and sits in `GROUP_INTERNAL` with the test-only args, so it is undocumented
  and absent from `--help`. Making it public would give scripts control over the language of
  messages and accepted display names without changing the Windows language - the workaround
  Daopu actually needed, since SkylineCmd ignores Tools > Options > Language.
  Considerations: arguments are processed in order, so `--culture` only affects what is parsed
  after it (value lists are evaluated per argument), meaning it must come first to be useful;
  decide whether it also belongs in the usage/help output and the generated `CommandLine.html`;
  and a test should assert it changes message language, not just that it parses.

## Files Modified

- `pwiz_tools/Skyline/CommandArgs.cs`
- `pwiz_tools/Skyline/Model/DocSettings/TransitionSettings.cs`
- `pwiz_tools/Skyline/TestData/CommandLineTest.cs`
