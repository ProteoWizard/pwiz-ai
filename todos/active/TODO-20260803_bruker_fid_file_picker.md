# TODO-20260803_bruker_fid_file_picker.md

## Branch Information
- **Branch**: `Skyline/work/20260803_bruker_fid_file_picker`
- **Module**: `pwiz` - the reported defect is an MSConvertGUI file picker failure and the fix
  restores reader-based identification in the shared dialog plus a Bruker reader correction;
  the only Skyline-side file is the unit test, which lives there because that is where the
  shared `CommonMsData` code is testable
- **Base**: `master` @ `5531ab22f`
- **Created**: 2026-08-03
- **Status**: In Progress - implemented, green, PR opened
- **GitHub Issue**: https://github.com/ProteoWizard/pwiz/issues/4510
- **PR**: https://github.com/ProteoWizard/pwiz/pull/4525
- **Cherry-pick to release**: no - post-release patch mode takes critical fixes only
  (crashes, data loss, security); this is a usability defect

## Objective

MSConvertGUI's file picker does not recognize Bruker FID data, descending into the
directory as if it were an ordinary folder instead of offering it as a source.

## Context

Reported by Michael Strobel in issue #4510, with `Test_FID_Data.zip`. A local copy of the
example data is at `D:\data\FID\DSM_105335_FID_File`.

Bruker FID is a directory tree - typically one subdirectory per MALDI spot, each holding a
spectrum directory (`1SLin`, `1SRef`, ...) with a `fid` file in it - and no level of it
carries a distinguishing extension the way Bruker BAF/TDF/TSF and Agilent `.d` folders do.

## Root cause

A regression from `6d497d12a`, "Add waters_connect support in MSConvertGUI (#4099)"
(Matt Chambers, 2026-05-18). That commit replaced MSConvertGUI's own `OpenDataSourceDialog`
with the shared `BaseFileDialogNE`, and in doing so dropped the delegate that asked the
reader about every folder:

```csharp
browseToFileDialog.FolderType = x =>
{
    string type = ReaderList.FullReaderList.identify(x);
    if (type == String.Empty)
        return "File Folder";
```

The shared dialog uses `DataSourceUtil`'s name-based rules instead, which have no entry for
any directory format without a distinguishing extension. `MainForm.IdentifySource` still
calls `identify()`, which is why the paste-the-path-and-click-Add workaround works while
browsing does not. SeeMS never went through that refactor and still does the reader-based
thing at `Dialogs/OpenDataSourceDialog.cs:487-499`.

## Changes

- `DataSourceUtil.GetSourceType(DirectoryInfo)` - when the name-based rules yield
  `FOLDER_TYPE`, ask the reader and take its answer. Restores the pre-#4099 behavior, and
  covers Bruker YEP and U2 as well as FID without a special case for any of them.
- `MsDataFileImpl.IdentifySourceType()` - wrapper needed to reach `ReaderList::identify`
  from `CommonMsData`.
- `Reader_Bruker_Detail.cpp` - the ten `fid` probes in `format()` now test
  `exists() && !is_directory()` through a new `is_fid_file()` helper. Necessary rather than
  incidental: `bfs::exists()` is true for directories, so with plain `exists()` any folder
  containing a subfolder named `fid` identifies as Bruker FID and becomes unnavigable. Found
  on `D:\Data`, which holds a folder named `FID`. Deliberately not `is_regular_file()`, which
  would reject a fid reached through a reparse point (cloud storage placeholder, compressed
  file).

## Deliberately out of scope

- The bare `fid` **file** still reports `unknown` rather than being selectable. Matt Chambers
  noted on the issue that FID is a single-spectrum format and the parent or grandparent
  directory is the useful selection, since it rolls up every spot into one mzML with spot
  IDs. Skipping it also avoids an `identify()` call per unrecognized file in every listing.
- Type-string vocabulary cleanup. `DataSourceUtil`'s display constants do not match the
  reader's own type names (`TYPE_BRUKER` = "Bruker BAF/TDF/TSF" vs the reader's separate
  "Bruker BAF"/"Bruker TDF"/"Bruker TSF"; `TYPE_AGILENT` = "Agilent MassHunter Data" vs
  "Agilent MassHunter"). Because `BaseFileDialogNE` filters by exact string equality against
  the type, MSConvertGUI's "Sources of type" dropdown already matches nothing for Bruker or
  Agilent. Pre-existing, orthogonal, and worth its own change.

## Known consequences of restoring reader-based identification

Both follow from the reader's intentional design rather than from this change, and neither
is a regression from master:

- A container folder directly above a spot-less acquisition (`Root\Exp1\1SRef\fid`) is
  itself identified as FID, so `Root` becomes unnavigable. This is the same
  check-the-first-subdirectory heuristic Matt described as deliberate, now visible in the
  dialog.
- FID directories are not navigable once selectable, so descending to a single spot by
  browsing is not possible. Pasting a spot path works, and the parent is the intended
  selection anyway.

## Testing

- `TestGetSourceType` (new, `Test.csproj`) - acquisition and spot directories are sources;
  the folder holding the acquisition, a folder holding a directory named `fid` or `FID`, and
  an ordinary folder are not. Mutation-verified: reverting `is_fid_file` to bare `exists()`
  fails at `HoldsLowerCaseFid`.
- `Reader_Bruker_Test` (C++) - passes; its data includes a real `1SRef/fid` tree.
- Real data at `D:\data\FID` - acquisition and every level below it selectable, `D:\Data`
  itself still a plain folder, sibling `.mzML` unaffected.
- `CodeInspectionTest` and full-solution ReSharper inspection.

## Notes for the next session

- The native DLL Skyline loads is the `--without-compassxtract` variant. Rebuilding
  `pwiz/utility/bindings/CLI` alone updates a *different* variant and leaves Skyline running
  stale code. Use
  `quickbuild.bat ... --without-compassxtract ... pwiz_tools/Skyline//install-native-dependencies`,
  which stages into `ProteowizardWrapper/obj/x64`, and verify by timestamp before trusting a
  green run.
