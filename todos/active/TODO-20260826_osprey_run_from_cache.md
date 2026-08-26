# Osprey: run from .spectra.bin alone, so a staged cohort can drop its raw files

## Branch Information
- **Branch**: `Skyline/work/20260826_osprey_run_from_cache`
- **Base**: `master`
- **Created**: 2026-08-26
- **Status**: Active - change written, local Stellar gate in flight
- **Module**: `osprey`
- **Machine**: BRENDANX-UW8, 63.7 GB RAM

## Objective

Let a search run when the source `.raw`/`.mzML` is gone but its `.spectra.bin` is present, so
the staging workflow becomes:

1. download the sources
2. `--task SpectraCache`
3. **delete the sources**
4. run the search

Stage 1 is the only stage that reads a source at all; everything after it reads the cache. So
after step 2 the sources are dead weight that roughly DOUBLES the disk a cohort needs. On the
446-file CHS set that is **~1.8 TB of .raw against ~1.2 TB of caches**, and the originals stay
recoverable from PanoramaWeb. Disk, not time, is now what limits how large a cohort this
machine can hold: after staging all 446 files, D: sits at ~1.08 TB free while a full 446-file
search wants ~560 GB of run output.

## The change

**One check was the entire blocker.** `Osprey/Program.cs` validated that every input exists on
disk and returned 1 before any reader or cache was consulted:

```
[ERROR] Input file not found: ...\EXP25033_2025us0064aX3_A.raw
```

Everything below that line already worked. `SpectraCache.TryComputeSourceFingerprint` documents
the absent-source case explicitly - it returns a `(0, 0)` fingerprint, which the load path reads
as "nothing to compare, trust the cache", and calls it "the documented resume case". Nothing
else in the pipeline stats the input (verified by grep over `config.InputFiles`).

So the fix is to accept a missing input when `SpectraCache.GetCachePath(inputFile)` exists, and
say so on the log:

```
N of M input(s) are absent but have a spectra cache; reading those from the cache.
```

The line is announced rather than silent on purpose: a run whose sources are gone cannot rebuild
a cache that later turns out to be wrong, so which files it came from is provenance the operator
has to be able to read back off the log.

**Proven before the harness was written.** Moved one `.raw` aside (cache kept) and ran the full
pipeline: 189,715 MS/MS spectra loaded from cache, all four tasks, 19,026 spectra written to the
blib. Restored the file afterwards.

## Regression coverage - folded in, not bolted on

The first attempt added a `mode 8` leg plus a `-SkipCacheOnly` switch. **Rejected** (Brendan):
an opt-in flag is a test only we would ever run, and it re-ran a whole pipeline to check one
thing. Replaced with a one-line change to an existing leg.

**The mode-2 resume leg now names inputs that do not exist** - same file names, but under the
work dir, where an mzML is never placed. Only the `.spectra.bin` the straight-through leg left
there is real (caches honor `--work-dir`; the sources stay in the read-only Perftests tree,
untouched - the test never moves or deletes shared data).

Mode 2 is the right carrier because it already asserts everything the property needs:
`PerFileScoring` and `PerFileRescoring` must hit cache, `FirstPassFDR` and `SecondPassFDR` must
recompute, and the blib is already compared to `$coldBlib`. The cache-only property therefore
costs nothing to assert there.

Mode 4 would have been weaker: its own comment notes a fully cached run "exits without reading
spectra or even loading the library", so it would only exercise the front-door check.

A `throw` guards the premise - if an mzML ever lands in the work dir the leg would quietly
revert to testing the ordinary path and this coverage would lapse with nothing going red.

## Gates

- [ ] `regression.ps1 -Dataset Stellar` (in flight)
- [ ] `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`
- [ ] `/code-review max`
- [ ] `regression.ps1 -Dataset All` / TeamCity Perf/Regression before merge

## Follow-ups this enables

* **`ai/docs/osprey-large-datasets.md`** should carry the staging recipe, since it is what any
  session on any machine will want: download -> SpectraCache -> delete sources -> search, with
  the disk arithmetic (0.615 GB of run output per GB of raw; caches ~2/3 the size of the raw).
* **CHS cleanup** is now a different conversation. Deleting the 446 `.raw` frees ~1.8 TB, far
  more than pruning run directories: those are dominated by the three plate legs, which must
  stay because leg 4 hard-links their per-file artifacts. Probe runs free only ~27 GB despite
  `du` reporting ~262 GB.

## Related

