# TDP-43 Plasma EV-Quant (164-file Astral DIA)

The scale complement to SEA-AD: **exactly 2x** in both dimensions (82 -> 164 runs,
484 -> 784 GB). Human plasma extracellular vesicles, UW-Latimer. Not downloaded
automatically - like SEA-AD, every script here resolves its locations and hard-fails with a
useful message rather than searching the wrong directory for hours.

The runner is a thin wrapper over `../Common/OspreyDatasetRun.psm1`, shared with
`../SEA-AD/Run-SeaAd.ps1`. Read `../SEA-AD/README.md` too - the library variants, the FDP
readers in `../SEA-AD/tools/`, and most of the measured facts are common to both datasets
and are documented there rather than duplicated here.

## Quick start

```powershell
setx OSPREY_TDP43_DIR "D:\test\osprey-runs\tdp43-plasma-ev\raw"
setx OSPREY_TDP43_LIB "D:\test\osprey-runs\sea-ad\lib"
# new shell, then prove the wiring before committing to hours
.\Run-Tdp43.ps1 -NumFiles 10 -WhatIf
.\Run-Tdp43.ps1 -PickLda -Pass2Mode protein-compact -NumFiles 10   # ~1 h, real run
.\Run-Tdp43.ps1 -PickLda -Pass2Mode protein-compact                # the full 163
```

`OSPREY_TDP43_LIB` points at the **SEA-AD** library root on purpose: this dataset has no
library of its own, and the SEA-AD regression library carries the entrapment + pairing
manifest that make FDP measurable. See "The library" below.

## Where the data is

* Portal: <https://panoramaweb.org/MacCoss/Collaborations/UW-Latimer/2025-TDP43-CSF-Plasma/TDP-43%20Plasma%20EV-Quant/project-begin.view>
* WebDAV raw: `https://panoramaweb.org/_webdav/MacCoss/Collaborations/UW-Latimer/2025-TDP43-CSF-Plasma/TDP-43%20Plasma%20EV-Quant/%40files/RawFiles/`

Local layout on this machine (`<dataset root>` = `D:\test\osprey-runs\tdp43-plasma-ev`):

| | |
|---|---|
| `raw\*.raw` | **164 files, 787 GB** (avg 4.8 GB) |
| `raw\*.spectra.bin` | **163 caches, 554 GB**, built 2026-07-30 in 10 h |
| `runs\<run name>\` | ALL run output and logs |

Unlike SEA-AD there is **no mzML anywhere and none is needed** - see "Vendor raw without a
vendor build" below.

## The one excluded file

`2025-0724-TDP43-PlasmaEV-PLT2-C03-5112-027-bad.raw` is an aborted acquisition the depositor
marked `-bad`; ProteoWizard reports `[RawFileImpl::ctor()] Corrupt RAW file`. **163 is the
correct working count, not a shortfall.** A WebDAV PROPFIND of the source lists 164 files
totalling 784.2 GB and that file is 826,790 bytes there - byte-for-byte what we have, the
smallest file at the source by a factor of ~3,900, with a valid Thermo header that simply
stops early. The download is faithful; the acquisition died and was uploaded as-is.

The runner excludes it by default (`-ExcludePattern '-bad\.raw$'`), which is what makes a
full run exit 0. Pass `-ExcludePattern ''` to include it and watch Osprey log it and carry on.

## Vendor raw without a vendor build

`EnsureSpectraCache` consults the `.spectra.bin` cache **before** it dispatches on file
extension, so pointing **any** build - including **net8.0, with no ProteoWizard at all** -
at these `.raw` files reuses the caches. `TestVendorCacheUsableWithoutVendorReader` pins that
ordering. Prefer net8.0: nothing in Stages 1-7 needs ProteoWizard once the caches exist, and
net8.0 has the better GC for a run this size.

**A missing or stale cache fails LOUDLY**, with an error naming
`/p:OspreyVendorReader=true`. That error means **"the cache is not where Osprey looked"** -
treat it as "something moved", NOT as "use the vendor build". The most likely cause is the
`--work-dir` trap below.

**Do not touch the `.raw` files.** The cache fingerprint is size + mtime. Any tool that
rewrites or re-downloads one invalidates its cache, and rebuilding costs ~3.8 min/file **and**
needs a vendor-enabled build.

### The `--work-dir` trap

Runs use `--output-dir`, never `--work-dir`. `--work-dir` sets **both** `OutputDir` and
`CacheDir` (`OspreyCommandArgs.cs`, `_config.CacheDir = _cacheDir ?? _workDir`), and an
explicit `CacheDir` wins outright in `ArtifactPaths.ResolveCacheDir` - the "beside the data
file if writable" preference below it is only reached when `CacheDir` is empty. So
`--work-dir` makes all 163 prebuilt caches invisible and the run dies on file 1 with the
vendor-reader error above. The runner gets this right; the note is here because the error
message points somewhere else entirely.

## The library

This dataset ships no library. Use the SEA-AD regression library - it comes from the
regression dataset but is good enough for these tests, and it carries the entrapment +
pairing manifest that make FDP measurable:

```
D:\test\osprey-runs\sea-ad\lib\target+decoy+entrapment\
    carafe_spectral_library.tsv      13.1 GB   -l
    osprey_library_db_pairing.tsv     392 MB   --decoy-pairing-manifest
    osprey_library_db_peptides.fasta  349 MB   (FDRBench only)
