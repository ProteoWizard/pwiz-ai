# Bruker YEP reader intermittently keeps analysis.yep open after Dispose

## Branch Information
- **Branch**: `Skyline/work/20261125_compassxtract_yep_handle_leak`
- **Base**: `master`
- **Created**: 2026-11-25
- **Status**: In Progress
- **Module**: `pwiz`
- **PR**: [#5076](https://github.com/ProteoWizard/pwiz/pull/5076)

## Objective

`Reader_Bruker_Sample_1_A_1_01_985` failed intermittently (clean master build `C:\dev\master_clean\build64.log`,
and about 2% of Bruker suite runs) with "This process still holds a handle on ...Sample_1-A,1_01_985.d after
Dispose". Find the cause and fix it.

## Findings

- An overnight soak of the Bruker suite (200 runs each) showed it on master (3/200) and on master before
  #5057 (5/200), so #5057 did not introduce it.
- The held file is `Analysis.yep`. Once held, it stays held for the life of the process (still held after
  10 s of GC + waiting), so later reads in the same process fail too.
- `CompassXtractData` released only the analysis and its spectrum collection on Dispose. Each spectrum
  (`_spectra[scan]`), its parameter collection and each parameter was left to RCW finalization.
- Repeated read-and-dispose of the fixture in one process, reader unchanged: first failure at cycle 31, 30,
  11, 6 (four processes). With every CompassXtract object released right after use: 0 failures in 200
  cycles, twice.
- The C++ harness suppresses this check for `Analysis.yep` as a CompassXtract bug
  (`VendorReaderTestHarness.cpp` "HACK: bug in CompassXtract"); in the C# reader the cause is ours.

## Tasks

- [x] Release each spectrum, parameter collection and parameter after use (YEP, FID, MALDI source check)
- [x] Full Bruker suite passes (17)
- [x] `/code-review` before opening the PR
- [x] Open the PR

## Regression Test

- **Test name**: `ReaderBrukerTests.Reader_Bruker_Sample_1_A_1_01_985` (post-Dispose handle check)
- **Fails on master**: intermittently (~2% per suite run; ~5% per cycle when repeated in one process)
- **Passes on fix**: 0/200 cycles in one process, twice (2026-11-25). A permanent loop test was not added:
  catching a 5% event reliably needs ~60 cycles (~2 min) per run.

## Progress Log

### 2026-11-25 - Root cause and fix

Diagnostic loop test (not committed) logged each cycle to `ai/.tmp/sessions/20261118-3e7798af/yep-diag-*.log`.
Baseline logs `yep-diag-2.log`, `yep-diag-4-baseline-{1,2,3}.log`; fixed `yep-diag-3-release.log`,
`yep-diag-5-final.log`. Soak data `bruker-soak/soak.csv`.

### 2026-11-25 - Code review, suite soak, PR

`/code-review medium`: fixed the forced-release race (FillSpectrum now under a lock), the OpenFid
error-path release order, the exposed parameter collection (list is now IDisposable) and the Release
comment; dropped the loop regression test (cost), a generic COM wrapper and the cache rebuild cost.

Test host crashes (7 in the overnight soak, 1 in this one) are access violations inside CompassXtract's
native DLLs (non-ASLR, base 0x180000000; three at 0x18000C861, others through junk pointers), all during
the YEP test. Likely the finalizer thread releasing leftover COM objects; the fix removes those releases.

Suite soak, master vs fix, alternating (`bruker-fix-soak/soak.csv`): master 2 handle failures, 1 crash
in 150; fix 0 and 0 in 149 (round 30 excluded: built mid-edit). Opened #5076.
