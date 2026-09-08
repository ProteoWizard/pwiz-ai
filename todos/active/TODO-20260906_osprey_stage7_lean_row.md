# TODO-20260906_osprey_stage7_lean_row.md - Stage 7 (SecondPassFDR) holds ~274 B objects where 88 B of row would serve

**Module**: `osprey`
**Status**: In Review - [#4642](https://github.com/ProteoWizard/pwiz/pull/4642) open, pushed,
all gates green. **NOT mergeable yet**: the developer will not merge until pass-2 diagnostics
fold within bounded memory (see "THE NEXT PHASE").
**Branch**: `Skyline/work/20260906_osprey_stage7_lean_row` in `C:\proj\pwiz-work1`,
cut from `c4921f3d6c` (master with #4633 merged).
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

> ### CORRECTION 2026-09-07: this measurement was attributed to the wrong code
>
> Everything above about the SHAPE is right - rising floor, mostly live, O(files) - and the
> attribution underneath it was wrong, in a way that would have sent the night session at the
> wrong function. The run does **not** die in Stage 7's pool rebuild
> (`BuildRescoredPool` -> `MaterializeFileSurvivors` -> `FirstPassSurvivorLoader.Load`). Read
> the log's last lines: it dies inside
>
> ```
> --input-scores: loading 446 per-file score parquet(s)
>     Loading file 381/446: ... (from ....scores-reconciled.parquet)
>       Loaded 788801 FDR stubs (features not loaded - not read on this path)
> ```
>
> That is `PerFileScoringTask`'s `--input-scores` merge building `ScoredEntries`, **before
> Stage 7 has computed anything at all**. `BuildRescoredPool` is never reached on this leg:
> `PerFileRescoreTask.Rehydrate`'s `ExpectReconciledInput` branch publishes
> `new RescoredEntries(_perFileEntries)` - the resident constructor, no per-file source.
>
> The consequence is that **the fix is at the hydrate, not at the pool build**, and the
> width/layout attack the paragraphs below recommend would not have moved this number: a
> narrower row is still 446 runs of rows held before the first fold starts. What moves it is
> giving the merge the per-run shape `CanHydratePerRun` already gives the rescore. Landed in
> `4d0bae8caf`; see "WHAT LANDED" below for the measurement.
>
> Method note, since this is the second time this branch has mis-attributed a peak: the
> correction came from reading the failing run's own last 25 lines, which cost one command.
> Neither the handoff nor this section had done that.

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

## THE TARGET, DECIDED 2026-09-06 (developer)

> *"The only modes we want to preserve are transfer and protein-compact and we want those to
> work with PerFileRescoring doing the per-file calculations and SecondPassFDR doing roll up.
> ... we should do everything we can to emulate through the experiment-wide FDR bin and
> diagnostics HTML, which leaves just writing the BLIB as the final thing to bound memory."*

**One calculation, one task.** The per-run pass-2 q-value is computed and written by
`PerFileRescoring` and by nothing else. `SecondPassFDR` rolls up. Today BOTH tasks compute and
write `<stem>.2nd-pass.fdr_scores.bin`, through four paths - the duplication is the defect.

| | today | target |
|---|---|---|
| per-run pass-2 q + sidecar | both tasks, 4 write paths | `PerFileRescoring` only |
| `transfer-compete` | frozen full-population competition | **CUT** |
| `OSPREY_PROTEIN_COMPACT_RETRAIN` | diagnostic A/B | **CUT** |
| `SecondPassFDR` | competes, writes per-run sidecars, holds 289 M `FdrEntry` | folds only |

**There is no second-pass model any more.** With retraining dead the pass-2 model IS the
pass-1 model; only the score distributions differ, because pass 2 runs on a subset. So the
`--model-diagnostics` pass-2 structural card decomposes into a model half and a distribution
half: `Coefficient` is the frozen weight (already on disk in `.1st-pass.model.json`, already a
Stage 7 input) and `TargetDecoyMeanGap` is `mean_target - mean_decoy`, i.e. **42 running sums**
(21 features x target/decoy, sum and count). `Weighted`, `Percent` and `Composite` derive from
those two. That is O(features) and folds per run in the fan-out - and it is strictly better
than today, where `pass2Contributions` is null under `transfer` so the card is simply missing.

### Sequence

1. **Cut `transfer-compete` and `OSPREY_PROTEIN_COMPACT_RETRAIN`.** With only `protein-compact`
   and `transfer` left, `ComputeAndPersist`'s projection branch becomes unreachable and deletes.
2. **Move `transfer` into `Pass2PerFileWorker`.** Already per-run by algorithm (#4438: "THAT
   FILE'S OWN score->run-q table, one file at a time"), and it wants the reconciled features the
   fan-out has in hand and Stage 7 reloads. Deletes one of doc 00's two documented exceptions to
   "Stage 7 reads no per-run first-pass file".
3. **Delete Stage 7's per-file pass-2 compute and write.** Worker becomes mandatory; an
   unreadable model sidecar becomes a hard failure instead of a silent relocation to the join.
   **The 289 M-entry pool goes here** - `ComputePass2Resident` and the resident branch delete.
4. **Pass-2 diagnostics become a fan-out product** - frozen coefficients + the 42 folded sums.
5. **Roll-up as folds**, on `RunFirstPassProteinFdrStreaming`'s pattern: experiment-wide bin via
   `FdrExperimentAccumulator`, protein FDR via the two-pass streamed shape. Reads the per-run
   2nd-pass sidecars: ~7.5 GB of 28 B records, a fifth of what FirstPassFDR already streams
   twice in 18 minutes over 1.34 B entries.
6. **Bound the blib write** - the last term. The two gates already fold to O(distinct); the
   collect does not (a compact record per passing observation, ~14 M at 446 runs). Keep the
   O(distinct-precursor) best-run assignment and emit per run, writing the rows whose best run
   is this one - the same fold-then-apply shape as the experiment-q clamp.

### Progress

| step | state |
|---|---|
| 1. cut `transfer-compete` + retrain toggle | **DONE** `ad4ef8d106`, `-Dataset Stellar` PASSED (15/15, incl. mode 1 vs golden) |
| 2a. extract `TransferOneFile` (the per-run seam) | **DONE** `d969570a3c` |
| 2b. wire it into `Pass2PerFileWorker`, admit `transfer` in `TryCreatePass2Worker` | open |
| 3. delete Stage 7's per-file pass-2 compute/write | open - and NO LONGER the step that removes the pool, see below |
| 4. pass-2 diagnostics as a fan-out product | open - and now the last thing holding the pool, see below |
| 5. roll-up as folds | **DONE** `4d0bae8caf` |
| 6. bound the blib write | **DONE** `4d0bae8caf` (the three gates fold; the collect keeps its ~14 M compact records) |

### WHAT LANDED 2026-09-07, and how the plan changed

The sequence above was written against the belief that Stage 7's pool was built by Stage 7.
It is not, on the leg that matters (see the CORRECTION in the "BEFORE" section): the
`--input-scores` merge hands the stage every run's survivors before it starts. So steps 5 and 6
turned out to be reachable FIRST, without steps 2b-4, and they are what removes the peak.

`4d0bae8caf` "Made SecondPassFDR fold over the runs instead of holding them":

* `ScoringTaskShared.CanStreamStage7Join` admits the reconciled-input leg to the per-run shape
  `CanHydratePerRun` already gives the rescore. The merge publishes one EMPTY list per run and
  reads no rows.
* `RescoreHydration.RefillOneRunSurvivors` rebuilds ONE run in place - load its reconciled
  stubs, overlay, compact - and Stage 7 folds it and drops it.
* Every Stage 7 consumer moved to `RescoredEntries.StreamFiles`: fragment release, the pass-2
  competition, protein FDR, the experiment-q re-clamp, all three blib gates, FDRBench.
* The two facts a resident pool carried BETWEEN passes - the 2nd-pass sidecar overlay and the
  experiment-q floors - are re-applied per run via `AddPostMaterialize`, in that order.
* `OSPREY_STAGE7_STREAM=0` keeps the resident arm as the byte-identity oracle, with a
  validity-key term so an in-place A/B cannot adopt the other arm's `.blib`.

**Measured at 446 runs** (`chs-446files-libdecoy-r1.0-protein-compact-s7fold`, same bed, same
recipe, same pinned version as the "before"):

| | before | after |
|---|---|---|
| `stage7-inherited` | (never reached) | 5.12 GB |
| `stage7-pool` | (never reached) | **5.12 GB** - flat, no pool built |
| outcome | killed at run 381/446 inside the load, 0.34 GB free | reaches the fold in ~1 min |

The log line to look for is `Second-pass join: folding over 446 run(s), each rebuilt from its
own artifacts and dropped`, and beside it `446 of 446 run(s) carry a current 2nd-pass sidecar
and are rebuilt without opening any 1st-pass file` - which is the Boundary 3 -> 4 contract
holding for the whole cohort, asserted per run rather than assumed.

**What is left holding a pool, and it is now step 4 rather than step 3.**
`--model-diagnostics` is the one Stage 7 consumer still handed the whole buffer:
`ModelDiagnosticsData`'s pass-2 builders index their runs BY POSITION and revisit a run across
two loops (`ModelDiagnosticsData.CoAssignment`), so they need a list, not a stream.
`CanStreamStage7Join` therefore declines the report leg outright - better than letting it stream
and then pull the pool back through `.Value`, which is the same peak by a longer route with
nothing in the log to say so. The fix is the accumulator the PASS-1 report already uses
(`FirstPassFdrTask`'s `mdiagAccumulator`, folded per run in the score pass); give pass 2 the
same and the exclusion goes.

**Two defects fixed on the way, both worth knowing about:**

1. `TransferOneFile`'s missing-features branch was a `return` where the loop it was extracted
   from (`d969570a3c`) had a `continue` - so ONE entry without reconciled features abandoned the
   rest of that run's survivors at their Stage-6 q AND skipped the run's `FilesDone` count. An
   extraction that "changed nothing" changed a control-flow keyword.
2. `-LinkFrom` did not stage `.1st-pass.stratum.json` (nor the model sidecar's own
   `.osprey.task`). #4633 split the stratum out of the model sidecar and the runner's
   `$STAGE_ARTIFACTS` table was not updated, so a cohort that reported "6690 file(s), 0 missing"
   was one artifact short and failed 11 minutes into Stage 7 with "could not run the frozen
   recompute ... or protein stratum are absent" - which reads as a code bug. Fixed in
   `ai/scripts/Osprey/Common/OspreyDatasetRun.psm1`; the link count is now 8028 = 446 x 18.

Also on the branch: `4b9df2a836` (chunked sidecar read, cherry-picked from the #4633 branch
where it was orphaned by the squash), `9a1eb514c1` (the per-file survivor source + StreamFiles),
`187c0a214c` (workflow page + doc 00 boundary lists updated for #4633), `73dda2efaa` (gate
mode 10). `-Dataset StellarLibDecoy` PASSED with mode 10, both new arms green on first run.

**NIGHT SESSION 2026-09-07**: the goal, the 446-file proof recipe, the gate order, the standing
authorizations and the traps already paid for are in
`ai/.tmp/handoff-20260907_osprey_stage7_night.md`. Read it before starting.

**Open decision for the developer**: mode 10's two arms measured 253.3s + 255.0s = 8.5 min on
StellarLibDecoy, against the ~5 min the second lane finishes early by - so both arms move lane 2
onto the critical path and take `-Dataset All` from ~1:05 to ~1:08. Keeping only the `meanbest2`
arm fits free and still exercises transfer, because protein-compact refuses a mean(best-N) first
pass so that arm runs transfer for pass 2 regardless.

**The gate already tracks this work's target.** Its "Known O(files) resident paths" section
names #4486 - `SecondPassFDR` pulling `RescoredEntries` rebuilds the whole-run survivor buffer,
"~20 GB at 82 files, ~103 GB projected at 500" - with a required-token count of 0. When the
folds land, that entry stops being reported. That is an asserted acceptance signal, better than
reading a plot.

**Step 2 is a port, not a rewrite** - verified by reading `TransferPerRunQ`: its
`foreach (var kvp in perFileEntries)` body resolves that file's own `.1st-pass.fdr_scores.bin`,
builds that file's own score->q tables from it, and classifies that file's survivors. The only
cross-file state is O(1) tallies. The first-pass sidecar it reads is a legal Boundary 2 -> 3
input in the fan-out, which is what makes the move delete Stage 7's last documented reason to
read per-run first-pass files.

**Test harness for the folds (steps 4-6)**: copy `TestStreamingFirstPassQMatchesFlat`
(`FdrTest.cs:2145`) - a seeded population fed to both the streaming builder row by row and the
flat oracle as arrays, asserting byte-identical maps, with `applyExperimentAgg: false` so an
ambient A/B sweep cannot produce a spurious failure. Do not improvise a different shape.

### HOW `transfer` GETS VALIDATED - the long run, last

**`regression.ps1` does not exercise `transfer` at all.** Every `OSPREY_PASS2_QVALUE` mention in
it is a comment; all 15 legs run the default. What IS covered is the algorithmic core -
`BuildScoreToQTable` and `AssignPerRunQ` have unit tests (`Pass2FdrSidecarTest.cs:306, 353`) - so
a port that reuses those helpers unchanged keeps them. The ORCHESTRATION around them (resolving
the file's sidecar, iterating survivors, the tallies) is what a port moves and what nothing
checks.

**The oracle is a SINGLE CHS PLATE, not SEA-AD** (developer, 2026-09-07): that is what the
#4633 session ran transfer + mean-best-N on, against a comparable library - libdecoys plus
entrapment peptides. Cheaper than it sounds, because the plates are already staged with
linkable Stage 1-4: `chs-86files-libdecoy-r1.0-protein-compact-p0059` (also p0060/85, p0061,
p0062). `Run-Chs.ps1 -Plates 0059 -Pass2Mode transfer -ExperimentAgg mean-best-6 -LinkFrom
<that dir>`, `-FdrBenchPass 2` to measure FDP, `-WhatIf` first.

The 82-file SEA-AD A/B in
`ai/todos/active/TODO-20260804_osprey_pass2_ab_and_library_production.md` remains where the
comparison's SHAPE is written down, and it is the larger validation if one is wanted later.

**Those numbers are HISTORICAL, not targets** (developer, 2026-09-06): recorded 2026-08-04,
and superseded. The change that invalidates them specifically is
[#4593](https://github.com/ProteoWizard/pwiz/pull/4593) - first-pass training now samples one
run per precursor - which increased detections substantially AND made them much more stable,
most visibly on SEA-AD. Any pass-2 comparison recorded before it is measuring a different
first pass. They establish that these are the two paths in competition, not a
bar to hit - the comparison needs re-running fresh, and protein-compact has improvements still
to try. Kept so the SHAPE of the comparison is not reconstructed from scratch:

| | protein-compact | **transfer** |
|---|---|---|
| pass-2 true FDP @ 1% reported q | 1.156% | **0.770%** |
| library spectra written | 37,078 | **38,913** |
| protein groups @ 1% FDR | 5,022 | **5,155** |

Pass 1 was calibrated identically in both arms (0.777% / 0.775%), so they started level - the
property that made the pass-2 difference attributable, and the one a fresh comparison must
preserve. The reason `transfer` must survive is not any single number: it is a genuine contender
against the default rather than a compatibility mode.

**Run it with `-LinkFrom` arm A so Stages 1-4 are byte-identical**, and read arm A's `run.log`
START line field-by-field rather than reconstructing its config - two errors that `-WhatIf`
caught before an 8-hour run came from exactly that:

* `-LibraryDir` must be arm A's library (`target+decoy+entrapment-gated-no-il`). The default
  resolution picks a DIFFERENT library, and with `-LinkFrom` hard-linking arm A's parquets that
  silently pairs one library's Stage 1-4 with another's Stage 5+.
* `-FdrBenchPass 2`, never the `both` default: `--fdrbench-pass 1` forces the RESIDENT
  first-pass pool, which OOMs at 82 files.

Always `-WhatIf` first.

### Gate legs for the two contender arms (mode 10), and the 4x multiplier rule

`regression.ps1` gained **mode 10**: the non-default pass-2 arms run and produce their
artifacts. Two arms - `transfer`, and `mean-best-2 + transfer` (they pair by necessity:
protein-compact REFUSES a mean(best-N) first pass). It asserts the ARTIFACT CONTRACT, not
values: the arm completes, writes `output.blib`, writes the analysis-wide
`output.2nd-pass.fdr_experiment.bin`, and writes a per-run `.2nd-pass.fdr_scores.bin` per
input. Deliberately not a golden - these arms are still moving, and a golden would freeze a
number nobody has agreed on. What must not change silently is that they RUN and PRODUCE,
which is exactly the defect that already shipped (transfer wrote no experiment sidecar at
all, invisible because the arm had never run under the gate).

**THE RULE THAT MATTERS MORE THAN THIS LEG** (developer, 2026-09-06): *"we need to be careful
about adding new test cases that are just blindly applied across everything we try. It doesn't
necessarily give us better coverage, but definitely multiplies the testing time consumed."*

The gate has **four dataset configs** - Stellar, StellarLibDecoy, StellarGenDecoyEntrap,
Astral - which is two acquisitions searched four ways. A leg written into the per-dataset loop
inherits a **4x multiplier** by default. Mode 10 as first written would have added EIGHT
straight-through runs and wrecked the 1:05 that `-Dataset All` was just tuned to. It is now
opted in by a single `AltPass2 = $true` on **StellarLibDecoy** - chosen because
library-SUPPLIED decoys are what the pass-2 comparison runs on real cohorts (SEA-AD is
`-DecoyMode libdecoy`), so the arms meet the decoy provenance they are actually used with, at
Stellar speed and off Astral's critical path.

**Backlog: audit the existing legs for the same blind 4x.** Some modes may be running on all
four configs where one would do. `SkipModes = @(2)` on Astral is the precedent for cutting
deliberately and pricing it; the question is which other legs never had that conversation.

### Why the cuts need no re-litigation

The statistical argument is already written down in
`pwiz_tools/Osprey/docs/12-second-pass-fdr.md`, "Why a second-pass null is a problem": first-pass
compaction leaves the pool **decoy-depleted**, so retraining an SVM on it "estimates the null
from a thin, biased decoy population and reports anti-conservative (optimistic) q-values" -
measured at 1.57% true FDP against a nominal 1% on Stellar libdecoy entrapment (0.92% for the
pass-1 q) and ~9% on 82-file SEA-AD, with the error growing with run count. The decision is
[#4484](https://github.com/ProteoWizard/pwiz/issues/4484), CLOSED. **Do not re-open the retrain
path**; git history holds the dropped approach.

Coverage check before cutting: **no gate leg and no unit test exercises either mode.**
`regression.ps1` mentions `transfer-compete` only in two comments; `FdrTest.cs` references it in
prose and in one assertion message on `TestFrozenModelScorerAcceptsBothClassifiers`, which tests
`FrozenModelScorer` (kept - both surviving modes score frozen) and needs only its wording fixed.

**Docs to update with the cut**: doc 12's mode table, its "Frozen vs. retrain" section, and its
stale in-flight note claiming the stratum "is moving out of the model sidecar" (it moved, in
#4633) plus the table above it still crediting `.1st-pass.model.json` with carrying the stratum.

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

## NIGHT SESSION RESULT, 2026-09-06/07

**PR #4642** - https://github.com/ProteoWizard/pwiz/pull/4642

### The 446-run proof

`chs-446files-libdecoy-r1.0-protein-compact-s7fold`, same bed / recipe / pinned version as the
"before". **exit 0 in 71 minutes.**

| | before (`-s7base`) | after (`-s7fold`) | `FirstPassFDR`, same cohort |
|---|---|---|---|
| managed peak | 68.0 GB | **23.5 GB** | 32.5 GB |
| private peak | 70.5 GB | **36.4 GB** | 40.1 GB |
| floor drift | +71 MB/run RISING | **-5 MB/run FALLING** | +4 MB/run |
| outcome | killed at run 381/446 | completed | - |

**The acceptance criterion is met**: SecondPassFDR peaks below FirstPassFDR on both axes.
Post-GC live footprint stays under 3 GB across the whole stage (`stage7-pass2-scored` 2.97 GB,
`stage7-protein-fdr` 2.98 GB), so what is left in the peak is transient, not a pool.
Zero reporting gaps over 30 s across the 71 minutes.

Output checked, not assumed: 45,643 `RefSpectra`, 20,351,447 `RetentionTimes`,
**446 `SpectrumSourceFiles`** (the count that catches a `.blib` silently missing runs), 5,502
protein groups at 1% protein FDR, 54.5 MB `out.2nd-pass.fdr_experiment.bin`.
Plot: `ai/.tmp/sessions/20260906-s7lean/stage7-after-446.png`.

### Gates

`-Dataset Stellar` PASSED (15 legs, incl. `mode3 (HPC chain==straight)` - byte-identity on the
leg this changes). `-Dataset StellarLibDecoy` PASSED (23 legs, both mode 10 arms).
`-Dataset All` re-run on the post-review code. 606 unit tests, inspection zero-warning.

### `/code-review max` - what was fixed, and what was dropped

Fixed in `cb1d67369a` (see the commit for the reasoning): the `transfer`-mode throw, the
empty-`.blib`-on-exit-0 path, the write loop that would blank worker-owned sidecars, the
format-probe-vs-validity-stamp divergence, the unresolved parquet path, the eager 400 MB
experiment map, the `_streamed`-after-yield window, and mode 10's env-var deletion.

**DROPPED, with the reason** (per the triage rule - not filed as issues):

* *"`totalScored == 0` aborts the perRunJoin leg"* - marked PLAUSIBLE by the reviewer and
  **disproved by the 446 run**: it logs "No scored entries found. Cannot perform FDR control."
  and continues to a complete `.blib`, exactly as the pre-existing `CanHydratePerRun` leg does.
* *`MaterializeAllFromSource` bypasses `_postMaterialize`* - the reviewer's own sweep shows it
  is unreachable (the `_streamed` throw precedes the `Lazy` build). Left as the expensive
  fallback it is; a future consumer must be converted to `StreamFiles` rather than left to it.
* Efficiency items (per-run dictionary churn in the overlay, the reference-array copy in
  `RefillOneRunSurvivors`, 4 KB stream buffers, `WriteSummaryReport` defaulting on). Real, and
  all of them trade wall clock, which is the axis this work is explicitly allowed to spend.
  Measure before optimising.

### STILL OPEN, in priority order

1. **The gate cannot see the streamed arm on 3 of 4 datasets.** `--model-diagnostics` is set on
   StellarLibDecoy, StellarGenDecoyEntrap and Astral, and `CanStreamStage7Join` declines on it -
   so mode 3's phase 4 takes the OLD resident path everywhere except plain Stellar. A defect on
   the streamed arm that needs library decoys, entrapment or hram data passes the suite green.
   Cheapest honest fix, and the one doc 00 prescribes for a path output cannot distinguish:
   assert the marker line (`Second-pass join: folding over N run(s)`) in mode 3's phase-4 log.
   Nothing runs the `OSPREY_STAGE7_STREAM=0` A/B either, and the variable is absent from
   `docs/20-command-line.md` and from `regression.ps1`'s `$abSwitchSet`.
2. **`--model-diagnostics` still needs the resident pool** - the last O(runs x entries)
   structure in Stage 7. `ModelDiagnosticsData`'s pass-2 builders index runs by position and
   revisit a run across two loops. The fix is the accumulator the pass-1 report already uses.
3. **Steps 2b and 3** (transfer's per-run half into `Pass2PerFileWorker`; delete Stage 7's
   per-file pass-2 compute). Still "one calculation, one task" - and now also what lets
   `CanStreamStage7Join` stop naming a single mode.
4. `FdrScoresSidecar.TryWalkRecords`' OOM-filtered catch was widened (in the cherry-picked
   `4b9df2a836`) to enclose the whole walk, so a mid-body IO fault returns false with records
   already overlaid - and the caller treats false as non-fatal.

## THE NEXT PHASE, decided by the developer 2026-09-07

> *"Next phase requires applying FirstPassFDR diagnostics handling to SecondPassFDR to make
> diagnostics achievable within bounded memory."*

This is item 1 of "STILL OPEN" promoted to THE next piece of work, and the developer has said
**#4642 will not be merged until it is done**. So it belongs on this branch or its immediate
successor, not in a backlog.

**What to copy.** `FirstPassFdrTask` already solved this for pass 1: it folds the report from a
streaming accumulator during the score pass (`mdiagAccumulator`, fed per run) instead of
walking a resident pool afterwards, and `--task ModelDiagnostics` then RENDERS from the
retained `.1st-pass.model-diagnostics.json` without processing anything. Pass 2 has neither
half - `ModelDiagnosticsReport.WritePass2AndFinalize` takes the whole pool.

**What blocks a naive conversion**, established 2026-09-07 and worth not rediscovering:
`ModelDiagnosticsData`'s pass-2 builders take `IReadOnlyList` and mean it. They index runs BY
POSITION (`perFileEntries[i]`, `perFileEntries[f].Key`) and `ModelDiagnosticsData.CoAssignment`
revisits the same run across two separate loops. Widening the parameter to `IEnumerable` makes
it compile and makes every view re-materialize each run several times - a fold per view, not a
fold per run. The accumulator is the fix; the parameter type is not.

**Why it is the last thing holding a pool.** With it landed, `CanStreamStage7Join` drops its
`config.ModelDiagnostics` term, and with that term gone the gate stops SKIPping the streamed
arm on StellarLibDecoy, StellarGenDecoyEntrap and Astral - so item 2 (three of four datasets
never exercise the streamed path) closes at the same time. Two of the four open items are one
change.

**Sequence it before steps 2b/3** (moving `transfer` into the worker). Those are architectural
tidiness - "one calculation, one task" - and this one is a merge blocker.

## Mode 10 cut to one arm (developer, 2026-09-07)

> *"Cut transfer alone run from regression.ps1. Its benefit may be diagnostic."*

Done. The `meanbest2` arm remains and exercises BOTH ideas, because protein-compact refuses a
mean(best-N) first pass and so that arm runs `transfer` for pass 2 regardless. The standalone
arm was the half whose coverage was already implied, and it cost 223.1 s of a 01:19:30
Perf/Regression wall that has to come in under 75 minutes. It stays reproducible by hand -
`OSPREY_PASS2_QVALUE=transfer` with `OSPREY_EXPERIMENT_AGG` unset - which is what you want when
the leg goes red and you need to know which of the two ideas moved.

**No goldens were produced or regenerated anywhere on this branch**, and that is the point:
`git diff master` touches no golden file, and mode 1 (`vs golden`) passing against the
UNCHANGED committed golden is the byte-identity proof. Had the fold moved any output, mode 1
would have gone red. Mode 10 asserts the artifact contract rather than values, deliberately -
these two arms are still moving, and a golden would freeze a number nobody has agreed on.

## Session close, 2026-09-07 07:15

**PR [#4642](https://github.com/ProteoWizard/pwiz/pull/4642)** - 11 commits, pushed, all gates
green, Copilot addressed. Held open deliberately: the developer will not merge until pass-2
diagnostics fold within bounded memory.

Final state of the four gate legs:

| gate | result |
|---|---|
| `Build-Osprey.ps1 -RunTests -RunInspection` | 606 tests (605 pass, 1 pre-existing skip), zero-warning |
| `regression.ps1 -Dataset Stellar` | PASSED, 16 legs (incl. the new `mode3 (streamed join)`) |
| `regression.ps1 -Dataset StellarLibDecoy` | PASSED, 22 legs (mode 10, one arm, both markers) |
| `regression.ps1 -Dataset All` | PASSED, 79 PASS / 0 FAIL |
| TeamCity Perf/Regression `pull/4642` | 78 PASS / 0 FAIL / 0 SKIP in **01:19:30** - ran on `1cc6fcc1`, predates the review fixes AND the mode-10 cut |

The mode-10 cut removes 223.1 s, so the next Perf/Regression run should land near **01:15:45**.
Still marginally over the 75-minute target; the remaining overage is not mode 10's.

**Do not re-trigger TeamCity without asking.** The developer's standing rule, and they have
said they will not merge before the next phase lands anyway - so the natural moment for the
re-trigger is when that work is ready, not now.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260906_osprey_stage7_lean_row.md` before starting work.

## THE NEXT PHASE LANDED, 2026-09-07 - pass-2 diagnostics fold within bounded memory

The merge blocker. `--model-diagnostics` no longer needs the resident survivor pool in
SecondPassFDR, so `CanStreamStage7Join`'s `config.ModelDiagnostics` term is gone and the
streamed join is reachable on every dataset.

### What the analysis found, and why it was smaller than the handoff feared

The handoff framed this as "apply FirstPassFDR's accumulator to SecondPassFDR". Comparing
what `BuildPass2` needs against what `ModelDiagnosticsData.Accumulator` already folds, **eight
of the nine pass-2 cards were already there**:

| pass-2 card | the reduction the accumulator already held |
|---|---|
| `ReduceToPrecs` -> `precs` | `_best` (max score, min q per modseq\|charge) |
| `BuildPerFile` | `_fileTargets` / `_fileDecoys` / `_fileEntrap` |
| `BuildIdYield` | from `_best` |
| `BuildCrossRunDetection` | the four `CrossRunStream`s (already folded, not retained) |
| `BuildPass2FdpViews` | from `_best` |
| `BuildModelPass2` | from `_best` |
| `BuildDensityRatio` | from `Model.Scores` |
| `BuildWinFraction` | `_bt` / `_tClass` |
| **`BuildCoAssignment`** | **nothing - the only real work** |

`Accumulator.Add` already takes exactly what an `FdrEntry` carries, so feeding it from the
stream is direct. What it needed was a `BuildPass2(contributions, coAssignment)` sibling to
`Build(contributions)` emitting `Pass2Data`, plus a `pass` ctor argument so pass 2 skips the
Frontier fold (`Pass2Data` has no Frontier card, and it is a dictionary lookup + update per
target row over the whole reported pool).

### Co-assignment is a TWO-PASS problem, not a resident-pool problem

`CoAssignmentPassBuilder` was already bounded to one run at a time (`SealRunCutoff`,
`FlushFile`). What it cannot do is fold in one walk: phase 1 draws the acceptance boundary as
a reduction over every row, and phase 2 compares every row against it. **There is no fold that
yields both.**

Phase 1 is per-row and cheap, so it rides along in the accumulator's pass. **Two stream passes,
not three:**

* **Pass A** - `accumulator.Add` + `ObserveCoAssignmentRun` (phase 1), one read
* **Pass B** - `BuildCoAssignmentDetection` (phase 2)

Stage 7 already re-streams several times over (experiment-q reclamp, retained base_ids, protein
FDR, the FDRBench TSV, the blib gates), so this is the stage's existing idiom, not a new cost
class - and it replaces a 78.3 GB resident pool. Wall clock is the cost, which is the axis this
work is explicitly allowed to spend.

### The alternative that was REJECTED, and why

Pass 1 gets its co-assignment panel from `PeakCoAssignmentSource` - the per-file sidecars joined
to `.scores.parquet` apex RT - rather than from the fold. The pass-2 analogue would read
`.2nd-pass.fdr_scores.bin` + `.scores-reconciled.parquet`, and would be cheaper per pass than a
rebuild.

**It was not taken.** The pass-2 panel must describe *the reported pool*, and the reported pool
is defined by the Stage 7 rebuild itself: retained base_ids, the pass-2 sidecar overlay, the
experiment-q floors. Reconstructing it from sidecars would put that definition in a SECOND
place - the class of defect this area keeps producing. One definition, two reads.

### Why the order-sensitivity worry does not apply

The accumulator's byte-identity argument has one order-sensitive step: `BuildScoreHistogram`'s
decoy mean/std accumulate non-associative floating-point sums, so both paths must enumerate
`_best.Values` in the same order. That was never exercised on the streamed arm before, because
`--model-diagnostics` forced the resident path.

It holds here **by construction, checked not assumed**: `PerFileRescoreTask.cs:705` builds the
resident whole-run pool with `MaterializeAllFromSource(buffer, stage7Source, ctx)` - the SAME
per-run source `StreamFiles` uses. Both arms fill each run's list through one code path, so row
order within a run is identical and the files are walked in `base.Value` order either way.

### Guards added, because a wrong panel is worse than no panel

The two phases index the acceptance boundary BY RUN POSITION. A source that yielded runs in a
different order on the second pass - or stopped short - would judge every row against another
run's boundary and still produce a complete, plausible panel that nothing downstream could
detect. `VerifyRunOrder` and `VerifyRunCount` throw instead.

### What the gate proved, 2026-09-07

`regression.ps1 -Dataset All` on the fold:

| leg | result |
|---|---|
| `mode3 (streamed join)` | **PASS on all four datasets** - previously SKIP on three |
| `mode1 (vs golden)`, `mode1b/1c`, `mode2`, `mode4`-`mode10` | PASS everywhere |
| `mode3 (HPC chain==straight)`, per-file FDR sidecars, experiment sidecars | PASS |
| `Build-Osprey -RunTests -RunInspection` | 606 tests (605 pass, 1 pre-existing skip), zero-warning |

**The streamed arm is now exercised on StellarLibDecoy, StellarGenDecoyEntrap and
Astral**, which is item 1 of "STILL OPEN" closed: `--model-diagnostics` no longer keeps
the resident pool, so `CanStreamStage7Join` stops declining and mode 3's phase 4 folds
per run on every dataset. That was two of the four open items in one change.

### The streamed fold reproduces the resident build - proven on real data

A temporary mode-3 leg comparing the pass-2 diagnostics product across routes went red on
StellarGenDecoyEntrap. **It was not the fold**, established by A/B rather than argument:

* `chain-streamed.json` and `chain-resident.json` (`OSPREY_STAGE7_STREAM=0`, same bed,
  same inputs) are **byte-identical** - `cmp` clean, 115,740 bytes each.
* Both differ from the straight-through product in the *same* 496 `fdpViews[].paired[]`
  values, to the last digit. Forcing the resident arm changes nothing.

So the accumulator + two-pass co-assignment reproduce the resident `BuildPass2` exactly on
production data, which is what the unit test asserts on a fixture.

### The leg was REMOVED, and why

It compared the HPC chain against straight-through and demanded BYTE identity of a derived
artifact. Mode 3 never contracted that: it compares sidecars at 1e-9. The difference it
found is real and pre-existing - filed as
[#4645](https://github.com/ProteoWizard/pwiz/issues/4645) - but it is not this branch's,
and a leg that reds on someone else's defect blocks the wrong PR.

**Developer's direction on the replacement (2026-09-07)**: do NOT build an
`OSPREY_STAGE7_STREAM` A/B into the gate.

> *"The long-term goal is to remove the ability to not-stream. So, it doesn't make a lot of
> sense to build the switch into the tests. Instead, we should post the issue and dig into
> it to understand the difference and how we might test against getting the wrong outcome
> before removing the option."*

What survives in the gate instead: `mode3 (streamed join)` asserted on every dataset (the
shape that ran), plus the existing blib / sidecar comparisons (the pool the fold reads).
The accumulator half is pinned by `TestStreamingAccumulatorMatchesBatchPass2`.

### Kept for the manual A/B, until the option goes

`OSPREY_STAGE7_STREAM` is now in `$abSwitchSet` (so the resident tokens are not stripped
under it), the streamed-join assertion SKIPs when it is set to 0 rather than failing a run
for complying, and doc 00 documents it as the Stage 7 sibling of
`OSPREY_STAGE6_STREAM_SURVIVORS`. That is what makes #4645 investigable.

### Pre-merge: cross-impl parity, and a Rust PR that was never opened

**Developer, 2026-09-07**: run the cross-impl comparison before merging, to confirm the
ability to compare C# and Rust is intact.

**Why the change is inert on that path** (static argument, still to be confirmed by the run):
`Compare-EndToEnd-Crossimpl.ps1` invokes a plain straight-through pipeline -
`-i ... -l ... -o output.blib --protein-fdr 0.01 --threads N --work-dir ...` - with NO
`--model-diagnostics` and NO `--input-scores`. So `ExpectReconciledInput` is false and
`CanStreamStage7Join` returns false at its FIRST condition, exactly as before this branch,
and the pass-2 diagnostics block never runs. `mode1 (vs golden)` passing on all four
datasets independently establishes the C# output is byte-identical, so the C#-to-Rust
relationship cannot have moved.

**The Rust checkout was parked on an UNMERGED branch.** `C:\proj\osprey` sits on
`fix/experiment-q-per-entry-not-per-file` (`90c8968`, 2026-08-29, pushed to its own remote
branch, clean). It is NOT in `origin/main`, and the repo's default branch is `main`, not
`master`. The commit makes the Rust protein-compact pass-2 map-back read pass-1 experiment
q per ENTRY (`read_analysis_wide_experiment_q`) instead of per file - the shape C# already
has via the analysis-wide `out.1st-pass.fdr_experiment.bin` (format v5, #4486).

Comparing against `main` would therefore surface Rust's MISSING fix as a divergence and
read as a regression of this branch - the stale-baseline trap
`ai/scripts/Osprey/Compare/README.md` documents (a "46% divergence" chased across three
sessions). So the comparison runs against the BRANCH.

**Follow-up the developer asked for**: open a PR in `maccoss/osprey` for `90c8968` once
this is passing. A prior session appears to have done the Rust-side work and never opened
one, which is how the two implementations start separating.

### Cross-impl parity confirmed, 2026-09-07

`Compare-EndToEnd-Crossimpl.ps1 -Files All` against the Rust branch, both datasets:

| check | Stellar | Astral |
|---|---|---|
| Stage 7 protein FDR (per-col 1e-9) | PASS | PASS |
| Blib content (SQL row+col 1e-9) | PASS | PASS |
| FDR sidecars (per-field 1e-9) | PASS | PASS |

**The comparison script has no `-SourceRoot` and defaults to `<project root>\pwiz`.** The
first attempt therefore aimed at `C:\proj\pwiz`, not the `pwiz-work1` checkout this branch
lives in, and hard-failed **exit 3 on a stale binary** - the guard working exactly as
designed, refusing to report a divergence measured against the wrong tree. Set
`$env:PWIZ_ROOT` to the active checkout before running it; the sibling-checkout rule in the
project CLAUDE.md applies to this script and nothing in its parameters enforces it.

Worth running rather than reasoning about: the static argument that this branch is inert on
the cross-impl path (no `--model-diagnostics`, no `--input-scores`, so
`CanStreamStage7Join` returns false at its first condition) was correct, and would still
have missed that the run was pointed at another checkout entirely.

### maccoss/osprey PR #67 opened

`90c8968` ("Read pass-1 experiment q-values per entry, not per file") had sat unmerged on
its branch since 2026-08-29 while C# carried the equivalent shape. Opened as
[maccoss/osprey#67](https://github.com/maccoss/osprey/pull/67) so `main` stops diverging
from pwiz Osprey. Rust CI gates verified green on the branch first (`cargo fmt --check`,
`clippy -D warnings`, `cargo test`).

**Until it merges, the cross-impl comparison must run against that BRANCH, not `main`** -
comparing against `main` would surface Rust's missing fix as a C# divergence.

### Commit

`a9f5190b8f` "Changed pass-2 model diagnostics to fold run by run" - 8 files,
692 insertions, 76 deletions. Not yet pushed.

## THE 446-FILE PROOF WITH DIAGNOSTICS ON (measured 2026-09-07 16:21-17:30)

Run `chs-446files-libdecoy-r1.0-protein-compact-s7mdiag`, exe `_bin\250-s7mdiag`
(v26.1.1.250, commit `a9f5190b8f`), `--task SecondPassFDR --model-diagnostics` linked from
`stages567`, 8028 artifacts linked / 0 missing, 30 threads.
Plot: `ai/.tmp/sessions/20260907-s7mdiag/s7mdiag-446.png`.
Reference plot regenerated alongside it: `s7fold-446-reference.png`.

**exit 0 in 69 minutes (1:08:40).** The marker line proves the shape that ran:

```
Second-pass join: folding over 446 run(s), each rebuilt from its own artifacts and
dropped (no all-runs survivor pool; 625620 retained base_id(s) read once).
446 of 446 run(s) carry a current 2nd-pass sidecar and are rebuilt without opening
any 1st-pass file.
```

That line could not exist before this branch: `--model-diagnostics` made
`CanStreamStage7Join` decline, so the report forced the resident pool - the 78.3 GB that
was killed at run 381/446. **Coupling 3 is closed.**

| | s7mdiag (mdiag ON) | s7fold (mdiag off) | FirstPassFDR | s7base (resident) |
|---|---|---|---|---|
| managed peak | **18.2 GB** | 23.5 GB | 32.5 GB | 68.0 GB |
| private peak | **29.0 GB** | 36.4 GB | 40.1 GB | 70.5 GB |
| sustained total | 24.0 GB / 300s | 26.2 GB / 300s | - | - |
| floor drift | **-3 MB/file FALLING** | -4 MB/file LEVEL | +4 MB/file | +71 MB/file RISING |
| gaps >= 30s | **0** (max 23s) | 0 (max 20s) | - | - |
| outcome | **exit 0, 1:08:40** | exit 0, 1:10:54 | - | killed 381/446 |

**THE ACCEPTANCE CRITERION IS MET WITH DIAGNOSTICS ON**: SecondPassFDR peaks below
FirstPassFDR on both axes, and the floor FALLS rather than rising. Stage 7 is not the
tallest region on the plot.

It also came in below the mdiag-OFF run while doing MORE work (two stream passes rather
than one, in comparable wall time). Treat the gap as partly GC-timing noise - `--memstamp`
includes uncollected garbage, so it shows shape not magnitude - but the sustained levels
agree (24.0 vs 26.2 GB).

### What this run does NOT cover - stated so nobody reads it as more than it is

* `[MODEL-DIAGNOSTICS] pass-1 data sidecar not found; pass-2 enrichment skipped`. The
  `stages567` bed has no `out.1st-pass.model-diagnostics.json`, so `Accumulator.BuildPass2`
  and the render NEVER EXECUTED. **Only the two stream passes are measured.** Those steps
  are O(distinct precursors), but unmeasured is unmeasured.
* It ran commit `a9f5190b8f`, not the tip. `2a8c198c0a` adds a guard that checks for the
  pass-1 product BEFORE folding - so on this bed the fixed binary would skip the fold
  entirely, and this measurement cannot be reproduced here with it. The guard is in front
  of the fold and does not change it, so the profile stands for the fold.
* The two sibling 446-file pass-1 products (`chs446-mdiag-coldfpfdr`,
  `chs446-mdiag-render-proof`) DIFFER from each other (252,021 vs 233,498 bytes), so
  neither is safely attributable to this pool. Not borrowed - a page splicing two first
  passes would be a misleading artifact.

### The rigorous matrix the developer asked for, and its blocker

> *"Truly rigorous testing would include some testing of --task ModelDiagnostics that
> should run the diagnostics passes in isolation and produce the same output as --task
> FirstPassFDR --model-diagnostics, and then --task SecondPassFDR --model-diagnostics with
> just the diagnostics JSON files deleted."*

| # | run | oracle |
|---|---|---|
| T1 | `--task FirstPassFDR --model-diagnostics` | produces the missing pass-1 product |
| T2 | `--task SecondPassFDR --model-diagnostics` on T1's dir, tip binary | the COMPLETE path: fold -> BuildPass2 -> render. Closes both gaps above |
| T3 | `--task ModelDiagnostics` on T2's dir | byte-identical HTML, no analysis (seconds) |
| T4 | delete only the pass-2 JSON, re-run T2 | reproduces it byte-for-byte |
| T5 | delete both JSONs, re-run T1 | reproduces the pass-1 JSON byte-for-byte |

**BLOCKER, measured with `-WhatIf`**: `-Task FirstPassFDR` with `-LinkFrom` stages only
**1784** files - "stages before FirstPassFDR", i.e. PerFileScoring only. The 446
`.1st-pass.fdr_scores.bin` are NOT staged, so FirstPassFDR RECOMPUTES rather than
re-entering, which is precisely the sidecar reproduction the developer wants to avoid.
`Program.cs` advertises the re-entry ("produce the pass-1 product from the completed
first-pass artifacts"), so the capability exists and the RUNNER is what does not stage it.

Way around: hard-link the WHOLE bed into a fresh dir (links cost no space) so the 1st-pass
sidecars are present and current, then run there. Validate on a small bed before spending
446-scale time. Note the 86-file bed
(`chs-86files-libdecoy-r1.0-protein-compact-retainedset-pfr3`) has **no**
`.1st-pass.stratum.json`, so it is not a drop-in for a protein-compact pass-2 leg.
