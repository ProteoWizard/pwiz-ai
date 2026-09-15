# TODO-20260915_wiff2_concurrency_tests.md

## Branch Information
- **Branch**: `Skyline/work/20260915_wiff2_concurrency_tests` (pushed 2026-09-15)
- **Base**: `Skyline/work/20260612_net8_port`
- **Checkout**: `C:\proj\pwiz-work1` (now on the branch above)
- **Module**: `pwiz` (pwiz-sharp vendor reader tests; nothing under `pwiz_tools/Skyline`)
- **Created**: 2026-09-15
- **Status**: In Progress - tests committed, review and PR pending
- **GitHub Issue**: none. Related filed issues: #4638 (retry latch blames AddFramingZeros for
  any SDK failure), #4639 (profile data stamped MS_centroid_spectrum after the centroid latch
  trips) - both pre-existing wiff2 defects found during the same investigation, not fixed here
- **PR**: (pending)

## Objective

Give a home to two `.wiff2` concurrency regression tests that have been modified-and-uncommitted
in `pwiz-work1` since 2026-09-04:

- `Reader_Sciex_wiff2_SecondReaderSurvivesFirstReaderDispose`
- `Reader_Sciex_wiff2_ConcurrentReadersSurviveChurnOnSamePath`

in `pwiz-sharp/pwiz/test/Sciex.Tests/ReaderSciexTests.cs` (a copy of the diff is at
`ai/.tmp/leak-tools/ReaderSciexTests-wiff2-concurrency.patch`, 2026-09-12). They pin the
behaviour that made the one known fix for the wiff2 SDK leak unshippable, so that anyone who
tries that fix again - and someone will, because the leak is the largest recurring managed leak
in the nightly - gets a red test instead of silent data loss.

## Background: the leak, the fix that was tried, and why these tests exist

Extracted from `TODO-20260612_net8_port.md` ("wiff2 leak: diagnosed, deliberately not fixed",
2026-09-03/04) and `TODO-20260907_leak_detection_baseline.md` (2026-09-09). The same analysis is
in the `<remarks>` of `AbstractUnitTest.IsAbWiff2Safe`.

**The leak.** Every `MsDataFileImpl` open of a `.wiff2` leaves a
`Clearcore2.RFLight.SampleDataProvider.SampleDataProviderServer` rooted by its own periodic
`Timer`, ~24 KB per open, which nothing can release: `CreateSampleDataApi` is called per file and
the SDK exposes no shutdown - `ISampleDataApi` and `DataApiFactory` are both non-disposable, and
`CloseFile` closes a file, not the server. Established with `GcRootReporter` (chain:
`Timer._timer -> TimerHolder -> TimerQueueTimer ... -> TimerCallback._target ->
SampleDataProviderServer`) and confirmed in dotMemory; a capture with snapshots 30 iterations
apart (22.65 -> 23.66 MB) is at `ai/.tmp/leak-tools/wiff2-TestInstrumentInfo.dmw`. Four Skyline
tests read `.wiff2` and leaked 26-36 KB/run at R2 = 1.00 every night (`Wiff2ResultsTest`,
`FileTypeTest`, `TestInstrumentInfo`, `TestInstrumentSerialNumbers`).

**The fix that was tried, and reverted.** The C++ reader shares one `ISampleDataApi`
process-wide (`WiffFile2.ipp:64`) and has no leak. Doing the same in the C# port removed the
leak - but cpp keeps one reader per FILE and switches samples in place, while this port opens one
reader per SAMPLE, so several readers share one api and one `StorageLocationPool` entry per path.
`CloseFile` on one reader purges that pool entry, and a still-live reader on the same path then
hits `ObjectDisposedException: SQLiteConnection` - which the reader's catch blocks turn into
**empty spectra, not an error**. Skyline imports a multi-sample `.wiff2` as one replicate per
sample through `MultiFileLoader`, 12 loads at a time, and MsConvertGUI converts in parallel, so
this is the production shape. Silent data loss was judged worse than the leak; the shared-api
change was reverted and Brendan deferred the leak ("do not reopen without asking").

