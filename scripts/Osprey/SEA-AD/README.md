# SEA-AD Pilot-MTG (82-file Astral DIA)

The large-scale Osprey test set. Not a published Perftests zip and **not downloaded
automatically** - it is ~340 GB of source data, so every script here takes the location
as a parameter or an environment variable and hard-fails with a useful message when it
cannot find it. Nothing in this folder hardcodes a path.

This is the pattern for a new dataset: one subfolder under `ai/scripts/Osprey/`, a README
that says where the data actually lives, and scripts that resolve it rather than assume it.

## Quick start on a new machine

```powershell
setx OSPREY_SEAAD_DIR  "M:\home\brendanx\data\MacCoss\SEA-AD\Astral-DIA\mzml"
setx OSPREY_SEAAD_LIB  "D:\test\Pilot-MTG-Tissue-May2026\lib\regression"
# new shell, then prove the wiring before committing to a multi-hour run
.\Run-SeaAd.ps1 -DecoyMode libdecoy -Ratio 1.0 -NumFiles 2 -WhatIf
.\Run-SeaAd.ps1 -DecoyMode libdecoy -Ratio 1.0 -NumFiles 2          # ~minutes, real run
.\Run-SeaAd.ps1 -DecoyMode libdecoy -Ratio 1.0                      # the real thing, ~7.5 h
```

`-WhatIf` prints the resolved exe, mzML directory, library variant, output directory and
the exact command line. Read it. Every trap in this folder is a path resolving to
something you did not intend.

## Where the data is

**Fastest: the pre-converted lab share.** mzML AND `.spectra.bin` caches, so a first run
skips both msconvert and the spectra-cache build (which otherwise dominate a cold run):

```
M:\home\brendanx\data\MacCoss\SEA-AD\Astral-DIA\mzml      (\\gs-ddn2\maccoss-vol1)
```

**Source .raw files** (only if you need to re-convert - see `Convert-SeaAdRaw.ps1`):

```
https://panoramaweb.org/_webdav/MacCoss/Collaborations/SEA-AD_2.0/Pilot-MTG-Tissue-May2026/DIA_Data/%40files/RawFiles/
```

**Entrapment libraries** (target+decoy+entrapment, the r=1.0 set - every other variant is
derived from it locally):

```
https://panoramaweb.org/_webdav/MacCoss/maccoss/Shared_w_lab/%40files/RawFiles/osprey-testfiles/astral/AstralTest-TargetDecoyLibraries
```

Copying the mzML + `.spectra.bin` pair to a local SSD is worth it for repeated runs; the
share is fine for a one-off.

## Telling the scripts where it is

In precedence order - first one that resolves wins:

1. `-DataDir` / `-LibraryDir` / `-Exe` parameters
2. `$env:OSPREY_SEAAD_DIR` / `$env:OSPREY_SEAAD_LIB` / `$env:OSPREY_EXE`
3. The lab share (mzML) and the sibling pwiz checkout's Release build (exe)

A location you NAME must exist. An explicit `-DataDir` or `$env:OSPREY_SEAAD_DIR` that
does not resolve is an error, not a quiet fall-through to the next candidate - a typo
there would otherwise spend 7.5 h searching the wrong data and still report success.

`$env:OSPREY_SEAAD_LIB` points at the directory that HOLDS the library variants, not at
one library. The runner picks the variant from `-DecoyMode` and `-Ratio`.

## The library variants

Only the r=1.0 set is downloaded. `New-SeaAdLibrary.ps1` derives the rest and owns the
naming convention `Run-SeaAd.ps1` resolves, so both sides stay in step:

| folder | arm | built by |
|---|---|---|
| `target+decoy+entrapment` | r=1.0 libdecoy | downloaded |
| `target+decoy+entrapment-r<ratio>` | fractional libdecoy | `subset-entrapment-ratio.py` |
| `target+entrapment-r<ratio>-gendecoy` | gendecoy | `strip-decoys.py` |

```powershell
.\New-SeaAdLibrary.ps1 -Ratio 0.1 -DecoyMode libdecoy   # subset from the 1:1 set
.\New-SeaAdLibrary.ps1 -Ratio 0.1 -DecoyMode gendecoy   # strip decoys from that subset
```

A gendecoy variant derives from the libdecoy variant at the **same ratio** (built first if
missing), so the two arms differ only in where the decoys come from. Selection is a seeded
shuffle (default 2024), so the same ratio built on two machines picks the same quartets and
the runs are comparable across boxes.

Budget for it: the source library is ~13 GB and each variant is a full streamed copy. A
fresh variant has no `.libcache`, so Osprey builds one on its first use.

## Running

```powershell
# one arm
.\Run-SeaAd.ps1 -DecoyMode libdecoy -Ratio 1.0 -Pass2Mode percolator

# a comparison: arms run back to back, because only one Osprey fits on a 64 GB box
.\Invoke-SeaAdChain.ps1 -DecoyModes libdecoy,gendecoy -Ratios 0.1
.\Invoke-SeaAdChain.ps1 -Pass2Modes percolator,transfer

# detached, so a harness reap cannot kill a 7.5 h run
Start-Process pwsh -ArgumentList '-NoProfile','-File',"$PWD\Invoke-SeaAdChain.ps1",
  '-DecoyModes','libdecoy,gendecoy','-Ratios','0.1' -WindowStyle Hidden
```

