# TODO-20260928_diaumpire_ttof_net10_baseline.md

## Branch Information
- **Branch**: `Skyline/work/20260928_diaumpire_ttof_net10_baseline` (off the .NET 10 port branch
  `Skyline/work/20260612_net8_port`, PR #4619, after #4735 merged into it)
- **Module**: `skyline`
- **Created**: 2026-09-28
- **Status**: PR open; waiting for Nick to confirm the new values on other machines (NICKSH)
- **PR**: #4740 closed 2026-09-29 in favor of chambm's #4738 (same TestDiaTtofDiaUmpireTutorial.json
  byte-for-byte, plus the FullFileset re-record and CleanUpPersistentDir in a `finally`)

## Progress (2026-09-29, MACS2)

- The Bruker fix went in separately as #4735, squash-merged into `20260612_net8_port` (`553a145871`).
- MACS2 (2x Xeon Gold 6354, AVX-512) ran `TestDiaTtofDiaUmpireTutorial` in record mode on a fresh
  download of DIA-TTOF data and got the NIGHTLY values exactly: IrtIntercept -66.861, the same 8
  coefficients, FinalTargetCounts 213/283/1697. So three machines agree and NICKSH is the outlier.
- Leading theory for NICKSH: the stale 8/23 `collinsb_I180316_001_SW-A-diaumpire.mz5` in its
  persistent dir. Outside record mode the test keeps the first `*-diaumpire.*` file and reuses it,
  so NICKSH searched old pseudo-spectra for SW-A. Not yet confirmed.
- Committed MACS2's recorded JSON as `05a25461eb` (coefficients and MassErrorStats only).
  `TestDiaTtofDiaUmpireTutorialFullFileset.json` (NoNightlyTesting) was not re-recorded.
- MACS2's kept intermediate files: `E:\Users\nicksh\SkylineDownloadPath2\Tutorials\DIA-TTOF\DIA-TTOF\DIA\`
- Remaining: normal-mode verification run on MACS2; Nick reruns on NICKSH after deleting
  `*-diaumpire*`, `comet.*`, `make-pin.pin`, `percolator.*` from `D:\Downloads\Tutorials\DIA-TTOF\DIA`;
  then the hygiene items in step 4 below.

## The failure

Nightly "Integration with Perf Tests" (BRENDANX-UW7, SKYLINE-DEV6), .NET 10 port branch, every
run since 2026-09-25, every language (7 failures, identical values each time):

```
Assert.AreEqual failed. Expected:<-0.0771|-0.5769|3.7771|0.6398|-0.5188|0.9288|0.2308|-0.0726>.
Actual:<-0.0954|-0.5658|4.0999|0.5009|-0.5142|0.9069|0.2244|-0.0722>.
  at TestPerf.DiaUmpireTutorialTest.ValidateCoefficients ... DiaUmpireTutorialTest.cs:line 1004
  at TestPerf.DiaUmpireTutorialTest.DoTest() ... line 716
  at TestPerf.DiaUmpireTutorialTest.TestDiaTtofDiaUmpireTutorial() ... line 155
```

It takes `TestDiaTtofTutorial` and `TestDiaTtofFullSearchTutorialExtra` down with it, because
`CleanUpPersistentDir` (`DiaUmpireTutorialTest.cs` ~line 899) is not in a `finally` and leaves
`*-diaumpire.mzML` in the shared `DIA-TTOF\DIA` persistent dir.

## What is established

**Cause: the branch's expected values are stale since #4589.**
- #4589 (`83836d2827`, keeps zero-peak spectra that declare a scan window) deliberately
  re-recorded `TestDiaTtofDiaUmpireTutorial.json` on master (its coefficients moved too,
  e.g. `5.5994 -> 5.803`).
- The branch has its own copy, recorded 2026-07-28 with Comet (`7fbc17e6a4`), and the
  2026-09-24 master merge (`f50ba1c910`) kept it. Every other file #4589 re-recorded
  (DiaSwath TTOF/QE JSONs, PerfImportPrmPasefTest.cs) matches master+#4589 on the branch; only
  the two DIA-Umpire JSONs (branch-specific Comet baselines) are stale:
  `TestDiaTtofDiaUmpireTutorial.json` and `TestDiaTtofDiaUmpireTutorialFullFileset.json`
  (the latter is `NoNightlyTesting`).

**No reader bug (unlike the Bruker one).** Instrumented `SpectraChromDataProvider.IsEmptySpectrum`
on the branch and on master @ `83836d2827` (`I:\git_i\sky_zerolengthspectra`), ran the test on
both: every zero-peak spectrum the branch visits, master visits too, with the same id, the same
`300..2000` scan window and the same decision (kept). Master visits 62 more, all in isolation
windows 6/7/9/35/36 where the branch's Comet-built document has no targets.

