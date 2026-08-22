# TDP-43 163 files: pickrun3 + our library vs the 2026-08-16 baseline

## Branch Information
- **Branch**: none - measurement run, no code change
- **Created**: 2026-08-21
- **Status**: Active (result recorded; ONE decision open)
- **Module**: `osprey`
- **Companion**: `TODO-20260821_tdp43_pickrun3_ourlib-stats.html` (the tables, formatted)

## Objective

First test of the pickrun3 training selection on TDP-43, and the first run of this dataset
with our own library. Two variables move at once against the 2026-08-16 baseline,
deliberately: "our best current configuration vs. what we had", not an ablation.

## The run

```
D:\test\osprey-runs\tdp43-plasma-ev\runs\tdp43-163files-libdecoy-r1.0-protein-compact-pickrun3-ourlib
```

2026-08-21 17:59:56 -> 2026-08-22 13:00:32, **exit 0, 1141 min, single pass**. Osprey
26.1.1.233 (`5acc2dd24c`), pinned snapshot `D:\test\osprey-runs\_bin\26.1.1.233-20260821`.
libdecoy r=1.0, protein-compact, threads 30, `--fdrbench-pass 2`, `--model-diagnostics`,
library `target+decoy+entrapment-20260817`.

The baseline it is measured against crashed in `BlibWriter..ctor` after 1031 min (exit 1) and
needed a separate 29-minute `--task SecondPassFDR` recovery node. **That recovery RELOADED the
straight-through pass-2 result rather than recomputing it** (`Reloaded the persisted
protein-compact stratum (390627 base ids)`, 44 s against 22 min for the real competition), so
the baseline's `out.model-diagnostics.html` carries straight-through protein-compact numbers
and is a sound comparator. This resolves the open question the predecessor handoff raised;
do not re-derive it.

## RESULT - matched true FDP, experiment scope

| pass | baseline @0.750% | ours @0.750% | delta |
|---|---|---|---|
| 1 | 28,231 | 29,525 | **+4.58%** |
| 2 | 35,156 | 38,300 | **+8.94%** |

Full tables (n@1% q, FDP at that q, @0.650/0.750/1.000%) in the stats HTML companion.
Peptides seen in >= half the runs: 9,121 -> 10,095, **+10.68%**.

**Quote the matched-FDP column.** The pass-1 Percolator target count moved +11.06% and the
matched-FDP gain is +4.58% - the nominal figure overstates by ~2.4x, because this arm also
spends more error at the cutoff (0.9560% vs 0.9128%).

## THE OPEN DECISION

On SEA-AD the sampler ALONE gave +24.7% at matched FDP and our library ALONE +10.5%. Here the
two TOGETHER give +4.58% / +8.94%. Two independently positive changes composing to less than
either is the finding.

The predecessor handoff's rule: "only if the result does NOT look better do we do an A/B."
The result IS better at both passes, so by the literal rule this is recorded and closed. But
the magnitude is roughly a fifth of what the SEA-AD numbers imply, which is the case for
spending another ~19 h on the split (baseline's DELIVERED library on pickrun3, isolating
sampler from library). `-LinkFrom` does not help across a library change - Stage 1-4 artifacts
are library-specific - so it is a full run.

**Brendan's call. Not started.**

## Two harvest gates FAILED

1. **Reporting cadence** - 8 gaps >= 30 s (max 39 s) against a gate of 0. The baseline had
   zero (max 29 s, itself one second under). **7 of the 8 are in SecondPassFDR**, the stage
   that just absorbed pwiz #4600's whole-run join. Consolidating the join into its consumer
   was right; the consumer now needs progress reporting inside the work it inherited. This is
   the first concrete item for "join tasks are the ones to watch, tune and control".
2. **Pass-2 FDP inflation** - against its own pass 1 the baseline inflates 1.77x
   (0.9128% -> 1.6118%) and this run 1.93x (0.9560% -> 1.8465%). Worse, not "no worse than
   known". Does not change the sign of the result (matched-FDP already corrects for it), but
   it is the one FDR-quality regression here.

## pwiz #4600 confirmed at 163 files

| PerFileRescoring | pre-#4600 | post-#4600 |
|---|---|---|
| final decile max | **44.3 GB** | **20.2 GB** |
| verdict | 2.34x RAMPS INTO A JOIN | 1.04x flat iteration |
| wall | 17,496.7 s | 17,316.8 s (-1.0%) |

The fan-out task is flat, and it is the only stage that beat the baseline on wall time while
carrying +11% more survivors and +20% more reconciliation actions. SecondPassFDR now ramps
from 20.3 GB where the baseline OPENED at 40.4 GB. **The global peak did not fall, it moved**:
52.2 GB in FirstPassFDR -> 54.2 GB in SecondPassFDR, 85% of the 63.7 GB box.

## Measurement hygiene - the two arms are NOT configuration-identical

The baseline ran with `OSPREY_LOG_MEMORY=1` (999 `[MEM]` probe lines, each forcing a
`GC.Collect()` pair); this run ran without it (0 lines). Nothing in either run's output
recorded that. Consequences: the baseline paid forced-GC wall time and was STILL faster, so
our +10.0% / +5.9% stage deltas **understate** our overhead; and its peaks were measured under
repeated forced collection, so our memory advantage is **understated** too.

Fixed in the runner (ai `7fddade`): `-LogMemory`, exported in both directions, in the banner
and as `logmem=` on the START/DONE lines, default off so timings stay clean.

Also excluded from timing: a self-inflicted CPU-contention window 18:08-18:22 (two ReSharper
inspections plus three `-WhatIf` runs) covering PerFileScoring files 2-7.

## Falsified prediction, recorded so it is not repeated

Mid-run I predicted **>= +24.7%** at matched FDP, reasoning that the training max-bias grows
with batch size (mean `coelution_sum` 1.19 at one file -> 5.75 at 82) and TDP-43 at 163 files
is double SEA-AD's batch. Actual **+4.58%**. The mechanism is real; the extrapolation was not.
The training-set separation halving (0.9% -> 0.4% of training targets at 1% FDR, SVM C=1 in
both) does confirm the mechanism is acting - it just does not scale the way I assumed.

## Related

- `ai/todos/completed/TODO-20260819_osprey_train_sample_default.md` - pickrun3 and its SEA-AD
  numbers
- `ai/todos/active/TODO-20260821_osprey_pipeline_error_detail.md` - the `BlibWriter` crash was
  unattributable because the terminal handlers logged `ex.Message`; fixed on a branch
- `ai/todos/active/TODO-20260821_osprey_fdrbench_pass_bitmask.md` - `--fdrbench-pass both`
  silently emits pass 2 only
