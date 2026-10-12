# Diagnose TestDiaTtofDiaUmpireTutorial library count difference on TeamCity

## Branch Information
- **Branch**: `Skyline/work/20261011_diaumpire_ttof_diag` (DRAFT, not for merge)
- **Base**: `master`
- **Created**: 2026-10-11
- **Status**: Draft PR closed 2026-10-12 after finding the root cause; awaiting a decision on #4828 (discussed by email).
- **Module**: `skyline`
- **PR**: [#4826](https://github.com/ProteoWizard/pwiz/pull/4826) (draft, closed unmerged)
- **GitHub Issue**: [#4828](https://github.com/ProteoWizard/pwiz/issues/4828)
- **Checkout**: `E:\Users\nicksh\git_e\sky_TestDiaTtofDiaUmpireTutorial` (MACS2)

## Problem

On TeamCity, TestDiaTtofDiaUmpireTutorial fails at `DiaUmpireTutorialTest.cs:661`:
`LibraryPeptideCount` expected 14107, actual 14094. Another session suspected AVX-512.

## Established on MACS2 (Xeon Gold 6354, AVX-512, 72 logical cores), 2026-10-11

- The test passes (14107) with .NET's AVX-512 on (default) and off (`DOTNET_EnableAVX512=0`;
  `DOTNET_EnableAVX512F` is ignored on .NET 10).
- DIA-Umpire output (msconvert, .NET 10) is byte-identical per spectrum across Thread=1 vs 36
  and AVX-512 on vs off.
- Comet pins are identical at 4 vs 72 threads.
- So the difference comes from something specific to the TeamCity agent (CPU family, OS/UCRT,
  or the native crux build's behavior there). Which stage diverges is still unknown.
- Running three copies of this test at once on MACS2 (separate SKYLINE_DOWNLOAD_PATH each)
  stretched a ~40 minute run to ~3.5 hours. It looked hung at "[step 7 of 7]", but it was only slow.

## TeamCity results, builds 15555 and 15556 (2026-10-11)

- Agents pwiz-windows-i-0119f642b1075180f and pwiz-windows-i-02052ef86cb16ed5e (cloud).
- Both agents got 14094 in BOTH runs: as-is and with DOTNET_EnableAVX512=0. So .NET's AVX-512
  code paths are ruled out, and the result is repeatable on those agents.
- No DiaUmpireDiag.zip was published: the `=>` in the echoed publishArtifacts message was a cmd
  redirection. Fixed in ecea77372d (escaped as `=^>`, plus a `dir /s` of the diag folder).

## ROOT CAUSE: build 15562 (cloud) vs MACS2 (2026-10-12)

- Cloud agent EC2AMAZ-HH9KVFB: Xeon Platinum 8375C, 8 cores, Windows 10.0.17763 (Server 2019),
  ucrtbase 10.0.17763.8276. MACS2: Windows 10.0.20348, ucrtbase 10.0.20348.5622.
- DIA-Umpire output: identical (per-spectrum digests match).
- Comet (crux.exe) pins differ only in printf rounding of exact binary ties: IonFrac 0.03125 is
  written 0.0313 on 17763 and 0.0312 on 20348 (also 0.15625, 0.28125, ... and deltCn like
  0.0703125). About 1,000 rows per file, plus 1 PSM with different lnExpect/lnNumSP.
  The old UCRT rounds ties up; newer UCRT (Windows 10 2004 / 19041 on) rounds the exact
  binary value correctly, giving round-half-even on ties. crux uses the OS's ucrtbase.dll.
- Percolator trains on those features, so every score shifts slightly, and the library gets
  14105 vs 14118 distinct modified sequences, which gives the test's 14094 vs 14107.
- MacCoss TeamCity Agent 1 (build on ecea77372d) passed the count check; its diag files were
  deleted by TestRunner's leftover-temp-files check, because DiaUmpireDiag was under TestResults.
- Comparison tools: `ai/.tmp/sessions/20261011-avx512/compare_diag.py` and `pin_diff_columns.py`
  (on MACS2); output in `cmp-cloud15562-vs-macs2.txt` and `pin-diff-columns.txt` there.

## Diagnostic PR

- `DiaUmpireTutorialTest.cs`: when `SKYLINE_DIAUMPIRE_DIAG_DIR` is set, keeps Comet intermediates
  and copies them, plus percolator output, the .blib and .irtdb, to that directory. Writes
  per-spectrum SHA256 digests of each `*-diaumpire.mzML` and a `machine.txt` (CPU, OS, .NET, ucrtbase
  version, FMA/AVX2/AVX-512 support).
- `tc-perftests.bat`: runs only this test, once as-is and once with `DOTNET_EnableAVX512=0`, and
  publishes `DiaUmpireDiag.zip` through a `##teamcity[publishArtifacts]` service message.
- Local reference output: `E:\Users\nicksh\diaumpire_avx512_diag\local-macs2` on MACS2.

## Next steps

- [x] Rerun TeamCity on ecea77372d and download DiaUmpireDiag.zip (build 15562).
- [x] Compare stages against local-macs2: first divergence is Comet's printf tie rounding (UCRT).
- [ ] Decide the fix in #4828 (agent OS upgrade, test accepting both counts, or static-UCRT crux).
- [x] Clean up MACS2 worktrees `sky_diaumpire_avx512*`.
- [ ] Clean up `E:\Users\nicksh\diaumpire_avx512_*` on MACS2.
