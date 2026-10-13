# TestDiaTtofDiaUmpireTutorial fails on Server 2019 TeamCity agents because the UCRT rounds Comet's PIN values differently

## Branch Information
- **Branch**: `Skyline/work/20261012_diaumpire_ttof_msfragger`
- **Base**: `master`
- **Created**: 2026-10-12
- **Status**: In Progress
- **GitHub Issue**: [#4828](https://github.com/ProteoWizard/pwiz/issues/4828)
- **Module**: `skyline`
- **PR**: [#4834](https://github.com/ProteoWizard/pwiz/pull/4834)
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

- [x] Switch DiaUmpireTutorialTest search engine from Comet to MSFragger
      (handle MsFraggerDownloadDlg like DdaTutorialTest/DiaSearchTutorialTest)
- [x] Rewrite the Comet-rationale comment for MSFragger
- [x] Adjust/remove Comet-specific settings (Ms2Analyzer, num_output_lines,
      intermediate-file globs) and set an MSFragger fragment tolerance
- [x] Re-baseline expected values (record mode): TTOF, QE Extra, and both FullFileset JSONs
- [x] Re-record audit logs for TTOF and QE Extra in en, fr, ja, tr, zh (via new -RecordAuditLogs)
- [x] Verify runtime/memory is acceptable
- [x] Run test repeatedly locally to confirm stable counts (5 languages, fresh search each)
- [x] CodeInspection + /code-review before PR

## Regression Test

- **Test name**: TestDiaTtofDiaUmpireTutorial (the failing test itself)
- **Test project**: TestPerf
- **Fails on master**: yes, on Server 2019 cloud agents only (TeamCity builds 15555, 15556, 15562)
- **Passes on fix**: yes - TeamCity PR perf build 4214145 (#15581, 6f3aac2942) on a Windows 10.0.17763
  (Server 2019) cloud agent: TestDiaTtofDiaUmpireTutorial-en 0 failures, 1025 s, fresh MSFragger
  4.1 + JRE 17 + crux 4.3 tools. LibraryPeptideCount assert (17132) held. QE Extra is not in that config.

## Progress Log

### 2026-10-12 - Session Start

Created branch from master 5ce7256a61. Starting on the MSFragger switch.

* Switched the search to MSFragger; restored pre-Comet fragment tolerances
  (TTOF 40 ppm, QE 20 ppm); added MsFraggerDownloadDlg handling; cleanup now
  targets MSFragger/Percolator leftovers.
* Tutorial HTML still says MS Amanda - pre-existing mismatch (test already used Comet); left alone.
* Developer confirmed the FullFileset baselines are to be re-recorded on this branch too.
* Developer posted the start-of-work comment on #4828.
* TTOF recorded (en, 14 min): LibraryPeptideCount 14107 -> 17132; final targets
  11/213/283/1697 -> 11/217/289/1733; iRT 2.995/-66.861 -> 2.997/-66.935.
* Audit logs CANNOT be recorded in record mode: CheckRecordMode() throws right after
  DoTest(), before EndAuditLogging(). So: phase 1 = record JSONs with IsRecordMode=true;
  phase 2 = IsRecordMode=false + TestRunner.exe directly with recordauditlogs=on,
  language=en-US,fr-FR,ja-JP,tr-TR,zh-CHS loop=1 (also verifies the new JSONs).
* Fixed: moved CheckRecordMode() out of RunTest() to after EndAuditLogging() in
  TestFunctional; added -RecordAuditLogs to Run-Tests.ps1 (pwiz-ai, uncommitted until verified).
  Record mode + -RecordAuditLogs then recorded the en logs in one run (verified).
* Record mode still cannot cover other languages: TestRunner skips remaining languages
  after a failure (Program.cs ~2735), and record mode always fails. Doc says two runs.
* Phase 1 JSONs (en, record mode): QE Extra 8742 -> 10087; TTOF FullFileset 21316 -> 25615
  (28 min); QE FullFileset 12928 -> 15222 (68 min). (The record-mode rerun matched TTOF, but it reused the kept search outputs, so it is not a determinism check.)
* en audit-log diffs reviewed: engine, fragment tol 40 ppm, MS2 analyzer line gone,
  Peptides mapped/targets 100/101 -> 102/103 (TTOF).
* First all-language run: en passed its asserts for both tests (fresh search: TTOF 432 s,
  QE 882 s) but failed at cleanup with "PersistentFilesDir has been modified" - the
  record-mode runs had left -diaumpire outputs there (this test keeps them in record mode)
  and the normal cleanup deleted them. One-time artifact; rerunning.
* Rerun: all 10 test/language runs passed (fresh search each run; TTOF ~800-960 s,
  QE ~1560-1650 s); counts identical across languages. fr/ja/tr/zh audit logs recorded
  with the same changes as en. JSONs byte-identical to phase 1.
* Solution build clean; CodeInspection passed. Committed 2ed76834b8.
* /code-review medium: fixed one real leak - MSFragger writes decoy_*.fasta + .pepindex into
  the persistent DDA_search dir (missed locally because record mode created them before the
  snapshot; a fresh nightly download would fail). Cleanup now clears them; both tests pass
  from a clean dir and leave it clean (f2113f451d). Dropped the other 6 findings (old Comet
  globs, download gating, helper duplication, topN default already 1, record-mode order, comment).
