# Bruker YEP reader intermittently keeps analysis.yep open after Dispose

## Branch Information
- **Branch**: `Skyline/work/20261125_compassxtract_yep_handle_leak`
- **Base**: `master`
- **Created**: 2026-11-25
- **Status**: Completed
- **Module**: `pwiz`
- **PR**: [#5076](https://github.com/ProteoWizard/pwiz/pull/5076) (merged 2026-11-26)

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

### 2026-11-25 - Second and third code reviews

`/code-review high`: Dispose now takes the read lock (disposed check inside it); FID spectrum released
before its collection. `/code-review max` (no mechanical bug found): FID open/release moved into a
disposable `FidSpectrum`; corrected remarks on cpp's release (its `delete` is a no-op on an RCW) and on
the undisposed path; parameter list documented as owning its collection. Dropped: reentrancy, Dispose
without activation context, COM-typed parameter values, open-owner counter test, pre-existing COM
overhead, single-line if. Follow-up not in this PR: no lock across separate readers, so a multi-file
Skyline import still enters CompassXtract concurrently (predates the PR; worth a two-file soak).

Found outside the diff and filed as #5079: CompassXtract index entries never set MsLevel, so vendor
centroiding treats every YEP/FID spectrum as MS1.

### 2026-11-25 - Two-file concurrent soak

Follow-up from the max review (no lock across separate readers). Diagnostic test (not committed): two
threads, separate readers, YEP and FID fixtures read and disposed together in a loop. On the #5076 code,
30 processes x 200 cycles: 0 crashes, 0 exceptions, 0 held files (`cx-soak/concurrent-diag.log`). No
evidence a process-wide CompassXtract lock is needed. Not run against master as a positive control.

### 2026-11-25 - Concurrent soak on master (positive control)

Same two-thread soak on master's code: 9 of 30 processes crashed, 17 held analysis.yep, 0 exceptions
(`cx-soak/master-diag.log`). 8 crashes stopped on a modal "R6025 pure virtual function call" dialog,
1 was an access violation at CompassXtractMS.dll+0x44B5. CompassXtractMS.dll loads at 0x180000000, so
the overnight crashes at 0x18000C861 were inside it too. Two dumps of the dialog
(`testhost-55204-r6025.dmp`, `testhost-51076-r6025.dmp`) both show it on the .NET finalizer thread in
native code, with neither test thread inside CompassXtract. The fix: 0 of 30. PR description updated
with these numbers. On an interactive nightly agent the R6025 form would hang rather than crash.

### 2026-11-26 - Merged

PR #5076 merged as commit 7e2e1f0495, without a second human review (the change had
been through three code-review passes and the soaks above). Shipped: CompassXtractData
releases every CompassXtract object right after use, children before parent, which ends
both the sticky `analysis.yep` handle and the finalizer-thread crashes in
`CompassXtractMS.dll`; reads and Dispose are serialized. Follow-up found in review:
#5079 (YEP/FID vendor centroiding treated every spectrum as MS1), fixed in #5081, which
was stacked on this branch and retargeted to master after the merge.
