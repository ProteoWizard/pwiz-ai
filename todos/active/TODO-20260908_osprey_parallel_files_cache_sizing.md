# TODO: Osprey --parallel-files auto mode ignores memory on a cache-only cohort

## Branch Information
- **Branch**: `Skyline/work/20260908_osprey_parallel_files_cache_sizing`
- **Base**: `master`
- **Created**: 2026-09-08
- **Status**: Code complete, gate green; PR not opened. **The code cannot be found (checked
  2026-09-12):** the branch is not on origin, not in any `C:\proj\pwiz*` or `C:\Dev\*` checkout
  or worktree, not stashed, not in any reflog, and master has no `AssertCacheOnlySizing`. Either
  it lives on another machine or the working tree was reset before a commit. If it cannot be
  located, redo it from the Fix section below - it is small
- **Module**: `osprey`
- **PR**: none yet

## Problem

`--parallel-files` with no value (AUTO) sizes each input to decide how many files
fit in RAM. `FileParallelismResolver.EstimatePerFileBytes` did that with
`SafeFileLength`, which returns 0 when the path is neither a file nor a vendor
bundle directory.

A staged cohort deletes its sources once cached (pwiz #4616) and searches from
`.spectra.bin` alone. Every input path then resolves to a file that is not there,
every size comes back 0, `EstimatePerFileBytes` returns 0, and `ResolveAuto` takes
its no-signal branch -- which **drops the RAM budget entirely and returns
`min(nFiles, cores)`**.

On MACS2 (72 logical processors, 82-file SEA-AD cohort) that is 72 concurrent
files at roughly 5-15 GB each. The guard disappears on exactly the large staged
cohorts it exists to protect.

Explicit `--parallel-files N` was never affected -- the `Explicit` branch returns
before the estimator is called. That is why this went unnoticed: every large run
we have done passes an explicit N.

## Fix

* `EstimatePerFileBytes` takes an optional `Func<string, string> cachePathResolver`.
* `SafeFileLength` consults it only after both the file and the vendor-bundle
  directory checks miss, so no existing path changes behavior.
* `PerFileScoringTask.ResolveFileParallelism` passes `SpectraCache.GetCachePath`
  (layering: `FileParallelismResolver` is in Osprey.Core, `SpectraCache` in
  Osprey.IO, so the resolver has to be injected from the Tasks call site).

Sizing from the cache errs safe: `.spectra.bin` is ~1.07x its mzML, and the 3.0x
`FOOTPRINT_MULTIPLIER` was calibrated against a run that also paid the source
parse, which a cache-only run never does. Measured on MACS2: ~5 GB incremental
per concurrent file against a 4.2 GB cache, i.e. ~1.2x, so 3.0x stays
conservative.

## Deliberately NOT changed

`ResolveAuto`'s no-signal branch still returns the CPU cap. The existing tests
asserted that on purpose ("still bounded, unlike the old unbounded default"), and
once caches are sized the branch only fires when neither source nor cache exists
-- which fails at read time anyway. Worth a separate decision, not a drive-by.

## Verification

* `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`: 602 passed,
  1 skipped, 0 failed, zero-warning inspection clean.
* `FileParallelismResolverTests` gains `AssertCacheOnlySizing`: a deleted source
  with a present `.spectra.bin` sizes to cache x 3 with a resolver and 0 without,
  and a resolver that resolves to nothing still reports the unknown 0.

## Still to do

* Open the PR (`osprey:` prefix + `osprey` label) after `/code-review max`.
* Consider whether the runner should be able to REQUEST auto at all --
  `Run-SeaAd.ps1 -ParallelFiles` is `[int]` where 0 means "omit the flag", so
  there is no way to pass bare `--parallel-files` through `OspreyDatasetRun.psm1`.
