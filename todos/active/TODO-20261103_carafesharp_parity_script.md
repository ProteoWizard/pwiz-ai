# TODO-20261103_carafesharp_parity_script.md

## Branch Information
- **Branch**: `Skyline/work/20261103_carafesharp_parity_script`
- **Base**: `master` (049d045e98)
- **Created**: 2026-11-03
- **Status**: In Progress (PR open, awaiting the Perf/Regression gate the parent session queues and maccoss's review)
- **GitHub Issue**: [#4978](https://github.com/ProteoWizard/pwiz/issues/4978)
- **Module**: `osprey`
- **PR**: [#4982](https://github.com/ProteoWizard/pwiz/pull/4982)
- **Worktree**: `C:\proj\wt-carafe` (night-session agent worktree, round 2 wave D)

## Objective

Per Brendan's decision on #4978 (2026-11-03): the eight full-size CarafeSharp parity tests leave the
per-commit unit pass and become a developer-run parity script, like Osprey's cross-implementation
comparison; the committed subset twins stay as the unit tests; `tcregression.ps1` stops running them; the
per-commit pass reads `Passed 108` with nothing skipped.

## Design (as built)

- The comparisons stay C# test methods (they are the only implementation of the checks), tagged
  `TestCategory("FullParity")` (`TestData.FULL_PARITY_CATEGORY`), the same mechanism as the existing
  `Astral` full-size tests. `build.ps1`'s default CPU filter adds `TestCategory!=FullParity`, so no test
  pass runs them.
- `pwiz_tools/CarafeSharp/scripts/Compare-CarafeParity.ps1 [-Dataset Stellar|Astral|All] [-TestName] [-NoBuild]`
  calls `build.ps1 -TestCategory FullParity|Astral -RequireData -TestData Fetch -TestDataPackage <ids>`,
  then reads the trx and prints one line per comparison (outcome, time, first lines of a failure
  message) and `OVERALL: PASS/FAIL`, exit 0/1. Packages: Stellar `testfiles,export`; Astral `astral`
  (TestData.cs: the Astral items read only that package).
- **Location: `pwiz_tools/CarafeSharp/scripts`, not `ai/scripts/CarafeSharp`.** The in-tree `scripts/`
  folder holds what CarafeSharp's own entry points use (`TestData.ps1`, which `build.ps1`,
  `regression.ps1` and `tcregression.ps1` dot-source), and the script is a peer of `regression.ps1`: it
  needs no machine paths, only `build.ps1` and `testdata.json`, versions with the tests it runs, and is
  documented in the in-tree `docs/04-testing.md`. `ai/scripts/CarafeSharp` holds tooling that wraps the
  tree for our workflow (CRLF + inspection, package building, the workflow on machine data). A developer
  without pwiz-ai (Mike's Linux box) can run it.
- `tcregression.ps1` step 1 is now `build.ps1 -NoTests -TestData Fetch -TestDataPackage testfiles,regression-export`
  (the packages `regression.ps1 -Dataset Stellar` reads: FASTA + pairing manifest, and the v2 export);
  steps 2-3 (Stellar golden, StellarSubset repeat) unchanged. Its `Perftests\carafesharp` data folder is
  kept so the agent does not re-fetch.
- `testdata.json` package categories left as they were: `-TestData Fetch` with no category still fetches
  the Stellar packages, which `regression.ps1` needs; the doc now says the default pass reads none.
- Side fix: `CarafeSharp.Models/PeptdeepConstants.cs` had a redundant `using System.Collections.Generic`
  (from #4927) that failed CarafeSharp's ReSharper inspection on master.

## Tasks

- [x] Tag the eight; exclude the category in build.ps1
- [x] Script; docs/04-testing.md ("Full-size parity" section, test-pass and CI tables); tcregression.ps1;
      tcbuild.bat / tctest.bat comments
- [x] Gates (below)
- [x] /code-review medium (triage below)
- [x] PR #4982 (reviewer maccoss); commits ed0eb8892a, 5e23704f08

## Gate evidence

- `Build-CarafeSharp.ps1 -SourceRoot C:\proj\wt-carafe -RunTests -RunInspection -RequireData`:
  `Test outcomes: Passed 108`, inspection zero issues. Log `C:\proj\ai\.tmp\agentD-carafe-build.log`.
- `Compare-CarafeParity.ps1 -NoBuild` (fetched both packages, first time on this machine): 8/8 Passed,
  wall 5:36 incl. fetch, `OVERALL: PASS`. Log `C:\proj\ai\.tmp\agentD-parity-stellar.log`.
  Failure path: `-TestName NoSuchTest` -> `OVERALL: FAIL - Stellar: build.ps1 exited 1`.
- New tcregression step 1 run locally: fetched `carafesharp-testfiles-v1, carafesharp-export-v2`, built.
  Log `C:\proj\ai\.tmp\agentD-tcreg-step1.log`. Steps 2-3 unchanged, not re-run locally.
- Osprey pre-commit (`Build-Osprey.ps1 -SourceRoot C:\proj\wt-carafe -Configuration Debug -RunTests -RunInspection`):
  649 tests, inspection clean. Log `C:\proj\ai\.tmp\agentD-osprey-precommit.log`.
- No regression golden can move: no product code changed.

## Code review (/code-review medium, 8 findings)

Fixed (`5e23704f08`): (1) the script built inside the first dataset's call and set "built" even when that
failed, so `-Dataset All` could run Astral on stale binaries - now builds once up front with
`build.ps1 -NoTests` and stops on failure; (2) `-TestName` with `-Dataset All` failed the leg the name does
not exist in - now refused; (3) `[TimeSpan]::Parse` on a missing trx `duration` - guarded; (4) build.ps1's
fetch example said "regression.ps1 reads them" of a set that also holds export-v1 - reworded;
(5) `ai/scripts/CarafeSharp/Build-CarafeSharp.ps1`'s `-TestData Fetch ... -RequireData` example implied the
default pass reads the packages - split into a default example and a `-TestCategory FullParity` one.
Re-ran: `-Dataset All -TestName Masking` -> FAIL exit 1 with the message; full run (with build) 8/8 PASS,
3:51, log `C:\proj\ai\.tmp\agentD-parity-stellar2.log`.

Dropped: `Measure-CumulativeCoverage.ps1`'s "with data" leg no longer includes FullParity - a measurement
tool, its numbers are documented as pre-change, listed under decisions below; trx parsing duplicated from
build.ps1 / hardcoded trx name - a renamed trx surfaces as "no test results" and FAIL, not silently; the
separate `Perftests\carafesharp` folder on the agent - kept deliberately so the agent does not re-fetch 1.5 GB.

## Decisions Brendan might revisit

- The comparisons are still `[TestMethod]`s in `CarafeSharp.Test`, now in a category no pass runs, rather
  than code moved out of the test assembly; moving them would mean shipping test-only comparison code
  in a product assembly or a second test project for no gain.
- `-Dataset Astral` folds the four existing `Astral`-category tests into the same script (they were
  already developer-run via `build.ps1 -TestCategory Astral`).
- `ai/scripts/CarafeSharp/Measure-CumulativeCoverage.ps1`'s "with data" leg (`build.ps1 -Coverage -RequireData`)
  no longer includes the full-size tests; the doc's coverage table notes it was measured before. Not changed.

## Progress Log

### 2026-11-03 (night session, agent D)
- Built, gated and committed `ed0eb8892a`; code review and PR follow.
