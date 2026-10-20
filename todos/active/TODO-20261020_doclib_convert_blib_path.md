# TODO-20261020_doclib_convert_blib_path.md - Converted document library read its new index against the original .blib

## Branch Information
- **Branch**: `Skyline/work/20261020_doclib_convert_blib_path` (checkout `C:\Dev\BugFix`)
- **Base**: `master`
- **Module**: `skyline`
- **Created**: 2026-10-20
- **Status**: In Review
- **GitHub Issue**: (none)
- **Nightly failure**: https://skyline.ms/home/development/Nightly%20x64/testresults-showRun.view?runId=86204
- **PR**: (pending)

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
