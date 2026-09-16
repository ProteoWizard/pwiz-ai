# .wiff2 reader leaks ~34 KB per open; a refcounted shared ISampleDataApi fixes it, pending the multi-sample case

## Branch Information
- **Branch**: `Skyline/work/20260916_wiff2_shared_sample_data_api`
- **Base**: `Skyline/work/20260915_wiff2_concurrency_tests` (PR #4670), which is based on
  `Skyline/work/20260612_net8_port`. Stacked on purpose: #4670 carries the churn tests that are
  the acceptance test for this fix. Retarget the PR to `Skyline/work/20260612_net8_port` once
  #4670 merges (GitHub retargets automatically).
- **Checkout**: `C:\dev\pwiz-im7`
- **Created**: 2026-09-16
- **Status**: In Progress
- **GitHub Issue**: [#4674](https://github.com/ProteoWizard/pwiz/issues/4674)
- **Module**: `pwiz` (pwiz-sharp Sciex reader; the `IsAbWiff2Safe` removal touches
  `pwiz_tools/Skyline` test code, but the intent of the work is the vendor reader)
- **PR**: (pending)
- **Requester/Reporter**: none. Filed by Brendan, a developer of this project, handing the
  measured fix to the reader's owner - not an outside report, so no credit line (see
  version-control-guide.md, "Crediting Reporters and Requesters").

## Objective

Stop `.wiff2` opens leaking ~34 KB of unreleasable managed memory each, by sharing one
process-wide `ISampleDataApi` as the C++ `WiffFile2.ipp` does, with the per-path ownership
arbitration the C# reader needs because it keeps one reader per SAMPLE where cpp keeps one per
FILE.

Root of the leak: every `DataApiFactory.CreateSampleDataApi()` leaves a
`Clearcore2.RFLight.SampleDataProvider.SampleDataProviderServer` rooted by its own periodic
`Timer`. `ISampleDataApi` and `DataApiFactory` are not `IDisposable` and `CloseFile` closes a
file, not the server, so nothing can release it. Measured at 34.4 KB/run, linear over 9,951
iterations of `TestInstrumentInfo` with the mzML fallback disabled.

Sharing naively is unsafe: the SDK keeps one pooled storage location (a SQLite connection) per
path, and `CloseFile` from one reader purges it while another reader on the same path may have a
request in flight. `Wiff2File`'s catch blocks turn that into empty spectra / zero cycles rather
than an exception. The fix is per-path reference counting, so only the last reader on a path
calls `CloseFile`.

## Tasks

- [ ] Share one `ISampleDataApi` process-wide in `Wiff2File.cs` (`Lazy<ISampleDataApi>`,
      `ExecutionAndPublication`), replacing the per-reader `_api` field
- [ ] Add the per-path open count so `Dispose` calls `CloseFile` only for the last reader on
      that path
- [ ] Close the constructor window: increment the count before the first SDK call and decrement
      on throw, rather than after the sample/experiment reads succeed (the issue's own
      "What is NOT measured" item)
- [ ] Drop the dead `if (_api is IDisposable)` block in `Dispose` - the SDK api never is
- [ ] Verify against PR #4670's tests: `Reader_Sciex_wiff2_ConcurrentReadersSurviveChurnOnSamePath`
      and `Reader_Sciex_wiff2_SecondReaderSurvivesFirstReaderDispose`, repeated runs
- [ ] Multi-sample `.wiff2`: both `Reader_ABI_Test.data` fixtures are single-sample. Find or
      build a small multi-sample fixture and extend the churn test to readers on different
      sample indices, or record explicitly that it stayed unmeasured
- [ ] Remove `AbstractUnitTest.IsAbWiff2Safe` / `ExtAbWiff2Safe` and the four mzML fallbacks
      from #4659 (`PwizFileInfoTest`, `Results/SmallWiffTest`) so the leak pass reads real
      `.wiff2` again - that is what keeps the leak from regressing
- [ ] Confirm the leak is gone: `TestInstrumentInfo` in pass 1 with the fallback removed

## Regression Test

- **Test name**: `Reader_Sciex_wiff2_ConcurrentReadersSurviveChurnOnSamePath` (from PR #4670,
  the acceptance test for the arbitration); the leak itself is guarded by removing
  `IsAbWiff2Safe` so the nightly leak pass reads `.wiff2` again
- **Test project**: `pwiz-sharp/pwiz/test/Sciex.Tests` (arbitration); Skyline `TestData` leak
  pass (leak)
- **Fails on master**: (pending) - the churn test fails 8/8 against a shared api with no
  arbitration, which is the state this fix must not ship in
- **Passes on fix**: (pending)

## Progress Log

### 2026-09-16 - Session Start

Read #4674 and #4670, confirmed #4670 is green and mergeable into the .NET port branch, and
branched from its head so the churn tests are available while the fix is developed. Starting on
the `Wiff2File.cs` change.
