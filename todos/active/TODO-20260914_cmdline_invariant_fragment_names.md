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
- [ ] Commit and push branch
- [ ] Code review, PR
- [ ] Reply to support thread once fix ships

## Follow-up (not in this PR unless decided otherwise)

- Consider listing invariant names in `--help`
- Audit other command-line args whose value lists are localized labels

## Files Modified

- `pwiz_tools/Skyline/CommandArgs.cs`
- `pwiz_tools/Skyline/Model/DocSettings/TransitionSettings.cs`
- `pwiz_tools/Skyline/TestData/CommandLineTest.cs`
