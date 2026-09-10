# TODO: Integration-branch nightly builds successfully but runs no tests

**Status**: Active
**Priority**: Blocking — the .NET 10 port cannot be nightly-tested, which gates its merge to master

## Branch Information

- **Branch**: `Skyline/work/20260910_nightly_integration_no_tests` (off `Skyline/work/20260612_net8_port`)
- **Checkout**: `C:\proj\pwiz-work1`
- **PR target**: `Skyline/work/20260612_net8_port` — this is Matt's branch; a PR into it, not a
  direct push, unless Brendan says otherwise
- **Module**: `skyline`

## The failure

Matt marked `Skyline/work/20260612_net8_port` as the Integration branch for SkylineNightly. A run
now gets all the way through the build and then does nothing:

```
# Checking out Skyline (work/20260612_net8_port) source files...
> git clone ... -b "Skyline/work/20260612_net8_port" E:\Nightly\SkylineTesterForNightly_integration\pwiz
...
    784 Warning(s)
    0 Error(s)
Build succeeded; skipping tests (--no-tests).
# Build done.
# Nightly finished.
```

SkylineTester shows a modal **"No test assemblies were found, so no tests can be listed."** with no
"Looked in:" list, and SkylineNightly logs `No tests run in 8 minutes. Will try again in 10 minutes.`

Branch detection itself is FIXED — PR #4649 (merged, `e5afd8e6c2`) taught SkylineNightly to read the
branch from SkylineTester's assembly stamp, and the log confirms
`Branch Skyline/work/20260612_net8_port identified from SkylineTester.dll`.

## Root cause

`SkylineTesterWindow.GetPossibleBuildDirs()` returns eight slots matching the build radio buttons.
net472 fills the Nightly pair from the freshly cloned checkout:

    Path.Combine(GetNightlyBuildRoot(), @"pwiz\pwiz_tools\Skyline\bin\x86\Release"),
    Path.Combine(GetNightlyBuildRoot(), @"pwiz\pwiz_tools\Skyline\bin\x64\Release"),

The port replaced all eight with staging lookups derived from `ExeDir`, and left both Nightly slots
**null**. In a nightly run `SelectedBuild` is a Nightly slot, so `GetSelectedBuildDir()` returns null
and there is nowhere to find the tests that were just built. `GetNightlyBuildRoot()` still exists
(`Main.cs:280`) and still recognises a `SkylineTesterForNightly*` root — the concept survived, only
its use did not.

The empty "Looked in:" list is the corroborating detail: `GetBuildOutputTestDll` returns before
recording any path, because `SkylineDirectory()` — which walks up from `ExeDir` for a folder named
exactly `Skyline` — is null under `E:\Nightly\SkylineTesterForNightly_integration`.

## What the fix must do

1. **Fill the Nightly 64-bit slot from the nightly checkout.** `GetNet8StagingDir` and
   `GetStagingTargetDir` both derive their base from `SkylineDirectory()`. They need to accept an
   explicit Skyline directory so `<GetNightlyBuildRoot()>\pwiz\pwiz_tools\Skyline` can be passed in.
2. **Get the configuration right.** `PreferredConfiguration()` reads the parent folder of `ExeDir`;
   in a distro that is the unzip folder, so it answers `Debug` while the nightly builds `Release`.
   `nightlyBuildType` is 32/64-bit, not a configuration, and the port has no `_buildDebug`.
3. **Decide whether the nightly build stages at all.** The build runs with `--no-tests`, which may
   skip staging. If nothing is staged in the checkout, the slot must name the directory staging is
   *about to* produce — `GetStagingTargetDir()` already does this for the developer case and is the
   model to follow.
4. **Never show a modal in an unattended run.** `ReportNoTestAssembliesFound` calls
   `MessageBox.Show` unconditionally. On a nightly machine that blocks until someone dismisses it.
   It should log instead when running unattended. This is a real defect in its own right — it is why
   the failure presented as a hang rather than a message.

