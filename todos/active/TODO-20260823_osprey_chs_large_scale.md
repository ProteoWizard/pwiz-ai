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

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260823_chs_first_run.md` before starting work.
