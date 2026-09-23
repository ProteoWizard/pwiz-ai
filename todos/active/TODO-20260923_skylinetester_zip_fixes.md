# Make the distributed SkylineTester zip usable again on the port branch

## Branch Information
- **Branch**: `Skyline/work/20260923_skylinetester_zip_fixes`
- **Base**: `Skyline/work/20260612_net8_port`
- **Created**: 2026-09-23
- **Status**: In Progress
- **GitHub Issue**: (none)
- **Module**: `skyline`
- **PR**: (pending)

## Objective

Two independent defects in the SkylineTester distro zip, both introduced by the net472
to .NET SDK port and both found by opening
`E:\Nightly\SkylineTesterForNightly_integration_leak`:

1. Starting `SkylineTester Files\SkylineTester.exe` reports *"No test assemblies were
   found, so no tests can be listed"* although the eight test assemblies sit right
   beside it.
2. `SkylineTester.exe` in the zip root does not start at all.

## 1. No test assemblies found

`SkylineTesterWindow.FindTestAssembly` has a `#if NET472` branch that ends with
`GetSelectedBuildDir() ?? ExeDir` - its comment says *"One bin holds this program and
the tests alike"* - and an `#else` branch that never looks in `ExeDir`. The `#else`
branch tries exactly two places, and in a distributed zip neither can succeed:

- `GetBuildOutputTestDll` starts from `SkylineDirectory()`, which walks **up** from
  `ExeDir` looking for a folder named `Skyline`. An unzipped distro has no such
  ancestor, so it returns null.
- `GetSelectedBuildDir()` is null because nothing has been staged in a fresh unzip.

The shipped layout is the one-bin arrangement the net472 branch handles: the test DLLs
are in `SkylineTester Files` next to `SkylineTester.exe`. The port dropped the only
lookup that covers it.

**Fix**: look beside the program as a last resort in the `#else` branch.

A second, smaller defect made this hard to diagnose: `ReportNoTestAssembliesFound`
exists to name every directory searched, but `GetBuildOutputTestDll` returns on
`skylineDir == null` *before* recording anything, so the dialog listed nothing at all.
It now records that there is no Skyline source tree above the exe.

## 2. Root SkylineTester.exe does not start

`Program.Main` treats a root copy as a bootstrapper: it looks for
`SkylineTester Files\SkylineTester.exe` and, if found, relaunches that copy with the
nested directory current (*"The SkylineTester installation puts SkylineTester one
directory too high"*).

Under net472 the root copy was the assembly, so `Main` ran and did this. Under the .NET
SDK `SkylineTester.exe` is only an apphost; it needs `SkylineTester.dll`,
`SkylineTester.runtimeconfig.json` and `SkylineTester.deps.json` beside it, and all
three ship in `SkylineTester Files`. The lone copy at the root therefore exits before
`Main` is reached, with no error dialog.

Shipping the three companions at the root does not work either: `deps.json` resolves
against the application directory, and `additionalProbingPaths` expects a NuGet-style
layout rather than a flat folder.

**Fix**: ship `SkylineTester.cmd` at the zip root instead of the unusable apphost. A
script needs no runtime of its own and starts the nested copy with the right working
directory - the same thing the bootstrap was doing. `Program.Main`'s bootstrap is left
in place; it costs nothing and still applies to any older zip.

Nothing automated consumed the root copy: `SkylineNightly` launches
`SkylineTester Files\SkylineTester.exe` directly (`Nightly.cs`).

## Verification

- [ ] `Build-Skyline.ps1 -Target SkylineTester -Configuration Release` - 0 errors
- [ ] `build.bat Release --no-tests SkylineTester.zip` produces the distro zip
- [ ] Zip root contains `SkylineTester.cmd` and no `SkylineTester.exe`
- [ ] Extracted outside any `Skyline` ancestor, `SkylineTester Files\SkylineTester.exe`
      lists tests instead of showing the empty-tree dialog

## Notes

Found while reviewing Integration-branch nightly runs. The third issue from that review,
the `RefineConvertToSmallMolecules*` `LibraryDotProduct` failure, was fixed separately by
PR #4631 (`WaitForLibrariesLoaded`) and needs nothing here.
