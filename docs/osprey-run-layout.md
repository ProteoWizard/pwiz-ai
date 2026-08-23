# Where Osprey test data and runs live

One layout, on every machine. Three machines now test the same datasets, and a comparison
across them is only as good as the ability to say which run produced a number.

## The layout

```
D:\test\osprey-runs\
    _bin\                     pinned Osprey.exe snapshots, one dir per build
    <dataset>\
        raw\                  source files (.raw / .mzML) AND their .spectra.bin caches
        lib\                  spectral libraries used with this dataset
        runs\                 every run output directory, one per run
```

Rules:

* **Everything lives under `D:\test\osprey-runs\`.** No dataset gets its own top-level
  directory beside it.
* **A leading underscore means "not a dataset"** - `_bin` today. Anything else at that level
  is a dataset directory.
* **Dataset names are kebab-case and name the cohort**, not the acquisition or the study
  code: `sea-ad`, `tdp43-plasma-ev`, `aha-plasma-ev`, `chs-seer`, `stellar`,
  `astral-entrap-3file`.
* **The `.spectra.bin` cache sits beside its source file**, in `raw\`. It is not a separate
  tree: `ArtifactPaths.ResolveCacheDir` prefers "beside the data file if writable", and
  splitting them is how the `--work-dir` trap makes 163 prebuilt caches invisible.
* **Run output goes in `<dataset>\runs\`, never anywhere else.** The runners enforce this;
  see below.

## Naming a run directory

A run name has to carry the four things a number cannot be quoted without - **library,
config, run context, and N** - because the alternative is restating them by hand in every
comparison, and getting one wrong eventually.

The shared runner composes it:

```
<dataset>-<N>files-<decoymode>-r<ratio>-<pass2mode>[-pick][-agg][-qualify][-tag]
```

for example

```
tdp43-163files-libdecoy-r1.0-protein-compact-pickrun3-ourlib
seaad-82files-libdecoy-r1.0-protein-compact-p2-pickrun3-ours-n82
```

`-Tag` is where the experiment's own name goes. Everything before it is generated from the
arm, so two runs that differ in configuration cannot collide, and a finished directory is
self-describing.

**What the name still cannot carry**, and why the runner writes it into the `run.log` START
and DONE lines instead: the peak-pick model, the training sampler, the memory-probe setting.
Osprey logs none of them, so a run whose banner was not captured is unattributable after the
fact. That is why the runner exports those variables in both directions and records them.

## Why this is enforced in the runners, not just written here

A convention that lives only in a document drifts, and the drift is invisible in the output.
`OspreyDatasetRun.psm1` resolves the output directory from the dataset descriptor and refuses
to write outside `<dataset>\runs\`; `Test-PerfGate.ps1` takes the same root. A hand-rolled
script is the failure mode this guards - it is also how the `--work-dir` trap and the
"unrecorded env var" class of defect keep getting re-acquired.

## Housekeeping

* **Run directories are hard-linked.** `-LinkFrom` shares Stage 1-4 artifacts between runs,
  so a single `.scores.parquet` can carry 20-30 links. **Directory size is therefore not
  reclaimable space** - deleting one run of a linked family frees almost nothing, and you
  only get the blocks back when the last link goes. Check with
  `fsutil hardlink list <file>` before estimating a cleanup.
* **Prune by what a number still rests on.** A run directory is worth keeping when a
  published table cites it (the stats HTML companions list their provenance) or when it is
  the comparator for work in flight. Sweeps superseded by a shipped default are not worth
  keeping; they would be redone against the current default anyway.
* **Snapshot the exe before a long run** to `_bin\<version>-<date>`, and run from the copy.
  Windows locks a running executable, so a build during a multi-hour run fails until it
  finishes.

## Related

* `ai/docs/osprey-large-datasets.md` - the dataset catalog, sizes, and download budgeting
* `ai/scripts/Osprey/Common/OspreyDatasetRun.psm1` - the shared runner that owns the naming
* `ai/docs/memory-band-guide.md` - reading `--memstamp` output from a run