```

The runner resolves the variant from `-DecoyMode` / `-Ratio` using the convention
`New-SeaAdLibrary.ps1` owns, so the ratio series works here exactly as it does for SEA-AD.

**These libraries supply their own decoys**, so `libdecoy` adds `--decoys-in-library`.
Osprey identifies them by the `decoy_` protein-accession PREFIX, not the `Decoy` column,
which is 0 throughout these Carafe libraries. Filtering on the column is a silent no-op;
never "fix" it.

TDP-43 is Astral, so the runner uses `--resolution hram` (the Stellar regression sets are
`unit`).

## Facts worth knowing before you start a run

* **Nothing had run Osprey at 164 files before 2026-07-30**, so treat the first full run as
  an experiment, not a formality. #4488 (merged) bounded the per-file Stage 6 growth that
  used to make this scale with file count; whether that holds at 2x SEA-AD is the question
  this dataset exists to answer.
* **Measured, 6 files, default settings, straight through**: PerFileScoring 1,698 s
  (~4.7 min/file) with cache hits, peak working set 29.1 GB, and Stage 5 entered on the
  counts-only projection path with no resident pool. The library alone is 4.4 GB managed.
* **Library load is ~90 s** and writes a 2.2 GB `.libcache`. It lands in the **cache**
  directory (`ResolveCacheDir`), so with the default layout it is written beside the raws
  and reused by every later run.
* Disk budget for the full pipeline on this set is **~2,358 GB** (see
  `ai/docs/osprey-large-datasets.md`) against 4,427 GB free. The parquets are the growth
  term - watch it rather than assume.
* **Read the computed FLOOR, never two point samples**, when judging memory. Two
  `--memstamp` samples from the caching run (151 MB at file 1 vs 8.9 GB at file 113) looked
  like severe O(files) accumulation; the floor showed the private band actually FALLING.
  That trap already cost one wrong conclusion here. Run
  `python ai/scripts/perfviz.py <log> --files 163`, and see `ai/docs/memory-band-guide.md`.
* `OSPREY_LOG_MEMORY=1` gives post-GC probes, which are what answer "will it fit";
  `--memstamp` includes uncollected garbage and shows shape, not magnitude.

### The caches predate #4501

The 163 caches were built on 2026-07-30 **before** #4501 (retention-time precision) merged,
so they carry the pre-fix `GetStartTime` retention times. Nothing flags them as stale - the
fingerprint is the `.raw`'s size and mtime, which have not changed - so a fresh parse today
would produce slightly different RTs than the cache holds. The earlier census measured
9,269 of 161,099 MS2 records differing, worst |dRT| **3.55e-15 min**.

Brendan accepted this knowingly at merge time. It is almost certainly below anything these
tests resolve, but if you ever see an unexplained RT-shaped diff, this is the reason - not a
new defect. Rebuilding costs ~10 h and is fully scripted.

## FDRBench at this scale

`-FdrBenchPass` defaults to **`none`** here, unlike SEA-AD. The reasoning:

* `--fdrbench-pass 1` forces the RESIDENT first-pass pool, which grows O(files) - the exact
  growth #4488 was written to bound. Confirmed in source: `NeedsResidentPool` gates on
  `config.FdrBenchPass == 1` (`PerFileScoringTask.cs`). Do not reach for it at this scale.
* `2` and `both` are memory-safe - the `both` bitmask (3) never matches that `== 1` test -
  but they emit only the **pass-2** TSV, and pass-2 FDP is inflated by recalibration.

So the baseline uses `--model-diagnostics` alone, which gives the pass-1 paired-FDP estimate
and the diagnostics HTML with no resident-pool exposure. Run the external FDRBench oracle
later on a SMALL subset, where pass 1's resident pool is affordable and the opt-in env var is
a deliberate act rather than a workaround. Read the results with `../SEA-AD/tools/`.

## The recommended configuration

`-PickLda -Pass2Mode protein-compact` is the pairing Mike MacCoss recommends, recorded in
`ai/todos/completed/TODO-20260715_osprey_pass2_transfer_compete.md`. Neither is the product
default, deliberately - flipping them on is a coordinated C#+Rust golden re-baseline.

Both were validated on **Stellar**; that TODO lists **"Astral protein-compact validation"**
as deferred remaining work that never shipped. SEA-AD and TDP-43 are both Astral, so running
this pairing here **is** that deferred validation - at 2x the largest scale yet run. Treat
the result accordingly.

`-PickLda` **moves the discovery set**: it replaces the product-form peak pick
(`coelution * rt_penalty * ln_intensity`) with a frozen linear model over four z-normalized
terms, in which `median_polish` - a term the default ignores entirely - carries the largest
Astral weight and `ln_intensity` is effectively switched off. See
`pwiz_tools/Osprey/docs/peak-model-training.md`.

**Osprey logs nothing that records which pick model a run used.** The runner therefore
prints it in the banner, writes it to the `run.log` START line, and puts `-picklda` in the
run directory name - and clears `OSPREY_PICK_LDA` when the switch is off, so an exported
shell variable cannot silently apply it to an arm that did not ask for it. Without that a
finished run is unattributable after the fact.

## Related

* `../SEA-AD/README.md` - library variants, the FDP readers, cache portability, and the
  facts common to both datasets
* `../Common/OspreyDatasetRun.psm1` - the shared runner engine
* `ai/docs/osprey-large-datasets.md` - this dataset in the context of the others, and the
  disk budget table
* `ai/docs/memory-band-guide.md` - required before interpreting any memory number here
