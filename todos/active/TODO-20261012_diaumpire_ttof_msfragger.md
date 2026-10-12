# TestDiaTtofDiaUmpireTutorial fails on Server 2019 TeamCity agents because the UCRT rounds Comet's PIN values differently

## Branch Information
- **Branch**: `Skyline/work/20261012_diaumpire_ttof_msfragger`
- **Base**: `master`
- **Created**: 2026-10-12
- **Status**: In Progress
- **GitHub Issue**: [#4828](https://github.com/ProteoWizard/pwiz/issues/4828)
- **Module**: `skyline`
- **PR**: (pending)
- **Test Name**: TestDiaTtofDiaUmpireTutorial
- **Fix Type**: failure

## Objective

TestDiaTtofDiaUmpireTutorial fails on the Server 2019 TeamCity cloud agents
(`LibraryPeptideCount` 14094 vs 14107). `crux.exe` (Comet) writes PIN features
through the system UCRT `printf`, which rounds exact binary ties up on build 17763
and to even on 19041+. Percolator trains on those features, so the library count
shifts. Full analysis in #4828; diagnostics in closed draft PR #4826.

Approach (Matt C's proposal): search with MSFragger instead of Comet. MSFragger
(Java) and `FixMSFraggerPin` (.NET 10) format the PIN features independently of
the OS C runtime; crux is then used only as Percolator, which reads the pin.
Comet stays covered by TestFunctional/DdaSearchTest.

## Tasks

- [ ] Switch DiaUmpireTutorialTest search engine from Comet to MSFragger
      (handle MsFraggerDownloadDlg like DdaTutorialTest/DiaSearchTutorialTest)
- [ ] Rewrite the Comet-rationale comment for MSFragger
- [ ] Adjust/remove Comet-specific settings (Ms2Analyzer, num_output_lines,
      intermediate-file globs) and set an MSFragger fragment tolerance
- [ ] Re-baseline expected values (record mode) for the TTOF variants
- [ ] Verify runtime/memory is acceptable
- [ ] Run test twice locally to confirm stable counts
- [ ] CodeInspection + /code-review before PR

## Regression Test

- **Test name**: TestDiaTtofDiaUmpireTutorial (the failing test itself)
- **Test project**: TestPerf
- **Fails on master**: yes, on Server 2019 cloud agents only (TeamCity builds 15555, 15556, 15562)
- **Passes on fix**: (pending - needs a TeamCity cloud-agent run)

## Progress Log

### 2026-10-12 - Session Start

Created branch from master 5ce7256a61. Starting on the MSFragger switch.
