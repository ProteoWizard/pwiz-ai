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

## Paying for the diagnostics after the fact (P16)

A run that finished WITHOUT `--model-diagnostics` can be asked for the report later, and
the only work that happens is producing the diagnostics artifacts. That is principle P16 in
`pwiz_tools/Osprey/docs/00-pipeline-architecture.md`, and the recipe is:

```powershell
$env:OSPREY_CHS_LIB = 'D:\test\osprey-runs\sea-ad\lib'
.\Run-Chs.ps1 -Task ModelDiagnostics -LinkThroughTask `
    -LinkFrom '<the completed run>;<the run that produced its first pass>' `
    -Exe D:\test\osprey-runs\_bin\<tag>\Osprey.exe -Tag '-p16proof' -WhatIf
```

**`-LinkThroughTask` is the part that is easy to get wrong and expensive to get wrong.**
Without it, `-LinkFrom` stages only the stages strictly BEFORE `-Task`, which is right for a
re-MEASUREMENT of one phase and wrong for a re-ENTRY. A re-entry needs each stage's own
outputs *and their `.osprey.task` stamps* on disk, because the stamp is the only thing that
tells a pass it has already run. Stage too little and both passes recompute - and they
produce the CORRECT report, so no artifact and no gate can tell you it happened. The cost
at 446 files is 4h46m for the first pass and 69 min for the second, against minutes for the
fold.

**Assert the marker, not the wall clock.** Each pass logs the line that names the path it
took:

```
FirstPassFDR: every output but the model-diagnostics product is current;
folding the report from the completed first pass.
SecondPassFDR: every output but the model-diagnostics product is current;
folding the pass-2 report from the completed second pass.
```

Check for both within the first minutes and kill the run if either is missing. Wall clock
alone cannot serve: a compliant fold still STREAMS every run (the pass-2 cards are
reductions over every 2nd-pass sidecar and reconciled parquet, and the co-assignment panel
needs two reads of the pool), so a fold and a join differ by a factor rather than by a
category. "No analysis" means no recomputation, not no I/O.

**Two sources, in this order.** The completed Stage 7 run supplies the per-file artifacts
and the 2nd-pass experiment sidecar; an older leg may be the only place the *pass-1*
experiment sidecar's stamp survives, because staging used to drop the stamps of
analysis-wide artifacts. The first source that has a given file wins, so listing the
completed run first and the older leg second gets both. `-WhatIf` prints one
`analysis-wide:` line per file with the source it came from - read them, and treat a
`LinkFrom WARNING: no analysis-wide ...` as a staging error rather than a note.

Small-scale coverage for the same property is `regression.ps1` **mode 11**, which deletes
both diagnostics products from a completed run and asserts that the folds run, that the
join's markers do NOT appear, and that the products come back byte-identical.

## Re-measuring Stage 7 on the ORDINARY run (`-LinkUpTo`)

Stage 7 is the stage a memory measurement usually wants, and reaching it honestly is the
awkward part: the arm an operator exercises is a plain `-i ... --output-dir` run resumed at a
completed bed, and getting there through the runner used to cost either hours or the wrong
arm.

* No `-Task` links only the stages before `FirstPassFDR`, so the run re-does Stage 5 and the
  whole Stage 6 rescore before it reaches the thing being measured.
* `-Task SecondPassFDR` links exactly the right set, but puts `--task SecondPassFDR` on the
  command line - the HPC **merge** route, which is different code from the ordinary run.
  (That difference is not academic: the merge route was the only route that could stream the
  Stage-7 join until the admission was derived from the reconciled parquets on disk.)

`-LinkUpTo` names the boundary directly and leaves the command line alone:

```powershell
.\Run-Chs.ps1 -DecoyMode libdecoy -Ratio 1.0 -Pass2Mode protein-compact -Threads 30 `
    -NoModelDiagnostics -Tag '-s7straight' -Exe D:\test\osprey-runs\_bin\<tag>\Osprey.exe `
    -LibraryDir D:\test\osprey-runs\sea-ad\lib\target+decoy+entrapment-20260817 `
    -LinkFrom D:\test\osprey-runs\chs-seer\runs\chs-446files-libdecoy-r1.0-protein-compact-stages567 `
    -LinkUpTo SecondPassFDR -WhatIf
```

Every pre-Stage-7 artifact is hard-linked in, nothing but the inputs is on the command line,
and the run resumes straight into the join. Read the `-WhatIf` link tally first: `0 missing`
is the precondition, and a non-zero count means the bed does not cover this cohort.

**Assert the marker.** A streamed join logs

```
Second-pass join: folding over 446 run(s), ... (no all-runs survivor pool)
```

and a resident one logs `Stage 7 is taking the RESIDENT join` plus
`Rebuilding first-pass survivors from 446 file(s)`. The output is IDENTICAL either way - that
is the whole design - so the log line is the only evidence, exactly as it is for the P16 folds
above. `regression.ps1` asserts the same marker per leg at Stellar scale.

### The library directory is part of `search_hash` - pin it from the SOURCE run

A re-entry must resolve the SAME library file the bed was scored with, or Osprey refuses
the parquets:

```
[ERROR] Pipeline failed: ...scores-reconciled.parquet: search_hash mismatch: parquet was
scored with search_hash=dd85be27... but current config hashes to 661d98d9...
```

That is the guard working - it fails in about two minutes rather than describing a
different search - but the message names hashes, not the argument that differs, so it does
not tell you what to change. (Since the 2026-09-12 fix to the terminal error sinks the line
also carries the exception type ahead of the message and is followed by the stack frames;
the `search_hash mismatch` text is what to look for.)

The trap is that the lib root holds more than one library and the runner picks one by
convention. `chs-446files-libdecoy-r1.0-protein-compact-s7mdiag` was scored against
`target+decoy+entrapment-20260817`, while the default resolution finds
`target+decoy+entrapment` - same file name, different directory, different hash.

**Read the source run's own command line and pass `-LibraryDir` to match it:**

```powershell
Select-String -Path '<the source run>\run.log' -Pattern 'Command:' |
    Select-Object -First 1
```

then pass that directory explicitly:

```powershell
.\Run-Chs.ps1 -Task ModelDiagnostics -LinkThroughTask `
    -LibraryDir 'D:\test\osprey-runs\sea-ad\lib\target+decoy+entrapment-20260817' ...
```

`-WhatIf` prints the resolved `library :` line and the full command it would run. Diff that
command against the source run's `Command:` line before launching: for a diagnostics
re-entry the two should differ in `--task` and the output paths and in NOTHING ELSE.

## Related

* `ai/docs/osprey-large-datasets.md` - the catalog entry, access, and download budgeting
* `ai/docs/osprey-run-layout.md` - where this dataset's directories live and why
* `../SEA-AD/README.md` - the library variants and the FDP readers, shared with this dataset
