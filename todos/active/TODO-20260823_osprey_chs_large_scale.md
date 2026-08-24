# Osprey large-dataset scaling: CHS-SeerData, and the road to 500 files on 64 GB

## Branch Information
- **Branch**: none yet - staging and measurement so far, no code change
- **Base**: `master`
- **Created**: 2026-08-23
- **Status**: Active - cohort staged, first run not yet launched
- **Module**: `osprey`
- **Machine**: BRENDANX-UW8, 63.7 GB RAM, D: single spindle

## Objective

Push Osprey's usable cohort size upward, with the standing target of **500 files on a 64 GB
machine**. The rungs so far: SEA-AD 82 -> TDP-43 163 -> **CHS 256** -> 500.

CHS-SeerData is the right next rung for a reason beyond size: its samples **differ in
composition from each other**, which stresses Stage 6 reconciliation and cross-run consensus
RT. SEA-AD and TDP-43 are each a cohort of comparable material and structurally cannot fail
that way. So this rung tests correctness as well as scale.

## THE CONSTRAINT: memory at the pass-2 join

This is the whole problem, and it is not a file-count problem.

| dataset | files | pass-2 survivor observations | per file | SecondPassFDR peak |
|---|---|---|---|---|
| SEA-AD | 82 | 89.1 M | 1.09 M | - |
| TDP-43 | 163 | 92.2 M | 0.57 M | **54.2 GB of 63.7 GB (85%)** |

**Survivor count tracks sample richness, not file count.** SEA-AD reached nearly the same
observation count from half the files. So "will 500 files fit?" cannot be answered from 500;
it depends on what the samples contain.

pwiz #4600 deliberately moved the whole-run join out of PerFileRescoring and into
SecondPassFDR's pull. Measured on TDP-43 at 163 files:

| PerFileRescoring | before #4600 | after |
|---|---|---|
| final-decile peak | 44.3 GB | **20.2 GB** |
| verdict | 2.34x RAMPS INTO A JOIN | 1.04x flat iteration |

The fan-out stage is now genuinely flat - but **the global peak did not fall, it moved**:
52.2 GB in FirstPassFDR -> **54.2 GB in SecondPassFDR**. That is the intent (pressure sits in
the one task that is legitimately a join, where it can be tuned), and it makes SecondPassFDR
the thing standing between here and 500 files.

**Projection for CHS at 256 files**: at TDP-43's 0.57 M obs/file, ~146 M observations -> ~86 GB,
over the box. CHS is Seer bead-enriched plasma, which deliberately enriches low-abundance
protein, so it is likely *deeper* per file than plasma EV, not shallower. **A full 256-file
run is expected to die at the join** unless the join is bounded first.

Hence the staged plan below: one plate first, to measure obs/file for this matrix, which is
the single number that predicts 256 and 500.

## Where things stand

**CHS 3-plate cohort staged and verified** at `D:\test\osprey-runs\chs-seer\raw`:

| check | result |
|---|---|
| raw verified against server manifest | 256 / 256, 1,019.5 GB |
| `.spectra.bin` caches | 256 / 256, 671.6 GB |
| truncated or suspicious caches | 0 |
| cache failures across the whole staging | 0 |

Cohort structure: plates 0059/0060/0061, each holding BOTH bead preparations
(~43 samples x 2 beads per plate). So 256 files is **~128 samples run twice**, not 256
independent acquisitions - technical-replicate structure TDP-43 did not have. It will affect
experiment-level aggregation and the run-count reproducibility metric; read those with it in
mind.

**Tooling added** (`ai` commits, pushed):
* `ai/docs/osprey-run-layout.md` - the layout standard, now applied to this machine
* `ai/scripts/Osprey/CHS/Run-Chs.ps1` + `README.md` - the sanctioned runner
* `-IncludePattern` in `OspreyDatasetRun.psm1` - CHS's source is a flat directory of 446
  files with the plate encoded in the filename, so a cohort must be expressible as a regex
* `ai/scripts/phase_mem_shape.py` - per-phase memory shape with a fan-out-vs-join verdict

## Two bugs to fix before the first run

1. **`Run-Chs.ps1` `DefaultNumFiles = 0` means NONE, not ALL.** `Select-Object -First 0`
   returns nothing, so the dry run correctly includes 86 files then throws
   `No .raw files found`. Fix by teaching the module to treat 0 as unlimited (better - the
   comment near `OspreyDatasetRun.psm1` line 247 implies 0 is meaningful) or by setting a
   default above the cohort size.
