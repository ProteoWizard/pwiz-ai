# SEA-AD Pilot-MTG (82-file Astral DIA)

The large-scale Osprey test set. Not a published Perftests zip and **not downloaded
automatically** - it is ~340 GB of source data, so every script here takes the location
as a parameter or an environment variable and hard-fails with a useful message when it
cannot find it. Nothing in this folder hardcodes a path.

This is the pattern for a new dataset: one subfolder under `ai/scripts/Osprey/`, a README
that says where the data actually lives, and scripts that resolve it rather than assume it.

## Where the data is

**Fastest: the pre-converted lab share.** mzML AND `.spectra.bin` caches, so a first run
skips both msconvert and the spectra-cache build (which otherwise dominate a cold run):

```
M:\home\brendanx\data\MacCoss\SEA-AD\Astral-DIA\mzml      (\\gs-ddn2\maccoss-vol1)
```

**Source .raw files** (only if you need to re-convert):

```
https://panoramaweb.org/_webdav/MacCoss/Collaborations/SEA-AD_2.0/Pilot-MTG-Tissue-May2026/DIA_Data/%40files/RawFiles/
```

**Entrapment libraries** (target+decoy+entrapment, the r=1.0 set):

```
https://panoramaweb.org/_webdav/MacCoss/maccoss/Shared_w_lab/%40files/RawFiles/osprey-testfiles/astral/AstralTest-TargetDecoyLibraries
```

## Telling the scripts where it is

In precedence order - first one that resolves wins:

1. `-DataDir` / `-LibraryDir` parameters
2. `$env:OSPREY_SEAAD_DIR` / `$env:OSPREY_SEAAD_LIB` (recommended: set once per machine)
3. The lab share path above, if it is reachable

```powershell
# per machine, once
setx OSPREY_SEAAD_DIR "M:\home\brendanx\data\MacCoss\SEA-AD\Astral-DIA\mzml"
setx OSPREY_SEAAD_LIB "D:\test\Pilot-MTG-Tissue-May2026\lib\regression"
```

Copying the mzML + `.spectra.bin` pair to a local SSD is worth it for repeated runs; the
share is fine for a one-off.

## Facts worth knowing before you start a run

Measured, not guessed - these cost real time to learn:

* **Full 82-file run from scratch: ~7.5 h** at `--threads 30` **with** `.spectra.bin`
  present. Without the caches, add the parse time (~4.5 min/file uncached from HDD).
* **~150 GB of parquets**, peak ~49 GB private working set. Check free space first.
* **Run at full threads.** The old `--threads 8` cap was a workaround for a memory problem
  fixed 2026-07-25; it is obsolete and just makes runs slower.
* **Decoys are marked by the `decoy_` ProteinID PREFIX, not the `Decoy` column**, which is
  0 on every row of these Carafe entrapment libraries. Filtering on the column is a silent
  no-op. Never "fix" the column.
* Entrapment is **r = 1.0** (~1:1:2 target:entrapment:decoy); entrapment peptides carry a
  `_p_target` marker.
* `--model-diagnostics` forces the RESIDENT first-pass pool at FirstJoin. At 82 files that
  has OOM'd a 64 GB box - use the projection path (omit it) for a full-scale run, or split
  with `--task`.
* Use `--timestamp --memstamp` and tee to a single `run.log`; the memstamp trace is what
  `ai/scripts/perfviz.html` renders.
* Launch long runs detached (`Start-Process -WindowStyle Hidden`) so a harness reap does
  not kill them.

## Scripts here

* `Run-SeaAd.ps1` - resolve the data, then run Osprey over N files with the standard
  flags. `-WhatIf` prints the resolved paths and the command without running.

## Related

* `ai/docs/osprey-development-guide.md` - FDRBench entrapment validation, the oracle that
  outranks parity for anything that moves the discovery set
* `pwiz_tools/Osprey/regression.ps1` - the small published datasets and the CI gate; this
  set is the scale complement to that, not a replacement
