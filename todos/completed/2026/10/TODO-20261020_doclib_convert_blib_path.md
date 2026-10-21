# TODO-20261020_doclib_convert_blib_path.md - Converted document library read its new index against the original .blib

## Branch Information
- **Branch**: `Skyline/work/20261020_doclib_convert_blib_path` (checkout `C:\Dev\BugFix`)
- **Base**: `master`
- **Module**: `skyline`
- **Created**: 2026-10-20
- **Status**: Completed
- **GitHub Issue**: (none)
- **Nightly failure**: https://skyline.ms/home/development/Nightly%20x64/testresults-showRun.view?runId=86204
- **PR**: [#4879](https://github.com/ProteoWizard/pwiz/pull/4879) (merged 2026-10-21)

## Objective
Fix `TestTargetedMSMSTutorialAsSmallMolecules`, which failed on all six Nightly x64 machines on
2026-10-20 (the first nightly after #4868) with "A peak blob of 2523 bytes inflated to 3080 bytes
where 5016 were expected".

## Root Cause
`BlibDb.MinimizeLibrariesHelper` writes the converted library to
`<name>.converted_to_small_molecules.blib`, but for a **document library** it only renamed the spec
(`ChangeName(... + DotConvertedToSmallMolecules)`, from 2017), keeping the original `FilePath`. The
`BiblioSpecLiteLibrary` built from the new file's index (ids, `NumPeaks`) therefore read peaks from
the original file. Instrumented: converted id 5 = KVPQVSTPTLVEVSR (627 peaks); original id 5 =
HLVDEPQNLIK (385 peaks) - exactly the 3080 vs 5016 bytes.

#4868 did not introduce the mismatch; its `BlibWriter.DecodeBlob` length check exposed it. The old
reader `Uncompress`ed into a `numPeaks`-sized buffer without validating, so the test most likely
showed wrong peaks silently before (not verified).

## Fix
- `Model/Lib/BlibData/BlibDb.cs`: after naming the minimized spec, point it at `blibDb.FilePath`
  when it names another file.
- `TestTutorial/TargetedMSMSTutorialTest.cs`: the small-molecule property-sheet expectations
  lacked `IdFileName` (captured from the wrong-file state); the converted library now reports the
  same `.perc.xml` as the peptide library, so `IdFileName` is expected in both modes.

## Validation (C:\Dev\BugFix, Debug)
- [x] TestTargetedMSMSTutorialAsSmallMolecules - was red (blob mismatch), now passes
- [x] TestTargetedMSMSTutorial - passes
- [x] Minimize/share paths: TestBuildLibraryShare, TestSaveDocumentLibraryAs,
  TestSaveDocumentLibraryAsLocked, TestMinimizeIrt, TestManageLibraryRuns, TestRetentionTimeManager,
  TestSaveAsAlignmentTarget, TestDiannGlobalQValueFilter (+SurviveMinimize, +Document),
  TestPdResultGlobalValues, TestPdResultLegacyGlobalValues - pass (TestDiannGlobalQValueFilter
  failed once on a leftover `.ses` temp file, then passed 3x alone and in its batch)
- [x] CodeInspection - passes

## Follow-up: Save As cleanup (from Brendan's approving review)
Save As carried a `DotConvertedToSmallMolecules` special case that existed only for the test-only
conversion path, which predicted the saved `.sky` name and wrote its library there.
- `SkylineFiles.RenameDocumentLibraryAs`: copies from the document library spec's `FilePath`
  (the same as `GetLibraryFileName(DocumentFilePath)` for any document opened from disk), skips
  the copy when source and destination are the same file (full-path compare), and no longer
  checks the suffix. The helper's first save now takes that skip.
- `TestSaveDocumentLibraryAs` extended: Save As of a document whose library spec names a marked
  copy in another folder must copy that marked file (red against the old copy source).
- Helper NOT changed in the end. Making it write to a separate folder (cbc4daf1dd) broke
  re-conversion: `TestTargetedMSMSTutorialAsSmallMoleculeMasses` converts, runs Import Peptide
  Search, then converts again - that save goes to the same name, so no Save As moves the library
  into place. e1d9ec6079 reverted the helper. Widening the Save gate to plain Save was also tried
  and failed TestSaveDocumentLibraryAs: replacing the `.blib` beside the `.sky` hits the file the
  previous library still holds open (Brendan's warned hazard). So the "conversion writes anywhere"
  half of the suggestion is not achievable while re-conversion saves in place.
- `RefinementSettings.ConvertToSmallMolecules` needed no change - ~30 unit-test callers depend
  on the suffixed names.
- Validated (e1d9ec6079): TestSaveDocumentLibraryAs, TestSaveDocumentLibraryAsLocked,
  TestTargetedMSMSTutorial, every `*AsSmallMolecules` test through the helper (TargetedMSMS x2,
  CEOptimization, StandardType, EditSpectrumFilter, MultiSelectPeakAreaGraph, AssayLibraryImport,
  Optimization, ExportIsolationList x4), CodeInspection - all pass. Master merged in (f0a13c16fd).

## Progress Log

### 2026-10-21 - Merged

PR #4879 merged as commit 3559e6c0fa. Shipped: the minimized document library spec now names the
`.blib` it writes (the nightly TestTargetedMSMSTutorialAsSmallMolecules blob-length failure), and
Save As copies the document library from its spec's file, removing the test-only
`DotConvertedToSmallMolecules` special case, with TestSaveDocumentLibraryAs extended to cover it.
Deferred by design, not as a follow-up: the "conversion writes its library anywhere" half of
Brendan's suggestion, because re-conversion saves in place (see Follow-up above). No issues filed.
