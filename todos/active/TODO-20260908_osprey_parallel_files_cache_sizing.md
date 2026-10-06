# TODO: Osprey --parallel-files auto mode ignores memory on a cache-only cohort

## Branch Information
- **Branch**: `Skyline/work/20260908_osprey_parallel_files_cache_sizing`
- **Base**: `Skyline/work/20260612_net8_port` at `2937deaae8` (re-based 2026-10-05; was `master`)
- **Created**: 2026-09-08
- **Status**: Re-gating on the port branch before the PR (2026-10-05)
- **Owner**: the MACS2 per-stage parallel-files session (took it over 2026-10-05), worktree `pwiz-net10b`
- **Machine**: MACS2 - the original commit `cef106ecd8` was never pushed; kept as local branch
  `backup/20260908_cache_sizing-cef106ecd8`
- **Module**: `osprey`
- **PR**: [#4778](https://github.com/ProteoWizard/pwiz/pull/4778) (draft until `/code-review max` and the Stellar gate are done)

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
  (Belongs with the runner changes in `TODO-20261005_osprey_per_stage_parallel_files.md`.)

## 2026-10-05: re-based onto the port branch

Osprey development moved to the .NET 10 port branch after this was written, and the fix was never pushed.
Cherry-picked `cef106ecd8` onto the port tip `2937deaae8`: applied cleanly (`FileParallelism.cs`,
`PerFileScoringTask.cs`, `FileParallelismResolverTests.cs`, 70+/10-), now `47fad86a03`. The commit
message was corrected to the repo's attribution format (the original carried the harness's
model-named trailer and session URL). Checked on the new base: `SpectraCache.GetCachePath` resolves
through `ArtifactPaths.ResolveCacheDir`, which honors `--cache-dir` first, so a cohort whose caches
live in a separate folder (as TDP-43 on MACS2 now does) is sized correctly too.

Ship this BEFORE the per-stage work: that branch changes `FileParallelismResolver` as well.
