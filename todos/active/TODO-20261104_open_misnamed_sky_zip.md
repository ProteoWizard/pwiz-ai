# TODO-20261104_open_misnamed_sky_zip.md

## Branch Information
- **Branch**: `Skyline/work/20261104_open_misnamed_sky_zip`
- **Base**: `master`
- **Created**: 2026-11-04
- **Status**: In Progress
- **GitHub Issue**: (none - from support board)
- **Module**: `skyline`
- **PR**: (pending)

## Objective

Open a Skyline shared .sky.zip even when its file name has lost the .zip extension.

Support thread https://skyline.ms/home/support/announcements-thread.view?rowId=76196 -
a user attached a File > Share zip that arrived as `c18 .sky`. Opening it fails with
"does not appear to be a Skyline document ... XML document (1, 1)" because
`SkylineWindow.OpenFile` dispatches on extension and hands a zip to the XML parser.

## Approach

- `SkylineWindow.OpenFile`: if the file starts with the zip local-header signature
  (`PK\x03\x04`), route it to `OpenSharedFile` instead of the XML parser.
- `SrmDocumentSharing.ExtractDir`: also strip a `.sky` extension (and trailing spaces/dots,
  which Windows drops from folder names) so `c18 .sky` extracts to `c18`.
- `SrmDocumentSharing.GetNonExistentDir`: treat an existing FILE at the target path as taken,
  so a zip with no extension does not try to extract into a folder named after itself.

## Tasks

- [x] Failing test: extend `ShareDocumentTest.ShareWithRawDirectoriesTest` to open a copy of the
      .sky.zip renamed to `Renamed Share .sky` and `Renamed Share`
- [x] Fix
- [x] Green: TestDocumentSharing, CodeInspection

## Notes

- A renamed zip that is not `.sky.zip` still gets the stricter shared-file check (no non-data
  top-level folders), same as a plain `.zip`. Real File > Share output passes it; the test uses
  the share zip containing a `.d` folder for that reason.
- [x] `/code-review medium` - fixed: IsZipFile swallowing only IO errors (malformed path escaped
      OpenFile), a zip named just `.sky` extracting outside its folder, weak test location assert.
      Dropped: nested-zip recursion, non-Skyline zip message, empty/spanned zip signatures,
      extra 4-byte read, SkypFile ExtractDir trim, SkylineCmd `--in`
- [x] Developer review; PR opened for Copilot

## Out of Scope

- SkylineCmd `--in` does not open .sky.zip files under any name, so it is unchanged.