**The pwiz-sharp DIA-Umpire port is thread-count independent.** Ran branch `msconvert.exe
--filter "diaUmpire params=..."` (TripleTOF preset + 64 variable windows) on
`collinsb_I180316_002_SW-B.mzML` at Thread=16 twice and Thread=4/NestedThreads=4: the
`<spectrumList>` sections are identical (121413 spectra); only index offsets/checksums differ.

## The blocker: this result is machine-dependent on the branch

On NICKSH (i9-14900K, 32 logical CPUs, no AVX-512) the branch does NOT reproduce the nightly:

| | nightly (both machines) | NICKSH |
|---|---|---|
| IrtIntercept (line 646) | passes -66.861 | **-66.862** (fails before coefficients) |
| ScoringModelCoefficients | -0.0954\|-0.5658\|4.0999\|0.5009\|-0.5142\|0.9069\|0.2244\|-0.0722 | 0.1694\|-0.5246\|3.2978\|0.2689\|-0.3999\|0.7239\|0.0013\|-0.0548 |
| FinalTargetCounts | never reached | 163, 187, 1121 (was 213, 283, 1697) |

Master's committed values DO pass on NICKSH, so the machine dependence is specific to the
branch pipeline (pwiz-sharp DIA-Umpire -> Comet -> Percolator -> library/iRT). DIA-Umpire is
ruled out (above), and the divergence is already present at the iRT step (after the search,
before chromatogram import). Remaining suspects: Comet or Percolator (external exes, thread
counts from the machine), or Skyline's library build / iRT regression.

So re-recording on NICKSH would just move the failure. Recording on a nightly machine would make
the nightly pass but leave the test non-portable.

## Next steps

1. On a nightly machine (or any machine that reproduces the nightly's -66.861), and on NICKSH,
   keep the intermediate outputs and diff them in pipeline order to find the first divergence:
   `*-diaumpire.mzML` (compare `<spectrumList>` only), `comet.*-diaumpire.pep.xml`,
   `make-pin.pin`, `percolator.target.psms.txt`, the `.blib`. Setting `IsRecordMode => true`
   (line ~330) keeps these files in `DIA-TTOF\DIA`.
2. Fix the machine dependence if it is ours (e.g. pin threads or order the search output), or
   accept it and record on the nightly machines.
3. Re-record `TestDiaTtofDiaUmpireTutorial.json` (and FullFileset) and commit it on the branch
   above, alongside the Bruker fix.
4. Hygiene, worth doing regardless: put `CleanUpPersistentDir` in a `finally`; make the DiaSwath
   test's `*-diaumpire.*` deletion unconditional; note that the test deletes all but the FIRST
   `*-diaumpire.*` file and reuses it ("file reusability"), so a stray old file (NICKSH had an
   8/23 `...001_SW-A-diaumpire.mz5`) silently changes what gets regenerated.

## Reproduce

```bash
pwsh -File ai/scripts/Skyline/Build-Skyline.ps1 -Target TestPerf -Configuration Release -Summary -SourceRoot <checkout>
pwsh -File ai/scripts/Skyline/Run-Tests.ps1 -TestName TestDiaTtofDiaUmpireTutorial -Language en -Configuration Release -SourceRoot <checkout>
```

~28 min per run on NICKSH (DIA-Umpire ~4 min/file, Comet, Percolator). Persistent data is in the
Downloads folder (`D:\Downloads\Tutorials\DIA-TTOF` on NICKSH) and is shared by all checkouts,
so do not run two checkouts at once. On a master checkout use `-Target Solution` the first time;
building TestPerf alone left stale test DLLs that fail to load in TestRunner.

## Related: the Bruker fix already on this branch

`f32382a14e` fixed `pwiz-sharp/pwiz/src/Vendor/Bruker/TdfData.cs` omitting the mean ion mobility
array on zero-peak combined TIMS spectra (native pwiz always emits it). That was the cause of
`BrukerPrmPasefImportTest` failing (PeptideRetentionTime 22.8022 vs 22.81); verified failing
without and passing with the fix, and the 15 pwiz-sharp Bruker tests pass. No pwiz-sharp unit
test: none of the three committed TDF fixtures contains a zero-peak combined spectrum. That
investigation's own TODO (TODO-20260928_prmpasef_rt_net10.md) was written on another machine and
is not in pwiz-ai yet.
