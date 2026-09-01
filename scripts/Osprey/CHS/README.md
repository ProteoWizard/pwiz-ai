# CHS-SeerData (UW-Floyd Lab) - Seer nanoparticle plasma, 446 files

The **composition** dataset. SEA-AD (82 brain-tissue runs) and TDP-43 (163 plasma-EV runs)
are each a cohort of comparable material, so neither can fail the way this one can: CHS
samples differ in composition from each other, which is the condition that stresses
**Stage 6 reconciliation and cross-run consensus RT**. That makes it a correctness question,
not only a scale question - the reason `ai/docs/osprey-large-datasets.md` ranks it first.

Seer dataset: ~200 samples, each run twice with a different bead, annotated by plate.

## Quick start

```powershell
setx OSPREY_CHS_DIR "D:\test\osprey-runs\chs-seer\raw"
setx OSPREY_CHS_LIB "D:\test\osprey-runs\sea-ad\lib"
# new shell, then prove the wiring before committing to hours
.\Run-Chs.ps1 -Plates 0059 -NumFiles 2 -WhatIf
.\Run-Chs.ps1 -Plates 0059,0060,0061 -Pass2Mode protein-compact
```

`OSPREY_CHS_LIB` points at the SEA-AD library root on purpose: this dataset ships no library
of its own, exactly as TDP-43 does not.

## The plate is in the FILENAME, not the layout

```
EXP25033_2025us0059aX10_A.raw
                 ^^^^ plate
```

The WebDAV source is a **flat directory of 446 files** - no per-plate subfolders. `-Plates`
composes an `-IncludePattern` from that digit run, so a cohort stays expressible as an arm
and the run directory name still describes what was searched. Hand-listing inputs instead is
how a run stops being reproducible from its own name.

Measured from a PROPFIND, 2026-08-22:

| plate | files | GB |
|---|---|---|
| 0059 | 85 | 348.2 |
| 0060 | 85 | 329.9 |
| 0061 | 86 | 341.4 |
| 0062 | 86 | 349.1 |
| 0063 | 86 | 335.3 |
| 0064 | 17 | 66.5 |
| **total** | **445** | **1,770.4** (avg 3.98 GB) |

The staged cohort is **plates 0059-0061: 256 files, 1,019.5 GB**.

## Staging: download and cache, pipelined

Osprey reads the `.raw` directly through a **vendor-enabled build**
(`_bin\26.1.1.233-vendor-20260822` or later, net472 with `pwiz_data_cli`), so no msconvert
pass and no mzML copy is needed - which also makes it cheaper on disk than the mzML route.

Download with `../Get-PanoramaFiles.ps1` (resumable, skips complete files by size), and cache
as files land rather than after the whole pull:

```
https://panoramaweb.org/_webdav/MacCoss/Collaborations/UW-Floyd%20Lab/CHS-SeerData/%40files/RAW%20data%20files/
```

**Gate the caching on a size match against the server manifest, not on the file existing.**
A `.raw` that is still downloading opens fine and fails with
`[RawFileImpl::ctor()] Corrupt RAW file` - which reads like a bad acquisition rather than a
race, and would send you looking in the wrong place. The pipeline used for the first staging
is `ai/.tmp/chs-download.ps1` + `ai/.tmp/chs-cache-watch.ps1`.

Measured on this machine: download ~86 GB/h, caching ~120-150 s/file uncontended. Caching is
gated by arrival, so the two finish within about half an hour of each other. **Both rates
collapse under other disk activity** - one file took 2,997 s while a cleanup and a 21 GB hash
ran alongside, with Osprey at 6% CPU, I/O-starved rather than hung.

## Before a full-cohort run: the join

TDP-43 peaked at **54.2 GB of a 63.7 GB box** in SecondPassFDR, holding 92.2 M pass-2
survivor observations. Survivor count tracks sample richness, not file count - SEA-AD reached
89.1 M from only 82 files.

**Measured for CHS, 2026-08-23 (plate 0059, 86 files): 38.1 M survivor observations =
0.443 M/file, the LEANEST of the three cohorts.** This README previously predicted the
opposite - "bead-enriched plasma, deeper than neat plasma, so 256 files can plausibly land
well past the box". That was wrong: bead enrichment targets a subset, and plasma is lower
complexity than brain tissue. SecondPassFDR peaked at 42.1 GB and is FLAT, so the join
streams as intended.

**MEASURED 2026-08-24: all 257 files ran end to end on this 64 GB box, `exit=0` in 615 min.**
FirstPassFDR peaked at 53.7 GB, PerFileRescoring stayed FLAT at 16.5 GB, and SecondPassFDR
peaked at **69.0 GB** - past physical RAM, so it paged, and completed anyway at 40.0 s per M
observations, inside the single-plate range. Paging past the box cost essentially nothing.

Two things that projection got wrong, both worth not repeating:

* **Survivor observations are NOT additive across plates.** 257 files produced **137.0 M**
  against the three plates' summed 105.2 M - 30% more. Cross-run reconciliation and gap-fill
  transfer detections into files where they were not independently found, so observations per
  file RISE with cohort size: 0.410 M/file at ~86 files -> **0.533 M/file at 257**.
* **A tight fit over a narrow range constrains nothing.** The three plates agreed to 0.5% on
  ~1.10 GB per M obs, but spanned only 31-38 M observations. Over 31 -> 137 M the growth is
  clearly sublinear.

The model that fits BOTH cohorts across the full range:

> **peak ~= 23.9 GB + 0.330 GB per M observations**

