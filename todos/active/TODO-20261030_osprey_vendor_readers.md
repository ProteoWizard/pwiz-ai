# TODO-20261030_osprey_vendor_readers.md

## Branch Information
- **Branch**: `Skyline/work/20261030_osprey_vendor_readers`
- **Checkout**: `C:\proj\pwiz`
- **Base**: `master`
- **Created**: 2026-10-30
- **Status**: Code changes made and verified locally (build, tests, inspection, packaging, raw read). Needs the TeamCity
  step arguments (below) before the installers carry vendor readers.
- **GitHub Issue**: (none)
- **Module**: `osprey`
- **PR**: #4949

## Goal

Matt ran the Osprey package that Skyline's wizard downloads on a Thermo .raw and got:

```
Error: Pipeline failed: System.NotSupportedException: Cannot read '...raw': this build of Osprey
has no vendor instrument support. Rebuild with /p:IAgreeToVendorLicenses=true on Osprey.sln,
or with 'bjam pwiz_tools/Osprey//Osprey --i-agree-to-the-vendor-licenses'. ...
```

Three defects: the installers are built without the vendor readers, the message tells a user
to rebuild Osprey (with a bjam line that no longer applies after the .NET 10 port), and the
exception type makes the top level print it as a crash with a stack trace. Brendan also asked
for a pass over developer vocabulary in the user-facing help.

## Scope (agreed 2026-10-30)

1. Osprey installer artifacts build with the instrument vendor readers.
2. The vendor messages are reworded for users and thrown as `UserMessageException`.
3. `-d` / `--diagnostics` becomes the `OSPREY_DIAGNOSTICS` environment variable;
   `--memstamp` help matches Skyline's and says it is for monitoring memory use during long
   runs, with no mention of perfviz. The other developer options stay as they are.

## How Skyline and the pwiz installer get vendor readers on TeamCity

The agreement is an argument of the TeamCity build step, never a default in a committed file.
Core Windows x86_64 (bt83) runs `tcbuild.bat --i-agree-to-the-vendor-licenses --automated
--require-vendor-support`; Core Linux x86_64 (bt17) runs `tcbuild.sh` with the same three and
gets the cross-platform SDKs only. Osprey Windows .NET ran `pwiz_tools\Osprey\tcbuild.bat`
with no arguments, so every vendor reader built in its NO_VENDOR_SUPPORT mode.

## Changes on the branch

- `tcbuild.bat`, `tcbuild.sh`: accept `--i-agree-to-the-vendor-licenses` and
  `--require-vendor-support`, as the root scripts do, and pass the agreement to `build.ps1`
  and `package.ps1`. An unknown argument fails the build.
- `package.ps1 -IAgreeToVendorLicenses`: publishes with the property, fails if the Thermo SDK
  is missing from the stage, and copies the vendor `EULA.*.txt` beside LICENSE as the pwiz
  installer does. The SDKs are bundled, not fetched on first use.
- `SpectrumFileReader`: both vendor errors are `UserMessageException`; the no-reader message
  now says to convert to mzML with msconvert and nothing about rebuilding. Stale ja/zh-Hans
  drafts removed (they were unreviewed "New resource" drafts).
- `--input` help and the HTML intro no longer say "where the vendor readers are installed".
- `-d` / `--diagnostics` removed; `OSPREY_DIAGNOSTICS=1` turns on the same dump bundle.
  Docs in `pwiz_tools/Osprey/docs` and `ai/scripts/Osprey/DIAGNOSTICS.md` updated.
- `--memstamp` help reworded.

## Remaining

- [x] Local: Debug build, unit tests, inspection (646/646, 0 inspection warnings; the help-page test regenerated en/ja/zh-Hans CommandLine.html as designed)
- [x] Local: `package.ps1 -Rid win-x64 -IAgreeToVendorLicenses -OutputDir D:/test/osprey-vendor-pkg`:
      170.4 MB zip, every vendor SDK and six EULAs staged. The packaged Osprey.exe cached
      090701-LTQVelos-unittest-01.raw (28 MS2 + 58 MS1). No DIA vendor file was at hand for a full search
- [x] Local: the no-vendor Debug build gives one Error: line naming the file and msconvert, no stack,
      from both `--task SpectraCache` and a full search
- [x] TeamCity (Brendan, 2026-10-30): `--i-agree-to-the-vendor-licenses --require-vendor-support`
      added to the Command parameters of both Osprey configs; TeamCity committed them to master as
      .teamcity/patches (c44ef8dba5, 1296614c8c). A master merge touching only .teamcity fires no
      Osprey trigger. On 11e9d21b: Windows #1163 "Vendor support: ENABLED", win-x64 zip 170.5 MB,
      TestRawVsMzmlSpectraParity now reads the .raw (146 ms vs 6 ms); Linux #593 ENABLED
      (cross-platform SDKs), linux-x64 zip 206.7 MB. All green
- [ ] After a vendor-enabled master build: move Skyline's pinned Osprey build
      (`OspreyHelpers.OSPREY_VERSION` and build id) and raise `OSPREY_DOWNLOAD_SIZE_MB` (150) to about 170 for the vendor zip
- [x] `/code-review medium`: 6 findings. Fixed 4: the IOTest early return now requires the
      no-vendor-support inner exception, package.ps1 also checks a native SDK (timsdata.dll) on
      win-*, and four stale `-d` mentions. Dropped 2: a hidden `-d` alias (developer switch,
      docs name the replacement) and a shared EULA helper (5 lines in two independent scripts).
      Re-verified: 646/646, inspection clean, package passes its SDK check and reads the .raw
- [x] Commit 4e155ea1f7, PR #4949 (2026-10-30)