2. **`EXP25033_2025us0059aX10_A.raw` is on disk, absent from the manifest, and uncached.**
   The download filter `*us0059*` fetched 86 files for plate 0059; the PROPFIND-derived
   manifest holds 85, so the cache watcher never saw it. The name DOES match the manifest
   filter `us00(59|60|61)`, so **the omission is unexplained** - worth understanding before
   patching, in case other files were dropped the same way. Cache it with the vendor build
   (`_bin\26.1.1.233-vendor-20260822`, ~2 min); the net8.0 exe cannot read `.raw`.

## The plan: per-plate legs, then one join (Brendan, 2026-08-23)

Do not search 256 straight through. Score each plate separately, then run the full cohort
with `-LinkFrom` over the three legs so only the FDR stages re-run.

This works because **`PerFileScoring` is cohort-independent**: the peak-pick model is a
hardcoded resolution-keyed model, not trained on the cohort
(`OspreyEnvironment.PickLda`, `Osprey.Core/OspreyEnvironment.cs:277-295`), so a file's
`.scores.parquet` does not depend on what else was in the run. `OSPREY_TRAIN_PICK_RUN`
samples the *Percolator* training set and lives in FirstPassFDR, which leg 4 re-runs anyway.
Everything cohort-dependent - Percolator training, Stage 6 reconciliation, consensus RT, the
pass-2 join - runs fresh across all 256.

Costed from TDP-43's actual per-task log (163 files / 779 GB / 19.0 h: PerFileScoring 10.7 h,
FirstPassFDR 2.3 h, PerFileRescoring 4.8 h, SecondPassFDR 1.2 h):

| leg | files / GB | estimate |
|---|---|---|
| 1 - plate 0059 | 86 / 352 | ~7.8 h (measured rate, see log) |
| 2 - plate 0060 | 85 / 330 | ~8.0 h |
| 3 - plate 0061 | 86 / 341 | ~8.3 h |
| 4 - all three, linked | 257 / 1,023 | ~11 h (FP 3.0 + PFR 6.3 + SP 1.6) |

**~36 h total vs ~25 h for one straight run.** The ~11 h premium buys: the per-file half
becomes a durable asset (a join fix costs ~11 h to re-measure, not ~25 h); three independent
per-plate survivor measurements; and the first real number in ~8 h instead of ~25 h.

**The join retry is the payoff.** `-LinkFrom` links every stage strictly before `-Task`, so a
SecondPassFDR death retries as `-Task SecondPassFDR -LinkFrom <leg-4 dir>` at ~1.6 h per
attempt instead of 9.3 h. That is what makes "does the join fit" an iterable experiment.

**Open decision at check-in 1**: legs 2 and 3 could run `-Task PerFileScoring` only, saving
~3.5 h each (~7 h). That forfeits the per-plate FDP / reconciliation / survivor numbers.
Decide with plate 0059's numbers in hand, not now.

## LEG 1 RESULT: 257 files should fit; 500 will not (2026-08-23, plate 0059)

Plate 0059, 86 files, **exit=0 in 501 min (8.35 h)**.
Run: `D:\test\osprey-runs\chs-seer\runs\chs-86files-libdecoy-r1.0-protein-compact-p0059`

**The number: 38,135,138 pass-2 reconciled survivor observations = 0.443 M/file.**

| cohort | files | survivor obs | per file |
|---|---|---|---|
| SEA-AD | 82 | 89.1 M | 1.09 M |
| TDP-43 | 163 | 92.2 M | 0.57 M |
| **CHS** | **86** | **38.1 M** | **0.443 M** |

**CHS is the LEANEST of the three, not the deepest.** The standing expectation in this TODO
and in CHS/README.md - "bead-enriched plasma is deeper than plasma EV, so 256 files can
plausibly land well past the box" - is WRONG and should not be carried forward. Bead
enrichment targets a subset; plasma is lower complexity than brain tissue.

Per-phase peaks at 86 files: FirstPassFDR **46.3 GB** (ramps, 1.51x, but library-dominated -
see below), SecondPassFDR **42.1 GB** and **FLAT (1.03x)**. The protein-compact pass-2 really
does stream ("one file resident at a time" in the log), so the join is not accumulating.

### Projection to 257 and 500

Two-point fit on SURVIVOR OBSERVATIONS, not file count - memory holds observations, and this
TODO's own thesis is that survivor count tracks richness rather than files:

* (38.1 M obs, 42.1 GB) and (92.2 M obs, 54.2 GB) -> **0.224 GB per M obs + 33.6 GB fixed**

| cohort size | obs at 0.443 M/file | projected SecondPassFDR |
|---|---|---|
| 257 files | 113.9 M | **~59 GB** - fits, 93% of the 63.7 GB box |
| 500 files | 221.5 M | **~83 GB** - does NOT fit |

