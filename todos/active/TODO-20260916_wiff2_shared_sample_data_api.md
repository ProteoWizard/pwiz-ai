# .wiff2 reader leaks ~34 KB per open; a shared ISampleDataApi under a per-path lock fixes it

## Branch Information
- **Branch**: `Skyline/work/20260916_wiff2_shared_sample_data_api`
- **Base**: `Skyline/work/20260915_wiff2_concurrency_tests` (PR #4670), which is based on
  `Skyline/work/20260612_net8_port`. Stacked on purpose: #4670 carries the churn tests that are
  the acceptance test for this fix. Retarget the PR to `Skyline/work/20260612_net8_port` once
  #4670 merges (GitHub retargets automatically).
- **Checkout**: `C:\dev\pwiz-im7`
- **Created**: 2026-09-16
- **Status**: Code complete and measured; not committed. Next: `/code-review max`, then the PR.
- **GitHub Issue**: [#4674](https://github.com/ProteoWizard/pwiz/issues/4674)
- **Module**: `pwiz` (pwiz-sharp Sciex reader; the `IsAbWiff2Safe` removal touches
  `pwiz_tools/Skyline` test code, but the intent of the work is the vendor reader)
- **PR**: (pending)
- **Requester/Reporter**: none. Filed by Brendan, a developer of this project, handing the
  measured fix to the reader's owner - not an outside report, so no credit line (see
  version-control-guide.md, "Crediting Reporters and Requesters").

## Objective

Stop `.wiff2` opens leaking ~34 KB of unreleasable managed memory each, by sharing one
process-wide `ISampleDataApi` as cpp's `WiffFile2.ipp` does.

Root of the leak: every `DataApiFactory.CreateSampleDataApi()` leaves a
`Clearcore2.RFLight.SampleDataProvider.SampleDataProviderServer` rooted by its own periodic
`Timer`. `ISampleDataApi` and `DataApiFactory` are not `IDisposable` and `CloseFile` closes a
file, not the server, so nothing can release it.

## Design (decided 2026-09-16, changed twice from the issue's proposal)

The issue proposed per-path reference counting alone. Matt asked for **a static api with mutexed
access instead**; reading the cpp reader then showed cpp is not a precedent for either, and
measuring showed a process-wide lock is too coarse. What landed is a per-path lock plus the
count.

**What cpp actually does, and why it is not a precedent.** An earlier reading of this claimed cpp
keeps one reader per FILE and so never hits the race. That is wrong for the case that matters:

- `WiffFile::create` (`WiffFile.cpp:1176`) has no cache - a fresh `WiffFile2Impl` per call.
- `Reader_ABI::read(..., MSData&, int runIndex, ...)` (`Reader_ABI.cpp:201-210`), the single-run
  overload an `MSDataFile` open of one sample goes through, calls `WiffFile::create` itself. N
  replicates off one multi-sample `.wiff2` gives **N `WiffFile2Impl` on the same path**.
- Only the vector overload (`Reader_ABI.cpp:234-259`) shares one `wifffile` across samples. That
  is msconvert's all-samples-at-once path, which is why msconvert never saw this.
- cpp's destructor (`WiffFile2.ipp:48-58`) calls `CloseFile` unconditionally, and its locks
  (`SpectrumList_ABI.hpp:67,86`) are per-instance, so they do not serialize siblings on one path.

So the shipping C++ reader has the same race. **Worth its own issue against the cpp side** - the
failure is silent (empty spectra, not an exception).

**What landed.** A `Wiff2Sdk` static gateway holding three things:

1. One `Lazy<ISampleDataApi>` for the process, which removes the leak.
2. **A lock per path**, held across every SDK call *and* every read of an SDK object it handed
   back. Locking only the calls would not be enough: the objects outlive them, and
   `Wiff2Spectrum` reads `XValues`/`YValues` off its `ISpectrum` whenever the caller asks. That
   is why the diff is large - roughly 27 accessors across `Wiff2File`, `Wiff2Experiment` and
   `Wiff2Spectrum` now lock. Monitor, so a locked member calling another one is fine. The lock
   object is threaded from `Wiff2File` through the experiment to the spectrum.
   - Per PATH, not per reader, because the hazard is per path and cpp's per-reader locks do not
     cover siblings. Per PATH, not process-wide, because one global lock also serialized readers
     of DIFFERENT files and cost ~3x on a concurrent multi-file read (measured below) while
     buying nothing: every failure mode here is same-path.
   - `s_paths` entries are never removed, deliberately: a path's lock must be the same object
     for every reader that ever touches it, and dropping the entry at count zero would hand the
     next reader a different lock while a spectrum from the previous one is still alive.
3. Per-path open counts, so only the last reader on a path calls `CloseFile`. **Not** what makes
   this correct - the lock alone is correct, measured below. It keeps a multi-reader import from
   paying a purge and a re-create on every `Dispose`.

Two smaller decisions: the count and the lock are keyed on the resolved SDK path, not
`WiffPath`, so two readers spelling one file differently still share both; and the claim is
taken before the first SDK call and released on constructor throw, closing the window the issue
listed as unmeasured. `Dispose` takes the path lock BEFORE dropping the count, so a reader
constructing on the same path is either already counted (and we do not close under it) or
blocked until the close is done.

## Measurements (2026-09-16, this machine)

### Arbitration - what each piece is for

`swath.api.wiff2`, #4670's concurrency tests, 8 runs each:

| Configuration | Result | churn test time |
|---|---|---|
| Shared api, no lock, no count | **0 of 8 pass** | - |
| Shared api, lock, no count | 8 of 8 pass | 12 s |
| Shared api, lock, per-path count | 8 of 8 pass | 1 s |

The negative control reproduced all three documented failure modes, including the silent one:
`SQLiteException: bad parameter or other API misuse`, `ObjectDisposedException`, and
`TIC differs (0 points vs 44)`.

The middle row shows the count is a throughput measure, not a correctness one - and that it is
worth keeping: dropping it costs ~12x on the churn workload (47 ms -> 858 ms on the dispose
test), the purge/re-create the shared location pays on every close.

### Lock scope - why per-path and not process-wide

Four distinct `.wiff2` (`D:\test\ABI\210319_CEoptim\Raw data\210319_004_MRMoptim1-4.wiff2`,
~2.8 MB each), all 124,638 spectra, sequential total vs concurrent wall clock:

| Lock scope | sequential | concurrent | speedup |
|---|---|---|---|
| Process-wide | 8264 ms | 7891 ms | **1.05x** |
| Per path | 6150 ms | 1783 ms | **3.45x** |

A process-wide lock took essentially the whole parallel gain, which is what Skyline spends
importing several `.wiff2` replicates at once. Per-path recovers it and still covers every
measured failure, all of which are same-path. Its one assumption - that the shared api tolerates
concurrent calls on different paths - is now pinned by
`Reader_Sciex_wiff2_ConcurrentReadersOnDifferentPathsAgree` rather than left to cpp precedent.

### The multi-sample case the issue could not reach

Both in-repo `.wiff2` fixtures are single-sample. `D:\test\ABI\5Oct2020_Angio_dwell10.wiff2` is
the smallest multi-sample file in the local corpus (1.1 MB, 11 samples). Ran #4670's churn shape
against it with the three long-lived readers on DIFFERENT sample indices of the one path, and
the churn cycling samples too:

| Configuration | Result |
|---|---|
| Final design (per-path lock + count) | **5 of 5 pass** (150/150 churn opens, 4.4k-6.5k reads) |
| Shared api, no lock, no count | **0 of 5 pass** |

The negative control failed with `ObjectDisposedException: SQLiteConnection` - the exact
exception the old `AbstractUnitTest.IsAbWiff2Safe` comment named as the reason the previous
attempt at this fix was reverted - plus `NullReferenceException` and `SQLiteException`.

Machine-local only; not committed, since the fixture is not in the repo.

### The leak is gone

`TestInstrumentInfo`, Skyline leak pass (pass 1), reading real `.wiff2` after the
`IsAbWiff2Safe` removal. Managed MB per iteration:

- **Without the fix** (reader change stashed): 22.47 22.56 22.60 22.66 22.70 22.73 22.77 22.80
  22.84 22.87 22.91 22.94 22.98 23.01 23.05 23.08 23.12 23.15 23.19 23.21 23.25 23.28 - linear,
  **~37 KB per iteration**, no plateau, runs the full 24 iterations.
- **With the fix**: 22.50 22.52 22.53 22.55 then 22.56 for eleven more - flat from iteration 5,
  TestRunner stops at 15 having converged. Delta `managed = 0.2 KB`.

Note for whoever reads a nightly leak report: TestRunner's own estimator reported
`managed = -94.8 KB` for the LEAKING run, because a GC on the last iteration dropped the sample
to 22.43. The raw per-iteration trace is unambiguous where the summary number is not.

## Tasks

- [x] One process-wide `ISampleDataApi` (`Wiff2Sdk`, `Lazy`, `ExecutionAndPublication`)
- [x] A per-path lock across every SDK call and every read of an SDK object returned by one
- [x] Per-path open counts so `Dispose` closes only for the last reader
- [x] Claim the path before the first SDK call, release on constructor throw
- [x] `Dispose` takes the lock before dropping the count
- [x] Drop the dead `if (_api is IDisposable)` block - the SDK api never is
- [x] New committed test `Reader_Sciex_wiff2_ConcurrentReadersOnDifferentPathsAgree` pinning
      cross-path concurrency, using the two in-repo fixtures
- [x] Full `Sciex.Tests` suite green (11/11); concurrency tests 8/8
- [x] Negative control: confirm the tests still catch a bare shared api (0/8)
- [x] Multi-sample `.wiff2` measured locally against a real 11-sample file, with a negative
      control (0/5)
- [x] Remove `AbstractUnitTest.IsAbWiff2Safe` / `ExtAbWiff2Safe` and the four mzML fallbacks
      from #4659 - an exact inverse of that commit's hunks, plus the `using pwiz.CommonMsData`
      it had added only for `DataSourceUtil`
- [x] Four affected Skyline tests pass reading real `.wiff2` (`TestInstrumentInfo`,
      `TestInstrumentSerialNumbers`, `FileTypeTest`, `Wiff2ResultsTest`)
- [x] Confirm the leak is gone in pass 1
- [x] Measure the lock's cost to parallel multi-file import, and narrow the lock accordingly
- [ ] `/code-review max` in `C:\dev\pwiz-im7`, fold the findings into the opening commits
- [ ] Commit and open the PR (module prefix `pwiz:`, label `pwiz`, `Fixes #4674`)
- [ ] Consider filing the cpp-side issue described under Design

## Regression Test

- **Test name**: `Reader_Sciex_wiff2_ConcurrentReadersSurviveChurnOnSamePath` and
  `Reader_Sciex_wiff2_SecondReaderSurvivesFirstReaderDispose` (from PR #4670), plus
  `Reader_Sciex_wiff2_ConcurrentReadersOnDifferentPathsAgree` (added here). The leak itself is
  guarded by removing `IsAbWiff2Safe`, so the nightly leak pass reads `.wiff2` again.
- **Test project**: `pwiz-sharp/pwiz/test/Sciex.Tests` (arbitration); Skyline `TestData` leak
  pass (leak)
- **Fails without the fix**: yes - 0 of 8 runs on the in-repo fixture, 0 of 5 on a multi-sample
  file, and the leak pass climbs ~37 KB per iteration. All verified 2026-09-16 by toggling the
  lock and the count off in place, and by stashing the reader change.
- **Passes on fix**: yes - 8 of 8, 5 of 5, flat leak pass, full 11-test `Sciex.Tests` suite, and
  the four Skyline tests

## Progress Log

### 2026-09-16 - Session Start

Read #4674 and #4670, confirmed #4670 is green and mergeable into the .NET port branch, and
branched from its head so the churn tests are available while the fix is developed.

### 2026-09-16 - Reader fix landed and measured

First cut implemented the issue's per-path refcount as written (8/8 green). Matt then asked for
a static api with mutexed access instead, which prompted reading the cpp reader properly - and
finding that cpp does neither, and carries the same race in Skyline's multi-sample shape.

### 2026-09-16 - Test harness cleaned up, leak verified, lock narrowed to per-path

Removed the #4659 mzML fallbacks, confirmed the four affected tests pass on real `.wiff2`, and
proved the leak gone by stashing the reader change and re-running pass 1. Measured the
multi-sample case against a real 11-sample file with a negative control. Measured the
process-wide lock at 1.05x on a concurrent four-file read against 3.45x per-path, so narrowed
the lock to per-path and added a committed cross-path test to pin the assumption that buys.

Nothing committed on the pwiz branch yet; `/code-review max` is the next step.
