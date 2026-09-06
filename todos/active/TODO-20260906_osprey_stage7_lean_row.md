# TODO-20260906_osprey_stage7_lean_row.md - Stage 7 (SecondPassFDR) holds ~274 B objects where 88 B of row would serve

**Module**: `osprey`
**Status**: Not started - branch created, no commits yet
**Branch**: `Skyline/work/20260906_osprey_stage7_lean_row` in `C:\proj\pwiz-work1`,
cut from `c4921f3d6c` (master with #4633 merged). Local only - not pushed, no PR yet.
**Predecessor**: `todos/completed/TODO-20260901_osprey_stage5_reload_materialization.md`,
merged as [#4633](https://github.com/ProteoWizard/pwiz/pull/4633) / `c4921f3d6c` on 2026-09-06.

This is the work the predecessor was opened to reach. That TODO grew to cover everything that
had to be true FIRST - per-phase artifact durability, bounded Stage 6 planning, the
`--model-diagnostics` render, and getting the gate green and affordable again - and it has now
shipped. **Detail lives in the predecessor; this file carries only what is still open.** Do not
duplicate its sections here - cite them.

## The goal

Carry a **446-file analysis to completion with bounded memory** on a 63.7 GB box, and ideally
scale to **1000 runs** on the same hardware.

## THE ACCEPTANCE CRITERION (developer, 2026-09-02) - carried forward verbatim

> *"I would like to see both FDR tasks lower memory and SecondPass lower than FirstPass, because
> it is dealing with a much smaller bounded set of entries."*

Box-independent, and cannot be satisfied by adding RAM:

* FirstPassFDR processes the full PRE-compaction pool - 1,342,686,095 entries at 446 runs.
* SecondPassFDR processes only the survivors - 288,920,200. About **4.6x smaller**, and bounded.
* **A stage doing strictly less work must not peak higher.**

**The pass/fail test on any future perfviz plot: if Stage 7 is the tallest region, the goal is
not met even when the run completes.** The 257-file plot of 2026-08-24 shows the inversion -
SecondPassFDR ~70 GB against FirstPassFDR's ~55 GB - and that inversion IS the diagnosis:
Stage 7's cost is its REPRESENTATION, not its workload.

## What is still open

| # | item | where the analysis lives (predecessor TODO) |
|---|---|---|
| 1 | Stage 7 holds ~274 B `FdrEntry` objects rebuilt from parquet where 88 B of fixed-width row would serve | "THE STAGE 7 HANDOFF SHOULD BE A LEAN SIDECAR, NOT A LEAN STRUCT"; "The three-axis Stage 7 plan"; "THE STAGE 7 SIDECAR READ, and two corrections to the three-axis plan" |
| 2 | Measured cost to beat: **78.3 GB committed, ~240 MB/file at 446** | "STAGE 7 AT 446 FILES: 78.3 GB COMMITTED, ~240 MB/FILE (measured 2026-09-04)" |
| 3 | **Coupling 3** - pass-2 diagnostics read the whole-run survivor pool. The only one of the four memory couplings still open; it belongs with this work | predecessor's coupling table |
| 4 | Where the lean row does and does not apply | "Where the lean row does and does not apply to this work" |

## What the predecessor cleared out of the way

Recorded so this work does not re-litigate settled ground:

* **Per-phase durability**: model at training, protein-compact stratum at protein FDR, per-file
  `.1st-pass.fdr_scores.bin` in pass 1. A run interrupted after training re-enters at the
  compaction gate instead of repeating the score passes.
* **Stage 6 planning is bounded**: two per-file passes over the survivor loader instead of an
  all-files buffer. 30.89 -> 12.91 GB peak managed at 86 files, compaction boundary identical.
* **`--model-diagnostics` no longer pins the all-runs hydrate.** This was a stated MEMORY
  prerequisite for the lean row, not just a correctness one - it is now a render over retained
  per-pass products, verified to fold identically from the live score-pass sink and from the
  on-disk sidecars at 446 runs (exact match, 18,821 payload leaves).
* **Coupling 4 (peak co-assignment) is CLOSED as a non-issue** - characterised as a time term,
  not an O(runs) memory term. Do not re-open it as a memory item.
* **The gate is green and affordable**: `-Dataset All` is 1:06 on MacCoss TeamCity Agent 1 under
  the two-lane runner, with modes 8 and 9 now running on every dataset.

## CORRECTION 2026-09-06: the handoff names the wrong bed

The handoff points at `chs446-mdiag-coldfpfdr`, whose first pass is done but which stops
short of PerFileRescoring - reaching Stage 7 from it means running Stage 6 rescore first.
**Use `chs-446files-libdecoy-r1.0-protein-compact-stages567` instead.** It already carries a
complete 446-file PerFileRescoring (`.scores-reconciled.parquet`, `.2nd-pass.fdr_scores.bin`,
`.2nd-pass.fdr_decoys.bin`) plus both analysis-wide sidecars, and it is the very directory the
78.3 GB before-curve was measured in.

```powershell
.\Run-Chs.ps1 -DecoyMode libdecoy -Ratio 1.0 -Pass2Mode protein-compact -Threads 30 `
  -Task SecondPassFDR -Tag '-s7base' -NoModelDiagnostics -Exe <snapshot>\Osprey.exe `
  -LibraryDir D:\test\osprey-runs\sea-ad\lib\target+decoy+entrapment-20260817 `
  -LinkFrom D:\test\osprey-runs\chs-seer\runs\chs-446files-libdecoy-r1.0-protein-compact-stages567
```

That reaches `[TASK] SecondPassFDR:starting` in **under a minute**, and the runner pins
`OSPREY_VERSION_OVERRIDE=26.1.1.243` itself from the source stamps - no manual override.

Three things that are easy to get wrong here:

* **`-Task SecondPassFDR` is not merely faster, it is the only variant that reuses the work.**
  `-LinkFrom` links the stages strictly BEFORE `-Task`; with no `-Task` the runner links 1784
  files (`for stages before FirstPassFDR`, i.e. PerFileScoring only) and re-runs FirstPassFDR
  and PerFileRescoring. With it, 6690 link and 0 are missing.
* **`-NoModelDiagnostics` is required for the comparison.** The 78.3 GB baseline run records
  `mdiag=False` in its START line. Measuring with diagnostics on would compare two things.
  A separate mdiag-on leg is what measures coupling 3, and costs the same minute to set up.
* **`-Tag` is appended raw** (`OspreyDatasetRun.psm1:436`), so it must carry its own leading
  `-` or the run directory comes out as `...protein-compacts7base`.

**#4633 cannot invalidate the linked artifacts** - checked, not assumed. `PerFileRescoreTask`'s
validity key is `base + fdrsidecar + reconciliation + expagg + pass2 + trainpick + stage6stream
+ libfrag`, and `SearchIdentity.cs` (which computes the base and reconciliation hashes) is not
among #4633's 49 files; `FdrScoresSidecar.FormatVersion` is still 6; the `TaskValiditySidecar`
change is an additive `TryReadValidityKey` for `--task ModelDiagnostics`; and the only
`OspreyEnvironment` addition is `OSPREY_DROP_BETWEEN_TASKS`, default off and in no key.

## THE "BEFORE" AT 446 ON THE MERGED TIP (measured 2026-09-06 10:41-11:05)

Run `chs-446files-libdecoy-r1.0-protein-compact-s7base`, exe `_bin\249-s7lean-base`
(v26.1.1.249, `c4921f3d6c`), `--task SecondPassFDR` linked from `stages567`, mdiag off.
Plot: `ai/.tmp/sessions/20260906-s7lean/stage7-before-446.png`.

**It reached 85% (file 381/446) in 17:27, then froze for 6.5 minutes and was killed.**

```
managed MB : peak 68.0 GB  floor 25.2 -> 56.1 GB  drift +30.92 GB  +71 MB/file  RISING
             sustained 55.6 GB for 87s  (82% of peak - mostly LIVE)
total MB   : peak 70.5 GB  floor 35.3 -> 61.5 GB  drift +26.26 GB  +60 MB/file  RISING
             sustained 61.2 GB for 87s  (87% of peak - mostly LIVE)
```

At the kill: working set **3.86 GB** against **69.94 GB private**, with **0.34 GB available of
63.69 GB** - Windows had evicted nearly the whole process. That is the 2026-09-04 signature
(WS 0.29 GB, 0.45 GB available) reproduced on the merged tip, and it confirms #4633's Stage 6
planning fix does nothing for Stage 7, as expected - it addressed a different stage.

**The gate is satisfied: the pool is still the binding term, so the width/layout work is
cleared to start.**

**And the sustained level is MOSTLY LIVE - 82-87% of peak.** This is the finding that directs
the work. An earlier reading of the 40% probe (managed flat at 31.7 GB while private ran to
44.0 GB) suggested a large burst-allocation component; the 50% probe showed that was one GC's
timing, and perfviz confirms it. The peak is live, reachable pool, not committed-but-free
garbage. Consequences:

* **Representation is the right attack** - width (274 B -> 88 B) and layout, exactly as the
  predecessor's diagnosis says. Not allocation churn.
* **`571fb86edd` (chunked sidecar read) will not carry this peak.** Worth having for the LOH
  churn on a read every route performs, but do not expect it to move the sustained level.
* The plot shows why: a clean sawtooth whose FLOOR climbs monotonically to ~60 GB, and in the
  final three minutes **the teeth disappear entirely** - the GC has nothing left to reclaim.
  Rising floor = O(files) accumulation, per the memory-band guide.

Two reporting gaps over 30s (59s at 10:54:36, 62s at 10:56:18), both after a
`Loaded N FDR stubs` line - the paging starting.

**Cost of reproducing this: about 20 minutes.** `--task SecondPassFDR` linked from `stages567`
reaches `[TASK] SecondPassFDR:starting` in under a minute, and the wall arrives ~15 minutes
later. The A/B loop for this work is short; there is no need to schedule it overnight.

## THE CONTRACT SETTLES THE DIRECTION: FOLD, DO NOT SHRINK (2026-09-06)

Read `pwiz_tools/Osprey/docs/00-pipeline-architecture.md` and `Osprey-workflow.html` BEFORE
touching this - the osprey-development skill says so for any change to what a task reads,
writes or keeps, and this work is exactly that. Reading only the Boundary 3 -> 4 section
cost most of a session pointed at the wrong fix.

**A leaner resident row is not an option, it is the forbidden shape.** P3: *"Work goes in the
fan-out tasks; a join holds O(distinct), never O(runs x entries)."* The lean 88 B row would
take the pool from ~79 GB to ~25 GB and still be O(runs x entries) - it fits this box and
fails at 1000 runs, and doc 00 is explicit that this is "a scaling shape, not a constant
factor" that "no amount of available RAM changes". **Do not spend the width axis on Stage 7's
pool.** The 88 B row remains interesting only as an on-disk record, which the 28 B
`.2nd-pass.fdr_scores.bin` already is.

**The admissible shape is a fold over a stream**, and doc 00 supplies both the vocabulary and
the worked example:

| | Visits | Holds |
|---|---|---|
| Fold over a stream | every run | a bounded summary |
| Resident whole-experiment structure | every run | every run - **inadmissible** |

"Visited is not resident." Counting Stage 7's ten walks as if visiting were the cost is the
error that led to the lean-resident recommendation. Doc 00 names Stage 7's own computations
as folds - *"the best-of-runs experiment-q floor, protein parsimony, the pre-blib q
re-clamp"* - and points at `StreamingFdr.StreamingFirstPassQ` as the worked example, **pinned
against its resident twin by a test**. Copy that pattern AND that test shape; do not
improvise one.

**One defect, three descriptions.** `BuildRescoredPool` -> `MaterializeFileSurvivors` ->
`FirstPassSurvivorLoader.Load` reads all 446 `<stem>.1st-pass.fdr_scores.bin`. That single
read is:

* the **boundary violation** - doc 00's Boundary 3 -> 4 says "Not needed on the default path:
  `<stem>.1st-pass.fdr_scores.bin`. Establishing that is what issue #4486 was for", and the
  workflow page's SecondPassFDR band lists no per-run first-pass FDR file at all;
* the **P3 violation** - it is what materialises the O(runs x entries) pool;
* the **5.9x over-read** - the 1st-pass sidecar spans the whole pre-compaction set, so 1.69 B
  records / 47 GB are walked to place 289 M survivors. The 2nd-pass sidecar is written FROM
  the survivor set, so it is 1:1 and ~7.5 GB.

**Target per-run materialize**: survivor stubs from `.scores-reconciled.parquet`, then
`TryReadOverlay(pass2Path, byEntryId, Pass.SecondPass, pass2ExperimentRecords)` - which is
already the body of `ReloadPass2Sidecars`, a method Stage 7 runs today AFTER the competition.
Sourcing at materialize time collapses three steps into one read of the file the contract
designates, and removes `ResetRescoredTargetsForFile`, which exists only to undo values read
from the wrong file. Note the workflow page's qualifier: `.2nd-pass.fdr_scores.bin` is a
Stage 7 INPUT where the rescore worker produced it and an OUTPUT where it did not, so the
materialize needs both arms.

**Still to settle by comparison, not argument** (the predecessor's standing instruction): the
2nd-pass sidecar as a like-for-like substitute. `ResetRescoredTargetsForFile`'s existence says
rescore targets must return to Score 0 / q 1, so a pass-2 overlay could pre-apply pass 2. Gate
it: `regression.ps1 -Dataset Stellar`, then `-Dataset All`.

## Before starting

* Read `ai/docs/osprey-development-guide.md` on the two-lane gate - `-Dataset All` no longer
  costs double a Stellar-only run, so run the full gate rather than Stellar as a stand-in.
* The per-dataset coverage matrix and the reason for each asymmetry are in that same guide,
  beside the dataset table. Astral omits mode 2 deliberately; that is budgeted, not an oversight.

**Next session handoff**: For detailed startup protocol - including the 446-file bed whose
entire first pass is already done, the two settings required to reuse it, and what to measure
- read `ai/.tmp/handoff-20260906_osprey_stage7_lean_row.md` before starting work.
