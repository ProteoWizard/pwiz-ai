# .wiff2 reader leaks ~34 KB per open; a shared ISampleDataApi with per-path reader counts fixes it

## Branch Information
- **Branch**: `Skyline/work/20260916_wiff2_shared_sample_data_api`
- **Base**: `Skyline/work/20260915_wiff2_concurrency_tests` (PR #4670), which is based on
  `Skyline/work/20260612_net8_port`. Stacked on purpose: #4670 carries the churn tests that are
  the acceptance test for this fix. Retarget the PR to `Skyline/work/20260612_net8_port` once
  #4670 merges (GitHub retargets automatically).
- **Checkout**: `C:\dev\pwiz-im7`
- **Created**: 2026-09-16
- **Status**: PR open, awaiting CI and Copilot review
- **GitHub Issue**: [#4674](https://github.com/ProteoWizard/pwiz/issues/4674)
- **Module**: `pwiz`
- **PR**: [#4681](https://github.com/ProteoWizard/pwiz/pull/4681) into Skyline/work/20260915_wiff2_concurrency_tests
- **Requester/Reporter**: none. Filed by Brendan, a developer of this project - not an outside
  report, so no credit line.

## Objective

Stop `.wiff2` opens leaking ~34 KB of unreleasable managed memory each, by sharing one
process-wide `ISampleDataApi` as cpp's `WiffFile2.ipp` does.

Every `DataApiFactory.CreateSampleDataApi()` leaves a
`Clearcore2.RFLight.SampleDataProvider.SampleDataProviderServer` rooted by its own periodic
`Timer`. `ISampleDataApi` and `DataApiFactory` are not `IDisposable` and `CloseFile` closes a
file, not the server, so nothing can release it.

## Design - and two wrong turns worth recording

**Final: one shared api + per-path reader counts. No lock on the reader.**

A `Wiff2Sdk` static gateway holds the shared api and, per SDK path, a reader count plus the
sources to close. Only the last reader out of a path calls `CloseFile`. That is the whole fix.

### Wrong turn 1: cpp is not a precedent

An early reading claimed cpp keeps one reader per FILE and so never hits the race. Wrong for the
case that matters:

- `WiffFile::create` (`WiffFile.cpp:1176`) has no cache - a fresh `WiffFile2Impl` per call.
- `Reader_ABI::read(..., MSData&, int runIndex, ...)` (`Reader_ABI.cpp:201-210`), the single-run
  overload an `MSDataFile` open of one sample goes through, calls `WiffFile::create` itself. N
  replicates off one multi-sample `.wiff2` gives **N `WiffFile2Impl` on the same path**.
- Only the vector overload (`Reader_ABI.cpp:234-259`) shares one `wifffile` across samples - that
  is msconvert's all-samples-at-once path, which is why msconvert never saw this.
- cpp's destructor (`WiffFile2.ipp:48-58`) calls `CloseFile` unconditionally, and its locks
  (`SpectrumList_ABI.hpp:67,86`) are per-instance, so they do not serialize siblings on one path.

**The shipping C++ reader therefore has the same race.** Silent (empty spectra, not an
exception). Worth its own issue - still unfiled.

### Wrong turn 2: locking every SDK-object read

An intermediate version locked ~29 accessors across `Wiff2File`, `Wiff2Experiment` and
`Wiff2Spectrum`, on the stated rationale that the SDK objects outlive the calls that return them
and `Wiff2Spectrum` reads `XValues`/`YValues` lazily off its `ISpectrum`.

**That rationale is false.** Verified against
`pwiz-sharp/pwiz/src/Vendor/Sciex/Wiff2/bin/Release/net10.0/SCIEX.Apis.Data.v1.dll`: every
property those lock sites read - `XValues`, `YValues`, `Precursor`, `ScanType`, `MassRanges`,
`Sources`, `SampleName`, `MsLevel`, `StartTimestamp` - has a compiler-generated
`<Name>k__BackingField`. They are auto-properties on detached POCOs, i.e. plain field reads of
already-materialized data. They cannot re-enter the SDK or observe a `CloseFile` purge.

So the read locks bought nothing, cost ~130 lines, serialized the multi-sample import (the named
Skyline workload), and put the shared lock on Skyline's UI thread path via
`MsDataFileScanHelper.Dispose`'s `Join`. All of that is gone: `Wiff2Experiment` and
`Wiff2Spectrum` are now **untouched** by this change.

Credit where due - `/code-review max` found this, with the decompiled evidence.

## Measurements (2026-09-16, this machine)

### What actually fixes it

`swath.api.wiff2` + `7600ZenoTOFMSMS_EAD_TestData.wiff2`, the concurrency tests, 8 runs each:

| Configuration | Result |
|---|---|
| Shared api, no count, no lock | **0 of 8 pass** |
| Shared api, count, no lock (**shipped**) | **8 of 8 pass** |
| Shared api, no count, lock | 8 of 8 pass |
| Shared api, count + lock | 8 of 8 pass |

The count is the necessary and sufficient piece. Re-verified on the final code by disabling the
count in place: **7 of 8 runs fail** (`SQLiteException: bad parameter or other API misuse`,
`ObjectDisposedException`); the one pass is the hazard being probabilistic, as #4670 documents.

Notably, in every one of those failing runs the **cross-path test passed** - only the same-path
churn broke. Direct evidence that the cross-path axis is safe unserialized, which is what the
no-lock decision rests on.

### The multi-sample case

Both in-repo fixtures are single-sample. `D:\test\ABI\5Oct2020_Angio_dwell10.wiff2` (1.1 MB, 11
samples) is the smallest multi-sample file in the local corpus. Ran #4670's churn shape with
three long-lived readers on DIFFERENT sample indices of the one path: **5 of 5 pass**; **0 of 5**
with no arbitration, failing with `ObjectDisposedException: SQLiteConnection` - the exact
exception the old `IsAbWiff2Safe` comment named as why the previous attempt was reverted.
Machine-local; not committed.

### The leak is gone

`TestInstrumentInfo`, Skyline leak pass (pass 1), reading real `.wiff2`. Managed MB per iteration:

- **Without the fix**: 22.47 ... 23.28 over 22 iterations - linear, **~37 KB each**, no plateau.
- **With the fix**: 22.50 22.52 22.53 22.55 then flat at 22.56 - TestRunner stops early, having
  converged. Delta `managed = 0.2 KB`.

Note for nightly-leak readers: TestRunner's own estimator reported `managed = -94.8 KB` for the
LEAKING run, because a GC on the final iteration dropped the sample. The raw per-iteration trace
is unambiguous where the summary number is not.

### Lock scope (from the intermediate version, kept for the record)

Four distinct `.wiff2`, 124,638 spectra, sequential total vs concurrent wall clock: a
process-wide lock gave **1.05x**, a per-path lock **3.45x**. Both are moot now that there is no
lock, but they are why a process-wide lock was rejected before the locks went entirely.

## Defects fixed after review

All found by `/code-review max`, all verified before acting:

- **No finalizer.** A reader dropped without `Dispose` pinned the path's count above zero
  forever, making `CloseFile` unreachable for that path for the rest of the process - reachable
  today via `VendorReaderTestHarness.OpenWithoutDispose`. Added `~Wiff2File`, as the legacy
  `WiffFile.cs:337` already had for the same reason.
- **Constructor threw with the file open.** A throw after `GetSamples` succeeded (a bad sample
  index, or the documented `GetExperiments` `FileNotFoundException`) released the claim but
  closed nothing, and a constructor that throws never sees a `Dispose`. Sources are now
  registered as soon as `GetSamples` returns, and the catch runs the same close path.
- **Per-path count vs per-sample sources.** Only the last reader closed, and only its own
  sample's sources - so on a multi-sample file every other sample's sources were never released.
  `Wiff2Sdk` now collects sources per path and hands all of them to whoever closes.
- **Double-`Dispose` fail-open.** `_disposed` was a non-atomic check-then-set outside any lock,
  and `RemoveReader` returned "you own the close" at count 0. Now `Interlocked.Exchange`, and
  count 0 returns null.
- **`Lazy<T>` cached the api's exception forever**, so one transient SDK init failure disabled
  `.wiff2` for the process - a regression against the api-per-open code, which recovered. Now a
  plain guarded field that retries.
- **Finalizer could stall behind SDK init**: the dictionary lock and the api-creation lock are
  now separate objects.
- **Weak cross-path test.** The first version had no barrier, no overlap assertion, and neither
  thread disposed - it could pass having never overlapped. Replaced by
  `Reader_Sciex_wiff2_CloseOnOnePathDoesNotDisturbAnother`, where the churn is the ONLY reader on
  its path so every dispose reaches a real `CloseFile` while the other path is mid-read. Runtime
  went from 70 ms to ~12 s, which is the point.

## Flagged by review, deliberately NOT fixed here

- `s_framingZerosThrowsError` / `s_doCentroidThrowsError` are racy process-wide latches - but
  **pre-existing**: readers on different paths already ran fully unserialized before this change,
  so this is not a regression. Worth its own issue.
- `_ticCache` / `_cyclesCache` non-atomic publication in `Wiff2Experiment` - same, pre-existing,
  and that class is now untouched by this change.
- `Sciex.Tests.csproj` copies `Reference\*.mzML`, `*.wiff`, `*.wiff.scan` but **not `*.wiff2`**,
  so the documented pwiz-sharp override mechanism silently does not work for either wiff2
  fixture. Verified. One-line csproj fix, but it is #4670's area and no wiff2 override exists
  today - tell Brendan.
- `Reader_Sciex_wiff2_SecondReaderSurvivesFirstReaderDispose` (#4670's) is now close to vacuous:
  with both readers open, `first.Dispose()` cannot reach `CloseFile` by construction. The new
  cross-path test does exercise a real `CloseFile`, so the close path is covered - but that test
  is worth revisiting with Brendan.

## Tasks

- [x] One shared `ISampleDataApi` for the process, retryable after a transient failure
- [x] Per-path reader counts; only the last reader closes
- [x] Per-path source collection so no sample's sources are orphaned
- [x] Claim before the first SDK call; release AND close on constructor throw
- [x] Finalizer, `Interlocked` dispose guard, split locks
- [x] `Reader_Sciex_wiff2_CloseOnOnePathDoesNotDisturbAnother` added
- [x] `Sciex.Tests` 11/11; concurrency tests 8/8; negative control 7/8 fail
- [x] Multi-sample measured locally (5/5, negative control 0/5)
- [x] `IsAbWiff2Safe` / `ExtAbWiff2Safe` removal - exact inverse of 6ef677076e plus its now-unused
      `using pwiz.CommonMsData`
- [x] Four affected Skyline tests pass on real `.wiff2`
- [x] `/code-review max` (the first run reviewed the wrong checkout; the second was pinned to the
      branch and base explicitly)
- [x] Re-run the Skyline leak pass and the four tests on the FINAL code - four pass; leak pass flat at 22.56 MB from iteration 5, delta 0.1 KB over 15 iterations
- [x] Amend the commit (cedf35c6fe, unpushed)
- [x] Open the PR - #4681 (`pwiz:` prefix, `pwiz` label, `Fixes #4674`)
- [ ] File the cpp-side issue

## Regression Test

- **Test names**: `Reader_Sciex_wiff2_ConcurrentReadersSurviveChurnOnSamePath` and
  `Reader_Sciex_wiff2_SecondReaderSurvivesFirstReaderDispose` (#4670), plus
  `Reader_Sciex_wiff2_CloseOnOnePathDoesNotDisturbAnother` (added here). The leak itself is
  guarded by the `IsAbWiff2Safe` removal, so the nightly leak pass reads `.wiff2` again.
- **Test project**: `pwiz-sharp/pwiz/test/Sciex.Tests`; Skyline `TestData` leak pass
- **Fails without the fix**: yes - 7 of 8 runs with the count disabled in place, 0 of 5 on the
  multi-sample file, and the leak pass climbs ~37 KB per iteration
- **Passes on fix**: yes - 8 of 8, 5 of 5, flat leak pass, 11-test suite, four Skyline tests

## Progress Log

### 2026-09-16 - Session start, fix, and two design corrections

Branched from #4670's head so the churn tests were available. Implemented the issue's per-path
refcount (8/8 green), then reworked it to a static api with mutexed access at Matt's request,
which prompted reading cpp properly and finding it is not a precedent. Measured a process-wide
lock at 1.05x vs per-path 3.45x on concurrent multi-file reads and narrowed accordingly.

`/code-review max` then showed the read locks were justified by a false premise - the SDK's
contract objects are detached POCOs - so the locks came out entirely, leaving the reference
count, which the measurements had shown all along was the sufficient piece. `Wiff2Experiment`
and `Wiff2Spectrum` went back to untouched. Seven further defects from the same review are
fixed; four more are recorded above as pre-existing or out of scope.

The first `/code-review` run inferred its target from the shell's working directory and spent
29 minutes reviewing an unrelated branch. The re-run named the branch, the base and the expected
file set explicitly.
