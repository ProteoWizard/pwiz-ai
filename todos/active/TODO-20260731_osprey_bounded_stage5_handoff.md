# TODO-20260731_osprey_bounded_stage5_handoff.md

## Branch Information
- **Branch**: `Skyline/work/20260731_osprey_bounded_stage5_handoff`
- **Base**: `master` (at `d030522344`, i.e. after #4508 / #4509)
- **Created**: 2026-07-31
- **Status**: In Progress
- **Module**: `osprey`
- **PR**: (pending)

## Problem

The first-ever 163-file Osprey run (TDP-43 Plasma EV-Quant, 2x SEA-AD) peaked at
**90.2 GB private / 75.9 GB managed** in `FirstPassFDR`, against 128 GB of RAM. At 10 and
20 files the same phase peaked at 36.8 and 35.1 GB, so this was invisible at every cohort
size previously tested - the two smallest cohorts actually showed Stage 5 going DOWN as
files doubled.

Full evidence: `ai/.tmp/finding-20260731_osprey_stage5_o_files_memory.md`.

### The guard did its job; this is downstream of it

The run took the streaming projection correctly:

```
[MEM projection counts-only: 577590368 rows across 163 files
 (no resident rows); FdrEntry stubs released]   managed_heap=5.19 GB (post-GC)
```

`NeedsResidentPool` returned false and #4508's ratchet was never engaged. **This path needs
no token today, and none of the five in `ResidentPaths.KNOWN_UNFIXED` would admit or refuse
it.** All five gate the PRE-compaction first-pass `FdrEntry` pool. The growth here is
POST-compaction, in the normal handoff every run performs:

```
FirstJoinTask.cs:439      ctx.Publish(new CompactedEntries(perFileEntries));
PerFileRescoreTask.cs:201 _perFileEntries = ctx.Get<CompactedEntries>().Value;
PerFileRescoreTask.cs:208 ctx.Publish(new RescoredEntries(_perFileEntries));
```

One `List<KeyValuePair<string, List<FdrEntry>>>` holding ALL files is built in Stage 5,
overlaid in place by Stage 6 (`PerFileRescoreTask.cs:141` - "the shared buffer this task
overlays in place"), and handed to MergeNode. So the ratchet's stated invariant ("no unnamed
O(files) resident structure") is not actually what it enforces; it enforces "no unnamed
PRE-COMPACTION pool", and stops at the compaction line.

### Two distinct symptoms, measured

| | source 1 - the holder | source 2 - the churn |
|---|---|---|
| where | `CompactFirstPass` (`FirstJoinTask.cs:860`) | `Planning reconciliation across N file(s)` |
| signature | managed FLOOR rises to ~28 GB and stays there through all of Stage 6 | managed AMPLITUDE 31 <-> 76 GB, floor unchanged |
| scale term | 577,590,368 rows -> **88,875,901 retained entries** (446,343 passing base_ids) | 7,109,287 per-(file, entry) actions planned |

**They are coupled, and that matters for sequencing.** .NET's gen2 allocation budget scales
with the live set, so the churn's amplitude is a MULTIPLE of the hold:

```
live set          ~31 GB
GC growth factor  ~2.4x
predicted managed peak ~74 GB   observed 75.9 GB
predicted private peak ~90 GB   observed 90.2 GB
```

Fixing source 1 should shrink source 2 automatically - the GC will collect far sooner
against a small live set. **Do source 1 first and re-measure before touching the planning
loop's allocations.** The zoomed `--memstamp` plot shows ~7-8 slow sawteeth over the ~529 s
planning phase (NOT 163, so not per-file); they are gen2 cycles, and each returns to the
same ~31 GB floor - i.e. the churn retains nothing.

Note this shape defeats the heuristic in `ai/docs/memory-band-guide.md`: a sawtooth whose
FLOOR returns to the same level reads as "bounded", and this one does - yet its amplitude
alone drove the process to 90 GB of 128 GB. Bounded floor with O(files) amplitude is not a
case the guide covers; worth a paragraph there.

## Design (agreed with Brendan 2026-07-31)

Same pattern already applied elsewhere in Osprey: **the bounded path becomes the DEFAULT,
and the resident path survives only as a token-gated parity oracle until it is deleted.**

1. **Make the per-file (HPC) path the default for the in-process straight-through run.**
   Osprey already HAS the streaming design - `RescoreWorker` rescores one file from its own
   `scores.parquet` + `reconciliation.json` and never sees the other 162, and Stage 5 already
   writes both artifacts for every file. The in-process path simply does not use it. So this
   is "adopt the path that exists", not "invent streaming".
2. **Add a `ResidentPaths` token for the resident handoff** (proposed:
   `compacted-entries-buffer`). Without it, the resident path is unavailable. With it, the run
   takes the old buffer - which is the A/B oracle that proves the streamed path did not change
   results, exactly the role `PROJECTION_OFF` plays today.
3. **The token list may only shrink**: this ADDS an entry, which `ResidentPoolGuardTest` pins
   and which therefore shows up in review as the ratchet running backwards. Justify it in the
   PR as a path being NAMED for the first time (it was previously unguarded and unnamed), not
   as a bounded path regressing. Once the resident handoff is deleted the token goes with it.
4. **Extend the guard past the compaction line** so the next post-compaction resident
   structure cannot land in the same blind spot.

Rationale, in Brendan's words: maintaining two paths (HPC and "resident memory") is costing
the ability to scale on a single machine, and the "keep everything in memory for throughput"
premise looks dubious even at small N. Measured support: rescore costs **2.03-2.47 min/file**,
so re-reading a parquet that Stage 6 opens anyway is noise against that. `PerFileScoring`
already made this move - it never holds all features resident
(`PerFileScoringTask.cs:1362-1366` records that loading 21 doubles per row cost ~800 MB/file).

## Risk to resolve BEFORE implementing: the merge node

`ResidentPaths.HPC_MERGE` ("the HPC reconciled-input merge (`--task SecondPassFDR`), which
loads every worker's entries to reconcile them", tracked by **#4486**) is ALREADY a known
resident path. So "use the HPC path always" bounds Stage 5 and Stage 6 but may just move the
residency into the merge, which is resident by its own admission.

Mitigating evidence, to be confirmed rather than assumed: the in-process merge under
`protein-compact` already streams -

```
OSPREY_PASS2_QVALUE=protein-compact: recomputing q/PEP by streaming 163 file(s),
frozen-model scores swapped in for ... -- no retrain, one file resident at a time
```

So the frozen-model pass-2 modes appear bounded; the `percolator` retrain is the open
question. **Answer this first** - if the merge needs the whole pool for a retrain, this work
bounds two of three phases and #4486 becomes the blocker for the third.

## Parity requirement

The two paths must produce **byte-identical** output. This is the whole reason the resident
path survives behind a token. Gate:

* `pwiz_tools/Osprey/regression.ps1 -Dataset Stellar` mode1/2/3, then `-Dataset All` before
  merge - byte identity vs the committed golden, which must NOT move.
* A same-cohort A/B: one run default (streamed), one with
  `OSPREY_ALLOW_UNFIXED_RESIDENT=compacted-entries-buffer` (resident), diffing the blib and
  the reported q-values. Do this at a size where the resident path still fits - 20 files.
* TeamCity **Osprey Windows .NET Perf/Regression** on `pull/<N>` before human review (ASK
  Brendan first, every time).

## Verification at scale - cheap, because scoring is linkable

`-LinkFrom` hard-links only the four Stage 1-4 suffixes (`.calibration.json`,
`.scores.parquet`, and their `.osprey.task` stamps) and deliberately NOT the
`.1st-pass.fdr_scores.bin` sidecars - which matters here, because `--model-diagnostics` on a
FULL resume forces the resident pool (`MDIAG_FULL_RESUME`). So a Stage-5-only re-test at 163
files is honest and costs **~75 min**, less than the TeamCity perf gate:

```powershell
.\Run-Tdp43.ps1 -PickLda -Pass2Mode protein-compact `
    -LinkFrom <the completed 163-file run dir> -Task FirstPassFDR -Fresh
```

(`-Task` still needs adding to the runner - see below.)

Baseline to beat, from the 2026-07-30/31 run:

| | before |
|---|---|
| FirstPassFDR wall | 4535.6 s |
| FirstPassFDR peak private | 90.2 GB |
| FirstPassFDR peak managed | 75.9 GB |
| retained after compaction | 88,875,901 entries / ~28 GB managed floor |

**Prediction to test**: because the amplitude is coupled to the live set, cutting the hold
should drop the peak by roughly **2.4x** the reduction, not 1x. If peak falls only ~1x the
hold, the coupling model is wrong and the planning loop needs its own allocation fix.

## Runner support still needed

`ai/scripts/Osprey/Common/OspreyDatasetRun.psm1` gained `-ParallelFiles` on 2026-07-31 but
has no `-Task`. Add it (recorded in the banner and the `run.log` START/DONE lines, same
reasoning as `-PickLda`: an unrecorded setting makes a finished run unattributable).

## Open questions

1. Does the `percolator` pass-2 retrain need the whole rescored pool? (decides whether #4486
   blocks the third phase)
2. What is the 28 GB actually MADE of - 88.9 M bare objects at ~150 B, or arrays still hanging
   off `FdrEntry`'s six reference fields (`Features`, `CwtCandidates`, `FragmentMzs`,
   `FragmentIntensities`, `ReferenceXicRts`, `ReferenceXicIntensities`)? `FirstJoinTask`
   already nulls `Features` before compaction; the other five are unverified. If arrays
   survive, a payload fix might recover most of the 28 GB far more cheaply than the
   architectural change - worth ONE dotMemory snapshot after `First-pass compaction:` at 60
   files before committing to the full refactor.
3. Should the guard's error text distinguish "unnamed path" from "named but not allowed" for
   post-compaction structures, or is one message enough?
