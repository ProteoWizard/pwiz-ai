# TODO-20260914_cmdline_invariant_fragment_names.md

## Branch Information
- **Branch**: `Skyline/work/20260914_cmdline_invariant_fragment_names`
- **Base**: `master`
- **Created**: 2026-09-14
- **Status**: Completed
- **GitHub Issue**: [#4668](https://github.com/ProteoWizard/pwiz/issues/4668)
- **Module**: `skyline`
- **PR**: [#4669](https://github.com/ProteoWizard/pwiz/pull/4669) (merged 2026-09-29)

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
- [x] Code review (3 rounds) and Copilot rounds 1-2 ([#4669](https://github.com/ProteoWizard/pwiz/pull/4669))
- [x] Copilot round 3 (2026-09-23): `Values != null` gate bypassed `AcceptedValues` in
      `ArgumentBase.GetArgumentTextWithValue` and `NameValuePair.IsMatch`; both now gate on
      `IsValidValue`, with `ValuesForError` keeping the rejection message non-null. Latent today
      (no argument declares `AcceptedValues` alone). Test: `ValidateValueSources` covers all four
      combinations through both entry points
- [x] Exposed `--culture` (Brendan approved on #4668, 2026-09-23): as a workaround for the localized-key
      arguments we are putting off, a user on a ja/zh system can run SkylineCmd in English
  - `ARG_INTERNAL_CULTURE` -> public `ARG_CULTURE` in `GROUP_GENERAL_IO`, `_culture` description added
    to `CommandArgUsage.resx` (English only; translators own the ja/zh resx)
  - `Values` lists Skyline's localized languages for help, `HasValueChecking = true` so any culture name
    is accepted; `SetCulture` validates against `CultureInfo.GetCultures` and reports a usage error
  - Regenerated `Documentation/Help/{en,ja,zh-CHS}/CommandLine.html` via `IsRecordMode` (ja/zh rows carry
    the English description until translated)
  - Two of my own regressions, both caught by tests, not by reasoning: restricting `Values` to the display
    languages rejected `--culture=en-US`, which `SkylineCmdTest` passes on every invocation; and
    `CultureNotFoundException` never fires for well-formed names, so `not-a-culture` was accepted silently
- [x] Code review round 4 (`/code-review max`, 2026-09-28) and Copilot rounds 4-5 - see Progress Log
- [x] Human review - closed by the developer (2026-09-29)
- [x] Reply to support thread once fix ships - closed by the developer (2026-09-29)
- [x] Port to the .NET 10 branch: [#4742](https://github.com/ProteoWizard/pwiz/pull/4742)
      (`Skyline/work/20260929_net10_cmdline_invariant_values` into `Skyline/work/20260612_net8_port`,
      merged 2026-09-29 as `aec29a7127`)
- [x] Master follow-up [#4743](https://github.com/ProteoWizard/pwiz/pull/4743): zh-CHS parent check + soft hyphen escape
      (merged 2026-09-29 as `05b8c93b3a`)

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

## Progress Log

### 2026-09-28 - Final review rounds

- Copilot: `ARG_CULTURE + "en-US"` threw although parsing accepted it. Tried honoring `HasValueChecking` in
  `ArgumentBase.GetArgumentTextWithValue` again - reverted for the same reason as before
  (`ConsoleArgumentInvalidValuesTest`). Fixed with `AcceptedValues = GetKnownCultureNames` (1ecb1b598c).
- `/code-review max` returned 15 findings. Fixed (6311e7b3d4):
  - `CommandLine.Run` saves and restores `LocalizationHelper` and thread cultures around each command, so
    `--culture` no longer leaks through the in-process MCP / Immediate Window. It restores the thread cultures
    directly, not through `InitThread`, which would break commands run inside `CallWithCulture`. Verified red
    with the restore removed.
  - `SetCulture` validates the resolved `CultureInfo.Name` (catching `CultureNotFoundException`), so
    other spellings of a known name are accepted and a soft hyphen in the value is a usage error.
  - Multi-process import children get `--culture` when the UI culture differs from the original (the parent
    matches the localized error prefix). No test covers multi-process import.
  - `DISPLAY_LANGUAGE_NAMES` is `Lazy` (was ~115 ms per SkylineCmd run); `ParseKey` throws with
    `ValuesForError`; `_culture` added to `CommandArgUsage.Designer.cs`.
  - `--culture` kept setting formats as well as language (`SkylineCmdTest` relies on it), now documented in help.
  - Tests: a non-default "Test enrichment" makes the enrichment document assertions able to fail;
    `ValidateValueSources` hard-codes expected lists and compares whole messages.
- Dropped: console encoding with `--culture` under SkylineRunner / `--batch-commands`; case and Turkish-I
  matching in sibling args (pre-existing); localized help listing localized values (by design); defaults
  keyed by resource text (`--full-scan-isolation-scheme`, `--import-search-irts`, `--reintegrate-model-name`,
  already in Follow-up above).
- Copilot: regenerated `CommandLine.html` (en/ja/zh-CHS) for the new `_culture` text (1ac1c4b476).
- TeamCity: `en_US` is not resolved on every Windows version (agent rejected it, local machine accepted it);
  the test now uses a case change, `EN-us` (e4ea0e20b7).

### 2026-09-29 - Merged

PR #4669 merged as commit 10aac2d948. Shipped: the fragment finder, CE/DP/CoV/optimization library and
isotope enrichment arguments accept invariant names as well as localized ones in any UI language;
`ArgumentBase.AcceptedValues` for values accepted beyond the localized `Values`; and a public `--culture`
argument that applies to its own command only. Deferred: the Follow-up items above (#4696 filed for three of
them), the support-thread reply once a release carries the fix, and the .NET 10 port (task above).

### 2026-09-29 - .NET 10 port and master follow-up

- Port PR #4742: cherry-picked `10aac2d948`. Conflicts: the port's `ArgumentBase` (`operator +(ArgumentBase, object)`,
  moved to `Shared/CommonUtil/CommandLine`), the internal `--culture` example renamed to zh-Hans, and a whole-file
  conflict in `CommandLineTest.cs` because the port stores it LF and master CRLF (took the port's file and applied
  the PR's diff converted to LF). Help rows regenerated (`Help/zh-Hans`, per the port's rename in `dc12600f3a`).
- On .NET 10, `zh-CHS` is not in `CultureInfo.GetCultures` (parent `zh-Hans` is), so the #4669 known-culture check
  rejected it. `GetKnownCulture` now also accepts a culture whose parent is known; new `zh-CHS` test case red
  without it, green with it on net10.0-windows. Same code in master follow-up #4743 so later merges stay clean.
- Master had a literal U+00AD in `ConsoleCultureArgumentTest` where the escape was intended: Claude's Edit/Write
  tools decode a typed backslash-u escape in their input into the character. Fixed on both branches by byte-level replacement.
- Pre-existing: `Util/Adduct.cs:1206` had a U+00AD inside the adduct key "CH3CO2" (since #3201), so
  `[M+CH3CO2]` without a declared charge parsed as charge 0. Fixed in #4754 (2026-10-01), with a red-then-green
  case in AdductParserTest.
- #4743 merged to master as `05b8c93b3a`. #4742's first Skyline Windows .NET build failed `TestNativeMessageBox`
  ("Setting values is not supported for native dialog Dialog:Save As") on cloud agent
  `pwiz-windows-i-026de422cfdbcaf43`; unrelated to this change (#4735 passed on MacCoss TeamCity Agent 1).
  Re-run 4193863 queued on MacCoss TeamCity Agent 1.

### 2026-09-29 - Port merged

Re-run 4193863 passed on MacCoss TeamCity Agent 1 with no failed tests (TestNativeMessageBox included), confirming
the first failure was the cloud agent's environment. The Wine .NET Docker build, red only through its snapshot
dependency on the first run, passed on re-run 4193938. PR #4742 merged into `Skyline/work/20260612_net8_port` as
`aec29a7127`. All work for #4669 is complete on master and the .NET 10 branch.

## Files Modified

- `pwiz_tools/Shared/PortableUtil/CommandLine/ArgumentBase.cs`
- `pwiz_tools/Shared/PortableUtil/CommandLine/NameValuePair.cs`
- `pwiz_tools/Skyline/CommandArgs.cs`
- `pwiz_tools/Skyline/CommandArgUsage.resx`, `CommandArgUsage.Designer.cs`
- `pwiz_tools/Skyline/CommandLine.cs`
- `pwiz_tools/Skyline/Documentation/Help/{en,ja,zh-CHS}/CommandLine.html`
- `pwiz_tools/Skyline/Model/DocSettings/TransitionSettings.cs`
- `pwiz_tools/Skyline/Model/Results/ChromatogramCache.cs`
- `pwiz_tools/Skyline/TestData/CommandLineRefineTest.cs`
- `pwiz_tools/Skyline/TestData/CommandLineTest.cs`
