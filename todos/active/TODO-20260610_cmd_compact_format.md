# TODO-20260610_cmd_compact_format.md

## Branch Information
- **Branch**: `Skyline/work/20260610_cmd_compact_format`
- **Base**: `master`
- **Created**: 2026-06-10
- **Status**: In Progress
- **GitHub Issue**: [#4285](https://github.com/ProteoWizard/pwiz/issues/4285)
- **PR**: [#4288](https://github.com/ProteoWizard/pwiz/pull/4288)
- **Checkout**: `C:\Dev\cmdline` (full built checkout)

## Objective
Add a SkylineCmd argument `--save-compact-format=never|largefilesonly|always`
to control the on-disk document compact format per-invocation, so headless /
container / CI saves produce deterministic, diffable `.sky` output without
depending on the persisted per-profile `CompactFormatOption` user setting.

Originating support request:
https://skyline.ms/home/support/announcements-thread.view?rowId=75112
(user runs SkylineCmd headless in a Docker/Wine container; current workaround
is seeding `SkylineCmd.exe.config` with `<setting name="CompactFormatOption">`).

## Key Design Points
- The three flag values map 1:1 to existing `CompactFormatOption.Name`
  (`never` / `largefilesonly` / `always`); `CompactFormatOption.Parse`
  already resolves them.
- `DocumentWriter.CompactFormatOption` is already a **settable** property
  (defaults to `CompactFormatOption.FromSettings()`), so only plumbing of an
  optional override is needed.
- The flag is a **transient per-invocation override** — it must NOT persist
  to `Settings.Default` (persisting would defeat the determinism goal by
  mutating the profile a headless run reads from).
- Absent the flag, behavior is unchanged (reads settings).

## Relevant Code (verified on master)
- `Model/Serialization/CompactFormatOption.cs` — `Name`, `Parse`, `ALL_VALUES`,
  `FromSettings`
- `Model/Serialization/DocumentWriter.cs:47,52` — settable `CompactFormatOption`
- `Model/SrmDocument.cs:2257` `SerializeToXmlWriter`, `:2289` `SerializeToFile`
- `CommandLine.cs:3507` `SaveFile(saveFile, commandArgs)`, `:80`
  `IDocumentOperations.SaveDocument`, `:4474` `SaveDocument(doc, outFile, outText)`
- `CommandArgs.cs:210-214` `ARG_SHARE_TYPE` (model for enumerated-value arg),
  `:245` `GROUP_GENERAL_IO`

## Tasks
- [x] Add `ARG_SAVE_COMPACT_FORMAT` to `GROUP_GENERAL_IO` in `CommandArgs.cs`
      (modeled on `ARG_SHARE_TYPE`); store nullable override (null = use settings)
- [x] Thread override: `CommandLine.SaveFile` -> `IDocumentOperations.SaveDocument`
      -> `SrmDocument.SerializeToFile`/`SerializeToXmlWriter` ->
      set `DocumentWriter.CompactFormatOption`
- [x] Help text entry in `CommandArgUsage.resx` (master resx only;
      translators handle ja/zh-CHS separately)
- [x] CommandLineTest: save with `=never` and `=always`, assert presence /
      absence of `<transition_data>` in output (translation-proof assertions)
- [x] Build + run CommandLineTest and CodeInspection before commit
      (ConsoleSaveCompactFormatTest, CodeInspection, DocumentSerializerTest,
      CommandLineImportTest all green)
- [x] /pw-self-review (fresh-context agent) — findings addressed below
- [x] Commit + push branch, open PR #4288 (Fixes #4285)
- [ ] Copilot review (auto, ~5 min) -> /pw-respond 4288

## Self-Review Findings (2026-06-10)
- [MEDIUM, FIXED] Case-sensitivity mismatch: CommandArgs validates arg values
  case-insensitively but `CompactFormatOption.Parse` matched case-sensitively, so
  `--save-compact-format=Always` passed validation then silently fell back to DEFAULT
  (largefilesonly) -> wrong, non-deterministic output. Fixed: `Parse` now uses
  `OrdinalIgnoreCase`. Added largefilesonly + case-variant (ALWAYS) test legs.
- [LOW, DEFER] Flag is silently ignored if no `--out/--save/--save-as` is given
  (no dependency check). Matches existing `--share-type` precedent. Deferred.
- [LOW, INVESTIGATED -> DEFER/DOCUMENT] `--share-zip` and `--save-compact-format`.
  Attempted to extend the flag into the share path, but investigation showed it is
  unreachable dead code for the CLI: `SrmDocumentSharing.Share` only re-serializes
  (`SaveDocToTempFile`) when `ShareType.MustSaveNewDocument` (== `SkylineVersion != null`)
  or `DocumentPath` is empty (SrmDocumentSharing.cs:321). The CLI never sets a share
  SkylineVersion (`--share-type` only picks minimal/complete, both null version) and
  always has a DocumentPath from `--in`, so every CLI share takes the `else` branch and
  copies the on-disk `.sky` VERBATIM. Therefore a `--share-zip` already inherits the
  compact format of the previously saved file (which honors `--save-compact-format`).
  Reverted the share extension (SrmDocumentSharing.cs, the ShareDocument call site, the
  test share legs, and the help-text mention) rather than ship untestable dead code.
  Resolution: document that to control compact format in a shared archive, save with
  `--save-compact-format` first; the share copies that file.

## Files Changed (C:\Dev\cmdline)
- `CommandArgs.cs` - ARG_SAVE_COMPACT_FORMAT + SaveCompactFormat property + group
- `CommandLine.cs` - threaded optional CompactFormatOption through IDocumentOperations
  .SaveDocument / concrete SaveDocument / SaveFile
- `Model/SrmDocument.cs` - optional CompactFormatOption through SerializeToFile/
  Serialize/SerializeToXmlWriter; non-null override beats settings default
- `Model/Serialization/CompactFormatOption.cs` - Parse now case-insensitive (self-review fix)
- `ToolsUI/JsonToolServer.cs` - GUI IDocumentOperations impl accepts (ignores) param
- `CommandArgUsage.resx` - `_save_compact_format` help text
- `TestData/CommandLineImportTest.cs` - ConsoleSaveCompactFormatTest

## Notes / Decisions
- 2026-06-10: Issue #4285 filed from support thread.
- 2026-06-10: Work moved from a mistaken `cndline` worktree to the built `cmdline`
  checkout (worktrees lack the native pwiz bindings, so they cannot build Skyline).
- Test seeds the OPPOSITE persisted setting in each direction to prove the flag
  overrides settings, and asserts the flag does not persist back.
- Arg values reuse `CompactFormatOption.Name` 1:1 via `CompactFormatOption.Parse`.
