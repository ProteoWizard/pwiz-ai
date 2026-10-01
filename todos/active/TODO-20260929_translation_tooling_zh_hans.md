# TODO-20260929_translation_tooling_zh_hans.md - Translation tooling caught up with the zh-Hans rename and net10 on the port branch

## Branch Information
- **Branch**: `Skyline/work/20260929_translation_tooling_zh_hans` (checkout
  `E:\Users\nicksh\git_e\sky_net10_resourcesorganizer`; created 2026-09-29 at `553a145871`)
- **Base**: `Skyline/work/20260612_net8_port`
- **Module**: `skyline`
- **Created**: 2026-09-29
- **Status**: In Progress
- **GitHub Issue**: #4737
- **PR**: (pending)

## Objective
Fix the parts of the translation tooling that had not caught up with the port branch's
`zh-CHS` -> `zh-Hans` rename and the net10 retarget, as reported by Brendan in #4737 (found while
taking Osprey's first translation through ResourcesOrganizer on the Osprey branch, PR #4752).

## Done (commit `efab95f53a`, not pushed)
- [x] `LastReleaseResources.db`: one-time SQL `UPDATE LocalizedResource SET Language='zh-Hans'
      WHERE Language='zh-CHS'` + `VACUUM` (36,892 rows each for ja / zh-Hans). Other `zh-CHS`
      strings in the db (designer `$this.Language` metadata in ChooseViewsControl.resx and
      ToolStoreDlg.resx, the `WizardBlankDocument-zh-CHS.bmp` file reference) still match the
      tree and were left alone.
- [x] `UpdateResxFiles.bat`: `importLastVersion --language ja zh-Hans`; Jamfile comment updated.
- [x] `Generate/ImportLocalizationCsvFiles.bat` and TutorialLocalization `Jamfile.jam` `/restore`:
      byte-identical to the Osprey branch's commit `e472274c39` so the merge is clean.
- [x] TutorialLocalization crash: `lib\CsvHelper.dll` was the netstandard2.0 build (needs
      Microsoft.Bcl.HashCode / AsyncInterfaces polyfills net10 does not ship). Replaced with the
      net8.0 build of the same 33.0.0.0 that ResourcesOrganizer already uses. Verified: old dll
      crashes (FileNotFoundException Microsoft.Bcl.AsyncInterfaces), new dll produces a 66 MB
      MergedTutorials.zip with exit 0 and no tutorial changes.
- [x] Re-serialized files on every import: the 8 files (ViewEditor, AssociateProteinsDlg,
      EditSpectrumFilterDlg, GroupComparisonStrings; ja + zh-Hans) differed only in entry order,
      designer TrayLocation metadata, char references vs literal chars, and the trailing newline.
      Committed ResourcesOrganizer's normalized output once; a fresh exportResx now matches all
      625 localized resx byte-for-byte.
- [x] Renamed the five tool `*.zh-CHS.resx` to `.zh-Hans.resx` (SkylineBatch, MPPExport, SProCoP,
      SkyGadget, Turnover). Only `MPP Export.csproj` (classic) needed edits: EmbeddedResource and
      the post-build 7za line. This also closes #4737 follow-up item 2 (CSV scripts misrouting the
      tools still on zh-CHS).
- [x] #4737 follow-up item 1: `UpdateResxFiles.bat` sets `EXTRA_EXCLUDE=pwiz_tools\Osprey`, which
      `MakeResourcesDb.bat` appends to its exclude list, so Incremental/FinalizeResxFiles no longer
      revert Osprey's translations (Osprey has no rows in the baseline db). The CSV scripts still
      sweep Osprey. Verified: 349 resx files / 0 Osprey with the variable set, 357 / 8 without.

## Remaining
- [ ] `/code-review`, push, open PR against `Skyline/work/20260612_net8_port`.
- [ ] Left to the Osprey branch (#4752), not duplicated here to avoid conflicts:
      `ImportLocalizationCsvFiles.bat` `%ERRORLEVEL%` inside `if exist (...)` (now `|| goto error`)
      and the README naming `localization.zh-Hans.csv`.
- [ ] Once Osprey is in `LastReleaseResources.db`, remove the `EXTRA_EXCLUDE` line from
      `UpdateResxFiles.bat`.
- [ ] When the port branch merges to master, update `ai/docs/translation-guide.md` (still says
      zh-CHS throughout, which is correct for master today).

## Notes
- Nick (2026-09-30): ImportLastVersion dropping translations absent from the baseline is by
  design (only localizer-reviewed text ships). Kept the Osprey exclusion because Osprey has its own
  review process (#4752) and is not judged by Skyline's baseline.
- Built ResourcesOrganizer and TutorialLocalization with `dotnet build -c Release` from PowerShell
  (no ai/scripts wrapper covers DevTools projects; Nick approved). ResourcesOrganizer unit tests
  not run; their test data uses `zh-CHS` as a self-contained language string and was left as is.
- `TutorialLocalization/lib` still carries net472-era shims (Microsoft.Bcl.AsyncInterfaces,
  System.Numerics.Vectors, System.Threading.Tasks.Extensions) that nothing references any more.
