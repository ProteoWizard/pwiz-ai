# TODO-20261104_osprey_ci_inspection.md

## Branch Information
- **Branch**: `Skyline/work/20261104_osprey_ci_inspection` (local, not pushed), cut from `origin/master` at 3c2f42b552
- **Checkout**: `D:\Users\brendanx\proj\pwiz-scorelib` (worktree, MACS2)
- **Base**: `master`
- **Module**: `osprey`
- **Created**: 2026-11-03
- **Status**: Implemented and verified locally (f0cfff35f3, a25a25240a); ready for review and push. No PR yet.

## Objective (Brendan, 2026-11-03)
Run code inspection inside the "Osprey Windows .NET" TeamCity config (ProteoWizard_OspreyWindowsNet), as
Skyline's inspection was folded into bt209 "Skyline master and PRs" (Matt Chambers: cafeb7048c, 3f290fc763,
1c02f7d83e). ReSharper warnings kept reaching Osprey PRs and master with green checks - e.g. #4950's
PossibleNullReferenceException / RedundantCast in Osprey.IO/ParquetScoreCache.cs. Compiler warnings fail the
build too, and both fail it only AT THE END, after tests and installers ran, so the log carries everything.

## What was done
- `pwiz_tools/Osprey/tcinspect.ps1` (new, modeled on `pwiz_tools/Skyline/tcinspect.ps1`):
  - Restores the ReSharper CLI pinned in `pwiz_tools/Osprey/.config/dotnet-tools.json` (2025.3.3, as Skyline).
  - Pre-builds Osprey.Test.csproj (Release|x64) so out-of-solution references resolve, then runs
    `dotnet jb inspectcode Osprey.sln --profile=Osprey.sln.DotSettings -e=WARNING --no-swea --no-build`.
  - Reads the build-warnings log (`scripts/BuildWarnings.psm1`, as #4844), reports both in one verdict.
  - importData ReSharperInspectCode (Inspections tab), report and warnings log as artifacts.
  - Posts an 'Osprey code inspection' GitHub status when `GITHUB_STATUS_TOKEN` is set (not yet in the config).
  - Exit 0 clean, 1 warnings/findings, 2 a check did not run; non-zero also raises a buildProblem.
- `pwiz_tools/Osprey/tcbuild.bat`: calls `clean.bat` first (Skyline's config has a Clean step; an up-to-date
  project emits no warnings), passes one warnings log to every compile, no longer stops at the first failed
  step (first failure's exit code wins), skips installers after a failed compile/test, runs tcinspect.ps1 last.
- `pwiz_tools/Osprey/build.ps1`, `pwiz_tools/CarafeSharp/build.ps1`: `-BuildWarningsPath` adds the
  warnings-only file logger. Nothing promotes warnings to errors.
- Master needed no fixes: 0 compiler warnings (from-scratch Release build) and 0 inspection findings.

## Verification (logs in `ai/.tmp/sessions/20261103-inspect/`)
- Local driver = tcbuild.bat with coverage off and package.ps1 skipped (`tcbuild-local.bat`,
  `make_driver.py`), `PwizWarningsAsErrors=false` to match TeamCity:
  - [x] master: 650 + 108 tests passed, "No build warnings and no inspections", exit 0 (`e2e-1-master.log`)
  - [x] probe CS0219 + RedundantCast: all tests still ran and passed, then
    "failure - 1 build warnings; 2 inspections", exit 1 (`e2e-2-probe.log`)
  - [x] probe failing test + warnings: test buildProblem AND inspection buildProblem both raised,
    CarafeSharp still built/tested, installers skipped, exit 1 (`e2e-3-testfail.log`)
- [x] jb 2025.3.3 on #4950 (5340c30909): flags ParquetScoreCache.cs(407) PossibleNullReferenceException and
  (416) RedundantCast, exit 1 (`fdrgap-inspect.log`) - no need to pin 2026.2.1
- [ ] TeamCity run of the PR (first real agent run; watch the Inspections tab and the build-time cost)

## Remaining
- Optional TeamCity-side: add `env.GITHUB_STATUS_TOKEN=%GitHubAuthToken%` and
  `env.INSPECTION_TARGET_URL=https://teamcity.labkey.org/buildConfiguration/%system.teamcity.buildType.id%/%teamcity.build.id%?guest=1`
  to ProteoWizard_OspreyWindowsNet for the separate GitHub status.
- Linux config (OspreyLinuxNet, tcbuild.sh) unchanged.
