# TODO-20260610_cmd_compact_format.md

## Branch Information
- **Branch**: `Skyline/work/20260610_cmd_compact_format`
- **Base**: `master`
- **Created**: 2026-06-10
- **Status**: Completed
- **GitHub Issue**: [#4285](https://github.com/ProteoWizard/pwiz/issues/4285) (closed)
- **PR**: [#4288](https://github.com/ProteoWizard/pwiz/pull/4288) (merged 2026-06-15 as 6f041d31)
- **Checkout**: `C:\Dev\cmdline` (full built checkout)
- **Requester**: James (support thread rowId 75112)

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
- [x] Copilot review addressed (commit 1610a31ea, both threads resolved)
- [x] CI failure fixed: TestCommandLineHelpDocumentation (regenerated CommandLine.html)

## Copilot Review + CI (2026-06-11/12)
- [FIXED] Help-text wording: removed "(the default)"; clarified that omitting the
  argument uses the persisted CompactFormatOption setting (default largefilesonly).
- [FIXED] `CommandArgUsage.Designer.cs` had no `_save_compact_format` property while
  sibling keys do; added it for resx/designer consistency (works either way since
  Description reads via ResourceManager.GetString).
- [FIXED] TeamCity bt209 build #21255 failed TestCommandLineHelpDocumentation-en:
  the new arg changed `CommandArgs.GenerateUsageHtml()`, so the checked-in
  `Documentation/Help/{en,ja,zh-CHS}/CommandLine.html` reference files were stale.
  Regenerated via IsRecordMode toggle (ja/zh carry English fallback until translated).
  Second commit 1610a31ea pushed; all gates re-run green.
- [FIXED] Copilot 2nd pass (commit e96956c80, thread resolved): arg value validation
  used the framework default `CurrentCultureIgnoreCase`, which mishandles e.g.
  `LARGEFILESONLY` in Turkish locale (dotted-i). Set `HasValueChecking` on the arg and
  validate explicitly with `OrdinalIgnoreCase` in the handler (throwing
  `ValueInvalidException` for unknown values). Reverted the earlier
  `CompactFormatOption.Parse` change since the handler now owns case-insensitive matching.

## Lesson (for future SkylineCmd args)
- Adding a SkylineCmd argument requires regenerating the three checked-in
  `Documentation/Help/{en,ja,zh-CHS}/CommandLine.html` (via HelpDocumentationContentTest
  IsRecordMode) or TestCommandLineHelpDocumentation fails in CI - it is a TestFunctional
  test, outside the TestData gates run locally by default.
- For enumerated arg values, prefer explicit OrdinalIgnoreCase matching with
  HasValueChecking over the framework's CurrentCultureIgnoreCase default (locale safety).

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

### 2026-06-15 - Merged

PR #4288 merged as commit `6f041d31`; issue #4285 auto-closed. Requested by James
(support thread rowId 75112) — credited in the PR description.

**What shipped differs from the "threaded override" design above.** On review,
brendanx67 noted the threaded `CompactFormatOption` parameter never reached the
in-process Skyline MCP `RunCommand()` path (that path saves through the GUI's own
`SkylineFiles.SaveDocument` → `SerializeToFile`, which the extra parameter bypassed)
— and the entire CLI must work through MCP `RunCommand()`. He replaced the threading
with a **transient scoped override on `CompactFormatOption`** (`Effective` accessor +
`SetOverride` IDisposable scope), set for the whole invocation in `CommandLine.RunInner`
and read by `DocumentWriter`, so every save path (CLI and MCP) honors it; `FromSettings`
and the GUI options dialog are unchanged. `SrmDocument`/`JsonToolServer` reverted to
master. Our local threaded branch was abandoned in favor of his commits (3d6124317,
8e5b3812f); his approach is the cleaner expression of the same idea.

Post-refactor review handled: 4 Copilot comments addressed (`--save-as` added to the
no-save-target warning, commit 3d613513b; two thread-safety/race comments and a
`volatile` comment dismissed with reasoning — MCP command execution is serialized
[single-instance pipe + single ServerLoop thread] and the save's blocking `Invoke`
carries a memory barrier; the override mirrors the existing process-wide
`Settings.Default.CompactFormatOption`). Fresh-context self-review re-run on the merged
implementation: lifecycle/exception-safety/non-fatal-warning/locale all clean; its one
MEDIUM (a concurrent interactive save during an MCP command could adopt the override) is
benign (format-only, no autosave, narrow window) and consistent with the existing
override pattern (`Program.StartPageOverride`), so left as-is.

Deferred LOW items (unchanged): the `--share-zip` interaction is documented (CLI shares
copy the on-disk `.sky` verbatim, so save with `--save-compact-format` first).

Follow-up shipped to pwiz-ai (commit fa85a98): reporter-credit automation — `pw-startissue`
now resolves the requester first name at issue-start (incl. the `core.Users` lookup for
numeric support ids), `version-control-guide` documents that lookup, and a new
`Check-ReporterCredit` PreToolUse hook warns when a commit/PR closes an issue or links a
support thread without a credit line. No cherry-pick: this is a feature, and the current
release phase (Post-Release Patch Mode) takes bug fixes only.
