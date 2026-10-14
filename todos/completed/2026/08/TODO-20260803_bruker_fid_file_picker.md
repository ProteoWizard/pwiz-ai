# TODO-20260803_bruker_fid_file_picker.md

## Branch Information
- **Branch**: `Skyline/work/20260803_bruker_fid_file_picker`
- **Module**: `pwiz` - the reported defect is an MSConvertGUI file picker failure and the fix
  restores reader-based identification in the shared dialog plus a Bruker reader correction;
  the only Skyline-side file is the unit test, which lives there because that is where the
  shared `CommonMsData` code is testable
- **Base**: `master` @ `5531ab22f`
- **Created**: 2026-08-03
- **Status**: Completed
- **GitHub Issue**: https://github.com/ProteoWizard/pwiz/issues/4510
- **PR**: [#4525](https://github.com/ProteoWizard/pwiz/pull/4525) (merged 2026-08-17 as `656bd2b288`)
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

## Listing cost - measured, accepted

Asking the reader means every folder that the name rules do not recognize pays one
`ReaderList::identify` sweep. Measured on a local SSD, warm, 3 runs after warm-up:

| Target | Readable subdirs | identify() | Rest of GetSourceType |
|--------|------------------|------------|-----------------------|
| `C:\Windows` | 76 | 0.705 ms/folder | 0.959 ms/folder |
| `pwiz_tools\Skyline` | 41 | 0.377 ms/folder | 0.250 ms/folder |

So it roughly doubles the per-folder cost, on top of the two directory enumerations
`GetSourceType(DirectoryInfo)` already did. Locally that is +0.4-0.7 ms per folder, so
+0.1 s for 200 folders. Accepted as proportionate - and it is the same call MSConvertGUI
made on every folder before #4099, so this restores a cost the dialog used to carry.

Not measured: SMB/VPN/OneDrive, where round trips dominate. The ratio above suggests
doubling rather than a blowup, but that is extrapolation, not measurement.

Considered and rejected: skipping the reader on network drives via the existing
`DriveMightBeSlow` (`BaseFileDialogNE.cs:1556`), because it would silently stop
recognizing FID on shares - where instrument data usually lives - trading a performance
worry for a correctness hole. Worth doing separately if listing ever needs the work:
memoize per path (the cost is re-paid on filter change, F5 and Details toggle), or move
the listing onto a cancellable BackgroundWorker as SeeMS does
(`SeeMS/Dialogs/OpenDataSourceDialog.cs:491`). The loop is at least cooperatively
interruptible today - `Application.DoEvents()` and an `_abortPopulateList` check run per
item.

### Follow-up after Matt's review comment (2026-08-12)

Matt asked for profiling on large directories, remembering that Skyline hand-rolled
recognition because the reader was slow on them. Re-measured through
`pwiz_data_cli.dll`, local NVMe, warm:

| Shape | identify() | GetSourceType, gated |
|-------|-----------|----------------------|
| Ordinary folder, 5 files + 2 subdirs | 0.36 ms | 0.43 ms |
| Leaf folder, files only | 0.24 ms | 0.08 ms |
| Directory of 20000 files | 5.5 ms | 16.3 ms |
| Waters `.raw` / Agilent `.d` | not called | 0.06 ms |

Not recursion: `format()` walks one level and breaks at the first non-matching entry.
The per-entry term is `Reader_ABI_T2D::identify`, which globs `*.t2d`, `MS/*.t2d` and
`MSMS/*.t2d` - giving a 20000-entry directory equally large `MS/` and `MSMS/`
subdirectories took identify from 6.6 to 11.4 ms. `Reader_Waters` globs `_FUNC*.DAT`,
which seeks on its literal prefix and stays cheap.

Done in response:

- `GetSourceType` asks the reader only about directories that could be one - holding
  subdirectories, or a Bruker file name, or a `.u2`. Note `Reader_Bruker_Detail.cpp:106`
  wraps the whole FID block in `is_directory(itr->status())`, so even the
  `sourcePath/fid` clause needs a subdirectory; a directory holding only `fid`
  identifies as nothing, confirmed against the reader.
- `exists_as_file` takes one `status()` rather than `exists()` + `is_directory()`.
- `expand_pathmask` passes `FIND_FIRST_EX_LARGE_FETCH` and `FindExInfoBasic`. **No local
  gain measured** (5.4 vs 5.6 ms on 20000 entries, noise); kept for the round trips a
  share pays, and easy to drop - it is its own commit, 4e458888f.

Still not measured: SMB/VPN/OneDrive. No share is mapped on this machine.

### A directory could be read as an acquisition it merely resembled (2026-08-13)

Found while browsing a share whose root held loose `_FUNC*.DAT` files, hard linked in
from a Waters `.raw` parent by a flattening script: `Reader_Waters::identify` claimed the
whole share, so `IsDataSource` was true, and `OpenFolderFromTextBox`
(`BaseFileDialogNE.cs:1049`) checks that *before* `Directory.Exists`. The share could not
be navigated to in either dialog, and Import Results tried to import it as a single
Waters source. Master was immune only because it never asked the reader.

Fixed in the readers rather than in `DataSourceUtil`, so every consumer benefits:
`Reader_Waters`, `Reader_Agilent` and the Bruker marker-file branches now require the
directory to be named `.raw` or `.d`. Bruker FID stays exempt - it is the one Bruker
format whose directories carry no extension, and pwiz's own corpus agrees: every real
Bruker acquisition in the tree is `.d`, and the only extension-less one, `100 fmol BSA`,
is FID. ABI T2D cannot be gated at all (any directory holding `*.t2d`), which is the one
remaining way an ordinary folder can be claimed.

Vendor tests: `Reader_Waters_Test` and `Reader_Agilent_Test` pass. `Reader_Bruker_Test`
fails 4 of 52, identically with the changes stashed - YEP and FID reads under
`--without-compassxtract`, after identification has succeeded.

### Listing cost measured against a real master build (2026-08-13)

Earlier figures compared against a simulation of master and were warm; both were
misleading. Alternating cold passes, master's own `pwiz.CommonMsData.dll` from
`C:\Dev\master_clean` against the branch, over a share of 511 directories of real data:

| What is listed | master | branch |
|---|--------|--------|
| Directories named `.raw` or `.d` (376) | 5.85, 5.91 ms | 5.83, 5.93 ms |
| Directories with no such name (135) | 1.67, 1.80 ms | 7.28, 6.79 ms |
| Files (200 sampled) | 0.10, 0.11 ms | 0.09, 0.11 ms |

So vendor directories and files are untouched; the whole cost is the 135, and the
listing goes 2.33s to 3.06s. A share root of ordinary parent folders is the bad case at
~1 vs ~6 ms/dir, since nothing matches by name. Recognition changes by exactly one
entry: `Bruker 32 -> 33`, `File Folder 138 -> 137`.

Two ideas measured and dropped: a `Reader::canFormatBeDirectory` virtual so a
`ReaderList` skips file-only readers for a directory (built, verified wired up, 2-3% -
those readers never touch the filesystem), and a `_FUNC*.DAT` prefix glob in place of
the Waters listing (72ms across 256 directories - on SMB cost is round trips, not
entries; a 602-entry `.raw` lists as fast as a 15-entry one). Memoizing per path is
unsound: a directory's LastWriteTime does not change when a `fid` appears three levels
below it, verified, so a stale "File Folder" could not be cleared even by F5.

### The dialog now says what it is doing (2026-08-13)

`populateListViewFromDirectory` adds rows only after every entry has been examined
(`listView.Items.AddRange` at the end), so the list sat empty for the whole scan - seven
seconds on the share, reading as an empty folder. A message over the list counts entries
as they are found, appearing only once a scan passes 150ms and repainting at most every
100ms. Watch the z-order: `Controls.Add` puts a control at the *back*, so it needs
`BringToFront()` every time it is shown, and a `Label` is `Visible = true` by default.

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
- bjam keeps two spellings of the same build path, abbreviating when they grow long
  (`.../rls/adrs-mdl-64/...` beside `.../release/address-model-64/...`). A rebuild can land in
  one while you are running the binary from the other; check timestamps before believing a
  native result. Core pwiz tests also need the CI variant - `--without-compassxtract` leaves
  `Reader_Bruker_FID/YEP/U2` out of `ExtendedReaderList`, so `ReaderTest` fails there on an
  inventory check that has nothing to do with the change under test.

## Progress Log

### 2026-08-17 - Merged

PR #4525 merged as `656bd2b288`. Shipped: the shared file dialog asks the reader when the
naming rules cannot decide, so Bruker FID acquisitions are selectable in MSConvertGUI again
(regression from #4099) and in Skyline for the first time; the reader is asked only about
directories that could be one and each is settled by a single walk, so the added cost falls
only where a name says nothing; `DataSourceUtil` takes a reader answer for such a directory
only when it is Bruker FID; the vendor probes require a file rather than any existing path;
and the dialogs show a running count while reading a directory instead of an empty list.

Matt's review raised the large-directory cost, answered with measurements (vendor
directories and files unchanged, ~1 vs ~6 ms per directory whose name says nothing, 2.33s to
3.06s for a 511-directory share). His second point - not restricting Waters to `.raw` - was
accepted: a naming requirement briefly added to `Reader_Waters`, `Reader_Agilent` and the
Bruker marker-file branches was reverted, so msconvert still deduces a renamed acquisition,
and the naming question is asked only in the picker.

Deferred, not shipped: SeeMS still runs its own picker, which calls `identify()` per file
(160ms each on a share, ~230s for 1,432 files) and walks each source recursively for its
size; replacing it with the shared dialog is its own PR, and Matt was asked about it on the
thread. The squash subject landed without the `pwiz: ` module prefix, so `git log` does not
carry the module for this one; the PR label does.
