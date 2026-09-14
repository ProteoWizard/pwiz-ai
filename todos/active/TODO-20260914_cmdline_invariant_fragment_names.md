# TODO-20260914_cmdline_invariant_fragment_names.md

## Branch Information
- **Branch**: `Skyline/work/20260914_cmdline_invariant_fragment_names`
- **Base**: `master`
- **Created**: 2026-09-14
- **Status**: In Progress
- **GitHub Issue**: [#4668](https://github.com/ProteoWizard/pwiz/issues/4668)
- **Module**: `skyline`
- **PR**: (pending)

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

## Follow-up (not in this PR unless decided otherwise)

- Fragment-finder args still list only localized labels in `--help`
- `NameValuePair`/`ArgumentBase` value checks use `CurrentCultureIgnoreCase` (possible Turkish-I mismatch; unverified)

## Files Modified

- `pwiz_tools/Skyline/CommandArgs.cs`
- `pwiz_tools/Skyline/Model/DocSettings/TransitionSettings.cs`
- `pwiz_tools/Skyline/TestData/CommandLineTest.cs`
