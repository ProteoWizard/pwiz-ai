# Osprey Stage 7: make the survivor pool non-resident through pass-2 scoring and protein FDR

## Branch Information
- **Branch**: `Skyline/work/20260826_osprey_stage7_stream_pool`
- **Base**: `master` (2a0b0069f6, i.e. after #4615)
- **Worktree**: `C:\proj\pwiz-work1` — `C:\proj\pwiz` is held by the open PR #4616
  (cache-only inputs), which a CHS plate run is field-validating
- **Created**: 2026-08-26
- **Status**: In Progress
- **GitHub Issue**: [#4486](https://github.com/ProteoWizard/pwiz/issues/4486)
- **Module**: `osprey`
- **PR**: (pending)

## Objective

Stage 7 holds the whole-run survivor pool (`RescoredEntries` =
`List<KeyValuePair<string, List<FdrEntry>>>`) resident from pool construction through
pass-2 scoring, protein FDR and the blib write. Measured post-GC on **257 CHS files**
(2026-08-25, `OSPREY_LOG_MEMORY=1`, `--task SecondPassFDR`):

| post-GC probe | live managed |
|---|---|
| `library-resident` | 4.19 GB (6,175,389 entries) |
| `stage7-inherited` / `stage7-pool` | **41.97 GB** |
| `stage7-fragments-released` → `stage7-blib-written` | 39.62 GB, **flat** |

**4.19 GB library + ~147 MB/file live** → ~78 GB at 500 files, ~152 GB at 1,000. Over any
64 GB box, and it is the last structural wall between here and the 500-file target.

## Read the issue's correction chain before planning — it has reversed twice

This issue is nine comments long and has been rescoped four times. Two reversals matter:

1. **"Stage 7 costs nothing per file" (2026-08-08) was wrong and was retracted the next
   morning.** It came from post-GC probes at substep BOUNDARIES; the pass-2 competition
   allocated and released its state *between* two boundaries, so both probes read the same
   number and the phase looked free. ~2.5 GB at 16 files (hidden), ~13 GB at 82 (dominant).
2. **The concrete lever named in that retraction is already fixed.** The three
   `Dictionary<(string, uint), double>` + `HashSet<(string,uint)>` returned by
   `StreamingFdr.ComputeFullPopulationPrecursorFdrStreaming` — 86.6 M observations, ~13 GB
   at 82 files — are gone: **#4554 ("Bounded and instrumented the Stage 7 join")** replaced
   them with `StreamedCompetitionState`, O(distinct base_id / entry_id), and moved the
   per-survivor loop into the caller's per-file emit pass. Verified in the tree today.
   `Pass2FdrSidecar` is therefore **not** the target; the pool itself is.

**Methodological consequence, which applies to my own measurements on this branch**: the
2026-08-25 table showing a flat 39.62 GB live floor is boundary-sampled too. It is evidence
that nothing *accumulates* after pool construction — not evidence that no phase allocates a
large transient inside itself. Anything I measure at a boundary inherits that blind spot.

## What is actually left

The pool is built before pass-2 scoring and released after the blib write, and **the peak is
set at construction**. So releasing it earlier buys nothing; the fix has to make it
non-resident *through* the two phases that assume a global view:

1. **`RunProteinFdr` → `ProteinFdrEngine.RunSecondPass`** — parsimony + picked-protein TDC
   over a global stratum. Genuinely whole-run, but the open question is whether it needs
   every observation or an O(distinct peptide/protein) aggregate.
2. **`Pass2FdrSidecar.ComputeAndPersist`** — its cross-file state is already bounded by
   #4554, but it still receives `perFileEntries` and writes per-file sidecars. Question is
   what it reads off the pool beyond what `StreamedCompetitionState` already answers.
3. **`WriteBlibOutput`** — already aggregate-shaped (`BuildBestExpPrecursorQ`,
   `BuildSharedBoundaries`, `BuildCrossFileObservations`) and it emits per file, so it is
   the natural second streamed pass. The issue notes it "could run on aggregates alone".

Target shape (and the standing constraint on FDR memory): **per-file compute → O(entries)
aggregate → per-file emit, with emission a SECOND streamed pass.** No `O(files × entries)`
structure in either direction.

**Documented trap — do not start here.** `entriesByPrecursor` holds
`List<KeyValuePair<string, FdrEntry>>`, references that PIN the pool, while its consumers
read only `observations.Count`, `obs.Key`, `EffectiveRunQvalue` and `ApexRt/StartRt/EndRt`
(~40 B). Converting it to a value struct unpins the pool but, while the pool is held anyway,
makes memory WORSE (16 → 40 B per observation). Step two, not step one.

## Tasks

- [x] **Split inherited-vs-built on the straight-through path** — DONE 2026-08-26, no run
      needed: the full 5-7 run's log already carries the probes. Stage 7 **builds** the pool
      itself in-process (see the progress log). The work is inside Stage 7, not upstream.
- [ ] Establish, per consumer, exactly which `FdrEntry` fields are read and whether that is
      expressible as an O(distinct) aggregate — protein FDR is the one that decides feasibility
- [ ] Record the two-pass design here BEFORE writing it
- [ ] Implement, gated on byte-identical output
- [ ] Post-GC memory A/B at ≥100 files, plus an in-phase sample so a transient cannot hide
      between two boundary probes (the 2026-08-08 error)

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: Osprey.Test / `regression.ps1` modes 1+3
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

Stage 7 feeds the blib, so `regression.ps1 -Dataset All` byte-identical is the correctness
oracle, and **mode 3 (HPC chain == straight) is the direct one** because the chain runs
`--task SecondPassFDR`. Byte-parity alone cannot catch a pool that is still resident, so the
memory property additionally wants a `ResidentPoolGuardTest` entry — the ratchet that
retired `mdiag-full-resume` (#4505), `resume-survivor-handoff` (#4536) and `hpc-merge`
(#4554-era) from `ResidentPaths.KNOWN_UNFIXED`.

## The bar: Stage 7 out of contention, not merely smaller (Brendan, 2026-08-26)

The goal is **to take Stage 7 entirely out of contention for the whole-run peak**, not to
shave the pool. At 257 CHS files the other stages measured (working set, from the CHS
large-scale TODO): FirstPassFDR **53.7 GB**, PerFileRescoring 16.5 GB flat, SecondPassFDR
**69.0 GB** — the peak, and past the 63.7 GB box, so it paged.

Live at Stage 7 today is 4.19 GB library + 0.147 GB/file = **41.97 GB at 257**. Out of
contention means landing below FirstPassFDR with margin, i.e. **library + aggregates only**.
The aggregates are small: 501,247 distinct non-decoy precursor keys, ~5,000 protein groups,
~500 K peptides at 257 files — single-digit GB. So the target shape is ~4.2 GB library plus
a few GB, and the success criterion is that **FirstPassFDR becomes the run's high point.**

## Test target and baselines (named by Brendan, 2026-08-26)

| purpose | run directory under `D:\test\osprey-runs\chs-seer\runs\` |
|---|---|
| **`-LinkFrom` source** (per-file artifacts, 257 files, 596.5 GB) | `chs-257files-libdecoy-r1.0-protein-compact-p0059_0060_0061` |
| **working-set baseline** (`logmem=off`, no stage7 probes) | `...-p0059_0060_0061-s7base` |
| **post-GC live baseline** — the A/B number to beat | `chs-257files-libdecoy-r1.0-protein-compact-s7mem257` |

`s7mem257` is the run the 2026-08-25 issue comment quotes: `--task SecondPassFDR`,
`-LinkFrom` the p0059_0060_0061 dir, exe `_bin\26.1.1.233-stage7fix-20260825`, `logmem=on`,
81 min, exit 0. Its probe series is the baseline column:

```
[MEM library-resident]            4.19 GB (6175389 entries)
[MEM stage7-inherited]           41.97 GB (post-GC, entering Stage 7, files=257)
[MEM stage7-pool]                41.97 GB (post-GC, survivor pool built, files=257)
[MEM stage7-fragments-released]  39.62 GB (released=5173196)
[MEM stage7-pass2-scored]        39.62 GB
[MEM stage7-protein-fdr]         39.62 GB
[MEM stage7-blib-written]        39.62 GB
```

Note `-s7base` carries `logmem=off` and **zero** stage7 probes, so it is the working-set /
`--memstamp` baseline, not the live one. Do not quote it as a live figure.

## Measurement harness

Stage 7 alone against a completed run, ~70 min at 257 files / ~25 min at 100, without
re-running the ~15 h of per-file work:

```powershell
pwsh -File ai\scripts\Osprey\CHS\Run-Chs.ps1 -IncludePattern 'us(0059|0060|0061)' `
  -Task SecondPassFDR -LinkFrom '<completed 257-file run dir>' `
  -Tag '-s7probe' -LogMemory -DecoyMode libdecoy -Ratio 1.0 -Pass2Mode protein-compact `
  -Threads 30 -FdrBenchPass 2 -LibraryDir '<lib>' -Exe '<snapshot>\Osprey.exe'
```

Traps carried from the issue: a repeat run against a directory that still holds
`*.2nd-pass.fdr_scores.bin` self-gates to a no-op, exits 0 and measures nothing; and never
point `Measure-Stage6Rescore.ps1 -PhaseDir` at a real run directory — it begins by deleting
`*.2nd-pass.fdr_scores.bin` and `*.scores-reconciled.parquet` inside it.

## Sequencing note

An 8 h CHS plate-0062 search (PR #4616 field validation) holds the machine until roughly
19:30 on 2026-08-26, and a second ~9.5 h run follows it. Measurement contends with those for
disk and threads; reading and design do not.

## Related

- [#4486](https://github.com/ProteoWizard/pwiz/issues/4486) — nine comments, read the
  2026-08-09 correction and the 2026-08-25 measurement before planning
- #4554 — bounded the pass-2 competition's cross-file state (the previously-named lever)
- #4597 — the deferred pool build Stage 7 now pays for
- #4615 / `ai/todos/completed/TODO-20260825_osprey_stage7_memory.md` — the transient noise
  around this peak (LOH churn in `RestorePass1Scalars`, heartbeat, pre-sized lists)
- #4526 / #4530 / #4536 / #4545 — the O(files) work upstream; this is the O(survivors) residue
- `ai/docs/memory-band-guide.md` — post-GC probes vs `--memstamp`

## Progress Log

### 2026-08-26 - Session start

### 2026-08-26 - The memory landscape, Stages 5-7 at 257 files

`perfviz.py --files 257` over the full run and the Stage-7-alone runs.

**Full 5-7 run** (`...-p0059_0060_0061`, 10:14:28, managed peak 65.2 GB / private 69.0 GB,
floor drift **+138 MB/file RISING**):

| phase | managed p10 / p50 / peak | private peak | wall |
|---|---|---|---|
| FirstPassFDR | 7.0 / 13.2 / 49.5 GB | 53.7 GB | 160:34 |
| PerFileRescoring | 4.9 / 7.3 / 24.4 GB | 44.9 GB | 362:27 |
| **SecondPassFDR** | **24.3 / 43.2 / 65.2 GB** | **69.0 GB** | 91:23 |

**Stage 7 is the only stage with a high FLOOR.** `p10` approximates what the GC cannot
reclaim: 7.0 and 4.9 GB for the two per-file stages against **24.3 GB** for Stage 7, whose
median (43.2 GB) sits above FirstPassFDR's peak. The other two stages spike and release;
this one holds. That is the difference between a transient and a resident pool, visible
without any probe.

**The in-process split the issue called "the obvious next measurement" is already in that
log** — no run required:

| post-GC probe | `--task` (`s7mem257`) | **in-process (full run)** |
|---|---|---|
| `library-resident` | 4.19 GB | 4.19 GB |
| `stage7-inherited` | 41.97 GB | **4.26 GB** |
| `stage7-pool` | 41.97 GB | **38.75 GB** |
| `stage7-fragments-released` | 39.62 GB (released 5,173,196) | 38.76 GB (**released 0**) |
| `stage7-pass2-scored` / `-protein-fdr` / `-blib-written` | 39.62 GB | 38.75 GB |

In-process Stage 7 **inherits essentially nothing** (4.26 GB, i.e. the library) and **builds
34.5 GB itself** on the `.Value` read that #4597 deferred to it — **134 MB/file of pool**.
So the whole target is inside `SecondPassFdrTask`'s own build; no upstream stage has to
change. The `--task` path only differs in WHO built it, and its fragment release frees
2.35 GB where the in-process path frees nothing (`released=0`).

**Reading Stage 7 alone understates it.** Standalone `--task` peaks at 53.6 GB managed /
55.5 GB private (`s7fix257`, 69:47); the same stage in-process peaks at 65.2 / 69.0 GB. An
A/B measured only on the `--task` path is ~12 GB optimistic about the in-process peak.

**The 69.0 GB in that log is a PRE-#4615 number — read the plot, not the summary.** The PNG
shows the Stage 7 window as a ~50 GB private plateau with one narrow spike to 70 GB at
~23:05. That spike is `RestorePass1Scalars`' LOH churn, which #4615 fixed (131 -> 1 MB/file).
Quoting 69.0 GB as today's Stage 7 peak would be quoting a defect that is already gone.

What is left after #4615, at 257 files:

| | managed peak | private peak | live floor (post-GC) |
|---|---|---|---|
| FirstPassFDR (in-process) | 49.5 GB | **53.7 GB** | 7.0 GB (p10) |
| SecondPassFDR, `--task` alone (`s7fix257`) | 53.6 GB | **55.5 GB** | 39.62 GB |

So the two stages are **neck and neck on peak, and 5x apart on floor**. Stage 7 is still in
contention, and it is in contention because of what it HOLDS, not what it spikes. That is
the whole remaining issue.

**The prize**: with the pool streamed, Stage 7's live becomes library + aggregates (single-
digit GB), the run's high point becomes FirstPassFDR, and the whole-run floor drift
(+138 MB/file) should collapse — 134 of those 138 MB are this pool.

## There are TWO accumulating structures, one per path

Not one. A fix that removes either alone leaves the other path unchanged, and the two are
measured by different harnesses:

| | path | structure | slope |
|---|---|---|---|
| **A** | in-process (straight-through) | `RescoredEntries` survivor pool, built on the `.Value` read (#4597) inside Stage 7 | **134 MB/file** (4.26 -> 38.75 GB at 257) |
| **B** | `--task SecondPassFDR` | the reload's **pre-compaction** stub pool — `PerFileScoringTask.cs:1447` accumulates every file's full pre-compaction stub list | **311 MB/file** (#4615 TODO, measured to file 81 of 257) |

B is why `--task` ENTERS Stage 7 at 41.97 GB where in-process enters at 4.26 GB. #4615
stripped features out of that reload (~800 MB/file) but deliberately left the stubs: "a
restructuring job, not a buffer fix, and it was not in the requested scope."

**Consequence for measurement**: an A/B on the `-LinkFrom` / `--task` harness exercises B and
only the tail of A; the in-process peak needs a straight-through run. #4615 hit this and fell
back to a 100-file subset for exactly this reason.

## Deferred findings from #4615 that belong to this branch

Verified by `/code-review max` on that PR, left out of it by scope. All three reduce work
over the pool, so they compose with streaming rather than competing with it:

1. `BuildBestExpPrecursorQ` / `BuildSharedBoundaries` re-walk the whole pool to re-derive
   what `CollectPassingEntries` materialized 22 lines earlier — two of six full passes over
   the 137 M-row pool. `BuildSharedBoundaries` is `internal` and bound by
   `MultiChargeConsensusTest.cs:118`, so the signature change needs its own test pass.
2. `BuildCrossFileObservations` has **no `passingPrecursors` gate** — it filters on `IsDecoy`
   alone while its only consumer looks up passing keys exclusively, so every non-passing
   precursor's observation list is built and never read.
3. Three more whole-pool walks at the head of the blib phase (`ComputePassingPeptides`,
   `ComputePassingPrecursors`, `CollectPassingEntries`), ~70 s at 257 files, still silent.

A fourth is a correctness hazard, not memory, and #4615 says it deserves its own issue:
`FdrScoresSidecar`'s bare `catch { return false; }` reports an OutOfMemoryException as a
missing sidecar; those entries then reach picked-protein FDR at `Score == 0.0`, the decoy
side is not q-gated, so zeros compete in the null and the run exits 0 with corrupted protein
numbers. Cheap durable fix: `catch (Exception ex) when (!(ex is OutOfMemoryException))`.
**Flagged here, not silently adopted** — file it unless told otherwise.

**Correction on the baseline named for me**: `...-p0059_0060_0061-s7base` is not the
post-spike-fix run. Its exe is `_bin\26.1.1.233-20260821` (pre-#4615) and it **stopped at
file 93 of 257** with no DONE line, mid-load. Its perfviz numbers (30.6 GB managed peak,
+44 MB/file) describe a truncated load ramp, not the stage. The completed Stage-7-alone runs
on the fixed binary are `s7fix257` (logmem off, 69:47) and `s7mem257` (logmem on, 80:45).

### 2026-08-26 - Session start

Branch created in `C:\proj\pwiz-work1` off master 2a0b0069f6. Read the issue body and all
nine comments in full. Two things that a short read would have got wrong, recorded above:
the "Stage 7 costs nothing per file" finding was retracted, and the concrete lever its
retraction named (the per-observation dictionaries in `ComputeFullPopulationPrecursorFdrStreaming`)
has since been fixed by #4554 — confirmed in the tree, `StreamedCompetitionState` is O(distinct).
What remains is the live survivor pool itself.