`Invoke-SeaAdChain.ps1` waits for any Osprey already running to exit, then walks the
cross-product of the arms you gave it. It does not stop on a failed arm - a failure is
visible in that arm's `run.log` and in the chain log.

Output lands in `<dataset root>\runs\seaad-<N>files-<arm>-r<ratio>-<pass2>[<tag>]\`,
matching the layout of the runs already there.

**Say which build you mean.** By default the runner takes `Osprey.exe` from the shared
`pwiz` worktree's `Release/net8.0` output - whatever happens to be built there right now.
On a machine where someone is actively developing, that couples two sessions in both
directions: the run measures their in-progress branch instead of master, and it holds
those DLLs so their next build fails to relink. Both halves are silent. The runner prints
the build time and branch and warns when it is not master; pass `-SourceRoot <checkout>`
(or `-Exe`) to pin a tree nobody is building in, the same reasoning behind the pinned
`pwiz-perfbase` worktree used by the perf gate.

**Repeating an arm needs `-Fresh`.** Osprey adopts per-file caches it finds in the output
directory, so re-running into an existing one silently resumes and skips stages - fine for
continuing a crashed run, fatal to a from-scratch memory or timing measurement, and
invisible either way in the output. The runner refuses a non-empty output directory unless
you say which you meant: `-Fresh` (timestamped new directory) or `-Resume` (continue this
one). `-LinkFrom <completed run>` is the deliberate version: hard-link only the Stage 1-4
caches so Stage 5 onward - the part usually under test - always regenerates.

## Reading the results

`tools/` holds the readers. They take run directories and are path-clean:

| script | answers |
|---|---|
| `compute_pass2_fdp.py <run_dir>...` | entrapment FDP at reported q, from the pass-2 `fdrbench.tsv` |
| `fdp_at_count.py <run_dir>...` | FDP against accepted target COUNT, overlaying pass 1 and pass 2 |
| `runcount_fdp.py <run_dir>` | FDP by number-of-runs-identified (needs `--model-diagnostics`) |
| `Compare-Pass2AB.py <a> <b> <out.html>` | two `--model-diagnostics` runs side by side |

Osprey names its FDRBench output by how the run was launched - `fdrbench.tsv` from
`--fdrbench-pass 2`, `fdrbench.pass2.tsv` from `--fdrbench-pass both` (the runner's
default). The readers accept either, so a run launched one way is not reported as missing
by a tool expecting the other.

**Quote Pass 1, not Pass 2.** Pass-2 recalibration inflates FDP; that is a known open
issue, not a property of your run.

**Pass-1 FDP comes from the `--model-diagnostics` HTML, not from FDRBench.** Despite what
`--fdrbench-pass both` promises, no pass-1 TSV is written on the normal (projection) path:
Osprey gates the pre-compaction pool on `FdrBenchPass == 1` exactly, so the `both` bitmask
(3) misses the test and only pass 2 is emitted, silently. Verified on three runs including
one with `--model-diagnostics`, so it is not an mdiag interaction - see
`PerFileScoringTask.NeedsResidentPool` and `FirstJoinTask.WriteFdrBenchPass1IfRequested`.
This is a product bug, reported separately; until it is fixed, keep `--model-diagnostics`
on if you want pass-1 numbers, and read them from the report's `fdpViews` (which carry an
explicit `pass` field - select on it) via `fdp_at_count.py` / `runcount_fdp.py`.
`--fdrbench-pass 1` alone does emit the pass-1 TSV, but only by forcing the resident pool.

## Facts worth knowing before you start a run

Measured, not guessed - these cost real time to learn:

* **Full 82-file run from scratch: ~7.5 h** at `--threads 30` **with** `.spectra.bin`
  present. Without the caches, add the parse time (~4.5 min/file uncached from HDD).
* **~150 GB of parquets**, peak ~49 GB private working set. Check free space first.
* **Run at full threads.** The old `--threads 8` cap was a workaround for a memory problem
  fixed 2026-07-25; it is obsolete and just makes runs slower. Results are
  thread-independent - determinism is a project invariant - so threads never change a
  comparison, only its wall time.
* **Decoys are marked by the `decoy_` ProteinID PREFIX, not the `Decoy` column**, which is
  0 on every row of these Carafe entrapment libraries. Filtering on the column is a silent
  no-op. Never "fix" the column. (`strip-decoys.py` hard-fails when it drops nothing,
  precisely so this cannot pass unnoticed.)
* **Arms only compare on ID counts at the same entrapment ratio.** Yield rises as the
  ratio shrinks - a 1:1 marker library perturbs the search and suppresses detections -
  while the ratio-corrected FDP estimator stays valid at any r.
* **Read the COMBINED FDP when r != 1.** The paired estimator needs r=1 AND shuffled
  twins, so Osprey correctly suppresses the paired curve on a non-1:1 library.
* SEA-AD entrapment is **shuffle** (target anagrams), which reads higher than
  foreign-species entrapment because anagrams share the target's composition. Fine for
  arm-vs-arm; do not cite these as absolute error rates.
* `--model-diagnostics` is **on by default** here, and the warning that it OOMs a 64 GB
  box at 82 files is **obsolete**. It now streams its pass-1 report off the projection
  path rather than holding the whole-run pool resident; an 82-file mdiag run completed in
  448 min at ~43 GB peak private on 2026-07-26. It does still force the resident pool on a
  **full resume** (every `.1st-pass` sidecar already on disk) - that is the case to avoid
  at scale. `-NoModelDiagnostics` turns it off.
* Runs use `--output-dir`, not `--work-dir`: `--work-dir` would relocate the `.spectra.bin`
  cache too, so a directory that already has the caches would rebuild all 82. Pass
  `-CacheDir` when the input directory is genuinely read-only and has no caches.
* Every run gets `--timestamp --memstamp` teed to one `run.log`; the memstamp trace is what
  `ai/scripts/perfviz.html` renders.
* `Clear-StandbyCache.ps1` before a timing run - otherwise the OS file cache makes a cold
  read look warm.

## Scripts here

| script | purpose |
|---|---|
| `Run-SeaAd.ps1` | the runner: decoy arm x ratio x pass-2 mode, resolution, `-WhatIf` |
| `Invoke-SeaAdChain.ps1` | queue several arms one at a time on a single box |
| `New-SeaAdLibrary.ps1` | derive ratio-subset and gendecoy library variants |
| `Convert-SeaAdRaw.ps1` | .raw -> mzML (only if not using the pre-converted share) |
| `convert-one.cmd` | the msconvert command line, verbatim; cmd-specific quoting |
| `Clear-StandbyCache.ps1` | evict the OS file cache before a timing run |
| `Test-SpectraCache.ps1` | verify `.spectra.bin` are complete and will actually be USED |
| `Measure-Stage6Rescore.ps1` | measure one stage's resident memory vs file count (#4472) |
| `tools/*.py` | library derivation and the FDP readers |

### Copying caches between machines

`.spectra.bin` are portable - a cache built on one box streams on another, with no
re-parse. Nothing in the format is machine- or path-specific, and it is
**settings-independent**, so one cache per mzML serves every arm/ratio/pass-2 mode. Two
conditions, and both fail SILENTLY (Osprey logs `Spectra cache stale or invalid;
re-parsing mzML` and carries on, so you see a slow run, not an error):

1. **Format version must match exactly.** v4 landed 2026-07-16; a cache written before
   that bump is rejected outright regardless of anything else.
2. **The mzML's size AND last-write-time must match** what the writing machine saw.
   Size survives any copy; mtime only survives a timestamp-preserving one
   (`robocopy /COPY:DAT`). A plain stream download does not preserve it.

`Test-SpectraCache.ps1` answers both in seconds - it reads only the header plus the
footer, and verifies the exact v4 size identity
(`fileLength == indexOffset + nMs2*40 + 16`), so a truncated or still-uploading cache
reads as INCOMPLETE rather than being copied and trusted. Run it against the SHARE
before pulling hundreds of GB:

```powershell
.\Test-SpectraCache.ps1 -CacheDir M:\...\mzml   # vet in place, then copy the good ones
.\Test-SpectraCache.ps1 -Quiet                  # after copying: only non-ACCEPT is printed
```

**Copy mzML with timestamps preserved.** A file copied while its upload was still in
flight keeps the in-progress mtime, and the uploader then stamps the ORIGINAL time on the
source when it finishes - leaving the local copy NEWER than the source, which
`robocopy /XO` would then skip forever. If it happens, the repair is free: when the size
matches, only the timestamp is wrong, so restamping it from the source fixes every cache
without re-transferring a byte.

### Provenance

These replace the one-off harnesses that produced the runs under
`D:\test\Pilot-MTG-Tissue-May2026\runs` on the original machine, which lived in the
gitignored `ai/.tmp/` and so did not travel: `run-82file-decoyarm.ps1`,
`run-82file-gendecoy.ps1`, `run-pass2ab-82.ps1` and `chain-82file-libdecoy-r01.ps1`. They
differed only in which arm, ratio and pass-2 mode they selected, so those are parameters
here rather than four near-identical scripts. If you find the originals, prefer these.

`OSPREY_DECOY_SAME_ION_MAP` appears in the originals as the gendecoy arm's b<->y intensity
swap fix. The swap was removed from both implementations on 2026-07-27 (pwiz #4480 /
osprey #58), so on any build from that day forward the variable is a no-op and the runner
leaves it unset. Set it yourself only when reproducing a pre-fix build.

## Related

* `ai/docs/osprey-development-guide.md` - FDRBench entrapment validation, the oracle that
  outranks parity for anything that moves the discovery set
* `pwiz_tools/Osprey/docs/fractional-entrapment.md` - the ratio-corrected FDP estimators
* `pwiz_tools/Osprey/regression.ps1` - the small published datasets and the CI gate; this
  set is the scale complement to that, not a replacement
