# Consistent replicate-name keying in CLI (mProphet features export & peak boundary import)

## Branch Information
- **Branch**: `Skyline/work/20260616_cli_replicate_name_keying`
- **Base**: `master`
- **Status**: Active (started 2026-06-16)
- **Checkout**: `C:\Dev\cmdline`
- **GitHub Issue**: (pending)
- **Support thread**: https://skyline.ms/home/support/announcements-thread.view?rowId=75143

## Design decisions (2026-06-16)
- **Multi-file ambiguity**: when a replicate name resolves to a replicate that
  holds more than one file (multi-file replicate / multi-sample `.wiff`), FAIL
  with an explanatory message (per Brian) rather than guessing. Message should
  point the user at `FileName` (and optionally `SampleName`) to disambiguate.
- **Precedence when both columns present**: `FileName` wins per-row; the
  replicate-name path is used only when `filename` is absent/empty for that row.
  This keeps existing `FileName` behavior byte-identical (incl. the mProphet
  export -> peak-boundary import roundtrip in MProphetResultsHandlerTest, where
  both columns are present), so ambiguity-fail only triggers on the
  replicate-name path.
- **No CommandArgs/help changes**: both are file-format changes on existing args
  (`--exp-mprophet-features` output column; `--import-peak-boundaries` auto-
  detected input column), so no `CommandArgUsage.resx` / `CommandLine.html`
  regeneration gate (unlike #4288).
- **Export column placement**: `ReplicateName` is the **LAST** column (after the
  variable-length `main_var_/var_` feature columns), per Brian, so NO existing
  column index shifts -- protects any position-based downstream parser of the
  mProphet feature file. Always-on (not opt-in). This still changes
  `MProphetExpected.csv` -> must regenerate the checked-in expected files
  (en-US + intl) inside `Test\MProphetResultsHandlerTest.zip` (IsSaveAll).
- **Downstream risk (assessed)**: by-name parsers (R mProphet / pyprophet) ignore
  the extra named column; the only at-risk consumer is a positional/strict-schema
  script, which the last-column placement protects. Import side is zero-risk
  (recognizes an optional extra input column only).
- **Docs**: in-repo CLI help only for now (enrich `--import-peak-boundaries`
  help in `CommandArgUsage.resx` to mention the `ReplicateName` column; this
  re-incurs the `CommandLine.html` regen gate). skyline.ms wiki deferred.

## Problem

Two CLI interfaces have a fixed schema that exposes only the on-disk file
name, with no `Replicate.Name` equivalent. A user who keys everything on a
canonical, vendor-independent `Replicate.Name` (as custom reports allow via
`ResultFile.Replicate.Name`) is forced to re-couple to the on-disk filename
and its vendor extension (`.raw`, `.d`, `.wiff`, …):

1. `--exp-mprophet-features` — the exported CSV identifies rows only by
   `FileName`. To recover the replicate name the user has to run a second
   (custom report) export and join the mProphet rows back on the filename.
2. `--import-peak-boundaries` — the boundary CSV matches rows by a `FileName`
   column only. The user holds only the replicate name internally, so they
   reconstruct the filename (replicate name + vendor extension) to get a match.

Confirmed neither interface currently offers replicate-name keying, so this is
not a missed existing option. (The peak-boundary `filename` synonyms include
`R.FileName` and `align_origfilename`, but those are still the on-disk name.)

## Why it matters

As the user adds instrument support, depending on the on-disk filename and its
vendor extension is fragile. Keying on replicate identity matches how custom
reports already behave and decouples their pipeline from vendor specifics.

## Scope

Additive only — do NOT change existing `FileName` behavior. Offer
replicate-name keying *alongside* it:
- a `ReplicateName` column in the `--exp-mprophet-features` output, and
- `--import-peak-boundaries` accepting a replicate-name column (in addition
  to `FileName`).

## Code analysis (master_clean, 2026-06-16)

### Export — `Model/MProphetResultsHandler.cs`
- `WriteHeaderRow` (line ~218) writes a fixed column set:
  `transition_group_id, run_id, FileName, RT, MinStartTime, MaxEndTime,
  Sequence, PeptideModifiedSequence, ProteinName, PrecursorIsDecoy,
  mProphetScore, pValue, qValue` then the feature calculators.
- `WriteRow` (line ~291) derives the file name via
  `SampleHelp.GetFileName(features.Id.FilePath)`. There is a `run_id`
  (replicate index) but no replicate **name**.
- Headers are deliberately not localized (explicit comment ~line 50/221), so
  adding a literal `ReplicateName` column fits the convention.
- Approach: add a `ReplicateName` column to both header and row arrays. The
  replicate name is reachable from the document's `MeasuredResults` via the
  file path already in hand (`features.Id`), alongside the existing `run_id`.
  Low risk — purely additive output.

### Import — `Model/ImportPeakBoundaries.cs`
- `Field` enum (~line 111): `modified_peptide, filename, apex_time,
  start_time, end_time, charge, is_decoy, sample_name, q_value, score`.
- Synonym table at ~line 197; `filename` required.
- Matching (lines ~479–504): each row's `filename` is `MsDataFileUri.Parse`'d
  and resolved via `MeasuredResults.FindMatchingMSDataFile`, optionally
  narrowed by `sample_name` for multi-sample `.wiff`.
- Approach: add `Field.replicate_name` with synonyms (e.g. `"ReplicateName"`,
  `ColumnCaptions.Replicate`), keep it optional, and make `filename`
  non-required when a replicate column is present. When matching, resolve
  replicate name → `ChromatogramSet` directly (`chromSet.Name` already in hand
  at ~line 511) instead of going through `MsDataFileUri`.

## Open design question (settle before coding)

A replicate can hold multiple injected files (multi-file replicates /
multi-sample `.wiff`). Replicate name alone is unambiguous only at
1 file : 1 replicate — which is exactly this user's vendor-independent case.
Need a rule for the multi-file case: either apply the boundary to all files in
the replicate, or require `FileName`/`SampleName` as a tie-breaker when the
replicate is ambiguous.

## Tasks

- [ ] Settle the multi-file matching rule above.
- [ ] Export: add `ReplicateName` column to `--exp-mprophet-features`
      (header + row), sourced from `MeasuredResults` via the file path.
- [ ] Import: add optional replicate-name field + synonyms to
      `--import-peak-boundaries`; relax `filename` to non-required when a
      replicate column is present; resolve replicate name → `ChromatogramSet`.
- [ ] Tests (test-first): extend `CommandLineTest` / `CommandLinePeakBoundaryTest`
      to cover replicate-name keying for both interfaces.
- [ ] Verify both still work through the in-process MCP `RunCommand()` path,
      not just `SkylineCmd`.
- [ ] Update CommandLine.html help (en; translators handle ja/zh-CHS).
