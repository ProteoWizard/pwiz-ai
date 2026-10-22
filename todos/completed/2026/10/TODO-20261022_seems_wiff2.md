# TODO-20261022_seems_wiff2.md - SeeMS and MSConvertGUI could not open .wiff2 files

## Branch Information
- **Branch**: `Skyline/work/20261022_seems_wiff2` (checkout `C:\Dev\BugFix`)
- **Base**: `master`
- **Module**: `pwiz`
- **Created**: 2026-10-22
- **Status**: Completed
- **GitHub Issue**: (none)
- **PR**: [#4902](https://github.com/ProteoWizard/pwiz/pull/4902) (merged 2026-10-22)

## Objective
SeeMS failed to open any .wiff2 file: "Unable to find an entry point named 'sqlite3_config' in DLL
'SQLite.Interop.dll'" from `SCIEX.Apis.Data.v1 ... SampleMetadataRequestHandler.GetSamplesDescriptions`.

## Root Cause
The wiff2 SDK runs in `Wiff2LoadContext`, which loads its own SQLite 1.0.109 (and matching
`SQLite.Interop.dll`), the Cecil-patched `Unity.Abstractions.dll` and the VC++ CRT from a `wiff2\`
subfolder beside the executable. MsConvert, MsDiff and Sciex.Tests stage that folder with a
`StageWiff2NativeAssemblies` target; SeeMS (which references `Sciex.Wiff2.csproj`) and MSConvertGUI
(which gets the plugin through its `MsConvert.csproj` reference and reads in-process via
`Compat.ReaderList`) never did. Without the folder the SDK falls back to System.Data.SQLite 1.0.119's
native DLL, which lacks `sqlite3_config`.

## Fix
`SeeMS.csproj` and `MsConvertGUI.csproj` get MsDiff's `StageWiff2NativeAssemblies` target plus the
`VendorNativeCrt.targets` import. After Copilot review the target moved to
`pwiz_tools/Shared/Lib/SciexWiff2Staging.targets`, imported by msconvert, MsDiff, SeeMS, MSConvertGUI
and Sciex.Tests; it fails the build if `VendorNativeCrt.targets` is not also imported. Skyline gets
`wiff2\` through its msconvert deployment and does not import it (noted in both files).

## Validation
Test file: `ACO-CE-DKTGKN_2-332-Positive-2026-10-21-10-20-43.wiff2` (SCIEX ACO-CE optimization sample).
- [x] SeeMS: reproduced the sqlite3_config failure, then opened the file after the fix (confirmed by Brian)
- [x] MSConvertGUI: converted the file after the fix (confirmed by Brian)
- [x] msconvert: already worked (has the target)
- [x] Skyline: reads the file (its output already had `wiff2\`)

## Findings Not Addressed Here
- The `[VendorSdkLoader] could not supply 'SCIEX.Apis.Control.v1'` stderr message is noise: OFX's
  `ComponentLoader.CreateComponent` probes optional types by name during license/event-broker setup
  and tolerates the miss (msconvert prints it too and converts fine). Its "load error reported below is
  a consequence" line is misleading in this case.
- The wiff2 SDK reports these ACO-CE experiments with triple-quad scan types ("ProductIon", "Q1MI")
  that the reader's ZenoTOF-only mapping sent to MS, so product ion scans came out "MS1 spectrum" with
  no collision energy, and the Q1MI point had m/z 0. Being fixed on
  `Skyline/work/20261022_wiff2_scantypes` (C:\Dev\Quickee).

## Progress Log

### 2026-10-22 - Merged

PR #4902 merged as commit fcc22b7f68. SeeMS and MSConvertGUI now stage the wiff2\ folder through the
shared `SciexWiff2Staging.targets`, which replaced the per-project copies in msconvert, MsDiff and
Sciex.Tests (Copilot review suggestion). Verified by rebuilding all five importers from a deleted
`wiff2\` (identical 53-file folders) and opening/converting the ACO-CE .wiff2 in SeeMS, MSConvertGUI
and msconvert. The squash commit's body landed with lines 2+ indented two spaces (cosmetic). Nothing
deferred from this PR's scope; the scan type work above continues separately.
