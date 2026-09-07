# TODO-20260906_osprey_stage7_lean_row.md - Stage 7 (SecondPassFDR) holds ~274 B objects where 88 B of row would serve

**Module**: `osprey`
**Status**: In Progress - 7 commits, not pushed, no PR yet
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
| 2b. wire it into `Pass2PerFileWorker`, admit `transfer` in `TryCreatePass2Worker` | **NEXT** |
| 3. delete Stage 7's per-file pass-2 compute/write | **the step that removes the pool** |
| 4. pass-2 diagnostics as a fan-out product | |
| 5. roll-up as folds | |
| 6. bound the blib write | |

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

**The oracle is the 82-file SEA-AD A/B**, per the developer: a longer validation, run after
everything else is validated. Recipe and results:
`ai/todos/active/TODO-20260804_osprey_pass2_ab_and_library_production.md`.

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
