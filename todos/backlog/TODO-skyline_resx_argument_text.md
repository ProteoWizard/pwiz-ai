# TODO-skyline_resx_argument_text.md - command-line argument names out of translated text

## Branch Information
- **Branch**: (not started) - `Skyline/work/YYYYMMDD_resx_argument_text`
- **Base**: `master`
- **Module**: `skyline`
- **Created**: 2026-09-26 (Brendan, after the Osprey RESX session)

## Why
Skyline's `CommandArgs` / `Argument` made each command-line argument a typed instance that renders
its own text (`ARG_X.ArgumentText`), which is what generates `--help` and CommandLine.html. That
came after most of the command-line resources were written, so many English resources still spell
the flag out inline, and translators - who cannot know it is something a user types - sometimes
translate or drop it. The fix is the one Osprey's docs/21 now prescribes: the resource holds `{0}`
and the call site passes `ARG_X.ArgumentText` (or the value token), so the flag is never in
translated text and cannot drift from the parser.

## Measured 2026-09-26 (port-branch tree, session script in `ai/.tmp/sessions/20260926-resx/`)
- 93 English Skyline resources contain an inline `--flag`: 53 `CommandArgUsage.resx`,
  22 `SkylineResources.resx`, 17 `Properties/Resources.resx`, 1 SkylineBatch.
- Of the 76 with a translation, the flag set differs in 4 ja and 25 zh-Hans values. Confirmed
  real, not a matching artifact (the check needs an ASCII word boundary - CJK counts as `\w`):
  - zh `_refine_qvalue_cutoff`: `--refine-minimum-detections` was TRANSLATED to "调整最低检测" -
    the user is told to type a flag that does not exist.
  - ja and zh `_report_invariant`: the sentence "Specify --report-invariant=False ..." is gone.
  - others: `--report-file`, `--exp-isolation-list`, `--import-before` / `--import-on-or-after`,
    `--tool-program-macro`; zh `CommandArgs_GROUP_PANORAMA_postamble` gained an `--import-all`.

## Plan
1. Inventory every resource with an inline flag (and `=value` tokens such as `=False`,
   `--exp-method-type=triggered`), mapping each to its `CommandArgs.ARG_*` instance.
2. Rewrite each English value with `{N}` for the flag (and value token), update the call site to
   pass `ARG_X.ArgumentText` / `ARG_X + value` (the token builder Osprey's tests use). For
   `CommandArgUsage` descriptions, check how the usage renderer formats them - the argument
   description provider may need to supply the args.
3. Translations: update `.ja` / `.zh-Hans` values to the same `{N}` form (a mechanical rewrite of
   the flag text into `{N}` where the flag survived; for the 29 damaged values, restore the missing
   sentence with the flag as `{N}`) and mark them for the next review round
   (`FinalizeResxFiles` / "Needs Review" comments - see ResourcesOrganizer README).
4. Guard: a CodeInspectionTest check that no English .resx value under `pwiz_tools/Skyline`
   contains `(?<![A-Za-z0-9_-])--[a-z]` (exemption list for genuine prose uses, if any), and a
   LocalizedResourcesTest check that every translated value keeps the English value's `{N}` set.
5. Regenerate `Documentation/Help/en/CommandLine.html` (and the ja / zh-CHS help if generated)
   and confirm it is byte-identical in English.

Related: Osprey follows the same rule after the RESX PR
(`TODO-20260926_osprey_resx.md`; a few Osprey strings still inline `--decoys-in-library`,
`--parallel-files`, `--task PerFileScoring` - step 4 of `TODO-osprey_resx_translation.md`).
