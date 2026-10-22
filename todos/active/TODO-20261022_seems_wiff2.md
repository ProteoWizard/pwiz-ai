# TODO-20261022_seems_wiff2.md - SeeMS and MSConvertGUI could not open .wiff2 files

## Branch Information
- **Branch**: `Skyline/work/20261022_seems_wiff2` (checkout `C:\Dev\BugFix`)
- **Base**: `master`
- **Module**: `pwiz`
- **Created**: 2026-10-22
- **Status**: In Review
- **GitHub Issue**: (none)
- **PR**: [#4902](https://github.com/ProteoWizard/pwiz/pull/4902)

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
`VendorNativeCrt.targets` import.

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
- The wiff2 SDK reports these ACO-CE product-ion experiments as experiment type `MS`, so
  `TranslateAsSpectrumType` writes "MS1 spectrum" on ms level 2 spectra (cpp parity: the C++ reader
  writes the same), and no collision energy is reported. Affects Skyline's `HasDeclaredMSnSpectra`.
  Next item to work on.
