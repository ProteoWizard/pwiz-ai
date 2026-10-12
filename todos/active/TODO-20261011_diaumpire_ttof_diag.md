# Diagnose TestDiaTtofDiaUmpireTutorial library count difference on TeamCity

## Branch Information
- **Branch**: `Skyline/work/20261011_diaumpire_ttof_diag` (DRAFT, not for merge)
- **Base**: `master`
- **Created**: 2026-10-11
- **Status**: In Progress. Draft PR opened to collect intermediates from the failing TeamCity agent.
- **Module**: `skyline`
- **PR**: (pending)
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

## Diagnostic PR

- `DiaUmpireTutorialTest.cs`: when `SKYLINE_DIAUMPIRE_DIAG_DIR` is set, keeps Comet intermediates
  and copies them, plus percolator output, the .blib and .irtdb, to that directory. Writes
  per-spectrum SHA256 digests of each `*-diaumpire.mzML` and a `machine.txt` (CPU, OS, .NET, ucrtbase
  version, FMA/AVX2/AVX-512 support).
- `tc-perftests.bat`: runs only this test, once as-is and once with `DOTNET_EnableAVX512=0`, and
  publishes `DiaUmpireDiag.zip` through a `##teamcity[publishArtifacts]` service message.
- Local reference output: `E:\Users\nicksh\diaumpire_avx512_diag\local-macs2` on MACS2.

## Next steps

- [ ] Download DiaUmpireDiag.zip from the TeamCity run.
- [ ] Compare digests, then pep.xml/pin, then percolator output, against local-macs2 to find the
      first diverging stage.
- [ ] Fix (or make strict/deterministic) the diverging stage on a real branch; close this draft.
- [ ] Clean up MACS2 worktrees `sky_diaumpire_avx512*` and `E:\Users\nicksh\diaumpire_avx512_*`.
