# TODO-20260610_cmd_compact_format.md

## Branch Information
- **Branch**: `Skyline/work/20260610_cmd_compact_format`
- **Base**: `master`
- **Created**: 2026-06-10
- **Status**: In Progress
- **GitHub Issue**: [#4285](https://github.com/ProteoWizard/pwiz/issues/4285)
- **PR**: (pending)
- **Worktree**: `C:\Dev\cndline` (git worktree off `master_clean`)

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
- [ ] Add `ARG_SAVE_COMPACT_FORMAT` to `GROUP_GENERAL_IO` in `CommandArgs.cs`
      (modeled on `ARG_SHARE_TYPE`); store nullable override (null = use settings)
- [ ] Thread override: `CommandLine.SaveFile` -> `IDocumentOperations.SaveDocument`
      -> `SrmDocument.SerializeToFile`/`SerializeToXmlWriter` ->
      set `DocumentWriter.CompactFormatOption`
- [ ] Help text entry in `CommandArgUsage.resx` (master resx only;
      translators handle ja/zh-CHS separately)
- [ ] CommandLineTest: save with `=never` and `=always`, assert presence /
      absence of `<transition_data>` in output (translation-proof assertions)
- [ ] Build + run CommandLineTest and CodeInspection before commit
- [ ] /pw-self-review, then open PR (Fixes #4285), then Copilot review

## Notes / Decisions
- 2026-06-10: Issue #4285 filed from support thread. Branch + worktree created.
