# Consistent replicate-name keying in CLI (mProphet features export & peak boundary import)

## Branch Information
- **Branch**: `Skyline/work/20260616_cli_replicate_name_keying`
- **Base**: `master`
- **Status**: Completed
- **Checkout**: `C:\Dev\cmdline`
- **GitHub Issue**: [#4351](https://github.com/ProteoWizard/pwiz/issues/4351)
- **PR**: [#4350](https://github.com/ProteoWizard/pwiz/pull/4350) (merged 2026-07-20 as db2f5943, Fixes #4351)
- **Support thread**: https://skyline.ms/home/support/announcements-thread.view?rowId=75143
- **Requester**: James

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

- [x] Settle the multi-file matching rule above → FAIL with explanatory message
      (see Design decisions); FileName wins per-row when both columns present.
- [x] Export: `ReplicateName` column added to `--exp-mprophet-features` as the
      LAST column, sourced from `features.Id.ChromatogramSet.Name`
      (`MProphetResultsHandler.WriteHeaderRow`/`WriteRow` + `WriteTrailingField`).
- [x] Import: added `Field.replicate_name` + synonyms (`ReplicateName`,
      `ColumnCaptions.Replicate`); relaxed `filename` to non-required via
      `FILE_ID_FIELDS` + new `anyOfFields` param on `ReadFirstLine`/
      `DetermineCorrectSeparator`; `FindReplicateFileMatch` resolves replicate →
      single-file `ChromSetFileMatch` and throws on multi-file ambiguity.
- [x] Tests: `PeakBoundaryTest` — replicate-keying == filename-keying
      (`DocumentCloned`) + multi-file ambiguity throws the new resource string
      (synthesized multi-file replicate via `ChangeSettingsNoDiff`).
      `MProphetResultsHandlerTest` — regenerated `MProphetExpected.csv` (+ intl)
      in the zip; explicit last-column assertion.
- [x] MCP `RunCommand()` path: no divergence to worry about here. Unlike #4288
      (which bypassed via the GUI save path), both features run entirely through
      `CommandLine.cs` -> `PeakBoundaryImporter.Import` / `WriteScores`
      regardless of entry point; the mProphet export writes its CSV directly and
      the peak-boundary import mutates the in-memory doc before whatever save
      path runs. No scoped-override needed.
- [x] Help: enriched `--import-peak-boundaries` text in `CommandArgUsage.resx`;
      regenerated `Documentation/Help/en/CommandLine.html` (ja/zh unchanged — they
      already carry translations of this key; translators update separately).

## Gate results (2026-07-01, Debug unless noted)

- Build: green.
- `TestImportPeakBoundary` + `TestImportPeakBoundaryAsSmallMolecules`: green.
- `TestCommandLineImportPeakBoundary`: green.
- `TestMProphetResultsHandler`: green in en-US AND fr-FR (verifies both expected
  CSVs are byte-exact after in-place regeneration — the single-replicate doc let
  me append the column deterministically rather than capture temp files).
- `ConsoleMProphetModelTest`: green.
- `TestCommandLineHelpDocumentation`: green (was red until HTML regen).
- `CodeInspection`: green.
- Full ReSharper solution inspection (Release, CI-parity): clean for changed
  files (only pre-existing ExportMethodDlg phantom FP, #4312 not in this base).
- Fresh-context self-review (pre-PR): clean — no HIGH/bugs; one MEDIUM design-
  nuance (SampleName is inert on the replicate path, which is intended).

## Review round (commit 9fe785eed, 2026-07-01)

- **Copilot** (1 comment, resolved): test used a bare `"ReplicateName"` literal.
  Introduced shared `MProphetResultsHandler.REPLICATE_NAME_COLUMN` const, now
  referenced by the exporter, the import synonym, and the test — single source
  of truth, no drift. (The literal was locale-safe; headers are non-localized.)
- **`/pw-self-review` on PR #4350** (fresh context): clean, no HIGH/MEDIUM;
  independently re-verified the byte-identical claim, separator/anyOfFields,
  MCP path, multi-sample-wiff ambiguity, and tests. Two LOW fixes applied:
  `FindReplicateFileMatch` now uses `TryGetChromatogramSet` and treats only
  `FileCount > 1` as ambiguous (0-file replicate -> unrecognized, accurate msg).
- **Case-sensitivity** (self-review Q): kept ordinal/case-sensitive replicate
  matching — matches Skyline's internal `_dictNameToIndex` and James's exact
  programmatic keying. Documented decision, not a bug.
- Post-fix gates green: build, TestImportPeakBoundary, TestMProphetResultsHandler,
  CodeInspection.
- Merged master (web "Update branch") into the branch (commit 673443481, clean,
  no conflicts). Final full ReSharper inspection on the merged tree: **0 errors,
  0 warnings** (CI-parity). Reviewer: Nick Shulman assigned.

## TeamCity bt209 build 21452 FAILED -> fixed (commit 3c7cbf9eb, 2026-07-07)

- **Root cause**: a SECOND mProphet-export comparison test I missed locally --
  `pwiz.SkylineTestData.CommandLineTest.ConsoleExportMProphetTest` (TestData
  project, runs `--exp-mprophet-features` via the CLI and `AssertEx.FileEquals`
  against checked-in CSVs). The new `ReplicateName` last column made `actual`
  differ from the stale expected at line 1 pos 954. I had regenerated the
  `Test`-project `MProphetResultsHandlerTest.zip` but not this one.
- **Fix**: regenerated all 3 expected CSVs x {en, Intl} in
  `TestData\ConsoleExportMProphetTest.zip` (single replicate `Lepto4x_D2_M1`, so
  the same deterministic in-place column append). Verified: ConsoleExportMProphetTest
  green in en-US AND fr-FR locally.
- The build's only real failure was this one (the reported "2 failed" counts the
  installer/deployment test wrapper that hosts it). Steps 4-9 were skipped by the
  step-3 failure, so re-run bt209 will exercise TestFunctional/French/ja-zh.
- **Swept for others**: only two tests compare mProphet export output
  (MProphetResultsHandlerTest + ConsoleExportMProphetTest, both fixed). The two
  TestFunctional hits (DdaScoringTest, MixedSrmPrmTest) only call
  `GetPeakFeatures` in-memory, no CSV compare -> unaffected. ComparePeakBoundaries
  left unchanged, so peak-boundary compare tests unaffected.

## CLI end-to-end coverage for no-FileName import (commit a92a6d176, 2026-07-08)

- Refreshed branch against new master (merge 42caab9f5).
- Added a `CommandLinePeakBoundaryTest` leg: import a boundaries file with a
  `ReplicateName` column and NO `FileName` column via `--import-peak-boundaries`,
  assert same document as FileName keying. This covers the real **file-overload**
  path (`Import(string inputFile, ...)` incl. `IsMinutesPeakBoundaries`) that the
  importer-level `PeakBoundaryTest` (reader overload) did not exercise -- i.e.
  exactly James's usage. Green in en-US + fr-FR; CodeInspection green.
- Confirms the file-identity relaxation (filename OR replicate_name): a CSV with
  only a `ReplicateName` column passes header validation and keys every row on the
  replicate; `GetField(filename)` returns null -> `useReplicate` true.

## James tested build bt209/4080835 -> found a bug (commit 9ffdab350, 2026-07-08)

- James ran `SkylineCmd --import-peak-boundaries` with a replicate-keyed CSV and got
  `Failed to find the necessary headers FileName in the first line`.
- **Root cause**: the `replicate_name` synonym used `ColumnCaptions.Replicate`
  (= "Replicate") instead of `ColumnCaptions.ReplicateName` (= "Replicate Name").
  A custom report projecting `ResultFile.Replicate.Name` emits the header
  **"Replicate Name"** (display) or **"ReplicateName"** (invariant) -- never
  "Replicate". So his report-style "Replicate Name" header matched no synonym,
  file-identity check failed, and the error (wrongly) named only FileName.
- **Fix**: synonym -> `ColumnCaptions.ReplicateName`; now accepts "ReplicateName"
  (export/invariant) + "Replicate Name" (report display caption, localized).
  This is the "recognize our own report headers" goal.
- **Message fix** (per Brian): missing-file-identity error now reads
  "...necessary headers FileName or ReplicateName..." (either suffices), via a new
  `ModelResources.PeakBoundaryImporter_ReadFirstLine__0__or__1_` = "{0} or {1}"
  (CodeInspection/AssortResources moved it to ModelResources since it is Model-only;
  the FindReplicateFileMatch string stays in Resources.resx because a test references it).
- Tests: PeakBoundaryTest now imports via the "Replicate Name" caption (== filename
  keying) and asserts the FileName-or-ReplicateName wording. Green en-US + fr-FR;
  CodeInspection green.
- STILL WANT James's actual CSV (Brian asked in thread) to confirm his exact header
  and cover any other spelling.

## Broadened to all report header spellings + L10N (commit e565c4d69, 2026-07-08)

- "Replicate" (object column) and "Replicate Name" (Replicate.Name property) are
  DIFFERENT report columns but both export the replicate NAME (Replicate.ToString()
  returns Name). Plus the invariant "ReplicateName". So the synonym now accepts all
  three: `{REPLICATE_NAME_COLUMN, ColumnCaptions.ReplicateName, ColumnCaptions.Replicate}`.
- **L10N**: recognition is per-display-language (FIELD_NAMES loops
  `CultureUtil.AvailableDisplayLanguages()`), so ja/zh report headers are accepted:
  Replicate = 繰り返し測定 / 重复测定, ReplicateName = 繰り返し測定名 / 重复测定名称
  (both translations exist in ColumnCaptions.{ja,zh-CHS}.resx). Verified by running
  PeakBoundaryTest in en-US, ja, AND zh-CHS (headers built from the localized captions).
- No new translator work: reuses existing translated captions. Export header stays
  invariant "ReplicateName" (mProphet file convention). Only the new "{0} or {1}"
  fragment is master-only until translators localize "or" (cosmetic for ja/zh).

## SampleName support (commit e3e55953b, 2026-07-08)

- Per Brian ("let's support SampleName, even though it's probably uncommon"),
  relaxed the earlier "fail on any multi-file replicate" rule: `FindReplicateFileMatch`
  now takes the row's `sample_name` and, for a multi-file replicate, selects the
  file whose `MsDataFileUri.GetSampleName()` matches. Exactly-one match -> use it;
  zero or >1 -> explanatory "sample does not match a single file in replicate" error.
  No SampleName + >1 file -> the original ambiguity error (message reworded to point
  at adding a SampleName column). Single-file replicate + no SampleName unchanged.
- New resource `PeakBoundaryImporter_..._The_sample___0___..._does_not_match_a_single_file_in_the_replicate___2__`
  (stays in Resources.resx -- shared, referenced by the test).
- Tests: synthesized a 2-sample replicate (MsDataFilePath with sample names A/B);
  matching SampleName resolves (0 unrecognized peptides/files), wrong SampleName
  throws. Green en-US + ja; CodeInspection + small-molecule green.

## James's failure was the wrong build (2026-07-08)

- Brian pointed James at bt209/4080835 = build #21471 of **pull/4340** (a DIFFERENT
  PR, commit a30c9264) -- it did NOT contain this feature. That explains his
  "necessary headers FileName" error (pre-feature filename-required) and the later
  silent no-op. His header was "ReplicateName" (no space, already accepted) -- so the
  caption fix, while a good improvement, was NOT his root cause.
- Correct build for James: bt209 #21487 = ID **4083087**, commit e565c4d69 (latest
  green for PR #4350). SkylineTester URL:
  https://mc-tca-01.s3.us-west-2.amazonaws.com/ProteoWizard/bt209/4083087/SkylineTester.zip
- OPEN: `--import-peak-boundaries` silently imports nothing when rows match no
  file/peptide (UnrecognizedFiles/Peptides/ChargeStates not surfaced by the CLI).
  Consider surfacing a warning -- separate improvement, not yet done.

## Copilot round 2 + ComparePeakBoundaries (commit 284507207, 2026-07-08)

Copilot re-reviewed on 2026-07-08 (5 comments). All replied + threads resolved:
- [FIXED] `CommandArgUsage.resx` / `CommandLine.html` help said ReplicateName "must
  identify a replicate containing a single file" -- stale after SampleName. Reworded
  to mention adding a SampleName column; CommandLine.html regenerated (en; ja/zh keep
  existing translations).
- [FIXED] `FindReplicateFileMatch` set ChromSetFileMatch fileOrder=0. Now computes the
  global running file index via `GetGlobalFileOrder` (matches FindMatchingMSDataFile).
  (It's unused in the import path, but consistent now.)
- [FIXED] `PeakBoundaryTest` missing-header assertion used hardcoded "FileName"/
  "ReplicateName"; now uses `STANDARD_FIELD_NAMES[(int)Field.filename|replicate_name]`.
- [DISMISSED w/ reasoning] `ModelResources.designer.cs` version 4.0.0.0 vs 17.0.0.0:
  AssortResources.exe (run by CodeInspectionTest) emits 4.0.0.0 and the inspection
  passes on it, so it's CI-canonical here; hand-reverting would be re-flipped. Toolchain
  artifact, not correctness.
- Also extended `ComparePeakBoundaries` (Brian): its separator peek dropped the
  filename requirement + passes FILE_ID_FIELDS, so a replicate-keyed file is handled
  consistently there too. `TestPeakBoundaryCompare` green.
- Decision (Brian): keep erroring when a single-file replicate is given a non-matching
  SampleName (mirrors the FileName+SampleName mismatch error) -- no code change.
- Gates: build + PeakBoundaryTest (en/ja/zh + small-mol) + CommandLinePeakBoundaryTest
  + TestCommandLineHelpDocumentation + ConsoleExportMProphetTest + TestPeakBoundaryCompareTest
  + CodeInspection all green. (Full ReSharper re-run on the later merged head b76170792 --
  see below.)

## PR body rewritten + inspection re-run on merged head (2026-07-13)

The PR #4350 description had gone stale: it still described the design as of the first
commit (3cf4d7eb8), while four substantive commits landed after it. Rewrote the body to
match the branch:
- The "Ambiguity" bullet claimed a multi-file replicate always fails with an error --
  false since e3e55953b, where an optional `SampleName` column selects one file within
  the replicate (the error survives only with no SampleName, or one matching != 1 file).
- No mention of the accepted report header spellings (`ReplicateName`, the "Replicate
  Name" property caption, the "Replicate" object caption; per-display-language), which
  is what actually fixed James's `Failed to find the necessary headers FileName`.
- No mention of `ComparePeakBoundaries` (separator peek) or the "FileName or
  ReplicateName" error wording.
- Test plan lumped `TestImportPeakBoundary` with `...AsSmallMolecules`, overstating
  coverage: the new replicate-keying block is inside `if (!AsSmallMolecules)`.
- The "0 errors / 0 warnings" line was an unverified carry-over from an older tree.

Re-ran the inspect gate on the current merged head **b76170792** (Release, CI-parity):
build green, `CodeInspection` green, full ReSharper solution inspection **0 errors /
0 warnings** (368s). The test-plan line now names the head it was run against.

## Lesson

- Adding a column to the mProphet feature export breaks expected-file comparisons
  in BOTH `Test\MProphetResultsHandlerTest.zip` AND
  `TestData\ConsoleExportMProphetTest.zip` (the latter has 3 CSVs x en/Intl). The
  TestData `CommandLineTest` suite is NOT in the default local TestData gate I ran
  -- run `ConsoleExportMProphetTest` explicitly, or the full `CommandLineTest`
  class, when changing any `--exp-*` CLI output format.

### 2026-07-20 - Merged

PR #4350 merged to master as commit db2f5943 (squash), Fixes #4351. Shipped
replicate-name keying across both SkylineCmd interfaces: `--exp-mprophet-features`
now emits a trailing `ReplicateName` column (last, so no existing column index
shifts), and `--import-peak-boundaries` accepts a `ReplicateName` / "Replicate Name" /
`Replicate` column (all per-display-language), keying a row by replicate name when it
carries no `FileName` (FileName still wins per row). A multi-file replicate is
disambiguated by an optional `SampleName` column, else the row fails with an
explanatory message. Same file-identity relaxation extended to `ComparePeakBoundaries`,
and the missing-header error now reads "FileName or ReplicateName". Deferred (not in
scope of this PR): surfacing a CLI warning when `--import-peak-boundaries` matches no
file/peptide/charge (rows silently skipped) — noted as a separate improvement.

## Files changed (C:\Dev\cmdline)

- `Model/MProphetResultsHandler.cs` — `ReplicateName` last column + `WriteTrailingField`.
- `Model/ImportPeakBoundaries.cs` — `Field.replicate_name`, `FILE_ID_FIELDS`,
  `RequiredFieldsForImport`, `anyOfFields` plumbing, per-row precedence,
  `FindReplicateFileMatch`, cache key -> `Tuple<string,string,bool>`.
- `Model/ComparePeakBoundaries.cs` — separator peek drops the filename requirement,
  passes `FILE_ID_FIELDS` (replicate-keyed files detect their separator).
- `Properties/Resources.resx` + `Resources.Designer.cs` — ambiguity + SampleName-mismatch
  error strings.
- `Model/ModelResources.resx` + `ModelResources.designer.cs` —
  `PeakBoundaryImporter_ReadFirstLine__0__or__1_` ("{0} or {1}", Model-only per
  AssortResources).
- `CommandArgUsage.resx` — `--import-peak-boundaries` help text (ReplicateName +
  SampleName).
- `Documentation/Help/en/CommandLine.html` — regenerated.
- `Test/PeakBoundaryTest.cs` — replicate keying, both report captions, missing-header
  wording, multi-file ambiguity, SampleName resolve + mismatch (proteomic-only block).
- `Test/CommandLinePeakBoundaryTest.cs` — CLI end-to-end replicate-keyed import
  (file-overload path incl. minutes/seconds detection).
- `Test/MProphetResultsHandlerTest.cs` — last-column assertion.
- `Test/MProphetResultsHandlerTest.zip` — regenerated `MProphetExpected.csv` (+ intl).
- `TestData/ConsoleExportMProphetTest.zip` — regenerated expected CSVs (en/Intl).