Ceiling on this matrix with current code is roughly **250-300 files**. 257 sits right at it.
FirstPassFDR projects to ~56 GB by the separate file-count fit below, so both stages land in
the mid-to-high 50s - feasible, with little headroom.

Caveat: these are WORKING SET numbers, which include Server-GC retained-but-free pages (see
[[project_osprey_pipeline_peak_is_servergc_retained_committed]]), so true live demand is lower
and 93% is less alarming than it reads. TDP-43 ran successfully at 85%.

**500 files still needs the join bounded.** That is now a properly-scoped target: not "make
the join fit" but "cut ~20 GB out of a 0.224 GB/M-obs slope, or reduce the 33.6 GB fixed term".

### Stage 6 on heterogeneous samples: holds

4,074,680 reconciliation actions over 5,193,257 re-scored entries = 47.4 K actions/file,
against TDP-43's 59.9 K/file (2,810,216 use_cwt + 5,500,844 forced + 1,453,421 gap-fill over
163). Completed clean. The composition worry that motivated picking this cohort does not
show up as a reconciliation failure.

## FirstPassFDR memory is library-dominated, not file-count-dominated (2026-08-23)

`phase_mem_shape.py` on leg 1 (86 files) against the TDP-43 163-file run:

| phase | CHS 86 files | TDP-43 163 files |
|---|---|---|
| PerFileScoring | 21.5 -> 20.6 GB, flat | flat |
| **FirstPassFDR** | 23.9 -> 42.8 GB, max **46.3** | 24.3 -> 44.2 GB, max **50.8** |
| PerFileRescoring | **13.6 GB steady, flat** | flat |

**1.9x the files buys 4.5 GB.** Both runs start at ~24 GB and end at ~43-44 GB. The dominant
term is fixed - the shared 6,175,389-entry library - with a per-file slope of ~0.058 GB/file.
Fit: **257 files -> ~56 GB in FirstPassFDR**, under the 63.7 GB box.

Beware the ratio trap this corrects: CHS reaching 91% of TDP-43's working set with 53% of the
files reads as "CHS is much heavier per file" and is not - that is the signature of a large
FIXED cost. Compare the SHAPE across deciles, not the endpoint ratio.

**PerFileRescoring is confirmed flat at 13.6 GB**, so pwiz #4600 did what it claimed.

**`--fdrbench-pass 2` already takes the bounded path.** `FirstPassFdrTask.cs:376` forces the
resident first-pass pool only for `--fdrbench` WITH `--fdrbench-pass 1`; these runs are on the
streaming projection path already, so 46.3 GB is what streaming costs and there is no lean-path
lever left to pull at this stage.

Still open: SecondPassFDR for CHS. TDP-43's was the global peak (54.2 GB at 163 files).

## Next steps

1. Fix both bugs above; re-run `Run-Chs.ps1 -Plates 0059 ... -WhatIf` until it resolves 86
   files cleanly.
2. **Run plate 0059 (86 files) end to end**, TDP-43 settings: `-DecoyMode libdecoy -Ratio 1.0
   -Pass2Mode protein-compact -Threads 30 -FdrBenchPass 2`, model-diagnostics on, library
   `sea-ad\lib\target+decoy+entrapment-20260817`, exe `_bin\26.1.1.233-20260821`. ~8 h.
3. **Harvest the number that matters**: pass-2 survivor observations from the
   `OSPREY_PASS2_QVALUE=protein-compact` line, and the SecondPassFDR peak from
   `phase_mem_shape.py`. Those two give obs/file for this matrix and predict 256 and 500.
4. Read the composition question: does Stage 6 reconciliation hold on heterogeneous samples?
   Compare reconciliation action counts and gap-fill rates against TDP-43's
   (use_cwt 2,810,216 / forced 5,500,844 / gap-fill 1,453,421 at 163 files).
5. Decide on 256 based on (3), not on optimism. If the projection says it will not fit, the
   join work comes first.

## Measurement doctrine earned the hard way (2026-08-22/23 staging)

* **On this box, serial beats parallel for large-file I/O.** Download at 1 stream ran at
  **375 GB/h**; at 4 streams, **138 GB/h** - and the 4-stream case simultaneously starved
  caching from ~100 s/file to ~1,900 s/file. Single spindle: concurrent streams turn
  sequential access into seeks.
* **Parallel cache workers do NOT help.** 3 workers measured 521 s/file effective against
  ~327 s for one. The tempting inference (26 MB/s at 6% CPU on a 104 MB/s disk => latency
  bound => parallelize) is wrong here.
