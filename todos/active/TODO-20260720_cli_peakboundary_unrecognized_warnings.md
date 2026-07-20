# Surface unrecognized rows on --import-peak-boundaries (CLI warning)

## Branch Information
- **Branch**: `Skyline/work/20260720_cli_peakboundary_unrecognized_warnings`
- **Base**: `master`
- **Status**: Active (started 2026-07-20)
- **Checkout**: `C:\Dev\cmdline`
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
- [ ] Remaining: full ReSharper solution inspection (CI-parity); open PR; self-review.

## Design notes (as built)
- Non-fatal: warnings only, exit code unchanged (a skipped row is a warning, matching the GUI's
  default-continue). The importer, GUI path, and document result are untouched.
- Ordering mirrors the GUI (`PeakBoundaryImporterUI.UnrecognizedPeptidesCancel`): peptides,
  then files, then charge states; each header count-aware (singular vs plural {0}).
- MCP `RunCommand()` path: warnings are plain `_out` writes, so they surface identically through
  the in-process MCP path — no GUI dependency, no scoped override needed.
- Edge (accepted): importing into a document with no results makes every row an unrecognized
  file (the file-match block is gated on `HasResults`); same as the GUI, and a meaningless input.

## Files changed
- `CommandLine.cs` — `WarnUnrecognizedPeakBoundaries` + generic `WarnUnrecognizedItems<T>`.
- `SkylineResources.resx` + `.designer.cs` — 6 CLI warning strings.
- `Test/CommandLinePeakBoundaryTest.cs` — `TestCommandLineImportPeakBoundaryWarnings`.
