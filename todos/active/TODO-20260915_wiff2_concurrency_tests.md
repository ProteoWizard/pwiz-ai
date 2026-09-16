# TODO-20260915_wiff2_concurrency_tests.md

## Branch Information
- **Branch**: `Skyline/work/20260915_wiff2_concurrency_tests` (pushed 2026-09-15)
- **Base**: `Skyline/work/20260612_net8_port`
- **Checkout**: `C:\proj\pwiz-work1` (now on the branch above)
- **Module**: `pwiz` (pwiz-sharp vendor reader tests; nothing under `pwiz_tools/Skyline`)
- **Created**: 2026-09-15
- **Status**: PR open, awaiting CI and review
- **GitHub Issue**: [#4674](https://github.com/ProteoWizard/pwiz/issues/4674) - the leak fix itself, filed
  2026-09-15 and assigned to Matt (the wiff2 reader is his). Related filed issues: #4638 (retry latch blames AddFramingZeros for
  any SDK failure), #4639 (profile data stamped MS_centroid_spectrum after the centroid latch
  trips) - both pre-existing wiff2 defects found during the same investigation, not fixed here
- **PR**: [#4670](https://github.com/ProteoWizard/pwiz/pull/4670) into `Skyline/work/20260612_net8_port`

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
break)". **It was right, and my first reading of it was wrong**: `Sciex.csproj` does reference
unconditionally, but it `<Compile Remove>`s `AbstractWiffFile.cs` itself whenever
`NativeVendorsAvailable != true`, which is `IAgreeToVendorLicenses AND PwizTargetIsWindows` -
false on Linux with the licences agreed. The 2026-09-15 `/code-review max` reproduced it
(12 `CS0103`s with `-p:IAgreeToVendorLicenses=false`). Fixed by moving the tests to their own
file, removed under the same condition, as `Agilent.Tests.csproj` does.

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
- [x] Confirm the churn test FAILS against the shared-api change: `stash@{0}` in `pwiz-work1`
      holds it (with per-path refcounting). Bare shared api (refcount disabled): original test
      6/6 red, reworked test 8/8 red. Refcounted: 8/8 green. See the 2026-09-15 entry
- [x] `/code-review max`: 15 findings, the real ones folded into `b5e25403b8`
- [x] PR #4670 opened
- [ ] Watch the Linux and Windows .NET checks (the no-vendor build passes locally; TeamCity
      confirms the fixture is found on the Windows agent so the tests execute, not Inconclusive)
- [x] Leave the leak itself alone here: handed to Matt as #4674 with the refcounted fix, the
      measurements, and the multi-sample gap; #4670's churn test is its acceptance test

## Progress Log

### 2026-09-15 - TODO created