* **A contaminated experiment is worse than none.** The test that "confirmed" parallel
  scaling used a file downloaded minutes earlier, so it measured a page-cache RAM read, not
  a cold parallel disk read, and read degradation off a single file. Pick a file staged hours
  earlier and measure >= 3 per arm.
* **Hard links make directory size a lie.** `-LinkFrom` shares Stage 1-4 artifacts 20-30
  ways; an early "6.8 TB reclaimable" estimate was really ~290 GB. Check
  `fsutil hardlink list` before quoting a reclaim figure.
* **The next real lever is hardware**: caching to a different physical disk from the `.raw`
  source removes the seek contention entirely. Worth doing before staging the next cohort.

## Related

- `ai/todos/active/TODO-20260821_tdp43_pickrun3_ourlib.md` - the 163-file rung and its result
- `ai/docs/osprey-large-datasets.md` - the catalog; CHS entry, sizes, download budgeting
- `ai/docs/osprey-run-layout.md` - where runs live
- `ai/todos/completed/TODO-20260819_osprey_train_sample_default-stats.html` - the cross-dataset
  results page, now carrying SEA-AD, TDP-43 and the 3-file regression sets

## Progress log

**2026-08-23** - CHS 3-plate cohort downloaded (1,019.5 GB) and cached (671.6 GB), fully
verified, zero failures. `D:\test` cleaned and normalized to the layout standard: 3.1 TB
freed (1,786 -> 4,895 GB), `osprey-runs` now matches the other test machine. Runner, README
and layout doc committed. First run not launched - two bugs found in the dry run, recorded
above.

**2026-08-23 (afternoon)** - Both bugs fixed and committed; leg 1 launched 14:15.

* **Bug 1 fixed**: `OspreyDatasetRun.psm1` now treats `NumFiles = 0` as the whole candidate
  set (`Select-Object -First 0` returned nothing). Also added the plate list to the CHS run
  directory name - plates 0059 and 0061 are BOTH 86 files, so two single-plate runs would
  have resolved to one directory.
* **Bug 2 fixed**: `EXP25033_2025us0059aX10_A.raw` cached with the vendor build in 130.8 s
  (2.84 GB bin) - squarely in the documented 121-150 s band, which also proves the `.raw` was
  complete rather than truncated. Plate 0059 is now **86 files**, not 85.
* **The manifest omission is explained.** `chs-sizes.json` holds 256 of the 257 `.raw` on
  disk, and the one missing file is the **lexicographic first of the whole sorted set**
  (`us0059aX10` sorts before `us0059aX11` because `0` < `_`; 0059 is the lowest plate). Every
  other plate's first file is present. That is a dropped head element - a `Skip 1` meant to
  discard the WebDAV collection's self-entry, applied after the plate filter had already
  removed it. Only one file can be lost this way, and a both-directions diff of manifest vs
  disk confirms exactly one asymmetry. The manifest is otherwise trustworthy.
* **Library comparability proven, not assumed.** TDP-43 ran against
  `AstralTest-TargetDecoyLibraries\target+decoy+entrapment-20260817`, which the D: cleanup
  moved; the CHS run uses `sea-ad\lib\target+decoy+entrapment-20260817`. Both load
  **6,175,389 library entries** - identical. (The surviving
  `AstralTest-TargetDecoyLibraries\target+decoy+entrapment` is a *different*, older library:
  13.09 GB / Jun 30 vs 12.39 GB / Aug 17. The TODO's "every file has a same-size peer" claim
  below is wrong for the entrapment library.)
* **`-LinkFrom` now takes several sources**, for leg 4. Probed in order, first hit wins; all
  sources must carry the same Osprey version stamp or it refuses to start (a mixed-build join
  would otherwise fail hours in as an "osprey version mismatch" naming one file); the banner
  tallies each source so a leg contributing nothing is visible up front. `-WhatIf` now walks
  the link block in probe mode - it used to `return` before it, leaving the most
  expensive-to-get-wrong step as the one the dry run never exercised. Verified on synthetic
  sources: 2-source link, version-mismatch refusal, dead-source tally, single-source
  backward compatibility.
* **Separator is `;` in one quoted argument** - `pwsh -File` cannot bind an array at all.
* **Early signal**: CHS is scoring **3.66 M entries/file** against TDP-43's mean of
  3,663,958 - effectively identical, so the per-file load is not deeper despite the bead
  enrichment. This is NOT the survivor count and does not settle the join question.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260823_chs_first_run.md` before starting work. Note its "85 files" and
"257 .raw" figures are now stale: plate 0059 is 86 files and all 257 are cached.