- `ai/todos/completed/TODO-20260825_osprey_stage7_memory.md` - the run this came out of
- `ai/scripts/Osprey/CHS/README.md` - the staging doctrine and measured rates
- [#4486](https://github.com/ProteoWizard/pwiz/issues/4486) - Stage 7 residency, still open

## /code-review max, 2026-08-26 - the change is NOT sound as written

Gates were green (Stellar regression incl. mode 2, 592/592 tests, inspection) and the review
still found two structural defects. Green gates measured the wrong things here.

### BLOCKER 1 - the gate tests cache PRESENCE, not usability (Program.cs:229)

`File.Exists(SpectraCache.GetCachePath(...))` only proves a file with that name exists.
`SpectraCache.TryReadHeader` rejects a cache on bad magic, `FINGERPRINT_UNMEASURABLE`, or
`version != VERSION` - and **VERSION was bumped three times in ten weeks** (v2 2026-05-09,
v3 2026-06-09, v4 2026-07-16), each comment promising old caches "invalidate ... and
re-populate on first use".

Re-population is precisely what a deleted source makes impossible. So: stage 446 files, delete
1.8 TB of `.raw` on the strength of this feature, upgrade Osprey, and validation passes all 446,
logs "446 of 446 input(s) are absent but have a spectra cache", then `ScoringTaskShared.cs:156`
logs "Spectra cache stale or invalid; re-parsing the input" and calls `LoadAllSpectra` on a file
that no longer exists. **The feature promises the sources are deletable and cannot keep that
promise across a version bump.**

Fix: validate with `TryReadHeader` / `SpectraWindowIndex.BuildFromCache`, not a filename probe.
A cache-format bump then becomes a loud refusal at startup instead of a failure hours in.

### BLOCKER 2 - the regression leg never opens a cache (regression.ps1:1712)

Mode 2 asserts `-ExpectSkipped @('PerFileScoring','PerFileRescoring')`, and those are **the only
two pipeline call sites that open a `.spectra.bin`**. A skipped task never runs. So the marker
proves only that `Program.cs`'s own `LogInfo` fired - not that anything read a cache.

Falsification the reviewer supplies: tighten the `(0,0)`-fingerprint skip at `SpectraCache.cs:343`
so an absent source becomes a hard cache rejection. Every source-deleted cohort breaks. Mode 2
stays GREEN. Real coverage needs a leg where **PerFileScoring actually RUNS with the source
absent**, which mode 2 by construction cannot be.

### My comment states a false mechanism (regression.ps1:1671)

"Osprey resolves the cache by STEM, so the directory in these paths is irrelevant" - **false**.
`ResolveCacheDir` returns `InputDir(inputPath)` when no `--work-dir`/`--cache-dir`/`--output-dir`
is set. The leg passes only because `Invoke-OspreyRun` always passes `--work-dir`. Worse, the
recipe this TODO blesses - download, SpectraCache, delete, caches beside the data, no
redirection - is the in-input-directory path, and **no leg exercises it**.

### Also real, unfixed

* `OspreyCommandArgs.cs:375` - positional (non-`-i`) inputs still gate on existence and are
  silently DROPPED with "Unknown argument". A partially-staged cohort then runs on the surviving
  subset with a quietly smaller experiment-wide FDR population. `regression.ps1` cannot catch it:
  `Invoke-OspreyRun` always passes `-i`.
* `SpectraCacheTask.cs:149` - the relaxation is unconditional, so `--task SpectraCache` itself is
  exempt. With the source gone it logs "Cached 82 of 82 file(s)" and exits 0 having staged
  nothing. Automation reads that as success and deletes the next batch.
* `Program.cs:214` - `Directory.Exists` short-circuits before the new branch, so vendor DIRECTORY
  formats (.d, Waters .raw) never reach it, while `TryComputeSourceFingerprint` returns false for
  an emptied bundle and rejects its cache. Stripping files inside a bundle - the natural way to
  free that disk - is silently unsupported.
* Cache identity becomes STEM-ONLY with the fingerprint check disabled, so a typo'd `-i` dir is
  served another file's spectra instead of erroring.
* `FileParallelism.cs:224` - `SafeFileLength` returns 0 for absent inputs, so auto
  `--parallel-files` silently discards its RAM budget. Same command, different parallelism,
  depending only on whether the `.raw` was deleted.
* regression.ps1: `Test-Path $p` binds to `-Path` and GLOBS - misses a real file named
  `samp[1].mzML`, the exact event the guard exists to catch. Every sibling uses `-LiteralPath`.
  The marker also matches any count ("1 of 3" passes as readily as "3 of 3"), and both new
  failure paths `throw`, aborting all remaining datasets and then deleting the log the message
  says to read.
* **Docs now state the inverse of the new invariant**: `docs/14-intermediate-files.md:158,502`
  says `.spectra.bin` is "safe to delete - recreated on next run", and
  `15-hpc-scoring-split.md:146,91` says "no join depends on it" and claims an mzML fallback that
  `PerFileRescoreTask.LoadSpectraForRescore` explicitly does not have. An operator following
  those prunes caches after deleting sources. Unrecoverable, and fails hours in.

### Where this leaves it

The idea is sound and the measurement stands - Stage 1 is the only stage that reads a source, and
a full pipeline did run from cache alone. But the implementation promises more than it delivers,
and the test does not cover the promise. **Do not open a PR on this branch as-is.** Next session:
fix blockers 1 and 2 first, then re-triage the rest.