(TDP-43 92.2 M -> 54.2; CHS 137.0 M -> 69.0; CHS plate 31.0 M -> 34.1.) The other two plates
sit 4-6 GB above it because Server GC is lazy when there is headroom. **Do not compare
working-set peaks across runs at different memory utilization** - that artifact is what made
CHS look like it cost 1.9x TDP-43 per observation.

At 0.533 M obs/file, **500 files is ~266 M obs -> ~112 GB and still needs the join bounded**.

**Bound the SecondPassFDR join before searching the full cohort**, or start with one plate
(~85 files) and measure the survivor count before scaling. pwiz #4600 moved the whole-run
join into SecondPassFDR deliberately, which is why that stage is now the one to watch; see
`ai/scripts/phase_mem_shape.py` for the fan-out-vs-join shape check.

### Run it in per-plate legs, then join once

Do NOT search 256 files straight through. Score each plate on its own, then join the three
legs with `-LinkFrom`:

```powershell
# Legs 1-3: one plate each, ~8 h apiece. Each is also a complete 85-86 file result.
.\Run-Chs.ps1 -Plates 0059 -DecoyMode libdecoy -Ratio 1.0 -Pass2Mode protein-compact -Threads 30
.\Run-Chs.ps1 -Plates 0060 ...
.\Run-Chs.ps1 -Plates 0061 ...

# Leg 4: the whole cohort, per-file stages linked from the legs. Note the ';' - see below.
.\Run-Chs.ps1 -Plates 0059,0060,0061 -DecoyMode libdecoy -Ratio 1.0 -Pass2Mode protein-compact `
  -Threads 30 -LinkFrom '<runs>\chs-86files-...-p0059;<runs>\chs-85files-...-p0060;<runs>\chs-86files-...-p0061'
```

**Why this and not one straight run.** `PerFileScoring` is over half the wall time and it is
cohort-INDEPENDENT - the peak-pick model is a hardcoded resolution-keyed model, not trained
on the cohort (`OspreyEnvironment.PickLda`), so a file's `.scores.parquet` is the same
whichever cohort it was scored in. Everything that IS cohort-dependent - Percolator training,
Stage 6 reconciliation, consensus RT, the pass-2 join - still runs fresh across all 256 in
leg 4. The legs cost ~10 h more machine time in total, and buy:

* the per-file half becomes a durable asset - if the join needs bounding in code, re-running
  costs only the FDR stages (~11 h), not the ~15 h of scoring again;
* three independent per-plate measurements of survivor observations, which is the
  richness-not-file-count question the whole exercise is about;
* the first real number in ~8 h instead of ~25 h.

**Retrying the join is cheap.** `-LinkFrom` links every stage strictly before `-Task`, so if
SecondPassFDR is what dies, the next attempt is `-Task SecondPassFDR -LinkFrom <leg-4 dir>`
at ~1.6 h, not another 9 h through PerFileRescoring.

**Separate sources with ';' in ONE quoted argument.** `pwsh -File` passes arguments literally
and cannot bind an array: `-LinkFrom a,b` arrives as the single string `a,b`, and
`-LinkFrom a b` binds `b` to the next parameter - which surfaces as a ValidateSet error
naming a parameter you did not touch. Comma syntax works only when dot-invoking from a pwsh
prompt. All sources must carry the same Osprey version stamp or the run refuses to start, and
the banner tallies each source's contribution so a leg that linked nothing is visible up
front. `-WhatIf` walks the link block in probe mode, so check the tally before committing.

## Joining legs scored by DIFFERENT builds

Legs scored days apart carry different `osprey.version` stamps, and `-LinkFrom` refuses the
set. Two things are true at once and it is worth keeping them apart:

* **Osprey's guard** (`ParquetScoreCache`) compares the parquet stamp to the current binary and
  hard-fails. `OSPREY_VERSION_OVERRIDE` is the sanctioned way past it - the code says so, and
  the stamp is pure provenance.
* **The runner's check** reads the FIRST `*.osprey.task` in each source and throws when they
  disagree. **`OSPREY_VERSION_OVERRIDE` does NOT rescue this** - the throw runs before the
  override is consulted. In a completed run directory that first file is
  `.1st-pass.fdr_scores.bin.FirstPassFDR.osprey.task`, a later stage's marker.

**Stage hard links, do not restamp.** Build one directory per leg holding links to only the
four PerFileScoring artifacts (`.scores.parquet`, `.calibration.json`, and each one's
`.PerFileScoring.osprey.task`). Every source then holds exactly one kind of task file, the
version sets agree, and the join links from those. Hard links cost no disk and mutate nothing;
`ai/.tmp/chs-stage-linksrc.ps1` is a worked example, and this is the cheaper answer.

Restamping is the heavier alternative and needs *evidence*, because the guard asks "was this
scored by exactly my binary?" while restamping asserts "this scoring is identical to my
binary's". Establish that first by re-scoring a few of the same files on the new build and
diffing with `../Compare-ScoreParquets.py`; `../Restamp-OspreyVersion.py` then patches the
stamp in place. Do not restamp the later stages' markers - their binary sidecars embed the
version internally, so moving the marker alone manufactures an inconsistency.

Measured on this dataset 2026-09-01: six files re-scored on 26.1.1.243 were bit-identical to
their stored 26.1.1.233 and 26.1.1.238 originals, so `PerFileScoring` output is
build-invariant across those three daily builds as well as cohort-independent.

## Related

* `ai/docs/osprey-large-datasets.md` - the catalog entry, access, and download budgeting
* `ai/docs/osprey-run-layout.md` - where this dataset's directories live and why
* `../SEA-AD/README.md` - the library variants and the FDP readers, shared with this dataset