**What was shipped instead (#4659, merged 2026-09-12 into the port branch):** the four Skyline
tests read the equivalent mzML in the leak pass via `AbstractUnitTest.IsAbWiff2Safe` /
`ExtAbWiff2Safe`, and still read real `.wiff2` in pass 2. The leak is excluded from detection,
not fixed.

**These two tests are the guard.** The churn test fails on the shared-api version and passes on
current code; the dispose test is the single-threaded form. They were kept out of #4659 because
that PR was Skyline-side and they are pwiz-sharp-side.

## What has to be decided before the PR

### 1. Where they run - and whether `IsAbWiff2Safe` applies

Brendan's concern is that tests which open `.wiff2` repeatedly would produce consistent detected
leaks in the nightly's leak pass. Checked 2026-09-15:

- `Sciex.Tests` is a pwiz-sharp MSTest project in `pwiz-sharp/Pwiz.sln`, run by `dotnet test` /
  vstest in the pwiz-sharp CI. Skyline's `TestRunner` loads only its own seven assemblies
  (`TEST_DLLS`, `TestRunner/Program.cs:61`), so **as they stand these tests never run in pass 1**
  and cannot appear in a leak report. `IsAbWiff2Safe` is a Skyline `TestUtil` member keyed off
  `TestPass`; it is not reachable from pwiz-sharp and is not needed there.
- The churn test opens readers as fast as it can for 5 seconds - hundreds of leaked
  `SampleDataProviderServer`s in the vstest process. Harmless for a one-shot run, but it is the
  reason the test must NOT be relocated into a Skyline test project without a pass-1 skip: a
  fallback to mzML (what `ExtAbWiff2Safe` does) would make it test nothing, so it would need
  `if (!IsAbWiff2Safe) return;` outright.

**Recommendation:** keep them in `Sciex.Tests`. They test `AbstractWiffFile`, a pwiz-sharp API,
next to the other `Reader_Sciex_*` tests, and the project already has the vendor-license and
native-assembly gating the tests need. No `IsAbWiff2Safe` change. Record the decision in the PR.

### 2. The six review findings from 2026-09-11 (`/code-review max` on #4659's tree)

Only the headline survived in the record: "will not compile without vendor licenses (a Linux CI
break)". On inspection that looks wrong - everything the tests use (`AbstractWiffFile.Open`,
`GetExperiment`, `CycleCount`, `GetTic`, `GetSpectrum`, `XValues`) is in `Sciex.csproj`, which
`Sciex.Tests` references unconditionally; only `Sciex.Wiff2` and the OFX stub are gated on
`IAgreeToVendorLicenses`. The Linux CI check on the PR will settle it (it passes
`IAgreeToVendorLicenses=true` with no native vendors). The other five findings are lost; run
`/code-review max` on the branch again before opening the PR and treat that as the review.

### 3. Fixture availability

Both tests `Assert.Inconclusive` when `swath.api.wiff2` is absent (`FindTestDataRoot()`), which
is the right behaviour on Linux and on agents without the vendor test data - but confirm on
TeamCity that "inconclusive" is not counted as a failure by the vstest step, and that on the
Windows check the fixture IS found so the tests actually execute somewhere.

## Tasks

- [x] Create `Skyline/work/20260915_wiff2_concurrency_tests` off the port branch; commit the
      `ReaderSciexTests.cs` diff from `pwiz-work1` (verified byte-identical to the `.patch` in
      `ai/.tmp/leak-tools/`) - `22dbcc68b4`
- [x] Build and run `Sciex.Tests` locally with vendor licenses: 10/10, both new tests pass (not
      inconclusive), churn test 5 s. Via the new `ai/scripts/PwizSharp/Build-PwizSharp.ps1`
      (`-Project pwiz/test/Sciex.Tests/Sciex.Tests.csproj -RunTests -Filter "Name~wiff2"`) -
      there was no wrapper for building one pwiz-sharp project and running one test project;
      `build.bat` builds and tests everything, `Run-Tests-Parallel.ps1` assumes a prior build
- [ ] Confirm the churn test still FAILS against the shared-api change, if that diff can be
      recovered from the port branch's reflog or reconstructed from `WiffFile2.ipp:64` - the
      test is only worth shipping if it is red on the thing it guards. If it cannot be recovered
      cheaply, say so in the PR and rely on the recorded 2026-09-04 result
- [ ] `/code-review max` from `C:\proj\pwiz-work1`; fix what is real
- [ ] Open the PR: `pwiz: Added .wiff2 concurrent-reader regression tests for the shared
      SampleDataApi hazard`, label `pwiz`, base `Skyline/work/20260612_net8_port`, body carrying
      the background above in short form and the run-location decision
- [ ] Watch the Linux and Windows .NET checks for the compile and fixture questions above
- [ ] Leave the leak itself alone. If a session wants to attempt the shared-api fix again, the
      ownership arbitration it needs (per-path reference counting so `CloseFile` runs only when
      the last reader on that path closes, or one reader per FILE as in cpp) is the design
      question, and these tests are its acceptance test

## Progress Log

### 2026-09-15 - TODO created

Extracted from the port and leak-detection TODOs at Brendan's request, so the tests can travel in
their own PR instead of riding along uncommitted in `pwiz-work1` (they were explicitly left out of
#4659 and #4667). Established that the tests do not run in Skyline's leak pass and so need no
`IsAbWiff2Safe` guard where they are; that the "does not compile without vendor licenses" review
finding is not supported by the project references; and that the other five findings from that
review were never recorded.

Branch created off `ea391bde4e` (port branch tip), tests committed as `22dbcc68b4` and pushed.
`Sciex.Tests` 10/10 locally with vendor licenses. Next: `/code-review max`, then the PR.
