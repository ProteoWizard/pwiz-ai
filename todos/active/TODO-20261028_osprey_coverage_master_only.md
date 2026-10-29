# TODO-20261028_osprey_coverage_master_only.md

## Branch Information
- **Branch**: `Skyline/work/20261028_osprey_coverage_master_only` (from `master` at 15c39798df)
- **Created**: 2026-10-28
- **Status**: In Progress
- **GitHub Issue**: (none)
- **Module**: `osprey`
- **PR**: [#4933](https://github.com/ProteoWizard/pwiz/pull/4933)
- **Checkout**: `C:\proj\pwiz-tccov` (sparse worktree: `pwiz_tools/Osprey/*.ps1`, `*.bat`)

## Objective

Bring the per-commit `ProteoWizard_OspreyWindowsNet` TeamCity config back to about 10 minutes by
collecting dotCover coverage only on master builds. Master builds after each merge keep a running
view of coverage, so a slip over time is still caught.

## Why

The config grew from under 1 minute (through 2026-09-27) to ~17 min on MacCoss Agent 1 and ~28 min
on the EC2 agents it now runs on (EC2 routing is intentional: TCA1 is kept for the long perf gates).
Per-test attribution from the TeamCity REST API (builds #767-#1141):

- ~25 end-to-end `SubsetPipelineTest` cases were added from 2026-09-28 (TestSubsetOptionVariants
  110 s, the LibraryBuildTuned family 30-72 s each) plus CarafeSharp.Test from 2026-10-13
  (TestRegressionSubset 62 s, TestSubsetFastaBuildsMatchCarafe 57 s).
- `tcbuild.bat` runs both suites under dotCover. Measured on the dev box: TestSubsetOptionVariants
  12 s plain vs 96 s under dotCover (8x). Osprey.Test as a whole runs 1.6 min plain locally vs 10.95 min
  covered on TCA1 (#1140). CarafeSharp barely slows (1.6x): its time is in native libtorch.

## Change

- `pwiz_tools/Osprey/tc-is-default-branch.ps1` (new): reads `teamcity.build.branch.is_default` from
  the agent's configuration properties file; exit 0 = master, 1 = PR branch. Outside TeamCity, or when
  the parameter cannot be read, exits 0 so coverage stays on (the prior behavior).
- `pwiz_tools/Osprey/tcbuild.bat`: passes `-Coverage` to the Osprey and CarafeSharp `build.ps1` only
  when the check says master.

## Progress

- [x] Helper verified against simulated property files (master / PR / missing / outside TeamCity)
- [x] tcbuild.bat dry-run with pwsh stand-ins: PR runs all three steps without -Coverage, master with
- [x] PR build #1144 (EC2) logged "Not the default branch: running tests without coverage."; build 10.4 min
      (was 27.6 median on EC2), Osprey.Test 2.3 min, CarafeSharp.Test 3.4 min, 762 tests, 0 failed
- [ ] After merge: first master build still imports both .dcvr snapshots (Code Coverage tab populated)