## Traps — both already paid for once

- **Do NOT fall back to `ExeDir`.** Tried and reverted in this session. It "works": the zip's
  `SkylineTester Files` holds a full set of TeamCity-built test DLLs, so tests run and pass — against
  the artifact instead of the branch that was just cloned and built, with nothing in the log saying
  so. Green results on the wrong binaries is worse than the current loud failure.
- **Do NOT relax `SkylineDirectory()`'s exact `"Skyline"` match.** That is Matt's deliberate
  `Skyline` vs `SkylineTester` distinction from `7e97746fa2`. `RootDir`'s `StartsWith("Skyline")`
  walk (donmarsh, 2014) is the separate, distro-facing one, and both are correct for their own
  question. Relaxing the exact match would make `GetBuildOutputTestDll` hunt inside
  `SkylineTester Files\TestFunctional\bin\x64\Debug\`, replacing a clean null with confident nonsense.

## Related drift — not blocking, worth a separate look

The port moved SkylineTester's output from `pwiz_tools\Skyline\bin\x64\Release` to
`pwiz_tools\Skyline\SkylineTester\bin\x64\Release\net10.0-windows`, so `RootDir`'s
`StartsWith("Skyline")` walk now stops at `SkylineTester` instead of `Skyline`. `SkylineTester.log`,
`SkylineTester Results` and `GetZipPath`'s probe all moved with it. Brendan flagged this as a known
side effect.

## Definition of done

- A nightly run against the Integration branch clones, builds, and **runs tests from the checkout it
  just built** — verifiable in the log by tests appearing after `# Build done.`
- The tests that run are the freshly built ones, not the zip's. Check the assembly path in the log.
- No modal dialog in an unattended run.

## Progress Log

### 2026-09-09 (night) - Fixed and VERIFIED

Commit `a187e20154`. The diagnosis in this TODO held up in full; the missing piece was in
`build.bat`, not in SkylineTester.

**VERIFIED 22:44, log `D:\Nightly\Logs\BRENDANX-UW8_2026-09-09_22-40-38.log`.**
The run used the distro built from this branch (stamp
`3.0.26252+a187e20154.branch.Skyline/work/20260910_nightly_integration_no_tests`) against a
checkout of the PURE Integration branch at `5c046bdb7a` - the fix ships in SkylineTester, so
the branch under test deliberately does not carry it.

The log holds exactly two runner invocations, and the split is the whole point:

| # | path | role |
|---|---|---|
| 1 | `...\SkylineTester Files\TestRunner.exe` | the STAGER (`stage=1 configuration=Release`). Correct: `FindStagerExe` prefers the binary beside the program, and that stager resolves its SOURCE from the checkout. |
| 2 | `...\pwiz\pwiz_tools\Skyline\bin\staging\Release\TestRunner.exe` | the TEST RUNNER - the freshly built checkout. |

Every staged project resolved into the checkout, ending
`Staged tests to: ...\pwiz\pwiz_tools\Skyline\bin\staging\Release`.
No path under `SkylineTester Files\` is used for tests, so this is NOT the trap in Traps above.

Timeline: `# Build done.` 22:43:06 -> stage -> first tests 22:44, unattended, no modal.
All three definition-of-done criteria met.

Commits: `a187e20154` (the fix) and `db3f33979b` (two further unattended modals).

Rig, dead ends and the remaining `build.bat` defect are in
`ai/.tmp/handoff-20260910_nightly_integration_no_tests_NIGHT.md`.

**The other half of item 3.** `build.bat:179` takes the `--no-tests` early exit
*unconditionally*, and that exit sits BEFORE the `Stage-Tests.ps1` step. So the nightly's
build genuinely never stages, and the Nightly slot cannot be "find an existing staged dir"
(which is all `GetNet8StagingDir` can do - it requires `TestRunner.exe` to already be
present). It has to NAME the directory staging will create, and let the existing
`AddTestRunner` -> `AddStagingCommand` path create it, exactly as it already does for a
developer after a clean build.

