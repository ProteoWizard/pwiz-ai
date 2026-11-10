# TODO-20261110_rinstaller_test_offline.md

## Branch Information
- **Branch**: `Skyline/work/20261110_rinstaller_test_offline`
- **Base**: `master`
- **Created**: 2026-11-10
- **Status**: In Progress
- **GitHub Issue**: (none - from nightly tests, e.g. Nightly x64 run 86656)
- **Module**: `skyline`
- **PR**: (pending)
- **Checkout**: `C:\Dev\TestIssues`

## Objective

Stop the recurring TestRInstaller failures: 25 in Nightly x64 between 2026-08-01 and
2026-11-10, on 6 machines and in 5 languages. Before installing packages, RInstaller sends
a real HEAD request to check that r-project.org is reachable, and the package subtests did
not mock it. Whichever subtest ran first while www.r-project.org was slow got "Failed to
connect to the website www.r-project.org" instead of its expected message. Failures rose
from rare to almost daily after 2026-10-26.

## Approach

- RInstallerTest: answer the HEAD probe locally (through the RequestResponseFactory test
  seam) for the package subtests and TestStartToFinish. The mock fails the test if the probe
  goes to any host other than RUtil.INTERNET_CHECK_SITE.
- RUtil probe: target cran.r-project.org instead of www.r-project.org. The in-repo
  tool install scripts use cran.us.r-project.org, and Skyline downloads R from
  cran.r-project.org. Cancel the probe after 30 seconds instead of the 120-second HTTP
  response timeout, with a new message "Timed out after {0} seconds."
- New subtest TestInternetConnectionTimeout: a loopback TcpListener that never answers
  proves the probe gives up on its own timeout.
- HttpClientWithProgress.Head() now disposes its response (found by /code-review).

## Verification

- TestRInstaller passes in en, fr, ja, zh and tr
- With the probe pointed at an unreachable host: passes with the fix, fails without it
  (same failure the nightlies show)
- With the timeout disconnected: the timeout subtest fails after 129 seconds
- CodeInspection and tcinspect.ps1 clean

## Follow-up (not in this PR)

- The in-repo tool install scripts use http:// for CRAN; https would be safer (tool change)
