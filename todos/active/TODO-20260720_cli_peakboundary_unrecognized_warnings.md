# Surface unrecognized rows on --import-peak-boundaries (CLI warning)

## Branch Information
- **Branch**: `Skyline/work/20260720_cli_peakboundary_unrecognized_warnings`
- **Base**: `master`
- **Status**: Active (started 2026-07-20)
- **Checkout**: `C:\Dev\cmdline`
- **GitHub Issue**: [#4439](https://github.com/ProteoWizard/pwiz/issues/4439)
- **PR**: [#4440](https://github.com/ProteoWizard/pwiz/pull/4440) (opened 2026-07-20, Fixes #4439)
- **Origin**: Deferred follow-up from #4350 (replicate-name keying). While testing that
  feature, James hit a silent no-op: `SkylineCmd --import-peak-boundaries` imports nothing
  when rows match no file/peptide/charge, giving no clue why. Requester: James.

## Problem

`PeakBoundaryImporter` already tracks every row it skips in three sets —
`UnrecognizedPeptides`, `UnrecognizedFiles`, `UnrecognizedChargeStates` — and the GUI
surfaces them via `PeakBoundaryImporterUI.UnrecognizedPeptidesCancel` (a bounded
summary + up to 10 items per category, OK/Cancel). The CLI path
(`CommandLine.ImportPeakBoundaries`) constructs the importer, calls `ModifyDocument`,
and **never inspects the three sets**, so a boundaries file that matches nothing (wrong
replicate name, wrong file name, unknown peptide, absent charge state) imports silently
and reports success. The user cannot tell the difference between "worked" and
"matched nothing".

`CommandLinePeakBoundaryTest` cases 8, 9, 10, 14 (`ImportNoException` after an
unrecognized file/peptide/charge) document exactly this silent-skip behavior.

## Scope

Additive, CLI-only. When `--import-peak-boundaries` finishes, emit a `Warning:` line per
non-empty Unrecognized* category (mirroring the GUI's summary + bounded item list), then
continue and keep the success exit code (a partial/empty match is a warning, not an error,
matching the GUI's default-continue). No change to the importer, the GUI path, or the
document result.

## Design decisions
- **Detail level**: mirror the GUI — a count header (singular/plural) per category plus up
  to 10 offending values, then `...` when truncated. Listing the unmatched identifiers is
  the actionable part (James's case: which replicate name failed to match).
- **New resource strings, not GUI reuse**: the GUI strings are dialog-worded
  ("Continue peak boundary import ignoring these peptides") — per team rule, do not reuse
  resource strings across contexts; author CLI-worded `Warning:` strings.
- **Non-fatal**: warn and continue; exit code unchanged. Works identically through the MCP
  `RunCommand()` path (import runs entirely in `CommandLine`, no GUI dependency).

## Tasks
- [x] Test-first (red): added `TestCommandLineImportPeakBoundaryWarnings` — asserts the file /
      peptide / charge-state warning surfaces, a clean import warns about nothing, and the list
      is bounded (12 unrecognized peptides -> plural header + `...`). Verified RED: with the
      `WarnUnrecognizedPeakBoundaries` call disabled the test fails on the missing file warning.
- [x] Implement: `CommandLine.ImportPeakBoundaries` now calls `WarnUnrecognizedPeakBoundaries`,
      which reads `importer.Unrecognized{Peptides,Files,ChargeStates}` and writes bounded
      (<=10 items + ellipsis) `Warning:` lines via a generic `WarnUnrecognizedItems<T>` helper.
- [x] Resource strings: 6 new keys in `SkylineResources.resx` (+ designer), singular/plural per
      category. Master resx only; translators handle ja/zh separately.
- [x] Gates (Debug, en unless noted): build green; `TestCommandLineImportPeakBoundaryWarnings`
      green en + fr; `TestCommandLineImportPeakBoundary` + `TestImportPeakBoundary` green;
      `CodeInspection` green (resx ordering canonical — SortRESX modified 0 files).
- [x] Full ReSharper solution inspection (Debug, CI-parity, jb 2026.1.3) on the final committed
      state: 0 warnings / 0 errors in all changed files; 0 findings of any severity inside the new
      CommandLine methods. Remaining notes are pre-existing style suggestions in the large files.
- [x] Self-review (fresh-context agent): clean; one LOW applied (ordering), one dismissed.
- [ ] Remaining: open PR (outward — awaiting go-ahead), then Copilot/optional review.

## Design notes (as built)
- Non-fatal: warnings only, exit code unchanged (a skipped row is a warning, matching the GUI's
  default-continue). The importer, GUI path, and document result are untouched.
- Ordering mirrors the GUI (`PeakBoundaryImporterUI.UnrecognizedPeptidesCancel`): peptides,
  then files, then charge states; each header count-aware (singular vs plural {0}).
- MCP `RunCommand()` path: warnings are plain `_out` writes, so they surface identically through
  the in-process MCP path — no GUI dependency, no scoped override needed.
- Edge (accepted): importing into a document with no results makes every row an unrecognized
  file (the file-match block is gated on `HasResults`); same as the GUI, and a meaningless input.

## Line numbers in the warnings (2026-07-20, per Brian)
- Each listed value is prefixed with the input-file line it first appeared on, e.g.
  `line 4: PEPTIDER`, so the user can jump straight to the offending row.
- Importer now records first-occurrence line numbers in three parallel dictionaries
  (`Unrecognized{Peptide,File,ChargeState}Lines`), populated only when the existing dedup
  `HashSet.Add` returns true. The deduped sets, the GUI, and the audit log are untouched —
  the dictionaries are additive, CLI-only data.
- New `"line {0}: {1}"` resource string; `WarnUnrecognizedItems<T>` takes the line dictionary
  and prefixes each shown value. Test asserts the cited line for each category and that exactly
  ten (bounded) line-prefixed items show in the >10 case (matcher built from the resource string,
  so it survives localization).

## "File or replicate name" wording (2026-07-20, per Brian)
- `UnrecognizedFiles` holds the file *identity*, which is the on-disk file name for FileName-keyed
  rows but the replicate name for replicate-keyed rows (#4350). The warning header now reads
  "file or replicate name(s)" so a replicate-keyed no-match (James's exact case) is labeled
  accurately instead of calling his replicate name a "file name". Keys renamed to match the values
  (strings are new in this branch, so no released/translated text is affected).

## Self-review (fresh-context agent, 2026-07-20)
- No HIGH/MEDIUM defects. Verified clean: line numbers correct (1-based, charge recorded only after
  peptide+file match), set/dict never diverge (dict written only inside `if (HashSet.Add(...))`, and
  the previously-ignored return value keeps GUI/audit-log semantics byte-identical), bound/ellipsis
  edge cases (exactly 10 vs 11), no throw paths, exit code/error-count unaffected, resx/designer
  consistency, existing tests unaffected.
- LOW (applied): the bounded 10 were taken in HashSet order, so a user with >10 bad rows might not see
  the *earliest* ones and cited lines could read out of order. `WarnUnrecognizedItems` now `OrderBy`
  first-appearance line before bounding; test asserts line 2 shown and line 13 truncated.
- LOW (dismissed): bare `@"..."` ellipsis literal — matches the existing GUI code
  (`PeakBoundaryImporterUI`), an ellipsis is not translatable, and CodeInspection passes.

## Files changed
- `Model/ImportPeakBoundaries.cs` — first-occurrence line dictionaries recorded at each skip site.
- `CommandLine.cs` — `WarnUnrecognizedPeakBoundaries` + generic `WarnUnrecognizedItems<T>` (line-prefixed).
- `SkylineResources.resx` + `.designer.cs` — 6 category warning strings + `"line {0}: {1}"`.
- `Test/CommandLinePeakBoundaryTest.cs` — `TestCommandLineImportPeakBoundaryWarnings`.