**Item 2 dissolved.** `AddStagingCommand` takes the configuration from the LEAF of the build
dir path, not from `PreferredConfiguration()`. Putting `Release` in the slot's path means the
distro's wrong `Debug` answer is never consulted on this path at all. No change to
`PreferredConfiguration` was needed.

**The stager already resolves to the right tree.** `TestRunner.GetSkylineDirectory()` walks up
and then *into* sibling directories looking for `pwiz_tools\Skyline`, so the stager running
from `SkylineTesterForNightly_integration\SkylineTester Files\` resolves to the freshly cloned
`pwiz\` checkout rather than to itself.

What landed:
1. `GetPossibleBuildDirs` Nightly-64 slot = new `GetNightlyStagingDir()` =
   `<GetNightlyBuildRoot()>\pwiz\pwiz_tools\Skyline\bin\staging\Release`, returned whether or
   not it exists yet. Nightly-32 stays null (x64-only).
2. New `TabBuild.BUILD_CONFIGURATION`, used by BOTH the build command and the slot, so they
   cannot drift into naming different configurations.
3. `IsUnattended` + `ReportOrShow`: the three modals on the nightly's critical path
   (`ReportNoTestAssembliesFound`, `AddTestRunner`'s no-build box, `AddStagingCommand`'s
   no-stager box) log to the run log instead of blocking. `IsUnattended` covers `--autorun`,
   `commandShell.IsUnattended`, a `.skytr` argument, and a SkylineNightly parent.

**Why the log will prove it.** `AddTestRunner` builds the runner path as
`Path.Combine(selectedBuildDir, "TestRunner.exe")` (Main.cs:343) from the resolved directory,
so the queued command names the path outright. Success looks like
`...\SkylineTesterForNightly_integration\pwiz\pwiz_tools\Skyline\bin\staging\Release\TestRunner.exe`;
the trap this TODO warns about would instead read `...\SkylineTester Files\`.

**Verification setup** (no push needed, no GitHub clone):
- `D:\Nightly\SkylineTesterForNightly_integration\pwiz` seeded (8.14 GB) by cloning the LOCAL
  checkout at net8_port `5c046bdb7a`; the run uses nukeBuild=false / updateBuild=true so it
  pulls rather than re-cloning. The distro carries the fix, the checkout is the pure
  Integration branch - the stricter test, since the fix ships in SkylineTester.
- A first attempt hand-patched `SkylineTester.dll` into TeamCity's distro. That does NOT work:
  ZedGraph carries a wildcard assembly version, so each build tree has its own, and the
  swapped DLL threw `Could not load file or assembly 'ZedGraph, Version=5.1.9748.40017'`
  behind a WinForms ThreadExceptionDialog. Use `--local` with a real zip instead.
- `build.bat Release SkylineTester.zip --no-tests` produces NO zip, for the same reason as
  above: the `--no-tests` exit precedes the zip step too. Build the zip without `--no-tests`.

**Separate defect found, not yet fixed** (see Related drift): because the `--no-tests` exit at
`build.bat:179` is unconditional, the second `--no-tests` check at `build.bat:237` is dead
code, and the flag is documented TWICE in the header block with conflicting meanings - one
saying "skip staging", the other "build and stage (and produce any requested distro zips)".
The documented `build.bat Release SkylineTester.zip --no-tests` combination therefore fails
silently, producing nothing.

### 2026-09-09 - Diagnosed, not fixed

Root-caused to the null Nightly slots in `GetPossibleBuildDirs()`. An `ExeDir` fallback was written,
built, and **reverted** on discovering it would test the zip's artifact rather than the branch just
built. Recorded rather than fixed, because the remaining work depends on configuration semantics that
cannot be verified from a developer tree — every path involved behaves differently in a distro.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260910_nightly_integration_no_tests.md` before starting work.
