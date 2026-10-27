# TODO-20261027_admin_installer_missing_dlls.md

## Branch Information
- **Branch**: `Skyline/work/20261027_admin_installer_missing_dlls`
- **Base**: `Skyline/skyline_26_1_1` (.NET 4.7.2 Skyline-daily branch)
- **Created**: 2026-10-27
- **Status**: Completed
- **GitHub Issue**: (none)
- **Module**: `skyline`
- **PR**: [#4922](https://github.com/ProteoWizard/pwiz/pull/4922) (into `Skyline/skyline_26_1_1`, merged 2026-10-27);
  master follow-up [#4924](https://github.com/ProteoWizard/pwiz/pull/4924) (merged 2026-10-27;
  `Skyline/work/20261027_installer_test_file_guard`, built in `C:\proj\pwiz`, which was then
  switched back to `Skyline/work/20261026_nightly_runtime_servicing`)
- **Checkout**: `C:\proj\daily`

## Objective

The WiX admin installer (.msi) for Skyline-daily 26.1.1.279 is missing files the
ClickOnce package ships. Reported by Philip (Thermo): SkylineCmd from
`C:\Program Files\Skyline-daily` failed importing a transition list with
"Could not load file or assembly 'Sprache, Version=2.3.1.0'".

## Root cause

`Product-template.wxs` is a hand-maintained file list; ClickOnce takes the whole
build output. New dependencies reach ClickOnce automatically but not the MSI.
Diff of the 279 ClickOnce manifest (`bin\x64\Release\app.publish\...\Skyline-daily.exe.manifest`)
against the .wxs + FileList64.txt:

- `Sprache.dll` - added with #4115 (2026-06-24) for `FilterClauseSerializer`
  (`SpectrumClassFilter`); new to 26.1.1, not in the 26.1 release
- `Microsoft.Web.WebView2.{Core,WinForms,Wpf}.dll` + `runtimes\win-x64\native\WebView2Loader.dll`
  - missing since Ardia support (2024-11); used by `ArdiaLoginDlg` (incl. SkylineCmd) and
  `DocumentationViewer`
- `Method\Thermo\Thermo.TNG.MethodXMLInterface2.dll` - optional DLL in `DllFinder`, missing since #2954
- `ja\` and `zh-CHS\PanoramaClient.resources.dll`
- Not needed: `skyline.ico` (embedded), Method builder .pdb files; percolator VC runtimes
  are already installed from the root copies

## Master (.NET 10)

Master replaced WiX with Inno Setup (#4755): `build.ps1` stages the entire build output
(minus doc XML and non-Windows runtimes) and `Setup.iss` ships `{#StagingDir}\*`, so this
omission class does not apply. The WiX Jamfile was removed in #4658; `Product-template.wxs`,
`FileList64-template.txt`, `SetupDeployProject.*` and the WiX half of `README.txt` remain on
master as unused leftovers.

## Tasks

- [x] Add missing files to `Product-template.wxs` and `FileList64-template.txt`
- [x] `/code-review medium`: added ja/zh-CHS `SkylineBatch.resources.dll` (MSI-only app, so
  absent from the ClickOnce diff), `zh-CHS\pwiz.CommonUtil.resources.dll` to the file list,
  and a `RuntimeIdentifier` define in place of duplicated x64/x86 blocks
- [x] Build MSI (`b.bat pwiz_tools/Skyline/Executables/Installer//setup.exe`): 0 errors; file
  table vs the shipped 279 MSI is +10 files, -0 (279 has 351, matching Philip's count)
- [x] PR into `Skyline/skyline_26_1_1`: #4922
- [x] Master PR #4924: `build.ps1` fails before staging when `$SkylineBinDir` holds test
  assemblies, harnesses or MSTest platform DLLs; tested on a minimal fake bin (real exes +
  test files) both ways; `/code-review medium` folded in (check before copy, single
  enumeration, platform patterns so unlisted test projects are caught, clearer message)
- [x] Draft reply to Philip in Gmail Drafts (Brendan sends): asks how urgent; fix ships in the
  next 4.7.2 Skyline-daily only if a patch forces one, else the first .NET 10 Skyline-daily
  (~mid-November); interim workaround is copying Sprache.dll from ClickOnce

## Not done (by decision)

- Root-level `WebView2Loader.dll`: ClickOnce ships only `runtimes\win-x64\native`, and works
- WebView2 runtime bootstrap in the MSI: ClickOnce has none either; the runtime ships with Windows
- Jamfile `test_msi` copies `Microsoft*.dll` into the install before testing, which would hide a
  missing WebView2 assembly; pre-existing and the WiX path is gone on master
- Build-time check of the .wxs against the build output: not worth it on the 4.7.2 branch;
  master's Inno installer ships the whole output

## Progress Log

### 2026-10-27 - Merged

PR #4922 merged into `Skyline/skyline_26_1_1` as e54bea0699 and PR #4924 merged into master
as c4275fc7ac, both with `--admin` at Brendan's direction. #4922 was blocked only by the
manually started "Skyline Release Perf and Tutorial tests" required check, which never ran
(all 10 reported checks green, 1674 Skyline tests passed). #4924 failed only
TestNativeMessageBox in bt209 (a known intermittent form-lookup failure, 8 nightly failures on
2026-08-23), and the Wine Docker build failed on that snapshot dependency; the change touches
only `build.ps1`, which CI does not run. The admin MSI fix ships with the next 4.7.2
Skyline-daily; no release was cut.
