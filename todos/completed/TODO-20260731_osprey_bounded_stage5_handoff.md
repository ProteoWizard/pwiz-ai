# TODO-20260731_osprey_bounded_stage5_handoff.md

## Branch Information
- **Branch**: `Skyline/work/20260803_osprey_bounded_stage5_handoff`
- **Base**: `master` (at `e7b5a917ba`, i.e. after #4528)
- **Created**: 2026-07-31 (branch cut 2026-08-03)
- **Status**: Completed
- **GitHub Issue**: [#4526](https://github.com/ProteoWizard/pwiz/issues/4526)
- **Module**: `osprey`
- **PR**: [#4530](https://github.com/ProteoWizard/pwiz/pull/4530) (merged 2026-08-05 as `b554ce6f0d`)
- **TeamCity Perf/Regression**: build 4121676 on `pull/4530` - SUCCESS

> The `Skyline/work/20260731_osprey_bounded_stage5_handoff` branch name on `origin` was
> reused by the progress-reporting work that became #4513 (merged), so it carries none of
> this. Work happens on the `20260803_` branch above.

## RESOLVED: the pause below is lifted (2026-08-04)

#4528 merged and this branch is rebased onto `e7b5a917ba`, so every fix in the table below
is now IN the tree. Kept because the general trap it names is worth carrying, and because
the `survivorScoreOverride` / effective-path row is directly relevant to the open Stage 7
divergence recorded further down.

## STOP: paused on purpose, and re-reading the code will mislead you

**Brendan stopped this work on 2026-08-03 because the session running it was finding issues
that [TODO-20260802_osprey_default_flip.md](TODO-20260802_osprey_default_flip.md) (#4484) had
ALREADY FIXED on a branch that had not merged yet.** Those fixes live in exactly the Stage
5/6/pass-2 code this TODO bounds, so reading master here surfaces defects that are already
resolved, and "fixing" them costs a session and then conflicts.

**Rebase onto #4484 FIRST. Then re-derive.** Do not treat anything below as a live defect
until you have. Already fixed on that branch, all in this code:

| already fixed in #4484 | commit |
|---|---|
| Stage-6 rescored entries reach pass 2 UNSCORED in-process (`OverlayRescoredEntries` resets `Score=0`/q=1; protein-compact's off-stratum branch then read the sentinel). Straight-through UNDER-REPORTED against the HPC chain | `8796e7a13` |
| `survivorScoreOverride` presence is NOT a "Stage 6 changed" signal - it holds every post-reconciliation survivor whose identity resolves, and the effective-path helper falls back to the ORIGINAL parquet for untouched files. Now keyed on a bit-exact score difference | `1e90d5453` |
| Off-stratum peaks re-maxed the CROSS-FILE experiment accumulator over only the files that changed them, which is guaranteed to understate and silently DROPPED peptides. Now carries the pass-1 experiment q | `03f31954a` |
| The protein-compact stratum was never persisted, so a `--task SecondPassFDR` merge node could not run the mode at all | earlier on the same branch |
| `OSPREY_PICK_LDA` / `OSPREY_PASS2_QVALUE` were absent from every resume validity key, so a run adopted the other arm's cached artifacts | `cb9b68c60` |
| Two dead null guards in `StreamingFdr.Admit` (`ConditionIsAlwaysTrueOrFalse`) | `cb9b68c60` |

The general trap, worth carrying beyond these two branches: **when two Osprey branches touch
the same stage, the later one cannot tell an unfixed defect from an unmerged fix by reading
the code.** Only the merge order can. Sequence, do not parallelize.

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

## The merge node - NOT a blocker, because pass-2 Percolator is being removed

`ResidentPaths.HPC_MERGE` ("the HPC reconciled-input merge (`--task SecondPassFDR`), which
loads every worker's entries to reconcile them", tracked by **#4486**) is already a known
resident path, so the obvious worry is that "use the HPC path always" merely relocates the
residency into the merge.

**It does not, and the reason is a product decision rather than a memory argument.**
Brendan and Mike have settled that `OSPREY_PASS2_QVALUE=percolator` must GO: the 2nd-pass
Percolator retrain fits on the decoy-DEPLETED, target-selected reported pool, which makes
the model over-confident and the q-values **anti-conservative** (Stellar true FDP 1.08%,
Astral 1.24% at 1% reported q). Written up in the completed TODOs:

* `TODO-20260710_osprey_pass2_recalibration_fix.md:146` - "the null is decoy-depleted and
  target-selected. Retraining on it makes the model over-confident and the q-values
  anti-conservative" ... ":149" - "Step 2 is the entire anti-conservative source".
* `TODO-20260720_osprey_pass2_per_run_qvalue.md:127` - same conclusion on the per-run path.
* `TODO-20260715_osprey_pass2_transfer_compete.md` - the frozen-model replacements
  (`transfer`, `transfer-compete`, `protein-compact`) and their measured FDP recovery.

The replacement has not been chosen, but **every candidate is a FROZEN-model mode, and those
already stream**. Observed on this very 163-file run:

```
OSPREY_PASS2_QVALUE=protein-compact: recomputing q/PEP by streaming 163 file(s),
frozen-model scores swapped in for 2234621 reconciled survivors
-- no retrain, one file resident at a time, competition CONSTRAINED to the
   458345-base_id protein stratum
```

So the only pass-2 mode that plausibly needs the whole pool resident is the one being
deleted. **Do NOT design this work around keeping `percolator` viable** - that is the
opposite of where the product is heading, and preserving it would be the reason to keep a
resident merge. Scope accordingly: bound Stage 5 and Stage 6 here, and expect the merge to
follow for free once `percolator` is gone (#4486 then covers only the true HPC
`--task SecondPassFDR` merge, not the in-process path).

Practical consequence for this branch: the parity A/B and the regression gate should run
with a frozen-model pass-2 mode as the primary configuration. `percolator` remains the
regression golden's mode today, so byte-identity against the committed golden still has to
hold - but it is a compatibility check on a doomed path, not a design constraint.

### THAT LAST PARAGRAPH EXPIRES ON MERGE OF #4484 (noted 2026-08-03 from the flip branch)

`Skyline/work/20260802_osprey_default_flip` ([TODO-20260802_osprey_default_flip.md](TODO-20260802_osprey_default_flip.md),
umbrella [#4484](https://github.com/ProteoWizard/pwiz/issues/4484)) **removes the
`percolator` pass-2 mode outright** - an unrecognized `OSPREY_PASS2_QVALUE` is now a startup
error - and **re-baselines all four regression goldens onto `protein-compact`**. Rebase onto
it before resuming here, and read these three consequences:

* **The "compatibility check on a doomed path" is gone**, not merely deprioritized. The
  committed golden's mode IS `protein-compact` after the re-baseline, so "run the gate with a
  frozen-model mode as the primary configuration" stops being a special instruction - it is
  simply what the default gate does.
* **Do not re-baseline the goldens again for the memory work.** Bounding the handoff is
  supposed to be output-neutral, so mode 1 staying green against the NEW baseline is the
  proof. A golden move would be the signal that the streamed path changed results.
* **`OSPREY_PICK_LDA` and `OSPREY_PASS2_QVALUE` now participate in the resume validity key**
  (pwiz `cb9b68c60`), so an output directory written before that commit is invalidated once
  and re-runs Stage 1-4. Expect one surprising cold run on a `-LinkFrom` adoption of an older
  directory; it is correct, not a regression.

The memory accumulation this TODO covers is **explicitly NOT in scope for #4484** (Brendan,
2026-08-03) and does not block its merge - it was already known from the `--memstamp` and
env-var-gated tests recorded above, and it does not affect the golden re-baseline.

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

## Measured 2026-08-03 (answers open questions 2 and 4)

### Q2 - what the 28 GB is made of: bare objects. Answered from code; no dotMemory needed.

Survivors are reloaded by `ParquetScoreCache.LoadFdrStubsFromParquet`
(`ParquetScoreCache.cs:802-815`), which sets only the 10 scalar columns plus
`ModifiedSequence`. **All six reference fields are left null** - `Features`,
`CwtCandidates`, `FragmentMzs`, `FragmentIntensities`, `ReferenceXicRts`,
`ReferenceXicIntensities`. There is no payload to shed, so a payload fix recovers nothing
and the architectural change is the only lever on the object count.

`FdrEntry` = 14 doubles + 7 references + 3 small scalars = **~208 B/object** including
header and the `List<T>` slot -> 88.9 M objects at ~18.5 GB. The remaining ~5-6 GB is one
`ModifiedSequence` string per row, read from parquet with **no interning on that path**
(the library-load path interns - `Interned library strings: 10481622 distinct / 21174537
total (50.5% collapsed)`). **Unverified**: whether Parquet.Net shares dictionary-encoded
string instances. If it does not, interning there is a cheap independent ~5 GB.

### Q4 (new) - the `protein-compact` stratum is 84% of the buffer

Measured directly from all 163 `.1st-pass.fdr_scores.bin` sidecars, splitting the
compaction gate (`FirstJoinTask.ComputeFirstPassBaseIds`) into its three clauses
(script: `ai/.tmp/gate_split.py`):

| gate clause | base_ids | survivor rows |
|---|---|---|
| `RunPeptideQvalue <= 0.01` | 58,429 | |
| `RunProteinQvalue <= 0.01` | 59,857 | |
| union of the two FDR clauses | **59,857** | **14,501,070** |
| actual, with `stratum.Contains(baseId)` | **446,343** | **88,875,901** |

The stratum clause admits **386,486 extra base_ids (86.6%) and 74.4 M extra entries
(84%)** - precursors that passed first-pass FDR in no file, carried resident through the
whole 5.5-hour rescore. Their consumer, the pass-2 stratified competition, **already
streams one file at a time**.

**Open, deliberately out of scope for the first PR**: whether stratum-only survivors need
to be materialized as Stage-6 `FdrEntry` at all, or could travel as a base_id set and be
materialized at pass 2 from the reconciled parquet. That is a ~6x term on the same buffer,
independent of the streaming change. Recorded so it is not lost.

### Scaling is super-linear, not linear

The survivor count is O(files x passing base_ids) and the base_id set itself grows with
files, so the product outruns the file count. Same arm, same library, same dataset:

| files | survivor entries | passing base_ids | entries/file | measured floor |
|---|---|---|---|---|
| 3 | 408,685 | 99,560 | 136k | |
| 6 | 1,140,686 | 133,788 | 190k | |
| 10 | 2,210,261 | 172,381 | 221k | |
| 20 | 5,178,890 | 210,126 | 259k | 6.65 GB |
| 40 | 13,398,508 | 272,526 | 335k | |
| 163 | 88,875,901 | 446,343 | 545k | 28.17 GB |

20 -> 163 files is **8.2x the files but 17.2x the entries**. This is why the residual
#4488 measured did not hold: that PR projected ~19 MB/file and "no longer the scaling
blocker"; this run is **173 MB/file**, and rising.

### Phase split confirms #4488 worked and this is the floor beneath it

`perfviz.py` over the phase-split `run-saved.log`:

| phase | wall | managed floor | verdict |
|---|---|---|---|
| `PerFileScoring` | 10:36:13 | 5.2 -> 5.7 GB (+3 MB/file) | LEVEL |
| `FirstPassFDR` | 1:15:35 | 25.1 -> 28.4 GB, peak 75.9 GB | the handoff is built here |
| `PerFileRescoring` | 5:31:35 | 28.2 -> 28.9 GB (+4 MB/file) | LEVEL |

## Streaming implementation status (2026-08-04, rebased onto #4528)

`OSPREY_STAGE6_STREAM_SURVIVORS` (default ON) makes Stage 6 refill each file's survivors
from its `.scores.parquet` + 1st-pass sidecar just before rescoring it, drop them after its
reconciled parquet is written, and rebuild the buffer once at the end for Stage 7.

**The opt-out is verified inert.** `OSPREY_STAGE6_STREAM_SURVIVORS=0` passes all five
Stellar legs with the exact golden blib, so every divergence below belongs to the new path
and the resident path remains the A/B oracle the design calls for.

### Fixed, with evidence

1. **Rehydrate overlaid onto a released buffer.** A resume that re-ran Stage 5 reached
   `PerFileRescoreTask.Rehydrate` with empty lists and overlaid the reconciled parquets onto
   nothing, producing a 196 KB blib. Refill first. This is what made `mode2` green.
2. **The rescore's score/q reset was applied at the wrong point.** A fresh
   `OverlayRescoredEntries` sets every rescore target to `Score=0, q=1.0` for the 2nd pass to
   fill in; that reset lives only in memory (the reconciled parquet stores boundaries and
   features, not scores, and `OverlayReconciledIntoBuffer` documents that it preserves
   1st-pass Score/q). The rebuild must reapply it - and BEFORE the overlay, because the
   overlay appends gap-fill rows and re-sorts, which shifts the planner's positional indices.
   Applying it after shifted the reset onto neighbouring rows (visible as adjacent rows 941 /
   942 swapping values in the Stage-6 dump).
3. **The rebuild must not canonicalize.** A fresh rescore appends gap-fill at the END and
   never re-sorts; sorting moved those rows into EntryId order.

After 2 and 3, the Stage-6 buffers match on every dumped column, the reconciled parquets are
semantically identical (`pyarrow` column-wise, metadata included), the 1st-pass sidecars are
byte-identical, and the 2nd-pass `score` and `run_prot_q` columns match exactly.

4. **The rebuild dropped the rescored `ScanNumber`.** `OverlayReconciledIntoBuffer` copies
   boundaries, area and features but NOT `ScanNumber`, and a MOVED peak's scan changes
   (the fresh rescore replaces the buffer entry with the newly scored one). The pass-2
   frozen-model override is looked up by `(EntryId, Charge, ScanNumber)` in
   `Pass2FdrSidecar`, so every moved peak missed it: **110,541 of 994,509 survivors got no
   override**, the `ov != scores[i]` discriminator in `StreamingFdr` saw `changed=0` instead
   of `changed=110,646`, `changedBaseIds` stayed empty, those peaks never earned a fresh
   run q, and they were reported on the stale pass-1 q their moved peak no longer justified.
   Reported spectra 31,583 against the golden 29,364. Copying the reconciled `ScanNumber`
   restores `changed=110,646` and the reported count to exactly 29,364.

### Where it stands

Stellar, streaming ON by default: **mode1 8 issues, mode3 3, mode2==straight 3** (from
71 / 29 / 24). mode4 and mode2 cache-hits green. Streaming OFF still passes all five legs
with the exact golden blib, so the oracle is intact.

### Open: NRunsDetected off by one on 95 precursors

`OspreyExperimentScores.NRunsDetected: 95/29364 rows differ (golden='2' run='3')` - the
streamed arm sees a precursor detected in one MORE run than the golden. Correlated counts:
the streamed arm emits 994,614 reported survivors where resident emits 994,899 (-285).

**Gap-fill has been RULED OUT** - and an earlier guess in this file was wrong, so read the
measurement rather than the guess:

* The resident buffer has **994,899 rows and 994,899 distinct `(file, entry_id)` keys -
  zero duplicates**. A fresh rescore never leaves two rows for one precursor in one file,
  so "append gap-fill unconditionally" is wrong and so is "overwrite duplicates"; both were
  tried and neither matched.
* Capturing the gap-fill rows in memory during each file's rescore and replaying them
  verbatim was tried, and measured identical to the persisted tail replay (8 / 3 / 3). It
  was then REVERTED, and must not be reintroduced: (a) under `--task PerFileRescoring` each
  file is rescored in its own process, so carried rows are gone by the time the merge node
  needs them - the mechanism cannot work on HPC, which is the path this whole change exists
  to adopt; (b) it is itself an O(files) resident term, ~270 MB at 163 files (gap-fill runs
  2.7k-25.4k targets per file there, against 390 rows TOTAL on the 3-file Stellar set the
  "cheap to keep" claim was based on). Read the tail from the reconciled parquet instead:
  the fresh append order survives on disk because those rows are written after the
  originals.

So the residual is NOT in which rows exist. Both arms build the same rows; the streamed arm
REPORTS 116 (peptide, file) observations the golden does not, on 95 precursors.

### GREEN 2026-08-04: `regression.ps1 -Dataset Stellar` passes all five legs

With `OSPREY_STAGE6_STREAM_SURVIVORS` ON by default: mode1 (vs golden), mode3 (HPC chain ==
straight), mode4 (warm), mode2 (resume cache hits), mode2 (resume == straight) all PASS.

The last defect was the gap-fill append. Three mechanisms were tried; only the third is
correct, and the two failures are worth keeping because both looked right:

1. **Carry the rows out of the rescore in memory.** Cannot work on HPC - `--task
   PerFileRescoring` rescores each file in its own process, so nothing held there reaches
   the merge node. Also an O(files) resident term (~270 MB at 163 files), the shape this
   change exists to remove.
2. **Replay the reconciled parquet's appended tail by row index.** Looked exact - the
   parquet does write gap-fill rows after the originals - but `LoadFullFdrEntries` does NOT
   preserve parquet row order, so the "tail" is not the gap-fill rows. Measured on Stellar
   file 20: it appended 36 rows that were not gap fill and dropped all 133 that were
   (`133 entry_ids only in resident, 36 only in streamed`, no duplicates either side).
3. **Append from the target list in `reconciliation.json`** - what the resume overlay
   already did. Same source, works on a merge node, holds nothing. Both paths now share it.

The lesson worth carrying: the buffer's gap-fill rows are recoverable ONLY from the
persisted target list. Row order in a parquet read-back is not a contract.

### First memory measurement (Stellar, 3 files) - the mechanism removes the right term

```
resident   [MEM reconciliation-floor] managed_heap=0.84 GB   29,364 spectra
streamed   [MEM reconciliation-floor] managed_heap=0.64 GB   29,364 spectra
           [MEM stage5-handoff-released] managed_heap=0.64 GB (after planning)
```

The floor drops 0.20 GB, and the survivor pool it sheds is 994,509 entries x ~208 B =
0.207 GB - i.e. the reduction is EXACTLY the term the change targets, with byte-identical
output. Three files is far too small to project from, so this is a mechanism check, not a
scale result.

**Use 40 files, not 20 or 163** (established 2026-08-04 by perfviz over the existing runs).
`tdp43-40files-delivered` is already a `--task FirstPassFDR` run and shows the term:
`134,395,432 -> 13,398,508` survivors = **~2.8 GB** of resident pool against a ~4.4 GB
library floor, so the signal is ~40% of the floor. Stage 5 alone is 34 min there. The other
seven 40-file runs are `PerFileScoring` only and show nothing of Stage 5/6.

Because `reconciliation-floor` fires BEFORE the rescore loop, the measurement needs Stage 6
to START, not finish - kill each arm when the line prints. ~70 min for both arms against
~7 h for the 163-file pair. Full command, and the mandatory
`OSPREY_VERSION_OVERRIDE=26.1.1.211` pin for the `Stages1to4` link source, are in the
handoff.

### MEASURED 2026-08-04: the Stage 6 plateau is gone at 40 files

`Run-Tdp43.ps1 -NumFiles 40 -PickLda -Pass2Mode protein-compact -Fresh -LinkFrom
Stages1to4-picklda`, streamed default, `OSPREY_LOG_MEMORY=1`. Same cohort as the
`tdp43-40files-delivered` baseline - compaction `134,395,432 -> 13,398,508 entries
(272,526 passing base_ids)` matches it exactly, so the discovery set is unchanged.

| probe | managed heap |
|---|---|
| `library-resident` (6.32 M entries) | 4.38 GB |
| `stage5-start-live` | 4.41 GB |
| `stage5-handoff-released` (survivors dropped after planning) | **4.53 GB** |
| `reconciliation-floor` (Stage 6 entry) | **4.57 GB** |

Stage 6 enters the rescore **0.19 GB above the bare library floor**. The resident arm carries
the whole survivor pool at this point: 13,398,508 x ~208 B = **~2.8 GB**, which is what the
~7.2 GB prediction was made of. The term is simply absent.

`perfviz.py` over the Stage-6-ONLY slice (log split at `PerFileRescoring:starting`; 8 files,
14 min) - which is where floor drift has to be judged, per `memory-band-guide.md`:

```
managed MB : peak 14.5 GB   floor 4.8 -> 4.8 GB   drift -0.00 GB   -0 MB/file   LEVEL
total MB   : peak 31.7 GB   floor 24.2 -> 14.0 GB  drift -10.29 GB            FALLING
```

Per-file sawteeth all return to the SAME floor: no step-up, no plateau. Compare the 82-file
resident run Brendan captured (`ai/.tmp/` image, peak 50.7 GB), where Stage 6 rises to a
40-50 GB band and stays there for the rest of the run.

**What this is NOT**: a paired A/B. Only the streamed arm was run at 40 files, so the ~7.2 GB
resident figure remains a prediction rather than a measurement. What is measured is that the
O(files) term is absent and the Stage 6 floor does not drift. The `=0` arm's byte-identity is
gated separately by `regression.ps1` on Stellar.

**Still to measure - OPEN, not superseded:**
* **The 40-file paired A/B** (default vs `OSPREY_STAGE6_STREAM_SURVIVORS=0`). This is still the
  actual claim of this TODO and it has NOT been run: only the streamed arm was measured, so the
  ~7.2 GB resident figure is a prediction. An earlier version of this section filed it under
  "superseded", which it is not - the single-arm run answers "is the plateau gone" but not "by
  exactly how much against the resident arm on the same box".
* ~~Stage-5-only re-measure at 163 files~~ - DROPPED by Brendan 2026-08-04: the 40-file run
  answers whether the plateau is gone, and 163 costs ~75 min to confirm it.

**Superseded plan below** (kept for the baseline numbers it cites):
* 40-file A/B, default vs `OSPREY_STAGE6_STREAM_SURVIVORS=0`, comparing the
  `reconciliation-floor` lines (and the blib if allowed to finish).
* Stage-5-only re-measure at 163 files via `-LinkFrom` (~75 min) against the baseline:
  `FirstPassFDR` 4535.6 s wall, 90.2 GB private / 75.9 GB managed peak, 28.17 GB floor.
  Prediction to test: because the churn amplitude is coupled to the live set, the PEAK
  should fall by roughly 2.4x the reduction in the hold, not 1x. If it falls only ~1x, the
  coupling model is wrong and the planning loop needs its own allocation fix.
* `-Dataset All` before merge, and the TeamCity Perf/Regression gate on `pull/<N>` (ASK
  Brendan first).

### Measured 2026-08-04: the residual was 116 LOST per-run observations (now fixed)

Direct resident-vs-streamed blib comparison (`ai/.tmp/who_extra.py`), which is more
reliable than reading the harness's run-vs-golden labels - an earlier note in this file
called this "over-reporting", and that was the wrong sign:

```
resident observations 88,092   streamed 87,976
only in streamed: 0     only in resident: 116
by file: _22 47, _20 37, _21 32
95 distinct precursors affected (74 lose one observation, 21 lose two)
all 95 still reported elsewhere in streamed
```

So nothing is invented and no precursor disappears; the streamed arm simply fails to report
116 (precursor, file) observations. That is a RUN-LEVEL q gate outcome - those entries exist
in both buffers with identical scores, so their run q must come out worse in the streamed
arm. It explains every mode1 issue: `RefSpectra` count matches, only `copies` /
`NRunsDetected` move, on exactly 95 rows.

**Next probe**: for the 116, resolve their entry_id (join the blib peptide back through the
library or the reconciled parquet's modseq column), then read `run_pep_q` for those ids from
both arms' `.2nd-pass.fdr_scores.bin` (`ai/.tmp/diff_pass2_join.py` already loads them).
Two outcomes, two different defects: if the streamed q is worse, the competition population
for that file differs; if the q is EQUAL, the loss is downstream of the sidecar, in the blib
write's per-run selection. Do not guess between them - the sidecars are on disk in
`ai/.tmp/ab4526/d8_res` and `d8_str`, so this costs no run.

### Superseded probe (kept for the reasoning)

Take the 116 `RetentionTimes` keys present only in the run and classify
them - are they gap-fill targets, moved peaks, or ordinary survivors? Then pull those exact
entries out of both arms' `.2nd-pass.fdr_scores.bin` (join on entry_id;
`ai/.tmp/diff_pass2_join.py`) and compare their q against the 1% gate. That says whether
the streamed arm gives them a BETTER q or merely fails to suppress them, which are
different defects. `ai/.tmp/ab2.ps1` is the A/B harness - use FRESH output dirs each run or
the second arm silently warm-resumes and produces no Stage 6 at all.

### Superseded: the 2nd-pass q divergence

Stellar straight-through reports **31,583** spectra against the golden **29,364** (chain leg
= 29,364, i.e. the resident behaviour). Joined on `entry_id`, per file:

* `entry_id` sets identical, `score` identical, `run_prot_q` identical
* `run_pep_q` differs on 170,677 of 331,623; `exp_pep_q` on 242,672; both directions
* passing at 1%: run `A=27,057 B=26,687`; experiment `A=30,433 B=32,744`

Identical population and identical scores producing different q means the divergence is
**order- or selection-dependent inside Stage 7**, not a lost/extra entry. The 2nd-pass
sidecar still reports `entry_id order identical: False`, so buffer order is the leading
suspect - but note the Stage-6 dump is written sorted by `entry_id` within file (verified
monotonic), so it CANNOT witness order. Any further order comparison needs the sidecar, not
the dump.

Replaying the gap-fill append from the reconciled parquet's appended tail (rather than by
ascending `TargetEntryId`) is in, and moved the passing count (94,749 -> 94,624) without
closing the gap.

**Next probe**: instrument `Pass2FdrSidecar.ComputeAndPersist` to log the population it
actually competes - how many entries it scores, how many are on- vs off-stratum, and in what
order - for the resident and streamed arms. That distinguishes "same set, different order"
from "different set", which the current evidence cannot. A/B harness:
`ai/.tmp/ab-stage6.ps1`; comparators `ai/.tmp/diff_pass2_join.py`, `diff_parquet.py`,
`diff_dump.py`.

## Session log - 2026-08-04

Rebased onto `e7b5a917ba` (#4528, protein-compact now the default). Took the streamed path
from 71/29/24 regression issues to **all five Stellar legs PASS**, by finding four distinct
divergences from the resident path - the decisive one being the rescored `ScanNumber`, which
the pass-2 frozen-model override is keyed on. First memory measurement taken (floor
0.84 -> 0.64 GB, the survivor pool exactly). Then `/code-review max` found 15 findings; two
correctness defects fixed, six open. **Branch is NOT PR-ready** - see the findings section
below.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260803_osprey_bounded_stage5_handoff.md` before starting work.

## Session log - 2026-08-04 (second session): review findings closed

All 13 open `/code-review max` findings fixed (itemized below). Gate after: **574/574 unit
tests, zero ReSharper inspections, `regression.ps1 -Dataset Stellar` all five legs PASS** with
the byte-identical golden blib (25,407,488 bytes on straight-through, HPC chain and resume).

Two of the fixes changed behaviour on paths the golden covers, and both were deliberate
experiments rather than safe refactors:

* **Gap-fill append order** was unified by changing the COLD path (sort the appended block by
  EntryId) rather than by teaching the rebuild to reproduce cold's emit order. The emit order
  is a function of which targets CWT hit, which is persisted nowhere, so the rebuild could
  never have matched it - the divergence was unfixable from the rebuild side. **No golden
  moved on ANY dataset** (`-Dataset All`: Stellar, StellarLibDecoy, StellarGenDecoyEntrap,
  Astral, including the mode1b diagnostics comparison), so the relative order of gap-fill rows
  among themselves does not reach the output; what matters is only that they sit at the END,
  where the planner's positional indices need them.
* **The rescored `ScanNumber` / `CoelutionSum` carry became unconditional**, removing the
  `reproducingFreshRescore` flag. mode2 and mode4 stayed green against the exact golden, which
  says the resume paths had been reconstructing buffers with stale scan numbers and nothing
  downstream had been sensitive enough to notice. Under protein-compact it would have been.

**Deliberately NOT done**: the 163-file `-LinkFrom` re-measure (Brendan, this session - the
40-file run answers whether the plateau is gone, and 163 costs ~75 min for a confirmation).

### The 70-minute repro cycle needs a re-stamped Stage 1-4 staging dir

The whole point of `-LinkFrom D:\test\osprey-runs\tdp43-plasma-ev\runs\Stages1to4` is to skip
Stages 1-4 and get a Stage 5+6 measurement in ~70 min. **That staging dir no longer resumes**,
and the failure is silent: the run just starts scoring file 1/40 and takes hours.

Cause is the one this TODO already predicted from #4484: `cb9b68c60` made the pick model
participate in the resume validity key UNCONDITIONALLY (`OspreyTask.ValidityKey` ->
`PickValidityKeySuffix`), so every `.osprey.task` written before it is missing
`;pick=lda;pickmodel=none` and is invalidated exactly once.

Fix, and it is a one-liner per stamp rather than a re-run:
`ai/scripts/Osprey/TDP43/Repair-Stages1to4Stamps.ps1` builds
`runs\Stages1to4-picklda` - HARD LINKS for the parquet / calibration artifacts (no copy, no
disk cost) and patched COPIES of the 326 `.osprey.task` stamps with the suffix appended. Link
from that dir instead. Do NOT patch `Stages1to4` in place: its artifacts are hard links shared
with the 163-file picklda run, so an in-place edit rewrites that run's provenance too.

Appending the term is recording what is true, not defeating the guard - the staged artifacts
are byte-identical (same size and mtime) to the `tdp43-163files-...-picklda` run's, so they
really were picked by the LDA model.

Also note `-NumFiles`, not `-Files` (the older handoff had this wrong), and `-Task` already
exists on the runner - the "runner support still needed" item further up this file is stale.

## `/code-review max` findings (2026-08-04) - all closed in the second session

15 findings on `origin/master...HEAD`. Stellar green does NOT clear these: most are on
paths Stellar never exercises (write failure, resume with Stage-5 invalidated, multi-row
EntryId, files with both CWT and forced gap fill).

**Fixed:**
- [x] `RescoreOneFileStreamed`'s `finally` cleared unconditionally, defeating
      `RescoreOneFile`'s `if (wroteReconciled)` gate. On a failed/no-op reconciled write
      those arrays are the ONLY copy of the rescore; the rebuild then restored 1st-pass
      values and the precursors vanished from the report on a warning.
- [x] `CoelutionSum` was not carried through the overlay - same omission class as the
      ScanNumber bug. Cold replaces it, it IS persisted and loaded, Stage 7 reads it off
      the buffer (`PercolatorEntryBuilder` basic-feature fallback, best-per-precursor), and
      `ReleaseRescoredPayload` then nulls Features, destroying the only fresh copy.

**Correctness - ALL FIXED 2026-08-04 (second session), Stellar green after:**
- [x] `ResetRescoredTargets` resets EVERY planner index in EVERY file, but the reset it
      reproduces only ran for files that reached scoring. `TryResumeRescoredFile` (per-file
      resume skip) and `TryAssembleRescoreTargets` returning false after `combinedTargets`
      is populated both return earlier. Streamed zeroes those; resident leaves real q. Under
      protein-compact an off-stratum survivor keeps its q, so they drop out - the mirror of
      the 31,583-vs-29,364 over-report. Its `idx >= entries.Count` guard also silently
      swallows the one detectable symptom of a misaligned rebuild.
      **Fix**: `RescoreOneFile` now reports whether it reached the scoring engine; the
      per-file flags come back out of `ExecuteRescore` as a `rescoredFiles` set and the reset
      applies to exactly those. The out-of-range index now THROWS with the file and the two
      counts - the fresh rescore would have thrown `IndexOutOfRange` on the same index.
- [x] Both fixes are applied to only ONE of three callers of the shared overlay. `Rehydrate`
      and `TryResumeRescoredFile` pass `reproducingFreshRescore: false` and never reset, so
      cold and resume provably differ.
      **Fix**: the parameter is GONE. Carrying the rescored `ScanNumber` / `CoelutionSum` is
      what "reproduce the buffer a rescore left" means, and all three callers want that; the
      flag only encoded which caller had been fixed. Making it unconditional left mode2 and
      mode4 green with the exact golden blib, so the resume paths were carrying stale values
      that nothing had yet been sensitive enough to catch.
- [x] Gap-fill ORDER still differs: cold appends all CWT-pass rows then all forced rows, each
      in scoring-emit order; the rebuild appends by ascending `TargetEntryId`.
      **Confirmed real at scale, and Stellar cannot see it**: at 163 files EVERY file emits
      both kinds (file 1: 10,965 CWT + 2,361 forced), so the two buffers diverge on every
      file of a real cohort.
      **Fix**: at the root rather than in the rebuild. The emit order depends on which targets
      CWT happened to hit, which is recorded NOWHERE on disk, so no rebuild could ever
      reproduce it. `RunGapFillTwoPass` now collects both passes and appends the block sorted
      by EntryId - the one order both paths can produce. Still appended at the END, which is
      the property the planner's positional indices actually need. Golden did not move.
- [x] The `entry.ScanNumber = r.ScanNumber` carry uses byId's FIRST-wins row, so if a file
      holds >1 survivor per EntryId (two isolation windows) they collapse onto one scan and
      become duplicate pass-2 identities.
      **Fix**: `byId` keeps ALL rows per EntryId in parquet order and the overlay pairs them
      POSITIONALLY with the buffer's rows for that id.
      **This was initially fixed on the WRONG ARM, and `/code-review max` caught it after the
      PR was opened.** The survivor rows come from `.scores.parquet`, written after Stage 4's
      `DeduplicatePairs`, so they cannot duplicate - the arm that got the positional fix is the
      one that never needed it. The GAP-FILL arm is where duplicates actually arise:
      `RunGapFillTwoPass` calls `RunCoelutionScoring` with neither `DeduplicatePairs` nor
      `DeduplicateDoubleCounting` (verified: both are called only from `PerFileScoringTask`),
      and `ScoreWindow` admits a candidate per isolation window, so one target in two
      overlapping windows emits two stubs. Cold appended both; the rebuild took `gapRows[0]`
      and dropped one, silently removing a survivor from the buffer Stage 7 competes over. The
      gap-fill append now takes every row for the target. There is no finer stable key available
      - Charge does not separate two isolation windows and ScanNumber is the field the rescore
      moves - so positional pairing is the most specific correspondence the data supports.
      The old comment claiming "at most one row per EntryId after compaction" was wrong:
      compaction filters by base_id, it does not collapse rows.
- [x] `OverlayReconciledIntoAllFiles` overlays any reconciled parquet that merely EXISTS.
      **Fix**: both it and `ReconciledParquetOnDisk` now ask `PerFileResumeDriver.IsCurrent`
      against the task validity key - the same question the rescore's own per-file gate asks,
      so the two cannot disagree about whether a parquet is usable.
- [x] The `!didPlan && ...` no-op arm now behaves differently with streaming on vs off.
      **Fix**: on that arm the RESIDENT path does nothing at all - it leaves the buffer at its
      `CompactedEntries` state. So the streamed path now does exactly one thing, refill what
      FirstJoin released, and no longer overlays. Overlaying applied Stage-6 boundaries the
      resident arm never applies, which is precisely what disqualified `=0` as an oracle here.

**Robustness / perf - ALL FIXED:**
- [x] `throw` inside `Parallel.For` loses the actionable message. **Fix**: per-file load
      errors are collected into an array and thrown AFTER the loop, so the message naming the
      file and the missing artifact survives.
- [x] Per-file survivor reload multiplied the transient by file parallelism (~700 MB/file at
      163 files). **Fix**: the refill is serialized behind a lock. The rescore is 2-2.5
      min/file against seconds for the load, so the wall-clock cost is a rounding error and
      the transient stays at 1x instead of Px.
- [x] Cold runs fat-decoded every reconciled parquet only to null the payload 16 lines later.
      **Fix**: `LoadFullFdrEntries(path, scalarsOnly: true)` skips the 21 PIN feature columns
      and the four blob columns. Every scalar field is set exactly as the full read sets it,
      and every caller of the overlay releases the payload immediately, so nothing loses data.
      **Only HALF of that finding is fixed, and an earlier version of this line wrongly claimed
      both.** `scalarsOnly` narrows COLUMNS within one read, and it applies to
      `.scores-reconciled.parquet`. The other half - "`.scores.parquet` goes from 1 read per run
      to 3" - is an OPEN count of distinct opens, still 3 on the cold streamed default
      (`FirstJoinTask` survivor reload, the per-file refill in `RescoreOneFileStreamed`, and the
      end-of-loop `MaterializeAllSurvivors`, whose `Count > 0` skip never fires because the
      loop emptied every file). That is the read amplification the streaming buys the memory
      with; it is a deliberate trade, not a fixed defect.
- [x] `MaterializeAllSurvivors` and `OverlayReconciledIntoAllFiles` were unreported
      sequential loops. **Fix**: both report per-file progress.
- [x] No `ResidentPaths` token, guard, test, `ValidityKey` suffix, or docs. **Fix**: all five.
      `ResidentPaths.COMPACTED_ENTRIES_BUFFER` (`compacted-entries-buffer`);
      `PerFileScoringTask.Stage6ResidentHandoffGuardError` called from FirstJoin at the
      release decision, BEFORE the release, so a refused run fails in seconds instead of
      OOMing hours into Stage 6; `ResidentPoolGuardTest` pins the new token and covers the new
      guard; `;stage6stream=0` joins the Stage 6 validity key (EMPTY on the streamed default,
      so no existing output directory is invalidated); env-var reference section in
      `ai/docs/osprey-development-guide.md`.
      **Note for review**: this GROWS `KNOWN_UNFIXED`, which the ratchet says must only
      shrink. The justification is in the constant's doc comment - it names a path that was
      previously UNNAMED rather than re-admitting a fixed one, because the old guard's
      invariant stops at the compaction line and this buffer is built after it.
- [x] **`OSPREY_ALLOW_UNFIXED_RESIDENT` now takes a LIST** (comma/semicolon separated), and
      `regression.ps1` mode 2 ADDS its token instead of replacing the caller's.
      **Found by running the oracle**, not by reading: `-Dataset Stellar` with
      `OSPREY_STAGE6_STREAM_SURVIVORS=0` aborted mode 2 on the guard I had just added, because
      mode 2 overwrites `OSPREY_ALLOW_UNFIXED_RESIDENT` with `mdiag-full-resume` and only ONE
      path could ever be named. The A/B that proves this change bounded could not be run.
      The single-value limit was a pre-existing hole - any run tripping two known-unfixed paths
      hit it - that the new token merely exposed. A list keeps the property that matters (every
      admitted path named individually; nothing rides along unnamed), while a single value only
      ever prevented honest work.
      **A first attempt at diagnosing this was wrong**: gating the guard on `_didPlan` would
      NOT have helped, because the resume log shows planning DOES run on the mode-2 resume
      (`Planning reconciliation across 3 file(s)`, `Wrote reconciliation.json`). The fix came
      from reading the failure, not from the hypothesis.
- [x] 5th copy of the canonical comparison and the 8-field reset. **Fix**: `FdrEntry.CANONICAL_ORDER`
      and `FdrEntry.ResetScores()`. Note the repo's `TestNoUnstableSort` guard requires an
      inline `// Array.Sort OK: <reason>` at each call site, and the reason genuinely differs
      per site (ParquetIndex unique per row vs EntryId unique within the gap-fill block).
- [x] **False claim corrected in the code**: the comment blaming `LoadFullFdrEntries` for not
      preserving parquet row order is gone. It DOES preserve it. The tail replay failed
      because `StreamReconciledScoresParquet` MERGES gap-fill rows into canonical
      (entry_id, charge, scan) position, so there is no tail to replay.

## Gate status 2026-08-04 (end of second session)

| gate | result |
|---|---|
| `Build-Osprey.ps1 -RunTests -RunInspection` | 574/574, zero inspections |
| `regression.ps1 -Dataset Stellar` (streamed default) | all five legs PASS, golden blib 25,407,488 B |
| `regression.ps1 -Dataset Stellar` with `OSPREY_STAGE6_STREAM_SURVIVORS=0` + token | all five legs PASS, same golden blib - **the oracle is intact** |
| 40-file Stage 6 memory measurement | floor LEVEL, plateau gone (above) |
| `regression.ps1 -Dataset All` | **PASS** - Stellar, StellarLibDecoy, StellarGenDecoyEntrap, Astral; incl. mode1b diagnostics + FDR sanity bounds. Re-run AFTER the gap-fill duplicate fix and still PASS |
| `/code-review max` | re-run at end of session - found the gap-fill duplicate defect, fixed in `cdbed2f0ef` |
| TeamCity Perf/Regression | build 4121676 on `pull/4530` - **SUCCESS** (Stellar + Astral + perf leg) |

**`/code-review max` needs the developer to ASK for it, once.** An unprompted model invocation
is refused (`disable-model-invocation`), but the same call succeeds after the developer asks
for it in the session - so the earlier handoff's "self-launchable" is half right, and the
correction in an earlier draft of this file ("cannot be launched by the model") was too strong.
The practical rule: the model cannot decide to run it on its own, so ASK the developer to
request it rather than reporting it as unavailable.

**One unexplained event, recorded rather than dismissed**: an oracle-leg run aborted with
`0xC0000005` (access violation) in the straight-through leg, and the identical command passed
on the next invocation. It happened seconds after a force-kill of the 40-file Osprey process,
so a stale handle is plausible but UNPROVEN. If it recurs, it is real.

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: Osprey.Test (guard/token pinning) + `regression.ps1` (byte parity)
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

Two distinct verifiers are needed, because the change has two halves:

1. **`ResidentPoolGuardTest`** pins `ResidentPaths.KNOWN_UNFIXED` exactly, so adding
   `compacted-entries-buffer` forces a deliberate test edit - that is the ratchet working.
   Extend it to cover the post-compaction trigger, so a future unnamed post-compaction
   resident structure fails a test rather than passing silently.
2. **Byte parity** is `regression.ps1` (`-Dataset Stellar` mode1/2/3, `-Dataset All`
   before merge) against the committed golden, which must not move. The memory claim
   itself is not unit-testable; it is the 20-file A/B plus the ~75 min Stage-5-only
   `-LinkFrom` re-measure at 163 files.

## Open questions

1. ~~Does the `percolator` pass-2 retrain need the whole rescored pool?~~ **Moot** - pass-2
   Percolator is being removed (see "The merge node" above). Every replacement candidate is a
   frozen-model mode and those stream one file at a time. Do not preserve `percolator`
   viability as a design constraint.
2. ~~What is the 28 GB actually MADE of?~~ **Answered above** - bare objects, all six
   reference fields null. No payload fix available.
3. Should the guard's error text distinguish "unnamed path" from "named but not allowed" for
   post-compaction structures, or is one message enough?
4. ~~How much of the survivor set is the `protein-compact` stratum?~~ **Answered above** -
   84% of entries. Follow-up lever, not first-PR scope.

## Progress Log

### 2026-08-05 - Merged

PR #4530 merged as commit `b554ce6f0d`. Stage 6 no longer holds every file's
post-compaction survivors: it refills one file at a time from that file's `.scores.parquet`
plus its 1st-pass sidecar, drops them once the reconciled parquet is written, and rebuilds
the buffer once at the end for Stage 7. The resident handoff survives behind
`OSPREY_STAGE6_STREAM_SURVIVORS=0` as the byte-identity oracle, and is now the NAMED
`ResidentPaths` path `compacted-entries-buffer` rather than a silent one, with the guard
checked at the release decision so a refused run fails in seconds instead of OOMing hours
into Stage 6.

Measured at 40 files: Stage 6 enters the rescore at a 4.57 GB floor, 0.19 GB above the bare
library floor, and the Stage-6-only slice shows the managed floor LEVEL (4.8 -> 4.8 GB,
drift -0.00 GB). The 82-file resident comparison rises to a 40-50 GB band and stays there.

Gates: 574/574 unit tests, zero inspections; `regression.ps1 -Dataset All` PASS on all four
datasets (re-run after the final fix); the same gate PASS with the resident arm forced, so
the oracle is intact; TeamCity Perf/Regression build 4121676 SUCCESS on `pull/4530`.

Two defects were found AFTER the PR opened and fixed in `cdbed2f0ef`, both by
`/code-review max` rather than by the green gates: the duplicate-EntryId fix had been
applied to the survivor arm, which cannot duplicate, while the gap-fill arm - the only one
that can, since neither of its scoring passes runs the Stage 4 dedup - still took the first
row and silently dropped a survivor; and the scalar-only overlay was still assigning payload
fields that were now always null. A third fix landed in `ai/`: the Stage 1-4 re-stamp script
committed earlier that day would delete its own source directory if `-Destination` resolved
to `-Source`, and report success.

**Deferred, deliberately, and still open on #4526:**

* The 40-file PAIRED A/B (default vs `OSPREY_STAGE6_STREAM_SURVIVORS=0`) was never run - only
  the streamed arm was measured, so the ~7.2 GB resident figure remains a prediction. What is
  measured is that the O(files) term is absent and the floor does not drift.
* The `.scores.parquet` read count is 3 per run on the cold streamed default, up from 1. That
  is the trade streaming buys the memory with, not a defect, but it is real and unaddressed.
* The `protein-compact` stratum is 84% of the survivor entries and its consumer already
  streams one file at a time; whether stratum-only survivors need to be Stage-6 entries at
  all is a ~6x term on the same buffer.
* The 163-file Stage-5-only re-measure was dropped: the 40-file run answers the question.