Extracted from the port and leak-detection TODOs at Brendan's request, so the tests can travel in
their own PR instead of riding along uncommitted in `pwiz-work1` (they were explicitly left out of
#4659 and #4667). Established that the tests do not run in Skyline's leak pass and so need no
`IsAbWiff2Safe` guard where they are; that the "does not compile without vendor licenses" review
finding is not supported by the project references; and that the other five findings from that
review were never recorded.

Branch created off `ea391bde4e` (port branch tip), tests committed as `22dbcc68b4` and pushed.
`Sciex.Tests` 10/10 locally with vendor licenses.

### 2026-09-15 (later) - review, the guard measured against the thing it guards, PR #4670

`/code-review max` on `22dbcc68b4` returned 15 findings. The ones that changed the code:

- **Linux break, reproduced** (see decision 2 above) - own file, `<Compile Remove>` gated.
- **`addZeros:true` blinds the oracle**: `FetchSpectrumWithRetry` swallows the first SDK
  failure through a process-wide latch and retries. Measured on the bare shared api: with
  `addZeros:true` one of three readers reported; with `false`, all three.
- **The dispose test cannot observe the purge**: the SDK re-creates a purged storage location
  on the next request, so only an in-flight request sees it. Measured: the dispose test stayed
  green on the bare shared api every run while the churn test went red. Its doc now says so.
- No hang guard (`[Timeout(60_000)]` added), `first` not disposed on a failure path (`using`),
  `TargetInvocationException` hiding the real error (`GetBaseException`), `CycleCount`
  memoized so the post-dispose assertion was dead (baseline comparison on TIC and spectrum),
  duplicated health checks and fixture preamble (helpers), single-line ifs, a 5 s clock with
  no proof any churn happened (fixed 150 opens with counters).
- `GetTic` is also memoized (the review said it was fresh; `Wiff2File.cs` `_ticCache` says
  otherwise), so the spectrum is the only read that re-enters the SDK each iteration.

**Measuring the guard.** `git stash list` in `pwiz-work1` turned up the shared-api attempt
(`stash@{0}`, "WIP on Skyline/work/20260612_net8_port: 5c046bdb7a"): a static
`Lazy<ISampleDataApi>`, a per-path `_openCounts` dictionary so only the last reader on a path
calls `CloseFile`, and `SKY_WIFF2_NOCLOSE` diagnostics. Checked out over `Wiff2File.cs`:

| Wiff2File.cs variant | original churn test | reworked churn test | dispose test |
|---|---|---|---|
| current (api per reader) | green | green (8 s) | green |
| stash as written (shared + refcount) | green 5/5 | green 8/8 (1 s) | green |
| stash with refcount disabled (bare shared) | **red 6/6** | **red 8/8** | green |

Two things the rework had to get right to keep the reworked test at 8/8: the churn thread must
touch only the cycle count (a spectrum read of its own, whose SDK enumerator is never disposed,
halved the rate - presumably `CloseFile` failing or deferring with a statement still open, and
`Dispose` swallows that), and the churn needs ~150 opens (100 gave 3/6, 20 gave 2/5). A
readiness barrier that held the churn until every reader was open made no difference.

**For Brendan - the refcounted shared api passes its acceptance test.** The record says the
shared-api fix was reverted because the churn test proved it caused silent data loss; the
stash shows a later iteration with per-path reference counting that this test does not fail,
8/8. That is the arbitration the 2026-09-03 entry said was needed. Not acted on ("do not reopen
without asking"); whether the stash also removes the leak in pass 1 (it should - one
`SampleDataProviderServer` per process instead of per open) has not been measured. If it does,
`IsAbWiff2Safe` and the four mzML fallbacks can go, and `Wiff2ResultsTest` etc. read real
`.wiff2` in the leak pass again. That would be its own PR, gated by #4670's tests.

PR #4670 opened into the port branch, label `pwiz`. `ai/scripts/PwizSharp/Build-PwizSharp.ps1`
gained `-NoVendorLicenses` for the Linux-shaped build check.

### 2026-09-15 (evening) - the refcounted fix measured; handed to Matt as #4674

Brendan: the wiff2 reader is Matt's, and the port has only *hidden* the leak for its baseline.
Measured before filing, all on the stash's refcounted shared api vs current code:

- **Leak**: `TestInstrumentInfo` pass 1 with the mzML fallback disabled. Current: LEAKED
  34.4 KB/run, linear over 9,951 iterations (22.65 -> 364.8 MB - TestRunner's leak hanger ran
  it for 3 h; see the method note). Refcounted: flat at 22.77 MB, no leak.
- **Two different files concurrently**, 2 readers each, churn alternating both paths:
  refcount 4/4 green, bare shared api 3/3 red.
- **Three threads open/read/dispose on one path**, no long-lived reader (the stash's
  increment-at-end-of-constructor window): refcount 5/5 green, bare 2/3 red - one failure
  as `cycles 0` with a spectrum, silently.
- **Skyline's four wiff2 tests**, pass 2 x3: green.
- **Not measurable here: multiple samples of one multi-sample `.wiff2`.** No such fixture on
  this machine or in test data (`OnyxTOFMS.wiff2` in `SmallWiff.zip` is legacy format). This is
  the case Brendan recalls the 09-03 session hitting; the record does not name it. Stated as the
  open gap in #4674.

Also checked: Matt's #4640 is the `.wiff` (Clearcore2) side and does not touch `Wiff2File.cs`;
#4670 merged onto it locally is 10/10. Replied to his comment on #4670 accordingly.
